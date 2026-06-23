import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../core/log_service.dart';

/// Управляет бинарниками sing-box и wintun.
/// При первом запуске скачивает их с GitHub.
class BinaryManager {
  BinaryManager._();
  static final instance = BinaryManager._();

  static const _singboxVersion = '1.10.1';
  static const _singboxUrl =
      'https://github.com/SagerNet/sing-box/releases/download/'
      'v$_singboxVersion/sing-box-$_singboxVersion-windows-amd64.zip';
  static const _wintunUrl = 'https://www.wintun.net/builds/wintun-0.14.1.zip';

  late Directory _binDir;
  bool _initialized = false;

  File get singboxExe => File('${_binDir.path}\\sing-box.exe');
  File get wintunDll => File('${_binDir.path}\\wintun.dll');
  File get configFile => File('${_binDir.path}\\config.json');
  File get pidFile => File('${_binDir.path}\\sing-box.pid');

  /// Инициализация — создаём папку для бинарников
  Future<void> init() async {
    if (_initialized) return;
    final appDir = await getApplicationSupportDirectory();
    _binDir = Directory('${appDir.path}\\singbox');
    await _binDir.create(recursive: true);
    _initialized = true;
    log.i('Директория бинарников: ${_binDir.path}', tag: 'BIN');
  }

  /// Проверяет наличие всех необходимых файлов
  bool get isReady => singboxExe.existsSync() && wintunDll.existsSync();

  /// Скачивает sing-box и wintun если они отсутствуют
  Future<void> ensureBinaries({
    void Function(String status, double? progress)? onStatus,
  }) async {
    await init();

    if (!singboxExe.existsSync()) {
      await _downloadSingbox(onStatus: onStatus);
    } else {
      log.i('sing-box.exe уже есть: ${singboxExe.path}', tag: 'BIN');
    }

    if (!wintunDll.existsSync()) {
      await _downloadWintun(onStatus: onStatus);
    } else {
      log.i('wintun.dll уже есть', tag: 'BIN');
    }
  }

  Future<void> _downloadSingbox({
    void Function(String, double?)? onStatus,
  }) async {
    log.i('Скачиваем sing-box v$_singboxVersion...', tag: 'BIN');
    onStatus?.call('Скачиваем sing-box $_singboxVersion...', 0);

    final zipPath = '${_binDir.path}\\sing-box.zip';
    final dio = Dio();

    try {
      await dio.download(
        _singboxUrl,
        zipPath,
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
      await _extractExeFromZip(zipPath, 'sing-box.exe', singboxExe.path);
      await File(zipPath).delete();
      log.i('sing-box.exe готов', tag: 'BIN');
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

    final zipPath = '${_binDir.path}\\wintun.zip';
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
      // wintun.dll находится в wintun/bin/amd64/wintun.dll
      await _extractFileFromZip(
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

  /// Извлекает конкретный EXE из ZIP через PowerShell
  Future<void> _extractExeFromZip(
    String zipPath,
    String exeName,
    String destPath,
  ) async {
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      '''
      Add-Type -AssemblyName System.IO.Compression.FileSystem
      \$zip = [System.IO.Compression.ZipFile]::OpenRead('$zipPath')
      \$entry = \$zip.Entries | Where-Object { \$_.Name -eq '$exeName' } | Select-Object -First 1
      if (\$entry) {
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile(\$entry, '$destPath', \$true)
        Write-Output "OK"
      } else {
        Write-Error "Entry $exeName not found"
        exit 1
      }
      \$zip.Dispose()
      ''',
    ]);

    if (result.exitCode != 0) {
      throw Exception('Не удалось извлечь $exeName: ${result.stderr}');
    }
  }

  Future<void> _extractFileFromZip(
    String zipPath,
    String entryPath,
    String destPath,
  ) async {
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      '''
      Add-Type -AssemblyName System.IO.Compression.FileSystem
      \$zip = [System.IO.Compression.ZipFile]::OpenRead('$zipPath')
      \$entry = \$zip.Entries | Where-Object { \$_.FullName -eq '$entryPath' } | Select-Object -First 1
      if (\$entry) {
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile(\$entry, '$destPath', \$true)
        Write-Output "OK"
      } else {
        Write-Error "Entry $entryPath not found"
        exit 1
      }
      \$zip.Dispose()
      ''',
    ]);

    if (result.exitCode != 0) {
      throw Exception('Не удалось извлечь $entryPath: ${result.stderr}');
    }
  }

  /// Пишет конфиг sing-box в файл
  Future<void> writeConfig(String jsonConfig) async {
    await init();
    await configFile.writeAsString(jsonConfig, flush: true);
    log.d('Конфиг записан: ${configFile.path}', tag: 'BIN');
  }
}
