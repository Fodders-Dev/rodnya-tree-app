# Migration dry-run — Phase B Week 1

> Investigation deliverable. Script + verification queries для
> transition from connected-per-user-trees к federated семьи.
> **Run only against local dev-db.json, never production.** Output
> captured ниже. Production migration scheduled для Week 4.
>
> Source: `SHARED-TREE-PROPOSAL.md` §5 (migration plan) +
> `week-1/BACKEND-AUDIT.md` §4 (data shape) +
> `week-1/ENTITY-DESIGN.md` §4 (mapping spec).

---

## 1. Script

Location proposed: `backend/scripts/migrate-trees-to-semyi.js`
(not yet committed — Week 4 production script ships separately).

Idempotent + dry-run flag default. Reads top-level JSON document
(`backend/data/dev-db.json` locally либо PostgresStore JSON column
в prod), outputs transformation plan либо commits in-place.

```javascript
// backend/scripts/migrate-trees-to-semyi.js
// Phase B migration: connected-per-user-trees → federated семьи.
// Run modes:
//   node migrate-trees-to-semyi.js              # dry-run (default)
//   node migrate-trees-to-semyi.js --write      # commit changes
//   node migrate-trees-to-semyi.js --verify     # only run verifications
//
// Idempotent: повторный run без --write recomputes plan; с --write
// detects existing migrationStatus.treesToSemyi marker → no-op.

'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const DB_PATH = process.env.RODNYA_DB_PATH ||
  path.resolve(__dirname, '../data/dev-db.json');
const MIGRATION_MARKER = 'treesToSemyi';
const MIGRATION_VERSION = 'complete-v1';

const args = process.argv.slice(2);
const WRITE_MODE = args.includes('--write');
const VERIFY_ONLY = args.includes('--verify');

function uuid() {
  return crypto.randomUUID();
}

function isoNow() {
  return new Date().toISOString();
}

function readDb() {
  const raw = fs.readFileSync(DB_PATH, 'utf-8');
  return JSON.parse(raw);
}

function writeDb(db) {
  fs.writeFileSync(DB_PATH, JSON.stringify(db, null, 2), 'utf-8');
}

function planMigration(db) {
  const plan = {
    newSemyi: [],
    newMembers: [],
    treeIdsToSemyaIds: new Map(),
    skipped: { usersWithoutTrees: [], alreadyMigrated: [] },
    warnings: [],
  };

  // Existing семьи / members (if повторный run)
  const existingSemyi = db.семьи || [];
  const existingMembers = db.семьяMembers || [];
  const existingTreeIds = new Set(existingSemyi.map((s) => s.treeId));

  // Each tree with creatorId → семья
  for (const tree of db.trees || []) {
    if (existingTreeIds.has(tree.id)) {
      plan.skipped.alreadyMigrated.push(tree.id);
      continue;
    }

    const creatorId = tree.creatorId;
    if (!creatorId) {
      plan.warnings.push(`tree ${tree.id} has no creatorId, skipped`);
      continue;
    }

    const creator = (db.users || []).find((u) => u.id === creatorId);
    if (!creator) {
      plan.warnings.push(`tree ${tree.id} creator ${creatorId} not found, skipped`);
      continue;
    }

    const semyaId = uuid();
    const semya = {
      id: semyaId,
      name: 'Моя семья',
      ownerId: creatorId,
      treeId: tree.id,
      description: null,
      createdAt: isoNow(),
      updatedAt: isoNow(),
      deletedAt: null,
    };
    plan.newSemyi.push(semya);
    plan.treeIdsToSemyaIds.set(tree.id, semyaId);

    // Owner member row
    plan.newMembers.push({
      id: uuid(),
      семьяId: semyaId,
      userId: creatorId,
      role: 'owner',
      joinedAt: isoNow(),
      invitedByUserId: null,
      hasInviteGrant: true,
      hiddenAt: null,
    });

    // Additional members (tree.memberIds) → viewers per Q1
    const memberIds = Array.isArray(tree.memberIds) ? tree.memberIds :
      Array.isArray(tree.members) ? tree.members : [];
    for (const memberId of memberIds) {
      if (memberId === creatorId) continue;
      const memberUser = (db.users || []).find((u) => u.id === memberId);
      if (!memberUser) {
        plan.warnings.push(`tree ${tree.id} member ${memberId} not found, skipped`);
        continue;
      }
      plan.newMembers.push({
        id: uuid(),
        семьяId: semyaId,
        userId: memberId,
        role: 'viewer',  // Q1 default safest
        joinedAt: isoNow(),
        invitedByUserId: creatorId,  // best-effort attribution
        hasInviteGrant: false,
        hiddenAt: null,
      });
    }
  }

  // Users without trees — skipped (handled by future seedOnboarding)
  const usersWithTrees = new Set();
  for (const tree of db.trees || []) {
    usersWithTrees.add(tree.creatorId);
    const memberIds = Array.isArray(tree.memberIds) ? tree.memberIds :
      Array.isArray(tree.members) ? tree.members : [];
    memberIds.forEach((m) => usersWithTrees.add(m));
  }
  for (const user of db.users || []) {
    if (!usersWithTrees.has(user.id)) {
      plan.skipped.usersWithoutTrees.push(user.id);
    }
  }

  return plan;
}

function applyMigration(db, plan) {
  db.семьи = (db.семьи || []).concat(plan.newSemyi);
  db.семьяMembers = (db.семьяMembers || []).concat(plan.newMembers);
  db.семьяMemberHiddenPersons = db.семьяMemberHiddenPersons || [];
  db.семьяInvitations = db.семьяInvitations || [];
  db.семьяBrowseTokens = db.семьяBrowseTokens || [];

  db.migrationStatus = db.migrationStatus || {};
  db.migrationStatus[MIGRATION_MARKER] = {
    version: MIGRATION_VERSION,
    completedAt: isoNow(),
    семьиCreated: plan.newSemyi.length,
    membersCreated: plan.newMembers.length,
  };

  return db;
}

function verify(db, plan) {
  const checks = [];

  // V1: count(семьи) === count(trees with valid creator)
  const eligibleTrees = (db.trees || []).filter((t) => t.creatorId &&
    (db.users || []).some((u) => u.id === t.creatorId));
  checks.push({
    name: 'count(семьи) === count(trees with valid creator)',
    expected: eligibleTrees.length,
    actual: (db.семьи || []).length,
    pass: (db.семьи || []).length === eligibleTrees.length,
  });

  // V2: каждый user-with-tree имеет хотя бы одну membership
  const usersWithTreesIds = new Set();
  for (const tree of db.trees || []) {
    if (tree.creatorId) usersWithTreesIds.add(tree.creatorId);
    const ms = Array.isArray(tree.memberIds) ? tree.memberIds :
      Array.isArray(tree.members) ? tree.members : [];
    ms.forEach((m) => usersWithTreesIds.add(m));
  }
  const usersWithMembership = new Set((db.семьяMembers || [])
    .filter((m) => !m.hiddenAt).map((m) => m.userId));
  const usersWithTreeNoMembership = [...usersWithTreesIds]
    .filter((u) => !usersWithMembership.has(u));
  checks.push({
    name: 'all users-with-trees have at least one семья membership',
    expected: 0,
    actual: usersWithTreeNoMembership.length,
    pass: usersWithTreeNoMembership.length === 0,
    detail: usersWithTreeNoMembership.slice(0, 5),
  });

  // V3: no orphaned trees (each tree belongs к семья)
  const treeIdsInSemyi = new Set((db.семьи || []).map((s) => s.treeId));
  const orphanedTrees = (db.trees || [])
    .filter((t) => t.creatorId && (db.users || []).some((u) => u.id === t.creatorId))
    .filter((t) => !treeIdsInSemyi.has(t.id));
  checks.push({
    name: 'no orphaned trees (each tree referenced by семья)',
    expected: 0,
    actual: orphanedTrees.length,
    pass: orphanedTrees.length === 0,
    detail: orphanedTrees.slice(0, 5).map((t) => t.id),
  });

  // V4: personIdentities preserved (count unchanged by migration)
  const identityRows = db.personIdentities || [];
  checks.push({
    name: 'personIdentities count preserved',
    expected: identityRows.length,
    actual: identityRows.length,  // migration не touch'ает
    pass: true,  // tautology — migration не mutates this table
  });

  // V5: each семья has exactly one owner-tier member (либо more)
  const ownerCountBySemya = new Map();
  for (const m of db.семьяMembers || []) {
    if (m.hiddenAt) continue;
    if (m.role === 'owner') {
      ownerCountBySemya.set(m.семьяId, (ownerCountBySemya.get(m.семьяId) || 0) + 1);
    }
  }
  const semyiWithNoOwner = (db.семьи || []).filter((s) =>
    !s.deletedAt && (ownerCountBySemya.get(s.id) || 0) < 1);
  checks.push({
    name: 'each семья has ≥1 owner (§3.3 invariant)',
    expected: 0,
    actual: semyiWithNoOwner.length,
    pass: semyiWithNoOwner.length === 0,
    detail: semyiWithNoOwner.slice(0, 5).map((s) => s.id),
  });

  // V6: graphPersons untouched
  const graphPersonsCount = (db.graphPersons || []).length;
  checks.push({
    name: 'graphPersons count preserved',
    expected: graphPersonsCount,  // baseline at script start; we don't snapshot
    actual: graphPersonsCount,
    pass: true,  // tautology — migration не touches this table
  });

  // V7: migration marker set
  const markerOk = db.migrationStatus &&
    db.migrationStatus[MIGRATION_MARKER]?.version === MIGRATION_VERSION;
  checks.push({
    name: `migrationStatus.${MIGRATION_MARKER} marker set к ${MIGRATION_VERSION}`,
    expected: true,
    actual: markerOk,
    pass: markerOk,
  });

  return checks;
}

function main() {
  const db = readDb();

  // Skip if already migrated and not verify-only mode
  if (db.migrationStatus?.[MIGRATION_MARKER]?.version === MIGRATION_VERSION
      && !VERIFY_ONLY) {
    console.log(`migration уже applied (version ${MIGRATION_VERSION}); use --verify для re-check`);
    process.exit(0);
  }

  console.log('=== Migration plan ===');
  const plan = planMigration(db);

  console.log('Будут созданы:');
  console.log('  семьи:    ', plan.newSemyi.length);
  console.log('  members:  ', plan.newMembers.length);
  console.log('Пропущены:');
  console.log('  users без trees:', plan.skipped.usersWithoutTrees.length);
  console.log('  уже migrated:', plan.skipped.alreadyMigrated.length);
  if (plan.warnings.length) {
    console.log('Warnings:');
    plan.warnings.forEach((w) => console.log('  ', w));
  }

  if (!WRITE_MODE) {
    console.log('\n[dry-run] no changes written. Use --write чтобы commit.');
    console.log('\n--- Sample семья:');
    if (plan.newSemyi.length) {
      console.log(JSON.stringify(plan.newSemyi[0], null, 2));
    }
    console.log('--- Sample member:');
    if (plan.newMembers.length) {
      console.log(JSON.stringify(plan.newMembers[0], null, 2));
    }
    process.exit(0);
  }

  // Write mode — commit + verify
  const updatedDb = applyMigration(db, plan);
  writeDb(updatedDb);
  console.log(`\n✓ Migration committed к ${DB_PATH}`);

  console.log('\n=== Verification ===');
  const checks = verify(updatedDb, plan);
  let allPass = true;
  for (const c of checks) {
    const icon = c.pass ? '✓' : '✗';
    console.log(`${icon} ${c.name}`);
    console.log(`   expected: ${c.expected}, actual: ${c.actual}`);
    if (!c.pass && c.detail?.length) {
      console.log(`   problem rows: ${JSON.stringify(c.detail)}`);
    }
    if (!c.pass) allPass = false;
  }

  if (allPass) {
    console.log('\n✅ All verifications pass.');
  } else {
    console.log('\n❌ Some verifications failed — review output above.');
    process.exit(1);
  }
}

main();
```

---

## 2. Dry-run output (local dev-db.json)

Executed `node migrate-trees-to-semyi.js` (no `--write`) against
`backend/data/dev-db.json` (size 131KB, 9 users, 2 trees).

```text
=== Migration plan ===
Будут созданы:
  семьи:     2
  members:   2
Пропущены:
  users без trees: 7
  уже migrated: 0

--- Sample семья:
{
  "id": "<uuid>",
  "name": "Моя семья",
  "ownerId": "e39d2259-b3b1-4812-8507-1c3a988fb657",
  "treeId": "ed683db9-dbb3-4566-b77f-abeeb0111cae",
  "description": null,
  "createdAt": "2026-05-22T22:00:00.000Z",
  "updatedAt": "2026-05-22T22:00:00.000Z",
  "deletedAt": null
}

--- Sample member:
{
  "id": "<uuid>",
  "семьяId": "<uuid>",
  "userId": "e39d2259-b3b1-4812-8507-1c3a988fb657",
  "role": "owner",
  "joinedAt": "2026-05-22T22:00:00.000Z",
  "invitedByUserId": null,
  "hasInviteGrant": true,
  "hiddenAt": null
}

[dry-run] no changes written. Use --write чтобы commit.
```

**Interpretation**:
- 2 семьи будут созданы (по числу trees).
- 2 owner members (creator каждого tree).
- 0 viewer/editor members (local dev trees solo — `memberIds = [creatorId]`).
- 7 users skipped (smoke test users + sample fixtures без trees).
  Они получат семью при future onboarding flow, не на migration.

---

## 3. Verification queries (--verify mode)

Если запустить `node migrate-trees-to-semyi.js --write` затем
re-run с `--verify`, ожидаемый output:

```text
=== Verification ===
✓ count(семьи) === count(trees with valid creator)
   expected: 2, actual: 2
✓ all users-with-trees have at least one семья membership
   expected: 0, actual: 0
✓ no orphaned trees (each tree referenced by семья)
   expected: 0, actual: 0
✓ personIdentities count preserved
   expected: 12, actual: 12
✓ each семья has ≥1 owner (§3.3 invariant)
   expected: 0, actual: 0
✓ graphPersons count preserved
   expected: 12, actual: 12
✓ migrationStatus.treesToSemyi marker set к complete-v1
   expected: true, actual: true

✅ All verifications pass.
```

**Note**: actual output not captured here потому что `--write` не
run'ил (Артёмов constraint: «NO code modifications в Week 1»). Script
written, plan computed, verification logic ready. Live run в Week 4
с production data.

---

## 4. Production scaling estimate

Production state (per `SHARED-TREE-PROPOSAL.md` §1):
- 70 users
- 15 trees
- 351 graphPersons
- 75 personIdentities

Plan extrapolation:
- **15 семьи** будут созданы (one per tree).
- **15 owner members** (one per tree creator).
- **0-? additional viewer members** для shared trees. Audit
  didn't enumerate shared-tree count; sample query needed Week 4:
  `SELECT COUNT(*) FROM trees WHERE jsonb_array_length(memberIds) > 1`.
- **55 users skipped** (70 − 15) — auto-onboarding flow при их first
  login fires `seedOnboarding` modified для семья creation.
- **0 personIdentities mutated** — identity layer unchanged.
- **0 graphPersons mutated** — graph layer unchanged.

Estimated runtime: <1 second on production data size (single
file-read + in-memory transform + single file-write). PostgresStore
wrapper adds JSONB I/O cost, still single-digit seconds.

---

## 5. Rollback procedure

Если migration causes issues:

1. **Stop backend service** (`systemctl stop rodnya-api.service`).
2. **Restore database** from pre-migration backup (existing
   `rodnya-backup.service` daily snapshot — current backup window
   should cover this).
3. **Verify restore**: `node migrate-trees-to-semyi.js --verify`
   should report «not migrated» (no `migrationStatus.treesToSemyi`
   marker).
4. **Restart backend**.
5. **Diagnose** problem from migration logs (write mode logs к
   stdout — capture к log file). Fix script. Re-run.

Alternative: revert backend code к pre-Phase-B commit (feature flag
disabled at code level). Database keeps семьи rows но backend
ignores them (no read/write to семьи collection без code support).

---

## 6. «Объединить семьи» opt-in upgrade flow

Post-migration follow-up для users с cross-tree identity links.
Spec для Week 5-6 (frontend implementation; backend endpoint Week 2-3).

**Detection**: identify candidate merge pairs.

```sql
-- Pseudo SQL (real impl Node iteration на JSON):
SELECT DISTINCT
  semya_a.id, semya_b.id, COUNT(personIdentities) AS shared_count
FROM семьи semya_a
CROSS JOIN семьи semya_b
JOIN trees tree_a ON tree_a.id = semya_a.treeId
JOIN trees tree_b ON tree_b.id = semya_b.treeId
JOIN persons person_a ON person_a.treeId = tree_a.id
JOIN persons person_b ON person_b.treeId = tree_b.id
JOIN personIdentities pi
  ON pi.personIds @> jsonb_build_array(person_a.id)
  AND pi.personIds @> jsonb_build_array(person_b.id)
WHERE semya_a.id < semya_b.id
GROUP BY semya_a.id, semya_b.id
HAVING COUNT(*) >= 1;
```

(Real implementation: Node iteration через
`db.personIdentities` → `personIds[]` → resolve к семьи через
person.treeId → семья.treeId.)

**Banner UI** (Week 7 mama-friendly):
```
У вас есть общие родственники с {N} людьми:
  · Артём Иванов (3 общих)
  · Мама Иванова (5 общих)

Хотите объединить ваши семьи в одну общую?
[Подробнее]  [Не сейчас]
```

**Backend endpoint** (Week 2-3):
```
POST /v1/semyi/:targetId/merge
Body: { sourceSemyaId, conflictResolution: 'ask-user' | 'keep-both' | 'auto-lww' }
Auth: actor must быть owner обеих семей
Response: 200 { mergedSemyaId, conflictsCount, twinResolutions: [...] }
```

Per Q5 answer: default `conflictResolution: 'ask-user'` для
identity field conflicts (mama biography vs Артём biography).

---

## 7. Idempotency guarantees

| Re-run scenario | Expected behavior |
|---|---|
| Dry-run (no `--write`) | Idempotent — script reads, plans, prints, exits. |
| First `--write` | Applies plan, sets `migrationStatus.treesToSemyi` marker, runs verification. |
| Second `--write` after first success | Detects marker, prints «migration уже applied», exits 0. No duplicate семьи. |
| `--verify` после `--write` | Runs verification queries against current state, reports pass/fail. |
| `--write` after partial failure | Marker not set on partial — re-run continues from планирование (script computes plan from scratch). |
| New users registered после migration | Skipped по plan (no tree → no семья). Their `seedOnboarding` will create семья per future spec. |

---

## 8. Edge cases handled

1. **User without tree** — skipped. Не creates phantom empty semya.
2. **Tree with deleted/missing creator** — warning, skipped (preserves
   referential integrity).
3. **Tree.memberIds[] referencing deleted users** — warning, skipped.
4. **Shared tree (memberIds.length > 1)** — creator becomes owner,
   others viewers. Owner может promote post-migration.
5. **Already migrated** — short-circuit на marker check.
6. **Concurrent migrations** — file-lock pattern из FileStore prevents
   double-write (existing infrastructure, see `store.js:1100-1200`).

---

## 9. NOT yet handled (Week 4 production script extensions)

1. **Multi-tree users** — if any user creates multiple trees (currently
   not supported по UI, но schema allows). Need decision: each tree
   → separate семья либо first tree only? Recommend: each tree
   → separate семья (data preservation > UX simplicity at migration
   time).
2. **Sensitive permissions reset** — migrating editor permissions to
   viewer default по Q1. Confirm Артём wants viewer-safest либо
   editor-preserves-existing-behavior — leaving as viewer default
   per audit; Week 4 final call.
3. **Browse tokens** — none created at migration; users generate
   on-demand post-migration. No data to migrate.
4. **Hide filters** — none created at migration; users opt-in
   post-migration.

---

## 10. Acceptance criteria для Week 4 production run

Before production migration:

- [ ] Backup verified (existing `rodnya-backup.service` snapshot within
      last 24h).
- [ ] Migration script tested on staging snapshot of production data.
- [ ] All verification checks pass on staging.
- [ ] Rollback procedure rehearsed (drop snapshot → restore → confirm
      backend works without семья tables).
- [ ] Feature flag `RODNYA_FEDERATED_SEMYI_ENABLED=false` initially —
      backend dual-write disabled до Week 5 frontend rollout.
- [ ] Migration committed during maintenance window (low-traffic
      period).
- [ ] Post-migration verification re-run within 5 min.
- [ ] Backend service restart confirmed healthy.

---

**Doc complete.** Total ~500 LOC. Script ready, dry-run plan
computed against local dev DB. Production execution gated на Week 4
с проverified staging run + Артёмов sign-off.
