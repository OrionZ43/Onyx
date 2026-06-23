import 'dart:ui';
import 'package:flutter/material.dart';
import 'theme/app_colors.dart';

/// Универсальный виджет жидкого стекла.
/// Использует BackdropFilter для frosted glass эффекта.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = 24.0,
    this.blur = 20.0,
    this.opacity = 1.0,
    this.padding,
    this.border = true,
    this.glowColor,
    this.margin,
  });

  final Widget child;
  final double borderRadius;
  final double blur;
  final double opacity;
  final EdgeInsetsGeometry? padding;
  final bool border;
  final Color? glowColor;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final gc = glowColor;

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: gc != null
            ? [BoxShadow(color: gc, blurRadius: 32, spreadRadius: -4)]
            : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              gradient: AppColors.gradientGlass(opacity: opacity),
              borderRadius: radius,
              border: border
                  ? Border.all(color: AppColors.glassBorder, width: 1.0)
                  : null,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Тонкая стеклянная плашка — для статусов, бейджей
class GlassPill extends StatelessWidget {
  const GlassPill({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  });

  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(100),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: color?.withValues(alpha: 0.15) ?? AppColors.glass,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: color?.withValues(alpha: 0.3) ?? AppColors.glassBorder,
              width: 0.8,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
