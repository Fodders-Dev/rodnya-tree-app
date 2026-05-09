> ⚠️ **SUPERSEDED — этот план был написан без знания о RFC
> [`docs/tree_model_overhaul_rfc.md`](../tree_model_overhaul_rfc.md).
> Не использовать. Источник правды — RFC.**
>
> Решение зафиксировано 2026-05-09 в [DECISIONS.md](DECISIONS.md).
> Текущий код находится на пути RFC (Phase 0/1.1/1.2/3.1/3.4/6.1
> уже сделаны), и graphPersons + branches слой остаётся.

# Connected Per-User Trees — архитектурный рефакторинг

Целевой документ для многонедельной работы. Любой агент, работающий
над этой задачей, ОБЯЗАН начинать с чтения этого файла и
сверяться с ним перед каждым изменением. Если возникает решение,
которое расходится с планом, — фиксировать в `DECISIONS.md` рядом
с этим файлом, не молча отступать.

## Контекст

«Родня» — семейная социальная сеть. Сейчас (2026-05) в продукте
конфликт между двумя ментальными моделями:

1. **Per-user multi-tree** — текущая реализация. Юзер может
   создать N деревьев, у каждого `creatorId` владелец, остальные
   юзеры присоединяются по invite-link к конкретному person-слоту
   и становятся `members` БЕЗ прав редактирования.
2. **Connected per-user single-tree** — желаемое. У каждого юзера
   ОДНО дерево, корнем стоит он сам. Когда два юзера ссылаются на
   одного и того же реального человека (общая бабушка, например),
   `personId` записи разных деревьев связываются через **общий
   `personIdentityId`**. Каждый видит дерево со своей перспективы,
   но за кулисами — единый identity-граф.

Основной симптом проблемы (из жалобы юзера):
> «А если Степа начнёт своих родственников добавлять, то что, они
> у меня все будут на моем дереве? ... Я прихожу к мысли, что нужно
> у каждого пользователя держать одно дерево, которое будет
> разрастаться общими усилиями.»

Дополнительные боли:
* Дубликаты одних и тех же людей в разных деревьях разных юзеров
  (в семье есть N родственников, у каждого N person-record'ов
  каждого общего предка).
* Приглашённый юзер не имеет прав редактировать ничего, кроме
  собственного слота — фактически он observer.
* Юзеры без приглашения (просто скачали через RuStore) начинают
  с пустого экрана; невозможно «вступить» в чью-то семью без
  ручной отправки им link'а владельцем.

## Текущее состояние (snapshot, 2026-05)

### Сущности (backend, `backend/src/store.js`)

* `users` — учётные записи с профилем, `identityId` (ссылка на
  общий identity-record).
* `trees` — деревья. Поля: `id`, `name`, `creatorId`, `kind`
  (`family` | `friends`), `memberIds[]`, `members[]`, `isPrivate`.
  *Множественность*: один юзер может быть и creator, и member
  нескольких trees.
* `persons` — person-узлы. Tree-scoped (`treeId`). Поля включая
  `name`, `gender`, dates, `userId` (опционально — если node
  привязана к user-аккаунту), `identityId` (опционально — связь с
  cross-tree identity).
* `personIdentities` — cross-tree identity записи. Поля: `id`,
  `userId` (если identity attached к user-аккаунту),
  `claimedByUserId`, `personIds[]`, `primaryPersonId`. **Уже есть
  каркас** для cross-tree линковки, но используется только в
  узких сценариях (identity-claim suggestions, manual merge).
* `relations` — связи между persons в одном дереве. Tree-scoped
  (нет cross-tree relation'ов).
* `notifications` — обычная inbox-таблица.

### API (sample)

* `POST /v1/trees` — создать новое дерево, текущий user становится
  creator.
* `POST /v1/invitations/pending/process` — обработать invite-link;
  привязывает personId к userId (`linkPersonToUser` в store).
* `POST /v1/trees/:treeId/persons` — добавить person в дерево
  (только creator).
* `POST /v1/trees/:treeId/persons/:personId/link-identity` —
  ручная связь identity между двумя person-records через REST.
* `DELETE /v1/trees/:treeId/persons/:personId/user-link` — отвязать
  user-аккаунт от person-слота (новый, добавлен в этой сессии).

### Клиентские экраны

* `tree_view_screen.dart` — основной экран дерева. Имеет `BranchSwitcher`
  для переключения между несколькими деревьями юзера.
* `relatives_screen.dart` — список людей в выбранном дереве.
* `relative_details_screen.dart` — детали персоны, edit, добавить
  связь, отвязать пользователя.
* `add_relative_screen.dart` — добавить нового родственника к
  существующему слоту.

### Что уже есть в пользу cross-tree модели

* `personIdentities` таблица с full lifecycle.
* `linkPersonsByIdentity` API.
* Identity-suggestions backend (анализ имён + дат для предложения
  «эти двое — один человек»).
* `identity_review_screen.dart` — UX для подтверждения
  identity-claim'ов и предложений.

### Что мешает прямо сейчас

* Tree создаётся вручную, не автоматом при регистрации.
* `creatorId` — один владелец, нет понятия «co-owners».
* Invite-link → `linkPersonToUser` (привязка к слоту), а не к
  identity. Степа после invite — пассивный участник, не активный
  редактор своей ветки.
* `BranchSwitcher` в UI закрепляет multi-tree модель в
  пользовательском mental model'е.

## Целевая архитектура

### Главный invariant

> Каждый зарегистрированный юзер имеет ровно ОДНО дерево, корнем
> которого он является. Все cross-tree связи между разными
> юзерами выражаются через `personIdentities`.

### Сущности после рефакторинга

* `users` — без изменений.
* `trees` — упрощается. Один tree = один user. Поля: `id`,
  `ownerId` (вместо `creatorId`), `kind`, `name` (default = «Дерево
  Имя»), `isPrivate`. **Удаляется** `memberIds`, `members`.
* `persons` — без существенных изменений. Tree-scoped. `userId` и
  `identityId` остаются.
* `personIdentities` — становится **первоклассной** сущностью.
  Каждый реальный человек = один identity-record, на него
  указывают N person-записей из разных деревьев.
* `relations` — без изменений (внутри-древесные).
* Новая сущность **`treeVisibility`** — позволяет юзеру X
  предоставить юзеру Y доступ на просмотр своего дерева. Опционально
  на этот этап.

### Поведенческие изменения

#### При регистрации

* Создаётся дефолтное дерево «Дерево {firstName}» с user'ом как
  ownerId.
* В дереве создаётся одна person-нода, представляющая user'а
  самого (привязанная к его userId и identityId).

#### При добавлении родственника

* User в своём дереве добавляет person → обычный flow.
* Если backend identity-matcher находит candidates с других деревьев
  (по совпадению имени + даты + других сигналов), юзеру всплывает
  inline-suggestion: «Возможно, это {Имя} из дерева {OwnerName}.
  Связать?». При confirm — оба person-record'а получают общий
  identityId.

#### При invite

* Семантика invite-link меняется с «join my tree» на **«я обозначаю
  тебя как такого-то родственника, давай свяжем твой identity со
  слотом»**.
* Receiver принимает invite → его user-account создаёт identity
  link между его self-person в его дереве и слотом в дереве
  отправителя. Receiver получает push на свой self-person с
  обновлённой identityId. Дереву отправителя — также обновляется.
* В UI receiver'а появляется badge: «Вы связаны с {OwnerName}».

#### При просмотре дерева

* По умолчанию: user видит **своё** дерево.
* Кнопка «Расширенное родство» показывает identity-граф,
  в котором узлы из чужих деревьев тоже видны (с их именами как
  они их сами назвали). Есть pivot между «my view» / «aggregated
  network».

#### При conflict resolution

* Два юзера обозначают одного человека по-разному (Артём пишет
  «Бабушка Лида», Степа — «Mocharова Лидия Александровна 1949»).
* Identity-matcher предлагает «связать как одного человека».
* После связи каждый видит свой текст, но за кулисами — один
  identity-record.

### Что удаляется

* Multi-tree per-user. ОДНО дерево на юзера.
* `creatorId` поле в trees (заменяется `ownerId`).
* Invite-link semantics «привязать чужой userId к моему слоту»
  (заменяется identity-link semantics).
* `BranchSwitcher` widget (на старте) — заменяется простым view-toggle.

## План работ (по фазам)

### Phase 0 — design & audit (1-2 дня)

* Полный audit всех мест в коде (backend + client) которые
  трогают `treeId`, `creatorId`, `memberIds`. Список в
  `AUDIT.md`.
* Уточнить семантику identity matcher'а (какие сигналы он
  использует, насколько надёжен). Документ в `IDENTITY-MATCHER.md`.
* Написать ER-diagram текущей и целевой моделей. Сохранить
  в `SCHEMA.md`.
* Решить: сохраняем ли поддержку multi-tree per-user как
  legacy (для существующих юзеров с уже двумя деревьями) или
  принудительно сливаем при миграции? Зафиксировать в
  `DECISIONS.md`.
* DoD: PRs ждут начала Phase 1; есть consensus с user'ом о
  целевой схеме.

### Phase 1 — auto-create tree on registration (3-5 дней)

* Backend: при `POST /v1/auth/...` (любой sign-up flow) после
  создания user'а сразу создаётся default tree с user'ом
  как ownerId + self-person.
* Migration: для существующих юзеров без дерева создать
  дефолтные деревья.
* Client: тihi-tree селектор остаётся, но default-state — твоё
  главное дерево, авто-выбрано после login'а.
* Добавить feature-flag `connectedTreesPhase` в
  `BackendRuntimeConfig` чтобы можно было катить поэтапно.
* DoD: новый юзер регистрируется → сразу видит свою «Я» person
  в своём дереве. Существующие юзеры не сломаны.

### Phase 2 — identity backbone (5-8 дней)

* Backend: усилить identity-matcher, чтобы предлагать
  candidates из ВСЕХ доступных деревьев (с уважением приватности
  — на старте только из деревьев тех юзеров, кто прямо или
  косвенно связан через identity-граф).
* New API: `GET /v1/persons/identity-suggestions` — для
  inline-предложений при add-relative.
* Client: интегрировать suggestion-UI в add-relative-flow.
  Когда user вводит имя + дату, fetch candidates → показывает
  inline список → confirm создаёт identity link.
* Identity-review screen уже есть; усилить его чтобы был
  главным экраном «Cross-family connections», не просто
  «merge proposals».
* DoD: добавить родственника, выбрать predicted identity,
  оба user'а видят shared identity в своих интерфейсах.

### Phase 3 — invite semantics (3-5 дней)

* Backend: новый endpoint `POST /v1/invitations/identity-claim`
  (вместо текущего `linkPersonToUser`). Принимает treeId,
  personId, и **создаёт identity link** между этим slot'ом и
  self-person'ом receiver'а. Если у receiver'а нет дерева —
  создаётся (auto-tree из Phase 1).
* Migration: старые invite-links продолжают работать (legacy
  endpoint жив), но новые генерятся в новом формате.
* Client: `InvitationLinkService` строит ссылки нового
  формата (`#/invite-identity?...`).
* Snackbar на receiver-стороне: «Вы связаны с {OwnerName}, теперь
  он видит вас в своём дереве, а вы его — в своём».
* DoD: Артём шлёт invite Степе → оба видят shared identity,
  каждый в собственном дереве.

### Phase 4 — cross-tree network view (5-10 дней)

* Backend: `GET /v1/me/extended-family` — обходит identity-граф
  начиная от self-person и собирает связных людей через
  трёх-степенные shortest-path обходы. Возвращает
  «agglomerated» tree-snapshot.
* Client: новый view-mode «Расширенное родство» в `tree_view_screen`.
  Toggle вверху между «Моё дерево» / «Расширенная сеть».
  При расширенном — рендерим узлы из чужих деревьев другим
  стилем + имя owner'а в badge.
* DoD: Артём видит маму → Mocharова Лидия → её родители (через
  identity link с маминой стороны), причём узлы из чужих
  деревьев визуально отличимы.

### Phase 5 — permissions & ownership (3-5 дней)

* Backend: `tree.creatorId` → `tree.ownerId` (rename across
  codebase).
* Удалить концепт `memberIds` / `members[]` — каждый юзер сам
  владеет своим деревом.
* Permission model: у тебя есть права RW в **только своём**
  дереве. В чужих деревьях ты можешь только смотреть (если
  хост дал разрешение через identity-граф).
* Client: убрать `BranchSwitcher` (либо упростить до тoggle
  «family / friends»). На переходный период feature-flag
  включает оба варианта.
* DoD: пермишн model устаканился; нет «co-owners» концепта.

### Phase 6 — data migration (5-8 дней)

* Migration script: для существующих юзеров с multiple trees:
  выбрать «primary» (обычно — где user является creatorId), либо
  предложить юзеру выбрать, либо merge всех в одно дерево.
* Для существующих trees с multiple `memberIds`: каждый member
  получает собственное дерево с identity link к слоту в
  предыдущем общем дереве.
* Существующие person-records с одинаковым именем и датой через
  identity-matcher предлагаются для авто-merge'а (с явным
  consent юзера).
* Migration runs с feature-flag, поэтапно по группам юзеров,
  rollback готов.
* DoD: все юзеры pre-rollout получили миграцию без data loss;
  postmortem пишется.

### Phase 7 — cleanup & docs (2-3 дня)

* Удалить deprecated codepath'ы (старый invite-link, multi-tree
  selector).
* Обновить документацию (developer guide, end-user FAQ).
* Final регрессионное тестирование.
* DoD: все feature-flags `connectedTreesPhase` обернуты в
  default-on, можно физически снимать.

## Метрики успеха

* **Кардинальная метрика**: % юзеров у которых хотя бы один
  identity-link с другим юзером. Цель: > 60% активных юзеров
  через 30 дней после Phase 4.
* **Побочные метрики**:
  * Снижение количества person-record'ов в БД для одного и того
    же реального человека (среднее < 1.3 per real human).
  * Drop-off при invite-flow: у receiver'а conversion от тапа
    по link'у до identity-link создан > 70% (сейчас непонятно,
    скорее всего <50% из-за UX-friction'а).
  * Жалобы на «у меня в дереве чужие люди» / «дубликаты» <
    1 в неделю (сейчас регулярны).

## Главные риски

1. **Migration data loss** — самая страшная угроза. Mitigation:
   все migrations идут через staged rollout с возможностью
   rollback. Backup всех trees + persons перед запуском
   migration. Migration проверяется dry-run в staging.

2. **Privacy regression** — расширение видимости (cross-tree)
   может «вытащить» данные которые юзер не хотел показывать.
   Mitigation: identity-link требует явного двустороннего
   consent'а. Вид «extended family» только показывает узлы
   связанные через подтверждённые identity links — никогда не
   через предположения.

3. **Identity-matcher false positives** — система предлагает связать
   разных людей с одинаковым именем. Mitigation: confidence
   threshold; на confidence < 0.85 не показывать suggestion;
   ручной flag «не связывать» для отказов.

4. **Backward compat для invite-link'ов** — у юзеров на руках
   могут быть старые ссылки (path-based, не hash; legacy
   `linkPersonToUser`). Mitigation: Phase 6 миграция должна
   поддерживать оба формата ещё ~3 месяца, после депрекейтить.

5. **Сложность UX** — extended-family view может быть
   непонятным простым юзерам. Mitigation: feature-flag, пилот
   на ~50 юзеров перед общим раскатом, user-research перед
   Phase 4.

## Что НЕ входит в этот рефакторинг (вне scope)

* Группы / friend-circles в новом формате (TreeKind.friends
  остаётся как есть; их можно сделать identity-graph'ом
  отдельно позже).
* Импорт/экспорт GEDCOM (отдельная задача).
* Multi-language UX (только RU на старте).
* Federation между Родней и другими генеалогическими
  сервисами (отдельный продуктовый разговор).

## Файлы, к которым нужно подходить осторожно

Это самые «горячие» места. Любое изменение — phased, с
feature-flag'ом, с тестами:

* `backend/src/store.js` — `linkPersonToUser`,
  `_attachPersonToIdentity`, `_reconcilePersonIdentities`,
  `unlinkUserFromPerson`. Все четыре трогают данные мульти-юзерно.
* `backend/src/identity-matcher.js` — расширяется в Phase 2.
  Любое изменение порождает ложноположительные suggestions.
* `lib/services/custom_api_family_tree_service.dart` —
  `createRelation`, `disconnectRelation`, `addRelative`,
  `deleteRelative`. Эти методы вызываются из undo/redo, любые
  изменения сигнатур ломают TreeMutationHistory.
* `lib/services/invitation_link_service.dart` и
  `app_router_guards.dart` — invite-link обработка. Меняется в
  Phase 3.
* `lib/screens/tree_view_screen.dart` — UI каркас. Меняется в
  Phase 4 / 5.
* `web/index.html` — legacy redirect для старых invite-link'ов
  должен пережить Phase 3.

## Тесты и QA

Каждая фаза заканчивается:
* Backend tests (npm test) — все зелёные, включая новые регрессии.
* Flutter analyze — нет issues.
* Manual smoke на реальном устройстве (Артём + Степа happy path).
* Запись в `PHASE-N-DONE.md` с скриншотами и summary.

## Способ работы агента

Любая сессия по этой задаче должна:
1. Открыть и **прочитать** `PLAN.md` (этот файл) полностью.
2. Прочитать `DECISIONS.md` если есть (делается ходу работы).
3. Открыть `CURRENT-PHASE.md` чтобы понять на каком этапе сейчас.
4. Спросить у user-а подтверждение фазы и конкретного scope
   изменений ПЕРЕД любыми коммитами.
5. После каждого коммита обновлять `PROGRESS.md`.
6. Если возникает вопрос архитектурный — фиксировать в
   `DECISIONS.md` с датой и кратким обоснованием, не
   принимать решения молча.

Всё что меняет схему БД — двойной chest-checkout: feature-flag
на стороне сервера, миграционный скрипт с reversible-режимом.
