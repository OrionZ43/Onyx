import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'm3/app_shapes.dart';
import 'm3/app_state_layer.dart';
import 'm3/app_typography.dart';
import 'onyx_tokens.dart';
import 'theme_kind.dart';

/// Сборка `ThemeData` для трёх тем.
///
/// * Onyx — тёплый чёрный, акцент шампань `#D2B98F`, Inter / Inter Tight.
/// * Signal — абсолютный чёрный (OLED), акцент «REC» `#FF3B2F`, Onest / JetBrains Mono.
/// * Material — Material 3 Expressive: схема из обоев (Android 12+) или
///   эталонная схема M3, типошкала M3 с emphasized-стилями, Material Symbols и
///   компоненты, перенесённые из «Расписания МИТСО» (`docs/m3/`).
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

  /// Сид эталонной схемы M3 (`#6750A4`) — для справки: сама схема берётся
  /// встроенной ([materialScheme]), а не выводится из сида.
  static const Color materialSeed = Color(0xFF6750A4);

  /// Эталонная тёмная схема M3 (`ColorDarkTokens`): во Flutter это встроенная
  /// схема `ThemeData`, а `fromSeed(#6750A4)` дал бы другие роли.
  static final ColorScheme _baselineDark =
      ThemeData(brightness: Brightness.dark, useMaterial3: true).colorScheme;

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

  /// Схема темы Material: цвета обоев (Android 12+, `DynamicColorBuilder`),
  /// иначе эталон M3 (Windows, Android до 12, тесты).
  static ColorScheme materialScheme(ColorScheme? dynamicDark) =>
      dynamicDark ?? _baselineDark;

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
      // Старые экраны кладут поля в свои контейнеры — глобально поле без
      // заливки и рамки; новые поля задают вид явно (onyxInputDecoration).
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(color: t.textFaint),
        border: InputBorder.none,
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

  /// Material 3 Expressive — как `buildTheme` в «Расписании МИТСО»:
  /// типошкала M3 (`AppTypography`, Roboto), Material Symbols, ripple и
  /// state layer по `StateTokens`, компоненты Flutter — по токенам M3.
  static ThemeData _material(ColorScheme s, OnyxTokens t) {
    final TextTheme text = AppTypography.textTheme().apply(
      bodyColor: s.onSurface,
      displayColor: s.onSurface,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: s,
      fontFamily: 'Roboto',
      textTheme: text,
      extensions: [t],
      scaffoldBackgroundColor: s.surface,
      canvasColor: s.surface,

      // Material Symbols: https://m3.material.io/styles/icons — вес 400,
      // оптический размер по размеру иконки, grade −25 для светлых иконок на
      // тёмном фоне.
      iconTheme: IconThemeData(
        size: 24,
        opticalSize: 24,
        weight: 400,
        grade: -25,
        fill: 0,
        color: s.onSurfaceVariant,
      ),

      // State layer цветом содержимого: pressed/focus 10 %, hover 8 %
      // (`StateTokens.kt`). Ripple — как `ripple()` в Compose, без InkSparkle.
      splashFactory: InkRipple.splashFactory,
      splashColor: s.onSurface.withValues(alpha: AppStateLayer.pressedOpacity),
      highlightColor: s.onSurface.withValues(alpha: AppStateLayer.pressedOpacity),
      hoverColor: s.onSurface.withValues(alpha: AppStateLayer.hoverOpacity),
      focusColor: s.onSurface.withValues(alpha: AppStateLayer.focusOpacity),

      // App bar: `AppBarTokens` — контейнер surface, при прокрутке под ним —
      // surfaceContainer, без тени; заголовок titleLarge, отступ действий 4dp.
      appBarTheme: AppBarTheme(
        backgroundColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.scrolledUnder)
              ? s.surfaceContainer
              : s.surface,
        ),
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleTextStyle: text.titleLarge,
        actionsPadding: const EdgeInsetsDirectional.only(end: 4),
        systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: s.surface,
        ),
      ),

      // Карточки: умолчания Flutter M3 совпадают с токенами (filled —
      // surfaceContainerHighest, 12dp).
      cardTheme: const CardThemeData(margin: EdgeInsets.zero),

      // Plain tooltip: `PlainTooltipTokens` — inverseSurface / inverseOnSurface,
      // bodySmall, углы 4dp, поля 8×4, ширина до 200dp.
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: s.inverseSurface,
          borderRadius: AppShapes.all(AppShapes.extraSmall),
        ),
        textStyle: text.bodySmall!.copyWith(color: s.onInverseSurface),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        constraints: const BoxConstraints(minWidth: 40, minHeight: 24, maxWidth: 200),
      ),

      // Пункт списка: `ListTokens` — поля 16, сверху и снизу 10, между слотами 12.
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
        minVerticalPadding: 10,
        horizontalTitleGap: 12,
        minLeadingWidth: 24,
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodyMedium!.copyWith(color: s.onSurfaceVariant),
        iconColor: s.onSurfaceVariant,
      ),

      dividerTheme: DividerThemeData(color: s.outlineVariant, thickness: 1, space: 1),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: s.inverseSurface,
        contentTextStyle: text.bodyMedium!.copyWith(color: s.onInverseSurface),
        shape: AppShapes.rounded(AppShapes.extraSmall),
        insetPadding: const EdgeInsets.all(12),
      ),

      // Заполненное поле M3 (`FilledTextFieldTokens`): surfaceContainerHighest,
      // верхние углы 4dp, индикатор снизу — умолчания Flutter при filled.
      inputDecorationTheme: const InputDecorationTheme(filled: true),

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
