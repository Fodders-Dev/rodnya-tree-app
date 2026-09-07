// SPEED-15: корзина deletedPersons поверх таблицы на pg-mem — НАСТОЯЩИЙ SQL
// стора: бут-миграция блоб→таблица (бэкап, маркер, идемпотентность), список
// для пользователя/семьи, restore (мутирует строку + возвращает персону в
// блоб) и hardDelete (удаляет строку), новая запись из унаследованного
// deletePerson (FileStore) дренируется в таблицу на _write.
const test = require("node:test");
const assert = require("node:assert/strict");

const {newDb} = require("pg-mem");
const {PostgresStore} = require("../src/postgres-store");

const USERS = [
  {id: "user-1", email: "ivan@rodnya-tree.ru", profile: {displayName: "Иван"}},
  {id: "user-2", email: "anna@rodnya-tree.ru", profile: {displayName: "Анна"}},
  {id: "user-3", email: "oleg@rodnya-tree.ru", profile: {displayName: "Олег"}},
];
const TREE = {
  id: "tree-1",
  name: "Наше дерево",
  creatorId: "user-1",
  memberIds: ["user-1", "user-2"],
  createdAt: "2026-04-01T10:00:00.000Z",
  updatedAt: "2026-04-01T10:00:00.000Z",
  semyaId: "semya-1",
};
const PERSONS = [
  {id: "person-1", treeId: "tree-1", name: "Пётр", firstName: "Пётр", createdAt: "2026-04-01T10:00:00.000Z"},
];

const TABLE = `"public"."rodnya_state_deleted_persons"`;
const BACKUPS_TABLE = `"public"."rodnya_state_deleted_persons_backups"`;
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

function deletedPersonRow(overrides = {}) {
  const now = Date.now();
  return {
    id: overrides.id || "dp-1",
    originalPersonId: overrides.originalPersonId || "person-gone-1",
    treeId: overrides.treeId || "tree-1",
    semyaId: overrides.semyaId === undefined ? "semya-1" : overrides.semyaId,
    snapshot: overrides.snapshot || {
      id: overrides.originalPersonId || "person-gone-1",
      treeId: "tree-1",
      name: "Ушедший",
      firstName: "Ушедший",
    },
    relationsSnapshot: overrides.relationsSnapshot || [],
    deletedAt: overrides.deletedAt || new Date(now - 3600_000).toISOString(),
    deletedByUserId: overrides.deletedByUserId || "user-1",
    hardDeleteScheduledAt:
      overrides.hardDeleteScheduledAt || new Date(now + 30 * 24 * 3600_000).toISOString(),
    earliestHardDelete:
      overrides.earliestHardDelete !== undefined
        ? overrides.earliestHardDelete
        : new Date(now - 3600_000).toISOString(), // floor already elapsed by default (test convenience)
    restoredAt: overrides.restoredAt || null,
    restoredByUserId: overrides.restoredByUserId || null,
  };
}

function seed(extra = {}) {
  return {
    users: USERS,
    trees: [TREE],
    persons: PERSONS,
    relations: [],
    semyi: [{id: "semya-1", name: "Семья", createdAt: "2026-04-01T10:00:00.000Z"}],
    semyaMembers: [
      {userId: "user-1", semyaId: "semya-1", hiddenAt: null},
      {userId: "user-2", semyaId: "semya-1", hiddenAt: null},
    ],
    deletedPersons: [
      deletedPersonRow({id: "dp-restorable", originalPersonId: "person-gone-1", deletedByUserId: "user-1"}),
      deletedPersonRow({
        id: "dp-elapsed",
        originalPersonId: "person-gone-2",
        deletedByUserId: "user-2",
        hardDeleteScheduledAt: "2020-01-01T00:00:00.000Z",
      }),
      deletedPersonRow({id: "dp-other-semya", originalPersonId: "person-gone-3", semyaId: "semya-2", deletedByUserId: "user-3"}),
      // Битая запись (без id) — остаётся только в бэкапе.
      {treeId: "tree-1", originalPersonId: "broken"},
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

  const rows = await rawPool.query(`SELECT id, semya_id, deleted_by_user_id FROM ${TABLE} ORDER BY id`);
  assert.deepEqual(rows.rows.map((r) => r.id), ["dp-elapsed", "dp-other-semya", "dp-restorable"]);

  const backup = await rawPool.query(`SELECT id, backup_data FROM ${BACKUPS_TABLE}`);
  assert.equal(backup.rows.length, 1);
  const backupData = typeof backup.rows[0].backup_data === "string"
    ? JSON.parse(backup.rows[0].backup_data) : backup.rows[0].backup_data;
  assert.equal(backupData.deletedPersons.length, 4, "битая запись тоже в бэкапе");

  const state = await stateRow(rawPool);
  assert.deepEqual(state.deletedPersons, []);
  assert.equal(state.migrationStatus.deletedPersonsToTables, "complete-v1");

  // Повторный бут — не дублирует.
  const {store: again, rawPool: againPool} = buildStore(seed());
  await again.initialize();
  await again.initialize();
  const againRows = await againPool.query(`SELECT count(*)::int AS n FROM ${TABLE}`);
  assert.equal(againRows.rows[0].n, 3);
});

test("listDeletedPersonsForUser: своя + по членству семьи, без restored", async () => {
  const {store} = buildStore(seed());
  const forUser1 = await store.listDeletedPersonsForUser({userId: "user-1"});
  assert.deepEqual(forUser1.map((r) => r.id).sort(), ["dp-elapsed", "dp-restorable"], "член semya-1 видит обе записи семьи");

  const forUser3 = await store.listDeletedPersonsForUser({userId: "user-3"});
  assert.deepEqual(forUser3.map((r) => r.id), ["dp-other-semya"], "свою запись видит, даже не будучи членом semya-2");
});

test("listDeletedPersonsForSemya: требует членства, NOT_MEMBER иначе", async () => {
  const {store} = buildStore(seed());
  const rows = await store.listDeletedPersonsForSemya({semyaId: "semya-1", userId: "user-1"});
  assert.deepEqual(rows.map((r) => r.id).sort(), ["dp-elapsed", "dp-restorable"]);
  await assert.rejects(
    store.listDeletedPersonsForSemya({semyaId: "semya-2", userId: "user-1"}),
    /NOT_MEMBER/,
  );
});

test("restorePerson: возвращает персону в блоб, помечает строку restored в таблице", async () => {
  const {store, rawPool} = buildStore(seed());
  const restored = await store.restorePerson({deletedPersonId: "dp-restorable", actorUserId: "user-1"});
  assert.equal(restored.restoredByUserId, "user-1");
  assert.ok(restored.restoredAt);

  const db = await store._read();
  assert.ok(db.persons.find((p) => p.id === "person-gone-1"), "снапшот вернулся в db.persons");

  const row = await rawPool.query(`SELECT restored_at, restored_by_user_id FROM ${TABLE} WHERE id = $1`, ["dp-restorable"]);
  assert.equal(row.rows[0].restored_by_user_id, "user-1");
  assert.ok(row.rows[0].restored_at, "restored_at заполнен в таблице");

  // Повторный restore того же id → ALREADY_RESTORED.
  await assert.rejects(
    store.restorePerson({deletedPersonId: "dp-restorable", actorUserId: "user-1"}),
    /ALREADY_RESTORED/,
  );
});

test("restorePerson: HARD_DELETE_ELAPSED / FORBIDDEN / DELETED_PERSON_NOT_FOUND", async () => {
  const {store} = buildStore(seed());
  await assert.rejects(
    store.restorePerson({deletedPersonId: "dp-elapsed", actorUserId: "user-2"}),
    /HARD_DELETE_ELAPSED/,
  );
  await assert.rejects(
    store.restorePerson({deletedPersonId: "dp-other-semya", actorUserId: "user-1"}),
    /FORBIDDEN/,
    "не член semya-2 и не оригинальный актор",
  );
  await assert.rejects(
    store.restorePerson({deletedPersonId: "nope", actorUserId: "user-1"}),
    /DELETED_PERSON_NOT_FOUND/,
  );
});

test("hardDeletePerson: удаляет строку из таблицы без записи блоба", async () => {
  const {store, rawPool} = buildStore(seed());
  const result = await store.hardDeletePerson({deletedPersonId: "dp-elapsed", actorUserId: "user-2"});
  assert.deepEqual(result, {purged: true, deletedPersonId: "dp-elapsed"});
  const row = await rawPool.query(`SELECT id FROM ${TABLE} WHERE id = $1`, ["dp-elapsed"]);
  assert.equal(row.rows.length, 0);

  await assert.rejects(
    store.hardDeletePerson({deletedPersonId: "dp-elapsed", actorUserId: "user-2"}),
    /DELETED_PERSON_NOT_FOUND/,
  );
});

test("hardDeletePerson: FORBIDDEN для чужой не-семейной записи", async () => {
  const {store} = buildStore(seed());
  await assert.rejects(
    store.hardDeletePerson({deletedPersonId: "dp-other-semya", actorUserId: "user-1"}),
    /FORBIDDEN/,
  );
});

test("deletePerson: новая запись рождается в блобе и дренируется в таблицу", async () => {
  const {store, rawPool} = buildStore(seed());
  const ok = await store.deletePerson("tree-1", "person-1", "user-1");
  assert.equal(ok, true);

  const state = await stateRow(rawPool);
  assert.deepEqual(state.deletedPersons, [], "в блобе не задерживается");

  const rows = await rawPool.query(`SELECT original_person_id FROM ${TABLE} WHERE original_person_id = $1`, ["person-1"]);
  assert.equal(rows.rows.length, 1, "новая запись уехала в таблицу");

  const listed = await store.listDeletedPersonsForUser({userId: "user-1"});
  assert.ok(listed.find((r) => r.originalPersonId === "person-1"));
});
