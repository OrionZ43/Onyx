import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/glass_widget.dart';
import '../../domain/entities/node.dart';
import '../providers/subscription_provider.dart';

class NodeListSheet extends ConsumerStatefulWidget {
  const NodeListSheet({super.key});

  @override
  ConsumerState<NodeListSheet> createState() => _NodeListSheetState();
}

class _NodeListSheetState extends ConsumerState<NodeListSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  _SortMode _sort = _SortMode.latency;
  String? _expandedCountry; // null = все свёрнуты / страна = раскрыта

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sub   = ref.watch(subscriptionProvider);
    final nodes = sub.nodes;

    // Фильтр + поиск
    final filtered = nodes.where((n) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return n.name.toLowerCase().contains(q) ||
          n.host.toLowerCase().contains(q) ||
          n.sni.toLowerCase().contains(q);
    }).toList();

    // Сортировка
    filtered.sort((a, b) => switch (_sort) {
      _SortMode.latency => _cmpLatency(a, b),
      _SortMode.country => a.name.compareTo(b.name),
      _SortMode.alive   => (b.isAlive ? 1 : 0) - (a.isAlive ? 1 : 0),
    });

    // Группировка по стране
    final groups = <String, List<Node>>{};
    for (final n in filtered) {
      final country = _extractCountry(n.name);
      groups.putIfAbsent(country, () => []).add(n);
    }
    final sortedCountries = groups.keys.toList()..sort();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollCtrl) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xF0090815),
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              border: Border(
                top:   BorderSide(color: AppColors.glassBorder),
                left:  BorderSide(color: AppColors.glassBorder),
                right: BorderSide(color: AppColors.glassBorder),
              ),
            ),
            // ── Используем Column вместо SliverPersistentHeader ──────
            // SliverPersistentHeader требует точных размеров — опасно.
            // Column + ListView безопаснее и без layout-ошибок.
            child: Column(
              children: [
                // Прилипающая шапка
                _SheetHeader(
                  aliveCount:  sub.aliveNodes.length,
                  totalCount:  nodes.length,
                  sort:        _sort,
                  isProbing:   sub.status == SubStatus.probing || sub.status == SubStatus.deepProbing,
                  onSort:      (s) => setState(() => _sort = s),
                  onRefresh:   () => ref.read(subscriptionProvider.notifier).reprobe(),
                  searchCtrl:  _searchCtrl,
                  onSearch:    (q) => setState(() => _query = q),
                ),

                // Прогресс пробинга
                if (sub.status == SubStatus.probing)
                  LinearProgressIndicator(
                    value: sub.nodes.isNotEmpty
                        ? sub.probedCount / sub.nodes.length
                        : null,
                    backgroundColor: AppColors.void3,
                    color: AppColors.plasma,
                    minHeight: 2,
                  ),

                // Контент — скроллится
                Expanded(child: CustomScrollView(
                  controller: scrollCtrl,
                  slivers: [

                // ── Пустое состояние ──────────────────────────────────
                if (filtered.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _query.isEmpty
                                ? Icons.cloud_off_rounded
                                : Icons.search_off_rounded,
                            color: AppColors.nebula2, size: 44,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _query.isEmpty
                                ? 'Нет серверов'
                                : 'Ничего не найдено',
                            style: const TextStyle(
                              fontFamily: 'Syne', color: AppColors.nebula2,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  // ── Группы по странам ──────────────────────────────
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) {
                        final country = sortedCountries[i];
                        final countryNodes = groups[country]!;
                        final isExpanded = _expandedCountry == country;
                        final aliveInGroup =
                            countryNodes.where((n) => n.isAlive).length;
                        final bestMs = countryNodes
                            .where((n) => n.isAlive && n.latencyMs != null)
                            .fold<int?>(null, (best, n) =>
                                best == null || n.latencyMs! < best
                                    ? n.latencyMs
                                    : best);

                        return _CountryGroup(
                          country:    country,
                          nodes:      countryNodes,
                          alive:      aliveInGroup,
                          bestMs:     bestMs,
                          expanded:   isExpanded,
                          onToggle:   () => setState(() =>
                              _expandedCountry =
                                  isExpanded ? null : country),
                        ).animate(delay: (i * 20).ms).fadeIn(duration: 200.ms);
                      },
                      childCount: sortedCountries.length,
                    ),
                  ),

                SliverToBoxAdapter(
                  child: SizedBox(
                    height: MediaQuery.of(context).padding.bottom + 24,
                  ),
                ),
              ],
            )), // closes Expanded + CustomScrollView
              ],
            ), // closes Column
          ),
        ),
      ),
    );
  }

  int _cmpLatency(Node a, Node b) {
    if (!a.isAlive && !b.isAlive) return 0;
    if (!a.isAlive) return 1;
    if (!b.isAlive) return -1;
    return (a.latencyMs ?? 9999).compareTo(b.latencyMs ?? 9999);
  }

  String _extractCountry(String name) {
    // "🇩🇪 Germany — #76" → "🇩🇪 Germany"
    final parts = name.split('—');
    return parts.first.trim();
  }
}

// ── Режим сортировки ───────────────────────────────────────────────────────

enum _SortMode { latency, country, alive }


// ── Шапка шита ────────────────────────────────────────────────────────────

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.aliveCount,
    required this.totalCount,
    required this.sort,
    required this.isProbing,
    required this.onSort,
    required this.onRefresh,
    required this.searchCtrl,
    required this.onSearch,
  });

  final int aliveCount, totalCount;
  final _SortMode sort;
  final bool isProbing;
  final ValueChanged<_SortMode> onSort;
  final VoidCallback onRefresh;
  final TextEditingController searchCtrl;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xF2090815),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ручка
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppColors.nebula2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Строка заголовка
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              ShaderMask(
                shaderCallback: (b) => AppColors.gradientPlasma
                    .createShader(Rect.fromLTWH(0, 0, b.width, b.height)),
                child: const Icon(Icons.dns_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 8),
              const Text('Серверы', style: TextStyle(
                fontFamily: 'Syne', fontSize: 17,
                fontWeight: FontWeight.w700, color: AppColors.nebula0,
              )),
              const SizedBox(width: 8),
              GlassPill(
                color: AppColors.plasma,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: Text('$aliveCount/$totalCount', style: const TextStyle(
                  fontFamily: 'DM Sans', fontSize: 11,
                  color: AppColors.plasmaLight, fontWeight: FontWeight.w600,
                )),
              ),
              const Spacer(),

              // Сортировка
              _SortBtn(current: sort, onChanged: onSort),
              const SizedBox(width: 8),

              // Обновить
              GestureDetector(
                onTap: onRefresh,
                child: GlassPill(
                  color: AppColors.plasma,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    isProbing
                        ? const SizedBox(
                            width: 12, height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: AppColors.plasma))
                        : const Icon(Icons.radar_rounded,
                            size: 13, color: AppColors.plasma),
                    const SizedBox(width: 5),
                    const Text('Проверить', style: TextStyle(
                      fontFamily: 'DM Sans', fontSize: 11,
                      color: AppColors.plasmaLight,
                    )),
                  ]),
                ),
              ),
            ]),
          ),

          const SizedBox(height: 10),

          // Поиск
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.glass,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: Row(children: [
                    const SizedBox(width: 12),
                    const Icon(Icons.search_rounded,
                        color: AppColors.nebula2, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: searchCtrl,
                        onChanged: onSearch,
                        style: const TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 13, color: AppColors.nebula0,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Поиск по стране, хосту, SNI...',
                          hintStyle: TextStyle(
                            color: AppColors.nebula2, fontSize: 13,
                          ),
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    if (searchCtrl.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          searchCtrl.clear();
                          onSearch('');
                        },
                        child: const Padding(
                          padding: EdgeInsets.only(right: 10),
                          child: Icon(Icons.close_rounded,
                              color: AppColors.nebula2, size: 14),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Кнопка сортировки ──────────────────────────────────────────────────────

class _SortBtn extends StatelessWidget {
  const _SortBtn({required this.current, required this.onChanged});
  final _SortMode current;
  final ValueChanged<_SortMode> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<_SortMode>(
    color: AppColors.void2,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: AppColors.glassBorder),
    ),
    onSelected: onChanged,
    child: GlassPill(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.sort_rounded, size: 13, color: AppColors.nebula1),
        const SizedBox(width: 5),
        Text(_sortLabel(current), style: const TextStyle(
          fontFamily: 'DM Sans', fontSize: 11, color: AppColors.nebula1,
        )),
      ]),
    ),
    itemBuilder: (_) => [
      _item(_SortMode.latency, 'По пингу',   Icons.speed_rounded),
      _item(_SortMode.country, 'По стране',  Icons.flag_rounded),
      _item(_SortMode.alive,   'По статусу', Icons.circle_rounded),
    ],
  );

  String _sortLabel(_SortMode m) => switch (m) {
    _SortMode.latency => 'Пинг',
    _SortMode.country => 'Страна',
    _SortMode.alive   => 'Статус',
  };

  PopupMenuItem<_SortMode> _item(
    _SortMode mode, String label, IconData icon,
  ) => PopupMenuItem(
    value: mode,
    child: Row(children: [
      Icon(icon, size: 14,
          color: mode == current ? AppColors.plasma : AppColors.nebula1),
      const SizedBox(width: 10),
      Text(label, style: TextStyle(
        fontFamily: 'DM Sans', fontSize: 13,
        color: mode == current ? AppColors.plasma : AppColors.nebula0,
      )),
    ]),
  );
}

// ── Группа по стране ───────────────────────────────────────────────────────

class _CountryGroup extends StatelessWidget {
  const _CountryGroup({
    required this.country,
    required this.nodes,
    required this.alive,
    required this.bestMs,
    required this.expanded,
    required this.onToggle,
  });

  final String country;
  final List<Node> nodes;
  final int alive;
  final int? bestMs;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Строка-заголовок страны
        GestureDetector(
          onTap: onToggle,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: expanded
                  ? AppColors.plasma.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: expanded
                    ? AppColors.horizonGlow
                    : AppColors.glassBorder.withValues(alpha: 0.4),
              ),
            ),
            child: Row(children: [
              // Флаг + страна
              Expanded(
                child: Text(country, style: TextStyle(
                  fontFamily: 'Syne', fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: expanded ? AppColors.plasma : AppColors.nebula0,
                )),
              ),

              // Живых / всего
              Text('$alive/${nodes.length}', style: const TextStyle(
                fontFamily: 'DM Sans', fontSize: 11,
                color: AppColors.nebula2,
              )),
              const SizedBox(width: 10),

              // Лучший пинг
              if (bestMs != null)
                _MsChip(ms: bestMs!),
              const SizedBox(width: 8),

              // Стрелка
              AnimatedRotation(
                turns: expanded ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: const Icon(Icons.keyboard_arrow_down_rounded,
                    color: AppColors.nebula2, size: 18),
              ),
            ]),
          ),
        ),

        // Список нод внутри группы
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: expanded
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < nodes.length; i++)
                      _CompactNodeRow(node: nodes[i])
                          .animate(delay: (i * 25).ms)
                          .fadeIn(duration: 200.ms)
                          .slideX(begin: 0.04),
                    const SizedBox(height: 4),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ── Компактная строка ноды ─────────────────────────────────────────────────

class _CompactNodeRow extends StatelessWidget {
  const _CompactNodeRow({required this.node});
  final Node node;

  Color _qColor() => switch (node.quality) {
    NodeQuality.excellent => AppColors.aurora,
    NodeQuality.good      => const Color(0xFF80E8B0),
    NodeQuality.poor      => AppColors.ember,
    NodeQuality.dead      => AppColors.nebula2,
  };

  @override
  Widget build(BuildContext context) {
    final qc = _qColor();
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 12, 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        // ← НОВОЕ: зеленоватая подсветка для isTrulyWorking нод
        color: node.isTrulyWorking
            ? AppColors.aurora.withValues(alpha: 0.06)
            : AppColors.void2.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: node.isTrulyWorking
              ? AppColors.aurora.withValues(alpha: 0.3)
              : AppColors.glassBorder.withValues(alpha: 0.3),
        ),
      ),
      child: Row(children: [
        // Точка статуса
        Container(
          width: 6, height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: qc,
            boxShadow: node.isAlive
                ? [BoxShadow(color: qc.withValues(alpha: 0.6), blurRadius: 5)]
                : null,
          ),
        ),
        const SizedBox(width: 10),

        // Номер
        Text('#${node.id.substring(0, 4)}', style: const TextStyle(
          fontFamily: 'DM Mono', fontSize: 10, color: AppColors.nebula2,
        )),
        const SizedBox(width: 10),

        // Транспорт + безопасность
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: AppColors.void3,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${node.network.toUpperCase()} · ${node.security.toUpperCase()}',
            style: const TextStyle(
              fontFamily: 'DM Mono', fontSize: 9, color: AppColors.nebula2,
            ),
          ),
        ),
        const SizedBox(width: 8),

        // SNI
        Expanded(
          child: Text(node.sni,
            style: const TextStyle(
              fontFamily: 'DM Sans', fontSize: 11, color: AppColors.nebula1,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),

        // ← НОВОЕ: бейдж "✓ LIVE" (приоритет над MUX)
        if (node.isTrulyWorking) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.aurora.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                  color: AppColors.aurora.withValues(alpha: 0.4), width: 0.6),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: const [
              Icon(Icons.verified_rounded, size: 8, color: AppColors.aurora),
              SizedBox(width: 2),
              Text('LIVE', style: TextStyle(
                fontFamily: 'DM Mono', fontSize: 8,
                fontWeight: FontWeight.w700, color: AppColors.aurora,
              )),
            ]),
          ),
          const SizedBox(width: 4),
        ] else if (node.muxEnabled) ...[
          _SmallBadge('MUX', AppColors.plasma),
          const SizedBox(width: 4),
        ],

        // Пинг
        if (node.latencyMs != null)
          _MsChip(ms: node.latencyMs!)
        else
          const Text('—', style: TextStyle(
              fontFamily: 'DM Mono', fontSize: 11, color: AppColors.nebula2)),
      ]),
    );
  }
}

class _MsChip extends StatelessWidget {
  const _MsChip({required this.ms});
  final int ms;

  Color get _c => ms < 150 ? AppColors.aurora
      : ms < 400 ? AppColors.ember
      : AppColors.nova;

  @override
  Widget build(BuildContext context) => Text('${ms}мс',
    style: TextStyle(
      fontFamily: 'DM Mono', fontSize: 11,
      fontWeight: FontWeight.w700, color: _c,
    ));
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
    child: Text(label, style: TextStyle(
      fontFamily: 'DM Mono', fontSize: 8,
      fontWeight: FontWeight.w700, color: color,
    )),
  );
}
