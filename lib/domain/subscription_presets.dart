/// Встроенная публичная подписка с зеркалами.
class SubscriptionPreset {
  const SubscriptionPreset({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.url,
    this.mirrors = const [],
  });

  final String id;
  final String title;
  final String subtitle;

  /// Основной URL. По нему же пресет узнаётся в сохранённых настройках.
  final String url;

  /// Зеркала того же файла: перебираются, если основной URL недоступен
  /// (raw.githubusercontent.com в Китае обычно режется).
  final List<String> mirrors;
}

/// Встроенные бесплатные подписки.
///
/// ВНИМАНИЕ: это чужие публичные ноды. Они живут часы или дни, бывают
/// перегружены, владелец ноды видит метаданные трафика. Onyx отбирает живые
/// (TCP → HTTPS → STUN/UDP) и переключается сам, но стабильности это не
/// гарантирует.
abstract final class SubscriptionPresets {
  static const _pawdroidPath = 'Pawdroid/Free-servers/main/sub';

  /// Бесплатные ноды для материкового Китая: Pawdroid/Free-servers
  /// (~20 нод, обновление ~раз в 6 часов: VLESS REALITY, Hysteria2, SS).
  static const chinaFree = SubscriptionPreset(
    id: 'china-free',
    title: 'Бесплатные (Китай)',
    subtitle: 'бесплатные, нестабильные · обновляются каждые ~6 ч',
    url: 'https://raw.githubusercontent.com/$_pawdroidPath',
    mirrors: [
      'https://ghfast.top/https://raw.githubusercontent.com/$_pawdroidPath',
      'https://gh-proxy.com/https://raw.githubusercontent.com/$_pawdroidPath',
      'https://cdn.jsdmirror.com/gh/Pawdroid/Free-servers@main/sub',
      'https://fastly.jsdelivr.net/gh/Pawdroid/Free-servers@main/sub',
    ],
  );

  static const all = [chinaFree];

  static SubscriptionPreset? byUrl(String url) {
    final u = url.trim();
    for (final p in all) {
      if (p.url == u) return p;
    }
    return null;
  }
}
