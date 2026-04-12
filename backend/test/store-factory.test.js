const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");

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

test("createStore rejects postgres until adapter is implemented", async () => {
  await assert.rejects(
    () => createStore({storageBackend: "postgres", dataPath: "unused.json"}),
    /not implemented yet/i,
  );
});
