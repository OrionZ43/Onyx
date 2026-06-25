import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:local_notifier/local_notifier.dart';
import 'core/theme/app_theme.dart';
import 'core/log_service.dart';
import 'infrastructure/binary_manager.dart';
import 'presentation/screens/setup_screen.dart';
import 'presentation/screens/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await localNotifier.setup(appName: 'Onyx');
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1200, 800),
      minimumSize: Size(800, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  // Только на мобильных — фиксируем портрет
  if (!Platform.isWindows) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF03020A),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  log.i('Onyx стартует... Платформа: ${Platform.operatingSystem}', tag: 'MAIN');

  // Инициализируем BinaryManager (создаёт директорию)
  await BinaryManager.instance.init();
  log.i('BinaryManager инициализирован', tag: 'MAIN');

  runApp(const ProviderScope(child: OnyxApp()));
}

class OnyxApp extends StatefulWidget {
  const OnyxApp({super.key});

  @override
  State<OnyxApp> createState() => _OnyxAppState();
}

class _OnyxAppState extends State<OnyxApp> with WindowListener, TrayListener {
  bool _setupDone = false;
  bool _isVisible = true;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      windowManager.addListener(this);
      trayManager.addListener(this);
      _initTray();
    }
    // Если бинарники уже есть — пропускаем SetupScreen
    _setupDone = !Platform.isWindows || BinaryManager.instance.isReady;
    log.i('Бинарники готовы: $_setupDone', tag: 'MAIN');
  }

  Future<void> _initTray() async {
    await trayManager.setIcon('windows/runner/resources/app_icon.ico');
    Menu menu = Menu(
      items: [
        MenuItem(key: 'show_window', label: 'Развернуть'),
        MenuItem.separator(),
        MenuItem(key: 'exit_app', label: 'Выход'),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  @override
  void onWindowMinimize() async {
    setState(() => _isVisible = false);
    await windowManager.hide();
    LocalNotification notification = LocalNotification(
      title: 'Onyx VPN',
      body: 'Приложение свернуто в трей и продолжает работу.',
    );
    await notification.show();
  }

  @override
  void onWindowRestore() {
    setState(() => _isVisible = true);
  }

  @override
  void onTrayIconMouseDown() async {
    setState(() => _isVisible = true);
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (menuItem.key == 'show_window') {
      setState(() => _isVisible = true);
      await windowManager.show();
      await windowManager.restore();
      await windowManager.focus();
    } else if (menuItem.key == 'exit_app') {
      await windowManager.destroy();
      exit(0);
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Onyx',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      // МАГИЯ ОПТИМИЗАЦИИ ЗДЕСЬ: TickerMode ставит на паузу все AnimationController'ы
      builder: (context, child) =>
          TickerMode(enabled: _isVisible, child: child!),
      home: _setupDone
          ? const OnboardingScreen()
          : SetupScreen(onComplete: () => setState(() => _setupDone = true)),
    );
  }
}
