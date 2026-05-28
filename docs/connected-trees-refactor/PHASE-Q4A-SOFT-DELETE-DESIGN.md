# Phase Q4a — Person soft-delete + 30-day restore design pass

> **Status**: Design proposal. Pure markdown — no code changes этим
> документом. Implementation deferred к explicit Артёма approval после
> doc review.
>
> **Author**: Worker (Ship 25, 2026-05-28). Follows Ship 24 FE3b deep
> link work + closes Q4a deferral from session 2026-05-26 («Q4a
> investigate Phase 3.6 hard-delete state — read before edit»).

## 1. Контекст

Q4 (shipped 2026-05-26, commit `50edd73`) added per-person delete
confirmation dialog с copy «**Это действие нельзя отменить**» —
*честно* отражая backend reality. `deletePerson` (store.js:13035)
is **hard delete** через `db.persons.filter(...)` (line 13052): row
+ relations + tree.memberIds wiped immediately, никакого 30-day
restore window.

User-side expectation (per Q4a deferral comments): people who
accidentally tap «Удалить» want recovery option. Common modern app
pattern: 30-day soft-delete с «Восстановить» action.

Q4a выявил briefing-vs-reality mismatch 2026-05-26 (briefing
predполагал Phase 3.6 soft-deletes legacy persons). Discipline
applied — read-verify ground truth перед edits. Result: defer,
write design doc first. **Этот документ.**

## 2. Current state — read-verify discipline

### 2.1 db.persons consumer inventory

**95 occurrences in backend/src/store.js** (per grep on `db.persons`,
counted via `grep --count`). **1 in backend/src/routes/** (semya-browse-routes.js:219).

Сategorized by purpose:

#### Read paths (selection + filtering)

| Line | Purpose | deletedAt-aware? | Migration impact |
|---|---|---|---|
| store.js:793 | List trees user belongs к | No | Filter `!person.deletedAt` |
| store.js:844 | List trees creator + member | No | Same |
| store.js:904 | findTreesForUser core | No | Same |
| store.js:1436 | `_loadUserById` loop | No | Same |
| store.js:4495 | Find person by id (no tree scope) | No | Same |
| store.js:5598 | findPersonByTreeAndId | No | Same |
| store.js:5831 | Per-person merge candidate loop | No | Same |
| store.js:5864 | Map ids → persons (creator helpers) | No | Same |
| store.js:8725 | Read persons by treeId | No | Same |
| store.js:8887 | Find person callback (graph helper) | No | Same |
| store.js:8932 | listPersons (по treeId) — **main read path** | No | **Critical** filter |
| store.js:9017 | Identity propagation loop | No | Same |
| store.js:9107 | Find person для identity-link | No | Same |
| store.js:9128 | Existing-linked-person check | No | Same |
| store.js:9190 | Find by id для unlink | No | Same |
| store.js:9210 | stillHasPersonInTree check | No | Same |
| store.js:9245 | findByIdentityId | No | Same |
| store.js:9270 | identity person resolution | No | Same |
| store.js:9344 | listPersonsForUser | No | Same |
| store.js:9357 | Find person для media | No | Same |
| store.js:9407 | identity-propagate loop | No | Same |
| store.js:9505 | Pull-person source lookup | No | Same |
| store.js:9590 | bulkImport source person | No | Same |
| store.js:9593 | bulkImport target check | No | Same |
| store.js:9662 | Other-person matching loop | No | Same |
| store.js:9772 | Find target для relation create | No | Same |
| store.js:9792 | Find target для identity merge | No | Same |
| store.js:9858 | findBloodRelation from-person | No | Same |
| store.js:9861 | findBloodRelation candidate | No | Same |
| store.js:9927 | findBloodRelation expanded | No | Same |
| store.js:9930 | findBloodRelation expanded candidate | No | Same |
| store.js:10009 | Steward persons filter | No | Same |
| store.js:10021 | All persons read | No | Same |
| store.js:10138 | Identity sync loop | No | Same |
| store.js:10268 | Find for hide-filter check | No | Same |
| store.js:10296 | Find for hide-filter remove | No | Same |
| store.js:10356 | Find для identity claim resolve | No | Same |
| store.js:10373 | Same | No | Same |
| store.js:10522 | Identity primary person | No | Same |
| store.js:10523 | Identity twin person | No | Same |
| store.js:10561 | linked person check | No | Same |
| store.js:10595 | Source person bulk-import | No | Same |
| store.js:10728 | Map ids → persons (import) | No | Same |
| store.js:10737 | Target person loop | No | Same |
| store.js:10815 | Candidate-person check | No | Same |
| store.js:10908 | Find for media list | No | Same |
| store.js:11045 | linked persons filter | No | Same |
| store.js:11470 | stillOnBranch check | No | Same |
| store.js:11494 | stillReferenced check | No | Same |
| store.js:11515 | legacyPerson lookup (graph helper) | No | Same |
| store.js:11837 | legacyPerson lookup (graph helper) | No | Same |
| store.js:12167 | treePersons filter (graph sync) | No | Same |
| store.js:12368 | Сycle через persons (graph identity sync) | No | Same |
| store.js:12856 | _buildPersonViewFromGraph legacyPerson | No | Same |
| store.js:12929 | _syncGraphFromLegacy snapshot | No | Same |
| store.js:13037 | **deletePerson — target find** | No | **Critical** soft-delete entry point |
| store.js:13060 | Remaining-linked check after delete | Yes (needs to be deletedAt-aware) | New |
| store.js:13113 | undelete? (not currently exists) | — | Needed |
| store.js:13197 | Person media read | No | Same |
| store.js:13279 | Person profile-contributions read | No | Same |
| store.js:13348 | listRelations treePersons | No | Same |
| store.js:13358 | getTreeGraphSnapshot treePersons | No | **Critical** (main read) |
| store.js:13367 | viewer person lookup | No | Same |
| store.js:13433 | person1Exists for relation create | No | Same |
| store.js:13436 | person2Exists for relation create | No | Same |
| store.js:13800 | Identity-suggestions loop | No | Same |
| store.js:13894 | listPersonsForGraph | No | Same |
| store.js:13957 | findPerson related | No | Same |
| store.js:14623 | bulkImport identity check | No | Same |
| store.js:14740 | treePersons import target | No | Same |
| store.js:14994 | persons list (story handler) | No | Same |
| store.js:15366 | Loop через legacy persons | No | Same |
| store.js:15508 | Tree-bind treePersons | No | Same |
| store.js:16347 | Find person for media operation | No | Same |
| store.js:16544 | treePersons (post operations) | No | Same |
| store.js:17564 | linkedPerson find для relation | No | Same |
| store.js:17705 | Find person for tree-routes | No | Same |
| store.js:17993 | Tree-merge: filter persons из prev treeId | No | Same |
| store.js:18041 | Onboarding seed `db.persons.push` | — | Write path |
| store.js:18042 | Same | — | Write path |
| store.js:18063 | Onboarding seed relative push | — | Write path |
| routes/semya-browse-routes.js:219 | Browse-tree person filter | No | **Critical** (anonymous view) |

#### Write paths (push / filter-remove)

| Line | Purpose | Migration impact |
|---|---|---|
| store.js:6150 | Duplicate merge — filter-remove duplicate | Move к deletedPersons (если within tree) либо preserve hard-delete |
| store.js:7235 | Bulk import — filter live persons | Filter `!deletedAt` for "live" |
| store.js:7255 | Bulk import — filter-remove deduped | Same |
| store.js:7632 | Tree creation — push creator person | No change (creation path) |
| store.js:8967 | Tree delete — filter-remove all persons of tree | Hard delete still appropriate (tree itself deleted) |
| store.js:9325 | addPerson | No change |
| store.js:9532 | listAllPersons (debug?) | No change |
| store.js:10650 | linkExistingPersonAsRelative push | No change |
| store.js:10787 | Bulk import push | No change |
| store.js:13052 | **deletePerson filter-remove** | **REPLACE** с soft-delete |
| store.js:13357 (.filter chain) | treePersons for restoration check | New deletedAt-aware filter |

### 2.2 Graph layer (graphPersons) — already soft-delete-capable

Critical finding: `graphPersons` collection **already** supports
`deletedAt` + `hardDeleteScheduledAt` (store.js:11261-11266,
11311-11327). Phase 3.6 hard-delete job (`backend/src/jobs/hard-delete-job.js`)
runs as background sweep — prunes graph entities с `deletedAt +
retentionDays < now`.

The mismatch: **legacy db.persons (mirror layer) gets HARD deleted
immediately**, breaking graph's soft-delete contract при mirror
sync. Phase 3 squash kept legacy mirror для backwards compat with
older clients + identity matcher. Soft-delete must be added either:

- **At legacy mirror layer** (db.persons gets deletedAt field) — `option A`
- **OR** at separate snapshot collection (deletedPersons) — `option B` ← *recommended*

### 2.3 Existing related primitives

* `Phase 3.6 hard-delete job` (already live в проде — 2026-05-19
  activation): sweeps graph entities + branches + relations + identities
  whose `deletedAt + retentionDays < now`. Extension к legacy persons
  surface небольшой если соответствующий schema added.
* `_appendTreeChangeRecord` (store.js:13090): emits `person.deleted`
  event с `details.before: deletedPerson` snapshot. Audit trail
  already present. Restore could leverage этот snapshot пока
  retention window открыт.
* Soft-delete pattern для semя (store.js:8703-8705) — `deletedAt`
  set + memberships hidden. Mature pattern.
* `_syncGraphFromLegacy` (store.js:12921): legacy is source of truth
  для current Phase 3 model. Graph soft-deletes when legacy disappears
  (line 12970-12972).

## 3. Proposed architecture — Path 2 (deletedPersons snapshot
collection)

### 3.1 Why Path 2 (snapshot collection) over Path 1 (deletedAt on
legacy)

**Path 1 (deletedAt field on db.persons)**:
- Pros: Simpler schema change; aligns с graph layer.
- Cons: **Every of 95 read sites needs deletedAt-aware filter** OR
  every read becomes potentially-stale. High audit cost, easy to
  miss site, silent leak risk («deleted» person still visible
  somewhere). Goes against «verify ground truth» discipline that
  saved Q4a once.

**Path 2 (deletedPersons separate collection)**:
- Pros: **db.persons remains live-only** (existing 95 sites
  unchanged). DELETE moves row к `deletedPersons` collection. Reads
  unaffected — accidental leak impossible by construction. Restore
  = move back from deletedPersons. Hard-delete job consumes
  `deletedPersons` table only.
- Cons: Two tables to keep coherent при schema migrations. Snapshot
  shape duplicated (acceptable — JSON storage cheap).

**Decision**: Path 2. Safer surface + minimal risk of leak (95 read
sites не trogan'ся).

### 3.2 Entity schema

```javascript
// New collection: db.deletedPersons
{
  id: "dp-{uuid}",                  // Deletion record id (NOT person.id)
  personId: "person-uuid",          // Original person id (для restore lookup)
  treeId: "tree-uuid",              // Tree person belonged к
  semyaId: "semya-uuid",            // Семя binding (если any) — для permission gate
  snapshot: { ...person },          // Full person record (deep clone)
  relationsSnapshot: [{ ...relation }],  // All relations involving this person
  deletedAt: "2026-05-28T12:34:56.789Z",
  actorUserId: "user-uuid",         // Who tapped «Удалить»
  hardDeleteScheduledAt: "2026-06-27T12:34:56.789Z",  // deletedAt + 30 days
  restoredAt: null,                 // Set on successful restore (NULL → row eligible для restore)
  restoredByUserId: null,
}
```

**Key invariants**:
- `personId` may NOT be unique (e.g., create → delete → recreate same id
  unlikely but possible) — index by `(personId, deletedAt)` для lookups.
- `hardDeleteScheduledAt = deletedAt + retentionDays` (default 30d, configurable
  via `RODNYA_DELETED_PERSONS_RETENTION_DAYS` env var).
- Soft-deleted rows live в `deletedPersons` только. **Original `db.persons`
  row removed entirely**. Restore = move back (with relations).

### 3.3 DELETE endpoint flow

```
DELETE /v1/trees/:treeId/persons/:personId  (existing)
  ↓ requireTreeAccess + edit-perm check
  ↓ store.deletePerson(treeId, personId, actorId)
    ↓ 1. find person + relations (as today)
    ↓ 2. NEW: build deletedPersons row { snapshot, relations,
            deletedAt: now, hardDeleteScheduledAt: now+30d }
    ↓ 3. push к db.deletedPersons
    ↓ 4. filter-remove from db.persons + db.relations (as today)
    ↓ 5. _appendTreeChangeRecord («person.deleted») — preserves
         existing event surface for audit log
    ↓ 6. _reconcilePersonIdentities + graph sync (as today —
         graph layer marks identity as deletedAt по auto-sync)
  Returns: {personId, hardDeleteScheduledAt}  // for «Восстановить within 30d» copy
```

### 3.4 New endpoints

```
GET  /v1/me/deleted-persons              — list caller's soft-deleted persons
GET  /v1/trees/:treeId/deleted-persons   — list tree's soft-deleted (requires edit perm)
POST /v1/me/deleted-persons/:dpId/restore — restore a person (transaction)
DELETE /v1/me/deleted-persons/:dpId      — explicit early hard-delete (skip 30d)
```

**Permission gate**: same actor-or-tree-owner pattern as current
deletePerson. Семя-aware: deleted person tied к семя's tree; only
семя members с edit perm can restore.

**Restore atomicity**: `restoreDeletedPerson(dpId)` must:
1. Find row, check `restoredAt == null` AND `hardDeleteScheduledAt > now`.
2. Move snapshot back к `db.persons`.
3. Move `relationsSnapshot` back к `db.relations`.
4. Set `deletedPersons.restoredAt = now`, `restoredByUserId = actor`.
5. Emit `person.restored` tree-change event.
6. Trigger graph re-sync (legacy person resurrected → graphPerson
   `deletedAt` cleared by existing `_syncGraphFromLegacy`).

### 3.5 Phase 3.6 hard-delete job extension

Existing job (`backend/src/jobs/hard-delete-job.js`) extended:
- Sweep `db.deletedPersons` where `restoredAt == null` AND
  `hardDeleteScheduledAt < now` → physical delete (row gone).
- Audit entry per deletion в existing `state.hardDeleteAudit`.

Min retention 24h hard floor (no «accidentally early purge» if env
flag misconfigured). Configurable via env per existing pattern.

## 4. Migration plan

### 4.1 Schema bootstrap

```javascript
// Add к store.js EMPTY_DB:
deletedPersons: [],

// Add к _read normalization:
deletedPersons: Array.isArray(parsed?.deletedPersons)
  ? parsed.deletedPersons
  : [],
```

Backwards-compat: existing data files без `deletedPersons` field
treated as empty (auto-initialized). Zero migration script needed.

### 4.2 Per-call-site review

Read sites (95 в store.js + 1 в routes) **mostly unchanged** —
db.persons remains live-only by construction. Specific сайтs needing
attention:

1. **store.js:13037 (deletePerson find)**: Original — finds в
   db.persons. With Path 2, deletePerson now ALSO checks if
   person already pending-soft-delete (idempotent — return existing
   record).
2. **store.js:13060 (Remaining-linked check after delete)**: Logic
   unchanged — checks db.persons (live) for remaining row by userId.
3. **store.js:17993 (Tree-merge filter persons from prev treeId)**:
   When merging trees, soft-deleted persons из source tree must
   either also be moved к target's deletedPersons OR hard-purged.
   **Decision question Q5 below**.
4. **routes/semya-browse-routes.js:219**: Anonymous browse view —
   currently filters live persons по treeId. Soft-deleted not
   surfaced. No change needed — Path 2 guarantees.

### 4.3 Implementation phases

| Phase | Scope | Effort |
|---|---|---|
| Backend P1 | Schema + store.softDeletePerson + restore | ~150 LOC |
| Backend P2 | 4 new endpoints + tests | ~200 LOC |
| Backend P3 | Phase 3.6 job extension + tests | ~80 LOC |
| Backend P4 | Bug-hunt — verify each of 95 sites unchanged за DELETE write path | Review |
| Frontend P1 | Service interface + `listDeletedPersons` + `restoreDeletedPerson` | ~80 LOC |
| Frontend P2 | «Удалённые родственники» settings tile + section widget | ~200 LOC |
| Frontend P3 | Q4 confirmation dialog copy update («можно восстановить 30 дней») | ~30 LOC |
| Frontend P4 | Tests | ~250 LOC |
| Tests       | Backend invariants + frontend widget + integration | included above |
| **Total**   | | **~1000 LOC** |

### 4.4 Backwards compat

- **Old Q4 confirmation copy** («Это действие нельзя отменить»)
  becomes inaccurate after Q4a ships. Update к «Удалить — можно
  восстановить в течение 30 дней».
- **Existing tree-change events** (`person.deleted` с `details.before`)
  preserved. New `person.restored` event added.
- **Older clients** что don't know о deletedPersons collection:
  they see DELETE returns success, tree refresh hides person.
  Same UX as before. Restore feature invisible к them — graceful
  degradation.

## 5. Endpoints sketch (full HTTP contracts)

### GET /v1/me/deleted-persons

Auth: requireAuth.

```json
Response 200:
{
  "deletedPersons": [
    {
      "id": "dp-uuid",
      "personId": "person-uuid",
      "treeId": "tree-uuid",
      "semyaId": "semya-uuid",
      "snapshot": {
        "id": "person-uuid",
        "name": "Иван Иванов",
        "gender": "male",
        "birthDate": "1990-05-14",
        ...
      },
      "deletedAt": "2026-05-28T12:34:56.789Z",
      "hardDeleteScheduledAt": "2026-06-27T12:34:56.789Z",
      "actorUserId": "user-uuid",
      "daysRemaining": 28
    }
  ]
}
```

Filtered by accessibility: caller sees deleted persons из trees
where they have edit access либо they were the actor.

### POST /v1/me/deleted-persons/:dpId/restore

Auth: requireAuth + edit-perm check on tree.

```json
Response 200:
{
  "restoredPerson": {
    "id": "person-uuid",
    "treeId": "tree-uuid",
    ...
  },
  "restoredRelations": [
    {"id": "rel-uuid", ...}
  ]
}

Response 404 — DELETED_PERSON_NOT_FOUND либо already restored
Response 410 — HARD_DELETE_ELAPSED (hardDeleteScheduledAt < now)
Response 403 — FORBIDDEN (no edit perm на tree)
```

### DELETE /v1/me/deleted-persons/:dpId

Explicit hard-purge before 30d window. For users who want immediate
GDPR-style erasure.

```json
Response 204 — purged
Response 404 — already gone
Response 403 — FORBIDDEN
```

## 6. Frontend integration

### 6.1 «Удалённые родственники» settings section

Pattern mirrors FE6b «Активные ссылки» либо FE7 «Скрытые от меня»:
- Lives в семя details либо settings (per «Скрытые» pattern decision)
- Lists deleted persons с avatar + name + «Восстановить» button
- Empty state: «Здесь будут появляться удалённые родственники в
  течение 30 дней. После — окончательно удаляются.»
- Per-row «Восстановить» → calls service → snackbar + remove
  row + parent screen refresh

### 6.2 Q4 confirmation copy update

```diff
- «Это действие нельзя отменить.»
+ «Можно восстановить в течение 30 дней через настройки.»
```

Mirror updates в:
- `lib/screens/tree_view_screen.dart` _showDeletePersonConfirmation
- `lib/widgets/safe_delete_confirmation_dialog.dart` defaults (if
  reusable copy там)

### 6.3 Service method additions

```dart
abstract class SemyaCapableFamilyTreeService {
  // ... existing

  Future<List<DeletedPerson>> listDeletedPersons();

  Future<RestoredPersonResult> restoreDeletedPerson({
    required String deletedPersonId,
  });

  Future<void> hardPurgeDeletedPerson({
    required String deletedPersonId,
  });
}
```

Plus new model `DeletedPerson` mirroring backend shape.

## 7. Tests

### 7.1 Backend

* `deletePerson` now creates deletedPersons row + tree-change event
* `restoreDeletedPerson` happy path: row moved back + relations
  restored + idempotent restoredAt
* `restoreDeletedPerson` past 30d window: returns 410
* `restoreDeletedPerson` non-actor non-owner: returns 403
* Phase 3.6 job sweep: deletedPersons.hardDeleteScheduledAt < now
  → row physically gone
* Tree-merge migration: soft-deleted person from source tree
  handling (per Q5 decision)
* Existing 95 read sites: regression suite untouched — Path 2
  guarantees

### 7.2 Frontend

* DeletedPerson model parse round-trip
* listDeletedPersons returns empty list on graceful failure
* restoreDeletedPerson happy path → row gone from local state
* «Удалённые родственники» section widget tests
* Q4 confirmation copy verified (new wording)
* Integration test: delete person → seen в deletedPersons list →
  restore → person back в tree

## 8. Risk assessment

| Risk | Likelihood | Mitigation |
|---|---|---|
| 95 read sites accidentally surface soft-deleted person | **Low** — Path 2 keeps db.persons live-only | Path 2 by construction; integration test verifies |
| Tree-merge orphans deletedPersons | Medium | Q5 decision below; explicit cleanup на merge |
| Privacy concern — deleted persons retain в DB 30d | Low (industry standard) | Document в privacy policy; user can DELETE для immediate purge |
| GraphPersons → legacy person sync confusion | Low | Existing `_syncGraphFromLegacy` already handles graphPerson `deletedAt` based on legacy presence; soft-delete uses different table, не affects graph sync |
| Relations cascade: deleted person's relations also need restore | Medium | Snapshot relations in deletedPersons row; restore inserts them back |
| Identity matcher confusion: deletedPersons row's identityId resurfacing | Medium | Lazy expiry — graph layer's identity claim management still authoritative |

## 9. Implementation phases

Per §4.3 table: 4 backend phases + 4 frontend phases. **Recommended
single backend ship** (P1-P4 combined ~430 LOC) followed by **single
frontend ship** (P1-P4 combined ~560 LOC), bracketing с tests
throughout.

Estimated: ~1000 LOC product + ~250 LOC tests = ~1250 LOC. Ship
breakdown TBD per Артёма cadence preference (single backend +
single frontend, либо more chunks).

## 10. Decision questions для Артёма (pre-implementation)

**Q1 — Path 2 confirmed?**
Snapshot collection (deletedPersons) vs deletedAt field on db.persons.
Recommend Path 2 (safer — preserves 95 live-read sites untouched).

**Q2 — Retention window?**
Spec default 30 days. Configurable via env. Confirm 30d default или
prefer 14d / 60d?

**Q3 — Posts also soft-delete? Comments?**
Q4a scope = persons only. Posts/comments в trees use separate
collections с own delete semantics. Out of scope этого ship либо
extend the pattern к posts тоже? Recommend persons only first;
posts later if user requests.

**Q4 — Семя-bound restriction?**
Should restore require семья membership? Semя may have been deleted
(soft-deleted) в meantime — restore would orphan person. Recommend:
restore allowed only если parent семья (and tree) still exist; UI
shows «Нельзя восстановить — семья удалена» otherwise. Backend
backstop.

**Q5 — Tree merge с soft-deleted persons?**
When two trees merge, soft-deleted persons in source tree behavior:
(a) move к target's deletedPersons (preserving 30d window from
original delete) либо (b) hard-purge during merge. Recommend (a) —
user expectation matches.

**Q6 — Hard-delete job MIN window?**
Currently sweep eligibility ≥ retention threshold. Min 24h floor
hardcoded для safety? Or rely on env config? Recommend 24h hard
floor — defensive against env misconfiguration.

**Q7 — Restore audit trail?**
`person.restored` tree-change event with `details.dpId` + restored
data shape? Or omit для privacy (deleted person should not be
permanently audit-logged once restored)? Recommend log restore
event с minimal details — audit trail consistency с delete event.

**Q8 — Frontend section location?**
«Удалённые родственники» lives в:
- (a) Settings (mirror FE7b «Скрытые родственники» pattern), либо
- (b) Семя details screen, либо
- (c) Both (settings tile → семя picker → details section)
Recommend (a) — settings tile с semя picker if multi (matches FE7b
final wiring).

## 11. Open items (not blockers, но track для review)

- iOS universal links для deep-link-restore («restore link» в email
  notification of «person deleted, you have 30d») — separate ship
  per FE3b precedent.
- Push notification to inviter «X удалил Y» — opt-in; Phase B+1
  scope.
- Restore as «branch reset» — recursive restoration of multi-person
  chains (out of scope; restore is single-person + their relations).

---

**Status post-doc**: Implementation deferred к explicit Артёма
approval после doc review. Decision questions §10 awaited.
