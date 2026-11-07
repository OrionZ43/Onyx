import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/onyx_tokens.dart';

/// Набор иконок приложения. Каждая тема рисует их своим набором:
/// Onyx — Phosphor Light (`assets/icons/onyx`), Signal — Pixelarticons
/// (`assets/icons/signal`), Material — встроенные Material Icons (rounded).
/// Лицензии — `assets/icons/LICENSES.md`.
enum OnyxGlyph {
  power('power', Icons.power_settings_new_rounded),
  settings('settings', Icons.settings_outlined),
  globe('globe', Icons.language_rounded),
  chevronRight('chev', Icons.chevron_right_rounded),
  chevronDown('chevd', Icons.expand_more_rounded),
  back('back', Icons.arrow_back_rounded),
  search('search', Icons.search_rounded),
  plus('plus', Icons.add_rounded),
  down('down', Icons.arrow_downward_rounded),
  up('up', Icons.arrow_upward_rounded),
  clock('clock', Icons.schedule_rounded),
  shield('shield', Icons.verified_user_outlined),
  zap('zap', Icons.bolt_rounded),
  check('check', Icons.check_rounded),
  more('more', Icons.more_vert_rounded),
  refresh('refresh', Icons.refresh_rounded),
  close('close', Icons.close_rounded),
  sliders('sliders', Icons.tune_rounded),
  paste('paste', Icons.content_paste_rounded),
  link('link', Icons.link_rounded),
  qr('qr', Icons.qr_code_scanner_rounded),
  error('error', Icons.error_outline_rounded),
  ai('ai', Icons.auto_awesome_outlined),
  voice('voice', Icons.mic_none_rounded),
  terminal('terminal', Icons.terminal_rounded),
  help('help', Icons.help_outline_rounded),
  star('star', Icons.star_outline_rounded),
  trash('trash', Icons.delete_outline_rounded),
  copy('copy', Icons.content_copy_rounded),
  info('info', Icons.info_outline_rounded),

  /// Кнопки окна — рисуются линиями во всех темах (как в Windows 11).
  minimize('', null),
  maximize('', null);

  const OnyxGlyph(this.asset, this.material);
  final String asset;
  final IconData? material;
}

class OnyxIcon extends StatelessWidget {
  const OnyxIcon(this.glyph, {super.key, this.size = 20, this.color});

  final OnyxGlyph glyph;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final c = color ?? IconTheme.of(context).color ?? t.textMuted;
    if (glyph == OnyxGlyph.minimize || glyph == OnyxGlyph.maximize) {
      return CustomPaint(
        size: Size.square(size),
        painter: _WindowGlyphPainter(glyph, c),
      );
    }
    if (t.isMaterial) return Icon(glyph.material, size: size, color: c);
    final dir = t.isSignal ? 'signal' : 'onyx';
    return SvgPicture.asset(
      'assets/icons/$dir/${glyph.asset}.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(c, BlendMode.srcIn),
    );
  }
}

class _WindowGlyphPainter extends CustomPainter {
  _WindowGlyphPainter(this.glyph, this.color);
  final OnyxGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final s = size.width * 0.72, o = (size.width - s) / 2;
    if (glyph == OnyxGlyph.minimize) {
      canvas.drawLine(Offset(o, size.height / 2), Offset(o + s, size.height / 2), p);
    } else {
      canvas.drawRect(Rect.fromLTWH(o + 0.5, o + 0.5, s - 1, s - 1), p);
    }
  }

  @override
  bool shouldRepaint(_WindowGlyphPainter old) =>
      old.color != color || old.glyph != glyph;
}
