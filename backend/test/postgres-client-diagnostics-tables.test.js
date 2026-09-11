// SPEED-15: clientDiagnostics поверх таблицы на pg-mem — НАСТОЯЩИЙ SQL стора:
// бут-миграция блоб→таблица (бэкап, маркер, идемпотентность), создание с
// ring-buffer cap на 500, чтение с фильтрами type/userId/limit. Append-only,
// не участвует в _mutate — createClientDiagnostic/listClientDiagnostics
// полностью на SQL после миграции (никакого дренажа «новых записей»: блоб-
// массив больше никто не пополняет).
const test = require("node:test");
const assert = require("node:assert/strict");

const {newDb} = require("pg-mem");
const {PostgresStore} = require("../src/postgres-store");

const TABLE = `"public"."rodnya_state_client_diagnostics"`;
const BACKUPS_TABLE = `"public"."rodnya_state_client_diagnostics_backups"`;
const STATE_TABLE = `"public"."rodnya_state"`;

function buildStore(seededState) {
  const memDb = newDb();
  const {Pool} = memDb.adapters.createPg();
  const rawPool = new Pool();
  const pool = {
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
  const store = new PostgresStore({
    connectionString: "postgresql://unused/rodnya",
    pool,
    snapshotCachePath: null,
  });
  return {store, rawPool};
}

function diag(overrides = {}) {
  return {
    id: overrides.id,
    userId: overrides.userId ?? "user-1",
    sessionId: overrides.sessionId ?? null,
    type: overrides.type || "client_event",
    message: overrides.message || "",
    platform: overrides.platform ?? null,
    appVersion: overrides.appVersion ?? null,
    context: overrides.context || {},
    error: overrides.error ?? null,
    stackTrace: overrides.stackTrace ?? null,
    createdAt: overrides.createdAt || "2026-08-01T10:00:00.000Z",
  };
}

function seed(extra = {}) {
  return {
    users: [{id: "user-1", email: "ivan@rodnya-tree.ru"}],
    clientDiagnostics: [
      diag({id: "diag_old", createdAt: "2026-05-01T10:00:00.000Z", type: "tree_layout_snapshot"}),
      diag({id: "diag_new", createdAt: "2026-08-20T10:00:00.000Z", type: "client_event", userId: "user-2"}),
      // Битая запись (без id) — остаётся только в бэкапе.
      {type: "broken", createdAt: "2026-08-01T10:00:00.000Z"},
    ],
    ...extra,
  };
}

async function stateRow(rawPool) {
  const result = await rawPool.query(`SELECT data FROM ${STATE_TABLE} WHERE id = $1`, ["default"]);
  const raw = result.rows[0].data;
  return typeof raw === "string" ? JSON.parse(raw) : raw;
}

test("миграция: блоб → таблица, бэкап, маркер, идемпотентность", async () => {
  const {store, rawPool} = buildStore(seed());
  await store.initialize();

  const rows = await rawPool.query(`SELECT id, type FROM ${TABLE} ORDER BY id`);
  assert.deepEqual(rows.rows.map((r) => r.id), ["diag_new", "diag_old"]);

  const backup = await rawPool.query(`SELECT id, backup_data FROM ${BACKUPS_TABLE}`);
  assert.equal(backup.rows.length, 1);
  const backupData = typeof backup.rows[0].backup_data === "string"
    ? JSON.parse(backup.rows[0].backup_data) : backup.rows[0].backup_data;
  assert.equal(backupData.clientDiagnostics.length, 3, "битая запись тоже в бэкапе");

  const state = await stateRow(rawPool);
  assert.deepEqual(state.clientDiagnostics, []);
  assert.equal(state.migrationStatus.clientDiagnosticsToTables, "complete-v1");

  const {store: again, rawPool: againPool} = buildStore(seed());
  await again.initialize();
  await again.initialize();
  const againRows = await againPool.query(`SELECT count(*)::int AS n FROM ${TABLE}`);
  assert.equal(againRows.rows[0].n, 2);
});

test("createClientDiagnostic: новая запись в таблице, блоб не пополняется", async () => {
  const {store, rawPool} = buildStore(seed());
  const event = await store.createClientDiagnostic({
    userId: "user-1",
    type: "crash",
    message: "тест",
    context: {screen: "tree"},
  });
  assert.ok(event.id.startsWith("diag_"));
  const row = await rawPool.query(`SELECT type FROM ${TABLE} WHERE id = $1`, [event.id]);
  assert.equal(row.rows[0]?.type, "crash");
  const state = await stateRow(rawPool);
  assert.deepEqual(state.clientDiagnostics, []);
});

test("createClientDiagnostic: ring-buffer cap на 500 записей", async () => {
  const {store, rawPool} = buildStore(seed({clientDiagnostics: []}));
  await store.initialize();
  // Засеваем 500 строк напрямую SQL (быстро) вместо 500 последовательных
  // вызовов createClientDiagnostic — сам cap проверяется одним РЕАЛЬНЫМ
  // вызовом сверху, механизм тот же (DELETE ... WHERE id NOT IN (... LIMIT
  // 500)), просто без O(n) вызовов store на подготовку.
  for (let i = 0; i < 500; i += 1) {
    const createdAt = new Date(Date.parse("2026-08-01T00:00:00.000Z") + i * 1000).toISOString();
    // eslint-disable-next-line no-await-in-loop
    await rawPool.query(
      `INSERT INTO ${TABLE} (id, user_id, type, created_at, row_data) VALUES ($1, $2, $3, $4, $5::jsonb)`,
      [`diag_seed_${i}`, "user-1", "client_event", createdAt, JSON.stringify(diag({id: `diag_seed_${i}`, createdAt}))],
    );
  }
  const before = await rawPool.query(`SELECT count(*)::int AS n FROM ${TABLE}`);
  assert.equal(before.rows[0].n, 500);

  const event = await store.createClientDiagnostic({userId: "user-1", type: "client_event", message: "новейшая"});

  const after = await rawPool.query(`SELECT count(*)::int AS n FROM ${TABLE}`);
  assert.equal(after.rows[0].n, 500, "cap держит ровно 500 строк");
  const newest = await rawPool.query(`SELECT id FROM ${TABLE} WHERE id = $1`, [event.id]);
  assert.equal(newest.rows.length, 1, "новая запись осталась");
  const oldest = await rawPool.query(`SELECT id FROM ${TABLE} WHERE id = $1`, ["diag_seed_0"]);
  assert.equal(oldest.rows.length, 0, "самая старая запись вытеснена");
});

test("listClientDiagnostics: фильтры type/userId и порядок по created_at DESC", async () => {
  const {store} = buildStore(seed());
  const all = await store.listClientDiagnostics({});
  assert.deepEqual(all.map((d) => d.id), ["diag_new", "diag_old"], "новые первыми");

  const byType = await store.listClientDiagnostics({type: "tree_layout_snapshot"});
  assert.deepEqual(byType.map((d) => d.id), ["diag_old"]);

  const byUser = await store.listClientDiagnostics({userId: "user-2"});
  assert.deepEqual(byUser.map((d) => d.id), ["diag_new"]);

  const limited = await store.listClientDiagnostics({limit: 1});
  assert.equal(limited.length, 1);
});
