import 'package:flutter/material.dart';

abstract final class AppColors {
  // ── Void (Backgrounds) ────────────────────────────────────────────────────
  static const void0 = Color(0xFF000000); // Абсолютная тьма (Onyx Black)
  static const void1 = Color(0xFF050508); // Глубокий космос
  static const void2 = Color(0xFF0A0A10); // Поверхность карточек
  static const void3 = Color(0xFF12121A); // Приподнятые элементы

  // ── Glass (Премиальное матовое стекло) ────────────────────────────────────
  static const glass = Color(0x0AFFFFFF); // Едва заметная подложка
  static const glassBorder = Color(0x1AFFFFFF); // Тонкая серебряная обводка

  // ── Accents (Благородные металлы) ─────────────────────────────────────────
  static const accentGold = Color(0xFFD4AF37); // Stardust Gold (Подключено)
  static const accentGoldGlow = Color(0x44D4AF37);

  static const accentSilver = Color(0xFF8A9DB0); // Холодное серебро (Отключено)
  static const accentSilverGlow = Color(0x228A9DB0);

  static const nova = Color(0xFFE54B4B); // Красный карлик (Ошибка)

  // ── Text (Nebula) ─────────────────────────────────────────────────────────
  static const nebula0 = Color(0xFFFFFFFF); // Чистый белый
  static const nebula1 = Color(0xFFA0A5B5); // Пепельно-серый
  static const nebula2 = Color(0xFF5A6070); // Глубокий серый

  static const horizon = Color(0xFF1A1A24); // Разделители

  static LinearGradient gradientGlass({double opacity = 1.0}) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0x15FFFFFF).withOpacity(opacity),
          const Color(0x05FFFFFF).withOpacity(opacity),
        ],
      );

  static const gradientNebula = RadialGradient(
    center: Alignment(0, -0.2),
    radius: 1.5,
    colors: [Color(0xFF0B0F1C), Color(0xFF050508), Color(0xFF000000)],
    stops: [0.0, 0.6, 1.0],
  );
}
