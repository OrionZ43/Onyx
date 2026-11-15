import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/infrastructure/binary_manager.dart';
import 'package:onyx/infrastructure/update_service.dart';

/// #54: встроенное обновление ставит новую версию установщиком
/// (`OnyxSetup_<tag>.exe /VERYSILENT`) и проверяет SHA-256 из релиза.

/// «Установщик» для тестов: заголовок MZ и чуть больше минимального размера.
Uint8List _fakeSetup({int fill = 0}) {
  final b = Uint8List(UpdateService.minInstallerBytes + 4096)..fillRange(2, UpdateService.minInstallerBytes + 4096, fill);
  b[0] = 0x4D; // M
  b[1] = 0x5A; // Z
  return b;
}

String _sha(List<int> bytes) => crypto.sha256.convert(bytes).toString();

void main() {
  const tag = 'v0.4.0';
  final good = _sha(_fakeSetup());

  group('файл установщика в релизе', () {
    Map asset(String name, {String? digest}) => {
          'name': name,
          'browser_download_url': 'https://github.com/OrionZ43/Onyx/releases/download/$tag/$name',
          if (digest != null) 'digest': digest,
        };

    test('берём OnyxSetup_<tag>.exe и его SHA-256; payload.zip — нет', () {
      final a = UpdateService.pickInstallerAsset([
        asset('Onyx_${tag}_payload.zip', digest: 'sha256:${'1' * 64}'),
        asset('onyx-setup-windows.exe', digest: 'sha256:${'2' * 64}'),
        asset('OnyxSetup_$tag.exe', digest: 'sha256:${good.toUpperCase()}'),
      ], tag)!;
      expect(a.url, endsWith('/OnyxSetup_$tag.exe'));
      expect(a.sha256, good); // в нижнем регистре
    });

    test('запасные имена: любой OnyxSetup_*.exe, затем onyx-setup-windows.exe', () {
      expect(UpdateService.pickInstallerAsset([asset('OnyxSetup_v0.4.0-rc1.exe')], tag)!.url, endsWith('OnyxSetup_v0.4.0-rc1.exe'));
      final stable = UpdateService.pickInstallerAsset([asset('onyx-setup-windows.exe')], tag)!;
      expect(stable.url, endsWith('/onyx-setup-windows.exe'));
      expect(stable.sha256, isNull); // без digest — суммы нет
      expect(UpdateService.pickInstallerAsset([asset('Onyx_${tag}_payload.zip')], tag), isNull);
    });

    test('digest: только sha256 из 64 hex-символов', () {
      expect(UpdateService.parseDigest('sha256:$good'), good);
      expect(UpdateService.parseDigest('sha512:${'a' * 128}'), isNull);
      expect(UpdateService.parseDigest('sha256:abc'), isNull);
      expect(UpdateService.parseDigest(null), isNull);
      expect(UpdateService.parseDigest(42), isNull);
    });
  });

  group('откуда качать', () {
    const url = 'https://github.com/OrionZ43/Onyx/releases/download/v0.4.0/OnyxSetup_v0.4.0.exe';

    test('сумма известна — сначала GitHub, потом зеркала', () {
      expect(UpdateService.downloadSources(url, good), [
        url,
        for (final m in BinaryManager.githubMirrors) '$m$url',
      ]);
    });

    test('суммы нет — только GitHub напрямую (подмену на зеркале нечем поймать)', () {
      expect(UpdateService.downloadSources(url, null), [url]);
    });

    test('не github.com — без зеркал', () {
      expect(UpdateService.downloadSources('https://example.com/OnyxSetup.exe', good), ['https://example.com/OnyxSetup.exe']);
    });
  });

  group('проверка скачанного', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('onyx_upd_test_'));
    tearDown(() async => tmp.delete(recursive: true));

    Future<File> write(List<int> bytes) async => File('${tmp.path}${Platform.pathSeparator}s.exe')..writeAsBytesSync(bytes);

    test('MZ, размер и сумма совпали — ок', () async {
      await UpdateService.verifyInstaller(await write(_fakeSetup()), good);
      await UpdateService.verifyInstaller(await write(_fakeSetup()), null);
    });

    test('сумма не та — отказ', () async {
      await expectLater(UpdateService.verifyInstaller(await write(_fakeSetup(fill: 7)), good), throwsFormatException);
    });

    test('не exe или слишком маленький — отказ', () async {
      final notExe = _fakeSetup()..[0] = 0x50;
      await expectLater(UpdateService.verifyInstaller(await write(notExe), null), throwsFormatException);
      await expectLater(UpdateService.verifyInstaller(await write([0x4D, 0x5A, 1, 2, 3]), null), throwsFormatException);
    });
  });

  group('загрузка', () {
    late Directory tmp;
    late HttpServer server;
    final hits = <String>[];

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('onyx_upd_dl_');
      UpdateService.updateDir = () => tmp;
      hits.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        hits.add(req.uri.path);
        switch (req.uri.path) {
          case '/tampered':
            req.response.add(_fakeSetup(fill: 9)); // «зеркало» с подменой
          case '/good':
            req.response.add(_fakeSetup());
          default:
            req.response.statusCode = 404;
        }
        await req.response.close();
      });
    });

    tearDown(() async {
      UpdateService.updateDir = () => Directory('${Directory.systemTemp.path}${Platform.pathSeparator}onyx_update');
      UpdateService.sourcesFor = UpdateService.downloadSources;
      await server.close(force: true);
      await tmp.delete(recursive: true);
    });

    String at(String p) => 'http://127.0.0.1:${server.port}$p';

    test('подмена и 404 отбрасываются, берётся источник с верной суммой', () async {
      UpdateService.sourcesFor = (_, __) => [at('/missing'), at('/tampered'), at('/good')];
      final path = await UpdateService().downloadUpdate(at('/x'), sha256: good);
      expect(hits, ['/missing', '/tampered', '/good']);
      expect(_sha(File(path).readAsBytesSync()), good);
    });

    test('все источники плохие — понятная ошибка, файла не остаётся', () async {
      UpdateService.sourcesFor = (_, __) => [at('/tampered')];
      await expectLater(UpdateService().downloadUpdate(at('/x'), sha256: good), throwsException);
      expect(File('${tmp.path}${Platform.pathSeparator}OnyxSetup.exe').existsSync(), isFalse);
    });
  });

  test('тихий запуск установщика: без окон, без перезагрузки, с отметкой обновления и журналом', () {
    expect(UpdateService.silentArgs(r'C:\t\setup.log'), [
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/ONYXUPDATE=1',
      r'/LOG=C:\t\setup.log',
    ]);
  });

  test('обновление тестовой установки остаётся тестовым и в её папке (#104)', () {
    expect(UpdateService.silentArgs(r'C:\t\setup.log', testInstallDir: r'C:\Users\U Z\AppData\Local\Onyx-test'), [
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/ONYXUPDATE=1',
      '/ONYXTEST=1',
      r'/DIR=C:\Users\U Z\AppData\Local\Onyx-test',
      r'/LOG=C:\t\setup.log',
    ]);
  });

  test('тестовая установка узнаётся по метке onyxtest.flag рядом с onyx.exe', () async {
    final dir = await Directory.systemTemp.createTemp('onyx_test_install_');
    addTearDown(() => dir.delete(recursive: true));
    expect(UpdateService.isTestInstall(dir.path), isFalse);
    await File('${dir.path}${Platform.pathSeparator}onyxtest.flag').writeAsString('ONYXTEST');
    expect(UpdateService.isTestInstall(dir.path), isTrue);
  });

  test('версии: релиз новее своей pre-release, старый релиз — не новее', () {
    expect(UpdateService.isNewerVersion('0.4.0', '0.3.0'), isTrue);
    expect(UpdateService.isNewerVersion('0.3.0', '0.3.0-rc1'), isTrue);
    expect(UpdateService.isNewerVersion('0.2.0', '0.3.0'), isFalse);
    expect(UpdateService.isNewerVersion('0.3.0-rc2', '0.3.0'), isFalse);
  });
}
