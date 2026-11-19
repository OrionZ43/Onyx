import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/domain/smart_probe.dart';

/// Брошенные конфиги проб (в них учётные данные серверов) убираются при
/// старте; свежие — нет: ими может пользоваться соседний экземпляр Onyx.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('onyx_probe_cleanup'));
  tearDown(() => dir.deleteSync(recursive: true));

  File make(String name, {Duration age = Duration.zero}) {
    final f = File('${dir.path}${Platform.pathSeparator}$name')..writeAsStringSync('{}');
    if (age > Duration.zero) f.setLastModifiedSync(DateTime.now().subtract(age));
    return f;
  }

  test('старые onyx_probe_*.json удаляются, свежие и чужие — нет', () {
    final old = make('onyx_probe_2091.json', age: const Duration(hours: 5));
    final fresh = make('onyx_probe_2092.json');
    final foreign = make('other_probe_1.json', age: const Duration(hours: 5));
    final notJson = make('onyx_probe_2093.txt', age: const Duration(hours: 5));

    expect(DeepProbe.cleanupStaleConfigs(dir: dir), 1);
    expect(old.existsSync(), isFalse);
    expect(fresh.existsSync(), isTrue);
    expect(foreign.existsSync(), isTrue);
    expect(notJson.existsSync(), isTrue);
  });
}
