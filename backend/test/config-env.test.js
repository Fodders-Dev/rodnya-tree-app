const test = require("node:test");
const assert = require("node:assert/strict");
const path = require("node:path");

const {createConfig} = require("../src/config");

test("createConfig reads postgres pool max from env", () => {
  const previous = process.env.RODNYA_POSTGRES_POOL_MAX;
  process.env.RODNYA_POSTGRES_POOL_MAX = "3";

  try {
    const config = createConfig();
    assert.equal(config.postgresPoolMax, 3);
  } finally {
    if (previous == null) {
      delete process.env.RODNYA_POSTGRES_POOL_MAX;
    } else {
      process.env.RODNYA_POSTGRES_POOL_MAX = previous;
    }
  }
});

test("createConfig derives postgres snapshot cache path from the backend data path", () => {
  const previousDataPath = process.env.RODNYA_BACKEND_DATA_PATH;
  const previousSnapshotCachePath = process.env.RODNYA_POSTGRES_SNAPSHOT_CACHE_PATH;
  process.env.RODNYA_BACKEND_DATA_PATH = "/srv/rodnya/state/dev-db.json";
  delete process.env.RODNYA_POSTGRES_SNAPSHOT_CACHE_PATH;

  try {
    const config = createConfig();
    assert.equal(
      config.postgresSnapshotCachePath,
      path.join(
        path.dirname(process.env.RODNYA_BACKEND_DATA_PATH),
        "postgres-state-cache.json",
      ),
    );
  } finally {
    if (previousDataPath == null) {
      delete process.env.RODNYA_BACKEND_DATA_PATH;
    } else {
      process.env.RODNYA_BACKEND_DATA_PATH = previousDataPath;
    }
    if (previousSnapshotCachePath == null) {
      delete process.env.RODNYA_POSTGRES_SNAPSHOT_CACHE_PATH;
    } else {
      process.env.RODNYA_POSTGRES_SNAPSHOT_CACHE_PATH = previousSnapshotCachePath;
    }
  }
});
