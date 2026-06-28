import 'dart:io';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';

class InstallLogic {
  static Future<void> install(void Function(double, String) onProgress) async {
    final logFile = File('C:\\Users\\Public\\onyx_install_log.txt');
    void log(String msg) {
      logFile.writeAsStringSync('${DateTime.now()}: $msg\n',
          mode: FileMode.append);
    }

    try {
      log('=== Install started ===');

      final appData = Platform.environment['LOCALAPPDATA'];
      final roamingAppData = Platform.environment['APPDATA'];
      final userProfile = Platform.environment['USERPROFILE'];
      log('LOCALAPPDATA=$appData');

      if (appData == null || roamingAppData == null || userProfile == null) {
        throw Exception('Could not resolve environment variables.');
      }

      final installDir = '$appData\\Onyx';
      final serviceExePath = '$installDir\\OnyxService.exe';
      final appExePath = '$installDir\\onyx.exe';

      onProgress(0.1, 'Extracting files...');
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final payloadZip = File('$exeDir\\Onyx_v0.1.0_payload.zip');
      log('ZIP path: ${payloadZip.path}, exists: ${payloadZip.existsSync()}');

      if (!payloadZip.existsSync()) {
        throw Exception('ZIP not found at: ${payloadZip.path}');
      }

      final bytes = payloadZip.readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);
      log('Archive entries: ${archive.length}');

      for (var i = 0; i < archive.length; i++) {
        final file = archive[i];
        final filename = file.name;
        final path = '$installDir\\$filename';
        if (file.isFile) {
          final data = file.content as List<int>;
          final f = File(path);
          f.createSync(recursive: true);
          f.writeAsBytesSync(data);
        } else {
          Directory(path).createSync(recursive: true);
        }
      }
      log('Extraction done');

      onProgress(0.4, 'Verifying files...');
      final files = Directory(installDir)
          .listSync()
          .map((e) => e.path.split('\\').last)
          .join(', ');
      log('Files in installDir: $files');

      if (!File(appExePath).existsSync()) {
        throw Exception('onyx.exe not found. Files: $files');
      }
      if (!File(serviceExePath).existsSync()) {
        throw Exception('OnyxService.exe not found. Files: $files');
      }
      log('Verification OK');

      onProgress(0.5, 'Registering autostart task...');
      final taskScript = '''
\$action = New-ScheduledTaskAction -Execute "$serviceExePath"
\$trigger = New-ScheduledTaskTrigger -AtLogOn
\$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
\$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName "OnyxVpnService" -Action \$action -Trigger \$trigger -Principal \$principal -Settings \$settings -Force
''';
      final taskResult = await _runPowerShellWithResult(taskScript);
      log('Task register result: $taskResult');

      onProgress(0.7, 'Starting service...');
      final startResult = await Process.run('powershell', [
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-Command', 'Start-ScheduledTask -TaskName "OnyxVpnService"'
      ]);
      log('Task start exit: ${startResult.exitCode}, out: ${startResult.stdout}, err: ${startResult.stderr}');

      onProgress(0.8, 'Creating shortcuts...');
      final startMenuPath =
          '$roamingAppData\\Microsoft\\Windows\\Start Menu\\Programs\\Onyx.lnk';
      final desktopPath = '$userProfile\\Desktop\\Onyx.lnk';
      await _createShortcut(appExePath, startMenuPath);
      await _createShortcut(appExePath, desktopPath);
      log('Shortcuts created');

      onProgress(0.9, 'Registering uninstaller...');
      final regScript = '''
\$p = "HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Onyx"
New-Item -Path \$p -Force | Out-Null
New-ItemProperty -Path \$p -Name "DisplayName" -Value "Onyx VPN" -PropertyType String -Force | Out-Null
New-ItemProperty -Path \$p -Name "DisplayVersion" -Value "0.1.0" -PropertyType String -Force | Out-Null
New-ItemProperty -Path \$p -Name "Publisher" -Value "Z43 Studios" -PropertyType String -Force | Out-Null
''';
      await _runPowerShellWithResult(regScript);
      log('Registry done');

      onProgress(1.0, 'Done! Launching Onyx...');
      log('Launching $appExePath');
      await Future.delayed(const Duration(seconds: 1));
      await Process.start(appExePath, []);
      exit(0);
    } catch (e, stack) {
      logFile.writeAsStringSync('ERROR: $e\nSTACK: $stack\n',
          mode: FileMode.append);
      onProgress(-1.0, 'ERROR: $e');
    }
  }

  static Future<String> _runPowerShellWithResult(String script) async {
    final tempFile =
    File('${Directory.systemTemp.path}\\onyx_setup_script.ps1');
    await tempFile.writeAsString(script);
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy', 'Bypass',
      '-File', tempFile.path,
    ]);
    try { await tempFile.delete(); } catch (_) {}
    return 'exit=${result.exitCode} out=${result.stdout} err=${result.stderr}';
  }

  static Future<void> _createShortcut(
      String targetPath, String shortcutPath) async {
    final script = '''
\$WshShell = New-Object -comObject WScript.Shell
\$Shortcut = \$WshShell.CreateShortcut("$shortcutPath")
\$Shortcut.TargetPath = "$targetPath"
\$Shortcut.Save()
''';
    await _runPowerShellWithResult(script);
  }
}