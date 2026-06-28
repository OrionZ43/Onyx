import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:archive/archive.dart';
import '../core/log_service.dart';

/// Управляет бинарниками sing-box и wintun.
/// При первом запуске скачивает их с GitHub.
class BinaryManager {
  BinaryManager._();
  static final instance = BinaryManager._();

  static const _singboxVersion = '1.10.1';
  static const _singboxUrlWindows =
      'https://github.com/SagerNet/sing-box/releases/download/'
      'v$_singboxVersion/sing-box-$_singboxVersion-windows-amd64.zip';
  static const _singboxUrlAndroid =
      'https://github.com/SagerNet/sing-box/releases/download/'
      'v$_singboxVersion/sing-box-$_singboxVersion-android-arm64.tar.gz';

  static const _wintunUrl = 'https://www.wintun.net/builds/wintun-0.14.1.zip';
  static const _geositeUrl =
      'https://github.com/SagerNet/sing-geosite/releases/latest/download/geosite.db';
  static const _geoipUrl =
      'https://github.com/SagerNet/sing-geoip/releases/latest/download/geoip.db';

  late Directory _binDir;
  bool _initialized = false;

  File get singboxExe => Platform.isWindows
      ? File(path.join(_binDir.path, 'sing-box.exe'))
      : File(path.join(_binDir.path, 'sing-box'));

  File get wintunDll => File(path.join(_binDir.path, 'wintun.dll'));
  File get geositeDb => File(path.join(_binDir.path, 'geosite.db'));
  File get geoipDb => File(path.join(_binDir.path, 'geoip.db'));
  File get configFile => File(path.join(_binDir.path, 'config.json'));
  File get pidFile => File(path.join(_binDir.path, 'sing-box.pid'));

  /// Инициализация — создаём папку для бинарников
  Future<void> init() async {
    if (_initialized) return;
    final appDir = await getApplicationSupportDirectory();
    _binDir = Directory(path.join(appDir.path, 'singbox'));
    await _binDir.create(recursive: true);
    _initialized = true;
    log.i('Директория бинарников: ${_binDir.path}', tag: 'BIN');
  }

  /// Проверяет наличие всех необходимых файлов
  bool get isReady {
    if (Platform.isWindows) {
      return singboxExe.existsSync() &&
          wintunDll.existsSync() &&
          geositeDb.existsSync() &&
          geoipDb.existsSync();
    }
    return singboxExe.existsSync() &&
        geositeDb.existsSync() &&
        geoipDb.existsSync();
  }

  /// Скачивает sing-box и wintun если они отсутствуют
  Future<void> ensureBinaries({
    void Function(String status, double? progress)? onStatus,
  }) async {
    await init();

    if (!singboxExe.existsSync()) {
      await _downloadSingbox(onStatus: onStatus);
    } else {
      log.i('sing-box уже есть: ${singboxExe.path}', tag: 'BIN');
    }

    if (Platform.isWindows) {
      if (!wintunDll.existsSync()) {
        await _downloadWintun(onStatus: onStatus);
      } else {
        log.i('wintun.dll уже есть', tag: 'BIN');
      }
    }

    if (!geositeDb.existsSync()) {
      await _downloadFile(_geositeUrl, geositeDb.path, 'geosite.db', onStatus);
    } else {
      log.i('geosite.db уже есть', tag: 'BIN');
    }

    if (!geoipDb.existsSync()) {
      await _downloadFile(_geoipUrl, geoipDb.path, 'geoip.db', onStatus);
    } else {
      log.i('geoip.db уже есть', tag: 'BIN');
    }
  }

  Future<void> _downloadFile(
    String url,
    String savePath,
    String name,
    void Function(String, double?)? onStatus,
  ) async {
    log.i('Скачиваем $name...', tag: 'BIN');
    onStatus?.call('Скачиваем $name...', 0);
    final dio = Dio();

    try {
      await dio.download(
        url,
        savePath,
        onReceiveProgress: (got, total) {
          if (total > 0) {
            final pct = got / total;
            onStatus?.call(
              'Скачиваем $name... ${(pct * 100).toInt()}%',
              pct,
            );
          }
        },
      );
      log.i('$name скачан', tag: 'BIN');
    } catch (e) {
      log.e('Ошибка скачивания $name: $e', tag: 'BIN');
      rethrow;
    }
  }

  Future<void> _downloadSingbox({
    void Function(String, double?)? onStatus,
  }) async {
    log.i('Скачиваем sing-box v$_singboxVersion...', tag: 'BIN');
    onStatus?.call('Скачиваем sing-box $_singboxVersion...', 0);

    final url = Platform.isAndroid ? _singboxUrlAndroid : _singboxUrlWindows;
    final extension = Platform.isAndroid ? '.tar.gz' : '.zip';
    final archivePath = path.join(_binDir.path, 'sing-box$extension');
    final dio = Dio();

    try {
      await dio.download(
        url,
        archivePath,
        onReceiveProgress: (got, total) {
          if (total > 0) {
            final pct = got / total;
            onStatus?.call(
              'Скачиваем sing-box... ${(pct * 100).toInt()}%',
              pct,
            );
          }
        },
      );

      log.i('Распаковываем sing-box...', tag: 'BIN');
      onStatus?.call('Распаковываем...', null);

      final entryName = Platform.isWindows ? 'sing-box.exe' : 'sing-box';
      if (Platform.isAndroid) {
        await _extractFromTarGz(archivePath, entryName, singboxExe.path);
      } else {
        await _extractFromZip(archivePath, entryName, singboxExe.path);
      }

      await File(archivePath).delete();
      log.i('sing-box готов', tag: 'BIN');
    } catch (e) {
      log.e('Ошибка загрузки sing-box: $e', tag: 'BIN');
      rethrow;
    }
  }

  Future<void> _downloadWintun({
    void Function(String, double?)? onStatus,
  }) async {
    log.i('Скачиваем wintun...', tag: 'BIN');
    onStatus?.call('Скачиваем WinTUN драйвер...', 0);

    final zipPath = path.join(_binDir.path, 'wintun.zip');
    final dio = Dio();

    try {
      await dio.download(
        _wintunUrl,
        zipPath,
        onReceiveProgress: (got, total) {
          if (total > 0) {
            onStatus?.call(
              'Скачиваем WinTUN... ${((got / total) * 100).toInt()}%',
              got / total,
            );
          }
        },
      );

      log.i('Распаковываем wintun.dll...', tag: 'BIN');
      await _extractFromZip(
        zipPath,
        'wintun/bin/amd64/wintun.dll',
        wintunDll.path,
      );
      await File(zipPath).delete();
      log.i('wintun.dll готов', tag: 'BIN');
    } catch (e) {
      log.e('Ошибка загрузки wintun: $e', tag: 'BIN');
      rethrow;
    }
  }

  Future<void> _extractFromZip(String zipPath, String entryName, String destPath) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive) {
      if (file.name.endsWith(entryName) && file.isFile) {
        final data = file.content as List<int>;
        await File(destPath).writeAsBytes(data);
        return;
      }
    }
    throw Exception('Entry $entryName not found in ZIP');
  }

  Future<void> _extractFromTarGz(String tgzPath, String entryName, String destPath) async {
    final bytes = await File(tgzPath).readAsBytes();
    final gzDecoded = GZipDecoder().decodeBytes(bytes);
    final archive = TarDecoder().decodeBytes(gzDecoded);
    for (final file in archive) {
      if (file.name.endsWith(entryName) && file.isFile) {
        final data = file.content as List<int>;
        await File(destPath).writeAsBytes(data);
        if (Platform.isAndroid) {
          await Process.run('chmod', ['+x', destPath]);
        }
        return;
      }
    }
    throw Exception('Entry $entryName not found in tar.gz');
  }

  /// Пишет конфиг sing-box в файл
  Future<void> writeConfig(String jsonConfig) async {
    await init();
    await configFile.writeAsString(jsonConfig, flush: true);
    log.d('Конфиг записан: ${configFile.path}', tag: 'BIN');
  }
}
