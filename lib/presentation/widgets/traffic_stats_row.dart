import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/vpn_state.dart';

class TrafficStatsRow extends StatelessWidget {
  const TrafficStatsRow({super.key, required this.state});
  final VpnConnected state;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        gradient: AppColors.gradientGlass(),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.horizonGlow),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _Stat(
            icon: Icons.arrow_downward_rounded,
            iconColor: AppColors.aurora,
            label: 'Получено',
            value: _fmtBytes(state.rxBytes),
          ),
          _VDivider(),
          _Stat(
            icon: Icons.timer_outlined,
            iconColor: AppColors.plasmaLight,
            label: 'Время',
            value: _fmtDuration(state.uptime),
          ),
          _VDivider(),
          _Stat(
            icon: Icons.arrow_upward_rounded,
            iconColor: AppColors.plasma,
            label: 'Отправлено',
            value: _fmtBytes(state.txBytes),
          ),
        ],
      ),
    );
  }

  String _fmtBytes(int b) {
    if (b < 1024) return '${b}Б';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)}КБ';
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)}МБ';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)}ГБ';
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: 16),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Syne',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.nebula0,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'DM Sans',
            fontSize: 10,
            color: AppColors.nebula2,
          ),
        ),
      ],
    );
  }
}

class _VDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 40, color: AppColors.horizon);
}
