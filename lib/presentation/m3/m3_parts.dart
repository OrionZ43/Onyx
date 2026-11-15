// Детали экранов темы Material 3 Expressive: флаг в форме, пинг, AI-бейдж,
// статус, карточка сервера, переключатели функций, трафик.
//
// Компоненты — перенесённые из «Расписания МИТСО» (lib/presentation/widgets/m3),
// токены и источники — docs/m3/. Решения по Onyx — docs/redesign/m3.md.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/m3/app_spacing.dart';
import '../../core/theme/m3/app_typography.dart';
import '../../domain/entities/node.dart';
import '../../domain/entities/vpn_state.dart';
import '../../infrastructure/platform_features.dart';
import '../providers/settings_provider.dart';
import '../providers/subscription_provider.dart';
import '../util/country.dart';
import '../util/platform_kind.dart';
import '../widgets/country_flag.dart' show PolygonClipper;
import '../widgets/hero/hero_state.dart';
import '../widgets/home_parts.dart' show SecondTicker, formatBytes, formatClock;
import '../widgets/m3/m3_button_group.dart';
import '../widgets/m3/m3_buttons.dart';
import '../widgets/m3/m3_snackbar.dart';
import '../widgets/m3/m3_toggle_button.dart';
import '../widgets/m3/segmented_list.dart';

// ── Флаг в форме ────────────────────────────────────────────────────────────

/// Флаг страны в форме MaterialShapes (`Cookie4Sided`) — «shape as image
/// container» (https://m3.material.io/styles/shape/overview). Квадратный флаг
/// (flag-icons, MIT) целиком помещается в форму. Форма у всех флагов одна:
/// в списке разные фигуры спорили бы с данными.
///
/// Неизвестная страна — та же форма `secondaryContainer` с глобусом.
class M3Flag extends StatelessWidget {
  const M3Flag({super.key, required this.code, this.size = 40});

  /// ISO alpha-2 в нижнем регистре или ''.
  final String code;

  /// `ListTokens.ItemLeadingAvatarSize` — 40dp.
  final double size;

  static final RoundedPolygon shape = MaterialShapes.cookie4Sided;

  @override
  Widget build(BuildContext context) {
    final ColorScheme s = context.colors;
    final bool known = code.isNotEmpty && hasFlagAsset(code);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: ClipPath(
          clipper: PolygonClipper(shape),
          child: known
              ? SvgPicture.asset('assets/flags/square/$code.svg', fit: BoxFit.cover)
              : ColoredBox(
                  color: s.secondaryContainer,
                  child: Icon(Symbols.public, size: size * 0.5, color: s.onSecondaryContainer),
                ),
        ),
      ),
    );
  }
}

/// Иконка в форме — ведущий элемент строки списка вместо аватара
/// (`ListTokens.ItemLeadingAvatarSize` 40dp, иконка 24dp).
class M3ShapeIcon extends StatelessWidget {
  const M3ShapeIcon({
    super.key,
    required this.icon,
    required this.shape,
    required this.color,
    required this.onColor,
    this.size = 40,
  });

  final IconData icon;
  final RoundedPolygon shape;
  final Color color, onColor;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox.square(
          dimension: size,
          child: Stack(alignment: Alignment.center, children: [
            Positioned.fill(
              child: ClipPath(clipper: PolygonClipper(shape), child: ColoredBox(color: color)),
            ),
            Icon(icon, size: size * 0.5, color: onColor),
          ]),
        ),
      );
}

// ── Пинг и AI ───────────────────────────────────────────────────────────────

/// Пинг: полосы сигнала Material Symbols (`signal_cellular_alt*`) и число.
/// Медленный сервер (> 150 мс) — одна полоса цветом `error`.
class M3Ping extends StatelessWidget {
  const M3Ping({super.key, required this.ms, this.alive = true});

  final int? ms;
  final bool alive;

  static IconData iconFor(int? ms) => switch (ms) {
        null => Symbols.signal_cellular_null,
        < 80 => Symbols.signal_cellular_alt,
        < 150 => Symbols.signal_cellular_alt_2_bar,
        _ => Symbols.signal_cellular_alt_1_bar,
      };

  @override
  Widget build(BuildContext context) {
    final ColorScheme s = context.colors;
    final int? p = alive ? ms : null;
    final Color c = p != null && p > 150 ? s.error : s.onSurfaceVariant;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(iconFor(p), size: 16, opticalSize: 20, color: c),
      const SizedBox(width: AppSpacing.space50),
      Text(
        p == null ? (alive ? 'нет данных' : 'недоступен') : '$p мс',
        style: context.text.bodyMedium!.copyWith(
          color: c,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ]);
  }
}

/// Отметка «сервер прошёл AI-пробу»: искра в форме `Sunny`,
/// `tertiaryContainer` — третичный цвет M3 для дополнительных акцентов
/// (https://m3.material.io/styles/color/roles).
class M3AiBadge extends StatelessWidget {
  const M3AiBadge({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) {
    final ColorScheme s = context.colors;
    return Tooltip(
      message: 'AI-проба пройдена',
      child: Semantics(
        label: 'AI-проба пройдена',
        child: M3ShapeIcon(
          icon: Symbols.auto_awesome,
          shape: MaterialShapes.sunny,
          color: s.tertiaryContainer,
          onColor: s.onTertiaryContainer,
          size: size,
        ),
      ),
    );
  }
}

// ── Статус ──────────────────────────────────────────────────────────────────

/// Крупный статус над кнопкой — emphasized display, как «hero moment»
/// типографики M3 Expressive; строка под ним — bodyLarge `onSurfaceVariant`.
class M3StatusHeadline extends StatelessWidget {
  const M3StatusHeadline({super.key, required this.vpn, this.compact = false});

  final VpnState vpn;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ColorScheme s = context.colors;
    final HeroPhase phase = heroPhaseOf(vpn);
    final String title = switch (phase) {
      HeroPhase.off => 'Не защищено',
      HeroPhase.connecting => vpn is VpnDisconnecting ? 'Отключение…' : 'Подключение…',
      HeroPhase.on => 'Защищено',
      HeroPhase.error => 'Нет соединения',
    };
    final TextStyle big = (compact ? context.text.headlineLarge! : context.text.displaySmall!).emphasized;
    final TextStyle line = context.text.bodyLarge!.copyWith(color: s.onSurfaceVariant);

    final Widget supporting = switch (vpn) {
      VpnConnected() => SecondTicker(
          active: true,
          builder: (_) => Text(
            'Трафик зашифрован · ${formatClock((vpn as VpnConnected).uptime)}',
            style: line.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
      VpnConnecting(node: final n) => Text('${displayNodeName(n.name)} · устанавливаем туннель', style: line),
      VpnDisconnecting() => Text('Закрываем туннель', style: line),
      VpnError(message: final m) => Text(m, style: line, maxLines: 2),
      VpnDisconnected() => Text('Трафик идёт напрямую', style: line),
    };

    return Semantics(
      liveRegion: true,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(title, textAlign: TextAlign.center, style: big.copyWith(color: phase == HeroPhase.error ? s.error : s.onSurface)),
        const SizedBox(height: AppSpacing.space100),
        DefaultTextStyle.merge(textAlign: TextAlign.center, child: supporting),
      ]),
    );
  }
}

/// Подсказка действия под кнопкой — labelLarge `onSurfaceVariant`.
class M3HeroCaption extends StatelessWidget {
  const M3HeroCaption({super.key, required this.phase});
  final HeroPhase phase;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Text(
          switch (phase) {
            HeroPhase.off => 'Нажмите, чтобы подключиться',
            HeroPhase.connecting => 'Нажмите, чтобы отменить',
            HeroPhase.on => 'Нажмите, чтобы отключить',
            HeroPhase.error => 'Нажмите, чтобы повторить',
          },
          style: context.text.labelLarge!.copyWith(color: context.colors.onSurfaceVariant),
        ),
      );
}

// ── Текущий сервер ──────────────────────────────────────────────────────────

/// Текущий сервер — пункт списка M3 Expressive в своей группе: флаг, имя,
/// страна и пинг, AI-бейдж. Нажатие открывает список серверов; во время
/// подключения справа — значок защиты вместо стрелки.
class M3ServerCard extends StatelessWidget {
  const M3ServerCard({super.key, required this.node, required this.sub, required this.locked, required this.onTap});

  final Node? node;
  final SubscriptionState sub;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme s = context.colors;
    final Node? n = node;
    final Country country = n == null ? Country.unknown : countryOfName(n.name);
    final Widget supporting = switch (sub.status) {
      SubStatus.fetching => const Text('Загружаем список…'),
      SubStatus.probing => Text('Проверяем серверы ${sub.probedCount} из ${sub.nodes.length}'),
      SubStatus.deepProbing => Text('AI-проба ${sub.deepProbedCount} из ${sub.deepProbeTotal}'),
      _ when n == null => const Text('Добавьте подписку'),
      _ => Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Text(country.isKnown ? country.name : 'Сервер', overflow: TextOverflow.ellipsis)),
          const SizedBox(width: AppSpacing.space100),
          M3Ping(ms: n.latencyMs, alive: n.isAlive),
        ]),
    };
    return SegmentedList(children: [
      M3ListItem(
        leading: M3Flag(code: country.code),
        overline: const Text('Сервер'),
        headline: Text(n == null ? 'Нет серверов' : displayNodeName(n.name), maxLines: 1, overflow: TextOverflow.ellipsis),
        supporting: supporting,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (n?.aiReachable == true) ...[const M3AiBadge(), const SizedBox(width: AppSpacing.space100)],
          Icon(locked ? Symbols.verified_user : Symbols.chevron_right, color: s.onSurfaceVariant),
        ]),
        onTap: onTap,
        semanticsLabel: n == null ? 'Серверы' : 'Сервер ${displayNodeName(n.name)}, открыть список',
      ),
    ]);
  }
}

// ── Функции: группа переключателей ──────────────────────────────────────────

/// Тихие функции — стандартная группа кнопок M3 Expressive
/// (https://m3.material.io/components/button-groups): переключатели
/// «Авто» и «AI-канал», третьим — «Маршруты» (Windows) или ссылка на
/// системный Kill switch (Android: состояния у приложения нет, это обычная
/// кнопка, а не переключатель).
class M3FeatureToggles extends ConsumerWidget {
  const M3FeatureToggles({super.key});

  static const M3ButtonSize size = M3ButtonSize.small;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);

    M3ButtonGroupItem toggle(String label, IconData icon, bool value, ValueChanged<bool> onChanged) => M3ButtonGroupItem(
          builder: (context, states) => M3ToggleButton(
            checked: value,
            onCheckedChange: (v) {
              HapticFeedback.selectionClick();
              onChanged(v);
            },
            icon: Icon(icon),
            size: size,
            color: M3ToggleButtonColor.tonal,
            statesController: states,
            child: Text(label),
          ),
        );

    return M3ButtonGroup(
      spacing: M3ButtonGroupDefaults.spacingFor(size),
      children: [
        toggle('Авто', Symbols.bolt, settings.autoFailover, n.toggleAutoFailover),
        toggle('AI-канал', Symbols.auto_awesome, settings.aiDirectLane, n.toggleAiDirectLane),
        if (uiIsAndroid)
          M3ButtonGroupItem(
            builder: (context, states) => M3Button(
              onPressed: () => PlatformFeatures.instance.openVpnSettings(),
              icon: const Icon(Symbols.verified_user),
              size: size,
              color: M3ButtonColor.outlined,
              statesController: states,
              child: const Text('Kill switch'),
            ),
          )
        else
          toggle('Маршруты', Symbols.language, settings.smartRouting, n.toggleSmartRouting),
      ],
    );
  }
}

// ── Трафик ──────────────────────────────────────────────────────────────────

/// Трафик сессии — две плитки в общей группе: 4dp между ними и крупные
/// внешние углы, как у сегментированных групп M3 Expressive.
class M3TrafficTiles extends StatelessWidget {
  const M3TrafficTiles({super.key, required this.state});
  final VpnConnected state;

  @override
  Widget build(BuildContext context) {
    final ColorScheme s = context.colors;
    Widget tile(IconData icon, String label, String value, BorderRadius r) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(AppSpacing.space200, AppSpacing.space150, AppSpacing.space200, AppSpacing.space150),
            decoration: BoxDecoration(color: s.surfaceContainer, borderRadius: r),
            child: Row(children: [
              Icon(icon, color: s.primary),
              const SizedBox(width: AppSpacing.space150),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: context.text.labelMedium!.copyWith(color: s.onSurfaceVariant)),
                  Text(
                    value,
                    style: context.text.titleLarge!.emphasized.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ]),
              ),
            ]),
          ),
        );
    const Radius outer = Radius.circular(16), inner = Radius.circular(4);
    return Semantics(
      container: true,
      label: 'Получено ${formatBytes(state.rxBytes)}, отправлено ${formatBytes(state.txBytes)}',
      excludeSemantics: true,
      child: Row(children: [
        tile(Symbols.arrow_downward, 'Получено', formatBytes(state.rxBytes),
            const BorderRadius.horizontal(left: outer, right: inner)),
        const SizedBox(width: AppSpacing.space50),
        tile(Symbols.arrow_upward, 'Отправлено', formatBytes(state.txBytes),
            const BorderRadius.horizontal(left: inner, right: outer)),
      ]),
    );
  }
}

// ── Сообщения ───────────────────────────────────────────────────────────────

/// Короткое сообщение снекбаром M3 (`M3SnackbarHost`, порт Compose). Вне
/// экрана с хостом (например, в листе) — снекбар Flutter в теме M3.
void showM3Message(BuildContext context, String message, {String? actionLabel, VoidCallback? onAction}) {
  final M3SnackbarHostState? host = context.findAncestorStateOfType<M3SnackbarHostState>();
  if (host != null) {
    host.show(message, actionLabel: actionLabel, onAction: onAction);
    return;
  }
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
    content: Text(message),
    action: actionLabel == null ? null : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
  ));
}

// ── Плашки над главным экраном ──────────────────────────────────────────────

/// Плашка — заполненная карточка M3 (`surfaceContainerHighest`): иконка,
/// текст и текстовая кнопка. Компонента «banner» в M3 нет, карточка — его
/// замена по Cards → Usage.
class M3Notice extends StatelessWidget {
  const M3Notice({super.key, required this.icon, required this.text, required this.action, required this.onAction});

  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final ColorScheme s = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.space200, AppSpacing.space100, AppSpacing.space200, 0),
      child: Card.filled(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.space200, AppSpacing.space50, AppSpacing.space100, AppSpacing.space50),
          child: Row(children: [
            Icon(icon, color: s.onSurfaceVariant),
            const SizedBox(width: AppSpacing.space150),
            Expanded(child: Text(text, style: context.text.bodyMedium)),
            M3Button(onPressed: onAction, color: M3ButtonColor.text, child: Text(action)),
          ]),
        ),
      ),
    );
  }
}
