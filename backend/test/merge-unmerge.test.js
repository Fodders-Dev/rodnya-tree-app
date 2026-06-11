// D1: un-merge identity — полное слияние пишет журнал, разъединение по
// журналу восстанавливает identities (включая absorbed userId), история
// сохраняется, повторный матч может предложить заново. Легаси-boolean
// (слияние до журнала) — честный отказ.

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");

const {FileStore} = require("../src/store");

async function seededStore() {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-unmerge-"));
  const dataPath = path.join(tempDir, "dev-db.json");

  const bootstrap = new FileStore(dataPath);
  await bootstrap.initialize();

  const db = JSON.parse(await fs.readFile(dataPath, "utf8"));
  db.users = [
    {id: "user-a", email: "a@rodnya.app", profile: {displayName: "Артём"}},
    {id: "user-b", email: "b@rodnya.app", profile: {displayName: "Наталья"}},
  ];
  db.trees = [
    {
      id: "tree-a",
      name: "Семья А",
      creatorId: "user-a",
      memberIds: ["user-a"],
      members: ["user-a"],
    },
    {
      id: "tree-b",
      name: "Семья Б",
      creatorId: "user-b",
      memberIds: ["user-b"],
      members: ["user-b"],
    },
  ];
  db.persons = [
    {
      id: "p-a",
      treeId: "tree-a",
      identityId: "identity-a",
      name: "Иванов Иван Петрович",
      gender: "male",
      birthDate: "1970-03-12T00:00:00.000Z",
      isAlive: true,
    },
    {
      id: "p-b",
      treeId: "tree-b",
      identityId: "identity-b",
      name: "Иванов Иван Петрович",
      gender: "male",
      birthDate: "1970-03-12T00:00:00.000Z",
      isAlive: true,
    },
  ];
  db.personIdentities = [
    {
      id: "identity-a",
      userId: null,
      claimedByUserId: null,
      personIds: ["p-a"],
      stewardUserIds: ["user-a"],
      isLiving: true,
      isPublicDiscoverable: true,
    },
    {
      id: "identity-b",
      // У source есть привязанный пользователь — target его поглотит,
      // а unmerge обязан вернуть.
      userId: "user-b",
      claimedByUserId: "user-b",
      personIds: ["p-b"],
      stewardUserIds: ["user-b"],
      isLiving: true,
      isPublicDiscoverable: true,
    },
  ];
  db.personAttributes = [
    {
      id: "attr-b-1",
      identityId: "identity-b",
      sourcePersonId: "p-b",
      type: "birthDate",
      status: "active",
    },
  ];
  db.mergeProposals = [
    {
      id: "mp-1",
      fromPersonId: "p-a",
      candidatePersonId: "p-b",
      toIdentityId: "identity-a",
      candidateIdentityId: "identity-b",
      reviewerUserIds: ["user-a", "user-b"],
      reviews: [],
      status: "pending",
      matchScore: 0.92,
      reasons: ["Совпадает ФИО"],
      createdAt: new Date().toISOString(),
    },
  ];
  await fs.writeFile(dataPath, JSON.stringify(db, null, 2));

  const store = new FileStore(dataPath);
  await store.initialize();
  return {store, dataPath};
}

async function acceptBoth(store) {
  await store.reviewMergeProposal({
    proposalId: "mp-1",
    reviewerUserId: "user-a",
    decision: "accept",
  });
  return store.reviewMergeProposal({
    proposalId: "mp-1",
    reviewerUserId: "user-b",
    decision: "accept",
  });
}

test("merge пишет журнал; unmerge восстанавливает identities и absorbed userId", async () => {
  const {store, dataPath} = await seededStore();

  const accepted = await acceptBoth(store);
  assert.equal(accepted.status, "accepted");

  // Журнал заполнен.
  let db = JSON.parse(await fs.readFile(dataPath, "utf8"));
  const applied = db.mergeProposals[0].mergeApplied;
  assert.ok(applied && typeof applied === "object", "журнал — объект");
  assert.deepEqual(applied.movedPersonIds, ["p-b"]);
  assert.deepEqual(applied.movedAttributeIds, ["attr-b-1"]);
  assert.equal(applied.sourceIdentityId, "identity-b");
  assert.equal(applied.targetIdentityId, "identity-a");
  assert.equal(applied.userIdAbsorbed, true);
  assert.equal(applied.claimedByAbsorbed, true);
  assert.ok(applied.appliedAt);

  // Слияние реально применилось.
  const personB = db.persons.find((p) => p.id === "p-b");
  assert.equal(personB.identityId, "identity-a");
  const targetAfterMerge = db.personIdentities.find(
    (i) => i.id === "identity-a",
  );
  assert.equal(targetAfterMerge.userId, "user-b");
  const sourceAfterMerge = db.personIdentities.find(
    (i) => i.id === "identity-b",
  );
  assert.equal(sourceAfterMerge.mergedInto, "identity-a");

  // Видно в списке «Объединённые ранее» обоим ответственным.
  const mergedForA = await store.listMergedProposalsForUser("user-a");
  assert.equal(mergedForA.length, 1);
  assert.equal(mergedForA[0].id, "mp-1");

  // Разъединяем (право — любой ответственный; жмёт user-a).
  const unmerged = await store.unmergeMergeProposal({
    proposalId: "mp-1",
    actorUserId: "user-a",
  });
  assert.equal(unmerged.status, "unmerged");

  db = JSON.parse(await fs.readFile(dataPath, "utf8"));
  const source = db.personIdentities.find((i) => i.id === "identity-b");
  assert.equal(source.mergedInto, null);
  assert.deepEqual(source.personIds, ["p-b"]);
  // В публичный поиск не возвращаем — включают осознанно.
  assert.equal(source.isPublicDiscoverable, false);

  const target = db.personIdentities.find((i) => i.id === "identity-a");
  assert.equal(target.userId, null, "absorbed userId снят");
  assert.equal(target.claimedByUserId, null, "absorbed claimedBy снят");
  assert.ok(!(target.personIds || []).includes("p-b"));

  const personBRestored = db.persons.find((p) => p.id === "p-b");
  assert.equal(personBRestored.identityId, "identity-b");
  const attr = db.personAttributes.find((a) => a.id === "attr-b-1");
  assert.equal(attr.identityId, "identity-b");

  // История сохраняется, из «Объединённых ранее» предложение ушло.
  assert.equal(db.mergeProposals[0].status, "unmerged");
  assert.ok(db.mergeProposals[0].unmergedAt);
  const mergedAfter = await store.listMergedProposalsForUser("user-a");
  assert.equal(mergedAfter.length, 0);
});

test("после unmerge повторный merge возможен", async () => {
  const {store, dataPath} = await seededStore();
  await acceptBoth(store);
  await store.unmergeMergeProposal({proposalId: "mp-1", actorUserId: "user-b"});

  // Повторный матч — новое предложение на те же identity.
  const db = JSON.parse(await fs.readFile(dataPath, "utf8"));
  db.mergeProposals.push({
    id: "mp-2",
    fromPersonId: "p-a",
    candidatePersonId: "p-b",
    toIdentityId: "identity-a",
    candidateIdentityId: "identity-b",
    reviewerUserIds: ["user-a", "user-b"],
    reviews: [],
    status: "pending",
    matchScore: 0.92,
    reasons: ["Совпадает ФИО"],
    createdAt: new Date().toISOString(),
  });
  await fs.writeFile(dataPath, JSON.stringify(db, null, 2));
  const store2 = new FileStore(dataPath);
  await store2.initialize();

  await store2.reviewMergeProposal({
    proposalId: "mp-2",
    reviewerUserId: "user-a",
    decision: "accept",
  });
  const accepted = await store2.reviewMergeProposal({
    proposalId: "mp-2",
    reviewerUserId: "user-b",
    decision: "accept",
  });
  assert.equal(accepted.status, "accepted");

  const dbAfter = JSON.parse(await fs.readFile(dataPath, "utf8"));
  const personB = dbAfter.persons.find((p) => p.id === "p-b");
  assert.equal(personB.identityId, "identity-a");
});

test("права и легаси: не-ревьюер 403-сценарий, легаси-boolean — отказ", async () => {
  const {store, dataPath} = await seededStore();
  await acceptBoth(store);

  // Чужак — false (роут переведёт в 403).
  const stranger = await store.unmergeMergeProposal({
    proposalId: "mp-1",
    actorUserId: "user-zzz",
  });
  assert.equal(stranger, false);

  // Несуществующее — null (404).
  const missing = await store.unmergeMergeProposal({
    proposalId: "mp-nope",
    actorUserId: "user-a",
  });
  assert.equal(missing, null);

  // Легаси: mergeApplied = true (до журнала) — честный отказ.
  const db = JSON.parse(await fs.readFile(dataPath, "utf8"));
  db.mergeProposals[0].mergeApplied = true;
  await fs.writeFile(dataPath, JSON.stringify(db, null, 2));
  const store2 = new FileStore(dataPath);
  await store2.initialize();

  const legacy = await store2.unmergeMergeProposal({
    proposalId: "mp-1",
    actorUserId: "user-a",
  });
  assert.deepEqual(legacy, {error: "legacy"});
});

test("удалённые с момента слияния persons пропускаются молча", async () => {
  const {store, dataPath} = await seededStore();
  await acceptBoth(store);

  // Карточку p-b удалили после слияния.
  const db = JSON.parse(await fs.readFile(dataPath, "utf8"));
  db.persons = db.persons.filter((p) => p.id !== "p-b");
  await fs.writeFile(dataPath, JSON.stringify(db, null, 2));
  const store2 = new FileStore(dataPath);
  await store2.initialize();

  const unmerged = await store2.unmergeMergeProposal({
    proposalId: "mp-1",
    actorUserId: "user-a",
  });
  assert.equal(unmerged.status, "unmerged");

  const dbAfter = JSON.parse(await fs.readFile(dataPath, "utf8"));
  const source = dbAfter.personIdentities.find((i) => i.id === "identity-b");
  assert.equal(source.mergedInto, null);
  assert.deepEqual(source.personIds, [], "удалённая карточка не вернулась");
});
