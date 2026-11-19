import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Интерполяция цвета, как `lerp(Color, Color, Float)` из Compose
/// `ui-graphics` (`Color.kt`): через Oklab, а не покомпонентно в sRGB, как
/// `Color.lerp` Flutter. Тем же пространством пользуется
/// `Color.VectorConverter`, то есть и `animateColorAsState`.
///
/// Та же функция, что `_lerpOklab` в перенесённом `m3_flexible_app_bar.dart`;
/// вынесена, чтобы ею пользовались и другие компоненты темы Material.
///
/// Матрицы — из описания Oklab (Björn Ottosson, «A perceptual color space for
/// image processing»).
Color lerpOklab(Color start, Color stop, double t) {
  if (t <= 0) return start;
  if (t >= 1) return stop;

  double toLinear(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  double fromLinear(double c) => c <= 0.0031308
      ? 12.92 * c
      : 1.055 * math.pow(c, 1 / 2.4).toDouble() - 0.055;
  double cbrt(double x) =>
      x < 0 ? -math.pow(-x, 1 / 3).toDouble() : math.pow(x, 1 / 3).toDouble();

  List<double> toOklab(Color color) {
    final double r = toLinear(color.r);
    final double g = toLinear(color.g);
    final double b = toLinear(color.b);
    final double l = cbrt(
      0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b,
    );
    final double m = cbrt(
      0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b,
    );
    final double s = cbrt(
      0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b,
    );
    return [
      0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
      1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
      0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
    ];
  }

  final List<double> a = toOklab(start);
  final List<double> b = toOklab(stop);
  double mix(double x, double y) => x + (y - x) * t;
  final double lightness = mix(a[0], b[0]);
  final double green = mix(a[1], b[1]);
  final double blue = mix(a[2], b[2]);

  double cube(double x) => x * x * x;
  final double l = cube(lightness + 0.3963377774 * green + 0.2158037573 * blue);
  final double m = cube(lightness - 0.1055613458 * green - 0.0638541728 * blue);
  final double s = cube(lightness - 0.0894841775 * green - 1.2914855480 * blue);
  return Color.from(
    alpha: mix(start.a, stop.a),
    red: fromLinear(
      4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    ).clamp(0.0, 1.0),
    green: fromLinear(
      -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    ).clamp(0.0, 1.0),
    blue: fromLinear(
      -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
    ).clamp(0.0, 1.0),
  );
}
