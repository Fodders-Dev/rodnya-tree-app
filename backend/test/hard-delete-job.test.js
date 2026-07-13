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

// ── Unbounded log/history retention sweep (blob-shrink) ────────────
const HOUR_MS = 3_600_000;

function makeCall(overrides) {
  return {
    id: `call_${Math.random().toString(36).slice(2)}`,
    chatId: "chat-1",
    initiatorId: "user-a",
    recipientId: "user-b",
    state: "ended",
    createdAt: null,
    updatedAt: null,
    endedAt: null,
    ...overrides,
  };
}

const LOG_RETENTION = {
  callsTerminalHours: 24,
  callsTerminalMax: 500,
  pushDeliveriesDays: 7,
  pushDeliveriesMax: 2000,
  notifSilentHours: 48,
  notifReadDays: 30,
  notifUnreadDays: 365,
  treeChangeDetailDays: 30,
};

test("log sweep: db.calls — terminal past TTL trimmed, busy calls untouched", async () => {
  const {store, tempDir} = await makeStore();
  const now = new Date("2026-05-18T00:00:00Z");
  await seedState(store, (db) => {
    db.calls.push(
      // busy — must NEVER be trimmed regardless of age
      makeCall({id: "call-ringing", state: "ringing", createdAt: isoOffset(now, -10 * DAY_MS), updatedAt: isoOffset(now, -10 * DAY_MS)}),
      makeCall({id: "call-active", state: "active", createdAt: isoOffset(now, -10 * DAY_MS), updatedAt: isoOffset(now, -10 * DAY_MS)}),
      // terminal older than 24h → trimmed
      makeCall({id: "call-old-ended", state: "ended", createdAt: isoOffset(now, -3 * DAY_MS), updatedAt: isoOffset(now, -2 * DAY_MS), endedAt: isoOffset(now, -2 * DAY_MS)}),
      makeCall({id: "call-old-cancelled", state: "cancelled", createdAt: isoOffset(now, -5 * DAY_MS), updatedAt: isoOffset(now, -5 * DAY_MS)}),
      // terminal within 24h → kept
      makeCall({id: "call-recent-ended", state: "ended", createdAt: isoOffset(now, -2 * HOUR_MS), updatedAt: isoOffset(now, -1 * HOUR_MS), endedAt: isoOffset(now, -1 * HOUR_MS)}),
    );
  });

  const summary = await store.hardDeleteExpired({now, retentionDays: 30, logRetention: LOG_RETENTION});

  assert.equal(summary.logRetention.callsTerminal, 2);
  const db = await store._read();
  assert.deepEqual(
    db.calls.map((c) => c.id).sort(),
    ["call-active", "call-recent-ended", "call-ringing"],
  );
  await cleanup(tempDir);
});

test("log sweep: db.calls — newest-N cap trims surplus terminal calls", async () => {
  const {store, tempDir} = await makeStore();
  const now = new Date("2026-05-18T00:00:00Z");
  await seedState(store, (db) => {
    // 4 terminal calls all within TTL (last few hours) — cap=2 keeps newest 2
    for (let i = 0; i < 4; i += 1) {
      db.calls.push(
        makeCall({
          id: `call-${i}`,
          state: "ended",
          createdAt: isoOffset(now, -(i + 1) * HOUR_MS),
          updatedAt: isoOffset(now, -(i + 1) * HOUR_MS),
          endedAt: isoOffset(now, -(i + 1) * HOUR_MS),
        }),
      );
    }
    db.calls.push(makeCall({id: "call-busy", state: "ringing", createdAt: isoOffset(now, -1 * HOUR_MS), updatedAt: isoOffset(now, -1 * HOUR_MS)}));
  });

  const summary = await store.hardDeleteExpired({
    now,
    retentionDays: 30,
    logRetention: {...LOG_RETENTION, callsTerminalMax: 2},
  });

  assert.equal(summary.logRetention.callsTerminal, 2);
  const db = await store._read();
  // newest two terminal (call-0, call-1) + the busy call survive
  assert.deepEqual(db.calls.map((c) => c.id).sort(), ["call-0", "call-1", "call-busy"]);
  await cleanup(tempDir);
});

test("log sweep: *_MAX=0 DISABLES the cap (does not wipe the collection)", async () => {
  const {store, tempDir} = await makeStore();
  const now = new Date("2026-05-18T00:00:00Z");
  await seedState(store, (db) => {
    // 5 terminal calls all within the 24h TTL → cap would normally apply
    for (let i = 0; i < 5; i += 1) {
      db.calls.push(makeCall({id: `call-${i}`, state: "ended", createdAt: isoOffset(now, -(i + 1) * HOUR_MS), updatedAt: isoOffset(now, -(i + 1) * HOUR_MS), endedAt: isoOffset(now, -(i + 1) * HOUR_MS)}));
    }
    for (let i = 0; i < 5; i += 1) {
      db.pushDeliveries.push({id: `pd-${i}`, createdAt: isoOffset(now, -i * HOUR_MS)});
    }
  });

  // MAX=0 must DISABLE the cap, not slice(0)→wipe. TTL windows also disabled.
  const summary = await store.hardDeleteExpired({
    now,
    retentionDays: 30,
    logRetention: {callsTerminalHours: 0, callsTerminalMax: 0, pushDeliveriesDays: 0, pushDeliveriesMax: 0},
  });

  assert.equal(summary.logRetention.callsTerminal, 0, "cap=0 must not delete calls");
  assert.equal(summary.logRetention.pushDeliveries, 0, "cap=0 must not delete deliveries");
  const db = await store._read();
  assert.equal(db.calls.length, 5, "all calls preserved when cap disabled");
  assert.equal(db.pushDeliveries.length, 5, "all deliveries preserved when cap disabled");
  await cleanup(tempDir);
});

test("log sweep: notification with missing createdAt is never deleted", async () => {
  const {store, tempDir} = await makeStore();
  const now = new Date("2026-05-18T00:00:00Z");
  await seedState(store, (db) => {
    db.notifications.push(
      {id: "n-no-date-unread", userId: "u1"}, // no createdAt, unread → must be kept
      {id: "n-ancient-unread", userId: "u1", createdAt: isoOffset(now, -400 * DAY_MS)}, // trimmed
    );
  });

  const summary = await store.hardDeleteExpired({now, retentionDays: 30, logRetention: LOG_RETENTION});

  assert.equal(summary.logRetention.notificationsUnread, 1);
  const db = await store._read();
  assert.deepEqual(db.notifications.map((n) => n.id).sort(), ["n-no-date-unread"]);
  await cleanup(tempDir);
});

test("log sweep: db.pushDeliveries — age TTL trims old telemetry", async () => {
  const {store, tempDir} = await makeStore();
  const now = new Date("2026-05-18T00:00:00Z");
  await seedState(store, (db) => {
    db.pushDeliveries.push(
      {id: "pd-old", createdAt: isoOffset(now, -8 * DAY_MS)},
      {id: "pd-edge", createdAt: isoOffset(now, -6 * DAY_MS)},
      {id: "pd-fresh", createdAt: isoOffset(now, -1 * DAY_MS)},
    );
  });

  const summary = await store.hardDeleteExpired({now, retentionDays: 30, logRetention: LOG_RETENTION});

  assert.equal(summary.logRetention.pushDeliveries, 1);
  const db = await store._read();
  assert.deepEqual(db.pushDeliveries.map((d) => d.id).sort(), ["pd-edge", "pd-fresh"]);
  await cleanup(tempDir);
});

test("log sweep: db.notifications — silent/read/unread windows", async () => {
  const {store, tempDir} = await makeStore();
  const now = new Date("2026-05-18T00:00:00Z");
  await seedState(store, (db) => {
    db.notifications.push(
      // silent > 48h → trimmed
      {id: "n-silent-old", userId: "u1", silent: true, createdAt: isoOffset(now, -3 * DAY_MS)},
      // silent < 48h → kept
      {id: "n-silent-fresh", userId: "u1", silent: true, createdAt: isoOffset(now, -1 * DAY_MS)},
      // read > 30d → trimmed
      {id: "n-read-old", userId: "u1", readAt: isoOffset(now, -40 * DAY_MS), createdAt: isoOffset(now, -45 * DAY_MS)},
      // read < 30d → kept
      {id: "n-read-fresh", userId: "u1", readAt: isoOffset(now, -5 * DAY_MS), createdAt: isoOffset(now, -6 * DAY_MS)},
      // unread > 365d → trimmed
      {id: "n-unread-ancient", userId: "u1", createdAt: isoOffset(now, -400 * DAY_MS)},
      // unread recent → kept (the live feature window)
      {id: "n-unread-fresh", userId: "u1", createdAt: isoOffset(now, -2 * DAY_MS)},
    );
  });

  const summary = await store.hardDeleteExpired({now, retentionDays: 30, logRetention: LOG_RETENTION});

  assert.equal(summary.logRetention.notificationsSilent, 1);
  assert.equal(summary.logRetention.notificationsRead, 1);
  assert.equal(summary.logRetention.notificationsUnread, 1);
  const db = await store._read();
  assert.deepEqual(
    db.notifications.map((n) => n.id).sort(),
    ["n-read-fresh", "n-silent-fresh", "n-unread-fresh"],
  );
  await cleanup(tempDir);
});

test("log sweep: db.treeChangeRecords — strips old snapshots, keeps record + article history", async () => {
  const {store, tempDir} = await makeStore();
  const now = new Date("2026-05-18T00:00:00Z");
  await seedState(store, (db) => {
    db.treeChangeRecords.push(
      // old non-article with heavy snapshots → stripped, record kept
      {
        id: "tc-old-update",
        treeId: "t1",
        type: "person.updated",
        createdAt: isoOffset(now, -60 * DAY_MS),
        details: {before: {name: "A", huge: "x".repeat(1000)}, after: {name: "B"}, changedFields: ["name"]},
      },
      // recent non-article → left intact (still within detail window)
      {
        id: "tc-recent-update",
        treeId: "t1",
        type: "person.updated",
        createdAt: isoOffset(now, -5 * DAY_MS),
        details: {before: {name: "C"}, after: {name: "D"}},
      },
      // article.* → NEVER touched (biography edit provenance)
      {
        id: "tc-article-old",
        treeId: "t1",
        type: "article.block-updated",
        createdAt: isoOffset(now, -200 * DAY_MS),
        details: {before: {text: "old bio"}, after: {text: "new bio"}},
      },
    );
  });

  const summary = await store.hardDeleteExpired({now, retentionDays: 30, logRetention: LOG_RETENTION});

  assert.equal(summary.logRetention.treeChangeDetailsStripped, 1);
  const db = await store._read();
  const byId = Object.fromEntries(db.treeChangeRecords.map((r) => [r.id, r]));
  // record survives; heavy keys gone; lightweight metadata retained
  assert.ok(byId["tc-old-update"], "old record kept (timeline intact)");
  assert.equal(byId["tc-old-update"].details.before, undefined);
  assert.equal(byId["tc-old-update"].details.after, undefined);
  assert.deepEqual(byId["tc-old-update"].details.changedFields, ["name"]);
  // recent + article untouched
  assert.deepEqual(byId["tc-recent-update"].details.before, {name: "C"});
  assert.deepEqual(byId["tc-article-old"].details.before, {text: "old bio"});
  await cleanup(tempDir);
});

test("log sweep: dry-run reports counts but mutates nothing", async () => {
  const {store, tempDir} = await makeStore();
  const now = new Date("2026-05-18T00:00:00Z");
  await seedState(store, (db) => {
    db.calls.push(makeCall({id: "call-old", state: "ended", createdAt: isoOffset(now, -3 * DAY_MS), updatedAt: isoOffset(now, -3 * DAY_MS), endedAt: isoOffset(now, -3 * DAY_MS)}));
    db.pushDeliveries.push({id: "pd-old", createdAt: isoOffset(now, -30 * DAY_MS)});
    db.notifications.push({id: "n-silent-old", userId: "u1", silent: true, createdAt: isoOffset(now, -10 * DAY_MS)});
    db.treeChangeRecords.push({id: "tc-old", treeId: "t1", type: "person.updated", createdAt: isoOffset(now, -60 * DAY_MS), details: {before: {a: 1}, after: {a: 2}}});
  });

  const summary = await store.hardDeleteExpired({now, retentionDays: 30, dryRun: true, logRetention: LOG_RETENTION});

  assert.equal(summary.logRetention.callsTerminal, 1);
  assert.equal(summary.logRetention.pushDeliveries, 1);
  assert.equal(summary.logRetention.notificationsSilent, 1);
  assert.equal(summary.logRetention.treeChangeDetailsStripped, 1);

  const db = await store._read();
  assert.equal(db.calls.length, 1, "call preserved in dry-run");
  assert.equal(db.pushDeliveries.length, 1, "push delivery preserved");
  assert.equal(db.notifications.length, 1, "notification preserved");
  // heavy snapshot NOT stripped in dry-run
  assert.deepEqual(db.treeChangeRecords[0].details.before, {a: 1});
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
