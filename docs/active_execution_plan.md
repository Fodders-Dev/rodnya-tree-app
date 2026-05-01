# Active Execution Plan

## 0. Execution Checklist — Global Family Graph / Circles

- [x] **Wave 0 — Тихая identity-миграция** *(server/data model, no UI behavior change)*
  - [x] миграция создаёт `PersonIdentity` 1:1 для каждой `FamilyPerson` без identity
  - [x] создание новой `FamilyPerson` всегда привязывает карточку к `PersonIdentity`
  - [x] API отдаёт `identityId` в `FamilyPerson` response как nullable/additive поле
  - [x] Flutter `FamilyPerson` принимает nullable `identityId` без breaking changes
  - [x] regression tests покрывают идемпотентность миграции и новые responses
- [x] **Wave 1 — Within-tree dedup suggestions**
  - [x] matcher внутри одного дерева
  - [x] read-only endpoint для suggested duplicates
  - [x] минимальный UI surface без merge actions
- [x] **Wave 2 — Circles model**
  - [x] backend `circles` / `circleMembers`
  - [x] default `all_tree` / `favorites`
  - [x] optional `circleId` для posts как backward-compatible audience
  - [x] Flutter `AudiencePicker` для posts/stories
  - [x] home/stories audience filtering UI smoke
- [x] **Wave 3 — Auto-circles по структуре дерева**
  - [x] descendants/ancestors/pair circles
  - [x] audience picker preview
- [x] **Wave 4 — Cross-tree merge proposals**
  - [x] cross-tree matcher
  - [x] merge review endpoint/UI
  - [x] privacy gates before release
- [x] **Wave 5+ — Field-level visibility, identity claims, public discoverability**
  - [x] field-level visibility
  - [x] identity claims
  - [x] opt-in public discovery

## 0.1 Current Execution Log

- [x] 2026-04-29 — Wave 0 completed: additive `PersonIdentity` backfill, new `FamilyPerson` identity links, API regression coverage; no UI behavior changes.
- [x] 2026-04-29 — Wave 1 completed: within-tree duplicate matcher, read-only `/v1/trees/:treeId/duplicates` endpoint, relative details duplicate comparison surface; merge actions intentionally not added.
- [x] 2026-04-29 — Wave 2 backend slice completed: `circles`/`circleMembers`, default `all_tree`/`favorites`, post `circleId`, and feed filtering by viewer circle membership. Flutter AudiencePicker remains open.
- [x] 2026-04-30 — Wave 2 completed: Flutter `AudiencePicker` added to post/story composers, stories now carry `circleId`, feed/story filtering is covered by backend + widget tests, and local web shell smoke passed after `sync_web_shell_assets`.
- [x] 2026-04-30 — Wave 3 completed: relation-derived system circles (`descendants_of`, `ancestors_of`, `pair`) are recalculated from tree structure, exposed in the audience picker with member counts, and protected from manual member edits.
- [x] 2026-05-01 — Wave 4 completed: cross-tree merge proposals are generated from matcher evidence, reviewed by all stewards before identity merge, surfaced in notifications/review UI, and return only safe name + birth-year previews.
- [x] 2026-05-01 — Wave 5+ completed: card/field visibility records, identity claim review flow, and explicit public discovery opt-in are wired through backend API, Flutter service, relative privacy sheet, and review screen.

---

## Claude Plan — Global Family Graph / Circles

Понял задумку полностью. До деталей. Прежде чем дам инженерный план — кратко проверю одну вещь в коде, которая важна для предложения.

Хорошая новость: половина фундамента уже есть. В [`backend/src/store.js:3679`](backend/src/store.js) живёт `createPersonIdentityRecord({id, userId, personIds[]})` — это уже «один человек, много карточек в разных деревьях», но сейчас он привязан только к claimed-пользователям. На этом можно эволюционировать без big-bang.

Ниже — инженерный план под все 9 пунктов твоего брифа.

---

## 1. Продуктовая модель

**Базовая идея перевода:**

«Дерево» в Родне перестаёт быть копией реальности — оно становится **личной приватной проекцией общего родственного графа** + контейнером контента (посты, истории, чаты). Реальные люди — это `PersonIdentity`. Карточка в дереве — `FamilyPerson` (как сейчас), но обязательно ссылается на одного `PersonIdentity`.

**Сущности:**

| Сущность | Что это | Уже есть? |
|---|---|---|
| `PersonIdentity` | Глобально уникальный человек в графе. Идентификатор. Не содержит данных, только ссылки. | Частично: запись есть, но привязана только к claimed user'ам. |
| `FamilyPerson` (карточка) | Локальное представление человека внутри одного `Tree`. Поля заполняет владелец дерева. Уже есть. | Да, [`lib/models/family_person.dart`](lib/models/family_person.dart). |
| `PersonAttribute` | Атомарный факт об identity (имя, дата рождения, фото, город, …) с источником, confidence и audience. | Нет. Ввести постепенно. |
| `Tree` | Семейное пространство-проекция. Owner, members, default audience. | Да, [`lib/models/family_tree.dart`](lib/models/family_tree.dart). |
| `Relation` | Связь между двумя `FamilyPerson` (а опосредованно — между `PersonIdentity`). Уже есть. | Да, [`lib/models/family_relation.dart`](lib/models/family_relation.dart). |
| `Circle` | Аудитория поверх дерева: «близкие», «ветка отца», «потомки бабушки», «избранные». | Нет. Главное новое понятие. |
| `MergeProposal` | «Похоже, эти два FamilyPerson — один и тот же PersonIdentity». | Нет. |
| `IdentityClaim` | Запрос «я и есть этот человек» от пользователя на чужой карточке. | Частично, через relation-requests. Нужна отдельная сущность для identity. |

**Что меняется в восприятии пользователя:**

- Создаёт ветку → видит подсказку «возможно, ваш дядя Иван уже есть в дереве вашей мамы».
- При публикации поста выбирает не дерево, а **круг**: «всем в дереве», «ветка отца», «избранные», «бабушке и её детям», «только моей паре».
- Карточка человека показывает не одно состояние, а «ваша версия данных» + «есть другие версии в N других деревьях, можно посмотреть/принять».

**Что НЕ меняется в MVP:**
- Логика дерева, рендер, чаты, пуши, медиа — всё как сейчас.
- Старая модель «опубликовать пост в дерево» — остаётся как default-circle «всё дерево».

---

## 2. Эволюция data model (минимальная, аддитивная)

**Backend (`backend/src/store.js`, `postgres-store.js`):**

Добавляем коллекции (в `EMPTY_DB` они пойдут рядом с уже существующей `personIdentities`):

```
personIdentities      // расширить существующее
personAttributes      // новое
circles               // новое
circleMembers         // новое
mergeProposals        // новое
identityClaims        // новое
audienceTargets       // новое (универсальный target поста/истории)
```

**`PersonIdentity` (расширение):**
```
{
  id,
  primaryPersonId,        // источник истины для отображения, если нет конфликтов
  personIds: [...],       // все карточки FamilyPerson, связанные с этой identity
  claimedByUserId,        // если человек подтвердил аккаунт
  isLiving,               // влияет на privacy default
  isPublicDiscoverable,   // false по умолчанию
  stewardUserIds: [...],  // те, кто может одобрять merge'и (создатели карточек)
  createdAt, updatedAt,
}
```

**`PersonAttribute` (новое):**
```
{
  id, identityId,
  field,                  // 'firstName' | 'birthDate' | 'photoUrl' | ...
  value,
  sourcePersonId,         // FamilyPerson, откуда пришло
  sourceUserId,
  confidence,             // 0-1
  visibility,             // 'private' | 'tree' | 'circle:<id>' | 'public'
  status,                 // 'active' | 'disputed' | 'archived'
  createdAt,
}
```
В MVP можно НЕ вводить `PersonAttribute` сразу — оставить данные на `FamilyPerson`, а слой identity-агрегации пусть просто читает «primary card». Но схему держать в голове, чтобы не упереться позже.

**`Circle` (новое):**
```
{
  id, treeId, ownerUserId,
  kind,                   // 'manual' | 'descendants_of' | 'ancestors_of' | 'pair' | 'all_tree' | 'favorites'
  anchorPersonId,         // для авто-кругов
  name, icon, color,
  createdAt, updatedAt,
}

CircleMember {
  circleId, identityId,   // membership через identity, не через карточку
  addedByUserId, addedAt,
}
```

**`MergeProposal` (новое):**
```
{
  id,
  fromPersonId,           // карточка, для которой нашли совпадение
  toIdentityId,           // куда мерджим
  candidatePersonId,      // конкретная другая карточка
  matchScore,             // 0-1
  matchSignals: {...},    // {nameMatch, dobMatch, parentMatch, ...}
  status,                 // 'pending' | 'accepted' | 'rejected' | 'expired'
  proposedByUserId,       // обычно null = system
  reviewerUserIds: [...], // кто должен подтвердить (steward'ы обеих сторон)
  reviews: [{userId, decision, reason, at}],
  createdAt, resolvedAt,
}
```

**`IdentityClaim` (новое):**
```
{
  id, identityId, claimantUserId,
  evidence,               // текст / phone / email
  status,                 // 'pending' | 'approved' | 'denied'
  reviewerUserIds: [...], // steward'ы
  createdAt, resolvedAt,
}
```

**Postgres-таблицы:** один-в-один, JSONB для `matchSignals` и `attributes`. На `personIdentities(id)`, `circles(treeId)`, `mergeProposals(status, createdAt)`, `circleMembers(circleId, identityId)` — индексы. Без секционирования в MVP.

---

## 3. PersonIdentity vs FamilyPerson — разделение ответственности

**Принцип:**

| | `PersonIdentity` | `FamilyPerson` (карточка) |
|---|---|---|
| Уровень | Глобальный граф | Локальная проекция в дереве |
| Кто создаёт | Система автоматически при создании любой карточки | Пользователь вручную |
| Кто видит | Никогда напрямую — это технический id | Все участники дерева |
| Содержит данные | Нет (или только агрегированные) | Да — все поля как сейчас |
| Удалить | Только если осталось 0 карточек и 0 claims | Да, как сейчас |
| Изменить «суть» | Только через merge/split | Свободно |

**Как живёт:**

- Создаётся `FamilyPerson` → сразу создаётся `PersonIdentity` с `personIds: [thatPerson.id]`. Невидимо для пользователя.
- Карточки разных деревьев, указывающие на одну реальную бабушку, — каждая со своей identity, до момента merge.
- Слияние = `PersonIdentity` поглощает `personIds` другого identity, второй помечается `mergedInto = winnerId` и архивируется.
- Split (на случай ошибки) = из identity отделяется одна карточка обратно в свою identity.

**Контракт API:**
- Везде, где сейчас `personId` — оставляем как есть (обратная совместимость).
- Появляется `identityId` как параллельное поле в API responses (опционально).
- Эндпоинты типа `/v1/persons/:personId/identity` для получения identity-данных.
- НЕ ломаем `family_person.dart` модель Flutter — добавляем nullable поле `identityId`.

---

## 4. Merge / dedup flow

### 4.1 Поиск кандидатов (matcher)

Новый модуль [`backend/src/identity-matcher.js`](backend/src/identity-matcher.js):

**Сигналы:**
1. Нормализованное ФИО (Levenshtein ≥ 0.85 на нормализованной строке) — учитывать девичью фамилию, ё/е, диминутивы (Саша=Александр).
2. Год рождения совпадает ±1 год.
3. **Контекст связей** — критичный сигнал. Совпадение хотя бы одного родителя ИЛИ супруга, который уже находится в общей identity, → +большой буст.
4. Город рождения / города жизни (если оба указаны).
5. Подтверждённый identity claim (если кто-то заявил аккаунт).

**Score = взвешенная сумма.** Пороги:
- `< 0.5` — игнорировать.
- `0.5 – 0.75` — soft suggestion в карточке.
- `0.75 – 0.9` — активный merge proposal.
- `≥ 0.9` И оба deceased И один steward — авто-merge с уведомлением (опционально, можно НЕ включать в MVP).

### 4.2 Когда запускать matcher

- При создании / редактировании `FamilyPerson` — асинхронно, после ответа клиенту.
- При добавлении новой `Relation` — пересчёт для двух соседей.
- Раз в сутки batch-job по дереву (на случай новых данных в смежных деревьях).

### 4.3 Подтверждение

**Никогда не сливать молча.** Правила:

| Сценарий | Кто подтверждает |
|---|---|
| Обе карточки созданы одним пользователем, обе unclaimed | Этот же пользователь, в один клик |
| Карточки в разных деревьях, оба deceased | Steward'ы обеих сторон (двое) |
| Хотя бы одна карточка claimed (живой человек подтвердил аккаунт) | Сам владелец identity + steward другой стороны |
| Спорный случай (низкий score, старая карточка) | Только полное согласие steward'ов |

**UI flow:**
- Уведомление «найдено возможное совпадение» → открывается экран сравнения двух карточек side-by-side → варианты «Это один человек», «Это разные люди», «Не уверен».
- «Не уверен» помечает proposal как `snoozed` на 30 дней.
- «Это разные люди» сохраняет negative-signal, чтобы matcher больше не предлагал ту же пару.

### 4.4 Что после merge

- Все `personId` ссылки в чатах, постах, историях остаются на старых карточках (НЕ переписываем, чтобы не риск потери данных).
- В UI карточка показывает «объединено с …», и при открытии любой из них показывается агрегированное представление.
- Поля разрешаются: если `birthDate` отличается → показываем оба значения с источниками («ваша мама указала 1948, ваш дядя — 1949»). НЕ выбираем за пользователя.
- Чувствительные поля (телефон, точная дата, фото) — visibility наследуется по самому строгому из двух.

### 4.5 Split (отмена merge)

- Любой steward может в течение 30 дней инициировать split. После — нужен консенсус всех steward'ов.
- Split восстанавливает прежние identity-id'ы, но сохраняет историю в `mergeProposals.status='reverted'`.

---

## 5. Privacy / access model

### 5.1 Базовый принцип

> Living person → private by default. Deceased → tree-default. Public discoverable → opt-in явный.

### 5.2 Уровни доступа

```
visibility:
  private       — только steward'ы и сам человек (если claimed)
  tree          — все участники конкретного Tree
  circle:<id>   — конкретный круг
  cross-tree    — другие деревья, где есть та же identity, видят общие поля
  public        — поиск, ссылки наружу (только с opt-in identity owner'а)
```

### 5.3 Field-level controls

На карточке живого человека (или identity, если claimed) — настройка для каждой группы полей:

| Группа | Default living | Default deceased |
|---|---|---|
| Имя/фамилия | tree | tree |
| Фото | circle:close | tree |
| Дата рождения (полная) | circle:close | tree |
| Год рождения | tree | tree |
| Города/места | circle:close | tree |
| Телефон, email | private | private (наследники claim) |
| Заметки | circle:close | tree |
| Связи | tree | tree |

**В MVP:** ввести `visibility` ТОЛЬКО на уровне карточки целиком (`private/tree/circle/public`), а field-level — Wave 4+. Это снимает 80% риска без огромной работы.

### 5.4 Cross-tree visibility

Когда identity объединена и присутствует в дереве A и B:

- Дерево A видит **только** те поля карточки B, у которых visibility ≥ `cross-tree`.
- Steward identity (исторически — создатель) решает, что разрешить кросс-просмотр.
- По умолчанию — только имя, год рождения, родственная связь. Никаких фото / контактов / заметок.

### 5.5 Аудитория контента (посты/истории/чаты)

- Старая модель: `post.treeId` → видят все в дереве. Сохраняем как «default audience = circle:all_tree».
- Новая: `post.audienceTargetId` → ссылка на `Circle`. Один пост = один круг.
- Чаты — отдельная история (1:1 и группы), они НЕ привязываются к кругам в MVP. В будущем: `chat.kind = 'circle' | 'direct' | 'group'`.

### 5.6 Что точно НЕ делаем в MVP

- ❌ Никакого глобального «вы добавлены в общее древо», без явного действия пользователя.
- ❌ Никаких автоматических merge'ей живых людей.
- ❌ Никаких public-search до отдельной opt-in настройки.
- ❌ Никаких уведомлений «вас добавили» во внешние каналы — только in-app.

---

## 6. Phased implementation plan (маленькие безопасные волны)

### Wave 0 — Тихая identity-миграция *(server-only, no UI)*
- Бэкенд: для каждой существующей `FamilyPerson` без identity создать `PersonIdentity` 1:1 (миграция в [`backend/src/migration-utils.js`](backend/src/migration-utils.js)).
- API: добавить `identityId` в `FamilyPerson` response (nullable).
- Flutter: добавить `identityId` в [`lib/models/family_person.dart`](lib/models/family_person.dart) как nullable поле, не использовать.
- Tests: `node --test backend/test/postgres-store.test.js`, миграционный тест.
- **Done when:** все карточки имеют identity, никаких UI изменений.

### Wave 1 — Within-tree dedup suggestions *(safe baseline)*
- Бэкенд: новый модуль `backend/src/identity-matcher.js`, эндпоинт `GET /v1/trees/:treeId/duplicates` — возвращает пары кандидатов в одном дереве.
- Flutter: на [`lib/screens/relative_details_screen.dart`](lib/screens/relative_details_screen.dart) баннер «возможно, это один человек с …» + экран сравнения, действия «объединить / разные».
- Только manual merge внутри одного дерева, оба unclaimed.
- **Зачем сначала это:** обкатать matcher и UI согласия в безопасном scope.

### Wave 2 — Circles model (data + simple audience)
- Бэкенд: `circles`, `circleMembers`, эндпоинты CRUD: `routes/circle-routes.js` (по паттерну `routes/profile-routes.js`).
- Авто-круги: `all_tree` создаётся при создании дерева; `favorites` — пустой по умолчанию.
- API постов: `POST /v1/posts` принимает опциональный `circleId`; default — `all_tree` дерева.
- Flutter: новый виджет `AudiencePicker` в [`lib/screens/create_post_screen.dart`](lib/screens/create_post_screen.dart) и [`lib/screens/create_story_screen.dart`](lib/screens/create_story_screen.dart). Если выбрано «всё дерево» — UI как раньше.
- Lists фильтрация: home feed подставляет `circleIds`, в которые входит viewer.
- **Зачем:** даёт юзеру контроль над аудиторией ДО рискованных cross-tree вещей.

### Wave 3 — Auto-circles по структуре дерева
- Бэкенд: при создании/изменении relation пересчитывать «потомков X», «ветку Y», «пару Z + дети». Хранить как `Circle.kind = 'descendants_of'` с `anchorPersonId`.
- Flutter: AudiencePicker показывает рассчитанные circles с превью «12 человек».
- **Не трогает privacy — только удобный subset of tree.**

### Wave 4 — Cross-tree merge proposals
- Бэкенд: matcher теперь сканит между деревьями. Эндпоинты `GET /v1/merge-proposals/pending`, `POST /v1/merge-proposals/:id/review`. Privacy gates: ничего не показываем, кроме «совпадение по имени и году рождения».
- Flutter: новый раздел «Возможные совпадения» в notifications, экран review.
- ВАЖНО: на этой волне впервые появляется возможность увидеть данные из чужого дерева — обязательно обновить privacy defaults для living people ПЕРЕД релизом этой волны.

### Wave 5 — Field-level visibility + identity claims
- Бэкенд: `personAttributes` с `visibility`, `identityClaims` flow.
- Flutter: настройка приватности на карточке (4–5 групп полей), экран claim'а аккаунта.

### Wave 6 — Public discoverability (opt-in)
- Bare minimum: «разрешить искать меня по ФИО + году» — отдельная настройка identity owner'а. Без неё — невидим извне.

### Wave 7+ — Будущее: chat audiences, контент в кругах из других деревьев, и т.д.

---

## 7. Какие файлы Родни вероятно затронет

**Flutter — модели (Wave 0, 1):**
- [`lib/models/family_person.dart`](lib/models/family_person.dart) (+`.g.dart`) — поле `identityId`.
- new: `lib/models/person_identity.dart`, `lib/models/merge_proposal.dart`.

**Flutter — модели (Wave 2):**
- new: `lib/models/circle.dart`, `lib/models/audience_target.dart`.
- [`lib/models/post.dart`](lib/models/post.dart), [`lib/models/story.dart`](lib/models/story.dart) — поле `circleId` / `audience`.

**Flutter — сервисы:**
- [`lib/services/custom_api_family_tree_service.dart`](lib/services/custom_api_family_tree_service.dart) — эндпоинты duplicates, merges, identity (Wave 1, 4).
- [`lib/services/custom_api_post_service.dart`](lib/services/custom_api_post_service.dart), [`lib/services/custom_api_story_service.dart`](lib/services/custom_api_story_service.dart) — параметр circleId (Wave 2).
- new: `lib/services/circle_service.dart`, `lib/services/identity_service.dart`.
- Интерфейсы в [`lib/backend/interfaces/`](lib/backend/interfaces/) — расширить.

**Flutter — экраны:**
- [`lib/screens/relative_details_screen.dart`](lib/screens/relative_details_screen.dart) (1773 строки!) — баннер совпадений, «объединено с …», cross-tree-info. **Это сильно осложнит без волны B (split sections) из предыдущего аудита.** Рекомендую сначала тот split, потом эти изменения.
- [`lib/screens/create_post_screen.dart`](lib/screens/create_post_screen.dart), [`lib/screens/create_story_screen.dart`](lib/screens/create_story_screen.dart) — `AudiencePicker`.
- [`lib/screens/home_screen.dart`](lib/screens/home_screen.dart) — фильтрация feed по circles.
- [`lib/screens/notifications_screen.dart`](lib/screens/notifications_screen.dart) — merge proposal items.
- new: `lib/screens/merge_review_screen.dart`, `lib/screens/circle_management_screen.dart`.

**Flutter — виджеты:**
- new: `lib/widgets/audience_picker.dart`, `lib/widgets/identity_match_card.dart`.
- [`lib/widgets/interactive_family_tree.dart`](lib/widgets/interactive_family_tree.dart) — потенциально показывать «возможные совпадения» как бейдж на узле.

**Backend:**
- [`backend/src/store.js`](backend/src/store.js) — расширить `EMPTY_DB`, добавить методы `findIdentityCandidates`, `proposeMerge`, `reviewMerge`, `listCircles`, …
- [`backend/src/postgres-store.js`](backend/src/postgres-store.js) — новые таблицы и projection-апдейты.
- [`backend/src/migration-utils.js`](backend/src/migration-utils.js) — Wave 0 миграция.
- [`backend/src/app.js`](backend/src/app.js) — регистрация новых routes.
- new: `backend/src/identity-matcher.js`.
- new: `backend/src/routes/circle-routes.js`, `backend/src/routes/identity-routes.js`, `backend/src/routes/merge-routes.js`, `backend/src/routes/post-routes.js` (волна D из прошлого аудита — туда же добавляем `circleId`).

**Tests:**
- new: `backend/test/identity-matcher.test.js`, `circle-routes.test.js`, `merge-routes.test.js`.
- update: `test/relative_details_screen_test.dart`, `test/home_screen_test.dart`, `test/post_card_test.dart`.

---

## 8. Backward compat & migrations

**Гарантии:**

1. **Existing API контракт не ломаем.** Все новые поля — additive nullable. Старые клиенты продолжают работать.
2. **Старые посты без `circleId`** трактуются как `circle:all_tree(treeId)` — view-time mapping, без переписывания данных.
3. **Identity миграция (Wave 0)** идемпотентна: повторный запуск не создаёт дубликаты. Условие создания: `WHERE NOT EXISTS (SELECT 1 FROM person_identities WHERE personId IN ...)`.
4. **Merge — реверсивный** (split в течение 30 дней).
5. **Adapter-слой между слоями:**
   - В Flutter: интерфейсы `FamilyTreeServiceInterface` остаются, добавляем подметоды `IdentityServiceInterface`. Никаких breaking changes для UI кода вне зон волн.
   - В backend: `store.js` оставляем, новые методы добавляем. Не трогаем существующие сигнатуры.
6. **Feature flag** через [`backend_runtime_config.dart`](lib/backend/backend_runtime_config.dart) — `enableIdentityMerge`, `enableCircles`. Можно выкатить data-слой и держать UI скрытым до проверки.
7. **Никаких разрушительных DDL.** Только `CREATE TABLE`, `ADD COLUMN ... NULL`. Никаких `DROP COLUMN` / `RENAME` в этой работе.
8. **Откат каждой волны** = revert одного коммита + (для Wave 0) ничего, потому что данные additive.

**Calls/voice/video** — НЕ трогаем. `CallCoordinatorService`, `livekit-service.js`, маршруты `/v1/calls/*` остаются как есть.

---

## TL;DR для следующего шага

Если хочешь, чтобы я начал делать — берём **Wave 0** одним коммитом:

1. Скрипт миграции в `backend/src/migration-utils.js`: создать `PersonIdentity` для каждой `FamilyPerson` без неё.
2. Эндпоинт `GET /v1/persons/:personId` возвращает `identityId`.
3. Поле `identityId` добавлено в [`lib/models/family_person.dart`](lib/models/family_person.dart) и `.g.dart` пересобран (`flutter pub run build_runner build`).
4. Тесты: `backend/test/postgres-store.test.js` + новый `identity_migration.test.js`.
5. Никаких UI изменений.

После Wave 0 пойдём к **Wave 1** (suggestions внутри одного дерева) — это первая фича, которую увидит пользователь.

Скажи, какую часть плана хочешь обсудить/уточнить перед стартом — модель кругов, merge-флоу, privacy default'ы, последовательность волн? И хочешь ли, чтобы я начал с Wave 0 или сначала закрыл pending refactor-волны из предыдущего аудита (особенно split [`relative_details_screen.dart`](lib/screens/relative_details_screen.dart), он сильно облегчит Wave 1).
