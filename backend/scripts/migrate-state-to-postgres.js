#!/usr/bin/env node

const fs = require("node:fs/promises");
const path = require("node:path");

const {createConfig} = require("../src/config");
const {PostgresStore} = require("../src/postgres-store");
const {normalizeDbState} = require("../src/store");
const {
  formatSnapshotSummary,
  hashSnapshot,
  summarizeSnapshot,
} = require("../src/migration-utils");

function parseArgs(argv) {
  const result = {
    dryRun: false,
    source: "",
  };

  for (const argument of argv) {
    if (argument === "--dry-run") {
      result.dryRun = true;
      continue;
    }
    if (argument.startsWith("--source=")) {
      result.source = argument.slice("--source=".length);
    }
  }

  return result;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const config = createConfig();
  const sourcePath = path.resolve(
    args.source || config.dataPath || path.join(__dirname, "..", "data", "dev-db.json"),
  );

  const rawSource = await fs.readFile(sourcePath, "utf8");
  const snapshot = normalizeDbState(JSON.parse(rawSource));
  const sourceSummary = summarizeSnapshot(snapshot);
  const sourceHash = hashSnapshot(snapshot);

  console.log(`[state-migration] source: ${sourcePath}`);
  console.log(`[state-migration] source summary: ${formatSnapshotSummary(sourceSummary)}`);
  console.log(`[state-migration] source hash: ${sourceHash}`);

  if (args.dryRun) {
    console.log("[state-migration] dry-run complete, postgres write skipped");
    return;
  }

  const store = new PostgresStore({
    connectionString: config.postgresUrl,
    schema: config.postgresSchema,
    table: config.postgresStateTable,
    rowId: config.postgresStateRowId,
  });

  try {
    await store.initialize();
    await store._write(snapshot);
    const writtenSnapshot = await store._read();
    const writtenSummary = summarizeSnapshot(writtenSnapshot);
    const writtenHash = hashSnapshot(writtenSnapshot);

    console.log(
      `[state-migration] target summary: ${formatSnapshotSummary(writtenSummary)}`,
    );
    console.log(`[state-migration] target hash: ${writtenHash}`);

    if (writtenHash !== sourceHash) {
      throw new Error(
        "PostgreSQL snapshot verification failed: source and target hashes differ",
      );
    }

    console.log("[state-migration] PostgreSQL snapshot migration completed");
  } finally {
    await store.close();
  }
}

main().catch((error) => {
  console.error("[state-migration] failed:", error);
  process.exitCode = 1;
});
