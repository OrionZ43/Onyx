export 'singbox_bridge.dart';
import 'singbox_bridge.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import '../domain/udp_probe.dart';
import '../core/log_service.dart';
import '../domain/entities/node.dart';
import '../domain/singbox_config_builder.dart';
import 'binary_manager.dart';
import 'singbox_api_client.dart';
import 'win_child_guard.dart';


/// Windows-реализация sing-box моста.
///
/// Жизненный цикл:
///   start() → [проверка бинарников] → [резолв IP сервера] →
///   [запись конфига] → [запуск sing-box.exe] → [ожидание API] → running
///   stop()  → [SIGTERM sing-box.exe] → idle
///
/// Трафик-статистика берётся из Clash API (9090).
class SingboxBridgeWindows implements SingboxBridge {
  SingboxBridgeWindows._();
  static final instance = SingboxBridgeWindows._();

  static const _apiPort = 9090;

  final _binMgr = BinaryManager.instance;
  final _apiClient = SingboxApiClient(port: _apiPort);
  final _builder = const SingboxConfigBuilder();

  Process? _process;
  Timer? _statsTimer;
  Timer? _trafficWatchdog;
  BridgeState _state = BridgeState.idle;

  // ИСПРАВЛЕНО: права администратора кэшируются на весь срок жизни
  // процесса. Windows не позволяет процессу "приобрести" права после
  // старта — либо requireAdministrator в манифесте отработал при запуске,
  // либо нет. Раньше _checkAdmin() спавнил `net session` (внешний процесс,
  // десятки-сотни мс) на КАЖДЫЙ connect(), хотя результат не может
  // измениться между вызовами в рамках одного запуска приложения.
  bool? _isAdminCached;

  // Стримы для UI
  final _stateCtrl = StreamController<BridgeState>.broadcast();
  final _statsCtrl = StreamController<(int rx, int tx)>.broadcast();
  final _errorCtrl = StreamController<String>.broadcast();

  @override
  Stream<BridgeState> get stateStream => _stateCtrl.stream;
  @override
  Stream<(int rx, int tx)> get statsStream => _statsCtrl.stream;
  @override
  Stream<String> get errorStream => _errorCtrl.stream;
  @override
  BridgeState get state => _state;

  // Пробы — отдельные sing-box.exe: правило process_name → direct выводит их
  // мимо TUN. Сам onyx.exe TUN ловит.
  @override
  bool get probesBypassTunnel => true;

  @override
  bool get appTrafficBypassesTunnel => _state != BridgeState.running;

  // ── Публичный API ──────────────────────────────────────────────────────

  /// Скачивает бинарники если нужно. Вызывать при старте приложения.
  @override
  Future<void> ensureBinaries({
    void Function(String status, double? progress)? onStatus,
  }) async {
    await _binMgr.ensureBinaries(onStatus: onStatus);
  }

  @override
  bool get binariesReady => _binMgr.isReady;

  /// Запускает VPN-туннель для [node].
  ///
  /// [excludedApps] (split tunneling) на Windows не поддерживается —
  /// параметр игнорируется. Per-app маршрутизация возможна только через
  /// WFP-фильтры по PID, что требует отдельного драйверного решения.
  @override
  Future<BridgeResult> start(
      Node node, {
        List<Node> fallbacks = const [],
        RoutingOptions routing = const RoutingOptions(),
        List<String> excludedApps = const [],
      }) async {
    if (_state == BridgeState.running || _state == BridgeState.starting) {
      return const BridgeResult(success: false, error: 'Уже запущен');
    }

    _setState(BridgeState.starting);
    log.i('Запускаем sing-box для ${node.name}', tag: 'BRIDGE');

    try {
      // 1. Бинарники: раскладываем бандл установщика или обновляем версию
      // (без сети, если установщик положил core\).
      await _binMgr.ensureBinaries();

      // 2. Проверяем права администратора (результат кэшируется —
      // см. комментарий у _isAdminCached)
      final isAdmin = await _checkAdmin();
      if (!isAdmin) {
        log.w('Нет прав администратора — WinTUN требует прав!', tag: 'BRIDGE');
      } else {
        log.i('Права администратора: OK', tag: 'BRIDGE');
      }

      // 3. Резолвим IP сервера ДО создания TUN-интерфейса.
      //
      // Зачем: правило `domain: [node.host]` в route не работает для
      // сырых IP-пакетов из WinTUN. Нужен ip_cidr, а для него нужен IP.
      // Резолвим сейчас — пока TUN не поднят и системный DNS доступен.
      // IP нужны для ВСЕХ серверов группы автопереключения.
      final serverIps = <String>{};
      for (final n in [node, ...fallbacks]) {
        final ip = _isIpAddress(n.host) ? n.host : await _resolveServerIp(n.host);
        if (ip != null) serverIps.add(ip);
      }

      // 4. Генерируем конфиг. Clash API защищён случайным секретом:
      // без него любой локальный процесс мог управлять туннелем.
      final secret = _newSecret();
      _apiClient.secret = secret;
      final config = _builder.buildTunConfig(
        node,
        fallbacks: fallbacks,
        serverIps: serverIps.toList(),
        socksPort: 2080,
        routing: routing,
        clashSecret: secret,
        clashPort: _apiPort,
      );
      if (fallbacks.isNotEmpty) {
        log.i(
          'Автопереключение транспорта: ${[node, ...fallbacks].map((n) => n.protocol).join(" + ")}',
          tag: 'BRIDGE',
        );
      }

      final configJson = _builder.buildJson(config);

      // Дамп конфига в лог. ВАЖНО: этот дамп содержит uuid/reality-ключи
      // в открытом виде — это ожидаемо для локальной отладки (тег CFG
      // виден только на экране логов), но LogService.exportText()
      // маскирует эти поля перед копированием/отправкой, так что секрет
      // не покидает устройство при "Скопировать лог".
      log.d('=== ПОЛНЫЙ КОНФИГ SING-BOX ===', tag: 'BRIDGE');
      for (final line in configJson.split('\n')) {
        log.d(line, tag: 'CFG');
      }
      log.d('=== КОНЕЦ КОНФИГА ===', tag: 'BRIDGE');

      await _binMgr.writeConfig(configJson);
      log.d('Конфиг записан: ${_binMgr.configFile.path}', tag: 'BIN');
      log.d('Конфиг записан для ноды: ${node.name}', tag: 'BRIDGE');
      log.d('API порт: $_apiPort', tag: 'BRIDGE');

      // 5. Завершаем старый процесс если висит
      await _killExisting();

      // 6–8. Запуск sing-box.exe и ожидание API. Один повтор при ошибке TUN:
      // при быстром переподключении Windows ещё не успевает удалить старый
      // адаптер WinTUN → «create adapter: Cannot create a file when that file
      // already exists». Через пару секунд адаптер исчезает и старт проходит.
      var ready = false;
      for (var attempt = 0; attempt < 2 && !ready; attempt++) {
        _stderrTail.clear();
        log.i('Запускаем: ${_binMgr.singboxExe.path}', tag: 'BRIDGE');
        final proc = await Process.start(
          _binMgr.singboxExe.path,
          ['run', '--config', _binMgr.configFile.path],
          workingDirectory: _binMgr.singboxExe.parent.path,
          mode: ProcessStartMode.normal,
        );
        _process = proc;
        log.i('sing-box PID: ${proc.pid}', tag: 'BRIDGE');
        // Туннель не переживает onyx.exe даже при падении или «Снять задачу»:
        // иначе WinTUN с маршрутами остаётся без хозяина (#57).
        WinChildGuard.adopt(proc.pid);

        // sing-box пишет ВСЕ свои логи в stderr — это штатно.
        proc.stdout.transform(const SystemEncoding().decoder).listen(_parseSingboxOutput);
        proc.stderr.transform(const SystemEncoding().decoder).listen(_parseSingboxOutput);

        var exited = false;
        final exitFuture = proc.exitCode.then((code) {
          exited = true;
          log.w('sing-box завершился с кодом: $code', tag: 'BRIDGE');
          if (identical(_process, proc) && _state == BridgeState.running) {
            _errorCtrl.add('sing-box неожиданно завершился (код $code)');
            _setState(BridgeState.error);
            _stopStats();
            _stopTrafficWatchdog();
          }
          return false;
        });

        log.i('Ждём готовности API sing-box...', tag: 'BRIDGE');
        // Не ждём все 15 с, если процесс уже упал.
        ready = await Future.any([
          _apiClient.waitReady(timeout: const Duration(seconds: 15)),
          exitFuture,
        ]);
        if (ready) break;

        await _killProcess();
        final tunBusy = _stderrTail.toString().contains('configure tun interface');
        if (attempt == 0 && tunBusy) {
          log.w('WinTUN-адаптер ещё не освобождён — повторяем запуск через 3 с', tag: 'BRIDGE');
          await Future.delayed(const Duration(seconds: 3));
          continue;
        }
        throw Exception(exited
            ? 'sing-box завершился при запуске: ${_lastFatal() ?? 'см. лог'}'
            : 'sing-box не ответил за 15 секунд. Возможно, не хватает прав администратора.');
      }

      final version = await _apiClient.getVersion();
      log.i('sing-box готов! Версия: $version', tag: 'BRIDGE');

      // 9. Запускаем сбор статистики + watchdog нулевого трафика.
      _startStats();
      _startTrafficWatchdog();
      _setState(BridgeState.running);

      log.i(
        'VPN активен. Подожди 5–10 секунд — Windows перестраивает маршруты '
            'после поднятия TUN. Интернет появится автоматически.',
        tag: 'BRIDGE',
      );

      return const BridgeResult(success: true);
    } catch (e, stack) {
      log.e('Ошибка запуска: $e', tag: 'BRIDGE');
      log.d('Stack: $stack', tag: 'BRIDGE');
      await _killProcess();
      _setState(BridgeState.error);
      return BridgeResult(success: false, error: e.toString());
    }
  }

  /// Проверка реальной связности через туннель: HTTPS-запрос через
  /// локальный mixed-прокси sing-box (2080). Если процесс sing-box мёртв,
  /// соединение с прокси просто не откроется — ложноположительный результат
  /// невозможен, в отличие от прямого запроса в обход прокси.
  @override
  Future<bool> verifyTunnel() async {
    if (_state != BridgeState.running) return false;

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    client.findProxy = (uri) => 'PROXY 127.0.0.1:2080';
    client.badCertificateCallback = (cert, host, port) => true;

    try {
      final request = await client.getUrl(
        Uri.parse('https://cp.cloudflare.com/generate_204'),
      );
      request.headers.set(HttpHeaders.connectionHeader, 'close');
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      await response.drain<void>();
      return response.statusCode >= 200 && response.statusCode < 400;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<int> measureLatency() async {
    if (_state != BridgeState.running) return -1;

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    client.findProxy = (uri) => 'PROXY 127.0.0.1:2080';
    client.badCertificateCallback = (cert, host, port) => true;

    final sw = Stopwatch()..start();
    try {
      final request = await client.getUrl(
        Uri.parse('https://cp.cloudflare.com/generate_204'),
      );
      request.headers.set(HttpHeaders.connectionHeader, 'close');
      final response =
          await request.close().timeout(const Duration(seconds: 5));
      await response.drain<void>();
      sw.stop();
      final ok = response.statusCode >= 200 && response.statusCode < 400;
      return ok ? sw.elapsedMilliseconds : -1;
    } catch (_) {
      return -1;
    } finally {
      client.close(force: true);
    }
  }

  /// Останавливает VPN-туннель.
  @override
  Future<void> stop() async {
    if (_state == BridgeState.idle) return;
    _setState(BridgeState.stopping);
    log.i('Останавливаем sing-box...', tag: 'BRIDGE');

    _stopStats();
    _stopTrafficWatchdog();
    await _killProcess();

    _setState(BridgeState.idle);
    log.i('sing-box остановлен', tag: 'BRIDGE');
  }

  // ── Приватные методы ──────────────────────────────────────────────────

  void _setState(BridgeState s) {
    _state = s;
    _stateCtrl.add(s);
  }

  /// Резолвит доменное имя сервера в IP-адрес ДО запуска TUN.
  String _newSecret() {
    final r = Random.secure();
    return List.generate(24, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  Future<UdpProbeResult> checkUdp() async {
    if (_state != BridgeState.running) {
      return const UdpProbeResult.failed('VPN не подключён');
    }
    // mixed-inbound sing-box (2080) умеет SOCKS5 UDP ASSOCIATE: датаграммы
    // идут тем же outbound-ом `proxy`, что и трафик Discord.
    return UdpProbe.viaSocks5(2080);
  }

  Future<String?> _resolveServerIp(String host) async {
    if (_isIpAddress(host)) {
      log.d('Хост уже IP-адрес: $host', tag: 'BRIDGE');
      return null;
    }

    log.i('Резолвим IP сервера: $host', tag: 'BRIDGE');
    try {
      final addresses = await InternetAddress.lookup(
        host,
      ).timeout(const Duration(seconds: 5));

      final ipv4 = addresses
          .where((a) => a.type == InternetAddressType.IPv4)
          .firstOrNull;
      final result = ipv4?.address ?? addresses.firstOrNull?.address;

      if (result != null) {
        log.i('IP сервера: $result', tag: 'BRIDGE');
      } else {
        log.w(
          'DNS вернул пустой список для $host. '
              'Bypass не будет добавлен — рассчитываем на auto_detect_interface.',
          tag: 'BRIDGE',
        );
      }
      return result;
    } catch (e) {
      log.w(
        'Не удалось резолвнуть $host: $e. '
            'Bypass не будет добавлен — рассчитываем на auto_detect_interface.',
        tag: 'BRIDGE',
      );
      return null;
    }
  }

  bool _isIpAddress(String host) {
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) return true;
    if (host.contains(':')) return true;
    return false;
  }

  /// Парсит вывод sing-box и логирует с правильным уровнем.
  /// Хвост вывода текущего запуска sing-box (для диагностики старта).
  final StringBuffer _stderrTail = StringBuffer();

  String? _lastFatal() {
    for (final l in _stderrTail.toString().split('\n').reversed) {
      if (l.contains('FATAL')) return l.replaceAll(RegExp(r'\x1b\[[0-9;]*m'), '').trim();
    }
    return null;
  }

  void _parseSingboxOutput(String chunk) {
    if (_stderrTail.length < 16384) _stderrTail.write(chunk);
    for (final rawLine in chunk.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.contains(' ERROR ') || line.contains(' FATAL ')) {
        log.e('[sing-box] $line', tag: 'SBOX');
      } else if (line.contains(' WARN ')) {
        log.w('[sing-box] $line', tag: 'SBOX');
      } else {
        log.i('[sing-box] $line', tag: 'SBOX');
      }
    }
  }

  void _startStats() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final (rx, tx) = await _apiClient.getTotalBytes();
        _statsCtrl.add((rx, tx));
      } catch (e) {
        log.w('Ошибка получения статистики трафика: $e', tag: 'BRIDGE');
      }
    });
  }

  void _stopStats() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }

  /// Watchdog: проверяет что через 8 секунд после подключения трафик не ноль.
  void _startTrafficWatchdog() {
    _trafficWatchdog?.cancel();
    _trafficWatchdog = Timer(const Duration(seconds: 8), () async {
      if (_state != BridgeState.running) return;
      try {
        final (rx, tx) = await _apiClient.getTotalBytes();
        final total = rx + tx;
        if (total == 0) {
          log.w(
            '⚠ WATCHDOG: 8 секунд прошло, трафик = 0 байт!\n'
                '  Скорее всего причина одна из:\n'
                '  1. Нет прав Администратора — WinTUN не может изменить таблицу маршрутов\n'
                '  2. VLESS-сервер недоступен или не поддерживает MUX (smux)\n'
                '  3. IP сервера не удалось резолвнуть до старта — проверь DNS',
            tag: 'DIAG',
          );
          _errorCtrl.add('WATCHDOG_NO_TRAFFIC');
        } else {
          log.i(
            '✓ WATCHDOG: трафик идёт — rx=${_fmtBytes(rx)}, tx=${_fmtBytes(tx)}. '
                'VPN работает нормально.',
            tag: 'DIAG',
          );
        }
      } catch (e) {
        log.w('WATCHDOG: не смог получить статистику: $e', tag: 'DIAG');
      }
    });
  }

  void _stopTrafficWatchdog() {
    _trafficWatchdog?.cancel();
    _trafficWatchdog = null;
  }

  String _fmtBytes(int b) {
    if (b < 1024) return '${b}B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)}KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  Future<void> _killProcess() async {
    if (_process == null) return;
    try {
      _process!.kill(ProcessSignal.sigterm);
      await _process!.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          _process!.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    } catch (_) {}
    _process = null;
  }

  /// Перед запуском: свой прошлый процесс и брошенные копии нашего
  /// sing-box.exe (родитель уже не жив — например, после падения Onyx).
  /// Раньше здесь был `taskkill /F /IM sing-box.exe`: он убивал ВСЕ sing-box
  /// на машине — чужие клиенты, туннель соседней сборки Onyx и собственные
  /// пробы Deep Probe посреди проверки (нода ложно становилась «мёртвой»).
  Future<void> _killExisting() async {
    await _killProcess();
    try {
      WinChildGuard.killOrphans(_binMgr.singboxExe.path);
    } catch (e) {
      log.w('Поиск брошенных sing-box не удался: $e', tag: 'BRIDGE');
    }
  }

  /// Проверяет права администратора один раз за время жизни процесса
  /// и кэширует результат. `net session` — относительно тяжёлый вызов
  /// (спавн процесса + запрос к SCM), права не могут измениться в
  /// течение работы приложения, поэтому повторные проверки — чистые
  /// потери времени на каждый connect().
  Future<bool> _checkAdmin() async {
    if (_isAdminCached != null) return _isAdminCached!;
    try {
      final r = await Process.run('net', ['session'], runInShell: true);
      _isAdminCached = r.exitCode == 0;
    } catch (_) {
      _isAdminCached = false;
    }
    return _isAdminCached!;
  }

  void dispose() {
    _stateCtrl.close();
    _statsCtrl.close();
    _errorCtrl.close();
    _statsTimer?.cancel();
    _trafficWatchdog?.cancel();
  }
}