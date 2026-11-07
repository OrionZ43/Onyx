import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/log_service.dart';
import '../../domain/entities/vpn_state.dart';
import '../../domain/entities/node.dart';
import '../../domain/node_sanitizer.dart';
import '../../infrastructure/singbox_bridge_windows.dart';
import '../../infrastructure/singbox_bridge_android.dart';
import '../../infrastructure/vpn_notification_service.dart';
import 'subscription_provider.dart';
import 'groups_provider.dart';
import 'connect_phase.dart';
import 'sources_provider.dart';
import '../../domain/sources/node_pool.dart';
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
    final fallbacks = _transportFallbacks(node);
    final result = await _bridge.start(
      node,
      fallbacks: fallbacks,
      routing: RoutingOptions(
        smartRouting: settingsSnapshot.smartRouting,
        region: settingsSnapshot.effectiveRegion,
        aiDirectLane: settingsSnapshot.aiDirectLane,
        discordMode: settingsSnapshot.discordMode,
      ),
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

  // ── Автопилот «один тап» ──────────────────────────────────────────────

  /// Сколько ждать проверки серверов перед подключением.
  static const _probeWaitLimit = Duration(seconds: 90);

  /// Тап по кнопке в режиме «Автовыбор»: обновить устаревшие подписки,
  /// проверить серверы (TCP → Deep Probe → UDP), выбрать лучший живой (в
  /// режиме Discord — с UDP), подключиться, а при отказе — следующий.
  /// Этапы — в [connectPhaseProvider]. Ручной выбор сервера — [connect].
  Future<void> smartConnect() async {
    if (state is VpnConnecting || state is VpnConnected) return;
    final phase = ref.read(connectPhaseProvider.notifier);
    final srcCtl = ref.read(sourcesProvider.notifier);
    final subCtl = ref.read(subscriptionProvider.notifier);
    await srcCtl.ready;

    void fail(ConnectFailure r, String msg, List<ConnectAction> a) {
      log.w('Автопилот: $msg', tag: 'VPN');
      phase.state = ConnectPhase.failed(r, msg, a);
    }

    // 1. Источники.
    final enabled = ref.read(sourcesProvider).where((s) => s.enabled).toList();
    if (enabled.isEmpty) {
      return fail(
        ConnectFailure.noSources,
        'Нет серверов. Добавьте подписку, ссылку или свой сервер.',
        const [ConnectAction.addServer, ConnectAction.awsGuide],
      );
    }
    final now = DateTime.now();
    final stale = enabled.where((s) {
      if (s.kind != SourceKind.subscription) return false;
      final last = s.lastUpdatedAt;
      final hours = s.autoUpdateHours > 0 ? s.autoUpdateHours : 24;
      return last == null || now.difference(last) >= Duration(hours: hours);
    }).toList();
    if (stale.isNotEmpty || ref.read(subscriptionProvider).nodes.isEmpty) {
      phase.state = ConnectPhase.updating;
      for (final s in (stale.isEmpty ? enabled : stale)) {
        await srcCtl.refresh(s.id, probe: false);
      }
    }
    if (ref.read(subscriptionProvider).nodes.isEmpty) {
      final errs = [
        for (final s in ref.read(sourcesProvider))
          if (s.enabled && s.error != null) '${s.name}: ${s.error}',
      ];
      return fail(
        ConnectFailure.sourcesUnreachable,
        'Не удалось загрузить серверы${errs.isEmpty ? '' : ' (${errs.join('; ')})'}. '
            'Проверьте интернет или добавьте свой сервер.',
        const [ConnectAction.refresh, ConnectAction.addServer, ConnectAction.awsGuide],
      );
    }

    // 2. Проверка: ждём, пока появится подходящий кандидат.
    final discord = ref.read(settingsProvider).discordMode;
    bool good(Node n) => n.isTrulyWorking && (!discord || n.udpSupported);
    Node? candidate() {
      final sub = ref.read(subscriptionProvider);
      final groupId = ref.read(autoGroupProvider);
      final pool = groupId == null ? sub.nodes : ref.read(groupNodesProvider(groupId));
      return NodePool.best(pool.where(good), exclude: sub.quarantined) ??
          NodePool.best(sub.nodes.where(good), exclude: sub.quarantined);
    }

    if (candidate() == null) {
      if (!subCtl.isProbing) unawaited(subCtl.reprobe());
      final deadline = DateTime.now().add(_probeWaitLimit);
      await Future.delayed(const Duration(milliseconds: 300));
      while (DateTime.now().isBefore(deadline) && candidate() == null) {
        final s = ref.read(subscriptionProvider);
        final deep = s.status == SubStatus.deepProbing;
        phase.state = ConnectPhase.checking(
          deep ? s.deepProbedCount : s.probedCount,
          deep ? s.deepProbeTotal : s.probeTotal,
        );
        if (!subCtl.isProbing) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    // 3–4. Выбор и подключение; до 3 попыток на разных серверах.
    for (var attempt = 0; attempt < 3; attempt++) {
      final node = candidate() ?? ref.read(autoNodeProvider);
      if (node == null) break;
      phase.state = ConnectPhase.connecting(node.name);
      await connect(node);
      if (state is VpnConnected) {
        final noUdp = discord && !node.udpSupported;
        phase.state = noUdp
            ? const ConnectPhase.notice(
                'Подключено, но сервер с рабочим UDP не найден — голос Discord может не работать. '
                'Попробуйте «Обновить» позже или свой сервер.',
              )
            : ConnectPhase.idle;
        return;
      }
      // Не поднялся — на карантин и следующий.
      subCtl.markNodeAsDead(node.id);
      log.w('Автопилот: ${node.name} не поднялся — пробуем следующий', tag: 'VPN');
    }

    fail(
      ConnectFailure.allDead,
      'Ни один сервер сейчас не отвечает. Обновите список позже или добавьте свой сервер.',
      const [ConnectAction.refresh, ConnectAction.addServer, ConnectAction.awsGuide],
    );
  }

  /// Другие транспорты ТОГО ЖЕ сервера (тот же host, другой протокол или
  /// порт): например REALITY + Hysteria2 от нашего серверного скрипта.
  /// Мост объединит их в urltest-группу — sing-box сам переключится на
  /// живой транспорт, если GFW задушит UDP или заблокирует TCP-порт.
  /// Мёртвых членов группы urltest отсеет сам; берём не больше 3.
  List<Node> _transportFallbacks(Node node) {
    final nodes = ref.read(subscriptionProvider).nodes;
    return nodes
        .where((n) =>
            n.id != node.id &&
            n.serverKey == node.serverKey &&
            (n.protocol != node.protocol || n.port != node.port))
        .map(_sanitizer.sanitize)
        .take(3)
        .toList();
  }

  /// Проверка UDP через активный туннель (голос/видео Discord).
  /// Нужен статус «подключено»; длится до ~4 с.
  Future<UdpProbeResult> checkUdp() async {
    if (state is! VpnConnected) {
      return const UdpProbeResult.failed('VPN не подключён');
    }
    var r = await _bridge.checkUdp();
    if (!r.ok && !r.serverUnreachable) {
      // Ответов нет. Отличаем «UDP заблокирован» от «сервер мёртв»:
      // если и HTTPS через туннель не проходит — дело не в UDP.
      final tunnelAlive = await _bridge.verifyTunnel();
      if (!tunnelAlive) r = UdpProbeResult.unreachable(sent: r.sent);
    }
    log.i('Проверка UDP: ${r.summary}', tag: 'VPN');
    return r;
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

  /// Первая проверка после подключения.
  static const _firstCheckDelay = Duration(seconds: 6);

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
    Future<void> tick() async {
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
    }

    // Первая проверка — быстро после подключения: если сервер мёртв
    // (connect timeout), не ждём плановые 20 с, а через ~6+3 с переключаемся.
    _healthTimer = Timer(_firstCheckDelay, () async {
      await tick();
      if (mySession != _sessionId || state is! VpnConnected) return;
      _healthTimer = Timer.periodic(_healthInterval, (_) => tick());
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
    final phase = ref.read(connectPhaseProvider.notifier);
    phase.state = ConnectPhase.switching(deadNode.name, next.name);
    await connect(next);
    phase.state = state is VpnConnected
        ? ConnectPhase.notice('Переключились: ${deadNode.name} → ${next.name}')
        : ConnectPhase.idle;
  }

  /// Выбирает лучшего кандидата для переключения.
  /// Порядок: сперва AI-годные (если preferAi), затем просто рабочие,
  /// внутри группы — по минимальной задержке. Текущая нода исключается.
  Node? _pickFailoverCandidate({
    required String excludeId,
    required bool preferAi,
    required SubscriptionState sub,
  }) {
    // Сначала — в группе автовыбора (если выбрана), потом по всем.
    final groupId = ref.read(autoGroupProvider);
    return NodePool.failover(
      excludeId: excludeId,
      groupNodes: groupId == null ? sub.nodes : ref.read(groupNodesProvider(groupId)),
      allNodes: sub.nodes,
      preferAi: preferAi,
      exclude: sub.quarantined,
    );
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
