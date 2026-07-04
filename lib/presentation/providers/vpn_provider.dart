import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/log_service.dart';
import '../../domain/entities/vpn_state.dart';
import '../../domain/entities/node.dart';
import '../../domain/node_sanitizer.dart';
import '../../infrastructure/singbox_bridge.dart';
import '../../infrastructure/singbox_bridge_windows.dart';
import '../../infrastructure/singbox_bridge_android.dart';
import '../../infrastructure/vpn_notification_service.dart';
import 'subscription_provider.dart';
import 'node_provider.dart';
import 'settings_provider.dart';

class VpnController extends StateNotifier<VpnState> {
  VpnController(this.ref) : super(const VpnDisconnected()) {
    _listenBridge();
    _listenNotificationActions();
  }

  StreamSubscription? _bridgeStateSub;

  final Ref ref;
  final _sanitizer = const NodeSanitizer();
  final _bridge = Platform.isAndroid
      ? SingboxBridgeAndroid.instance
      : SingboxBridgeWindows.instance;
  final _notif = VpnNotificationService.instance;

  StreamSubscription? _statsSub;
  StreamSubscription? _errorSub;
  StreamSubscription? _notifActionSub;
  Timer? _healthTimer;
  Timer? _notifUpdateTimer;

  // Монотонно растущий id сессии подключения — защита от гонки таймеров
  // при быстром connect → disconnect → connect на разных нодах.
  int _sessionId = 0;

  // Последние известные байты трафика — нужны чтобы обновлять уведомление
  // не только из statsStream, но и сразу при смене состояния (сброс на 0
  // при новом коннекте).
  int _lastRx = 0;
  int _lastTx = 0;

  // ── Подключение ────────────────────────────────────────────────────────

  Future<void> connect(Node rawNode) async {
    if (state is VpnConnecting || state is VpnConnected) return;

    final mySession = ++_sessionId;
    _healthTimer?.cancel();

    final node = _sanitizer.sanitize(rawNode);
    log.i(
      'Подключаемся к ${node.name} [${node.host}:${node.port}]',
      tag: 'VPN',
    );
    log.d(
      'SNI: ${node.sni}, fp: ${node.fingerprint}, '
          'mux: ${node.muxEnabled}',
      tag: 'VPN',
    );

    state = VpnConnecting(node: node);
    _lastRx = 0;
    _lastTx = 0;
    unawaited(_notif.show(
      nodeName: node.name,
      rxBytes: 0,
      txBytes: 0,
      connected: false,
    ));

    final settingsSnapshot = ref.read(settingsProvider);
    final result = await _bridge.start(
      node,
      smartRouting: settingsSnapshot.smartRouting,
      aiDirectLane: settingsSnapshot.aiDirectLane,
      excludedApps: settingsSnapshot.splitTunnelingEnabled
          ? settingsSnapshot.excludedApps.toList()
          : const [],
    );

    if (mySession != _sessionId) {
      log.d(
        'connect(): сессия $mySession устарела (текущая $_sessionId), '
            'игнорируем результат start()',
        tag: 'VPN',
      );
      if (result.success) {
        await _bridge.stop();
      }
      return;
    }

    if (!result.success) {
      log.e('Не удалось подключиться: ${result.error}', tag: 'VPN');
      state = VpnError(
        message: result.error ?? 'Неизвестная ошибка',
        node: node,
      );
      await _notif.cancel();
      return;
    }

    log.i('VPN подключён!', tag: 'VPN');
    state = VpnConnected(node: node, connectedAt: DateTime.now());
    unawaited(_notif.show(
      nodeName: node.name,
      rxBytes: 0,
      txBytes: 0,
      connected: true,
    ));
    _startHealthMonitor(mySession);
    _startNotificationUpdates(mySession, node.name);
  }

  // ── Отключение ────────────────────────────────────────────────────────

  Future<void> disconnect() async {
    final current = state;
    if (current is! VpnConnected && current is! VpnConnecting) return;

    final node = switch (current) {
      VpnConnected(node: final n) => n,
      VpnConnecting(node: final n) => n,
      _ => null,
    };

    if (node == null) return;

    _sessionId++;

    log.i('Отключаемся...', tag: 'VPN');
    state = VpnDisconnecting(node: node);

    _healthTimer?.cancel();
    _healthTimer = null;
    _notifUpdateTimer?.cancel();
    _notifUpdateTimer = null;

    await _bridge.stop();
    await _notif.cancel();

    state = const VpnDisconnected();
    log.i('VPN отключён', tag: 'VPN');
  }

  void clearError() {
    if (state is VpnError) state = const VpnDisconnected();
  }

  // ── Уведомление: кнопка "Отключить" из шторки ────────────────────────

  /// Подписывается на события от нативного Android-уведомления. Когда
  /// пользователь жмёт "Отключить" в шторке (даже если приложение
  /// свёрнуто), вызываем ровно ту же disconnect(), что и из UI — никакой
  /// отдельной логики, состояние приложения остаётся источником истины.
  void _listenNotificationActions() {
    if (!Platform.isAndroid) return;
    _notif.startListening();
    _notifActionSub = _notif.onDisconnectRequested.listen((_) {
      log.i('Отключение по кнопке из уведомления', tag: 'VPN');
      disconnect();
    });
  }

  /// Обновляет уведомление раз в секунду актуальными цифрами трафика,
  /// пока сессия активна. Использует последние значения из statsStream
  /// (см. _listenBridge), не делает отдельных запросов к API.
  void _startNotificationUpdates(int mySession, String nodeName) {
    _notifUpdateTimer?.cancel();
    _notifUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mySession != _sessionId) return;
      if (state is! VpnConnected) return;
      unawaited(_notif.show(
        nodeName: nodeName,
        rxBytes: _lastRx,
        txBytes: _lastTx,
        connected: true,
      ));
    });
  }

  // ── Active Health Monitor (латентность + деградация) ──────────────────
  //
  // Ловит НЕ только смерть ноды, но и деградацию: пинг улетел в 5000 мс,
  // туннель формально жив (downstream идёт — ты всех слышишь), но uplink
  // захлёбывается (тебя не слышно). Булев verifyTunnel такое пропускал —
  // теперь меряем конкретную задержку.
  //
  // Щадящий режим: в норме проверка редкая (_healthInterval). При первой
  // же плохой пробе делаем быстрое переподтверждение (_recheckDelay), и
  // только если и оно плохое — переключаемся. Так в покое нагрузка
  // минимальна, а реакция на реальный сбой — считанные секунды.

  /// Интервал плановой проверки в норме (щадящий).
  static const _healthInterval = Duration(seconds: 20);

  /// Быстрое переподтверждение после первой плохой пробы.
  static const _recheckDelay = Duration(seconds: 3);

  /// Порог задержки (мс), выше которого нода считается деградировавшей.
  /// -1 (нет ответа) тоже трактуется как плохая проба.
  static int get _latencyThresholdMs => Platform.isAndroid ? 3000 : 2500;

  /// Сколько плохих проб подряд → переключение.
  static const _badSamplesToSwitch = 2;

  int _badSamples = 0;
  bool _isFailingOver = false;

  void _startHealthMonitor(int mySession) {
    _healthTimer?.cancel();
    _badSamples = 0;
    _isFailingOver = false;
    _healthTimer = Timer.periodic(_healthInterval, (_) async {
      if (mySession != _sessionId) return;
      if (state is! VpnConnected) return;
      if (_isFailingOver) return;

      final bad = await _sampleIsBad(mySession);
      if (mySession != _sessionId || state is! VpnConnected) return;

      if (!bad) {
        // Хорошая проба — сбрасываем счётчик.
        if (_badSamples > 0) {
          log.d('Health: связь в норме (было $_badSamples плохих)', tag: 'VPN');
        }
        _badSamples = 0;
        return;
      }

      _badSamples++;
      log.w(
        'Health: плохая проба $_badSamples/$_badSamplesToSwitch',
        tag: 'VPN',
      );

      if (_badSamples < _badSamplesToSwitch) {
        // Не дёргаемся на одиночном спайке — быстрое переподтверждение.
        await Future.delayed(_recheckDelay);
        if (mySession != _sessionId || state is! VpnConnected) return;
        final stillBad = await _sampleIsBad(mySession);
        if (mySession != _sessionId || state is! VpnConnected) return;
        if (!stillBad) {
          log.d('Health: спайк прошёл, нода восстановилась', tag: 'VPN');
          _badSamples = 0;
          return;
        }
        _badSamples++;
      }

      if (_badSamples >= _badSamplesToSwitch) {
        log.w('Health: нода деградировала — переключаемся', tag: 'VPN');
        _healthTimer?.cancel();
        await _failover(mySession);
      }
    });
  }

  /// Одна проба: меряет задержку через туннель и решает, плохая ли она.
  /// Плохая = нет ответа (-1) или задержка выше порога.
  Future<bool> _sampleIsBad(int mySession) async {
    final ms = await _bridge.measureLatency();
    if (mySession != _sessionId) return false;

    if (ms < 0) {
      log.d('Health: туннель не ответил (-1)', tag: 'VPN');
      return true;
    }
    final bad = ms > _latencyThresholdMs;
    log.d(
      'Health: задержка ${ms}мс (порог $_latencyThresholdMs) → '
      '${bad ? "плохо" : "ок"}',
      tag: 'VPN',
    );
    return bad;
  }

  /// Переключение на лучшую доступную ноду при деградации/смерти текущей.
  ///
  /// Приоритет кандидата: если авто-переключение включено — берём лучшую
  /// рабочую ноду, при этом если текущая была AI-годной, предпочитаем
  /// тоже AI-годную (чтобы доступ к нейронкам не пропал после свитча).
  Future<void> _failover(int mySession) async {
    if (mySession != _sessionId) return;
    if (_isFailingOver) return;
    _isFailingOver = true;

    final current = state;
    if (current is! VpnConnected) {
      _isFailingOver = false;
      return;
    }
    final deadNode = current.node;

    // Уважаем настройку: если пользователь выключил автопереключение —
    // просто уведомляем и остаёмся как есть (не рвём звонок без спроса).
    final autoFailover = ref.read(settingsProvider).autoFailover;
    if (!autoFailover) {
      log.i('Автопереключение выключено — только уведомляем', tag: 'VPN');
      unawaited(_notif.show(
        nodeName: '${deadNode.name} — нестабилен',
        rxBytes: _lastRx,
        txBytes: _lastTx,
        connected: true,
      ));
      _isFailingOver = false;
      // Возобновляем мониторинг — вдруг восстановится.
      _startHealthMonitor(mySession);
      return;
    }

    log.w('🔄 Переключение: ${deadNode.name} деградировал', tag: 'VPN');

    // Помечаем текущую как ненадёжную и ищем замену ДО отключения,
    // чтобы знать, есть ли куда переключаться.
    final sub = ref.read(subscriptionProvider);
    final wasAi = deadNode.aiReachable;

    Node? next = _pickFailoverCandidate(
      excludeId: deadNode.id,
      preferAi: wasAi,
      sub: sub,
    );

    if (next == null) {
      log.e('❌ Нет запасных серверов для переключения', tag: 'VPN');
      unawaited(_notif.show(
        nodeName: 'Нет запасных серверов',
        rxBytes: 0,
        txBytes: 0,
        connected: false,
      ));
      _isFailingOver = false;
      return;
    }

    await disconnect();
    ref.read(subscriptionProvider.notifier).markNodeAsDead(deadNode.id);
    ref.read(nodeSelectionProvider.notifier).clear();

    log.i('🚀 Переключаемся на ${next.name}', tag: 'VPN');
    // Уведомление о самом факте свитча — пользователь поймёт, почему
    // звонок дёрнулся на секунду.
    unawaited(_notif.show(
      nodeName: '${deadNode.name} подвисал → ${next.name}',
      rxBytes: 0,
      txBytes: 0,
      connected: false,
    ));

    _isFailingOver = false;
    await connect(next);
  }

  /// Выбирает лучшего кандидата для переключения.
  /// Порядок: сперва AI-годные (если preferAi), затем просто рабочие,
  /// внутри группы — по минимальной задержке. Текущая нода исключается.
  Node? _pickFailoverCandidate({
    required String excludeId,
    required bool preferAi,
    required SubscriptionState sub,
  }) {
    int lat(Node n) => n.latencyMs ?? 9999;

    if (preferAi) {
      final aiNodes = sub.nodes
          .where((n) => n.aiReachable && n.id != excludeId)
          .toList()
        ..sort((a, b) => lat(a).compareTo(lat(b)));
      if (aiNodes.isNotEmpty) return aiNodes.first;
    }

    final working = sub.nodes
        .where((n) => n.isTrulyWorking && n.id != excludeId)
        .toList()
      ..sort((a, b) => lat(a).compareTo(lat(b)));
    if (working.isNotEmpty) return working.first;

    // Последний шанс — любая живая, кроме текущей.
    final alive = sub.nodes
        .where((n) => n.isAlive && n.id != excludeId)
        .toList()
      ..sort((a, b) => lat(a).compareTo(lat(b)));
    return alive.isEmpty ? null : alive.first;
  }

  // ── Слушаем мост ──────────────────────────────────────────────────────

  void _listenBridge() {
    // ── Синхронизация с реальным состоянием моста ─────────────────────────
    //
    // РАНЬШЕ подписки на stateStream не было вовсе, и Riverpod-состояние
    // жило своей жизнью. Из-за этого, например, нажатие "ОТКЛЮЧИТЬ" в
    // РОДНОМ уведомлении плагина flutter_v2ray (не нашем) останавливало
    // VPN на нативном уровне, мост переходил в idle, а UI продолжал
    // показывать "Защищён" до ручного отключения.
    _bridgeStateSub = _bridge.stateStream.listen((bridgeState) {
      final current = state;
      switch (bridgeState) {
        case BridgeState.idle:
          // Туннель погас снаружи (нативная кнопка, отзыв VPN-разрешения
          // системой и т.п.), а мы всё ещё считаем себя подключёнными.
          if (current is VpnConnected) {
            log.w('Мост перешёл в idle — синхронизируем UI', tag: 'VPN');
            _healthTimer?.cancel();
            _notifUpdateTimer?.cancel();
            _sessionId++;
            state = const VpnDisconnected();
            unawaited(_notif.cancel());
          }
        case BridgeState.error:
          // Ошибки с текстом приходят через errorStream; здесь ловим только
          // молчаливый переход в error (например, watchdog Android-моста).
          if (current is VpnConnected) {
            _healthTimer?.cancel();
            _notifUpdateTimer?.cancel();
          }
        case BridgeState.starting ||
              BridgeState.running ||
              BridgeState.stopping:
          break; // Эти переходы инициируем мы сами — UI уже в курсе.
      }
    });

    _statsSub = _bridge.statsStream.listen((stats) {
      _lastRx = stats.$1;
      _lastTx = stats.$2;
      final current = state;
      if (current is VpnConnected) {
        state = current.withTraffic(rx: stats.$1, tx: stats.$2);
      }
    });

    _errorSub = _bridge.errorStream.listen((error) {
      if (error == 'WATCHDOG_NO_TRAFFIC') {
        _failover(_sessionId);
        return;
      }

      log.e('Мост сообщил об ошибке: $error', tag: 'VPN');
      final current = state;
      final node = current is VpnConnected ? current.node : null;
      state = VpnError(message: error, node: node);
    });
  }

  @override
  void dispose() {
    _sessionId++;
    _healthTimer?.cancel();
    _notifUpdateTimer?.cancel();
    _statsSub?.cancel();
    _errorSub?.cancel();
    _notifActionSub?.cancel();
    _bridgeStateSub?.cancel();
    super.dispose();
  }
}

final vpnControllerProvider = StateNotifierProvider<VpnController, VpnState>(
      (ref) => VpnController(ref),
);