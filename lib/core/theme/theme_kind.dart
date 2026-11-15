/// Темы оформления Onyx. Переключаются в «Настройки → Оформление».
///
/// Концепции и мокапы — `docs/redesign/concepts.md` (разделы 9–10).
enum AppThemeKind {
  /// Глубокий чёрный, тёплый акцент шампань, кнопка «Линза». По умолчанию.
  onyx('Onyx', 'Чёрный камень и тёплый акцент'),

  /// OLED-чёрный, точечная матрица, красная REC-точка.
  signal('Signal', 'Точечная матрица, OLED-чёрный'),

  /// Material 3 Expressive: формы MaterialShapes, пружины, цвета из обоев.
  material('Material', 'Material 3 Expressive, цвета обоев');

  const AppThemeKind(this.label, this.description);

  final String label;
  final String description;

  /// Тема одобрена и есть в «Оформлении». Material 3 пока НЕТ: пользователь
  /// не принял её макеты (m3, m3c) — «M3 в коде только после одобрения»;
  /// код темы остаётся для доработки по канону (docs/redesign/M3-BRIEF.md).
  /// Вернуть — одна строка здесь.
  bool get released => this != AppThemeKind.material;

  /// Темы для выбора в «Оформлении».
  static List<AppThemeKind> get selectable => [for (final k in values) if (k.released) k];

  /// Сохранённая тема. Неизвестная или не выпущенная (Material, выбранный в
  /// тестовых сборках) — Onyx.
  static AppThemeKind byName(String? name) => AppThemeKind.values.firstWhere(
        (k) => k.name == name && k.released,
        orElse: () => AppThemeKind.onyx,
      );
}
