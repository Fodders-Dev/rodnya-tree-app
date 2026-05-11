# Audit — connected-trees refactor

**Дата**: 2026-05-09 (Phase 0 / read-only audit)
**Контекст**: см. `PLAN.md` (целевая модель — connected per-user trees через
identity-граф) и `tree_model_overhaul_rfc.md` (более ранний RFC, частично
исполнен в коде — см. секцию **«Pre-existing graph layer»** ниже).

> ⚠️ **Главная находка аудита**: в коде уже существует параллельный
> unified-graph слой (`graphPersons`/`graphRelations`/`branches`/
> `branchPersonViews`), скрытый за `_syncGraphFromLegacy`. Это исполнение
> отдельного RFC (`docs/tree_model_overhaul_rfc.md`, 2026-05-07), которое
> не упомянуто в `PLAN.md`. Соотношение этих двух планов нужно зафиксировать
> в `DECISIONS.md` ДО старта Phase 1 — иначе мы можем дублировать или
> перетирать уже сделанную работу. Раздел **«Open architecture questions»**
> в конце этого документа.

---

## Категории и источники изменений

В каждом разделе помечены сущности, которые трогает место, и фаза по
`PLAN.md`, в которой это место будет переписано.

Легенда сущностей:
- `T` — `tree.creatorId`/`memberIds`/`members` (multi-tree модель)
- `P` — `linkPersonToUser`/`unlinkUserFromPerson` (slot-link semantics)
- `I` — identity-matcher и identity-граф
- `B` — `BranchSwitcher`/multi-tree UI
- `M` — миграции (legacy → graph/branch)

Легенда фаз — по `PLAN.md`:
- **0** — design/audit (текущая)
- **1** — auto-create tree on registration
- **2** — identity backbone
- **3** — invite semantics
- **4** — cross-tree network view
- **5** — permissions & ownership (rename `creatorId` → `ownerId`, удалить `memberIds`)
- **6** — data migration
- **7** — cleanup

---

## 1. Backend

### 1.1 Хранилище и схема

| Файл | Что делает | Сущности | Фаза |
|---|---|---|---|
| [backend/src/store.js:49](backend/src/store.js:49) (`EMPTY_DB`) | Объявляет коллекции БД. Включает legacy `trees`/`persons`/`relations`/`personIdentities` И новые `graphPersons`/`graphRelations`/`branches`/`branchPersonViews`/`migrationStatus`. | T, P, I, M | 5/6/7 |
| [backend/src/store.js:130](backend/src/store.js:130) (`normalizeDbState`) | Гарантирует наличие всех коллекций при чтении JSON. Любое новое поле в `tree`/`branch` идёт сюда. | T, M | 5/6 |
| [backend/src/store.js:130-220](backend/src/store.js:130) (`createPostRecord`) | Внутри `createPostRecord` уже есть ветка «`if (normalizedBranchIds.length === 0 && treeId)` → `branchIds = [treeId]`» — backward-compat между legacy `treeId` и новым `branchIds`. | T, M | 6 |
| [backend/src/store.js:5470-5503](backend/src/store.js:5470) (`initialize` → миграции на старте) | На каждом старте вызывает `backfillPersonIdentities` + `migrateTreesToGraphAndBranches`. **Важно**: `migrateTreesToGraphAndBranches` уже бежит и заполняет graph/branches, идемпотентно по `migrationStatus.treesToGraph`. | I, M | 6 |
| [backend/src/store.js:5510-5542](backend/src/store.js:5510) (`_read` / `_write`) | На каждом read/write вызывает `_syncGraphFromLegacy`, держа graph mirror eventually-consistent с legacy. | M | 6/7 |
| [backend/src/store.js:5601-5717](backend/src/store.js:5601) (`_reconcilePersonIdentities`) | Поддерживает консистентность `personIdentities[]` ↔ `persons[].identityId` ↔ `users[].identityId`. Перестраивает stewardUserIds. Запускается после ВСЕХ операций над person/identity. | I | 2 |
| [backend/src/store.js:5719-5751](backend/src/store.js:5719) (`_ensureUserIdentity`) | На любого юзера гарантирует одну identity-запись, привязанную к `userId`. Используется при регистрации (не сейчас — сейчас вызывается отложенно при `createTree`). | I | 1 |
| [backend/src/store.js:5753-5780](backend/src/store.js:5753) (`_attachPersonToIdentity`) | Связывает person с identity, опционально фиксируя `userId`. Вызывается из `linkPersonToUser`, `linkPersonsByIdentity`, `ensureUserPersonInTree`, `createTree`, и проч. — около 14 call sites. **Ядерная функция identity-графа.** | I, P | 2 |

### 1.2 Tree CRUD и доступ

| Файл / строки | Что делает | Сущности | Фаза |
|---|---|---|---|
| [backend/src/store.js:7331-7393](backend/src/store.js:7331) (`createTree`) | Создаёт tree с `creatorId`, `memberIds: [creatorId]`, `members: [creatorId]`. Сразу делает self-person, привязывает к `_ensureUserIdentity`. **Должна стать дефолтной при регистрации** (Phase 1) — сейчас вызывается явно из `POST /v1/trees`. | T, I | 1, 5 |
| [backend/src/store.js:7395-7408](backend/src/store.js:7395) (`listUserTrees`) | Фильтр: `creatorId === userId || memberIds.includes(userId)`. Применяется почти во всех мульти-tree сценариях. | T | 5 |
| [backend/src/store.js:7644-7793](backend/src/store.js:7644) (`removeTreeForUser`) | Если `creatorId === userId` — удаляет дерево целиком. Если `member` — отвязывает юзера через `memberIds`/`members`. После Phase 5 «multiple members per tree» исчезнет. | T | 5/6 |
| [backend/src/store.js:7929-8036](backend/src/store.js:7929) (`ensureUserPersonInTree`) | Идемпотентно создаёт self-person в дереве для юзера + добавляет в `memberIds`. Используется при `accepted` relation request (chained tree access grant). | T, P | 5 |
| [backend/src/store.js:8167-8179](backend/src/store.js:8167) (`_userCanAccessTreeRecord`) | Helper для access guards: `creatorId === userId || memberIds.includes || members.includes`. Используется в search, identity suggestions, etc. | T | 5 |
| [backend/src/app.js:1719-1736](backend/src/app.js:1719) (`requireTreeAccess`) | Middleware-helper: `tree.creatorId === userId || memberIds.includes(userId)`. **Применяется в 18+ роутах** (см. список регистраций в [app.js:2335](backend/src/app.js:2335)–`2410`). После Phase 5 → `tree.ownerId === userId` (нет шеринга — каждый сам в своём дереве). | T | 5 |

### 1.3 Person ↔ User binding (slot-link)

| Файл / строки | Что делает | Сущности | Фаза |
|---|---|---|---|
| [backend/src/store.js:7796-7863](backend/src/store.js:7796) (`linkPersonToUser`) | Привязывает userId к person-слоту в чужом дереве. Делает `_attachPersonToIdentity`, добавляет user в `tree.memberIds`. **Использует `additive: true`** в `applyCanonicalProfileToPerson` (фикс предыдущей сессии). | T, P, I | 3 (semantics меняется на identity-link) |
| [backend/src/store.js:7877-7927](backend/src/store.js:7877) (`unlinkUserFromPerson`) | Отвязывает userId от person-слота. Owner-only (`tree.creatorId !== actorId → 403`). После отвязки если у юзера больше нет person в этом дереве — убирает его из `memberIds`. **Останется в Phase 3 как owner-side recovery.** | T, P | 3, 5 |
| [backend/src/store.js:8278-...](backend/src/store.js:8278) (`linkPersonsByIdentity`) | Связывает два person-record'а по общему identityId. Гард `CONFLICTING_IDENTITIES` (если оба claimed разными userId — отказ). Используется в Phase 1.2 voltage-indicator. **Это будущий main path** identity-link semantics в Phase 3. | I | 2/3 |
| [backend/src/store.js:9056-9063](backend/src/store.js:9056) (`searchPublicIdentities` / cross-tree share helpers) | Helper'ы для public identity discovery + cross-tree share. Используются в `identity-routes.js`. Расширяются в Phase 2. | I | 2 |

### 1.4 Routes

| Файл | Endpoints | Что делает | Сущности | Фаза |
|---|---|---|---|---|
| [backend/src/routes/tree-routes.js:25-41](backend/src/routes/tree-routes.js:25) | `POST /v1/trees` | Ручное создание tree. После Phase 1 это будет «создать дополнительную ветку» (если решим оставить multi-tree) или вообще удалится. | T | 1, 5 |
| [backend/src/routes/tree-routes.js:43-48](backend/src/routes/tree-routes.js:43) | `GET /v1/trees` | Список trees юзера. После Phase 1 у новых юзеров — всегда не пусто. После Phase 5/6 — длина 1. | T | 1, 5 |
| [backend/src/routes/tree-routes.js:50-85](backend/src/routes/tree-routes.js:50) | `DELETE /v1/trees/:treeId` | Удаление/leave дерева. Проверка через `creatorId`+`memberIds`. | T | 5 |
| [backend/src/routes/tree-routes.js:133-142](backend/src/routes/tree-routes.js:133) | `GET /v1/trees/selectable` | Облегчённый список для селектора (только id+name+createdAt). После Phase 5 пустой/сильно урезается. | T, B | 5 |
| [backend/src/routes/tree-routes.js:157-199](backend/src/routes/tree-routes.js:157) | `GET /v1/persons/search` | Cross-tree picker (Phase 0 unified-graph migration). **Этот endpoint — уже identity-friendly**, но scope ограничен «accessible trees» (через `_userCanAccessTreeRecord`). Расширяется в Phase 4. | I | 2/4 |
| [backend/src/routes/tree-routes.js:213-238](backend/src/routes/tree-routes.js:213) | `GET /v1/trees/:treeId/duplicates` | Within-tree duplicate suggestions. Не меняется. | I | — |
| [backend/src/routes/tree-routes.js:245-275](backend/src/routes/tree-routes.js:245) | `GET /v1/trees/:treeId/persons/:personId/identity-suggestions` | Cross-tree 💡 indicator. Внутри: `findCrossTreeSuggestionsForPerson`. Расширяется в Phase 2 (более широкий accessible scope). | I | 2 |
| [backend/src/routes/tree-routes.js:283-333](backend/src/routes/tree-routes.js:283) | `POST /v1/trees/:treeId/persons/:personId/link-identity` | Confirm 💡-suggestion → `linkPersonsByIdentity`. **Это уже Phase 3-friendly шлюз.** В Phase 3 invite-flow на нём строится. | I | 3 |
| [backend/src/routes/tree-routes.js:340-365](backend/src/routes/tree-routes.js:340) | `DELETE /v1/trees/:treeId/persons/:personId/user-link` | Owner отвязывает юзера от слота. Останется как owner-side recovery. | T, P | 5 |
| [backend/src/routes/tree-routes.js:370-390](backend/src/routes/tree-routes.js:370) | `POST /v1/trees/:treeId/persons/:personId/dismiss-suggestion` | User-level dismiss — не показывать эту пару в 💡. | I | — |
| [backend/src/routes/tree-routes.js:403-498](backend/src/routes/tree-routes.js:403) | `GET /v1/trees/:treeId/digest`, `GET /v1/trees/:treeId/conflicts`, `POST .../resolve` | Phase 1.3 conflict surfacing + Phase 6.3 digest. **Уже на новой identity-модели.** | I | — |
| [backend/src/routes/tree-routes.js:507-572](backend/src/routes/tree-routes.js:507) | `POST /v1/trees/:treeId/persons/import` | Bulk-import persons из дерева A в дерево B (Step 2 selection-mode). После Phase 5 теряет смысл (одно дерево на юзера) — либо мигрирует в «merge into me» logic. | T, I | 5/6 |
| [backend/src/routes/tree-routes.js:574-614](backend/src/routes/tree-routes.js:574) | `POST /v1/trees/:treeId/persons` | Создать person, опционально с `sourcePersonId` (cross-tree picker). | T, I | — |
| [backend/src/routes/tree-routes.js:616-872](backend/src/routes/tree-routes.js:616) | `GET/PATCH/DELETE /v1/trees/:treeId/persons/:personId` (+ media) | Person CRUD + propagation `_propagatedTo`. Стабильно. | T | — |
| [backend/src/routes/tree-routes.js:874-892](backend/src/routes/tree-routes.js:874) | `GET /v1/trees/:treeId/history` | Tree change records. | T | — |
| [backend/src/routes/tree-routes.js:894-1032](backend/src/routes/tree-routes.js:894) | `GET/POST/DELETE /v1/trees/:treeId/relations(/:id)` + `GET /graph` | Relations + tree graph snapshot. | T | — |
| [backend/src/routes/tree-invitation-routes.js](backend/src/routes/tree-invitation-routes.js) | `GET /v1/tree-invitations/pending`, `POST /v1/trees/:treeId/invitations`, `POST /v1/tree-invitations/:id/respond` | Tree-level invitation: отдельный entity, добавляет userId в `tree.memberIds`. **Этот flow конкурирует с invite-link/`linkPersonToUser`.** В Phase 3 либо мерджится с identity-link, либо депрекейтится. | T | 3, 5 |
| [backend/src/routes/pending-invitation-routes.js](backend/src/routes/pending-invitation-routes.js) | `POST /v1/invitations/pending/process` | Принимает `{treeId, personId}` и вызывает `linkPersonToUser`. **Главный invite-link endpoint.** Будет переименован/заменён на identity-claim в Phase 3. | T, P | 3 |
| [backend/src/routes/relation-request-routes.js](backend/src/routes/relation-request-routes.js) | `GET/POST/POST` relation-requests (4 endpoints) | Параллельный flow «отправить запрос на родство». При accepted вызывает `linkPersonToUser`/`ensureUserPersonInTree`. **Этот flow тоже добавляет в `tree.memberIds` через `linkPersonToUser`.** В Phase 3 нужно решить — либо identity-claim, либо как добавление родственника в чужое дерево (но тогда нарушает «одно дерево на юзера»). | T, P | 3, 5 |
| [backend/src/routes/identity-routes.js](backend/src/routes/identity-routes.js) | `/identity-claims/*`, `/identity-discovery/*`, person attributes | Identity claims (manual), public discoverability, person privacy. Phase 2 этим расширяется. | I | 2 |
| [backend/src/routes/merge-routes.js](backend/src/routes/merge-routes.js) | `/merge-proposals/pending`, `/merge-proposals/:id/review` | Merge-proposal flow (две карточки → одна). Используется когда автомерджа нельзя сделать. | I | 2 |
| [backend/src/routes/graph-routes.js](backend/src/routes/graph-routes.js) | `GET /v1/graph/relation?from=&to=` | **Phase 4 endpoint.** BFS по `graphRelations`, возвращает chain+label+degree. Уже работает на unified-графе. | I, M | 4 |

### 1.5 Identity matcher

| Файл / строки | Что делает | Сущности | Фаза |
|---|---|---|---|
| [backend/src/identity-matcher.js:6-14](backend/src/identity-matcher.js:6) (`normalizeName`) | Кириллица + латиница, ё→е, lowercase. | I | — |
| [backend/src/identity-matcher.js:58-131](backend/src/identity-matcher.js:58) (`scorePersonPair`) | Главная функция scoring. Сигналы: ФИО, дата/год рождения, пол, место рождения, дата смерти. Возвращает `{score, reasons}` или `null` если threshold не пройден. См. [IDENTITY-MATCHER.md](IDENTITY-MATCHER.md). | I | 2 |
| [backend/src/identity-matcher.js:133-198](backend/src/identity-matcher.js:133) (`findWithinTreeDuplicateCandidates`) | Within-tree O(N²) сравнение. Применяется в `/v1/trees/:treeId/duplicates`. | I | — |
| [backend/src/identity-matcher.js:213-281](backend/src/identity-matcher.js:213) (`findCrossTreeIdentitySuggestions`) | Cross-tree (только в accessible trees caller'а). Применяется в `findCrossTreeSuggestionsForPerson` → 💡 indicator. **Расширяется в Phase 2** (расширить scope до identity-граф соседей с двусторонним consent). | I | 2 |

### 1.6 Migration utils & graph layer

| Файл / строки | Что делает | Сущности | Фаза |
|---|---|---|---|
| [backend/src/migration-utils.js:106-259](backend/src/migration-utils.js:106) (`backfillPersonIdentities`) | Гарантирует identityId на каждом person + дедуплицирует identity rows. Вызывается на startup и в `_reconcilePersonIdentities`. | I | — (стабильно) |
| [backend/src/migration-utils.js:261-576](backend/src/migration-utils.js:261) (`migrateTreesToGraphAndBranches`) | **One-shot migration** legacy → graph: PersonIdentity→graphPerson, tree→branch (`ownerId` вместо `creatorId`!), relations dedup, branchPersonViews. Идемпотентно по `migrationStatus.treesToGraph === "complete"`. | I, M | 6 |
| [backend/src/store.js:9919-...](backend/src/store.js:9919) (`_syncPersonToGraph`, `_syncTreeToBranch`, `_markPersonDeletedInGraph`, `_syncGraphFromLegacy`) | Incremental graph mirror — каждый legacy write зеркалится в graph. **Это значит: graph/branches уже работают, вторая половина Phase 3 PLAN.md уже реализована.** | M | 6/7 |

### 1.7 Postgres-store

[backend/src/postgres-store.js](backend/src/postgres-store.js) — это thin wrapper над JSONB-документом в Postgres (одна row `state`, columns с jsonb-патчами). НЕ нормализует схему в реляционные таблицы. Trees/persons/relations лежат как массивы внутри `data->'trees'`, `data->'persons'`. Поэтому миграции = JSONB-операции, не ALTER TABLE.

**Важно для Phase 6**: миграция в реальной prod-БД = переписать JSONB документ. Транзакционно (одна row), но требует staging-теста на копии prod-данных.

---

## 2. Client (Flutter)

### 2.1 Модели

| Файл | Поля под рефакторинг | Фаза |
|---|---|---|
| [lib/models/family_tree.dart](lib/models/family_tree.dart) | `creatorId`, `memberIds`, `members`. Hive type 2 — миграция Hive box при изменении полей! | 5/6 |
| [lib/models/family_tree.g.dart](lib/models/family_tree.g.dart) | Auto-generated Hive adapter. Регенерируется через build_runner. | 5/6 |
| [lib/models/family_person.dart](lib/models/family_person.dart) | Использует `creatorId` (creator-of-this-person, не tree). Стабильно. | — |
| [lib/models/event.dart](lib/models/event.dart) | Использует `creatorId` event-author. Не тот контекст. | — |
| [lib/backend/models/identity_suggestion.dart](lib/backend/models/identity_suggestion.dart) | Phase 1.2 модель — `sourcePersonId/targetPersonId`. Стабильно. | — |
| [lib/backend/models/cross_tree_person_suggestion.dart](lib/backend/models/cross_tree_person_suggestion.dart) | Phase 0 cross-tree picker. Стабильно. | — |
| [lib/backend/models/branch_digest.dart](lib/backend/models/branch_digest.dart) | Phase 6.3 digest. | — |

### 2.2 Сервисы

| Файл | Что трогает | Фаза |
|---|---|---|
| [lib/services/custom_api_family_tree_service.dart](lib/services/custom_api_family_tree_service.dart) | Все `/v1/trees/...` HTTP вызовы. ~50 вхождений `treeId`. Меняются URL-схемы / payload. **Особо аккуратно**: `createRelation`, `disconnectRelation`, `addRelative`, `deleteRelative` — используются в `TreeMutationHistory` (undo/redo). | 1, 3, 5 |
| [lib/services/custom_api_family_tree_service.dart:1622](lib/services/custom_api_family_tree_service.dart:1622) | Парсинг `tree.memberIds` из json. | 5 |
| [lib/services/custom_api_auth_service.dart:1112-1185](lib/services/custom_api_auth_service.dart:1112) (`processPendingInvitation`) | Вызывает `POST /v1/invitations/pending/process` после авторизации. **Меняется в Phase 3** (новый identity-claim endpoint). | P | 3 |
| [lib/services/custom_api_auth_service.dart:807,876,946,1256,1268](lib/services/custom_api_auth_service.dart:807) | 5 точек вызова `processPendingInvitation` (после login, OAuth, complete-profile, etc.). | 3 |
| [lib/services/invitation_link_service.dart](lib/services/invitation_link_service.dart) | Строит `/#/invite?treeId=&personId=`. **Phase 3**: новый формат `/#/invite-identity?...` или identity-token. Старый формат должен пережить ~3 месяца. | 3 |
| [lib/services/invitation_service.dart](lib/services/invitation_service.dart) | Persists `pending_invitation_tree_id_v1` + `pending_invitation_person_id_v1` (SharedPreferences). При смене формата — миграция ключей или supports-both на старте. | 3 |
| [lib/services/tree_mutation_history.dart](lib/services/tree_mutation_history.dart) | Undo/redo для relations + person edit/delete. Зависит от сигнатур `createRelation`/`disconnectRelation`/`addRelative`/`deleteRelative`. **Не ломать сигнатуры** при Phase 3/5 рефакторинге. | 3, 5 |
| [lib/services/tree_graph_cache.dart](lib/services/tree_graph_cache.dart) | Кеш graph-snapshot per `treeId`. Инвалидация по `_propagatedTo` (Phase 1.1). При Phase 5 ключ кеша станет либо `branchId`, либо что-то другое. | 5 |
| [lib/services/public_tree_service.dart](lib/services/public_tree_service.dart) | Публичные деревья (без auth). Использует `creatorId`, `memberIds`. Меняется минимально. | 5 |
| [lib/services/local_storage_service.dart](lib/services/local_storage_service.dart) | Hive cache для FamilyTree/FamilyPerson. При смене модели — Hive box migration. | 6 |
| [lib/services/event_service.dart](lib/services/event_service.dart), [posts_cache.dart](lib/services/posts_cache.dart), [custom_api_post_service.dart](lib/services/custom_api_post_service.dart), [custom_api_story_service.dart](lib/services/custom_api_story_service.dart), [custom_api_chat_service.dart](lib/services/custom_api_chat_service.dart), [custom_api_circle_service.dart](lib/services/custom_api_circle_service.dart), [custom_api_identity_service.dart](lib/services/custom_api_identity_service.dart), [custom_api_notification_service.dart](lib/services/custom_api_notification_service.dart), [custom_api_profile_service.dart](lib/services/custom_api_profile_service.dart) | Все используют `treeId` как key для постов/историй/событий. После Phase 5 либо `branchId`, либо просто остаются — единственный treeId юзера = его id. | 5 |

### 2.3 Провайдеры и навигация

| Файл | Что делает | Фаза |
|---|---|---|
| [lib/providers/tree_provider.dart](lib/providers/tree_provider.dart) | Хранит `_selectedTreeId`/`_selectedTreeName`/`_selectedTreeKind`. Lazy load `availableTrees`. Persist в SharedPreferences. **После Phase 1**: всегда есть один default tree, после Phase 5 — селектор почти не нужен. | 1, 5 |
| [lib/navigation/app_router_guards.dart](lib/navigation/app_router_guards.dart) | Гард для `/invite?treeId=&personId=` — складывает в `InvitationService.setPendingInvitation` и тригерит `processPendingInvitation` после login. **Меняется в Phase 3** (identity-claim semantics). | 3 |
| [lib/navigation/app_router_guards.dart:75-93](lib/navigation/app_router_guards.dart:75) (`resolveTreeRootRedirect`) | Редирект `/` → `/tree/view/{selectedTreeId}`. После Phase 5 — `/tree/view/me` или просто `/tree/view`. | 1, 5 |
| [lib/navigation/app_shell_route_module.dart](lib/navigation/app_shell_route_module.dart) | Top-level navigation, treeId в URL. | 5 |
| [lib/navigation/app_overlay_route_module.dart](lib/navigation/app_overlay_route_module.dart) | Overlay routes (включая BranchSwitcher entry). | 5 |

### 2.4 Экраны

| Файл | Главные точки | Фаза |
|---|---|---|
| [lib/screens/tree_view_screen.dart](lib/screens/tree_view_screen.dart) | 2619 LOC. Главный canvas. Использует `TreeProvider.selectedTreeId`, BranchSwitcher, `_loadData(selectedTreeId)`, `_familyService.getUserTrees()`. **В Phase 4/5 — добавляется toggle «моё / расширенная сеть».** | 4, 5 |
| [lib/screens/tree_view_screen_sections.dart](lib/screens/tree_view_screen_sections.dart) | Sections-helper для main screen. | 4, 5 |
| [lib/screens/tree_selector_screen.dart](lib/screens/tree_selector_screen.dart) | Multi-tree selector. `_isOwnedByCurrentUser(tree)` через `tree.creatorId == currentUserId` ([:873](lib/screens/tree_selector_screen.dart:873)). Owner может удалить, member может leave. **Удаляется/упрощается в Phase 5** (либо переименовывается в branch-selector). | 5 |
| [lib/screens/relatives_screen.dart](lib/screens/relatives_screen.dart) | Список людей в выбранном tree. Использует `treeId`. | 4 (расширенный вид) |
| [lib/screens/relative_details_screen.dart](lib/screens/relative_details_screen.dart) | Карточка person. **Содержит вызов `unlinkUserFromPerson` ([:1571](lib/screens/relative_details_screen.dart:1571))**. Также cross-tree identity link UI. | 3, 5 |
| [lib/screens/add_relative_screen.dart](lib/screens/add_relative_screen.dart) | Add relative + cross-tree picker. **В Phase 2 — расширенный identity-suggestion inline.** | 2 |
| [lib/screens/find_relative_screen.dart](lib/screens/find_relative_screen.dart) | Поиск кандидата для отправки relation request. | 3 |
| [lib/screens/family_tree/create_tree_screen.dart](lib/screens/family_tree/create_tree_screen.dart) | UI создания нового дерева. **В Phase 1 этот экран либо отключается (auto-create), либо превращается в «создать дополнительную ветку».** | 1, 5 |
| [lib/screens/relation_request_screen.dart](lib/screens/relation_request_screen.dart), [relation_requests_screen.dart](lib/screens/relation_requests_screen.dart), [send_relation_request_screen.dart](lib/screens/send_relation_request_screen.dart) | Relation-request flow: отправка/inbox/ответ. Зависит от backend `linkPersonToUser`. | 3 |
| [lib/screens/identity_review_screen.dart](lib/screens/identity_review_screen.dart) (косвенно — упомянут в PLAN.md и graph-sync test) | Identity-claim review UX. **В Phase 2 становится главным экраном «Cross-family connections».** | 2 |
| [lib/screens/home_screen.dart](lib/screens/home_screen.dart), [home_screen_sections.dart](lib/screens/home_screen_sections.dart) | Главная лента. Использует `selectedTreeId`. После Phase 6.3 (`/digest`) — может ссылаться на digest. | 4 |
| [lib/screens/profile_screen.dart](lib/screens/profile_screen.dart), [profile_screen_sections.dart](lib/screens/profile_screen_sections.dart) | Профиль user'а. Trees-info (treeId, member-of). | 5 |
| [lib/screens/post_search_screen.dart](lib/screens/post_search_screen.dart), [story_viewer_screen.dart](lib/screens/story_viewer_screen.dart), [chat_screen.dart](lib/screens/chat_screen.dart), etc. | treeId как scope-filter в feed/stories/chats. | 5 |

### 2.5 Виджеты

| Файл | Что делает | Фаза |
|---|---|---|
| [lib/widgets/branch_switcher_chip.dart](lib/widgets/branch_switcher_chip.dart) | **`BranchSwitcherChip`** — Phase 6.1 chip в top bar. Показывает selected tree + opens bottom sheet с tree list. **Удаляется или упрощается в Phase 5** (если решим — single tree per user). | 5 |
| [lib/widgets/interactive_family_tree.dart](lib/widgets/interactive_family_tree.dart) | Главный canvas для рисования дерева. Принимает treeId, persons, relations. После Phase 4 будет рендерить «расширенный режим» с stylized чужими nodes. | 4 |
| [lib/widgets/interactive_family_tree_layout_models.dart](lib/widgets/interactive_family_tree_layout_models.dart) | Layout models. memberIds в context. | 5 |
| [lib/widgets/audience_picker.dart](lib/widgets/audience_picker.dart) | Audience picker для постов. Per-tree scope. | 5 |

---

## 3. Tests

### 3.1 Backend

| Файл | LOC | Релевантные сценарии | Фаза |
|---|---|---|---|
| [backend/test/api.test.js](backend/test/api.test.js) | 13693 | `tree endpoints cover create tree, persons and relations` ([:3350](backend/test/api.test.js:3350)), `tree duplicate endpoint` ([:3479](backend/test/api.test.js:3479)), `photo media propagates` ([:3805](backend/test/api.test.js:3805)), `voltage-indicator matcher` ([:3939](backend/test/api.test.js:3939)), `identity propagation` ([:4192](backend/test/api.test.js:4192)), `cross-tree person picker` ([:4951](backend/test/api.test.js:4951)), `merge proposals` ([:5220](backend/test/api.test.js:5220), [:5374](backend/test/api.test.js:5374)), `identity claims/discovery` ([:5478](backend/test/api.test.js:5478)), `tree delete` ([:6095](backend/test/api.test.js:6095)), `relation requests + invite processing` ([:11181](backend/test/api.test.js:11181)), `tree invitations` ([:11450](backend/test/api.test.js:11450)), `tree graph snapshot` (множество тестов от [:9271](backend/test/api.test.js:9271) до [:10846](backend/test/api.test.js:10846)). | 1-7 (каждая фаза затронет какой-то блок) |
| [backend/test/graph-sync.test.js](backend/test/graph-sync.test.js) | 1136 | Целевые тесты `_syncGraphFromLegacy` инкрементального зеркалирования. **Эти тесты зафиксируют целевое поведение Phase 6** — нужно расширить ими. | 6 |
| [backend/test/identity-matcher.test.js](backend/test/identity-matcher.test.js) | 77 | Только `findWithinTreeDuplicateCandidates`. **Cross-tree, false-positive, мульти-сигнал — НЕ покрыто. Расширить в Phase 2.** | 2 |
| [backend/test/migration-utils.test.js](backend/test/migration-utils.test.js) | 455 | `backfillPersonIdentities`, `summarizeSnapshot`, hash. **`migrateTreesToGraphAndBranches` — НЕ покрыта тестом. Добавить перед Phase 6.** | 6 |
| [backend/test/postgres-store.test.js](backend/test/postgres-store.test.js) | 1174 | Postgres-side. JSONB операции, миграции. Phase 6 prod-cutover проверяется здесь. | 6 |

### 3.2 Client

| Файл | Что покрывает | Фаза |
|---|---|---|
| [test/tree_view_screen_test.dart](test/tree_view_screen_test.dart) | Main canvas behaviour, BranchSwitcher integration. | 5 |
| [test/tree_selector_screen_test.dart](test/tree_selector_screen_test.dart) | Multi-tree selector + leave/delete. | 5 |
| [test/tree_provider_test.dart](test/tree_provider_test.dart) | Persistence selectedTreeId. | 1, 5 |
| [test/create_tree_screen_test.dart](test/create_tree_screen_test.dart) | Manual tree creation flow. | 1 |
| [test/relatives_screen_test.dart](test/relatives_screen_test.dart) | Per-tree relatives list. | 4, 5 |
| [test/relative_details_screen_test.dart](test/relative_details_screen_test.dart) | Person card UX, **включая `unlinkUserFromPerson` UI**. | 3, 5 |
| [test/add_relative_screen_test.dart](test/add_relative_screen_test.dart) | Add relative + cross-tree picker. | 2 |
| [test/find_relative_screen_test.dart](test/find_relative_screen_test.dart) | Find relative for relation-request. | 3 |
| [test/identity_review_screen_test.dart](test/identity_review_screen_test.dart) | Identity-claim/merge UX. | 2 |
| [test/invitation_link_service_test.dart](test/invitation_link_service_test.dart) | Build/parse `/#/invite?...`. | 3 |
| [test/deep_link_handler_test.dart](test/deep_link_handler_test.dart) | Deep link routing. | 3 |
| [test/app_router_tree_route_test.dart](test/app_router_tree_route_test.dart) | Router guards + redirects. | 1, 5 |
| [test/custom_api_family_tree_service_test.dart](test/custom_api_family_tree_service_test.dart) | HTTP service. **Sigfauchen `unlinkUserFromPerson` (1170:), `createRelation`/`disconnectRelation` — undo/redo.** | 3, 5 |
| [test/custom_api_auth_service_test.dart](test/custom_api_auth_service_test.dart) | `processPendingInvitation` flow. | 3 |
| [test/custom_api_identity_service_test.dart](test/custom_api_identity_service_test.dart) | Identity claims/discovery. | 2 |
| [test/send_relation_request_screen_test.dart](test/send_relation_request_screen_test.dart), [interactive_family_tree_test.dart](test/interactive_family_tree_test.dart) | Relation-request flow + canvas. | 3 |

---

## 4. Documentation

| Файл | Что описывает | Связь с PLAN.md |
|---|---|---|
| [docs/connected-trees-refactor/PLAN.md](docs/connected-trees-refactor/PLAN.md) | Текущий план рефакторинга. **Single tree per user.** | (источник правды) |
| [docs/connected-trees-refactor/CURRENT-PHASE.md](docs/connected-trees-refactor/CURRENT-PHASE.md), [DECISIONS.md](docs/connected-trees-refactor/DECISIONS.md), [PROGRESS.md](docs/connected-trees-refactor/PROGRESS.md), [KICKOFF-PROMPT.md](docs/connected-trees-refactor/KICKOFF-PROMPT.md) | Trekker-файлы текущего плана. | (источник правды) |
| [docs/tree_model_overhaul_rfc.md](docs/tree_model_overhaul_rfc.md) (2026-05-07) | **Альтернативный/предыдущий RFC.** Описывает «единый граф + N веток per user». **Частично исполнен в коде** (Phase 1.1, 1.2, 1.3, 3.1, 3.4, 6.1 — см. секцию «Pre-existing graph layer» ниже). | ⚠️ конкурирует с PLAN.md — см. open questions |
| [docs/branches_ux_plan_2026-05-04.md](docs/branches_ux_plan_2026-05-04.md) | UX-план для audience-picker. Не схема данных. | independent |
| [docs/feed_audience_model_rfc_2026-05-08.md](docs/feed_audience_model_rfc_2026-05-08.md) | Feed audience scopes. Использует `branchIds[]`. | indirect |
| [docs/auth_identity_linking_2026-04-16.md](docs/auth_identity_linking_2026-04-16.md) | Identity-linking при auth (canonical profile, identityId). Совпадает с тем что уже в коде. | reference |
| [docs/backend_target_architecture.md](docs/backend_target_architecture.md), [docs/backend_audit.md](docs/backend_audit.md) | Бэкенд миграция Firebase → custom (старое). Не актуально для current refactor. | obsolete |
| [docs/active_execution_plan.md](docs/active_execution_plan.md), [active_execution_plan_chat_calls.md](docs/active_execution_plan_chat_calls.md) | Текущие execution plans (chats/calls). Не связано напрямую. | independent |
| [docs/session_handoff_*.md](docs) | Хронология сессий. Контекст. | reference |

---

## 5. Pre-existing graph layer (главное архитектурное обнаружение)

В коде уже существует параллельный unified-graph слой, который реализует
**бо́льшую часть** того, что PLAN.md описывает как «целевая модель»:

### Что уже есть в коде

* `EMPTY_DB.graphPersons` ([store.js:89](backend/src/store.js:89)) — один узел на одного реального человека (id=identityId).
* `EMPTY_DB.graphRelations` ([:90](backend/src/store.js:90)) — дедуплицированные рёбра между graphPersons.
* `EMPTY_DB.branches` ([:91](backend/src/store.js:91)) — каждое legacy `tree` зеркалится как `branch` с `ownerId` (вместо `creatorId`!) + `includeRules` + `legacyTreeId`.
* `EMPTY_DB.branchPersonViews` ([:92](backend/src/store.js:92)) — per-(branch, person) editorial annotation.
* `EMPTY_DB.migrationStatus` ([:97](backend/src/store.js:97)) — флаг идемпотентности миграции.
* [migration-utils.js:395-576](backend/src/migration-utils.js:395) (`migrateTreesToGraphAndBranches`) — one-shot миграция, бежит на startup, идемпотентна.
* [store.js:9919+](backend/src/store.js:9919) (`_syncGraphFromLegacy` + помощники) — incremental mirror. Каждый legacy write зеркалится в graph; на _read/_write вызывается синхронизация.
* [routes/graph-routes.js](backend/src/routes/graph-routes.js) — endpoint `GET /v1/graph/relation` (Phase 4 BFS — уже работает!).
* [widgets/branch_switcher_chip.dart](lib/widgets/branch_switcher_chip.dart) — UI чип «ветки» (Phase 6.1).

### Что это значит для PLAN.md

| Аспект PLAN.md | Реальность в коде |
|---|---|
| «`personIdentities` становится первоклассной» | Уже сделано — `personIdentities` имеет полный lifecycle, `_reconcilePersonIdentities`, identity propagation, conflict log. |
| «`creatorId` → `ownerId`» (Phase 5) | В `branches` уже `ownerId`. Просто legacy `trees.creatorId` ещё жив параллельно. |
| «удалить `memberIds`» (Phase 5) | В `branches.memberIds` пока копируется из `tree.memberIds`, но семантически уже не нужен. |
| «расширенный cross-tree вид» (Phase 4) | Endpoint `/v1/graph/relation` уже считает BFS по графу. |
| «one-shot data migration» (Phase 6) | `migrateTreesToGraphAndBranches` уже бежит. |
| «один корень на юзера» (главный invariant) | ❌ **Не сделано.** Сейчас и в legacy и в graph-слое юзер может быть в N branches. |

**Главный конфликт**: PLAN.md описывает модель «один tree per user», а реальный
graph-слой реализует модель «общий граф + N branches per user». Это **разные
модели данных** — одна сводит дерево к строго личному пространству, вторая
делает дерево shared-but-filtered.

---

## 6. Open architecture questions (ДО старта Phase 1)

Перечисляю вопросы, на которые нужны ответы прежде чем начинать менять код.
Каждый вопрос будет зафиксирован в `DECISIONS.md` после ответа.

### Q1. Single-tree-per-user (PLAN.md) vs single-graph-many-branches (RFC + текущий код) — какую модель довести до конца?

* **PLAN.md** говорит: «У каждого юзера ровно ОДНО дерево, корнем которого он является. Удаляется multi-tree per-user. ОДНО дерево на юзера». Phase 5: «Удалить концепт `memberIds` / `members[]` — каждый юзер сам владеет своим деревом».
* **`tree_model_overhaul_rfc.md` + текущий graph-слой** говорит: «общий граф людей + N branches per user (срезы графа)».

Это две **разные** модели:

| | PLAN.md | RFC + код |
|---|---|---|
| Сколько деревьев у юзера | 1 | N branches |
| Что такое «дерево» в UI | моё личное дерево | one of my branches |
| BranchSwitcherChip | удаляется | оставляется (центральный UX) |
| Cross-tree связи | через `personIdentities` cross-link | через общий graphPerson |
| Канонический person record | нет (каждый person в своём дереве) | да (`graphPerson` для каждого реального человека) |

**Влияет на**: всё. Phase 1, 3, 4, 5 будут принципиально разные в зависимости от ответа.

**Возможные ответы**:
- A: «PLAN.md правильный, RFC устарел — graph-слой выпиливаем». Это значит **снять** уже сделанные Phase 3.1+1.2+1.3+6.1.
- B: «RFC правильный, PLAN.md описывает одно из срезов graph-модели — переписать PLAN.md, чтобы он соответствовал реальности». Тогда «одно дерево» = «branch с `includeRules.type === "blood-from-me"`», но multi-branch остаётся.
- C: «Гибрид: оставить graph под капотом, но пользователь видит только своё дерево». В этом случае BranchSwitcherChip скрывается, но `branches` коллекция жива.

### Q2. Что делать с `memberIds` — удалять или оставить как «приглашённый имеет read-доступ»?

PLAN.md (Phase 5) говорит «удалить `memberIds` полностью». Но текущая модель реальной семейной соцсети предполагает что несколько юзеров часто работают над одним деревом (Артём + Степа на семейном дереве). Если каждый видит только своё — это значит каждое родство дублируется в N деревьях через identity-link. Identity-matcher должен ВСЕГДА предложить связь — иначе UX распадается.

**Возможные ответы**:
- A: Полностью удалить. Identity-link через explicit consent — единственный механизм cross-user видимости.
- B: Оставить как «view-only» permission в чужом дереве (без редактирования). Это становится `treeVisibility` сущностью, упомянутой в PLAN.md.
- C: Перенести значение `memberIds` в `personIdentities.stewardUserIds` (уже есть в коде).

### Q3. Что делать с tree-invitations vs identity-claim — мерджить или оставить параллельно?

Сейчас три разных flow «привлечь юзера в моё дерево»:
1. `linkPersonToUser` через invite-link (`/v1/invitations/pending/process`) — слот-link, добавляет в memberIds.
2. `createTreeInvitation` (`/v1/trees/:treeId/invitations`) — explicit invite по userId/email, добавляет в memberIds.
3. `linkPersonsByIdentity` (`/v1/trees/:treeId/persons/:personId/link-identity`) — identity-claim между двумя existing person record'ами.

PLAN.md Phase 3 говорит «новый endpoint `POST /v1/invitations/identity-claim`». Это четвёртый или замена одному из существующих?

**Возможные ответы**:
- A: Новый identity-claim **заменяет** все три. Старые endpoints депрекейтятся, но живут 3 месяца.
- B: Новый identity-claim добавляется. Существующие три остаются как legacy + tree-invitation.
- C: Переименовать `linkPersonsByIdentity` → identity-claim invite, мерджить с tree-invitations.

### Q4. Hive box migration — нужен ли offline mode после refactor?

[lib/services/local_storage_service.dart](lib/services/local_storage_service.dart) хранит `FamilyTree`/`FamilyPerson` в Hive box (Hive type 2 для tree, type для person). После Phase 5 поля у `FamilyTree` поменяются (нет `memberIds`/`creatorId`). Hive type bump = открытие старого box на новой версии падает.

**Возможные ответы**:
- A: Bump type id + написать adapter migration. Сложнее, но offline продолжает работать.
- B: Drop Hive cache при первом запуске после миграции. Проще, но юзер на короткое время теряет offline-кеш.
- C: Параллельные модели (legacy `FamilyTree` + новая `Branch` или `MyTree`), Hive держит обе.

### Q5. Старые invite-links — поддерживать сколько?

PLAN.md говорит «старые ~3 месяца». Но `invitation_link_service.dart` пишет в SharedPreferences ключи `pending_invitation_tree_id_v1` + `pending_invitation_person_id_v1`. После cutover старые ключи могут существовать на устройствах — миграция = «прочитать legacy ключи, преобразовать в identity-claim, очистить».

**Уточнение**: 3 месяца считаем с первого деплоя Phase 3 или с финала Phase 7?

### Q6. Что с `creatorId` в `posts` / `stories` / `chat` записях?

Не tree.creatorId — но author-of-content `creatorId`/`createdBy` поля. Это **не тот** `creatorId` из tree-модели и в рефакторе НЕ участвует. Просто чтобы не путаться при grep'е.

---

## 7. Файлы под особой охраной (повтор PLAN.md «Файлы, к которым нужно подходить осторожно»)

| Файл | Почему | Фаза |
|---|---|---|
| [backend/src/store.js](backend/src/store.js) | 15500 LOC, ядро. `linkPersonToUser`, `_attachPersonToIdentity`, `_reconcilePersonIdentities`, `unlinkUserFromPerson`, `_syncGraphFromLegacy`. | 2, 3, 5, 6 |
| [backend/src/identity-matcher.js](backend/src/identity-matcher.js) | Расширение в Phase 2 порождает false-positives. См. [IDENTITY-MATCHER.md](IDENTITY-MATCHER.md). | 2 |
| [backend/src/migration-utils.js](backend/src/migration-utils.js) | One-shot миграции. Любая правка идёт под dry-run + rollback план. | 6 |
| [lib/services/custom_api_family_tree_service.dart](lib/services/custom_api_family_tree_service.dart) | 2178 LOC. `createRelation`/`disconnectRelation`/`addRelative`/`deleteRelative` зашиты в `TreeMutationHistory` (undo/redo). | 3, 5 |
| [lib/services/invitation_link_service.dart](lib/services/invitation_link_service.dart) + [lib/navigation/app_router_guards.dart](lib/navigation/app_router_guards.dart) | Invite-link обработка. Phase 3. | 3 |
| [lib/screens/tree_view_screen.dart](lib/screens/tree_view_screen.dart) | UI каркас. Phase 4/5. | 4, 5 |
| [web/index.html](web/index.html) | Legacy redirect для старых invite-link'ов должен пережить Phase 3. | 3 |

---

## 8. Что НЕ меняется (вне scope)

* Чаты и звонки — независимый flow.
* Stories — частично завязаны на `treeId` (audience scope), но модель stories не меняется.
* Posts — `treeId` уже сосуществует с `branchIds[]`. После Phase 5 → только `branchIds[]`.
* Auth (Google/VK/MAX/Telegram/email) — не меняется.
* Push-notifications — пути доставки не меняются.
* Profile fields, identity-discovery — стабильно.
* GEDCOM, federation — out of scope.

---

## Резюме

* Backend: ~15 файлов с активными ссылками на `treeId/creatorId/memberIds`. Из них 8 — routes, остальные — store + utils + identity-matcher.
* Client: ~89 файлов с `treeId`. Из них горячие — services (10), screens (~20), navigation (3), models (5–7), widgets (~5).
* Tests: backend api.test.js (13693 LOC) — главный источник регрессий, нужны inline-добавления почти во всех фазах. Client tests (~80) — тоже расширяются.
* Documentation: 2 параллельных RFC (PLAN.md vs tree_model_overhaul_rfc.md). До старта Phase 1 нужно зафиксировать в DECISIONS.md, какой из них «source of truth», и принять решения по Q1-Q5.
