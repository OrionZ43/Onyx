# Onyx — правила работы

Flutter-клиент VPN (Android + Windows, Riverpod). Три темы оформления
(`AppThemeKind`, «Настройки → Оформление»): Onyx, Signal и Material 3 Expressive.
Концепции — [`docs/redesign/concepts.md`](docs/redesign/concepts.md), тема
Material — [`docs/redesign/m3.md`](docs/redesign/m3.md).

## Тема Material 3 Expressive: главное правило

Ни один элемент интерфейса, анимация или взаимодействие темы Material не
придумываются «на глаз». Прежде чем добавить или поменять компонент:

1. Открыть его раздел в [`docs/m3/`](docs/m3/README.md) — там ссылки, ключевые
   токены, поведение и известные расхождения.
2. Сверить с первоисточниками (порядок — от главного):
   - **m3.material.io** — Guidelines / Specs / Accessibility компонента. Сайт
     рендерится скриптом, поэтому текст выгружается скриптом:
     `python tools/m3_guidelines.py` (всё) или
     `python tools/m3_guidelines.py components/switch` (страница) →
     `.m3-guidelines/<slug>.md` с правилами Do/Don't и таблицами токенов.
   - **Compose Material3** — эталонная реализация Expressive: размеры, формы,
     какой токен `MotionScheme` что анимирует, взаимодействия (например,
     расширение нажатой кнопки в группе). API:
     https://developer.android.com/reference/kotlin/androidx/compose/material3/package-summary
     Исходники (частичный клон, ~2 минуты):
     ```bash
     git clone --filter=blob:none --no-checkout https://github.com/androidx/androidx.git ax
     cd ax && git config core.longpaths true
     git sparse-checkout set --no-cone compose/material3/material3/src/commonMain compose/material3/material3/samples
     git checkout
     ```
     Компоненты — `compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/*.kt`,
     токены — `.../material3/tokens/*.kt`, примеры — `compose/material3/material3/samples`.
   - **MDC-Android** — https://github.com/material-components/material-components-android/tree/master/docs
     (`docs/components/*.md`, `docs/theming/Motion.md`) и исходники
     `lib/java/com/google/android/material/**` для значений, которых нет выше.
3. Если Flutter-виджет расходится с Compose (размеры, анимации, состояния) —
   портировать поведение Compose, а не мириться с дефолтом Flutter. Готовые
   порты лежат в `lib/presentation/widgets/m3/` (перенесены из «Расписания
   МИТСО», пометка «Порт из …» в первой строке), токены — в `lib/core/theme/m3/`;
   новые класть туда же.
4. Каждое отступление от спеки — осознанное: записать причину в
   [`docs/redesign/m3.md`](docs/redesign/m3.md), раздел «Отступления».
5. После изменения компонента обновить его раздел в `docs/m3/`.

Экраны темы Material — `lib/presentation/m3/`. Общие экраны (`HomeScreen`,
`SettingsScreen`, `SubscriptionManagerScreen`, `SubscriptionImport`, шторка
серверов) первой строкой `build` отдают M3-версию, если
`OnyxTokens.of(context).isMaterial`; темы Onyx и Signal это не затрагивает.

## Движение

Пружины `AppMotion` (`lib/core/theme/app_motion.dart`) = `ExpressiveMotionTokens`
из Compose. Какой токен у какого свойства — смотреть в исходнике аналогичного
компонента Compose (`MotionSchemeKeyTokens.*`), не выбирать самому. Темы Onyx и
Signal двигаются по `OnyxMotion` — без перелёта.

## Иконки

Тема Material рисует иконки Material Symbols (`OnyxGlyph.material`), Onyx и
Signal — свои SVG (`assets/icons`). Новый глиф — только по согласованию с
владельцем проекта; если точного глифа нет, сначала свои картинки.

## Проверки

```bash
flutter analyze
flutter test
flutter test --update-goldens test/m3_screens_golden_test.dart   # PNG в test/goldens/m3-*.png — посмотреть глазами
```

Снимки тем копируются в `docs/redesign/screens/`.
