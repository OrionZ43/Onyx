/// Страна сервера по его имени из подписки — только для отображения
/// (флаг, группировка). Сетевую часть не трогает.
///
/// Порядок: emoji-флаг (пара региональных индикаторов) → название страны
/// (рус./англ.) → отдельный двухбуквенный код (`NL`, `de-1`).
library;

class Country {
  const Country(this.code, this.name);

  /// ISO 3166-1 alpha-2 в нижнем регистре (`nl`) или '' если не распознали.
  final String code;

  /// Название по-русски.
  final String name;

  bool get isKnown => code.isNotEmpty;

  static const unknown = Country('', 'Другие');
}

const Map<String, String> _names = {
  'ad': 'Андорра', 'ae': 'ОАЭ', 'al': 'Албания', 'am': 'Армения',
  'ar': 'Аргентина', 'at': 'Австрия', 'au': 'Австралия', 'az': 'Азербайджан',
  'ba': 'Босния и Герцеговина', 'be': 'Бельгия', 'bg': 'Болгария',
  'bh': 'Бахрейн', 'br': 'Бразилия', 'by': 'Беларусь', 'ca': 'Канада',
  'ch': 'Швейцария', 'cl': 'Чили', 'cn': 'Китай', 'co': 'Колумбия',
  'cy': 'Кипр', 'cz': 'Чехия', 'de': 'Германия', 'dk': 'Дания',
  'ee': 'Эстония', 'eg': 'Египет', 'es': 'Испания', 'fi': 'Финляндия',
  'fr': 'Франция', 'gb': 'Великобритания', 'ge': 'Грузия', 'gr': 'Греция',
  'hk': 'Гонконг', 'hr': 'Хорватия', 'hu': 'Венгрия', 'id': 'Индонезия',
  'ie': 'Ирландия', 'il': 'Израиль', 'in': 'Индия', 'is': 'Исландия',
  'it': 'Италия', 'jp': 'Япония', 'kg': 'Киргизия', 'kr': 'Южная Корея',
  'kz': 'Казахстан', 'lt': 'Литва', 'lu': 'Люксембург', 'lv': 'Латвия',
  'md': 'Молдова', 'me': 'Черногория', 'mk': 'Северная Македония',
  'mn': 'Монголия', 'mt': 'Мальта', 'mx': 'Мексика', 'my': 'Малайзия',
  'ng': 'Нигерия', 'nl': 'Нидерланды', 'no': 'Норвегия', 'nz': 'Новая Зеландия',
  'pe': 'Перу', 'ph': 'Филиппины', 'pk': 'Пакистан', 'pl': 'Польша',
  'pt': 'Португалия', 'qa': 'Катар', 'ro': 'Румыния', 'rs': 'Сербия',
  'ru': 'Россия', 'sa': 'Саудовская Аравия', 'se': 'Швеция', 'sg': 'Сингапур',
  'si': 'Словения', 'sk': 'Словакия', 'th': 'Таиланд', 'tr': 'Турция',
  'tw': 'Тайвань', 'ua': 'Украина', 'us': 'США', 'uz': 'Узбекистан',
  'vn': 'Вьетнам', 'za': 'ЮАР',
};

/// Ключевые слова → код. Сравнение по нижнему регистру, подстрокой.
const Map<String, String> _keywords = {
  'нидерланд': 'nl', 'голланд': 'nl', 'netherlands': 'nl', 'holland': 'nl', 'amsterdam': 'nl', 'амстердам': 'nl',
  'герман': 'de', 'germany': 'de', 'frankfurt': 'de', 'франкфурт': 'de', 'berlin': 'de', 'берлин': 'de',
  'финлянд': 'fi', 'finland': 'fi', 'helsinki': 'fi', 'хельсинки': 'fi',
  'швец': 'se', 'sweden': 'se', 'stockholm': 'se', 'стокгольм': 'se',
  'польш': 'pl', 'poland': 'pl', 'warsaw': 'pl', 'варшав': 'pl',
  'сша': 'us', 'usa': 'us', 'united states': 'us', 'new york': 'us', 'нью-йорк': 'us',
  'япон': 'jp', 'japan': 'jp', 'tokyo': 'jp', 'токио': 'jp',
  'великобрит': 'gb', 'англи': 'gb', 'united kingdom': 'gb', 'london': 'gb', 'лондон': 'gb',
  'франц': 'fr', 'france': 'fr', 'paris': 'fr', 'париж': 'fr',
  'швейцар': 'ch', 'switzerland': 'ch', 'zurich': 'ch', 'цюрих': 'ch',
  'австри': 'at', 'austria': 'at', 'vienna': 'at', 'вена': 'at',
  'эстони': 'ee', 'estonia': 'ee', 'tallinn': 'ee', 'таллин': 'ee',
  'латви': 'lv', 'latvia': 'lv', 'riga': 'lv', 'рига': 'lv',
  'литв': 'lt', 'lithuania': 'lt', 'vilnius': 'lt', 'вильнюс': 'lt',
  'казахстан': 'kz', 'kazakhstan': 'kz', 'almaty': 'kz', 'алматы': 'kz',
  'турци': 'tr', 'turkey': 'tr', 'türkiye': 'tr', 'istanbul': 'tr', 'стамбул': 'tr',
  'канад': 'ca', 'canada': 'ca', 'сингапур': 'sg', 'singapore': 'sg',
  'гонконг': 'hk', 'hong kong': 'hk', 'росси': 'ru', 'russia': 'ru', 'moscow': 'ru', 'москв': 'ru',
  'украин': 'ua', 'ukraine': 'ua', 'испани': 'es', 'spain': 'es', 'итали': 'it', 'italy': 'it',
  'норвег': 'no', 'norway': 'no', 'дани': 'dk', 'denmark': 'dk', 'чехи': 'cz', 'czech': 'cz',
  'румыни': 'ro', 'romania': 'ro', 'венгри': 'hu', 'hungary': 'hu', 'болгари': 'bg', 'bulgaria': 'bg',
  'сербия': 'rs', 'serbia': 'rs', 'молдов': 'md', 'moldova': 'md', 'грузи': 'ge', 'georgia': 'ge',
  'армени': 'am', 'armenia': 'am', 'оаэ': 'ae', 'emirates': 'ae', 'dubai': 'ae', 'дубай': 'ae',
  'израил': 'il', 'israel': 'il', 'инди': 'in', 'india': 'in', 'корея': 'kr', 'korea': 'kr',
  'австрали': 'au', 'australia': 'au', 'бразили': 'br', 'brazil': 'br', 'ирланд': 'ie', 'ireland': 'ie',
  'бельги': 'be', 'belgium': 'be', 'португал': 'pt', 'portugal': 'pt', 'греци': 'gr', 'greece': 'gr',
};

Country countryOfName(String name) {
  // 1. emoji-флаг: два символа U+1F1E6..U+1F1FF.
  final runes = name.runes.toList();
  for (var i = 0; i + 1 < runes.length; i++) {
    final a = runes[i], b = runes[i + 1];
    if (_isRegional(a) && _isRegional(b)) {
      final code = String.fromCharCodes([a - 0x1F1E6 + 0x61, b - 0x1F1E6 + 0x61]);
      return Country(code, _names[code] ?? code.toUpperCase());
    }
  }
  // 2. Название страны или города.
  final lower = name.toLowerCase();
  for (final e in _keywords.entries) {
    if (lower.contains(e.key)) return Country(e.value, _names[e.value]!);
  }
  // 3. Отдельный двухбуквенный код: «NL», «DE-2», «[FI] …».
  for (final m in RegExp(r'(?:^|[^A-Za-z])([A-Z]{2})(?![A-Za-z])').allMatches(name)) {
    final code = m.group(1)!.toLowerCase();
    if (_names.containsKey(code)) return Country(code, _names[code]!);
  }
  return Country.unknown;
}

/// Страна по коду (выбор пользователя, страна выхода из проверки).
/// Неизвестный код — [Country.unknown].
Country countryByCode(String code) {
  final c = code.toLowerCase();
  final name = _names[c];
  return name == null ? Country.unknown : Country(c, name);
}

/// Все страны, для которых есть флаг, — по алфавиту (выбор страны вручную).
List<Country> allCountries() =>
    [for (final e in _names.entries) Country(e.key, e.value)]..sort((a, b) => a.name.compareTo(b.name));

/// Имя сервера без emoji-флага и лишних разделителей — для заголовка строки.
String displayNodeName(String name) {
  final cleaned = _withoutFlags(name).replaceAll(RegExp(r'^[\s|\-–—·•:]+'), '').trim();
  return cleaned.isEmpty ? name : cleaned;
}

/// Готовая фраза домена («Связь с 🇳🇱 AMS-03 постоянно рвётся…») — без
/// emoji-флагов. Имена серверов в фразы автопилота попадают как есть, а
/// Windows рисует флаг двумя буквами («NL»); флаг в интерфейсе — свой
/// (CountryFlag). Пробелы, оставшиеся от флага, схлопываем.
String uiText(String text) => _withoutFlags(text).replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();

String _withoutFlags(String s) => String.fromCharCodes(s.runes.where((r) => !_isRegional(r) && r != 0xFE0F));

bool _isRegional(int r) => r >= 0x1F1E6 && r <= 0x1F1FF;

/// Есть ли флаг в ассетах (см. assets/flags).
bool hasFlagAsset(String code) => _names.containsKey(code);
