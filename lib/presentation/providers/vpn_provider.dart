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

  // Порог отказа адаптивный по платформе — на Android нестабильность
  // сети (лифт, метро, смена вышки) это норма, а не признак мёртвой ноды.
  static int get _maxFailedPings => Platform.isAndroid ? 4 : 2;

  StreamSubscription? _statsSub;
  StreamSubscription? _errorSub;
  StreamSubscription? _notifActionSub;
  Timer? _healthTimer;
  Timer? _notifUpdateTimer;
  int _failedPings = 0;

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

  // ── Active Health Monitor ─────────────────────────────────────────────

  void _startHealthMonitor(int mySession) {
    _healthTimer?.cancel();
    _failedPings = 0;
    _healthTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (mySession != _sessionId) return;

      final current = state;
      if (current is! VpnConnected) return;

      // Проверка связности делегирована мосту (verifyTunnel):
      //   • Windows — HTTPS через локальный прокси sing-box (2080);
      //   • Android — замер задержки САМИМ v2ray-core.
      //
      // Раньше на Android здесь был прямой HTTPS-запрос без прокси —
      // расчёт был на то, что VpnService туннелирует весь трафик. Ловушка:
      // если туннель НЕ поднялся, тот же запрос спокойно уходит через
      // обычную сеть и тоже возвращает 204. Такой health-check «подтверждал»
      // связность на мёртвом VPN (именно это сбило диагностику симптома B —
      // failedPings=0/4 при фактически не созданном VPN-интерфейсе).
      // verifyTunnel() по построению не может дать ложноположительный
      // результат: на обеих платформах запрос физически идёт через туннель.
      final ok = await _bridge.verifyTunnel();
      if (ok) {
        if (_failedPings > 0) {
          log.d(
            'Health Monitor: связь восстановлена (было $_failedPings ошибок)',
            tag: 'VPN',
          );
        }
        _failedPings = 0;
      } else {
        log.d('Health Monitor: проверка туннеля не прошла', tag: 'VPN');
        _failedPings++;
      }

      if (mySession != _sessionId) return;

      log.d(
        'Health Monitor: failedPings=$_failedPings/$_maxFailedPings '
            '(платформа: ${Platform.isAndroid ? "Android" : "Desktop"})',
        tag: 'VPN',
      );

      if (_failedPings >= _maxFailedPings) {
        _healthTimer?.cancel();
        _autoSwitch(mySession);
      }
    });
  }

  Future<void> _autoSwitch(int mySession) async {
    if (mySession != _sessionId) return;

    final current = state;
    if (current is! VpnConnected) return;
    final deadNode = current.node;

    log.w(
      '🔄 Авто-переключение: нода ${deadNode.name} не отвечает!',
      tag: 'VPN',
    );

    await disconnect();

    ref.read(subscriptionProvider.notifier).markNodeAsDead(deadNode.id);
    ref.read(nodeSelectionProvider.notifier).clear();

    final nextNode = ref.read(subscriptionProvider).bestNode;

    if (nextNode != null) {
      log.i(
        '🚀 Переключаемся на следующий сервер: ${nextNode.name}',
        tag: 'VPN',
      );
      await connect(nextNode);
    } else {
      log.e('❌ Нет доступных серверов для авто-переключения', tag: 'VPN');
      state = const VpnError(message: 'Все серверы недоступны');
    }
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
        _autoSwitch(_sessionId);
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