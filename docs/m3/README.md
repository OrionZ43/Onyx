# Material 3 Expressive в Onyx — справочник

Справочник для темы **Material** (`AppThemeKind.material`). У каждого компонента и
стиля свой файл: ссылки на гайдлайны m3.material.io, Compose Material3 и
MDC-Android, ключевые токены, поведение и движение, доступность. Правила работы —
в [`CLAUDE.md`](../../CLAUDE.md), решения именно Onyx — в
[`docs/redesign/m3.md`](../redesign/m3.md).

**Откуда.** Справочник перенесён из приложения «Расписание МИТСО» (тот же автор),
где по нему собраны компоненты M3 Expressive. Сами компоненты перенесены сюда же:
`mitso_schedule/lib/widgets/` → `lib/presentation/widgets/m3/`, токены →
`lib/core/theme/m3/`, пружины — `lib/core/theme/app_motion.dart`. Общие части
каждого файла — источники, токены, поведение, доступность — справедливы как есть.
Разделы «В приложении» и «Реализация во Flutter» описывают эталонную реализацию:
пути вида `mitso_schedule/...` — файлы того проекта, остальные — файлы Onyx.
Статус в первой строке файла — тоже статус эталона.

Текст гайдлайнов целиком (с Do/Don't и таблицами токенов) выгружается
скриптом `python tools/m3_guidelines.py` в `.m3-guidelines/`.

## Порядок источников

1. **m3.material.io** — что и когда использовать, токены, доступность.
2. **Compose Material3** (`androidx/compose/material3`) — эталонная реализация
   Expressive: точные значения, какой токен `MotionScheme` что анимирует,
   взаимодействия.
3. **MDC-Android** — когда первых двух не хватает.

Если источники расходятся, в файле компонента записано, что выбрано и почему.

## Стили

| Тема | Файл |
|---|---|
| Движение: пружины, переходы | [styles/motion.md](styles/motion.md) |
| Форма: шкала скруглений, MaterialShapes, морфинг | [styles/shape.md](styles/shape.md) |
| Цвет: роли, динамические цвета, дополнительные цвета | [styles/color.md](styles/color.md) |
| Типографика: шкала, emphasized, шрифт | [styles/typography.md](styles/typography.md) |
| Высота и scrim | [styles/elevation.md](styles/elevation.md) |
| Иконки: Material Symbols, оси, размеры | [styles/icons.md](styles/icons.md) |
| Раскладка, отступы, breakpoints | [styles/layout.md](styles/layout.md) |
| Состояния взаимодействия, state layer | [styles/interaction-states.md](styles/interaction-states.md) |
| Доступность | [styles/accessibility.md](styles/accessibility.md) |

## Компоненты

Статус — в первой строке каждого файла (✅ соответствует, ⚠️ частично,
❌ не соответствует, — не используется).

| Группа | Компоненты |
|---|---|
| Кнопки | [выбор кнопки](components/all-buttons.md), [кнопки](components/buttons.md), [icon buttons](components/icon-buttons.md), [группы кнопок](components/button-groups.md), [FAB](components/floating-action-button.md), [extended FAB](components/extended-fab.md), [FAB menu](components/fab-menu.md), [split button](components/split-button.md), [segmented button](components/segmented-buttons.md) (устарел) |
| Выбор и ввод | [переключатель](components/switch.md), [чекбокс](components/checkbox.md), [радиокнопка](components/radio-button.md), [чипы](components/chips.md), [поиск](components/search.md), [текстовые поля](components/text-fields.md), [меню](components/menus.md), [слайдеры](components/sliders.md) |
| Навигация и контейнеры | [navigation bar](components/navigation-bar.md), [app bars](components/app-bars.md), [toolbars](components/toolbars.md), [tabs](components/tabs.md), [нижний лист](components/bottom-sheets.md), [диалоги](components/dialogs.md), [карточки](components/cards.md), [списки](components/lists.md), [разделитель](components/divider.md), [карусель](components/carousel.md), [navigation rail](components/navigation-rail.md), [navigation drawer](components/navigation-drawer.md), [side sheets](components/side-sheets.md) |
| Индикаторы и обратная связь | [индикатор загрузки](components/loading-indicator.md), [индикаторы прогресса](components/progress-indicators.md), [pull-to-refresh](components/pull-to-refresh.md), [badges](components/badges.md), [снекбар](components/snackbar.md), [подсказки](components/tooltips.md) |

## Реализация во Flutter

Flutter 3.44 не поставляет большинство Expressive-компонентов и `MotionScheme`,
поэтому они портированы с Compose (в «Расписании МИТСО») и перенесены сюда:

| Что | Где |
|---|---|
| Пружины `MotionScheme`, уменьшение движения | `lib/core/theme/app_motion.dart` |
| Пружина Compose (`ComposeSpringSimulation`) | `lib/core/theme/compose_spring.dart` |
| Типошкала и emphasized | `lib/core/theme/m3/app_typography.dart` |
| Шкала форм | `lib/core/theme/m3/app_shapes.dart` |
| Отступы | `lib/core/theme/m3/app_spacing.dart` |
| State layer | `lib/core/theme/m3/app_state_layer.dart` |
| Цвет в Oklab (`animateColorAsState`) | `lib/core/theme/m3/oklab.dart` |
| ThemeData темы Material | `lib/core/theme/app_theme.dart` (`_material`) |
| Компоненты | `lib/presentation/widgets/m3/` — кнопки, группы кнопок, переключатель, фильтр-чипы, сегментированные списки, нижний лист, поиск, снекбар, индикатор загрузки, волнистый прогресс, app bar, FAB, подсказки, пустое состояние |
| Главная кнопка (фигура + LoadingIndicator) | `lib/presentation/widgets/hero/m3_shape_button.dart` |
| Экраны темы | `lib/presentation/m3/` |
