// B2: статус союза на узле — бывший супруг/партнёр любому узлу. Тип
// остаётся примитивным (spouse/partner), «бывший» — свойство союза
// (unionStatus='past'). Граф выводит метку бывшего союза; текущий супруг
// не регрессирует.

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");

const {FileStore} = require("../src/store");

async function seededStore() {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-union-"));
  const dataPath = path.join(tempDir, "dev-db.json");

  const bootstrap = new FileStore(dataPath);
  await bootstrap.initialize();

  const db = JSON.parse(await fs.readFile(dataPath, "utf8"));
  db.users = [
    {id: "user-a", email: "a@rodnya.app", profile: {displayName: "Артём"}},
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

async function makePerson(store, name, gender, {userId = null} = {}) {
  const person = await store.createPerson({
    treeId: "tree-a",
    creatorId: "user-a",
    userId,
    personData: {firstName: name, lastName: "Тест", gender},
  });
  return person.id;
}

function labelFor(snapshot, personId) {
  const descriptor = snapshot.viewerDescriptors.find(
    (entry) => entry.personId === personId,
  );
  return descriptor ? descriptor.primaryRelationLabel : null;
}

test("B2: spouse с unionStatus=past персистится и граф выводит «Бывшая жена»", async () => {
  const store = await seededStore();
  const meId = await makePerson(store, "Артём", "male", {userId: "user-a"});
  const exWifeId = await makePerson(store, "Бывшая", "female");

  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: meId,
    person2Id: exWifeId,
    relation1to2: "spouse",
    relation2to1: "spouse",
    unionStatus: "past",
  });

  // Персист: статус союза сохранён как past (тип остаётся spouse).
  const relations = await store.listRelations("tree-a");
  const union = relations.find(
    (relation) =>
      (relation.person1Id === meId && relation.person2Id === exWifeId) ||
      (relation.person1Id === exWifeId && relation.person2Id === meId),
  );
  assert.ok(union, "союз должен сохраниться");
  assert.equal(union.unionStatus, "past");

  // Граф: метка бывшего союза (гендерная).
  const snapshot = await store.getTreeGraphSnapshot("tree-a", {
    viewerUserId: "user-a",
  });
  assert.equal(labelFor(snapshot, exWifeId), "Бывшая жена");
});

test("B2: текущий супруг остаётся «Жена» (без регресса)", async () => {
  const store = await seededStore();
  const meId = await makePerson(store, "Артём", "male", {userId: "user-a"});
  const wifeId = await makePerson(store, "Жена", "female");

  // Без unionStatus → текущий союз (дефолтное поведение не меняется).
  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: meId,
    person2Id: wifeId,
    relation1to2: "spouse",
    relation2to1: "spouse",
  });

  const snapshot = await store.getTreeGraphSnapshot("tree-a", {
    viewerUserId: "user-a",
  });
  assert.equal(labelFor(snapshot, wifeId), "Жена");
});

test("B2: бывший партнёр (partner+past) → «Бывший партнёр»", async () => {
  const store = await seededStore();
  const meId = await makePerson(store, "Артём", "male", {userId: "user-a"});
  const exId = await makePerson(store, "Бывший", "male");

  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: meId,
    person2Id: exId,
    relation1to2: "partner",
    relation2to1: "partner",
    unionStatus: "past",
  });

  const snapshot = await store.getTreeGraphSnapshot("tree-a", {
    viewerUserId: "user-a",
  });
  assert.equal(labelFor(snapshot, exId), "Бывший партнёр");
});
