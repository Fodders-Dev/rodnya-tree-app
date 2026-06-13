// K1: _mergeProposalView отдаёт зрителю его собственный статус
// (myDecision / awaitingMyDecision) и поимённый список ответственных
// (reviewers) — баннер на home обязан гаснуть сразу после голоса, а
// экран ревью показывает «Вы ✓ · Наталья — ждём» вместо безликого «0/2».

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");

const {FileStore} = require("../src/store");

async function seededStore() {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-mpv-"));
  const dataPath = path.join(tempDir, "dev-db.json");

  // Скелет схемы — от самого store, чтобы не дублировать дефолты.
  const bootstrap = new FileStore(dataPath);
  await bootstrap.initialize();

  const db = JSON.parse(await fs.readFile(dataPath, "utf8"));
  db.users = [
    {
      id: "user-a",
      email: "a@rodnya.app",
      profile: {displayName: "Артём"},
    },
    {
      id: "user-b",
      email: "b@rodnya.app",
      profile: {displayName: "Наталья"},
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
  db.mergeProposals = [
    {
      id: "mp-1",
      fromPersonId: "p-a",
      candidatePersonId: "p-b",
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
  return store;
}

test("view: до голоса awaitingMyDecision=true и поимённые ревьюеры", async () => {
  const store = await seededStore();

  const proposals = await store.listPendingMergeProposalsForUser("user-a");
  const mine = proposals.find((entry) => entry.id === "mp-1");
  assert.ok(mine, "посеянное предложение должно вернуться зрителю");

  assert.equal(mine.myDecision, null);
  assert.equal(mine.awaitingMyDecision, true);
  assert.equal(mine.reviewers.length, 2);

  const me = mine.reviewers.find((entry) => entry.userId === "user-a");
  const other = mine.reviewers.find((entry) => entry.userId === "user-b");
  assert.equal(me.isViewer, true);
  assert.equal(me.displayName, "Артём");
  assert.equal(me.decision, null);
  assert.equal(other.isViewer, false);
  assert.equal(other.displayName, "Наталья");
  assert.equal(other.decision, null);
});

test("view: ownership — своя карточка own, чужая other (A-copy бейдж)", async () => {
  const store = await seededStore();

  // Зритель user-a — стюард tree-a (его p-a), tree-b чужое.
  const forA = (await store.listPendingMergeProposalsForUser("user-a")).find(
    (entry) => entry.id === "mp-1",
  );
  assert.ok(forA);
  assert.equal(forA.personA.ownership, "own"); // p-a в его дереве
  assert.equal(forA.personB.ownership, "other"); // p-b в чужом

  // Симметрично для user-b — теперь своя карточка вторая.
  const forB = (await store.listPendingMergeProposalsForUser("user-b")).find(
    (entry) => entry.id === "mp-1",
  );
  assert.ok(forB);
  assert.equal(forB.personA.ownership, "other");
  assert.equal(forB.personB.ownership, "own");
});

test("view: после голоса myDecision=accepted, awaitingMyDecision=false, статус по-прежнему pending", async () => {
  const store = await seededStore();

  const reviewed = await store.reviewMergeProposal({
    proposalId: "mp-1",
    reviewerUserId: "user-a",
    decision: "accept",
  });

  assert.equal(reviewed.status, "pending"); // консенсус 1/2 — ждём второго
  assert.equal(reviewed.myDecision, "accepted");
  assert.equal(reviewed.awaitingMyDecision, false);
  const me = reviewed.reviewers.find((entry) => entry.userId === "user-a");
  assert.equal(me.decision, "accepted");

  // Список проголосовавшего: предложение остаётся (для секции «Ждём
  // других»), но решения зрителя больше не ждёт — баннер на home по
  // этому флагу гаснет.
  const mineAfter = await store.listPendingMergeProposalsForUser("user-a");
  const stillListed = mineAfter.find((entry) => entry.id === "mp-1");
  assert.ok(stillListed);
  assert.equal(stillListed.awaitingMyDecision, false);

  // А второй ответственный всё ещё должен видеть «ждём вас».
  const theirs = await store.listPendingMergeProposalsForUser("user-b");
  const waiting = theirs.find((entry) => entry.id === "mp-1");
  assert.ok(waiting);
  assert.equal(waiting.awaitingMyDecision, true);
  assert.equal(waiting.myDecision, null);
});
