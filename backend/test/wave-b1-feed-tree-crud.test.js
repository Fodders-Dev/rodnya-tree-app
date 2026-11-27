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

  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-wave-b1-"));
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

async function startPostgresStore(seededState = {}) {
  const memDb = newDb();
  const {Pool} = memDb.adapters.createPg();
  const rawPool = new Pool();
  const pool = seedingPool(rawPool, seededState);
  const store = new PostgresStore({pool, rowId: "default"});
  await store.initialize();
  return {store, pool, rawPool};
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

function authHeaders(session) {
  return {
    "content-type": "application/json",
    authorization: `Bearer ${session.accessToken}`,
  };
}

test("P1.1 Feed CRUD: Post GET/PATCH, Comment PATCH, Poll PATCH/un-vote, Gathering PATCH & audience GET", async () => {
  const ctx = await startFileServer({useSemyaModel: true});
  try {
    const owner = await registerUser(ctx.baseUrl, "b1-owner@test.app", "Owner");
    const editor = await registerUser(ctx.baseUrl, "b1-editor@test.app", "Editor");
    const viewer = await registerUser(ctx.baseUrl, "b1-viewer@test.app", "Viewer");
    const outsider = await registerUser(ctx.baseUrl, "b1-outsider@test.app", "Outsider");

    const tree = await ctx.store.createTree({
      creatorId: owner.user.id,
      name: "Лента B1",
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

    // 1. Create Post as editor -> GET /v1/posts/:postId -> PATCH /v1/posts/:postId
    const postCreateRes = await fetch(`${ctx.baseUrl}/v1/posts`, {
      method: "POST",
      headers: authHeaders(editor),
      body: JSON.stringify({treeId: tree.id, content: "Первый текст"}),
    });
    assert.equal(postCreateRes.status, 201);
    const createdPost = await postCreateRes.json();

    const postGetViewerRes = await fetch(
      `${ctx.baseUrl}/v1/posts/${createdPost.id}`,
      {headers: authHeaders(viewer)},
    );
    assert.equal(postGetViewerRes.status, 200);
    const loadedPost = await postGetViewerRes.json();
    assert.equal(loadedPost.content, "Первый текст");
    assert.equal(loadedPost.editedAt, null);

    // Non-member cannot read single post (403)
    const postGetOutsiderRes = await fetch(
      `${ctx.baseUrl}/v1/posts/${createdPost.id}`,
      {headers: authHeaders(outsider)},
    );
    assert.equal(postGetOutsiderRes.status, 403);

    // Owner/viewer cannot PATCH another's post (author-only edit -> 403)
    const postPatchOwnerRes = await fetch(
      `${ctx.baseUrl}/v1/posts/${createdPost.id}`,
      {
        method: "PATCH",
        headers: authHeaders(owner),
        body: JSON.stringify({content: "Правка чужого"}),
      },
    );
    assert.equal(postPatchOwnerRes.status, 403);

    // Empty post edit without images rejected (400)
    const postPatchEmptyRes = await fetch(
      `${ctx.baseUrl}/v1/posts/${createdPost.id}`,
      {
        method: "PATCH",
        headers: authHeaders(editor),
        body: JSON.stringify({content: "   "}),
      },
    );
    assert.equal(postPatchEmptyRes.status, 400);

    // Author can PATCH post -> editedAt stamped
    const postPatchAuthorRes = await fetch(
      `${ctx.baseUrl}/v1/posts/${createdPost.id}`,
      {
        method: "PATCH",
        headers: authHeaders(editor),
        body: JSON.stringify({content: "Обновлённый текст"}),
      },
    );
    assert.equal(postPatchAuthorRes.status, 200);
    const patchedPost = await postPatchAuthorRes.json();
    assert.equal(patchedPost.content, "Обновлённый текст");
    assert.ok(patchedPost.editedAt);

    // 2. Comment PATCH (author-only)
    const commentRes = await fetch(
      `${ctx.baseUrl}/v1/posts/${createdPost.id}/comments`,
      {
        method: "POST",
        headers: authHeaders(viewer),
        body: JSON.stringify({content: "Коммент зрителя"}),
      },
    );
    assert.equal(commentRes.status, 201);
    const createdComment = await commentRes.json();

    const commentPatchEditorRes = await fetch(
      `${ctx.baseUrl}/v1/posts/${createdPost.id}/comments/${createdComment.id}`,
      {
        method: "PATCH",
        headers: authHeaders(editor),
        body: JSON.stringify({content: "Не мой коммент"}),
      },
    );
    assert.equal(commentPatchEditorRes.status, 403);

    const commentPatchAuthorRes = await fetch(
      `${ctx.baseUrl}/v1/posts/${createdPost.id}/comments/${createdComment.id}`,
      {
        method: "PATCH",
        headers: authHeaders(viewer),
        body: JSON.stringify({content: "Обновлённый коммент"}),
      },
    );
    assert.equal(commentPatchAuthorRes.status, 200);
    const patchedComment = await commentPatchAuthorRes.json();
    assert.equal(patchedComment.content, "Обновлённый коммент");
    assert.ok(patchedComment.editedAt);

    // 3. Poll PATCH + withdraw vote + closeNow + 409 after closed
    const pollCreateRes = await fetch(`${ctx.baseUrl}/v1/polls`, {
      method: "POST",
      headers: authHeaders(editor),
      body: JSON.stringify({
        treeId: tree.id,
        question: "Когда дача?",
        options: ["Суббота", "Воскресенье"],
      }),
    });
    assert.equal(pollCreateRes.status, 201);
    const createdPoll = await pollCreateRes.json();

    // Viewer votes and withdraws vote
    const voteRes = await fetch(
      `${ctx.baseUrl}/v1/polls/${createdPoll.id}/respond`,
      {
        method: "POST",
        headers: authHeaders(viewer),
        body: JSON.stringify({optionIds: [createdPoll.options[0].id]}),
      },
    );
    assert.equal(voteRes.status, 200);
    assert.equal((await voteRes.json()).responses.length, 1);

    const unvoteRes = await fetch(
      `${ctx.baseUrl}/v1/polls/${createdPoll.id}/respond`,
      {
        method: "DELETE",
        headers: authHeaders(viewer),
      },
    );
    assert.equal(unvoteRes.status, 200);
    assert.equal((await unvoteRes.json()).responses.length, 0);

    // Author edits question
    const pollPatchRes = await fetch(
      `${ctx.baseUrl}/v1/polls/${createdPoll.id}`,
      {
        method: "PATCH",
        headers: authHeaders(editor),
        body: JSON.stringify({question: "Точно когда дача?"}),
      },
    );
    assert.equal(pollPatchRes.status, 200);
    const editedPoll = await pollPatchRes.json();
    assert.equal(editedPoll.question, "Точно когда дача?");
    assert.equal(editedPoll.isClosed, false);

    // Semya owner can closeNow even if not author (but cannot edit question)
    const ownerEditQuestionRes = await fetch(
      `${ctx.baseUrl}/v1/polls/${createdPoll.id}`,
      {
        method: "PATCH",
        headers: authHeaders(owner),
        body: JSON.stringify({question: "Попытка владельца"}),
      },
    );
    assert.equal(ownerEditQuestionRes.status, 403);

    const ownerCloseRes = await fetch(
      `${ctx.baseUrl}/v1/polls/${createdPoll.id}`,
      {
        method: "PATCH",
        headers: authHeaders(owner),
        body: JSON.stringify({closeNow: true}),
      },
    );
    assert.equal(ownerCloseRes.status, 200);
    assert.equal((await ownerCloseRes.json()).isClosed, true);

    // Voting or withdrawing on closed poll -> 409
    const voteClosedRes = await fetch(
      `${ctx.baseUrl}/v1/polls/${createdPoll.id}/respond`,
      {
        method: "POST",
        headers: authHeaders(viewer),
        body: JSON.stringify({optionIds: [createdPoll.options[0].id]}),
      },
    );
    assert.equal(voteClosedRes.status, 409);

    const unvoteClosedRes = await fetch(
      `${ctx.baseUrl}/v1/polls/${createdPoll.id}/respond`,
      {
        method: "DELETE",
        headers: authHeaders(viewer),
      },
    );
    assert.equal(unvoteClosedRes.status, 409);

    // 4. Gathering PATCH & audience-mode GET /v1/gatherings (no treeId)
    const gatheringCreateRes = await fetch(`${ctx.baseUrl}/v1/gatherings`, {
      method: "POST",
      headers: authHeaders(editor),
      body: JSON.stringify({
        treeId: tree.id,
        title: "Ужин",
        startAt: "2026-08-10T18:00:00.000Z",
        place: "Дом",
      }),
    });
    assert.equal(gatheringCreateRes.status, 201);
    const createdGathering = await gatheringCreateRes.json();

    // GET /v1/gatherings without treeId works in audience mode
    const audienceGatheringsRes = await fetch(`${ctx.baseUrl}/v1/gatherings`, {
      headers: authHeaders(viewer),
    });
    assert.equal(audienceGatheringsRes.status, 200);
    const audienceGatherings = await audienceGatheringsRes.json();
    assert.equal(audienceGatherings.length, 1);
    assert.equal(audienceGatherings[0].id, createdGathering.id);

    // Invalid time range rejected (400)
    const invalidRangeRes = await fetch(
      `${ctx.baseUrl}/v1/gatherings/${createdGathering.id}`,
      {
        method: "PATCH",
        headers: authHeaders(editor),
        body: JSON.stringify({endAt: "2026-08-10T17:00:00.000Z"}),
      },
    );
    assert.equal(invalidRangeRes.status, 400);

    // Author updates gathering
    const patchGatheringRes = await fetch(
      `${ctx.baseUrl}/v1/gatherings/${createdGathering.id}`,
      {
        method: "PATCH",
        headers: authHeaders(editor),
        body: JSON.stringify({
          title: "Семейный ужин",
          place: "Дача",
          endAt: "2026-08-10T21:00:00.000Z",
        }),
      },
    );
    assert.equal(patchGatheringRes.status, 200);
    const patchedGathering = await patchGatheringRes.json();
    assert.equal(patchedGathering.title, "Семейный ужин");
    assert.equal(patchedGathering.place, "Дача");
    assert.ok(patchedGathering.editedAt);
  } finally {
    await stopFileServer(ctx);
  }
});

test("P1.2 Tree/Semya sync, selectable route ordering, include-rules co-owner, softDelete & restore", async () => {
  const ctx = await startFileServer({useSemyaModel: true});
  try {
    const owner = await registerUser(ctx.baseUrl, "b12-owner@test.app", "Owner");
    const coOwner = await registerUser(ctx.baseUrl, "b12-co@test.app", "CoOwner");
    const kicked = await registerUser(ctx.baseUrl, "b12-kicked@test.app", "Kicked");

    const tree = await ctx.store.createTree({
      creatorId: owner.user.id,
      name: "Первое название",
      description: "Описание",
      kind: "family",
      bindSemya: true,
    });
    const semya = await ctx.store.findSemyaById(tree.semyaId);
    await ctx.store.addMembership({
      semyaId: semya.id,
      userId: coOwner.user.id,
      role: "editor",
      invitedByUserId: owner.user.id,
    });
    await ctx.store.updateMembership({
      semyaId: semya.id,
      targetUserId: coOwner.user.id,
      role: "owner",
      actorUserId: owner.user.id,
    });
    await ctx.store.addMembership({
      semyaId: semya.id,
      userId: kicked.user.id,
      role: "viewer",
      invitedByUserId: owner.user.id,
    });
    // Kick viewer BEFORE soft-delete so we verify restore doesn't resurrect earlier kicks
    await ctx.store.removeMembership({
      semyaId: semya.id,
      targetUserId: kicked.user.id,
      actorUserId: owner.user.id,
    });

    // 1. GET /v1/trees/selectable must not be shadowed by GET /v1/trees/:treeId
    const selectableRes = await fetch(`${ctx.baseUrl}/v1/trees/selectable`, {
      headers: authHeaders(owner),
    });
    assert.equal(selectableRes.status, 200);
    const selectableBody = await selectableRes.json();
    assert.equal(selectableBody.trees.length, 1);

    // 2. GET /v1/trees/:treeId
    const singleTreeRes = await fetch(`${ctx.baseUrl}/v1/trees/${tree.id}`, {
      headers: authHeaders(coOwner),
    });
    assert.equal(singleTreeRes.status, 200);
    assert.equal((await singleTreeRes.json()).tree.id, tree.id);

    // 3. PATCH /v1/trees/:treeId syncs name/description -> bound Semya
    const patchTreeRes = await fetch(`${ctx.baseUrl}/v1/trees/${tree.id}`, {
      method: "PATCH",
      headers: authHeaders(coOwner),
      body: JSON.stringify({
        name: "Род Ивановых",
        description: "Общее дерево",
        isPrivate: false,
        publicSlug: "rod-ivanovyh",
      }),
    });
    assert.equal(patchTreeRes.status, 200);
    const patchedTree = (await patchTreeRes.json()).tree;
    assert.equal(patchedTree.name, "Род Ивановых");
    assert.equal(patchedTree.isPrivate, false);
    assert.equal(patchedTree.publicSlug, "rod-ivanovyh");

    const semyaAfterTreePatch = await ctx.store.findSemyaById(semya.id);
    assert.equal(semyaAfterTreePatch.name, "Род Ивановых");
    assert.equal(semyaAfterTreePatch.description, "Общее дерево");

    // Public tree reachable by custom slug after isPrivate=false
    const publicTreeRes = await fetch(
      `${ctx.baseUrl}/v1/public/trees/rod-ivanovyh`,
    );
    assert.equal(publicTreeRes.status, 200);

    // 4. PATCH /v1/semya/:id syncs name/description -> bound FamilyTree
    const patchSemyaRes = await fetch(`${ctx.baseUrl}/v1/semya/${semya.id}`, {
      method: "PATCH",
      headers: authHeaders(owner),
      body: JSON.stringify({name: "Семья Петровых", description: "Ветвь П"}),
    });
    assert.equal(patchSemyaRes.status, 200);
    const treeAfterSemyaPatch = await ctx.store.findTree(tree.id);
    assert.equal(treeAfterSemyaPatch.name, "Семья Петровых");
    assert.equal(treeAfterSemyaPatch.description, "Ветвь П");

    // 5. include-rules allows co-owner (not just creatorId) and blocks demoted creator
    const includeCoRes = await fetch(
      `${ctx.baseUrl}/v1/trees/${tree.id}/include-rules`,
      {
        method: "PATCH",
        headers: authHeaders(coOwner),
        body: JSON.stringify({includeRules: {type: "blood-from-me"}}),
      },
    );
    assert.equal(includeCoRes.status, 200);
    assert.equal((await includeCoRes.json()).includeRules.type, "blood-from-me");

    // Demote original creator -> co-owner stays owner, creator can no longer edit tree or include-rules
    await ctx.store.updateMembership({
      semyaId: semya.id,
      targetUserId: owner.user.id,
      role: "editor",
      actorUserId: coOwner.user.id,
    });
    const demotedPatchRes = await fetch(`${ctx.baseUrl}/v1/trees/${tree.id}`, {
      method: "PATCH",
      headers: authHeaders(owner),
      body: JSON.stringify({name: "Не пройдёт"}),
    });
    assert.equal(demotedPatchRes.status, 403);
    const demotedRulesRes = await fetch(
      `${ctx.baseUrl}/v1/trees/${tree.id}/include-rules`,
      {
        method: "PATCH",
        headers: authHeaders(owner),
        body: JSON.stringify({includeRules: {type: "manual"}}),
      },
    );
    assert.equal(demotedRulesRes.status, 403);

    // 6. softDeleteSemya hides tree from GET /v1/trees & restoreSemya restores members without resurrecting old kick
    const deleteSemyaRes = await fetch(`${ctx.baseUrl}/v1/semya/${semya.id}`, {
      method: "DELETE",
      headers: authHeaders(coOwner),
    });
    assert.equal(deleteSemyaRes.status, 200);

    const treesWhileDeletedRes = await fetch(`${ctx.baseUrl}/v1/trees`, {
      headers: authHeaders(coOwner),
    });
    assert.equal(treesWhileDeletedRes.status, 200);
    assert.equal((await treesWhileDeletedRes.json()).trees.length, 0);

    // Non-owner cannot restore (403)
    const editorRestoreRes = await fetch(
      `${ctx.baseUrl}/v1/semya/${semya.id}/restore`,
      {
        method: "POST",
        headers: authHeaders(owner),
      },
    );
    assert.equal(editorRestoreRes.status, 403);

    // Owner restores -> tree reappears, coOwner & owner active, kicked stays kicked
    const ownerRestoreRes = await fetch(
      `${ctx.baseUrl}/v1/semya/${semya.id}/restore`,
      {
        method: "POST",
        headers: authHeaders(coOwner),
      },
    );
    assert.equal(ownerRestoreRes.status, 200);

    const treesRestoredRes = await fetch(`${ctx.baseUrl}/v1/trees`, {
      headers: authHeaders(coOwner),
    });
    assert.equal((await treesRestoredRes.json()).trees.length, 1);

    const membershipsAfterRestore = await ctx.store.listMembershipsForSemya(
      semya.id,
    );
    const activeIds = new Set(membershipsAfterRestore.map((m) => m.userId));
    assert.equal(activeIds.has(coOwner.user.id), true);
    assert.equal(activeIds.has(owner.user.id), true);
    assert.equal(activeIds.has(kicked.user.id), false);
  } finally {
    await stopFileServer(ctx);
  }
});

test("P1.2 hardDeleteExpired sweeps soft-deleted Semya after 90d on FileStore & PostgresStore", async () => {
  const now = new Date("2026-10-01T00:00:00.000Z");
  const expiredAt = "2026-06-01T00:00:00.000Z"; // > 90 days ago
  const recentAt = "2026-08-15T00:00:00.000Z"; // 47 days ago (>30d, <90d -> must NOT sweep)

  const seededState = {
    users: [{id: "u1", email: "u1@test.app", createdAt: expiredAt}],
    trees: [
      {id: "tree-exp", name: "Old", creatorId: "u1", memberIds: ["u1"], members: ["u1"], semyaId: "semya-exp", createdAt: expiredAt},
      {id: "tree-rec", name: "Recent", creatorId: "u1", memberIds: ["u1"], members: ["u1"], semyaId: "semya-rec", createdAt: recentAt},
    ],
    semyi: [
      {id: "semya-exp", name: "Old Semya", ownerId: "u1", treeId: "tree-exp", deletedAt: expiredAt},
      {id: "semya-rec", name: "Recent Semya", ownerId: "u1", treeId: "tree-rec", deletedAt: recentAt},
    ],
    semyaMembers: [
      {id: "m-exp", semyaId: "semya-exp", userId: "u1", role: "owner", hiddenAt: expiredAt},
      {id: "m-rec", semyaId: "semya-rec", userId: "u1", role: "owner", hiddenAt: recentAt},
    ],
    semyaInvitations: [
      {id: "inv-exp", semyaId: "semya-exp", status: "revoked"},
      {id: "inv-rec", semyaId: "semya-rec", status: "pending"},
    ],
    semyaBrowseTokens: [
      {id: "bt-exp", semyaId: "semya-exp", token: "t1"},
      {id: "bt-rec", semyaId: "semya-rec", token: "t2"},
    ],
    semyaMemberHiddenPersons: [
      {id: "hp-exp", semyaId: "semya-exp", userId: "u1", personId: "p1"},
    ],
    deletedPersons: [
      {
        id: "dp-exp",
        originalPersonId: "p1",
        treeId: "tree-exp",
        semyaId: "semya-exp",
        deletedAt: "2026-09-20T00:00:00.000Z", // only 11d old, but parent semya expired 90d!
        hardDeleteScheduledAt: "2026-10-20T00:00:00.000Z",
        earliestHardDelete: "2026-09-20T03:00:00.000Z",
        snapshot: {id: "p1", treeId: "tree-exp", name: "Test"},
      },
    ],
  };

  // FileStore verification
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-b1-hd-"));
  try {
    const dataPath = path.join(tempDir, "db.json");
    await fs.writeFile(dataPath, JSON.stringify(seededState));
    const fileStore = new FileStore(dataPath);
    await fileStore.initialize();

    const summary = await fileStore.hardDeleteExpired({now});
    assert.equal(summary.deleted.semyi, 1);
    assert.deepEqual(summary.sampleIds.semya, ["semya-exp"]);

    const after = await fileStore._read();
    assert.deepEqual(after.semyi.map((s) => s.id), ["semya-rec"]);
    assert.deepEqual(after.semyaMembers.map((m) => m.id), ["m-rec"]);
    assert.deepEqual(after.semyaInvitations.map((i) => i.id), ["inv-rec"]);
    assert.deepEqual(after.semyaBrowseTokens.map((b) => b.id), ["bt-rec"]);
    assert.equal(after.semyaMemberHiddenPersons.length, 0);
    assert.equal(after.deletedPersons.length, 0);
    assert.equal(
      after.trees.find((t) => t.id === "tree-exp").semyaId,
      null,
    );
  } finally {
    await fs.rm(tempDir, {recursive: true, force: true}).catch(() => {});
  }

  // PostgresStore verification (including deleted_persons extracted table cascade)
  const pg = await startPostgresStore(seededState);
  try {
    const pgSummary = await pg.store.hardDeleteExpired({now});
    assert.equal(pgSummary.deleted.semyi, 1);
    const remainingPgDeletedPersons = await pg.rawPool.query(
      `SELECT id FROM ${pg.store._qualifiedDeletedPersonsTableName} WHERE semya_id = 'semya-exp'`,
    );
    assert.equal(remainingPgDeletedPersons.rows.length, 0);
  } finally {
    await pg.store.close();
  }
});
