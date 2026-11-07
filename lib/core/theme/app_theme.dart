import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'onyx_tokens.dart';
import 'theme_kind.dart';

/// Сборка `ThemeData` для трёх тем.
///
/// * Onyx — тёплый чёрный, акцент шампань `#D2B98F`, Inter / Inter Tight.
/// * Signal — абсолютный чёрный (OLED), акцент «REC» `#FF3B2F`, Onest / JetBrains Mono.
/// * Material — Material 3 Expressive: схема из обоев (Android 12+) или из сида,
///   шкала форм и типошкала M3, Roboto.
abstract final class AppTheme {
  // ── Onyx ──────────────────────────────────────────────────────────────────
  static const OnyxTokens onyxTokens = OnyxTokens(
    kind: AppThemeKind.onyx,
    bg: Color(0xFF050506),
    surface: Color(0xFF0C0C0E),
    surfaceHigh: Color(0xFF131316),
    surfaceTop: Color(0xFF1B1B1F),
    line: Color(0xFF222226),
    lineStrong: Color(0xFF2E2E33),
    text: Color(0xFFF3F1EC),
    textMuted: Color(0xFF8F8C86),
    textFaint: Color(0xFF57554F),
    accent: Color(0xFFD2B98F),
    accentMuted: Color(0xFF8E7B5B),
    onAccent: Color(0xFF050506),
    danger: Color(0xFFC8655A),
    radiusCard: 20,
    radiusSheet: 28,
    radiusChip: 14,
    displayFont: 'InterTight',
    bodyFont: 'Inter',
    monoFont: 'InterTight',
  );

  // ── Signal ────────────────────────────────────────────────────────────────
  static const OnyxTokens signalTokens = OnyxTokens(
    kind: AppThemeKind.signal,
    bg: Color(0xFF000000),
    surface: Color(0xFF0B0B0B),
    surfaceHigh: Color(0xFF141414),
    surfaceTop: Color(0xFF1C1C1C),
    line: Color(0xFF1C1C1C),
    lineStrong: Color(0xFF2A2A2A),
    text: Color(0xFFFFFFFF),
    textMuted: Color(0xFF9B9B9B),
    textFaint: Color(0xFF555555),
    accent: Color(0xFFFFFFFF),
    accentMuted: Color(0xFF9B9B9B),
    onAccent: Color(0xFF000000),
    danger: Color(0xFFFF3B2F),
    radiusCard: 24,
    radiusSheet: 32,
    radiusChip: 18,
    displayFont: 'Onest',
    bodyFont: 'Onest',
    monoFont: 'JetBrainsMono',
  );

  /// Красная REC-точка Signal: «в эфире», выбранный сервер.
  static const Color signalRec = Color(0xFFFF3B2F);

  /// Сид статичной схемы Material, когда цвета обоев недоступны
  /// (Windows, Android < 12): эталон M3 `#6750A4`.
  static const Color materialSeed = Color(0xFF6750A4);

  static OnyxTokens materialTokens(ColorScheme s) => OnyxTokens(
        kind: AppThemeKind.material,
        bg: s.surface,
        surface: s.surfaceContainer,
        surfaceHigh: s.surfaceContainerHigh,
        surfaceTop: s.surfaceContainerHighest,
        line: s.outlineVariant,
        lineStrong: s.outline,
        text: s.onSurface,
        textMuted: s.onSurfaceVariant,
        textFaint: s.onSurfaceVariant.withValues(alpha: 0.6),
        accent: s.primary,
        accentMuted: s.primaryContainer,
        onAccent: s.onPrimary,
        danger: s.error,
        radiusCard: 28,
        radiusSheet: 28,
        radiusChip: 8,
        displayFont: 'Roboto',
        bodyFont: 'Roboto',
        monoFont: 'Roboto',
      );

  static ColorScheme materialScheme(ColorScheme? dynamicDark) =>
      dynamicDark ??
      ColorScheme.fromSeed(
        seedColor: materialSeed,
        brightness: Brightness.dark,
      );

  /// Тема по виду. [dynamicDark] — тёмная схема обоев (Android 12+), только для Material.
  static ThemeData build(AppThemeKind kind, {ColorScheme? dynamicDark}) {
    final OnyxTokens t = switch (kind) {
      AppThemeKind.onyx => onyxTokens,
      AppThemeKind.signal => signalTokens,
      AppThemeKind.material => materialTokens(materialScheme(dynamicDark)),
    };
    // Старые экраны берут цвета из AppColors — подменяем палитру на активную.
    AppColors.active = t;
    return kind == AppThemeKind.material
        ? _material(materialScheme(dynamicDark), t)
        : _dark(t);
  }

  /// Onyx / Signal: собственная тёмная тема поверх Material 3.
  static ThemeData _dark(OnyxTokens t) {
    final scheme = ColorScheme.dark(
      primary: t.accent,
      onPrimary: t.onAccent,
      secondary: t.accentMuted,
      onSecondary: t.text,
      surface: t.bg,
      onSurface: t.text,
      onSurfaceVariant: t.textMuted,
      surfaceContainerLowest: t.bg,
      surfaceContainerLow: t.surface,
      surfaceContainer: t.surface,
      surfaceContainerHigh: t.surfaceHigh,
      surfaceContainerHighest: t.surfaceTop,
      error: t.danger,
      outline: t.lineStrong,
      outlineVariant: t.line,
    );
    final text = _textTheme(t);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: t.bg,
      canvasColor: t.bg,
      fontFamily: t.bodyFont,
      textTheme: text,
      extensions: [t],
      splashFactory: InkSparkle.splashFactory,
      dividerTheme: DividerThemeData(color: t.line, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: t.textMuted, size: 20),
      appBarTheme: AppBarTheme(
        backgroundColor: t.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: t.textMuted),
        systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: t.bg,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: t.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.radiusCard),
          side: t.isOnyx ? BorderSide(color: t.line) : BorderSide.none,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? (t.isSignal ? t.bg : t.accent)
              : t.textFaint,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? (t.isSignal ? t.text : const Color(0xFF2A2418))
              : t.surfaceTop,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? (t.isSignal ? t.text : const Color(0xFF4A3F2C))
              : t.lineStrong,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: t.surfaceHigh,
        contentTextStyle: text.bodyMedium?.copyWith(color: t.text),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.radiusChip),
          side: BorderSide(color: t.line),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(t.radiusSheet),
          side: BorderSide(color: t.line),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: Colors.black.withValues(alpha: 0.66),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(t.radiusSheet)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.isSignal ? t.surfaceHigh : t.bg,
        hintStyle: TextStyle(color: t.textFaint),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.isSignal ? 24 : 22),
          borderSide: t.isSignal ? BorderSide.none : BorderSide(color: t.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.isSignal ? 24 : 22),
          borderSide: t.isSignal ? BorderSide.none : BorderSide(color: t.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(t.isSignal ? 24 : 22),
          borderSide: BorderSide(color: t.lineStrong),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: t.accent,
        selectionColor: t.accent.withValues(alpha: 0.25),
        selectionHandleColor: t.accent,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  static TextTheme _textTheme(OnyxTokens t) {
    TextStyle d(double size, FontWeight w, {double tracking = 0}) => TextStyle(
          fontFamily: t.displayFont,
          fontSize: size,
          fontWeight: w,
          letterSpacing: tracking,
          color: t.text,
        );
    TextStyle b(double size, FontWeight w, Color c, {double tracking = 0}) =>
        TextStyle(
          fontFamily: t.bodyFont,
          fontSize: size,
          fontWeight: w,
          letterSpacing: tracking,
          color: c,
        );
    final light = t.isOnyx ? FontWeight.w300 : FontWeight.w500;
    return TextTheme(
      displayLarge: d(48, light, tracking: -1.2),
      displayMedium: d(40, light, tracking: -1),
      displaySmall: d(34, light, tracking: -0.7),
      headlineLarge: d(30, light, tracking: -0.6),
      headlineMedium: d(26, t.isOnyx ? FontWeight.w400 : FontWeight.w500,
          tracking: -0.5),
      headlineSmall: d(22, FontWeight.w500, tracking: -0.3),
      titleLarge: d(18, FontWeight.w500, tracking: -0.2),
      titleMedium: b(15, FontWeight.w500, t.text),
      titleSmall: b(13.5, FontWeight.w500, t.text),
      bodyLarge: b(15, FontWeight.w400, t.text),
      bodyMedium: b(13.5, FontWeight.w400, t.textMuted),
      bodySmall: b(12, FontWeight.w400, t.textMuted),
      labelLarge: b(14, FontWeight.w500, t.text),
      labelMedium: b(12, FontWeight.w500, t.textMuted),
      labelSmall: b(11, FontWeight.w500, t.textFaint, tracking: 0.3),
    );
  }

  /// Material 3 Expressive: стандартная тема M3 со схемой [s], типошкалой M3
  /// (https://m3.material.io/styles/typography/type-scale-tokens) и шкалой форм.
  static ThemeData _material(ColorScheme s, OnyxTokens t) {
    TextStyle st(double size, double height, double tracking, FontWeight w) =>
        TextStyle(
          fontFamily: 'Roboto',
          fontSize: size,
          height: height / size,
          letterSpacing: tracking,
          fontWeight: w,
        );
    final text = TextTheme(
      displayLarge: st(57, 64, -0.25, FontWeight.w400),
      displayMedium: st(45, 52, 0, FontWeight.w400),
      displaySmall: st(36, 44, 0, FontWeight.w400),
      headlineLarge: st(32, 40, 0, FontWeight.w400),
      headlineMedium: st(28, 36, 0, FontWeight.w400),
      headlineSmall: st(24, 32, 0, FontWeight.w400),
      titleLarge: st(22, 28, 0, FontWeight.w400),
      titleMedium: st(16, 24, 0.15, FontWeight.w500),
      titleSmall: st(14, 20, 0.1, FontWeight.w500),
      bodyLarge: st(16, 24, 0.5, FontWeight.w400),
      bodyMedium: st(14, 20, 0.25, FontWeight.w400),
      bodySmall: st(12, 16, 0.4, FontWeight.w400),
      labelLarge: st(14, 20, 0.1, FontWeight.w500),
      labelMedium: st(12, 16, 0.5, FontWeight.w500),
      labelSmall: st(11, 16, 0.5, FontWeight.w500),
    ).apply(bodyColor: s.onSurface, displayColor: s.onSurface);
    return ThemeData(
      useMaterial3: true,
      colorScheme: s,
      fontFamily: 'Roboto',
      textTheme: text,
      extensions: [t],
      scaffoldBackgroundColor: s.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: s.surface,
        scrolledUnderElevation: 0,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: s.surface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: s.surfaceContainer,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: s.surfaceContainerLow,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: s.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// Совместимость со старым кодом (`AppTheme.dark`) — тема Onyx.
  static ThemeData get dark => build(AppThemeKind.onyx);
}
