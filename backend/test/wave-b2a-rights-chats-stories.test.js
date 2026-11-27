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

const PNG_1X1_BYTES = Buffer.from([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, 0x49,
  0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06,
  0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44,
  0x41, 0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0d,
  0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42,
  0x60, 0x82,
]);

async function startServer({useSemyaModel = true, usePostgres = false} = {}) {
  const prevFlag = process.env.RODNYA_FEDERATED_SEMYI_ENABLED;
  if (useSemyaModel) {
    process.env.RODNYA_FEDERATED_SEMYI_ENABLED = "true";
  } else {
    delete process.env.RODNYA_FEDERATED_SEMYI_ENABLED;
  }

  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-wave-b2a-"));
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
    const inst = app.listen(0, "127.0.0.1", () => resolve(inst));
  });
  realtimeHub.attach(server);
  return {
    baseUrl: `http://127.0.0.1:${server.address().port}`,
    server,
    store,
    pool,
    tempDir,
    prevFlag,
  };
}

async function stopServer({server, tempDir, prevFlag}) {
  if (prevFlag === undefined) {
    delete process.env.RODNYA_FEDERATED_SEMYI_ENABLED;
  } else {
    process.env.RODNYA_FEDERATED_SEMYI_ENABLED = prevFlag;
  }
  await new Promise((resolve) => server.close(resolve));
  await fs.rm(tempDir, {recursive: true, force: true}).catch(() => {});
}

async function registerUser(baseUrl, email, displayName) {
  const res = await fetch(`${baseUrl}/v1/auth/register`, {
    method: "POST",
    headers: {"content-type": "application/json"},
    body: JSON.stringify({
      email,
      password: "Password123!",
      displayName,
      firstName: displayName,
      lastName: "Тестов",
      consentDocVersion: "test-consent-v1",
    }),
  });
  assert.equal(res.status, 201);
  const body = await res.json();
  return {
    token: body.accessToken,
    user: body.user,
    userId: body.user.id,
  };
}

async function apiJson(baseUrl, pathname, {method = "GET", token, body} = {}) {
  const res = await fetch(`${baseUrl}${pathname}`, {
    method,
    headers: {
      ...(token ? {authorization: `Bearer ${token}`} : {}),
      ...(body !== undefined ? {"content-type": "application/json"} : {}),
    },
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

async function setupFamilyTreeWithMember(ctx, owner, member, treeName = "Семья Б2А") {
  const tree = await ctx.store.createTree({
    creatorId: owner.userId,
    name: treeName,
    kind: "family",
    bindSemya: true,
  });
  const semyaId = tree.semyaId;

  if (member) {
    await ctx.store.addMembership({
      semyaId,
      userId: member.userId,
      role: "editor",
      invitedByUserId: owner.userId,
    });
  }

  return {treeId: tree.id, semyaId};
}

test("Wave B2a · EditGrant validates grantee, hydrates GET /grants, notifies, and supports grantee self-revoke", async () => {
  const ctx = await startServer();
  try {
    const owner = await registerUser(ctx.baseUrl, "grant-owner@example.com", "Олег");
    const grantee = await registerUser(ctx.baseUrl, "grant-grantee@example.com", "Ирина");
    const stranger = await registerUser(ctx.baseUrl, "grant-stranger@example.com", "Чужой");
    const {treeId} = await setupFamilyTreeWithMember(ctx, owner, grantee);

    const createdPerson = await apiJson(ctx.baseUrl, `/v1/trees/${treeId}/persons`, {
      method: "POST",
      token: owner.token,
      body: {name: "Бабушка Анна", gender: "female", isLiving: true},
    });
    assert.equal(createdPerson.status, 201);
    const createdPersonId =
      (createdPerson.body.person || createdPerson.body).id;
    const personRead = await apiJson(
      ctx.baseUrl,
      `/v1/trees/${treeId}/persons/${createdPersonId}`,
      {token: owner.token},
    );
    assert.equal(personRead.status, 200);
    const graphPersonId =
      personRead.body.person?.identityId || personRead.body.identityId;
    assert.ok(graphPersonId);

    const missingGranteeRes = await apiJson(
      ctx.baseUrl,
      `/v1/graph-persons/${graphPersonId}/grants`,
      {
        method: "POST",
        token: owner.token,
        body: {granteeUserId: "user-does-not-exist", scope: "edit"},
      },
    );
    assert.equal(missingGranteeRes.status, 404);

    const grantedRes = await apiJson(
      ctx.baseUrl,
      `/v1/graph-persons/${graphPersonId}/grants`,
      {
        method: "POST",
        token: owner.token,
        body: {granteeUserId: grantee.userId, scope: "edit"},
      },
    );
    assert.equal(grantedRes.status, 201);
    const grantId = grantedRes.body.grant.id;

    // Grantee receives notification.
    const notifs = await apiJson(ctx.baseUrl, "/v1/notifications?status=unread&limit=20", {
      token: grantee.token,
    });
    assert.equal(notifs.status, 200);
    const items = notifs.body.items || notifs.body.notifications || notifs.body;
    assert.ok(
      items.some(
        (n) =>
          n.type === "edit_grant_received" &&
          n.data?.grantId === grantId &&
          n.data?.graphPersonId === graphPersonId,
      ),
    );

    // Owner lists hydrated grants for card.
    const listGrants = await apiJson(
      ctx.baseUrl,
      `/v1/graph-persons/${graphPersonId}/grants`,
      {token: owner.token},
    );
    assert.equal(listGrants.status, 200);
    assert.equal(listGrants.body.grants.length, 1);
    assert.equal(listGrants.body.grants[0].grantee?.id, grantee.userId);
    assert.equal(listGrants.body.grants[0].grantee?.displayName, "Ирина");

    // Stranger and grantee cannot revoke on the grantor endpoint (403).
    const strangerRevoke = await apiJson(
      ctx.baseUrl,
      `/v1/graph-persons/${graphPersonId}/grants/${grantId}`,
      {method: "DELETE", token: stranger.token},
    );
    assert.equal(strangerRevoke.status, 403);

    const granteeOwnerRoute = await apiJson(
      ctx.baseUrl,
      `/v1/graph-persons/${graphPersonId}/grants/${grantId}`,
      {method: "DELETE", token: grantee.token},
    );
    assert.equal(granteeOwnerRoute.status, 403);

    // Owner cannot relinquish someone else's incoming grant.
    const ownerRelinquish = await apiJson(
      ctx.baseUrl,
      `/v1/me/edit-grants/${grantId}`,
      {method: "DELETE", token: owner.token},
    );
    assert.equal(ownerRelinquish.status, 403);

    // Grantee can self-relinquish via /v1/me/edit-grants/:grantId!
    const selfRevoke = await apiJson(
      ctx.baseUrl,
      `/v1/me/edit-grants/${grantId}`,
      {method: "DELETE", token: grantee.token},
    );
    assert.equal(selfRevoke.status, 200);
    assert.ok(selfRevoke.body.grant.revokedAt);
  } finally {
    await stopServer(ctx);
  }
});

for (const usePostgres of [false, true]) {
  const label = usePostgres ? "PostgresStore" : "FileStore";

  test(`Wave B2a · Chat lifecycle (${label}): archive/mute prefs, direct hide+clear+resurface, group createdBy transfer, hard delete`, async () => {
    const ctx = await startServer({usePostgres});
    try {
      const alice = await registerUser(ctx.baseUrl, `alice-${label}@example.com`, "Алиса");
      const bob = await registerUser(ctx.baseUrl, `bob-${label}@example.com`, "Борис");
      const clara = await registerUser(ctx.baseUrl, `clara-${label}@example.com`, "Клара");

      // 1. Direct chat between Alice & Bob.
      const directChatRes = await apiJson(ctx.baseUrl, "/v1/chats/direct", {
        method: "POST",
        token: alice.token,
        body: {otherUserId: bob.userId},
      });
      assert.equal(directChatRes.status, 200);
      const directChatId = directChatRes.body.chatId;

      const msg1 = await apiJson(ctx.baseUrl, `/v1/chats/${directChatId}/messages`, {
        method: "POST",
        token: alice.token,
        body: {text: "Старое сообщение до удаления"},
      });
      assert.equal(msg1.status, 201);

      // Mute & archive for Bob -> verify preview fields and suppressed push notification.
      const prefsRes = await apiJson(
        ctx.baseUrl,
        `/v1/chats/${directChatId}/preferences`,
        {
          method: "PATCH",
          token: bob.token,
          body: {isArchived: true, notificationLevel: "muted"},
        },
      );
      assert.equal(prefsRes.status, 200);
      assert.equal(prefsRes.body.isArchived, true);
      assert.equal(prefsRes.body.notificationLevel, "muted");

      const bobPreviews1 = await apiJson(ctx.baseUrl, "/v1/chats", {token: bob.token});
      assert.equal(bobPreviews1.status, 200);
      const bobDirectPreview = bobPreviews1.body.chats.find((c) => c.chatId === directChatId);
      assert.equal(bobDirectPreview.isArchived, true);
      assert.equal(bobDirectPreview.notificationLevel, "muted");

      const msgMuted = await apiJson(ctx.baseUrl, `/v1/chats/${directChatId}/messages`, {
        method: "POST",
        token: alice.token,
        body: {text: "Тихое сообщение"},
      });
      assert.equal(msgMuted.status, 201);
      await new Promise((r) => setTimeout(r, 30));
      const bobNotifs = await apiJson(ctx.baseUrl, "/v1/notifications?status=unread&limit=20", {
        token: bob.token,
      });
      const bobNotifList = bobNotifs.body.items || bobNotifs.body.notifications || bobNotifs.body;
      assert.equal(
        bobNotifList.some(
          (n) => n.type === "chat_message" && n.data?.messageId === msgMuted.body.id,
        ),
        false,
      );

      // Wait 5ms so clearedBefore > msgMuted.timestamp strictly.
      await new Promise((r) => setTimeout(r, 10));

      // Alice hides/deletes direct chat for herself -> Bob still sees history!
      const aliceDel = await apiJson(ctx.baseUrl, `/v1/chats/${directChatId}`, {
        method: "DELETE",
        token: alice.token,
      });
      assert.equal(aliceDel.status, 200);
      assert.equal(aliceDel.body.action, "hidden");

      const alicePreviewsHidden = await apiJson(ctx.baseUrl, "/v1/chats", {
        token: alice.token,
      });
      assert.equal(
        alicePreviewsHidden.body.chats.some((c) => c.chatId === directChatId),
        false,
      );
      const aliceMsgsAfterDelete = await apiJson(
        ctx.baseUrl,
        `/v1/chats/${directChatId}/messages`,
        {token: alice.token},
      );
      assert.equal(aliceMsgsAfterDelete.body.messages.length, 0);

      // Bob still sees both messages.
      const bobMsgs = await apiJson(
        ctx.baseUrl,
        `/v1/chats/${directChatId}/messages`,
        {token: bob.token},
      );
      assert.equal(bobMsgs.body.messages.length, 2);

      // Bob sends a new message -> chat resurfaces for Alice with ONLY the new message!
      await new Promise((r) => setTimeout(r, 10));
      const msgAfterClear = await apiJson(
        ctx.baseUrl,
        `/v1/chats/${directChatId}/messages`,
        {
          method: "POST",
          token: bob.token,
          body: {text: "Новое сообщение после очистки"},
        },
      );
      assert.equal(msgAfterClear.status, 201);

      const alicePreviewsResurfaced = await apiJson(ctx.baseUrl, "/v1/chats", {
        token: alice.token,
      });
      const resurfaced = alicePreviewsResurfaced.body.chats.find(
        (c) => c.chatId === directChatId,
      );
      assert.ok(resurfaced);
      assert.equal(resurfaced.isArchived, false);
      assert.equal(resurfaced.unreadCount, 1);

      const aliceNewMsgs = await apiJson(
        ctx.baseUrl,
        `/v1/chats/${directChatId}/messages`,
        {token: alice.token},
      );
      assert.equal(aliceNewMsgs.body.messages.length, 1);
      assert.equal(aliceNewMsgs.body.messages[0].text, "Новое сообщение после очистки");

      // 2. Group chat: createdBy leaves -> ownership transfers; last leaves OR ?forAll=true -> deleted cleanly.
      const groupRes = await apiJson(ctx.baseUrl, "/v1/chats/groups", {
        method: "POST",
        token: alice.token,
        body: {
          title: "Семейный совет",
          participantIds: [bob.userId, clara.userId],
        },
      });
      assert.equal(groupRes.status, 201);
      const groupId = groupRes.body.chatId;

      // Bob (non-creator) cannot delete for all.
      const bobForAll = await apiJson(
        ctx.baseUrl,
        `/v1/chats/${groupId}?forAll=true`,
        {method: "DELETE", token: bob.token},
      );
      assert.equal(bobForAll.status, 403);

      // Alice (creator) leaves -> createdBy transfers to next participant (bob or clara).
      const aliceLeave = await apiJson(ctx.baseUrl, `/v1/chats/${groupId}/leave`, {
        method: "POST",
        token: alice.token,
      });
      assert.equal(aliceLeave.status, 200);
      const newOwnerId = aliceLeave.body.chat.createdBy;
      assert.ok(newOwnerId === bob.userId || newOwnerId === clara.userId);
      assert.equal(aliceLeave.body.chat.participantIds.includes(alice.userId), false);

      // New owner can hard-delete group for all!
      const ownerToken = newOwnerId === bob.userId ? bob.token : clara.token;
      const groupHardDel = await apiJson(
        ctx.baseUrl,
        `/v1/chats/${groupId}?forAll=true`,
        {method: "DELETE", token: ownerToken},
      );
      assert.equal(groupHardDel.status, 200);
      assert.equal(groupHardDel.body.action, "deleted");

      const checkDeletedGroup = await apiJson(ctx.baseUrl, `/v1/chats/${groupId}`, {
        token: bob.token,
      });
      assert.equal(checkDeletedGroup.status, 403);
    } finally {
      await stopServer(ctx);
    }
  });
}

test("Wave B2a · StoryArchive retains expired stories for author only, blocks view/react, sweeps >365d + orphan reactions", async () => {
  const ctx = await startServer();
  try {
    const author = await registerUser(ctx.baseUrl, "story-author@example.com", "Дарья");
    const reader = await registerUser(ctx.baseUrl, "story-reader@example.com", "Егор");
    const {treeId} = await setupFamilyTreeWithMember(ctx, author, reader);

    // Seed one recently-expired story (10 days ago) and one active story, plus a >400d story.
    const expired10dIso = new Date(Date.now() - 10 * 86_400_000).toISOString();
    const expired400dIso = new Date(Date.now() - 400 * 86_400_000).toISOString();

    const activeRes = await apiJson(ctx.baseUrl, "/v1/stories", {
      method: "POST",
      token: author.token,
      body: {treeId, type: "text", text: "Активная история"},
    });
    assert.equal(activeRes.status, 201);

    await ctx.store._mutate((db) => {
      db.stories.push(
        {
          id: "story-expired-10d",
          treeId,
          authorId: author.userId,
          authorName: "Дарья",
          authorPhotoUrl: null,
          type: "text",
          text: "История 10 дней назад",
          mediaUrl: null,
          thumbnailUrl: null,
          viewedBy: [],
          circleId: null,
          scopeType: "wholeTree",
          anchorPersonIds: [],
          createdAt: expired10dIso,
          updatedAt: expired10dIso,
          expiresAt: expired10dIso,
        },
        {
          id: "story-expired-400d",
          treeId,
          authorId: author.userId,
          authorName: "Дарья",
          authorPhotoUrl: null,
          type: "text",
          text: "Очень старая история",
          mediaUrl: null,
          thumbnailUrl: null,
          viewedBy: [],
          circleId: null,
          scopeType: "wholeTree",
          anchorPersonIds: [],
          createdAt: expired400dIso,
          updatedAt: expired400dIso,
          expiresAt: expired400dIso,
        },
      );
      db.storyReactions = db.storyReactions || [];
      db.storyReactions.push({
        storyId: "story-missing-999",
        userId: author.userId,
        emoji: "❤️",
        createdAt: expired10dIso,
      });
    });

    // Default feed hides expired stories, AND no longer deletes them from storage!
    const feedStories = await apiJson(ctx.baseUrl, `/v1/stories?treeId=${treeId}`, {
      token: reader.token,
    });
    assert.equal(feedStories.status, 200);
    assert.equal(feedStories.body.length, 1);
    assert.equal(feedStories.body[0].id, activeRes.body.id);

    // Other user CANNOT fetch author's expired stories even with includeArchive=true.
    const readerArchive = await apiJson(
      ctx.baseUrl,
      `/v1/stories?authorId=${author.userId}&includeArchive=true`,
      {token: reader.token},
    );
    assert.equal(readerArchive.status, 200);
    assert.equal(readerArchive.body.some((s) => s.id === "story-expired-10d"), false);

    // Author gets both active and expired stories with includeArchive=true.
    const authorArchive = await apiJson(
      ctx.baseUrl,
      `/v1/stories?authorId=${author.userId}&includeArchive=true`,
      {token: author.token},
    );
    assert.equal(authorArchive.status, 200);
    assert.ok(authorArchive.body.some((s) => s.id === "story-expired-10d"));
    assert.ok(authorArchive.body.some((s) => s.id === activeRes.body.id));

    // View & reactions reject expired stories with 404.
    const viewExpired = await apiJson(
      ctx.baseUrl,
      "/v1/stories/story-expired-10d/view",
      {method: "POST", token: reader.token},
    );
    assert.equal(viewExpired.status, 404);

    // Maintenance sweep removes >365d expired stories + orphan reactions while keeping 10d archive.
    const sweepSummary = await ctx.store.hardDeleteExpired({
      logRetention: {storiesArchiveDays: 365},
    });
    assert.equal(sweepSummary.logRetention.storiesExpiredArchive, 1);
    assert.equal(sweepSummary.logRetention.storyReactionsOrphan, 1);

    const dbAfterSweep = await ctx.store._read();
    assert.equal(
      dbAfterSweep.stories.some((s) => s.id === "story-expired-400d"),
      false,
    );
    assert.equal(
      dbAfterSweep.stories.some((s) => s.id === "story-expired-10d"),
      true,
    );

    // Author can delete an expired archived story via DELETE /v1/stories/:id.
    const delExpired = await apiJson(
      ctx.baseUrl,
      "/v1/stories/story-expired-10d",
      {method: "DELETE", token: author.token},
    );
    assert.equal(delExpired.status, 204);
  } finally {
    await stopServer(ctx);
  }
});

test("Wave B2a · StoryRequest v2: PATCH edit, PUT /media upload, and combined + legacy in-app answers", async () => {
  const ctx = await startServer();
  try {
    const asker = await registerUser(ctx.baseUrl, "sr-asker@example.com", "Артём");
    const target = await registerUser(ctx.baseUrl, "sr-target@example.com", "Лида");
    const {treeId} = await setupFamilyTreeWithMember(ctx, asker, target);

    const personRes = await apiJson(ctx.baseUrl, `/v1/trees/${treeId}/persons`, {
      method: "POST",
      token: asker.token,
      body: {
        name: "Бабушка Лида",
        gender: "female",
        isLiving: true,
      },
    });
    assert.equal(personRes.status, 201);
    const personId = (personRes.body.person || personRes.body).id;

    // Create in-app request.
    const req1 = await apiJson(ctx.baseUrl, "/v1/story-requests", {
      method: "POST",
      token: asker.token,
      body: {
        treeId,
        personId,
        deliveryMode: "in_app",
        targetUserId: target.userId,
        question: {text: "Как прошло ваше детство в деревне?"},
      },
    });
    assert.equal(req1.status, 201);
    const requestId = req1.body.request.id;

    // Target cannot PATCH initiator's question.
    const targetPatch = await apiJson(
      ctx.baseUrl,
      `/v1/story-requests/${requestId}`,
      {
        method: "PATCH",
        token: target.token,
        body: {questionText: "Чужое редактирование"},
      },
    );
    assert.equal(targetPatch.status, 403);

    // Initiator can PATCH questionText while pending.
    const askerPatch = await apiJson(
      ctx.baseUrl,
      `/v1/story-requests/${requestId}`,
      {
        method: "PATCH",
        token: asker.token,
        body: {questionText: "Какой дом детства запомнился больше всего?"},
      },
    );
    assert.equal(askerPatch.status, 200);
    assert.equal(
      askerPatch.body.request.question.text,
      "Какой дом детства запомнился больше всего?",
    );

    // Authenticated target uploads photo via PUT /v1/story-requests/:id/media.
    const mediaUpload = await fetch(
      `${ctx.baseUrl}/v1/story-requests/${requestId}/media?kind=photo`,
      {
        method: "PUT",
        headers: {
          authorization: `Bearer ${target.token}`,
          "content-type": "image/png",
        },
        body: PNG_1X1_BYTES,
      },
    );
    assert.equal(mediaUpload.status, 201);
    const mediaBody = await mediaUpload.json();
    assert.ok(mediaBody.url);

    // Combined v2 answer: audio (with transcript) + text + photo in one submit!
    const combinedAnswer = await apiJson(
      ctx.baseUrl,
      `/v1/story-requests/${requestId}/answer`,
      {
        method: "POST",
        token: target.token,
        body: {
          audio: {
            mediaUrl: `${ctx.baseUrl}/uploads/story-answers/test-voice.m4a`,
            durationSec: 18,
            transcript: "Помню большой сад за домом.",
          },
          text: "И старую яблоню у колодца.",
          photo: {
            mediaUrl: mediaBody.url,
            caption: "Дом в 1978 году",
          },
        },
      },
    );
    assert.equal(combinedAnswer.status, 200);
    assert.equal(combinedAnswer.body.blocks.length, 3);
    assert.equal(combinedAnswer.body.blocks[0].type, "audio");
    assert.equal(
      combinedAnswer.body.blocks[0].content.transcript,
      "Помню большой сад за домом.",
    );
    assert.equal(combinedAnswer.body.blocks[1].type, "paragraph");
    assert.equal(combinedAnswer.body.blocks[2].type, "photo");
    assert.equal(combinedAnswer.body.request.answer.articleBlockIds.length, 3);

    // After answer, PATCH returns 409 NOT_PENDING.
    const patchAfterAnswer = await apiJson(
      ctx.baseUrl,
      `/v1/story-requests/${requestId}`,
      {
        method: "PATCH",
        token: asker.token,
        body: {questionText: "Поздно менять"},
      },
    );
    assert.equal(patchAfterAnswer.status, 409);

    // Legacy single-kind payload with audioDurationMs still works.
    const req2 = await apiJson(ctx.baseUrl, "/v1/story-requests", {
      method: "POST",
      token: asker.token,
      body: {
        treeId,
        personId,
        deliveryMode: "in_app",
        targetUserId: target.userId,
        question: {text: "Кто научил готовить пироги?"},
      },
    });
    assert.equal(req2.status, 201);
    const legacyAnswer = await apiJson(
      ctx.baseUrl,
      `/v1/story-requests/${req2.body.request.id}/answer`,
      {
        method: "POST",
        token: target.token,
        body: {
          kind: "text",
          text: "Бабушка Маша каждое воскресенье.",
        },
      },
    );
    assert.equal(legacyAnswer.status, 200);
    assert.equal(legacyAnswer.body.block.type, "paragraph");
    assert.equal(legacyAnswer.body.blocks.length, 1);
  } finally {
    await stopServer(ctx);
  }
});
