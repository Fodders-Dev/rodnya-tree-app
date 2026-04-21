const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const {newDb} = require("pg-mem");

const {createStore} = require("../src/store-factory");

test("createStore creates file-backed store by default", async () => {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-store-"));
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
    postgresUrl: "postgresql://unused/rodnya",
    postgresSchema: "public",
    postgresStateTable: "rodnya_state",
    postgresStateRowId: "default",
    _pool: pool,
  });

  try {
    assert.equal(store.storageMode, "postgres");
    const snapshot = await store._read();
    assert.ok(Array.isArray(snapshot.users));
    await store._write({
      ...snapshot,
      users: [{id: "u-1", email: "pg@rodnya.app"}],
    });
    const updated = await store._read();
    assert.equal(updated.users.length, 1);
    assert.equal(updated.users[0].id, "u-1");
  } finally {
    await store.close();
  }
});

test("touchSession throttles repeated writes for hot auth traffic", async () => {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-session-"));
  const dataPath = path.join(tempDir, "dev-db.json");

  const store = await createStore({
    dataPath,
    storageBackend: "file",
  });

  const sessionTokens = await store.createSession("user-1");
  const initialSession = await store.findSession(sessionTokens.token);
  assert.ok(initialSession);

  const untouchedSession = await store.touchSession(sessionTokens.token);
  assert.ok(untouchedSession);
  assert.equal(untouchedSession.lastSeenAt, initialSession.lastSeenAt);
  const unchangedSession = await store.findSession(sessionTokens.token);
  assert.equal(unchangedSession.lastSeenAt, initialSession.lastSeenAt);

  const dbSnapshot = await store._read();
  const storedSession = dbSnapshot.sessions.find(
    (entry) => entry.token === sessionTokens.token,
  );
  storedSession.lastSeenAt = "2020-01-01T00:00:00.000Z";
  await store._write(dbSnapshot);
  store._sessionTouchCache.clear();

  const refreshedSession = await store.touchSession(sessionTokens.token);
  assert.notEqual(refreshedSession.lastSeenAt, "2020-01-01T00:00:00.000Z");

  const repeatedTouch = await store.touchSession(sessionTokens.token);
  assert.equal(repeatedTouch, null);
  const repeatedSessionSnapshot = await store.findSession(sessionTokens.token);
  assert.equal(repeatedSessionSnapshot.lastSeenAt, refreshedSession.lastSeenAt);
});

test("touchSession collapses parallel touches for the same token into one write", async () => {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-session-"));
  const dataPath = path.join(tempDir, "dev-db.json");

  const store = await createStore({
    dataPath,
    storageBackend: "file",
  });

  const sessionTokens = await store.createSession("user-1");
  const dbSnapshot = await store._read();
  const storedSession = dbSnapshot.sessions.find(
    (entry) => entry.token === sessionTokens.token,
  );
  storedSession.lastSeenAt = "2020-01-01T00:00:00.000Z";
  await store._write(dbSnapshot);
  store._sessionTouchCache.clear();

  let writeCount = 0;
  const originalWrite = store._write.bind(store);
  store._write = async (data) => {
    writeCount += 1;
    return originalWrite(data);
  };

  await Promise.all(
    Array.from({length: 5}, () => store.touchSession(sessionTokens.token)),
  );

  assert.equal(writeCount, 1);
});
