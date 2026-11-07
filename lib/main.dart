import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_kind.dart';
import 'presentation/providers/theme_provider.dart';
import 'presentation/widgets/window_title_bar.dart';
import 'core/log_service.dart';
import 'infrastructure/binary_manager.dart';
import 'infrastructure/singbox_bridge_windows.dart';
import 'presentation/providers/groups_provider.dart';
import 'presentation/providers/node_provider.dart';
import 'presentation/providers/settings_provider.dart';
import 'presentation/providers/subscription_provider.dart';
import 'presentation/providers/vpn_provider.dart';
import 'presentation/providers/window_prefs_provider.dart';
import 'presentation/screens/brand_splash.dart';
import 'presentation/screens/setup_screen.dart';
import 'presentation/tray/onyx_tray.dart';
import 'presentation/screens/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  // «Запускать свёрнутым»: окно не показываем, Onyx живёт в трее.
  final startMinimized = prefs.getBool(StartMinimizedNotifier.key) ?? false;

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await localNotifier.setup(appName: 'Onyx');
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1200, 800),
      minimumSize: Size(800, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      // Свой тайтлбар в стиле темы (WindowTitleBar), системный скрыт.
      titleBarStyle: TitleBarStyle.hidden,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (startMinimized) return;
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
      systemNavigationBarColor: Color(0xFF050506),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  log.i('Onyx стартует... Платформа: ${Platform.operatingSystem}', tag: 'MAIN');

  // Инициализируем BinaryManager (создаёт директорию)
  // BinaryManager инициализируется под сплэшем (BrandSplash), а не до первого кадра.
  final init = BinaryManager.instance.init().then((_) => log.i('BinaryManager инициализирован', tag: 'MAIN'));

  // Тему читаем до первого кадра, чтобы не мигала тема по умолчанию.
  final themeKind = AppThemeKind.byName(prefs.getString(ThemeKindNotifier.key));

  runApp(ProviderScope(
    overrides: [
      themeKindProvider.overrideWith((ref) => ThemeKindNotifier(themeKind)),
      startMinimizedProvider.overrideWith((ref) => StartMinimizedNotifier(startMinimized)),
    ],
    child: OnyxBoot(init: init, kind: themeKind, app: const OnyxApp()),
  ));
}

class OnyxApp extends ConsumerStatefulWidget {
  const OnyxApp({super.key});

  @override
  ConsumerState<OnyxApp> createState() => _OnyxAppState();
}

class _OnyxAppState extends ConsumerState<OnyxApp> with WindowListener, TrayListener {
  bool _setupDone = false;
  late bool _isVisible = !ref.read(startMinimizedProvider);
  OnyxTray? _tray;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      windowManager.addListener(this);
      trayManager.addListener(this);
      _tray = OnyxTray(ref: ref, onShow: _showWindow, onExit: _exit);
      _tray!.sync();
    }
    // Если бинарники уже есть — пропускаем SetupScreen
    _setupDone = BinaryManager.instance.isReady;
    log.i('Бинарники готовы: $_setupDone', tag: 'MAIN');
  }

  Future<void> _showWindow() async {
    setState(() => _isVisible = true);
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
  }

  Future<void> _exit() async {
    // ВАЖНО: перед выходом гасим sing-box, иначе процесс с поднятым
    // WinTUN-интерфейсом остаётся жить после закрытия приложения —
    // маршруты не восстанавливаются, и весь интернет у пользователя
    // «пропадает» до ручного убийства sing-box.exe в диспетчере задач.
    try {
      await SingboxBridgeWindows.instance.stop();
    } catch (_) {
      // Даже если остановка не удалась — всё равно выходим.
    }
    await trayManager.destroy();
    await windowManager.destroy();
    exit(0);
  }

  @override
  void onWindowMinimize() async {
    setState(() => _isVisible = false);
    await windowManager.hide();
    LocalNotification notification = LocalNotification(
      title: 'Onyx VPN',
      body: 'Onyx свернут в трей и продолжает работу.',
    );
    await notification.show();
  }

  @override
  void onWindowRestore() {
    setState(() => _isVisible = true);
  }

  /// Левый клик по значку — показать или спрятать окно.
  @override
  void onTrayIconMouseDown() async {
    if (_isVisible && await windowManager.isVisible() && !await windowManager.isMinimized()) {
      setState(() => _isVisible = false);
      await windowManager.hide();
    } else {
      await _showWindow();
    }
  }

  /// Правый клик — меню.
  @override
  void onTrayIconRightMouseDown() async {
    await _tray?.sync();
    await trayManager.popUpContextMenu();
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
    if (_tray != null) {
      // Трей следует за состоянием VPN, серверами и настройками.
      void sync(_, __) => _tray!.sync();
      ref.listen(vpnControllerProvider, sync);
      ref.listen(subscriptionProvider.select((s) => s.nodes), sync);
      ref.listen(settingsProvider, sync);
      ref.listen(nodeSelectionProvider, sync);
      ref.listen(autoGroupProvider, sync);
      ref.listen(groupsProvider, sync);
    }
    final kind = ref.watch(themeKindProvider);
    // DynamicColorBuilder отдаёт схему обоев на Android 12+; используется только
    // темой Material, остальные темы её игнорируют.
    return DynamicColorBuilder(
      builder: (_, dynamicDark) => _app(
        AppTheme.build(kind, dynamicDark: dynamicDark?.harmonized()),
      ),
    );
  }

  Widget _app(ThemeData theme) {
    return MaterialApp(
      title: 'Onyx',
      debugShowCheckedModeBanner: false,
      theme: theme,
      themeMode: ThemeMode.dark,
      // МАГИЯ ОПТИМИЗАЦИИ ЗДЕСЬ: TickerMode ставит на паузу все AnimationController'ы
      builder: (context, child) => TickerMode(
        enabled: _isVisible,
        child: Platform.isWindows
            ? Column(children: [
                const WindowTitleBar(),
                Expanded(child: child!),
              ])
            : child!,
      ),
      home: _setupDone
          ? const OnboardingScreen()
          : SetupScreen(onComplete: () => setState(() => _setupDone = true)),
    );
  }
}