import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/log_service.dart';
import '../domain/cidr_utils.dart';
import '../domain/entities/node.dart';
import '../domain/routing_domains.dart';
import '../domain/routing_region.dart';
import '../domain/singbox_config_builder.dart';
import '../domain/udp_probe.dart';
import 'binary_manager.dart';
import 'singbox_bridge.dart';

/// Android-мост поверх flutter_v2ray 1.0.10.
///
/// ─── ВАЖНО: ограничения плагина, найденные при разборе его исходников ──────
///
/// 1. `dns.servers` в конфиге — ТОЛЬКО плоские IPv4-строки.
///    V2rayVPNService.setup() плагина проходит по dns.servers и для КАЖДОГО
///    элемента вызывает VpnService.Builder.addDnsServer(getString(i)).
///    Android-овский org.json приводит НЕ-строки (объекты) к их JSON-тексту,
///    а addDnsServer() принимает только числовой IP. Любая DoH-ссылка
///    ('https://8.8.8.8/dns-query'), 'localhost' или объект вида
///    {'address': ..., 'domains': [...]} → IllegalArgumentException, который
///    пролетает мимо catch(JSONException) плагина, валит setup() → runLoop
///    v2ray-core падает → VPN-интерфейс НЕ создаётся вовсе.
///    Именно это и было корнем симптома B (см. CHANGELOG).
///
/// 2. Статус-стрим плагина живёт на CountDownTimer(7200, 1000) — ~7 тиков по
///    секунде, затем onFinish() перезапускает таймер ТОЛЬКО если
///    v2RayPoint.getIsRunning() == true. Если core не стартовал, стрим
///    замолкает навсегда ровно на ~8-й секунде — та самая "жёстко зашитая
///    константа", которую искали. При живом core стрим тикает бесконечно,
///    но на всякий случай у нас есть резервный watchdog (_statusWatchdog).
///
/// 3. `bypassSubnets` — это НЕ "исключить подсети", а allowlist маршрутов
///    VpnService ("захватывать только эти подсети"). Подробно — в
///    cidr_utils.dart. Поэтому для умной маршрутизации мы передаём туда
///    КОМПЛЕМЕНТ RU-подсетей.
///
/// 4. geoip:/geosite:-матчеры в routing/dns НЕ работают: приложение не
///    бандлит geoip.dat/geosite.dat, плагин их не поставляет, а Xray при
///    ссылке на отсутствующую БД не стартует. Используем только явные
///    domain:-суффиксы и CIDR-списки (routing_domains.dart).
class SingboxBridgeAndroid implements SingboxBridge {
  SingboxBridgeAndroid._();
  static final instance = SingboxBridgeAndroid._();

  BridgeState _state = BridgeState.idle;

  final _stateCtrl = StreamController<BridgeState>.broadcast();
  final _statsCtrl = StreamController<(int rx, int tx)>.broadcast();
  final _errorCtrl = StreamController<String>.broadcast();

  bool _initialized = false;

  /// Время последнего события из статус-стрима плагина. Используется
  /// резервным watchdog-ом: если нативный стрим замолчал, состояние
  /// подтверждается независимой проверкой через v2ray-core.
  DateTime? _lastStatusEventAt;
  Timer? _statusWatchdog;
  int _watchdogMisses = 0;

  /// Ждун первого CONNECTED от плагина (см. start()).
  Completer<bool>? _connectedCompleter;

  late final FlutterV2ray _v2ray = FlutterV2ray(
    onStatusChanged: (V2RayStatus status) {
      _lastStatusEventAt = DateTime.now();

      log.i('[V2RAY] state=${status.state} '
          'duration=${status.duration} '
          'upload=${status.upload} '
          'download=${status.download}', tag: 'BRIDGE');

      switch (status.state) {
        case 'CONNECTED':
          _setState(BridgeState.running);
          final c = _connectedCompleter;
          if (c != null && !c.isCompleted) c.complete(true);
        case 'CONNECTING':
          if (_state != BridgeState.running) {
            _setState(BridgeState.starting);
          }
        case 'DISCONNECTED':
          if (_state != BridgeState.idle) {
            _setState(BridgeState.idle);
          }
        case 'ERROR':
          _setState(BridgeState.error);
          _errorCtrl.add('V2Ray connection error');
          // Если мы прямо сейчас ждём подтверждения туннеля в start(),
          // нет смысла досиживать дедлайн — сообщаем о провале сразу.
          final ec = _connectedCompleter;
          if (ec != null && !ec.isCompleted) ec.complete(false);
      }

      // Emit traffic stats on every status update
      if (status.state == 'CONNECTED') {
        _statsCtrl.add((
          status.download.toInt(),
          status.upload.toInt(),
        ));
      }
    },
  );

  @override
  Future<void> ensureBinaries({
    void Function(String, double?)? onStatus,
  }) async {
    if (!_initialized) {
      await _v2ray.initializeV2Ray(
        notificationIconResourceType: 'mipmap',
        notificationIconResourceName: 'ic_launcher',
      );
      _initialized = true;
    }
    onStatus?.call('Готово', 1.0);
  }

  @override
  bool get binariesReady => true;

  @override
  Future<BridgeResult> start(
    Node node, {
    List<Node> fallbacks = const [],
    RoutingOptions routing = const RoutingOptions(),
    List<String> excludedApps = const [],
  }) async {
    final smartRouting = routing.smartRouting;
    final aiDirectLane = routing.aiDirectLane;
    if (_state == BridgeState.running || _state == BridgeState.starting) {
      return const BridgeResult(success: false, error: 'Уже запущен');
    }

    _setState(BridgeState.starting);
    log.i('Запускаем V2Ray для ${node.name} (Android)', tag: 'BRIDGE');
    log.d(
      'smartRouting=$smartRouting aiDirectLane=$aiDirectLane '
      'excludedApps=${excludedApps.length}',
      tag: 'BRIDGE',
    );

    try {
      if (!_initialized) await ensureBinaries();

      // Android 13+ (API 33) требует явного runtime-разрешения на показ
      // ЛЮБЫХ уведомлений, включая foreground-уведомление активного
      // VpnService. Без этого разрешения ни родное уведомление плагина,
      // ни наше собственное (VpnNotificationService) не покажутся —
      // без ошибки, просто молча. На более старых версиях Android
      // Permission.notification.request() возвращает granted сразу,
      // диалог не показывается.
      //
      // Намеренно не блокируем подключение, если пользователь отказал —
      // VPN должен продолжать работать, просто без уведомления о статусе.
      final notifStatus = await Permission.notification.status;
      if (notifStatus.isDenied) {
        final result = await Permission.notification.request();
        log.i('Разрешение на уведомления: $result', tag: 'BRIDGE');
      }

      final allowed = await _v2ray.requestPermission();
      if (!allowed) {
        _setState(BridgeState.idle);
        return const BridgeResult(
          success: false,
          error: 'VPN permission denied by user',
        );
      }

      // ── Выбор режима: Xray напрямую или цепочка Xray → sing-box ─────────
      //
      // Xray из flutter_v2ray умеет только то, что умел в 2024-м (VLESS и
      // старые протоколы). Hysteria2/TUIC/AnyTLS, автопереключение
      // транспорта и регион «Китай» (rule-set geosite-cn/geoip-cn)
      // обслуживает sing-box из libsingbox.so, запущенный как локальный
      // прокси. Проверенный VLESS-путь для России/Беларуси не меняем.
      final useChain = node.protocol != NodeProtocol.vless ||
          fallbacks.isNotEmpty ||
          (smartRouting && routing.region == RoutingRegion.china);

      final String config;
      List<String>? captureRoutes;
      var blockedApps = List<String>.from(excludedApps);

      if (useChain) {
        await _startChain(node, fallbacks, routing);
        config = _buildChainXrayConfig();
        // Своё приложение — мимо VPN: иначе сокеты sing-box (к серверу и
        // direct) снова попадут в туннель и замкнутся в петлю.
        blockedApps = {...blockedApps, _ownPackage}.toList();
        // Захватываем всё: регион и обход решает sing-box (rule-set).
        captureRoutes = null;
        log.i(
          'Режим цепочки: Xray → sing-box ($_chainPort) → '
          '${[node, ...fallbacks].map((n) => NodeProtocol.label(n.protocol)).join(" + ")}',
          tag: 'BRIDGE',
        );
      } else {
        // Resolve server IP before VPN starts to prevent routing loop
        final resolvedIp = await _resolveServerIp(node.host);
        log.i('Resolved ${node.host} → $resolvedIp', tag: 'BRIDGE');

        // Build vless:// share link from Node and parse it
        final shareLink = node.toShareLink();
        log.d('Share link: $shareLink', tag: 'BRIDGE');

        final V2RayURL parsed = FlutterV2ray.parseFromURL(shareLink);

        // Sniffing: без него Xray видит только IP от tun2socks и доменные
        // правила (AI-lane, RU-CDN, Discord) не срабатывают. routeOnly —
        // домен используется только для маршрутизации, адрес не подменяется.
        parsed.inbound['sniffing'] = {
          'enabled': true,
          'destOverride': ['http', 'tls', 'quic'],
          'routeOnly': true,
        };

        // DNS: только плоские IP (см. ограничение №1 в шапке файла).
        parsed.dns = _buildDns();

        // Routing: без geoip/geosite (ограничение №4), с AI Direct Lane.
        parsed.routing = _buildRouting(
          resolvedServerIp: resolvedIp,
          smartRouting: smartRouting,
          aiDirectLane: aiDirectLane,
          discordMode: routing.discordMode,
        );

        config = parsed.getFullConfiguration();

        // ── Исключение RU-подсетей на уровне VpnService ───────────────────
        //
        // ВНИМАНИЕ: bypassSubnets у плагина — allowlist захватываемых
        // маршрутов (см. ограничение №3). Чтобы ИСКЛЮЧИТЬ RU-подсети из
        // туннеля, передаём их комплемент: "всё пространство, кроме RU".
        // При выключенной умной маршрутизации — null → плагин сам добавит
        // маршрут 0.0.0.0/0 (захват всего трафика).
        captureRoutes = smartRouting ? complementCidrs(kRuBypassSubnets) : null;
        if (captureRoutes != null) {
          log.d(
            'VpnService-маршруты: ${captureRoutes.length} CIDR '
            '(комплемент ${kRuBypassSubnets.length} RU-подсетей)',
            tag: 'BRIDGE',
          );
        }
      }
      log.d('V2Ray config: $config', tag: 'BRIDGE');

      // Подготовка к ожиданию реального CONNECTED (см. ниже).
      final connected = Completer<bool>();
      _connectedCompleter = connected;

      await _v2ray.startV2Ray(
        remark: node.name,
        config: config,
        // Split tunneling: плагин добавляет каждый пакет в
        // VpnService.Builder.addDisallowedApplication() — эти приложения
        // работают в обход VPN.
        blockedApps: blockedApps.isEmpty ? null : blockedApps,
        bypassSubnets: captureRoutes,
        proxyOnly: false,
        // Кнопка "Отключить" в родном уведомлении плагина (то самое
        // системное foreground-уведомление, которое Android требует для
        // любого активного VpnService и убрать нельзя). Эта кнопка
        // останавливает VPN на нативном уровне и триггерит наш
        // onStatusChanged → DISCONNECTED; состояние в Riverpod обновится,
        // потому что VpnController слушает stateStream моста.
        notificationDisconnectButtonName: 'ОТКЛЮЧИТЬ',
      );

      // ── Ждём РЕАЛЬНОГО подтверждения туннеля ────────────────────────────
      //
      // startV2Ray() — fire-and-forget: он резолвится сразу после отправки
      // Intent сервису, задолго до того, как v2ray-core реально поднимет
      // туннель (или упадёт при старте). Раньше мы возвращали success сразу
      // и UI показывал "подключено" на мёртвом туннеле.
      //
      // Теперь success возвращается только когда:
      //   а) плагин прислал state=CONNECTED, ЛИБО
      //   б) нативный стрим молчит, но независимая проверка через сам
      //      v2ray-core (getConnectedServerDelay) подтвердила связность —
      //      резерв на случай, если стрим статуса умер, а туннель жив.
      final ok = await _awaitConnected(connected);
      _connectedCompleter = null;

      if (!ok) {
        log.e(
          'Туннель не подтвердился за отведённое время — останавливаем',
          tag: 'BRIDGE',
        );
        try {
          await _v2ray.stopV2Ray();
        } catch (_) {}
        await _stopChain();
        _setState(BridgeState.error);
        return const BridgeResult(
          success: false,
          error: 'Туннель не поднялся: нет подтверждения от V2Ray-ядра. '
              'Попробуйте другой сервер.',
        );
      }

      _setState(BridgeState.running);
      _startStatusWatchdog();

      log.i('V2Ray started for ${node.name}', tag: 'BRIDGE');
      return const BridgeResult(success: true);
    } catch (e, stack) {
      _connectedCompleter = null;
      await _stopChain();
      log.e('Start error: $e', tag: 'BRIDGE');
      log.d('Stack: $stack', tag: 'BRIDGE');
      _setState(BridgeState.error);
      return BridgeResult(success: false, error: e.toString());
    }
  }

  /// Ожидание подтверждения туннеля: событие CONNECTED от плагина
  /// (быстрый путь) или успешная проверка через v2ray-core (резерв).
  /// Событие ERROR завершает ожидание немедленно. Общий дедлайн — 25 секунд.
  Future<bool> _awaitConnected(Completer<bool> connected) async {
    final deadline = DateTime.now().add(const Duration(seconds: 25));

    // Быстрый путь: большинство подключений подтверждаются (или падают
    // с ERROR) в первые секунды.
    try {
      return await connected.future.timeout(const Duration(seconds: 6));
    } on TimeoutException {
      // Стрим молчит — переходим к активной проверке.
    }

    while (DateTime.now().isBefore(deadline)) {
      if (connected.isCompleted) return connected.future;
      if (await verifyTunnel()) {
        log.i(
          'Статус-стрим молчит, но v2ray-core подтвердил связность — '
          'считаем туннель поднятым',
          tag: 'BRIDGE',
        );
        return true;
      }
      await Future.delayed(const Duration(seconds: 3));
    }
    if (connected.isCompleted) return connected.future;
    return false;
  }

  /// Резервный монитор статуса: если нативный стрим плагина замолчал
  /// (Doze, гибель CountDownTimer-а, любой другой сбой репортинга),
  /// подтверждаем/опровергаем состояние независимой проверкой через
  /// сам v2ray-core, а не слепо доверяем мёртвому стриму.
  void _startStatusWatchdog() {
    _statusWatchdog?.cancel();
    _watchdogMisses = 0;
    _statusWatchdog = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (_state != BridgeState.running) return;

      final last = _lastStatusEventAt;
      final silentFor = last == null
          ? const Duration(days: 1)
          : DateTime.now().difference(last);
      if (silentFor < const Duration(seconds: 12)) {
        _watchdogMisses = 0;
        return; // стрим живой — ничего не делаем
      }

      final alive = await verifyTunnel();
      if (alive) {
        _watchdogMisses = 0;
        log.d(
          'Watchdog: стрим статуса молчит ${silentFor.inSeconds}с, '
          'но туннель жив (подтверждено core)',
          tag: 'BRIDGE',
        );
        return;
      }

      _watchdogMisses++;
      log.w(
        'Watchdog: стрим молчит и core не отвечает '
        '($_watchdogMisses/2)',
        tag: 'BRIDGE',
      );
      if (_watchdogMisses >= 2) {
        _statusWatchdog?.cancel();
        _errorCtrl.add('Туннель перестал отвечать');
        _setState(BridgeState.error);
      }
    });
  }

  @override
  Future<bool> verifyTunnel() async {
    try {
      // Задержка меряется САМИМ v2ray-core через его connected-outbound:
      // положительное значение возможно только при живом туннеле.
      // При мёртвом/незапущенном core плагин возвращает -1.
      final delay = await _v2ray
          .getConnectedServerDelay(url: 'https://cp.cloudflare.com/generate_204')
          .timeout(const Duration(seconds: 10));
      return delay >= 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<int> measureLatency() async {
    try {
      // getConnectedServerDelay меряет задержку самим v2ray-core через
      // connected-outbound: возвращает мс при живом туннеле, -1 при мёртвом.
      // Это ровно то, что нужно для детекта деградации, и почти бесплатно.
      final delay = await _v2ray
          .getConnectedServerDelay(url: 'https://cp.cloudflare.com/generate_204')
          .timeout(const Duration(seconds: 5), onTimeout: () => -1);
      return delay;
    } catch (_) {
      return -1;
    }
  }

  @override
  Future<void> stop() async {
    log.i('Stopping V2Ray...', tag: 'BRIDGE');
    _statusWatchdog?.cancel();
    _statusWatchdog = null;
    _connectedCompleter = null;
    await _v2ray.stopV2Ray();
    await _stopChain();
    _setState(BridgeState.idle);
  }

  @override
  Stream<BridgeState> get stateStream => _stateCtrl.stream;
  @override
  Stream<(int rx, int tx)> get statsStream => _statsCtrl.stream;
  @override
  Stream<String> get errorStream => _errorCtrl.stream;
  @override
  BridgeState get state => _state;

  void _setState(BridgeState s) {
    if (_state == s) return;
    _state = s;
    _stateCtrl.add(s);
  }

  Future<String?> _resolveServerIp(String host) async {
    if (_isIpAddress(host)) return null;
    try {
      final addresses = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 5));
      final ipv4 = addresses
          .where((a) => a.type == InternetAddressType.IPv4)
          .firstOrNull;
      return ipv4?.address ?? addresses.firstOrNull?.address;
    } catch (_) {
      return null;
    }
  }

  bool _isIpAddress(String host) =>
      RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host) ||
          host.contains(':');

  // ── Цепочка Xray → sing-box ────────────────────────────────────────────

  static const _ownPackage = 'z43.studios.onyx';
  static const _chainPort = 2081;
  static const _xraySocksPort = 10808;

  Process? _chainProcess;

  /// Запускает sing-box (libsingbox.so) как локальный mixed-прокси.
  Future<void> _startChain(
    Node node,
    List<Node> fallbacks,
    RoutingOptions routing,
  ) async {
    await _stopChain();
    final binMgr = BinaryManager.instance;
    await binMgr.ensureBinaries(); // rule-set → binDir
    final dir = binMgr.binDir.path;
    final config = const SingboxConfigBuilder().buildChainConfig(
      node,
      fallbacks: fallbacks,
      listenPort: _chainPort,
      routing: RoutingOptions(
        smartRouting: routing.smartRouting,
        region: routing.region,
        aiDirectLane: routing.aiDirectLane,
        discordMode: routing.discordMode,
        ruleSetDir: dir,
      ),
      cacheFilePath: '$dir/chain-cache.db',
    );
    final file = File('$dir/chain.json');
    await file.writeAsString(const SingboxConfigBuilder().buildJson(config), flush: true);

    final proc = await Process.start(
      binMgr.singboxExe.path,
      ['run', '-c', file.path],
      workingDirectory: dir,
    );
    _chainProcess = proc;
    proc.stderr
        .transform(const SystemEncoding().decoder)
        .listen((l) => log.d(l.trim(), tag: 'SINGBOX'));
    proc.stdout
        .transform(const SystemEncoding().decoder)
        .listen((l) => log.d(l.trim(), tag: 'SINGBOX'));
    var exited = false;
    unawaited(proc.exitCode.then((code) {
      exited = true;
      if (identical(_chainProcess, proc)) {
        log.w('sing-box (цепочка) завершился с кодом $code', tag: 'BRIDGE');
        if (_state == BridgeState.running) {
          _errorCtrl.add('sing-box неожиданно завершился (код $code)');
          _setState(BridgeState.error);
        }
      }
    }));

    // Ждём, пока mixed-inbound начнёт принимать соединения.
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (DateTime.now().isBefore(deadline)) {
      if (exited) {
        throw Exception('sing-box не запустился — проверьте ноду (см. лог SINGBOX)');
      }
      try {
        final s = await Socket.connect('127.0.0.1', _chainPort,
            timeout: const Duration(milliseconds: 500));
        s.destroy();
        log.i('sing-box (цепочка) слушает 127.0.0.1:$_chainPort', tag: 'BRIDGE');
        return;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }
    await _stopChain();
    throw Exception('sing-box не открыл порт $_chainPort за 8 секунд');
  }

  Future<void> _stopChain() async {
    final p = _chainProcess;
    _chainProcess = null;
    if (p == null) return;
    try {
      p.kill();
      await p.exitCode.timeout(const Duration(seconds: 2), onTimeout: () {
        p.kill(ProcessSignal.sigkill);
        return -1;
      });
    } catch (_) {}
  }

  /// Конфиг Xray для цепочки: всё из TUN → socks-outbound в sing-box.
  /// Маршрутизацию (регион, Discord, ИИ) делает sing-box.
  String _buildChainXrayConfig() {
    final cfg = {
      'log': {'loglevel': 'warning'},
      'inbounds': [
        {
          'tag': 'in_proxy',
          'port': _xraySocksPort,
          'protocol': 'socks',
          'listen': '127.0.0.1',
          'settings': {'auth': 'noauth', 'udp': true, 'userLevel': 8},
        },
      ],
      'outbounds': [
        {
          // ПЕРВЫЙ outbound: плагин читает из него адрес сервера
          // (settings.servers[0]) для своего уведомления.
          'tag': 'proxy',
          'protocol': 'socks',
          'settings': {
            'servers': [
              {'address': '127.0.0.1', 'port': _chainPort},
            ],
          },
        },
        {'tag': 'direct', 'protocol': 'freedom'},
        {'tag': 'blackhole', 'protocol': 'blackhole'},
      ],
      // Только плоские IP — ограничение №1. DNS-пакеты к ним уходят в
      // sing-box и перехватываются там (hijack-dns).
      'dns': _buildDns(),
      'routing': {
        'domainStrategy': 'AsIs',
        'rules': [
          {
            'type': 'field',
            'ip': kPrivateCidrs,
            'outboundTag': 'direct',
          },
        ],
      },
    };
    return const JsonEncoder.withIndent('  ').convert(cfg);
  }

  @override
  Future<UdpProbeResult> checkUdp() async {
    if (_state != BridgeState.running) {
      return const UdpProbeResult.failed('VPN не подключён');
    }
    // socks-inbound Xray (udp: true) — общий вход для обоих режимов.
    // Наше приложение исключено из VPN только в режиме цепочки, а к
    // 127.0.0.1 ходит напрямую в любом режиме.
    return UdpProbe.viaSocks5(_xraySocksPort);
  }

  // ── DNS ──────────────────────────────────────────────────────────────────
  //
  // ТОЛЬКО плоские IPv4-строки — жёсткое требование плагина (ограничение №1
  // в шапке файла). Никаких DoH-URL, 'localhost' или объектов с 'domains'.
  //
  // Утечек DNS при этом нет: VpnService направляет DNS-запросы устройства
  // в TUN, внутри v2ray-core резолв идёт через эти серверы, а сами
  // DNS-пакеты к 1.1.1.1/8.8.8.8 маршрутизируются routing-правилами в
  // outbound 'proxy' — то есть уходят провайдеру уже зашифрованными внутри
  // VLESS. ТСПУ видит только TLS-поток к VPN-серверу.
  Map<String, dynamic> _buildDns() => {
        'servers': [
          '1.1.1.1',
          '8.8.8.8',
        ],
        'queryStrategy': 'UseIPv4',
      };

  // ── Routing ──────────────────────────────────────────────────────────────

  Map<String, dynamic> _buildRouting({
    String? resolvedServerIp,
    bool smartRouting = true,
    bool aiDirectLane = true,
    bool discordMode = true,
  }) {
    final rules = <Map<String, dynamic>>[
      // Режим Discord: домены Discord — строго в туннель, раньше всего.
      // (Голос идёт по IP voice-серверов и попадает в туннель и так:
      // их адреса не входят в RU-исключения.)
      if (discordMode)
        {
          'type': 'field',
          'domain': [for (final d in kDiscordDomainSuffixes) 'domain:$d'],
          'outboundTag': 'proxy',
        },
      // ── AI Direct Lane: максимальный приоритет ──────────────────────────
      // Домены ИИ-сервисов всегда идут строго в 'proxy', раньше любых
      // direct-правил умной маршрутизации. DNS для них резолвится
      // v2ray-core через серверы из _buildDns(), чьи запросы сами уходят
      // через туннель — утечки DNS/гео нет.
      if (aiDirectLane)
        {
          'type': 'field',
          'domain': [for (final d in kAiDomainSuffixes) 'domain:$d'],
          'outboundTag': 'proxy',
        },
      // Локальные адреса никогда не идут через прокси.
      // Явные CIDR вместо geoip:private — geoip.dat на Android недоступен
      // (ограничение №4 в шапке файла).
      {
        'type': 'field',
        'ip': kPrivateCidrs,
        'outboundTag': 'direct',
      },
      if (resolvedServerIp != null)
        {
          'type': 'field',
          'ip': ['$resolvedServerIp/32'],
          'outboundTag': 'direct',
        },
      if (smartRouting) ...[
        {
          'type': 'field',
          // 'domain:суффикс' в v2ray = сам домен + все поддомены.
          // Явный список вместо geosite:ru — geosite.dat недоступен.
          'domain': [for (final d in kRuCdnDomainSuffixes) 'domain:$d'],
          'outboundTag': 'direct',
        },
        // IP-уровневый обход RU-подсетей реализован на уровне VpnService
        // (см. captureRoutes в start()) — правило geoip:ru здесь не нужно
        // и не работало бы без geoip.dat.
      ],
    ];

    return {
      'domainStrategy': 'IPIfNonMatch',
      'rules': rules,
    };
  }
}
