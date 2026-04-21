# Family Calendar Execution Plan 2026-04-21

## Goal

Сделать первый новый продуктовый сценарий после MVP freeze: семейный календарь,
который собирает дни рождения, годовщины, памятные даты и ручные семейные
события в один спокойный daily-use экран.

## Why this first

- даёт понятную ежедневную ценность без переизобретения дерева
- опирается на уже существующие профили, родственников, события и уведомления
- хорошо монетизирует внимание: у пользователя появляется причина возвращаться
  в приложение не только ради дерева и чатов
- не требует ломать текущую backend архитектуру

## MVP scope

### Include

- список ближайших семейных событий на 30 дней
- today / this week / later группировки
- автоматические дни рождения из профилей и карточек родственников
- автоматические даты памяти для deceased profiles
- ручные семейные события с типом, датой, описанием и привязкой к дереву
- переход из события в профиль человека, карточку родственника или дерево
- базовые reminder notifications

### Exclude

- сложные recurring rules beyond yearly birthdays/memorial dates
- shared editing history для каждого события
- внешняя calendar sync интеграция
- медиавложения внутри событий

## Data model

### CalendarEvent

- `id`
- `treeId`
- `personId?`
- `source`
  - `birthday`
  - `memorial`
  - `manual`
- `title`
- `description?`
- `startsOn`
- `endsOn?`
- `isAllDay`
- `visibilityScope`
- `createdBy`
- `createdAt`
- `updatedAt`

### Derived events

- birthdays и memorial dates не дублируются в storage, а вычисляются из dossier
  и person data
- manual events живут отдельно и дополняют derived stream

## Backend

1. Добавить `GET /v1/trees/:treeId/calendar`
   - query: `from`, `to`
   - response: merged list of derived + manual events

2. Добавить manual event CRUD:
   - `POST /v1/trees/:treeId/calendar/events`
   - `PATCH /v1/trees/:treeId/calendar/events/:eventId`
   - `DELETE /v1/trees/:treeId/calendar/events/:eventId`

3. Вынести shared event projection helper
   - birthdays from linked profile or offline person birth date
   - memorial dates from deceased person death date
   - label builder with Russian-friendly wording

4. Подготовить notification feed
   - reminder window `today`, `tomorrow`, `in 7 days`
   - не создавать push flood; один consolidated reminder per tree/day

## Flutter

### Routes

- `/#/calendar`
- optional tree-scoped deep link `/#/calendar/:treeId`

### UI

- dense desktop/mobile layout
- hero with `Сегодня`, `На этой неделе`, `Скоро`
- segmented filters:
  - `Все`
  - `Дни рождения`
  - `Память`
  - `Семейные события`
- event cards with direct CTA:
  - `Открыть профиль`
  - `Открыть карточку`
  - `Напомнить семье`

### Editing

- simple create/edit sheet for manual events
- reuse dossier/person pickers where possible
- owner/editor permissions follow tree collaborative rules

## Notifications

- integrate with existing notifications service instead of a parallel channel
- reminder payload opens calendar first, then event context
- keep tone human and concise:
  - `Сегодня день рождения у ...`
  - `Завтра день памяти ...`

## Verification

- backend tests for merged calendar projection
- flutter widget tests for empty/loading/error states
- route smoke for `/#/calendar`
- manual production smoke:
  - today birthday
  - memorial date
  - manual event create/edit/delete
  - reminder notification open path

## Rollout

1. backend read endpoint + derived projection
2. read-only calendar screen
3. manual event CRUD
4. reminder notifications
5. final polish on dense desktop/mobile layout

## Success criteria

- пользователь открывает Родню не только ради структуры дерева, но и чтобы
  быстро увидеть, что у семьи происходит в ближайшие дни
- экран полезен даже в дереве без активных постов и переписок
- сценарий не создаёт новые operational риски по сравнению с текущим MVP
