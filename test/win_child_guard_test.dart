import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/infrastructure/win_child_guard.dart';

/// #57: дочерние sing-box не переживают onyx.exe, брошенные копии
/// убираются, чужие процессы не трогаются.
void main() {
  group('selectOrphans', () {
    const exe = r'C:\Users\U\AppData\Roaming\z43.studios\onyx\singbox\sing-box.exe';
    final images = <int, String?>{
      10: exe, // сирота: родителя 999 нет
      11: exe, // ребёнок живого onyx.exe (20)
      12: r'C:\Program Files\Hiddify\sing-box.exe', // чужой sing-box, тоже сирота
      13: exe.toUpperCase(), // путь в другом регистре — тот же файл
      14: null, // образ не узнать (нет доступа) — не трогаем
    };
    final procs = [
      const ProcEntry(10, 999, 'sing-box.exe'),
      const ProcEntry(11, 20, 'sing-box.exe'),
      const ProcEntry(12, 998, 'sing-box.exe'),
      const ProcEntry(13, 997, 'SING-BOX.EXE'),
      const ProcEntry(14, 996, 'sing-box.exe'),
      const ProcEntry(20, 1, 'onyx.exe'),
      const ProcEntry(30, 999, 'notepad.exe'),
    ];

    test('только наш образ и только с мёртвым родителем', () {
      expect(WinChildGuard.selectOrphans(procs, exe, (pid) => images[pid]), [10, 13]);
    });

    test('ребёнок живого процесса — не сирота', () {
      final res = WinChildGuard.selectOrphans(procs, exe, (pid) => images[pid]);
      expect(res, isNot(contains(11)));
    });

    test('чужой sing-box с тем же именем не трогаем', () {
      final res = WinChildGuard.selectOrphans(procs, exe, (pid) => images[pid]);
      expect(res, isNot(contains(12)));
    });

    test('PID родителя занят живым процессом — считаем родителя живым', () {
      // Сирота 40, но её PID родителя (20) теперь у живого onyx.exe.
      final list = [...procs, const ProcEntry(40, 20, 'sing-box.exe')];
      final res = WinChildGuard.selectOrphans(list, exe, (pid) => pid == 40 ? exe : images[pid]);
      expect(res, isNot(contains(40)));
    });
  });

  group('Windows: задание и сироты', () {
    late Directory dir;
    late String dummy;
    final started = <Process>[];

    setUpAll(() async {
      if (!Platform.isWindows) return;
      // Уникальная копия ping.exe — так killOrphans не может задеть чужие процессы.
      dir = await Directory.systemTemp.createTemp('onyx57-');
      dummy = '${dir.path}\\onyx57dummy.exe';
      await File('${Platform.environment['SystemRoot']}\\System32\\PING.EXE').copy(dummy);
    });

    tearDownAll(() async {
      if (!Platform.isWindows) return;
      for (final p in started) {
        p.kill();
      }
      for (final pid in WinChildGuard.pidsOf(dummy)) {
        Process.killPid(pid);
      }
      for (var i = 0; i < 20; i++) {
        try {
          await dir.delete(recursive: true);
          break;
        } catch (_) {
          await Future.delayed(const Duration(milliseconds: 250));
        }
      }
    });

    Future<void> waitFor(bool Function() cond) async {
      for (var i = 0; i < 40 && !cond(); i++) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }

    test('adopt привязывает дочерний процесс к заданию', () async {
      final p = await Process.start(dummy, ['-n', '60', '127.0.0.1']);
      started.add(p);
      expect(WinChildGuard.isAdopted(p.pid), isFalse);
      expect(WinChildGuard.adopt(p.pid), isTrue);
      expect(WinChildGuard.isAdopted(p.pid), isTrue);
      p.kill();
      await p.exitCode;
    }, skip: !Platform.isWindows);

    test('killOrphans гасит сироту и не трогает ребёнка живого процесса', () async {
      final child = await Process.start(dummy, ['-n', '60', '127.0.0.1']);
      started.add(child);
      // Сирота: PowerShell запускает копию и сразу выходит — родителя нет.
      await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        "Start-Process -FilePath '$dummy' -ArgumentList '-n','60','127.0.0.1' -WindowStyle Hidden",
      ]);
      await waitFor(() => WinChildGuard.pidsOf(dummy).length >= 2);
      final before = WinChildGuard.pidsOf(dummy);
      expect(before, contains(child.pid));
      expect(before.length, greaterThanOrEqualTo(2));

      final killed = WinChildGuard.killOrphans(dummy);
      expect(killed, 1);
      await waitFor(() => WinChildGuard.pidsOf(dummy).length == 1);
      expect(WinChildGuard.pidsOf(dummy), [child.pid]);
    }, skip: !Platform.isWindows);
  });
}
