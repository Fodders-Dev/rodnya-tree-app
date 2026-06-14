// B3: со-родительство достраивается симметрично — при создании ребра
// parent→child И при создании/«текущести» брака; существующие деревья
// само-лечатся при следующей мутации. Гарды строгие: единственный
// родитель в наборе + ровно один ТЕКУЩИЙ супруг + супруг ещё не родитель;
// past/divorced не триггерят; набор с 2 родителями не дублируется.

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");

const {FileStore} = require("../src/store");

async function seededStore() {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-coparent-"));
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

  return {store: new FileStore(dataPath), dataPath};
}

async function makePerson(store, name, gender) {
  const person = await store.createPerson({
    treeId: "tree-a",
    creatorId: "user-a",
    personData: {firstName: name, lastName: "Тест", gender},
  });
  return person.id;
}

function parentIdsOf(relations, childId) {
  const ids = new Set();
  for (const relation of relations) {
    if (relation.relation1to2 === "parent" && relation.person2Id === childId) {
      ids.add(relation.person1Id);
    } else if (
      relation.relation2to1 === "parent" &&
      relation.person1Id === childId
    ) {
      ids.add(relation.person2Id);
    }
  }
  return ids;
}

test("B3 (a): союз есть, потом parent→child → второй родитель достраивается", async () => {
  const {store} = await seededStore();
  const motherId = await makePerson(store, "Мать", "female");
  const fatherId = await makePerson(store, "Отец", "male");
  const childId = await makePerson(store, "Дочь", "female");

  // Сначала текущий брак.
  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: motherId,
    person2Id: fatherId,
    relation1to2: "spouse",
    relation2to1: "spouse",
  });
  // Потом мать привязывается к ребёнку.
  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: motherId,
    person2Id: childId,
    relation1to2: "parent",
    relation2to1: "child",
  });

  const parents = parentIdsOf(await store.listRelations("tree-a"), childId);
  assert.deepEqual([...parents].sort(), [motherId, fatherId].sort());
});

test("B3 (b): parent→child есть, потом брак → второй родитель достраивается (новый триггер)", async () => {
  const {store} = await seededStore();
  const motherId = await makePerson(store, "Мать", "female");
  const fatherId = await makePerson(store, "Отец", "male");
  const childId = await makePerson(store, "Дочь", "female");

  // Сначала мать привязана к ребёнку — отца ещё нет.
  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: motherId,
    person2Id: childId,
    relation1to2: "parent",
    relation2to1: "child",
  });
  let parents = parentIdsOf(await store.listRelations("tree-a"), childId);
  assert.deepEqual([...parents], [motherId]);

  // Муж добавлен ПОЗЖЕ — со-родительство достраивается по новому триггеру.
  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: motherId,
    person2Id: fatherId,
    relation1to2: "spouse",
    relation2to1: "spouse",
  });
  parents = parentIdsOf(await store.listRelations("tree-a"), childId);
  assert.deepEqual([...parents].sort(), [motherId, fatherId].sort());
});

test("B3 (c): предсуществующее sole-parent+супруг дерево лечится при следующей мутации", async () => {
  const {store, dataPath} = await seededStore();
  const motherId = await makePerson(store, "Мать", "female");
  const fatherId = await makePerson(store, "Отец", "male");
  const childId = await makePerson(store, "Дочь", "female");
  const grandmaId = await makePerson(store, "Бабушка", "female");

  // Симулируем «старое» сломанное дерево: правим JSON напрямую —
  // мать привязана к ребёнку, брак есть, но отец НЕ родитель.
  const now = new Date().toISOString();
  const db = JSON.parse(await fs.readFile(dataPath, "utf8"));
  db.relations.push(
    {
      id: "rel-mother-child",
      treeId: "tree-a",
      person1Id: motherId,
      person2Id: childId,
      relation1to2: "parent",
      relation2to1: "child",
      parentSetId: `ps:tree-a:${childId}:biological:0`,
      parentSetType: "biological",
      isPrimaryParentSet: true,
      isConfirmed: true,
      createdAt: now,
      updatedAt: now,
    },
    {
      id: "rel-mother-father",
      treeId: "tree-a",
      person1Id: motherId,
      person2Id: fatherId,
      relation1to2: "spouse",
      relation2to1: "spouse",
      unionStatus: "current",
      isConfirmed: true,
      createdAt: now,
      updatedAt: now,
    },
  );
  await fs.writeFile(dataPath, JSON.stringify(db, null, 2));

  const freshStore = new FileStore(dataPath);
  // До мутации отец не родитель.
  let parents = parentIdsOf(await freshStore.listRelations("tree-a"), childId);
  assert.deepEqual([...parents], [motherId]);

  // Любая мутация дерева запускает идемпотентный гард-проход → лечит.
  await freshStore.upsertRelation({
    treeId: "tree-a",
    person1Id: grandmaId,
    person2Id: motherId,
    relation1to2: "parent",
    relation2to1: "child",
  });

  parents = parentIdsOf(await freshStore.listRelations("tree-a"), childId);
  assert.deepEqual([...parents].sort(), [motherId, fatherId].sort());
});

test("B3 (d): past/divorced союз НЕ достраивает второго родителя", async () => {
  const {store} = await seededStore();
  const motherId = await makePerson(store, "Мать", "female");
  const exId = await makePerson(store, "Бывший", "male");
  const childId = await makePerson(store, "Дочь", "female");

  // Бывший супруг (past).
  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: motherId,
    person2Id: exId,
    relation1to2: "ex_spouse",
    relation2to1: "ex_spouse",
  });
  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: motherId,
    person2Id: childId,
    relation1to2: "parent",
    relation2to1: "child",
  });

  const parents = parentIdsOf(await store.listRelations("tree-a"), childId);
  assert.deepEqual([...parents], [motherId],
    "бывший супруг не должен авто-стать родителем");
});

test("B3 (f): явный step-родитель не перезаписывается в biological", async () => {
  const {store} = await seededStore();
  const motherId = await makePerson(store, "Мать", "female");
  const stepId = await makePerson(store, "Отчим", "male");
  const childId = await makePerson(store, "Ребёнок", "female");

  // Биологическая мать.
  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: motherId,
    person2Id: childId,
    relation1to2: "parent",
    relation2to1: "child",
  });
  // Отчим ЯВНО записан как step-родитель (отдельный набор).
  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: stepId,
    person2Id: childId,
    relation1to2: "parent",
    relation2to1: "child",
    parentSetType: "step",
  });
  // Брак матери и отчима — триггерит со-родительство.
  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: motherId,
    person2Id: stepId,
    relation1to2: "spouse",
    relation2to1: "spouse",
  });

  const relations = await store.listRelations("tree-a");
  const stepEdge = relations.find(
    (relation) =>
      (relation.person1Id === stepId &&
        relation.person2Id === childId &&
        relation.relation1to2 === "parent") ||
      (relation.person1Id === childId &&
        relation.person2Id === stepId &&
        relation.relation2to1 === "parent"),
  );
  assert.ok(stepEdge, "явная step-связь должна сохраниться");
  assert.equal(stepEdge.parentSetType, "step",
    "step-статус не должен схлопнуться в biological");
});

test("B3 (g): супруг приёмной матери НЕ достраивается (adoptive не идёт через брак)", async () => {
  const {store} = await seededStore();
  const momId = await makePerson(store, "Приёмная мать", "female");
  const husbandId = await makePerson(store, "Муж", "male");
  const childId = await makePerson(store, "Ребёнок", "female");

  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: momId,
    person2Id: childId,
    relation1to2: "parent",
    relation2to1: "child",
    parentSetType: "adoptive",
  });
  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: momId,
    person2Id: husbandId,
    relation1to2: "spouse",
    relation2to1: "spouse",
  });

  const parents = parentIdsOf(await store.listRelations("tree-a"), childId);
  assert.deepEqual([...parents], [momId],
    "супруг приёмной матери не должен авто-стать родителем ребёнка");
});

test("B3 (e): у ребёнка уже 2 родителя — не дублируется и не ломается", async () => {
  const {store} = await seededStore();
  const motherId = await makePerson(store, "Мать", "female");
  const fatherId = await makePerson(store, "Отец", "male");
  const childId = await makePerson(store, "Дочь", "female");

  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: motherId,
    person2Id: childId,
    relation1to2: "parent",
    relation2to1: "child",
  });
  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: fatherId,
    person2Id: childId,
    relation1to2: "parent",
    relation2to1: "child",
  });
  // Брак поверх уже-полного набора родителей.
  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: motherId,
    person2Id: fatherId,
    relation1to2: "spouse",
    relation2to1: "spouse",
  });

  const relations = await store.listRelations("tree-a");
  const parents = parentIdsOf(relations, childId);
  assert.deepEqual([...parents].sort(), [motherId, fatherId].sort());
  // Ровно две parent→child связи к ребёнку — без дублей.
  const parentEdges = relations.filter(
    (relation) =>
      (relation.relation1to2 === "parent" && relation.person2Id === childId) ||
      (relation.relation2to1 === "parent" && relation.person1Id === childId),
  );
  assert.equal(parentEdges.length, 2);
});
