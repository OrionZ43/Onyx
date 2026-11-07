// Выгрузка эталонных контуров MaterialShapes (порт androidx.graphics.shapes /
// Compose Material3) в SVG-пути для HTML-мокапов. Запуск разовый:
//   скопировать в test/tool/ и запустить: flutter test test/tool/m3_shapes_dump_test.dart
// Результат: docs/redesign/src/m3-shapes.js (копия файла лежит в docs/redesign/src).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:onyx/presentation/widgets/m3/m3_loading_indicator.dart';

String svg(List<Cubic> cubics) {
  final b = StringBuffer();
  String f(double v) => (v * 100).toStringAsFixed(3);
  for (var i = 0; i < cubics.length; i++) {
    final c = cubics[i];
    if (i == 0) b.write('M${f(c.anchor0X)} ${f(c.anchor0Y)}');
    b.write('C${f(c.control0X)} ${f(c.control0Y)} ${f(c.control1X)} ${f(c.control1Y)} ${f(c.anchor1X)} ${f(c.anchor1Y)}');
  }
  return '${b}Z';
}

void main() {
  test('dump', () {
    final names = {
      'circle': MaterialShapes.circle, 'square': MaterialShapes.square, 'slanted': MaterialShapes.slanted,
      'arch': MaterialShapes.arch, 'semiCircle': MaterialShapes.semiCircle, 'oval': MaterialShapes.oval,
      'pill': MaterialShapes.pill, 'triangle': MaterialShapes.triangle, 'arrow': MaterialShapes.arrow,
      'fan': MaterialShapes.fan, 'diamond': MaterialShapes.diamond, 'clamShell': MaterialShapes.clamShell,
      'pentagon': MaterialShapes.pentagon, 'gem': MaterialShapes.gem, 'sunny': MaterialShapes.sunny,
      'verySunny': MaterialShapes.verySunny, 'cookie4Sided': MaterialShapes.cookie4Sided,
      'cookie6Sided': MaterialShapes.cookie6Sided, 'cookie7Sided': MaterialShapes.cookie7Sided,
      'cookie9Sided': MaterialShapes.cookie9Sided, 'cookie12Sided': MaterialShapes.cookie12Sided,
      'clover4Leaf': MaterialShapes.clover4Leaf, 'clover8Leaf': MaterialShapes.clover8Leaf,
      'burst': MaterialShapes.burst, 'softBurst': MaterialShapes.softBurst, 'boom': MaterialShapes.boom,
      'softBoom': MaterialShapes.softBoom, 'flower': MaterialShapes.flower, 'puffy': MaterialShapes.puffy,
      'puffyDiamond': MaterialShapes.puffyDiamond, 'ghostish': MaterialShapes.ghostish,
      'pixelCircle': MaterialShapes.pixelCircle, 'pixelTriangle': MaterialShapes.pixelTriangle,
      'bun': MaterialShapes.bun, 'heart': MaterialShapes.heart,
    };
    final out = StringBuffer('// Сгенерировано test/tool/m3_shapes_dump_test.dart из material_new_shapes 1.0.0\n'
        '// (Dart-порт androidx.graphics.shapes; параметры MaterialShapes — из Compose Material3).\n'
        '// Координаты 0..100, фигуры нормализованы, как в MaterialShapes.\n'
        'const M3_SHAPES = {\n');
    names.forEach((k, v) => out.writeln("  $k: '${svg(v.cubics)}',"));
    out.writeln('};');
    // Кадры морфа LoadingIndicator (IndeterminateIndicatorPolygons): пары соседних форм.
    final seq = LoadingIndicatorShapes.indeterminatePolygons;
    out.writeln('const M3_LOADING_MORPH = [');
    for (var i = 0; i < seq.length; i++) {
      final m = Morph(seq[i], seq[(i + 1) % seq.length]);
      out.writeln("  [${[0.0, 0.35, 0.5, 0.65].map((p) => "'${svg(m.asCubics(p))}'").join(', ')}],");
    }
    out.writeln('];');
    // Морф главной кнопки Onyx-M3: Cookie9 → Sunny (подключено), Cookie9 → Puffy (ошибка).
    for (final e in {'COOKIE_TO_SUNNY': MaterialShapes.sunny, 'COOKIE_TO_PUFFY': MaterialShapes.puffy}.entries) {
      final m = Morph(MaterialShapes.cookie9Sided, e.value);
      out.writeln("const M3_${e.key} = [${[0.0, 0.25, 0.5, 0.75, 1.0].map((p) => "'${svg(m.asCubics(p))}'").join(', ')}];");
    }
    File('m3-shapes.js').writeAsStringSync(out.toString());
  });
}
