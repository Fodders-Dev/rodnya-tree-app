#!/usr/bin/env node
//
// Phase 3.1 migration dry-run.
//
// Reads the JSONB snapshot at the configured data path (or
// --source=<path>), runs `backfillPersonIdentities` then
// `migrateTreesToGraphAndBranches` against an in-memory copy, and
// prints a before/after diff. Original snapshot file is not touched.
//
// Use this on a copy of production data BEFORE flipping the
// cluster — Phase 3.1 rebuilds graphPersons from per-field
// highest-completeness logic and writes migration-time conflicts
// into `identityFieldConflicts`. The pre-flight count check
// throws when graphPersons / branches / graphRelations counts
// drift from expectations; abort-on-throw means we never write a
// half-migrated snapshot to disk.
//
// Usage:
//   node scripts/dry-run-phase31-migration.js \
//     [--source=path/to/db.json] [--verbose]

const fs = require("node:fs/promises");
const path = require("node:path");

const {normalizeDbState} = require("../src/store");
const {
  backfillPersonIdentities,
  formatSnapshotSummary,
  migrateTreesToGraphAndBranches,
  summarizeSnapshot,
} = require("../src/migration-utils");

function parseArgs(argv) {
  const result = {source: "", verbose: false};
  for (const arg of argv) {
    if (arg === "--verbose") result.verbose = true;
    else if (arg.startsWith("--source=")) {
      result.source = arg.slice("--source=".length);
    }
  }
  return result;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const sourcePath = path.resolve(
    args.source ||
      path.join(__dirname, "..", "data", "dev-db.json"),
  );

  const raw = await fs.readFile(sourcePath, "utf8");
  const parsed = JSON.parse(raw);
  const normalized = normalizeDbState(parsed);

  const beforeSummary = summarizeSnapshot(normalized);
  const beforeLedger = normalized.migrationStatus?.treesToGraph || "(none)";
  const beforeMigrationConflicts = (
    normalized.identityFieldConflicts || []
  ).filter((entry) => entry?.origin === "migration").length;
  const beforeRuntimeConflicts = (
    normalized.identityFieldConflicts || []
  ).filter((entry) => entry?.origin !== "migration").length;

  console.log(`Dry-run source: ${sourcePath}`);
  console.log(`Before ledger: ${beforeLedger}`);
  console.log(`Before counts: ${formatSnapshotSummary(beforeSummary)}`);
  console.log(
    `Before identityFieldConflicts: migration=${beforeMigrationConflicts}, runtime=${beforeRuntimeConflicts}`,
  );

  const identityRun = backfillPersonIdentities(normalized);
  if (identityRun.changed) {
    console.log(
      `backfillPersonIdentities: createdCount=${identityRun.createdCount}, linkedPersonCount=${identityRun.linkedPersonCount}`,
    );
  }

  let migrationResult;
  try {
    migrationResult = migrateTreesToGraphAndBranches(normalized);
  } catch (error) {
    console.error("\n❌ Migration aborted by pre-flight check:");
    console.error(`   ${error.message}`);
    console.error(
      "   No write would have happened. Investigate the snapshot and re-run.",
    );
    process.exitCode = 2;
    return;
  }

  const afterSummary = summarizeSnapshot(normalized);
  const afterLedger = normalized.migrationStatus?.treesToGraph || "(unset)";
  const afterMigrationConflicts = (
    normalized.identityFieldConflicts || []
  ).filter((entry) => entry?.origin === "migration").length;
  const afterRuntimeConflicts = (
    normalized.identityFieldConflicts || []
  ).filter((entry) => entry?.origin !== "migration").length;

  console.log(`\nAfter ledger: ${afterLedger}`);
  console.log(`After counts: ${formatSnapshotSummary(afterSummary)}`);
  console.log(
    `After identityFieldConflicts: migration=${afterMigrationConflicts}, runtime=${afterRuntimeConflicts}`,
  );

  if (migrationResult?.changed) {
    console.log(
      `\nMigration summary: ${JSON.stringify(migrationResult.summary, null, 2)}`,
    );
  } else {
    console.log("\nMigration was a no-op (ledger already complete-v2).");
  }

  // Sanity diffs — tracking the things that should change vs.
  // things that must NOT.
  const dropped = [];
  for (const key of [
    "users",
    "trees",
    "persons",
    "relations",
    "personIdentities",
    "treeInvitations",
    "relationRequests",
  ]) {
    const before = beforeSummary[key] || 0;
    const after = afterSummary[key] || 0;
    if (before !== after) {
      dropped.push(`${key}: ${before} → ${after}`);
    }
  }
  if (dropped.length > 0) {
    console.error(
      "\n❌ Legacy collection counts changed — migration must NOT mutate legacy rows:",
    );
    for (const entry of dropped) console.error(`   ${entry}`);
    process.exitCode = 3;
    return;
  }

  // Runtime conflicts must survive a v1→v2 rerun.
  if (afterRuntimeConflicts !== beforeRuntimeConflicts) {
    console.error(
      `\n❌ Runtime identityFieldConflicts changed (${beforeRuntimeConflicts} → ${afterRuntimeConflicts}). Phase 1.3 user-resolved state must survive migration.`,
    );
    process.exitCode = 4;
    return;
  }

  if (args.verbose && Array.isArray(normalized.graphPersons)) {
    console.log(
      `\nFirst 3 graphPersons after migration:\n${JSON.stringify(
        normalized.graphPersons.slice(0, 3),
        null,
        2,
      )}`,
    );
  }

  console.log("\n✓ Dry-run completed without writing.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
