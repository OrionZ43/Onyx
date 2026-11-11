import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum LogLevel { debug, info, warn, error }

class LogEntry {
  LogEntry({
    required this.level,
    required this.message,
    required this.timestamp,
    this.tag = 'APP',
  });

  final LogLevel level;
  final String message;
  final DateTime timestamp;
  final String tag;

  String get levelLabel => switch (level) {
    LogLevel.debug => 'DBG',
    LogLevel.info => 'INF',
    LogLevel.warn => 'WRN',
    LogLevel.error => 'ERR',
  };

  String get timeStr {
    final t = timestamp;
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}'
        '.${(t.millisecond ~/ 10).toString().padLeft(2, '0')}';
  }

  @override
  String toString() => '[$timeStr][$levelLabel][$tag] $message';
}

/// Глобальный логгер. Хранит последние 500 записей в памяти.
/// Пользователь может скопировать весь лог кнопкой "Share" для саппорта —
/// поэтому ЛЮБОЙ секрет (UUID, Reality-ключи) должен быть вымаран из
/// экспортируемого текста, даже если он присутствовал в исходном сообщении
/// (например, дамп конфига sing-box в BRIDGE/CFG тегах).
class LogService extends ChangeNotifier {
  static final instance = LogService._();
  LogService._();

  static const _maxEntries = 500;
  final List<LogEntry> _entries = [];

  List<LogEntry> get entries => List.unmodifiable(_entries);

  // ── Журнал в файле (#69) ────────────────────────────────────────────
  //
  // «Журнал» и «События» живут в памяти и пропадают с выходом Onyx: после
  // жалобы «сам сменил сервер» разобрать случай было не по чему. Теперь
  // строки дублируются в файл: секреты вымараны, как при «Скопировать всё»,
  // дамп конфига (CFG) не пишется. До [maxFileBytes], потом файл уходит в
  // «.1» (одна копия) — на диске не больше двух мегабайт.

  static int maxFileBytes = 1024 * 1024;
  File? _file;
  int _fileBytes = 0;

  /// Файл журнала, если запись в файл включена.
  File? get file => _file;

  /// Выключить запись в файл (тесты).
  @visibleForTesting
  void detachFile() {
    _file = null;
    _fileBytes = 0;
  }

  /// Включить запись журнала в `<dir>/onyx.log`.
  void persistTo(Directory dir) {
    try {
      dir.createSync(recursive: true);
      final f = File('${dir.path}${Platform.pathSeparator}onyx.log');
      _fileBytes = f.existsSync() ? f.lengthSync() : 0;
      _file = f;
      _appendToFile('${'=' * 12} Onyx запущен ${DateTime.now().toIso8601String()} ${'=' * 12}');
    } catch (_) {
      _file = null; // без файла — не беда, журнал в памяти остаётся
    }
  }

  void _appendToFile(String line) {
    final f = _file;
    if (f == null) return;
    try {
      if (_fileBytes > maxFileBytes) {
        final old = File('${f.path}.1');
        if (old.existsSync()) old.deleteSync();
        f.renameSync(old.path);
        _fileBytes = 0;
      }
      final bytes = utf8.encode('$line\n');
      f.writeAsBytesSync(bytes, mode: FileMode.append);
      _fileBytes += bytes.length;
    } catch (_) {
      // Файл занят или диск полон — журнал в памяти всё равно есть.
    }
  }

  void _add(LogLevel level, String message, String tag) {
    _entries.add(
      LogEntry(
        level: level,
        message: message,
        timestamp: DateTime.now(),
        tag: tag,
      ),
    );
    if (_entries.length > _maxEntries) {
      _entries.removeAt(0);
    }
    if (_file != null && tag != 'CFG') {
      final e = _entries.last;
      final t = e.timestamp;
      final day = '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
      _appendToFile('$day ${_redact(e.toString())}');
    }
    // Дублируем в консоль разработчика (полный, немаскированный текст —
    // это локальная консоль во время разработки, не покидает устройство)
    if (kDebugMode) {
      debugPrint(_entries.last.toString());
    }
    notifyListeners();
  }

  void d(String msg, {String tag = 'APP'}) => _add(LogLevel.debug, msg, tag);
  void i(String msg, {String tag = 'APP'}) => _add(LogLevel.info, msg, tag);
  void w(String msg, {String tag = 'APP'}) => _add(LogLevel.warn, msg, tag);
  void e(String msg, {String tag = 'APP'}) => _add(LogLevel.error, msg, tag);

  void clear() {
    _entries.clear();
    notifyListeners();
  }

  // ── Редакция секретов ────────────────────────────────────────────────
  //
  // Конфиг sing-box логируется построчно (тег CFG) для отладки маршрутизации
  // и содержит: uuid (ключ доступа к VLESS-серверу), reality public_key,
  // reality short_id, IP сервера. Всё это должно остаться на экране (для
  // локальной отладки), но НЕ должно уйти при "Скопировать и отправить" —
  // иначе пользователь случайно сольёт свой приватный доступ в саппорт-чат.
  //
  // Паттерны намеренно широкие (ловят JSON-поле независимо от форматирования
  // sing-box: с пробелами, без пробелов, в одну строку или построчно).
  static final List<RegExp> _secretPatterns = [
    RegExp(r'("uuid"\s*:\s*")[^"]+(")'),
    RegExp(r'("public_key"\s*:\s*")[^"]+(")'),
    RegExp(r'("short_id"\s*:\s*")[^"]+(")'),
    RegExp(r'("password"\s*:\s*")[^"]+(")'),
    RegExp(r'("secret"\s*:\s*")[^"]+(")'), // clash_api secret, если задан
  ];

  static String _redact(String line) {
    var out = line;
    for (final pattern in _secretPatterns) {
      out = out.replaceAllMapped(pattern, (m) => '${m[1]}***${m[2]}');
    }
    return out;
  }

  /// Весь лог одной строкой — для кнопки "Скопировать и отправить".
  /// Секреты вымараны независимо от того, как они попали в лог.
  String exportText() =>
      _entries.map((e) => _redact(e.toString())).join('\n');
}

// Shortcut для удобного использования везде
final log = LogService.instance;

// Riverpod provider для watch в UI
final logProvider = ChangeNotifierProvider<LogService>(
      (_) => LogService.instance,
);