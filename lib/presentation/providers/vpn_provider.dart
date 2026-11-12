import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/log_service.dart';
import '../../domain/entities/vpn_state.dart';
import '../../domain/entities/node.dart';
import '../../domain/failover_policy.dart';
import '../../domain/node_sanitizer.dart';
import '../../domain/smart_probe.dart';
import '../../infrastructure/binary_manager.dart';
import '../../infrastructure/singbox_bridge_windows.dart';
import '../../infrastructure/singbox_bridge_android.dart';
import '../../infrastructure/vpn_notification_service.dart';
import '../../infrastructure/exit_ip.dart';
import '../../infrastructure/network_watcher.dart';
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
    if (backgroundNetwork) {
      // Смена сети (этап 2): подключены — сразу проверяем туннель, отключены —
      // перепроверяем серверы в фоне (данные проб с прошлой сети устарели).
      _netSub = NetworkWatcher.instance.changes.listen(_onNetworkEvent);
      // Регион «Авто» по IP (этап 2) — при старте, пока туннеля нет.
      unawaited(_refreshGeo());
    }
  }

  /// Фоновая сетевая активность (опрос сетей, страна по IP). Под `flutter
  /// test` выключена: юнит-тесты не ходят в сеть и не оставляют таймеров.
  static bool backgroundNetwork = !Platform.environment.containsKey('FLUTTER_TEST');

  /// Можно ли сейчас ходить в сеть напрямую (запрос страны по IP): VPN не
  /// поднят или сокеты приложения идут мимо туннеля (Android-цепочка). На
  /// Windows с TUN и в Android-режиме Xray узнали бы страну сервера.
  bool _directNetwork() =>
      state is VpnDisconnected || state is VpnError || _bridge.appTrafficBypassesTunnel;

  /// Регион «Авто», а страна по IP ещё не известна — подождать ответа (до
  /// [_geoWait]) перед подключением: иначе первое подключение у друга с
  /// английской Windows соберётся с регионом по часовому поясу. Без сети или
  /// после недавней неудачной попытки не ждём.
  Future<void> _ensureGeo() async {
    final settings = ref.read(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    if (settings.routingRegion != RoutingRegion.auto || n.geoFresh || !_directNetwork()) return;
    final last = _geoAttemptAt;
    if (last != null && DateTime.now().difference(last) < const Duration(minutes: 10)) return;
    _geoAttemptAt = DateTime.now();
    try {
      await _refreshGeo().timeout(_geoWait);
    } catch (_) {}
  }

  static const _geoWait = Duration(seconds: 4);

  /// Сколько после своего подключения или отключения изменения сети — не
  /// события (#69): поднимается или гаснет свой туннель, Windows
  /// перестраивает маршруты.
  static const _ownNetChange = Duration(seconds: 20);
  DateTime? _geoAttemptAt;

  Future<void> _refreshGeo({bool force = false}) async {
    try {
      await ref.read(settingsProvider.notifier).refreshGeo(canLookup: _directNetwork, force: force);
    } catch (e) {
      log.d('Регион по IP: $e', tag: 'GEO');
    }
  }

  StreamSubscription? _netSub;

  /// Фоновая перепроверка кандидатов на замену, пока подключены (этап 2).
  Timer? _bgProbeTimer;

  /// Смена сети или выход из сна (этап 2): подключены — сразу проверяем
  /// туннель и при обрыве переподключаемся ([_recover]); отключены —
  /// перепроверяем серверы в фоне. Новая сеть — возможно, другая страна.
  void _onNetworkEvent(NetEvent e) {
    final s = state;
    if (s is VpnConnected) {
      if (!_isFailingOver && !_recovering) unawaited(_checkTunnelAfter(e, _sessionId));
    } else if (s is VpnDisconnected || s is VpnError) {
      ref.read(subscriptionProvider.notifier).networkChanged();
    }
    if (e == NetEvent.changed && _directNetwork()) unawaited(_refreshGeo(force: true));
  }

  String _why(NetEvent e) => e == NetEvent.resumed ? 'после спящего режима' : 'после смены сети';

  /// Пара быстрых проб туннеля после смены сети; обе не ответили — обрыв.
  Future<void> _checkTunnelAfter(NetEvent e, int mySession) async {
    log.i('Сеть: ${e.name} — проверяем туннель', tag: 'VPN');
    await Future.delayed(const Duration(seconds: 2)); // сеть поднимается
    for (var i = 0; i < 2; i++) {
      if (mySession != _sessionId || state is! VpnConnected) return;
      final ms = await _bridge.measureLatency();
      if (ms >= 0) {
        log.i('Туннель жив ${_why(e)} ($ms мс)', tag: 'VPN');
        return;
      }
      await Future.delayed(const Duration(seconds: 3));
    }
    if (mySession != _sessionId || state is! VpnConnected) return;
    await _recover(_why(e));
  }

  // ── Восстановление после обрыва (этап 2) ──────────────────────────────
  //
  // Туннель умер после смены сети, сна или падения ядра. Сначала
  // переподключаемся к ТОМУ ЖЕ серверу — это не «прыжок», критерии #60 не
  // нарушаем. Не вышло, и автопереключение разрешено (тумблер включён и
  // сервер не выбран вручную) — подбираем сервер заново (smartConnect).
  // Иначе честно говорим, что сервер не отвечает. Не чаще 3 раз за 10 минут;
  // без физической сети не дёргаемся — подождём следующего события сети.

  bool _recovering = false;
  final List<DateTime> _recoveries = [];

  Future<void> _recover(String why) async {
    if (_recovering) return;
    final s = state;
    final node = switch (s) {
      VpnConnected(node: final n) => n,
      VpnError(node: final n) => n,
      _ => null,
    };
    if (node == null) return;
    if (!NetworkWatcher.instance.hasNetwork) {
      log.w('Туннель не отвечает $why, но физической сети нет — ждём сеть', tag: 'VPN');
      return;
    }
    final now = DateTime.now();
    _recoveries.removeWhere((t) => now.difference(t) > const Duration(minutes: 10));
    final phase = ref.read(connectPhaseProvider.notifier);
    if (_recoveries.length >= 3) {
      log.w('Восстановление $why: слишком часто — останавливаемся', tag: 'VPN');
      phase.state = ConnectPhase.notice(
        'Связь с ${node.name} постоянно рвётся. Проверьте интернет или выберите другой сервер.',
        kind: NoticeKind.warning,
      );
      return;
    }
    _recoveries.add(now);
    _recovering = true;
    try {
      final plan = RecoveryPolicy.plan(
        autoFailover: ref.read(settingsProvider).autoFailover,
        manualPick: ref.read(nodeSelectionProvider) != null,
      );
      log.w('Туннель не отвечает $why — переподключаемся к ${node.name}', tag: 'VPN');
      phase.state = ConnectPhase.connecting(node.name);
      if (state is VpnConnected || state is VpnConnecting) await disconnect();
      await connect(node);
      if (state is VpnConnected) {
        phase.state = ConnectPhase.notice('Соединение восстановлено $why', kind: NoticeKind.recovered);
        return;
      }
      if (plan.sameNodeOnly) {
        phase.state = ConnectPhase.notice(
          plan == RecoveryStep.sameNodeManual
              ? '${node.name} не отвечает $why. Сервер выбран вручную, поэтому Onyx его не меняет — '
                  'выберите другой или «Автовыбор».'
              : '${node.name} не отвечает $why. Автопереключение выключено, поэтому Onyx его не меняет — '
                  'выберите другой сервер или включите автопереключение в Настройках.',
          kind: NoticeKind.warning,
        );
        return;
      }
      log.w('${node.name} не поднялся $why — подбираем сервер заново', tag: 'VPN');
      phase.state = ConnectPhase.idle;
      await smartConnect();
    } finally {
      _recovering = false;
    }
  }

  void _startBackgroundProbe(int mySession) {
    _bgProbeTimer?.cancel();
    _bgProbeTimer = Timer.periodic(SubscriptionController.backgroundEvery, (t) {
      final s = state;
      if (mySession != _sessionId || s is! VpnConnected) {
        t.cancel();
        return;
      }
      ref.read(subscriptionProvider.notifier).backgroundReprobe(excludeId: s.node.id);
    });
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
    // Регион «Авто»: сначала узнаём страну по IP, если ещё не знаем (этап 2).
    await _ensureGeo();
    if (state is VpnConnecting || state is VpnConnected) return;

    final mySession = ++_sessionId;
    // Свой туннель сейчас поднимется: это не «смена сети» (#69).
    NetworkWatcher.instance.quietFor(_ownNetChange);
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
    NetworkWatcher.instance.quietFor(_ownNetChange);
    unawaited(_notif.show(
      nodeName: node.name,
      rxBytes: 0,
      txBytes: 0,
      connected: true,
    ));
    _startHealthMonitor(mySession);
    _startBackgroundProbe(mySession);
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
    if (_smartActive) return; // уже идёт прогон
    final run = ++_smartRun;
    _smartActive = true;
    try {
      await _smartConnect(run);
    } finally {
      if (run == _smartRun) _smartActive = false;
    }
  }

  /// Номер текущего прогона автопилота. Любая отмена (cancelSmartConnect,
  /// disconnect) его увеличивает — после каждого await прогон проверяет,
  /// не отменили ли его, и тихо выходит: не переподключается против воли
  /// пользователя и не отправляет живой сервер на карантин.
  int _smartRun = 0;
  bool _smartActive = false;

  /// Идёт ли сейчас прогон автопилота (для кнопки «Отмена»).
  bool get isSmartConnecting => _smartActive;

  /// Остановить автопилот на любом этапе. Если туннель уже поднимается —
  /// отключиться.
  Future<void> cancelSmartConnect() async {
    _smartRun++;
    _smartActive = false;
    ref.read(connectPhaseProvider.notifier).state = ConnectPhase.idle;
    if (state is VpnConnecting || state is VpnConnected) await disconnect();
  }

  Future<void> _smartConnect(int run) async {
    bool cancelled() => run != _smartRun;
    final phase = ref.read(connectPhaseProvider.notifier);
    final srcCtl = ref.read(sourcesProvider.notifier);
    final subCtl = ref.read(subscriptionProvider.notifier);
    await srcCtl.ready;
    if (cancelled()) return;

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
        if (cancelled()) return;
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
    // UDP нужен в режиме Discord или если Discord сейчас запущен (Windows,
    // этап 2 автопилота) — без него голос не работает.
    final discord = ref.read(settingsProvider).discordMode || SubscriptionController.discordRunning();
    bool good(Node n) => n.isTrulyWorking && (!discord || n.udpSupported);
    Node? candidate() {
      final sub = ref.read(subscriptionProvider);
      final groupId = ref.read(autoGroupProvider);
      final pool = groupId == null ? sub.nodes : ref.read(groupNodesProvider(groupId));
      // Для голоса Discord — UDP-нативный протокол при сопоставимой задержке (#73).
      return NodePool.best(pool.where(good), exclude: sub.quarantined, preferUdpNative: discord) ??
          NodePool.best(sub.nodes.where(good), exclude: sub.quarantined, preferUdpNative: discord);
    }

    if (candidate() == null) {
      if (!subCtl.isProbing) unawaited(subCtl.reprobe());
      final deadline = DateTime.now().add(_probeWaitLimit);
      await Future.delayed(const Duration(milliseconds: 300));
      while (DateTime.now().isBefore(deadline) && candidate() == null) {
        if (cancelled()) return;
        final s = ref.read(subscriptionProvider);
        final deep = s.status == SubStatus.deepProbing;
        phase.state = ConnectPhase.checking(
          deep ? s.deepProbedCount : s.probedCount,
          deep ? s.deepProbeTotal : s.probeTotal,
        );
        if (!subCtl.isProbing) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }
      if (cancelled()) return;
    }

    // 3–4. Выбор и подключение; до 3 попыток на разных серверах.
    for (var attempt = 0; attempt < 3; attempt++) {
      final node = candidate() ?? ref.read(autoNodeProvider);
      if (node == null) break;
      phase.state = ConnectPhase.connecting(node.name);
      await connect(node);
      // Отменили во время подключения — никаких повторов и карантина.
      if (cancelled()) return;
      if (state is VpnConnected) {
        final noUdp = discord && !node.udpSupported;
        phase.state = noUdp
            ? const ConnectPhase.notice(
                'Подключено, но сервер с рабочим UDP не найден — голос Discord может не работать. '
                'Позже нажмите «Обновить» или добавьте свой сервер.',
                kind: NoticeKind.warning,
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
    // Запасной транспорт того же сервера — тоже автоматическая смена (sing-box
    // сам переключает urltest-группу). Сервер выбран вручную или тумблер
    // автопереключения выключен — ровно то, что выбрали (#69).
    if (!ref.read(settingsProvider).autoFailover || ref.read(nodeSelectionProvider) != null) {
      return const [];
    }
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

  /// Внешний IP выхода через туннель (для «IP выхода» в UI). null — VPN
  /// не подключён или сервисы определения IP не ответили. ~1–6 с.
  Future<String?> exitIp() async {
    if (state is! VpnConnected) return null;
    return ExitIp.fetch();
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
    // Отключение пользователем отменяет и автопилот (если он идёт).
    if (_smartActive) {
      _smartRun++;
      _smartActive = false;
      ref.read(connectPhaseProvider.notifier).state = ConnectPhase.idle;
    }
    final current = state;
    if (current is! VpnConnected && current is! VpnConnecting) return;

    final node = switch (current) {
      VpnConnected(node: final n) => n,
      VpnConnecting(node: final n) => n,
      _ => null,
    };

    if (node == null) return;

    _sessionId++;
    // Свой туннель гаснет: это не «смена сети» (#69).
    NetworkWatcher.instance.quietFor(_ownNetChange);

    log.i('Отключаемся...', tag: 'VPN');
    state = VpnDisconnecting(node: node);

    _healthTimer?.cancel();
    _healthTimer = null;
    _bgProbeTimer?.cancel();
    _bgProbeTimer = null;
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

  /// Переподтверждение после плохой пробы.
  static const _recheckDelay = Duration(seconds: 4);

  /// Порог задержки (мс), выше которого нода считается деградировавшей.
  /// -1 (нет ответа) тоже трактуется как плохая проба.
  static int get _latencyThresholdMs => Platform.isAndroid ? 3000 : 2500;

  /// Сколько плохих проб подряд → деградация. #60: три за ~8 с, а не две
  /// за 3 с — короткий спайк не должен рвать игру и звонок.
  static const _badSamplesToSwitch = 3;

  int _badSamples = 0;

  /// Сколько плохих проб подряд были «нет ответа вовсе» (#69). Мёртвым сервер
  /// считается, только если ВСЕ плохие пробы такие, а не одна последняя.
  int _deadSamples = 0;
  bool _isFailingOver = false;

  /// Последний замер текущей ноды (мс; −1 — не ответила).
  int _lastHealthMs = -1;

  /// Идёт ли сейчас своя проверка серверов (Deep Probe: десятки sing-box).
  /// Пока идёт, медленная проба здоровья не в счёт (#69). В тестах подменяется.
  static bool Function(Ref ref) probesBusy =
      (ref) => ref.read(subscriptionProvider.notifier).isProbing || DeepProbe.inFlight > 0;

  /// Когда Onyx в последний раз сам сменил сервер (гистерезис).
  DateTime? _lastAutoSwitch;

  /// До какого момента не искать замену снова (после безуспешного поиска).
  DateTime? _noBetterUntil;

  /// Когда последний раз предупреждали «сервер нестабилен» (антиспам).
  DateTime? _lastUnstableNotice;

  void _startHealthMonitor(int mySession) {
    _healthTimer?.cancel();
    _badSamples = 0;
    _deadSamples = 0;
    _isFailingOver = false;
    Future<void> check() async {
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
        _deadSamples = 0;
        return;
      }

      _badSamples++;
      if (_lastHealthMs < 0) _deadSamples++;
      // Не дёргаемся на одиночном спайке — быстрые переподтверждения.
      while (_badSamples < _badSamplesToSwitch) {
        log.w('Health: плохая проба $_badSamples/$_badSamplesToSwitch', tag: 'VPN');
        await Future.delayed(_recheckDelay);
        if (mySession != _sessionId || state is! VpnConnected) return;
        final stillBad = await _sampleIsBad(mySession);
        if (mySession != _sessionId || state is! VpnConnected) return;
        if (!stillBad) {
          log.d('Health: спайк прошёл, нода восстановилась', tag: 'VPN');
          _badSamples = 0;
          _deadSamples = 0;
          return;
        }
        _badSamples++;
        if (_lastHealthMs < 0) _deadSamples++;
      }

      log.w('Health: нода деградировала ($_badSamples плохих проб подряд)', tag: 'VPN');
      _healthTimer?.cancel();
      await _failover(mySession);
    }

    // Одна проверка за раз: плановая и внеплановая (смена сети) не должны
    // считать плохие пробы дважды.
    var running = false;
    Future<void> tick() async {
      if (running) return;
      running = true;
      try {
        await check();
      } finally {
        running = false;
      }
    }

    // Первая проверка — быстро после подключения: если сервер мёртв
    // (connect timeout), не ждём плановые 20 с.
    _healthTimer = Timer(_firstCheckDelay, () async {
      await tick();
      if (mySession != _sessionId || state is! VpnConnected) return;
      _healthTimer = Timer.periodic(_healthInterval, (_) => tick());
    });
  }

  /// Одна проба: меряет задержку через туннель и решает, плохая ли она
  /// ([FailoverPolicy.healthSampleBad]): нет ответа (-1) или задержка выше
  /// порога — но медленная, пока идёт своя проверка серверов, не в счёт.
  Future<bool> _sampleIsBad(int mySession) async {
    final ms = await _bridge.measureLatency();
    if (mySession != _sessionId) return false;
    _lastHealthMs = ms;

    if (ms < 0) {
      log.d('Health: туннель не ответил (-1)', tag: 'VPN');
      return true;
    }
    final busy = probesBusy(ref);
    final bad = FailoverPolicy.healthSampleBad(ms, thresholdMs: _latencyThresholdMs, probesBusy: busy);
    log.d(
      'Health: задержка $msмс (порог $_latencyThresholdMs) → '
      '${bad ? "плохо" : ms > _latencyThresholdMs ? "медленно, но идёт проверка серверов — не в счёт" : "ок"}',
      tag: 'VPN',
    );
    return bad;
  }

  /// Деградация текущей ноды: решаем, можно ли прыгать, и куда (#60).
  ///
  /// Не прыгаем, если: «Автопереключение» выключено; сервер выбран вручную;
  /// недавно уже прыгали сами, а сервер отвечает (пауза); недавно искали
  /// и не нашли. Иначе 2–3 лучших кандидата (без заведомо медленных)
  /// перепроверяются свежим замером, прыжок — только на кандидата в
  /// пределах потолка и заметно быстрее текущего ([FailoverPolicy]). Нет
  /// такого — остаёмся и честно говорим, что стабильного сервера нет.
  ///
  /// [watchdog] — сторож «через туннель 0 байт»: сервер считаем мёртвым.
  Future<void> _failover(int mySession, {bool watchdog = false}) async {
    if (mySession != _sessionId) return;
    if (_isFailingOver) return;
    _isFailingOver = true;

    final current = state;
    if (current is! VpnConnected) {
      _isFailingOver = false;
      return;
    }
    final deadNode = current.node;
    if (watchdog) {
      _lastHealthMs = -1;
      _deadSamples = _badSamplesToSwitch;
    }
    final settings = ref.read(settingsProvider);
    final picked = ref.read(nodeSelectionProvider);

    final gate = FailoverPolicy.gate(
      autoFailover: settings.autoFailover,
      manualPick: picked != null,
      // Мёртв — только если не ответил ни на одну из плохих проб (#69).
      currentDead: _deadSamples >= _badSamplesToSwitch,
      now: DateTime.now(),
      connectedAt: current.connectedAt,
      lastAutoSwitch: _lastAutoSwitch,
      noBetterUntil: _noBetterUntil,
    );
    if (gate != FailoverGate.allowed) {
      log.i('Автопереключение не выполняется: ${gate.name}', tag: 'VPN');
      // Только что подключились — молча ждём: сервер отвечает, это не сбой.
      if (gate != FailoverGate.settling) {
        _notifyUnstable(gate == FailoverGate.manual
            ? '${deadNode.name} нестабилен — выбран вручную, остаёмся'
            : '${deadNode.name} — нестабилен');
      }
      _isFailingOver = false;
      // Возобновляем мониторинг — вдруг восстановится.
      _startHealthMonitor(mySession);
      return;
    }

    log.w('🔄 ${deadNode.name} деградировал — ищем замену', tag: 'VPN');
    final sub = ref.read(subscriptionProvider);
    final groupId = ref.read(autoGroupProvider);
    final wantUdp = settings.discordMode || SubscriptionController.discordRunning();
    final shortlist = NodePool.failoverShortlist(
      excludeId: deadNode.id,
      groupNodes: groupId == null ? sub.nodes : ref.read(groupNodesProvider(groupId)),
      allNodes: sub.nodes,
      preferAi: deadNode.aiReachable,
      preferUdpNative: wantUdp,
      exclude: sub.quarantined,
    );

    // Свежий замер кандидатов: старые пинги из проверки подписки могли
    // устареть. Если пробы шли бы через сам VPN (Android, режим Xray), честно
    // замерить кандидатов нельзя: медленный текущий сервер тогда не меняем, а
    // мёртвый — меняем по последним данным (в рамках потолка задержки).
    final canMeasure = _bridge.probesBypassTunnel;
    if (!canMeasure && _lastHealthMs >= 0) {
      log.i('Кандидатов не замерить мимо VPN — медленный сервер не меняем', tag: 'VPN');
      _isFailingOver = false;
      _startHealthMonitor(mySession);
      return;
    }
    final fresh = shortlist.isEmpty
        ? const <String, int>{}
        : canMeasure
            ? await DeepProbe(singboxExePath: BinaryManager.instance.singboxExe.path).measure(shortlist)
            : {for (final n in shortlist) n.id: FailoverPolicy.storedAsFreshMs(n)};
    if (mySession != _sessionId || state is! VpnConnected) {
      _isFailingOver = false;
      return;
    }
    final next = FailoverPolicy.choose(
      candidates: shortlist,
      fresh: fresh,
      currentMs: _lastHealthMs,
      preferUdp: wantUdp,
      preferAi: deadNode.aiReachable,
    );

    if (next == null) {
      log.w(
        'Стабильной замены нет (кандидатов ${shortlist.length}, '
        'замеры $fresh, текущий $_lastHealthMs мс) — остаёмся на ${deadNode.name}',
        tag: 'VPN',
      );
      _noBetterUntil = DateTime.now().add(FailoverPolicy.backoff);
      final text = 'Стабильного сервера сейчас нет — остаёмся на ${deadNode.name}';
      _notifyUnstable(text);
      ref.read(connectPhaseProvider.notifier).state = ConnectPhase.notice(
        '$text. Позже нажмите «Обновить» или добавьте свой сервер.',
        kind: NoticeKind.warning,
      );
      _isFailingOver = false;
      _startHealthMonitor(mySession);
      return;
    }

    final ms = fresh[next.id];
    await disconnect();
    ref.read(subscriptionProvider.notifier).markNodeAsDead(deadNode.id);
    _lastAutoSwitch = DateTime.now();
    _noBetterUntil = null;

    log.i('🚀 Переключаемся на ${next.name} ($ms мс)', tag: 'VPN');
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
        ? ConnectPhase.notice('Переключились: ${deadNode.name} → ${next.name}', kind: NoticeKind.switched)
        : ConnectPhase.idle;
  }

  /// Сторож моста: через 8 с после подключения через туннель 0 байт. Это ещё
  /// не значит, что сервер мёртв (#69): человек мог просто ничего не открыть.
  /// Сначала проба через туннель; ответила — не трогаем сервер.
  Future<void> _onNoTraffic(int mySession) async {
    final ms = await _bridge.measureLatency();
    if (mySession != _sessionId || state is! VpnConnected) return;
    if (ms >= 0) {
      log.i('WATCHDOG: трафика не было, но туннель отвечает ($ms мс) — сервер не меняем', tag: 'VPN');
      return;
    }
    await _failover(mySession, watchdog: true);
  }

  /// Уведомление «сервер нестабилен» — не чаще [FailoverPolicy.notifyEvery]
  /// (раньше при долгой деградации приходило каждые 20–30 с).
  void _notifyUnstable(String text) {
    final now = DateTime.now();
    final last = _lastUnstableNotice;
    if (last != null && now.difference(last) < FailoverPolicy.notifyEvery) return;
    _lastUnstableNotice = now;
    unawaited(_notif.show(
      nodeName: text,
      rxBytes: _lastRx,
      txBytes: _lastTx,
      connected: true,
    ));
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
        unawaited(_onNoTraffic(_sessionId));
        return;
      }

      log.e('Мост сообщил об ошибке: $error', tag: 'VPN');
      final current = state;
      final node = current is VpnConnected ? current.node : null;
      state = VpnError(message: error, node: node);
      // Туннель упал сам, пока был поднят (ядро завершилось, Android-сторож):
      // пробуем восстановить — тот же сервер, затем по правилам автопилота.
      if (current is VpnConnected && !_isFailingOver) {
        _healthTimer?.cancel();
        _bgProbeTimer?.cancel();
        unawaited(_recover('после сбоя'));
      }
    });
  }

  @override
  void dispose() {
    _sessionId++;
    _healthTimer?.cancel();
    _bgProbeTimer?.cancel();
    _netSub?.cancel();
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

/// Действует ли автопереключение на самом деле (#60): тумблер включён и
/// сервер не выбран вручную — с ручного выбора Onyx сам не уводит. Для
/// плашки «Автопереключение» на главной.
final autoFailoverActiveProvider = Provider<bool>((ref) =>
    ref.watch(settingsProvider).autoFailover && ref.watch(nodeSelectionProvider) == null);
