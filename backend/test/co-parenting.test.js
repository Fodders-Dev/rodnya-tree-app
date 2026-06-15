// B3 (ревью): со-родительство достраивается УЗКО — ТОЛЬКО при явном
// создании ребра parent→child и ТОЛЬКО для набора этого ребёнка. НЕ на
// браке, НЕ задним числом, НЕ по всему дереву. Данные не отличают
// «нуклеарную семью» от «повторного брака на постороннем ребёнку», поэтому
// прежняя широкая автоматика (триггер на браке + tree-wide backfill)
// корраптила сводные семьи. Гарды: единственный родитель в наборе +
// биологический набор + ровно один текущий СУПРУГ/ПАРТНЁР (романтический;
// friend/other/past исключены) + партнёр ещё не родитель ребёнка.

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

test("B3 (e): узкий валидный кейс — текущий супруг есть, потом parent→child → второй родитель достраивается", async () => {
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
  // Потом мать привязывается к ребёнку — это явное ребро parent→child,
  // на нём (и только на нём) достраиваем второго родителя.
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

test("B3 (a): повторный брак ПОСЛЕ привязки к ребёнку НЕ делает нового супруга родителем", async () => {
  const {store} = await seededStore();
  const motherId = await makePerson(store, "Мать", "female");
  const exId = await makePerson(store, "Бывший", "male");
  const childId = await makePerson(store, "Дочь", "female");
  const newSpouseId = await makePerson(store, "Новый муж", "male");

  // Ребёнок из прошлого союза: мать привязана к ребёнку (отца ещё нет).
  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: motherId,
    person2Id: childId,
    relation1to2: "parent",
    relation2to1: "child",
  });
  // Прошлый союз (для контекста сводной семьи).
  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: motherId,
    person2Id: exId,
    relation1to2: "ex_spouse",
    relation2to1: "ex_spouse",
  });
  // Мать выходит замуж повторно — БРАК создаётся ПОСЛЕ привязки к ребёнку.
  // Это НЕ ребро parent→child → со-родительство НЕ срабатывает: посторонний
  // ребёнку человек не должен молча стать его биологическим родителем.
  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: motherId,
    person2Id: newSpouseId,
    relation1to2: "spouse",
    relation2to1: "spouse",
  });

  const parents = parentIdsOf(await store.listRelations("tree-a"), childId);
  assert.deepEqual([...parents], [motherId],
    "новый супруг не должен авто-стать родителем ребёнка из прошлого союза");
});

test("B3 (d): несвязанная мутация НЕ переписывает родителей чужого ребёнка (нет backfill)", async () => {
  const {store, dataPath} = await seededStore();
  const motherId = await makePerson(store, "Мать", "female");
  const fatherId = await makePerson(store, "Отчим", "male");
  const childId = await makePerson(store, "Дочь", "female");
  const grandmaId = await makePerson(store, "Бабушка", "female");

  // «Старое» дерево: мать привязана к ребёнку, есть текущий брак с мужчиной,
  // но муж НЕ записан родителем (он мог быть отчимом). Правим JSON напрямую.
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
      id: "rel-mother-husband",
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
  // Несвязанная мутация: добавляем бабушку как родителя МАТЕРИ.
  await freshStore.upsertRelation({
    treeId: "tree-a",
    person1Id: grandmaId,
    person2Id: motherId,
    relation1to2: "parent",
    relation2to1: "child",
  });

  // Набор ребёнка не трогался: муж матери НЕ должен быть подтянут в родители
  // (никакого молчаливого backfill существующих деревьев).
  const parents = parentIdsOf(await freshStore.listRelations("tree-a"), childId);
  assert.deepEqual([...parents], [motherId],
    "несвязанная мутация не должна переписывать родителей ребёнка");
});

test("B3 (b): 'friend'-союз НЕ делает друга родителем (FR2 — только spouse/partner)", async () => {
  const {store} = await seededStore();
  const motherId = await makePerson(store, "Мать", "female");
  const friendId = await makePerson(store, "Друг", "male");
  const childId = await makePerson(store, "Дочь", "female");

  // Текущий союз типа 'friend' (не романтический).
  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: motherId,
    person2Id: friendId,
    relation1to2: "friend",
    relation2to1: "friend",
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
    "друг (friend-союз) не должен авто-стать родителем ребёнка");
});

test("B3 (c): past/divorced союз НЕ достраивает второго родителя", async () => {
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

  // Биологическая мать (одна в наборе).
  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: motherId,
    person2Id: childId,
    relation1to2: "parent",
    relation2to1: "child",
  });
  // Отчим ЯВНО записан как step-родитель (отдельный набор) — он уже родитель
  // ребёнка, поэтому узкий триггер его не дублирует и не схлопывает в bio.
  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: stepId,
    person2Id: childId,
    relation1to2: "parent",
    relation2to1: "child",
    parentSetType: "step",
  });
  // Брак матери и отчима — НЕ триггерит со-родительство (узко: только на
  // ребре parent→child). step-набор остаётся step.
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

  // Текущий брак, затем привязка к ребёнку в adoptive-наборе — биологический
  // гард должен отсечь достройку (приёмный статус персональный).
  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: momId,
    person2Id: husbandId,
    relation1to2: "spouse",
    relation2to1: "spouse",
  });
  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: momId,
    person2Id: childId,
    relation1to2: "parent",
    relation2to1: "child",
    parentSetType: "adoptive",
  });

  const parents = parentIdsOf(await store.listRelations("tree-a"), childId);
  assert.deepEqual([...parents], [momId],
    "супруг приёмной матери не должен авто-стать родителем ребёнка");
});

test("B3 (h): у ребёнка уже 2 родителя — не дублируется и не ломается", async () => {
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
  // Брак поверх уже-полного набора родителей — ничего не достраивает.
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

// Сводная семья: у матери ребёнок из ПРОШЛОГО союза (только она) и общий
// ребёнок с партнёром P. Прежняя tree-wide материализация sibling-вывода
// (_materializeInferredParentLinks) молча ПЕРСИСТИЛА P биологическим
// родителем ребёнка из прошлого союза — по любому союзу (friend/ex/past),
// мимо всех B3-гардов, на любой мутации. Эти тесты пиннят, что вывод
// больше НЕ материализуется (ревью F1).
async function buildHalfSiblingTree(store, unionRelation) {
  const motherId = await makePerson(store, "Мать", "female");
  const partnerId = await makePerson(store, "Партнёр", "male");
  const childPriorId = await makePerson(store, "Ребёнок-прошлый", "female");
  const childSharedId = await makePerson(store, "Ребёнок-общий", "male");
  const grandmaId = await makePerson(store, "Бабушка", "female");

  // Союз матери и партнёра (friend / ex_spouse — НЕ текущий романтический).
  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: motherId,
    person2Id: partnerId,
    relation1to2: unionRelation,
    relation2to1: unionRelation,
  });
  // Ребёнок из прошлого союза — только мать.
  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: motherId,
    person2Id: childPriorId,
    relation1to2: "parent",
    relation2to1: "child",
  });
  // Общий ребёнок — мать + партнёр (набор из 2 родителей).
  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: motherId,
    person2Id: childSharedId,
    relation1to2: "parent",
    relation2to1: "child",
  });
  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: partnerId,
    person2Id: childSharedId,
    relation1to2: "parent",
    relation2to1: "child",
  });
  // Несвязанная мутация — раньше она триггерила tree-wide материализацию.
  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: grandmaId,
    person2Id: motherId,
    relation1to2: "parent",
    relation2to1: "child",
  });
  return {motherId, partnerId, childPriorId};
}

test("B3 (ревью F1): friend-союз с общим ребёнком НЕ персистит друга родителем ребёнка из прошлого союза", async () => {
  const {store} = await seededStore();
  const {motherId, childPriorId} = await buildHalfSiblingTree(store, "friend");

  const parents = parentIdsOf(await store.listRelations("tree-a"), childPriorId);
  assert.deepEqual([...parents], [motherId],
    "друг не должен быть записан родителем ребёнка из прошлого союза");
});

test("B3 (ревью F1): ex-супруг с общим ребёнком НЕ персистится родителем ребёнка из прошлого союза", async () => {
  const {store} = await seededStore();
  const {motherId, childPriorId} = await buildHalfSiblingTree(store, "ex_spouse");

  const parents = parentIdsOf(await store.listRelations("tree-a"), childPriorId);
  assert.deepEqual([...parents], [motherId],
    "бывший супруг не должен быть записан родителем ребёнка из прошлого союза");
});

test("B3 (ревью F3): повторный upsert ребра parent→child ПОСЛЕ брака не ретро-линкует супруга", async () => {
  const {store} = await seededStore();
  const motherId = await makePerson(store, "Мать", "female");
  const childId = await makePerson(store, "Дочь", "female");
  const newSpouseId = await makePerson(store, "Новый муж", "male");

  // Привязка к ребёнку (супруга ещё нет).
  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: motherId,
    person2Id: childId,
    relation1to2: "parent",
    relation2to1: "child",
  });
  // Брак ПОСЛЕ привязки к ребёнку.
  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: motherId,
    person2Id: newSpouseId,
    relation1to2: "spouse",
    relation2to1: "spouse",
  });
  // Повторное сохранение ТОГО ЖЕ ребра parent→child (idempotent re-POST /
  // правка дат / подтверждение) — НЕ должно ретро-линковать нового супруга.
  await store.upsertRelation({
    treeId: "tree-a",
    person1Id: motherId,
    person2Id: childId,
    relation1to2: "parent",
    relation2to1: "child",
  });

  const parents = parentIdsOf(await store.listRelations("tree-a"), childId);
  assert.deepEqual([...parents], [motherId],
    "повторный upsert не должен ретро-линковать нового супруга родителем");
});
