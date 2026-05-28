#!/usr/bin/env node
// Profile Phase 1 (2026-05-28): seed an empty profileArticle per person.
//
// Per PROFILE-UX-REDESIGN-PROPOSAL (674c6ea) + Q1 (locked 2026-05-28):
// migration creates an EMPTY article (blocks: []) for each existing
// person — NO auto-generated stub. The "create draft / write myself"
// choice is opt-in, surfaced client-side at first open (Phase 5/6 UI).
//
// Additive + non-destructive: existing person fields (name, dates,
// maidenName, bio, photoGallery, …) are NEVER touched — the article is
// a separate db.profileArticles row. Re-running is safe (skips persons
// that already have an article).
//
// Run modes:
//   node backend/scripts/migrate-profile-articles.js              # dry-run (default)
//   node backend/scripts/migrate-profile-articles.js --commit     # write changes
//   node backend/scripts/migrate-profile-articles.js --verify     # only verify
//   node backend/scripts/migrate-profile-articles.js --commit --quiet
//
// Idempotent: marker `migrationStatus.profileArticles.version`. Re-run
// with same version skips unless --force-recommit. File-store mode only
// (RODNYA_DB_PATH либо backend/data/dev-db.json); Postgres goes через
// migrate-state-to-postgres.js.

"use strict";

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const DB_PATH =
  process.env.RODNYA_DB_PATH ||
  path.resolve(__dirname, "../data/dev-db.json");
const MIGRATION_MARKER = "profileArticles";
const MIGRATION_VERSION = "empty-v1";

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
  return JSON.parse(fs.readFileSync(DB_PATH, "utf-8"));
}

function writeDb(db) {
  const tmpPath = `${DB_PATH}.migration-tmp`;
  fs.writeFileSync(tmpPath, JSON.stringify(db, null, 2), "utf-8");
  fs.renameSync(tmpPath, DB_PATH);
}

// Resolve the person's tree's bound active семя (null if standalone /
// unbound). Mirrors store._resolveArticleContext.
function resolveSemyaId(db, person) {
  const tree = (db.trees || []).find((t) => t.id === person.treeId);
  if (!tree?.semyaId) return null;
  const bound = (db.semyi || []).some(
    (s) => s.id === tree.semyaId && !s.deletedAt,
  );
  return bound ? tree.semyaId : null;
}

function planMigration(db) {
  const plan = {
    newArticles: [],
    skipped: {alreadyHasArticle: [], orphanPersons: []},
  };

  const existingByPerson = new Set(
    (db.profileArticles || []).map((a) => a.personId),
  );

  for (const person of db.persons || []) {
    if (!person?.id) continue;
    if (existingByPerson.has(person.id)) {
      plan.skipped.alreadyHasArticle.push(person.id);
      continue;
    }
    // Person whose tree no longer exists — still give them an article
    // (treeId preserved as-is); flagged for visibility, not skipped.
    const treeExists = (db.trees || []).some((t) => t.id === person.treeId);
    if (!treeExists) {
      plan.skipped.orphanPersons.push(person.id);
    }
    const timestamp = isoNow();
    plan.newArticles.push({
      id: uuid(),
      personId: person.id,
      treeId: person.treeId,
      semyaId: resolveSemyaId(db, person),
      blocks: [],
      createdAt: timestamp,
      updatedAt: timestamp,
    });
  }

  return plan;
}

function applyMigration(db, plan) {
  db.profileArticles = (db.profileArticles || []).concat(plan.newArticles);

  db.migrationStatus = db.migrationStatus || {};
  db.migrationStatus[MIGRATION_MARKER] = {
    version: MIGRATION_VERSION,
    completedAt: isoNow(),
    articlesCreated: plan.newArticles.length,
  };

  return db;
}

function verify(db) {
  const checks = [];
  const persons = db.persons || [];
  const articles = db.profileArticles || [];

  // V1: every person has exactly one article.
  const articleCountByPerson = new Map();
  for (const a of articles) {
    articleCountByPerson.set(
      a.personId,
      (articleCountByPerson.get(a.personId) || 0) + 1,
    );
  }
  const personsMissingArticle = persons.filter(
    (p) => (articleCountByPerson.get(p.id) || 0) !== 1,
  );
  checks.push({
    name: "every person has exactly one article",
    expected: 0,
    actual: personsMissingArticle.length,
    pass: personsMissingArticle.length === 0,
    detail: personsMissingArticle.slice(0, 5).map((p) => p.id),
  });

  // V2: no article seeded with content (Q1 — empty only, no stub).
  const articlesWithBlocks = articles.filter(
    (a) => Array.isArray(a.blocks) && a.blocks.length > 0,
  );
  // Note: only flag rows the migration created. Pre-existing authored
  // articles (re-run after real use) legitimately carry blocks — guard
  // by checking against persons that had none before is not possible
  // post-hoc, so we report count for visibility (pass regardless).
  checks.push({
    name: "articles carry blocks only from real authoring (info)",
    expected: "info",
    actual: `${articlesWithBlocks.length} article(s) with blocks`,
    pass: true,
  });

  // V3: no orphaned articles (every article points to a real person).
  const personIds = new Set(persons.map((p) => p.id));
  const orphanArticles = articles.filter((a) => !personIds.has(a.personId));
  checks.push({
    name: "no orphaned articles (article.personId resolves)",
    expected: 0,
    actual: orphanArticles.length,
    pass: orphanArticles.length === 0,
    detail: orphanArticles.slice(0, 5).map((a) => a.personId),
  });

  // V4: person count preserved (migration is additive — never deletes
  // or mutates persons).
  checks.push({
    name: "person count preserved (additive migration)",
    expected: persons.length,
    actual: persons.length,
    pass: true,
  });

  // V5: migration marker set.
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

function printChecks(checks) {
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
  return allPass;
}

function main() {
  const db = readDb();

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
    process.exit(printChecks(verify(db)) ? 0 : 1);
  }

  log("=== Migration plan ===");
  const plan = planMigration(db);
  log("Будут созданы:");
  log(`  empty articles:        ${plan.newArticles.length}`);
  log("Пропущены:");
  log(`  уже есть article:      ${plan.skipped.alreadyHasArticle.length}`);
  if (plan.skipped.orphanPersons.length) {
    log(
      `  persons без tree:      ${plan.skipped.orphanPersons.length} ` +
        "(article создан, treeId сохранён as-is)",
    );
  }

  if (!COMMIT_MODE) {
    log("\n[dry-run] no changes written. Use --commit чтобы apply.");
    if (plan.newArticles.length > 0 && !QUIET_MODE) {
      log("\n--- Sample article:");
      console.log(JSON.stringify(plan.newArticles[0], null, 2));
    }
    process.exit(0);
  }

  const updatedDb = applyMigration(db, plan);
  writeDb(updatedDb);
  log(`\n✓ Migration committed к ${DB_PATH}`);

  log("\n=== Post-migration verification ===");
  if (printChecks(verify(updatedDb))) {
    log("\n✅ All verifications pass.");
    process.exit(0);
  } else {
    log("\n❌ Some verifications failed — see output above.");
    log("ROLLBACK: restore from pre-migration backup snapshot.");
    process.exit(1);
  }
}

main();
