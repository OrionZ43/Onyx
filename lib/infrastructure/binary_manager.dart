import 'dart:io';
import 'package:crypto/crypto.dart' show sha256;
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/services.dart';
import 'package:archive/archive.dart';
import '../core/log_service.dart';
import '../domain/singbox_config_builder.dart';
import '../domain/smart_probe.dart';
import 'win_child_guard.dart';

/// Управляет бинарниками sing-box / wintun и rule-set файлами маршрутизации.
///
/// Откуда берутся файлы (по порядку):
///   1. **Бандл.** Windows-установщик кладёт `core\sing-box.exe` и
///      `core\wintun.dll` рядом с onyx.exe; на Android sing-box лежит в
///      nativeLibraryDir как libsingbox.so. Rule-set (.srs) — во Flutter
///      assets. Сеть не нужна: это главное для Китая, где загрузки с GitHub
///      режутся.
///   2. **Загрузка** (только если бандла нет — dev-сборка или старый
///      установщик): GitHub, затем зеркала. Каждый архив сверяется с
///      закреплённым SHA-256, поэтому подмена на зеркале не пройдёт.
///
/// Версия sing-box записывается в `singbox.version`: при обновлении Onyx
/// старый бинарник в рабочей папке заменяется (конфиг нового формата старый
/// sing-box 1.10 не понимает).
class BinaryManager {
  static const _channel = MethodChannel('z43.studios.onyx/native');

  Future<String> _getNativeLibraryDir() async {
    final dir = await _channel.invokeMethod<String>('getNativeLibraryDir');
    return dir!;
  }

  BinaryManager._();
  static final instance = BinaryManager._();

  static const singboxVersion = '1.14.4';

  static const _singboxUrlWindows =
      'https://github.com/SagerNet/sing-box/releases/download/'
      'v$singboxVersion/sing-box-$singboxVersion-windows-amd64.zip';
  static const _singboxSha256Windows =
      '99185d75d314a07dbba4a130c8ad986cbeb629a07927975636b341ca61f991df';

  static const _wintunUrl = 'https://www.wintun.net/builds/wintun-0.14.1.zip';
  static const _wintunSha256 =
      '07c256185d6ee3652e09fa55c0b673e2624b565e02c4b9091c79ca7d2f24ef51';

  /// Зеркала для github.com (префикс + исходный URL). Используются, только
  /// если прямая загрузка не удалась; целостность гарантирует SHA-256.
  static const githubMirrors = [
    'https://ghfast.top/',
    'https://gh-proxy.com/',
  ];

  late Directory _binDir;
  bool _initialized = false;
  String? _androidNativeLibDir;

  Directory get binDir => _binDir;

  File get singboxExe {
    if (Platform.isAndroid && _androidNativeLibDir != null) {
      return File(path.join(_androidNativeLibDir!, 'libsingbox.so'));
    }
    return Platform.isWindows
        ? File(path.join(_binDir.path, 'sing-box.exe'))
        : File(path.join(_binDir.path, 'sing-box'));
  }

  File get wintunDll => File(path.join(_binDir.path, 'wintun.dll'));
  File get configFile => File(path.join(_binDir.path, 'config.json'));
  File get pidFile => File(path.join(_binDir.path, 'sing-box.pid'));
  File get _versionFile => File(path.join(_binDir.path, 'singbox.version'));

  /// Папка, куда установщик кладёт бандл (`<папка onyx.exe>\core`).
  Directory get _bundledCoreDir =>
      Directory(path.join(File(Platform.resolvedExecutable).parent.path, 'core'));

  Future<void> init() async {
    if (_initialized) return;
    final appDir = await getApplicationSupportDirectory();
    _binDir = Directory(path.join(appDir.path, 'singbox'));
    await _binDir.create(recursive: true);

    if (Platform.isAndroid) {
      _androidNativeLibDir = await _getNativeLibraryDir();
    }

    _initialized = true;
    log.i('Директория бинарников: ${_binDir.path}', tag: 'BIN');

    // Брошенные копии нашего sing-box от прошлого запуска (пробы, туннель
    // после падения) держат singbox\sing-box.exe — обновление ядра не смогло
    // бы его заменить. Свои процессы этого запуска ещё не стартовали (#57).
    if (Platform.isWindows) {
      try {
        WinChildGuard.killOrphans(singboxExe.path);
      } catch (e) {
        log.w('Поиск брошенных sing-box не удался: $e', tag: 'BIN');
      }
    }
    // Их конфиги (с учётными данными серверов) — тоже.
    DeepProbe.cleanupStaleConfigs();
  }

  bool get _ruleSetsReady => SingboxConfigBuilder.ruleSetFiles
      .every((n) => File(path.join(_binDir.path, '$n.srs')).existsSync());

  bool get _versionCurrent =>
      _versionFile.existsSync() &&
      _versionFile.readAsStringSync().trim() == singboxVersion;

  /// Всё ли на месте для подключения.
  ///
  /// Если бандл есть, но ещё не разложен — возвращаем true: ensureBinaries()
  /// разложит его без сети за доли секунды, SetupScreen не нужен.
  bool get isReady {
    if (Platform.isAndroid) return true;
    final local = singboxExe.existsSync() &&
        _versionCurrent &&
        _ruleSetsReady &&
        (!Platform.isWindows || wintunDll.existsSync());
    return local || _hasBundle;
  }

  bool get _hasBundle =>
      Platform.isWindows &&
      File(path.join(_bundledCoreDir.path, 'sing-box.exe')).existsSync() &&
      File(path.join(_bundledCoreDir.path, 'wintun.dll')).existsSync();

  /// Готовит sing-box, wintun и rule-set файлы.
  Future<void> ensureBinaries({
    void Function(String status, double? progress)? onStatus,
  }) async {
    await init();

    // Rule-set — на всех платформах (Android: для цепочки sing-box).
    await _ensureRuleSets(force: !_versionCurrent);

    if (Platform.isAndroid) {
      if (!singboxExe.existsSync()) {
        throw Exception(
          'libsingbox.so не найден в ${singboxExe.path}. Переустановите приложение.',
        );
      }
      await _versionFile.writeAsString(singboxVersion);
      onStatus?.call('Готово', 1.0);
      return;
    }

    final needSingbox = !singboxExe.existsSync() || !_versionCurrent;
    final needWintun = Platform.isWindows && !wintunDll.existsSync();

    if (needSingbox || needWintun) {
      if (_hasBundle) {
        onStatus?.call('Распаковываем ядро...', null);
        if (needSingbox) {
          await _copy(path.join(_bundledCoreDir.path, 'sing-box.exe'), singboxExe.path);
        }
        if (needWintun) {
          await _copy(path.join(_bundledCoreDir.path, 'wintun.dll'), wintunDll.path);
        }
        log.i('Ядро взято из бандла установщика (${_bundledCoreDir.path})', tag: 'BIN');
      } else {
        if (needSingbox) await _downloadSingbox(onStatus: onStatus);
        if (needWintun) await _downloadWintun(onStatus: onStatus);
      }
    }

    await _versionFile.writeAsString(singboxVersion);
    onStatus?.call('Готово', 1.0);
  }

  Future<void> _copy(String from, String to) async {
    await File(from).copy(to);
  }

  Future<void> _ensureRuleSets({bool force = false}) async {
    for (final name in SingboxConfigBuilder.ruleSetFiles) {
      final dest = File(path.join(_binDir.path, '$name.srs'));
      if (!force && dest.existsSync()) continue;
      final data = await rootBundle.load('assets/rules/$name.srs');
      await dest.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    log.d('Rule-set файлы на месте', tag: 'BIN');
  }

  // ── Загрузка (резервный путь) ────────────────────────────────────────────

  /// Скачивает [url] (и при неудаче — через зеркала), проверяет SHA-256.
  Future<List<int>> _downloadVerified(
    String url,
    String expectedSha256,
    String label,
    void Function(String, double?)? onStatus,
  ) async {
    final candidates = [
      url,
      if (url.startsWith('https://github.com/'))
        for (final m in githubMirrors) '$m$url',
    ];
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 3),
    ));
    Object? lastError;
    for (final candidate in candidates) {
      try {
        log.i('Скачиваем $label: $candidate', tag: 'BIN');
        final resp = await dio.get<List<int>>(
          candidate,
          options: Options(responseType: ResponseType.bytes),
          onReceiveProgress: (got, total) {
            if (total > 0) {
              onStatus?.call('Скачиваем $label... ${(got * 100 ~/ total)}%', got / total);
            }
          },
        );
        final bytes = resp.data ?? const <int>[];
        final digest = sha256.convert(bytes).toString();
        if (digest != expectedSha256) {
          lastError = 'SHA-256 не совпал ($digest)';
          log.w('$label с $candidate: неверный SHA-256 — отбрасываем', tag: 'BIN');
          continue;
        }
        return bytes;
      } catch (e) {
        lastError = e;
        log.w('$label: $candidate недоступен: $e', tag: 'BIN');
      }
    }
    throw Exception('Не удалось скачать $label: $lastError');
  }

  Future<void> _downloadSingbox({void Function(String, double?)? onStatus}) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Загрузка sing-box поддерживается только на Windows');
    }
    onStatus?.call('Скачиваем sing-box $singboxVersion...', 0);
    final bytes = await _downloadVerified(
      _singboxUrlWindows,
      _singboxSha256Windows,
      'sing-box',
      onStatus,
    );
    onStatus?.call('Распаковываем...', null);
    _extractFromZip(bytes, 'sing-box.exe', singboxExe.path);
    log.i('sing-box $singboxVersion готов', tag: 'BIN');
  }

  Future<void> _downloadWintun({void Function(String, double?)? onStatus}) async {
    onStatus?.call('Скачиваем WinTUN драйвер...', 0);
    final bytes = await _downloadVerified(_wintunUrl, _wintunSha256, 'WinTUN', onStatus);
    _extractFromZip(bytes, 'wintun/bin/amd64/wintun.dll', wintunDll.path);
    log.i('wintun.dll готов', tag: 'BIN');
  }

  void _extractFromZip(List<int> bytes, String entryName, String destPath) {
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive) {
      if (file.name.endsWith(entryName) && file.isFile) {
        File(destPath).writeAsBytesSync(file.content as List<int>, flush: true);
        return;
      }
    }
    throw Exception('Entry $entryName not found in ZIP');
  }

  /// Пишет конфиг sing-box в файл.
  Future<void> writeConfig(String jsonConfig) async {
    await init();
    await configFile.writeAsString(jsonConfig, flush: true);
    log.d('Конфиг записан: ${configFile.path}', tag: 'BIN');
  }
}
