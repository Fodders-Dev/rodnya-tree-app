# UI Ship Execution Plan

## Цель
Довести web/UI `Родни` до состояния, которое можно спокойно показывать на `rodnya-tree.ru`: меньше текста, меньше тяжёлых блоков, сильнее визуальная иерархия, лучше desktop/mobile ритм.

## Главная проблема сейчас
- `Home` всё ещё местами выглядит как набор параллельных модулей, а не как один сценарий.
- `Stories` слишком похожи на мини-постеры, а не на быстрый верхний rail.
- `Events` визуально слишком крупные и спорят с лентой.
- В приложении ещё остались экраны, где старый UI-язык проскакивает через sheets, secondary lists и редкие entry points.

## Визуальный тезис
- `Stories` как быстрый visual rail сверху.
- `Events` как вторичный компактный rail под stories.
- `Feed` как главный контент ниже.
- Вся вторичная информация уходит в chips, counters, icons, sheets.

## Приоритетный execution order

### Wave 1. Home composition
- Переделать desktop `Home` из горизонтальных трёх блоков в вертикальный сценарий:
  - stories сверху
  - compact events под ними
  - feed ниже
- Сделать `StoryRail` ближе к `Instagram / Telegram`:
  - первый слот всегда `создать`
  - сами истории в кружках или squircle-аватарах
  - короткие подписи, без больших постерных карточек
- Уменьшить `EventCard`:
  - ниже по высоте
  - уже по ширине
  - меньше текста
- Добавить wheel-friendly horizontal scroll для event rail на desktop/web

### Wave 2. Home polish
- Упростить пустую ленту и состояния недоступности
- Проверить, что stories/events/feed не спорят по акценту
- Проверить desktop 1280 / 1440 / 1600 и mobile 390 / 430

### Wave 3. Tree and detail surfaces
- Добить `Tree` toolbar и inspector до ещё более тихого состояния
- Упростить `RelativeDetails` header, gallery summary и secondary blocks
- Проверить `Profile` и `Relatives` после нового `StoryRail`, чтобы не появилось лишнего воздуха

### Wave 4. Remaining UI debt
- `Notifications`
- `Offline / blocked / relation request` screens
- `Public tree / entry` screens
- `About / privacy / legal` surfaces
- Все мелкие sheets, pickers и confirm dialogs

### Wave 5. Final ship pass
- Проверка иконок, spacing, hover, focus, scroll
- Проверка web smoke на локальном static bundle
- Проверка целевых экранов на продовом домене после push

## Acceptance
- `Home` читается сверху вниз без ощущения трёх независимых колонок.
- `Stories` воспринимаются как быстрый visual layer.
- `Events` не спорят с лентой и не занимают лишний вес.
- На экране нет длинных поясняющих абзацев без действия.
- Desktop и mobile чувствуют себя одной системой, а не двумя разными раскладками.

## Текущий шаг
- Закрыть `Wave 1` полностью.
- Прогнать `dart format`, `flutter analyze`, релевантные тесты и web smoke.
- Закоммитить и запушить, чтобы проверить `rodnya-tree.ru`.
