import 'dart:async';
import 'dart:io';
import '../core/log_service.dart';
import '../domain/entities/node.dart';
import '../domain/singbox_config_builder.dart';
import 'binary_manager.dart';
import 'singbox_api_client.dart';

enum BridgeState { idle, starting, running, stopping, error }

/// Результат операции моста
class BridgeResult {
  const BridgeResult({required this.success, this.error});
  final bool success;
  final String? error;
}

/// Windows-реализация sing-box моста.
///
/// Жизненный цикл:
///   start() → [проверка бинарников] → [резолв IP сервера] →
///   [запись конфига] → [запуск sing-box.exe] → [ожидание API] → running
///   stop()  → [SIGTERM sing-box.exe] → idle
///
/// Трафик-статистика берётся из Clash API (9090).
class SingboxBridgeWindows {
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

  // Стримы для UI
  final _stateCtrl = StreamController<BridgeState>.broadcast();
  final _statsCtrl = StreamController<(int rx, int tx)>.broadcast();
  final _errorCtrl = StreamController<String>.broadcast();

  Stream<BridgeState> get stateStream => _stateCtrl.stream;
  Stream<(int rx, int tx)> get statsStream => _statsCtrl.stream;
  Stream<String> get errorStream => _errorCtrl.stream;
  BridgeState get state => _state;

  // ── Публичный API ──────────────────────────────────────────────────────

  /// Скачивает бинарники если нужно. Вызывать при старте приложения.
  Future<void> ensureBinaries({
    void Function(String status, double? progress)? onStatus,
  }) async {
    await _binMgr.ensureBinaries(onStatus: onStatus);
  }

  bool get binariesReady => _binMgr.isReady;

  /// Запускает VPN-туннель для [node].
  Future<BridgeResult> start(Node node, {bool smartRouting = true}) async {
    if (_state == BridgeState.running || _state == BridgeState.starting) {
      return const BridgeResult(success: false, error: 'Уже запущен');
    }

    _setState(BridgeState.starting);
    log.i('Запускаем sing-box для ${node.name}', tag: 'BRIDGE');

    try {
      // 1. Проверка бинарников
      if (!_binMgr.isReady) {
        throw Exception(
          'Бинарники не готовы. Запустите ensureBinaries() сначала.',
        );
      }

      // 2. Проверяем права администратора
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
      final resolvedServerIp = await _resolveServerIp(node.host);

      // 4. Генерируем конфиг
      final config = _builder.buildTunConfig(
        node,
        socksPort: 2080,
        resolvedServerIp: resolvedServerIp,
        smartRouting: smartRouting,
      );

      // ИСПРАВЛЕНО: мержим experimental вместо полной перезаписи,
      // чтобы сохранить cache_file из _buildExperimental().
      final experimental = Map<String, dynamic>.from(
        config['experimental'] as Map? ?? {},
      );
      experimental['clash_api'] = {
        'external_controller': '127.0.0.1:$_apiPort',
        'secret': '',
      };
      config['experimental'] = experimental;

      final configJson = _builder.buildJson(config);

      // Дамп конфига в лог
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

      // 6. Запускаем sing-box.exe
      log.i('Запускаем: ${_binMgr.singboxExe.path}', tag: 'BRIDGE');
      _process = await Process.start(
        _binMgr.singboxExe.path,
        ['run', '--config', _binMgr.configFile.path],
        workingDirectory: _binMgr.singboxExe.parent.path,
        mode: ProcessStartMode.normal,
      );

      log.i('sing-box PID: ${_process!.pid}', tag: 'BRIDGE');

      // 7. Пишем stdout/stderr в лог
      //
      // ИСПРАВЛЕНО: sing-box пишет ВСЕ свои логи в stderr — это его штатное
      // поведение, а не признак ошибки. Раньше весь stderr тегировался как
      // [ERR], что создавало ложный алерт на обычные INFO-сообщения.
      // Теперь парсим уровень из текста самого sing-box и логируем правильно.
      _process!.stdout
          .transform(const SystemEncoding().decoder)
          .listen(_parseSingboxOutput);

      _process!.stderr
          .transform(const SystemEncoding().decoder)
          .listen(
            _parseSingboxOutput,
          ); // sing-box пишет сюда ВСЁ, не только ошибки

      // Следим за завершением процесса
      _process!.exitCode.then((code) {
        log.w('sing-box завершился с кодом: $code', tag: 'BRIDGE');
        if (_state == BridgeState.running) {
          _errorCtrl.add('sing-box неожиданно завершился (код $code)');
          _setState(BridgeState.error);
          _stopStats();
          _stopTrafficWatchdog();
        }
      });

      // 8. Ждём готовности API
      log.i('Ждём готовности API sing-box...', tag: 'BRIDGE');
      final ready = await _apiClient.waitReady(
        timeout: const Duration(seconds: 15),
      );

      if (!ready) {
        await _killProcess();
        throw Exception(
          'sing-box не ответил за 15 секунд. '
          'Возможно, не хватает прав администратора.',
        );
      }

      final version = await _apiClient.getVersion();
      log.i('sing-box готов! Версия: $version', tag: 'BRIDGE');

      // 9. Запускаем сбор статистики + watchdog нулевого трафика.
      //    Watchdog проверяет через 8 секунд — этого достаточно чтобы
      //    Windows достроил маршруты TUN и пошёл первый трафик.
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

  /// Останавливает VPN-туннель.
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
  ///
  /// Результат используется для ip_cidr bypass в route-конфиге.
  /// Резолвим сейчас, потому что:
  ///   • TUN ещё не поднят → системный DNS работает нормально
  ///   • После поднятия TUN весь трафик идёт через него, и DNS
  ///     может не успеть настроиться до первого пакета к серверу
  ///
  /// Возвращает null если хост уже IP-адрес или резолв не удался.
  Future<String?> _resolveServerIp(String host) async {
    if (_isIpAddress(host)) {
      log.d('Хост уже IP-адрес: $host', tag: 'BRIDGE');
      return null; // buildTunConfig сам возьмёт его из node.host
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
  ///
  /// Sing-box пишет строки вида:
  ///   +0300 2026-05-17 17:50:25 INFO router: updated default interface...
  ///   +0300 2026-05-17 17:50:25 WARN tun: ...
  ///   +0300 2026-05-17 17:50:25 ERROR ...
  ///
  /// Мы вычленяем уровень и логируем с соответствующим тегом.
  void _parseSingboxOutput(String chunk) {
    for (final rawLine in chunk.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      // Ищем уровень в формате sing-box: "... INFO ...", "... WARN ...", "... ERROR ..."
      if (line.contains(' ERROR ') || line.contains(' FATAL ')) {
        log.e('[sing-box] $line', tag: 'SBOX');
      } else if (line.contains(' WARN ')) {
        log.w('[sing-box] $line', tag: 'SBOX');
      } else {
        // INFO, DEBUG и всё остальное → info
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
  ///
  /// 8 секунд выбрано потому что Windows после поднятия TUN-адаптера
  /// несколько секунд перестраивает таблицу маршрутов — в это время
  /// "нет сети" это нормально. Если через 8 секунд всё ещё 0 — реальная
  /// проблема.
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

  Future<void> _killExisting() async {
    try {
      await Process.run('taskkill', [
        '/F',
        '/IM',
        'sing-box.exe',
      ], runInShell: true);
      log.d('Завершены старые процессы sing-box', tag: 'BRIDGE');
    } catch (_) {}
  }

  Future<bool> _checkAdmin() async {
    try {
      final r = await Process.run('net', ['session'], runInShell: true);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _stateCtrl.close();
    _statsCtrl.close();
    _errorCtrl.close();
    _statsTimer?.cancel();
    _trafficWatchdog?.cancel();
  }
}
