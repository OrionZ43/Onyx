import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';

import '../core/log_service.dart';
import 'binary_manager.dart';

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String releaseNotes;
  final DateTime publishedAt;

  /// SHA-256 установщика из релиза (поле `digest` файла в GitHub API), hex в
  /// нижнем регистре. null — у релиза суммы нет: тогда качаем только с
  /// github.com напрямую (TLS), без зеркал.
  final String? sha256;

  UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.publishedAt,
    this.sha256,
  });
}

/// Файл установщика в релизе: ссылка и SHA-256 (если GitHub её отдал).
typedef InstallerAsset = ({String url, String? sha256});

/// Встроенное обновление Windows (#54): скачать установщик релиза и
/// запустить его тихо — тот же Inno-установщик, что ставит Onyx вручную.
///
/// Раньше качался `Onyx_<tag>_payload.zip`, и отдельный OnyxUpdater.exe
/// распаковывал его поверх папки. Это обходило установщик: не обновлялось
/// ядро туннеля в Program Files (#55), запись в «Программах», ярлыки. Теперь:
/// `OnyxSetup_<tag>.exe /VERYSILENT /SUPPRESSMSGBOXES /ONYXUPDATE=1` —
/// установщик сам закрывает Onyx, обновляет файлы (UAC — только если
/// обновилось ядро) и запускает Onyx снова.
///
/// Целостность: SHA-256 из релиза (GitHub API, поле `digest`). Только когда
/// сумма известна, разрешены зеркала github.com — в Китае без VPN github.com
/// часто не открывается, а подмену на зеркале выдаст сумма.
class UpdateService {
  static const _githubApi =
      'https://api.github.com/repos/OrionZ43/Onyx/releases/latest';

  // Версия вшивается из git-тега при сборке в CI: --dart-define=APP_VERSION.
  // Локальная сборка без этого флага — dev: обновления ей НЕ предлагаются,
  // иначе апдейтер ставил бы поверх dev-сборки старый релиз с GitHub
  // (раньше по умолчанию было '0.0.0' — «обновлялось» на что угодно).
  static const isDevBuild = !bool.hasEnvironment('APP_VERSION');
  static const currentVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '0.3.0-dev',
  );
  static const _currentVersion = currentVersion;

  /// Меньше этого — точно не установщик (настоящий ≈ 33 МБ).
  static const minInstallerBytes = 1024 * 1024;

  /// Куда скачивать установщик (в тестах — временная папка).
  static Directory Function() updateDir =
      () => Directory('${Directory.systemTemp.path}${Platform.pathSeparator}onyx_update');

  /// Откуда качать (в тестах подменяется на локальный сервер).
  static List<String> Function(String url, String? sha256) sourcesFor = downloadSources;

  /// Суммы установщиков из последней проверки: экран обновления передаёт в
  /// [downloadUpdate] только ссылку.
  static final _knownSha = <String, String>{};

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 60),
  ));

  Future<UpdateInfo?> checkForUpdate() async {
    // На Android обновления не поддерживаются (APK обновляется через магазин)
    if (Platform.isAndroid) return null;
    // Dev-сборка: не предлагаем «обновиться» на релиз с GitHub.
    if (isDevBuild) return null;

    try {
      final response = await _dio.get(_githubApi);
      if (response.statusCode == 200) {
        final data = response.data;
        final tagName = data['tag_name'] as String;
        final latestVersion = tagName.replaceAll('v', '');

        if (isNewerVersion(latestVersion, _currentVersion)) {
          final asset = pickInstallerAsset(data['assets'] as List, tagName);
          if (asset != null) {
            final sha = asset.sha256;
            if (sha != null) _knownSha[asset.url] = sha;
            return UpdateInfo(
              version: latestVersion,
              downloadUrl: asset.url,
              releaseNotes: data['body'] ?? 'No release notes available.',
              publishedAt: DateTime.parse(data['published_at']),
              sha256: sha,
            );
          }
        }
      }
    } catch (e) {
      log.w('Проверка обновлений не удалась: $e', tag: 'UPDATE');
    }
    return null;
  }

  /// Установщик среди файлов релиза: `OnyxSetup_<tag>.exe`, иначе любой
  /// `OnyxSetup_*.exe`, иначе стабильное `onyx-setup-windows.exe`. Старый
  /// payload.zip не берём.
  static InstallerAsset? pickInstallerAsset(List assets, String tag) {
    InstallerAsset? byName(bool Function(String) test) {
      for (final a in assets) {
        if (a is Map && test('${a['name']}') && a['browser_download_url'] is String) {
          return (url: a['browser_download_url'] as String, sha256: parseDigest(a['digest']));
        }
      }
      return null;
    }

    return byName((n) => n == 'OnyxSetup_$tag.exe') ??
        byName((n) => n.startsWith('OnyxSetup_') && n.endsWith('.exe')) ??
        byName((n) => n == 'onyx-setup-windows.exe');
  }

  /// Поле `digest` файла релиза в GitHub API: «sha256:<64 hex>» → hex в
  /// нижнем регистре. Другое (нет поля, другой алгоритм) — null.
  static String? parseDigest(Object? digest) {
    if (digest is! String) return null;
    final m = RegExp(r'^sha256:([0-9a-fA-F]{64})$').firstMatch(digest.trim());
    return m?.group(1)?.toLowerCase();
  }

  /// Откуда качать: сначала по ссылке релиза; если сумма известна — ещё и
  /// через зеркала github.com (как ядро в [BinaryManager]).
  static List<String> downloadSources(String url, String? sha256) => [
        url,
        if (sha256 != null && url.startsWith('https://github.com/'))
          for (final m in BinaryManager.githubMirrors) '$m$url',
      ];

  /// Скачивает установщик во временную папку и проверяет его; возвращает
  /// путь. [sha256] — сумма из [UpdateInfo]; не передали — берём из
  /// последней проверки обновлений.
  Future<String> downloadUpdate(
    String downloadUrl, {
    void Function(double progress)? onProgress,
    String? sha256,
  }) async {
    final expected = sha256 ?? _knownSha[downloadUrl];
    if (expected == null) {
      log.w('У релиза нет SHA-256 установщика — качаем только с GitHub напрямую', tag: 'UPDATE');
    }
    final dir = updateDir();
    await dir.create(recursive: true);
    final savePath = '${dir.path}${Platform.pathSeparator}OnyxSetup.exe';

    Object? lastError;
    for (final src in sourcesFor(downloadUrl, expected)) {
      try {
        await _dio.download(
          src,
          savePath,
          onReceiveProgress: (received, total) {
            if (total != -1 && onProgress != null) onProgress(received / total);
          },
        );
        await verifyInstaller(File(savePath), expected);
        log.i('Установщик скачан ($src)${expected == null ? '' : ', SHA-256 совпала'}', tag: 'UPDATE');
        return savePath;
      } catch (e) {
        lastError = e;
        log.w('Установщик с $src не подошёл: $e', tag: 'UPDATE');
        try {
          await File(savePath).delete();
        } catch (_) {}
      }
    }
    throw Exception('Не удалось скачать установщик Onyx: $lastError');
  }

  /// Скачанный файл — установщик: заголовок MZ, разумный размер и, если
  /// известна, SHA-256 из релиза.
  static Future<void> verifyInstaller(File f, String? expectedSha256) async {
    final len = await f.length();
    final head = <int>[];
    await for (final chunk in f.openRead(0, 2)) {
      head.addAll(chunk);
    }
    if (len < minInstallerBytes || head.length < 2 || head[0] != 0x4D || head[1] != 0x5A) {
      throw const FormatException('Скачанный файл не похож на установщик Onyx');
    }
    if (expectedSha256 != null) {
      final got = (await crypto.sha256.bind(f.openRead()).first).toString();
      if (got != expectedSha256.toLowerCase()) {
        throw const FormatException('Контрольная сумма установщика не совпала с релизом');
      }
    }
  }

  /// Аргументы тихого обновления (видны в тестах).
  /// [testInstallDir] — Onyx запущен из тестовой установки (`/ONYXTEST=1`):
  /// обновляем её же, в её папке. Без этого установщик взял бы папку основной
  /// установки, и проверка обновления задела бы рабочую Onyx (#104).
  static List<String> silentArgs(String logPath, {String? testInstallDir}) => [
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        '/ONYXUPDATE=1',
        if (testInstallDir != null) ...['/ONYXTEST=1', '/DIR=$testInstallDir'],
        '/LOG=$logPath',
      ];

  /// Тестовая установка: установщик с `/ONYXTEST=1` кладёт рядом с onyx.exe
  /// метку `onyxtest.flag`.
  static bool isTestInstall(String installDir) =>
      File('$installDir${Platform.pathSeparator}onyxtest.flag').existsSync();

  /// Запускает установщик тихо и отдельно от Onyx; Onyx после этого
  /// выходит сам (update_screen), установщик закроет остатки, обновит
  /// файлы и снова запустит Onyx. UAC — только если обновилось ядро.
  /// Туннель гаснет вместе с Onyx: ядро (#55) следит за его PID.
  Future<void> applyUpdate(String setupPath) async {
    if (!File(setupPath).existsSync()) {
      throw Exception('Установщик не найден: $setupPath');
    }
    final logPath = '${File(setupPath).parent.path}${Platform.pathSeparator}setup.log';
    final installDir = File(Platform.resolvedExecutable).parent.path;
    final args = silentArgs(logPath, testInstallDir: isTestInstall(installDir) ? installDir : null);
    log.i('Обновление: запускаем $setupPath ${args.join(' ')}', tag: 'UPDATE');
    await Process.start(setupPath, args, mode: ProcessStartMode.detached);
  }

  /// ИСПРАВЛЕНО: терпимо к pre-release суффиксам вида "0.2.0-beta",
  /// "0.3.0-rc1". Раньше `int.parse` на "0-beta" падал в catch и весь
  /// метод молча возвращал false — обновление никогда не предлагалось,
  /// если тег содержал суффикс.
  ///
  /// Стратегия: сначала сравниваем числовую часть (major.minor.patch).
  /// Если она равна — pre-release считается МЕНЕЕ приоритетной, чем
  /// релиз без суффикса (семверный принцип: 1.0.0-beta < 1.0.0).
  static bool isNewerVersion(String latest, String current) {
    try {
      final (latestNums, latestSuffix) = _splitVersion(latest);
      final (currentNums, currentSuffix) = _splitVersion(current);

      for (int i = 0; i < 3; i++) {
        final l = i < latestNums.length ? latestNums[i] : 0;
        final c = i < currentNums.length ? currentNums[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }

      // Числовая часть идентична — решает наличие suffix.
      // "1.0.0" (без суффикса) новее чем "1.0.0-beta".
      final latestIsPrerelease = latestSuffix.isNotEmpty;
      final currentIsPrerelease = currentSuffix.isNotEmpty;

      if (currentIsPrerelease && !latestIsPrerelease) return true;
      if (!currentIsPrerelease && latestIsPrerelease) return false;

      // Оба pre-release или оба релиз с одинаковыми числами — не новее.
      return false;
    } catch (_) {
      return false;
    }
  }

  /// "0.2.0-beta.1" → ([0, 2, 0], "beta.1")
  /// "0.2.0"        → ([0, 2, 0], "")
  static (List<int>, String) _splitVersion(String version) {
    final dashIndex = version.indexOf('-');
    final numericPart =
    dashIndex == -1 ? version : version.substring(0, dashIndex);
    final suffix = dashIndex == -1 ? '' : version.substring(dashIndex + 1);
    final nums = numericPart.split('.').map(int.parse).toList();
    return (nums, suffix);
  }
}
