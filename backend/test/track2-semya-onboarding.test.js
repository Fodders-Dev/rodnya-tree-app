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
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-t2-"));
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

test("seedOnboarding auto-binds Semya and POST /v1/trees?bindSemya=true binds Semya", async () => {
  const ctx = await startTestServer();
  try {
    const owner = await registerUser(ctx, "seed-semya@example.com", "Иван");

    const seedRes = await fetch(`${ctx.baseUrl}/v1/onboarding/seed`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${owner.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        profile: {name: "Иван", gender: "male"},
        relatives: [],
      }),
    });
    assert.equal(seedRes.status, 201);
    const seedJson = await seedRes.json();
    assert.ok(seedJson.treeId);

    const semyiAfterSeed = await fetch(`${ctx.baseUrl}/v1/me/semya`, {
      headers: {authorization: `Bearer ${owner.accessToken}`},
    });
    assert.equal(semyiAfterSeed.status, 200);
    const {semyi} = await semyiAfterSeed.json();
    assert.equal(semyi.length, 1);
    assert.equal(semyi[0].treeId, seedJson.treeId);
    assert.equal(semyi[0].name, "Моя семья");

    const createTreeRes = await fetch(`${ctx.baseUrl}/v1/trees`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${owner.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        name: "Ветка Петрова",
        kind: "family",
        bindSemya: true,
      }),
    });
    assert.equal(createTreeRes.status, 201);
    const {tree} = await createTreeRes.json();
    assert.ok(tree.semyaId);

    const semyiAfterCreate = await fetch(`${ctx.baseUrl}/v1/me/semya`, {
      headers: {authorization: `Bearer ${owner.accessToken}`},
    });
    const list2 = (await semyiAfterCreate.json()).semyi;
    assert.equal(list2.length, 2);
    assert.ok(list2.some((s) => s.id === tree.semyaId && s.name === "Ветка Петрова"));
  } finally {
    await stopTestServer(ctx);
  }
});

test("semya invitation notifications carry token and treeId with Russian copy", async () => {
  const ctx = await startTestServer();
  try {
    const owner = await registerUser(ctx, "inviter-t2@example.com", "Ольга");
    const invitee = await registerUser(ctx, "invitee-t2@example.com", "Дарья");

    await fetch(`${ctx.baseUrl}/v1/onboarding/seed`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${owner.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({profile: {name: "Ольга"}, relatives: []}),
    });
    const {semyi} = await (
      await fetch(`${ctx.baseUrl}/v1/me/semya`, {
        headers: {authorization: `Bearer ${owner.accessToken}`},
      })
    ).json();
    const semya = semyi[0];

    const invRes = await fetch(`${ctx.baseUrl}/v1/semya/${semya.id}/invitation`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${owner.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({recipientEmail: "invitee-t2@example.com", role: "editor"}),
    });
    assert.equal(invRes.status, 201);
    const {invitation} = await invRes.json();

    const recvNotifs = await (
      await fetch(`${ctx.baseUrl}/v1/notifications`, {
        headers: {authorization: `Bearer ${invitee.accessToken}`},
      })
    ).json();
    const recv = recvNotifs.notifications.find((n) => n.type === "semya_invitation_received");
    assert.ok(recv);
    assert.equal(recv.data.token, invitation.token);
    assert.equal(recv.body, "Вас пригласили в семью в Родне — откройте, чтобы принять.");

    const accRes = await fetch(
      `${ctx.baseUrl}/v1/invitation/${invitation.token}/accept`,
      {
        method: "POST",
        headers: {authorization: `Bearer ${invitee.accessToken}`},
      },
    );
    assert.equal(accRes.status, 200);
    const accJson = await accRes.json();
    assert.equal(accJson.treeId, semya.treeId);

    const ownerNotifs = await (
      await fetch(`${ctx.baseUrl}/v1/notifications`, {
        headers: {authorization: `Bearer ${owner.accessToken}`},
      })
    ).json();
    const accNotif = ownerNotifs.notifications.find((n) => n.type === "semya_invitation_accepted");
    assert.ok(accNotif);
    assert.equal(accNotif.data.treeId, semya.treeId);
  } finally {
    await stopTestServer(ctx);
  }
});
