// Выбор страны сервера вручную (#68) — если по названию и проверке страна
// определилась неверно или не определилась. Флаги — в стиле темы
// (CountryFlag: круг в Onyx, точки в Signal).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/onyx_tokens.dart';
import '../util/country.dart';
import 'country_flag.dart';
import 'onyx_field.dart';
import 'onyx_icon.dart';

/// Возвращает код страны, '' — «Определять автоматически», null — отмена.
/// [picked] — выбранная пользователем страна (если есть), [detected] — что
/// определилось бы без него.
Future<String?> showCountryPicker(
  BuildContext context, {
  required String serverName,
  String? picked,
  required Country detected,
}) {
  final t = OnyxTokens.of(context);
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: t.isMaterial ? null : t.surface,
    builder: (_) => _CountryPicker(serverName: serverName, picked: picked, detected: detected),
  );
}

class _CountryPicker extends StatefulWidget {
  const _CountryPicker({required this.serverName, required this.picked, required this.detected});
  final String serverName;
  final String? picked;
  final Country detected;

  @override
  State<_CountryPicker> createState() => _CountryPickerState();
}

class _CountryPickerState extends State<_CountryPicker> {
  final _query = TextEditingController();
  final _all = allCountries();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final mq = MediaQuery.of(context);
    final q = _query.text.trim().toLowerCase();
    final list = q.isEmpty ? _all : _all.where((c) => c.name.toLowerCase().contains(q) || c.code == q).toList();
    final check = t.isSignal ? AppTheme.signalRec : t.accent;
    final pad = t.isMaterial ? 16.0 : 20.0;

    Widget row({required Widget lead, required String title, String? subtitle, required bool selected, required VoidCallback onTap}) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: pad, vertical: 10),
            child: Row(children: [
              lead,
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: TextStyle(fontFamily: t.bodyFont, fontSize: 14.5, fontWeight: FontWeight.w500, color: t.text)),
                  if (subtitle != null)
                    Text(subtitle, style: TextStyle(fontFamily: t.bodyFont, fontSize: 12.5, color: t.textMuted)),
                ]),
              ),
              if (selected) OnyxIcon(OnyxGlyph.check, size: 18, color: check),
            ]),
          ),
        );

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SizedBox(
        height: math.min(620, mq.size.height * .78),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, 2),
            child: Text(t.isSignal ? 'СТРАНА СЕРВЕРА' : 'Страна сервера',
                style: t.isSignal ? t.caps(size: 11) : TextStyle(fontFamily: t.displayFont, fontSize: 18, color: t.text)),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, 12),
            child: Text(widget.serverName,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: t.bodyFont, fontSize: 12.5, color: t.textMuted)),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              style: TextStyle(fontFamily: t.bodyFont, fontSize: t.isMaterial ? 16 : 14, color: t.text),
              decoration: onyxInputDecoration(
                context,
                hint: 'Поиск страны',
                prefix: OnyxIcon(OnyxGlyph.search, size: t.isMaterial ? 24 : 16, color: t.textFaint),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(padding: const EdgeInsets.only(bottom: 16), children: [
              if (q.isEmpty)
                row(
                  lead: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: t.isOnyx ? const Color(0xFF3A3326) : t.lineStrong)),
                    child: OnyxIcon(OnyxGlyph.zap, size: 13, color: t.isSignal ? t.text : t.accent),
                  ),
                  title: 'Определять автоматически',
                  subtitle: widget.detected.isKnown ? 'Сейчас: ${widget.detected.name} — по названию' : 'По названию и проверке сервера',
                  selected: widget.picked == null,
                  onTap: () => Navigator.pop(context, ''),
                ),
              for (final c in list)
                row(
                  lead: CountryFlag(code: c.code, size: 26),
                  title: c.name,
                  selected: widget.picked == c.code,
                  onTap: () => Navigator.pop(context, c.code),
                ),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('Такой страны нет в списке', textAlign: TextAlign.center, style: TextStyle(fontFamily: t.bodyFont, color: t.textMuted)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
