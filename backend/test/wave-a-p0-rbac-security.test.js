const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");
const {newDb} = require("pg-mem");

const {createApp} = require("../src/app");
const {FileStore} = require("../src/store");
const {PostgresStore} = require("../src/postgres-store");
const {RealtimeHub} = require("../src/realtime-hub");
const {PushGateway} = require("../src/push-gateway");

async function startFileServer({useSemyaModel = true} = {}) {
  const prevFlag = process.env.RODNYA_FEDERATED_SEMYI_ENABLED;
  if (useSemyaModel) {
    process.env.RODNYA_FEDERATED_SEMYI_ENABLED = "true";
  } else {
    delete process.env.RODNYA_FEDERATED_SEMYI_ENABLED;
  }

  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-wave-a-"));
  const dataPath = path.join(tempDir, "dev-db.json");
  const store = new FileStore(dataPath);
  await store.initialize();
  const realtimeHub = new RealtimeHub({store});
  const pushGateway = new PushGateway({store});
  const app = createApp({
    store,
    config: {
      corsOrigin: "*",
      dataPath,
      mediaRootPath: path.join(tempDir, "uploads"),
    },
    realtimeHub,
    pushGateway,
  });
  const server = await new Promise((resolve) => {
    const inst = app.listen(0, "127.0.0.1", () => resolve(inst));
  });
  realtimeHub.attach(server);
  return {
    baseUrl: `http://127.0.0.1:${server.address().port}`,
    server,
    store,
    tempDir,
    prevFlag,
  };
}

async function stopFileServer({server, tempDir, prevFlag}) {
  if (prevFlag === undefined) {
    delete process.env.RODNYA_FEDERATED_SEMYI_ENABLED;
  } else {
    process.env.RODNYA_FEDERATED_SEMYI_ENABLED = prevFlag;
  }
  await new Promise((resolve) => server.close(resolve));
  await fs.rm(tempDir, {recursive: true, force: true}).catch(() => {});
}

function seedingPool(rawPool, seededState) {
  return {
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
}

async function startPostgresServer(seededState = {}) {
  const memDb = newDb();
  const {Pool} = memDb.adapters.createPg();
  const rawPool = new Pool();
  const pool = seedingPool(rawPool, seededState);
  const store = new PostgresStore({pool, rowId: "default"});
  await store.initialize();
  const realtimeHub = new RealtimeHub({store});
  const pushGateway = new PushGateway({store});
  const app = createApp({
    store,
    config: {
      corsOrigin: "*",
      dataPath: "",
      mediaRootPath: os.tmpdir(),
    },
    realtimeHub,
    pushGateway,
  });
  const server = await new Promise((resolve) => {
    const inst = app.listen(0, "127.0.0.1", () => resolve(inst));
  });
  realtimeHub.attach(server);
  return {
    baseUrl: `http://127.0.0.1:${server.address().port}`,
    server,
    store,
  };
}

async function registerUser(baseUrl, email, displayName) {
  const res = await fetch(`${baseUrl}/v1/auth/register`, {
    method: "POST",
    headers: {"content-type": "application/json"},
    body: JSON.stringify({
      email,
      password: "Password123!",
      displayName,
      consentDocVersion: "test-consent-v1",
    }),
  });
  assert.equal(res.status, 201);
  return res.json();
}

test("P0.1 (FileStore): DeletedPerson restore/purge blocks viewer & protects claimed cards", async () => {
  const ctx = await startFileServer({useSemyaModel: true});
  try {
    const owner = await registerUser(ctx.baseUrl, "p01-owner@test.app", "Owner");
    const editor = await registerUser(ctx.baseUrl, "p01-editor@test.app", "Editor");
    const viewer = await registerUser(ctx.baseUrl, "p01-viewer@test.app", "Viewer");
    const claimedUser = await registerUser(ctx.baseUrl, "p01-claimed@test.app", "Claimed");

    const tree = await ctx.store.createTree({
      creatorId: owner.user.id,
      name: "Семья П01",
      kind: "family",
      bindSemya: true,
    });
    const semya = await ctx.store.findSemyaById(tree.semyaId);
    await ctx.store.addMembership({
      semyaId: semya.id,
      userId: editor.user.id,
      role: "editor",
      invitedByUserId: owner.user.id,
    });
    await ctx.store.addMembership({
      semyaId: semya.id,
      userId: viewer.user.id,
      role: "viewer",
      invitedByUserId: owner.user.id,
    });
    await ctx.store.addMembership({
      semyaId: semya.id,
      userId: claimedUser.user.id,
      role: "viewer",
      invitedByUserId: owner.user.id,
    });

    const anonA = await ctx.store.createPerson({
      treeId: tree.id,
      creatorId: owner.user.id,
      personData: {firstName: "Дед", gender: "male"},
    });
    const anonB = await ctx.store.createPerson({
      treeId: tree.id,
      creatorId: owner.user.id,
      personData: {firstName: "Бабушка", gender: "female"},
    });
    const claimedPerson = await ctx.store.createPerson({
      treeId: tree.id,
      creatorId: owner.user.id,
      userId: claimedUser.user.id,
      personData: {firstName: "Внучка", gender: "female"},
    });

    await ctx.store.deletePerson(tree.id, anonA.id, owner.user.id);
    await ctx.store.deletePerson(tree.id, anonB.id, owner.user.id);
    await ctx.store.deletePerson(tree.id, claimedPerson.id, claimedUser.user.id);

    const db = await ctx.store._read();
    for (const row of db.deletedPersons) {
      row.earliestHardDelete = "2020-01-01T00:00:00.000Z";
    }
    await ctx.store._write(db);

    const delAnonA = db.deletedPersons.find((r) => r.originalPersonId === anonA.id);
    const delAnonB = db.deletedPersons.find((r) => r.originalPersonId === anonB.id);
    const delClaimed = db.deletedPersons.find((r) => r.originalPersonId === claimedPerson.id);

    // Viewer cannot restore or purge anonymous deleted person
    const viewerRestore = await fetch(
      `${ctx.baseUrl}/v1/deleted-persons/${delAnonA.id}/restore`,
      {method: "POST", headers: {authorization: `Bearer ${viewer.accessToken}`}},
    );
    assert.equal(viewerRestore.status, 403);

    const viewerPurge = await fetch(
      `${ctx.baseUrl}/v1/deleted-persons/${delAnonA.id}`,
      {method: "DELETE", headers: {authorization: `Bearer ${viewer.accessToken}`}},
    );
    assert.equal(viewerPurge.status, 403);

    // Editor CAN restore & purge anonymous cards
    const editorRestore = await fetch(
      `${ctx.baseUrl}/v1/deleted-persons/${delAnonA.id}/restore`,
      {method: "POST", headers: {authorization: `Bearer ${editor.accessToken}`}},
    );
    assert.equal(editorRestore.status, 200);

    const editorPurge = await fetch(
      `${ctx.baseUrl}/v1/deleted-persons/${delAnonB.id}`,
      {method: "DELETE", headers: {authorization: `Bearer ${editor.accessToken}`}},
    );
    assert.equal(editorPurge.status, 200);

    // Claimed card: ungranted editor & owner get 403; claimed owner (even viewer!) gets 200
    const editorClaimed = await fetch(
      `${ctx.baseUrl}/v1/deleted-persons/${delClaimed.id}/restore`,
      {method: "POST", headers: {authorization: `Bearer ${editor.accessToken}`}},
    );
    assert.equal(editorClaimed.status, 403);

    const ownerClaimedPurge = await fetch(
      `${ctx.baseUrl}/v1/deleted-persons/${delClaimed.id}`,
      {method: "DELETE", headers: {authorization: `Bearer ${owner.accessToken}`}},
    );
    assert.equal(ownerClaimedPurge.status, 403);

    const selfRestore = await fetch(
      `${ctx.baseUrl}/v1/deleted-persons/${delClaimed.id}/restore`,
      {method: "POST", headers: {authorization: `Bearer ${claimedUser.accessToken}`}},
    );
    assert.equal(selfRestore.status, 200);

    // Grant with scope="soft-delete" lets grantee manage claimed deleted person
    const claimed2 = await ctx.store.createPerson({
      treeId: tree.id,
      creatorId: claimedUser.user.id,
      userId: claimedUser.user.id,
      personData: {firstName: "Внучка2", gender: "female"},
    });
    const graphClaimed = await ctx.store.findGraphPersonByLegacy(claimed2.id);
    await ctx.store.addGraphPersonGrant({
      graphPersonId: graphClaimed.id,
      grantorUserId: claimedUser.user.id,
      granteeUserId: editor.user.id,
      scope: "soft-delete",
    });
    await ctx.store.deletePerson(tree.id, claimed2.id, claimedUser.user.id);
    const dbAfter = await ctx.store._read();
    const delClaimed2 = dbAfter.deletedPersons.find(
      (r) => !r.restoredAt && r.originalPersonId === claimed2.id,
    );
    const granteeRestore = await fetch(
      `${ctx.baseUrl}/v1/deleted-persons/${delClaimed2.id}/restore`,
      {method: "POST", headers: {authorization: `Bearer ${editor.accessToken}`}},
    );
    assert.equal(granteeRestore.status, 200);
  } finally {
    await stopFileServer(ctx);
  }
});

test("P0.1 (PostgresStore): viewer blocked from DeletedPerson restore & purge; editor succeeds on anon", async () => {
  const now = new Date().toISOString();
  const past = "2020-01-01T00:00:00.000Z";
  const future = "2035-01-01T00:00:00.000Z";
  const ctx = await startPostgresServer({
    users: [
      {id: "u-owner", email: "o@pg.test", profile: {displayName: "Owner"}},
      {id: "u-editor", email: "e@pg.test", profile: {displayName: "Editor"}},
      {id: "u-viewer", email: "v@pg.test", profile: {displayName: "Viewer"}},
    ],
    sessions: [
      {token: "t-owner", refreshToken: "ro", userId: "u-owner", createdAt: now},
      {token: "t-editor", refreshToken: "re", userId: "u-editor", createdAt: now},
      {token: "t-viewer", refreshToken: "rv", userId: "u-viewer", createdAt: now},
    ],
    trees: [
      {
        id: "tree-pg",
        name: "PG Tree",
        creatorId: "u-owner",
        memberIds: ["u-owner", "u-editor", "u-viewer"],
        members: ["u-owner", "u-editor", "u-viewer"],
        semyaId: "semya-pg",
      },
    ],
    semyi: [
      {id: "semya-pg", name: "PG Semya", ownerId: "u-owner", treeId: "tree-pg", deletedAt: null},
    ],
    semyaMembers: [
      {id: "m1", semyaId: "semya-pg", userId: "u-owner", role: "owner", hiddenAt: null},
      {id: "m2", semyaId: "semya-pg", userId: "u-editor", role: "editor", hiddenAt: null},
      {id: "m3", semyaId: "semya-pg", userId: "u-viewer", role: "viewer", hiddenAt: null},
    ],
    deletedPersons: [
      {
        id: "dp-pg-anon",
        originalPersonId: "p-anon",
        treeId: "tree-pg",
        semyaId: "semya-pg",
        snapshot: {id: "p-anon", treeId: "tree-pg", name: "Прадед", userId: null},
        relationsSnapshot: [],
        deletedAt: now,
        deletedByUserId: "u-viewer",
        hardDeleteScheduledAt: future,
        earliestHardDelete: past,
        restoredAt: null,
      },
      {
        id: "dp-pg-claimed",
        originalPersonId: "p-cl",
        treeId: "tree-pg",
        semyaId: "semya-pg",
        snapshot: {id: "p-cl", treeId: "tree-pg", name: "Владелец", userId: "u-owner"},
        relationsSnapshot: [],
        deletedAt: now,
        deletedByUserId: "u-owner",
        hardDeleteScheduledAt: future,
        earliestHardDelete: past,
        restoredAt: null,
      },
    ],
  });
  try {
    // Even if viewer had deletedByUserId on dp-pg-anon, active Semya requires editor+
    const viewerRestore = await fetch(
      `${ctx.baseUrl}/v1/deleted-persons/dp-pg-anon/restore`,
      {method: "POST", headers: {authorization: "Bearer t-viewer"}},
    );
    assert.equal(viewerRestore.status, 403);

    const viewerPurge = await fetch(
      `${ctx.baseUrl}/v1/deleted-persons/dp-pg-anon`,
      {method: "DELETE", headers: {authorization: "Bearer t-viewer"}},
    );
    assert.equal(viewerPurge.status, 403);

    // Editor cannot restore/purge claimed dp-pg-claimed
    const editorClaimed = await fetch(
      `${ctx.baseUrl}/v1/deleted-persons/dp-pg-claimed`,
      {method: "DELETE", headers: {authorization: "Bearer t-editor"}},
    );
    assert.equal(editorClaimed.status, 403);

    // Editor CAN hard-purge dp-pg-anon in PostgresStore
    const editorPurge = await fetch(
      `${ctx.baseUrl}/v1/deleted-persons/dp-pg-anon`,
      {method: "DELETE", headers: {authorization: "Bearer t-editor"}},
    );
    assert.equal(editorPurge.status, 200);
  } finally {
    await new Promise((resolve) => ctx.server.close(resolve));
  }
});

test("P0.2: legacy TreeInvitation enforces hasInviteGrant and blocks editor un-kick", async () => {
  const ctx = await startFileServer({useSemyaModel: true});
  try {
    const owner = await registerUser(ctx.baseUrl, "p02-o@test.app", "Owner");
    const plainEditor = await registerUser(ctx.baseUrl, "p02-e1@test.app", "PlainEditor");
    const grantEditor = await registerUser(ctx.baseUrl, "p02-e2@test.app", "GrantEditor");
    const kicked = await registerUser(ctx.baseUrl, "p02-k@test.app", "Kicked");
    const freshUser = await registerUser(ctx.baseUrl, "p02-f@test.app", "Fresh");

    const tree = await ctx.store.createTree({
      creatorId: owner.user.id,
      name: "Семья П02",
      bindSemya: true,
    });
    const semya = await ctx.store.findSemyaById(tree.semyaId);
    await ctx.store.addMembership({
      semyaId: semya.id,
      userId: plainEditor.user.id,
      role: "editor",
      hasInviteGrant: false,
      invitedByUserId: owner.user.id,
    });
    await ctx.store.addMembership({
      semyaId: semya.id,
      userId: grantEditor.user.id,
      role: "editor",
      hasInviteGrant: true,
      invitedByUserId: owner.user.id,
    });
    await ctx.store.addMembership({
      semyaId: semya.id,
      userId: kicked.user.id,
      role: "viewer",
      invitedByUserId: owner.user.id,
    });

    // Editor without hasInviteGrant cannot invite via legacy endpoint
    const plainRes = await fetch(
      `${ctx.baseUrl}/v1/trees/${tree.id}/invitations`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${plainEditor.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({recipientUserId: freshUser.user.id}),
      },
    );
    assert.equal(plainRes.status, 403);

    // Pre-existing invitation created by grantEditor BEFORE kick
    const preKickInvRes = await fetch(
      `${ctx.baseUrl}/v1/trees/${tree.id}/invitations`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${grantEditor.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({recipientUserId: freshUser.user.id}),
      },
    );
    assert.equal(preKickInvRes.status, 201);

    // Owner kicks kickedUser
    await ctx.store.removeMembership({
      semyaId: semya.id,
      targetUserId: kicked.user.id,
      actorUserId: owner.user.id,
    });

    // grantEditor CANNOT invite kicked user via legacy endpoint
    const kickedInvRes = await fetch(
      `${ctx.baseUrl}/v1/trees/${tree.id}/invitations`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${grantEditor.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({recipientUserId: kicked.user.id}),
      },
    );
    assert.equal(kickedInvRes.status, 403);

    // Pre-existing editor-created invite for a user who is later kicked cannot unhide them
    const staleInvite = await ctx.store.createTreeInvitation({
      treeId: tree.id,
      userId: freshUser.user.id,
      addedBy: grantEditor.user.id,
    });
    // Remove pending duplicate and simulate user joining then kicked, with stale editor invite
    const db = await ctx.store._read();
    db.semyaMembers.push({
      id: "kicked-fresh",
      semyaId: semya.id,
      userId: freshUser.user.id,
      role: "viewer",
      hiddenAt: new Date().toISOString(),
    });
    await ctx.store._write(db);
    void staleInvite;

    const firstPreKickId = (await preKickInvRes.json()).invitation.invitationId;
    const staleAccept = await fetch(
      `${ctx.baseUrl}/v1/tree-invitations/${firstPreKickId}/respond`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${freshUser.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({accept: true}),
      },
    );
    assert.equal(staleAccept.status, 403);

    // Owner CAN still re-invite kicked user
    const ownerReinvite = await fetch(
      `${ctx.baseUrl}/v1/trees/${tree.id}/invitations`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${owner.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({recipientUserId: kicked.user.id}),
      },
    );
    assert.equal(ownerReinvite.status, 201);
    const reinviteId = (await ownerReinvite.json()).invitation.invitationId;
    const kickedAccept = await fetch(
      `${ctx.baseUrl}/v1/tree-invitations/${reinviteId}/respond`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${kicked.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({accept: true}),
      },
    );
    assert.equal(kickedAccept.status, 200);
  } finally {
    await stopFileServer(ctx);
  }
});

test("P0.3: claim-token issuance, deceased/blocked guards, single-use token, and strict mode", async () => {
  const prevStrict = process.env.RODNYA_REQUIRE_PERSON_CLAIM_TOKEN;
  delete process.env.RODNYA_REQUIRE_PERSON_CLAIM_TOKEN;
  const ctx = await startFileServer({useSemyaModel: true});
  try {
    const owner = await registerUser(ctx.baseUrl, "p03-o@test.app", "Owner");
    const editorNoGrant = await registerUser(ctx.baseUrl, "p03-e@test.app", "Editor");
    const target = await registerUser(ctx.baseUrl, "p03-t@test.app", "Target");
    const blocked = await registerUser(ctx.baseUrl, "p03-b@test.app", "Blocked");

    const tree = await ctx.store.createTree({
      creatorId: owner.user.id,
      name: "Семья П03",
      bindSemya: true,
    });
    const semya = await ctx.store.findSemyaById(tree.semyaId);
    await ctx.store.addMembership({
      semyaId: semya.id,
      userId: editorNoGrant.user.id,
      role: "editor",
      hasInviteGrant: false,
      invitedByUserId: owner.user.id,
    });

    const deceased = await ctx.store.createPerson({
      treeId: tree.id,
      creatorId: owner.user.id,
      personData: {
        firstName: "Прадед",
        gender: "male",
        deathDate: "1995-05-01",
      },
    });
    const living = await ctx.store.createPerson({
      treeId: tree.id,
      creatorId: owner.user.id,
      personData: {firstName: "Брат", gender: "male", isAlive: true},
    });
    const living2 = await ctx.store.createPerson({
      treeId: tree.id,
      creatorId: owner.user.id,
      personData: {firstName: "Сестра", gender: "female", isAlive: true},
    });

    // Deceased cannot be claimed or issued token
    const deceasedIssue = await fetch(
      `${ctx.baseUrl}/v1/trees/${tree.id}/persons/${deceased.id}/claim-token`,
      {method: "POST", headers: {authorization: `Bearer ${owner.accessToken}`}},
    );
    assert.equal(deceasedIssue.status, 400);

    const deceasedClaim = await fetch(`${ctx.baseUrl}/v1/invitations/pending/process`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${target.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({treeId: tree.id, personId: deceased.id}),
    });
    assert.equal(deceasedClaim.status, 400);

    // Blocked user rejected
    const blockRes = await fetch(`${ctx.baseUrl}/v1/blocks`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${owner.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({userId: blocked.user.id}),
    });
    assert.equal(blockRes.status, 201);
    const blockedClaim = await fetch(`${ctx.baseUrl}/v1/invitations/pending/process`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${blocked.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({treeId: tree.id, personId: living.id}),
    });
    assert.equal(blockedClaim.status, 403);

    // Editor without hasInviteGrant cannot issue claim token
    const editorIssue = await fetch(
      `${ctx.baseUrl}/v1/trees/${tree.id}/persons/${living.id}/claim-token`,
      {method: "POST", headers: {authorization: `Bearer ${editorNoGrant.accessToken}`}},
    );
    assert.equal(editorIssue.status, 403);

    // Owner issues claim token; person GET never leaks inviteClaimToken
    const ownerIssue = await fetch(
      `${ctx.baseUrl}/v1/trees/${tree.id}/persons/${living.id}/claim-token`,
      {method: "POST", headers: {authorization: `Bearer ${owner.accessToken}`}},
    );
    assert.equal(ownerIssue.status, 201);
    const {claimToken} = await ownerIssue.json();
    assert.ok(claimToken);

    const personsRes = await fetch(`${ctx.baseUrl}/v1/trees/${tree.id}/persons`, {
      headers: {authorization: `Bearer ${owner.accessToken}`},
    });
    const personsBody = await personsRes.json();
    const mappedLiving = personsBody.persons.find((p) => p.id === living.id);
    assert.equal("inviteClaimToken" in mappedLiving, false);

    // Missing or wrong claimToken fails with 403
    const noTokenClaim = await fetch(`${ctx.baseUrl}/v1/invitations/pending/process`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${target.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({treeId: tree.id, personId: living.id}),
    });
    assert.equal(noTokenClaim.status, 403);

    const badTokenClaim = await fetch(`${ctx.baseUrl}/v1/invitations/pending/process`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${target.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({treeId: tree.id, personId: living.id, claimToken: "wrong-token"}),
    });
    assert.equal(badTokenClaim.status, 403);

    // Valid token succeeds and clears single-use token
    const validClaim = await fetch(`${ctx.baseUrl}/v1/invitations/pending/process`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${target.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({treeId: tree.id, personId: living.id, claimToken}),
    });
    assert.equal(validClaim.status, 200);

    // Strict mode blocks tokenless claim on living2
    process.env.RODNYA_REQUIRE_PERSON_CLAIM_TOKEN = "true";
    const strictReject = await fetch(`${ctx.baseUrl}/v1/invitations/pending/process`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${target.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({treeId: tree.id, personId: living2.id}),
    });
    assert.equal(strictReject.status, 403);
  } finally {
    if (prevStrict === undefined) {
      delete process.env.RODNYA_REQUIRE_PERSON_CLAIM_TOKEN;
    } else {
      process.env.RODNYA_REQUIRE_PERSON_CLAIM_TOKEN = prevStrict;
    }
    await stopFileServer(ctx);
  }
});

test("P0.4: unlinkUserFromPerson hides non-owner semyaMembers row and revokes tree access", async () => {
  const ctx = await startFileServer({useSemyaModel: true});
  try {
    const owner = await registerUser(ctx.baseUrl, "p04-o@test.app", "Owner");
    const member = await registerUser(ctx.baseUrl, "p04-m@test.app", "Member");

    const tree = await ctx.store.createTree({
      creatorId: owner.user.id,
      name: "Семья П04",
      bindSemya: true,
    });
    const person = await ctx.store.createPerson({
      treeId: tree.id,
      creatorId: owner.user.id,
      userId: member.user.id,
      personData: {firstName: "Степан", gender: "male"},
    });

    const beforeAccess = await fetch(`${ctx.baseUrl}/v1/trees/${tree.id}/persons`, {
      headers: {authorization: `Bearer ${member.accessToken}`},
    });
    assert.equal(beforeAccess.status, 200);

    const unlinkRes = await fetch(
      `${ctx.baseUrl}/v1/trees/${tree.id}/persons/${person.id}/user-link`,
      {
        method: "DELETE",
        headers: {authorization: `Bearer ${owner.accessToken}`},
      },
    );
    assert.equal(unlinkRes.status, 200);

    const afterAccess = await fetch(`${ctx.baseUrl}/v1/trees/${tree.id}/persons`, {
      headers: {authorization: `Bearer ${member.accessToken}`},
    });
    assert.equal(afterAccess.status, 403);
  } finally {
    await stopFileServer(ctx);
  }
});

test("P0.5: deleteUser transfers Semya ownership, soft-deletes empty Semya, cleans GDPR fields & tables", async () => {
  const now = new Date().toISOString();
  const future = "2035-01-01T00:00:00.000Z";
  const ctx = await startPostgresServer({
    users: [
      {id: "u-sole", email: "sole@pg.test", profile: {displayName: "SoleOwner"}},
      {id: "u-ed", email: "ed@pg.test", profile: {displayName: "EditorSurvivor"}},
      {id: "u-lonely", email: "lonely@pg.test", profile: {displayName: "LonelyOwner"}},
    ],
    sessions: [
      {token: "t-sole", refreshToken: "r1", userId: "u-sole", createdAt: now},
      {token: "t-ed", refreshToken: "r2", userId: "u-ed", createdAt: now},
      {token: "t-lonely", refreshToken: "r3", userId: "u-lonely", createdAt: now},
    ],
    trees: [
      {
        id: "t-shared",
        name: "Общее дерево",
        creatorId: "u-sole",
        memberIds: ["u-sole", "u-ed"],
        members: ["u-sole", "u-ed"],
        semyaId: "s-shared",
      },
      {
        id: "t-solo",
        name: "Одиночное дерево",
        creatorId: "u-lonely",
        memberIds: ["u-lonely"],
        members: ["u-lonely"],
        semyaId: "s-solo",
      },
    ],
    semyi: [
      {id: "s-shared", name: "Общая семья", ownerId: "u-sole", treeId: "t-shared", deletedAt: null},
      {id: "s-solo", name: "Одиночная семья", ownerId: "u-lonely", treeId: "t-solo", deletedAt: null},
    ],
    semyaMembers: [
      {id: "sm-1", semyaId: "s-shared", userId: "u-sole", role: "owner", joinedAt: "2026-01-01T00:00:00Z", hiddenAt: null},
      {id: "sm-2", semyaId: "s-shared", userId: "u-ed", role: "editor", joinedAt: "2026-01-02T00:00:00Z", hiddenAt: null},
      {id: "sm-3", semyaId: "s-solo", userId: "u-lonely", role: "owner", joinedAt: "2026-01-01T00:00:00Z", hiddenAt: null},
    ],
    semyaInvitations: [
      {id: "si-1", semyaId: "s-shared", inviterUserId: "u-sole", recipientUserId: "u-ed", status: "pending"},
      {id: "si-2", semyaId: "s-solo", inviterUserId: "u-lonely", recipientEmail: "x@y.z", status: "pending"},
    ],
    semyaBrowseTokens: [
      {id: "bt-1", semyaId: "s-shared", createdByUserId: "u-sole", token: "tok1"},
      {id: "bt-2", semyaId: "s-shared", createdByUserId: "u-ed", token: "tok2"},
    ],
    semyaMemberHiddenPersons: [
      {id: "hp-1", semyaId: "s-shared", userId: "u-sole", personId: "p-any"},
    ],
    onboardingStates: [
      {userId: "u-sole", completed: true, treeId: "t-shared"},
    ],
    profileContributions: [
      {id: "pc-1", authorUserId: "u-sole", targetUserId: "u-ed", treeId: "t-shared", personId: "p-ed"},
    ],
    mergeProposals: [
      {id: "mp-solo", proposedByUserId: "u-sole", reviewerUserIds: ["u-ed"], status: "pending"},
      {id: "mp-rev", proposedByUserId: "u-ed", reviewerUserIds: ["u-sole"], status: "pending"},
    ],
    identityClaims: [
      {id: "ic-1", claimantUserId: "u-sole", reviewerUserIds: ["u-ed"], status: "pending"},
    ],
    deletedPersons: [
      {
        id: "dp-snap",
        originalPersonId: "p-sole-del",
        treeId: "t-shared",
        semyaId: "s-shared",
        snapshot: {id: "p-sole-del", treeId: "t-shared", userId: "u-sole"},
        relationsSnapshot: [],
        deletedAt: now,
        deletedByUserId: "u-ed",
        hardDeleteScheduledAt: future,
        earliestHardDelete: future,
        restoredAt: null,
      },
    ],
    deletedPosts: [
      {
        id: "dpost-1",
        originalPostId: "post-1",
        treeId: "t-shared",
        snapshot: {id: "post-1", authorId: "u-sole"},
        deletedByUserId: "u-sole",
      },
    ],
  });
  try {
    // Delete sole owner of shared Semya -> u-ed is promoted to owner
    const delSole = await fetch(`${ctx.baseUrl}/v1/auth/account`, {
      method: "DELETE",
      headers: {authorization: "Bearer t-sole"},
    });
    assert.equal(delSole.status, 204);

    // Delete lonely owner -> lonely Semya is soft-deleted
    const delLonely = await fetch(`${ctx.baseUrl}/v1/auth/account`, {
      method: "DELETE",
      headers: {authorization: "Bearer t-lonely"},
    });
    assert.equal(delLonely.status, 204);

    const db = await ctx.store._read();
    const sharedSemya = db.semyi.find((s) => s.id === "s-shared");
    const soloSemya = db.semyi.find((s) => s.id === "s-solo");
    const sharedTree = db.trees.find((t) => t.id === "t-shared");
    const edMembership = db.semyaMembers.find(
      (m) => m.semyaId === "s-shared" && m.userId === "u-ed",
    );

    assert.equal(sharedSemya.deletedAt, null);
    assert.equal(sharedSemya.ownerId, "u-ed");
    assert.equal(sharedTree.creatorId, "u-ed");
    assert.equal(edMembership.role, "owner");
    assert.equal(edMembership.hasInviteGrant, true);

    assert.ok(soloSemya.deletedAt);
    assert.equal(db.semyaInvitations.length, 0);
    assert.equal(db.semyaBrowseTokens.length, 1);
    assert.equal(db.semyaBrowseTokens[0].id, "bt-2");
    assert.equal(db.semyaMemberHiddenPersons.length, 0);
    assert.equal(db.onboardingStates.length, 0);
    assert.equal(db.profileContributions.length, 0);
    assert.equal(db.mergeProposals.length, 0);
    assert.equal(db.identityClaims.length, 0);
    assert.equal(db.deletedPosts.length, 0);

    // Postgres deletedPersons table should also have purged snapshot.userId === 'u-sole'
    const edDeletedList = await ctx.store.listDeletedPersonsForUser({userId: "u-ed"});
    assert.equal(edDeletedList.length, 0);
  } finally {
    await new Promise((resolve) => ctx.server.close(resolve));
  }
});

test("P0.6: federated viewer blocked from feed creation, can react/comment/vote/RSVP, Semya owner can moderate, kicked blocked from search", async () => {
  const ctx = await startFileServer({useSemyaModel: true});
  try {
    const owner = await registerUser(ctx.baseUrl, "p06-o@test.app", "Owner");
    const editor = await registerUser(ctx.baseUrl, "p06-e@test.app", "Editor");
    const viewer = await registerUser(ctx.baseUrl, "p06-v@test.app", "Viewer");

    const tree = await ctx.store.createTree({
      creatorId: owner.user.id,
      name: "Семья П06",
      bindSemya: true,
    });
    const semya = await ctx.store.findSemyaById(tree.semyaId);
    await ctx.store.addMembership({
      semyaId: semya.id,
      userId: editor.user.id,
      role: "editor",
      invitedByUserId: owner.user.id,
    });
    await ctx.store.addMembership({
      semyaId: semya.id,
      userId: viewer.user.id,
      role: "viewer",
      invitedByUserId: owner.user.id,
    });

    // Viewer blocked from creating post, story, poll, gathering
    assert.equal(
      (
        await fetch(`${ctx.baseUrl}/v1/posts`, {
          method: "POST",
          headers: {authorization: `Bearer ${viewer.accessToken}`, "content-type": "application/json"},
          body: JSON.stringify({treeId: tree.id, content: "Viewer post"}),
        })
      ).status,
      403,
    );
    assert.equal(
      (
        await fetch(`${ctx.baseUrl}/v1/stories`, {
          method: "POST",
          headers: {authorization: `Bearer ${viewer.accessToken}`, "content-type": "application/json"},
          body: JSON.stringify({treeId: tree.id, type: "text", text: "Viewer story"}),
        })
      ).status,
      403,
    );
    assert.equal(
      (
        await fetch(`${ctx.baseUrl}/v1/polls`, {
          method: "POST",
          headers: {authorization: `Bearer ${viewer.accessToken}`, "content-type": "application/json"},
          body: JSON.stringify({treeId: tree.id, question: "Q?", options: ["Да", "Нет"]}),
        })
      ).status,
      403,
    );
    assert.equal(
      (
        await fetch(`${ctx.baseUrl}/v1/gatherings`, {
          method: "POST",
          headers: {authorization: `Bearer ${viewer.accessToken}`, "content-type": "application/json"},
          body: JSON.stringify({treeId: tree.id, title: "Ужин", startAt: "2027-01-01T18:00:00Z"}),
        })
      ).status,
      403,
    );

    // Editor creates post, story, poll, gathering
    const postRes = await fetch(`${ctx.baseUrl}/v1/posts`, {
      method: "POST",
      headers: {authorization: `Bearer ${editor.accessToken}`, "content-type": "application/json"},
      body: JSON.stringify({treeId: tree.id, content: "Секрет семьи для поиска"}),
    });
    assert.equal(postRes.status, 201);
    const post = await postRes.json();

    const storyRes = await fetch(`${ctx.baseUrl}/v1/stories`, {
      method: "POST",
      headers: {authorization: `Bearer ${editor.accessToken}`, "content-type": "application/json"},
      body: JSON.stringify({treeId: tree.id, type: "text", text: "История редактора"}),
    });
    assert.equal(storyRes.status, 201);
    const story = await storyRes.json();

    const pollRes = await fetch(`${ctx.baseUrl}/v1/polls`, {
      method: "POST",
      headers: {authorization: `Bearer ${editor.accessToken}`, "content-type": "application/json"},
      body: JSON.stringify({treeId: tree.id, question: "Когда встречаемся?", options: ["Суббота", "Воскресенье"]}),
    });
    assert.equal(pollRes.status, 201);
    const poll = await pollRes.json();

    const gatheringRes = await fetch(`${ctx.baseUrl}/v1/gatherings`, {
      method: "POST",
      headers: {authorization: `Bearer ${editor.accessToken}`, "content-type": "application/json"},
      body: JSON.stringify({treeId: tree.id, title: "Семейный ужин", startAt: "2027-01-01T18:00:00Z"}),
    });
    assert.equal(gatheringRes.status, 201);
    const gathering = await gatheringRes.json();

    // Viewer CAN read, react, comment, vote, and RSVP
    assert.equal(
      (await fetch(`${ctx.baseUrl}/v1/posts?treeId=${tree.id}`, {headers: {authorization: `Bearer ${viewer.accessToken}`}})).status,
      200,
    );
    const commentRes = await fetch(`${ctx.baseUrl}/v1/posts/${post.id}/comments`, {
      method: "POST",
      headers: {authorization: `Bearer ${viewer.accessToken}`, "content-type": "application/json"},
      body: JSON.stringify({content: "Очень круто!"}),
    });
    assert.equal(commentRes.status, 201);
    const comment = await commentRes.json();

    assert.equal(
      (
        await fetch(`${ctx.baseUrl}/v1/posts/${post.id}/reactions`, {
          method: "POST",
          headers: {authorization: `Bearer ${viewer.accessToken}`, "content-type": "application/json"},
          body: JSON.stringify({emoji: "❤️"}),
        })
      ).status,
      200,
    );
    assert.equal(
      (
        await fetch(`${ctx.baseUrl}/v1/polls/${poll.id}/respond`, {
          method: "POST",
          headers: {authorization: `Bearer ${viewer.accessToken}`, "content-type": "application/json"},
          body: JSON.stringify({optionIds: [poll.options[0].id]}),
        })
      ).status,
      200,
    );
    assert.equal(
      (
        await fetch(`${ctx.baseUrl}/v1/gatherings/${gathering.id}/rsvp`, {
          method: "POST",
          headers: {authorization: `Bearer ${viewer.accessToken}`, "content-type": "application/json"},
          body: JSON.stringify({status: "yes"}),
        })
      ).status,
      200,
    );

    // Kicked viewer cannot see secret post in searchPosts even if stale tree.memberIds remained
    const dbKick = await ctx.store._read();
    const kickedMem = dbKick.semyaMembers.find(
      (m) => m.semyaId === semya.id && m.userId === viewer.user.id,
    );
    kickedMem.hiddenAt = new Date().toISOString();
    const targetTree = dbKick.trees.find((t) => t.id === tree.id);
    targetTree.memberIds = Array.from(new Set([...(targetTree.memberIds || []), viewer.user.id]));
    await ctx.store._write(dbKick);

    const searchAfterKick = await fetch(
      `${ctx.baseUrl}/v1/posts/search?q=${encodeURIComponent("Секрет семьи")}`,
      {headers: {authorization: `Bearer ${viewer.accessToken}`}},
    );
    assert.equal(searchAfterKick.status, 200);
    assert.equal((await searchAfterKick.json()).length, 0);

    // Active Semya owner CAN moderate/delete editor's comment, post, story, poll, gathering
    assert.equal(
      (
        await fetch(`${ctx.baseUrl}/v1/posts/${post.id}/comments/${comment.id}`, {
          method: "DELETE",
          headers: {authorization: `Bearer ${owner.accessToken}`},
        })
      ).status,
      204,
    );
    assert.equal(
      (
        await fetch(`${ctx.baseUrl}/v1/posts/${post.id}`, {
          method: "DELETE",
          headers: {authorization: `Bearer ${owner.accessToken}`},
        })
      ).status,
      204,
    );
    assert.equal(
      (
        await fetch(`${ctx.baseUrl}/v1/stories/${story.id}`, {
          method: "DELETE",
          headers: {authorization: `Bearer ${owner.accessToken}`},
        })
      ).status,
      204,
    );
    assert.equal(
      (
        await fetch(`${ctx.baseUrl}/v1/polls/${poll.id}`, {
          method: "DELETE",
          headers: {authorization: `Bearer ${owner.accessToken}`},
        })
      ).status,
      204,
    );
    assert.equal(
      (
        await fetch(`${ctx.baseUrl}/v1/gatherings/${gathering.id}`, {
          method: "DELETE",
          headers: {authorization: `Bearer ${owner.accessToken}`},
        })
      ).status,
      204,
    );
  } finally {
    await stopFileServer(ctx);
  }
});
