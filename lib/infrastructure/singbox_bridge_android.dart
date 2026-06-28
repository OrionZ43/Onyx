import 'dart:async';

import 'dart:io';

import '../core/log_service.dart';
import '../domain/entities/node.dart';
import '../domain/singbox_config_builder.dart';
import 'binary_manager.dart';
import 'singbox_api_client.dart';
import 'singbox_bridge.dart';

class SingboxBridgeAndroid implements SingboxBridge {
  SingboxBridgeAndroid._();
  static final instance = SingboxBridgeAndroid._();

  static const _apiPort = 9090;

  final _binMgr = BinaryManager.instance;
  final _apiClient = SingboxApiClient(port: _apiPort);
  final _builder = const SingboxConfigBuilder();

  Process? _process;
  Timer? _statsTimer;
  Timer? _trafficWatchdog;
  BridgeState _state = BridgeState.idle;

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

  @override
  Future<void> ensureBinaries({
    void Function(String status, double? progress)? onStatus,
  }) async {
    await _binMgr.ensureBinaries(onStatus: onStatus);
  }

  @override
  bool get binariesReady => _binMgr.isReady;

  @override
  Future<BridgeResult> start(Node node, {bool smartRouting = true}) async {
    if (_state == BridgeState.running || _state == BridgeState.starting) {
      return const BridgeResult(success: false, error: 'Уже запущен');
    }

    _setState(BridgeState.starting);
    log.i('Запускаем sing-box для ${node.name} (Android)', tag: 'BRIDGE');

    try {
      await _killExisting();

      final resolvedIp = await _resolveServerIp(node.host);

      final config = _builder.buildTunConfig(
        node,
        socksPort: 2080,
        resolvedServerIp: resolvedIp,
        smartRouting: smartRouting,
        isAndroid: true,
      );

      final experimental = Map<String, dynamic>.from(
        config['experimental'] as Map? ?? {},
      );
      experimental['clash_api'] = {
        'external_controller': '127.0.0.1:$_apiPort',
        'secret': '',
      };
      config['experimental'] = experimental;

      final configJson = _builder.buildJson(config);

      log.d('=== ПОЛНЫЙ КОНФИГ SING-BOX (Android) ===', tag: 'BRIDGE');
      for (final line in configJson.split('\n')) {
        log.d(line, tag: 'CFG');
      }
      log.d('=== КОНЕЦ КОНФИГА ===', tag: 'BRIDGE');

      await _binMgr.writeConfig(configJson);

      log.i('Запускаем: ${_binMgr.singboxExe.path}', tag: 'BRIDGE');
      _process = await Process.start(
        _binMgr.singboxExe.path,
        ['run', '--config', _binMgr.configFile.path],
        workingDirectory: _binMgr.singboxExe.parent.path,
        mode: ProcessStartMode.normal,
      );

      log.i('sing-box PID: ${_process!.pid}', tag: 'BRIDGE');

      _process!.stdout
          .transform(const SystemEncoding().decoder)
          .listen(_parseSingboxOutput);

      _process!.stderr.transform(const SystemEncoding().decoder).listen(
            _parseSingboxOutput,
          );

      _process!.exitCode.then((code) {
        log.w('sing-box завершился с кодом: $code', tag: 'BRIDGE');
        if (_state == BridgeState.running) {
          _errorCtrl.add('sing-box неожиданно завершился (код $code)');
          _setState(BridgeState.error);
          _stopStats();
          _stopTrafficWatchdog();
        }
      });

      log.i('Ждём готовности API sing-box...', tag: 'BRIDGE');
      final ready = await _apiClient.waitReady(
        timeout: const Duration(seconds: 15),
      );

      if (!ready) {
        await _killProcess();
        throw Exception(
          'sing-box не ответил за 15 секунд.',
        );
      }

      final version = await _apiClient.getVersion();
      log.i('sing-box готов! Версия: $version', tag: 'BRIDGE');

      _startStats();
      _startTrafficWatchdog();
      _setState(BridgeState.running);

      return const BridgeResult(success: true);
    } catch (e, stack) {
      log.e('Ошибка запуска: $e', tag: 'BRIDGE');
      log.d('Stack: $stack', tag: 'BRIDGE');
      await _killProcess();
      _setState(BridgeState.error);
      return BridgeResult(success: false, error: e.toString());
    }
  }

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

  void _setState(BridgeState s) {
    _state = s;
    _stateCtrl.add(s);
  }

  Future<String?> _resolveServerIp(String host) async {
    if (_isIpAddress(host)) return null;

    try {
      final addresses = await InternetAddress.lookup(
        host,
      ).timeout(const Duration(seconds: 5));

      final ipv4 = addresses
          .where((a) => a.type == InternetAddressType.IPv4)
          .firstOrNull;
      return ipv4?.address ?? addresses.firstOrNull?.address;
    } catch (e) {
      log.w('Не удалось резолвнуть $host: $e.', tag: 'BRIDGE');
      return null;
    }
  }

  bool _isIpAddress(String host) {
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) return true;
    if (host.contains(':')) return true;
    return false;
  }

  void _parseSingboxOutput(String chunk) {
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

  void _startTrafficWatchdog() {
    _trafficWatchdog?.cancel();
    _trafficWatchdog = Timer(const Duration(seconds: 8), () async {
      if (_state != BridgeState.running) return;
      try {
        final (rx, tx) = await _apiClient.getTotalBytes();
        final total = rx + tx;
        if (total == 0) {
          log.w(
            '⚠ WATCHDOG: 8 секунд прошло, трафик = 0 байт!',
            tag: 'DIAG',
          );
          _errorCtrl.add('WATCHDOG_NO_TRAFFIC');
        } else {
          log.i(
            '✓ WATCHDOG: трафик идёт — rx=${_fmtBytes(rx)}, tx=${_fmtBytes(tx)}.',
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
      await Process.run('killall', ['sing-box']);
    } catch (_) {}
  }

  void dispose() {
    _stateCtrl.close();
    _statsCtrl.close();
    _errorCtrl.close();
    _statsTimer?.cancel();
    _trafficWatchdog?.cancel();
  }
}
