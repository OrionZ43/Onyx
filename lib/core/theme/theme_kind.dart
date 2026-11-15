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

  /// Тема есть в «Оформлении». Все три выпущены: Material 3 Expressive —
  /// работа сессии пользователя (порт из «Расписания МИТСО»), доведённая до
  /// нынешних функций (#105, docs/redesign/m3.md). Скрыть тему до
  /// доработки — вернуть сюда условие.
  bool get released => true;

  /// Темы для выбора в «Оформлении».
  static List<AppThemeKind> get selectable => [for (final k in values) if (k.released) k];

  /// Сохранённая тема. Неизвестная или не выпущенная (если тему снова скроют)
  /// — Onyx.
  static AppThemeKind byName(String? name) => AppThemeKind.values.firstWhere(
        (k) => k.name == name && k.released,
        orElse: () => AppThemeKind.onyx,
      );
}
