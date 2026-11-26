const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");

const {createApp} = require("../src/app");
const {FileStore} = require("../src/store");
const {RealtimeHub} = require("../src/realtime-hub");
const {PushGateway} = require("../src/push-gateway");

async function startServer({
  useSemyaModel = false,
  liveKitService = null,
  maxAuthClient = null,
} = {}) {
  const prevFlag = process.env.RODNYA_FEDERATED_SEMYI_ENABLED;
  if (useSemyaModel) {
    process.env.RODNYA_FEDERATED_SEMYI_ENABLED = "true";
  } else {
    delete process.env.RODNYA_FEDERATED_SEMYI_ENABLED;
  }

  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-wave2-"));
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
      publicAppUrl: "https://rodnya-tree.ru",
    },
    realtimeHub,
    pushGateway,
    ...(liveKitService ? {liveKitService} : {}),
    ...(maxAuthClient ? {maxAuthClient} : {}),
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
      consentDocVersion: "test-consent-v1",
    }),
  });
  assert.equal(res.status, 201);
  return res.json();
}

test("Wave 2.1: federated viewer cannot mutate tree/anonymous cards, can edit own card, and browse/invite tokens are scoped", async () => {
  const ctx = await startServer({useSemyaModel: true});
  try {
    const owner = await registerUser(ctx.baseUrl, "w2-owner@test.app", "Owner");
    const viewer = await registerUser(ctx.baseUrl, "w2-viewer@test.app", "Viewer");

    const tree = await ctx.store.createTree({
      creatorId: owner.user.id,
      name: "Семья",
      kind: "family",
    });
    const semya = await ctx.store.createSemya({
      ownerId: owner.user.id,
      name: "Семья",
      treeId: tree.id,
    });
    const anonPerson = await ctx.store.createPerson({
      treeId: tree.id,
      creatorId: owner.user.id,
      personData: {firstName: "Дедушка", gender: "male"},
    });
    const viewerPerson = await ctx.store.createPerson({
      treeId: tree.id,
      creatorId: owner.user.id,
      userId: viewer.user.id,
      personData: {firstName: "Внук", gender: "male"},
    });
    await ctx.store.addMembership({
      semyaId: semya.id,
      userId: viewer.user.id,
      role: "viewer",
      invitedByUserId: owner.user.id,
    });

    const addPersonRes = await fetch(`${ctx.baseUrl}/v1/trees/${tree.id}/persons`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${viewer.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({firstName: "Новый", gender: "male"}),
    });
    assert.equal(addPersonRes.status, 403);

    const editAnonRes = await fetch(
      `${ctx.baseUrl}/v1/trees/${tree.id}/persons/${anonPerson.id}`,
      {
        method: "PATCH",
        headers: {
          authorization: `Bearer ${viewer.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({firstName: "Прадед"}),
      },
    );
    assert.equal(editAnonRes.status, 403);

    const editOwnRes = await fetch(
      `${ctx.baseUrl}/v1/trees/${tree.id}/persons/${viewerPerson.id}`,
      {
        method: "PATCH",
        headers: {
          authorization: `Bearer ${viewer.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({firstName: "Внук Обновлённый"}),
      },
    );
    assert.equal(editOwnRes.status, 200);

    // Viewer list of invitations omits plaintext token
    await ctx.store.createInvitation({
      semyaId: semya.id,
      inviterUserId: owner.user.id,
      recipientUserId: (await registerUser(ctx.baseUrl, "w2-r@test.app", "Rec")).user.id,
      role: "editor",
    });
    const invListRes = await fetch(`${ctx.baseUrl}/v1/semya/${semya.id}/invitations`, {
      headers: {authorization: `Bearer ${viewer.accessToken}`},
    });
    assert.equal(invListRes.status, 200);
    const invListBody = await invListRes.json();
    assert.equal(invListBody.invitations.length, 1);
    assert.equal("token" in invListBody.invitations[0], false);

    // Browse token omits identityId/photos/bio; revoke returns status
    const browseToken = await ctx.store.createBrowseToken({
      semyaId: semya.id,
      createdByUserId: owner.user.id,
    });
    const browseRes = await fetch(`${ctx.baseUrl}/v1/browse/${browseToken.token}`);
    assert.equal(browseRes.status, 200);
    const browseBody = await browseRes.json();
    // owner auto-person + anonPerson + viewerPerson
    assert.equal(browseBody.browse.persons.length, 3);
    for (const p of browseBody.browse.persons) {
      assert.equal("identityId" in p, false);
      assert.equal("photoUrl" in p, false);
    }

    const revokeRes = await fetch(
      `${ctx.baseUrl}/v1/semya/${semya.id}/browse-token/${browseToken.id}`,
      {
        method: "DELETE",
        headers: {authorization: `Bearer ${owner.accessToken}`},
      },
    );
    assert.equal(revokeRes.status, 200);
    const revokeBody = await revokeRes.json();
    assert.equal(revokeBody.token.status, "revoked");
  } finally {
    await stopServer(ctx);
  }
});

test("Wave 2.2: media blocks HTML/SVG uploads, enforces ownership on DELETE, and sets nosniff/CSP", async () => {
  const ctx = await startServer();
  try {
    const u1 = await registerUser(ctx.baseUrl, "m1@test.app", "U1");
    const u2 = await registerUser(ctx.baseUrl, "m2@test.app", "U2");

    const svgRes = await fetch(
      `${ctx.baseUrl}/v1/media/object?bucket=posts&path=${u1.user.id}/evil.svg`,
      {
        method: "PUT",
        headers: {
          authorization: `Bearer ${u1.accessToken}`,
          "content-type": "image/svg+xml",
        },
        body: Buffer.from("<svg onload=alert(1)/>"),
      },
    );
    assert.equal(svgRes.status, 400);

    const htmlRes = await fetch(
      `${ctx.baseUrl}/v1/media/object?bucket=posts&path=${u1.user.id}/page.html`,
      {
        method: "PUT",
        headers: {
          authorization: `Bearer ${u1.accessToken}`,
          "content-type": "text/html",
        },
        body: Buffer.from("<script>alert(1)</script>"),
      },
    );
    assert.equal(htmlRes.status, 400);

    const pngRes = await fetch(
      `${ctx.baseUrl}/v1/media/object?bucket=posts&path=shared-uuid.png`,
      {
        method: "PUT",
        headers: {
          authorization: `Bearer ${u1.accessToken}`,
          "content-type": "image/png",
        },
        body: Buffer.from(
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7Z0uoAAAAASUVORK5CYII=",
          "base64",
        ),
      },
    );
    assert.equal(pngRes.status, 201);
    const uploaded = await pngRes.json();

    const getRes = await fetch(uploaded.url);
    assert.equal(getRes.status, 200);
    assert.equal(getRes.headers.get("x-content-type-options"), "nosniff");
    assert.match(getRes.headers.get("content-security-policy") || "", /default-src 'none'/);

    const deleteByOther = await fetch(`${ctx.baseUrl}/v1/media`, {
      method: "DELETE",
      headers: {
        authorization: `Bearer ${u2.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({url: uploaded.url}),
    });
    assert.equal(deleteByOther.status, 403);

    const deleteByOwner = await fetch(`${ctx.baseUrl}/v1/media`, {
      method: "DELETE",
      headers: {
        authorization: `Bearer ${u1.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({url: uploaded.url}),
    });
    assert.equal(deleteByOwner.status, 204);
  } finally {
    await stopServer(ctx);
  }
});

test("Wave 2.3 & 2.4: story request self-ask, circle IDOR/secondary branch, closed poll, and MAX stashed redirect", async () => {
  const ctx = await startServer({
    maxAuthClient: {
      isEnabled: true,
      buildStartUrl: ({flowCode}) => `https://max.example/start?code=${flowCode}`,
      verifyInitData: (initData) => ({
        startParam: initData,
        user: {id: "max-user-1", first_name: "Max", last_name: "User"},
        authDate: Math.floor(Date.now() / 1000),
      }),
    },
  });
  try {
    const alice = await registerUser(ctx.baseUrl, "s24-alice@test.app", "Alice");
    const bob = await registerUser(ctx.baseUrl, "s24-bob@test.app", "Bob");
    const charlie = await registerUser(ctx.baseUrl, "s24-charlie@test.app", "Charlie");

    const treeA = await ctx.store.createTree({
      creatorId: alice.user.id,
      name: "Branch A",
    });
    const treeB = await ctx.store.createTree({
      creatorId: bob.user.id,
      name: "Branch B",
    });
    await ctx.store.ensureTreeMembership(treeA.id, charlie.user.id);
    await ctx.store.ensureTreeMembership(treeB.id, alice.user.id);

    // Claimed person for Charlie in TreeA; Bob is not even on TreeA, Alice IS.
    const charliePerson = await ctx.store.createPerson({
      treeId: treeA.id,
      creatorId: alice.user.id,
      userId: charlie.user.id,
      personData: {firstName: "Чарли", gender: "male"},
    });
    const alicePerson = await ctx.store.createPerson({
      treeId: treeA.id,
      creatorId: alice.user.id,
      userId: alice.user.id,
      personData: {firstName: "Алиса", gender: "female"},
    });

    // Alice (member of TreeA without grant on Charlie) asks Charlie about Charlie himself -> 201!
    const selfAskRes = await fetch(`${ctx.baseUrl}/v1/story-requests`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${alice.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        treeId: treeA.id,
        personId: charliePerson.id,
        targetUserId: charlie.user.id,
        question: {text: "Расскажи про детство!"},
      }),
    });
    assert.equal(selfAskRes.status, 201);

    // Circle IDOR + secondary branch
    const secretCircle = await ctx.store.createCircle({
      treeId: treeA.id,
      name: "Ближний круг",
      createdBy: alice.user.id,
    });
    await ctx.store.replaceCircleMembers({
      treeId: treeA.id,
      circleId: secretCircle.id,
      identityIds: [],
      personIds: [alicePerson.id],
    });
    const scopedPost = await ctx.store.createPost({
      treeId: treeA.id,
      branchIds: [treeA.id, treeB.id],
      authorId: alice.user.id,
      authorName: "Alice",
      content: "Секрет круга",
      scopeType: "circle",
      circleId: secretCircle.id,
    });

    const charlieComments = await fetch(
      `${ctx.baseUrl}/v1/posts/${scopedPost.id}/comments`,
      {headers: {authorization: `Bearer ${charlie.accessToken}`}},
    );
    assert.equal(charlieComments.status, 403, "Tree member outside circle gets 403");

    const bobComments = await fetch(
      `${ctx.baseUrl}/v1/posts/${scopedPost.id}/comments`,
      {headers: {authorization: `Bearer ${bob.accessToken}`}},
    );
    assert.equal(bobComments.status, 200, "Secondary branch member gets 200");

    // Closed poll rejects voting (409)
    const closedPoll = await ctx.store.createPoll({
      treeId: treeA.id,
      authorId: alice.user.id,
      authorName: "Alice",
      question: "Когда встреча?",
      options: ["Сегодня", "Завтра"],
      closesAt: "2020-01-01T00:00:00.000Z",
    });
    const voteRes = await fetch(`${ctx.baseUrl}/v1/polls/${closedPoll.id}/respond`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${alice.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({optionIds: [closedPoll.options[0].id]}),
    });
    assert.equal(voteRes.status, 409);

    // MAX stashedFinalRedirect preserved
    const startMax = await fetch(
      `${ctx.baseUrl}/v1/auth/max/start?finalRedirect=${encodeURIComponent("rodnya://oauth/callback")}`,
      {redirect: "manual"},
    );
    assert.equal(startMax.status, 302);
    const location = startMax.headers.get("location");
    const flowCode = new URL(location).searchParams.get("code");
    const completeMax = await fetch(`${ctx.baseUrl}/v1/auth/max/complete`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({initData: `rodnya-login-${flowCode}`}),
    });
    assert.equal(completeMax.status, 200);
    const completeBody = await completeMax.json();
    assert.match(completeBody.redirectUrl, /^rodnya:\/\/oauth\/callback/);
  } finally {
    await stopServer(ctx);
  }
});

test("Wave 2.5: blocked call create rejected (403), group reject keeps call alive, busy #3 rejected (409)", async () => {
  const ctx = await startServer({
    liveKitService: {
      isConfigured: true,
      async ensureRoom() {},
      async createSession({roomName, participantIdentity, participantName}) {
        return {
          roomName,
          url: "wss://livekit.test",
          token: `tok-${participantIdentity}`,
          participantIdentity,
          participantName,
        };
      },
    },
  });
  try {
    const a = await registerUser(ctx.baseUrl, "c-a@test.app", "A");
    const b = await registerUser(ctx.baseUrl, "c-b@test.app", "B");
    const c = await registerUser(ctx.baseUrl, "c-c@test.app", "C");
    const d = await registerUser(ctx.baseUrl, "c-d@test.app", "D");

    // Busy call for C with D first
    const chatCD = await ctx.store.ensureDirectChat(c.user.id, d.user.id);
    const callCD = await fetch(`${ctx.baseUrl}/v1/calls`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${c.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({chatId: chatCD.id, mediaMode: "audio"}),
    });
    assert.equal(callCD.status, 201);

    // A starts group call with B & C -> 409 because C is busy!
    const groupABC = await ctx.store.createGroupChat({
      title: "Group",
      participantIds: [b.user.id, c.user.id],
      createdBy: a.user.id,
    });
    const busyGroupRes = await fetch(`${ctx.baseUrl}/v1/calls`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${a.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({chatId: groupABC.id, mediaMode: "audio"}),
    });
    assert.equal(busyGroupRes.status, 409);

    // End CD call, start group ABC, then B rejects -> call stays ringing for C!
    const callCdId = (await callCD.json()).call.id;
    await ctx.store.cancelCall({callId: callCdId, userId: c.user.id});

    const startGroup = await fetch(`${ctx.baseUrl}/v1/calls`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${a.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({chatId: groupABC.id, mediaMode: "audio"}),
    });
    assert.equal(startGroup.status, 201);
    const groupCallId = (await startGroup.json()).call.id;

    const rejectB = await fetch(`${ctx.baseUrl}/v1/calls/${groupCallId}/reject`, {
      method: "POST",
      headers: {authorization: `Bearer ${b.accessToken}`},
    });
    assert.equal(rejectB.status, 200);
    const rejectBody = await rejectB.json();
    assert.equal(rejectBody.call.state, "ringing");
    assert.deepEqual(
      [...rejectBody.call.participantIds].sort(),
      [a.user.id, c.user.id].sort(),
    );

    await ctx.store.cancelCall({callId: groupCallId, userId: a.user.id});

    // Block between A and B blocks direct call create -> 403
    const chatAB = await ctx.store.ensureDirectChat(a.user.id, b.user.id);
    const blockRes = await fetch(`${ctx.baseUrl}/v1/blocks`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${a.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({userId: b.user.id}),
    });
    assert.equal(blockRes.status, 201);
    const blockedCallRes = await fetch(`${ctx.baseUrl}/v1/calls`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${b.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({chatId: chatAB.id, mediaMode: "audio"}),
    });
    assert.equal(blockedCallRes.status, 403);
  } finally {
    await stopServer(ctx);
  }
});
