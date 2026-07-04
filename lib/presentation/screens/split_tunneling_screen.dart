import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/glass_widget.dart';
import '../../infrastructure/platform_features.dart';
import '../providers/settings_provider.dart';

/// Экран выбора приложений, работающих в обход VPN (split tunneling).
///
/// Стиль повторяет settings_screen: шапка с BackdropFilter blur 20,
/// подложка Color(0x99050410), кнопка «назад» 36×36. Список приложений
/// грузится с нативной стороны (PlatformFeatures.getInstalledApps), иконки
/// не тянем — рисуем glass-аватар с первой буквой имени. Системные
/// приложения по умолчанию скрыты (их сотни), с переключателем «показать».
class SplitTunnelingScreen extends ConsumerStatefulWidget {
  const SplitTunnelingScreen({super.key});

  @override
  ConsumerState<SplitTunnelingScreen> createState() =>
      _SplitTunnelingScreenState();
}

class _SplitTunnelingScreenState extends ConsumerState<SplitTunnelingScreen> {
  List<InstalledApp>? _apps;
  String _query = '';
  bool _showSystem = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apps = await PlatformFeatures.instance.getInstalledApps();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _loading = false;
    });
  }

  List<InstalledApp> get _filtered {
    final apps = _apps ?? const [];
    final q = _query.trim().toLowerCase();
    return apps.where((a) {
      if (!_showSystem && a.isSystem) return false;
      if (q.isEmpty) return true;
      return a.appName.toLowerCase().contains(q) ||
          a.packageName.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final excluded = ref.watch(
      settingsProvider.select((s) => s.excludedApps),
    );
    final filtered = _filtered;

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
                    _header(context, excluded.length),
                    _searchBar(),
                    Expanded(
                      child: _loading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.plasma,
                              ),
                            )
                          : filtered.isEmpty
                              ? const Center(
                                  child: Text(
                                    'Ничего не найдено',
                                    style: TextStyle(
                                      fontFamily: 'DM Sans',
                                      color: AppColors.nebula1,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                      20, 8, 20, 24),
                                  itemCount: filtered.length,
                                  itemBuilder: (context, i) {
                                    final app = filtered[i];
                                    final isExcluded =
                                        excluded.contains(app.packageName);
                                    return _AppRow(
                                      app: app,
                                      excluded: isExcluded,
                                      onChanged: (val) => ref
                                          .read(settingsProvider.notifier)
                                          .setAppExcluded(
                                              app.packageName, val),
                                    );
                                  },
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

  Widget _header(BuildContext context, int excludedCount) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: const BoxDecoration(
            color: Color(0x99050410),
            border: Border(
              bottom: BorderSide(color: AppColors.glassBorder),
            ),
          ),
          child: Row(
            children: [
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
                    border: Border.all(color: AppColors.glassBorder),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_rounded,
                    size: 14,
                    color: AppColors.nebula1,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Обход VPN',
                      style: TextStyle(
                        fontFamily: 'Syne',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.nebula0,
                      ),
                    ),
                    Text(
                      excludedCount == 0
                          ? 'Приложения не выбраны'
                          : '$excludedCount в обход туннеля',
                      style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 12,
                        color: AppColors.nebula1,
                      ),
                    ),
                  ],
                ),
              ),
              // Тумблер показа системных приложений
              GestureDetector(
                onTap: () => setState(() => _showSystem = !_showSystem),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _showSystem
                        ? AppColors.plasmaTrace
                        : AppColors.glass,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _showSystem
                          ? AppColors.plasma
                          : AppColors.glassBorder,
                    ),
                  ),
                  child: Text(
                    'Системные',
                    style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 12,
                      color: _showSystem
                          ? AppColors.plasmaLight
                          : AppColors.nebula1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        borderRadius: 14,
        child: TextField(
          onChanged: (v) => setState(() => _query = v),
          style: const TextStyle(
            fontFamily: 'DM Sans',
            fontSize: 14,
            color: AppColors.nebula0,
          ),
          cursorColor: AppColors.plasma,
          decoration: const InputDecoration(
            hintText: 'Поиск приложения…',
            hintStyle: TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 14,
              color: AppColors.nebula2,
            ),
            icon: Icon(Icons.search_rounded, color: AppColors.nebula1, size: 20),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.app,
    required this.excluded,
    required this.onChanged,
  });

  final InstalledApp app;
  final bool excluded;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final letter =
        (app.appName.isNotEmpty ? app.appName[0] : '?').toUpperCase();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        borderRadius: 14,
        child: Row(
          children: [
            // Glass-аватар с первой буквой (иконки не тянем — см. коммент
            // в MainActivity.getInstalledApps).
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.plasmaTrace,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Text(
                letter,
                style: const TextStyle(
                  fontFamily: 'Syne',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.plasmaLight,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app.appName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.nebula0,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    app.packageName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 11,
                      color: AppColors.nebula2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch.adaptive(
              value: excluded,
              activeThumbColor: AppColors.plasma,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
