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

async function startServer({useSemyaModel = true, usePostgres = false} = {}) {
  const prevFlag = process.env.RODNYA_FEDERATED_SEMYI_ENABLED;
  if (useSemyaModel) {
    process.env.RODNYA_FEDERATED_SEMYI_ENABLED = "true";
  } else {
    delete process.env.RODNYA_FEDERATED_SEMYI_ENABLED;
  }

  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-wave-b2b-"));
  const dataPath = path.join(tempDir, "dev-db.json");
  let store;
  let pool = null;
  if (usePostgres) {
    const memDb = newDb();
    const {Pool} = memDb.adapters.createPg();
    pool = new Pool();
    store = new PostgresStore({pool, rowId: "default"});
  } else {
    store = new FileStore(dataPath);
  }
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
    const instance = app.listen(0, "127.0.0.1", () => resolve(instance));
  });
  const port = server.address().port;
  return {
    baseUrl: `http://127.0.0.1:${port}`,
    store,
    pool,
    tempDir,
    prevFlag,
    server,
  };
}

async function stopServer(ctx) {
  await new Promise((resolve) => ctx.server.close(resolve));
  if (ctx.pool) {
    await ctx.pool.end().catch(() => {});
  }
  await fs.rm(ctx.tempDir, {recursive: true, force: true}).catch(() => {});
  if (ctx.prevFlag !== undefined) {
    process.env.RODNYA_FEDERATED_SEMYI_ENABLED = ctx.prevFlag;
  } else {
    delete process.env.RODNYA_FEDERATED_SEMYI_ENABLED;
  }
}

async function apiJson(baseUrl, pathname, {method = "GET", token = null, body = undefined} = {}) {
  const headers = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body !== undefined) headers["Content-Type"] = "application/json";
  const res = await fetch(`${baseUrl}${pathname}`, {
    method,
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = text;
  }
  return {status: res.status, body: json};
}

async function registerUser(baseUrl, email, displayName) {
  const res = await apiJson(baseUrl, "/v1/auth/register", {
    method: "POST",
    body: {
      email,
      password: "Password123!",
      displayName,
      consentDocVersion: "2026-09-06",
    },
  });
  assert.equal(res.status, 201);
  return {
    userId: res.body.user.id,
    token: res.body.accessToken,
    identityId: res.body.user.identityId,
  };
}

async function createSemyaTreeWithMembers(ctx, owner, name, members = []) {
  const tree = await ctx.store.createTree({
    creatorId: owner.userId,
    name,
    kind: "family",
    bindSemya: true,
  });
  for (const {user, role = "editor"} of members) {
    await ctx.store.addMembership({
      semyaId: tree.semyaId,
      userId: user.userId,
      role,
      invitedByUserId: owner.userId,
    });
  }
  return {semyaId: tree.semyaId, treeId: tree.id};
}

test("Wave B2b: RelationRequest sender cancel (POST respond + DELETE + outgoing direction)", async () => {
  const ctx = await startServer();
  try {
    const sender = await registerUser(ctx.baseUrl, "s1@rodnya.app", "Отправитель");
    const recipient = await registerUser(ctx.baseUrl, "r1@rodnya.app", "Получатель");
    const {treeId} = await createSemyaTreeWithMembers(ctx, sender, "Род", [
      {user: recipient, role: "editor"},
    ]);

    // 1. Create request and test POST /respond {response:"canceled"} by sender
    const req1 = await apiJson(
      ctx.baseUrl,
      `/v1/trees/${treeId}/relation-requests`,
      {
        method: "POST",
        token: sender.token,
        body: {recipientId: recipient.userId, senderToRecipient: "sibling"},
      },
    );
    assert.equal(req1.status, 201);
    const id1 = req1.body.request.id;

    // Outgoing filter returns id1 for sender; empty for recipient's outgoing
    const outSender = await apiJson(
      ctx.baseUrl,
      `/v1/relation-requests/pending?treeId=${treeId}&direction=outgoing`,
      {token: sender.token},
    );
    assert.equal(outSender.status, 200);
    assert.equal(outSender.body.requests.length, 1);
    assert.equal(outSender.body.requests[0].id, id1);

    // Recipient cannot pass canceled; sender cannot pass accepted
    const badRecipientCancel = await apiJson(
      ctx.baseUrl,
      `/v1/relation-requests/${id1}/respond`,
      {method: "POST", token: recipient.token, body: {response: "canceled"}},
    );
    assert.equal(badRecipientCancel.status, 403);
    const badSenderAccept = await apiJson(
      ctx.baseUrl,
      `/v1/relation-requests/${id1}/respond`,
      {method: "POST", token: sender.token, body: {response: "accepted"}},
    );
    assert.equal(badSenderAccept.status, 403);

    // Sender cancels via POST /respond
    const canceledRes = await apiJson(
      ctx.baseUrl,
      `/v1/relation-requests/${id1}/respond`,
      {method: "POST", token: sender.token, body: {response: "canceled"}},
    );
    assert.equal(canceledRes.status, 200);
    assert.equal(canceledRes.body.request.status, "canceled");

    // Recipient received relation_request_canceled notification (not sender)
    const notifRecipient = await apiJson(ctx.baseUrl, "/v1/notifications", {
      token: recipient.token,
    });
    assert.ok(
      notifRecipient.body.notifications.some(
        (n) => n.type === "relation_request_canceled" && n.data?.requestId === id1,
      ),
    );
    const notifSender = await apiJson(ctx.baseUrl, "/v1/notifications", {
      token: sender.token,
    });
    assert.equal(
      notifSender.body.notifications.some((n) => n.type === "relation_request_canceled"),
      false,
    );

    // Double-action returns 409
    const dupCancel = await apiJson(
      ctx.baseUrl,
      `/v1/relation-requests/${id1}`,
      {method: "DELETE", token: sender.token},
    );
    assert.equal(dupCancel.status, 409);

    // 2. Re-sending works after cancel, and sender cancels via DELETE /v1/relation-requests/:id
    const req2 = await apiJson(
      ctx.baseUrl,
      `/v1/trees/${treeId}/relation-requests`,
      {
        method: "POST",
        token: sender.token,
        body: {recipientId: recipient.userId, senderToRecipient: "sibling"},
      },
    );
    assert.equal(req2.status, 201);
    const id2 = req2.body.request.id;

    // Recipient cannot DELETE
    const forbidDel = await apiJson(
      ctx.baseUrl,
      `/v1/relation-requests/${id2}`,
      {method: "DELETE", token: recipient.token},
    );
    assert.equal(forbidDel.status, 403);

    const delRes = await apiJson(
      ctx.baseUrl,
      `/v1/relation-requests/${id2}`,
      {method: "DELETE", token: sender.token},
    );
    assert.equal(delRes.status, 200);
    assert.equal(delRes.body.request.status, "canceled");
  } finally {
    await stopServer(ctx);
  }
});

test("Wave B2b: IdentityClaim list mine, cancel by claimant, forbidden by others, and 409 post-cancel review", async () => {
  const ctx = await startServer();
  try {
    const owner = await registerUser(ctx.baseUrl, "own@rodnya.app", "Владелец");
    const claimant = await registerUser(ctx.baseUrl, "clm@rodnya.app", "Заявитель");
    const {treeId} = await createSemyaTreeWithMembers(ctx, owner, "Семья", [
      {user: claimant, role: "editor"},
    ]);

    // Offline person created by owner
    const personRes = await apiJson(ctx.baseUrl, `/v1/trees/${treeId}/persons`, {
      method: "POST",
      token: owner.token,
      body: {firstName: "Дед", lastName: "Петров", gender: "male"},
    });
    assert.equal(personRes.status, 201);
    const personId = personRes.body.person.id;

    const claimRes = await apiJson(ctx.baseUrl, "/v1/identity-claims", {
      method: "POST",
      token: claimant.token,
      body: {treeId, personId, evidence: "Это я"},
    });
    assert.equal(claimRes.status, 201);
    const claimId = claimRes.body.claim.id;

    const mine = await apiJson(ctx.baseUrl, "/v1/identity-claims/mine", {
      token: claimant.token,
    });
    assert.equal(mine.status, 200);
    assert.equal(mine.body.claims.length, 1);
    assert.equal(mine.body.claims[0].id, claimId);
    assert.equal(mine.body.claims[0].personId, personId);
    assert.equal(mine.body.claims[0].treeId, treeId);
    assert.ok(mine.body.claims[0].personName);

    // Owner/reviewer cannot cancel claimant's claim
    const forbidCancel = await apiJson(
      ctx.baseUrl,
      `/v1/identity-claims/${claimId}`,
      {method: "DELETE", token: owner.token},
    );
    assert.equal(forbidCancel.status, 403);

    // Claimant cancels
    const cancelRes = await apiJson(
      ctx.baseUrl,
      `/v1/identity-claims/${claimId}`,
      {method: "DELETE", token: claimant.token},
    );
    assert.equal(cancelRes.status, 200);
    assert.equal(cancelRes.body.claim.status, "canceled");

    // Reviewing canceled claim returns 409; double-cancel returns 409
    const reviewCanceled = await apiJson(
      ctx.baseUrl,
      `/v1/identity-claims/${claimId}/review`,
      {method: "POST", token: owner.token, body: {decision: "approve"}},
    );
    assert.equal(reviewCanceled.status, 409);

    const dupCancel = await apiJson(
      ctx.baseUrl,
      `/v1/identity-claims/${claimId}`,
      {method: "DELETE", token: claimant.token},
    );
    assert.equal(dupCancel.status, 409);

    // Can re-submit a fresh claim after cancel
    const claim2 = await apiJson(ctx.baseUrl, "/v1/identity-claims", {
      method: "POST",
      token: claimant.token,
      body: {treeId, personId},
    });
    assert.equal(claim2.status, 201);
    assert.notEqual(claim2.body.claim.id, claimId);
  } finally {
    await stopServer(ctx);
  }
});

test("Wave B2b: Circle owner/creator check + orphan rebind across posts, deletedPosts, stories, gatherings, polls", async () => {
  const ctx = await startServer();
  try {
    const owner = await registerUser(ctx.baseUrl, "c-own@rodnya.app", "Владелец");
    const editorA = await registerUser(ctx.baseUrl, "c-eda@rodnya.app", "РедакторА");
    const editorB = await registerUser(ctx.baseUrl, "c-edb@rodnya.app", "РедакторБ");
    const viewer = await registerUser(ctx.baseUrl, "c-vw@rodnya.app", "Читатель");
    const {treeId} = await createSemyaTreeWithMembers(ctx, owner, "Круги", [
      {user: editorA, role: "editor"},
      {user: editorB, role: "editor"},
      {user: viewer, role: "viewer"},
    ]);

    // Editor A creates a custom circle
    const cRes = await apiJson(ctx.baseUrl, `/v1/trees/${treeId}/circles`, {
      method: "POST",
      token: editorA.token,
      body: {name: "Ближний круг А"},
    });
    assert.equal(cRes.status, 201);
    const circleId = cRes.body.id;

    // Editor B (not creator, not owner) is forbidden from renaming, updating members, or deleting
    assert.equal(
      (
        await apiJson(ctx.baseUrl, `/v1/trees/${treeId}/circles/${circleId}`, {
          method: "PATCH",
          token: editorB.token,
          body: {name: "Чужое имя"},
        })
      ).status,
      403,
    );
    assert.equal(
      (
        await apiJson(
          ctx.baseUrl,
          `/v1/trees/${treeId}/circles/${circleId}/members`,
          {
            method: "PUT",
            token: editorB.token,
            body: {identityIds: [editorB.identityId]},
          },
        )
      ).status,
      403,
    );
    assert.equal(
      (
        await apiJson(ctx.baseUrl, `/v1/trees/${treeId}/circles/${circleId}`, {
          method: "DELETE",
          token: editorB.token,
        })
      ).status,
      403,
    );

    // Editor A (creator) can rename & update members
    const patchA = await apiJson(
      ctx.baseUrl,
      `/v1/trees/${treeId}/circles/${circleId}`,
      {
        method: "PATCH",
        token: editorA.token,
        body: {name: "Обновлённый круг А"},
      },
    );
    assert.equal(patchA.status, 200);
    assert.equal(patchA.body.name, "Обновлённый круг А");

    // Seed post, soft-deleted post, story, gathering, poll targeting custom circleId
    const post1 = await apiJson(ctx.baseUrl, "/v1/posts", {
      method: "POST",
      token: editorA.token,
      body: {treeId, circleId, content: "Пост в круге"},
    });
    assert.equal(post1.status, 201);
    const postToDelete = await apiJson(ctx.baseUrl, "/v1/posts", {
      method: "POST",
      token: editorA.token,
      body: {treeId, circleId, content: "Корзинный пост"},
    });
    assert.equal(postToDelete.status, 201);
    const postToDeleteId = (postToDelete.body.post || postToDelete.body).id;
    await apiJson(ctx.baseUrl, `/v1/posts/${postToDeleteId}`, {
      method: "DELETE",
      token: editorA.token,
    });
    const story1 = await apiJson(ctx.baseUrl, "/v1/stories", {
      method: "POST",
      token: editorA.token,
      body: {treeId, circleId, type: "text", text: "История в круге"},
    });
    assert.equal(story1.status, 201);
    const poll1 = await apiJson(ctx.baseUrl, "/v1/polls", {
      method: "POST",
      token: editorA.token,
      body: {
        treeId,
        circleId,
        question: "Когда встречаемся?",
        options: ["Суббота", "Воскресенье"],
      },
    });
    assert.equal(poll1.status, 201);
    const gath1 = await apiJson(ctx.baseUrl, "/v1/gatherings", {
      method: "POST",
      token: editorA.token,
      body: {
        treeId,
        circleId,
        title: "Ужин",
        startAt: new Date(Date.now() + 86400000).toISOString(),
      },
    });
    assert.equal(gath1.status, 201);

    // Before deletion, viewer is not in custom circle -> cannot see story/poll/gathering/post
    const preStories = await apiJson(ctx.baseUrl, `/v1/stories?treeId=${treeId}`, {token: viewer.token});
    assert.equal((Array.isArray(preStories.body) ? preStories.body : preStories.body.stories).length, 0);

    // Semya owner CAN delete Editor A's circle (204)
    const delOwner = await apiJson(
      ctx.baseUrl,
      `/v1/trees/${treeId}/circles/${circleId}`,
      {method: "DELETE", token: owner.token},
    );
    assert.equal(delOwner.status, 204);

    // After deletion, all 4 active collections + deletedPost snapshot rebound to all_tree -> viewer sees them!
    const viewerPosts = await apiJson(ctx.baseUrl, `/v1/posts?treeId=${treeId}`, {token: viewer.token});
    const viewerStories = await apiJson(ctx.baseUrl, `/v1/stories?treeId=${treeId}`, {token: viewer.token});
    const viewerPolls = await apiJson(ctx.baseUrl, `/v1/polls?treeId=${treeId}`, {token: viewer.token});
    const viewerGatherings = await apiJson(ctx.baseUrl, `/v1/gatherings?treeId=${treeId}`, {token: viewer.token});
    assert.equal((Array.isArray(viewerPosts.body) ? viewerPosts.body : viewerPosts.body.posts).length, 1);
    assert.equal((Array.isArray(viewerStories.body) ? viewerStories.body : viewerStories.body.stories).length, 1);
    assert.equal((Array.isArray(viewerPolls.body) ? viewerPolls.body : viewerPolls.body.polls).length, 1);
    assert.equal((Array.isArray(viewerGatherings.body) ? viewerGatherings.body : viewerGatherings.body.gatherings).length, 1);

    // Restore deleted post -> visible to viewer because snapshot.circleId was rebound!
    const deletedListRes = await apiJson(ctx.baseUrl, "/v1/me/deleted-posts", {
      token: editorA.token,
    });
    assert.equal(deletedListRes.status, 200);
    const deletedRow = (deletedListRes.body.deletedPosts || []).find(
      (entry) =>
        entry.originalPostId === postToDeleteId ||
        entry.postId === postToDeleteId ||
        entry.id === postToDeleteId,
    );
    assert.ok(deletedRow, "deleted post row should exist in /v1/me/deleted-posts");
    const restoreRes = await apiJson(
      ctx.baseUrl,
      `/v1/deleted-posts/${deletedRow.id}/restore`,
      {method: "POST", token: editorA.token},
    );
    assert.equal(restoreRes.status, 200);
    const viewerPostsAfterRestore = await apiJson(
      ctx.baseUrl,
      `/v1/posts?treeId=${treeId}`,
      {token: viewer.token},
    );
    assert.equal((Array.isArray(viewerPostsAfterRestore.body) ? viewerPostsAfterRestore.body : viewerPostsAfterRestore.body.posts).length, 2);
  } finally {
    await stopServer(ctx);
  }
});

test("Wave B2b: UserProfile photo sync via PATCH /users/:id/profile & photoURL alias fixes photoGallery short-circuit", async () => {
  const ctx = await startServer();
  try {
    const user = await registerUser(ctx.baseUrl, "pic@rodnya.app", "Фото Юзер");
    const treeRes = await apiJson(ctx.baseUrl, "/v1/trees", {
      method: "POST",
      token: user.token,
      body: {name: "Дерево", isPrivate: true},
    });
    const treeId = treeRes.body.tree.id;

    // Auto-created user person exists in tree; patch via /v1/users/:id/profile with uppercase photoURL
    const photoUrl = "https://cdn.rodnya-tree.ru/avatars/new-photo.jpg";
    const patch = await apiJson(
      ctx.baseUrl,
      `/v1/users/${user.userId}/profile`,
      {
        method: "PATCH",
        token: user.token,
        body: {photoURL: photoUrl},
      },
    );
    assert.equal(patch.status, 200);
    assert.equal(patch.body.profile.photoUrl, photoUrl);

    const personsRes = await apiJson(ctx.baseUrl, `/v1/trees/${treeId}/persons`, {
      token: user.token,
    });
    const mePerson = personsRes.body.persons.find((p) => p.userId === user.userId);
    assert.ok(mePerson);
    assert.equal(mePerson.photoUrl, photoUrl);
    assert.equal(mePerson.primaryPhotoUrl, photoUrl);
    assert.ok(
      Array.isArray(mePerson.photoGallery) &&
        mePerson.photoGallery.some((g) => g.url === photoUrl && g.isPrimary === true),
      "photoGallery should include synced profile photo as primary",
    );
  } finally {
    await stopServer(ctx);
  }
});

for (const usePostgres of [false, true]) {
  const label = usePostgres ? "PostgresStore (pg-mem)" : "FileStore";
  test(`Wave B2b (${label}): change-password keeps current session, revokes other sessions, & unlocks safe OAuth unlink`, async () => {
    const ctx = await startServer({usePostgres});
    try {
      // Seed an OAuth-only user (password: null, only Google linked)
      const oauthUser = await ctx.store.createUser({
        email: "oauth-only@rodnya.app",
        password: null,
        displayName: "Гугл Пользователь",
        authIdentity: {
          provider: "google",
          providerUserId: "goog-uid-1",
          email: "oauth-only@rodnya.app",
          displayName: "Гугл Пользователь",
        },
        consentDocVersion: "2026-09-06",
      });
      const sess1 = await ctx.store.createSession(oauthUser.id, {deviceName: "Phone"});
      const sess2 = await ctx.store.createSession(oauthUser.id, {deviceName: "Web"});

      // Unlinking sole OAuth method without password returns 409 LAST_LOGIN_METHOD
      const blockedUnlink = await apiJson(ctx.baseUrl, "/v1/auth/providers/google", {
        method: "DELETE",
        token: sess1.token,
      });
      assert.equal(blockedUnlink.status, 409);

      // Unknown or password provider rejected with 400; non-linked vk rejected with 404
      assert.equal(
        (
          await apiJson(ctx.baseUrl, "/v1/auth/providers/password", {
            method: "DELETE",
            token: sess1.token,
          })
        ).status,
        400,
      );
      assert.equal(
        (
          await apiJson(ctx.baseUrl, "/v1/auth/providers/vk", {
            method: "DELETE",
            token: sess1.token,
          })
        ).status,
        404,
      );

      // OAuth-only user sets initial password via /v1/auth/change-password without currentPassword
      const setPw = await apiJson(ctx.baseUrl, "/v1/auth/change-password", {
        method: "POST",
        token: sess1.token,
        body: {newPassword: "NewPassword123!"},
      });
      assert.equal(setPw.status, 200);
      assert.equal(setPw.body.hasPassword, true);
      assert.ok(setPw.body.providerIds.includes("password"));
      assert.ok(setPw.body.providerIds.includes("google"));

      // Caller session sess1 stays valid, sess2 is revoked (401)
      assert.equal(
        (
          await apiJson(
            ctx.baseUrl,
            "/v1/profile/me/account-linking-status",
            {token: sess1.token},
          )
        ).status,
        200,
      );
      assert.equal(
        (
          await apiJson(
            ctx.baseUrl,
            "/v1/profile/me/account-linking-status",
            {token: sess2.token},
          )
        ).status,
        401,
      );

      // Wrong currentPassword returns 401; same password returns 400; valid change succeeds
      assert.equal(
        (
          await apiJson(ctx.baseUrl, "/v1/auth/change-password", {
            method: "POST",
            token: sess1.token,
            body: {currentPassword: "WrongPassword!", newPassword: "AnotherPassword123!"},
          })
        ).status,
        401,
      );
      assert.equal(
        (
          await apiJson(ctx.baseUrl, "/v1/auth/change-password", {
            method: "POST",
            token: sess1.token,
            body: {currentPassword: "NewPassword123!", newPassword: "NewPassword123!"},
          })
        ).status,
        400,
      );
      const changed = await apiJson(ctx.baseUrl, "/v1/auth/change-password", {
        method: "POST",
        token: sess1.token,
        body: {currentPassword: "NewPassword123!", newPassword: "FinalPassword123!"},
      });
      assert.equal(changed.status, 200);

      // Now unlinking google succeeds AND google stays gone (deriveProviderIdsForUser union check)
      const unlinked = await apiJson(ctx.baseUrl, "/v1/auth/providers/google", {
        method: "DELETE",
        token: sess1.token,
      });
      assert.equal(unlinked.status, 200);
      assert.deepEqual(unlinked.body.providerIds, ["password"]);
      assert.deepEqual(unlinked.body.linkedProviderIds, []);
      assert.equal(unlinked.body.primaryTrustedChannel, null);

      const statusAfter = await apiJson(
        ctx.baseUrl,
        "/v1/profile/me/account-linking-status",
        {token: sess1.token},
      );
      assert.equal(statusAfter.status, 200);
      assert.deepEqual(statusAfter.body.linkedProviderIds, ["password"]);
      assert.deepEqual(
        statusAfter.body.identities.map((i) => i.provider),
        ["password"],
      );

      // Repeating unlink returns 404
      assert.equal(
        (
          await apiJson(ctx.baseUrl, "/v1/auth/providers/google", {
            method: "DELETE",
            token: sess1.token,
          })
        ).status,
        404,
      );
    } finally {
      await stopServer(ctx);
    }
  });
}
