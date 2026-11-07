import 'package:flutter/material.dart';

import 'onyx_tokens.dart';

/// Совместимость для экранов, ещё не переведённых на [OnyxTokens].
///
/// Раньше здесь была «космическая» палитра (plasma / aurora / nebula). Теперь
/// это фасад над токенами активной темы: [AppTheme.build] выставляет [active],
/// а при смене темы `MaterialApp` перестраивается целиком (см. `main.dart`).
/// Новый код берёт цвета из `OnyxTokens.of(context)`.
abstract final class AppColors {
  static late OnyxTokens active;

  // ── Фоны ──────────────────────────────────────────────────────────────────
  static Color get void0 => active.bg;
  static Color get void1 => active.bg;
  static Color get void2 => active.surface;
  static Color get void3 => active.surfaceHigh;

  // ── Бывшее «стекло» — теперь плотные поверхности с хайрлайном ─────────────
  static Color get glass => active.surface;
  static Color get glassBorder => active.line;
  static Color get glassShine => Colors.transparent;
  static Color get glassDeep => Colors.transparent;

  // ── Акцент ────────────────────────────────────────────────────────────────
  static Color get plasma => active.accent;
  static Color get plasmaLight => active.accent;
  static Color get plasmaDim => active.accentMuted;
  static Color get plasmaGlow => active.accent.withValues(alpha: 0.25);
  static Color get plasmaTrace => active.accent.withValues(alpha: 0.08);

  /// Текст и иконки поверх акцента (бывший `gradientPlasma`).
  static Color get onPlasma => active.onAccent;

  /// «Подключено» — тот же единственный акцент.
  static Color get aurora => active.accent;
  static Color get auroraGlow => active.accent.withValues(alpha: 0.25);
  static Color get auroraDim => active.accentMuted;

  /// Переходное состояние.
  static Color get ember => active.accentMuted;
  static Color get emberGlow => active.accentMuted.withValues(alpha: 0.25);

  /// Ошибка.
  static Color get nova => active.danger;
  static Color get novaGlow => active.danger.withValues(alpha: 0.25);

  // ── Текст ─────────────────────────────────────────────────────────────────
  static Color get nebula0 => active.text;
  static Color get nebula1 => active.textMuted;
  static Color get nebula2 => active.textFaint;

  // ── Разделители ───────────────────────────────────────────────────────────
  static Color get horizon => active.line;
  static Color get horizonGlow => active.lineStrong;

  // ── Бывшие градиенты — теперь плоские ─────────────────────────────────────
  static LinearGradient get gradientVoid =>
      LinearGradient(colors: [active.bg, active.bg]);
  static LinearGradient get gradientPlasma =>
      LinearGradient(colors: [active.accent, active.accent]);
  static LinearGradient get gradientAurora =>
      LinearGradient(colors: [active.accent, active.accent]);
  static LinearGradient gradientGlass({double opacity = 1.0}) =>
      LinearGradient(colors: [active.surface, active.surface]);
  static RadialGradient get gradientNebula =>
      RadialGradient(colors: [active.bg, active.bg]);
}

/// Шрифты для старых экранов: раньше были прописаны 'Syne' / 'DM Sans' /
/// 'DM Mono', которые в приложение не встраивались (задача #31).
abstract final class AppFonts {
  static String get display => AppColors.active.displayFont;
  static String get body => AppColors.active.bodyFont;
  static String get mono => AppColors.active.monoFont;
}
