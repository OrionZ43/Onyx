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