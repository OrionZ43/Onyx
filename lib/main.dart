import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_retriever/screen_retriever.dart' as sr;
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
import 'presentation/tray/tray_flyout.dart';
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
      // Крестик — выход через _exit(): сначала гасим sing-box (см. onWindowClose).
      await windowManager.setPreventClose(true);
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

  // ── Мини-панель у значка трея (#46) ─────────────────────────────────────
  // Панель — то же окно в «режиме панели»: маленькое, поверх всех окон, без
  // кнопки на панели задач, у значка трея. Провайдеры и логика — общие.
  static const Size _normalMin = Size(800, 600);
  static const Size _normalDefault = Size(1200, 800);
  bool _flyout = false;
  int _flyoutShowId = 0;
  Rect? _normalBounds;
  bool _normalMaximized = false;
  // Панель открыта поверх показанного полного окна — Esc возвращает к нему.
  bool _flyoutFromWindow = false;
  bool _switching = false;
  DateTime _lastFlyoutHide = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastTrayDown = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      windowManager.addListener(this);
      trayManager.addListener(this);
      _tray = OnyxTray(ref: ref);
      _tray!.sync();
    }
    // Если бинарники уже есть — пропускаем SetupScreen
    _setupDone = BinaryManager.instance.isReady;
    log.i('Бинарники готовы: $_setupDone', tag: 'MAIN');
  }

  /// Рабочие области мониторов (без панели задач) в логических пикселях:
  /// основной монитор и все. У пользователя может быть несколько мониторов,
  /// в том числе левее основного (отрицательные координаты).
  Future<(Rect, List<Rect>)> _workAreas() async {
    Rect area(sr.Display d) => (d.visiblePosition ?? Offset.zero) & (d.visibleSize ?? d.size);
    try {
      final primary = area(await sr.screenRetriever.getPrimaryDisplay());
      final all = [for (final d in await sr.screenRetriever.getAllDisplays()) area(d)];
      return (primary, all.isEmpty ? [primary] : all);
    } catch (e) {
      log.w('Мониторы не определились ($e)', tag: 'MAIN');
      final ds = WidgetsBinding.instance.platformDispatcher.displays;
      final size = ds.isEmpty ? const Size(1280, 720) : ds.first.size / ds.first.devicePixelRatio;
      final r = Rect.fromLTWH(0, 0, size.width, size.height - 48);
      return (r, [r]);
    }
  }

  /// Где показать панель: у значка трея (Shell_NotifyIconGetRect), внутри
  /// рабочей области его монитора — как системные всплывающие окна, в 12 px от
  /// панели задач. Если значок не нашёлся — правый нижний угол основного
  /// монитора.
  Future<Rect> _flyoutRect() async {
    const s = TrayFlyout.size, m = 12.0;
    final (primary, areas) = await _workAreas();
    Rect? icon;
    try {
      icon = await trayManager.getBounds();
    } catch (_) {}
    if (icon == null || icon.width <= 0 || icon.width > 96 || icon.height <= 0 || icon.height > 96) {
      return Rect.fromLTWH(primary.right - s.width - m, primary.bottom - s.height - m, s.width, s.height);
    }
    final c = icon.center;
    double dist(Rect r) {
      final dx = c.dx < r.left ? r.left - c.dx : (c.dx > r.right ? c.dx - r.right : 0.0);
      final dy = c.dy < r.top ? r.top - c.dy : (c.dy > r.bottom ? c.dy - r.bottom : 0.0);
      return dx * dx + dy * dy;
    }

    // Монитор значка — с ближайшей к нему рабочей областью.
    final a = areas.reduce((p, q) => dist(p) <= dist(q) ? p : q);
    double cx(double v) => v.clamp(a.left + m, math.max(a.left + m, a.right - s.width - m)).toDouble();
    double cy(double v) => v.clamp(a.top + m, math.max(a.top + m, a.bottom - s.height - m)).toDouble();
    final double x, y;
    if (c.dy >= a.bottom || c.dy <= a.top) {
      // Панель задач снизу (обычно) или сверху.
      x = cx(c.dx - s.width / 2);
      y = c.dy >= a.bottom ? a.bottom - s.height - m : a.top + m;
    } else if (c.dx >= a.right || c.dx <= a.left) {
      // Панель задач справа или слева.
      x = c.dx >= a.right ? a.right - s.width - m : a.left + m;
      y = cy(c.dy - s.height / 2);
    } else {
      // Значок в окошке скрытых значков — над ним.
      x = cx(c.dx - s.width / 2);
      y = cy(icon.top - s.height - m);
    }
    return Rect.fromLTWH(x, y, s.width, s.height);
  }

  /// window_manager сворачивает и разворачивает окно сообщением, то есть
  /// асинхронно, — дождаться, пока состояние сменится.
  Future<void> _settle(Future<bool> Function() done) async {
    for (var i = 0; i < 25 && !await done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  /// Запомнить место полного окна, чтобы вернуть его туда же.
  Future<void> _rememberNormal() async {
    if (_flyout || !await windowManager.isVisible() || await windowManager.isMinimized()) return;
    _normalMaximized = await windowManager.isMaximized();
    if (!_normalMaximized) _normalBounds = await windowManager.getBounds();
  }

  Future<void> _showFlyout() async {
    if (_switching) return;
    _switching = true;
    try {
      final minimized = await windowManager.isMinimized();
      if (!_flyout) _flyoutFromWindow = !minimized && await windowManager.isVisible();
      // Из свёрнутого и развёрнутого состояний панель не построить: Windows
      // вернёт окну прежний размер. Сначала — обычное состояние.
      if (minimized) {
        await windowManager.restore();
        await _settle(() async => !await windowManager.isMinimized());
      }
      if (!_flyout) {
        _normalMaximized = await windowManager.isMaximized();
        if (_normalMaximized) {
          await windowManager.unmaximize();
          await _settle(() async => !await windowManager.isMaximized());
        }
        if (await windowManager.isVisible()) _normalBounds = await windowManager.getBounds();
      }
      final rect = await _flyoutRect();
      setState(() {
        _flyout = true;
        _flyoutShowId++;
        _isVisible = true;
      });
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSkipTaskbar(true);
      await windowManager.setResizable(false);
      await windowManager.setMinimumSize(TrayFlyout.size);
      await windowManager.setBounds(rect);
      await windowManager.show();
      await windowManager.focus();
      // Без фокуса панель не спрячется по клику мимо — вторая попытка.
      if (!await windowManager.isFocused()) {
        await Future<void>.delayed(const Duration(milliseconds: 60));
        await windowManager.focus();
      }
      await _tray?.sync();
    } finally {
      _switching = false;
    }
  }

  Future<void> _hideFlyout() async {
    if (!_flyout || !_isVisible) return;
    _lastFlyoutHide = DateTime.now();
    _flyoutFromWindow = false;
    setState(() => _isVisible = false);
    await windowManager.hide();
  }

  /// Esc в панели: открыли поверх полного окна — к нему и вернуться.
  void _onFlyoutEsc() => _flyoutFromWindow ? _showWindow() : _hideFlyout();

  /// Полное окно Onyx (из панели, двойной клик по значку и т. п.).
  Future<void> _showWindow() async {
    if (_switching) return;
    _switching = true;
    try {
      if (_flyout) {
        setState(() => _flyout = false);
        _flyoutFromWindow = false;
        await windowManager.setAlwaysOnTop(false);
        await windowManager.setSkipTaskbar(false);
        await windowManager.setResizable(true);
        await windowManager.setMinimumSize(_normalMin);
        final (primary, _) = await _workAreas();
        await windowManager.setBounds(_normalBounds ??
            Rect.fromCenter(
              center: primary.center,
              width: math.min(_normalDefault.width, primary.width),
              height: math.min(_normalDefault.height, primary.height),
            ));
      }
      setState(() => _isVisible = true);
      await windowManager.show();
      await windowManager.restore();
      if (_normalMaximized) await windowManager.maximize();
      await windowManager.focus();
    } finally {
      _switching = false;
    }
  }

  /// «Свернуть»: Onyx уходит в трей и продолжает работу.
  Future<void> _hideToTray() async {
    await _rememberNormal();
    setState(() => _isVisible = false);
    await windowManager.hide();
    await LocalNotification(
      title: 'Onyx VPN',
      body: 'Onyx свернут в трей и продолжает работу.',
    ).show();
  }

  Future<void> _exit() async {
    // ВАЖНО: перед выходом гасим sing-box, иначе процесс с поднятым
    // WinTUN-интерфейсом остаётся жить после закрытия приложения —
    // маршруты не восстанавливаются, и весь интернет у пользователя
    // «пропадает» до ручного убийства sing-box.exe в диспетчере задач.
    try {
      await SingboxBridgeWindows.instance.stop().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Даже если остановка не удалась — всё равно выходим.
    }
    await trayManager.destroy();
    await windowManager.destroy();
    exit(0);
  }

  /// Панель прячется, как системные всплывающие окна, при потере фокуса.
  @override
  void onWindowBlur() {
    if (_flyout && !_switching) _hideFlyout();
  }

  /// Крестик и Alt+F4. Из панели — только спрятать её.
  @override
  void onWindowClose() => _flyout ? _hideFlyout() : _exit();

  @override
  void onWindowMinimize() {
    if (_switching) return;
    // Системное сворачивание (Win+M, клик по кнопке на панели задач).
    _flyout ? _hideFlyout() : _hideToTray();
  }

  @override
  void onWindowMoved() => _rememberNormal();

  @override
  void onWindowResized() => _rememberNormal();

  @override
  void onWindowRestore() {
    setState(() => _isVisible = true);
  }

  /// Левый клик по значку — мини-панель (повторный клик — спрятать),
  /// двойной клик — полное окно.
  @override
  void onTrayIconMouseDown() async {
    final now = DateTime.now();
    if (now.difference(_lastTrayDown) < const Duration(milliseconds: 400)) {
      _lastTrayDown = DateTime.fromMillisecondsSinceEpoch(0);
      await _showWindow();
      return;
    }
    _lastTrayDown = now;
    await _toggleFlyout(now);
  }

  /// Правый клик — тоже мини-панель (вместо системного меню).
  @override
  void onTrayIconRightMouseDown() async => _toggleFlyout(DateTime.now());

  Future<void> _toggleFlyout(DateTime now) async {
    if (_flyout && _isVisible) {
      await _hideFlyout();
      return;
    }
    // Клик по значку сначала снимает фокус с панели (она прячется по blur) —
    // не открываем её тут же снова.
    if (now.difference(_lastFlyoutHide) < const Duration(milliseconds: 300)) return;
    await _showFlyout();
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
      builder: (context, child) {
        if (!Platform.isWindows) return TickerMode(enabled: _isVisible, child: child!);
        final shell = Column(children: [
          WindowTitleBar(onMinimize: _hideToTray),
          Expanded(child: child!),
        ]);
        if (!_flyout) return TickerMode(enabled: _isVisible, child: shell);
        // Режим панели: обычный интерфейс живёт скрытым в своих полных
        // размерах (навигация не теряется), сверху — мини-панель.
        final full = _normalBounds?.size ?? _normalDefault;
        return TickerMode(
          enabled: _isVisible,
          child: Stack(children: [
            Offstage(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: full.width, maxWidth: full.width,
                minHeight: full.height, maxHeight: full.height,
                child: TickerMode(enabled: false, child: shell),
              ),
            ),
            // Своя Overlay — для подсказок и тостов панели (она вне Navigator).
            Overlay(
              key: ValueKey(_flyoutShowId),
              initialEntries: [
                OverlayEntry(
                  builder: (_) => Scaffold(
                    backgroundColor: Colors.transparent,
                    body: TrayFlyout(
                      showId: _flyoutShowId,
                      onOpenApp: _showWindow,
                      onExit: _exit,
                      onDismiss: _onFlyoutEsc,
                    ),
                  ),
                ),
              ],
            ),
          ]),
        );
      },
      home: _setupDone
          ? const OnboardingScreen()
          : SetupScreen(onComplete: () => setState(() => _setupDone = true)),
    );
  }
}