import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'installer_screen.dart';
import 'core/theme/app_colors.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const InstallerApp());
}

class InstallerApp extends StatelessWidget {
  const InstallerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Onyx Installer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.void1,
        fontFamily: 'DM Sans',
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: AppColors.nebula0),
          bodyMedium: TextStyle(color: AppColors.nebula0),
        ),
      ),
      home: const InstallerScreen(),
    );
  }
}
