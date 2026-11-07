import 'package:flutter/material.dart';

import 'theme/onyx_tokens.dart';

/// Карточка-поверхность темы.
///
/// Раньше — «жидкое стекло» с BackdropFilter (blur 12–24), что клало GPU на
/// среднем железе и визуально ничего не давало на тёмном фоне. Теперь — плотная
/// поверхность с хайрлайном (Onyx) или без обводки (Signal / Material).
/// API прежний, чтобы старые экраны не менять.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius,
    this.blur = 0,
    this.opacity = 1.0,
    this.padding,
    this.border = true,
    this.glowColor,
    this.margin,
  });

  final Widget child;
  final double? borderRadius;
  final double blur;
  final double opacity;
  final EdgeInsetsGeometry? padding;
  final bool border;
  final Color? glowColor;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final radius = BorderRadius.circular(borderRadius ?? t.radiusCard);
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: radius,
        border: border && t.isOnyx ? Border.all(color: t.line) : null,
      ),
      child: child,
    );
  }
}

/// Плашка-капсула для статусов и бейджей.
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
    final t = OnyxTokens.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color?.withValues(alpha: 0.12) ?? t.surfaceHigh,
        borderRadius: BorderRadius.circular(100),
        border: t.isOnyx
            ? Border.all(color: color?.withValues(alpha: 0.3) ?? t.line)
            : null,
      ),
      child: child,
    );
  }
}

/// Круглая иконка-кнопка.
class GlassIconBtn extends StatelessWidget {
  const GlassIconBtn({super.key, required this.icon, required this.onTap, this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, size: 18, color: t.textMuted),
      style: IconButton.styleFrom(
        fixedSize: const Size(40, 40),
        backgroundColor: t.isSignal ? t.surfaceHigh : Colors.transparent,
        shape: CircleBorder(
          side: t.isOnyx ? BorderSide(color: t.line) : BorderSide.none,
        ),
      ),
    );
  }
}
