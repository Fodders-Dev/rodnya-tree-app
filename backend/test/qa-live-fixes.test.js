const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");

const {createApp} = require("../src/app");
const {FileStore} = require("../src/store");
const {RealtimeHub} = require("../src/realtime-hub");
const {PushGateway} = require("../src/push-gateway");

async function startServer({useSemyaModel = true} = {}) {
  const prevFlag = process.env.RODNYA_FEDERATED_SEMYI_ENABLED;
  if (useSemyaModel) {
    process.env.RODNYA_FEDERATED_SEMYI_ENABLED = "true";
  } else {
    delete process.env.RODNYA_FEDERATED_SEMYI_ENABLED;
  }

  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-qa-live-"));
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

async function stopServer({server, store, tempDir, prevFlag}) {
  if (prevFlag === undefined) {
    delete process.env.RODNYA_FEDERATED_SEMYI_ENABLED;
  } else {
    process.env.RODNYA_FEDERATED_SEMYI_ENABLED = prevFlag;
  }
  await new Promise((resolve) => server.close(resolve));
  await store.close?.();
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

test("QA 1b: poll response notification uses gender-neutral Russian title", async () => {
  const ctx = await startServer();
  try {
    const author = await registerUser(
      ctx.baseUrl,
      "poll-author@test.app",
      "Артём",
    );
    const responder = await registerUser(
      ctx.baseUrl,
      "poll-responder@test.app",
      "Наталья Геннадьевна Кузнецова",
    );

    const tree = await ctx.store.createTree({
      creatorId: author.user.id,
      name: "Семья Кузнецовых",
      kind: "family",
    });
    const semya = await ctx.store.createSemya({
      ownerId: author.user.id,
      name: "Семья Кузнецовых",
      treeId: tree.id,
    });
    await ctx.store.addMembership({
      semyaId: semya.id,
      userId: responder.user.id,
      role: "editor",
      invitedByUserId: author.user.id,
    });

    const pollRes = await fetch(`${ctx.baseUrl}/v1/polls`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${author.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        treeId: tree.id,
        question: "Когда соберёмся?",
        options: ["Суббота", "Воскресенье"],
      }),
    });
    assert.equal(pollRes.status, 201);
    const poll = await pollRes.json();

    const voteRes = await fetch(`${ctx.baseUrl}/v1/polls/${poll.id}/respond`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${responder.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        optionIds: [poll.options[0].id],
      }),
    });
    assert.equal(voteRes.status, 200);

    const unreadRes = await fetch(`${ctx.baseUrl}/v1/notifications`, {
      headers: {authorization: `Bearer ${author.accessToken}`},
    });
    assert.equal(unreadRes.status, 200);
    const notificationsBody = await unreadRes.json();
    const items = Array.isArray(notificationsBody)
      ? notificationsBody
      : notificationsBody.notifications || notificationsBody.items || [];
    const pollNotif = items.find((item) => item.type === "poll_response");
    assert.ok(pollNotif, "Expected poll_response notification for author");
    assert.equal(
      pollNotif.title,
      "Наталья Геннадьевна Кузнецова: новый ответ в опросе",
    );
    assert.ok(!pollNotif.title.includes(" ответил "));
  } finally {
    await stopServer(ctx);
  }
});

test("QA 2: GET /v1/me/semya resolves legacy 'Моя семья' placeholder to bound tree.name and keeps custom names", async () => {
  const ctx = await startServer();
  try {
    const owner = await registerUser(
      ctx.baseUrl,
      "semya-owner@test.app",
      "Владелец",
    );

    const tree1 = await ctx.store.createTree({
      creatorId: owner.user.id,
      name: "Семья Кузнецовых",
      kind: "family",
    });
    const tree2 = await ctx.store.createTree({
      creatorId: owner.user.id,
      name: "Близкие друзья",
      kind: "friends",
    });
    const tree3 = await ctx.store.createTree({
      creatorId: owner.user.id,
      name: "Родня",
      kind: "family",
    });

    await ctx.store.createSemya({
      ownerId: owner.user.id,
      name: "Моя семья",
      treeId: tree1.id,
    });
    await ctx.store.createSemya({
      ownerId: owner.user.id,
      name: "Моя семья",
      treeId: tree2.id,
    });
    const renamedSemya = await ctx.store.createSemya({
      ownerId: owner.user.id,
      name: "Особая семья",
      treeId: tree3.id,
    });

    const listRes = await fetch(`${ctx.baseUrl}/v1/me/semya`, {
      headers: {authorization: `Bearer ${owner.accessToken}`},
    });
    assert.equal(listRes.status, 200);
    const listBody = await listRes.json();
    const byTreeId = new Map(
      (listBody.semyi || []).map((entry) => [entry.treeId, entry]),
    );
    assert.equal(byTreeId.get(tree1.id)?.name, "Семья Кузнецовых");
    assert.equal(byTreeId.get(tree2.id)?.name, "Близкие друзья");
    assert.equal(byTreeId.get(tree3.id)?.name, "Особая семья");

    const singleRes = await fetch(
      `${ctx.baseUrl}/v1/semya/${byTreeId.get(tree1.id).id}`,
      {headers: {authorization: `Bearer ${owner.accessToken}`}},
    );
    assert.equal(singleRes.status, 200);
    const singleBody = await singleRes.json();
    assert.equal(singleBody.semya?.name, "Семья Кузнецовых");

    const renamedRes = await fetch(
      `${ctx.baseUrl}/v1/semya/${renamedSemya.id}`,
      {headers: {authorization: `Bearer ${owner.accessToken}`}},
    );
    assert.equal(renamedRes.status, 200);
    const renamedBody = await renamedRes.json();
    assert.equal(renamedBody.semya?.name, "Особая семья");
  } finally {
    await stopServer(ctx);
  }
});

test("QA 10e: GET /v1/trees/:treeId/history returns resolved actorName and personName", async () => {
  const ctx = await startServer();
  try {
    const editor = await registerUser(
      ctx.baseUrl,
      "history-editor@test.app",
      "Артём Кузнецов",
    );
    const tree = await ctx.store.createTree({
      creatorId: editor.user.id,
      name: "Семья Кузнецовых",
      kind: "family",
    });

    const createRes = await fetch(
      `${ctx.baseUrl}/v1/trees/${tree.id}/persons`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${editor.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          firstName: "Наталья",
          lastName: "Кузнецова",
          gender: "female",
        }),
      },
    );
    assert.equal(createRes.status, 201);
    const createPayload = await createRes.json();
    const createdPerson = createPayload.person || createPayload;

    const updateRes = await fetch(
      `${ctx.baseUrl}/v1/trees/${tree.id}/persons/${createdPerson.id}`,
      {
        method: "PATCH",
        headers: {
          authorization: `Bearer ${editor.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({notes: "Обновлённая заметка"}),
      },
    );
    assert.equal(updateRes.status, 200);

    const historyRes = await fetch(
      `${ctx.baseUrl}/v1/trees/${tree.id}/history`,
      {headers: {authorization: `Bearer ${editor.accessToken}`}},
    );
    assert.equal(historyRes.status, 200);
    const historyBody = await historyRes.json();
    const updatedRecord = (historyBody.records || []).find(
      (entry) =>
        entry.type === "person.updated" && entry.personId === createdPerson.id,
    );
    assert.ok(updatedRecord, "Expected person.updated record in tree history");
    assert.equal(updatedRecord.actorName, "Артём Кузнецов");
    assert.ok(updatedRecord.personName);
    assert.ok(updatedRecord.personName.includes("Наталья"));
    assert.ok(updatedRecord.personName.includes("Кузнецова"));
  } finally {
    await stopServer(ctx);
  }
});
