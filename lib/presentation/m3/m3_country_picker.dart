// Выбор страны сервера вручную в теме Material 3 Expressive (#68): модальный
// нижний лист M3, поле поиска, «Определять автоматически», страны с флагами в
// форме (M3Flag). Логика та же, что у showCountryPicker тем Onyx и Signal:
// возвращает код страны, '' — снова определять автоматически, null — отмена.

import 'package:flutter/material.dart';
import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/m3/app_spacing.dart';
import '../../core/theme/m3/app_typography.dart';
import '../util/country.dart';
import '../widgets/m3/m3_bottom_sheet.dart';
import '../widgets/m3/segmented_list.dart';
import 'm3_parts.dart';

Future<String?> showM3CountryPicker(
  BuildContext context, {
  required String serverName,
  String? picked,
  required Country detected,
  String? detectedHow,
}) =>
    showM3ModalBottomSheet<String>(
      context: context,
      builder: (context, controller) => _CountryPicker(
        controller: controller,
        serverName: serverName,
        picked: picked,
        detected: detected,
        detectedHow: detectedHow,
      ),
    );

class _CountryPicker extends StatefulWidget {
  const _CountryPicker({
    required this.controller,
    required this.serverName,
    required this.picked,
    required this.detected,
    required this.detectedHow,
  });

  final ScrollController controller;
  final String serverName;
  final String? picked;
  final Country detected;
  final String? detectedHow;

  @override
  State<_CountryPicker> createState() => _CountryPickerState();
}

class _CountryPickerState extends State<_CountryPicker> {
  final TextEditingController _query = TextEditingController();
  final List<Country> _all = allCountries();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme s = context.colors;
    final String q = _query.text.trim().toLowerCase();
    final List<Country> list = q.isEmpty ? _all : _all.where((c) => c.name.toLowerCase().contains(q) || c.code == q).toList();
    final Widget check = Icon(Symbols.check, color: s.onSecondaryContainer);
    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(AppSpacing.space200, 0, AppSpacing.space200, AppSpacing.space300),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.space100, 0, AppSpacing.space100, AppSpacing.space50),
          child: Text('Страна сервера', style: context.text.titleLarge),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.space100, 0, AppSpacing.space100, AppSpacing.space200),
          child: Text(widget.serverName,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium!.copyWith(color: s.onSurfaceVariant)),
        ),
        TextField(
          controller: _query,
          onChanged: (_) => setState(() {}),
          style: context.text.bodyLarge,
          decoration: const InputDecoration(labelText: 'Поиск страны', prefixIcon: Icon(Symbols.search)),
        ),
        const SizedBox(height: AppSpacing.space200),
        SegmentedList(children: [
          if (q.isEmpty)
            M3ListItem(
              leading: M3ShapeIcon(
                icon: Symbols.bolt,
                shape: MaterialShapes.softBurst,
                color: s.tertiaryContainer,
                onColor: s.onTertiaryContainer,
              ),
              headline: const Text('Определять автоматически'),
              supporting: Text(widget.detected.isKnown
                  ? 'Сейчас: ${widget.detected.name}${widget.detectedHow == null ? '' : ' — ${widget.detectedHow}'}'
                  : 'По названию и проверке сервера'),
              trailing: widget.picked == null ? check : null,
              selected: widget.picked == null,
              onTap: () => Navigator.of(context).pop(''),
            ),
          for (final Country c in list)
            M3ListItem(
              leading: M3Flag(code: c.code),
              headline: Text(c.name),
              trailing: widget.picked == c.code ? check : null,
              selected: widget.picked == c.code,
              onTap: () => Navigator.of(context).pop(c.code),
            ),
        ]),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.space400),
            child: Text('Такой страны нет в списке',
                textAlign: TextAlign.center, style: context.text.bodyLarge!.copyWith(color: s.onSurfaceVariant)),
          ),
      ],
    );
  }
}
