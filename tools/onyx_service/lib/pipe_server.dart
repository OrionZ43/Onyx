import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'singbox_launcher.dart';

const String _pipeName = r'\\.\pipe\OnyxVpnService';
Isolate? _pipeIsolate;
SendPort? _controlPort;

void startPipeServer() async {
  final receivePort = ReceivePort();

  _pipeIsolate = await Isolate.spawn(_pipeServerIsolate, receivePort.sendPort);

  // Получаем порт для управления изолятом
  _controlPort = await receivePort.first as SendPort;
}

void stopPipeServer() {
  if (_controlPort != null) {
    _controlPort!.send('stop');
  }
}

void _pipeServerIsolate(SendPort sendPort) async {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  bool isRunning = true;

  receivePort.listen((message) {
    if (message == 'stop') {
      isRunning = false;
      receivePort.close();
    }
  });

  // Запуск сервера в цикле, пока isRunning
  await _runNamedPipeServer(() => isRunning);
}

Future<void> _runNamedPipeServer(bool Function() isRunningFunc) async {
  final pipeNamePtr = _pipeName.toNativeUtf16();

  // Create a default SECURITY_ATTRIBUTES struct.
  // In a robust implementation, this would use advapi32.dll dynamically.
  // We will leave lpSecurityDescriptor as nullptr for now and load the correct dll directly if needed
  // Let's implement dynamic calling of ConvertStringSecurityDescriptorToSecurityDescriptorW
  final advapi32 = DynamicLibrary.open('advapi32.dll');

  final convertFunc = advapi32
      .lookupFunction<
        Int32 Function(
          Pointer<Utf16>,
          Uint32,
          Pointer<Pointer<Void>>,
          Pointer<Uint32>,
        ),
        int Function(
          Pointer<Utf16>,
          int,
          Pointer<Pointer<Void>>,
          Pointer<Uint32>,
        )
      >('ConvertStringSecurityDescriptorToSecurityDescriptorW');

  final sa = calloc<SECURITY_ATTRIBUTES>();
  final ppSd = calloc<Pointer<Void>>();
  final sddl = 'D:(A;;GRGW;;;WD)(A;;GA;;;SY)(A;;GA;;;BA)'.toNativeUtf16();

  if (convertFunc(sddl, 1, ppSd, nullptr) != 0) {
    sa.ref.nLength = sizeOf<SECURITY_ATTRIBUTES>();
    sa.ref.lpSecurityDescriptor = ppSd.value;
    sa.ref.bInheritHandle = 1;
  } else {
    print('Failed to set security descriptor');
  }

  while (isRunningFunc()) {
    final hPipe = CreateNamedPipe(
      pipeNamePtr,
      PIPE_ACCESS_DUPLEX,
      PIPE_TYPE_MESSAGE | PIPE_READMODE_MESSAGE | PIPE_WAIT,
      PIPE_UNLIMITED_INSTANCES,
      512,
      512,
      0,
      sa,
    );

    if (hPipe == INVALID_HANDLE_VALUE) {
      await Future.delayed(const Duration(seconds: 1));
      continue;
    }

    final connected = ConnectNamedPipe(hPipe, nullptr) != 0
        ? true
        : (GetLastError() == ERROR_PIPE_CONNECTED);

    if (connected) {
      await _handlePipeClient(hPipe);
    }

    CloseHandle(hPipe);
  }

  free(pipeNamePtr);
  if (ppSd.value != nullptr) {
    LocalFree(ppSd.value);
  }
  free(ppSd);
  free(sa);
  free(sddl);
}

Future<void> _handlePipeClient(int hPipe) async {
  final bufferSize = 4096;
  final buffer = calloc<Uint8>(bufferSize);
  final bytesRead = calloc<DWORD>();
  final bytesWritten = calloc<DWORD>();

  try {
    while (true) {
      final success = ReadFile(hPipe, buffer, bufferSize, bytesRead, nullptr);

      if (success == 0 || bytesRead.value == 0) {
        break; // Клиент отключился или ошибка
      }

      final msgBytes = buffer.cast<Uint8>().asTypedList(bytesRead.value);
      final msgString = utf8.decode(msgBytes);

      // Разделение по newline
      final commands = msgString.split('\n').where((s) => s.trim().isNotEmpty);

      for (final cmdString in commands) {
        try {
          final jsonCmd = jsonDecode(cmdString);
          final response = await _processCommand(jsonCmd);

          final responseString = jsonEncode(response) + '\n';
          final responseBytes = utf8.encode(responseString);

          final respBuffer = calloc<Uint8>(responseBytes.length);
          respBuffer
              .cast<Uint8>()
              .asTypedList(responseBytes.length)
              .setAll(0, responseBytes);

          WriteFile(
            hPipe,
            respBuffer,
            responseBytes.length,
            bytesWritten,
            nullptr,
          );

          free(respBuffer);
        } catch (e) {
          print('Error processing command: $e');
        }
      }
    }
  } finally {
    free(buffer);
    free(bytesRead);
    free(bytesWritten);
    DisconnectNamedPipe(hPipe);
  }
}

Future<Map<String, dynamic>> _processCommand(Map<String, dynamic> cmd) async {
  final command = cmd['cmd'] as String?;

  if (command == 'start') {
    final configPath = cmd['configPath'] as String?;
    if (configPath != null) {
      final success = await SingboxLauncher.start(configPath);
      return {'status': success ? 'ok' : 'error'};
    }
    return {'status': 'error', 'reason': 'missing configPath'};
  } else if (command == 'stop') {
    SingboxLauncher.stop();
    return {'status': 'ok'};
  } else if (command == 'status') {
    final isRunning = SingboxLauncher.isRunning();
    final hasError = SingboxLauncher.hasError();
    return {
      'state': isRunning ? 'running' : (hasError ? 'error' : 'idle'),
      'pid': SingboxLauncher.getPid(),
    };
  }

  return {'status': 'error', 'reason': 'unknown command'};
}
