const test = require("node:test");
const assert = require("node:assert/strict");

const {FileStore, EMPTY_DB} = require("../src/store");

// All Phase 3.1 helpers are pure functions over the in-memory db
// object — same testing pattern as graph-sync.test.js.
function makeStoreStub() {
  return Object.create(FileStore.prototype);
}

function freshDb() {
  return structuredClone(EMPTY_DB);
}

// Convenience builder for a small kinship graph used across visibility
// + branch-include-rules tests.
//   user-self  ── parent → user-mom
//   user-mom   ── parent → user-grandma
//   user-mom   ── parent → user-uncle (sibling of self via mom)
//   user-self  ── child  → user-kid
//   user-self  ── child  → user-other-kid
function seedKinship(db) {
  db.users = [
    {id: "u-self", identityId: "id-self"},
    {id: "u-other", identityId: "id-other"},
    {id: "u-stranger", identityId: "id-stranger"},
  ];
  db.graphPersons = [
    {id: "id-self", userId: "u-self", visibility: "connected-via-blood-graph", visibilityOverride: false, deletedAt: null},
    {id: "id-mom", userId: null, createdBy: "u-self", visibility: "connected-via-blood-graph", visibilityOverride: false, deletedAt: null},
    {id: "id-grandma", userId: null, createdBy: "u-self", visibility: "connected-via-blood-graph", visibilityOverride: false, deletedAt: null, isAlive: false, birthDate: "1900-01-01"},
    {id: "id-greatgrandma", userId: null, createdBy: "u-self", visibility: "connected-via-blood-graph", visibilityOverride: false, deletedAt: null},
    {id: "id-uncle", userId: null, createdBy: "u-self", visibility: "connected-via-blood-graph", visibilityOverride: false, deletedAt: null},
    {id: "id-kid", userId: null, createdBy: "u-self", visibility: "connected-via-blood-graph", visibilityOverride: false, deletedAt: null},
    {id: "id-other-kid", userId: null, createdBy: "u-self", visibility: "connected-via-blood-graph", visibilityOverride: false, deletedAt: null},
    {id: "id-far-away", userId: null, createdBy: "u-stranger", visibility: "connected-via-blood-graph", visibilityOverride: false, deletedAt: null},
    {id: "id-other", userId: "u-other", visibility: "connected-via-blood-graph", visibilityOverride: false, deletedAt: null},
  ];
  db.graphRelations = [
    {id: "r-mom", person1Id: "id-mom", person2Id: "id-self", relation1to2: "parent", relation2to1: "child", deletedAt: null, legacyRelationIds: ["r-mom"]},
    {id: "r-grandma", person1Id: "id-grandma", person2Id: "id-mom", relation1to2: "parent", relation2to1: "child", deletedAt: null, legacyRelationIds: ["r-grandma"]},
    {id: "r-greatgrandma", person1Id: "id-greatgrandma", person2Id: "id-grandma", relation1to2: "parent", relation2to1: "child", deletedAt: null, legacyRelationIds: ["r-greatgrandma"]},
    {id: "r-uncle", person1Id: "id-mom", person2Id: "id-uncle", relation1to2: "parent", relation2to1: "child", deletedAt: null, legacyRelationIds: ["r-uncle"]},
    {id: "r-kid", person1Id: "id-self", person2Id: "id-kid", relation1to2: "parent", relation2to1: "child", deletedAt: null, legacyRelationIds: ["r-kid"]},
    {id: "r-other-kid", person1Id: "id-self", person2Id: "id-other-kid", relation1to2: "parent", relation2to1: "child", deletedAt: null, legacyRelationIds: ["r-other-kid"]},
  ];
}

// ── _buildBranchVisiblePersonIds ──────────────────────────────────────

test("_buildBranchVisiblePersonIds: manual rule returns the explicit list verbatim", () => {
  const store = makeStoreStub();
  const db = freshDb();
  seedKinship(db);

  const branch = {
    id: "branch-1",
    ownerId: "u-self",
    includeRules: {
      type: "manual",
      manualPersonIds: ["id-self", "id-mom", "id-kid"],
      anchorPersonId: null,
      maxHops: 5,
    },
  };
  const visible = store._buildBranchVisiblePersonIds(db, branch, "u-self");
  assert.deepEqual(
    [...visible].sort(),
    ["id-kid", "id-mom", "id-self"].sort(),
  );
});

test("_buildBranchVisiblePersonIds: blood-from-me walks both directions to maxHops", () => {
  const store = makeStoreStub();
  const db = freshDb();
  seedKinship(db);

  const branch = {
    id: "branch-1",
    ownerId: "u-self",
    includeRules: {
      type: "blood-from-me",
      anchorPersonId: null,
      maxHops: 2,
    },
  };
  const visible = store._buildBranchVisiblePersonIds(db, branch, "u-self");
  // Self + parents (1 hop) + grandparents/uncles/kids (2 hops).
  // Greatgrandma (3 hops) выходит за maxHops=2.
  assert.ok(visible.has("id-self"));
  assert.ok(visible.has("id-mom"));
  assert.ok(visible.has("id-grandma"));
  assert.ok(visible.has("id-uncle"));
  assert.ok(visible.has("id-kid"));
  assert.ok(visible.has("id-other-kid"));
  assert.equal(visible.has("id-greatgrandma"), false);
  assert.equal(visible.has("id-far-away"), false);
});

test("_buildBranchVisiblePersonIds: blood-from-me default maxHops=5 reaches greatgrandma", () => {
  const store = makeStoreStub();
  const db = freshDb();
  seedKinship(db);

  const branch = {
    id: "branch-1",
    ownerId: "u-self",
    includeRules: {
      type: "blood-from-me",
      anchorPersonId: null,
      // maxHops omitted → default 5 per DECISIONS.md ответ D.
    },
  };
  const visible = store._buildBranchVisiblePersonIds(db, branch, "u-self");
  assert.ok(visible.has("id-greatgrandma"));
});

test("_buildBranchVisiblePersonIds: descendants-of walks ONLY child edges", () => {
  const store = makeStoreStub();
  const db = freshDb();
  seedKinship(db);

  const branch = {
    id: "branch-grandma-line",
    ownerId: "u-self",
    includeRules: {
      type: "descendants-of",
      anchorPersonId: "id-grandma",
      maxHops: 3,
    },
  };
  const visible = store._buildBranchVisiblePersonIds(db, branch, "u-self");
  // grandma + mom (1) + uncle (1) + self (2) + kid/other-kid (3).
  // greatgrandma — это предок grandma, не должна попасть.
  assert.ok(visible.has("id-grandma"));
  assert.ok(visible.has("id-mom"));
  assert.ok(visible.has("id-uncle"));
  assert.ok(visible.has("id-self"));
  assert.ok(visible.has("id-kid"));
  assert.ok(visible.has("id-other-kid"));
  assert.equal(visible.has("id-greatgrandma"), false);
});

test("_buildBranchVisiblePersonIds: ancestors-of walks ONLY parent edges", () => {
  const store = makeStoreStub();
  const db = freshDb();
  seedKinship(db);

  const branch = {
    id: "branch-ancestors",
    ownerId: "u-self",
    includeRules: {
      type: "ancestors-of",
      anchorPersonId: "id-self",
      maxHops: 5,
    },
  };
  const visible = store._buildBranchVisiblePersonIds(db, branch, "u-self");
  // self + mom (1) + grandma (2) + greatgrandma (3).
  // Дети, sibling'и mom, uncle — не предки, не должны попасть.
  assert.ok(visible.has("id-self"));
  assert.ok(visible.has("id-mom"));
  assert.ok(visible.has("id-grandma"));
  assert.ok(visible.has("id-greatgrandma"));
  assert.equal(visible.has("id-kid"), false);
  assert.equal(visible.has("id-uncle"), false);
});

test("_buildBranchVisiblePersonIds: blood-from-me without self-graph returns empty set", () => {
  const store = makeStoreStub();
  const db = freshDb();
  seedKinship(db);
  // Юзер существует, но не имеет identityId → нет self-graph node.
  db.users.push({id: "u-orphan"});

  const branch = {
    id: "branch-orphan",
    ownerId: "u-orphan",
    includeRules: {type: "blood-from-me", anchorPersonId: null, maxHops: 5},
  };
  const visible = store._buildBranchVisiblePersonIds(db, branch, "u-orphan");
  assert.equal(visible.size, 0);
});

test("_buildBranchVisiblePersonIds: descendants-of with missing anchor returns empty set", () => {
  const store = makeStoreStub();
  const db = freshDb();
  seedKinship(db);

  const branch = {
    id: "branch-broken",
    includeRules: {type: "descendants-of", anchorPersonId: null, maxHops: 5},
  };
  const visible = store._buildBranchVisiblePersonIds(db, branch, "u-self");
  assert.equal(visible.size, 0);
});

test("_buildBranchVisiblePersonIds: unknown rule type returns empty set (no crash)", () => {
  const store = makeStoreStub();
  const db = freshDb();
  seedKinship(db);

  const branch = {
    id: "branch-1",
    includeRules: {type: "definitely-not-a-known-type", maxHops: 5},
  };
  const visible = store._buildBranchVisiblePersonIds(db, branch, "u-self");
  assert.equal(visible.size, 0);
});

// ── _userCanSeeGraphPerson ────────────────────────────────────────────

test("_userCanSeeGraphPerson: owner sees their own node always", () => {
  const store = makeStoreStub();
  const db = freshDb();
  seedKinship(db);
  // Even if explicit visibility=owner-only with override, owner sees.
  const node = db.graphPersons.find((g) => g.id === "id-self");
  node.visibility = "owner-only";
  node.visibilityOverride = true;
  assert.equal(store._userCanSeeGraphPerson(db, node, "u-self"), true);
});

test("_userCanSeeGraphPerson: public node visible to anyone", () => {
  const store = makeStoreStub();
  const db = freshDb();
  seedKinship(db);
  const node = db.graphPersons.find((g) => g.id === "id-mom");
  node.visibility = "public";
  node.visibilityOverride = true;
  assert.equal(
    store._userCanSeeGraphPerson(db, node, "u-stranger"),
    true,
  );
});

test("_userCanSeeGraphPerson: deceased + >100 years auto-resolves to public", () => {
  const store = makeStoreStub();
  const db = freshDb();
  seedKinship(db);
  const grandma = db.graphPersons.find((g) => g.id === "id-grandma");
  // grandma уже isAlive=false, birthDate=1900-01-01 — авто public.
  // Visibility override НЕ выставлен.
  assert.equal(grandma.visibilityOverride, false);
  assert.equal(
    store._userCanSeeGraphPerson(db, grandma, "u-stranger"),
    true,
  );
});

test("_userCanSeeGraphPerson: visibilityOverride blocks deceased+old auto-public", () => {
  const store = makeStoreStub();
  const db = freshDb();
  seedKinship(db);
  const grandma = db.graphPersons.find((g) => g.id === "id-grandma");
  grandma.visibility = "owner-only";
  grandma.visibilityOverride = true;
  // Stranger без access → не видит.
  assert.equal(
    store._userCanSeeGraphPerson(db, grandma, "u-stranger"),
    false,
  );
});

test("_userCanSeeGraphPerson: connected-via-blood-graph requires ≤4 hops", () => {
  const store = makeStoreStub();
  const db = freshDb();
  seedKinship(db);
  const mom = db.graphPersons.find((g) => g.id === "id-mom");
  // u-self ←→ id-self ←→ id-mom = 1 hop. Видит.
  assert.equal(store._userCanSeeGraphPerson(db, mom, "u-self"), true);

  const farAway = db.graphPersons.find((g) => g.id === "id-far-away");
  // far-away не связан blood-edges с u-self (создан u-stranger).
  // Default visibility connected-via-blood-graph → не видит.
  assert.equal(
    store._userCanSeeGraphPerson(db, farAway, "u-self"),
    false,
  );
});

test("_userCanSeeGraphPerson: explicit grant unlocks owner-only node", () => {
  const store = makeStoreStub();
  const db = freshDb();
  seedKinship(db);
  const node = db.graphPersons.find((g) => g.id === "id-mom");
  node.visibility = "owner-only";
  node.visibilityOverride = true;
  // u-other грантован "edit" доступ — visibility unlocked too.
  db.graphPersonEditGrants = [
    {
      id: "g-1",
      graphPersonId: "id-mom",
      grantorUserId: "u-self",
      granteeUserId: "u-other",
      scope: "edit",
      grantedAt: "2026-05-01T00:00:00.000Z",
      revokedAt: null,
    },
  ];
  assert.equal(store._userCanSeeGraphPerson(db, node, "u-other"), true);
});

test("_userCanSeeGraphPerson: revoked grant no longer unlocks", () => {
  const store = makeStoreStub();
  const db = freshDb();
  seedKinship(db);
  const node = db.graphPersons.find((g) => g.id === "id-mom");
  node.visibility = "owner-only";
  node.visibilityOverride = true;
  db.graphPersonEditGrants = [
    {
      id: "g-1",
      graphPersonId: "id-mom",
      grantorUserId: "u-self",
      granteeUserId: "u-other",
      scope: "edit",
      grantedAt: "2026-05-01T00:00:00.000Z",
      revokedAt: "2026-05-09T00:00:00.000Z",
    },
  ];
  assert.equal(store._userCanSeeGraphPerson(db, node, "u-other"), false);
});

test("_userCanSeeGraphPerson: deletedAt blocks visibility for everyone except later resurrect", () => {
  const store = makeStoreStub();
  const db = freshDb();
  seedKinship(db);
  const node = db.graphPersons.find((g) => g.id === "id-mom");
  node.deletedAt = "2026-05-09T00:00:00.000Z";
  // Owner лишён visibility пока узел soft-deleted — это намеренно;
  // 30-day undo window поднимает узел через _syncPersonToGraph
  // resurrect-path. Read-time же — узла «нет».
  assert.equal(store._userCanSeeGraphPerson(db, node, "u-self"), false);
});

// ── _userCanEditGraphPerson ───────────────────────────────────────────

test("_userCanEditGraphPerson: owner can edit by default", () => {
  const store = makeStoreStub();
  const db = freshDb();
  seedKinship(db);
  const node = db.graphPersons.find((g) => g.id === "id-self");
  assert.equal(store._userCanEditGraphPerson(db, node, "u-self"), true);
});

test("_userCanEditGraphPerson: stranger blocked without grant", () => {
  const store = makeStoreStub();
  const db = freshDb();
  seedKinship(db);
  const node = db.graphPersons.find((g) => g.id === "id-self");
  assert.equal(
    store._userCanEditGraphPerson(db, node, "u-stranger"),
    false,
  );
});

test("_userCanEditGraphPerson: grant unlocks per-scope only", () => {
  const store = makeStoreStub();
  const db = freshDb();
  seedKinship(db);
  const node = db.graphPersons.find((g) => g.id === "id-self");
  db.graphPersonEditGrants = [
    {
      id: "g-1",
      graphPersonId: "id-self",
      grantorUserId: "u-self",
      granteeUserId: "u-other",
      scope: "edit",
      grantedAt: "2026-05-01T00:00:00.000Z",
      revokedAt: null,
    },
  ];
  // Edit scope → granted user может editить.
  assert.equal(
    store._userCanEditGraphPerson(db, node, "u-other", "edit"),
    true,
  );
  // Merge consent — другой scope, не granted.
  assert.equal(
    store._userCanEditGraphPerson(db, node, "u-other", "merge-consent"),
    false,
  );
  // Soft-delete тоже отдельный scope.
  assert.equal(
    store._userCanEditGraphPerson(db, node, "u-other", "soft-delete"),
    false,
  );
});

test("_userCanEditGraphPerson: deletedAt blocks edit even for owner", () => {
  const store = makeStoreStub();
  const db = freshDb();
  seedKinship(db);
  const node = db.graphPersons.find((g) => g.id === "id-self");
  node.deletedAt = "2026-05-09T00:00:00.000Z";
  // Once soft-deleted, no further edits — only resurrect path through
  // un-deleting the legacy person. Owner — не исключение.
  assert.equal(store._userCanEditGraphPerson(db, node, "u-self"), false);
});

// ── _userCanSeeSensitiveAttribute ─────────────────────────────────────

test("_userCanSeeSensitiveAttribute: phone owner-only even on public node", () => {
  const store = makeStoreStub();
  const db = freshDb();
  seedKinship(db);
  const node = db.graphPersons.find((g) => g.id === "id-mom");
  node.visibility = "public";
  node.visibilityOverride = true;
  // Phone is sensitive — owner-only по DECISIONS.md ответ A.3.
  assert.equal(
    store._userCanSeeSensitiveAttribute(db, node, "u-stranger", "phone"),
    false,
  );
  // Owner видит.
  assert.equal(
    store._userCanSeeSensitiveAttribute(db, node, "u-self", "phone"),
    true,
  );
});

test("_userCanSeeSensitiveAttribute: non-sensitive falls through to visibility check", () => {
  const store = makeStoreStub();
  const db = freshDb();
  seedKinship(db);
  const node = db.graphPersons.find((g) => g.id === "id-mom");
  // birthDate — не sensitive, не в SENSITIVE_KEYS.
  // Default visibility connected-via-blood-graph → u-self (1 hop) видит.
  assert.equal(
    store._userCanSeeSensitiveAttribute(db, node, "u-self", "birthDate"),
    true,
  );
  // u-stranger через default visibility не видит.
  assert.equal(
    store._userCanSeeSensitiveAttribute(db, node, "u-stranger", "birthDate"),
    false,
  );
});

// ── _effectiveGraphPersonVisibility ───────────────────────────────────

test("_effectiveGraphPersonVisibility: stored value wins when override=true", () => {
  const store = makeStoreStub();
  const node = {
    visibility: "owner-only",
    visibilityOverride: true,
    isAlive: false,
    birthDate: "1850-01-01",
  };
  // Override blocks auto-public for >100-year-old deceased.
  assert.equal(store._effectiveGraphPersonVisibility(node), "owner-only");
});

test("_effectiveGraphPersonVisibility: deceased <100 years stays at stored default", () => {
  const store = makeStoreStub();
  const node = {
    visibility: "connected-via-blood-graph",
    visibilityOverride: false,
    isAlive: false,
    birthDate: `${new Date().getFullYear() - 50}-01-01`,
  };
  assert.equal(
    store._effectiveGraphPersonVisibility(node),
    "connected-via-blood-graph",
  );
});

test("_effectiveGraphPersonVisibility: missing visibility falls back to default", () => {
  const store = makeStoreStub();
  // Старый JSONB без поля → effective default.
  const node = {visibilityOverride: false};
  assert.equal(
    store._effectiveGraphPersonVisibility(node),
    "connected-via-blood-graph",
  );
});

// ── _selfGraphPersonIdForUser ─────────────────────────────────────────

test("_selfGraphPersonIdForUser: returns identityId of the user's own graphPerson", () => {
  const store = makeStoreStub();
  const db = freshDb();
  seedKinship(db);
  assert.equal(store._selfGraphPersonIdForUser(db, "u-self"), "id-self");
});

test("_selfGraphPersonIdForUser: returns null when user has no identity", () => {
  const store = makeStoreStub();
  const db = freshDb();
  db.users = [{id: "u-anon"}];
  assert.equal(store._selfGraphPersonIdForUser(db, "u-anon"), null);
});

test("_selfGraphPersonIdForUser: returns null when graphPerson is soft-deleted", () => {
  const store = makeStoreStub();
  const db = freshDb();
  db.users = [{id: "u-self", identityId: "id-self"}];
  db.graphPersons = [{id: "id-self", deletedAt: "2026-05-09T00:00:00.000Z"}];
  assert.equal(store._selfGraphPersonIdForUser(db, "u-self"), null);
});
