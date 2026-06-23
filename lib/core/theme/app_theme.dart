import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';

abstract final class AppTheme {
  static ThemeData get dark {
    const base = ColorScheme.dark(
      brightness: Brightness.dark,
      primary: AppColors.accentSilver,
      onPrimary: AppColors.nebula0,
      secondary: AppColors.accentSilver,
      onSecondary: AppColors.nebula0,
      surface: AppColors.void2,
      onSurface: AppColors.nebula0,
      error: AppColors.nova,
      outline: AppColors.horizon,
    );

    return ThemeData.dark(useMaterial3: true).copyWith(
      colorScheme: base,
      scaffoldBackgroundColor: AppColors.void1,
      textTheme: _textTheme,
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.glassBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.horizon,
        thickness: 1,
        space: 1,
      ),
      iconTheme: const IconThemeData(color: AppColors.nebula1, size: 20),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
        ),
        titleTextStyle: _textTheme.titleLarge,
        iconTheme: const IconThemeData(color: AppColors.nebula1),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.void3,
        contentTextStyle: _textTheme.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.void2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: const BorderSide(color: AppColors.glassBorder),
        ),
      ),
    );
  }

  static const TextTheme _textTheme = TextTheme(
    // Syne — геометрический гротеск, отличается от всего стандартного
    displayLarge: TextStyle(
      fontFamily: 'Syne',
      fontSize: 48,
      fontWeight: FontWeight.w800,
      color: AppColors.nebula0,
      letterSpacing: -2,
    ),
    headlineLarge: TextStyle(
      fontFamily: 'Syne',
      fontSize: 32,
      fontWeight: FontWeight.w700,
      color: AppColors.nebula0,
      letterSpacing: -1,
    ),
    headlineMedium: TextStyle(
      fontFamily: 'Syne',
      fontSize: 24,
      fontWeight: FontWeight.w700,
      color: AppColors.nebula0,
      letterSpacing: -0.5,
    ),
    titleLarge: TextStyle(
      fontFamily: 'Syne',
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: AppColors.nebula0,
    ),
    titleMedium: TextStyle(
      fontFamily: 'Syne',
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: AppColors.nebula0,
      letterSpacing: 0.2,
    ),
    // DM Sans — чёткий, читаемый, но не дефолтный
    bodyLarge: TextStyle(
      fontFamily: 'DM Sans',
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: AppColors.nebula0,
    ),
    bodyMedium: TextStyle(
      fontFamily: 'DM Sans',
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: AppColors.nebula1,
    ),
    bodySmall: TextStyle(
      fontFamily: 'DM Sans',
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: AppColors.nebula2,
    ),
    labelLarge: TextStyle(
      fontFamily: 'DM Sans',
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: AppColors.nebula0,
      letterSpacing: 0.8,
    ),
    labelMedium: TextStyle(
      fontFamily: 'DM Sans',
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: AppColors.nebula1,
      letterSpacing: 1.2,
    ),
  );
}
