// «Спросить историю» MVP-1 tests (STORY-REQUEST-MVP1-BRIEF.md §2.5).
//
// Covers: create (success/dup/limit/self/not-in-tree/invalid-question/
// person-not-found/no-edit-permission), received/issued lists + GET :id
// (with person/requester/target attachments + third-party privacy 404),
// answer (audio/text/photo → article block with `source` + notification;
// target needs NO edit grant to answer), decline, revoke, and lazy expiry
// with its one-shot notification.

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");

const {createApp} = require("../src/app");
const {FileStore} = require("../src/store");
const {RealtimeHub} = require("../src/realtime-hub");
const {PushGateway} = require("../src/push-gateway");

async function startTestServer() {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-sreq-"));
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
    const instance = app.listen(0, "127.0.0.1", () => resolve(instance));
  });
  realtimeHub.attach(server);
  return {
    baseUrl: `http://127.0.0.1:${server.address().port}`,
    server,
    store,
    tempDir,
  };
}

async function stopTestServer(ctx) {
  await new Promise((resolve, reject) => {
    ctx.server.close((error) => (error ? reject(error) : resolve()));
  });
  await fs.rm(ctx.tempDir, {recursive: true, force: true});
}

async function registerUser(ctx, email, displayName) {
  const response = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
    method: "POST",
    headers: {"content-type": "application/json"},
    body: JSON.stringify({
      email,
      password: "secret123",
      consentDocVersion: "test-consent-v1",
      displayName: displayName || email,
    }),
  });
  assert.equal(response.status, 201);
  return response.json();
}

async function createTree(ctx, owner, name = "Тест") {
  const response = await fetch(`${ctx.baseUrl}/v1/trees`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${owner.accessToken}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({name, description: "", isPrivate: true}),
  });
  assert.equal(response.status, 201);
  return (await response.json()).tree;
}

async function createPerson(ctx, token, treeId, body) {
  const response = await fetch(`${ctx.baseUrl}/v1/trees/${treeId}/persons`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
  assert.equal(response.status, 201);
  return (await response.json()).person;
}

// Mirrors owner-model-enforcement.test.js — the real invite→accept HTTP
// flow, so `tree.memberIds` ends up exactly as it would in production
// (rather than poking the blob directly).
async function inviteAndAccept(ctx, owner, recipient, treeId) {
  const inviteResponse = await fetch(
    `${ctx.baseUrl}/v1/trees/${treeId}/invitations`,
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${owner.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({recipientUserId: recipient.user.id}),
    },
  );
  assert.equal(inviteResponse.status, 201);
  const invitation = await inviteResponse.json();
  const acceptResponse = await fetch(
    `${ctx.baseUrl}/v1/tree-invitations/${invitation.invitation.invitationId}/respond`,
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${recipient.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({accept: true}),
    },
  );
  assert.equal(acceptResponse.status, 200);
}

// Claims an anonymous person slot for `user` — the same
// /v1/invitations/pending/process path owner-model-enforcement.test.js
// uses, which sets graphPerson.userId (person becomes "claimed").
async function claimPerson(ctx, user, treeId, personId) {
  const response = await fetch(
    `${ctx.baseUrl}/v1/invitations/pending/process`,
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${user.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({treeId, personId}),
    },
  );
  assert.equal(response.status, 200);
}

function askBody({treeId, personId, targetUserId, text = "Как вы познакомились?", themeKey, sourceQuestionId}) {
  return {
    treeId,
    personId,
    targetUserId,
    question: {text, themeKey, sourceQuestionId},
  };
}

async function ask(ctx, token, body) {
  return fetch(`${ctx.baseUrl}/v1/story-requests`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

async function listRequests(ctx, token, role, status) {
  const qs = new URLSearchParams({role, ...(status ? {status} : {})});
  return fetch(`${ctx.baseUrl}/v1/me/story-requests?${qs}`, {
    headers: {authorization: `Bearer ${token}`},
  });
}

async function getRequest(ctx, token, id) {
  return fetch(`${ctx.baseUrl}/v1/story-requests/${id}`, {
    headers: {authorization: `Bearer ${token}`},
  });
}

async function answer(ctx, token, id, body) {
  return fetch(`${ctx.baseUrl}/v1/story-requests/${id}/answer`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

async function decline(ctx, token, id) {
  return fetch(`${ctx.baseUrl}/v1/story-requests/${id}/decline`, {
    method: "POST",
    headers: {authorization: `Bearer ${token}`},
  });
}

async function revoke(ctx, token, id) {
  return fetch(`${ctx.baseUrl}/v1/story-requests/${id}/revoke`, {
    method: "POST",
    headers: {authorization: `Bearer ${token}`},
  });
}

// Common fixture: alice creates a tree, a "hero" anonymous person, and
// invites bob so bob is a real tree member (target-eligible).
async function seedTreeHeroAndMember(ctx, {aliceEmail, bobEmail}) {
  const alice = await registerUser(ctx, aliceEmail, "Alice");
  const bob = await registerUser(ctx, bobEmail, "Bob");
  const tree = await createTree(ctx, alice);
  await inviteAndAccept(ctx, alice, bob, tree.id);
  const hero = await createPerson(ctx, alice.accessToken, tree.id, {
    firstName: "Бабушка",
    lastName: "Лидия",
    gender: "female",
  });
  return {alice, bob, tree, hero};
}

// ── create ──────────────────────────────────────────────────────────

test("POST /story-requests: no auth → 401", async () => {
  const ctx = await startTestServer();
  try {
    const response = await ask(ctx, "", {});
    assert.equal(response.status, 401);
  } finally {
    await stopTestServer(ctx);
  }
});

test("POST /story-requests: missing fields → 400", async () => {
  const ctx = await startTestServer();
  try {
    const alice = await registerUser(ctx, "missing@test.app");
    const response = await ask(ctx, alice.accessToken, {question: {text: "Вопрос?"}});
    assert.equal(response.status, 400);
  } finally {
    await stopTestServer(ctx);
  }
});

test("POST /story-requests: self-request → 400 SELF_REQUEST_FORBIDDEN", async () => {
  const ctx = await startTestServer();
  try {
    const {alice, tree, hero} = await seedTreeHeroAndMember(ctx, {
      aliceEmail: "self-a@test.app",
      bobEmail: "self-b@test.app",
    });
    const response = await ask(
      ctx,
      alice.accessToken,
      askBody({treeId: tree.id, personId: hero.id, targetUserId: alice.user.id}),
    );
    assert.equal(response.status, 400);
  } finally {
    await stopTestServer(ctx);
  }
});

test("POST /story-requests: question too short/too long → 400 INVALID_QUESTION", async () => {
  const ctx = await startTestServer();
  try {
    const {alice, bob, tree, hero} = await seedTreeHeroAndMember(ctx, {
      aliceEmail: "q-a@test.app",
      bobEmail: "q-b@test.app",
    });
    const tooShort = await ask(
      ctx,
      alice.accessToken,
      askBody({treeId: tree.id, personId: hero.id, targetUserId: bob.user.id, text: "Хм"}),
    );
    assert.equal(tooShort.status, 400);

    const tooLong = await ask(
      ctx,
      alice.accessToken,
      askBody({
        treeId: tree.id,
        personId: hero.id,
        targetUserId: bob.user.id,
        text: "a".repeat(501),
      }),
    );
    assert.equal(tooLong.status, 400);
  } finally {
    await stopTestServer(ctx);
  }
});

test("POST /story-requests: person not found → 404 PERSON_NOT_FOUND", async () => {
  const ctx = await startTestServer();
  try {
    const {alice, bob, tree} = await seedTreeHeroAndMember(ctx, {
      aliceEmail: "pnf-a@test.app",
      bobEmail: "pnf-b@test.app",
    });
    const response = await ask(
      ctx,
      alice.accessToken,
      askBody({treeId: tree.id, personId: "ghost-person", targetUserId: bob.user.id}),
    );
    assert.equal(response.status, 404);
  } finally {
    await stopTestServer(ctx);
  }
});

test("POST /story-requests: requester without edit permission on claimed person → 403", async () => {
  const ctx = await startTestServer();
  try {
    const alice = await registerUser(ctx, "perm-alice@test.app", "Alice");
    const bob = await registerUser(ctx, "perm-bob@test.app", "Bob");
    const stepa = await registerUser(ctx, "perm-stepa@test.app", "Stepa");
    const tree = await createTree(ctx, alice);
    await inviteAndAccept(ctx, alice, bob, tree.id);
    await inviteAndAccept(ctx, alice, stepa, tree.id);

    const stepaPerson = await createPerson(ctx, alice.accessToken, tree.id, {
      firstName: "Стёпа",
      gender: "male",
    });
    await claimPerson(ctx, stepa, tree.id, stepaPerson.id);

    // Bob is a plain tree member with no ownership/grant on Stepa's now-
    // claimed person — asking a story request about Stepa requires the
    // SAME edit right a PATCH would (§1).
    const response = await ask(
      ctx,
      bob.accessToken,
      askBody({treeId: tree.id, personId: stepaPerson.id, targetUserId: alice.user.id}),
    );
    assert.equal(response.status, 403);
  } finally {
    await stopTestServer(ctx);
  }
});

test("POST /story-requests: target not a tree member → 404 TARGET_NOT_IN_TREE", async () => {
  const ctx = await startTestServer();
  try {
    const alice = await registerUser(ctx, "nit-a@test.app", "Alice");
    const stranger = await registerUser(ctx, "nit-stranger@test.app", "Stranger");
    const tree = await createTree(ctx, alice);
    const hero = await createPerson(ctx, alice.accessToken, tree.id, {
      firstName: "Дед",
      gender: "male",
    });
    const response = await ask(
      ctx,
      alice.accessToken,
      askBody({treeId: tree.id, personId: hero.id, targetUserId: stranger.user.id}),
    );
    assert.equal(response.status, 404);
  } finally {
    await stopTestServer(ctx);
  }
});

test("POST /story-requests: success → 201 pending + story_request_received notification", async () => {
  const ctx = await startTestServer();
  try {
    const {alice, bob, tree, hero} = await seedTreeHeroAndMember(ctx, {
      aliceEmail: "ok-a@test.app",
      bobEmail: "ok-b@test.app",
    });
    const response = await ask(
      ctx,
      alice.accessToken,
      askBody({
        treeId: tree.id,
        personId: hero.id,
        targetUserId: bob.user.id,
        text: "Как вы познакомились с дедушкой?",
        sourceQuestionId: "meeting-story",
      }),
    );
    assert.equal(response.status, 201);
    const body = await response.json();
    assert.equal(body.request.status, "pending");
    assert.equal(body.request.requesterUserId, alice.user.id);
    assert.equal(body.request.targetUserId, bob.user.id);
    assert.equal(body.request.personId, hero.id);
    assert.equal(body.request.question.sourceQuestionId, "meeting-story");
    assert.ok(body.request.id.startsWith("sreq_"));
    assert.ok(body.request.expiresAt);
    // person/requester/target attachments are documented ONLY for GET
    // list/:id, not the bare create response (§1).
    assert.equal(body.request.person, undefined);

    const db = await ctx.store._read();
    const notification = db.notifications.find(
      (n) => n.userId === bob.user.id && n.type === "story_request_received",
    );
    assert.ok(notification, "target должен получить story_request_received");
    assert.equal(notification.title, "Alice хочет узнать историю");
    assert.equal(notification.body, "Как вы познакомились с дедушкой?");
    assert.deepEqual(notification.data, {
      requestId: body.request.id,
      treeId: tree.id,
      personId: hero.id,
    });
  } finally {
    await stopTestServer(ctx);
  }
});

test("POST /story-requests: duplicate pending (same triple + same question) → 409, другой вопрос → 201", async () => {
  const ctx = await startTestServer();
  try {
    const {alice, bob, tree, hero} = await seedTreeHeroAndMember(ctx, {
      aliceEmail: "dup-a@test.app",
      bobEmail: "dup-b@test.app",
    });
    const body = askBody({treeId: tree.id, personId: hero.id, targetUserId: bob.user.id});
    const first = await ask(ctx, alice.accessToken, body);
    assert.equal(first.status, 201);
    const second = await ask(ctx, alice.accessToken, body);
    assert.equal(second.status, 409);
    // Другой вопрос той же паре про того же человека — не дубль (правило
    // уточнено 13.09 на живой проверке: два вопроса бабушке за вечер — норма).
    const other = await ask(ctx, alice.accessToken, {
      ...body,
      question: {text: "Какие семейные традиции были в вашей семье?"},
    });
    assert.equal(other.status, 201);
  } finally {
    await stopTestServer(ctx);
  }
});

test("POST /story-requests: >20 open requests by initiator → 429 TOO_MANY_PENDING", async () => {
  const ctx = await startTestServer();
  try {
    const alice = await registerUser(ctx, "cap-a@test.app", "Alice");
    const tree = await createTree(ctx, alice);
    // 21 distinct target members so each create is a distinct triple
    // (duplicate-pending would otherwise mask the rate limit).
    const targets = [];
    for (let i = 0; i < 21; i += 1) {
      const target = await registerUser(ctx, `cap-target-${i}@test.app`, `T${i}`);
      await inviteAndAccept(ctx, alice, target, tree.id);
      targets.push(target);
    }
    const hero = await createPerson(ctx, alice.accessToken, tree.id, {
      firstName: "Прадед",
      gender: "male",
    });

    let lastResponse;
    for (const target of targets) {
      lastResponse = await ask(
        ctx,
        alice.accessToken,
        askBody({treeId: tree.id, personId: hero.id, targetUserId: target.user.id}),
      );
    }
    assert.equal(lastResponse.status, 429);
  } finally {
    await stopTestServer(ctx);
  }
});

// ── lists + get by id ───────────────────────────────────────────────

test("GET /me/story-requests: role required → 400 without role", async () => {
  const ctx = await startTestServer();
  try {
    const alice = await registerUser(ctx, "role-a@test.app");
    const response = await fetch(`${ctx.baseUrl}/v1/me/story-requests`, {
      headers: {authorization: `Bearer ${alice.accessToken}`},
    });
    assert.equal(response.status, 400);
  } finally {
    await stopTestServer(ctx);
  }
});

test("GET /me/story-requests: received/issued separation + attachments", async () => {
  const ctx = await startTestServer();
  try {
    const {alice, bob, tree, hero} = await seedTreeHeroAndMember(ctx, {
      aliceEmail: "list-a@test.app",
      bobEmail: "list-b@test.app",
    });
    await ask(
      ctx,
      alice.accessToken,
      askBody({treeId: tree.id, personId: hero.id, targetUserId: bob.user.id}),
    );

    const issued = await listRequests(ctx, alice.accessToken, "issued");
    const issuedBody = await issued.json();
    assert.equal(issuedBody.requests.length, 1);
    assert.equal(issuedBody.requests[0].requesterUserId, alice.user.id);
    assert.equal(issuedBody.requests[0].person.id, hero.id);
    assert.equal(issuedBody.requests[0].person.name, hero.name);
    assert.equal(issuedBody.requests[0].requester.id, alice.user.id);
    assert.equal(issuedBody.requests[0].target.id, bob.user.id);

    const received = await listRequests(ctx, bob.accessToken, "received");
    const receivedBody = await received.json();
    assert.equal(receivedBody.requests.length, 1);
    assert.equal(receivedBody.requests[0].targetUserId, bob.user.id);

    const aliceReceived = await listRequests(ctx, alice.accessToken, "received");
    const aliceReceivedBody = await aliceReceived.json();
    assert.equal(aliceReceivedBody.requests.length, 0);
  } finally {
    await stopTestServer(ctx);
  }
});

test("GET /story-requests/:id: visible to requester and target, 404 for a third member", async () => {
  const ctx = await startTestServer();
  try {
    const alice = await registerUser(ctx, "third-a@test.app", "Alice");
    const bob = await registerUser(ctx, "third-b@test.app", "Bob");
    const carol = await registerUser(ctx, "third-c@test.app", "Carol");
    const tree = await createTree(ctx, alice);
    await inviteAndAccept(ctx, alice, bob, tree.id);
    await inviteAndAccept(ctx, alice, carol, tree.id);
    const hero = await createPerson(ctx, alice.accessToken, tree.id, {
      firstName: "Бабушка",
      gender: "female",
    });
    const created = await ask(
      ctx,
      alice.accessToken,
      askBody({treeId: tree.id, personId: hero.id, targetUserId: bob.user.id}),
    );
    const {request} = await created.json();

    const asRequester = await getRequest(ctx, alice.accessToken, request.id);
    assert.equal(asRequester.status, 200);
    const asTarget = await getRequest(ctx, bob.accessToken, request.id);
    assert.equal(asTarget.status, 200);
    // Third tree member — same 404 as a truly unknown id, so existence
    // of a request between two OTHER members is never leaked (§2.5).
    const asThirdParty = await getRequest(ctx, carol.accessToken, request.id);
    assert.equal(asThirdParty.status, 404);
    const unknown = await getRequest(ctx, alice.accessToken, "ghost-request");
    assert.equal(unknown.status, 404);
  } finally {
    await stopTestServer(ctx);
  }
});

// ── answer ──────────────────────────────────────────────────────────

test("POST .../answer: audio → article block with source + story_request_answered notification", async () => {
  const ctx = await startTestServer();
  try {
    const {alice, bob, tree, hero} = await seedTreeHeroAndMember(ctx, {
      aliceEmail: "ans-audio-a@test.app",
      bobEmail: "ans-audio-b@test.app",
    });
    const created = await ask(
      ctx,
      alice.accessToken,
      askBody({
        treeId: tree.id,
        personId: hero.id,
        targetUserId: bob.user.id,
        text: "Расскажи о своём детстве",
      }),
    );
    const {request} = await created.json();

    const response = await answer(ctx, bob.accessToken, request.id, {
      kind: "audio",
      mediaUrl: "https://media.example/audio.m4a",
      durationSec: 42,
    });
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.request.status, "answered");
    assert.equal(body.request.answer.kind, "audio");
    assert.equal(body.request.answer.answeredByUserId, bob.user.id);
    assert.equal(body.block.type, "audio");
    assert.equal(body.block.content.url, "https://media.example/audio.m4a");
    assert.equal(body.block.content.durationSec, 42);
    assert.equal(body.block.content.transcript, null, "MVP-1: без расшифровки речи");
    assert.equal(body.block.source.requestId, request.id);
    assert.equal(body.block.source.askedByUserId, alice.user.id);
    assert.equal(body.block.source.question.text, "Расскажи о своём детстве");

    // The block actually landed on the hero's article.
    const articleResponse = await fetch(
      `${ctx.baseUrl}/v1/persons/${hero.id}/article`,
      {headers: {authorization: `Bearer ${alice.accessToken}`}},
    );
    const article = await articleResponse.json();
    assert.equal(article.article.blocks.length, 1);
    assert.equal(article.article.blocks[0].id, body.block.id);
    assert.equal(article.article.blocks[0].source.requestId, request.id);

    const db = await ctx.store._read();
    const notification = db.notifications.find(
      (n) => n.userId === alice.user.id && n.type === "story_request_answered",
    );
    assert.ok(notification);
    assert.equal(notification.title, "Bob делится историей");
    // No gendered "ответил(а)" form anywhere in the copy (§1 decision).
    assert.doesNotMatch(notification.title, /\(а\)/);
    assert.equal(notification.data.articleBlockId, body.block.id);
  } finally {
    await stopTestServer(ctx);
  }
});

test("POST .../answer: text → paragraph block", async () => {
  const ctx = await startTestServer();
  try {
    const {alice, bob, tree, hero} = await seedTreeHeroAndMember(ctx, {
      aliceEmail: "ans-text-a@test.app",
      bobEmail: "ans-text-b@test.app",
    });
    const created = await ask(
      ctx,
      alice.accessToken,
      askBody({treeId: tree.id, personId: hero.id, targetUserId: bob.user.id}),
    );
    const {request} = await created.json();

    const response = await answer(ctx, bob.accessToken, request.id, {
      kind: "text",
      text: "Мы познакомились на танцах в 1968 году.",
    });
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.block.type, "paragraph");
    assert.equal(body.block.content.spans[0].text, "Мы познакомились на танцах в 1968 году.");
    assert.equal(body.request.answer.kind, "text");
  } finally {
    await stopTestServer(ctx);
  }
});

test("POST .../answer: photo → photo block", async () => {
  const ctx = await startTestServer();
  try {
    const {alice, bob, tree, hero} = await seedTreeHeroAndMember(ctx, {
      aliceEmail: "ans-photo-a@test.app",
      bobEmail: "ans-photo-b@test.app",
    });
    const created = await ask(
      ctx,
      alice.accessToken,
      askBody({treeId: tree.id, personId: hero.id, targetUserId: bob.user.id}),
    );
    const {request} = await created.json();

    const response = await answer(ctx, bob.accessToken, request.id, {
      kind: "photo",
      mediaUrl: "https://media.example/photo.jpg",
      caption: "Свадебное фото",
    });
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.block.type, "photo");
    assert.equal(body.block.content.url, "https://media.example/photo.jpg");
    assert.equal(body.block.content.caption, "Свадебное фото");
  } finally {
    await stopTestServer(ctx);
  }
});

test("POST .../answer: target needs NO edit grant on the hero person to answer", async () => {
  const ctx = await startTestServer();
  try {
    const alice = await registerUser(ctx, "noperm-alice@test.app", "Alice");
    const bob = await registerUser(ctx, "noperm-bob@test.app", "Bob");
    const stepa = await registerUser(ctx, "noperm-stepa@test.app", "Stepa");
    const tree = await createTree(ctx, alice);
    await inviteAndAccept(ctx, alice, bob, tree.id);
    await inviteAndAccept(ctx, alice, stepa, tree.id);

    const stepaPerson = await createPerson(ctx, alice.accessToken, tree.id, {
      firstName: "Стёпа",
      gender: "male",
    });
    await claimPerson(ctx, stepa, tree.id, stepaPerson.id);

    // Stepa (owner of his own claimed person → has edit rights) asks Bob
    // to tell a story about him. Bob has NO grant/ownership on Stepa's
    // person — the pending request itself is Bob's one-time permission
    // slip to write this one block (§1, deliberate design).
    const created = await ask(
      ctx,
      stepa.accessToken,
      askBody({treeId: tree.id, personId: stepaPerson.id, targetUserId: bob.user.id}),
    );
    assert.equal(created.status, 201);
    const {request} = await created.json();

    const response = await answer(ctx, bob.accessToken, request.id, {
      kind: "text",
      text: "Стёпа был очень весёлым в детстве.",
    });
    assert.equal(response.status, 200, "адресат без права редактирования персоны всё равно отвечает");
  } finally {
    await stopTestServer(ctx);
  }
});

test("POST .../answer: non-target → 403", async () => {
  const ctx = await startTestServer();
  try {
    const {alice, bob, tree, hero} = await seedTreeHeroAndMember(ctx, {
      aliceEmail: "ans-403-a@test.app",
      bobEmail: "ans-403-b@test.app",
    });
    const created = await ask(
      ctx,
      alice.accessToken,
      askBody({treeId: tree.id, personId: hero.id, targetUserId: bob.user.id}),
    );
    const {request} = await created.json();
    const response = await answer(ctx, alice.accessToken, request.id, {
      kind: "text",
      text: "Пытаюсь ответить сам себе.",
    });
    assert.equal(response.status, 403);
  } finally {
    await stopTestServer(ctx);
  }
});

test("POST .../answer: already answered → 409 NOT_PENDING", async () => {
  const ctx = await startTestServer();
  try {
    const {alice, bob, tree, hero} = await seedTreeHeroAndMember(ctx, {
      aliceEmail: "ans-409-a@test.app",
      bobEmail: "ans-409-b@test.app",
    });
    const created = await ask(
      ctx,
      alice.accessToken,
      askBody({treeId: tree.id, personId: hero.id, targetUserId: bob.user.id}),
    );
    const {request} = await created.json();
    await answer(ctx, bob.accessToken, request.id, {kind: "text", text: "Первый ответ."});
    const second = await answer(ctx, bob.accessToken, request.id, {
      kind: "text",
      text: "Второй ответ.",
    });
    assert.equal(second.status, 409);
  } finally {
    await stopTestServer(ctx);
  }
});

test("POST .../answer: invalid answer (missing mediaUrl) → 400 INVALID_ANSWER", async () => {
  const ctx = await startTestServer();
  try {
    const {alice, bob, tree, hero} = await seedTreeHeroAndMember(ctx, {
      aliceEmail: "ans-400-a@test.app",
      bobEmail: "ans-400-b@test.app",
    });
    const created = await ask(
      ctx,
      alice.accessToken,
      askBody({treeId: tree.id, personId: hero.id, targetUserId: bob.user.id}),
    );
    const {request} = await created.json();
    const response = await answer(ctx, bob.accessToken, request.id, {kind: "audio"});
    assert.equal(response.status, 400);
  } finally {
    await stopTestServer(ctx);
  }
});

// ── decline ─────────────────────────────────────────────────────────

test("POST .../decline: target declines → 200 declined + notification (gender-neutral copy)", async () => {
  const ctx = await startTestServer();
  try {
    const {alice, bob, tree, hero} = await seedTreeHeroAndMember(ctx, {
      aliceEmail: "dec-a@test.app",
      bobEmail: "dec-b@test.app",
    });
    const created = await ask(
      ctx,
      alice.accessToken,
      askBody({treeId: tree.id, personId: hero.id, targetUserId: bob.user.id}),
    );
    const {request} = await created.json();

    const response = await decline(ctx, bob.accessToken, request.id);
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.request.status, "declined");
    assert.ok(body.request.respondedAt);

    const db = await ctx.store._read();
    const notification = db.notifications.find(
      (n) => n.userId === alice.user.id && n.type === "story_request_declined",
    );
    assert.ok(notification);
    assert.doesNotMatch(notification.title, /\(а\)/);
  } finally {
    await stopTestServer(ctx);
  }
});

test("POST .../decline: non-target → 403; already declined → 409", async () => {
  const ctx = await startTestServer();
  try {
    const {alice, bob, tree, hero} = await seedTreeHeroAndMember(ctx, {
      aliceEmail: "dec-403-a@test.app",
      bobEmail: "dec-403-b@test.app",
    });
    const created = await ask(
      ctx,
      alice.accessToken,
      askBody({treeId: tree.id, personId: hero.id, targetUserId: bob.user.id}),
    );
    const {request} = await created.json();

    const wrongActor = await decline(ctx, alice.accessToken, request.id);
    assert.equal(wrongActor.status, 403);

    await decline(ctx, bob.accessToken, request.id);
    const again = await decline(ctx, bob.accessToken, request.id);
    assert.equal(again.status, 409);
  } finally {
    await stopTestServer(ctx);
  }
});

// ── revoke ──────────────────────────────────────────────────────────

test("POST .../revoke: initiator revokes own pending → 200 revoked + target notification", async () => {
  const ctx = await startTestServer();
  try {
    const {alice, bob, tree, hero} = await seedTreeHeroAndMember(ctx, {
      aliceEmail: "rev-a@test.app",
      bobEmail: "rev-b@test.app",
    });
    const created = await ask(
      ctx,
      alice.accessToken,
      askBody({treeId: tree.id, personId: hero.id, targetUserId: bob.user.id}),
    );
    const {request} = await created.json();

    const response = await revoke(ctx, alice.accessToken, request.id);
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.request.status, "revoked");

    const db = await ctx.store._read();
    const notification = db.notifications.find(
      (n) => n.userId === bob.user.id && n.type === "story_request_revoked",
    );
    assert.ok(notification);
    assert.deepEqual(notification.data, {requestId: request.id});
  } finally {
    await stopTestServer(ctx);
  }
});

test("POST .../revoke: non-initiator → 403; already answered → 409", async () => {
  const ctx = await startTestServer();
  try {
    const {alice, bob, tree, hero} = await seedTreeHeroAndMember(ctx, {
      aliceEmail: "rev-403-a@test.app",
      bobEmail: "rev-403-b@test.app",
    });
    const created = await ask(
      ctx,
      alice.accessToken,
      askBody({treeId: tree.id, personId: hero.id, targetUserId: bob.user.id}),
    );
    const {request} = await created.json();

    const wrongActor = await revoke(ctx, bob.accessToken, request.id);
    assert.equal(wrongActor.status, 403);

    await answer(ctx, bob.accessToken, request.id, {kind: "text", text: "Ответ подоспел раньше."});
    const tooLate = await revoke(ctx, alice.accessToken, request.id);
    assert.equal(tooLate.status, 409);
  } finally {
    await stopTestServer(ctx);
  }
});

// ── lazy expiry ─────────────────────────────────────────────────────

test("expiry sweep: pending request past 30d → status=expired on-read + one-shot notification", async () => {
  const ctx = await startTestServer();
  try {
    const {alice, bob, tree, hero} = await seedTreeHeroAndMember(ctx, {
      aliceEmail: "exp-a@test.app",
      bobEmail: "exp-b@test.app",
    });
    const created = await ask(
      ctx,
      alice.accessToken,
      askBody({treeId: tree.id, personId: hero.id, targetUserId: bob.user.id}),
    );
    const {request} = await created.json();

    const db = await ctx.store._read();
    const idx = db.storyRequests.findIndex((r) => r.id === request.id);
    db.storyRequests[idx].expiresAt = new Date(Date.now() - 86_400_000).toISOString();
    await ctx.store._write(db);

    const issued = await listRequests(ctx, alice.accessToken, "issued");
    const issuedBody = await issued.json();
    assert.equal(issuedBody.requests[0].status, "expired");

    const dbAfter = await ctx.store._read();
    const expiredNotifications = dbAfter.notifications.filter(
      (n) => n.userId === alice.user.id && n.type === "story_request_expired",
    );
    assert.equal(expiredNotifications.length, 1);

    // Second read (e.g. GET :id) must NOT double-dispatch — the
    // one-shot claim (expiredNotifiedAt) already persisted.
    await getRequest(ctx, alice.accessToken, request.id);
    const dbAfterSecond = await ctx.store._read();
    const stillOne = dbAfterSecond.notifications.filter(
      (n) => n.userId === alice.user.id && n.type === "story_request_expired",
    );
    assert.equal(stillOne.length, 1, "no double notification on a second sweep-triggering read");
  } finally {
    await stopTestServer(ctx);
  }
});
