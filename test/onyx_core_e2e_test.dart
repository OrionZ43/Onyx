import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #55: onyx-core.exe на настоящих процессах, без прав администратора
/// (конфиг без TUN). Не в CI:
///
///   ONYX_CORE_EXE    — путь к собранному onyx-core.exe;
///   ONYX_E2E_SINGBOX — путь к sing-box.exe.
void main() {
  final core = Platform.environment['ONYX_CORE_EXE'];
  final sb = Platform.environment['ONYX_E2E_SINGBOX'];
  final skip = (!Platform.isWindows || core == null || sb == null) ? 'ONYX_CORE_EXE/ONYX_E2E_SINGBOX не заданы' : false;

  late Directory root;
  late String coreDir, runDir, userDir, fakeOnyx;

  Future<int> freePort() async {
    final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = s.port;
    await s.close();
    return p;
  }

  Future<bool> listening(int port) async {
    try {
      final s = await Socket.connect('127.0.0.1', port, timeout: const Duration(milliseconds: 300));
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> until(Future<bool> Function() cond, {int seconds = 10}) async {
    for (var i = 0; i < seconds * 4 && !await cond(); i++) {
      await Future.delayed(const Duration(milliseconds: 250));
    }
  }

  setUpAll(() {
    if (skip != false) return;
    root = Directory.systemTemp.createTempSync('onyx55');
    coreDir = '${root.path}\\core';
    runDir = '${root.path}\\run';
    userDir = '${root.path}\\user';
    for (final d in [coreDir, runDir, userDir]) {
      Directory(d).createSync(recursive: true);
    }
    File(sb!).copySync('$coreDir\\sing-box.exe');
    // «Onyx»-заказчик: копия ping.exe под именем onyx.exe (проверка имени).
    fakeOnyx = '${root.path}\\onyx.exe';
    File('${Platform.environment['SystemRoot']}\\System32\\PING.EXE').copySync(fakeOnyx);
  });

  tearDownAll(() async {
    if (skip != false) return;
    for (var i = 0; i < 20; i++) {
      try {
        root.deleteSync(recursive: true);
        break;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }
  });

  Future<(Process, int, Process)> startCore() async {
    final port = await freePort();
    final api = await freePort();
    final victim = '${root.path}\\victim.txt';
    File('$userDir\\config.json').writeAsStringSync(jsonEncode({
      'log': {'level': 'info', 'output': victim}, // путь записи — должен исчезнуть
      'inbounds': [
        {'type': 'mixed', 'tag': 'mixed-in', 'listen': '127.0.0.1', 'listen_port': port},
      ],
      'outbounds': [
        {'type': 'direct', 'tag': 'direct'},
      ],
      'experimental': {
        'clash_api': {'external_controller': '127.0.0.1:$api', 'external_ui': victim},
      },
    }));
    final parent = await Process.start(fakeOnyx, ['-n', '120', '127.0.0.1']);
    File('$userDir\\core.pid').writeAsStringSync('${parent.pid}');
    final stop = File('$userDir\\core.stop');
    if (stop.existsSync()) stop.deleteSync();
    final p = await Process.start(core!, ['--core-dir', coreDir, '--run-dir', runDir, '--user-dir', userDir]);
    await until(() => listening(port));
    return (p, port, parent);
  }

  test('конфиг пересобран, туннель гаснет, когда Onyx закрылся', () async {
    final (p, port, parent) = await startCore();
    expect(await listening(port), isTrue, reason: File('$runDir\\sing-box.log').readAsStringSync());
    final cfg = File('$runDir\\config.json').readAsStringSync();
    expect(cfg, isNot(contains('victim')));
    expect(File('${root.path}\\victim.txt').existsSync(), isFalse);

    parent.kill(); // «Onyx» упал
    final code = await p.exitCode.timeout(const Duration(seconds: 10));
    expect(code, 0);
    expect(await listening(port), isFalse);
    expect(File('$runDir\\sing-box.log').readAsStringSync(), contains('Onyx закрылся'));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  test('файл остановки гасит туннель', () async {
    final (p, port, parent) = await startCore();
    expect(await listening(port), isTrue);
    File('$userDir\\core.stop').writeAsStringSync('1');
    final code = await p.exitCode.timeout(const Duration(seconds: 10));
    parent.kill();
    expect(code, 0);
    expect(await listening(port), isFalse);
    expect(File('$runDir\\sing-box.log').readAsStringSync(), contains('остановка по запросу'));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  test('чужой конфиг — отказ без запуска sing-box', () async {
    File('$userDir\\config.json').writeAsStringSync('{"inbounds":[{"type":"mixed","listen":"0.0.0.0","listen_port":1}],"outbounds":[]}');
    final p = await Process.start(core!, ['--core-dir', coreDir, '--run-dir', runDir, '--user-dir', userDir]);
    expect(await p.exitCode.timeout(const Duration(seconds: 10)), 3);
    expect(File('$runDir\\sing-box.log').readAsStringSync(), contains('конфиг отклонён'));
  }, skip: skip);
}
