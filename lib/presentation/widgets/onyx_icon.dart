import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/onyx_tokens.dart';

/// Набор иконок приложения. Каждая тема рисует их своим набором:
/// Onyx — Phosphor Light (`assets/icons/onyx`), Signal — Pixelarticons
/// (`assets/icons/signal`), Material — Material Symbols (система иконок M3,
/// https://m3.material.io/styles/icons), те же глифы.
/// Лицензии — `assets/icons/LICENSES.md`.
enum OnyxGlyph {
  power('power', Symbols.power_settings_new),
  settings('settings', Symbols.settings),
  globe('globe', Symbols.language),
  chevronRight('chev', Symbols.chevron_right),
  chevronDown('chevd', Symbols.expand_more),
  back('back', Symbols.arrow_back),
  search('search', Symbols.search),
  plus('plus', Symbols.add),
  down('down', Symbols.arrow_downward),
  up('up', Symbols.arrow_upward),
  clock('clock', Symbols.schedule),
  shield('shield', Symbols.verified_user),
  zap('zap', Symbols.bolt),
  check('check', Symbols.check),
  more('more', Symbols.more_vert),
  refresh('refresh', Symbols.refresh),
  close('close', Symbols.close),
  sliders('sliders', Symbols.tune),
  paste('paste', Symbols.content_paste),
  link('link', Symbols.link),
  qr('qr', Symbols.qr_code_scanner),
  error('error', Symbols.error),
  ai('ai', Symbols.auto_awesome),
  terminal('terminal', Symbols.terminal),
  help('help', Symbols.help),
  star('star', Symbols.star),
  trash('trash', Symbols.delete),
  copy('copy', Symbols.content_copy),
  info('info', Symbols.info),

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
