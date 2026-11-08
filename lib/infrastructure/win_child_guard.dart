import 'dart:ffi';
import 'dart:io';

import '../core/log_service.dart';

/// Процесс в снимке системы: PID, PID родителя, имя файла образа.
class ProcEntry {
  final int pid;
  final int parentPid;
  final String exeName;

  const ProcEntry(this.pid, this.parentPid, this.exeName);
}

/// Дочерние sing-box (туннель и пробы Deep Probe) не должны переживать
/// onyx.exe (#57).
///
/// Раньше пробы запускались detached и гасились только в `finally` своего
/// прохода: если Onyx закрывали, падал или его снимали в диспетчере посреди
/// проверки, sing-box оставались сиротами. Они работали с правами админа,
/// держали `singbox\sing-box.exe` (обновление ядра не могло его заменить)
/// и гоняли трафик.
///
/// * [adopt] кладёт процесс в задание Windows (Job Object) с
///   `KILL_ON_JOB_CLOSE`. Хэндл задания живёт до конца onyx.exe и не
///   закрывается явно: при любом выходе (штатном, падении, «Снять задачу»)
///   ОС закрывает его сама и завершает всё, что к нему привязано. Привязываем
///   только свои sing-box: апдейтер, запущенный перед выходом, переживает
///   onyx.exe как и раньше.
/// * [killOrphans] — при старте и перед подключением завершает брошенные
///   копии нашего `sing-box.exe` (тот же путь образа, родитель уже не жив).
///   Чужие sing-box (другие клиенты, соседняя сборка Onyx с живым
///   родителем) не трогаем — раньше `taskkill /IM sing-box.exe` убивал все.
///
/// Только Windows x64/arm64 (8-байтные указатели); на других платформах — no-op.
class WinChildGuard {
  WinChildGuard._();

  static _Kernel32? _k;
  static bool _kFailed = false;

  /// Хэндл задания; 0 — ещё не создано или создать не удалось.
  static int _job = 0;
  static bool _jobFailed = false;

  static _Kernel32? get _kernel {
    if (!Platform.isWindows || _kFailed) return null;
    if (_k != null) return _k;
    if (sizeOf<IntPtr>() != 8) {
      _kFailed = true;
      return null;
    }
    try {
      return _k = _Kernel32();
    } catch (e) {
      _kFailed = true;
      log.w('kernel32 недоступен: $e', tag: 'PROC');
      return null;
    }
  }

  /// Привязать процесс [pid] к заданию «завершить вместе с onyx.exe».
  /// true — привязан. Ошибка не мешает работе: в худшем случае процесс
  /// переживёт onyx.exe, и его подберёт [killOrphans] при следующем старте.
  static bool adopt(int pid) {
    final k = _kernel;
    if (k == null) return false;
    final job = _ensureJob(k);
    if (job == 0) return false;
    final h = k.openProcess(_processSetQuota | _processTerminate, 0, pid);
    if (h == 0) {
      log.w('PID $pid: не открыть для привязки (код ${k.getLastError()})', tag: 'PROC');
      return false;
    }
    try {
      if (k.assignProcessToJobObject(job, h) != 0) return true;
      log.w('PID $pid: не привязан к заданию (код ${k.getLastError()})', tag: 'PROC');
      return false;
    } finally {
      k.closeHandle(h);
    }
  }

  /// Привязан ли [pid] к заданию [adopt] (для тестов и диагностики).
  static bool isAdopted(int pid) {
    final k = _kernel;
    if (k == null || _job == 0) return false;
    final h = k.openProcess(_processQueryLimitedInformation, 0, pid);
    if (h == 0) return false;
    final result = k.alloc(4);
    try {
      if (result == nullptr) return false;
      return k.isProcessInJob(h, _job, result.cast()) != 0 &&
          result.cast<Int32>().value != 0;
    } finally {
      k.free(result);
      k.closeHandle(h);
    }
  }

  /// Завершить брошенные копии [exePath]: процессы с тем же путём образа,
  /// чей родитель уже не жив. Возвращает число завершённых.
  static int killOrphans(String exePath) {
    final k = _kernel;
    if (k == null) return 0;
    final orphans = selectOrphans(_snapshot(k), exePath, (pid) => _imagePath(k, pid));
    var killed = 0;
    for (final pid in orphans) {
      final h = k.openProcess(_processTerminate, 0, pid);
      if (h == 0) {
        // Например, сирота с правами админа, а мы без них.
        log.w('Сирота sing-box PID $pid: нет доступа (код ${k.getLastError()})', tag: 'PROC');
        continue;
      }
      try {
        if (k.terminateProcess(h, 1) != 0) killed++;
      } finally {
        k.closeHandle(h);
      }
    }
    if (orphans.isNotEmpty) {
      log.i('Брошенные sing-box: найдено ${orphans.length}, завершено $killed', tag: 'PROC');
    }
    return killed;
  }

  /// PID всех процессов с образом [exePath] (диагностика и тесты).
  static List<int> pidsOf(String exePath) {
    final k = _kernel;
    if (k == null) return const [];
    final target = exePath.toLowerCase();
    final name = target.split(RegExp(r'[\\/]')).last;
    return [
      for (final p in _snapshot(k))
        if (p.exeName.toLowerCase() == name && _imagePath(k, p.pid)?.toLowerCase() == target) p.pid,
    ];
  }

  /// Чистая логика выбора сирот. [imageOf] — полный путь образа процесса
  /// (null — не узнать: такой процесс не трогаем). Если PID родителя занят
  /// другим живым процессом, считаем родителя живым — ошибаемся в сторону
  /// «не убивать».
  static List<int> selectOrphans(
    List<ProcEntry> procs,
    String exePath,
    String? Function(int pid) imageOf,
  ) {
    final alive = {for (final p in procs) p.pid};
    final target = exePath.toLowerCase();
    final name = target.split(RegExp(r'[\\/]')).last;
    return [
      for (final p in procs)
        if (p.exeName.toLowerCase() == name &&
            !alive.contains(p.parentPid) &&
            imageOf(p.pid)?.toLowerCase() == target)
          p.pid,
    ];
  }

  // ── WinAPI ────────────────────────────────────────────────────────────

  static const _processTerminate = 0x0001;
  static const _processSetQuota = 0x0100;
  static const _processQueryLimitedInformation = 0x1000;
  static const _th32csSnapProcess = 0x00000002;
  static const _jobObjectExtendedLimitInformation = 9;
  static const _jobObjectLimitKillOnJobClose = 0x00002000;

  // JOBOBJECT_EXTENDED_LIMIT_INFORMATION (x64): 144 байта, LimitFlags — +16
  static const _jobInfoSize = 144;
  static const _jobInfoLimitFlags = 16;

  // PROCESSENTRY32W (x64): 568 байт
  static const _peSize = 568;
  static const _pePid = 8;
  static const _peParentPid = 32;
  static const _peExeFile = 44;
  static const _maxPath = 260;

  static int _ensureJob(_Kernel32 k) {
    if (_job != 0 || _jobFailed) return _job;
    final job = k.createJobObjectW(nullptr, nullptr);
    if (job == 0) {
      _jobFailed = true;
      log.w('Задание Windows не создано (код ${k.getLastError()})', tag: 'PROC');
      return 0;
    }
    final info = k.alloc(_jobInfoSize);
    try {
      if (info == nullptr) {
        k.closeHandle(job);
        _jobFailed = true;
        return 0;
      }
      (info + _jobInfoLimitFlags).cast<Uint32>().value = _jobObjectLimitKillOnJobClose;
      if (k.setInformationJobObject(job, _jobObjectExtendedLimitInformation, info.cast(), _jobInfoSize) == 0) {
        log.w('Задание Windows: KILL_ON_JOB_CLOSE не включён (код ${k.getLastError()})', tag: 'PROC');
        k.closeHandle(job);
        _jobFailed = true;
        return 0;
      }
    } finally {
      k.free(info);
    }
    // Хэндл не закрываем: его закроет ОС при выходе onyx.exe — в этом и смысл.
    _job = job;
    return job;
  }

  static List<ProcEntry> _snapshot(_Kernel32 k) {
    final snap = k.createToolhelp32Snapshot(_th32csSnapProcess, 0);
    if (snap == 0 || snap == -1) return const [];
    final pe = k.alloc(_peSize);
    final res = <ProcEntry>[];
    try {
      if (pe == nullptr) return const [];
      pe.cast<Uint32>().value = _peSize;
      var ok = k.process32FirstW(snap, pe) != 0;
      while (ok) {
        final pid = (pe + _pePid).cast<Uint32>().value;
        final ppid = (pe + _peParentPid).cast<Uint32>().value;
        final chars = (pe + _peExeFile).cast<Uint16>().asTypedList(_maxPath);
        var len = 0;
        while (len < _maxPath && chars[len] != 0) {
          len++;
        }
        res.add(ProcEntry(pid, ppid, String.fromCharCodes(chars, 0, len)));
        ok = k.process32NextW(snap, pe) != 0;
      }
    } finally {
      k.free(pe);
      k.closeHandle(snap);
    }
    return res;
  }

  static String? _imagePath(_Kernel32 k, int pid) {
    final h = k.openProcess(_processQueryLimitedInformation, 0, pid);
    if (h == 0) return null;
    const cap = 1024;
    final buf = k.alloc(cap * 2);
    final size = k.alloc(4);
    try {
      if (buf == nullptr || size == nullptr) return null;
      size.cast<Uint32>().value = cap;
      if (k.queryFullProcessImageNameW(h, 0, buf.cast(), size.cast()) == 0) return null;
      final len = size.cast<Uint32>().value;
      return String.fromCharCodes(buf.cast<Uint16>().asTypedList(len));
    } finally {
      k.free(buf);
      k.free(size);
      k.closeHandle(h);
    }
  }
}

/// Нужные функции kernel32. Память — LocalAlloc/LocalFree: так не нужен
/// пакет ffi (calloc) только ради пары буферов.
class _Kernel32 {
  _Kernel32() : _lib = DynamicLibrary.open('kernel32.dll') {
    createJobObjectW = _lib.lookupFunction<IntPtr Function(Pointer<Void>, Pointer<Void>),
        int Function(Pointer<Void>, Pointer<Void>)>('CreateJobObjectW');
    setInformationJobObject = _lib.lookupFunction<Int32 Function(IntPtr, Int32, Pointer<Void>, Uint32),
        int Function(int, int, Pointer<Void>, int)>('SetInformationJobObject');
    assignProcessToJobObject = _lib.lookupFunction<Int32 Function(IntPtr, IntPtr),
        int Function(int, int)>('AssignProcessToJobObject');
    isProcessInJob = _lib.lookupFunction<Int32 Function(IntPtr, IntPtr, Pointer<Int32>),
        int Function(int, int, Pointer<Int32>)>('IsProcessInJob');
    openProcess = _lib.lookupFunction<IntPtr Function(Uint32, Int32, Uint32),
        int Function(int, int, int)>('OpenProcess');
    terminateProcess = _lib.lookupFunction<Int32 Function(IntPtr, Uint32),
        int Function(int, int)>('TerminateProcess');
    closeHandle = _lib.lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
    createToolhelp32Snapshot = _lib.lookupFunction<IntPtr Function(Uint32, Uint32),
        int Function(int, int)>('CreateToolhelp32Snapshot');
    process32FirstW = _lib.lookupFunction<Int32 Function(IntPtr, Pointer<Uint8>),
        int Function(int, Pointer<Uint8>)>('Process32FirstW');
    process32NextW = _lib.lookupFunction<Int32 Function(IntPtr, Pointer<Uint8>),
        int Function(int, Pointer<Uint8>)>('Process32NextW');
    queryFullProcessImageNameW = _lib.lookupFunction<Int32 Function(IntPtr, Uint32, Pointer<Uint16>, Pointer<Uint32>),
        int Function(int, int, Pointer<Uint16>, Pointer<Uint32>)>('QueryFullProcessImageNameW');
    getLastError = _lib.lookupFunction<Uint32 Function(), int Function()>('GetLastError');
    _localAlloc = _lib.lookupFunction<IntPtr Function(Uint32, IntPtr), int Function(int, int)>('LocalAlloc');
    _localFree = _lib.lookupFunction<IntPtr Function(IntPtr), int Function(int)>('LocalFree');
  }

  final DynamicLibrary _lib;
  late final int Function(Pointer<Void>, Pointer<Void>) createJobObjectW;
  late final int Function(int, int, Pointer<Void>, int) setInformationJobObject;
  late final int Function(int, int) assignProcessToJobObject;
  late final int Function(int, int, Pointer<Int32>) isProcessInJob;
  late final int Function(int, int, int) openProcess;
  late final int Function(int, int) terminateProcess;
  late final int Function(int) closeHandle;
  late final int Function(int, int) createToolhelp32Snapshot;
  late final int Function(int, Pointer<Uint8>) process32FirstW;
  late final int Function(int, Pointer<Uint8>) process32NextW;
  late final int Function(int, int, Pointer<Uint16>, Pointer<Uint32>) queryFullProcessImageNameW;
  late final int Function() getLastError;
  late final int Function(int, int) _localAlloc;
  late final int Function(int) _localFree;

  static const _lptr = 0x0040; // LMEM_FIXED | LMEM_ZEROINIT

  /// Обнулённый буфер; nullptr — не выделить.
  Pointer<Uint8> alloc(int bytes) => Pointer<Uint8>.fromAddress(_localAlloc(_lptr, bytes));

  void free(Pointer<NativeType> p) {
    if (p != nullptr) _localFree(p.address);
  }
}
