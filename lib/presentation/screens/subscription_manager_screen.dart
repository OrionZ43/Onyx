import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/glass_widget.dart';
import '../providers/subscription_provider.dart';

/// Экран управления подписками.
/// Позволяет: добавить, удалить, обновить подписки.
class SubscriptionManagerScreen extends ConsumerStatefulWidget {
  const SubscriptionManagerScreen({super.key});

  @override
  ConsumerState<SubscriptionManagerScreen> createState() =>
      _SubscriptionManagerScreenState();
}

class _SubscriptionManagerScreenState
    extends ConsumerState<SubscriptionManagerScreen> {
  List<_SubEntry> _entries = [];
  bool _loading = true;

  static const _subsKey = 'saved_subscriptions';

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_subsKey) ?? [];

    // Формат: "Название||URL"
    setState(() {
      _entries = saved.map((s) {
        final parts = s.split('||');
        return _SubEntry(
          name: parts.length > 1 ? parts[0] : 'Подписка',
          url:  parts.length > 1 ? parts[1] : parts[0],
        );
      }).toList();
      _loading = false;
    });
  }

  Future<void> _saveEntries() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _subsKey,
      _entries.map((e) => '${e.name}||${e.url}').toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sub = ref.watch(subscriptionProvider);

    return Scaffold(
      backgroundColor: AppColors.void0,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0D0420), Color(0xFF03020A)],
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // ── Шапка ─────────────────────────────────────────────
                ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      decoration: const BoxDecoration(
                        color: Color(0x99050410),
                        border: Border(
                          bottom: BorderSide(color: AppColors.glassBorder),
                        ),
                      ),
                      child: Row(children: [
                        GestureDetector(
                          onTap: () { WidgetsBinding.instance.addPostFrameCallback((_) { Navigator.pop(context); }); },
                          child: Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: AppColors.glass,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.glassBorder),
                            ),
                            child: const Icon(Icons.arrow_back_ios_rounded,
                                size: 14, color: AppColors.nebula1),
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Text('Подписки', style: TextStyle(
                          fontFamily: 'Syne', fontSize: 18,
                          fontWeight: FontWeight.w700, color: AppColors.nebula0,
                        )),
                        const Spacer(),
                        // Добавить
                        GestureDetector(
                          onTap: _showAddDialog,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: AppColors.gradientPlasma,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [BoxShadow(
                                color: AppColors.plasma.withValues(alpha: 0.35),
                                blurRadius: 12,
                              )],
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_rounded,
                                    color: Colors.white, size: 16),
                                SizedBox(width: 6),
                                Text('Добавить', style: TextStyle(
                                  fontFamily: 'Syne', fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                )),
                              ],
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),

                // ── Статус текущей загрузки ───────────────────────────
                if (sub.status == SubStatus.fetching ||
                    sub.status == SubStatus.probing)
                  Container(
                    color: AppColors.plasma.withValues(alpha: 0.06),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    child: Row(children: [
                      const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: AppColors.plasma),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        sub.status == SubStatus.fetching
                            ? 'Загружаем серверы...'
                            : 'Проверяем серверы... '
                                '${sub.probedCount}/${sub.nodes.length}',
                        style: const TextStyle(
                          fontFamily: 'DM Sans', fontSize: 12,
                          color: AppColors.nebula1,
                        ),
                      ),
                    ]),
                  ),

                // ── Список подписок ────────────────────────────────────
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.plasma))
                      : _entries.isEmpty
                          ? _EmptyState(onAdd: _showAddDialog)
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _entries.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, i) => _SubCard(
                                entry: _entries[i],
                                isActive: sub.url == _entries[i].url,
                                nodeCount: sub.url == _entries[i].url
                                    ? sub.nodes.length
                                    : null,
                                aliveCount: sub.url == _entries[i].url
                                    ? sub.aliveNodes.length
                                    : null,
                                onLoad: () => _loadSub(_entries[i]),
                                onDelete: () => _deleteSub(i),
                                onEdit: () => _showEditDialog(i),
                              ).animate(delay: (i * 60).ms)
                               .fadeIn(duration: 300.ms)
                               .slideY(begin: 0.15),
                            ),
                ),

                // ── Подсказка ──────────────────────────────────────────
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      20, 8, 20,
                      MediaQuery.of(context).padding.bottom + 12),
                  child: const Text(
                    'Поддерживаются ссылки на VLESS-подписки '
                    'и прямые base64-строки',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'DM Sans', fontSize: 11,
                      color: AppColors.nebula2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _loadSub(_SubEntry entry) {
    ref.read(subscriptionProvider.notifier).loadFromUrl(entry.url);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) Navigator.pop(context);
    });
  }

  Future<void> _deleteSub(int index) async {
    setState(() => _entries.removeAt(index));
    await _saveEntries();
  }

  void _showAddDialog() => _showSubDialog();
  void _showEditDialog(int index) => _showSubDialog(existing: _entries[index], editIndex: index);

  Future<void> _showSubDialog({_SubEntry? existing, int? editIndex}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final urlCtrl  = TextEditingController(text: existing?.url  ?? '');

    final result = await showDialog<_SubEntry>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          backgroundColor: AppColors.void2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: AppColors.glassBorder),
          ),
          title: Text(
            existing == null ? 'Добавить подписку' : 'Изменить подписку',
            style: const TextStyle(
              fontFamily: 'Syne', fontSize: 16,
              fontWeight: FontWeight.w700, color: AppColors.nebula0,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DialogField(
                ctrl: nameCtrl,
                label: 'Название',
                hint: 'Мой VPN',
                icon: Icons.label_outline_rounded,
              ),
              const SizedBox(height: 12),
              _DialogField(
                ctrl: urlCtrl,
                label: 'URL подписки',
                hint: 'https://...',
                icon: Icons.link_rounded,
                isUrl: true,
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async {
                  final d = await Clipboard.getData('text/plain');
                  if (d?.text != null) urlCtrl.text = d!.text!.trim();
                },
                child: Row(children: [
                  const Icon(Icons.content_paste_rounded,
                      size: 13, color: AppColors.plasma),
                  const SizedBox(width: 6),
                  Text('Вставить из буфера',
                    style: TextStyle(
                      fontFamily: 'DM Sans', fontSize: 12,
                      color: AppColors.plasma.withValues(alpha: 0.8),
                    )),
                ]),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена',
                style: TextStyle(color: AppColors.nebula2)),
            ),
            GestureDetector(
              onTap: () {
                if (urlCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, _SubEntry(
                  name: nameCtrl.text.trim().isEmpty
                      ? 'Подписка'
                      : nameCtrl.text.trim(),
                  url: urlCtrl.text.trim(),
                ));
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  gradient: AppColors.gradientPlasma,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  existing == null ? 'Добавить' : 'Сохранить',
                  style: const TextStyle(
                    fontFamily: 'Syne', fontSize: 13,
                    fontWeight: FontWeight.w600, color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;

    setState(() {
      if (editIndex != null) {
        _entries[editIndex] = result;
      } else {
        _entries.add(result);
      }
    });
    await _saveEntries();

    // Сразу загружаем если первая
    if (_entries.length == 1 || editIndex == null) {
      _loadSub(result);
    }
  }
}

// ── Карточка подписки ──────────────────────────────────────────────────────

class _SubCard extends StatelessWidget {
  const _SubCard({
    required this.entry,
    required this.isActive,
    required this.onLoad,
    required this.onDelete,
    required this.onEdit,
    this.nodeCount,
    this.aliveCount,
  });

  final _SubEntry entry;
  final bool isActive;
  final int? nodeCount, aliveCount;
  final VoidCallback onLoad, onDelete, onEdit;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      borderRadius: 18,
      glowColor: isActive
          ? AppColors.plasma.withValues(alpha: 0.12)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            // Иконка активной
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                gradient: isActive
                    ? AppColors.gradientPlasma
                    : const LinearGradient(
                        colors: [AppColors.void3, AppColors.void3]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isActive
                    ? Icons.cloud_done_rounded
                    : Icons.cloud_outlined,
                color: isActive ? Colors.white : AppColors.nebula2,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(entry.name, style: const TextStyle(
                      fontFamily: 'Syne', fontSize: 14,
                      fontWeight: FontWeight.w600, color: AppColors.nebula0,
                    )),
                    if (isActive) ...[
                      const SizedBox(width: 8),
                      GlassPill(
                        color: AppColors.aurora,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        child: const Text('Активна', style: TextStyle(
                          fontFamily: 'DM Sans', fontSize: 9,
                          color: AppColors.aurora, fontWeight: FontWeight.w600,
                        )),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    entry.url,
                    style: const TextStyle(
                      fontFamily: 'DM Sans', fontSize: 11,
                      color: AppColors.nebula2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Меню
            PopupMenuButton<String>(
              color: AppColors.void2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: const BorderSide(color: AppColors.glassBorder),
              ),
              onSelected: (v) {
                if (v == 'edit')   onEdit();
                if (v == 'delete') onDelete();
              },
              icon: const Icon(Icons.more_vert_rounded,
                  color: AppColors.nebula2, size: 18),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit',
                    child: Row(children: [
                      Icon(Icons.edit_outlined, size: 15, color: AppColors.nebula1),
                      SizedBox(width: 10),
                      Text('Изменить', style: TextStyle(
                        fontFamily: 'DM Sans', color: AppColors.nebula0, fontSize: 13)),
                    ])),
                const PopupMenuItem(value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline_rounded, size: 15, color: AppColors.nova),
                      SizedBox(width: 10),
                      Text('Удалить', style: TextStyle(
                        fontFamily: 'DM Sans', color: AppColors.nova, fontSize: 13)),
                    ])),
              ],
            ),
          ]),

          // Статистика (только активная)
          if (isActive && nodeCount != null) ...[
            const SizedBox(height: 12),
            const Divider(color: AppColors.horizon, height: 1),
            const SizedBox(height: 10),
            Row(children: [
              _StatPill(
                icon: Icons.circle_rounded,
                color: AppColors.aurora,
                label: '$aliveCount доступно',
              ),
              const SizedBox(width: 8),
              _StatPill(
                icon: Icons.dns_outlined,
                color: AppColors.nebula1,
                label: '$nodeCount серверов',
              ),
              const Spacer(),
              // Обновить
              GestureDetector(
                onTap: onLoad,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded,
                        size: 13, color: AppColors.plasma),
                    SizedBox(width: 4),
                    Text('Обновить', style: TextStyle(
                      fontFamily: 'DM Sans', fontSize: 11,
                      color: AppColors.plasma,
                    )),
                  ],
                ),
              ),
            ]),
          ],

          // Кнопка подключить (неактивные)
          if (!isActive) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: onLoad,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  gradient: AppColors.gradientPlasma,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Text('Загрузить эту подписку', style: TextStyle(
                    fontFamily: 'Syne', fontSize: 13,
                    fontWeight: FontWeight.w600, color: Colors.white,
                  )),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.icon, required this.color, required this.label});
  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 8, color: color),
      const SizedBox(width: 5),
      Text(label, style: TextStyle(
        fontFamily: 'DM Sans', fontSize: 11, color: color,
      )),
    ],
  );
}

// ── Поле диалога ──────────────────────────────────────────────────────────

class _DialogField extends StatelessWidget {
  const _DialogField({
    required this.ctrl,
    required this.label,
    required this.hint,
    required this.icon,
    this.isUrl = false,
  });

  final TextEditingController ctrl;
  final String label, hint;
  final IconData icon;
  final bool isUrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(
          fontFamily: 'DM Sans', fontSize: 11, color: AppColors.nebula2,
        )),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AppColors.void3,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Row(children: [
            const SizedBox(width: 12),
            Icon(icon, color: AppColors.nebula2, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: ctrl,
                style: const TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 13, color: AppColors.nebula0,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: hint,
                  hintStyle: const TextStyle(
                    color: AppColors.nebula2, fontSize: 13,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 12),
                ),
                keyboardType: isUrl
                    ? TextInputType.url
                    : TextInputType.text,
                autocorrect: false,
              ),
            ),
            const SizedBox(width: 8),
          ]),
        ),
      ],
    );
  }
}

// ── Пустое состояние ──────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded,
              color: AppColors.nebula2, size: 56),
          const SizedBox(height: 16),
          const Text('Нет подписок', style: TextStyle(
            fontFamily: 'Syne', fontSize: 18,
            fontWeight: FontWeight.w700, color: AppColors.nebula1,
          )),
          const SizedBox(height: 8),
          const Text(
            'Добавьте ссылку на подписку\nдля загрузки серверов',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'DM Sans', fontSize: 14,
              color: AppColors.nebula2, height: 1.5,
            ),
          ),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 28, vertical: 14),
              decoration: BoxDecoration(
                gradient: AppColors.gradientPlasma,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(
                  color: AppColors.plasma.withValues(alpha: 0.4),
                  blurRadius: 20,
                )],
              ),
              child: const Text('Добавить подписку', style: TextStyle(
                fontFamily: 'Syne', fontSize: 15,
                fontWeight: FontWeight.w700, color: Colors.white,
              )),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Модель ────────────────────────────────────────────────────────────────

class _SubEntry {
  const _SubEntry({required this.name, required this.url});
  final String name, url;
}
