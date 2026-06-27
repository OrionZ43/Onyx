import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'core/theme/app_colors.dart';
import 'install_logic.dart';

class InstallerScreen extends StatefulWidget {
  const InstallerScreen({super.key});

  @override
  State<InstallerScreen> createState() => _InstallerScreenState();
}

class _InstallerScreenState extends State<InstallerScreen> {
  double _progress = 0.0;
  String _status = 'Ready to install';
  bool _isInstalling = false;
  bool _hasError = false;

  void _startInstall() {
    setState(() {
      _isInstalling = true;
      _hasError = false;
    });

    InstallLogic.install((progress, status) {
      if (!mounted) return;
      setState(() {
        if (progress < 0) {
          _hasError = true;
          _progress = 0;
          _status = status;
          _isInstalling = false;
        } else {
          _progress = progress;
          _status = status;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.gradientVoid),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppColors.void2,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ShaderMask(
                    shaderCallback: (bounds) =>
                        AppColors.gradientPlasma.createShader(bounds),
                    child: const Text(
                      'ONYX INSTALLER',
                      style: TextStyle(
                        fontFamily: 'Syne',
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ).animate().fadeIn().slideY(begin: -0.2),
                  const SizedBox(height: 32),

                  if (_isInstalling || _progress > 0) ...[
                    Text(
                      _status,
                      style: TextStyle(
                        color: _hasError ? AppColors.nova : AppColors.nebula1,
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _progress,
                        minHeight: 8,
                        backgroundColor: AppColors.glass,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.plasma,
                        ),
                      ),
                    ),
                  ] else ...[
                    ElevatedButton(
                      onPressed: _startInstall,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.plasma,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 48,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'INSTALL',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ).animate().fadeIn().scale(begin: const Offset(0.95, 0.95)),
        ),
      ),
    );
  }
}
