import 'entities/node.dart';

/// Умная система весов (Scoring System) для приоритизации нод перед Deep Probe.
///
/// ## Мотивация
///
/// Наивная сортировка по [Node.latencyMs] проигрывает в реальных условиях РФ:
/// обычный TLS-сервер с пингом 40 мс обрывает UDP-трафик (Discord) через
/// 10–15 секунд из-за ТСПУ, тогда как REALITY-нода с пингом 60 мс работает
/// идеально. Географическая близость дополнительно снижает latency для голоса.
///
/// ## Формула (чем МЕНЬШЕ счёт — тем ВЫШЕ приоритет)
///
/// ```
/// score = latencyMs               // базовый (9999 если null / нода мертва)
///       − 5000  if reality        // протокол невидим для ТСПУ
///       − 2000  if optimal_geo    // Германия, Нидерланды, Польша, Финляндия,
///                                 // Швеция, Турция, Великобритания
/// ```
///
/// ## Примеры
///
/// | Нода                         | latency | security | geo  | score  |
/// |------------------------------|---------|----------|------|--------|
/// | 🇩🇪 REALITY DE               | 60 ms   | reality  | ✅   | −6940  |
/// | 🇩🇪 TLS DE                   | 40 ms   | tls      | ✅   | −1960  |
/// | 🇺🇸 REALITY US               | 150 ms  | reality  | ❌   | −4850  |
/// | 🇺🇸 TLS US (обманка CDN)     | 10 ms   | tls      | ❌   | 10     |
/// | Мёртвая нода                 | null    | any      | any  | в конце|
///
/// REALITY DE (−6940) занимает первое место и идёт в Deep Probe первой.
class NodeScorer {
  // Приватный конструктор: класс используется только через статические методы.
  const NodeScorer._();

  // ── Веса бонусов ──────────────────────────────────────────────────────────

  /// Бонус за REALITY: протокол использует уникальный TLS-стек (uTLS + XTLS
  /// Vision), статистически неотличимый от легитимного HTTPS.
  /// ТСПУ не может его идентифицировать и заблокировать UDP-трафик.
  static const int _realityBonus = 5000;

  /// Бонус за оптимальную для РФ географию: минимальный RTT для голоса/видео
  /// и максимальная вероятность доступности при блокировках.
  static const int _geoBonus = 2000;

  // ── Оптимальные локации для РФ ────────────────────────────────────────────

  /// Unicode-флаги (code points U+1F1E6..U+1F1FF в парах) оптимальных стран.
  /// Используем Set для O(1) поиска.
  static const Set<String> _optimalFlags = {
    '🇩🇪', // Германия       — короткий маршрут, сильная инфра
    '🇳🇱', // Нидерланды     — крупнейший европейский IXP (AMS-IX)
    '🇵🇱', // Польша         — рядом с РФ, много дешёвых дедиков
    '🇫🇮', // Финляндия      — граница с РФ, исторически низкий пинг
    '🇸🇪', // Швеция         — балтийские кабели, стабильность
    '🇹🇷', // Турция         — нейтральная юрисдикция, хорошая связность
    '🇬🇧', // Великобритания — Лондон как крупный интернет-хаб
  };

  /// Текстовые ключевые слова тех же локаций (сравнение без учёта регистра).
  /// Покрывают случаи, когда флаг не используется в имени ноды.
  static const List<String> _optimalKeywords = [
    // Германия
    'germany', 'german', 'de-', 'frankfurt', 'berlin', 'munich',
    // Нидерланды
    'netherlands', 'dutch', 'holland', 'amsterdam',
    // Польша
    'poland', 'polish', 'warsaw',
    // Финляндия
    'finland', 'finnish', 'helsinki',
    // Швеция
    'sweden', 'swedish', 'stockholm',
    // Турция
    'turkey', 'turkish', 'istanbul',
    // Великобритания
    'united kingdom', 'britain', 'british', 'london',
    // Двухбуквенные ISO-коды в имени (например "| NL |" или "NL-01")
    // Используем слова целиком, чтобы избежать ложных срабатываний.
    // Короткие коды ищем отдельно в _containsIsoCode().
  ];

  /// Двухбуквенные ISO 3166-1 коды оптимальных стран для точного поиска.
  static const Set<String> _optimalIsoCodes = {
    'de',
    'nl',
    'pl',
    'fi',
    'se',
    'tr',
    'gb',
    'uk',
  };

  // ── Публичный API ─────────────────────────────────────────────────────────

  /// Вычисляет приоритетный счёт ноды. **Меньше = лучше = выше в списке.**
  ///
  /// Вызывайте только после Этапа 1 (TCP-пинг), когда [node.latencyMs] уже
  /// заполнен. Для мёртвых нод (не [node.isAlive]) возвращает [_deadScore].
  static int score(Node node) {
    // Мёртвые ноды получают максимальный штрафной счёт.
    if (!node.isAlive) return _deadScore;

    int s = node.latencyMs ?? 9999;

    // Бонус за протокол REALITY (наивысший приоритет).
    if (node.security == 'reality') {
      s -= _realityBonus;
    }

    // Бонус за оптимальную географию.
    if (_isOptimalGeo(node.name)) {
      s -= _geoBonus;
    }

    return s;
  }

  /// Компаратор для [List.sort]: сортирует по возрастанию [score].
  /// Живые ноды всегда идут перед мёртвыми.
  ///
  /// Использование:
  /// ```dart
  /// nodes.sort(NodeScorer.compare);
  /// ```
  static int compare(Node a, Node b) {
    // Мёртвые в конец, независимо от score.
    if (!a.isAlive && !b.isAlive) return 0;
    if (!a.isAlive) return 1;
    if (!b.isAlive) return -1;

    return score(a).compareTo(score(b));
  }

  /// Человекочитаемая причина бонусов для диагностического логирования.
  ///
  /// Пример: `"REALITY +5000pts | 🇩🇪 GEO +2000pts | latency=60ms | score=−6940"`
  static String debugLabel(Node node) {
    if (!node.isAlive) return 'DEAD → score=$_deadScore';

    final parts = <String>[];
    final ms = node.latencyMs ?? 9999;

    if (node.security == 'reality') parts.add('REALITY +${_realityBonus}pts');
    if (_isOptimalGeo(node.name)) parts.add('GEO +${_geoBonus}pts');

    final bonusStr = parts.isEmpty ? 'no bonus' : parts.join(' | ');
    return '$bonusStr | latency=${ms}ms | score=${score(node)}';
  }

  // ── Приватные утилиты ────────────────────────────────────────────────────

  /// Штрафной счёт для мёртвых нод — гарантированно ниже любого живого.
  static const int _deadScore = 99999;

  /// Проверяет, содержит ли имя ноды признак оптимальной локации:
  /// флаг-эмодзи, ключевое слово или ISO-код страны.
  static bool _isOptimalGeo(String name) {
    // 1. Проверка эмодзи-флагов (самый надёжный и быстрый способ).
    for (final flag in _optimalFlags) {
      if (name.contains(flag)) return true;
    }

    final lower = name.toLowerCase();

    // 2. Полнословные ключевые слова (без учёта регистра).
    for (final kw in _optimalKeywords) {
      if (lower.contains(kw)) return true;
    }

    // 3. Двухбуквенные ISO-коды: ищем только как отдельные «слова»,
    //    чтобы "NL" в "nl.example.com" не дало ложное срабатывание,
    //    но "NL-01" или "| NL |" — сработало.
    if (_containsIsoCode(lower)) return true;

    return false;
  }

  /// Ищет ISO-код как отдельный токен (окружённый не-буквенными символами).
  ///
  /// Пример совпадений: "🇩🇪 DE-01", "| NL |", "FI_proxy", "server-GB"
  /// Пример несовпадений: "delay", "model", "default" (содержат 'de', но как
  /// часть слова — не как код страны).
  static bool _containsIsoCode(String lower) {
    // Разбиваем на токены по любым не-буквенным символам.
    final tokens = lower.split(RegExp(r'[^a-z]+'));
    for (final token in tokens) {
      if (_optimalIsoCodes.contains(token)) return true;
    }
    return false;
  }
}
