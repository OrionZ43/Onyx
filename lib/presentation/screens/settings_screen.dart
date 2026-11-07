
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_new_shapes/material_new_shapes.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/onyx_tokens.dart';
import '../../core/theme/theme_kind.dart';
import '../../infrastructure/platform_features.dart';
import '../../domain/entities/vpn_state.dart';
import '../providers/settings_provider.dart';
import '../providers/vpn_provider.dart';
import '../widgets/onyx_toast.dart';
import '../providers/theme_provider.dart';
import '../providers/window_prefs_provider.dart';
import '../util/platform_kind.dart';
import '../widgets/country_flag.dart' show PolygonClipper;
import '../widgets/onyx_icon.dart';
import '../widgets/onyx_switch.dart';
import '../../infrastructure/update_service.dart';
import 'about_screen.dart';
import 'faq_screen.dart';
import 'groups_screen.dart';
import 'log_screen.dart';
import 'split_tunneling_screen.dart';
import 'subscription_manager_screen.dart';

/// Настройки. Здесь живёт всё, что убрано с главного экрана: оформление,
/// защита (AI, автопереключение, split tunneling, kill switch), подписки,
/// логи и справка.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = OnyxTokens.of(context);
    final settings = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final kind = ref.watch(themeKindProvider);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        leading: IconButton(
          tooltip: 'Назад',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: OnyxIcon(OnyxGlyph.back, size: t.isMaterial ? 24 : 18, color: t.isMaterial ? null : t.text),
        ),
        title: Text(
          'Настройки',
          style: t.isMaterial
              ? null
              : TextStyle(fontFamily: t.displayFont, fontSize: 20, fontWeight: t.isSignal ? FontWeight.w500 : FontWeight.w400, color: t.text),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: EdgeInsets.fromLTRB(t.isMaterial ? 16 : 20, 4, t.isMaterial ? 16 : 20, 32),
            children: [
              const _Section('Оформление'),
              _ThemePicker(
                value: kind,
                onChanged: (k) {
                  HapticFeedback.selectionClick();
                  ref.read(themeKindProvider.notifier).set(k);
                },
              ),
              const _Section('Защита'),
              _Group(children: [
                _SwitchTile(
                  glyph: OnyxGlyph.zap,
                  title: 'Автопереключение серверов',
                  subtitle: 'Если сервер начал подвисать или отвалился — Onyx сам перейдёт на лучший рабочий.',
                  value: settings.autoFailover,
                  onChanged: n.toggleAutoFailover,
                ),
                _SwitchTile(
                  glyph: OnyxGlyph.ai,
                  title: 'Приоритет для ИИ-сервисов',
                  subtitle: 'ChatGPT, Claude, Gemini и др. — строго через туннель, DNS внутри него.',
                  value: settings.aiDirectLane,
                  onChanged: n.toggleAiDirectLane,
                ),
                _SwitchTile(
                  glyph: OnyxGlyph.globe,
                  title: 'Умная маршрутизация',
                  subtitle: 'Локальные сервисы — напрямую, остальное — через туннель.',
                  value: settings.smartRouting,
                  onChanged: n.toggleSmartRouting,
                ),
                if (settings.smartRouting)
                  const _RegionTile(),
                _SwitchTile(
                  glyph: OnyxGlyph.voice,
                  title: 'Режим Discord',
                  subtitle: 'Голос и звонки Discord — через туннель по UDP. По умолчанию включён.',
                  value: settings.discordMode,
                  onChanged: n.toggleDiscordMode,
                ),
                const _UdpCheckTile(),
                if (uiIsAndroid) ...[
                  _SwitchTile(
                    glyph: OnyxGlyph.sliders,
                    title: 'Раздельный туннель',
                    subtitle: 'Выбранные приложения работают в обход VPN.',
                    value: settings.splitTunnelingEnabled,
                    onChanged: n.toggleSplitTunneling,
                  ),
                  if (settings.splitTunnelingEnabled)
                    _NavTile(
                      glyph: OnyxGlyph.more,
                      title: 'Приложения в обход VPN',
                      trailing: settings.excludedApps.isEmpty ? 'Не выбраны' : '${settings.excludedApps.length}',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SplitTunnelingScreen())),
                    ),
                  _NavTile(
                    glyph: OnyxGlyph.shield,
                    title: 'Kill switch',
                    subtitle: 'Системный Always-on VPN и «Блокировать соединения без VPN».',
                    trailing: 'Настроить',
                    onTap: () => PlatformFeatures.instance.openVpnSettings(),
                  ),
                ],
              ]),
              if (uiIsWindows) ...[
                const _Section('Окно'),
                _Group(children: [
                  _SwitchTile(
                    glyph: OnyxGlyph.minimize,
                    title: 'Запускать свёрнутым в трей',
                    subtitle: 'Onyx стартует без окна; открыть — кликом по лисе в трее.',
                    value: ref.watch(startMinimizedProvider),
                    onChanged: (v) => ref.read(startMinimizedProvider.notifier).set(v),
                  ),
                ]),
              ],
              const _Section('Серверы'),
              _Group(children: [
                _NavTile(
                  glyph: OnyxGlyph.link,
                  title: 'Подписки и серверы',
                  subtitle: 'Источники: подписки и ссылки, обновление, встроенные пресеты.',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SubscriptionManagerScreen())),
                ),
                _NavTile(
                  glyph: OnyxGlyph.star,
                  title: 'Группы',
                  subtitle: 'Свои наборы серверов и группа для автовыбора.',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GroupsScreen())),
                ),
              ]),
              const _Section('Диагностика'),
              _Group(children: [
                _NavTile(
                  glyph: OnyxGlyph.terminal,
                  title: 'Журнал',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LogScreen())),
                ),
                _NavTile(
                  glyph: OnyxGlyph.help,
                  title: 'Вопросы и ответы',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FaqScreen())),
                ),
              ]),
              const _Section('О приложении'),
              _Group(children: [
                _NavTile(
                  glyph: OnyxGlyph.info,
                  title: 'О программе',
                  subtitle: 'Onyx ${UpdateService.currentVersion} · Z43 Studios',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutScreen())),
                ),
                _NavTile(
                  glyph: OnyxGlyph.copy,
                  title: 'Лицензии',
                  subtitle: 'Шрифты OFL, флаги и иконки MIT',
                  onTap: () => showLicensePage(context: context, applicationName: 'Onyx'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Выбор темы ──────────────────────────────────────────────────────────────

class _ThemePicker extends StatelessWidget {
  const _ThemePicker({required this.value, required this.onChanged});
  final AppThemeKind value;
  final ValueChanged<AppThemeKind> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final narrow = box.maxWidth < 420;
      final cards = [
        for (final k in AppThemeKind.values)
          _ThemeCard(kind: k, selected: k == value, onTap: () => onChanged(k)),
      ];
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) SizedBox(width: narrow ? 8 : 12),
            Expanded(child: cards[i]),
          ],
        ],
      );
    });
  }
}

/// Карточка темы с мини-превью её главной кнопки — в цветах самой темы.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({required this.kind, required this.selected, required this.onTap});
  final AppThemeKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final preview = switch (kind) {
      AppThemeKind.onyx => _PreviewOnyx(),
      AppThemeKind.signal => _PreviewSignal(),
      AppThemeKind.material => _PreviewMaterial(),
    };
    final bg = switch (kind) {
      AppThemeKind.onyx => AppTheme.onyxTokens.bg,
      AppThemeKind.signal => AppTheme.signalTokens.bg,
      AppThemeKind.material => const Color(0xFF141218),
    };
    final radius = BorderRadius.circular(t.isMaterial ? 20 : (t.isSignal ? 20 : 16));
    return Semantics(
      selected: selected,
      button: true,
      label: 'Тема ${kind.label}',
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              height: 116,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: radius,
                border: Border.all(
                  color: selected ? (t.isSignal ? AppTheme.signalRec : t.accent) : t.line,
                  width: selected ? 2 : 1,
                ),
              ),
              alignment: Alignment.center,
              child: preview,
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Text(
                  t.isSignal ? kind.label.toUpperCase() : kind.label,
                  style: t.isSignal
                      ? t.caps(size: 11, color: selected ? t.text : t.textMuted)
                      : TextStyle(fontFamily: t.bodyFont, fontSize: 14, fontWeight: FontWeight.w500, color: selected ? t.text : t.textMuted),
                ),
              ),
              if (selected) OnyxIcon(OnyxGlyph.check, size: 16, color: t.isSignal ? AppTheme.signalRec : t.accent),
            ]),
            const SizedBox(height: 2),
            Text(kind.description,
                maxLines: 2,
                style: TextStyle(fontFamily: t.bodyFont, fontSize: 11.5, height: 1.3, color: t.textFaint)),
          ],
        ),
      ),
    );
  }
}

class _PreviewOnyx extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(center: Alignment(0, -1), radius: 1.1, colors: [Color(0xFF1F1D19), Color(0xFF070706)]),
          border: Border.all(color: const Color(0xFFD2B98F), width: 1.2),
          boxShadow: const [BoxShadow(color: Color(0x33D2B98F), blurRadius: 18)],
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.power_settings_new_rounded, size: 18, color: Color(0xFFD2B98F)),
      );
}

class _PreviewSignal extends StatelessWidget {
  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size.square(70), painter: _MiniDotRing());
}

class _MiniDotRing extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const n = 28;
    for (var i = 0; i < n; i++) {
      final a = i / n * 6.2831853 - 1.5707963;
      canvas.drawCircle(
        c + Offset(_cos(a), _sin(a)) * (size.width / 2 - 3),
        i == 0 ? 2.6 : 1.9,
        Paint()..color = i == 0 ? AppTheme.signalRec : Colors.white,
      );
    }
  }

  static double _cos(double a) => math.cos(a);
  static double _sin(double a) => math.sin(a);

  @override
  bool shouldRepaint(_MiniDotRing old) => false;
}

class _PreviewMaterial extends StatelessWidget {
  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: 68,
        child: Stack(alignment: Alignment.center, children: [
          ClipPath(
            clipper: PolygonClipper(MaterialShapes.cookie9Sided),
            child: const ColoredBox(color: Color(0xFF4F378B), child: SizedBox.expand()),
          ),
          const Icon(Icons.power_settings_new_rounded, size: 22, color: Color(0xFFEADDFF)),
        ]),
      );
}

// ── Плитки ──────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(t.isMaterial ? 16 : 4, 28, 4, 12),
      child: Text(
        t.isMaterial ? title : title.toUpperCase(),
        style: t.isMaterial
            ? Theme.of(context).textTheme.titleSmall!.copyWith(color: Theme.of(context).colorScheme.primary)
            : t.caps(size: 10.5, color: t.textFaint),
      ),
    );
  }
}

/// Группа плиток: Onyx — карточка с хайрлайнами, Signal — плитки без обводок,
/// Material — сегментированный список (радиусы 20 по краям, 4 внутри).
class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    if (t.isOnyx) {
      return Container(
        decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(t.radiusCard), border: Border.all(color: t.line)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 56, color: t.line),
            children[i],
          ],
        ]),
      );
    }
    final r = t.isMaterial ? 20.0 : 22.0, inner = t.isMaterial ? 4.0 : 8.0;
    return Column(children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) SizedBox(height: t.isMaterial ? 2 : 6),
        ClipRRect(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(i == 0 ? r : inner),
            bottom: Radius.circular(i == children.length - 1 ? r : inner),
          ),
          child: ColoredBox(color: t.surface, child: children[i]),
        ),
      ],
    ]);
  }
}

class _Leading extends StatelessWidget {
  const _Leading(this.glyph);
  final OnyxGlyph glyph;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    if (t.isMaterial) {
      final s = Theme.of(context).colorScheme;
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: s.secondaryContainer, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Icon(glyph.material, size: 20, color: s.onSecondaryContainer),
      );
    }
    return SizedBox(width: 24, child: OnyxIcon(glyph, size: 18, color: t.isSignal ? t.text : t.textMuted));
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({required this.glyph, required this.title, required this.subtitle, required this.value, required this.onChanged});
  final OnyxGlyph glyph;
  final String title, subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => _Tile(
        glyph: glyph,
        title: title,
        subtitle: subtitle,
        trailing: OnyxSwitch(value: value, onChanged: onChanged),
        onTap: () => onChanged(!value),
      );
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.glyph, required this.title, this.subtitle, this.trailing, required this.onTap});
  final OnyxGlyph glyph;
  final String title;
  final String? subtitle, trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    return _Tile(
      glyph: glyph,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (trailing != null)
          Text(t.isSignal ? trailing!.toUpperCase() : trailing!,
              style: t.isSignal ? t.caps(size: 10.5) : TextStyle(fontFamily: t.bodyFont, fontSize: 13, color: t.textMuted)),
        const SizedBox(width: 6),
        OnyxIcon(OnyxGlyph.chevronRight, size: t.isMaterial ? 24 : 16, color: t.textFaint),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.glyph, required this.title, this.subtitle, required this.trailing, required this.onTap});
  final OnyxGlyph glyph;
  final String title;
  final String? subtitle;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: t.isMaterial ? 12 : 14),
        child: Row(children: [
          _Leading(glyph),
          SizedBox(width: t.isMaterial ? 16 : 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: t.isMaterial
                      ? text.titleMedium
                      : TextStyle(fontFamily: t.bodyFont, fontSize: t.isSignal ? 15.5 : 14.5, fontWeight: FontWeight.w500, color: t.text)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!,
                    style: t.isMaterial
                        ? text.bodyMedium!.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)
                        : TextStyle(fontFamily: t.bodyFont, fontSize: 12.5, height: 1.35, color: t.textMuted)),
              ],
            ]),
          ),
          const SizedBox(width: 12),
          trailing,
        ]),
      ),
    );
  }
}

// ── Регион и проверка UDP (#34/#35) ─────────────────────────────────────────

/// Регион маршрутизации (#47): пункт со значением, выбор — в листе. По
/// умолчанию — «Авто» (домен «Оникс»: часовой пояс и язык системы; для РФ и
/// Беларуси — РФ/РБ); на главном экране и в мини-панели регион не показан.
class _RegionTile extends ConsumerWidget {
  const _RegionTile();

  static String _short(RoutingRegion r) => switch (r) {
        RoutingRegion.auto => 'Авто',
        RoutingRegion.russia => 'РФ/РБ',
        RoutingRegion.china => 'Китай',
      };

  /// Подпись варианта; для «Авто» — во что он сейчас развернулся.
  static String _hint(RoutingRegion r, RoutingRegion effective) => switch (r) {
        RoutingRegion.auto => 'По часовому поясу и языку системы · сейчас ${_short(effective)}',
        RoutingRegion.russia => 'Российские и белорусские сайты — напрямую',
        RoutingRegion.china => 'Китайские сайты и сервисы — напрямую',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final region = s.routingRegion;
    return _NavTile(
      glyph: OnyxGlyph.globe,
      title: 'Регион маршрутизации',
      subtitle: 'Сайты этой страны — напрямую, мимо туннеля.',
      trailing: region == RoutingRegion.auto ? 'Авто · ${_short(s.effectiveRegion)}' : _short(region),
      onTap: () => _pick(context, ref, region, s.effectiveRegion),
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref, RoutingRegion current, RoutingRegion effective) async {
    final t = OnyxTokens.of(context);
    final v = await showModalBottomSheet<RoutingRegion>(
      context: context,
      backgroundColor: t.isMaterial ? null : t.surface,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(t.isSignal ? 'РЕГИОН МАРШРУТИЗАЦИИ' : 'Регион маршрутизации',
                style: t.isSignal ? t.caps(size: 11) : TextStyle(fontFamily: t.displayFont, fontSize: 18, color: t.text)),
          ),
          for (final r in RoutingRegion.values)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              title: Text(r.label, style: TextStyle(fontFamily: t.bodyFont, fontSize: 14.5, fontWeight: FontWeight.w500, color: t.text)),
              subtitle: Text(_hint(r, effective), style: TextStyle(fontFamily: t.bodyFont, fontSize: 12.5, color: t.textMuted)),
              trailing: r == current ? OnyxIcon(OnyxGlyph.check, size: 18, color: t.isSignal ? AppTheme.signalRec : t.accent) : null,
              onTap: () => Navigator.pop(c, r),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (v == null || v == current) return;
    HapticFeedback.selectionClick();
    await ref.read(settingsProvider.notifier).setRoutingRegion(v);
    if (context.mounted) showOnyxToast(context, 'Регион: ${v.label} — применится при следующем подключении', glyph: OnyxGlyph.globe);
  }
}

/// «Проверить UDP»: 5 STUN-запросов через туннель (~1–4 с), итог — в тосте.
class _UdpCheckTile extends ConsumerStatefulWidget {
  const _UdpCheckTile();

  @override
  ConsumerState<_UdpCheckTile> createState() => _UdpCheckTileState();
}

class _UdpCheckTileState extends ConsumerState<_UdpCheckTile> {
  bool _busy = false;
  String? _last;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    final r = await ref.read(vpnControllerProvider.notifier).checkUdp();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _last = r.summary;
    });
    if (r.ok) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
    showOnyxToast(context, r.summary, glyph: r.ok ? OnyxGlyph.voice : OnyxGlyph.error);
  }

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final connected = ref.watch(vpnControllerProvider) is VpnConnected;
    return _Tile(
      glyph: OnyxGlyph.refresh,
      title: 'Проверить UDP (голос)',
      subtitle: _last ?? (connected ? 'STUN через туннель, пара секунд' : 'Нужно активное подключение'),
      onTap: _run,
      trailing: _busy
          ? SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 1.6, color: t.accent))
          : OnyxIcon(OnyxGlyph.chevronRight, size: t.isMaterial ? 24 : 16, color: t.textFaint),
    );
  }
}
