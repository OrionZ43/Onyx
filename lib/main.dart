import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/log_service.dart';
import 'infrastructure/binary_manager.dart';
import 'presentation/screens/setup_screen.dart';
import 'presentation/screens/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

class _OnyxAppState extends State<OnyxApp> {
  bool _setupDone = false;

  @override
  void initState() {
    super.initState();
    // Если бинарники уже есть — пропускаем SetupScreen
    _setupDone = !Platform.isWindows || BinaryManager.instance.isReady;
    log.i('Бинарники готовы: $_setupDone', tag: 'MAIN');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Onyx',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: _setupDone
          ? const OnboardingScreen()
          : SetupScreen(onComplete: () => setState(() => _setupDone = true)),
    );
  }
}
