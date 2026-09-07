// SPEED-15: HTTP-уровень (createApp) поверх PostgresStore+pg-mem для корзины
// deletedPersons и client-diagnostics — доказывает, что маршруты отдают тот
// же контракт (статусы/тела ответов), что и на FileStore
// (test/deleted-persons-routes.test.js), уже после того как обе коллекции
// уехали в таблицы. requireTreeAccess/findTree сюда не заходят (эти
// маршруты — только auth + прямой store-вызов), поэтому, в отличие от
// speed11-shared-snapshot.test.js (см. её комментарий про pg-mem и LATERAL
// jsonb_array_elements внутри findTree), полноценный HTTP end-to-end здесь
// возможен.
const test = require("node:test");
const assert = require("node:assert/strict");

const {newDb} = require("pg-mem");
const {createApp} = require("../src/app");
const {PostgresStore} = require("../src/postgres-store");
const {RealtimeHub} = require("../src/realtime-hub");
const {PushGateway} = require("../src/push-gateway");

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

function deletedPersonRow(overrides = {}) {
  const now = Date.now();
  return {
    id: overrides.id,
    originalPersonId: overrides.originalPersonId,
    treeId: overrides.treeId || "tree-1",
    semyaId: overrides.semyaId === undefined ? "semya-1" : overrides.semyaId,
    snapshot: {id: overrides.originalPersonId, treeId: "tree-1", name: "Ушедший"},
    relationsSnapshot: [],
    deletedAt: new Date(now - 3600_000).toISOString(),
    deletedByUserId: overrides.deletedByUserId || "user-1",
    hardDeleteScheduledAt: new Date(now + 30 * 24 * 3600_000).toISOString(),
    earliestHardDelete: new Date(now - 3600_000).toISOString(),
    restoredAt: null,
    restoredByUserId: null,
  };
}

async function startTestServer(extraState = {}) {
  const memDb = newDb();
  const {Pool} = memDb.adapters.createPg();
  const rawPool = new Pool();
  const seeded = {
    users: [
      {id: "user-1", email: "ivan@rodnya-tree.ru", profile: {displayName: "Иван"}},
      {id: "user-2", email: "anna@rodnya-tree.ru", profile: {displayName: "Анна"}},
      {id: "admin-1", email: "admin@rodnya-tree.ru", profile: {displayName: "Модератор"}},
    ],
    sessions: [
      {token: "tok-user-1", refreshToken: "r1", userId: "user-1", createdAt: "2026-08-01T10:00:00.000Z"},
      {token: "tok-user-2", refreshToken: "r2", userId: "user-2", createdAt: "2026-08-01T10:00:00.000Z"},
      {token: "tok-admin-1", refreshToken: "r3", userId: "admin-1", createdAt: "2026-08-01T10:00:00.000Z"},
    ],
    semyi: [{id: "semya-1", name: "Семья", createdAt: "2026-04-01T10:00:00.000Z"}],
    semyaMembers: [
      {userId: "user-1", semyaId: "semya-1", hiddenAt: null},
    ],
    deletedPersons: [
      deletedPersonRow({id: "dp-1", originalPersonId: "person-gone-1", deletedByUserId: "user-1"}),
    ],
    ...extraState,
  };
  const store = new PostgresStore({
    connectionString: "postgresql://unused/rodnya",
    pool: seedingPool(rawPool, seeded),
    snapshotCachePath: null,
  });
  await store.initialize();
  const realtimeHub = new RealtimeHub({store});
  const pushGateway = new PushGateway({store});
  const app = createApp({
    store,
    config: {
      corsOrigin: "*",
      adminEmails: ["admin@rodnya-tree.ru"],
    },
    realtimeHub,
    pushGateway,
  });
  const server = await new Promise((resolve) => {
    const instance = app.listen(0, "127.0.0.1", () => resolve(instance));
  });
  realtimeHub.attach(server);
  return {
    baseUrl: `http://127.0.0.1:${server.address().port}`,
    server,
    store,
    rawPool,
  };
}

async function shutdown({server}) {
  await new Promise((resolve) => server.close(resolve));
}

test("GET /v1/me/deleted-persons — из таблицы, тот же контракт, что на FileStore", async () => {
  const ctx = await startTestServer();
  try {
    const res = await fetch(`${ctx.baseUrl}/v1/me/deleted-persons`, {
      headers: {Authorization: "Bearer tok-user-1"},
    });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.deletedPersons.length, 1);
    assert.equal(body.deletedPersons[0].id, "dp-1");
    assert.equal(body.deletedPersons[0].originalPersonId, "person-gone-1");
  } finally {
    await shutdown(ctx);
  }
});

test("GET /v1/semya/:id/deleted-persons — 403 NOT_MEMBER для чужой семьи", async () => {
  const ctx = await startTestServer();
  try {
    const res = await fetch(`${ctx.baseUrl}/v1/semya/semya-1/deleted-persons`, {
      headers: {Authorization: "Bearer tok-user-2"},
    });
    assert.equal(res.status, 403);
  } finally {
    await shutdown(ctx);
  }
});

test("POST /v1/deleted-persons/:id/restore — 200, затем повтор → 409 ALREADY_RESTORED", async () => {
  const ctx = await startTestServer();
  try {
    const first = await fetch(`${ctx.baseUrl}/v1/deleted-persons/dp-1/restore`, {
      method: "POST",
      headers: {Authorization: "Bearer tok-user-1"},
    });
    assert.equal(first.status, 200);
    const body = await first.json();
    assert.equal(body.restored.id, "dp-1");
    assert.ok(body.restored.restoredAt);

    const second = await fetch(`${ctx.baseUrl}/v1/deleted-persons/dp-1/restore`, {
      method: "POST",
      headers: {Authorization: "Bearer tok-user-1"},
    });
    assert.equal(second.status, 409);
  } finally {
    await shutdown(ctx);
  }
});

test("DELETE /v1/deleted-persons/:id — 200 hard-purge, повтор → 404", async () => {
  const ctx = await startTestServer();
  try {
    const first = await fetch(`${ctx.baseUrl}/v1/deleted-persons/dp-1`, {
      method: "DELETE",
      headers: {Authorization: "Bearer tok-user-1"},
    });
    assert.equal(first.status, 200);
    const body = await first.json();
    assert.deepEqual(body, {purged: true, deletedPersonId: "dp-1"});

    const second = await fetch(`${ctx.baseUrl}/v1/deleted-persons/dp-1`, {
      method: "DELETE",
      headers: {Authorization: "Bearer tok-user-1"},
    });
    assert.equal(second.status, 404);
  } finally {
    await shutdown(ctx);
  }
});

test("POST /v1/diagnostics/client-events + GET /v1/admin/client-diagnostics — round-trip через таблицу", async () => {
  const ctx = await startTestServer({deletedPersons: []});
  try {
    const created = await fetch(`${ctx.baseUrl}/v1/diagnostics/client-events`, {
      method: "POST",
      headers: {Authorization: "Bearer tok-user-1", "Content-Type": "application/json"},
      body: JSON.stringify({type: "crash", message: "тест SPEED-15", context: {screen: "tree"}}),
    });
    assert.equal(created.status, 202);
    const createdBody = await created.json();
    assert.ok(createdBody.eventId);

    // Без прав модератора — 403.
    const forbidden = await fetch(`${ctx.baseUrl}/v1/admin/client-diagnostics`, {
      headers: {Authorization: "Bearer tok-user-1"},
    });
    assert.equal(forbidden.status, 403);

    const asAdmin = await fetch(`${ctx.baseUrl}/v1/admin/client-diagnostics?type=crash`, {
      headers: {Authorization: "Bearer tok-admin-1"},
    });
    assert.equal(asAdmin.status, 200);
    const body = await asAdmin.json();
    assert.equal(body.diagnostics.length, 1);
    assert.equal(body.diagnostics[0].id, createdBody.eventId);
    assert.equal(body.diagnostics[0].message, "тест SPEED-15");
  } finally {
    await shutdown(ctx);
  }
});
