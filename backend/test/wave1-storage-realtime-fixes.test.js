// Wave 1 regression tests:
//   * hard-delete-job: dryRun boolean flag respected even when firstRunDry=false
//   * PostgresStore._hydrateAuthProjectionTablesFromStateRow: marker query failure never wipes auth_sessions
//   * PostgresStore._write() with sessionsOutOfBlob: preserves concurrent sessions; updateUserPassword deletes user sessions
//   * PostgresStore._loadSnapshot() / _commitCachedState(): distinct mutable reads & version regression guard
//   * PostgresStore.createPerson: forwards sourcePersonId (cross-tree identity inheritance)
//   * searchChatMessages (FileStore & PostgresStore): removed group member cannot read historical messages
//   * RealtimeHub: early disconnect during async auth/presence never leaks socket; throwing send does not abort broadcast

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");
const http = require("node:http");
const {EventEmitter} = require("node:events");
const {newDb} = require("pg-mem");
const {WebSocket} = require("ws");

const {FileStore} = require("../src/store");
const {PostgresStore} = require("../src/postgres-store");
const {runHardDeleteJob} = require("../src/jobs/hard-delete-job");
const {RealtimeHub} = require("../src/realtime-hub");

function seedingPool(rawPool, seededState) {
  return {
    query: (sql, params) => {
      let effectiveParams = params;
      if (
        String(sql).includes("ON CONFLICT (id) DO NOTHING") &&
        Array.isArray(params) &&
        params[0] === "default"
      ) {
        effectiveParams = [params[0], JSON.stringify(seededState)];
      }
      return rawPool.query(sql, effectiveParams);
    },
  };
}

test("hard-delete-job: hardDeleteDryRun=true runs as dryRun even when hardDeleteFirstRunDry=false", async () => {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-w1-hd-"));
  try {
    const store = new FileStore(path.join(tempDir, "db.json"));
    await store.initialize();
    await store._mutate((db) => {
      db.graphPersons.push({
        id: "gp-old",
        treeId: "t1",
        deletedAt: "2025-01-01T00:00:00.000Z",
        hardDeleteScheduledAt: "2025-02-01T00:00:00.000Z",
        earliestHardDelete: "2025-01-02T00:00:00.000Z",
      });
    });

    const summary = await runHardDeleteJob({
      store,
      config: {
        hardDeleteEnabled: true,
        hardDeleteFirstRunDry: false,
        hardDeleteDryRun: true,
        hardDeleteRetentionDays: 30,
        hardDeleteAuditRetentionDays: 90,
        hardDeleteMaxPerRun: 100,
      },
    });
    assert.equal(summary.dryRun, true);
    assert.equal(summary.deleted.graphPersons, 1);

    const dbAfter = await store._read();
    assert.equal(
      dbAfter.graphPersons.length,
      1,
      "dryRun=true must NOT physically delete expired graphPersons",
    );
  } finally {
    await fs.rm(tempDir, {recursive: true, force: true}).catch(() => {});
  }
});

test("PostgresStore._hydrateAuthProjectionTablesFromStateRow: marker query failure does NOT wipe auth_sessions", async () => {
  const memDb = newDb();
  const {Pool} = memDb.adapters.createPg();
  const rawPool = new Pool();
  const seeded = {
    users: [{id: "user-1", email: "a@rodnya-tree.ru"}],
    sessions: [
      {
        token: "tok-1",
        refreshToken: "ref-1",
        userId: "user-1",
        createdAt: "2026-08-01T10:00:00.000Z",
      },
    ],
  };
  let failMarker = false;
  const pool = {
    query: (sql, params) => {
      if (
        failMarker &&
        String(sql).includes("migrationStatus") &&
        String(sql).includes("sessionsOutOfBlob")
      ) {
        return Promise.reject(new Error("transient_db_blip"));
      }
      return seedingPool(rawPool, seeded).query(sql, params);
    },
  };
  const store = new PostgresStore({
    connectionString: "postgresql://unused/rodnya",
    pool,
    snapshotCachePath: null,
  });
  await store.initialize();
  await store.createSession("user-1", {platform: "android"});

  failMarker = true;
  await store._hydrateAuthProjectionTablesFromStateRow(undefined);
  failMarker = false;

  const count = await rawPool.query(
    `SELECT count(*)::int AS n FROM "public"."rodnya_state_auth_sessions"`,
  );
  assert.equal(
    count.rows[0].n,
    2,
    "transient failure reading sessionsOutOfBlob marker must never wipe auth_sessions",
  );
});

test("PostgresStore._write with sessionsOutOfBlob preserves concurrent sessions & updateUserPassword clears auth_sessions", async () => {
  const memDb = newDb();
  const {Pool} = memDb.adapters.createPg();
  const rawPool = new Pool();
  const seeded = {
    users: [
      {
        id: "user-1",
        email: "u1@rodnya-tree.ru",
        passwordHash: "oldhash",
        passwordSalt: "oldsalt",
      },
      {id: "user-2", email: "u2@rodnya-tree.ru"},
    ],
    sessions: [
      {
        token: "tok-1",
        refreshToken: "ref-1",
        userId: "user-1",
        createdAt: "2026-08-01T10:00:00.000Z",
      },
    ],
  };
  const store = new PostgresStore({
    connectionString: "postgresql://unused/rodnya",
    pool: seedingPool(rawPool, seeded),
    snapshotCachePath: null,
  });
  await store.initialize();

  // Request A reads snapshot before User 2 logs in.
  const staleDb = await store._read();
  // User 2 logs in concurrently (writes directly to auth_sessions).
  const created = await store.createSession("user-2", {platform: "web"});
  // Another read refreshes _lastSessionsProjectionHash.
  await store._read();
  // Request A writes staleDb (which only had user-1's session).
  await store._write(staleDb);

  const afterWrite = await rawPool.query(
    `SELECT token FROM "public"."rodnya_state_auth_sessions" ORDER BY token`,
  );
  const tokens = afterWrite.rows.map((r) => r.token);
  assert.ok(tokens.includes(created.token), "_write must not wipe concurrent session");
  assert.ok(tokens.includes("tok-1"));

  // Password reset on user-1 must delete user-1's sessions in auth_sessions.
  const ok = await store.updateUserPassword("user-1", "NewStrongPassword123!");
  assert.equal(ok, true);
  const afterReset = await rawPool.query(
    `SELECT token, user_id FROM "public"."rodnya_state_auth_sessions"`,
  );
  assert.deepEqual(
    afterReset.rows.map((r) => r.user_id),
    ["user-2"],
    "updateUserPassword must revoke user-1 sessions in auth_sessions",
  );
});

test("PostgresStore._loadSnapshot & _commitCachedState prevent shared mutable object & version regression", async () => {
  const memDb = newDb();
  const {Pool} = memDb.adapters.createPg();
  const rawPool = new Pool();
  const seeded = {
    users: [{id: "user-1", email: "a@rodnya-tree.ru"}],
    trees: [{id: "t1", creatorId: "user-1", memberIds: ["user-1"], name: "Initial"}],
  };
  const store = new PostgresStore({
    connectionString: "postgresql://unused/rodnya",
    pool: seedingPool(rawPool, seeded),
    snapshotCachePath: null,
  });
  await store.initialize();

  // Clear cache and fire two concurrent _read() calls.
  store._cachedState = null;
  store._cachedVersion = null;
  const [readA, readB] = await Promise.all([store._read(), store._read()]);
  assert.notStrictEqual(readA, readB, "concurrent _read() must not share mutable state");
  readA.trees[0].name = "MutatedInCallerA";
  assert.equal(readB.trees[0].name, "Initial");

  // Commit version base+5, then attempt version base+4 regression — must be ignored.
  const baseVersion = store._cachedVersion || 1;
  store._commitCachedState({users: [], trees: [{id: "t1", name: "v5"}]}, baseVersion + 5);
  store._commitCachedState({users: [], trees: [{id: "t1", name: "v4"}]}, baseVersion + 4);
  assert.equal(store._cachedVersion, baseVersion + 5);
  assert.equal(store._cachedState.trees[0].name, "v5");
});

test("PostgresStore.createPerson forwards sourcePersonId and inherits identityId", async () => {
  const memDb = newDb();
  const {Pool} = memDb.adapters.createPg();
  const rawPool = new Pool();
  const seeded = {
    users: [{id: "user-1", email: "a@rodnya-tree.ru"}],
    trees: [
      {id: "tree-1", creatorId: "user-1", memberIds: ["user-1"], members: ["user-1"]},
      {id: "tree-2", creatorId: "user-1", memberIds: ["user-1"], members: ["user-1"]},
    ],
    persons: [
      {
        id: "p-src",
        treeId: "tree-1",
        creatorId: "user-1",
        name: "Иван Петров",
        birthPlace: "Москва",
        identityId: "ident-1",
      },
    ],
    personIdentities: [{id: "ident-1", personIds: ["p-src"], canonicalPersonId: "p-src"}],
  };
  const store = new PostgresStore({
    connectionString: "postgresql://unused/rodnya",
    pool: seedingPool(rawPool, seeded),
    snapshotCachePath: null,
  });
  await store.initialize();

  const created = await store.createPerson({
    treeId: "tree-2",
    creatorId: "user-1",
    personData: {},
    sourcePersonId: "p-src",
  });
  assert.equal(created.identityId, "ident-1");
  assert.equal(created.birthPlace, "Москва");
});

test("searchChatMessages excludes removed group member on both FileStore and PostgresStore", async () => {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-w1-search-"));
  try {
    const fileStore = new FileStore(path.join(tempDir, "db.json"));
    await fileStore.initialize();
    await fileStore._mutate((db) => {
      db.users.push({id: "u1"}, {id: "u2"}, {id: "u3"});
    });
    const chat = await fileStore.createGroupChat({
      title: "Семья",
      createdBy: "u1",
      participantIds: ["u1", "u2", "u3"],
    });
    assert.ok(chat && chat.id);
    await fileStore.addChatMessage({
      chatId: chat.id,
      senderId: "u1",
      text: "Секретное слово альфа",
    });
    assert.equal(
      (await fileStore.searchChatMessages({userId: "u3", query: "альфа"})).length,
      1,
    );
    await fileStore.leaveGroupChat(chat.id, "u3");
    assert.equal(
      (await fileStore.searchChatMessages({userId: "u3", query: "альфа"})).length,
      0,
      "FileStore global search must not expose history to removed/left participant",
    );

    const memDb = newDb();
    const {Pool} = memDb.adapters.createPg();
    const rawPool = new Pool();
    const pgStore = new PostgresStore({
      connectionString: "postgresql://unused/rodnya",
      pool: seedingPool(rawPool, {
        users: [{id: "u1"}, {id: "u2"}, {id: "u3"}],
        chats: [
          {
            id: "chat_grp1",
            type: "group",
            title: "Семья",
            participantIds: ["u1", "u2", "u3"],
            createdAt: "2026-04-21T10:00:00.000Z",
            updatedAt: "2026-04-21T10:00:00.000Z",
          },
        ],
      }),
      snapshotCachePath: null,
    });
    await pgStore.initialize();
    await pgStore.addChatMessage({
      chatId: "chat_grp1",
      senderId: "u1",
      text: "Секретное слово бета",
    });
    assert.equal(
      (await pgStore.searchChatMessages({userId: "u3", query: "бета"})).length,
      1,
    );
    await pgStore.leaveGroupChat("chat_grp1", "u3");
    assert.equal(
      (await pgStore.searchChatMessages({userId: "u3", query: "бета"})).length,
      0,
      "PostgresStore global search must not expose history to removed/left participant",
    );
  } finally {
    await fs.rm(tempDir, {recursive: true, force: true}).catch(() => {});
  }
});

test("RealtimeHub: early disconnect does not leak socket and throwing socket.send does not abort publish", async () => {
  let resolveLookup;
  const fakeStore = {
    findSession: async (token) =>
      token === "tok-u1" ? {token, userId: "u1"} : null,
    findUserById: async (id) => ({id}),
    listRelatedChatParticipantIds: async () =>
      new Promise((resolve) => {
        resolveLookup = resolve;
      }),
    markUserSeenAt: async () => {},
    touchSession: async () => {},
  };

  const server = http.createServer();
  const hub = new RealtimeHub({store: fakeStore, logger: {warn: () => {}}});
  hub.attach(server);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const port = server.address().port;

  try {
    const ws = new WebSocket(`ws://127.0.0.1:${port}/v1/realtime?accessToken=tok-u1`);
    ws.on("error", () => {});
    await new Promise((resolve) => {
      if (ws.readyState === WebSocket.OPEN) {
        resolve();
      } else {
        ws.once("open", resolve);
      }
    });
    // Wait until listRelatedChatParticipantIds is pending, then close immediately.
    await new Promise((resolve) => {
      const check = () => (resolveLookup ? resolve() : setTimeout(check, 5));
      check();
    });
    ws.terminate();
    await new Promise((resolve) => setTimeout(resolve, 30));
    resolveLookup([]);
    await new Promise((resolve) => setTimeout(resolve, 30));
    assert.equal(
      hub.isUserOnline("u1"),
      false,
      "socket closed during async handshake must not stay online",
    );

    // publishToUser resilience when first socket throws synchronously
    const badSocket = new EventEmitter();
    badSocket.OPEN = 1;
    badSocket.readyState = 1;
    badSocket.send = () => {
      throw new Error("broken pipe");
    };
    badSocket.terminate = () => {};

    const received = [];
    const goodSocket = new EventEmitter();
    goodSocket.OPEN = 1;
    goodSocket.readyState = 1;
    goodSocket.send = (msg) => received.push(msg);

    hub._registerSocket("u2", badSocket);
    hub._registerSocket("u2", goodSocket);
    const sent = hub.publishToUser("u2", {type: "ping"});
    assert.equal(sent, true);
    assert.equal(received.length, 1);
    assert.equal(hub.userSockets.get("u2").has(badSocket), false);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
