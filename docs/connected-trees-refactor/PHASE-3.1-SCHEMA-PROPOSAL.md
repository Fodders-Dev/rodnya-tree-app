# Phase 3.1 — Schema design proposal

> **Статус**: design proposal, ожидает review Артёма.
> **Источник правды**: [tree_model_overhaul_rfc.md](../tree_model_overhaul_rfc.md)
> + [DECISIONS.md](DECISIONS.md) запись 2026-05-10 с ответами A–D.
> **Не лезть в код** до явного approve этого документа.

---

## 0. Контекст и DoD

### Что делаем в Phase 3.1

Расширяем существующий graph layer (`graphPersons` / `graphRelations`
/ `branches` / `branchPersonViews`) **полями и сущностями, которых
в нём пока нет**, чтобы он мог быть source-of-truth когда наступит
Phase 3.4 (flip writes from legacy to graph).

### Что НЕ делаем в Phase 3.1

* **Не** переключаем writes с legacy на graph (это Phase 3.4).
* **Не** удаляем legacy `trees` / `persons` / `relations` (это
  Phase 3.5/3.6 после успешного flip).
* **Не** мигрируем UI на «ветки» (это Phase 3.4 + 6.1, причём
  6.1 уже сделан — `BranchSwitcherChip`).
* **Не** реализуем owner-model UI (Phase 3.2).
* **Не** запускаем data migration в проде (Phase 3.3).

### DoD Phase 3.1

* Все новые поля и коллекции добавлены в `EMPTY_DB` + `normalizeDbState`.
* `migrateTreesToGraphAndBranches` дописана:
  - Per-field highest-completeness picking (B).
  - Запись divergent values в `identityFieldConflicts` (B).
  - Заполнение `lastPropagatedFields` на legacy persons после migration.
* `_syncGraphFromLegacy` + helpers продолжают работать с новыми полями.
* Backward-compat: старые JSONB документы читаются без ошибок.
* Все backend tests зелёные (`migration-utils.test.js`,
  `graph-sync.test.js`, `api.test.js`).
* `flutter analyze` без новых issues.
* Migration script в staging dry-run не показывает data loss.

---

## 1. Текущее состояние graph layer (для контекста)

Что уже есть в коде (по моему Phase 0 audit, см.
[AUDIT.md](AUDIT.md)):

### 1.1 Коллекции в `EMPTY_DB`

* [`graphPersons`](backend/src/store.js:89) — `{id (=identityId),
  legacyPersonIds, userId, name, gender, birthDate, deathDate,
  birthPlace, deathPlace, photoUrl, primaryPhotoUrl, photoGallery,
  maidenName, isAlive, mergedInto, deletedAt, version, isPublic,
  source, contactPrivacy, createdBy, createdAt, updatedAt}`.
* [`graphRelations`](backend/src/store.js:90) —
  `{id, person1Id, person2Id, relation1to2, relation2to1,
  isConfirmed, marriageDate, divorceDate, customRelationLabel*,
  parentSetId, parentSetType, isPrimaryParentSet, unionId,
  unionType, unionStatus, legacyRelationIds, legacyTreeIds,
  version, deletedAt, createdBy, createdAt, updatedAt}`.
* [`branches`](backend/src/store.js:91) —
  `{id (=legacyTreeId), legacyTreeId, ownerId (=tree.creatorId),
  name, description, isPrivate, kind, includeRules: {type:"manual",
  manualPersonIds: []}, memberIds, publicSlug, isCertified,
  certificationNote, deletedAt, createdAt, updatedAt}`.
* [`branchPersonViews`](backend/src/store.js:92) —
  `{id, branchId, personId, label, photoOverride, notes,
  familySummary, bio, visibility, legacyPersonId, createdAt, updatedAt}`.
* [`identityFieldConflicts`](backend/src/store.js:66) — Phase 1.3
  коллекция, переиспользуем для migration conflicts (см. B).

### 1.2 Migration + sync helpers

* [`migrateTreesToGraphAndBranches`](backend/src/migration-utils.js:395)
  — one-shot startup migration, idempotent через
  `migrationStatus.treesToGraph === "complete"`.
* `_syncGraphFromLegacy`, `_syncPersonToGraph`, `_syncTreeToBranch`,
  `_markPersonDeletedInGraph`, `_syncRelationToGraph`,
  `_markRelationDeletedInGraph` — incremental mirror, [store.js:9919+](backend/src/store.js:9919).
* `_findBloodRelationBetween` + `_buildBloodAdjacency` — Phase 4
  BFS, [store.js:10283+](backend/src/store.js:10283), уже работает на
  graph (`/v1/graph/relation`).

### 1.3 Что отсутствует (gaps)

| Gap | Закрывает ответ | Раздел в этом proposal |
|---|---|---|
| `graphPerson.visibility` | A | §2.A |
| `graphPerson.visibilityOverride` | A | §2.A |
| Sensitive fields gate | A | §2.A.3 |
| Per-field highest-completeness migration | B | §2.B |
| Migration → `identityFieldConflicts` | B | §2.B |
| `graphPersonEditGrants` коллекция | C | §2.C |
| `branch.includeRules.maxHops` + non-manual типы | D | §2.D |
| 30-day soft-delete window для `graphPerson.deletedAt` | C | §2.C.4 |
| `_buildBranchVisiblePersonIds` helper | D | §2.D.2 |

---

## 2. Изменения по ответам A–D

### 2.A. Privacy escape hatch (ответ A)

#### 2.A.1. Поля на `graphPerson`

```js
// Дополнения к существующей записи graphPerson:
{
  // ... существующие поля ...

  // Уровень видимости узла. Default — "connected-via-blood-graph"
  // (≤ maxBloodHops от viewer'а, см. §2.A.4). На `null` или
  // отсутствующее значение читать как default — для backward-compat
  // со старыми JSONB документами.
  visibility: "owner-only" | "connected-via-blood-graph" | "public" | null,

  // Owner явно установил visibility — не пересчитывать
  // automatically. Без этого флага мы могли бы при auto-resolve
  // (deceased+>100лет = public) затереть owner-only override.
  visibilityOverride: boolean,
}
```

* **Default (новый узел)**: `visibility: "connected-via-blood-graph"`,
  `visibilityOverride: false`.
* **Auto-derive в read path** (не в store): если
  `isAlive === false && birthYear < (now.year - 100) && !visibilityOverride`,
  effective visibility = `"public"`. Это **derived**, а не stored —
  старение само переключает узлы без backfill job.
* **Owner override**: при PATCH через UI ставится `visibility: "owner-only"`
  + `visibilityOverride: true`. После — никакой auto-public для этого узла.

#### 2.A.2. Visibility check helper (новый)

```js
// store.js — новый метод. Возвращает true когда viewer может видеть
// graphPerson. Heart-of-privacy: используется во всех cross-tree
// read paths (search, identity-suggestions, /v1/graph/relation,
// /v1/me/extended-family когда наступит Phase 4).
_userCanSeeGraphPerson(db, graphPerson, viewerUserId) {
  if (!graphPerson || graphPerson.deletedAt) return false;

  const visibility = this._effectiveVisibility(graphPerson);

  if (visibility === "public") return true;

  if (visibility === "owner-only") {
    return graphPerson.userId === viewerUserId
        || graphPerson.createdBy === viewerUserId;
  }

  // connected-via-blood-graph (default).
  // Viewer видит graphPerson если есть blood-path ≤ maxBloodHops
  // (§2.A.4) от self-graphPerson(viewer) до graphPerson.
  const viewerSelfId = this._selfGraphPersonIdForUser(db, viewerUserId);
  if (!viewerSelfId) return false;
  if (viewerSelfId === graphPerson.id) return true;

  const path = this._findBloodRelationBetween(
    db, viewerSelfId, graphPerson.id, {maxDepth: SENSITIVITY_MAX_HOPS},
  );
  return path !== null;
}

_effectiveVisibility(graphPerson) {
  if (graphPerson.visibilityOverride) {
    return graphPerson.visibility || "owner-only";
  }
  // Auto-public для исторических узлов.
  const birthYear = parseBirthYear(graphPerson.birthDate);
  if (graphPerson.isAlive === false && birthYear) {
    const yearsAgo = (new Date()).getFullYear() - birthYear;
    if (yearsAgo > 100) return "public";
  }
  return graphPerson.visibility || "connected-via-blood-graph";
}
```

`SENSITIVITY_MAX_HOPS` = 4 (per ответ A — «≤4 hops по кровным рёбрам»).

#### 2.A.3. Sensitive fields gate

Sensitive fields сейчас живут в `personAttributes` коллекции (а не на
самом `person` или `graphPerson`). Это удобно — gate можно поднять
только при чтении этих attributes:

```js
// Phase 3.1 расширение: при чтении listPersonAttributes / dossier,
// фильтровать sensitive fields через дополнительный gate.
const SENSITIVE_ATTRIBUTE_KEYS = new Set([
  "phone",
  "phoneNumber",
  "email",
  "currentAddress",
  "homeAddress",
  // (расширяемо — добавить позже telegram-handle, паспорт, etc.)
]);

// _userCanSeeSensitiveField(db, graphPerson, viewerUserId, key):
//   - key not in SENSITIVE_ATTRIBUTE_KEYS → return true
//   - viewer is owner of this graphPerson (userId или createdBy) → true
//   - otherwise → false
// Independently of node.visibility — даже public-ноды не показывают
// телефон-домашний.
```

* Поле `graphPerson.contactPrivacy = "owner-only"` уже есть в коде
  как константа default. В Phase 3.1 это превращается в **enforcement**
  через эти gates.

#### 2.A.4. Где enforced

| Read path | Phase 3.1 действие |
|---|---|
| `GET /v1/trees/:treeId/persons` (legacy) | Без изменений — это per-tree, не cross-graph. |
| `GET /v1/persons/search` (cross-tree picker) | Добавить gate `_userCanSeeGraphPerson`. |
| `GET /v1/trees/:treeId/persons/:id/identity-suggestions` (Phase 1.2 💡) | Уже scoped к accessibleTrees; добавить дополнительный fallback gate (на случай Phase 4 расширения). |
| `GET /v1/graph/relation` (Phase 4 BFS) | Add gate per-chain-node. |
| `GET /v1/me/extended-family` (Phase 4 future) | Полностью построен на gate. |

---

### 2.B. Migration conflict strategy (ответ B)

#### 2.B.1. `pickCanonicalPerson` — переписывается на per-field

Текущий [migration-utils.js:307](backend/src/migration-utils.js:307)
выбирает **одного** canonical-person'а целиком:
1. Тот, у кого `userId === identity.userId`.
2. Иначе — самый недавний по `updatedAt`.

**Меняется на per-field selection**:

```js
// migration-utils.js — новая функция, заменяет pickCanonicalPerson.
function pickCanonicalFieldsAndCollectConflicts(
  linkedPersons,
  identity,
  identityId,
  {now, idFactory},
) {
  const canonical = {};
  const conflicts = [];

  // Для каждого canonical-поля выбираем source с наибольшим
  // completeness (non-null > null; для строк — длиннее > короче;
  // для photoGallery — больше элементов > меньше). Все divergent
  // values записываем в conflicts.
  for (const field of GRAPH_PERSON_CANONICAL_FIELDS) {
    const candidates = linkedPersons
      .map((p) => ({person: p, value: p[field]}))
      .filter((c) => isNonEmpty(c.value));

    if (candidates.length === 0) {
      canonical[field] = null;
      continue;
    }

    // Sort by completeness score (descending), stable.
    candidates.sort((a, b) => completenessScore(b.value) - completenessScore(a.value));
    const winner = candidates[0];
    canonical[field] = winner.value;

    // Все остальные кандидаты с НЕ-equal value → conflict rows.
    for (const loser of candidates.slice(1)) {
      if (valuesEqualForPropagation(field, winner.value, loser.value)) continue;
      conflicts.push({
        id: idFactory(),
        identityId,
        sourcePersonId: winner.person.id,
        sourceTreeId: winner.person.treeId,
        targetPersonId: loser.person.id,
        targetTreeId: loser.person.treeId,
        field,
        sourceValue: structuredClone(winner.value),
        targetValue: structuredClone(loser.value),
        createdAt: now(),
        updatedAt: now(),
        resolvedAt: null,
        resolvedBy: null,
        // Маркер что conflict родился из migration, а не runtime
        // propagation. Для observability и possible future filter UI.
        origin: "migration",
      });
    }
  }

  return {canonical, conflicts};
}

function completenessScore(value) {
  if (value == null) return 0;
  if (typeof value === "string") return value.trim().length;
  if (Array.isArray(value)) return value.length;
  return 1; // boolean / number / object — non-null beats null.
}

function isNonEmpty(value) {
  if (value == null) return false;
  if (typeof value === "string") return value.trim() !== "";
  if (Array.isArray(value)) return value.length > 0;
  return true;
}
```

#### 2.B.2. `migrateTreesToGraphAndBranches` обновляется

```js
function migrateTreesToGraphAndBranches(snapshot, options) {
  // ... как сейчас до 1. PersonIdentity → graphPerson ...

  // ── 1. PersonIdentity → graphPerson with per-field selection ──
  for (const identity of personIdentities) {
    const linkedPersons = persons.filter(/* ... */);
    if (linkedPersons.length === 0) continue;

    // НОВОЕ: вместо pickCanonicalPerson —
    // pickCanonicalFieldsAndCollectConflicts.
    const {canonical, conflicts} = pickCanonicalFieldsAndCollectConflicts(
      linkedPersons,
      identity,
      identity.id,
      options,
    );

    // НОВОЕ: записать conflicts в коллекцию.
    if (Array.isArray(target.identityFieldConflicts)) {
      target.identityFieldConflicts.push(...conflicts);
    } else {
      target.identityFieldConflicts = conflicts;
    }

    // НОВОЕ: ставим lastPropagatedFields на каждом legacy person —
    // чтобы Phase 1.1 propagation не fired при первом edit'е после
    // migration. Сохраняем canonical в snapshot per-person.
    for (const person of linkedPersons) {
      if (!person.lastPropagatedFields) person.lastPropagatedFields = {};
      for (const field of GRAPH_PERSON_CANONICAL_FIELDS) {
        person.lastPropagatedFields[field] = structuredClone(canonical[field]);
      }
    }

    // НОВОЕ: дополнительные defaults для visibility (§2.A).
    const graphPerson = buildGraphPersonFromCanonicalFields(
      canonical, identity.id, linkedPersons, timestamp,
    );
    graphPerson.visibility = "connected-via-blood-graph";
    graphPerson.visibilityOverride = false;

    graphPersons.push(graphPerson);
    /* ... ID mapping ... */
  }

  // ... остальное как сейчас ...
}
```

#### 2.B.3. Что с persons без identity

Текущий код (line 453) делает 1:1 graphPerson из person без identity.
Они не нуждаются в conflict resolution (нет divergent sources). Не
меняется.

#### 2.B.4. Идемпотентность сохраняется

Migration уже идемпотентна через `migrationStatus.treesToGraph === "complete"`.
Не меняется. Если миграция запущена повторно (после wipe ledger) —
conflicts пересоздаются. Это OK.

---

### 2.C. Owner-model thresholds (ответ C)

#### 2.C.1. Default owner

```js
// Helper: кто owner данного graphPerson?
graphPersonOwnerUserId(graphPerson) {
  // Если узел представляет user-аккаунт (через userId), это он.
  if (graphPerson.userId) return graphPerson.userId;
  // Иначе — кто его создал в графе (deceased ancestor, etc.).
  return graphPerson.createdBy || null;
}
```

#### 2.C.2. Новая коллекция `graphPersonEditGrants`

```js
// EMPTY_DB:
graphPersonEditGrants: [],

// Запись:
{
  id: <uuid>,
  graphPersonId: <identityId>,
  grantorUserId: <ownerWhoGranted>,
  granteeUserId: <whoCanEdit>,
  scope: "edit" | "merge-consent" | "soft-delete",
  grantedAt: <iso>,
  revokedAt: <iso | null>,
  // Origin: "owner-grant" | "system" (на будущее, если когда-то
  // вернёмся к auto-extension).
  origin: "owner-grant",
}
```

* `scope: "edit"` — может PATCH canonical поля.
* `scope: "merge-consent"` — может одобрить merge proposal на этот узел.
* `scope: "soft-delete"` — может soft-delete (с 30-day window).

#### 2.C.3. Edit gate

```js
_userCanEditGraphPerson(db, graphPerson, viewerUserId, scope = "edit") {
  if (!graphPerson || graphPerson.deletedAt) return false;
  const owner = graphPersonOwnerUserId(graphPerson);
  if (owner === viewerUserId) return true;

  const grants = (db.graphPersonEditGrants || [])
    .filter(g =>
      g.graphPersonId === graphPerson.id
      && g.granteeUserId === viewerUserId
      && g.scope === scope
      && !g.revokedAt
    );
  return grants.length > 0;
}
```

#### 2.C.4. 30-day soft-delete window

Текущее `graphPerson.deletedAt` есть, но nothing про expiration.

```js
// Дополнительные поля на graphPerson:
{
  deletedAt: <iso | null>,
  // Когда expires soft-delete и узел переходит в hard-delete.
  // Заполняется при soft-delete: deletedAt + 30 days.
  // Hard-delete = drop row из db.graphPersons. Hold off на это
  // до Phase 3.6 (undo/rollback) — там будет background job.
  hardDeleteScheduledAt: <iso | null>,
  // Кто инициировал soft-delete.
  deletedByUserId: <userId | null>,
}
```

* В Phase 3.1 hard-delete не реализуется. Просто схема готова.
* Background job для hard-delete планируется в Phase 3.6.

#### 2.C.5. Merge через mergeProposals

`mergeProposals` уже двусторонний механизм (claimedByUserId с обеих
сторон). В Phase 3.1 не меняется. В Phase 3.2 в UI добавится
кнопка «Запросить merge», которая создаёт mergeProposal.

---

### 2.D. BFS depth для blood-branch (ответ D)

#### 2.D.1. Расширение `branch.includeRules`

```js
// Сейчас (миграция в migrateTreesToGraphAndBranches:
// `includeRules: {type: "manual", manualPersonIds: [...]}`)
//
// Phase 3.1:
includeRules: {
  type: "manual" | "blood-from-me" | "descendants-of" | "ancestors-of",

  // Для type === "manual"
  manualPersonIds: [<graphPersonId>],

  // Для type === "blood-from-me" / "descendants-of" / "ancestors-of"
  anchorPersonId: <graphPersonId | null>,  // null = self для blood-from-me
  maxHops: 5,  // default per D; UI slider 3..8
}
```

* **Backward-compat**: существующие migrated branches остаются с
  `type: "manual"` и `manualPersonIds: [...]`. Не трогаем.
* **Новые branches** через UI wizard (Phase 6.4) создаются с
  выбранным type.

#### 2.D.2. `_buildBranchVisiblePersonIds` helper

```js
// store.js — новый метод. Используется feed / tree-view / etc.
// для вычисления актуального set'а graphPerson IDs внутри branch.
_buildBranchVisiblePersonIds(db, branch, viewerUserId) {
  const rules = branch.includeRules || {type: "manual", manualPersonIds: []};

  switch (rules.type) {
    case "manual":
      return new Set(rules.manualPersonIds || []);

    case "blood-from-me": {
      const selfId = this._selfGraphPersonIdForUser(db, viewerUserId);
      if (!selfId) return new Set();
      return this._collectBloodPersonsWithinHops(
        db, selfId, rules.maxHops || 5,
      );
    }

    case "descendants-of": {
      const anchor = rules.anchorPersonId;
      if (!anchor) return new Set();
      return this._collectDescendantsWithinHops(
        db, anchor, rules.maxHops || 5,
      );
    }

    case "ancestors-of": {
      const anchor = rules.anchorPersonId;
      if (!anchor) return new Set();
      return this._collectAncestorsWithinHops(
        db, anchor, rules.maxHops || 5,
      );
    }

    default:
      return new Set();
  }
}
```

* `_collectBloodPersonsWithinHops`, `_collectDescendantsWithinHops`,
  `_collectAncestorsWithinHops` — реализуются через тот же
  `_buildBloodAdjacency` (line 10350), что использует
  `_findBloodRelationBetween`. BFS с маркировкой direction (parent vs.
  child edges).
* В Phase 3.1 — только helpers. UI для не-manual типов в Phase 6.4.

---

## 3. Финальная схема (после Phase 3.1)

Полная схема каждой коллекции, которая трогается. **Жирным** —
новые поля Phase 3.1; *italic* — defaults для backward-compat.

### 3.1. `graphPersons`

```js
{
  id,                         // === identityId
  legacyPersonIds: [...],
  userId,                     // или null для deceased ancestors
  createdBy,
  createdAt,
  updatedAt,
  version,
  mergedInto,                 // для merge proposals
  deletedAt,
  hardDeleteScheduledAt,      // **новое (C.4)**
  deletedByUserId,            // **новое (C.4)**
  // Canonical поля (RFC), уже есть:
  name, gender, birthDate, deathDate, isAlive,
  birthPlace, deathPlace, photoUrl, primaryPhotoUrl, photoGallery,
  maidenName,
  // Privacy:
  visibility,                 // **новое (A.1)**, default "connected-via-blood-graph"
  visibilityOverride,         // **новое (A.1)**, default false
  isPublic,                   // legacy, оставляем для совместимости — derived из visibility==="public"
  source,                     // "manual" | "wikidata" | "user-claim" (Phase 5)
  contactPrivacy,             // legacy, эффективно "owner-only" всегда — gate переключается на per-field
}
```

### 3.2. `graphRelations`

Без изменений в Phase 3.1.

### 3.3. `branches`

```js
{
  id,                         // === legacyTreeId
  legacyTreeId,
  ownerId,                    // === legacy tree.creatorId
  name,
  description,
  isPrivate,
  kind,                       // "family" | "friends"
  includeRules: {             // **расширено (D.1)**
    type: "manual" | "blood-from-me" | "descendants-of" | "ancestors-of",
    manualPersonIds: [...],
    anchorPersonId,           // **новое (D.1)**
    maxHops,                  // **новое (D.1)**, default 5
  },
  memberIds: [...],           // зеркалится из tree.memberIds (Phase 5 удалит)
  publicSlug,
  isCertified,
  certificationNote,
  deletedAt,
  createdAt,
  updatedAt,
}
```

### 3.4. `branchPersonViews`

Без изменений в Phase 3.1.

### 3.5. `graphPersonEditGrants` (новая коллекция, C.2)

```js
{
  id,
  graphPersonId,
  grantorUserId,
  granteeUserId,
  scope: "edit" | "merge-consent" | "soft-delete",
  grantedAt,
  revokedAt,
  origin: "owner-grant",
}
```

### 3.6. `identityFieldConflicts` (Phase 1.3, переиспользуется)

Без изменений в схеме. Migration просто **дописывает** rows с
`origin: "migration"` (новое опциональное поле — для observability).

---

## 4. Migration plan

### 4.1. Что меняет `migrateTreesToGraphAndBranches`

Сегодня (упрощённо):
```
1. personIdentities → graphPersons (один на identity, pickCanonicalPerson)
2. persons без identity → 1:1 graphPerson
3. trees → branches с includeRules.type=manual + manualPersonIds=all-persons-of-tree
4. relations → graphRelations (dedup)
5. branchPersonViews из per-(tree, person) editorial
6. posts.branchIds[] = [legacyTreeId]
7. status.treesToGraph = "complete"
```

После Phase 3.1:
```
1. personIdentities → graphPersons:
   - pickCanonicalFieldsAndCollectConflicts (B.1) — per-field winner
   - identityFieldConflicts получает rows для divergent values (B.2)
   - lastPropagatedFields ставится на каждом legacy person (B.2.4)
   - graphPerson.visibility = "connected-via-blood-graph", visibilityOverride = false (A.1)
2. persons без identity → 1:1 graphPerson + те же visibility defaults
3. trees → branches:
   - includeRules.type = "manual" (как сейчас)
   - includeRules.maxHops = null (для type=manual не используется)
   - includeRules.anchorPersonId = null
4. relations → graphRelations (без изменений)
5. branchPersonViews (без изменений)
6. posts.branchIds[] = [legacyTreeId] (без изменений)
7. status.treesToGraph = "complete-v2" (новый ledger key — для отличия от старой миграции при testing)
```

### 4.2. Идемпотентность

Если `status.treesToGraph === "complete-v2"` → no-op.
Если `status.treesToGraph === "complete"` (старая миграция) →
**re-run** с новым algorithm:
1. Wipe `graphPersons`, `graphRelations`, `branches`, `branchPersonViews`,
   `graphPersonEditGrants`.
2. Wipe `identityFieldConflicts` rows с `origin === "migration"` (Phase 1.3
   runtime conflicts остаются).
3. Re-run.
4. Set status to "complete-v2".

### 4.3. Rollback план

Перед запуском migration в проде:
1. **Backup snapshot** (full JSONB документ + media).
2. Dry-run в staging на копии prod-данных.
3. Сравнить count'ы: persons → graphPersons (с identity-merging),
   relations → graphRelations (с dedup), trees → branches (1:1).
4. Если drift — abort.

Rollback:
1. Restore backup snapshot.
2. Drop status.treesToGraph (без status миграция не идёт).

---

## 5. Backward-compat plan

### 5.1. Существующие routes

Routes, которые сейчас читают legacy `trees` / `persons` / `relations` —
**не меняются** в Phase 3.1. Они продолжают работать через legacy.
Переключение на graph — Phase 3.4.

### 5.2. Старые JSONB документы

`normalizeDbState` уже устойчив к отсутствующим коллекциям. После
Phase 3.1 он:
* Добавит defaults для новых полей `graphPerson.visibility`,
  `visibilityOverride`, `hardDeleteScheduledAt`, `deletedByUserId`.
* Создаст пустой `graphPersonEditGrants: []`.

### 5.3. Старые сlients

Flutter client пока не использует graph layer (кроме Phase 4 BFS
endpoint). Не ломаем.

### 5.4. Old `graphPerson.isPublic`, `contactPrivacy`

Сохраняем как deprecated read-only поля. После Phase 3.1:
* `isPublic` derived из `visibility === "public"` (effective).
* `contactPrivacy` ignored — sensitive fields gate работает
  независимо.

---

## 6. Тесты, которые нужно обновить/добавить

### 6.1. `migration-utils.test.js`

* **Update**: «collapses identity-linked persons» — теперь
  pick-per-field, не canonical-record. Adjust expected
  graphPerson values.
* **New**: «migration writes identityFieldConflicts for divergent
  values» — два linked persons с разными `birthDate`, конфликт
  записан, `origin: "migration"`.
* **New**: «migration sets lastPropagatedFields on legacy persons».
* **New**: «migration applies default visibility and override=false».
* **New**: «migration is re-runnable from complete → complete-v2».

### 6.2. `graph-sync.test.js`

* **Update**: проверки sync должны учитывать новые поля
  visibility / hardDeleteScheduledAt и т.д.
* **New**: «soft-delete sets deletedAt + hardDeleteScheduledAt».
* **New**: `_userCanSeeGraphPerson` smoke-tests (owner, public,
  blood ≤ 4 hops).
* **New**: `_userCanEditGraphPerson` с editGrants.

### 6.3. `api.test.js`

* **New**: «cross-tree person picker honors graphPerson visibility».
* **New**: «sensitive fields hidden from non-owner viewers».
* **New** (если уже не покрыто): «merge proposal требует
  двустороннего consent».

### 6.4. New: `branch-include-rules.test.js`

* `_buildBranchVisiblePersonIds` для каждого `type`:
  - manual → возвращает manualPersonIds
  - blood-from-me → BFS до maxHops
  - descendants-of → only descendants
  - ancestors-of → only ancestors

---

## 7. Open questions (минимизирую — большая часть закрыта A–D)

### Q1. Что делать со старым `migrationStatus.treesToGraph === "complete"` на prod-данных при cutover?

**Предложение**: re-run автоматически (см. §4.2 «Идемпотентность»).
Это значит, что юзеры с уже-ранним graph (для тех, кто на dev/staging
запустил v1) увидят свои graphPersons пересобранными.

* Risk: между "complete" → "complete-v2" пересборки исчезают
  custom-set данные на graphPerson (любые runtime PATCH'ы которые
  не отражены в legacy person'ах). На текущий момент graph — pure
  shadow от legacy, runtime PATCH'ей напрямую на graphPerson нет.
  Так что safe.

* Альтернатива: написать отдельный «migrate v1 → v2» step
  без full re-run. Сложнее, но safer для будущего.

**Спрашиваю**: re-run или incremental v1→v2 patch?

### Q2. Нужен ли немедленный backfill для существующих юзеров с legacy `tree.creatorId`?

`branch.ownerId` уже зеркалится через `_syncTreeToBranch`. Изменений
не требуется. ОК как есть.

### Q3. UI для visibility override (Phase 3.1 vs. Phase 3.4)?

Поле `visibility` появляется в Phase 3.1 (schema). UI для override
— Phase 3.4. Это значит **между фазами** все узлы на default
`connected-via-blood-graph`, override недоступен. ОК?

**Предложение**: ОК. Дефолт безопасен (≤4 hops видят узел), для
override юзер может попросить feature в Phase 3.4.

---

## 8. Вне scope Phase 3.1

* UI для branch creation wizard (Phase 6.4).
* UI для visibility override (Phase 3.4).
* UI для editGrants (Phase 3.2 owner-model UI).
* Background job для hard-delete после 30-day window (Phase 3.6).
* Flip writes из legacy в graph (Phase 3.4).
* Удаление legacy `trees` / `persons` (Phase 3.5/3.6).
* Phase 4 «Найти родство» UI (отдельная фаза).
* Phase 5 публичные исторические узлы (отдельная фаза).
* Расширение identity-matcher (Артём явно сказал «не приоритет»).

---

## 9. Risk summary

| Risk | Mitigation |
|---|---|
| Migration перетирает custom runtime данные на graph | На текущий момент graph — pure shadow; runtime PATCH'ей нет. После Phase 3.4 — другая история; до тех пор re-run safe. |
| `_userCanSeeGraphPerson` slow на больших графах (BFS на каждый read) | Кешировать blood-adjacency per `_read()`. BFS с maxDepth=4 на 1000 graphPersons ≤ 10ms. |
| Backwards-compat поломка для старых JSONB на prod | `normalizeDbState` имеет defaults для всех новых полей. Старые документы load'аются. Тестирую в staging. |
| Identity-field conflicts из migration пугают юзеров (массовый ⚠️ badge) | Ответ B и есть — это feature, не bug. UI Phase 1.3 уже есть. |
| Privacy gate ломает существующий cross-tree picker | accessibleTrees scope сохраняется как первый guard. Visibility — дополнительный, не replacement. Тест покрывает. |

---

## 10. Что мне нужно от Артёма перед началом кода

1. **Approve этого proposal'а целиком** или указать на правки.
2. **Ответ на Q1** (§7) — re-run миграции v1→v2 целиком, или
   incremental patch?
3. **Ответ на Q3** (§7) — приемлемо ли что override недоступен
   между Phase 3.1 и 3.4?

После approve:
1. Сделать changes в backend (EMPTY_DB, normalizeDbState,
   migration-utils, store.js syncs, helpers).
2. Расширить тесты (§6).
3. Запустить полный backend suite + dry-run миграции на
   синтетических данных.
4. Показать diff + tests перед commit.
5. Коммит на ветке, не push в main.

Никакого кода до approve.
