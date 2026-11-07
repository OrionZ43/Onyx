import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/onyx_tokens.dart';
import 'onyx_icon.dart';

/// Тихий тост в стиле темы: Onyx — капсула с хайрлайном, Signal — чёрная
/// капсула с красной точкой и капсом, Material — стандартный снэкбар M3.
void showOnyxToast(BuildContext context, String text, {OnyxGlyph glyph = OnyxGlyph.info}) {
  final t = OnyxTokens.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  if (t.isMaterial) {
    messenger.showSnackBar(SnackBar(content: Row(children: [
      Icon(glyph.material, size: 18, color: Theme.of(context).colorScheme.onInverseSurface),
      const SizedBox(width: 12),
      Expanded(child: Text(text)),
    ])));
    return;
  }
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      padding: EdgeInsets.zero,
      duration: const Duration(seconds: 4),
      content: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: t.isSignal ? t.surfaceHigh : t.surface,
            borderRadius: BorderRadius.circular(t.isSignal ? 22 : 14),
            border: t.isOnyx ? Border.all(color: t.line) : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (t.isSignal)
              Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTheme.signalRec))
            else
              OnyxIcon(glyph, size: 14, color: t.textMuted),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                t.isSignal ? text.toUpperCase() : text,
                style: t.isSignal
                    ? t.caps(size: 10.5, color: t.text)
                    : TextStyle(fontFamily: t.bodyFont, fontSize: 12.5, color: t.textMuted),
              ),
            ),
          ]),
        ),
      ),
    ),
  );
}
