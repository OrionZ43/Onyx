import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'pipe_server.dart';
import 'singbox_launcher.dart';

/// Глобальная переменная для статуса сервиса
final _status = calloc<SERVICE_STATUS>();
int _statusHandle = 0;

void startServiceHost(List<String> args) {
  final serviceName = 'OnyxService'.toNativeUtf16();

  final serviceTable = calloc<SERVICE_TABLE_ENTRY>(2);
  serviceTable[0].lpServiceName = serviceName;
  serviceTable[0].lpServiceProc = Pointer.fromFunction<LPSERVICE_MAIN_FUNCTION>(
    _serviceMain,
  );

  serviceTable[1].lpServiceName = nullptr;
  serviceTable[1].lpServiceProc = nullptr;

  if (StartServiceCtrlDispatcher(serviceTable) == 0) {
    // Не удалось запустить диспетчер сервисов (возможно, запущено не как сервис)
    print('StartServiceCtrlDispatcher failed or not running as service.');
    // Можно запустить напрямую для отладки
    // _runDirectly();
  }

  free(serviceName);
  free(serviceTable);
}

void _serviceMain(int argc, Pointer<Pointer<Utf16>> argv) {
  final serviceName = 'OnyxService'.toNativeUtf16();

  _statusHandle = RegisterServiceCtrlHandler(
    serviceName,
    Pointer.fromFunction<LPHANDLER_FUNCTION>(_serviceCtrlHandler),
  );

  free(serviceName);

  if (_statusHandle == 0) return;

  _status.ref.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
  _status.ref.dwServiceSpecificExitCode = 0;

  _reportStatus(SERVICE_START_PENDING, NO_ERROR, 3000);

  _serviceInit(argc, argv);
}

void _serviceInit(int argc, Pointer<Pointer<Utf16>> argv) {
  _reportStatus(SERVICE_RUNNING, NO_ERROR, 0);

  // Инициализация компонентов сервиса
  try {
    startPipeServer();
  } catch (e) {
    _reportStatus(SERVICE_STOPPED, ERROR_SERVICE_SPECIFIC_ERROR, 0);
    return;
  }

  // Сервис теперь работает и слушает Pipe (Pipe сервер запущен в изоляте или асинхронно,
  // поэтому основной поток сервиса свободен для SCM).
}

void _serviceCtrlHandler(int ctrlCode) {
  switch (ctrlCode) {
    case SERVICE_CONTROL_STOP:
      _reportStatus(SERVICE_STOP_PENDING, NO_ERROR, 0);

      // Останавливаем Pipe Server и дочерний процесс
      stopPipeServer();
      SingboxLauncher.stop();

      _reportStatus(SERVICE_STOPPED, NO_ERROR, 0);
      break;

    default:
      break;
  }
}

void _reportStatus(int currentState, int win32ExitCode, int waitHint) {
  // Для простоты используем статический checkpoint
  _status.ref.dwCurrentState = currentState;
  _status.ref.dwWin32ExitCode = win32ExitCode;
  _status.ref.dwWaitHint = waitHint;

  if (currentState == SERVICE_START_PENDING) {
    _status.ref.dwControlsAccepted = 0;
  } else {
    _status.ref.dwControlsAccepted = 0x00000001; // SERVICE_ACCEPT_STOP
  }

  if (currentState == SERVICE_RUNNING || currentState == SERVICE_STOPPED) {
    _status.ref.dwCheckPoint = 0;
  } else {
    _status.ref.dwCheckPoint = 1;
  }

  SetServiceStatus(_statusHandle, _status);
}
