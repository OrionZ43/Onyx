import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/glass_widget.dart';
import '../../core/log_service.dart';

class LogScreen extends ConsumerStatefulWidget {
  const LogScreen({super.key});
  @override
  ConsumerState<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends ConsumerState<LogScreen> {
  final _scroll   = ScrollController();
  bool _autoScroll = true;
  LogLevel? _filter;

  @override
  void dispose() { _scroll.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final svc     = ref.watch(logProvider);
    final entries = _filter == null
        ? svc.entries
        : svc.entries.where((e) => e.level == _filter).toList();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_autoScroll && _scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });

    return Scaffold(
      backgroundColor: AppColors.void0,
      body: Stack(
        children: [
          // Фоновый градиент
          Container(decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF0D0420), Color(0xFF03020A), Color(0xFF02091A)],
            ),
          )),

          SafeArea(
            child: Column(
              children: [
                // Шапка
                ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Color(0x99050410),
                        border: Border(bottom: BorderSide(color: AppColors.glassBorder)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(children: [
                        // Назад
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
                        const SizedBox(width: 12),

                        // Иконка терминала
                        ShaderMask(
                          shaderCallback: (b) => AppColors.gradientPlasma
                              .createShader(Rect.fromLTWH(0, 0, b.width, b.height)),
                          child: const Icon(Icons.terminal_rounded,
                              color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 10),
                        const Text('Консоль отладки', style: TextStyle(
                          fontFamily: 'Syne', fontSize: 16,
                          fontWeight: FontWeight.w700, color: AppColors.nebula0,
                        )),
                        const SizedBox(width: 8),

                        // Счётчик
                        GlassPill(
                          color: AppColors.plasma,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          child: Text('${entries.length}', style: const TextStyle(
                            fontFamily: 'DM Sans', fontSize: 11,
                            color: AppColors.plasmaLight, fontWeight: FontWeight.w700,
                          )),
                        ),
                        const Spacer(),

                        // Фильтр
                        _FilterBtn(current: _filter,
                            onChanged: (v) => setState(() => _filter = v)),
                        const SizedBox(width: 8),

                        // Копировать
                        _HeaderBtn(
                          icon: Icons.copy_rounded,
                          tooltip: 'Скопировать всё',
                          onTap: () async {
                            await Clipboard.setData(
                                ClipboardData(text: svc.exportText()));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Лог скопирован — отправь разработчику 📋'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                        ),
                        const SizedBox(width: 8),

                        // Очистить
                        _HeaderBtn(
                          icon: Icons.delete_outline_rounded,
                          tooltip: 'Очистить',
                          onTap: svc.clear,
                        ),
                      ]),
                    ),
                  ),
                ),

                // Строка авто-прокрутки
                Container(
                  color: AppColors.void2,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(children: [
                    const Icon(Icons.circle, size: 6, color: AppColors.aurora),
                    const SizedBox(width: 8),
                    const Text('Onyx Debug Console v0.1',
                        style: TextStyle(
                          fontFamily: 'DM Sans', fontSize: 10,
                          color: AppColors.nebula2, fontStyle: FontStyle.italic,
                        )),
                    const Spacer(),
                    const Text('Авто-прокрутка', style: TextStyle(
                        fontFamily: 'DM Sans', fontSize: 10, color: AppColors.nebula2)),
                    const SizedBox(width: 6),
                    Transform.scale(
                      scale: 0.7,
                      child: Switch.adaptive(
                        value: _autoScroll,
                        onChanged: (v) => setState(() => _autoScroll = v),
                        activeThumbColor: AppColors.plasma,
                      ),
                    ),
                  ]),
                ),

                // Записи
                Expanded(
                  child: entries.isEmpty
                  // ИСПРАВЛЕНО: добавлен const
                      ? const _EmptyState()
                      : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                        vertical: 8, horizontal: 0),
                    itemCount: entries.length,
                    itemBuilder: (_, i) => _LogRow(entry: entries[i]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderBtn extends StatelessWidget {
  const _HeaderBtn({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Tooltip(
      message: tooltip,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: AppColors.glass,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Icon(icon, size: 15, color: AppColors.nebula1),
      ),
    ),
  );
}

class _FilterBtn extends StatelessWidget {
  const _FilterBtn({required this.current, required this.onChanged});
  final LogLevel? current;
  final ValueChanged<LogLevel?> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<LogLevel?>(
    color: AppColors.void2,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: AppColors.glassBorder),
    ),
    onSelected: onChanged,
    child: Container(
      width: 34, height: 34,
      decoration: BoxDecoration(
        color: current != null ? AppColors.plasmaTrace : AppColors.glass,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: current != null ? AppColors.horizonGlow : AppColors.glassBorder,
        ),
      ),
      child: Icon(Icons.filter_list_rounded,
          size: 16,
          color: current != null ? AppColors.plasma : AppColors.nebula1),
    ),
    itemBuilder: (_) => [
      _item(null,           'Все',      Icons.list_rounded,          AppColors.nebula1),
      _item(LogLevel.debug, 'Debug',    Icons.bug_report_outlined,   AppColors.nebula2),
      _item(LogLevel.info,  'Info',     Icons.info_outline_rounded,  AppColors.plasmaLight),
      _item(LogLevel.warn,  'Warning',  Icons.warning_amber_rounded, AppColors.ember),
      _item(LogLevel.error, 'Error',    Icons.error_outline_rounded, AppColors.nova),
    ],
  );

  PopupMenuItem<LogLevel?> _item(
      LogLevel? level, String label, IconData icon, Color color,
      ) => PopupMenuItem(
    value: level,
    // ИСПРАВЛЕНО: добавлен const к Row и его children-литералу
    child: Row(children: [
      Icon(icon, size: 15, color: level == current ? AppColors.plasma : color),
      const SizedBox(width: 10),
      Text(label, style: TextStyle(
        fontFamily: 'DM Sans', fontSize: 13,
        color: level == current ? AppColors.plasma : AppColors.nebula0,
      )),
    ]),
  );
}

class _EmptyState extends StatelessWidget {
  // ИСПРАВЛЕНО: добавлен const конструктор
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.receipt_long_outlined, color: AppColors.nebula2, size: 44),
      const SizedBox(height: 12),
      const Text('Логов пока нет', style: TextStyle(
          fontFamily: 'Syne', fontSize: 15, color: AppColors.nebula2)),
      const SizedBox(height: 4),
      const Text('Здесь появятся события приложения', style: TextStyle(
          fontFamily: 'DM Sans', fontSize: 12, color: AppColors.nebula2)),
    ]),
  );
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});
  final LogEntry entry;

  Color get _levelColor => switch (entry.level) {
    LogLevel.debug => AppColors.nebula2,
    LogLevel.info  => AppColors.plasmaLight,
    LogLevel.warn  => AppColors.ember,
    LogLevel.error => AppColors.nova,
  };

  Color get _bg => switch (entry.level) {
    LogLevel.error => AppColors.nova.withValues(alpha: 0.04),
    LogLevel.warn  => AppColors.ember.withValues(alpha: 0.03),
    _              => Colors.transparent,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Время
          Text(entry.timeStr, style: const TextStyle(
            fontFamily: 'DM Mono', fontSize: 10, color: AppColors.nebula2,
          )),
          const SizedBox(width: 8),

          // Уровень
          Container(
            width: 30,
            padding: const EdgeInsets.symmetric(vertical: 1),
            decoration: BoxDecoration(
              color: _levelColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(entry.levelLabel,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'DM Mono', fontSize: 9,
                  fontWeight: FontWeight.w700, color: _levelColor,
                )),
          ),
          const SizedBox(width: 6),

          // Тег
          Text('[${entry.tag}]', style: TextStyle(
            fontFamily: 'DM Mono', fontSize: 10,
            color: AppColors.plasma.withValues(alpha: 0.5),
          )),
          const SizedBox(width: 6),

          // Сообщение
          Expanded(
            child: Text(entry.message, style: TextStyle(
              fontFamily: 'DM Mono', fontSize: 11,
              color: _levelColor == AppColors.nebula2
                  ? AppColors.nebula1 : _levelColor,
              height: 1.4,
            )),
          ),
        ],
      ),
    );
  }
}