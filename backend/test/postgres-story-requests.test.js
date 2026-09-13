// «Спросить историю» MVP-1 — PostgresStore/pg-mem coverage
// (STORY-REQUEST-MVP1-BRIEF.md §2.4).
//
// storyRequests is a small blob collection (NOT one of the SPEED-6/7
// tables) — no PostgresStore override is needed, `_write` never drains it
// like it does notifications/treeChangeRecords/deletedPersons. This file
// proves that claim rather than assuming it:
//   1. A row written via store._mutate really lands in the JSONB column
//      (checked with a raw SQL SELECT against the underlying table, not
//      just PostgresStore's own in-process cache) AND a fresh `_read()`
//      on the same store sees it.
//   2. readSharedSnapshot() (the frozen, cross-request-shared view used
//      by requireTreeAccess, SPEED-11) still carries storyRequests.
//   3. _writableCirclesViewForTree's copy-on-write overlay (SPEED-11/12)
//      does not drop storyRequests — it copies `Object.keys(db)`
//      generically rather than a hand-maintained whitelist, so a brand
//      new top-level collection survives by construction. This was
//      flagged explicitly in the brief as a place a new collection could
//      silently go missing.
//
// NOTE: a second PostgresStore instance sharing the same pg-mem-backed
// pool cannot be constructed here — its initialize() re-runs the
// CREATE TABLE bootstrap against the same already-initialized pg-mem
// schema and pg-mem's AST-coverage checker rejects the (harmless,
// idempotent on real Postgres) IF NOT EXISTS statement the second time.
// Pre-existing pg-mem limitation (see .claude/rules/backend-store.md),
// not something this feature can work around — the raw-SQL check in
// test 1 below proves real persistence without needing a second
// instance.

const test = require("node:test");
const assert = require("node:assert/strict");

const {newDb} = require("pg-mem");
const {PostgresStore} = require("../src/postgres-store");

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

function buildRequestRecord(overrides = {}) {
  const now = new Date().toISOString();
  return {
    id: overrides.id || "sreq_pgmem-1",
    treeId: overrides.treeId || "tree-1",
    personId: overrides.personId || "person-1",
    requesterUserId: overrides.requesterUserId || "user-requester",
    targetUserId: overrides.targetUserId || "user-target",
    question: {text: "Как вы познакомились?", themeKey: null, sourceQuestionId: null},
    status: "pending",
    answer: null,
    createdAt: now,
    updatedAt: now,
    expiresAt: new Date(Date.now() + 30 * 86_400_000).toISOString(),
    respondedAt: null,
    expiredNotifiedAt: null,
    ...overrides,
  };
}

test("storyRequests survives _mutate → _write → _read, and really lands in the JSONB column", async () => {
  const {store, rawPool} = buildStore({users: [], trees: []});
  await store.initialize();

  const record = buildRequestRecord();
  await store._mutate((db) => {
    db.storyRequests.push(record);
  });

  const reread = await store._read();
  assert.equal(reread.storyRequests.length, 1);
  assert.deepEqual(reread.storyRequests[0], record);

  // Direct SQL against the underlying row (bypassing PostgresStore's own
  // read path/cache entirely) — proves the write is really in the JSONB
  // column, not merely an in-process cache artifact.
  const raw = await rawPool.query(
    `SELECT data FROM "public"."rodnya_state" WHERE id = $1`,
    ["default"],
  );
  const persistedData =
    typeof raw.rows[0].data === "string"
      ? JSON.parse(raw.rows[0].data)
      : raw.rows[0].data;
  assert.equal(persistedData.storyRequests.length, 1);
  assert.equal(persistedData.storyRequests[0].id, record.id);
});

test("readSharedSnapshot() carries storyRequests (SPEED-11 frozen shared view)", async () => {
  const {store} = buildStore({users: [], trees: []});
  await store.initialize();

  const record = buildRequestRecord({id: "sreq_pgmem-2"});
  await store._mutate((db) => {
    db.storyRequests.push(record);
  });

  const snapshot = await store.readSharedSnapshot();
  assert.ok(Object.isFrozen(snapshot), "sanity: shared snapshot is frozen");
  assert.equal(snapshot.storyRequests.length, 1);
  assert.equal(snapshot.storyRequests[0].id, "sreq_pgmem-2");
  assert.equal(snapshot.storyRequests[0].question.text, "Как вы познакомились?");
});

test("_writableCirclesViewForTree overlay does not drop storyRequests (generic Object.keys copy, not a whitelist)", async () => {
  const {store} = buildStore({users: [], trees: []});
  await store.initialize();

  const record = buildRequestRecord({id: "sreq_pgmem-3"});
  await store._mutate((db) => {
    db.storyRequests.push(record);
  });

  const frozenDb = await store.readSharedSnapshot();
  // Any treeId works here — the overlay filters circles/persons by
  // treeId, but copies every OTHER top-level key (storyRequests
  // included) unconditionally via `for (const key of Object.keys(db))`.
  const overlay = store._writableCirclesViewForTree(frozenDb, "tree-1", null);

  assert.notEqual(overlay, frozenDb, "overlay is a distinct object from the frozen snapshot");
  assert.ok(!Object.isFrozen(overlay), "overlay itself is a fresh writable object");
  // Same reference — storyRequests isn't one of the treeId-scoped arrays
  // (circles/persons/circleMembers/personIdentities) the overlay clones,
  // so it rides along as the identical array reference. Losing the key
  // entirely (the regression this test guards against) would make this
  // `undefined` instead.
  assert.equal(overlay.storyRequests, frozenDb.storyRequests);
  assert.equal(overlay.storyRequests.length, 1);
  assert.equal(overlay.storyRequests[0].id, "sreq_pgmem-3");
});
