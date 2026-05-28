// Profile Phase 1b (2026-05-28): migrate-profile-articles.js tests.
//
// Drives the CLI script as a subprocess against a temp dev-db.json
// (RODNYA_DB_PATH). Asserts: dry-run writes nothing, --commit seeds one
// EMPTY article per person (no stub — Q1), semyaId resolves from the
// person's tree, and re-run is idempotent.

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const fsp = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");
const {execFileSync} = require("node:child_process");

const SCRIPT = path.resolve(
  __dirname,
  "../scripts/migrate-profile-articles.js",
);

function fixtureDb() {
  return {
    users: [],
    trees: [
      {id: "t-1", semyaId: "s-1"},
      {id: "t-2"}, // standalone (no семья)
    ],
    semyi: [{id: "s-1", deletedAt: null}],
    persons: [
      {id: "p-1", treeId: "t-1", name: "Лидия"},
      {id: "p-2", treeId: "t-1", name: "Пётр"},
      {id: "p-3", treeId: "t-2", name: "Одиночка"},
    ],
    profileArticles: [],
    migrationStatus: {},
  };
}

async function withTempDb(fn) {
  const tempDir = await fsp.mkdtemp(path.join(os.tmpdir(), "rodnya-art-mig-"));
  const dbPath = path.join(tempDir, "dev-db.json");
  fs.writeFileSync(dbPath, JSON.stringify(fixtureDb(), null, 2), "utf-8");
  try {
    await fn(dbPath);
  } finally {
    await fsp.rm(tempDir, {recursive: true, force: true});
  }
}

function runMigration(dbPath, args = []) {
  return execFileSync(process.execPath, [SCRIPT, ...args], {
    env: {...process.env, RODNYA_DB_PATH: dbPath},
    encoding: "utf-8",
  });
}

function readDb(dbPath) {
  return JSON.parse(fs.readFileSync(dbPath, "utf-8"));
}

test("dry-run writes nothing", async () => {
  await withTempDb(async (dbPath) => {
    runMigration(dbPath); // no --commit
    const db = readDb(dbPath);
    assert.equal(db.profileArticles.length, 0);
    assert.equal(db.migrationStatus.profileArticles, undefined);
  });
});

test("--commit seeds one empty article per person", async () => {
  await withTempDb(async (dbPath) => {
    runMigration(dbPath, ["--commit", "--quiet"]);
    const db = readDb(dbPath);

    assert.equal(db.profileArticles.length, 3);
    // Every person has exactly one article, all empty (Q1 — no stub).
    for (const personId of ["p-1", "p-2", "p-3"]) {
      const rows = db.profileArticles.filter((a) => a.personId === personId);
      assert.equal(rows.length, 1, `one article for ${personId}`);
      assert.deepEqual(rows[0].blocks, []);
    }
    // semyaId resolved from the person's tree.
    const a1 = db.profileArticles.find((a) => a.personId === "p-1");
    assert.equal(a1.semyaId, "s-1");
    assert.equal(a1.treeId, "t-1");
    // Standalone-tree person → semyaId null.
    const a3 = db.profileArticles.find((a) => a.personId === "p-3");
    assert.equal(a3.semyaId, null);
    // Marker set.
    assert.equal(db.migrationStatus.profileArticles.version, "empty-v1");
    assert.equal(db.migrationStatus.profileArticles.articlesCreated, 3);
  });
});

test("re-run --commit is idempotent (creates nothing new)", async () => {
  await withTempDb(async (dbPath) => {
    runMigration(dbPath, ["--commit", "--quiet"]);
    const afterFirst = readDb(dbPath).profileArticles.length;
    // Marker guard short-circuits a second --commit.
    runMigration(dbPath, ["--commit", "--quiet"]);
    const afterSecond = readDb(dbPath).profileArticles.length;
    assert.equal(afterFirst, 3);
    assert.equal(afterSecond, 3);
  });
});

test("existing authored articles preserved on re-run", async () => {
  await withTempDb(async (dbPath) => {
    // Pre-seed p-1 with an authored article (simulate real use before a
    // forced re-run). Migration must not touch it.
    const db = readDb(dbPath);
    db.profileArticles.push({
      id: "art-existing",
      personId: "p-1",
      treeId: "t-1",
      semyaId: "s-1",
      blocks: [{id: "b-1", type: "paragraph", content: {spans: [{text: "Hi"}]}}],
      createdAt: "2026-05-28T00:00:00.000Z",
      updatedAt: "2026-05-28T00:00:00.000Z",
    });
    fs.writeFileSync(dbPath, JSON.stringify(db, null, 2), "utf-8");

    runMigration(dbPath, ["--commit", "--quiet"]);
    const after = readDb(dbPath);
    // p-1 keeps its authored article (not duplicated, not wiped).
    const p1Articles = after.profileArticles.filter((a) => a.personId === "p-1");
    assert.equal(p1Articles.length, 1);
    assert.equal(p1Articles[0].id, "art-existing");
    assert.equal(p1Articles[0].blocks.length, 1);
    // p-2 + p-3 got fresh empty articles.
    assert.equal(after.profileArticles.length, 3);
  });
});
