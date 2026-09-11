// SPEED-16: hard-delete sweep of the deletedPersons TABLE (SPEED-15 moved the
// trash can out of the blob into `<table>_deleted_persons`). Before this fix,
// PostgresStore.hardDeleteExpired inherited FileStore's array-based sweep
// unchanged — it swept `db.deletedPersons`, which after SPEED-15 is drained
// back to `[]` on every `_write` (`_drainDeletedPersonsCollection`), so the
// 30-day "удалил → удалено" contract (DECISIONS.md 2026-05-18) silently
// stopped firing for anything migrated into the table.
//
// Covers:
//   * eligibility mirrors FileStore's isEligible (explicit
//     hardDeleteScheduledAt wins, else deletedAt+retention fallback),
//   * restoredAt rows are never swept,
//   * earliestHardDelete floor is respected,
//   * dry-run counts without deleting / without writing audit rows,
//   * maxPerRun budget is SHARED with the graph/branch/identity sweep above
//     (table sweep only gets what's left over),
//   * audit rows land in `<table>_hard_delete_audit` with entityType
//     "deletedPerson" and the SAME runId as the rest of the run,
//   * restorePerson() on an already hard-deleted row → DELETED_PERSON_NOT_FOUND,
//   * before the migration marker (`_deletedPersonsTablesReady === false`),
//     behaviour is byte-for-byte the old FileStore array sweep (delegation).
const test = require("node:test");
const assert = require("node:assert/strict");

const {newDb} = require("pg-mem");
const {PostgresStore} = require("../src/postgres-store");

const DAY_MS = 86_400_000;

const USERS = [
  {id: "user-1", email: "ivan@rodnya-tree.ru", profile: {displayName: "Иван"}},
  {id: "user-2", email: "anna@rodnya-tree.ru", profile: {displayName: "Анна"}},
];
const TREE = {
  id: "tree-1",
  name: "Наше дерево",
  creatorId: "user-1",
  memberIds: ["user-1", "user-2"],
  createdAt: "2026-04-01T10:00:00.000Z",
  updatedAt: "2026-04-01T10:00:00.000Z",
  semyaId: "semya-1",
};

const TABLE = `"public"."rodnya_state_deleted_persons"`;
const AUDIT_TABLE = `"public"."rodnya_state_hard_delete_audit"`;

function isoOffset(now, deltaMs) {
  return new Date(now.getTime() + deltaMs).toISOString();
}

function buildStore(seededState) {
  const memDb = newDb();
  const {Pool} = memDb.adapters.createPg();
  const rawPool = new Pool();
  const pool = {
    query: (sql, params) => {
      let effectiveParams = params;
      if (
        String(sql).includes("ON CONFLICT (id) DO NOTHING") &&
        Array.isArray(params) &&
        params[0] === "default"
      ) {
        effectiveParams = [params[0], JSON.stringify(seededState)];
      }
      return rawPool.query(sql, effectiveParams);
    },
  };
  const store = new PostgresStore({
    connectionString: "postgresql://unused/rodnya",
    pool,
    snapshotCachePath: null,
  });
  return {store, rawPool};
}

function deletedPersonRow(now, overrides = {}) {
  return {
    id: overrides.id || "dp-1",
    originalPersonId: overrides.originalPersonId || `person-gone-${overrides.id || "1"}`,
    treeId: "tree-1",
    semyaId: "semya-1",
    snapshot: {id: overrides.originalPersonId || "person-gone", treeId: "tree-1", name: "Ушедший"},
    relationsSnapshot: [],
    deletedByUserId: overrides.deletedByUserId || "user-1",
    deletedAt: overrides.deletedAt || isoOffset(now, -40 * DAY_MS),
    hardDeleteScheduledAt: overrides.hardDeleteScheduledAt ?? null,
    earliestHardDelete: overrides.earliestHardDelete ?? isoOffset(now, -1 * DAY_MS),
    restoredAt: overrides.restoredAt ?? null,
    restoredByUserId: overrides.restoredByUserId ?? null,
  };
}

function seed(now, deletedPersons) {
  return {
    users: USERS,
    trees: [TREE],
    persons: [],
    relations: [],
    semyi: [{id: "semya-1", name: "Семья", createdAt: "2026-04-01T10:00:00.000Z"}],
    semyaMembers: [
      {userId: "user-1", semyaId: "semya-1", hiddenAt: null},
      {userId: "user-2", semyaId: "semya-1", hiddenAt: null},
    ],
    deletedPersons,
  };
}

async function tableRows(rawPool) {
  const result = await rawPool.query(`SELECT * FROM ${TABLE} ORDER BY id`);
  return result.rows;
}

async function auditRows(rawPool) {
  const result = await rawPool.query(`SELECT audit_data FROM ${AUDIT_TABLE}`);
  return result.rows.map((r) =>
    typeof r.audit_data === "string" ? JSON.parse(r.audit_data) : r.audit_data,
  );
}

test("hardDeleteExpired (table): sweeps expired/scheduled rows, keeps recent/restored/floored", async () => {
  const now = new Date("2026-06-18T00:00:00Z");
  const {store, rawPool} = buildStore(
    seed(now, [
      // Fallback path: no explicit schedule, deletedAt 40d ago > 30d retention.
      deletedPersonRow(now, {id: "dp-expired", deletedAt: isoOffset(now, -40 * DAY_MS)}),
      // Explicit schedule wins even though deletedAt itself is recent.
      deletedPersonRow(now, {
        id: "dp-explicit",
        deletedAt: isoOffset(now, -2 * DAY_MS),
        hardDeleteScheduledAt: isoOffset(now, -1 * DAY_MS),
      }),
      // Within the 30-day retention window — must survive.
      deletedPersonRow(now, {id: "dp-recent", deletedAt: isoOffset(now, -5 * DAY_MS)}),
      // Restored — must survive regardless of age.
      deletedPersonRow(now, {
        id: "dp-restored",
        deletedAt: isoOffset(now, -60 * DAY_MS),
        restoredAt: isoOffset(now, -1 * DAY_MS),
        restoredByUserId: "user-1",
      }),
      // Floor not met yet — earliestHardDelete in the future blocks purge.
      deletedPersonRow(now, {
        id: "dp-floored",
        deletedAt: isoOffset(now, -60 * DAY_MS),
        earliestHardDelete: isoOffset(now, +10 * DAY_MS),
      }),
    ]),
  );
  await store.initialize();

  const summary = await store.hardDeleteExpired({now, retentionDays: 30, runId: "run-1"});

  assert.equal(summary.deleted.deletedPersons, 2);
  assert.deepEqual(summary.sampleIds.deletedPerson.sort(), ["dp-expired", "dp-explicit"].sort());

  const rows = await tableRows(rawPool);
  assert.deepEqual(rows.map((r) => r.id).sort(), ["dp-floored", "dp-recent", "dp-restored"]);

  const audit = await auditRows(rawPool);
  const deletedPersonAudit = audit.filter((a) => a.entityType === "deletedPerson");
  assert.equal(deletedPersonAudit.length, 2);
  assert.deepEqual(
    deletedPersonAudit.map((a) => a.entityId).sort(),
    ["dp-expired", "dp-explicit"].sort(),
  );
  for (const entry of deletedPersonAudit) {
    assert.equal(entry.runId, "run-1", "shares the single run's runId");
  }
});

test("hardDeleteExpired (table): dry-run counts without deleting or writing audit", async () => {
  const now = new Date("2026-06-18T00:00:00Z");
  const {store, rawPool} = buildStore(
    seed(now, [deletedPersonRow(now, {id: "dp-expired", deletedAt: isoOffset(now, -40 * DAY_MS)})]),
  );
  await store.initialize();

  const summary = await store.hardDeleteExpired({now, retentionDays: 30, dryRun: true});

  assert.equal(summary.dryRun, true);
  assert.equal(summary.deleted.deletedPersons, 1);
  assert.deepEqual(summary.sampleIds.deletedPerson, ["dp-expired"]);

  const rows = await tableRows(rawPool);
  assert.equal(rows.length, 1, "dry-run leaves the row in place");
  const audit = await auditRows(rawPool);
  assert.equal(audit.filter((a) => a.entityType === "deletedPerson").length, 0, "no audit row written");
});

test("hardDeleteExpired (table): maxPerRun budget shared with graph sweep above", async () => {
  const now = new Date("2026-06-18T00:00:00Z");
  const seeded = seed(now, [
    deletedPersonRow(now, {id: "dp-1", deletedAt: isoOffset(now, -40 * DAY_MS)}),
    deletedPersonRow(now, {id: "dp-2", deletedAt: isoOffset(now, -40 * DAY_MS)}),
    deletedPersonRow(now, {id: "dp-3", deletedAt: isoOffset(now, -40 * DAY_MS)}),
  ]);
  seeded.graphPersons = [
    {id: "gp-1", deletedAt: isoOffset(now, -40 * DAY_MS)},
    {id: "gp-2", deletedAt: isoOffset(now, -40 * DAY_MS)},
    {id: "gp-3", deletedAt: isoOffset(now, -40 * DAY_MS)},
  ];
  const {store, rawPool} = buildStore(seeded);
  await store.initialize();

  // Budget 4: graph sweep (3 graphPersons, no relations/branches/identities)
  // takes all 3 first (leaf→root order in FileStore), leaving exactly 1 for
  // the table sweep even though 3 deletedPersons rows are eligible.
  const summary = await store.hardDeleteExpired({now, retentionDays: 30, maxPerRun: 4});

  assert.equal(summary.deleted.graphPersons, 3);
  assert.equal(summary.deleted.deletedPersons, 1);
  assert.equal(summary.capHit, true, "combined total (4) hit the shared budget");

  const rows = await tableRows(rawPool);
  assert.equal(rows.length, 2, "only 1 of 3 eligible rows swept — budget exhausted by graph sweep");
});

test("restorePerson: DELETED_PERSON_NOT_FOUND once hard-delete swept the row", async () => {
  const now = new Date("2026-06-18T00:00:00Z");
  const {store} = buildStore(
    seed(now, [deletedPersonRow(now, {id: "dp-expired", deletedAt: isoOffset(now, -40 * DAY_MS)})]),
  );
  await store.initialize();

  await store.hardDeleteExpired({now, retentionDays: 30});

  await assert.rejects(
    store.restorePerson({deletedPersonId: "dp-expired", actorUserId: "user-1"}),
    /DELETED_PERSON_NOT_FOUND/,
  );
});

test("hardDeleteExpired: before migration marker — delegates to FileStore's array sweep untouched", async () => {
  const now = new Date("2026-06-18T00:00:00Z");
  const {store, rawPool} = buildStore(seed(now, []));
  await store.initialize();

  // Simulate "migration hasn't completed yet" — the exact gate the table
  // sweep checks. A row lives ONLY in the blob array (as it would pre-
  // SPEED-15), never touching the table.
  store._deletedPersonsTablesReady = false;
  const db = await store._read();
  db.deletedPersons.push({
    id: "dp-blob-only",
    deletedAt: isoOffset(now, -40 * DAY_MS),
    hardDeleteScheduledAt: null,
  });
  await store._write(db);

  const summary = await store.hardDeleteExpired({now, retentionDays: 30});

  assert.equal(summary.deleted.deletedPersons, 1, "FileStore's own array-based sweep still works");
  assert.deepEqual(summary.sampleIds.deletedPerson, ["dp-blob-only"]);

  const after = await store._read();
  assert.deepEqual(after.deletedPersons, [], "swept from the blob array");
  const rows = await tableRows(rawPool);
  assert.equal(rows.length, 0, "table never touched while the readiness gate is off");
});
