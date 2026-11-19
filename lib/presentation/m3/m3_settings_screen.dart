// Настройки темы Material 3 Expressive — раскладка как в «Расписании МИТСО»:
// small app bar M3, разделы SectionHeader и сегментированные списки
// M3ListItem; переключатели — M3Switch, нажатие по всей строке переключает
// (Lists → selection). Выбор темы — connected button group (взаимоисключающие
// варианты, Switch → Guidelines → Usage); выбор региона — нижний лист M3.
//
// Пункты, тексты и провайдеры — те же, что у SettingsScreen тем Onyx и Signal
// (#47: Discord и регион — только здесь; #58 — автозапуск; #60 — формулировка
// автопереключения).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/m3/app_spacing.dart';
import '../../core/theme/m3/app_typography.dart';
import '../../core/theme/theme_kind.dart';
import '../../domain/entities/vpn_state.dart';
import '../../infrastructure/platform_features.dart';
import '../../infrastructure/update_service.dart';
import '../providers/autostart_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/vpn_provider.dart';
import '../providers/window_prefs_provider.dart';
import '../screens/about_screen.dart';
import '../screens/faq_screen.dart';
import '../screens/groups_screen.dart';
import '../screens/log_screen.dart';
import '../screens/settings_screen.dart' show regionHint, regionValue;
import '../screens/split_tunneling_screen.dart';
import '../screens/subscription_manager_screen.dart';
import '../util/platform_kind.dart';
import '../widgets/m3/connected_button_group.dart';
import '../widgets/m3/m3_bottom_sheet.dart';
import '../widgets/m3/m3_buttons.dart';
import '../widgets/m3/m3_flexible_app_bar.dart';
import '../widgets/m3/m3_loading_indicator.dart';
import '../widgets/m3/m3_snackbar.dart';
import '../widgets/m3/m3_switch.dart';
import '../widgets/m3/section_header.dart';
import '../widgets/m3/segmented_list.dart';

class M3SettingsScreen extends ConsumerStatefulWidget {
  const M3SettingsScreen({super.key});

  @override
  ConsumerState<M3SettingsScreen> createState() => _M3SettingsScreenState();
}

class _M3SettingsScreenState extends ConsumerState<M3SettingsScreen> {
  final GlobalKey<M3SnackbarHostState> _snackbars = GlobalKey();
  bool _udpBusy = false;
  String? _udpLast;

  void _show(String message) => _snackbars.currentState?.show(message);

  /// «Проверить UDP»: 5 STUN-запросов через туннель (~1–4 с), итог — снекбаром.
  Future<void> _checkUdp() async {
    if (_udpBusy) return;
    setState(() => _udpBusy = true);
    final r = await ref.read(vpnControllerProvider.notifier).checkUdp();
    if (!mounted) return;
    setState(() {
      _udpBusy = false;
      _udpLast = r.summary;
    });
    r.ok ? HapticFeedback.lightImpact() : HapticFeedback.heavyImpact();
    _show(r.summary);
  }

  Future<void> _pickRegion(RoutingRegion current, RoutingRegion effective) async {
    final RoutingRegion? v = await showM3ModalBottomSheet<RoutingRegion>(
      context: context,
      builder: (context, controller) => ListView(
        controller: controller,
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(AppSpacing.space200, 0, AppSpacing.space200, AppSpacing.space300),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.space100, 0, AppSpacing.space100, AppSpacing.space150),
            child: Text('Регион маршрутизации', style: context.text.titleLarge),
          ),
          SegmentedList(children: [
            for (final RoutingRegion r in RoutingRegion.values)
              M3ListItem(
                headline: Text(r.label),
                supporting: Text(regionHint(r, effective)),
                trailing: r == current ? Icon(Symbols.check, color: context.colors.onSecondaryContainer) : null,
                selected: r == current,
                onTap: () => Navigator.of(context).pop(r),
              ),
          ]),
        ],
      ),
    );
    if (v == null || v == current) return;
    HapticFeedback.selectionClick();
    await ref.read(settingsProvider.notifier).setRoutingRegion(v);
    if (mounted) _show('Регион: ${v.label} — применится при следующем подключении');
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final AppThemeKind kind = ref.watch(themeKindProvider);
    final bool connected = ref.watch(vpnControllerProvider) is VpnConnected;
    final bool? autostart = ref.watch(autostartProvider);
    final double margin = AppSpacing.screenMargin(context);

    void push(Widget screen) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

    M3ListItem toggle(IconData icon, String title, String subtitle, bool value, ValueChanged<bool> onChanged) => M3ListItem(
          leading: Icon(icon),
          headline: Text(title),
          supporting: Text(subtitle),
          trailing: ExcludeSemantics(child: M3Switch(value: value, onChanged: onChanged)),
          onTap: () => onChanged(!value),
          semanticsLabel: '$title, ${value ? 'включено' : 'выключено'}',
        );

    M3ListItem nav(IconData icon, String title, VoidCallback onTap, {String? subtitle, String? trailing, Widget? trailingWidget}) =>
        M3ListItem(
          leading: Icon(icon),
          headline: Text(title),
          supporting: subtitle == null ? null : Text(subtitle),
          trailing: trailingWidget ??
              (trailing == null
                  ? Icon(Symbols.chevron_right, color: context.colors.onSurfaceVariant)
                  : Text(trailing, style: context.text.labelLarge!.copyWith(color: context.colors.onSurfaceVariant))),
          onTap: onTap,
        );

    return Scaffold(
      appBar: M3SmallAppBar(
        title: 'Настройки',
        leading: M3IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Symbols.arrow_back),
          tooltip: 'Назад',
          color: M3IconButtonColor.standard,
        ),
      ),
      body: M3SnackbarHost(
        key: _snackbars,
        child: M3AppBarSettle(
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(margin, 0, margin, AppSpacing.space400),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const SectionHeader('Оформление'),
                      ConnectedButtonGroup<AppThemeKind>(
                        values: AppThemeKind.selectable,
                        labelOf: (k) => k.label,
                        selected: kind,
                        onSelected: (k) {
                          HapticFeedback.selectionClick();
                          ref.read(themeKindProvider.notifier).set(k);
                        },
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.space200, AppSpacing.space100, AppSpacing.space200, 0),
                        child: Text(
                          kind.description,
                          style: context.text.bodyMedium!.copyWith(color: context.colors.onSurfaceVariant),
                        ),
                      ),
                      const SectionHeader('Защита'),
                      SegmentedList(children: [
                        toggle(
                          Symbols.bolt,
                          'Автоматически менять сервер при ухудшении',
                          'Если сервер начал подвисать, Onyx перепроверит запасные и перейдёт на заметно более быстрый. '
                              'Сервер, выбранный вручную, не меняется.',
                          settings.autoFailover,
                          n.toggleAutoFailover,
                        ),
                        toggle(Symbols.auto_awesome, 'Приоритет для ИИ-сервисов',
                            'ChatGPT, Claude, Gemini и др. — строго через туннель, DNS внутри него.', settings.aiDirectLane, n.toggleAiDirectLane),
                        toggle(Symbols.language, 'Умная маршрутизация', 'Локальные сервисы — напрямую, остальное — через туннель.',
                            settings.smartRouting, n.toggleSmartRouting),
                        if (settings.smartRouting)
                          nav(
                            Symbols.public,
                            'Регион маршрутизации',
                            () => _pickRegion(settings.routingRegion, settings.effectiveRegion),
                            subtitle: 'Сайты этой страны — напрямую, мимо туннеля.',
                            trailing: regionValue(settings.routingRegion, settings.effectiveRegion),
                          ),
                        toggle(Symbols.mic, 'Режим Discord', 'Голос и звонки Discord — через туннель по UDP. По умолчанию включён.',
                            settings.discordMode, n.toggleDiscordMode),
                        nav(
                          Symbols.network_check,
                          'Проверить UDP (голос)',
                          _checkUdp,
                          subtitle: _udpLast ?? (connected ? 'STUN через туннель, пара секунд' : 'Нужно активное подключение'),
                          trailingWidget: _udpBusy
                              ? const SizedBox.square(dimension: 24, child: M3LoadingIndicator(semanticsLabel: 'Проверяем UDP'))
                              : null,
                        ),
                        if (uiIsAndroid) ...[
                          toggle(Symbols.tune, 'Раздельный туннель', 'Выбранные приложения работают в обход VPN.',
                              settings.splitTunnelingEnabled, n.toggleSplitTunneling),
                          if (settings.splitTunnelingEnabled)
                            nav(Symbols.apps, 'Приложения в обход VPN', () => push(const SplitTunnelingScreen()),
                                trailing: settings.excludedApps.isEmpty ? 'Не выбраны' : '${settings.excludedApps.length}'),
                          nav(Symbols.verified_user, 'Kill switch', () => PlatformFeatures.instance.openVpnSettings(),
                              subtitle: 'Системный Always-on VPN и «Блокировать соединения без VPN».', trailing: 'Настроить'),
                        ],
                      ]),
                      if (uiIsWindows) ...[
                        const SectionHeader('Запуск'),
                        SegmentedList(children: [
                          // Автозапуск (#58): HKCU\…\Run, прав не нужно; null — реестр ещё читается.
                          if (autostart != null)
                            toggle(Symbols.power_settings_new, 'Запускать Onyx при входе в Windows',
                                'Onyx стартует вместе с системой и сразу уходит в трей.', autostart,
                                (v) => ref.read(autostartProvider.notifier).set(v)),
                          toggle(Symbols.minimize, 'Запускать свёрнутым в трей', 'Onyx стартует без окна; открыть — кликом по лисе в трее.',
                              ref.watch(startMinimizedProvider), (v) => ref.read(startMinimizedProvider.notifier).set(v)),
                        ]),
                      ],
                      const SectionHeader('Серверы'),
                      SegmentedList(children: [
                        nav(Symbols.link, 'Подписки и серверы', () => push(const SubscriptionManagerScreen()),
                            subtitle: 'Источники: подписки и ссылки, обновление, встроенные пресеты.'),
                        nav(Symbols.folder, 'Группы', () => push(const GroupsScreen()), subtitle: 'Свои наборы серверов и группа для автовыбора.'),
                      ]),
                      const SectionHeader('Диагностика'),
                      SegmentedList(children: [
                        nav(Symbols.terminal, 'Журнал', () => push(const LogScreen())),
                        nav(Symbols.help, 'Вопросы и ответы', () => push(const FaqScreen())),
                      ]),
                      const SectionHeader('О приложении'),
                      SegmentedList(children: [
                        nav(Symbols.info, 'О программе', () => push(const AboutScreen()),
                            subtitle: 'Onyx ${UpdateService.currentVersion} · Z43 Studios'),
                        nav(Symbols.license, 'Лицензии', () => showLicensePage(context: context, applicationName: 'Onyx'),
                            subtitle: 'Шрифты OFL, флаги и иконки MIT и Apache 2.0'),
                      ]),
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
