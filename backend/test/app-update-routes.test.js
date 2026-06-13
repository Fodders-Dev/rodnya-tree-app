// U1: GET /v1/app/latest — публичный эндпоинт версии для OTA-апдейтера
// sideload-сборок. Отдаёт env-конфиг при включённой фиче, 204 при
// выключенной (versionCode/apkUrl не заданы).

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");

const {createApp} = require("../src/app");
const {FileStore} = require("../src/store");
const {RealtimeHub} = require("../src/realtime-hub");
const {PushGateway} = require("../src/push-gateway");

async function startTestServer({latestAndroidUpdate} = {}) {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-appupd-"));
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
      latestAndroidUpdate,
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
    tempDir,
  };
}

async function shutdown({server, tempDir}) {
  await new Promise((resolve) => server.close(resolve));
  await fs.rm(tempDir, {recursive: true, force: true}).catch(() => {});
}

test("включённая фича: отдаёт версию, apkUrl, minVersionCode и notes", async () => {
  const ctx = await startTestServer({
    latestAndroidUpdate: {
      versionCode: 42,
      versionName: "1.0.3",
      apkUrl: "https://s3.ru-msk.example/rodnya/rodnya-1.0.3.apk",
      minVersionCode: 40,
      notes: "Чинят чаты и ленту",
    },
  });
  try {
    const res = await fetch(`${ctx.baseUrl}/v1/app/latest`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.deepEqual(body, {
      versionCode: 42,
      versionName: "1.0.3",
      apkUrl: "https://s3.ru-msk.example/rodnya/rodnya-1.0.3.apk",
      minVersionCode: 40,
      notes: "Чинят чаты и ленту",
      sha256: null,
    });
  } finally {
    await shutdown(ctx);
  }
});

test("U6: sha256 отдаётся когда задан; пусто → null", async () => {
  const ctx = await startTestServer({
    latestAndroidUpdate: {
      versionCode: 42,
      versionName: "1.0.3",
      apkUrl: "https://s3.ru-msk.example/rodnya/rodnya.apk",
      minVersionCode: 0,
      notes: "",
      sha256: "b".repeat(64),
    },
  });
  try {
    const res = await fetch(`${ctx.baseUrl}/v1/app/latest`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.sha256, "b".repeat(64));
  } finally {
    await shutdown(ctx);
  }

  const ctx2 = await startTestServer({
    latestAndroidUpdate: {
      versionCode: 42,
      apkUrl: "https://s3.ru-msk.example/rodnya/rodnya.apk",
      sha256: "",
    },
  });
  try {
    const res = await fetch(`${ctx2.baseUrl}/v1/app/latest`);
    const body = await res.json();
    assert.equal(body.sha256, null);
  } finally {
    await shutdown(ctx2);
  }
});

test("U6: apkUrl без host (схема ок, но URL не парсится/пустой host) → 204", async () => {
  // Голый "https://" проходит проверку схемы в enforceSafeUrl, но не
  // является корректным URL с host — должно дать 204, а не отдать мусор.
  for (const badUrl of ["https://", "https://  "]) {
    const ctx = await startTestServer({
      latestAndroidUpdate: {
        versionCode: 42,
        versionName: "1.0.3",
        apkUrl: badUrl,
        minVersionCode: 0,
        notes: "",
      },
    });
    try {
      const res = await fetch(`${ctx.baseUrl}/v1/app/latest`);
      assert.equal(res.status, 204, `url=${JSON.stringify(badUrl)}`);
    } finally {
      await shutdown(ctx);
    }
  }
});

test("notes/versionName опциональны: отсутствующие приходят как null", async () => {
  const ctx = await startTestServer({
    latestAndroidUpdate: {
      versionCode: 42,
      versionName: "",
      apkUrl: "https://s3.ru-msk.example/rodnya/rodnya.apk",
      minVersionCode: 0,
      notes: "",
    },
  });
  try {
    const res = await fetch(`${ctx.baseUrl}/v1/app/latest`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.versionCode, 42);
    assert.equal(body.versionName, null);
    assert.equal(body.notes, null);
    assert.equal(body.minVersionCode, 0);
  } finally {
    await shutdown(ctx);
  }
});

test("фича выключена (нет versionCode/apkUrl) — 204, пустое тело", async () => {
  const ctx = await startTestServer({
    latestAndroidUpdate: {
      versionCode: 0,
      versionName: "",
      apkUrl: "",
      minVersionCode: 0,
      notes: "",
    },
  });
  try {
    const res = await fetch(`${ctx.baseUrl}/v1/app/latest`);
    assert.equal(res.status, 204);
    const text = await res.text();
    assert.equal(text, "");
  } finally {
    await shutdown(ctx);
  }
});

test("есть versionCode, но нет apkUrl — фича остаётся выключенной (204)", async () => {
  const ctx = await startTestServer({
    latestAndroidUpdate: {
      versionCode: 42,
      versionName: "1.0.3",
      apkUrl: "",
      minVersionCode: 0,
      notes: "",
    },
  });
  try {
    const res = await fetch(`${ctx.baseUrl}/v1/app/latest`);
    assert.equal(res.status, 204);
  } finally {
    await shutdown(ctx);
  }
});

test("конфиг вовсе не задан — 204 (не падает)", async () => {
  const ctx = await startTestServer();
  try {
    const res = await fetch(`${ctx.baseUrl}/v1/app/latest`);
    assert.equal(res.status, 204);
  } finally {
    await shutdown(ctx);
  }
});

test("http apkUrl отвергается (только https) → 204", async () => {
  const ctx = await startTestServer({
    latestAndroidUpdate: {
      versionCode: 42,
      versionName: "1.0.3",
      apkUrl: "http://insecure.example/rodnya.apk",
      minVersionCode: 0,
      notes: "",
    },
  });
  try {
    const res = await fetch(`${ctx.baseUrl}/v1/app/latest`);
    assert.equal(res.status, 204);
  } finally {
    await shutdown(ctx);
  }
});

test("нефинитный minVersionCode (Infinity) не утекает — приходит 0", async () => {
  const ctx = await startTestServer({
    latestAndroidUpdate: {
      versionCode: 42,
      versionName: "1.0.3",
      apkUrl: "https://s3.ru-msk.example/rodnya/rodnya.apk",
      minVersionCode: Infinity,
      notes: "",
    },
  });
  try {
    const res = await fetch(`${ctx.baseUrl}/v1/app/latest`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.minVersionCode, 0);
  } finally {
    await shutdown(ctx);
  }
});

test("эндпоинт публичный — работает без Authorization", async () => {
  const ctx = await startTestServer({
    latestAndroidUpdate: {
      versionCode: 42,
      versionName: "1.0.3",
      apkUrl: "https://s3.ru-msk.example/rodnya/rodnya.apk",
      minVersionCode: 0,
      notes: "",
    },
  });
  try {
    // Никакого Bearer-токена — апдейт нужен и до входа.
    const res = await fetch(`${ctx.baseUrl}/v1/app/latest`);
    assert.equal(res.status, 200);
  } finally {
    await shutdown(ctx);
  }
});
