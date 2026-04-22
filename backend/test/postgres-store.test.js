const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");

const {PostgresStore} = require("../src/postgres-store");

test("PostgresStore recovers from a failed write without poisoning the queue", async () => {
  let state = {users: []};
  let writeAttempts = 0;
  const pool = {
    async query(sql, params = []) {
      if (sql.includes("CREATE SCHEMA")) {
        return {rows: []};
      }
      if (sql.includes("CREATE TABLE")) {
        return {rows: []};
      }
      if (sql.includes("ON CONFLICT (id) DO NOTHING")) {
        return {rows: []};
      }
      if (sql.includes("SELECT data")) {
        return {rows: [{data: state}]};
      }
      if (sql.includes("ON CONFLICT (id) DO UPDATE")) {
        writeAttempts += 1;
        if (writeAttempts === 1) {
          throw new Error("write_failed_once");
        }
        state = JSON.parse(params[1]);
        return {rows: []};
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  const store = new PostgresStore({
    connectionString: "postgresql://unused/rodnya",
    pool,
  });

  await store.initialize();
  await assert.rejects(
    store._write({users: [{id: "u-1"}]}),
    /write_failed_once/,
  );

  await assert.doesNotReject(store._read());
  await assert.doesNotReject(store._write({users: [{id: "u-2"}]}));

  const snapshot = await store._read();
  assert.deepEqual(snapshot.users, [{id: "u-2"}]);
});

test("PostgresStore serves cached snapshot when the write queue is stuck", async () => {
  let selectCalls = 0;
  const pool = {
    async query(sql) {
      if (
        sql.includes("CREATE SCHEMA") ||
        sql.includes("CREATE TABLE") ||
        sql.includes("ON CONFLICT (id) DO NOTHING")
      ) {
        return {rows: []};
      }
      if (sql.includes("SELECT data")) {
        selectCalls += 1;
        return {rows: [{data: {users: []}}]};
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  const store = new PostgresStore({
    connectionString: "postgresql://unused/rodnya",
    pool,
    queryTimeoutMs: 25,
  });

  await store.initialize();
  const firstSnapshot = await store._read();
  assert.deepEqual(firstSnapshot.users, []);
  store._writeQueue = new Promise(() => {});

  const secondSnapshot = await store._read();

  assert.deepEqual(secondSnapshot.users, []);
  assert.equal(selectCalls, 1);
});

test("PostgresStore still fails when the write queue is stuck before any snapshot is cached", async () => {
  const pool = {
    async query(sql) {
      if (
        sql.includes("CREATE SCHEMA") ||
        sql.includes("CREATE TABLE") ||
        sql.includes("ON CONFLICT (id) DO NOTHING")
      ) {
        return {rows: []};
      }
      if (sql.includes("SELECT data")) {
        return {rows: [{data: {users: []}}]};
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  const store = new PostgresStore({
    connectionString: "postgresql://unused/rodnya",
    pool,
    queryTimeoutMs: 25,
  });

  await store.initialize();
  store._writeQueue = new Promise(() => {});

  await assert.rejects(store._read(), (error) => {
    assert.equal(error?.code, "POSTGRES_WRITE_QUEUE_TIMEOUT");
    return true;
  });
});

test("PostgresStore reuses cached snapshot after the first successful read", async () => {
  let selectCalls = 0;
  const pool = {
    async query(sql) {
      if (
        sql.includes("CREATE SCHEMA") ||
        sql.includes("CREATE TABLE") ||
        sql.includes("ON CONFLICT (id) DO NOTHING")
      ) {
        return {rows: []};
      }
      if (sql.includes("SELECT data")) {
        selectCalls += 1;
        return {
          rows: [
            {
              data: {
                users: [{id: "u-1"}],
              },
            },
          ],
        };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  const store = new PostgresStore({
    connectionString: "postgresql://unused/rodnya",
    pool,
  });

  await store.initialize();
  const firstSnapshot = await store._read();
  const secondSnapshot = await store._read();

  assert.deepEqual(firstSnapshot.users, [{id: "u-1"}]);
  assert.deepEqual(secondSnapshot.users, [{id: "u-1"}]);
  assert.equal(selectCalls, 1);
});

test("PostgresStore retries a timed out read before failing", async () => {
  let selectCalls = 0;
  const pool = {
    async query(sql) {
      if (
        sql.includes("CREATE SCHEMA") ||
        sql.includes("CREATE TABLE") ||
        sql.includes("ON CONFLICT (id) DO NOTHING")
      ) {
        return {rows: []};
      }
      if (sql.includes("SELECT data")) {
        selectCalls += 1;
        if (selectCalls === 1) {
          throw new Error("Query read timeout");
        }
        return {
          rows: [
            {
              data: {
                sessions: [{token: "token-1"}],
              },
            },
          ],
        };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  const store = new PostgresStore({
    connectionString: "postgresql://unused/rodnya",
    pool,
    readRetryDelayMs: 0,
  });

  await store.initialize();
  const snapshot = await store._read();

  assert.deepEqual(snapshot.sessions, [{token: "token-1"}]);
  assert.equal(selectCalls, 2);
});

test("PostgresStore treats connection timeout reads as retriable", async () => {
  let selectCalls = 0;
  const pool = {
    async query(sql) {
      if (
        sql.includes("CREATE SCHEMA") ||
        sql.includes("CREATE TABLE") ||
        sql.includes("ON CONFLICT (id) DO NOTHING")
      ) {
        return {rows: []};
      }
      if (sql.includes("SELECT data")) {
        selectCalls += 1;
        if (selectCalls === 1) {
          throw new Error("Connection terminated due to connection timeout");
        }
        return {
          rows: [
            {
              data: {
                chats: [{id: "chat-1"}],
              },
            },
          ],
        };
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  const store = new PostgresStore({
    connectionString: "postgresql://unused/rodnya",
    pool,
    readRetryDelayMs: 0,
  });

  await store.initialize();
  const snapshot = await store._read();

  assert.deepEqual(snapshot.chats, [{id: "chat-1"}]);
  assert.equal(selectCalls, 2);
});

test("PostgresStore applies write timeout per query instead of relying on pool defaults", async () => {
  const queryCalls = [];
  const pool = {
    connect: async () => ({
      query: async () => ({rows: []}),
      release: () => {},
    }),
    async query(config) {
      queryCalls.push(config);
      if (config.text.includes("SELECT data")) {
        return {rows: [{data: {users: []}}]};
      }
      return {rows: []};
    },
  };

  const store = new PostgresStore({
    connectionString: "postgresql://unused/rodnya",
    pool,
    queryTimeoutMs: 1234,
  });

  await store.initialize();
  await store._write({users: [{id: "u-1"}]});

  const bootstrapAndWriteCalls = queryCalls.filter(
    (config) =>
      typeof config?.text === "string" &&
      !config.text.includes("SELECT data"),
  );

  assert.ok(bootstrapAndWriteCalls.length >= 3);
  for (const config of bootstrapAndWriteCalls) {
    assert.equal(config.query_timeout, 1234);
  }
});

test("PostgresStore exposes a lightweight health check", async () => {
  const queryCalls = [];
  const pool = {
    async query(sql) {
      queryCalls.push(sql);
      if (
        sql.includes("CREATE SCHEMA") ||
        sql.includes("CREATE TABLE") ||
        sql.includes("ON CONFLICT (id) DO NOTHING") ||
        sql === "SELECT 1"
      ) {
        return {rows: []};
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  const store = new PostgresStore({
    connectionString: "postgresql://unused/rodnya",
    pool,
  });

  await store.healthCheck();

  assert.ok(queryCalls.includes("SELECT 1"));
  assert.equal(
    queryCalls.filter((sql) => sql.includes("SELECT data")).length,
    0,
  );
});

test("PostgresStore persists snapshot cache after successful write", async () => {
  const cacheDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-pg-cache-"));
  const snapshotCachePath = path.join(cacheDir, "state-cache.json");
  let state = {users: []};
  const pool = {
    async query(sql, params = []) {
      if (sql.includes("CREATE SCHEMA")) {
        return {rows: []};
      }
      if (sql.includes("CREATE TABLE")) {
        return {rows: []};
      }
      if (sql.includes("ON CONFLICT (id) DO NOTHING")) {
        return {rows: []};
      }
      if (sql.includes("SELECT data")) {
        return {rows: [{data: state}]};
      }
      if (sql.includes("ON CONFLICT (id) DO UPDATE")) {
        state = JSON.parse(params[1]);
        return {rows: []};
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  try {
    const store = new PostgresStore({
      connectionString: "postgresql://unused/rodnya",
      pool,
      snapshotCachePath,
    });

    await store.initialize();
    await store._write({users: [{id: "u-7"}]});

    const persistedSnapshot = JSON.parse(
      await fs.readFile(snapshotCachePath, "utf8"),
    );
    assert.deepEqual(persistedSnapshot.users, [{id: "u-7"}]);
  } finally {
    await fs.rm(cacheDir, {recursive: true, force: true});
  }
});

test("PostgresStore hydrates cached snapshot from the sidecar file after restart", async () => {
  const cacheDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-pg-cache-"));
  const snapshotCachePath = path.join(cacheDir, "state-cache.json");
  const persistedSnapshot = {
    chats: [{id: "chat-1"}],
    messages: [{id: "msg-1", chatId: "chat-1"}],
  };

  const pool = {
    async query(sql) {
      if (
        sql.includes("CREATE SCHEMA") ||
        sql.includes("CREATE TABLE") ||
        sql.includes("ON CONFLICT (id) DO NOTHING")
      ) {
        return {rows: []};
      }
      if (sql.includes("SELECT data")) {
        throw new Error("Connection terminated due to connection timeout");
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  try {
    await fs.writeFile(snapshotCachePath, JSON.stringify(persistedSnapshot), "utf8");

    const store = new PostgresStore({
      connectionString: "postgresql://unused/rodnya",
      pool,
      queryTimeoutMs: 25,
      readRetryDelayMs: 0,
      snapshotCachePath,
    });

    await store.initialize();
    store._writeQueue = new Promise(() => {});

    const snapshot = await store._read();
    assert.deepEqual(snapshot.chats, [{id: "chat-1"}]);
    assert.deepEqual(snapshot.messages, [{id: "msg-1", chatId: "chat-1"}]);
  } finally {
    await fs.rm(cacheDir, {recursive: true, force: true});
  }
});
