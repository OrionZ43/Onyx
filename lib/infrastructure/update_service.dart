import 'dart:convert';
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
  static const _currentVersion = '0.1.0';

  final Dio _dio = Dio();

  Future<UpdateInfo?> checkForUpdate() async {
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
    final launchExe = '$installDir\\Onyx.exe';

    if (!File(updaterExe).existsSync()) {
      throw Exception('Updater executable not found at $updaterExe');
    }

    // Launch updater as a detached child process
    await Process.start(
      updaterExe,
      [zipPath, installDir, launchExe],
      mode: ProcessStartMode.detached,
    );
  }

  bool _isNewerVersion(String latest, String current) {
    try {
      final latestParts = latest.split('.').map(int.parse).toList();
      final currentParts = current.split('.').map(int.parse).toList();

      for (int i = 0; i < 3; i++) {
        final l = i < latestParts.length ? latestParts[i] : 0;
        final c = i < currentParts.length ? currentParts[i] : 0;

        if (l > c) return true;
        if (l < c) return false;
      }
    } catch (_) {}
    return false;
  }
}
