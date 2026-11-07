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

  static AppThemeKind byName(String? name) => AppThemeKind.values.firstWhere(
        (k) => k.name == name,
        orElse: () => AppThemeKind.onyx,
      );
}
