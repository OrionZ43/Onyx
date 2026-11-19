// Детали экранов темы Material 3 Expressive: флаг в форме, пинг, AI-бейдж,
// статус, карточка сервера, переключатели функций, трафик.
//
// Компоненты — перенесённые из «Расписания МИТСО» (lib/presentation/widgets/m3),
// токены и источники — docs/m3/. Решения по Onyx — docs/redesign/m3.md.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/m3/app_spacing.dart';
import '../../core/theme/m3/app_typography.dart';
import '../../domain/entities/node.dart';
import '../../domain/entities/vpn_state.dart';
import '../providers/connect_phase.dart';
import '../providers/country_provider.dart';
import '../providers/own_nodes_provider.dart';
import '../providers/subscription_provider.dart';
import '../util/country.dart';
import '../widgets/country_flag.dart' show PolygonClipper;
import '../widgets/hero/hero_state.dart';
import '../widgets/home_parts.dart' show AutopilotView, SecondTicker, formatBytes, formatClock;
import '../widgets/m3/m3_buttons.dart';
import '../widgets/m3/m3_snackbar.dart';
import '../widgets/m3/m3_wavy_linear_progress.dart';
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
///
/// [ms] — в одной шкале для всех протоколов (Node.rttMs, #73); у HY2/TUIC это
/// оценка из времени HTTPS — [approx] ставит «≈».
class M3Ping extends StatelessWidget {
  const M3Ping({super.key, required this.ms, this.alive = true, this.approx = false});

  /// Пинг сервера одной строкой — для [M3Ping] в списках и подписей.
  factory M3Ping.of(Node n) => M3Ping(ms: n.rttMs, alive: n.isAlive, approx: n.rttIsEstimate);

  final int? ms;
  final bool alive;
  final bool approx;

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
        p == null ? (alive ? 'Нет данных' : 'Недоступен') : '${approx ? '≈ ' : ''}$p мс',
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

/// «Свой» сервер — добавлен пользователем ссылкой (#68): человек в форме
/// `Cookie6Sided`, `secondaryContainer`. Пара к [M3AiBadge] — тот же приём
/// «иконка в форме», другая форма и роль, чтобы не спорить с AI.
class M3OwnBadge extends StatelessWidget {
  const M3OwnBadge({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) {
    final ColorScheme s = context.colors;
    return Tooltip(
      message: 'Добавлен вручную',
      child: Semantics(
        label: 'Свой сервер, добавлен вручную',
        child: M3ShapeIcon(
          icon: Symbols.person,
          shape: MaterialShapes.cookie6Sided,
          color: s.secondaryContainer,
          onColor: s.onSecondaryContainer,
          size: size,
        ),
      ),
    );
  }
}

/// Пинг и свойства сервера одной строкой — вспомогательный текст пункта
/// списка: пинг, протокол (кроме VLESS — он по умолчанию), голос (UDP).
/// «Нет UDP» — только у работающего сервера, где STUN молчит (#45).
class M3NodeMeta extends StatelessWidget {
  const M3NodeMeta({super.key, required this.node, this.leading});
  final Node node;

  /// Текст перед пингом, например страна на карточке сервера.
  final String? leading;

  @override
  Widget build(BuildContext context) {
    // В узком месте (панель окна, длинная страна) — перенос на вторую строку,
    // а не обрезка за краем. Пинг, протокол и голос переносятся вместе:
    // страна в первой строке, замеры — во второй, без одинокого значка.
    Wrap line(List<Widget> children) =>
        Wrap(spacing: AppSpacing.space100, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: children);
    final Wrap metrics = line([M3Ping.of(node), ...M3NodeBadges.meta(context, node)]);
    return leading == null ? metrics : line([Text(leading!), metrics]);
  }
}

/// Значки сервера в теме M3 без пинга: протокол (кроме VLESS), голос (UDP)
/// или «нет UDP», «Свой», AI — для мини-панели и общих экранов (NodeBadges).
/// В списках M3 протокол и голос идут в строке [M3NodeMeta], фигуры —
/// отдельно, рядом со звездой.
class M3NodeBadges extends StatelessWidget {
  const M3NodeBadges({super.key, required this.node, this.own = false, this.showProtocol = true});
  final Node node;
  final bool own;
  final bool showProtocol;

  /// Протокол и голос — те же, что в строке [M3NodeMeta].
  static List<Widget> meta(BuildContext context, Node node, {bool showProtocol = true}) {
    final ColorScheme s = context.colors;
    final TextStyle style = context.text.labelMedium!.copyWith(color: s.onSurfaceVariant);
    return [
      if (showProtocol && node.protocol != NodeProtocol.vless) Text(NodeProtocol.label(node.protocol), style: style),
      if (node.udpStatus == UdpStatus.ok)
        Tooltip(
          message: 'UDP проходит — голос Discord и звонки работают',
          child: Icon(Symbols.mic, size: 16, opticalSize: 20, color: s.onSurfaceVariant),
        ),
      if (node.udpStatus == UdpStatus.blocked)
        Tooltip(
          message: 'UDP заблокирован на этом сервере — голос Discord и звонки не пойдут',
          child: Text('нет UDP', style: style),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> items = [
      ...meta(context, node, showProtocol: showProtocol),
      if (own) const M3OwnBadge(size: 24),
      if (node.aiReachable) const M3AiBadge(size: 24),
    ];
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < items.length; i++) ...[if (i > 0) const SizedBox(width: AppSpacing.space100), items[i]],
    ]);
  }
}

// ── Статус ──────────────────────────────────────────────────────────────────

/// Крупный статус над кнопкой — emphasized display, как «hero moment»
/// типографики M3 Expressive; строка под ним — bodyLarge `onSurfaceVariant`.
class M3StatusHeadline extends StatelessWidget {
  const M3StatusHeadline({super.key, required this.vpn, this.compact = false, this.autopilot});

  final VpnState vpn;
  final bool compact;

  /// Этап автопилота «Оникс» поверх состояния VPN (#47): «Обновляю
  /// подписку», «Проверяю серверы · 7 из 20», отказ с причиной.
  final AutopilotView? autopilot;

  @override
  Widget build(BuildContext context) {
    final ColorScheme s = context.colors;
    final AutopilotView? ap = autopilot;
    final HeroPhase phase = ap?.phase ?? heroPhaseOf(vpn);
    final String title = ap?.title ??
        switch (phase) {
          HeroPhase.off => 'Не защищено',
          HeroPhase.connecting => vpn is VpnDisconnecting ? 'Отключение…' : 'Подключение…',
          HeroPhase.on => 'Защищено',
          HeroPhase.error => 'Нет соединения',
        };
    final TextStyle big = (compact ? context.text.headlineLarge! : context.text.displaySmall!).emphasized;
    final TextStyle line = context.text.bodyLarge!.copyWith(color: s.onSurfaceVariant);

    final Widget supporting = ap != null
        ? Text(ap.detail ?? (ap.phase == HeroPhase.connecting ? 'Onyx подбирает сервер' : ''), style: line, maxLines: 3)
        : switch (vpn) {
            VpnConnected() => SecondTicker(
                active: true,
                builder: (_) => Text(
                  'Трафик зашифрован · ${formatClock((vpn as VpnConnected).uptime)}',
                  style: line.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
            VpnConnecting(node: final n) => Text('${displayNodeName(n.name)} · устанавливаем туннель', style: line),
            VpnDisconnecting() => Text('Закрываем туннель', style: line),
            VpnError(message: final m) => Text(uiText(m), style: line, maxLines: 2),
            VpnDisconnected() => Text('Трафик идёт напрямую', style: line),
          };

    return Semantics(
      liveRegion: true,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(title, textAlign: TextAlign.center, style: big.copyWith(color: phase == HeroPhase.error ? s.error : s.onSurface)),
        const SizedBox(height: AppSpacing.space100),
        DefaultTextStyle.merge(textAlign: TextAlign.center, child: supporting),
        // Проверка серверов — определённый прогресс: волнистый линейный
        // индикатор M3 Expressive (Progress indicators → Wavy).
        if (ap?.progress != null) ...[
          const SizedBox(height: AppSpacing.space200),
          SizedBox(width: 220, child: M3WavyLinearProgress(value: ap!.progress!)),
        ],
      ]),
    );
  }
}

/// Действия, когда автопилот не смог подключиться (#47): «Обновить и
/// повторить» — главное (filled), «Добавить сервер» — второстепенное
/// (outlined). Стандартная группа кнопок M3 Expressive, маленький размер.
class M3PhaseActions extends StatelessWidget {
  const M3PhaseActions({super.key, required this.failure, required this.onRefresh, required this.onAddServer});

  final ConnectFailed failure;
  final VoidCallback onRefresh;
  final VoidCallback onAddServer;

  @override
  Widget build(BuildContext context) {
    final bool refresh = failure.actions.contains(ConnectAction.refresh);
    final bool add = failure.actions.contains(ConnectAction.addServer);
    return Wrap(alignment: WrapAlignment.center, spacing: AppSpacing.space100, runSpacing: AppSpacing.space100, children: [
      if (refresh)
        M3Button(
          onPressed: onRefresh,
          icon: const Icon(Symbols.refresh),
          size: M3ButtonSize.small,
          color: M3ButtonColor.filled,
          child: const Text('Обновить и повторить'),
        ),
      if (add)
        M3Button(
          onPressed: onAddServer,
          icon: const Icon(Symbols.add),
          size: M3ButtonSize.small,
          color: refresh ? M3ButtonColor.outlined : M3ButtonColor.filled,
          child: const Text('Добавить сервер'),
        ),
    ]);
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
class M3ServerCard extends ConsumerWidget {
  const M3ServerCard({super.key, required this.node, required this.sub, required this.locked, required this.onTap, this.trailing});

  final Node? node;
  final SubscriptionState sub;
  final bool locked;
  final VoidCallback onTap;

  /// Вместо стрелки — например текстовая кнопка «Сменить» в панели окна.
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme s = context.colors;
    final Node? n = node;
    // Страна одна для всех экранов: выбор пользователя → название → проверка (#68).
    final Country country = n == null ? Country.unknown : ref.watch(countryResolverProvider).of(n);
    final bool own = n != null && ref.watch(ownNodeIdsProvider).contains(n.id);
    // Серверы есть, но ни один ещё не ответил, — это не «нет серверов».
    final bool listed = sub.nodes.isNotEmpty;
    final Widget supporting = switch (sub.status) {
      SubStatus.fetching => const Text('Загружаем список…'),
      SubStatus.probing => Text('Проверяем серверы ${sub.probedCount} из ${sub.nodes.length}'),
      SubStatus.deepProbing => Text('AI-проба ${sub.deepProbedCount} из ${sub.deepProbeTotal}'),
      _ when n == null => Text(listed ? 'Лучший выберется при подключении' : 'Добавьте подписку'),
      _ => M3NodeMeta(node: n, leading: country.isKnown ? country.name : 'Сервер'),
    };
    return SegmentedList(children: [
      M3ListItem(
        leading: M3Flag(code: country.code),
        overline: const Text('Сервер'),
        headline: Text(n != null ? displayNodeName(n.name) : (listed ? 'Автовыбор' : 'Нет серверов'),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        supporting: supporting,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (own) ...[const M3OwnBadge(), const SizedBox(width: AppSpacing.space100)],
          if (n?.aiReachable == true) ...[const M3AiBadge(), const SizedBox(width: AppSpacing.space100)],
          trailing ?? Icon(locked ? Symbols.verified_user : Symbols.chevron_right, color: s.onSurfaceVariant),
        ]),
        onTap: onTap,
        semanticsLabel: n == null ? 'Серверы' : 'Сервер ${displayNodeName(n.name)}, открыть список',
      ),
    ]);
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
    duration: actionLabel == null ? M3SnackbarHostState.durationFor(message) : const Duration(seconds: 10),
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
