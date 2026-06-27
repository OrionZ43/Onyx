import 'dart:io';

import 'package:path/path.dart' as path;

class SingboxLauncher {
  static Process? _process;
  static int? _lastExitCode;

  /// Асинхронный запуск sing-box.exe
  static Future<bool> start(String configPath) async {
    if (_process != null) {
      stop();
    }

    try {
      final serviceDir = File(Platform.resolvedExecutable).parent.path;
      // Resolve sing-box.exe using the requested relative path approach
      final singboxExe = path.join(
        serviceDir,
        '..',
        'onyx_data',
        'sing-box.exe',
      );

      print(
        'Starting $singboxExe with config: $configPath',
      ); // configPath passed verbatim

      if (!File(singboxExe).existsSync()) {
        print('Error: sing-box.exe not found at $singboxExe');
        _lastExitCode = -1;
        return false;
      }

      _lastExitCode = null;
      _process = await Process.start(singboxExe, ['run', '-c', configPath]);

      final logDir = Directory(path.join(serviceDir, 'logs'));
      if (!logDir.existsSync()) {
        logDir.createSync(recursive: true);
      }
      final logFile = File(path.join(logDir.path, 'service.log'));
      final sink = logFile.openWrite(mode: FileMode.append);

      _process!.stdout.listen((data) {
        sink.add(data);
      });
      _process!.stderr.listen((data) {
        sink.add(data);
      });

      _process!.exitCode.then((code) {
        print('sing-box exited with code $code');
        _lastExitCode = code;
        _process = null;
        sink.close();
      });

      return true;
    } catch (e) {
      print('Error starting sing-box: $e');
      return false;
    }
  }

  static void stop() {
    if (_process != null) {
      print('Killing sing-box (PID: ${_process!.pid})');
      _process!.kill();
      _process = null;
    } else {
      // На случай если процесс не отслеживается (например, перезапуск сервиса)
      try {
        Process.runSync('taskkill', ['/F', '/IM', 'sing-box.exe']);
      } catch (_) {}
    }
  }

  static bool isRunning() {
    return _process != null;
  }

  static bool hasError() {
    return _process == null && _lastExitCode != null && _lastExitCode != 0;
  }

  static int? getPid() {
    return _process?.pid;
  }
}
