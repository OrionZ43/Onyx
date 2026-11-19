// «Подписки и серверы» в теме Material 3 Expressive (#40): small app bar M3,
// источники — сегментированный список (тип в форме, имя, состояние,
// переключатель «включён»), встроенные подписки — тот же список, extended FAB
// «Добавить» (лист добавления общий), действия источника — нижний лист M3,
// подтверждения — диалог M3.
//
// Провайдеры и действия — те же, что у SubscriptionManagerScreen тем Onyx и
// Signal (sourcesProvider: refresh / rename / setAutoUpdate / remove /
// setEnabled / exportJson / importJson; loadPreset).

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/m3/app_spacing.dart';
import '../../core/theme/m3/app_typography.dart';
import '../providers/settings_provider.dart';
import '../providers/sources_provider.dart';
import '../providers/subscription_provider.dart';
import '../screens/groups_screen.dart';
import '../widgets/add_source_sheet.dart';
import '../widgets/m3/empty_state.dart';
import '../widgets/m3/m3_bottom_sheet.dart';
import '../widgets/m3/m3_buttons.dart';
import '../widgets/m3/m3_fab.dart';
import '../widgets/m3/m3_flexible_app_bar.dart';
import '../widgets/m3/m3_loading_indicator.dart';
import '../widgets/m3/m3_snackbar.dart';
import '../widgets/m3/m3_switch.dart';
import '../widgets/m3/section_header.dart';
import '../widgets/m3/segmented_list.dart';
import '../widgets/preset_tile.dart' show loadPreset;
import 'm3_parts.dart';

class M3SubscriptionsScreen extends ConsumerStatefulWidget {
  const M3SubscriptionsScreen({super.key});

  @override
  ConsumerState<M3SubscriptionsScreen> createState() => _M3SubscriptionsScreenState();
}

String _plural(int n, String one, String few, String many) {
  final int d = n % 10, h = n % 100;
  if (d == 1 && h != 11) return one;
  if (d >= 2 && d <= 4 && (h < 12 || h > 14)) return few;
  return many;
}

String _ago(Duration d) {
  if (d.inMinutes < 1) return 'только что';
  if (d.inHours < 1) return '${d.inMinutes} мин назад';
  if (d.inDays < 1) return '${d.inHours} ч назад';
  return '${d.inDays} дн назад';
}

/// Название в диалоге M3: переименование источника.
Future<String?> _askName(BuildContext context, String current) =>
    showDialog<String>(context: context, builder: (_) => _NameDialog(current: current));

/// Диалог сам владеет полем: контроллер живёт, пока диалог на экране, в том
/// числе во время анимации закрытия.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.current});
  final String current;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _ctl = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Название'),
        content: TextField(
          controller: _ctl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Название источника'),
          // Enter — «Сохранить», как в диалоге Onyx.
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          M3Button(onPressed: () => Navigator.pop(context), color: M3ButtonColor.text, child: const Text('Отмена')),
          M3Button(onPressed: () => Navigator.pop(context, _ctl.text), color: M3ButtonColor.text, child: const Text('Сохранить')),
        ],
      );
}

class _M3SubscriptionsScreenState extends ConsumerState<M3SubscriptionsScreen> {
  final GlobalKey<M3SnackbarHostState> _snackbars = GlobalKey();

  void _show(String m) => _snackbars.currentState?.show(m);

  Future<void> _refreshAll() async {
    HapticFeedback.lightImpact();
    final report = await ref.read(sourcesProvider.notifier).refreshAll();
    if (mounted) _show(report.summary);
  }

  /// «Ещё»: группы и перенос настроек (источники, группы, избранное) через буфер.
  Future<void> _more() async {
    final String? v = await showM3ModalBottomSheet<String>(
      context: context,
      builder: (context, controller) => ListView(
        controller: controller,
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(AppSpacing.space200, 0, AppSpacing.space200, AppSpacing.space300),
        children: [
          SegmentedList(children: [
            M3ListItem(leading: const Icon(Symbols.folder), headline: const Text('Группы'), onTap: () => Navigator.pop(context, 'groups')),
            M3ListItem(
              leading: const Icon(Symbols.content_copy),
              headline: const Text('Скопировать настройки'),
              supporting: const Text('Источники, группы и избранное — в буфер'),
              onTap: () => Navigator.pop(context, 'export'),
            ),
            M3ListItem(
              leading: const Icon(Symbols.content_paste),
              headline: const Text('Вставить настройки'),
              supporting: const Text('Из буфера, скопированные на другом устройстве'),
              onTap: () => Navigator.pop(context, 'import'),
            ),
          ]),
        ],
      ),
    );
    if (v == null || !mounted) return;
    final SourcesController ctl = ref.read(sourcesProvider.notifier);
    switch (v) {
      case 'groups':
        Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GroupsScreen()));
      case 'export':
        await Clipboard.setData(ClipboardData(text: ctl.exportJson()));
        _show('Источники, группы и избранное скопированы');
      case 'import':
        final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
        final String text = data?.text ?? '';
        if (text.trim().isEmpty) return _show('В буфере пусто');
        final r = await ctl.importJson(text);
        if (mounted) _show(r.error ?? 'Добавлено: источников ${r.sources}, групп ${r.groups}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<SubscriptionSource> sources = ref.watch(sourcesProvider);
    final int total = ref.watch(subscriptionProvider.select((s) => s.nodes.length));
    final double margin = AppSpacing.screenMargin(context);
    final bool chinaActive = sources.any((s) => s.presetId == SubscriptionPresets.chinaFree.id);
    final bool needChina = chinaActive && ref.watch(settingsProvider.select((s) => s.effectiveRegion)) != RoutingRegion.china;

    return Scaffold(
      appBar: M3SmallAppBar(
        title: 'Подписки и серверы',
        leading: M3IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Symbols.arrow_back),
          tooltip: 'Назад',
          color: M3IconButtonColor.standard,
        ),
        actions: [
          M3IconButton(onPressed: _refreshAll, icon: const Icon(Symbols.refresh), tooltip: 'Обновить все', color: M3IconButtonColor.standard),
          M3IconButton(onPressed: _more, icon: const Icon(Symbols.more_vert), tooltip: 'Ещё', color: M3IconButtonColor.standard),
        ],
      ),
      floatingActionButton: M3ExtendedFab(
        onPressed: () => showAddSourceSheet(context),
        icon: const Icon(Symbols.add),
        label: 'Добавить',
      ),
      body: M3SnackbarHost(
        key: _snackbars,
        // Над extended FAB «Добавить» (56dp + поле 16dp + зазор).
        bottomPadding: 80,
        child: M3AppBarSettle(
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(margin, 0, margin, 96),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      SectionHeader('Источники · ${sources.length} · $total ${_plural(total, 'сервер', 'сервера', 'серверов')}'),
                      if (sources.isEmpty)
                        const EmptyState(
                          title: 'Источников пока нет',
                          description: 'Добавьте подписку по ссылке или вставьте ссылки серверов.',
                        )
                      else
                        SegmentedList(children: [for (final SubscriptionSource s in sources) _SourceItem(source: s, onMessage: _show)]),
                      const SectionHeader('Встроенные'),
                      SegmentedList(children: [for (final SubscriptionPreset p in SubscriptionPresets.all) M3PresetItem(preset: p)]),
                      if (needChina) ...[
                        const SizedBox(height: AppSpacing.space100),
                        Card.filled(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(AppSpacing.space200, AppSpacing.space50, AppSpacing.space100, AppSpacing.space50),
                            child: Row(children: [
                              Icon(Symbols.public, color: context.colors.onSurfaceVariant),
                              const SizedBox(width: AppSpacing.space150),
                              Expanded(
                                child: Text('Для Китая включите регион маршрутизации «Китай»: китайские сайты пойдут напрямую.',
                                    style: context.text.bodyMedium),
                              ),
                              M3Button(
                                onPressed: () {
                                  ref.read(settingsProvider.notifier).setRoutingRegion(RoutingRegion.china);
                                  _show('Регион «Китай» включён — применится при подключении');
                                },
                                color: M3ButtonColor.text,
                                child: const Text('Включить'),
                              ),
                            ]),
                          ),
                        ),
                      ],
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Источник: тип в форме (подписка — круг, ссылки — «свои», Cookie6Sided), имя,
/// состояние; переключатель «включён». Нажатие — действия в нижнем листе.
class _SourceItem extends ConsumerWidget {
  const _SourceItem({required this.source, required this.onMessage});
  final SubscriptionSource source;
  final ValueChanged<String> onMessage;

  Future<void> _actions(BuildContext context, WidgetRef ref) async {
    final SourcesController ctl = ref.read(sourcesProvider.notifier);
    final ColorScheme s = context.colors;
    final String? v = await showM3ModalBottomSheet<String>(
      context: context,
      builder: (context, controller) => ListView(
        controller: controller,
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(AppSpacing.space200, 0, AppSpacing.space200, AppSpacing.space300),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.space100, 0, AppSpacing.space100, AppSpacing.space150),
            child: Text(source.name, style: context.text.titleLarge),
          ),
          SegmentedList(children: [
            M3ListItem(leading: const Icon(Symbols.refresh), headline: const Text('Обновить'), onTap: () => Navigator.pop(context, 'refresh')),
            M3ListItem(leading: const Icon(Symbols.edit), headline: const Text('Переименовать'), onTap: () => Navigator.pop(context, 'rename')),
            // Тот же переключатель, что в строке, — пунктом: доступен и со скринридером.
            M3ListItem(
              leading: Icon(source.enabled ? Symbols.toggle_off : Symbols.toggle_on),
              headline: Text(source.enabled ? 'Выключить' : 'Включить'),
              supporting: Text(source.enabled ? 'Серверы источника пропадут из списка, пока не включите' : 'Серверы источника вернутся в список'),
              onTap: () => Navigator.pop(context, 'toggle'),
            ),
            M3ListItem(
              leading: const Icon(Symbols.schedule),
              headline: const Text('Автообновление'),
              supporting: Text(source.autoUpdateHours == 0 ? 'Выключено' : 'Каждые ${source.autoUpdateHours} ч'),
              onTap: () => Navigator.pop(context, 'auto'),
            ),
            if (source.url != null)
              M3ListItem(leading: const Icon(Symbols.content_copy), headline: const Text('Скопировать ссылку'), onTap: () => Navigator.pop(context, 'copy')),
            M3ListItem(
              leading: Icon(Symbols.delete, color: s.error),
              headline: Text('Удалить', style: TextStyle(color: s.error)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ]),
        ],
      ),
    );
    if (v == null || !context.mounted) return;
    switch (v) {
      case 'refresh':
        ctl.refresh(source.id);
      case 'toggle':
        ctl.setEnabled(source.id, !source.enabled);
      case 'rename':
        final String? name = await _askName(context, source.name);
        if (name != null && name.trim().isNotEmpty) ctl.rename(source.id, name.trim());
      case 'auto':
        final int next = switch (source.autoUpdateHours) { 0 => 6, 6 => 24, _ => 0 };
        ctl.setAutoUpdate(source.id, next);
        onMessage(next == 0 ? 'Автообновление выключено' : 'Обновлять каждые $next ч');
      case 'copy':
        await Clipboard.setData(ClipboardData(text: source.url!));
        onMessage('Ссылка скопирована');
      case 'delete':
        final bool? ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            icon: const Icon(Symbols.delete),
            title: Text('Удалить «${source.name}»?'),
            content: const Text('Серверы этого источника пропадут из списка и групп.'),
            actions: [
              M3Button(onPressed: () => Navigator.pop(c, false), color: M3ButtonColor.text, child: const Text('Отмена')),
              M3Button(onPressed: () => Navigator.pop(c, true), color: M3ButtonColor.text, child: const Text('Удалить')),
            ],
          ),
        );
        if (ok == true) ctl.remove(source.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme s = context.colors;
    final SourcesController ctl = ref.read(sourcesProvider.notifier);
    final int alive = ref.watch(subscriptionProvider.select((x) => x.nodes.where((n) => n.sourceIds.contains(source.id) && n.isAlive).length));
    final bool busy = source.status == SourceStatus.fetching;
    final bool links = source.kind == SourceKind.links;
    final String status = busy
        ? 'Загружается…'
        : source.status == SourceStatus.error
            ? 'Ошибка${source.error == null ? '' : ': ${source.error}'}'
            : '$alive из ${source.nodeCount} работают'
                '${source.lastUpdatedAt == null ? '' : ' · ${_ago(DateTime.now().difference(source.lastUpdatedAt!))}'}';
    final String what = links
        ? '${source.nodeCount} ${_plural(source.nodeCount, 'ссылка', 'ссылки', 'ссылок')}'
        : (Uri.tryParse(source.url ?? '')?.host ?? source.url ?? 'Подписка');
    return M3ListItem(
      leading: M3ShapeIcon(
        icon: links ? Symbols.link : Symbols.rss_feed,
        shape: links ? MaterialShapes.cookie6Sided : MaterialShapes.circle,
        color: links ? s.secondaryContainer : s.primaryContainer,
        onColor: links ? s.onSecondaryContainer : s.onPrimaryContainer,
      ),
      overline: Text(links ? 'Ссылки · $what' : 'Подписка · $what', maxLines: 1, overflow: TextOverflow.ellipsis),
      headline: Text(source.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      supporting: Text(source.enabled ? status : 'Выключен · $status',
          style: source.status == SourceStatus.error ? TextStyle(color: s.error) : null, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: busy
          ? const SizedBox.square(dimension: 24, child: M3LoadingIndicator(semanticsLabel: 'Загружается'))
          : ExcludeSemantics(child: M3Switch(value: source.enabled, onChanged: (v) => ctl.setEnabled(source.id, v))),
      onTap: () => _actions(context, ref),
      semanticsLabel: '${source.name}, $status, ${source.enabled ? 'включён' : 'выключен'}',
      semanticsActions: busy ? null : {
        CustomSemanticsAction(label: source.enabled ? 'Выключить' : 'Включить'): () => ctl.setEnabled(source.id, !source.enabled),
      },
    );
  }
}

/// Встроенная подписка: флаг (Китай) или глобус, название, честная подпись;
/// «Добавить» или отметка, если уже добавлена (loadPreset — общий).
class M3PresetItem extends ConsumerWidget {
  const M3PresetItem({super.key, required this.preset});
  final SubscriptionPreset preset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme s = context.colors;
    final SubscriptionSource? src = ref.watch(sourcesProvider).where((x) => x.presetId == preset.id).firstOrNull;
    final bool active = src != null;
    final bool busy = src?.status == SourceStatus.fetching;
    final bool china = preset.id == SubscriptionPresets.chinaFree.id;
    return M3ListItem(
      leading: M3Flag(code: china ? 'cn' : ''),
      headline: Text(preset.title),
      supporting: Text(preset.subtitle),
      trailing: busy
          ? const SizedBox.square(dimension: 24, child: M3LoadingIndicator(semanticsLabel: 'Загружается'))
          : active
              ? Icon(Symbols.check, color: s.primary)
              : M3Button(
                  onPressed: () => loadPreset(context, ref, preset),
                  color: M3ButtonColor.tonal,
                  size: M3ButtonSize.small,
                  child: const Text('Добавить'),
                ),
      onTap: active ? null : () => loadPreset(context, ref, preset),
      semanticsLabel: '${preset.title}, ${active ? 'добавлена' : 'не добавлена'}',
    );
  }
}
