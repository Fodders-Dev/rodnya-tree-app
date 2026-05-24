// Phase B Week 2 Ship 1: store-level семья + membership CRUD tests.
//
// Scope (per ENTITY-DESIGN.md §1 + §3):
// • createSemya happy path (semya + owner membership atomic)
// • findSemyaById / listSemyiForUser query correctness
// • listMembershipsForSemya / findMembership
// • One-tree-per-семья invariant rejection
// • Validation errors на missing/invalid fields
//
// HTTP routes coming in Ship 2 (semya-routes.js). Этот test file
// strictly validates store layer без endpoint wiring.

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");

const {FileStore} = require("../src/store");

async function makeStore() {
  const tempDir = await fs.mkdtemp(
    path.join(os.tmpdir(), "rodnya-semya-"),
  );
  const dataPath = path.join(tempDir, "dev-db.json");
  const store = new FileStore(dataPath);
  await store.initialize();
  return {store, tempDir};
}

async function seedUserAndTree(store, {email = "test@example.com"} = {}) {
  const user = await store.createUser({
    email,
    passwordHash: "test-hash",
    profile: {firstName: "Test", lastName: "User"},
  });
  const tree = await store.createTree({
    creatorId: user.id,
    name: "Test семейное дерево",
    description: "",
    isPrivate: true,
    kind: "family",
  });
  return {user, tree};
}

test("Phase B createSemya creates семья + atomic owner membership", async () => {
  const {store, tempDir} = await makeStore();
  try {
    const {user, tree} = await seedUserAndTree(store);

    const semya = await store.createSemya({
      ownerId: user.id,
      name: "Семья Тестовых",
      treeId: tree.id,
      description: "Test семья description",
    });

    assert.ok(semya.id, "семья has id");
    assert.equal(semya.name, "Семья Тестовых");
    assert.equal(semya.ownerId, user.id);
    assert.equal(semya.treeId, tree.id);
    assert.equal(semya.description, "Test семья description");
    assert.equal(semya.deletedAt, null);
    assert.ok(semya.createdAt && semya.updatedAt);

    // Atomic owner membership row created
    const memberships = await store.listMembershipsForSemya(semya.id);
    assert.equal(memberships.length, 1);
    const owner = memberships[0];
    assert.equal(owner.userId, user.id);
    assert.equal(owner.role, "owner");
    assert.equal(owner.hasInviteGrant, true);
    assert.equal(owner.invitedByUserId, null);
    assert.equal(owner.hiddenAt, null);
  } finally {
    await fs.rm(tempDir, {recursive: true, force: true});
  }
});

test("Phase B findSemyaById returns семья либо null", async () => {
  const {store, tempDir} = await makeStore();
  try {
    const {user, tree} = await seedUserAndTree(store);
    const created = await store.createSemya({
      ownerId: user.id,
      name: "Семья Findable",
      treeId: tree.id,
    });

    const found = await store.findSemyaById(created.id);
    assert.equal(found?.id, created.id);

    const missing = await store.findSemyaById("00000000-0000-0000-0000-000000000000");
    assert.equal(missing, null);

    // Bad input — falsy/non-string
    assert.equal(await store.findSemyaById(""), null);
    assert.equal(await store.findSemyaById(null), null);
    assert.equal(await store.findSemyaById(undefined), null);
  } finally {
    await fs.rm(tempDir, {recursive: true, force: true});
  }
});

test("Phase B listSemyiForUser returns только membership-bound семьи", async () => {
  const {store, tempDir} = await makeStore();
  try {
    const {user: userA, tree: treeA} = await seedUserAndTree(store, {
      email: "a@example.com",
    });
    const {user: userB, tree: treeB} = await seedUserAndTree(store, {
      email: "b@example.com",
    });

    const semyaA1 = await store.createSemya({
      ownerId: userA.id,
      name: "Семья A1",
      treeId: treeA.id,
    });
    const semyaB1 = await store.createSemya({
      ownerId: userB.id,
      name: "Семья B1",
      treeId: treeB.id,
    });

    const aSemyi = await store.listSemyiForUser(userA.id);
    const bSemyi = await store.listSemyiForUser(userB.id);

    assert.equal(aSemyi.length, 1, "A видит только свою семью");
    assert.equal(aSemyi[0].id, semyaA1.id);

    assert.equal(bSemyi.length, 1, "B видит только свою семью");
    assert.equal(bSemyi[0].id, semyaB1.id);

    // Empty/unknown user id → empty array
    assert.deepEqual(await store.listSemyiForUser(""), []);
    assert.deepEqual(await store.listSemyiForUser("unknown-id"), []);
  } finally {
    await fs.rm(tempDir, {recursive: true, force: true});
  }
});

test("Phase B findMembership returns row или null", async () => {
  const {store, tempDir} = await makeStore();
  try {
    const {user, tree} = await seedUserAndTree(store);
    const semya = await store.createSemya({
      ownerId: user.id,
      name: "Семья Membership",
      treeId: tree.id,
    });

    const membership = await store.findMembership(semya.id, user.id);
    assert.equal(membership?.userId, user.id);
    assert.equal(membership?.role, "owner");

    // Wrong semyaId либо userId → null
    assert.equal(
      await store.findMembership("bad-semya-id", user.id),
      null,
    );
    assert.equal(
      await store.findMembership(semya.id, "bad-user-id"),
      null,
    );
  } finally {
    await fs.rm(tempDir, {recursive: true, force: true});
  }
});

test("Phase B createSemya rejects одинаковый tree dvazhdy (one-tree-per-семья invariant §3.1)", async () => {
  const {store, tempDir} = await makeStore();
  try {
    const {user, tree} = await seedUserAndTree(store);
    await store.createSemya({
      ownerId: user.id,
      name: "Первая семья",
      treeId: tree.id,
    });

    await assert.rejects(
      store.createSemya({
        ownerId: user.id,
        name: "Дублирующая семья",
        treeId: tree.id,
      }),
      {message: "TREE_ALREADY_BOUND"},
    );
  } finally {
    await fs.rm(tempDir, {recursive: true, force: true});
  }
});

test("Phase B createSemya rejects missing либо invalid fields", async () => {
  const {store, tempDir} = await makeStore();
  try {
    const {user, tree} = await seedUserAndTree(store);

    await assert.rejects(
      store.createSemya({ownerId: "", name: "Семья", treeId: tree.id}),
      {message: "INVALID_OWNER_ID"},
    );
    await assert.rejects(
      store.createSemya({ownerId: user.id, name: "", treeId: tree.id}),
      {message: "INVALID_NAME"},
    );
    await assert.rejects(
      store.createSemya({ownerId: user.id, name: "Семья", treeId: ""}),
      {message: "INVALID_TREE_ID"},
    );
    await assert.rejects(
      store.createSemya({
        ownerId: "00000000-0000-0000-0000-000000000000",
        name: "Семья",
        treeId: tree.id,
      }),
      {message: "OWNER_NOT_FOUND"},
    );
    await assert.rejects(
      store.createSemya({
        ownerId: user.id,
        name: "Семья",
        treeId: "00000000-0000-0000-0000-000000000000",
      }),
      {message: "TREE_NOT_FOUND"},
    );
  } finally {
    await fs.rm(tempDir, {recursive: true, force: true});
  }
});
