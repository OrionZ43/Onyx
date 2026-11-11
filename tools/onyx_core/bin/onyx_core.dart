// onyx-core.exe — запускатель ядра sing-box для туннеля Onyx (Windows, #55).
//
// Запускается задачей планировщика \Onyx\OnyxCore_<пользователь> с наивысшими
// правами; задачу регистрирует установщик (один UAC). Сам Onyx работает без
// прав и только «дёргает» задачу. Поэтому здесь всё, что приходит от
// пользователя, — НЕДОВЕРЕННОЕ:
//
//  * свои файлы (sing-box.exe) — рядом с этим exe в C:\Program Files\Onyx\core
//    (писать туда может только администратор); пути НЕ берутся из переменных
//    окружения — их пользователь подменяет сам;
//  * конфиг из папки пользователя пересобирается по белому списку
//    (sanitizeCoreConfig) и пишется в защищённую C:\Program Files\Onyx\run;
//  * PID Onyx и файл остановки — только флаги.
//
// Туннель гасится: по файлу core.stop, при выходе Onyx (родитель-«заказчик»
// исчез) и вместе с этим процессом (задание Windows KILL_ON_JOB_CLOSE).
//
// Тестовые параметры (--core-dir, --run-dir, --user-dir) — только из
// командной строки: у задачи планировщика она фиксирована установщиком.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import '../../../lib/domain/core_config_sanitizer.dart';

Future<void> main(List<String> args) async {
  final opt = _parse(args);
  final coreDir = opt['core-dir'] ?? File(Platform.resolvedExecutable).parent.path;
  final runDir = opt['run-dir'] ?? '${Directory(coreDir).parent.path}\\run';
  final appData = Platform.environment['APPDATA'];
  final userDir = opt['user-dir'] ?? (appData == null ? null : '$appData\\z43.studios\\onyx\\singbox');
  final singbox = '$coreDir\\sing-box.exe';

  Directory(runDir).createSync(recursive: true);
  final log = File('$runDir\\sing-box.log').openWrite();
  void note(String s) => log.writeln('${DateTime.now().toIso8601String()} [onyx-core] $s');
  Future<Never> finish(int code) async {
    await log.flush();
    await log.close();
    exit(code);
  }

  if (userDir == null) {
    note('нет APPDATA — не знаю, где конфиг пользователя');
    await finish(2);
  }

  // ── Конфиг: недоверенный → пересборка по белому списку ──────────────
  final req = File('$userDir\\config.json');
  final Map<String, dynamic> cfg;
  try {
    if (!req.existsSync() || req.lengthSync() > 4 * 1024 * 1024) throw const FormatException('нет конфига');
    cfg = sanitizeCoreConfig(
      jsonDecode(req.readAsStringSync()),
      userSingboxDir: userDir,
      runDir: runDir,
    );
  } catch (e) {
    // Содержимое не печатаем: это мог быть чужой файл по ссылке.
    note('конфиг отклонён: ${e is FormatException ? e.message : e.runtimeType}');
    await finish(3);
  }
  final runCfg = '$runDir\\config.json';
  File(runCfg).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(cfg));

  final parentPid = _readPid('$userDir\\core.pid');
  final stopFile = File('$userDir\\core.stop');
  final started = DateTime.now();
  final k = _Kernel32.load();

  // Прошлый экземпляр ядра (если остался) мешал бы TUN и портам.
  k?.killByImage(singbox);

  note('запуск sing-box (заказчик PID ${parentPid ?? "?"})');
  final proc = await Process.start(singbox, ['run', '-c', runCfg, '-D', runDir], workingDirectory: runDir);
  k?.adopt(proc.pid);
  proc.stdout.listen(log.add);
  proc.stderr.listen(log.add);

  int? exitCode;
  unawaited(proc.exitCode.then((c) => exitCode = c));
  while (exitCode == null) {
    await Future.delayed(const Duration(milliseconds: 300));
    if (exitCode != null) break;
    if (_stopRequested(stopFile, started)) {
      note('остановка по запросу Onyx');
      break;
    }
    if (parentPid != null && k != null && !k.isOnyxAlive(parentPid)) {
      note('Onyx закрылся — гасим туннель');
      break;
    }
  }
  if (exitCode == null) {
    proc.kill();
    await proc.exitCode.timeout(const Duration(seconds: 5), onTimeout: () => -1);
  } else {
    note('sing-box завершился сам, код $exitCode');
  }
  await finish(0);
}

Map<String, String> _parse(List<String> args) {
  final m = <String, String>{};
  for (var i = 0; i + 1 < args.length; i++) {
    final a = args[i];
    if (a.startsWith('--')) m[a.substring(2)] = args[++i];
  }
  return m;
}

int? _readPid(String path) {
  try {
    final f = File(path);
    if (!f.existsSync() || f.lengthSync() > 32) return null;
    final v = int.tryParse(f.readAsStringSync().trim());
    return (v != null && v > 0) ? v : null;
  } catch (_) {
    return null;
  }
}

bool _stopRequested(File f, DateTime started) {
  try {
    return f.existsSync() && !f.lastModifiedSync().isBefore(started.subtract(const Duration(seconds: 1)));
  } catch (_) {
    return false;
  }
}

/// Минимум WinAPI: живость процесса-заказчика, задание KILL_ON_JOB_CLOSE,
/// завершение прошлого ядра по пути образа. Память — LocalAlloc.
class _Kernel32 {
  _Kernel32._(DynamicLibrary l)
      : _openProcess = l.lookupFunction<IntPtr Function(Uint32, Int32, Uint32), int Function(int, int, int)>('OpenProcess'),
        _closeHandle = l.lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle'),
        _wait = l.lookupFunction<Uint32 Function(IntPtr, Uint32), int Function(int, int)>('WaitForSingleObject'),
        _terminate = l.lookupFunction<Int32 Function(IntPtr, Uint32), int Function(int, int)>('TerminateProcess'),
        _queryImage = l.lookupFunction<Int32 Function(IntPtr, Uint32, Pointer<Uint16>, Pointer<Uint32>),
            int Function(int, int, Pointer<Uint16>, Pointer<Uint32>)>('QueryFullProcessImageNameW'),
        _createJob = l.lookupFunction<IntPtr Function(Pointer<Void>, Pointer<Void>), int Function(Pointer<Void>, Pointer<Void>)>('CreateJobObjectW'),
        _setJob = l.lookupFunction<Int32 Function(IntPtr, Int32, Pointer<Void>, Uint32), int Function(int, int, Pointer<Void>, int)>('SetInformationJobObject'),
        _assign = l.lookupFunction<Int32 Function(IntPtr, IntPtr), int Function(int, int)>('AssignProcessToJobObject'),
        _snapshot = l.lookupFunction<IntPtr Function(Uint32, Uint32), int Function(int, int)>('CreateToolhelp32Snapshot'),
        _first = l.lookupFunction<Int32 Function(IntPtr, Pointer<Uint8>), int Function(int, Pointer<Uint8>)>('Process32FirstW'),
        _next = l.lookupFunction<Int32 Function(IntPtr, Pointer<Uint8>), int Function(int, Pointer<Uint8>)>('Process32NextW'),
        _alloc = l.lookupFunction<IntPtr Function(Uint32, IntPtr), int Function(int, int)>('LocalAlloc'),
        _free = l.lookupFunction<IntPtr Function(IntPtr), int Function(int)>('LocalFree');

  static _Kernel32? load() {
    if (!Platform.isWindows || sizeOf<IntPtr>() != 8) return null;
    try {
      return _Kernel32._(DynamicLibrary.open('kernel32.dll'));
    } catch (_) {
      return null;
    }
  }

  final int Function(int, int, int) _openProcess;
  final int Function(int) _closeHandle;
  final int Function(int, int) _wait;
  final int Function(int, int) _terminate;
  final int Function(int, int, Pointer<Uint16>, Pointer<Uint32>) _queryImage;
  final int Function(Pointer<Void>, Pointer<Void>) _createJob;
  final int Function(int, int, Pointer<Void>, int) _setJob;
  final int Function(int, int) _assign;
  final int Function(int, int) _snapshot;
  final int Function(int, Pointer<Uint8>) _first;
  final int Function(int, Pointer<Uint8>) _next;
  final int Function(int, int) _alloc;
  final int Function(int) _free;

  static const _queryLimited = 0x1000;
  static const _synchronize = 0x00100000;
  static const _terminateAccess = 0x0001;
  static const _setQuota = 0x0100;
  static const _waitTimeout = 0x102;

  int _job = 0;

  Pointer<Uint8> _mem(int n) => Pointer<Uint8>.fromAddress(_alloc(0x40, n));
  void _release(Pointer p) {
    if (p != nullptr) _free(p.address);
  }

  String? _image(int h) {
    final buf = _mem(2048);
    final size = _mem(4);
    try {
      if (buf == nullptr || size == nullptr) return null;
      size.cast<Uint32>().value = 1024;
      if (_queryImage(h, 0, buf.cast(), size.cast()) == 0) return null;
      return String.fromCharCodes(buf.cast<Uint16>().asTypedList(size.cast<Uint32>().value));
    } finally {
      _release(buf);
      _release(size);
    }
  }

  /// Жив ли процесс [pid] и это onyx.exe (а не чужой процесс с тем же,
  /// переиспользованным PID).
  bool isOnyxAlive(int pid) {
    final h = _openProcess(_queryLimited | _synchronize, 0, pid);
    if (h == 0) return false;
    try {
      if (_wait(h, 0) != _waitTimeout) return false;
      final img = _image(h);
      return img == null || img.toLowerCase().endsWith('\\onyx.exe');
    } finally {
      _closeHandle(h);
    }
  }

  /// Привязать [pid] к заданию KILL_ON_JOB_CLOSE этого процесса: если
  /// onyx-core падает или его снимает планировщик, sing-box уходит вместе.
  void adopt(int pid) {
    if (_job == 0) {
      final job = _createJob(nullptr, nullptr);
      if (job == 0) return;
      final info = _mem(144); // JOBOBJECT_EXTENDED_LIMIT_INFORMATION (x64)
      try {
        if (info == nullptr) return;
        (info + 16).cast<Uint32>().value = 0x2000; // KILL_ON_JOB_CLOSE
        if (_setJob(job, 9, info.cast(), 144) == 0) {
          _closeHandle(job);
          return;
        }
      } finally {
        _release(info);
      }
      _job = job;
    }
    final h = _openProcess(_setQuota | _terminateAccess, 0, pid);
    if (h == 0) return;
    _assign(_job, h);
    _closeHandle(h);
  }

  /// Завершить процессы с образом [path] (прошлый экземпляр ядра).
  void killByImage(String path) {
    final target = path.toLowerCase();
    final name = target.split('\\').last;
    final snap = _snapshot(2, 0);
    if (snap == 0 || snap == -1) return;
    final pe = _mem(568); // PROCESSENTRY32W (x64)
    try {
      if (pe == nullptr) return;
      pe.cast<Uint32>().value = 568;
      var ok = _first(snap, pe) != 0;
      while (ok) {
        final pid = (pe + 8).cast<Uint32>().value;
        final chars = (pe + 44).cast<Uint16>().asTypedList(260);
        var len = 0;
        while (len < 260 && chars[len] != 0) {
          len++;
        }
        if (String.fromCharCodes(chars, 0, len).toLowerCase() == name) {
          final h = _openProcess(_queryLimited | _terminateAccess, 0, pid);
          if (h != 0) {
            if (_image(h)?.toLowerCase() == target) _terminate(h, 1);
            _closeHandle(h);
          }
        }
        ok = _next(snap, pe) != 0;
      }
    } finally {
      _release(pe);
      _closeHandle(snap);
    }
  }
}
