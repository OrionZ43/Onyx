// Очистка готовых фраз автопилота для показа (util/country.dart, #65).
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/presentation/util/country.dart';

void main() {
  test('uiText убирает emoji-флаги из имён серверов внутри фразы', () {
    expect(
      uiText('Связь с 🇳🇱 Амстердам AMS-03 постоянно рвётся. Проверьте интернет или выберите другой сервер.'),
      'Связь с Амстердам AMS-03 постоянно рвётся. Проверьте интернет или выберите другой сервер.',
    );
    expect(uiText('Переключились: 🇫🇮 HEL-02 → 🇩🇪 FRA-01'), 'Переключились: HEL-02 → FRA-01');
  });

  test('uiText не трогает фразы без флагов и «ёлочки»', () {
    const s = 'Стабильного сервера сейчас нет — остаёмся на AMS-03. Позже нажмите «Обновить».';
    expect(uiText(s), s);
  });

  test('displayNodeName — как раньше: без флага и ведущих разделителей', () {
    expect(displayNodeName('🇳🇱 | Амстердам AMS-03'), 'Амстердам AMS-03');
    expect(displayNodeName('🇳🇱'), '🇳🇱');
  });
}
