# Chat UI Execution Plan

Дата: `2026-04-14`

## Цель

Довести `Chats` до того же уровня, что уже получили `Home`, `Tree`, `Profile` и `Relatives`: меньше воздуха, меньше служебной писанины, чище и быстрее читаемый интерфейс, ближе к смеси `Telegram + WhatsApp` в спокойном `liquid glass`.

## Принципы

- Первое чтение экрана должно занимать 2-3 секунды.
- Основной акцент: список диалогов, сообщения, composer, быстрые действия.
- Любой длинный helper-text уходит, если смысл понятен из иконки, статуса и действия.
- На desktop и mobile чаты должны выглядеть плотнее, но не тяжелее.
- Пустые состояния: один смысл, одно действие.

## Обязательные поверхности

1. `ChatsListScreen`
2. `ChatScreen`
3. composer states:
   - обычный ввод
   - reply
   - forward
   - edit
   - attachments
   - recording
   - blocked state
4. pinned / unread / search overlays
5. create-chat bottom sheet

## Волны

### Wave 1. Chats list shell

- Упростить `AppBar`: оставить короткий заголовок и действие создания.
- Перенести контекст дерева/круга в chips и stats вместо второй строки под заголовком.
- Пересобрать desktop shell:
  - glass list panel
  - компактный side rail
  - меньше длинных описательных абзацев
- Ужать search и filter bar.
- Упростить empty/error/filter-empty states.

### Wave 2. Chat list items

- Сделать элементы списка ближе к messenger-list:
  - плотнее вертикальный ритм
  - стеклянная плитка вместо голого `ListTile`
  - сильнее иерархия: avatar -> name -> preview -> meta
- Убрать визуальный шум:
  - меньше серого текста
  - статусы через compact pills/badges
  - unread и archive читаются с первого взгляда

### Wave 3. Conversation shell

- Упростить верхнюю панель чата:
  - avatar
  - title
  - один subtitle
  - search/info actions
- Упростить bootstrap/error/empty/search states.
- Закреплённое сообщение сделать компактным glass-strip.
- Jump-to-latest и unread divider оставить, но выровнять под новый стиль.

### Wave 4. Composer

- Сделать composer компактнее:
  - убрать постоянные пояснения про контекст дерева
  - actions через иконки и pills
  - send/mic как единая primary action
- Reply / edit / forward bars сделать короче.
- Attachments panel сделать чище и понятнее без лишнего текста.
- Recording / blocked state привести к тому же визуальному языку.

### Wave 5. Secondary chat flows

- Упростить `ChatInfoSheet`.
- Упростить `CreateChatSheet`.
- Проверить attachment preview, voice preview, selection mode.

## Execution order

1. `ChatsListScreen` shell + list items
2. `ChatScreen` app bar + states + pinned
3. `ChatScreen` composer
4. `CreateChatSheet` / info sheet polish
5. Browser smoke и профильные widget tests

## Current pass

Сейчас в работе:

- `Wave 1`
- `Wave 2`
- начало `Wave 3`

## Acceptance

- В `Chats` нет больших описательных панелей ради текста.
- Список чатов читается быстрее: имя, превью, время, статус.
- Composer короче и визуально легче.
- Desktop shell не выглядит как старая form-page.
- `flutter analyze`, профильные chat tests и локальный web smoke проходят.
