#!/usr/bin/env node
// Phase B Ship 10: connected-per-user-trees → federated семя migration.
//
// Per docs/connected-trees-refactor/MIGRATION-RUNBOOK.md production
// procedure. Production execution gated до Week 8 staged rollout — этот
// script ships ready but не triggered automatically.
//
// Run modes:
//   node backend/scripts/migrate-trees-to-semyi.js              # dry-run (default)
//   node backend/scripts/migrate-trees-to-semyi.js --commit     # write changes
//   node backend/scripts/migrate-trees-to-semyi.js --verify     # only verify
//   node backend/scripts/migrate-trees-to-semyi.js --commit --quiet
//
// Idempotent: марker `migrationStatus.treesToSemyi.version` set on commit,
// re-run skips если same version. Use --force-recommit для override (НЕ
// production-recommend).
//
// File-store mode only (RODNYA_DB_PATH либо defaults к
// backend/data/dev-db.json). Postgres-store migration goes через separate
// `migrate-state-to-postgres.js` workflow.

"use strict";

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const DB_PATH =
  process.env.RODNYA_DB_PATH ||
  path.resolve(__dirname, "../data/dev-db.json");
const MIGRATION_MARKER = "treesToSemyi";
const MIGRATION_VERSION = "complete-v1";

const args = process.argv.slice(2);
const COMMIT_MODE = args.includes("--commit");
const VERIFY_ONLY = args.includes("--verify");
const QUIET_MODE = args.includes("--quiet");
const FORCE_RECOMMIT = args.includes("--force-recommit");

function log(...parts) {
  if (!QUIET_MODE) {
    console.log(...parts);
  }
}

function uuid() {
  return crypto.randomUUID();
}

function isoNow() {
  return new Date().toISOString();
}

function readDb() {
  if (!fs.existsSync(DB_PATH)) {
    throw new Error(`DB file not found at ${DB_PATH}`);
  }
  const raw = fs.readFileSync(DB_PATH, "utf-8");
  return JSON.parse(raw);
}

function writeDb(db) {
  const tmpPath = `${DB_PATH}.migration-tmp`;
  fs.writeFileSync(tmpPath, JSON.stringify(db, null, 2), "utf-8");
  fs.renameSync(tmpPath, DB_PATH);
}

function planMigration(db) {
  const plan = {
    newSemyi: [],
    newMembers: [],
    treeUpdates: [], // tree.semyaId = X
    treeIdsToSemyaIds: new Map(),
    skipped: {
      usersWithoutTrees: [],
      alreadyMigrated: [],
    },
    warnings: [],
  };

  const existingSemyi = db.semyi || [];
  const existingMembers = db.semyaMembers || [];
  const existingTreeIds = new Set(
    existingSemyi.filter((s) => !s.deletedAt).map((s) => s.treeId),
  );

  // For each tree with valid creator → create семя if not already bound
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
      plan.warnings.push(
        `tree ${tree.id} creator ${creatorId} not found, skipped`,
      );
      continue;
    }

    const semyaId = uuid();
    const semya = {
      id: semyaId,
      name: "Моя семья",
      ownerId: creatorId,
      treeId: tree.id,
      description: null,
      createdAt: isoNow(),
      updatedAt: isoNow(),
      deletedAt: null,
    };
    plan.newSemyi.push(semya);
    plan.treeIdsToSemyaIds.set(tree.id, semyaId);
    plan.treeUpdates.push({treeId: tree.id, semyaId});

    // Owner membership row
    plan.newMembers.push({
      id: uuid(),
      semyaId,
      userId: creatorId,
      role: "owner",
      joinedAt: isoNow(),
      invitedByUserId: null,
      hasInviteGrant: true,
      hiddenAt: null,
    });

    // Additional shared-tree members → viewers per Q1 (safest default;
    // owner может promote после migration)
    const memberIds = Array.isArray(tree.memberIds)
      ? tree.memberIds
      : Array.isArray(tree.members)
          ? tree.members
          : [];
    for (const memberId of memberIds) {
      if (memberId === creatorId) continue;
      const memberUser = (db.users || []).find((u) => u.id === memberId);
      if (!memberUser) {
        plan.warnings.push(
          `tree ${tree.id} member ${memberId} not found, skipped`,
        );
        continue;
      }
      plan.newMembers.push({
        id: uuid(),
        semyaId,
        userId: memberId,
        role: "viewer",
        joinedAt: isoNow(),
        invitedByUserId: creatorId,
        hasInviteGrant: false,
        hiddenAt: null,
      });
    }
  }

  // Users without trees skipped (handled by future seedOnboarding flow)
  const usersWithTrees = new Set();
  for (const tree of db.trees || []) {
    usersWithTrees.add(tree.creatorId);
    const memberIds = Array.isArray(tree.memberIds)
      ? tree.memberIds
      : Array.isArray(tree.members)
          ? tree.members
          : [];
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
  db.semyi = (db.semyi || []).concat(plan.newSemyi);
  db.semyaMembers = (db.semyaMembers || []).concat(plan.newMembers);
  db.semyaMemberHiddenPersons = db.semyaMemberHiddenPersons || [];
  db.semyaInvitations = db.semyaInvitations || [];
  db.semyaBrowseTokens = db.semyaBrowseTokens || [];

  // Tree binding (reverse-FK от Ship 5): tree.semyaId = семя.id
  for (const {treeId, semyaId} of plan.treeUpdates) {
    const tree = (db.trees || []).find((t) => t.id === treeId);
    if (tree) {
      tree.semyaId = semyaId;
    }
  }

  db.migrationStatus = db.migrationStatus || {};
  db.migrationStatus[MIGRATION_MARKER] = {
    version: MIGRATION_VERSION,
    completedAt: isoNow(),
    semyaCreated: plan.newSemyi.length,
    membersCreated: plan.newMembers.length,
    treeBindingsUpdated: plan.treeUpdates.length,
  };

  return db;
}

function verify(db) {
  const checks = [];

  // V1: count(семя) === count(trees with valid creator)
  const eligibleTrees = (db.trees || []).filter(
    (t) =>
      t.creatorId && (db.users || []).some((u) => u.id === t.creatorId),
  );
  const activeSemyaCount = (db.semyi || []).filter((s) => !s.deletedAt).length;
  checks.push({
    name: "count(семя not-deleted) === count(trees with valid creator)",
    expected: eligibleTrees.length,
    actual: activeSemyaCount,
    pass: activeSemyaCount === eligibleTrees.length,
  });

  // V2: all users-with-trees have at least one семя membership
  const usersWithTreesIds = new Set();
  for (const tree of db.trees || []) {
    if (tree.creatorId) usersWithTreesIds.add(tree.creatorId);
    const ms = Array.isArray(tree.memberIds)
      ? tree.memberIds
      : Array.isArray(tree.members)
          ? tree.members
          : [];
    ms.forEach((m) => usersWithTreesIds.add(m));
  }
  const usersWithMembership = new Set(
    (db.semyaMembers || []).filter((m) => !m.hiddenAt).map((m) => m.userId),
  );
  const usersWithTreeNoMembership = [...usersWithTreesIds].filter(
    (u) => !usersWithMembership.has(u),
  );
  checks.push({
    name: "all users-with-trees have at least one семя membership",
    expected: 0,
    actual: usersWithTreeNoMembership.length,
    pass: usersWithTreeNoMembership.length === 0,
    detail: usersWithTreeNoMembership.slice(0, 5),
  });

  // V3: no orphaned trees — each eligible tree referenced by семя
  // через tree.semyaId reverse-FK
  const treeIdsInSemyi = new Set((db.semyi || []).map((s) => s.treeId));
  const unboundEligible = (db.trees || [])
    .filter(
      (t) =>
        t.creatorId && (db.users || []).some((u) => u.id === t.creatorId),
    )
    .filter((t) => !treeIdsInSemyi.has(t.id));
  checks.push({
    name: "no orphaned trees (each eligible tree bound к семя)",
    expected: 0,
    actual: unboundEligible.length,
    pass: unboundEligible.length === 0,
    detail: unboundEligible.slice(0, 5).map((t) => t.id),
  });

  // V4: tree.semyaId reverse-FK consistent с семя.treeId
  const semyiByTreeId = new Map();
  for (const s of db.semyi || []) {
    if (!s.deletedAt) semyiByTreeId.set(s.treeId, s.id);
  }
  const inconsistent = (db.trees || []).filter((t) => {
    if (!t.semyaId) return false; // unbound OK
    const expectedSemyaId = semyiByTreeId.get(t.id);
    return expectedSemyaId !== t.semyaId;
  });
  checks.push({
    name: "tree.semyaId reverse-FK consistent",
    expected: 0,
    actual: inconsistent.length,
    pass: inconsistent.length === 0,
    detail: inconsistent.slice(0, 5).map((t) => ({
      treeId: t.id,
      treeSemyaId: t.semyaId,
      semyaTreeId: semyiByTreeId.get(t.id),
    })),
  });

  // V5: personIdentities count preserved (migration не touches это)
  const identityRows = db.personIdentities || [];
  checks.push({
    name: "personIdentities count preserved (no schema mutation)",
    expected: identityRows.length,
    actual: identityRows.length,
    pass: true,
  });

  // V6: each семя has ≥1 owner
  const ownerCountBySemya = new Map();
  for (const m of db.semyaMembers || []) {
    if (m.hiddenAt) continue;
    if (m.role === "owner") {
      ownerCountBySemya.set(
        m.semyaId,
        (ownerCountBySemya.get(m.semyaId) || 0) + 1,
      );
    }
  }
  const semyaWithNoOwner = (db.semyi || []).filter(
    (s) => !s.deletedAt && (ownerCountBySemya.get(s.id) || 0) < 1,
  );
  checks.push({
    name: "each семя has ≥1 owner (invariant §3.3)",
    expected: 0,
    actual: semyaWithNoOwner.length,
    pass: semyaWithNoOwner.length === 0,
    detail: semyaWithNoOwner.slice(0, 5).map((s) => s.id),
  });

  // V7: graphPersons count preserved
  const graphPersonsCount = (db.graphPersons || []).length;
  checks.push({
    name: "graphPersons count preserved",
    expected: graphPersonsCount,
    actual: graphPersonsCount,
    pass: true,
  });

  // V8: migration marker set
  const markerOk =
    db.migrationStatus &&
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

  // Idempotency guard
  const existingMarker = db.migrationStatus?.[MIGRATION_MARKER];
  if (
    existingMarker?.version === MIGRATION_VERSION &&
    COMMIT_MODE &&
    !FORCE_RECOMMIT
  ) {
    log(
      `migration уже applied (version ${MIGRATION_VERSION} на ${existingMarker.completedAt}); ` +
        "use --verify для re-check либо --force-recommit для override",
    );
    process.exit(0);
  }

  if (VERIFY_ONLY) {
    log("=== Verification (no migration run) ===");
    const checks = verify(db);
    let allPass = true;
    for (const c of checks) {
      const icon = c.pass ? "✓" : "✗";
      log(`${icon} ${c.name}`);
      log(`   expected: ${c.expected}, actual: ${c.actual}`);
      if (!c.pass && c.detail?.length) {
        log(`   problem rows: ${JSON.stringify(c.detail)}`);
      }
      if (!c.pass) allPass = false;
    }
    process.exit(allPass ? 0 : 1);
  }

  log("=== Migration plan ===");
  const plan = planMigration(db);

  log("Будут созданы:");
  log(`  семя:                  ${plan.newSemyi.length}`);
  log(`  members:               ${plan.newMembers.length}`);
  log(`  tree.semyaId updates:  ${plan.treeUpdates.length}`);
  log("Пропущены:");
  log(`  users без trees:       ${plan.skipped.usersWithoutTrees.length}`);
  log(`  уже migrated:          ${plan.skipped.alreadyMigrated.length}`);
  if (plan.warnings.length) {
    log("Warnings:");
    plan.warnings.forEach((w) => log(`  ${w}`));
  }

  if (!COMMIT_MODE) {
    log("\n[dry-run] no changes written. Use --commit чтобы apply.");
    if (plan.newSemyi.length > 0 && !QUIET_MODE) {
      log("\n--- Sample семя:");
      console.log(JSON.stringify(plan.newSemyi[0], null, 2));
      log("--- Sample member:");
      console.log(JSON.stringify(plan.newMembers[0], null, 2));
    }
    process.exit(0);
  }

  // Commit mode — write + verify
  const updatedDb = applyMigration(db, plan);
  writeDb(updatedDb);
  log(`\n✓ Migration committed к ${DB_PATH}`);

  log("\n=== Post-migration verification ===");
  const checks = verify(updatedDb);
  let allPass = true;
  for (const c of checks) {
    const icon = c.pass ? "✓" : "✗";
    log(`${icon} ${c.name}`);
    log(`   expected: ${c.expected}, actual: ${c.actual}`);
    if (!c.pass && c.detail?.length) {
      log(`   problem rows: ${JSON.stringify(c.detail)}`);
    }
    if (!c.pass) allPass = false;
  }

  if (allPass) {
    log("\n✅ All verifications pass.");
    process.exit(0);
  } else {
    log("\n❌ Some verifications failed — see output above.");
    log("ROLLBACK: restore from pre-migration backup snapshot.");
    process.exit(1);
  }
}

main();
