// lib/domain/cidr_utils.dart
//
// Вычисление КОМПЛЕМЕНТА набора IPv4-подсетей: "всё адресное пространство,
// КРОМЕ перечисленных CIDR".
//
// ─── Зачем это нужно ────────────────────────────────────────────────────────
//
// Параметр `bypassSubnets` у flutter_v2ray называется обманчиво. В нативной
// части плагина (V2rayVPNService.setup()) он реализован так:
//
//     if (BYPASS_SUBNETS пуст)  → builder.addRoute("0.0.0.0", 0)
//     else                      → builder.addRoute(<каждая подсеть из списка>)
//
// То есть это НЕ "исключить эти подсети из туннеля", а ровно наоборот:
// "захватывать в туннель ТОЛЬКО эти подсети". Список — allowlist маршрутов
// VpnService, а не blocklist.
//
// Старый код Onyx передавал туда 18 RU-подсетей, ожидая "RU в обход VPN".
// Фактический эффект был инверсным: в туннель попадал ТОЛЬКО трафик к этим
// RU-подсетям, а весь остальной интернет (включая заблокированные сервисы,
// ради которых VPN и включают) шёл напрямую, без шифрования.
//
// Правильный способ исключить подсети — передать плагину их КОМПЛЕМЕНТ:
// набор CIDR-блоков, покрывающий всё пространство 0.0.0.0/0, кроме
// исключаемых диапазонов. Это и делает [complementCidrs].
//
// Алгоритм: CIDR → полуинтервалы [start, end) → merge → комплемент над
// [0, 2^32) → минимальное CIDR-покрытие каждого интервала. Для 18 RU-подсетей
// комплемент состоит из ~207 блоков — VpnService спокойно переваривает
// сотни addRoute().

/// Возвращает минимальный набор CIDR, покрывающий всё IPv4-пространство,
/// кроме подсетей из [excluded].
///
/// Некорректные записи в [excluded] игнорируются (лучше захватить в туннель
/// лишнее, чем уронить подключение из-за опечатки в списке).
List<String> complementCidrs(List<String> excluded) {
  final ranges = <_Range>[];
  for (final cidr in excluded) {
    final r = _parseCidr(cidr);
    if (r != null) ranges.add(r);
  }
  if (ranges.isEmpty) return const ['0.0.0.0/0'];

  final merged = _merge(ranges);
  final complement = _complement(merged);

  final result = <String>[];
  for (final r in complement) {
    _rangeToCidrs(r.start, r.end, result);
  }
  return result;
}

class _Range {
  const _Range(this.start, this.end); // [start, end)
  final int start;
  final int end;
}

_Range? _parseCidr(String cidr) {
  final slash = cidr.split('/');
  if (slash.length != 2) return null;
  final prefix = int.tryParse(slash[1]);
  if (prefix == null || prefix < 0 || prefix > 32) return null;

  final octets = slash[0].split('.');
  if (octets.length != 4) return null;
  var ip = 0;
  for (final o in octets) {
    final v = int.tryParse(o);
    if (v == null || v < 0 || v > 255) return null;
    ip = (ip << 8) | v;
  }
  final size = 1 << (32 - prefix);
  // Выравниваем начало по границе блока — защита от записей вида 1.2.3.4/24.
  final start = ip & ~(size - 1);
  return _Range(start, start + size);
}

List<_Range> _merge(List<_Range> ranges) {
  final sorted = List<_Range>.from(ranges)
    ..sort((a, b) => a.start.compareTo(b.start));
  final out = <_Range>[];
  for (final r in sorted) {
    if (out.isNotEmpty && r.start <= out.last.end) {
      final last = out.removeLast();
      out.add(_Range(last.start, r.end > last.end ? r.end : last.end));
    } else {
      out.add(r);
    }
  }
  return out;
}

List<_Range> _complement(List<_Range> merged) {
  const space = 0x100000000; // 2^32
  final out = <_Range>[];
  var cursor = 0;
  for (final r in merged) {
    if (cursor < r.start) out.add(_Range(cursor, r.start));
    if (r.end > cursor) cursor = r.end;
  }
  if (cursor < space) out.add(_Range(cursor, space));
  return out;
}

/// Раскладывает полуинтервал [start, end) на минимальный набор CIDR-блоков.
void _rangeToCidrs(int start, int end, List<String> out) {
  var s = start;
  while (s < end) {
    // Максимальный блок, выровненный по s (low bit) и не выходящий за end.
    var maxAlign = s == 0 ? 0x100000000 : (s & -s);
    while (maxAlign > end - s) {
      maxAlign >>= 1;
    }
    final prefix = 32 - (maxAlign.bitLength - 1);
    out.add(
      '${(s >> 24) & 255}.${(s >> 16) & 255}.${(s >> 8) & 255}.${s & 255}'
      '/$prefix',
    );
    s += maxAlign;
  }
}
