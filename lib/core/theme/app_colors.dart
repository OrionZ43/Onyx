import 'package:flutter/material.dart';

abstract final class AppColors {
  // ── Void (backgrounds) ────────────────────────────────────────────────────
  static const void0 = Color(0xFF03020A); // абсолютная тьма
  static const void1 = Color(0xFF07060F); // основной фон
  static const void2 = Color(0xFF0C0B18); // поверхность карточек
  static const void3 = Color(0xFF121020); // приподнятые элементы

  // ── Glass (жидкое стекло) ─────────────────────────────────────────────────
  static const glass        = Color(0x14FFFFFF); // стеклянная подложка
  static const glassBorder  = Color(0x22FFFFFF); // обводка стекла
  static const glassShine   = Color(0x08FFFFFF); // блик сверху
  static const glassDeep    = Color(0x0A8080FF); // синеватое свечение стекла

  // ── Plasma (главный акцент — электрический индиго) ────────────────────────
  static const plasma       = Color(0xFF7B6FFF); // основной CTA
  static const plasmaLight  = Color(0xFFADA3FF); // светлый вариант
  static const plasmaDim    = Color(0xFF4A41CC); // тёмный вариант
  static const plasmaGlow   = Color(0x557B6FFF); // свечение
  static const plasmaTrace  = Color(0x1A7B6FFF); // еле заметный след

  // ── Aurora (подключено — живое зелёное) ───────────────────────────────────
  static const aurora       = Color(0xFF00F5B4); // connected
  static const auroraGlow   = Color(0x4400F5B4);
  static const auroraDim    = Color(0xFF00A87B);

  // ── Ember (переходное состояние) ──────────────────────────────────────────
  static const ember        = Color(0xFFFFAA44);
  static const emberGlow    = Color(0x44FFAA44);

  // ── Nova (ошибка) ─────────────────────────────────────────────────────────
  static const nova         = Color(0xFFFF4D6D);
  static const novaGlow     = Color(0x44FF4D6D);

  // ── Nebula (текст) ────────────────────────────────────────────────────────
  static const nebula0      = Color(0xFFEEEDFF); // primary text
  static const nebula1      = Color(0xFF8B89B0); // secondary text
  static const nebula2      = Color(0xFF3D3B5E); // disabled text

  // ── Horizon (разделители) ─────────────────────────────────────────────────
  static const horizon      = Color(0xFF1A1830); // border
  static const horizonGlow  = Color(0x337B6FFF); // glowing border

  // ── Gradients ─────────────────────────────────────────────────────────────

  /// Глубокий космос — фон всего приложения
  static const gradientVoid = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0D0420), Color(0xFF03020A), Color(0xFF02071A)],
    stops: [0.0, 0.5, 1.0],
  );

  /// Плазменный — кнопки, CTA
  static const gradientPlasma = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF9B8FFF), Color(0xFF6B5FEF), Color(0xFF5040CC)],
    stops: [0.0, 0.5, 1.0],
  );

  /// Аврора — подключено
  static const gradientAurora = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF00F5B4), Color(0xFF00C4D4)],
  );

  /// Стекло — карточки
  static LinearGradient gradientGlass({double opacity = 1.0}) => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      // ИСПРАВЛЕНО: добавлен const к конструкторам Color
      const Color(0x18FFFFFF).withValues(alpha: 0.09 * opacity),
      const Color(0x06FFFFFF).withValues(alpha: 0.03 * opacity),
    ],
  );

  /// Туманность — фоновые пятна
  static const gradientNebula = RadialGradient(
    center: Alignment(0, -0.25),
    radius: 1.3,
    colors: [Color(0xFF1E0A45), Color(0xFF07060F), Color(0xFF020B1E)],
    stops: [0.0, 0.55, 1.0],
  );
}