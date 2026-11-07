import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme/onyx_tokens.dart';
import 'onyx_icon.dart';
import 'onyx_wordmark.dart';

/// Тайтлбар окна Windows в стиле темы (системный скрыт в `main.dart`).
///
/// Перетаскивание — вся полоса, двойной клик — развернуть. Кнопки справа
/// повторяют системные: свернуть (уходит в трей), развернуть, закрыть.
class WindowTitleBar extends StatelessWidget {
  const WindowTitleBar({super.key, this.onMinimize});

  /// «Свернуть». В приложении — сразу спрятать в трей (main.dart): так окно
  /// не остаётся в свёрнутом состоянии, из которого Windows разворачивает его
  /// в прежний размер поверх мини-панели. По умолчанию — обычное сворачивание.
  final VoidCallback? onMinimize;

  static const double height = 40;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    return Material(
      color: t.bg,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          border: t.isOnyx ? Border(bottom: BorderSide(color: t.line)) : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: DragToMoveArea(
                child: Padding(
                  padding: const EdgeInsets.only(left: 18),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: OnyxWordmark(size: t.isMaterial ? 14 : 11.5),
                  ),
                ),
              ),
            ),
            _WinButton(
              glyph: OnyxGlyph.minimize,
              onTap: onMinimize ?? () => windowManager.minimize(),
            ),
            _WinButton(
              glyph: OnyxGlyph.maximize,
              onTap: () async => await windowManager.isMaximized()
                  ? windowManager.unmaximize()
                  : windowManager.maximize(),
            ),
            _WinButton(
              glyph: OnyxGlyph.close,
              danger: true,
              onTap: () => windowManager.close(),
            ),
          ],
        ),
      ),
    );
  }
}

class _WinButton extends StatefulWidget {
  const _WinButton({required this.glyph, required this.onTap, this.danger = false});
  final OnyxGlyph glyph;
  final VoidCallback onTap;
  final bool danger;

  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final hoverBg = widget.danger ? const Color(0xFFC42B1C) : t.surfaceHigh;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 46,
          height: WindowTitleBar.height,
          color: _hover ? hoverBg : Colors.transparent,
          alignment: Alignment.center,
          child: OnyxIcon(
            widget.glyph,
            size: 14,
            color: _hover && widget.danger ? Colors.white : t.textMuted,
          ),
        ),
      ),
    );
  }
}
