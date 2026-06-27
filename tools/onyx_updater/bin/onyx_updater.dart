import 'dart:io';
import 'package:archive/archive.dart';

void main(List<String> args) async {
  if (args.length < 3) {
    print('Usage: OnyxUpdater.exe <zipPath> <installDir> <launchExe>');
    exit(1);
  }

  final zipPath = args[0];
  final installDir = args[1];
  final launchExe = args[2];

  print('Waiting for Onyx.exe to exit...');
  // Wait up to 10 seconds for the app to exit
  for (int i = 0; i < 10; i++) {
    final result = await Process.run('tasklist', [
      '/FI',
      'IMAGENAME eq Onyx.exe',
    ]);
    if (!result.stdout.toString().contains('Onyx.exe')) {
      break;
    }
    await Future.delayed(const Duration(seconds: 1));
  }

  print('Extracting $zipPath to $installDir...');
  try {
    final bytes = File(zipPath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);

    // Create a backup directory to restore if something goes wrong
    final backupDir = Directory('$installDir\\.bak');
    if (!backupDir.existsSync()) {
      backupDir.createSync(recursive: true);
    }

    bool extractionFailed = false;

    for (var i = 0; i < archive.length; i++) {
      final file = archive[i];
      final filename = file.name;
      final path = '$installDir\\$filename';

      if (file.isFile) {
        final data = file.content as List<int>;
        final f = File(path);

        // Backup existing file if it exists
        if (f.existsSync()) {
          try {
            final backupPath = '${backupDir.path}\\$filename';
            File(backupPath).parent.createSync(recursive: true);
            f.copySync(backupPath);
          } catch (_) {}
        }

        // Retry logic for writing the file
        bool wrote = false;
        for (int attempt = 1; attempt <= 5; attempt++) {
          try {
            f.createSync(recursive: true);
            f.writeAsBytesSync(data);
            wrote = true;
            break; // Success
          } catch (e) {
            print('Write attempt $attempt failed for $filename: $e');
            if (attempt < 5) {
              await Future.delayed(const Duration(milliseconds: 500));
            }
          }
        }

        if (!wrote) {
          print('Failed to write $filename after 5 attempts.');
          extractionFailed = true;
          break; // Stop extraction, fallback
        }
      } else {
        Directory(path).createSync(recursive: true);
      }
    }

    if (extractionFailed) {
      print('Rolling back changes...');
      _rollback(backupDir.path, installDir);
    } else {
      // Cleanup backup
      try {
        backupDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  } catch (e) {
    print('Extraction failed: $e');
    // Try to launch anyway in case it partially succeeded
  }

  print('Launching $launchExe...');
  try {
    Process.start(launchExe, []);
  } catch (e) {
    print('Failed to launch: $e');
  }

  exit(0);
}

void _rollback(String backupDirPath, String installDir) {
  try {
    final backupDir = Directory(backupDirPath);
    if (!backupDir.existsSync()) return;

    for (final entity in backupDir.listSync(recursive: true)) {
      if (entity is File) {
        final relativePath = entity.path.substring(backupDirPath.length + 1);
        final restorePath = '$installDir\\$relativePath';
        try {
          entity.copySync(restorePath);
        } catch (e) {
          print('Rollback failed for $restorePath: $e');
        }
      }
    }
  } catch (e) {
    print('Rollback encountered an error: $e');
  }
}
