import 'package:flutter/material.dart';

import '../../core/theme/onyx_tokens.dart';

/// Оформление поля ввода в стиле темы: Onyx — капсула с хайрлайном на фоне,
/// Signal — заливка без рамки, Material — Search bar (56, full, surfaceContainerHigh).
InputDecoration onyxInputDecoration(
  BuildContext context, {
  required String hint,
  Widget? prefix,
  Widget? suffix,
}) {
  final t = OnyxTokens.of(context);
  final s = Theme.of(context).colorScheme;
  final radius = BorderRadius.circular(t.isMaterial ? 28 : (t.isSignal ? 24 : 22));
  final side = t.isOnyx ? BorderSide(color: t.line) : BorderSide.none;
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(fontFamily: t.bodyFont, color: t.isMaterial ? s.onSurfaceVariant : t.textFaint),
    filled: true,
    fillColor: t.isMaterial ? s.surfaceContainerHigh : (t.isSignal ? t.surfaceHigh : t.bg),
    isDense: !t.isMaterial,
    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: t.isMaterial ? 16 : 13),
    prefixIcon: prefix == null ? null : Padding(padding: const EdgeInsets.only(left: 14, right: 10), child: prefix),
    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    suffixIcon: suffix,
    border: OutlineInputBorder(borderRadius: radius, borderSide: side),
    enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: side),
    focusedBorder: OutlineInputBorder(
      borderRadius: radius,
      borderSide: t.isMaterial ? BorderSide.none : BorderSide(color: t.lineStrong),
    ),
  );
}
