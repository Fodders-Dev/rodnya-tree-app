// SPEED-15: sessions полностью вне блоба — pg-mem, НАСТОЯЩИЙ SQL стора.
//
// Это самая рискованная часть SPEED-15: auth_sessions (SPEED-6 проекция)
// уже единственный источник данных на ЧТЕНИЕ (_read() накладывает её поверх
// блоба на КАЖДОМ пути), но _hydrateAuthProjectionTablesFromStateRow
// перестраивала эту таблицу ИЗ блоба на КАЖДОМ боте — если бы блоб после
// миграции просто обнулился без гейта на маркер, второй же рестарт
// backend'а стёр бы все живые сессии (все разлогинены). Тесты ниже гоняют
// ДВА реальных бота одного и того же pg-mem состояния — ровно тот сценарий,
// который сломал бы прод.
const test = require("node:test");
const assert = require("node:assert/strict");

const {newDb} = require("pg-mem");
const {PostgresStore} = require("../src/postgres-store");

const AUTH_SESSIONS_TABLE = `"public"."rodnya_state_auth_sessions"`;
const SESSIONS_BACKUPS_TABLE = `"public"."rodnya_state_sessions_backups"`;
const STATE_TABLE = `"public"."rodnya_state"`;

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

function session(overrides = {}) {
  return {
    token: overrides.token,
    refreshToken: overrides.refreshToken || `refresh-${overrides.token}`,
    userId: overrides.userId || "user-1",
    createdAt: overrides.createdAt || "2026-08-01T10:00:00.000Z",
    lastSeenAt: overrides.lastSeenAt || "2026-08-01T10:00:00.000Z",
  };
}

function seed(extra = {}) {
  return {
    users: [
      {id: "user-1", email: "ivan@rodnya-tree.ru"},
      {id: "user-2", email: "anna@rodnya-tree.ru"},
    ],
    sessions: [
      session({token: "tok-1", userId: "user-1"}),
      session({token: "tok-2", userId: "user-2"}),
    ],
    ...extra,
  };
}

async function stateRow(rawPool) {
  const result = await rawPool.query(`SELECT data FROM ${STATE_TABLE} WHERE id = $1`, ["default"]);
  const raw = result.rows[0].data;
  return typeof raw === "string" ? JSON.parse(raw) : raw;
}

test("миграция: сессии из блоба → бэкап + маркер, блоб очищен, таблица цела", async () => {
  const memDb = newDb();
  const {Pool} = memDb.adapters.createPg();
  const rawPool = new Pool();
  const seeded = seed();
  const store = new PostgresStore({
    connectionString: "postgresql://unused/rodnya",
    pool: seedingPool(rawPool, seeded),
    snapshotCachePath: null,
  });
  await store.initialize();

  const state = await stateRow(rawPool);
  assert.deepEqual(state.sessions, [], "блоб больше не носит sessions");
  assert.equal(state.migrationStatus.sessionsOutOfBlob, "complete-v1");

  const tableRows = await rawPool.query(`SELECT token, user_id FROM ${AUTH_SESSIONS_TABLE} ORDER BY token`);
  assert.deepEqual(tableRows.rows.map((r) => r.token), ["tok-1", "tok-2"], "проекция цела");

  const backup = await rawPool.query(`SELECT backup_data FROM ${SESSIONS_BACKUPS_TABLE}`);
  assert.equal(backup.rows.length, 1);
  const backupData = typeof backup.rows[0].backup_data === "string"
    ? JSON.parse(backup.rows[0].backup_data) : backup.rows[0].backup_data;
  assert.equal(backupData.sessions.length, 2);

  // _read() всё равно отдаёт живые сессии — чтение не деградировало.
  const db = await store._read();
  assert.equal(db.sessions.length, 2);
});

// Второй физический процесс (рестарт/деплой) на pg-mem не смоделировать
// честно через второй `new PostgresStore(...)` на ТОМ ЖЕ пуле — pg-mem
// падает на повторном `CREATE TABLE IF NOT EXISTS rodnya_state` совершенно
// независимо от SPEED-15 (тот же AST-coverage quirk у любого re-bootstrap;
// см. docs/speed_measurement.md, раздел «pg-mem» в .claude/rules/backend-
// store.md — бут-миграции доказываются полностью только на реальном
// Postgres). Вместо этого дёргаем ИМЕННО ту функцию, которая на реальном
// проде вызывается на КАЖДОМ старте процесса
// (_hydrateAuthProjectionTablesFromStateRow), напрямую — с состоянием ДО и
// ПОСЛЕ маркера, это и есть развилка, от которой зависит, стирается таблица
// или нет.
test("КРИТИЧНО: _hydrateAuthProjectionTablesFromStateRow с маркером НЕ стирает auth_sessions", async () => {
  const memDb = newDb();
  const {Pool} = memDb.adapters.createPg();
  const rawPool = new Pool();
  const seeded = seed();
  const store = new PostgresStore({
    connectionString: "postgresql://unused/rodnya",
    pool: seedingPool(rawPool, seeded),
    snapshotCachePath: null,
  });
  await store.initialize();

  // Login «между рестартами» — новая сессия попадает ТОЛЬКО в проекцию
  // (createSession никогда не трогал блоб, см. SPEED-6/15), как и в проде.
  await store.createSession("user-1", {platform: "android"});
  const beforeRehydrate = await rawPool.query(`SELECT count(*)::int AS n FROM ${AUTH_SESSIONS_TABLE}`);
  assert.equal(beforeRehydrate.rows[0].n, 3, "2 из блоба + 1 новый логин");

  const migratedState = await stateRow(rawPool);
  assert.equal(migratedState.migrationStatus.sessionsOutOfBlob, "complete-v1");
  assert.deepEqual(migratedState.sessions, [], "блоб реально пуст — вот что делает следующую проверку значимой");

  // Ровно то, что _bootstrap() зовёт на КАЖДОМ старте процесса.
  await store._hydrateAuthProjectionTablesFromStateRow(migratedState);

  const afterRehydrate = await rawPool.query(`SELECT token FROM ${AUTH_SESSIONS_TABLE} ORDER BY token`);
  assert.equal(afterRehydrate.rows.length, 3, "маркер — таблица не тронута, ни одна сессия не потеряна");

  // Контрольный эксперимент: та же функция БЕЗ маркера (как будто вызвана
  // до того, как мы научили её его проверять) — вот тот самый прод-инцидент,
  // от которого защищает гейт: реальный блоб уже [] после миграции, значит
  // «честная» перестройка из блоба стирает всё.
  const stateWithoutMarker = {...migratedState, migrationStatus: {}};
  await store._hydrateAuthProjectionTablesFromStateRow(stateWithoutMarker);
  const afterUngatedRehydrate = await rawPool.query(`SELECT count(*)::int AS n FROM ${AUTH_SESSIONS_TABLE}`);
  assert.equal(
    afterUngatedRehydrate.rows[0].n,
    0,
    "без гейта на маркер перестройка из уже-пустого блоба стирает всё — именно поэтому гейт обязателен",
  );
});

test("_write не встраивает sessions в JSONB после миграции, но проекция синкается", async () => {
  const memDb = newDb();
  const {Pool} = memDb.adapters.createPg();
  const rawPool = new Pool();
  const seeded = seed();
  const store = new PostgresStore({
    connectionString: "postgresql://unused/rodnya",
    pool: seedingPool(rawPool, seeded),
    snapshotCachePath: null,
  });
  await store.initialize();

  // deleteUser (FileStore, унаследован) мутирует db.sessions ПРЯМО в блобе
  // внутри своего _read()+_write() — ровно путь, который раньше протаскивал
  // sessions обратно в JSONB на каждую такую запись.
  await store.deleteUser("user-2");

  const state = await stateRow(rawPool);
  assert.deepEqual(state.sessions, [], "sessions не воскресли в блобе");

  const tableRows = await rawPool.query(`SELECT token FROM ${AUTH_SESSIONS_TABLE} ORDER BY token`);
  assert.deepEqual(tableRows.rows.map((r) => r.token), ["tok-1"], "проекция реально почистилась от user-2");
});

test("деградированный путь без cursor (bootState=undefined) тоже гейтит по маркеру", async () => {
  // _hydrateAuthProjectionTablesFromStateRow(undefined) — путь «SPEED-9
  // C-boot снимок недоступен» (см. else-ветку _bootstrap()): функция сама
  // читает маркер дешёвым scalar-запросом, а не полагается на переданный
  // bootState. Проверяем оба исхода той же развилки без cursor.
  const memDb = newDb();
  const {Pool} = memDb.adapters.createPg();
  const rawPool = new Pool();
  const store = new PostgresStore({
    connectionString: "postgresql://unused/rodnya",
    pool: seedingPool(rawPool, seed()),
    snapshotCachePath: null,
  });
  await store.initialize();
  await store.createSession("user-1", {platform: "ios"});
  const before = await rawPool.query(`SELECT count(*)::int AS n FROM ${AUTH_SESSIONS_TABLE}`);
  assert.equal(before.rows[0].n, 3);

  // Маркер уже стоит (первый initialize() смигрировал) — вызов БЕЗ bootState
  // обязан сам его обнаружить и не перестраивать таблицу.
  await store._hydrateAuthProjectionTablesFromStateRow(undefined);
  const afterGated = await rawPool.query(`SELECT count(*)::int AS n FROM ${AUTH_SESSIONS_TABLE}`);
  assert.equal(afterGated.rows[0].n, 3, "scalar-фолбэк тоже уважает маркер");
});
