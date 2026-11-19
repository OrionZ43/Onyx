import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../tool/pe_subsystem.dart';

/// #69: onyx-core.exe — оконная подсистема, чтобы задача ядра не открывала
/// окно консоли (на Windows 11 — Терминал, похожий на PowerShell).

/// Минимальный заголовок PE32+: MZ → e_lfanew → «PE\0\0» → COFF →
/// необязательный заголовок (magic 0x20B) с подсистемой [subsystem].
Uint8List _fakePe({int subsystem = peSubsystemCui, int checksum = 0}) {
  final pe = Uint8List(0x200);
  final b = ByteData.sublistView(pe);
  pe[0] = 0x4D;
  pe[1] = 0x5A;
  b.setUint32(0x3C, 0x80, Endian.little);
  pe.setAll(0x80, [0x50, 0x45, 0, 0]);
  const opt = 0x80 + 24;
  b.setUint16(opt, 0x20B, Endian.little);
  b.setUint32(opt + 64, checksum, Endian.little);
  b.setUint16(opt + 68, subsystem, Endian.little);
  for (var i = 0x180; i < pe.length; i++) {
    pe[i] = i & 0xFF; // «код»
  }
  return pe;
}

void main() {
  test('консольный exe становится оконным; меняется только поле подсистемы', () {
    final pe = _fakePe();
    expect(peSubsystem(pe), peSubsystemCui);
    final gui = withPeSubsystem(pe, peSubsystemGui);
    expect(peSubsystem(gui), peSubsystemGui);
    final changed = [for (var i = 0; i < pe.length; i++) if (pe[i] != gui[i]) i];
    expect(changed, [0x80 + 24 + 68]); // младший байт Subsystem (3 → 2)
    expect(peSubsystem(pe), peSubsystemCui, reason: 'исходник не меняется');
  });

  test('повторный прогон ничего не меняет', () {
    final gui = withPeSubsystem(_fakePe(), peSubsystemGui);
    expect(withPeSubsystem(gui, peSubsystemGui), gui);
  });

  test('заданный CheckSum пересчитывается, нулевой остаётся нулём', () {
    final withSum = withPeSubsystem(_fakePe(checksum: 0x1234), peSubsystemGui);
    final b = ByteData.sublistView(withSum);
    const at = 0x80 + 24 + 64;
    expect(b.getUint32(at, Endian.little), peChecksum(withSum, at));
    expect(ByteData.sublistView(withPeSubsystem(_fakePe(), peSubsystemGui)).getUint32(at, Endian.little), 0);
  });

  test('не PE — отказ, файл не портим', () {
    expect(() => peSubsystem(Uint8List.fromList(List.filled(0x100, 0))), throwsFormatException);
    final noSig = _fakePe()..[0x80] = 0x51;
    expect(() => withPeSubsystem(noSig, peSubsystemGui), throwsFormatException);
    final shortFile = Uint8List.fromList([0x4D, 0x5A, 1, 2]);
    expect(() => peSubsystem(shortFile), throwsFormatException);
  });

  test('настоящий консольный exe Windows читается и правится', () {
    final whoami = File('${Platform.environment['SystemRoot'] ?? r'C:\Windows'}\\System32\\whoami.exe');
    final pe = whoami.readAsBytesSync();
    expect(peSubsystem(pe), peSubsystemCui);
    expect(peSubsystem(withPeSubsystem(pe, peSubsystemGui)), peSubsystemGui);
  }, skip: Platform.isWindows ? false : 'только Windows');
}
