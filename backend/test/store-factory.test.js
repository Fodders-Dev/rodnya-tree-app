const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const {newDb} = require("pg-mem");

const {createStore} = require("../src/store-factory");

test("createStore creates file-backed store by default", async () => {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "lineage-store-"));
  const dataPath = path.join(tempDir, "dev-db.json");

  const store = await createStore({
    dataPath,
    storageBackend: "file",
  });

  assert.equal(store.storageMode, "file-store");
  await assert.doesNotReject(fs.access(dataPath));
});

test("createStore creates postgres-backed store when pg config is provided", async () => {
  const db = newDb();
  const {Pool} = db.adapters.createPg();
  const pool = new Pool();
  const store = await createStore({
    storageBackend: "postgres",
    postgresUrl: "postgresql://unused/lineage",
    postgresSchema: "public",
    postgresStateTable: "lineage_state",
    postgresStateRowId: "default",
    _pool: pool,
  });

  try {
    assert.equal(store.storageMode, "postgres");
    const snapshot = await store._read();
    assert.ok(Array.isArray(snapshot.users));
    await store._write({
      ...snapshot,
      users: [{id: "u-1", email: "pg@lineage.app"}],
    });
    const updated = await store._read();
    assert.equal(updated.users.length, 1);
    assert.equal(updated.users[0].id, "u-1");
  } finally {
    await store.close();
  }
});
