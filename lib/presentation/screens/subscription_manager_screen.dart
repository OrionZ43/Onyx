// lib/presentation/screens/subscription_manager_screen.dart
//
// ИСПРАВЛЕНИЯ:
//  1. Убраны ВСЕ WidgetsBinding.instance.addPostFrameCallback при навигации.
//     Используется прямой Navigator.of(context).pop() с проверкой mounted.
//  2. Desktop-first layout: ConstrainedBox maxWidth 700, центрированный.
//  3. Диалоги добавления/редактирования уже используют showDialog — ок.

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/glass_widget.dart';
import '../providers/subscription_provider.dart';

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

    setState(() {
      _entries = saved.map((s) {
        final parts = s.split('||');
        return _SubEntry(
          name: parts.length > 1 ? parts[0] : 'Подписка',
          url: parts.length > 1 ? parts[1] : parts[0],
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
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Column(
                  children: [
                    // ── Шапка ─────────────────────────────────────────────
                    ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          decoration: const BoxDecoration(
                            color: Color(0x99050410),
                            border: Border(
                              bottom: BorderSide(color: AppColors.glassBorder),
                            ),
                          ),
                          child: Row(
                            children: [
                              // ── БАГ-ФИX: убран addPostFrameCallback ──────
                              GestureDetector(
                                onTap: () {
                                  if (!context.mounted) return;
                                  Navigator.of(context).pop();
                                },
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: AppColors.glass,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: AppColors.glassBorder,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.arrow_back_ios_rounded,
                                    size: 14,
                                    color: AppColors.nebula1,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              const Text(
                                'Подписки',
                                style: TextStyle(
                                  fontFamily: 'Syne',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.nebula0,
                                ),
                              ),
                              const Spacer(),
                              // Добавить
                              GestureDetector(
                                onTap: _showAddDialog,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: AppColors.gradientPlasma,
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.plasma.withValues(
                                          alpha: 0.35,
                                        ),
                                        blurRadius: 12,
                                      ),
                                    ],
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.add_rounded,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        'Добавить',
                                        style: TextStyle(
                                          fontFamily: 'Syne',
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // ── Статус текущей загрузки ───────────────────────────
                    if (sub.status == SubStatus.fetching ||
                        sub.status == SubStatus.probing)
                      Container(
                        color: AppColors.plasma.withValues(alpha: 0.06),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: AppColors.plasma,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              sub.status == SubStatus.fetching
                                  ? 'Загружаем серверы...'
                                  : 'Проверяем серверы... '
                                      '${sub.probedCount}/${sub.nodes.length}',
                              style: const TextStyle(
                                fontFamily: 'DM Sans',
                                fontSize: 12,
                                color: AppColors.nebula1,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // ── Список подписок ────────────────────────────────────
                    Expanded(
                      child: _loading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.plasma,
                              ),
                            )
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
                                  )
                                      .animate(delay: (i * 60).ms)
                                      .fadeIn(duration: 300.ms)
                                      .slideY(begin: 0.15),
                                ),
                    ),

                    // ── Подсказка ──────────────────────────────────────────
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        8,
                        20,
                        MediaQuery.of(context).padding.bottom + 12,
                      ),
                      child: const Text(
                        'Поддерживаются ссылки на VLESS-подписки '
                        'и прямые base64-строки',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 11,
                          color: AppColors.nebula2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _loadSub(_SubEntry entry) {
    ref.read(subscriptionProvider.notifier).loadFromUrl(entry.url);
    // БАГ-ФИX: убран addPostFrameCallback
    if (!context.mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _deleteSub(int index) async {
    setState(() => _entries.removeAt(index));
    await _saveEntries();
  }

  void _showAddDialog() => _showSubDialog();
  void _showEditDialog(int index) =>
      _showSubDialog(existing: _entries[index], editIndex: index);

  Future<void> _showSubDialog({_SubEntry? existing, int? editIndex}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final urlCtrl = TextEditingController(text: existing?.url ?? '');

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
              fontFamily: 'Syne',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.nebula0,
            ),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DialogField(
                  controller: nameCtrl,
                  label: 'Название',
                  hint: 'Мой VPN',
                  icon: Icons.label_outline_rounded,
                ),
                const SizedBox(height: 12),
                _DialogField(
                  controller: urlCtrl,
                  label: 'URL подписки',
                  hint: 'https://example.com/sub',
                  icon: Icons.link_rounded,
                  keyboardType: TextInputType.url,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text(
                'Отмена',
                style: TextStyle(
                  color: AppColors.nebula1,
                  fontFamily: 'DM Sans',
                ),
              ),
            ),
            GestureDetector(
              onTap: () {
                final url = urlCtrl.text.trim();
                final name = nameCtrl.text.trim();
                if (url.isEmpty) return;
                Navigator.of(ctx).pop(
                  _SubEntry(name: name.isEmpty ? 'Подписка' : name, url: url),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  gradient: AppColors.gradientPlasma,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.plasma.withValues(alpha: 0.3),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: Text(
                  existing == null ? 'Добавить' : 'Сохранить',
                  style: const TextStyle(
                    fontFamily: 'Syne',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
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
  }
}

// ── Dialog field ──────────────────────────────────────────────────────────

class _DialogField extends StatelessWidget {
  const _DialogField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
  });
  final TextEditingController controller;
  final String label, hint;
  final IconData icon;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 12,
              color: AppColors.nebula1,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: AppColors.void3,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(icon, size: 16, color: AppColors.nebula2),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: controller,
                    keyboardType: keyboardType,
                    autocorrect: false,
                    style: const TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 13,
                      color: AppColors.nebula0,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: hint,
                      hintStyle: const TextStyle(
                        color: AppColors.nebula2,
                        fontSize: 13,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ],
      );
}

// ── Empty state ───────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, color: AppColors.nebula2, size: 64),
            const SizedBox(height: 20),
            const Text(
              'Нет подписок',
              style: TextStyle(
                fontFamily: 'Syne',
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.nebula1,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Добавьте ссылку на VLESS-подписку\nчтобы начать',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 13,
                color: AppColors.nebula2,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: onAdd,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                  gradient: AppColors.gradientPlasma,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.plasma.withValues(alpha: 0.35),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Добавить подписку',
                      style: TextStyle(
                        fontFamily: 'Syne',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

// ── Sub card ──────────────────────────────────────────────────────────────

class _SubCard extends StatelessWidget {
  const _SubCard({
    required this.entry,
    required this.isActive,
    required this.nodeCount,
    required this.aliveCount,
    required this.onLoad,
    required this.onDelete,
    required this.onEdit,
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
      glowColor: isActive ? AppColors.plasma.withValues(alpha: 0.2) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Иконка
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: isActive
                      ? AppColors.gradientPlasma
                      : const LinearGradient(
                          colors: [AppColors.void3, AppColors.void3],
                        ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.rss_feed_rounded,
                  color: isActive ? Colors.white : AppColors.nebula2,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),

              // Название + URL
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      style: TextStyle(
                        fontFamily: 'Syne',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isActive ? AppColors.plasma : AppColors.nebula0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.url,
                      style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 11,
                        color: AppColors.nebula2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Активный бейдж
              if (isActive && nodeCount != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.plasma.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.plasma.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '$aliveCount/$nodeCount нод',
                    style: const TextStyle(
                      fontFamily: 'DM Mono',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.plasma,
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 12),

          // Кнопки действий
          Row(
            children: [
              // Загрузить / Активна
              Expanded(
                child: GestureDetector(
                  onTap: isActive ? null : onLoad,
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: isActive ? null : AppColors.gradientPlasma,
                      color: isActive ? AppColors.void3 : null,
                      borderRadius: BorderRadius.circular(10),
                      border: isActive
                          ? Border.all(color: AppColors.glassBorder)
                          : null,
                      boxShadow: isActive
                          ? null
                          : [
                              BoxShadow(
                                color: AppColors.plasma.withValues(alpha: 0.25),
                                blurRadius: 10,
                              ),
                            ],
                    ),
                    child: Center(
                      child: Text(
                        isActive ? '✓ Активна' : 'Загрузить',
                        style: TextStyle(
                          fontFamily: 'Syne',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isActive ? AppColors.nebula2 : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Редактировать
              _ActionBtn(
                icon: Icons.edit_outlined,
                onTap: onEdit,
                color: AppColors.nebula1,
              ),
              const SizedBox(width: 6),

              // Удалить
              _ActionBtn(
                icon: Icons.delete_outline_rounded,
                onTap: onDelete,
                color: AppColors.nova,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.onTap,
    required this.color,
  });
  final IconData icon;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      );
}

// ── Data class ────────────────────────────────────────────────────────────

class _SubEntry {
  const _SubEntry({required this.name, required this.url});
  final String name, url;
}
