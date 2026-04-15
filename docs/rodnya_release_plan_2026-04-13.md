# План доведения `Родни` до удобного релизного состояния

Дата: `2026-04-13`

## Цель

Довести Android и web до состояния, где `Родня` ощущается как ежедневный семейный продукт, а не как набор существующих фич. Приоритет: удобство, плотность интерфейса, стабильный медиа-path, совместное ведение дерева и понятная событийная ценность.

## Зафиксированная отправная точка

- `stories` как полноценный surface почти отсутствуют.
- События сейчас фактически ограничены днями рождения и `9/40` днями.
- На главной живёт постоянный приветственный hero-блок, который съедает полезное место.
- У родственника хранится только один `photoUrl`.
- Совместное редактирование дерева есть по ролям, но без истории изменений.
- Локальный backend-тест по `posts/like` проходит, значит проблему лайков считаем production-parity / client-sync задачей, а не поводом для слепого переписывания.

## Жёсткие продуктовые решения

- Публичный бренд проекта: `Родня`.
- Текущий Android `applicationId` и совместимые store identifiers сохраняются ради обновления существующей карточки в RuStore.
- Firebase cloud и hosted Supabase считаются legacy-зависимостями, если мешают доступности для пользователей в России.
- Big-bang rewrite не делать: сначала интерфейсы, адаптеры и compatibility aliases, потом постепенная миграция.
- `Stories` делаются только как `24h stories` без highlights, replies и reactions.
- Совместное редактирование дерева делается instant wiki-style, без approval flow.
- История изменений обязательна; one-click rollback не входит в первый pass.
- Российские и православные праздники поставляются локально, без внешнего API.

## Основные workstreams

### 1. Rebrand в `Родню`

- Перевести публичные UI-строки, README, docs, backend labels, CI labels, logger prefixes и служебные названия с `lineage` на `rodnya`.
- Переименовывать package/repo/import identifiers поэтапно, без массового риска для сборки.
- Оставить backward-compatible слой для legacy `lineage` storage/table/prefix aliases, пока не завершится мягкая миграция.
- Не менять Android `applicationId`.

### 2. Product hardening и плотность интерфейса

- Убрать постоянный приветственный hero на Home; заменить его на компактный header с avatar/status/actions.
- На Home, Tree, Profile и Relatives не оставлять постоянных крупных блоков без действий или живых данных.
- В Tree центр экрана должен оставаться за canvas дерева; объяснялки уходят в coach marks, overflow или contextual inspector.
- В профиле, родственниках и настройках длинные описательные панели заменить на плотные статусные секции и CTA.

### 3. Посты, stories, профиль и медиа

- Перевести `PostServiceInterface.toggleLike` на `Future<Post>` и синхронизировать итоговое состояние только из ответа сервера.
- Сделать production-parity проверку like flow и корректный rollback/refresh при ошибке.
- Доделать `StoryServiceInterface` и Story API:
  - `GET /v1/stories`
  - `POST /v1/stories`
  - `POST /v1/stories/:id/view`
  - `DELETE /v1/stories/:id`
- Добавить story rail на Home и Profile, composer для `text/image/video`, viewer с progress и seen-state.
- Сделать avatar-edit явным в header/profile/settings, с replace/remove/crop-preview.
- Довести Android/media path до стабильного состояния для post/chat/profile/relative media, включая image/video playback и compact voice preview.

### 4. События и семейный календарь

- Расширить `EventService` и event models:
  - дни рождения
  - годовщины свадьбы
  - годовщины смерти
  - `9/40` дней
  - кастомные семейные события
  - важные государственные праздники РФ
  - ключевые православные праздники
- Добавить в relation model `marriageDate` и `divorceDate`.
- Поддержать кастомные семейные даты на уровне person/custom events.
- На Home показывать единый компактный events rail/list с фильтрами по типам событий.

### 5. Совместное редактирование дерева и история изменений

- Перевести tree collaboration в wiki-style: любой участник дерева может редактировать людей, связи и медиа.
- Права `owner/editor` сохраняются для управления деревом, участниками и настройками.
- Добавить append-only журнал `TreeChangeRecord`.
- Добавить endpoint `GET /v1/trees/:treeId/history` с фильтрами по `personId/type/actorId`.
- Логировать create/update/delete person/relation/media.
- Отдельный rollback не добавлять; восстановление делается повторным редактированием по журналу.

### 6. Галерея родственников

- Перевести `FamilyPerson` с single-photo модели на `primaryPhotoUrl + photoGallery`.
- Оставить `photoUrl` как compatibility alias на primary photo.
- Добавить relative media API:
  - `POST /v1/trees/:treeId/persons/:personId/media`
  - `PATCH /v1/trees/:treeId/persons/:personId/media/:mediaId`
  - `DELETE /v1/trees/:treeId/persons/:personId/media/:mediaId`
- В detail/profile сделать gallery viewer; в tree node и списках использовать primary photo.

### 7. Упрощение tree editor

- Уйти от тяжёлых постоянных панелей к selection-based inspector.
- Дать быстрые действия на выбранном узле или связи.
- Сократить постоянные кнопки и helper text в пользу контекстных действий.
- На телефоне tree editing должен проходить без длинных инструкций на экране.

## Предпочтительный порядок исполнения

### Волна A. Базовая консолидация

- Зафиксировать план и rebrand-правила в repo docs.
- Подготовить phased rename policy: где бренд уже `Родня`, а где временно остаются compatibility identifiers.
- Перевести like flow на server-driven контракт и закрыть production-parity дыру.

### Волна B. Полезность основных экранов

- Ужать Home, Tree, Profile и Relatives до action-first UX.
- Убрать постоянные крупные helper-блоки.
- Свести tree editing к canvas + contextual inspector.

### Волна C. Социальный контур

- Доделать stories.
- Довести avatar/media flows.
- Закрыть Android media playback и fallback states.

### Волна D. Семейная ценность

- Расширить events/calendar.
- Добавить семейные даты и локальные праздники.
- Вынести события в единый компактный rail/list.

### Волна E. Совместная работа

- Перевести tree collaboration в wiki-style.
- Добавить историю изменений.
- Доделать галерею родственников.

## Acceptance по направлениям

### Branding

- Репозиторий, docs и UI не должны светить старый бренд, кроме:
  - Android `applicationId`
  - временных compatibility aliases
  - legacy migration notes

### Посты

- Like/comment/delete/create проходят локально и против production-like deploy.
- После серверной ошибки UI лайка не зависает в ложном состоянии.

### Stories

- Работают `create/view/delete`.
- Истории истекают через `24h`.
- Seen-state корректно виден второму пользователю.

### Events

- В upcoming events реально присутствуют birthday, wedding anniversary, death anniversary, `9/40`, RF holiday, orthodox holiday и custom family event.
- На Home нет постоянных описательных блоков ради текста.

### Android/media

- Фото, видео и голосовые стабильно отображаются и проигрываются на Android.
- Profile/relative/post/chat media viewer не разваливается на placeholders и broken open flows.

### Tree collaboration

- Два аккаунта могут править одного родственника.
- Изменения быстро видны второму участнику.
- История фиксирует `кто / когда / что`.

### Relative gallery

- У одного родственника может быть несколько фото.
- Основное фото можно выбирать явно.
- Tree/list/detail screens используют один и тот же primary image.

### UI

- Home, Tree, Profile и Relatives проходят smoke без крупных статичных текстовых блоков.
- Tree editor остаётся удобным на телефоне.

## Что считать ближайшим execution baseline

Если scope приходится резать, сначала должны быть закрыты:

1. Server-driven like flow и production parity.
2. Home/Tree/Profile/Relatives declutter.
3. Events expansion до реально полезного семейного календаря.
4. Relative gallery + tree history как база для совместного редактирования.
5. Stories как отдельный social layer поверх уже стабильных core surfaces.
