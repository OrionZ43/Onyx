// Подсистема PE-файла Windows: консольная (CUI) или оконная (GUI) — #69.
//
// onyx-core.exe (запускатель ядра, #55) собирается `dart compile exe`, а тот
// делает только консольные exe. Задача планировщика запускает его в сеансе
// пользователя — и Windows открывает для него окно консоли (на Windows 11 —
// в Терминале, похожем на PowerShell). Окно висит, пока работает туннель, а
// если его закрыть — туннель падает. Оконной подсистеме консоль не нужна:
// окна нет вовсе. sing-box ядро запускает через Process.start, а Dart
// создаёт дочерние процессы с CREATE_NO_WINDOW — у него окна тоже нет.
//
//   dart run tool/pe_subsystem.dart --gui build\onyx-core.exe
//
// Меняется только поле Subsystem необязательного заголовка PE (и CheckSum,
// если он был задан). Код и данные exe не трогаются.

import 'dart:io';
import 'dart:typed_data';

/// IMAGE_SUBSYSTEM_WINDOWS_GUI — оконная программа, консоль не создаётся.
const peSubsystemGui = 2;

/// IMAGE_SUBSYSTEM_WINDOWS_CUI — консольная программа.
const peSubsystemCui = 3;

/// Смещение поля Subsystem от начала необязательного заголовка: одинаково
/// для PE32 и PE32+.
const _subsystemOffset = 68;

/// Смещение CheckSum от начала необязательного заголовка.
const _checksumOffset = 64;

/// Начало необязательного заголовка PE; бросает [FormatException], если это
/// не PE-файл Windows.
int _optionalHeader(Uint8List pe) {
  final b = ByteData.sublistView(pe);
  if (pe.length < 0x40 || pe[0] != 0x4D || pe[1] != 0x5A) {
    throw const FormatException('не PE-файл: нет заголовка MZ');
  }
  final peOff = b.getUint32(0x3C, Endian.little);
  if (peOff + 24 + _subsystemOffset + 2 > pe.length) {
    throw const FormatException('не PE-файл: заголовок PE за пределами файла');
  }
  if (pe[peOff] != 0x50 || pe[peOff + 1] != 0x45 || pe[peOff + 2] != 0 || pe[peOff + 3] != 0) {
    throw const FormatException('не PE-файл: нет сигнатуры PE');
  }
  final opt = peOff + 24;
  final magic = b.getUint16(opt, Endian.little);
  if (magic != 0x10B && magic != 0x20B) {
    throw FormatException('неизвестный необязательный заголовок PE (0x${magic.toRadixString(16)})');
  }
  return opt;
}

/// Подсистема PE-файла ([peSubsystemGui], [peSubsystemCui] или другая).
int peSubsystem(Uint8List pe) =>
    ByteData.sublistView(pe).getUint16(_optionalHeader(pe) + _subsystemOffset, Endian.little);

/// Копия [pe] с подсистемой [subsystem]. CheckSum пересчитывается, только
/// если он был задан (у обычных exe он 0, загрузчик его не проверяет).
Uint8List withPeSubsystem(Uint8List pe, int subsystem) {
  final out = Uint8List.fromList(pe);
  final b = ByteData.sublistView(out);
  final opt = _optionalHeader(out);
  b.setUint16(opt + _subsystemOffset, subsystem, Endian.little);
  if (b.getUint32(opt + _checksumOffset, Endian.little) != 0) {
    b.setUint32(opt + _checksumOffset, peChecksum(out, opt + _checksumOffset), Endian.little);
  }
  return out;
}

/// Контрольная сумма PE (как CheckSumMappedFile): сумма 16-битных слов с
/// переносом, без самого поля CheckSum, плюс длина файла.
int peChecksum(Uint8List pe, int checksumAt) {
  var sum = 0;
  for (var i = 0; i < pe.length; i += 2) {
    if (i == checksumAt || i == checksumAt + 2) continue;
    final word = pe[i] | (i + 1 < pe.length ? pe[i + 1] << 8 : 0);
    sum += word;
    sum = (sum & 0xFFFF) + (sum >> 16);
  }
  sum = (sum & 0xFFFF) + (sum >> 16);
  return (sum + pe.length) & 0xFFFFFFFF;
}

Future<void> main(List<String> args) async {
  if (args.length != 2 || (args[0] != '--gui' && args[0] != '--cui')) {
    stderr.writeln('usage: dart run tool/pe_subsystem.dart --gui|--cui <file.exe>');
    exit(64);
  }
  final file = File(args[1]);
  final pe = await file.readAsBytes();
  final want = args[0] == '--gui' ? peSubsystemGui : peSubsystemCui;
  final was = peSubsystem(pe);
  if (was != want) await file.writeAsBytes(withPeSubsystem(pe, want), flush: true);
  stdout.writeln('${file.path}: subsystem $was → ${peSubsystem(await file.readAsBytes())}');
}
