const test = require("node:test");
const assert = require("node:assert/strict");

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

test("PostgresStore read fails fast when the write queue is stuck", async () => {
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
