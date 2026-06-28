import 'dart:io';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';

class InstallLogic {
  static Future<void> install(void Function(double, String) onProgress) async {
    try {
      final appData = Platform.environment['LOCALAPPDATA'];
      final roamingAppData = Platform.environment['APPDATA'];
      final userProfile = Platform.environment['USERPROFILE'];

      if (appData == null || roamingAppData == null || userProfile == null) {
        throw Exception('Could not resolve environment variables.');
      }

      final installDir = '$appData\\Onyx';
      final serviceExePath = '$installDir\\OnyxService.exe';
      final appExePath = '$installDir\\Onyx.exe';

      // Step 2: Extract ZIP
      onProgress(0.1, 'Extracting files...');
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final payloadZip = File('$exeDir\\Onyx_v0.1.0_payload.zip');

      if (!payloadZip.existsSync()) {
        throw Exception('Payload ZIP not found at ${payloadZip.path}');
      }

      final bytes = payloadZip.readAsBytesSync();
      final archive = ZipDecoder().decodeBytes(bytes);

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

      // Step 2.5: Verify Extracted files
      onProgress(0.4, 'Verifying files...');
      if (!File(appExePath).existsSync()) {
        throw Exception('Extraction failed: Onyx.exe not found at $appExePath');
      }
      if (!File(serviceExePath).existsSync()) {
        throw Exception(
          'Extraction failed: OnyxService.exe not found at $serviceExePath',
        );
      }

      // Step 3: Register Service
      onProgress(0.5, 'Registering service...');
      await _runCommand('sc', [
        'stop',
        'OnyxService',
      ]); // Ignore errors if it doesn't exist
      await Future.delayed(const Duration(seconds: 1));
      await _runCommand('sc', ['delete', 'OnyxService']);
      await Future.delayed(const Duration(seconds: 1));

      final scCreate = await Process.run('sc', [
        'create',
        'OnyxService',
        'binPath=',
        serviceExePath,
        'start=',
        'auto',
        'displayname=',
        'Onyx VPN Service',
      ]);
      if (scCreate.exitCode != 0 &&
          !scCreate.stdout.toString().contains('1073')) {
        // 1073 is "service already exists"
        throw Exception('Failed to create service: ${scCreate.stderr}');
      }

      // Step 4: Start Service
      onProgress(0.7, 'Starting service...');
      final scStart = await Process.run('sc', ['start', 'OnyxService']);
      if (scStart.exitCode != 0 &&
          !scStart.stdout.toString().contains('1056')) {
        // 1056 is "service is already running"
        print('Warning: Service start error: ${scStart.stderr}');
      }

      // Step 4.5: Wait for Named Pipe to be ready
      onProgress(0.75, 'Waiting for service to initialize...');
      bool pipeReady = false;
      for (int i = 0; i < 20; i++) {
        try {
          final testFile = File(r'\\.\pipe\OnyxVpnService');
          if (testFile.existsSync()) {
            pipeReady = true;
            break;
          }
        } catch (_) {}
        await Future.delayed(const Duration(milliseconds: 500));
      }
      if (!pipeReady) {
        throw Exception(
          'Service started but Named Pipe did not initialize within 10 seconds.',
        );
      }

      // Step 5 & 6: Shortcuts
      onProgress(0.8, 'Creating shortcuts...');
      final startMenuPath =
          '$roamingAppData\\Microsoft\\Windows\\Start Menu\\Programs\\Onyx.lnk';
      final desktopPath = '$userProfile\\Desktop\\Onyx.lnk';

      await _createShortcut(appExePath, startMenuPath);
      await _createShortcut(appExePath, desktopPath);

      // Step 7: Registry Uninstaller (Optional, simplify for now by ignoring or adding via reg)
      onProgress(0.9, 'Registering uninstaller...');
      final regScript = '''
        \$registryPath = "HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Onyx"
        New-Item -Path \$registryPath -Force | Out-Null
        New-ItemProperty -Path \$registryPath -Name "DisplayName" -Value "Onyx VPN" -PropertyType String -Force | Out-Null
        New-ItemProperty -Path \$registryPath -Name "DisplayVersion" -Value "0.1.0" -PropertyType String -Force | Out-Null
        New-ItemProperty -Path \$registryPath -Name "Publisher" -Value "Onyx" -PropertyType String -Force | Out-Null
      ''';
      await _runPowerShell(regScript);

      // Step 8: Launch
      onProgress(1.0, 'Installation complete! Launching...');
      await Future.delayed(const Duration(seconds: 1));

      Process.start(appExePath, []);
      exit(0);
    } catch (e) {
      onProgress(-1.0, 'Error: $e');
    }
  }

  static Future<void> _runCommand(String exe, List<String> args) async {
    try {
      await Process.run(exe, args);
    } catch (_) {}
  }

  static Future<void> _createShortcut(
    String targetPath,
    String shortcutPath,
  ) async {
    final script =
        '''
      \$WshShell = New-Object -comObject WScript.Shell
      \$Shortcut = \$WshShell.CreateShortcut("$shortcutPath")
      \$Shortcut.TargetPath = "$targetPath"
      \$Shortcut.Save()
    ''';
    await _runPowerShell(script);
  }

  static Future<void> _runPowerShell(String script) async {
    final tempFile = File(
      '\${Directory.systemTemp.path}\\onyx_setup_script.ps1',
    );
    await tempFile.writeAsString(script);
    await Process.run('powershell', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      tempFile.path,
    ]);
    try {
      await tempFile.delete();
    } catch (_) {}
  }
}
