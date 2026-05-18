// Phase 3.6 hard-delete background job tests.
//
// Covers:
//   * Eligibility (hybrid window — explicit `hardDeleteScheduledAt`
//     overrides age-based fallback).
//   * Delete order (relations → branches → identities → persons →
//     orphan views).
//   * Safety knobs: dry-run, pause, max-per-run cap.
//   * Audit log: entries created per delete + 90-day self-prune.
//   * Orphan branchPersonViews cleanup (no own deletedAt).
//   * `hardDeleteLastRunAt` persistence (drives scheduler catch-up).
//   * `computeFirstDelayMs` catch-up logic.

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");

const {FileStore} = require("../src/store");
const {
  runHardDeleteJob,
  computeFirstDelayMs,
  FIRST_RUN_DELAY_MS,
} = require("../src/jobs/hard-delete-job");

const DAY_MS = 86_400_000;

async function makeStore() {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-hd-"));
  const dataPath = path.join(tempDir, "dev-db.json");
  const store = new FileStore(dataPath);
  await store.initialize();
  return {store, tempDir};
}

async function cleanup(tempDir) {
  try {
    await fs.rm(tempDir, {recursive: true, force: true});
  } catch (_) {
    // best-effort на Windows tempdir race
  }
}

function isoOffset(now, deltaMs) {
  return new Date(now.getTime() + deltaMs).toISOString();
}

async function seedState(store, mutator) {
  const db = await store._read();
  mutator(db);
  await store._write(db);
}

test("hardDeleteExpired: deletes expired entries past explicit window", async () => {
  const {store, tempDir} = await makeStore();
  const now = new Date("2026-05-18T00:00:00Z");
  await seedState(store, (db) => {
    db.graphPersons.push(
      {
        id: "gp-expired",
        deletedAt: isoOffset(now, -40 * DAY_MS),
        hardDeleteScheduledAt: isoOffset(now, -10 * DAY_MS),
      },
      {
        id: "gp-future",
        deletedAt: isoOffset(now, -5 * DAY_MS),
        hardDeleteScheduledAt: isoOffset(now, +25 * DAY_MS),
      },
      {
        id: "gp-alive",
        deletedAt: null,
        hardDeleteScheduledAt: null,
      },
    );
  });

  const summary = await store.hardDeleteExpired({
    now,
    retentionDays: 30,
    runId: "test-run-1",
  });

  assert.equal(summary.deleted.graphPersons, 1);
  assert.equal(summary.dryRun, false);
  assert.deepEqual(summary.sampleIds.graphPerson, ["gp-expired"]);

  const db = await store._read();
  assert.deepEqual(
    db.graphPersons.map((p) => p.id).sort(),
    ["gp-alive", "gp-future"],
  );
  assert.equal(db.hardDeleteAudit.length, 1);
  assert.equal(db.hardDeleteAudit[0].entityId, "gp-expired");
  assert.equal(db.hardDeleteAudit[0].runId, "test-run-1");
  assert.equal(db.hardDeleteLastRunAt, now.toISOString());
  await cleanup(tempDir);
});

test("hardDeleteExpired: age-based fallback when hardDeleteScheduledAt missing", async () => {
  const {store, tempDir} = await makeStore();
  const now = new Date("2026-05-18T00:00:00Z");
  await seedState(store, (db) => {
    // Path B (reconciliation) leaves hardDeleteScheduledAt undefined.
    db.graphPersons.push(
      {id: "gp-old", deletedAt: isoOffset(now, -31 * DAY_MS)},
      {id: "gp-recent", deletedAt: isoOffset(now, -29 * DAY_MS)},
    );
    db.graphRelations.push({
      id: "gr-old",
      deletedAt: isoOffset(now, -40 * DAY_MS),
    });
    db.branches.push({
      id: "br-old",
      deletedAt: isoOffset(now, -45 * DAY_MS),
    });
    db.personIdentities.push({
      id: "pi-old",
      deletedAt: isoOffset(now, -60 * DAY_MS),
    });
  });

  const summary = await store.hardDeleteExpired({now, retentionDays: 30});

  assert.equal(summary.deleted.graphPersons, 1);
  assert.equal(summary.deleted.graphRelations, 1);
  assert.equal(summary.deleted.branches, 1);
  assert.equal(summary.deleted.personIdentities, 1);

  const db = await store._read();
  assert.deepEqual(db.graphPersons.map((p) => p.id), ["gp-recent"]);
  assert.deepEqual(db.graphRelations, []);
  assert.deepEqual(db.branches, []);
  assert.deepEqual(db.personIdentities, []);
  await cleanup(tempDir);
});

test("hardDeleteExpired: orphan branchPersonViews cleanup", async () => {
  const {store, tempDir} = await makeStore();
  const now = new Date("2026-05-18T00:00:00Z");
  await seedState(store, (db) => {
    db.branches.push({
      id: "br-doomed",
      deletedAt: isoOffset(now, -60 * DAY_MS),
    });
    db.graphPersons.push({
      id: "gp-doomed",
      deletedAt: isoOffset(now, -60 * DAY_MS),
    });
    db.branchPersonViews.push(
      // Orphan: branch doomed, gets cleaned.
      {id: "v-1", branchId: "br-doomed", graphPersonId: "gp-alive"},
      // Orphan: person doomed.
      {id: "v-2", branchId: "br-alive", graphPersonId: "gp-doomed"},
      // Alive: both refs live.
      {id: "v-3", branchId: "br-alive", graphPersonId: "gp-alive"},
    );
  });

  const summary = await store.hardDeleteExpired({now, retentionDays: 30});

  assert.equal(summary.deleted.branchPersonViews, 2);
  const db = await store._read();
  assert.deepEqual(
    db.branchPersonViews.map((v) => v.id),
    ["v-3"],
  );
  // Audit entries for orphan views — deletedAt/scheduledAt null
  // (they didn't have their own soft-delete).
  const orphanAuditEntries = db.hardDeleteAudit.filter(
    (e) => e.entityType === "branchPersonView",
  );
  assert.equal(orphanAuditEntries.length, 2);
  assert.equal(orphanAuditEntries[0].deletedAt, null);
  assert.equal(orphanAuditEntries[0].scheduledAt, null);
  await cleanup(tempDir);
});

test("hardDeleteExpired: dry-run does not mutate state", async () => {
  const {store, tempDir} = await makeStore();
  const now = new Date("2026-05-18T00:00:00Z");
  await seedState(store, (db) => {
    db.graphPersons.push({
      id: "gp-dry",
      deletedAt: isoOffset(now, -40 * DAY_MS),
    });
  });
  const before = await store._read();
  const beforeCount = before.graphPersons.length;
  const beforeAudit = before.hardDeleteAudit.length;
  const beforeLastRun = before.hardDeleteLastRunAt;

  const summary = await store.hardDeleteExpired({
    now,
    retentionDays: 30,
    dryRun: true,
  });

  assert.equal(summary.dryRun, true);
  assert.equal(summary.deleted.graphPersons, 1);
  assert.deepEqual(summary.sampleIds.graphPerson, ["gp-dry"]);
  assert.equal(summary.lastRunAt, beforeLastRun);

  const after = await store._read();
  assert.equal(after.graphPersons.length, beforeCount);
  assert.equal(after.hardDeleteAudit.length, beforeAudit);
  assert.equal(after.hardDeleteLastRunAt, beforeLastRun);
  await cleanup(tempDir);
});

test("hardDeleteExpired: max-per-run cap halts deletions and reports capHit", async () => {
  const {store, tempDir} = await makeStore();
  const now = new Date("2026-05-18T00:00:00Z");
  await seedState(store, (db) => {
    for (let i = 0; i < 12; i += 1) {
      db.graphPersons.push({
        id: `gp-${i}`,
        deletedAt: isoOffset(now, -40 * DAY_MS),
      });
    }
  });

  const summary = await store.hardDeleteExpired({
    now,
    retentionDays: 30,
    maxPerRun: 5,
  });

  assert.equal(summary.deleted.graphPersons, 5);
  assert.equal(summary.capHit, true);
  const db = await store._read();
  assert.equal(db.graphPersons.length, 7);
  assert.equal(db.hardDeleteAudit.length, 5);
  await cleanup(tempDir);
});

test("hardDeleteExpired: delete order — relations before persons", async () => {
  const {store, tempDir} = await makeStore();
  const now = new Date("2026-05-18T00:00:00Z");
  await seedState(store, (db) => {
    db.graphPersons.push({
      id: "gp-a",
      deletedAt: isoOffset(now, -40 * DAY_MS),
    });
    db.graphRelations.push({
      id: "gr-a",
      deletedAt: isoOffset(now, -40 * DAY_MS),
    });
  });

  // Cap = 1 — должен взять graphRelation первым (per order leaf→root).
  const summary = await store.hardDeleteExpired({
    now,
    retentionDays: 30,
    maxPerRun: 1,
  });

  assert.equal(summary.deleted.graphRelations, 1);
  assert.equal(summary.deleted.graphPersons, 0);
  const db = await store._read();
  assert.equal(db.graphRelations.length, 0);
  assert.equal(db.graphPersons.length, 1);
  await cleanup(tempDir);
});

test("hardDeleteExpired: audit self-prune drops entries older than auditRetentionDays", async () => {
  const {store, tempDir} = await makeStore();
  const now = new Date("2026-05-18T00:00:00Z");
  await seedState(store, (db) => {
    db.hardDeleteAudit.push(
      {
        runId: "old",
        entityType: "graphPerson",
        entityId: "gp-old",
        deletedAt: isoOffset(now, -200 * DAY_MS),
        scheduledAt: isoOffset(now, -170 * DAY_MS),
        hardDeletedAt: isoOffset(now, -100 * DAY_MS),
      },
      {
        runId: "recent",
        entityType: "graphPerson",
        entityId: "gp-recent",
        deletedAt: isoOffset(now, -50 * DAY_MS),
        scheduledAt: isoOffset(now, -20 * DAY_MS),
        hardDeletedAt: isoOffset(now, -30 * DAY_MS),
      },
    );
  });

  const summary = await store.hardDeleteExpired({
    now,
    retentionDays: 30,
    auditRetentionDays: 90,
  });

  assert.equal(summary.deleted.auditPruned, 1);
  const db = await store._read();
  assert.equal(db.hardDeleteAudit.length, 1);
  assert.equal(db.hardDeleteAudit[0].runId, "recent");
  await cleanup(tempDir);
});

test("hardDeleteExpired: recent deletedAt (within retention) preserved", async () => {
  // Note: невозможно тестировать «orphan graphPerson without deletedAt
  // preserved» — `_syncGraphFromLegacy` на каждом `_read` auto-soft-
  // deletes graphPersons без backing legacy person'а. То что мы
  // реально хотим проверить: recent soft-deletes (внутри retention
  // window) не trogается job'ом — это негативный case
  // hybrid-eligibility формулы.
  const {store, tempDir} = await makeStore();
  const now = new Date("2026-05-18T00:00:00Z");
  await seedState(store, (db) => {
    db.graphPersons.push(
      {id: "gp-fresh", deletedAt: isoOffset(now, -5 * DAY_MS)},
      {id: "gp-edge", deletedAt: isoOffset(now, -29 * DAY_MS)},
    );
  });
  const summary = await store.hardDeleteExpired({now, retentionDays: 30});
  assert.equal(summary.deleted.graphPersons, 0);
  const db = await store._read();
  assert.deepEqual(
    db.graphPersons.map((p) => p.id).sort(),
    ["gp-edge", "gp-fresh"],
  );
  await cleanup(tempDir);
});

test("runHardDeleteJob: pause flag returns paused summary without touching store", async () => {
  const {store, tempDir} = await makeStore();
  const now = new Date("2026-05-18T00:00:00Z");
  await seedState(store, (db) => {
    db.graphPersons.push({
      id: "gp-x",
      deletedAt: isoOffset(now, -100 * DAY_MS),
    });
  });

  const summary = await runHardDeleteJob({
    store,
    config: {
      hardDeletePaused: true,
      hardDeleteRetentionDays: 30,
    },
    runtimeInfo: null,
  });

  assert.equal(summary.paused, true);
  const db = await store._read();
  assert.equal(db.graphPersons.length, 1, "store untouched");
  await cleanup(tempDir);
});

test("runHardDeleteJob: firstRunDry forces dry-run even when DRY_RUN unset", async () => {
  const {store, tempDir} = await makeStore();
  const now = new Date("2026-05-18T00:00:00Z");
  await seedState(store, (db) => {
    db.graphPersons.push({
      id: "gp-y",
      deletedAt: isoOffset(now, -100 * DAY_MS),
    });
  });

  const summary = await runHardDeleteJob({
    store,
    config: {
      hardDeleteRetentionDays: 30,
      hardDeleteFirstRunDry: true,
      hardDeleteDryRun: false,
    },
    runtimeInfo: null,
  });

  assert.equal(summary.dryRun, true);
  assert.equal(summary.deleted.graphPersons, 1);
  const db = await store._read();
  assert.equal(db.graphPersons.length, 1, "dry-run leaves state intact");
  await cleanup(tempDir);
});

test("computeFirstDelayMs: firstRunDry overrides → 60s", async () => {
  const {store, tempDir} = await makeStore();
  const delay = await computeFirstDelayMs({
    store,
    config: {hardDeleteFirstRunDry: true, hardDeleteIntervalHours: 24},
  });
  assert.equal(delay, FIRST_RUN_DELAY_MS);
  await cleanup(tempDir);
});

test("computeFirstDelayMs: no lastRunAt → catch-up 60s", async () => {
  const {store, tempDir} = await makeStore();
  const delay = await computeFirstDelayMs({
    store,
    config: {hardDeleteFirstRunDry: false, hardDeleteIntervalHours: 24},
  });
  assert.equal(delay, FIRST_RUN_DELAY_MS);
  await cleanup(tempDir);
});

test("computeFirstDelayMs: stale lastRunAt (older than interval) → catch-up 60s", async () => {
  const {store, tempDir} = await makeStore();
  await seedState(store, (db) => {
    db.hardDeleteLastRunAt = new Date(
      Date.now() - 48 * 3_600_000,
    ).toISOString();
  });
  const delay = await computeFirstDelayMs({
    store,
    config: {hardDeleteFirstRunDry: false, hardDeleteIntervalHours: 24},
  });
  assert.equal(delay, FIRST_RUN_DELAY_MS);
  await cleanup(tempDir);
});

test("computeFirstDelayMs: recent lastRunAt → wait remainder", async () => {
  const {store, tempDir} = await makeStore();
  // 6h назад → должны ждать ~18h.
  await seedState(store, (db) => {
    db.hardDeleteLastRunAt = new Date(
      Date.now() - 6 * 3_600_000,
    ).toISOString();
  });
  const delay = await computeFirstDelayMs({
    store,
    config: {hardDeleteFirstRunDry: false, hardDeleteIntervalHours: 24},
  });
  // Allow ±2s clock drift.
  const expected = 18 * 3_600_000;
  assert.ok(
    Math.abs(delay - expected) < 2000,
    `expected ~${expected}ms, got ${delay}ms`,
  );
  await cleanup(tempDir);
});
