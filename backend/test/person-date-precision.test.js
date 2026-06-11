// F5: «знаю только год» — birthDatePrecision/deathDatePrecision гоняются
// насквозь: createPerson нормализует, updatePerson переключает в обе
// стороны, мусорные значения схлопываются в exact, точность без даты
// невозможна.

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");

const {FileStore} = require("../src/store");

async function seededStore() {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-prec-"));
  const dataPath = path.join(tempDir, "dev-db.json");

  const bootstrap = new FileStore(dataPath);
  await bootstrap.initialize();

  const db = JSON.parse(await fs.readFile(dataPath, "utf8"));
  db.users = [
    {
      id: "user-a",
      email: "a@rodnya.app",
      profile: {displayName: "Артём"},
    },
  ];
  db.trees = [
    {
      id: "tree-a",
      name: "Семья А",
      creatorId: "user-a",
      memberIds: ["user-a"],
      members: ["user-a"],
    },
  ];
  await fs.writeFile(dataPath, JSON.stringify(db, null, 2));

  return new FileStore(dataPath);
}

test("createPerson: yearOnly сохраняется, мусор схлопывается в exact", async () => {
  const store = await seededStore();

  const yearOnly = await store.createPerson({
    treeId: "tree-a",
    creatorId: "user-a",
    personData: {
      firstName: "Пётр",
      lastName: "Кузнецов",
      gender: "male",
      birthDate: "1888-01-01T00:00:00.000Z",
      birthDatePrecision: "yearOnly",
      deathDate: "1959-01-01T00:00:00.000Z",
      deathDatePrecision: "yearOnly",
    },
  });
  assert.equal(yearOnly.birthDatePrecision, "yearOnly");
  assert.equal(yearOnly.deathDatePrecision, "yearOnly");

  const garbage = await store.createPerson({
    treeId: "tree-a",
    creatorId: "user-a",
    personData: {
      firstName: "Иван",
      lastName: "Кузнецов",
      gender: "male",
      birthDate: "1980-06-21T00:00:00.000Z",
      birthDatePrecision: "approximately-ish",
    },
  });
  assert.equal(garbage.birthDatePrecision, "exact");
  assert.equal(garbage.deathDatePrecision, "exact");
});

test("updatePerson: переключение exact → yearOnly → exact", async () => {
  const store = await seededStore();

  const created = await store.createPerson({
    treeId: "tree-a",
    creatorId: "user-a",
    personData: {
      firstName: "Анна",
      lastName: "Кузнецова",
      gender: "female",
      birthDate: "1900-01-01T00:00:00.000Z",
    },
  });
  assert.equal(created.birthDatePrecision, "exact");

  // Владелец вручную помечает «знаю только год» в форме редактирования.
  const marked = await store.updatePerson("tree-a", created.id, {
    birthDate: "1900-01-01T00:00:00.000Z",
    birthDatePrecision: "yearOnly",
  });
  assert.equal(marked.birthDatePrecision, "yearOnly");

  // И обратно — узнал точную дату.
  const exact = await store.updatePerson("tree-a", created.id, {
    birthDate: "1900-03-08T00:00:00.000Z",
    birthDatePrecision: "exact",
  });
  assert.equal(exact.birthDatePrecision, "exact");
  assert.ok(exact.birthDate.startsWith("1900-03-08"));
});

test("updatePerson: точность без даты схлопывается в exact", async () => {
  const store = await seededStore();

  const created = await store.createPerson({
    treeId: "tree-a",
    creatorId: "user-a",
    personData: {
      firstName: "Мария",
      lastName: "Кузнецова",
      gender: "female",
    },
  });

  const updated = await store.updatePerson("tree-a", created.id, {
    birthDatePrecision: "yearOnly", // даты-то нет
  });
  assert.equal(updated.birthDate, null);
  assert.equal(updated.birthDatePrecision, "exact");
});
