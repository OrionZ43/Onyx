import 'package:flutter/material.dart';

import 'theme_kind.dart';

/// Семантические токены темы — общий словарь для всех трёх тем.
///
/// Виджеты берут цвета, радиусы и шрифты отсюда (`OnyxTokens.of(context)`),
/// а не из констант: так один и тот же экран выглядит как Onyx, Signal или
/// Material 3 Expressive.
@immutable
class OnyxTokens extends ThemeExtension<OnyxTokens> {
  const OnyxTokens({
    required this.kind,
    required this.bg,
    required this.surface,
    required this.surfaceHigh,
    required this.surfaceTop,
    required this.line,
    required this.lineStrong,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.accent,
    required this.accentMuted,
    required this.onAccent,
    required this.danger,
    required this.radiusCard,
    required this.radiusSheet,
    required this.radiusChip,
    required this.displayFont,
    required this.bodyFont,
    required this.monoFont,
  });

  final AppThemeKind kind;

  /// Фон экрана.
  final Color bg;

  /// Карточки, шторка.
  final Color surface;

  /// Приподнятые элементы, поля ввода, треки.
  final Color surfaceHigh;

  /// Самый верхний слой (выбранная строка, тумблер).
  final Color surfaceTop;

  /// Хайрлайн и разделители.
  final Color line;
  final Color lineStrong;

  final Color text;
  final Color textMuted;
  final Color textFaint;

  /// Единственный акцент: «защищено», выбор, активные индикаторы.
  final Color accent;

  /// Переходные состояния (подключение) и приглушённый акцент.
  final Color accentMuted;

  /// Текст и иконки поверх [accent].
  final Color onAccent;

  /// Ошибка: сдержанный, а не кислотный.
  final Color danger;

  final double radiusCard;
  final double radiusSheet;
  final double radiusChip;

  final String displayFont;
  final String bodyFont;
  final String monoFont;

  bool get isOnyx => kind == AppThemeKind.onyx;
  bool get isSignal => kind == AppThemeKind.signal;
  bool get isMaterial => kind == AppThemeKind.material;

  static OnyxTokens of(BuildContext context) =>
      Theme.of(context).extension<OnyxTokens>()!;

  /// Подпись капсом с трекингом — «КЛЮЧ» в Onyx/Signal; в Material — labelLarge.
  TextStyle caps({double size = 11, Color? color, FontWeight? weight}) =>
      isMaterial
          ? TextStyle(
              fontFamily: bodyFont,
              fontSize: size + 1,
              fontWeight: weight ?? FontWeight.w500,
              letterSpacing: 0.1,
              color: color ?? textMuted,
            )
          : TextStyle(
              fontFamily: isSignal ? monoFont : displayFont,
              fontSize: size,
              fontWeight: weight ?? FontWeight.w500,
              letterSpacing: isSignal ? size * 0.12 : size * 0.22,
              color: color ?? textMuted,
            );

  /// Крупные цифры (таймер, трафик) — моноширинные по ширине цифр.
  TextStyle numbers({double size = 22, Color? color, FontWeight? weight}) =>
      TextStyle(
        fontFamily: isSignal ? bodyFont : displayFont,
        fontSize: size,
        fontWeight: weight ?? (isOnyx ? FontWeight.w300 : FontWeight.w400),
        letterSpacing: isOnyx ? -0.02 * size : 0,
        color: color ?? text,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  @override
  OnyxTokens copyWith({AppThemeKind? kind, Color? accent, Color? danger}) =>
      OnyxTokens(
        kind: kind ?? this.kind,
        bg: bg,
        surface: surface,
        surfaceHigh: surfaceHigh,
        surfaceTop: surfaceTop,
        line: line,
        lineStrong: lineStrong,
        text: text,
        textMuted: textMuted,
        textFaint: textFaint,
        accent: accent ?? this.accent,
        accentMuted: accentMuted,
        onAccent: onAccent,
        danger: danger ?? this.danger,
        radiusCard: radiusCard,
        radiusSheet: radiusSheet,
        radiusChip: radiusChip,
        displayFont: displayFont,
        bodyFont: bodyFont,
        monoFont: monoFont,
      );

  @override
  OnyxTokens lerp(OnyxTokens? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    double d(double a, double b) => a + (b - a) * t;
    final near = t < 0.5 ? this : other;
    return OnyxTokens(
      kind: near.kind,
      bg: c(bg, other.bg),
      surface: c(surface, other.surface),
      surfaceHigh: c(surfaceHigh, other.surfaceHigh),
      surfaceTop: c(surfaceTop, other.surfaceTop),
      line: c(line, other.line),
      lineStrong: c(lineStrong, other.lineStrong),
      text: c(text, other.text),
      textMuted: c(textMuted, other.textMuted),
      textFaint: c(textFaint, other.textFaint),
      accent: c(accent, other.accent),
      accentMuted: c(accentMuted, other.accentMuted),
      onAccent: c(onAccent, other.onAccent),
      danger: c(danger, other.danger),
      radiusCard: d(radiusCard, other.radiusCard),
      radiusSheet: d(radiusSheet, other.radiusSheet),
      radiusChip: d(radiusChip, other.radiusChip),
      displayFont: near.displayFont,
      bodyFont: near.bodyFont,
      monoFont: near.monoFont,
    );
  }
}
