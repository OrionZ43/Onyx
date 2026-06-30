// lib/presentation/widgets/node_list_sheet.dart
//
// ИСПРАВЛЕНИЯ:
//  1. Серверы теперь кликабельны (_CompactNodeRow обёрнут в InkWell).
//  2. При клике сохраняется выбранный сервер в nodeSelectionProvider.
//  3. Шторка закрывается сразу через Navigator.of(context).pop() без addPostFrameCallback.
//  4. Убраны все WidgetsBinding.instance.addPostFrameCallback при навигации.

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/glass_widget.dart';
import '../../domain/entities/node.dart';
import '../providers/subscription_provider.dart';
import '../providers/node_provider.dart';

class NodeListSheet extends ConsumerStatefulWidget {
  const NodeListSheet({super.key});

  @override
  ConsumerState<NodeListSheet> createState() => _NodeListSheetState();
}

class _NodeListSheetState extends ConsumerState<NodeListSheet> {
  final Map<String, bool> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final sub = ref.watch(subscriptionProvider);
    final selected = ref.watch(nodeSelectionProvider);
    final nodes = sub.nodes;

    // Группируем по стране (первый emoji / первое слово)
    final groups = _group(nodes);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xCC0D0420), Color(0xCC03020A)],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: AppColors.glassBorder)),
          ),
          child: Column(
            children: [
              // ── Ручка + шапка ─────────────────────────────────────────────
              _SheetHeader(
                nodeCount: nodes.length,
                aliveCount: sub.aliveNodes.length,
              ),

              // ── Список ────────────────────────────────────────────────────
              Expanded(
                child: (sub.status == SubStatus.probing ||
                        sub.status == SubStatus.deepProbing ||
                        sub.status == SubStatus.fetching)
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                              color: AppColors.ember,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              sub.status == SubStatus.fetching
                                  ? 'Загружаем свежий список...'
                                  : sub.status == SubStatus.deepProbing
                                      ? 'Глубокая проверка... ${sub.deepProbedCount}/${sub.deepProbeTotal}'
                                      : 'TCP Пинг... ${sub.probedCount}/${sub.nodes.length}',
                              style: const TextStyle(
                                color: AppColors.nebula1,
                                fontFamily: 'DM Sans',
                              ),
                            ),
                          ],
                        ),
                      )
                    : nodes.isEmpty
                        ? _EmptyState()
                        : CustomScrollView(
                            slivers: [
                              const SliverPadding(
                                  padding: EdgeInsets.only(top: 4)),
                              for (final entry in groups.entries)
                                SliverMainAxisGroup(
                                  slivers: [
                                    SliverPersistentHeader(
                                      pinned: true,
                                      delegate: _CountryHeaderDelegate(
                                        country: entry.key,
                                        nodes: entry.value,
                                        alive: entry.value
                                            .where((n) => n.isAlive)
                                            .length,
                                        bestMs: _bestMs(entry.value),
                                        expanded: _expanded[entry.key] ??
                                            _shouldAutoExpand(
                                                entry.key, groups),
                                        hasSelectedNode: selected != null &&
                                            entry.value.any(
                                                (n) => n.id == selected.id),
                                        onToggle: () => setState(
                                          () => _expanded[entry.key] =
                                              !(_expanded[entry.key] ??
                                                  _shouldAutoExpand(
                                                      entry.key, groups)),
                                        ),
                                      ),
                                    ),
                                    if (_expanded[entry.key] ??
                                        _shouldAutoExpand(entry.key, groups))
                                      SliverList(
                                        delegate: SliverChildBuilderDelegate(
                                          (context, i) => _CompactNodeRow(
                                            node: entry.value[i],
                                            isSelected: selected?.id ==
                                                entry.value[i].id,
                                            onTap: () {
                                              ref
                                                  .read(nodeSelectionProvider
                                                      .notifier)
                                                  .select(entry.value[i]);
                                              if (!context.mounted) return;
                                              Navigator.of(context).pop();
                                            },
                                          ),
                                          childCount: entry.value.length,
                                        ),
                                      ),
                                  ],
                                ),
                              const SliverPadding(
                                  padding: EdgeInsets.only(bottom: 24)),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Map<String, List<Node>> _group(List<Node> nodes) {
    final map = <String, List<Node>>{};
    for (final n in nodes) {
      final key = _countryKey(n.name);
      (map[key] ??= []).add(n);
    }
    return map;
  }

  static const _countryNames = <String, String>{
    'DE': '🇩🇪 Германия',
    'GERMANY': '🇩🇪 Германия',
    'NL': '🇳🇱 Нидерланды',
    'NETHERLANDS': '🇳🇱 Нидерланды',
    'GB': '🇬🇧 Великобритания',
    'UK': '🇬🇧 Великобритания',
    'FI': '🇫🇮 Финляндия',
    'FINLAND': '🇫🇮 Финляндия',
    'RU': '🇷🇺 Россия',
    'RUSSIA': '🇷🇺 Россия',
    'SE': '🇸🇪 Швеция',
    'SWEDEN': '🇸🇪 Швеция',
    'LT': '🇱🇹 Литва',
    'LITHUANIA': '🇱🇹 Литва',
    'LV': '🇱🇻 Латвия',
    'LATVIA': '🇱🇻 Латвия',
    'CH': '🇨🇭 Швейцария',
    'SWITZERLAND': '🇨🇭 Швейцария',
    'US': '🇺🇸 США',
    'USA': '🇺🇸 США',
  };

  String _countryKey(String name) {
    String rawKey;
    // Если начинается с emoji-флага — берём первые 2 codepoint
    final runes = name.runes.toList();
    if (runes.isNotEmpty && runes[0] >= 0x1F1E6 && runes[0] <= 0x1F1FF) {
      rawKey = runes.take(2).map(String.fromCharCode).join();
    } else {
      // Иначе берём первое слово
      rawKey = name.split(RegExp(r'[\s|_-]+')).first.toUpperCase();
    }

    if (_countryNames.containsKey(rawKey)) {
      return _countryNames[rawKey]!;
    }

    // Если не нашли в словаре, но это короткий код или слово - делаем с заглавной буквы
    if (rawKey.length <= 2 && runes.isEmpty) {
      // Если не emoji
      return rawKey.toUpperCase();
    } else if (rawKey.length > 2) {
      return rawKey[0].toUpperCase() + rawKey.substring(1).toLowerCase();
    }

    return rawKey;
  }

  int? _bestMs(List<Node> nodes) {
    final alive = nodes.where((n) => n.isAlive && n.latencyMs != null).toList();
    if (alive.isEmpty) return null;
    alive.sort((a, b) => a.latencyMs!.compareTo(b.latencyMs!));
    return alive.first.latencyMs;
  }

  bool _shouldAutoExpand(String key, Map<String, List<Node>> groups) {
    // Авто-раскрываем первую группу
    return groups.keys.first == key;
  }
}

// ── Шапка шторки ──────────────────────────────────────────────────────────

class _SheetHeader extends ConsumerWidget {
  const _SheetHeader({required this.nodeCount, required this.aliveCount});
  final int nodeCount, aliveCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Ручка
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.nebula2.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(2),
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Row(
            children: [
              ShaderMask(
                shaderCallback: (b) => AppColors.gradientPlasma.createShader(
                  Rect.fromLTWH(0, 0, b.width, b.height),
                ),
                child: const Icon(
                  Icons.dns_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Выбор сервера',
                style: TextStyle(
                  fontFamily: 'Syne',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.nebula0,
                ),
              ),
              const Spacer(),
              GlassPill(
                color: AppColors.aurora,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                child: Text(
                  '$aliveCount / $nodeCount онлайн',
                  style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 11,
                    color: AppColors.aurora,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Кнопка обновления
              GestureDetector(
                onTap: () {
                  final url = ref.read(subscriptionProvider).url;
                  if (url.isNotEmpty) {
                    ref.read(subscriptionProvider.notifier).loadFromUrl(url);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.plasma.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: AppColors.plasma.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.sync_rounded,
                        size: 14,
                        color: AppColors.plasmaLight,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Обновить',
                        style: TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.plasmaLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        Container(height: 1, color: AppColors.glassBorder),
      ],
    );
  }
}

// ── Пустое состояние ──────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, color: AppColors.nebula2, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Серверы не загружены',
              style: TextStyle(
                fontFamily: 'Syne',
                fontSize: 16,
                color: AppColors.nebula1,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Добавьте подписку на главном экране',
              style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 12,
                color: AppColors.nebula2,
              ),
            ),
          ],
        ),
      );
}

// ── Группа страны ─────────────────────────────────────────────────────────

class _CountryHeaderDelegate extends SliverPersistentHeaderDelegate {
  _CountryHeaderDelegate({
    required this.country,
    required this.nodes,
    required this.alive,
    required this.bestMs,
    required this.expanded,
    required this.hasSelectedNode,
    required this.onToggle,
  });

  final String country;
  final List<Node> nodes;
  final int alive;
  final int? bestMs;
  final bool expanded;
  final bool hasSelectedNode;
  final VoidCallback onToggle;

  @override
  double get minExtent => 48; // Примерная высота заголовка

  @override
  double get maxExtent => 48;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    // Если внутри есть выбранная нода — подсвечиваем заголовок
    final isHighlighted = hasSelectedNode;

    return GestureDetector(
      onTap: onToggle,
      child: Container(
        // Отрисовываем фон поверх контента под ним, чтобы не просвечивал скролл
        color: const Color(
            0xCC0D0420), // Цвет фона шторки, чтобы заголовок перекрывал список
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isHighlighted
                ? AppColors.plasma.withValues(alpha: 0.15)
                : expanded
                    ? AppColors.plasma.withValues(alpha: 0.08)
                    : AppColors.void2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isHighlighted
                  ? AppColors.plasma.withValues(alpha: 0.8)
                  : expanded
                      ? AppColors.horizonGlow
                      : AppColors.glassBorder.withValues(alpha: 0.4),
              width: isHighlighted ? 1.5 : 1.0,
            ),
            boxShadow: isHighlighted
                ? [
                    BoxShadow(
                      color: AppColors.plasma.withValues(alpha: 0.2),
                      blurRadius: 10,
                      spreadRadius: 1,
                    )
                  ]
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  country,
                  style: TextStyle(
                    fontFamily: 'Syne',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isHighlighted || expanded
                        ? AppColors.plasma
                        : AppColors.nebula0,
                  ),
                ),
              ),
              Text(
                '$alive/${nodes.length}',
                style: const TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 11,
                  color: AppColors.nebula2,
                ),
              ),
              const SizedBox(width: 10),
              if (bestMs != null) _MsChip(ms: bestMs!),
              const SizedBox(width: 8),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppColors.nebula2,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _CountryHeaderDelegate oldDelegate) {
    return oldDelegate.country != country ||
        oldDelegate.expanded != expanded ||
        oldDelegate.hasSelectedNode != hasSelectedNode ||
        oldDelegate.alive != alive ||
        oldDelegate.bestMs != bestMs;
  }
}

// ── Компактная строка ноды (КЛИКАБЕЛЬНАЯ) ────────────────────────────────

class _CompactNodeRow extends StatelessWidget {
  const _CompactNodeRow({
    required this.node,
    required this.isSelected,
    required this.onTap,
  });
  final Node node;
  final bool isSelected;
  final VoidCallback onTap;

  Color _qColor() => switch (node.quality) {
        NodeQuality.excellent => AppColors.aurora,
        NodeQuality.good => const Color(0xFF80E8B0),
        NodeQuality.poor => AppColors.ember,
        NodeQuality.dead => AppColors.nebula2,
      };

  @override
  Widget build(BuildContext context) {
    final qc = _qColor();
    final selectedBorder = isSelected ? AppColors.plasma : null;

    // Вычисляем цвет фона и выносим его на уровень Material
    final bgColor = isSelected
        ? AppColors.plasma.withValues(alpha: 0.10)
        : node.isTrulyWorking
            ? AppColors.aurora.withValues(alpha: 0.06)
            : AppColors.void2.withValues(alpha: 0.8);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 12, 3),
      child: Material(
        color: bgColor, // <--- ФОН ТЕПЕРЬ ЗДЕСЬ
        borderRadius: BorderRadius.circular(10), // <--- СКРУГЛЕНИЕ ДЛЯ ФОНА
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          splashColor: AppColors.plasma.withValues(alpha: 0.25),
          highlightColor: AppColors.plasma.withValues(alpha: 0.1),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              // color: убрано отсюда, чтобы не перекрывать splash-эффект
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selectedBorder != null
                    ? selectedBorder.withValues(alpha: 0.6)
                    : node.isTrulyWorking
                        ? AppColors.aurora.withValues(alpha: 0.3)
                        : AppColors.glassBorder.withValues(alpha: 0.3),
                width: isSelected ? 1.2 : 1.0,
              ),
            ),
            child: Row(
              children: [
                // Точка статуса
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: qc,
                    boxShadow: node.isAlive
                        ? [
                            BoxShadow(
                              color: qc.withValues(alpha: 0.6),
                              blurRadius: 5,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 10),

                // Номер
                Text(
                  '#${node.id.substring(0, 4)}',
                  style: const TextStyle(
                    fontFamily: 'DM Mono',
                    fontSize: 10,
                    color: AppColors.nebula2,
                  ),
                ),
                const SizedBox(width: 10),

                // Транспорт + безопасность
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.void3,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${node.network.toUpperCase()} · ${node.security.toUpperCase()}',
                    style: const TextStyle(
                      fontFamily: 'DM Mono',
                      fontSize: 9,
                      color: AppColors.nebula2,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // SNI / имя
                Expanded(
                  child: Text(
                    node.name,
                    style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 11,
                      color: isSelected ? AppColors.plasma : AppColors.nebula1,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Бейдж LIVE / MUX
                if (node.isTrulyWorking) ...[
                  _SmallBadge('LIVE', AppColors.aurora),
                  const SizedBox(width: 4),
                ] else if (node.muxEnabled) ...[
                  _SmallBadge('MUX', AppColors.plasma),
                  const SizedBox(width: 4),
                ],

                // Иконка "выбрано"
                if (isSelected)
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 14,
                    color: AppColors.plasma,
                  ),

                // Пинг
                if (!isSelected && node.latencyMs != null)
                  _MsChip(ms: node.latencyMs!)
                else if (!isSelected)
                  const Text(
                    '—',
                    style: TextStyle(
                      fontFamily: 'DM Mono',
                      fontSize: 11,
                      color: AppColors.nebula2,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Вспомогательные виджеты ───────────────────────────────────────────────

class _MsChip extends StatelessWidget {
  const _MsChip({required this.ms});
  final int ms;

  Color get _c => ms < 150
      ? AppColors.aurora
      : ms < 400
          ? AppColors.ember
          : AppColors.nova;

  @override
  Widget build(BuildContext context) => Text(
        '${ms}мс',
        style: TextStyle(
          fontFamily: 'DM Mono',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _c,
        ),
      );
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 0.6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'DM Mono',
            fontSize: 8,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      );
}
