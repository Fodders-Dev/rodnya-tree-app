const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");

const {createApp} = require("../src/app");
const {FileStore} = require("../src/store");
const {RealtimeHub} = require("../src/realtime-hub");
const {PushGateway} = require("../src/push-gateway");
const {
  normalizeStoryAudio,
  transcribeStoryAudio,
} = require("../src/services/story-audio-service");

async function startTestServer(extraConfig = {}) {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-pub-sreq-"));
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
      ...extraConfig,
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

test("public_link story request: create, SSR HTML + OG + headers, media upload, combined answer, notification & cleanup", async () => {
  const ctx = await startTestServer({
    publicStoryBaseUrl: "https://rodnya-tree.ru",
  });
  try {
    const owner = await registerUser(ctx, "artem@example.com", "Артём");
    const tree = await createTree(ctx, owner, "Семья Соколовых");
    const grandma = await createPerson(ctx, owner.accessToken, tree.id, {
      name: "Лидия Петровна",
    });

    const createRes = await fetch(`${ctx.baseUrl}/v1/story-requests`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${owner.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        treeId: tree.id,
        personId: grandma.id,
        deliveryMode: "public_link",
        targetName: "Бабушка Лида",
        question: {text: "Как вы познакомились с дедушкой?"},
      }),
    });
    assert.equal(createRes.status, 201);
    const {request} = await createRes.json();
    assert.equal(request.deliveryMode, "public_link");
    assert.equal(request.targetUserId, null);
    assert.equal(request.targetName, "Бабушка Лида");
    assert.equal(request.shareToken, undefined);
    assert.match(request.shareUrl, /^https:\/\/rodnya-tree\.ru\/story\/[a-f0-9]{48}$/);

    const token = request.shareUrl.split("/story/")[1];

    // Repeated GET /story/:token simulates WhatsApp/Telegram bot + user opening — must not consume token.
    for (let i = 0; i < 2; i++) {
      const pageRes = await fetch(`${ctx.baseUrl}/story/${token}`);
      assert.equal(pageRes.status, 200);
      assert.match(pageRes.headers.get("content-type") || "", /^text\/html/);
      assert.equal(pageRes.headers.get("referrer-policy"), "no-referrer");
      assert.equal(pageRes.headers.get("x-frame-options"), "DENY");
      assert.match(pageRes.headers.get("permissions-policy") || "", /microphone=\(self\)/);
      assert.match(pageRes.headers.get("content-security-policy") || "", /script-src 'nonce-/);
      const html = await pageRes.text();
      assert.match(html, /Артём спрашивает о Лидия Петровна/);
      assert.match(html, /Как вы познакомились с дедушкой\?/);
      assert.match(html, /og:title/);
      assert.match(html, /noindex, nofollow, noarchive/);
    }

    // Reject invalid MIME type BEFORE reading/saving.
    const badMimeRes = await fetch(`${ctx.baseUrl}/story/${token}/media?kind=photo`, {
      method: "PUT",
      headers: {"content-type": "image/svg+xml"},
      body: Buffer.from("<svg/>"),
    });
    assert.equal(badMimeRes.status, 400);

    // Upload audio, superseded audio, and photo.
    const audio1 = await fetch(`${ctx.baseUrl}/story/${token}/media?kind=audio`, {
      method: "PUT",
      headers: {"content-type": "audio/mp4"},
      body: Buffer.from("old-audio-bytes"),
    });
    assert.equal(audio1.status, 201);
    const audio1Body = await audio1.json();

    const audio2 = await fetch(`${ctx.baseUrl}/story/${token}/media?kind=audio`, {
      method: "PUT",
      headers: {"content-type": "audio/mp4"},
      body: Buffer.from("final-audio-bytes"),
    });
    assert.equal(audio2.status, 201);
    const audio2Body = await audio2.json();

    const photoRes = await fetch(`${ctx.baseUrl}/story/${token}/media?kind=photo`, {
      method: "PUT",
      headers: {"content-type": "image/jpeg"},
      body: Buffer.from("jpeg-bytes"),
    });
    assert.equal(photoRes.status, 201);
    const photoBody = await photoRes.json();

    // Reject arbitrary external URL not belonging to guestUploads.
    const badSubmit = await fetch(`${ctx.baseUrl}/story/${token}/answer`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        photo: {mediaUrl: "https://evil.example/payload.jpg"},
      }),
    });
    assert.equal(badSubmit.status, 400);

    // Submit combined audio + text + photo answer.
    const submitRes = await fetch(`${ctx.baseUrl}/story/${token}/answer`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        respondentName: "Тётя Оля",
        audio: {mediaUrl: audio2Body.url, durationSec: 42, transcript: "Было тёплое лето"},
        text: "Познакомились на танцах в доме культуры.",
        photo: {mediaUrl: photoBody.url, caption: "Лето 1974"},
      }),
    });
    assert.equal(submitRes.status, 200);
    const submitJson = await submitRes.json();
    assert.equal(submitJson.ok, true);
    assert.equal(submitJson.blockIds.length, 3);

    // Unused superseded upload audio1 must be deleted; used audio2 must remain.
    const checkUnused = await fetch(audio1Body.url);
    assert.notEqual(checkUnused.status, 200);
    const checkUsed = await fetch(audio2Body.url);
    assert.equal(checkUsed.status, 200);

    // Second submit on already-answered link -> 410.
    const secondSubmit = await fetch(`${ctx.baseUrl}/story/${token}/answer`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({text: "Повтор"}),
    });
    assert.equal(secondSubmit.status, 410);

    // GET after answered returns 200 thank-you HTML (no active form).
    const afterRes = await fetch(`${ctx.baseUrl}/story/${token}`);
    assert.equal(afterRes.status, 200);
    const afterHtml = await afterRes.text();
    assert.match(afterHtml, /Спасибо! История уже в семейной книге/);

    // Article contains all 3 blocks in order with respondentName & channel.
    const articleRes = await fetch(
      `${ctx.baseUrl}/v1/persons/${grandma.id}/article`,
      {headers: {authorization: `Bearer ${owner.accessToken}`}},
    );
    assert.equal(articleRes.status, 200);
    const {article} = await articleRes.json();
    assert.equal(article.blocks.length, 3);
    assert.deepEqual(
      article.blocks.map((b) => b.type),
      ["audio", "paragraph", "photo"],
    );
    assert.equal(article.blocks[0].content.transcript, "Было тёплое лето");
    assert.equal(article.blocks[0].source.respondentName, "Тётя Оля");
    assert.equal(article.blocks[0].source.channel, "public_link");

    // Initiator got story_request_answered notification with respondentName.
    const notifRes = await fetch(`${ctx.baseUrl}/v1/notifications`, {
      headers: {authorization: `Bearer ${owner.accessToken}`},
    });
    assert.equal(notifRes.status, 200);
    const {notifications} = await notifRes.json();
    const answeredNotif = notifications.find((n) => n.type === "story_request_answered");
    assert.ok(answeredNotif);
    assert.equal(answeredNotif.title, "Тётя Оля делится историей");
    assert.equal(answeredNotif.data.respondentName, "Тётя Оля");
    assert.equal(answeredNotif.data.deliveryMode, "public_link");
  } finally {
    await stopTestServer(ctx);
  }
});

test("public_link rate/upload limit, revoke -> 410, unknown token -> 404, 413 oversized", async () => {
  const ctx = await startTestServer({
    publicStoryBaseUrl: "https://rodnya-tree.ru",
  });
  try {
    const owner = await registerUser(ctx, "owner2@example.com", "Мария");
    const tree = await createTree(ctx, owner, "Дерево");
    const hero = await createPerson(ctx, owner.accessToken, tree.id, {name: "Дед Иван"});

    // Unknown token -> 404 HTML
    const missingRes = await fetch(`${ctx.baseUrl}/story/${"a".repeat(48)}`);
    assert.equal(missingRes.status, 404);

    // Create public_link request
    const createRes = await fetch(`${ctx.baseUrl}/v1/story-requests`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${owner.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        treeId: tree.id,
        personId: hero.id,
        deliveryMode: "public_link",
        question: {text: "Где прошло ваше детство?"},
      }),
    });
    assert.equal(createRes.status, 201);
    const {request} = await createRes.json();
    const token = request.shareUrl.split("/story/")[1];

    // Issued list includes shareUrl for requester and omits target
    const issuedRes = await fetch(`${ctx.baseUrl}/v1/me/story-requests?role=issued`, {
      headers: {authorization: `Bearer ${owner.accessToken}`},
    });
    assert.equal(issuedRes.status, 200);
    const {requests} = await issuedRes.json();
    assert.equal(requests.length, 1);
    assert.equal(requests[0].shareUrl, request.shareUrl);
    assert.equal(requests[0].shareToken, undefined);

    // Received list does NOT match null targetUserId
    const recvRes = await fetch(`${ctx.baseUrl}/v1/me/story-requests?role=received`, {
      headers: {authorization: `Bearer ${owner.accessToken}`},
    });
    assert.equal(recvRes.status, 200);
    assert.equal((await recvRes.json()).requests.length, 0);

    // Oversized body (>20 MB) -> 413
    const hugeRes = await fetch(`${ctx.baseUrl}/story/${token}/media?kind=photo`, {
      method: "PUT",
      headers: {
        "content-type": "image/jpeg",
      },
      body: Buffer.alloc(20 * 1024 * 1024 + 16),
    });
    assert.equal(hugeRes.status, 413);

    // 4 uploads succeed, 5th returns 429
    for (let i = 0; i < 4; i++) {
      const up = await fetch(`${ctx.baseUrl}/story/${token}/media?kind=photo`, {
        method: "PUT",
        headers: {"content-type": "image/png"},
        body: Buffer.from(`png-${i}`),
      });
      assert.equal(up.status, 201);
    }
    const fifth = await fetch(`${ctx.baseUrl}/story/${token}/media?kind=photo`, {
      method: "PUT",
      headers: {"content-type": "image/png"},
      body: Buffer.from("png-5"),
    });
    assert.equal(fifth.status, 429);

    // Revoke works cleanly without crashing on null targetUserId -> GET /story/:token returns 410
    const revRes = await fetch(`${ctx.baseUrl}/v1/story-requests/${request.id}/revoke`, {
      method: "POST",
      headers: {authorization: `Bearer ${owner.accessToken}`},
    });
    assert.equal(revRes.status, 200);

    const goneRes = await fetch(`${ctx.baseUrl}/story/${token}`);
    assert.equal(goneRes.status, 410);
  } finally {
    await stopTestServer(ctx);
  }
});

test("latent db.blocks bug fix: blocked pair cannot answer in-app story request", async () => {
  const ctx = await startTestServer();
  try {
    const alice = await registerUser(ctx, "alice-blk@example.com", "Алиса");
    const bob = await registerUser(ctx, "bob-blk@example.com", "Борис");
    const tree = await createTree(ctx, alice, "Дом");
    const invRes = await fetch(`${ctx.baseUrl}/v1/trees/${tree.id}/invitations`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${alice.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({recipientUserId: bob.user.id}),
    });
    assert.equal(invRes.status, 201);
    const {invitation} = await invRes.json();
    const accRes = await fetch(
      `${ctx.baseUrl}/v1/tree-invitations/${invitation.invitationId}/respond`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${bob.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({accept: true}),
      },
    );
    assert.equal(accRes.status, 200);
    const hero = await createPerson(ctx, alice.accessToken, tree.id, {name: "Прадед"});

    const reqRes = await fetch(`${ctx.baseUrl}/v1/story-requests`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${alice.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        treeId: tree.id,
        personId: hero.id,
        targetUserId: bob.user.id,
        question: {text: "Кем работал прадед?"},
      }),
    });
    assert.equal(reqRes.status, 201);
    const {request} = await reqRes.json();

    // Block via real API /v1/blocks
    const blockRes = await fetch(`${ctx.baseUrl}/v1/blocks`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${alice.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({userId: bob.user.id}),
    });
    assert.ok([200, 201].includes(blockRes.status));

    const ansRes = await fetch(`${ctx.baseUrl}/v1/story-requests/${request.id}/answer`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${bob.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({kind: "text", text: "Инженером"}),
    });
    assert.equal(ansRes.status, 403);
  } finally {
    await stopTestServer(ctx);
  }
});

test("story-audio-service: normalizeStoryAudio & transcribeStoryAudio", async () => {
  const m4aBuf = Buffer.from("m4a-data");
  const passthrough = await normalizeStoryAudio({
    buffer: m4aBuf,
    contentType: "audio/mp4",
    originalExt: "m4a",
    ffmpegAvailable: false,
  });
  assert.equal(passthrough.contentType, "audio/mp4");
  assert.equal(passthrough.transcoded, false);

  const webmBuf = Buffer.from("webm-data");
  const noFfmpeg = await normalizeStoryAudio({
    buffer: webmBuf,
    contentType: "audio/webm",
    originalExt: "webm",
    ffmpegAvailable: false,
  });
  assert.equal(noFfmpeg.contentType, "audio/webm");
  assert.equal(noFfmpeg.transcoded, false);

  const disabledStt = await transcribeStoryAudio({
    buffer: m4aBuf,
    config: {sttEnabled: false},
  });
  assert.equal(disabledStt, null);

  const okStt = await transcribeStoryAudio({
    buffer: m4aBuf,
    config: {
      sttEnabled: true,
      sttApiUrl: "https://stt.example/v1/audio/transcriptions",
      sttApiKey: "secret",
      sttModel: "whisper-1",
    },
    fetchImpl: async () => ({
      ok: true,
      text: async () => JSON.stringify({text: "  Бабушка родилась в Вологде  "}),
    }),
  });
  assert.equal(okStt, "Бабушка родилась в Вологде");

  const failStt = await transcribeStoryAudio({
    buffer: m4aBuf,
    config: {
      sttEnabled: true,
      sttApiUrl: "https://stt.example/v1/audio/transcriptions",
      sttApiKey: "secret",
    },
    fetchImpl: async () => ({ok: false, status: 503}),
  });
  assert.equal(failStt, null);
});
