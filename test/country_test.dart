import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/presentation/util/country.dart';

void main() {
  group('countryOfName', () {
    test('emoji-флаг', () {
      expect(countryOfName('🇳🇱 Amsterdam #3').code, 'nl');
      expect(countryOfName('Сервер 🇩🇪 Frankfurt').code, 'de');
    });
    test('название страны или города', () {
      expect(countryOfName('Финляндия · Хельсинки').code, 'fi');
      expect(countryOfName('Tokyo premium').code, 'jp');
    });
    test('двухбуквенный код', () {
      expect(countryOfName('NL-AMS-03').code, 'nl');
      expect(countryOfName('[SE] fast').code, 'se');
    });
    test('неизвестно', () {
      expect(countryOfName('node-17').isKnown, isFalse);
    });
  });

  test('displayNodeName убирает emoji-флаг', () {
    expect(displayNodeName('🇳🇱 Amsterdam #3'), 'Amsterdam #3');
    expect(displayNodeName('🇫🇮 | Helsinki'), 'Helsinki');
  });

  test('для каждой известной страны есть оба флага в ассетах', () {
    for (final f in Directory('assets/flags/circle').listSync().whereType<File>().where((f) => f.path.endsWith('.svg'))) {
      final code = f.uri.pathSegments.last.replaceAll('.svg', '');
      expect(hasFlagAsset(code), isTrue, reason: code);
      expect(File('assets/flags/square/$code.svg').existsSync(), isTrue, reason: code);
    }
  });
}
