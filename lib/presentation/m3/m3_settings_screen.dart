// Настройки темы Material 3 Expressive — раскладка как в «Расписании МИТСО»:
// small app bar M3, разделы SectionHeader и сегментированные списки
// M3ListItem; переключатели — M3Switch, нажатие по всей строке переключает
// (Lists → selection). Выбор темы — connected button group: три
// взаимоисключающих варианта (Switch → Guidelines → Usage).
//
// Пункты и иконки — те же, что у SettingsScreen.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/m3/app_spacing.dart';
import '../../core/theme/m3/app_typography.dart';
import '../../core/theme/theme_kind.dart';
import '../../infrastructure/platform_features.dart';
import '../providers/settings_provider.dart';
import '../providers/theme_provider.dart';
import '../screens/faq_screen.dart';
import '../screens/log_screen.dart';
import '../screens/split_tunneling_screen.dart';
import '../util/platform_kind.dart';
import '../widgets/m3/connected_button_group.dart';
import '../widgets/m3/m3_buttons.dart';
import '../widgets/m3/m3_flexible_app_bar.dart';
import '../widgets/m3/m3_switch.dart';
import '../widgets/m3/section_header.dart';
import '../widgets/m3/segmented_list.dart';
import '../screens/subscription_manager_screen.dart';

class M3SettingsScreen extends ConsumerWidget {
  const M3SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final AppThemeKind kind = ref.watch(themeKindProvider);
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

    M3ListItem nav(IconData icon, String title, VoidCallback onTap, {String? subtitle, String? trailing}) => M3ListItem(
          leading: Icon(icon),
          headline: Text(title),
          supporting: subtitle == null ? null : Text(subtitle),
          trailing: trailing == null
              ? Icon(Symbols.chevron_right, color: context.colors.onSurfaceVariant)
              : Text(trailing, style: context.text.labelLarge!.copyWith(color: context.colors.onSurfaceVariant)),
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
      body: M3AppBarSettle(
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
                      values: AppThemeKind.values,
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
                      toggle(Symbols.bolt, 'Автопереключение серверов',
                          'Если сервер начал подвисать или отвалился — Onyx сам перейдёт на лучший рабочий.',
                          settings.autoFailover, n.toggleAutoFailover),
                      toggle(Symbols.auto_awesome, 'Приоритет для ИИ-сервисов',
                          'ChatGPT, Claude, Gemini и др. — строго через туннель, DNS внутри него.',
                          settings.aiDirectLane, n.toggleAiDirectLane),
                      toggle(Symbols.language, 'Умная маршрутизация', 'Локальные сервисы — напрямую, остальное — через туннель.',
                          settings.smartRouting, n.toggleSmartRouting),
                      if (uiIsAndroid) ...[
                        toggle(Symbols.tune, 'Раздельный туннель', 'Выбранные приложения работают в обход VPN.',
                            settings.splitTunnelingEnabled, n.toggleSplitTunneling),
                        if (settings.splitTunnelingEnabled)
                          nav(Symbols.more_vert, 'Приложения в обход VPN', () => push(const SplitTunnelingScreen()),
                              trailing: settings.excludedApps.isEmpty ? 'Не выбраны' : '${settings.excludedApps.length}'),
                        nav(Symbols.verified_user, 'Kill switch', () => PlatformFeatures.instance.openVpnSettings(),
                            subtitle: 'Системный Always-on VPN и «Блокировать соединения без VPN».', trailing: 'Настроить'),
                      ],
                    ]),
                    const SectionHeader('Серверы'),
                    SegmentedList(children: [
                      nav(Symbols.link, 'Подписки', () => push(const SubscriptionManagerScreen()),
                          subtitle: 'Ссылки на списки серверов, обновление.'),
                    ]),
                    const SectionHeader('Диагностика'),
                    SegmentedList(children: [
                      nav(Symbols.terminal, 'Журнал', () => push(const LogScreen())),
                      nav(Symbols.help, 'Вопросы и ответы', () => push(const FaqScreen())),
                    ]),
                    const SectionHeader('О приложении'),
                    SegmentedList(children: [
                      nav(Symbols.info, 'Onyx · Z43 Studios',
                          () => launchUrl(Uri.parse('https://t.me/Orion_Z43'), mode: LaunchMode.externalApplication),
                          subtitle: 'by Orion_Z43'),
                      nav(Symbols.content_copy, 'Лицензии', () => showLicensePage(context: context, applicationName: 'Onyx'),
                          subtitle: 'Шрифты OFL, флаги и иконки MIT и Apache 2.0'),
                    ]),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
