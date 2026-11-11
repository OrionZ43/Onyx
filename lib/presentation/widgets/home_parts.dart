import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/onyx_tokens.dart';
import '../../domain/entities/node.dart';
import '../../domain/entities/vpn_state.dart';
import '../providers/connect_phase.dart';
import '../providers/subscription_provider.dart';
import '../util/country.dart';
import 'country_flag.dart';
import 'hero/hero_state.dart';
import 'onyx_icon.dart';
import 'signal/dot_matrix.dart';

// ── Форматирование ──────────────────────────────────────────────────────────

String formatBytes(int b) {
  if (b < 1024) return '$b Б';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} КБ';
  if (b < 1024 * 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(b < 100 * 1024 * 1024 ? 1 : 0)} МБ';
  return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} ГБ';
}

String formatClock(Duration d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

/// Перестраивает потомка раз в секунду, пока [active] — для таймера сессии.
class SecondTicker extends StatefulWidget {
  const SecondTicker({super.key, required this.active, required this.builder});
  final bool active;
  final WidgetBuilder builder;

  @override
  State<SecondTicker> createState() => _SecondTickerState();
}

class _SecondTickerState extends State<SecondTicker> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(SecondTicker old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.active && _t == null) {
      _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    } else if (!widget.active) {
      _t?.cancel();
      _t = null;
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

// ── Статус над кнопкой ──────────────────────────────────────────────────────

class StatusHeader extends StatelessWidget {
  const StatusHeader({super.key, required this.vpn, this.compact = false, this.phase, this.title, this.detail});
  final VpnState vpn;
  final bool compact;

  /// Этап автоподключения (#47) поверх состояния VPN: фаза «Линзы», крупная
  /// строка и подпись — «Проверяю серверы», «3 из 20».
  final HeroPhase? phase;
  final String? title, detail;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final phase = this.phase ?? heroPhaseOf(vpn);
    final nodeName = switch (vpn) {
      VpnConnecting(node: final n) || VpnDisconnecting(node: final n) => displayNodeName(n.name),
      VpnError(node: final n?) => displayNodeName(n.name),
      _ => '',
    };
    final disconnecting = vpn is VpnDisconnecting;
    final errorText = vpn is VpnError ? uiText((vpn as VpnError).message) : '';

    // Ключ (капс) + крупная строка + подпись.
    final String key = switch (phase) {
      HeroPhase.off => 'Не защищено',
      HeroPhase.connecting => disconnecting ? 'Отключение' : 'Подключение',
      HeroPhase.on => t.isSignal ? 'Защита активна' : 'Защищено',
      HeroPhase.error => 'Нет соединения',
    };
    final String big = title ??
        switch (phase) {
          HeroPhase.off => 'Трафик открыт',
          HeroPhase.connecting => nodeName.isEmpty ? '…' : nodeName,
          HeroPhase.on => '', // таймер — ниже
          HeroPhase.error => 'Сервер не ответил',
        };
    var sub = detail ??
        switch (phase) {
          HeroPhase.connecting => disconnecting ? 'Закрываем туннель' : 'Устанавливаем туннель',
          HeroPhase.error => errorText,
          _ => '',
        };
    // В Signal крупной строки нет — этап идёт в подпись капсом, а длинная
    // причина отказа — ниже обычным шрифтом (капсом её не прочесть).
    String? note;
    if (t.isSignal && title != null) {
      sub = title!;
      note = detail;
    }

    if (t.isMaterial) return _materialHeader(context, phase, key, sub);

    final keyColor = switch (phase) {
      HeroPhase.on => t.isSignal ? t.text : t.accent,
      HeroPhase.connecting => t.isSignal ? t.text : t.accentMuted,
      HeroPhase.error => t.danger,
      HeroPhase.off => t.textMuted,
    };
    final dotColor = switch (phase) {
      HeroPhase.on => t.isSignal ? AppTheme.signalRec : t.accent,
      HeroPhase.connecting => t.isSignal ? t.text : t.accentMuted,
      HeroPhase.error => t.danger,
      HeroPhase.off => t.textFaint,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: t.isSignal ? 8 : 6,
              height: t.isSignal ? 8 : 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
                boxShadow: phase == HeroPhase.on ? [BoxShadow(color: dotColor, blurRadius: 10)] : null,
              ),
            ),
            SizedBox(width: t.isSignal ? 8 : 10),
            Text(key.toUpperCase(), style: t.caps(size: 11, color: keyColor)),
          ],
        ),
        if (!t.isSignal) ...[
          const SizedBox(height: 6),
          if (phase == HeroPhase.on && vpn is VpnConnected)
            SecondTicker(
              active: true,
              builder: (_) => Text(
                formatClock((vpn as VpnConnected).uptime),
                style: t.numbers(size: compact ? 30 : 34),
              ),
            )
          else
            Text(
              big,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: t.displayFont,
                fontSize: compact ? 30 : 34,
                fontWeight: FontWeight.w300,
                letterSpacing: -0.7,
                color: t.text,
              ),
            ),
        ],
        if (sub.isNotEmpty) ...[
          SizedBox(height: t.isSignal ? 8 : 4),
          Text(
            t.isSignal ? sub.toUpperCase() : sub,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.isSignal
                ? t.caps(size: 10.5, color: note == null ? t.textFaint : t.text)
                : TextStyle(fontFamily: t.bodyFont, fontSize: 13, color: t.textMuted),
          ),
        ],
        if (note != null && note.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            note,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: t.bodyFont, fontSize: 12.5, height: 1.35, color: t.textMuted),
          ),
        ],
      ],
    );
  }

  Widget _materialHeader(BuildContext context, HeroPhase phase, String key, String sub) {
    final s = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final String line = switch (phase) {
      HeroPhase.off => 'Трафик идёт напрямую',
      HeroPhase.on => '',
      _ => sub,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          phase == HeroPhase.connecting ? '$key…' : key,
          style: text.headlineLarge!.copyWith(color: phase == HeroPhase.error ? s.error : s.onSurface),
        ),
        const SizedBox(height: 6),
        if (phase == HeroPhase.on && vpn is VpnConnected)
          SecondTicker(
            active: true,
            builder: (_) => Text(
              'Трафик зашифрован · ${formatClock((vpn as VpnConnected).uptime)}',
              style: text.bodyMedium!.copyWith(color: s.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          )
        else
          Text(line, textAlign: TextAlign.center, maxLines: 2, style: text.bodyMedium!.copyWith(color: s.onSurfaceVariant)),
        if (phase == HeroPhase.connecting) ...[
          const SizedBox(height: 14),
          SizedBox(
            width: 220,
            child: LinearProgressIndicator(
              // ignore: deprecated_member_use
              year2023: false,
              borderRadius: BorderRadius.circular(4),
              minHeight: 4,
            ),
          ),
        ],
      ],
    );
  }
}

/// Подпись под кнопкой — только Material («Нажмите, чтобы подключиться»).
class HeroCaption extends StatelessWidget {
  const HeroCaption({super.key, required this.phase});
  final HeroPhase phase;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final text = switch (phase) {
      HeroPhase.off => 'Нажмите, чтобы подключиться',
      HeroPhase.connecting => 'Нажмите, чтобы отменить',
      HeroPhase.on => 'Нажмите, чтобы отключить',
      HeroPhase.error => 'Нажмите, чтобы повторить',
    };
    return Text(text, style: Theme.of(context).textTheme.labelLarge!.copyWith(color: s.onSurfaceVariant));
  }
}

// ── Бейджи ──────────────────────────────────────────────────────────────────

/// Отметка «сервер прошёл AI-пробу».
class AiBadge extends StatelessWidget {
  const AiBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    if (t.isMaterial) {
      final s = Theme.of(context).colorScheme;
      return Container(
        height: 24,
        padding: const EdgeInsets.only(left: 6, right: 8),
        decoration: BoxDecoration(color: s.tertiaryContainer, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.auto_awesome_outlined, size: 14, color: s.onTertiaryContainer),
          const SizedBox(width: 4),
          Text('AI', style: TextStyle(fontFamily: 'Roboto', fontSize: 12, fontWeight: FontWeight.w500, color: s.onTertiaryContainer)),
        ]),
      );
    }
    if (t.isSignal) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(color: t.text, borderRadius: BorderRadius.circular(4)),
        child: Text('AI', style: TextStyle(fontFamily: t.monoFont, fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: t.bg)),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 2, 5, 2),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF3A3326)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('AI', style: TextStyle(fontFamily: t.displayFont, fontSize: 9.5, fontWeight: FontWeight.w600, letterSpacing: 1.3, color: t.accent)),
    );
  }
}

/// Индикатор пинга: Onyx — 3 тонкие полосы, Signal — 4 точки, Material — 4 полосы.
class PingIndicator extends StatelessWidget {
  const PingIndicator({super.key, required this.ms});
  final int? ms;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final p = ms;
    if (t.isSignal) {
      final n = p == null ? 0 : p < 50 ? 4 : p < 80 ? 3 : p < 150 ? 2 : 1;
      return DotRow(lit: n, on: t.text, off: const Color(0xFF2A2A2A));
    }
    final count = t.isMaterial ? 4 : 3;
    final n = p == null
        ? 0
        : t.isMaterial
            ? (p < 50 ? 4 : p < 80 ? 3 : p < 150 ? 2 : 1)
            : (p < 50 ? 3 : p < 120 ? 2 : 1);
    final on = t.isMaterial ? Theme.of(context).colorScheme.primary : t.accent;
    final off = t.isMaterial ? Theme.of(context).colorScheme.outlineVariant : t.lineStrong;
    final w = t.isMaterial ? 3.0 : 2.0;
    return SizedBox(
      height: 14,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) SizedBox(width: t.isMaterial ? 2 : 3),
            Container(
              width: w,
              height: (t.isMaterial ? [5.0, 8.0, 11.0, 14.0] : [5.0, 8.0, 12.0])[i],
              decoration: BoxDecoration(color: i < n ? on : off, borderRadius: BorderRadius.circular(1.5)),
            ),
          ],
        ],
      ),
    );
  }
}

/// Пинг числом: «38 мс» / «38MS».
class PingText extends StatelessWidget {
  const PingText({super.key, required this.ms, this.width});
  final int? ms;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    if (ms == null) return SizedBox(width: width);
    final slow = ms! > 150;
    final c = slow && t.isOnyx ? const Color(0xFFB98B5E) : t.textMuted;
    final Widget w = t.isSignal
        ? Text('$ms', style: TextStyle(fontFamily: t.monoFont, fontSize: 13, fontWeight: FontWeight.w500, color: c))
        : Text.rich(
            TextSpan(children: [
              TextSpan(text: '$ms', style: TextStyle(fontFamily: t.displayFont, fontSize: 13, fontWeight: FontWeight.w500, color: c)),
              TextSpan(text: ' мс', style: TextStyle(fontFamily: t.displayFont, fontSize: 11, color: t.textFaint)),
            ]),
          );
    return SizedBox(width: width, child: Align(alignment: Alignment.centerRight, child: w));
  }
}

// ── Карточка текущего сервера ───────────────────────────────────────────────

class ServerCard extends ConsumerWidget {
  const ServerCard({super.key, required this.node, required this.sub, required this.locked, required this.onTap});
  final Node? node;
  final SubscriptionState sub;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = OnyxTokens.of(context);
    final n = node;
    final country = n == null ? Country.unknown : countryOfName(n.name);
    // Серверы есть, но ни один пока не ответил (проверка не прошла или все
    // недоступны) — это не «нет серверов»: автопилот проверит их по тапу.
    final listed = sub.nodes.isNotEmpty;
    final title = n != null ? displayNodeName(n.name) : (listed ? 'Автовыбор' : 'Нет серверов');
    final String subtitle;
    if (sub.status == SubStatus.fetching) {
      subtitle = 'Загружаем список…';
    } else if (sub.status == SubStatus.probing) {
      subtitle = 'Проверяем серверы ${sub.probedCount}/${sub.nodes.length}';
    } else if (sub.status == SubStatus.deepProbing) {
      subtitle = 'AI-проба ${sub.deepProbedCount}/${sub.deepProbeTotal}';
    } else if (n == null) {
      subtitle = listed ? 'Лучший выберется при подключении' : 'Добавьте подписку';
    } else {
      subtitle = country.isKnown ? country.name : '${sub.aliveNodes.length} из ${sub.nodes.length} доступно';
    }

    final s = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(t.isMaterial ? 28 : t.radiusCard);
    return Material(
      color: t.surface,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          padding: t.isMaterial
              ? const EdgeInsets.fromLTRB(12, 12, 12, 12)
              : EdgeInsets.symmetric(horizontal: t.isSignal ? 18 : 16, vertical: t.isSignal ? 16 : 14),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: t.isOnyx ? Border.all(color: t.line) : null,
          ),
          child: Row(
            children: [
              CountryFlag(code: country.code, size: t.isMaterial ? 48 : t.isSignal ? 30 : 34),
              SizedBox(width: t.isMaterial ? 16 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.isMaterial
                          ? Theme.of(context).textTheme.titleMedium
                          : TextStyle(fontFamily: t.bodyFont, fontSize: t.isSignal ? 17 : 15, fontWeight: FontWeight.w500, color: t.text, letterSpacing: t.isSignal ? -0.2 : 0),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t.isSignal ? subtitle.toUpperCase() : subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.isMaterial
                          ? Theme.of(context).textTheme.bodyMedium!.copyWith(color: s.onSurfaceVariant)
                          : t.isSignal
                              ? t.caps(size: 10, color: t.textFaint)
                              : TextStyle(fontFamily: t.bodyFont, fontSize: 12.5, color: t.textMuted),
                    ),
                  ],
                ),
              ),
              if (n != null) ...[NodeBadges(node: n), const SizedBox(width: 10)],
              if (t.isMaterial) PingIndicator(ms: n?.latencyMs) else PingText(ms: n?.latencyMs),
              const SizedBox(width: 6),
              OnyxIcon(locked ? OnyxGlyph.shield : OnyxGlyph.chevronRight, size: t.isMaterial ? 24 : 16, color: t.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Автопилот «один тап» (#47, API «Оникс») ─────────────────────────────────

/// Что показать вместо обычного статуса, пока автопилот обновляет подписку и
/// проверяет серверы (VPN ещё выключен) или когда он не смог подключиться.
/// null — показывать обычное состояние VPN: подключение, подключено и
/// отключение важнее этапа.
class AutopilotView {
  const AutopilotView({required this.phase, required this.title, this.detail, this.progress, this.failure});

  /// Фаза «Линзы».
  final HeroPhase phase;

  /// Крупная строка и подпись под ней.
  final String title;
  final String? detail;

  /// Проверено серверов из всех, 0..1.
  final double? progress;

  /// Отказ — с причиной и действиями.
  final ConnectFailed? failure;

  static AutopilotView? of(VpnState vpn, ConnectPhase p) {
    if (vpn is! VpnDisconnected && vpn is! VpnError) return null;
    return switch (p) {
      ConnectUpdating() => const AutopilotView(phase: HeroPhase.connecting, title: 'Обновляю подписку'),
      ConnectChecking(:final done, :final total) => AutopilotView(
          phase: HeroPhase.connecting,
          title: 'Проверяю серверы',
          detail: total > 0 ? '$done из $total' : null,
          progress: total > 0 ? done / total : null,
        ),
      ConnectConnecting(:final nodeName) => AutopilotView(phase: HeroPhase.connecting, title: displayNodeName(nodeName), detail: 'Подключаюсь'),
      ConnectSwitching(:final to) => AutopilotView(phase: HeroPhase.connecting, title: displayNodeName(to), detail: 'Переключаюсь'),
      final ConnectFailed f => AutopilotView(
          phase: HeroPhase.error,
          title: switch (f.reason) {
            ConnectFailure.noSources => 'Нет серверов',
            ConnectFailure.sourcesUnreachable => 'Серверы не загрузились',
            ConnectFailure.allDead => 'Серверы не отвечают',
          },
          detail: uiText(f.message),
          failure: f,
        ),
      _ => null,
    };
  }
}

// ── Действия при неудачном автоподключении (#47) ───────────────────────────

/// Кнопки под «Линзой», когда автоподключение не удалось: «Обновить и
/// повторить», «Добавить сервер», «Инструкция». Первая — главная.
/// Значок оговорки автопилота по её тону (NoticeKind, #66).
OnyxGlyph noticeGlyph(NoticeKind kind) => switch (kind) {
      NoticeKind.recovered => OnyxGlyph.check,
      NoticeKind.switched => OnyxGlyph.zap,
      NoticeKind.warning => OnyxGlyph.error,
      NoticeKind.info => OnyxGlyph.info,
    };

class PhaseActions extends StatelessWidget {
  const PhaseActions({super.key, required this.actions});
  final List<(String, VoidCallback)> actions;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    Widget button(int i) {
      final (label, onTap) = actions[i];
      final primary = i == 0;
      if (t.isMaterial) {
        return primary
            ? FilledButton(onPressed: onTap, child: Text(label))
            : OutlinedButton(onPressed: onTap, child: Text(label));
      }
      final fg = t.isSignal ? (primary ? t.bg : t.text) : (primary ? t.accent : t.text);
      return TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: fg,
          backgroundColor: t.isSignal ? (primary ? t.text : t.surfaceHigh) : Colors.transparent,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: StadiumBorder(
            side: t.isOnyx ? BorderSide(color: primary ? const Color(0xFF5A4E38) : t.line) : BorderSide.none,
          ),
        ),
        child: Text(
          t.isSignal ? label.toUpperCase() : label,
          style: t.isSignal
              ? t.caps(size: 10.5, color: fg, weight: FontWeight.w600)
              : TextStyle(fontFamily: t.bodyFont, fontSize: 13, fontWeight: FontWeight.w500, color: fg),
        ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [for (var i = 0; i < actions.length; i++) button(i)],
    );
  }
}

// ── Трафик сессии ───────────────────────────────────────────────────────────

class TrafficStats extends StatelessWidget {
  const TrafficStats({super.key, required this.state});
  final VpnConnected state;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final items = [
      (OnyxGlyph.down, 'Получено', formatBytes(state.rxBytes)),
      (OnyxGlyph.up, 'Отправлено', formatBytes(state.txBytes)),
    ];
    if (t.isMaterial) {
      final s = Theme.of(context).colorScheme;
      final text = Theme.of(context).textTheme;
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Row(children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(
              child: Container(
                color: s.surfaceContainer,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(items[i].$1.material, size: 14, color: s.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(items[i].$2, style: text.labelMedium!.copyWith(color: s.onSurfaceVariant)),
                  ]),
                  const SizedBox(height: 2),
                  Text(items[i].$3, style: text.titleLarge!.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                ]),
              ),
            ),
          ],
        ]),
      );
    }
    if (t.isSignal) {
      return Row(children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(20)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  OnyxIcon(items[i].$1, size: 12, color: t.textMuted),
                  const SizedBox(width: 6),
                  Text(items[i].$2.toUpperCase(), style: t.caps(size: 10)),
                ]),
                const SizedBox(height: 8),
                _valueUnit(t, items[i].$3, 22),
              ]),
            ),
          ),
        ],
      ]);
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final it in items)
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _valueUnit(t, it.$3, 22),
            const SizedBox(height: 4),
            Row(children: [
              OnyxIcon(it.$1, size: 10, color: t.textFaint),
              const SizedBox(width: 5),
              Text(it.$2.toUpperCase(), style: t.caps(size: 10, color: t.textFaint)),
            ]),
          ]),
      ],
    );
  }

  Widget _valueUnit(OnyxTokens t, String v, double size) {
    final i = v.lastIndexOf(' ');
    return Text.rich(TextSpan(children: [
      TextSpan(text: v.substring(0, i), style: t.numbers(size: size, weight: t.isSignal ? FontWeight.w500 : null)),
      TextSpan(
        text: ' ${v.substring(i + 1)}',
        style: TextStyle(fontFamily: t.isSignal ? t.monoFont : t.displayFont, fontSize: 12, color: t.textMuted),
      ),
    ]));
  }
}

// ── Протокол и голос (#34/#35) ──────────────────────────────────────────────

/// Метка протокола ноды: VLESS / HY2 / TUIC / SS / TROJAN / ANYTLS.
/// Тише AI-бейджа: только текст капсом, без заливки.
class ProtocolBadge extends StatelessWidget {
  const ProtocolBadge({super.key, required this.protocol});
  final String protocol;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final label = NodeProtocol.label(protocol);
    if (t.isMaterial) {
      final s = Theme.of(context).colorScheme;
      return Text(label, style: Theme.of(context).textTheme.labelSmall!.copyWith(color: s.onSurfaceVariant));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: t.isSignal ? t.lineStrong : t.line),
        borderRadius: BorderRadius.circular(t.isSignal ? 4 : 6),
      ),
      child: Text(
        label,
        style: t.isSignal
            ? TextStyle(fontFamily: t.monoFont, fontSize: 9.5, fontWeight: FontWeight.w500, letterSpacing: 0.6, color: t.textMuted)
            : TextStyle(fontFamily: t.displayFont, fontSize: 9, fontWeight: FontWeight.w500, letterSpacing: 1.1, color: t.textMuted),
      ),
    );
  }
}

/// Значок «голос» — нода пропускает UDP (проверено пробой): Discord, звонки.
class VoiceBadge extends StatelessWidget {
  const VoiceBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    return Tooltip(
      message: 'UDP проходит — голос Discord и звонки работают',
      child: OnyxIcon(
        OnyxGlyph.voice,
        size: t.isMaterial ? 20 : 14,
        color: t.isMaterial ? Theme.of(context).colorScheme.tertiary : (t.isSignal ? t.text : t.accent),
      ),
    );
  }
}

/// Сервер работает, но UDP не проходит — голос Discord и звонки не пойдут.
class _NoUdpBadge extends StatelessWidget {
  const _NoUdpBadge();

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    return Tooltip(
      message: 'UDP заблокирован на этом сервере — голос Discord и звонки не пойдут',
      child: Text('НЕТ UDP', style: t.caps(size: t.isMaterial ? 11 : 9.5, color: t.textFaint)),
    );
  }
}

/// Протокол + голос + AI одной строкой (порядок одинаковый во всех темах).
class NodeBadges extends StatelessWidget {
  const NodeBadges({super.key, required this.node, this.showProtocol = true});
  final Node node;
  final bool showProtocol;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[
      // VLESS — протокол по умолчанию: метку показываем только для остальных,
      // иначе она повторяется в каждой строке и съедает место под имя.
      if (showProtocol && node.protocol != NodeProtocol.vless) ProtocolBadge(protocol: node.protocol),
      // Честный UDP (#45): «нет UDP» — только если сервер работает, а STUN
      // молчит; у недоступного сервера бейджа голоса нет.
      if (node.udpStatus == UdpStatus.ok) const VoiceBadge(),
      if (node.udpStatus == UdpStatus.blocked) const _NoUdpBadge(),
      if (node.aiReachable) const AiBadge(),
    ];
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 0; i < items.length; i++) ...[if (i > 0) const SizedBox(width: 6), items[i]],
    ]);
  }
}
