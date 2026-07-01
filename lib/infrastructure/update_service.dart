import 'dart:io';
import 'package:dio/dio.dart';

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String releaseNotes;
  final DateTime publishedAt;

  UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.publishedAt,
  });
}

class UpdateService {
  static const _githubApi =
      'https://api.github.com/repos/OrionZ43/Onyx/releases/latest';

  // Версия вшивается автоматически из git-тега при сборке через --dart-define.
  // Локально (flutter run) = '0.0.0' чтобы всегда показывало обновление для отладки.
  static const _currentVersion = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: '0.0.0',
  );

  final Dio _dio = Dio();

  Future<UpdateInfo?> checkForUpdate() async {
    // На Android обновления не поддерживаются (APK обновляется через магазин)
    if (Platform.isAndroid) return null;

    try {
      final response = await _dio.get(_githubApi);
      if (response.statusCode == 200) {
        final data = response.data;
        final tagName = data['tag_name'] as String;
        final latestVersion = tagName.replaceAll('v', '');

        if (_isNewerVersion(latestVersion, _currentVersion)) {
          final assets = data['assets'] as List;
          String? downloadUrl;

          for (var asset in assets) {
            if (asset['name'].toString().startsWith('Onyx_') &&
                asset['name'].toString().endsWith('_payload.zip')) {
              downloadUrl = asset['browser_download_url'];
              break;
            }
          }

          if (downloadUrl != null) {
            return UpdateInfo(
              version: latestVersion,
              downloadUrl: downloadUrl,
              releaseNotes: data['body'] ?? 'No release notes available.',
              publishedAt: DateTime.parse(data['published_at']),
            );
          }
        }
      }
    } catch (e) {
      print('Update check failed: $e');
    }
    return null;
  }

  Future<String> downloadUpdate(
      String downloadUrl, {
        void Function(double progress)? onProgress,
      }) async {
    final tempDir = Directory.systemTemp.path;
    final savePath = '$tempDir\\onyx_update\\Onyx_Update_Payload.zip';

    final dir = Directory('$tempDir\\onyx_update');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    await _dio.download(
      downloadUrl,
      savePath,
      onReceiveProgress: (received, total) {
        if (total != -1 && onProgress != null) {
          onProgress(received / total);
        }
      },
    );

    return savePath;
  }

  Future<void> applyUpdate(String zipPath) async {
    final appData = Platform.environment['LOCALAPPDATA'];
    if (appData == null) throw Exception('LOCALAPPDATA not found');

    final installDir = '$appData\\Onyx';
    final updaterExe = '$installDir\\OnyxUpdater.exe';
    final launchExe = '$installDir\\onyx.exe';

    if (!File(updaterExe).existsSync()) {
      throw Exception('Updater executable not found at $updaterExe');
    }

    await Process.start(
      updaterExe,
      [zipPath, installDir, launchExe],
      mode: ProcessStartMode.detached,
    );
  }

  /// ИСПРАВЛЕНО: терпимо к pre-release суффиксам вида "0.2.0-beta",
  /// "0.3.0-rc1". Раньше `int.parse` на "0-beta" падал в catch и весь
  /// метод молча возвращал false — обновление никогда не предлагалось,
  /// если тег содержал суффикс.
  ///
  /// Стратегия: сначала сравниваем числовую часть (major.minor.patch).
  /// Если она равна — pre-release считается МЕНЕЕ приоритетной, чем
  /// релиз без суффикса (семверный принцип: 1.0.0-beta < 1.0.0).
  bool _isNewerVersion(String latest, String current) {
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
  (List<int>, String) _splitVersion(String version) {
    final dashIndex = version.indexOf('-');
    final numericPart =
    dashIndex == -1 ? version : version.substring(0, dashIndex);
    final suffix = dashIndex == -1 ? '' : version.substring(dashIndex + 1);
    final nums = numericPart.split('.').map(int.parse).toList();
    return (nums, suffix);
  }
}