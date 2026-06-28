import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../infrastructure/update_service.dart';
import '../screens/update_screen.dart';

class UpdateBanner extends StatelessWidget {
  final UpdateInfo updateInfo;

  const UpdateBanner({super.key, required this.updateInfo});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => UpdateScreen(updateInfo: updateInfo),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: AppColors.gradientPlasma,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppColors.plasma.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.system_update, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Доступно обновление: ${updateInfo.version}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'DM Sans',
                ),
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
          ],
        ),
      ),
    );
  }
}
