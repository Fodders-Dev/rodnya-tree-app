# Phase 3.2 — Owner-model enforcement gates on routes

> **Статус**: design proposal, ожидает review Артёма.
> **Источник правды**: [tree_model_overhaul_rfc.md](../tree_model_overhaul_rfc.md)
> + [DECISIONS.md](DECISIONS.md) ответ C («default owner-only edit,
> без auto-extension по hops, owner extension через explicit grants,
> двусторонний consent на merge»).
> **Не лезть в код** до явного approve этого документа.

---

## 0. Контекст и DoD

### Что делаем в Phase 3.2

После Phase 3.1 (commit `0d5acec`) у нас есть:
* `graphPerson.visibility` / `visibilityOverride` поля.
* `graphPersonEditGrants: []` коллекция.
* Pure helpers `_userCanSeeGraphPerson` / `_userCanEditGraphPerson` /
  `_userCanSeeSensitiveAttribute` / `_buildBranchVisiblePersonIds` /
  `_effectiveGraphPersonVisibility` / `_selfGraphPersonIdForUser`.

Schema готова, но **никакой route её не enforce'ит**. Curl-запрос
`PATCH /v1/trees/:treeId/persons/:personId {visibility: "public"}`
сейчас тихо запишет «public» на graphPerson через identity propagation
из legacy person — owner-only-всегда semantic нарушен.

Phase 3.2 закрывает этот surface: каждый route, который трогает
graphPerson canonical fields / soft-delete / merge / sensitive
attributes, проходит через owner-model gate. **End-to-end testable
через API tests без UI** — потому что если 3.2 ломает client-flow,
лучше знать сейчас, до Flutter-рефакторинга.

### Cutover plan (Артём 2026-05-10)

```
3.1 (done) → pre-prod (миграция + schema, legacy clients work)
3.2 (this) → pre-prod (enforcement, новые grants endpoints)
3.4        → pre-prod + prod (Flutter UI для visibility, grants, wizard)
```

Между 3.2 и 3.4 — **NO user-visible regression**. Legacy UI продолжает
работать на legacy persons (которые мигрированы в graphPersons, но
юзеру это не видно). Юзер не получит broken state.

### Что НЕ делаем в Phase 3.2

* Никакого Flutter UI (`Phase 3.4`).
* Никакой hard-delete background job (`Phase 3.6`).
* Никакого расширения identity-matcher.
* Никакого flip writes из legacy в graph (`Phase 3.4`).
* Не удаляем `tree.creatorId` / `memberIds` (`Phase 5/6`).

### DoD Phase 3.2

* Все routes, которые меняют graphPerson canonical / soft-delete /
  merge / visibility, gating'ованы.
* Новые endpoints `POST/GET/DELETE /v1/graph-persons/:id/grants` +
  `PATCH /v1/graph-persons/:id/visibility` работают.
* `GET /v1/me/edit-grants` — granted-юзер видит свои.
* Sensitive attributes filter'уются на READ для не-owner.
* Cross-tree READ paths (`/v1/persons/search`,
  `identity-suggestions`, `/v1/graph/relation`) honor visibility.
* Backward-compat: legacy creator/member может editить **anonymous**
  (graphPerson.userId === null) persons как раньше; **claimed** —
  только owner или grant.
* Все existing api.test.js — зелёные. Новые тесты — добавлены.
* `flutter analyze` без новых issues. `flutter test` —
  notification-test остаётся pre-existing fail (см. PROGRESS.md).

---

## 1. Anatomy: existing routes, кого gating'уем

Скан `backend/src/routes/`. Routes, которые трогают graphPerson
данные:

### 1.1 Mutate canonical / editorial / media (требуют edit gate)

| Endpoint | Что меняет | Текущий guard | Phase 3.2 gate |
|---|---|---|---|
| `PATCH /v1/trees/:treeId/persons/:personId` | name, dates, photos, visibility | `requireTreeAccess` | + `requireGraphPersonEdit(personId, "edit")` (см. §2.1 layered) |
| `DELETE /v1/trees/:treeId/persons/:personId` | hard-delete legacy → soft-delete graphPerson | `requireTreeAccess` | + `requireGraphPersonEdit(personId, "soft-delete")` |
| `POST /v1/trees/:treeId/persons/:personId/media` | photos | `requireTreeAccess` | + `requireGraphPersonEdit(personId, "edit")` |
| `PATCH /v1/trees/:treeId/persons/:personId/media/:mediaId` | photo metadata | `requireTreeAccess` | + same |
| `DELETE /v1/trees/:treeId/persons/:personId/media/:mediaId` | drop photo | `requireTreeAccess` | + same |
| `PUT /v1/trees/:treeId/persons/:personId/attributes` | personAttributes write | `requireTreeAccess` | + same; sensitive write остаётся owner-only-всегда (§4.2) |
| `POST /v1/trees/:treeId/persons/:personId/profile-contributions` | suggestion (не direct edit) | `requireTreeAccess` | без изменений — это explicit suggestion-flow, не edit |

### 1.2 Mutate relations (двойной edit gate)

| Endpoint | Что | Текущий | Phase 3.2 |
|---|---|---|---|
| `POST /v1/trees/:treeId/relations` | create relation | `requireTreeAccess` | + `requireGraphPersonEdit(person1Id, "edit")` AND `requireGraphPersonEdit(person2Id, "edit")` |
| `DELETE /v1/trees/:treeId/relations/:id` | drop relation | `requireTreeAccess` | + same двойная проверка |

Обоснование: relation описывает родство **между** двумя людьми. Если
ты не можешь editить ни одного из них — не можешь и связь между ними.
Если один — твой self, второй — claimed чужой → нужен `merge-consent`
от чужой стороны (через mergeProposals flow). Это уже есть в коде.

### 1.3 Identity merge / link

| Endpoint | Что | Текущий | Phase 3.2 |
|---|---|---|---|
| `POST /v1/trees/:treeId/persons/:personId/link-identity` | link two persons по identityId | `requireTreeAccess` для source AND target | + `requireGraphPersonEdit(sourcePersonId, "merge-consent")` AND `requireGraphPersonEdit(targetPersonId, "merge-consent")` |
| `POST /v1/identity-claims` | claim that this person = me | `requireTreeAccess` | без изменений — это асимметричный flow, claim создаётся юзером и ждёт review owner'ом |
| `POST /v1/identity-claims/:claimId/review` | accept/reject claim | already enforces `_userCanReviewClaim` через store | расширить: reviewer должен `_userCanEditGraphPerson(scope: "merge-consent")` для целевого графа |
| `POST /v1/merge-proposals/:proposalId/review` | accept merge | already enforces ownership | расширить: reviewer должен иметь `merge-consent` scope над involved graphPersons |

### 1.4 Soft-delete trees / unlink user от слота

| Endpoint | Что | Текущий | Phase 3.2 |
|---|---|---|---|
| `DELETE /v1/trees/:treeId` | leave or delete tree | tree.creatorId check | без изменений — tree-level operation, не graph-level |
| `DELETE /v1/trees/:treeId/persons/:personId/user-link` | owner отвязывает userId от слота | tree.creatorId !== actorId → 403 | без изменений — explicit «owner of TREE может recovery» semantic, не graphPerson |

### 1.5 Read paths (visibility gate)

| Endpoint | Что | Текущий | Phase 3.2 |
|---|---|---|---|
| `GET /v1/trees/:treeId/persons` (list in own tree) | list | `requireTreeAccess` | без изменений — own tree, всё видно |
| `GET /v1/trees/:treeId/persons/:personId` | single read | `requireTreeAccess` | без изменений — own tree |
| `GET /v1/trees/:treeId/persons/:personId/dossier` | merged read | `requireTreeAccess` | + sensitive-attribute filter (§4.2) |
| `GET /v1/persons/search` (cross-tree picker) | search across accessible | accessibleTrees scope | + per-result `_userCanSeeGraphPerson` check |
| `GET /v1/trees/:treeId/persons/:personId/identity-suggestions` | cross-tree suggestions | accessibleTrees scope | + per-suggestion `_userCanSeeGraphPerson` check |
| `GET /v1/identity-discovery/search` | public discovery | already public-only | без изменений |
| `GET /v1/graph/relation?from=&to=` (Phase 4 BFS) | BFS chain | `requireAuth` | + per-chain-node `_userCanSeeGraphPerson` filter (если visibility blocked — return null или filtered chain) |
| `GET /v1/trees/:treeId/persons/:personId/attributes` | read attributes | `requireTreeAccess` | + sensitive filter (§4.2) |

### 1.6 Что НЕ трогаем (out of scope 3.2)

* Все chat / call / story / post / comment / reaction routes — не
  трогают graphPerson напрямую.
* Auth routes — не трогают graphPerson.
* Notification routes — не трогают.
* Tree CRUD (`POST/GET /v1/trees`, `GET /v1/trees/selectable`) —
  это tree-level, не graph-level.
* `audience-presets` — оперирует над persons в tree, gate
  по tree-access.

---

## 2. Implementation: gates

### 2.1 `requireGraphPersonEdit(req, res, treeId, personId, scope)`

Новый helper в `app.js` рядом с `requireTreeAccess`:

```js
async function requireGraphPersonEdit(req, res, treeId, personId, scope = "edit") {
  // Шаг 1: traditional tree-access — пропускаем route только если
  // viewer хотя бы на этом дереве. Без этого мы могли бы дать grant
  // на graphPerson с tree-A и через PATCH /v1/trees/:treeB/... позволить
  // edit'ить, что нелогично по shape API.
  const tree = await requireTreeAccess(req, res, treeId);
  if (!tree) return null;

  // Шаг 2: найти legacy person → graphPerson.
  const legacyPerson = await store.findPerson(treeId, personId);
  if (!legacyPerson) {
    res.status(404).json({message: "Человек не найден"});
    return null;
  }
  const graphPerson = await store.findGraphPersonByLegacy(personId);
  // graphPerson может быть null в edge-case'ах (между migration
  // и первым read'ом). В этом случае fail-open на legacy gate —
  // tree-access уже прошёл.
  if (!graphPerson) return {tree, legacyPerson, graphPerson: null};

  // Шаг 3: backward-compat — anonymous person'ы (graphPerson.userId
  // === null AND createdBy === viewer || tree-creator чьего-нибудь
  // tree) допускаются на edit без grant'а. Это сохраняет
  // существующее «creator может editить родственников в своём
  // дереве» поведение.
  const isAnonymousPerson = !graphPerson.userId;
  const isViewerSomeoneWhoCanEdit = store._userCanEditGraphPerson(
    db, graphPerson, req.auth.user.id, scope,
  );
  // На anonymous: tree-access достаточен (мы прошли requireTreeAccess).
  // На claimed: только owner или active grant per scope.
  if (!isAnonymousPerson && !isViewerSomeoneWhoCanEdit) {
    res.status(403).json({
      message: scope === "soft-delete"
        ? "Только владелец карточки может удалить её"
        : scope === "merge-consent"
          ? "Объединение требует согласия владельца карточки"
          : "Только владелец карточки может её редактировать",
    });
    return null;
  }

  return {tree, legacyPerson, graphPerson};
}
```

#### Backward-compat правило (важно)

Anonymous (graphPerson.userId === null) допускается на edit, если
viewer прошёл tree-access. Это сохраняет существующий UX:
* Артём создал «бабушку» в своём tree → graphPerson.userId=null,
  createdBy=u-artem. Артём может editить (как owner) и член
  tree-a (через member memberIds + tree-access path).
* Стёпа после invite'а claimed свой self-person → graphPerson.userId=u-stepa.
  Артём попытался editить стёпину карточку (legacy PATCH через свой
  tree-a где этот person тоже фигурирует) → reject, потому что
  Стёпа claimed.

Это в точности то, что Артём писал в RFC + недавнем `additive: true`
коммите — claimed users защищены, anonymous shared.

### 2.2 `requireGraphPersonRead(req, res, graphPersonId)` для cross-tree

Cross-tree READ paths (search, identity-suggestions, BFS chain):
не идут через tree-access (это вне их scope) — нужен прямой
visibility gate.

```js
async function requireGraphPersonRead(req, res, graphPersonId) {
  const db = await store._read();
  const graphPerson = (db.graphPersons || []).find(g => g.id === graphPersonId);
  if (!graphPerson) {
    res.status(404).json({message: "Карточка не найдена"});
    return null;
  }
  if (!store._userCanSeeGraphPerson(db, graphPerson, req.auth.user.id)) {
    res.status(403).json({message: "Карточка скрыта приватностью"});
    return null;
  }
  return graphPerson;
}
```

Используется в:
* `/v1/graph/relation` — для каждого node в chain check'аем
  visibility. Если стартовый или целевой блокирован → 403. Если
  intermediate — return null path или скрыть intermediate names
  (см. §4.3).

Для list-paths (search / identity-suggestions) — не throw на каждый
hidden person, а **тихо filter'ить** (не leak info о существовании).

---

## 3. Новые endpoints

### 3.1 `POST /v1/graph-persons/:graphPersonId/grants`

**Body**:
```json
{
  "granteeUserId": "u-other",
  "scope": "edit" | "merge-consent" | "soft-delete"
}
```

**Behavior**:
* Только owner graphPerson'а может выписывать grant'ы.
* Если уже есть active grant с тем же `(graphPersonId, granteeUserId, scope)` —
  возвращаем 200 + existing row (idempotent).
* Если есть **revoked** grant с тем же ключом — создаём **новый**
  row (audit trail сохраняется, не overwrite revoked).
* Возвращает созданный grant + `granteeUserId` profile preview.

**Response**:
```json
{
  "grant": {
    "id": "...",
    "graphPersonId": "...",
    "grantorUserId": "...",
    "granteeUserId": "...",
    "scope": "edit",
    "grantedAt": "2026-05-10T12:00:00Z",
    "revokedAt": null,
    "origin": "owner-grant"
  },
  "grantee": {"id": "...", "displayName": "..."}
}
```

**Errors**:
* 403: `"Только владелец карточки может выписывать права"`.
* 404: `"Карточка не найдена"`.
* 400: invalid scope или missing `granteeUserId`.
* 409: grantee — это сам owner (бессмысленно).

### 3.2 `DELETE /v1/graph-persons/:graphPersonId/grants/:grantId`

**Behavior**:
* Только owner graphPerson'а может revoke. Grantee — НЕ может revoke
  свой grant (это owner-side контроль).
* Sets `revokedAt = now`, не drop row (audit).
* Idempotent: если уже revoked — 200, ничего не делаем.

**Errors**:
* 403: viewer не owner.
* 404: grant не найден или принадлежит другому graphPerson'у.

### 3.3 `GET /v1/graph-persons/:graphPersonId/grants`

**Behavior**:
* Только owner может смотреть все grants (включая revoked, для
  audit).
* Возвращает все grants на этот graphPerson + grantee preview.

### 3.4 `GET /v1/me/edit-grants`

**Behavior**:
* Любой аутентифицированный user видит **свои** active grants.
* Возвращает список с graphPerson preview (имя, фото) — чтобы
  granted-юзер мог понять «куда меня пустили».
* Включает revoked **за последние 30 дней** для transparency,
  потом архивируются.

### 3.5 `PATCH /v1/graph-persons/:graphPersonId/visibility`

**Body**:
```json
{
  "visibility": "owner-only" | "connected-via-blood-graph" | "public"
}
```

**Behavior**:
* Только owner graphPerson'а может ставить — никаких grants, даже
  «edit» scope.
* Sets `visibility` + `visibilityOverride: true` (override blocks
  auto-public для deceased+>100лет).
* Если `visibility` тот же что был — все равно ставим
  `visibilityOverride: true` (signals «owner осознанно подтвердил»).

**Errors**:
* 403: viewer не owner.
* 400: invalid visibility value.

### 3.6 `DELETE /v1/graph-persons/:graphPersonId/visibility-override`

**Behavior**:
* Только owner. Сбрасывает `visibilityOverride: false`.
* После — auto-resolve работает (deceased+>100лет → public).
* Stored `visibility` остаётся как был (для будущей backfill).

---

## 4. Sensitive attributes gate

### 4.1 SENSITIVE_KEYS list

Уже определён в Phase 3.1 как `FileStore._sensitiveAttributeKeys`:
`phone`, `phoneNumber`, `email`, `currentAddress`, `homeAddress`.

### 4.2 На READ — filter

`GET /v1/trees/:treeId/persons/:personId/attributes` и
`GET /v1/trees/:treeId/persons/:personId/dossier`:

```js
// В route handler'е, после listPersonAttributes:
const visibleAttributes = attributes.filter(attr =>
  store._userCanSeeSensitiveAttribute(
    db, graphPerson, req.auth.user.id, attr.key,
  )
);
```

Не-owner viewer не видит phone/email/address. Owner — видит всё.
Это **не зависит от node visibility** — даже если узел `public`,
телефон скрыт.

### 4.3 На WRITE (PUT attributes)

* **Не sensitive key**: edit gate (`requireGraphPersonEdit`).
* **Sensitive key**: только owner. Никаких grants.
* Текущий код уже принимает `attributes` массив — добавить per-key
  check: для sensitive — owner-only.

### 4.4 BFS chain (Phase 4)

`/v1/graph/relation` уже использует `previewGraphPersonsByIds`. Оно
возвращает `name`, `photoUrl`, etc. для всех в chain. Phase 3.2
расширение: для каждого node в chain — `_userCanSeeGraphPerson`.
Если viewer не может — node превращается в:
```json
{"id": "...", "name": "(скрыто)", "photoUrl": null, "birthDate": null, "gender": null, "deathDate": null, "hidden": true}
```

Это сохраняет path-shape (BFS не падает), но не leak'ает info.

---

## 5. Migration concerns / backward-compat

### 5.1 Existing tests (api.test.js, ~263 теста)

* Tests которые делают `PATCH /v1/trees/:treeId/persons/:personId`
  на anonymous person — должны продолжать pass'ить.
* Tests которые делают edit на claimed person как другой юзер
  (не owner, не grant) — **должны теперь fail** с 403. Если такие
  тесты есть — adjust expectations.
* Tests которые делают `PATCH /v1/trees/:treeId/persons/:selfPersonId`
  как owner — продолжают pass'ить.

**Проверю в audit перед commit'ом**: какие именно тесты ломаются —
их adjust'у или (если behavior был исключительно legacy artifact)
заменю на right-shape.

### 5.2 Existing UI

Flutter сейчас даёт юзеру возможность editить ANY person в его
дереве. После 3.2:
* Anonymous persons (большинство) — edit как раньше.
* Claimed persons других юзеров — edit получает 403.

Артём подтвердил «между шагами 2 и 3 — НЕТ user-visible regression:
legacy UI продолжает работать на legacy persons (которые мигрированы
в graphPersons но юзеру это не видно). Юзер не получит broken state.»

Это accurate в том смысле, что **на anonymous persons** UI работает.
Edge case — если Артём редактирует чужую claimed карточку (Стёпа после
invite'а), 403 reach до UI. Это **новое** поведение, не regression от
правильной semantic'и: ровно это Артём исправил `additive: true`
коммитом — Артём не должен трогать стёпино имя.

В Phase 3.4 UI получит lock-icon на claimed persons + кнопку
«Запросить право редактирования» (создаёт grant request). Между 3.2
и 3.4 — у юзера нет UX-handle на это, но и ломаться нечего: ситуации
встречаются у мизерного числа юзеров (Артём это подтвердил в Q3
ответе для visibility).

### 5.3 Performance

Per-row visibility check на cross-tree READ — это BFS до 4 hops
для каждого result. Для search с limit=20 → 20 BFS на 4-hop graph
(~50-200 узлов на средний tree). Профиль:
* Cache `_buildBloodAdjacency` на per-`_read()` — already есть в
  Phase 4 BFS path. Расширить на gates.
* Если понадобится — кешировать `viewerSelfId` пер-request.
* Бенчмарк в тесте — добавить smoke'у на 100-search-results.

---

## 6. Тесты

### 6.1 Новый файл `backend/test/owner-model-enforcement.test.js`

Серия integration тестов через `startTestServer`:

* `PATCH /v1/trees/.../persons/:id`:
  - owner can edit own anonymous person ✓
  - owner can edit own claimed self-person ✓
  - other-user (member of tree) can edit anonymous person ✓
  - other-user **cannot** edit claimed someone else's person → 403
  - other-user with `edit` grant **can** edit claimed person ✓
  - other-user with **revoked** grant **cannot** → 403
  - viewer not in tree at all → 403 from `requireTreeAccess` (existing)

* `DELETE /v1/trees/.../persons/:id` (soft-delete):
  - owner can soft-delete own anonymous person ✓
  - other-user **cannot** without `soft-delete` scope grant → 403

* `POST /v1/trees/.../relations`:
  - both endpoints owner — ОК
  - one anonymous one claimed someone else's → 403 на claimed
    side
  - both claimed — оба должны grant edit → 403 если хотя бы один
    blocked

* `PATCH /v1/graph-persons/:id/visibility`:
  - owner sets visibility="owner-only" → ОК + visibilityOverride=true
  - other user with `edit` grant → 403 (visibility = owner-only-всегда)
  - non-existent graphPerson → 404
  - invalid value → 400

* `POST /v1/graph-persons/:id/grants`:
  - owner grants `edit` to other → 200
  - same again → 200, idempotent (no duplicate row)
  - non-owner tries grant → 403
  - granting yourself → 409 (бессмысленно)
  - invalid scope → 400

* `DELETE /v1/graph-persons/:id/grants/:grantId`:
  - owner revokes → 200, `revokedAt` set
  - grantee tries revoke → 403
  - already-revoked → 200 (idempotent)

* `GET /v1/me/edit-grants`:
  - returns grants where granteeUserId === viewer
  - revoked > 30 days назад — не возвращается
  - возвращает graphPerson preview (name, photoUrl)

* `GET /v1/persons/search`:
  - hidden-by-visibility persons filtered out
  - viewer's own self-person в результатах
  - blood-graph 4-hop persons видимы
  - distant cousin (5+ hops) — отфильтрован

* `GET /v1/graph/relation`:
  - chain с hidden middle node — node anonymized но chain
    сохраняется
  - chain через blocked endpoints → 403

* sensitive attributes:
  - `GET .../attributes` → owner видит phone, non-owner не видит
  - `PUT .../attributes` с phone от non-owner → 403 для phone-key
  - `PUT .../attributes` с не-sensitive key от member → ОК

### 6.2 Update existing tests в api.test.js

Сканирую перед commit'ом — какие тесты делают edit на чужой
claimed person как member и ожидают success. Возможно до 5-10
таких тестов; адаптирую expectation на 403.

### 6.3 Smoke benchmark

* Тест: 100 graphPersons, 50 search results, BFS-gating должен
  выполниться < 500ms. Если медленнее — `_buildBloodAdjacency` не
  кешируется per-request.

---

## 7. Open questions

### Q1. Member-of-tree редактирование anonymous persons — оставить или резать?

Сейчас (legacy): любой `tree.memberIds` юзер может editить anonymous
person в этом tree.

Phase 3.2 backward-compat predлагает оставить как есть. **Альтернатива**:
member может только VIEW, owner may edit. Это строже, но потенциально
breaks существующих use case'ов (multi-creator семейные деревья).

**Я рекомендую**: оставить как сейчас (member может editить
anonymous). `tree.memberIds` — legacy concept, который фaded out в
Phase 5/6. До тех пор — edit allowed на anonymous через member route.

**Спрашиваю**: согласен или строже?

### Q2. Что делать с `POST /v1/trees/:treeId/persons` (create new)?

Создание нового person'а в дереве — текущий guard `requireTreeAccess`.
После 3.2 — keep as-is? Создание не trogает existing graphPerson;
создаётся новый, с createdBy=viewer и userId=null (если не self).
Owner = viewer. Edit'ить может только viewer + grant'ы (которых
ещё нет). Так что create = bootstrap новый узел в графе.

Я **рекомендую** keep as-is. Member tree может создать новый
anonymous person, и он становится owner созданного.

### Q3. `/v1/me/edit-grants` — отдавать revoked или нет?

Согласно proposal'у — отдаём revoked **за 30 дней**, чтобы юзер
видел «у меня было право, недавно отозвали». 30 дней — отражает
30-day soft-delete window. Можно сделать configurable (`?since=...`).

**Спрашиваю**: 30 дней разумно?

### Q4. Что с `tree.memberIds` после Phase 3.2?

Не удаляем. RFC Phase 5/6 удалит. Между Phase 3.2 и Phase 5 —
`memberIds` остаётся как legacy backward-compat для existing
tests/UIs.

### Q5. `merge-consent` scope: outerwise обоснование

Сейчас `linkPersonsByIdentity` (Phase 1.2 voltage-indicator) уже
имеет conflict guard через `claimedByUserId`. Phase 3.2 добавляет
дополнительный gate `requireGraphPersonEdit(scope: "merge-consent")`.

Почему отдельный scope: merge — это **destructive** (collapse two
identities). Юзер может разрешить «edit мои canonical fields» (scope
edit), но НЕ хотеть, чтобы кто-то другой мог merge'ить его в чужой
identity. Раздельные scope'ы дают этот контроль.

**Подтверждаю**: keep как отдельный scope.

---

## 8. Out of scope Phase 3.2

* Flutter UI (Phase 3.4).
* Hard-delete background job (Phase 3.6).
* Расширение identity-matcher.
* Owner transfer когда original creator удалил аккаунт (mentioned
  в RFC Phase 3.2 «owner deleted → transfer to closest blood
  relative» — это complex, отдельный design pass позже).
* Grant TTL / expiration (Phase 3.4 UI может exposed; backend
  пока store-side бессрочные).
* Grant invitation flow (granter sends invite → grantee accepts).
  Сейчас owner просто выписывает grant, grantee видит через
  `/v1/me/edit-grants`. Phase 3.4 может добавить notify + accept.

---

## 9. Risk summary

| Risk | Mitigation |
|---|---|
| Backward-compat regression на legacy creator/member edits | Anonymous person (graphPerson.userId=null) — edit via tree-access. Только claimed gates. Тесты покрывают. |
| Performance hit от per-row visibility check | `_buildBloodAdjacency` cached per-`_read()`. Smoke benchmark. |
| Существующие api.test.js падают на claimed-edit-as-member case | Adjust expectations after audit, document в коммите. |
| Cross-tree READ leak (search returns count даже когда visibility=hidden) | Filter ДО pagination/limit. Total count берём из visible-only. |
| `/v1/graph/relation` chain leak names через intermediate hidden nodes | Anonymize node (`hidden: true`, name="(скрыто)"). Chain shape сохраняется. |
| Sensitive attributes leak через dossier endpoint | Per-attribute filter. |
| Owner-only-всегда semantic для visibility слишком restrict (Стёпа не может попросить unlock) | Phase 3.4 добавит «request visibility unlock» flow, отдельный design. Phase 3.2 — только enforce. |
| Grant abuse (owner grants затем revoke много раз) | Audit-trail в graphPersonEditGrants (revoked rows сохраняются). Если станет проблемой — rate-limit в Phase 3.6. |

---

## 10. Что мне нужно от Артёма перед началом кода

1. **Approve этого proposal'а целиком** или указать на правки.
2. **Ответ на Q1** — member-of-tree edit anonymous persons:
   keep as-is (recommended) или строже?
3. **Ответ на Q3** — `/v1/me/edit-grants` показывает revoked
   за 30 дней — разумно?

После approve:
1. Implement helpers (`requireGraphPersonEdit`,
   `requireGraphPersonRead`, `findGraphPersonByLegacy` в store).
2. Wire gates во все routes из §1.
3. Implement новые endpoints (§3).
4. Sensitive attributes filter (§4).
5. Audit existing api.test.js — adjust expectations.
6. Новый `owner-model-enforcement.test.js` (§6.1).
7. `flutter analyze` (только для уверенности что Dart-код не
   ломается из-за изменений в API responses — должны быть compatible).
8. Diff на показ перед commit.

Никакого кода до approve.
