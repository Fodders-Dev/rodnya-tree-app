const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");

const {PostgresStore} = require("../src/postgres-store");

test("PostgresStore recovers from a failed write without poisoning the queue", async () => {
  let state = {users: []};
  let writeAttempts = 0;
  const pool = {
    async query(sql, params = []) {
      if (sql.includes("CREATE SCHEMA")) {
        return {rows: []};
      }
      if (sql.includes("CREATE TABLE") || sql.includes("CREATE INDEX")) {
        return {rows: []};
      }
      if (sql.includes("ON CONFLICT (id) DO NOTHING")) {
        return {rows: []};
      }
      if (
        sql.includes("DELETE FROM \"public\".\"rodnya_state_auth_users\"") ||
        sql.includes("DELETE FROM \"public\".\"rodnya_state_auth_sessions\"") ||
        sql.includes("INSERT INTO \"public\".\"rodnya_state_auth_users\"") ||
        sql.includes("INSERT INTO \"public\".\"rodnya_state_auth_sessions\"")
      ) {
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
        sql.includes("CREATE INDEX") ||
        sql.includes("ON CONFLICT (id) DO NOTHING")
      ) {
        return {rows: []};
      }
      if (
        sql.includes("DELETE FROM \"public\".\"rodnya_state_auth_users\"") ||
        sql.includes("DELETE FROM \"public\".\"rodnya_state_auth_sessions\"") ||
        sql.includes("INSERT INTO \"public\".\"rodnya_state_auth_users\"") ||
        sql.includes("INSERT INTO \"public\".\"rodnya_state_auth_sessions\"")
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

test("PostgresStore reuses one shared pool for identical config", async () => {
  let state = {users: []};
  let createdPoolCount = 0;
  let endCount = 0;
  const poolFactory = () => {
    createdPoolCount += 1;
    return {
      async query(sql) {
        if (
          sql.includes("CREATE SCHEMA") ||
          sql.includes("CREATE TABLE") ||
          sql.includes("CREATE INDEX") ||
          sql.includes("ON CONFLICT (id) DO NOTHING")
        ) {
          return {rows: []};
        }
        if (
          sql.includes("DELETE FROM \"public\".\"rodnya_state_auth_users\"") ||
          sql.includes("DELETE FROM \"public\".\"rodnya_state_auth_sessions\"") ||
          sql.includes("INSERT INTO \"public\".\"rodnya_state_auth_users\"") ||
          sql.includes("INSERT INTO \"public\".\"rodnya_state_auth_sessions\"")
        ) {
          return {rows: []};
        }
        if (sql.includes("SELECT data")) {
          return {rows: [{data: state}]};
        }
        throw new Error(`Unexpected query: ${sql}`);
      },
      async end() {
        endCount += 1;
      },
    };
  };

  const firstStore = new PostgresStore({
    connectionString: "postgresql://unused/rodnya",
    poolFactory,
  });
  const secondStore = new PostgresStore({
    connectionString: "postgresql://unused/rodnya",
    poolFactory,
  });

  await firstStore.initialize();
  await secondStore.initialize();

  const firstSnapshot = await firstStore._read();
  const secondSnapshot = await secondStore._read();

  assert.deepEqual(firstSnapshot.users, state.users);
  assert.deepEqual(secondSnapshot.users, state.users);
  assert.equal(createdPoolCount, 1);

  await firstStore.close();
  assert.equal(endCount, 0);

  await secondStore.close();
  assert.equal(endCount, 1);
});

test("PostgresStore auth hot paths avoid full state reads", async () => {
  const passwordSalt = "salt-1";
  const passwordHash = crypto
    .scryptSync("secret123", passwordSalt, 64)
    .toString("hex");
  const userRecord = {
    id: "user-1",
    email: "smoke@rodnya-tree.ru",
    passwordSalt,
    passwordHash,
    profile: {displayName: "Smoke User"},
  };
  let sessions = [
    {
      token: "token-1",
      refreshToken: "refresh-1",
      userId: "user-1",
      createdAt: "2026-01-01T00:00:00.000Z",
      lastSeenAt: "2020-01-01T00:00:00.000Z",
    },
  ];
  let projectedUsers = [userRecord];
  let projectedSessions = [...sessions];
  const queries = [];
  const pool = {
    async query(sql, params = []) {
      queries.push(sql);
      if (
        sql.includes("CREATE SCHEMA") ||
        sql.includes("CREATE TABLE") ||
        sql.includes("CREATE INDEX") ||
        sql.includes("ON CONFLICT (id) DO NOTHING")
      ) {
        return {rows: []};
      }
      if (sql.includes("DELETE FROM \"public\".\"rodnya_state_auth_users\"")) {
        projectedUsers = [];
        return {rows: []};
      }
      if (sql.includes("DELETE FROM \"public\".\"rodnya_state_auth_sessions\"")) {
        projectedSessions = [];
        return {rows: []};
      }
      if (
        sql.includes("INSERT INTO \"public\".\"rodnya_state_auth_users\"") &&
        sql.includes("FROM \"public\".\"rodnya_state\",")
      ) {
        projectedUsers = [userRecord];
        return {rows: []};
      }
      if (
        sql.includes("INSERT INTO \"public\".\"rodnya_state_auth_sessions\"") &&
        sql.includes("FROM \"public\".\"rodnya_state\",")
      ) {
        projectedSessions = [...sessions];
        return {rows: []};
      }
      if (
        sql.includes("INSERT INTO \"public\".\"rodnya_state_auth_users\"") &&
        sql.includes("jsonb_array_elements($1::jsonb)")
      ) {
        projectedUsers = JSON.parse(params[0]);
        return {rows: []};
      }
      if (
        sql.includes("INSERT INTO \"public\".\"rodnya_state_auth_sessions\"") &&
        sql.includes("jsonb_array_elements($1::jsonb)")
      ) {
        projectedSessions = JSON.parse(params[0]);
        sessions = projectedSessions;
        return {rows: []};
      }
      if (sql.includes("SELECT user_data")) {
        const userParam = params[0];
        const match = projectedUsers.find(
          (entry) => entry.id === userParam || entry.email === userParam,
        );
        return {rows: match ? [{user_data: match}] : []};
      }
      if (sql.includes("SELECT session_data")) {
        const sessionParam = params[0];
        if (sql.includes("ORDER BY created_at NULLS FIRST, token")) {
          return {
            rows: projectedSessions.map((entry) => ({session_data: entry})),
          };
        }
        const match = projectedSessions.find(
          (entry) =>
            entry.token === sessionParam || entry.refreshToken === sessionParam,
        );
        return {rows: match ? [{session_data: match}] : []};
      }
      if (sql.includes("jsonb_set(") && sql.includes("'{sessions}'")) {
        sessions = projectedSessions;
        return {rows: []};
      }
      if (sql.includes("SELECT data")) {
        throw new Error("full_state_read_not_allowed");
      }
      throw new Error(`Unexpected query: ${sql}`);
    },
  };

  const store = new PostgresStore({
    connectionString: "postgresql://unused/rodnya",
    pool,
  });

  await store.initialize();

  const authenticatedUser = await store.authenticate(
    "smoke@rodnya-tree.ru",
    "secret123",
  );
  assert.equal(authenticatedUser?.id, "user-1");

  const userById = await store.findUserById("user-1");
  assert.equal(userById?.email, "smoke@rodnya-tree.ru");

  const userByEmail = await store.findUserByEmail("smoke@rodnya-tree.ru");
  assert.equal(userByEmail?.id, "user-1");

  const sessionByToken = await store.findSession("token-1");
  assert.equal(sessionByToken?.userId, "user-1");

  const sessionByRefreshToken = await store.findSessionByRefreshToken("refresh-1");
  assert.equal(sessionByRefreshToken?.token, "token-1");

  store._sessionTouchCache.clear();
  const touchedSession = await store.touchSession("token-1");
  assert.equal(touchedSession?.token, "token-1");
  assert.notEqual(touchedSession?.lastSeenAt, "2020-01-01T00:00:00.000Z");

  const createdSession = await store.createSession("user-1");
  assert.ok(createdSession?.token);
  assert.ok(createdSession?.refreshToken);
  assert.equal(sessions.filter((entry) => entry.userId === "user-1").length, 2);

  await store.deleteSession("token-1");
  assert.equal(sessions.some((entry) => entry.token === "token-1"), false);

  await store.deleteSessionsForUser("user-1");
  assert.equal(sessions.length, 0);
  assert.equal(
    queries.some((sql) => sql.includes("SELECT data FROM")),
    false,
  );
});
