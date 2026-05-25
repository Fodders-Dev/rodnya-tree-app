# Ship 9 — `resolveTreeAudienceUserIds` audience diff analysis

> Pre-implementation safety review. Phase B Week 3 Ship 9 extends
> `dispatchTreeMutation` audience scope к семя members. Этот doc
> proves extension purely ADDITIVE — никто existing recipient не
> silently dropped.

---

## 1. Existing audience inputs (store.js:15264-15322)

`resolveTreeAudienceUserIds(treeId, {excludeUserId})` returns
deduplicated Set of userIds от четырёх sources:

| # | Source | Reference |
|---|---|---|
| 1 | `tree.creatorId` | store.js:15275 |
| 2 | `tree.memberIds[]` либо legacy `tree.members[]` alias | store.js:15278-15286 |
| 3 | `graphPerson.userId` for claimed graphPersons в tree (resolved via `legacyPersonIds → db.persons.treeId` reverse-lookup) | store.js:15294-15311 |
| 4 | `graphPersonEditGrants.granteeUserId` for active grants on tree's graphPersons | store.js:15313-15319 |

All inputs added to single `Set`. `excludeUserId` filtered (typically actor of mutation).

## 2. Call sites — invariants protected

`dispatchTreeMutation({treeId, kind, actorUserId})` invokes
`resolveTreeAudienceUserIds` and dispatches `tree_mutated` notification
к each recipient. 6 call sites:

| File | Line | Mutation context |
|---|---|---|
| tree-routes.js | 32 | helper definition |
| tree-routes.js | 827 | POST /v1/trees/:treeId/persons (person create) |
| tree-routes.js | 925 | PATCH .../persons/:personId (update) |
| tree-routes.js | 1004 | DELETE .../persons/:personId (soft-delete) |
| tree-routes.js | 1355 | POST .../relations (relation create) |
| tree-routes.js | 1387 | DELETE .../relations/:relationId (delete) |
| semya-pull-routes.js | 158 | POST /v1/semya/:targetSemyaId/pull-person (Ship 6) |

Plus this function is used as building block в any future endpoint
dispatching `tree_mutated`.

## 3. Phase B addition: семя members source #5

**Proposed**: add Source 5 — `db.semyaMembers` where
`semyaId === tree.semyaId` AND `!hiddenAt`. Member userIds added к
audience Set.

```javascript
// Ship 9 addition после source #4 grants:
if (tree.semyaId) {
  for (const m of db.semyaMembers || []) {
    if (m.semyaId !== tree.semyaId) continue;
    if (m.hiddenAt) continue;  // removed либо kicked members excluded
    if (!m.userId) continue;
    if (m.userId === normalizedExcluded) continue;
    audience.add(m.userId);
  }
}
```

## 4. Drop-recipient safety analysis

**Claim**: extension never reduces audience size. Strict superset.

Per-source analysis:

| Source | Affected by extension? | Safety guarantee |
|---|---|---|
| #1 `tree.creatorId` | No | Always added (line 15275). Семя ownership distinct concept; creator field preserved. |
| #2 `tree.memberIds[]` | No | Always traversed (line 15283). Семя dual-write (Ship 5) adds семя members к this array, но pre-existing entries не touched. |
| #3 `graphPerson.userId` | No | Always traversed (line 15300). Семя has no interaction с graph layer ownership. |
| #4 `graphPersonEditGrants` | No | Always traversed (line 15313). Grants per-graphPerson, not per-семя. |
| #5 NEW `db.semyaMembers` | Added | Only triggers если `tree.semyaId` set. Unbound trees: skip entirely (empty contribution). Bound trees: Set semantics dedup users already present от sources 1-4. |

**Mathematical guarantee**: `audience_post = audience_pre ∪ семя_members_if_bound`. Union operation never removes. `tree.semyaId === null` → empty contribution → `audience_post === audience_pre`.

## 5. Edge cases verified

### 5a. Tree with creator + members + grants + identity-linked + bound к семя

Pre-Ship-9 audience: creator + members + claimed graphPerson owners + grant holders.
Post-Ship-9: same + active семя members.

Tree.memberIds[] vs семя members: via Ship 5 dual-write, semya member adds к tree.memberIds. So semya member already в audience через #2. Extension adds duplicate (dedup'd by Set) — no-op в practice.

Real benefit: **catches drift case**. If somehow tree.memberIds out-of-sync с semyaMembers (e.g. concurrent operation race, либо manual DB mutation, либо pre-Ship-5 семья), Ship 9 catches missing recipients.

### 5b. Tree unbound (tree.semyaId === null либо undefined)

Extension skip'ит entirely (guarded `if (tree.semyaId)`). Result identical к pre-Ship-9.

Important: undefined/null/empty string все treated как falsy by `if (tree.semyaId)`. Безопасно.

### 5c. Soft-deleted семя (semya.deletedAt set)

Currently `tree.semyaId` stays referenced even после semya soft-delete. Should extension include семя members?

**Decision**: extension reads ALL `semyaMembers` rows where `semyaId === tree.semyaId AND !hiddenAt`. Семя soft-delete (Ship 2 `softDeleteSemya`) ALSO sets `hiddenAt` на все memberships (store.js:1117-1121). Поэтому removed-by-semya-delete memberships excluded автоматически.

If семя.deletedAt set но memberships somehow not hidden (data drift), extension would still include them. Negligible — tree access already broken через requireTreeAccess for soft-deleted семья. Notification к them harmless (UI won't render tree they can't access).

### 5d. Race: семя created/seeded в middle of dispatch

`resolveTreeAudienceUserIds` reads db snapshot once (line 15270 `await this._read()`). Audience computed against single snapshot — internally consistent. Concurrent семя creation либо membership add fires next dispatch с next snapshot.

### 5e. Семя without bound tree (semya.treeId orphaned)

Per ENTITY-DESIGN §3.1 invariant, every семя has exactly one tree.
Reverse: tree.semyaId points back. createSemya (Ship 1) sets both atomically.

Edge: tree deleted while семя still exists. Not currently possible — но если случится, `tree` not found at line 15271 → early return. Extension never reached.

### 5f. Excluded user

`excludeUserId` filter applies к ALL sources uniformly. Extension добавляет та же check.

## 6. Audit log change (Ship 9 optional)

Existing `tree_mutated` notification data: `{treeId, kind, actorUserId}`.
Ship 9 не меняет shape — only audience expansion.

If хотим explicit semya context в notification payload, add `semyaId`:
```
data: {treeId, kind, actorUserId, semyaId?: tree.semyaId || undefined}
```

**Decision**: defer. Frontend Week 5-6 might want semya context, но не requirement для Ship 9 audience extension. Keep payload back-compat.

## 7. Test plan (Phase 2 implementation)

Required test cases:

| Test | Assertion |
|---|---|
| Unbound tree audience unchanged | Pre-Ship-9 + Post-Ship-9 results identical for `tree.semyaId === null` |
| Bound tree adds семя members | `audience.includes(semyaMember.userId)` for active member |
| Bound tree preserves creator | `audience.includes(tree.creatorId)` even если creator не в semyaMembers |
| Bound tree preserves grants | `audience.includes(graphPersonEditGrants.granteeUserId)` even если grantee не в semyaMembers |
| Excluded user filtered | `!audience.includes(excludeUserId)` even if excluded is семя member |
| Soft-deleted семя membership excluded | `hiddenAt` set → not in audience |
| Race tolerance | Audience function returns consistent snapshot |

## 8. Verdict

**SAFE TO IMPLEMENT**. Extension purely ADDITIVE — Set union never reduces. Edge cases all benign (skipped либо deduped). Existing test suite should pass unchanged. New tests verify семя members included for bound trees.

Implementation phase 2: add 8-12 LOC к `resolveTreeAudienceUserIds` after grants loop, before final `return Array.from(audience)`.

## 9. Out-of-scope (deferred к later ships либо frontend)

- Missing `tree_mutated` broadcasts on media/identity-link/conflict-resolve operations (audit §7.3 items 3-5). Each touches different endpoint — separate ships либо Week 4 polish.
- Pre-existing `kinship_check_expired` notification dispatch bug (audit §7.3 item 8). Different notification type, separate fix.
- Notification payload `semyaId` field — frontend Week 5-6 may request.
- Realtime channel scoping (if frontend wants per-семья channel subscriptions) — separate refactor.

**Принято**: Артём + Claude, 2026-05-25.
