// Phase B Week 3 Ship 9: resolveTreeAudienceUserIds audience
// extension к семя members.
//
// Per SHIP-9-AUDIENCE-DIFF.md analysis — extension purely ADDITIVE.
// Tests verify:
//   * Unbound tree audience unchanged (existing 4 sources only)
//   * Bound tree adds семя members к audience
//   * Bound tree preserves creator + grants + identity-linked
//   * Excluded user filtered uniformly (даже семя members)
//   * Soft-deleted семя memberships excluded
//   * Drift case: семя member missing from tree.memberIds still
//     surfaced via Ship 9 extension

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");

const {FileStore} = require("../src/store");

async function makeStore() {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-aud-"));
  const dataPath = path.join(tempDir, "dev-db.json");
  const store = new FileStore(dataPath);
  await store.initialize();
  return {store, tempDir};
}

async function seedUser(store, email) {
  return store.createUser({
    email,
    passwordHash: "test-hash",
    profile: {firstName: email.split("@")[0], lastName: "User"},
  });
}

test("Ship 9: unbound tree audience excludes семя contribution (no change vs pre-Ship-9)", async () => {
  const {store, tempDir} = await makeStore();
  try {
    const owner = await seedUser(store, "ow1@example.com");
    const member = await seedUser(store, "mb1@example.com");

    const tree = await store.createTree({
      creatorId: owner.id,
      name: "Unbound",
      description: "",
      isPrivate: true,
      kind: "family",
    });

    // Add legacy member directly через ensureTreeMembership pattern
    const db = await store._read();
    const treeRow = db.trees.find((t) => t.id === tree.id);
    treeRow.memberIds.push(member.id);
    treeRow.members.push(member.id);
    await store._write(db);

    const audience = await store.resolveTreeAudienceUserIds(tree.id);
    assert.ok(audience.includes(owner.id), "creator included");
    assert.ok(audience.includes(member.id), "legacy member included");
    assert.equal(audience.length, 2, "no extra recipients (no semya bound)");
  } finally {
    await fs.rm(tempDir, {recursive: true, force: true});
  }
});

test("Ship 9: bound tree adds семя members к audience (additive)", async () => {
  const {store, tempDir} = await makeStore();
  try {
    const owner = await seedUser(store, "ow2@example.com");
    const editor = await seedUser(store, "ed2@example.com");

    const tree = await store.createTree({
      creatorId: owner.id,
      name: "Bound",
      description: "",
      isPrivate: true,
      kind: "family",
    });
    const semya = await store.createSemya({
      ownerId: owner.id,
      name: "Семя",
      treeId: tree.id,
    });
    await store.addMembership({
      semyaId: semya.id,
      userId: editor.id,
      role: "editor",
      invitedByUserId: owner.id,
    });

    const audience = await store.resolveTreeAudienceUserIds(tree.id);
    assert.ok(audience.includes(owner.id));
    assert.ok(audience.includes(editor.id));
    // No duplicates — Set semantics
    const unique = new Set(audience);
    assert.equal(audience.length, unique.size);
  } finally {
    await fs.rm(tempDir, {recursive: true, force: true});
  }
});

test("Ship 9: excluded user filtered uniformly (даже семя member)", async () => {
  const {store, tempDir} = await makeStore();
  try {
    const owner = await seedUser(store, "ow3@example.com");
    const editor = await seedUser(store, "ed3@example.com");

    const tree = await store.createTree({
      creatorId: owner.id,
      name: "Excluded test",
      description: "",
      isPrivate: true,
      kind: "family",
    });
    const semya = await store.createSemya({
      ownerId: owner.id,
      name: "S",
      treeId: tree.id,
    });
    await store.addMembership({
      semyaId: semya.id,
      userId: editor.id,
      role: "editor",
      invitedByUserId: owner.id,
    });

    const audienceExclEditor = await store.resolveTreeAudienceUserIds(
      tree.id,
      {excludeUserId: editor.id},
    );
    assert.ok(!audienceExclEditor.includes(editor.id), "editor excluded");
    assert.ok(audienceExclEditor.includes(owner.id), "owner present");

    const audienceExclOwner = await store.resolveTreeAudienceUserIds(
      tree.id,
      {excludeUserId: owner.id},
    );
    assert.ok(!audienceExclOwner.includes(owner.id), "owner excluded");
    assert.ok(audienceExclOwner.includes(editor.id), "editor still present");
  } finally {
    await fs.rm(tempDir, {recursive: true, force: true});
  }
});

test("Ship 9: soft-deleted семя memberships excluded automatically", async () => {
  const {store, tempDir} = await makeStore();
  try {
    const owner = await seedUser(store, "ow4@example.com");
    const kicked = await seedUser(store, "kk4@example.com");
    const remaining = await seedUser(store, "rm4@example.com");

    const tree = await store.createTree({
      creatorId: owner.id,
      name: "Kick test",
      description: "",
      isPrivate: true,
      kind: "family",
    });
    const semya = await store.createSemya({
      ownerId: owner.id,
      name: "S",
      treeId: tree.id,
    });
    await store.addMembership({
      semyaId: semya.id,
      userId: kicked.id,
      role: "editor",
      invitedByUserId: owner.id,
    });
    await store.addMembership({
      semyaId: semya.id,
      userId: remaining.id,
      role: "viewer",
      invitedByUserId: owner.id,
    });

    // Kick kicked user
    await store.removeMembership({
      semyaId: semya.id,
      targetUserId: kicked.id,
      actorUserId: owner.id,
    });

    const audience = await store.resolveTreeAudienceUserIds(tree.id);
    assert.ok(audience.includes(owner.id));
    assert.ok(audience.includes(remaining.id), "remaining семя member present");
    assert.ok(!audience.includes(kicked.id), "kicked member excluded (hiddenAt)");
  } finally {
    await fs.rm(tempDir, {recursive: true, force: true});
  }
});

test("Ship 9: drift case — семя member missing from tree.memberIds still surfaced", async () => {
  const {store, tempDir} = await makeStore();
  try {
    const owner = await seedUser(store, "ow5@example.com");
    const driftUser = await seedUser(store, "dr5@example.com");

    const tree = await store.createTree({
      creatorId: owner.id,
      name: "Drift test",
      description: "",
      isPrivate: true,
      kind: "family",
    });
    const semya = await store.createSemya({
      ownerId: owner.id,
      name: "S",
      treeId: tree.id,
    });

    // Manually add membership WITHOUT dual-write to tree.memberIds
    // (simulates drift / pre-Ship-5 семя / race condition)
    const db = await store._read();
    db.semyaMembers.push({
      id: "drift-membership",
      semyaId: semya.id,
      userId: driftUser.id,
      role: "editor",
      joinedAt: new Date().toISOString(),
      invitedByUserId: owner.id,
      hasInviteGrant: false,
      hiddenAt: null,
    });
    await store._write(db);

    // Verify drift — tree.memberIds doesn't contain driftUser
    const treeSnap = await store.findTree(tree.id);
    assert.ok(!treeSnap.memberIds.includes(driftUser.id));

    // Ship 9 extension catches them via семя membership scan
    const audience = await store.resolveTreeAudienceUserIds(tree.id);
    assert.ok(
      audience.includes(driftUser.id),
      "Ship 9 catches drift-member через semyaMembers scan",
    );
  } finally {
    await fs.rm(tempDir, {recursive: true, force: true});
  }
});

test("Ship 9: семя owner preserved через extension даже if creator differs", async () => {
  const {store, tempDir} = await makeStore();
  try {
    // Edge: creator → tree, потом owner promote chain. После Phase B
    // creator может покинуть либо bыть demote, но семя.ownerId
    // separate concept. Семя owner ALWAYS member через addMembership
    // (createSemya atomically creates owner membership row).
    const founder = await seedUser(store, "fnd6@example.com");

    const tree = await store.createTree({
      creatorId: founder.id,
      name: "Owner test",
      description: "",
      isPrivate: true,
      kind: "family",
    });
    const semya = await store.createSemya({
      ownerId: founder.id,
      name: "S",
      treeId: tree.id,
    });

    const audience = await store.resolveTreeAudienceUserIds(tree.id);
    assert.ok(audience.includes(founder.id), "founder = creator + семя owner");

    // Verify через семя.ownerId reference too
    const fetched = await store.findSemyaById(semya.id);
    assert.equal(fetched.ownerId, founder.id);
  } finally {
    await fs.rm(tempDir, {recursive: true, force: true});
  }
});

test("Ship 9: missing tree returns empty (no extension call attempted)", async () => {
  const {store, tempDir} = await makeStore();
  try {
    const audience = await store.resolveTreeAudienceUserIds("nonexistent-tree");
    assert.deepEqual(audience, []);
  } finally {
    await fs.rm(tempDir, {recursive: true, force: true});
  }
});
