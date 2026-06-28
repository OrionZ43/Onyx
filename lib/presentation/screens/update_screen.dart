import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/glass_widget.dart';
import '../../infrastructure/update_service.dart';

class UpdateScreen extends StatefulWidget {
  final UpdateInfo updateInfo;

  const UpdateScreen({super.key, required this.updateInfo});

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  final UpdateService _updateService = UpdateService();
  bool _isDownloading = false;
  double _progress = 0.0;
  String _error = '';

  Future<void> _startUpdate() async {
    setState(() {
      _isDownloading = true;
      _error = '';
    });

    try {
      final zipPath = await _updateService.downloadUpdate(
        widget.updateInfo.downloadUrl,
        onProgress: (p) {
          setState(() {
            _progress = p;
          });
        },
      );

      await _updateService.applyUpdate(zipPath);
      exit(0);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isDownloading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.void1,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: GlassCard(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) =>
                      AppColors.gradientPlasma.createShader(bounds),
                  child: Text(
                    'Доступно обновление ${widget.updateInfo.version}',
                    style: const TextStyle(
                      fontFamily: 'Syne',
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
                GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: SingleChildScrollView(
                      child: Text(
                        widget.updateInfo.releaseNotes,
                        style: const TextStyle(
                          fontFamily: 'DM Sans',
                          color: AppColors.nebula1,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                if (_error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _error,
                      style: const TextStyle(color: AppColors.nova),
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (_isDownloading) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: _progress,
                      minHeight: 8,
                      backgroundColor: AppColors.glass,
                      color: AppColors.plasma,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${(_progress * 100).toStringAsFixed(1)}%',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.nebula0),
                  ),
                ] else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Позже',
                            style: TextStyle(color: AppColors.nebula1)),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: _startUpdate,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.plasma,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Обновить'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ).animate().fadeIn().scale(begin: const Offset(0.95, 0.95)),
        ),
      ),
    );
  }
}
