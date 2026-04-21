const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs/promises");
const path = require("node:path");
const os = require("node:os");

const {createApp} = require("../src/app");
const {FileStore, buildTreeGraphSnapshot, buildGraphWarnings} = require("../src/store");
const {RealtimeHub} = require("../src/realtime-hub");
const {PushGateway} = require("../src/push-gateway");

async function startTestServer() {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-backend-"));
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
    wsBaseUrl: `ws://127.0.0.1:${server.address().port}`,
    server,
    store,
    tempDir,
  };
}

async function startConfiguredTestServer({
  configOverrides = {},
  pushGateway = null,
  pushGatewayFactory = null,
  googleTokenVerifier = null,
  vkAuthClient = null,
  liveKitService = null,
  runtimeInfo = null,
} = {}) {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-backend-"));
  const dataPath = path.join(tempDir, "dev-db.json");
  const store = new FileStore(dataPath);
  await store.initialize();

  const realtimeHub = new RealtimeHub({store});
  const resolvedConfig = {
    corsOrigin: "*",
    dataPath,
    mediaRootPath: path.join(tempDir, "uploads"),
    publicAppUrl: "https://rodnya-tree.ru",
    webPushPublicKey: "",
    webPushPrivateKey: "",
    webPushSubject: "https://rodnya-tree.ru",
    webPushEnabled: false,
    ...configOverrides,
  };
  const resolvedPushGateway =
    pushGateway ??
    (pushGatewayFactory
      ? pushGatewayFactory({store, config: resolvedConfig})
      : new PushGateway({store, config: resolvedConfig}));
  const app = createApp({
    store,
    config: resolvedConfig,
    realtimeHub,
    pushGateway: resolvedPushGateway,
    googleTokenVerifier,
    vkAuthClient,
    liveKitService,
    runtimeInfo,
  });

  const server = await new Promise((resolve) => {
    const instance = app.listen(0, "127.0.0.1", () => resolve(instance));
  });
  realtimeHub.attach(server);

  return {
    baseUrl: `http://127.0.0.1:${server.address().port}`,
    wsBaseUrl: `ws://127.0.0.1:${server.address().port}`,
    server,
    store,
    tempDir,
  };
}

async function stopTestServer(ctx) {
  await new Promise((resolve, reject) => {
    ctx.server.close((error) => (error ? reject(error) : resolve()));
  });
  if (typeof ctx.store?.close === "function") {
    await ctx.store.close();
  }
  await fs.rm(ctx.tempDir, {recursive: true, force: true});
}

function extractHashQueryParameters(redirectUrl) {
  const parsedUrl = new URL(redirectUrl);
  const hashValue = String(parsedUrl.hash || "");
  const queryPart = hashValue.includes("?") ? hashValue.split("?").slice(1).join("?") : "";
  return new URLSearchParams(queryPart);
}

function buildMaxInitData({
  botToken,
  startParam,
  queryId = crypto.randomUUID(),
  authDate = Math.floor(Date.now() / 1000),
  user,
}) {
  const payload = {
    auth_date: String(authDate),
    query_id: String(queryId),
    start_param: String(startParam || ""),
    user: JSON.stringify(user || {}),
  };
  const launchParams = Object.entries(payload)
    .sort(([leftKey], [rightKey]) => leftKey.localeCompare(rightKey))
    .map(([key, value]) => `${key}=${value}`)
    .join("\n");
  const secretKey = crypto
    .createHmac("sha256", "WebAppData")
    .update(String(botToken || ""), "utf8")
    .digest();
  const hash = crypto
    .createHmac("sha256", secretKey)
    .update(launchParams, "utf8")
    .digest("hex");

  return Object.entries({
    ...payload,
    hash,
  })
    .map(
      ([key, value]) =>
        `${encodeURIComponent(key)}=${encodeURIComponent(String(value))}`,
    )
    .join("&");
}

test("auth + profile bootstrap flow works end-to-end", async () => {
  const ctx = await startTestServer();

  try {
    const registerResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "dev@rodnya.app",
        password: "secret123",
        displayName: "Dev User",
      }),
    });
    assert.equal(registerResponse.status, 201);
    const registered = await registerResponse.json();
    assert.equal(registered.user.email, "dev@rodnya.app");
    assert.equal(registered.profileStatus.isComplete, false);

    const token = registered.accessToken;
    assert.ok(token);

    const sessionResponse = await fetch(`${ctx.baseUrl}/v1/auth/session`, {
      headers: {authorization: `Bearer ${token}`},
    });
    assert.equal(sessionResponse.status, 200);
    const session = await sessionResponse.json();
    assert.equal(session.user.id, registered.user.id);

    const bootstrapResponse = await fetch(
      `${ctx.baseUrl}/v1/profile/me/bootstrap`,
      {
        method: "PUT",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          firstName: "Иван",
          lastName: "Иванов",
          middleName: "Иванович",
          username: "ivanov",
          phoneNumber: "+79990001122",
          countryCode: "+7",
          countryName: "Россия",
          city: "Москва",
          gender: "male",
        }),
      },
    );
    assert.equal(bootstrapResponse.status, 200);
    const bootstrap = await bootstrapResponse.json();
    assert.equal(bootstrap.profile.firstName, "Иван");
    assert.equal(bootstrap.profileStatus.isComplete, true);
    assert.equal(bootstrap.profile.displayName, "Иван Иванович Иванов");

    const refreshedSessionResponse = await fetch(`${ctx.baseUrl}/v1/auth/session`, {
      headers: {authorization: `Bearer ${token}`},
    });
    assert.equal(refreshedSessionResponse.status, 200);
    const refreshedSession = await refreshedSessionResponse.json();
    assert.equal(refreshedSession.user.displayName, "Иван Иванович Иванов");

    const searchResponse = await fetch(
      `${ctx.baseUrl}/v1/users/search?query=ivanov`,
      {
        headers: {authorization: `Bearer ${token}`},
      },
    );
    assert.equal(searchResponse.status, 200);
    const search = await searchResponse.json();
    assert.equal(search.users.length, 1);
    assert.equal(search.users[0].username, "ivanov");
    assert.equal("email" in search.users[0], false);
    assert.equal("phoneNumber" in search.users[0], false);
  } finally {
    await stopTestServer(ctx);
  }
});

test("auth routes stay available even when session touch fails in the background", async () => {
  const ctx = await startConfiguredTestServer();

  try {
    const registerResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "touch-failure@rodnya.app",
        password: "secret123",
        displayName: "Touch Failure",
      }),
    });
    assert.equal(registerResponse.status, 201);
    const registered = await registerResponse.json();

    let touchCalls = 0;
    ctx.store.touchSession = async () => {
      touchCalls += 1;
      throw new Error("touch_failed");
    };

    const sessionResponse = await fetch(`${ctx.baseUrl}/v1/auth/session`, {
      headers: {authorization: `Bearer ${registered.accessToken}`},
    });
    assert.equal(sessionResponse.status, 200);
    const sessionPayload = await sessionResponse.json();
    assert.equal(sessionPayload.user.email, "touch-failure@rodnya.app");

    await new Promise((resolve) => setTimeout(resolve, 25));
    assert.equal(touchCalls, 1);
  } finally {
    await stopTestServer(ctx);
  }
});

test("direct call lifecycle works with backend signaling and webhook updates", async () => {
  const fakeLiveKitService = {
    isConfigured: true,
    async ensureRoom() {},
    async createSession({
      roomName,
      participantIdentity,
      participantName,
    }) {
      return {
        roomName,
        url: "wss://livekit.test",
        token: `token-${participantIdentity}`,
        participantIdentity,
        participantName,
        createdAt: new Date().toISOString(),
      };
    },
    async receiveWebhook(body) {
      return JSON.parse(body);
    },
  };
  const ctx = await startConfiguredTestServer({
    liveKitService: fakeLiveKitService,
  });

  async function registerUser(email, displayName) {
    const response = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email,
        password: "secret123",
        displayName,
      }),
    });
    assert.equal(response.status, 201);
    return response.json();
  }

  try {
    const caller = await registerUser("caller@rodnya.app", "Арина");
    const callee = await registerUser("callee@rodnya.app", "Егор");

    const createChatResponse = await fetch(`${ctx.baseUrl}/v1/chats/direct`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${caller.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        otherUserId: callee.user.id,
      }),
    });
    assert.equal(createChatResponse.status, 200);
    const createdChat = await createChatResponse.json();
    const chatId = createdChat.chat.id;

    const startCallResponse = await fetch(`${ctx.baseUrl}/v1/calls`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${caller.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        chatId,
        mediaMode: "video",
      }),
    });
    assert.equal(startCallResponse.status, 201);
    const startedCall = await startCallResponse.json();
    assert.equal(startedCall.call.state, "ringing");
    assert.equal(startedCall.call.mediaMode, "video");

    const activeRingingResponse = await fetch(
      `${ctx.baseUrl}/v1/calls/active?chatId=${encodeURIComponent(chatId)}`,
      {
        headers: {
          authorization: `Bearer ${caller.accessToken}`,
        },
      },
    );
    assert.equal(activeRingingResponse.status, 200);
    const activeRingingPayload = await activeRingingResponse.json();
    assert.equal(activeRingingPayload.call.id, startedCall.call.id);
    assert.equal(activeRingingPayload.call.state, "ringing");

    const acceptCallResponse = await fetch(
      `${ctx.baseUrl}/v1/calls/${startedCall.call.id}/accept`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${callee.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({}),
      },
    );
    assert.equal(acceptCallResponse.status, 200);
    const acceptedCall = await acceptCallResponse.json();
    assert.equal(acceptedCall.call.state, "active");
    assert.equal(acceptedCall.call.session.roomName, `call_${startedCall.call.id}`);
    assert.equal(acceptedCall.call.session.url, "wss://livekit.test");

    const getAcceptedCallResponse = await fetch(
      `${ctx.baseUrl}/v1/calls/${startedCall.call.id}`,
      {
        headers: {
          authorization: `Bearer ${callee.accessToken}`,
        },
      },
    );
    assert.equal(getAcceptedCallResponse.status, 200);
    const fetchedAcceptedCall = await getAcceptedCallResponse.json();
    assert.equal(fetchedAcceptedCall.call.id, startedCall.call.id);
    assert.equal(fetchedAcceptedCall.call.state, "active");
    assert.equal(fetchedAcceptedCall.call.session.participantIdentity, callee.user.id);

    const webhookResponse = await fetch(`${ctx.baseUrl}/v1/livekit/webhook`, {
      method: "POST",
      headers: {
        "content-type": "application/webhook+json",
      },
      body: JSON.stringify({
        event: "participant_left",
        room: {
          name: `call_${startedCall.call.id}`,
        },
        participant: {
          identity: callee.user.id,
        },
      }),
    });
    assert.equal(webhookResponse.status, 200);

    const endedCall = await ctx.store.findCall(startedCall.call.id);
    assert.equal(endedCall.state, "ended");
    assert.equal(endedCall.endedReason, callee.user.id);
  } finally {
    await stopTestServer(ctx);
  }
});

test("ringing calls automatically expire to missed after timeout", async () => {
  const fakeLiveKitService = {
    isConfigured: true,
    async ensureRoom() {},
    async createSession({
      roomName,
      participantIdentity,
      participantName,
    }) {
      return {
        roomName,
        url: "wss://livekit.test",
        token: `token-${participantIdentity}`,
        participantIdentity,
        participantName,
        createdAt: new Date().toISOString(),
      };
    },
    async receiveWebhook(body) {
      return JSON.parse(body);
    },
  };
  const ctx = await startConfiguredTestServer({
    configOverrides: {
      callInviteTimeoutMs: 75,
    },
    liveKitService: fakeLiveKitService,
  });

  async function registerUser(email, displayName) {
    const response = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email,
        password: "secret123",
        displayName,
      }),
    });
    assert.equal(response.status, 201);
    return response.json();
  }

  try {
    const caller = await registerUser("caller-timeout@rodnya.app", "Зоя");
    const callee = await registerUser("callee-timeout@rodnya.app", "Никита");

    const createChatResponse = await fetch(`${ctx.baseUrl}/v1/chats/direct`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${caller.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        otherUserId: callee.user.id,
      }),
    });
    assert.equal(createChatResponse.status, 200);
    const createdChat = await createChatResponse.json();
    const chatId = createdChat.chat.id;

    const startCallResponse = await fetch(`${ctx.baseUrl}/v1/calls`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${caller.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        chatId,
        mediaMode: "audio",
      }),
    });
    assert.equal(startCallResponse.status, 201);
    const startedCall = await startCallResponse.json();
    assert.equal(startedCall.call.state, "ringing");

    await new Promise((resolve) => setTimeout(resolve, 380));

    const expiredCall = await ctx.store.findCall(startedCall.call.id);
    assert.equal(expiredCall.state, "missed");
    assert.equal(expiredCall.endedReason, "missed");

    const activeCallResponse = await fetch(
      `${ctx.baseUrl}/v1/calls/active?chatId=${encodeURIComponent(chatId)}`,
      {
        headers: {
          authorization: `Bearer ${caller.accessToken}`,
        },
      },
    );
    assert.equal(activeCallResponse.status, 200);
    const activeCallPayload = await activeCallResponse.json();
    assert.equal(activeCallPayload.call, null);
  } finally {
    await stopTestServer(ctx);
  }
});

test("stale ringing call lazily expires consistently for both participants", async () => {
  const fakeLiveKitService = {
    isConfigured: true,
    async ensureRoom() {},
    async createSession({
      roomName,
      participantIdentity,
      participantName,
    }) {
      return {
        roomName,
        url: "wss://livekit.test",
        token: `token-${participantIdentity}`,
        participantIdentity,
        participantName,
        createdAt: new Date().toISOString(),
      };
    },
    async receiveWebhook(body) {
      return JSON.parse(body);
    },
  };
  const ctx = await startConfiguredTestServer({
    configOverrides: {
      callInviteTimeoutMs: 60_000,
    },
    liveKitService: fakeLiveKitService,
  });

  async function registerUser(email, displayName) {
    const response = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email,
        password: "secret123",
        displayName,
      }),
    });
    assert.equal(response.status, 201);
    return response.json();
  }

  try {
    const caller = await registerUser("caller-lazy-timeout@rodnya.app", "Лена");
    const callee = await registerUser("callee-lazy-timeout@rodnya.app", "Павел");

    const createChatResponse = await fetch(`${ctx.baseUrl}/v1/chats/direct`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${caller.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        otherUserId: callee.user.id,
      }),
    });
    assert.equal(createChatResponse.status, 200);
    const createdChat = await createChatResponse.json();
    const chatId = createdChat.chat.id;

    const startCallResponse = await fetch(`${ctx.baseUrl}/v1/calls`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${caller.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        chatId,
        mediaMode: "audio",
      }),
    });
    assert.equal(startCallResponse.status, 201);
    const startedCall = await startCallResponse.json();

    const db = await ctx.store._read();
    const storedCall = db.calls.find((entry) => entry.id === startedCall.call.id);
    storedCall.createdAt = new Date(Date.now() - 120_000).toISOString();
    storedCall.updatedAt = storedCall.createdAt;
    await ctx.store._write(db);

    const callerCallResponse = await fetch(
      `${ctx.baseUrl}/v1/calls/${startedCall.call.id}`,
      {
        headers: {
          authorization: `Bearer ${caller.accessToken}`,
        },
      },
    );
    assert.equal(callerCallResponse.status, 200);
    const callerCallPayload = await callerCallResponse.json();
    assert.equal(callerCallPayload.call.state, "missed");

    const calleeCallResponse = await fetch(
      `${ctx.baseUrl}/v1/calls/${startedCall.call.id}`,
      {
        headers: {
          authorization: `Bearer ${callee.accessToken}`,
        },
      },
    );
    assert.equal(calleeCallResponse.status, 200);
    const calleeCallPayload = await calleeCallResponse.json();
    assert.equal(calleeCallPayload.call.state, "missed");

    const activeCallResponse = await fetch(
      `${ctx.baseUrl}/v1/calls/active?chatId=${encodeURIComponent(chatId)}`,
      {
        headers: {
          authorization: `Bearer ${callee.accessToken}`,
        },
      },
    );
    assert.equal(activeCallResponse.status, 200);
    const activeCallPayload = await activeCallResponse.json();
    assert.equal(activeCallPayload.call, null);
  } finally {
    await stopTestServer(ctx);
  }
});

test("new call creation ignores stale ringing busy state after lazy reconciliation", async () => {
  const fakeLiveKitService = {
    isConfigured: true,
    async ensureRoom() {},
    async createSession({
      roomName,
      participantIdentity,
      participantName,
    }) {
      return {
        roomName,
        url: "wss://livekit.test",
        token: `token-${participantIdentity}`,
        participantIdentity,
        participantName,
        createdAt: new Date().toISOString(),
      };
    },
    async receiveWebhook(body) {
      return JSON.parse(body);
    },
  };
  const ctx = await startConfiguredTestServer({
    configOverrides: {
      callInviteTimeoutMs: 60_000,
    },
    liveKitService: fakeLiveKitService,
  });

  async function registerUser(email, displayName) {
    const response = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email,
        password: "secret123",
        displayName,
      }),
    });
    assert.equal(response.status, 201);
    return response.json();
  }

  try {
    const caller = await registerUser("caller-reconcile@rodnya.app", "Ира");
    const callee = await registerUser("callee-reconcile@rodnya.app", "Матвей");

    const createChatResponse = await fetch(`${ctx.baseUrl}/v1/chats/direct`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${caller.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        otherUserId: callee.user.id,
      }),
    });
    assert.equal(createChatResponse.status, 200);
    const createdChat = await createChatResponse.json();
    const chatId = createdChat.chat.id;

    const firstCallResponse = await fetch(`${ctx.baseUrl}/v1/calls`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${caller.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        chatId,
        mediaMode: "audio",
      }),
    });
    assert.equal(firstCallResponse.status, 201);
    const firstCallPayload = await firstCallResponse.json();

    const db = await ctx.store._read();
    const storedCall = db.calls.find(
      (entry) => entry.id === firstCallPayload.call.id,
    );
    storedCall.createdAt = new Date(Date.now() - 120_000).toISOString();
    storedCall.updatedAt = storedCall.createdAt;
    await ctx.store._write(db);

    const secondCallResponse = await fetch(`${ctx.baseUrl}/v1/calls`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${caller.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        chatId,
        mediaMode: "video",
      }),
    });
    assert.equal(secondCallResponse.status, 201);
    const secondCallPayload = await secondCallResponse.json();
    assert.notEqual(secondCallPayload.call.id, firstCallPayload.call.id);
    assert.equal(secondCallPayload.call.state, "ringing");
    assert.equal(secondCallPayload.call.mediaMode, "video");
  } finally {
    await stopTestServer(ctx);
  }
});

test("person dossier merges profile data, preserves family summary, and handles suggestions", async () => {
  const ctx = await startTestServer();

  async function registerUser(email, displayName) {
    const response = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email,
        password: "secret123",
        displayName,
      }),
    });
    assert.equal(response.status, 201);
    return response.json();
  }

  try {
    const owner = await registerUser("dossier-owner@rodnya.app", "Анна Иванова");
    const ownerHeaders = {
      authorization: `Bearer ${owner.accessToken}`,
      "content-type": "application/json",
    };

    const bootstrapResponse = await fetch(
      `${ctx.baseUrl}/v1/profile/me/bootstrap`,
      {
        method: "PUT",
        headers: ownerHeaders,
        body: JSON.stringify({
          firstName: "Анна",
          lastName: "Иванова",
          middleName: "Петровна",
          username: "anna",
          birthPlace: "Тула",
          countryName: "Россия",
          city: "Москва",
          bio: "Собирает хронику семьи.",
          work: "Архивист",
          profileContributionPolicy: "suggestions",
        }),
      },
    );
    assert.equal(bootstrapResponse.status, 200);

    const treeResponse = await fetch(`${ctx.baseUrl}/v1/trees`, {
      method: "POST",
      headers: ownerHeaders,
      body: JSON.stringify({
        name: "Семья Ивановых",
        description: "",
        isPrivate: true,
      }),
    });
    assert.equal(treeResponse.status, 201);
    const tree = await treeResponse.json();

    const personResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${tree.tree.id}/persons`,
      {
        method: "POST",
        headers: ownerHeaders,
        body: JSON.stringify({
          userId: owner.user.id,
          familySummary: "Любит собирать семейные документы.",
        }),
      },
    );
    assert.equal(personResponse.status, 201);
    const person = await personResponse.json();

    const patchLinkedResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${tree.tree.id}/persons/${person.person.id}`,
      {
        method: "PATCH",
        headers: ownerHeaders,
        body: JSON.stringify({
          firstName: "Зоя",
          familySummary: "Хранит письма и фотографии семьи.",
        }),
      },
    );
    assert.equal(patchLinkedResponse.status, 200);
    const patchedPersonPayload = await patchLinkedResponse.json();
    assert.equal(
      patchedPersonPayload.person.name,
      "Иванова Анна Петровна",
    );
    assert.equal(
      patchedPersonPayload.person.familySummary,
      "Хранит письма и фотографии семьи.",
    );

    const dossierResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${tree.tree.id}/persons/${person.person.id}/dossier`,
      {
        headers: {
          authorization: `Bearer ${owner.accessToken}`,
        },
      },
    );
    assert.equal(dossierResponse.status, 200);
    const dossierPayload = await dossierResponse.json();
    assert.equal(dossierPayload.dossier.mode, "self");
    assert.equal(dossierPayload.dossier.person.familySummary, "Хранит письма и фотографии семьи.");
    assert.equal(dossierPayload.dossier.linkedProfile.birthPlace, "Тула");
    assert.equal(dossierPayload.dossier.linkedProfile.bio, "Собирает хронику семьи.");

    const createContributionResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${tree.tree.id}/persons/${person.person.id}/profile-contributions`,
      {
        method: "POST",
        headers: ownerHeaders,
        body: JSON.stringify({
          message: "Добавил более точное описание работы.",
          fields: {
            work: "Семейный архивист",
            bio: "Собирает хронику семьи и ведёт архив.",
          },
        }),
      },
    );
    assert.equal(createContributionResponse.status, 201);
    const contributionPayload = await createContributionResponse.json();
    assert.equal(contributionPayload.contribution.fields.work, "Семейный архивист");

    const queueResponse = await fetch(`${ctx.baseUrl}/v1/profile/me/contributions`, {
      headers: {
        authorization: `Bearer ${owner.accessToken}`,
      },
    });
    assert.equal(queueResponse.status, 200);
    const queuePayload = await queueResponse.json();
    assert.equal(queuePayload.contributions.length, 1);

    const acceptResponse = await fetch(
      `${ctx.baseUrl}/v1/profile/me/contributions/${contributionPayload.contribution.id}/accept`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${owner.accessToken}`,
        },
      },
    );
    assert.equal(acceptResponse.status, 200);
    const acceptedPayload = await acceptResponse.json();
    assert.equal(acceptedPayload.profile.work, "Семейный архивист");
    assert.equal(
      acceptedPayload.profile.bio,
      "Собирает хронику семьи и ведёт архив.",
    );

    const disableSuggestionsResponse = await fetch(
      `${ctx.baseUrl}/v1/profile/me`,
      {
        method: "PATCH",
        headers: ownerHeaders,
        body: JSON.stringify({
          profileContributionPolicy: "disabled",
        }),
      },
    );
    assert.equal(disableSuggestionsResponse.status, 200);

    const blockedContributionResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${tree.tree.id}/persons/${person.person.id}/profile-contributions`,
      {
        method: "POST",
        headers: ownerHeaders,
        body: JSON.stringify({
          fields: {
            bio: "Это предложение не должно пройти.",
          },
        }),
      },
    );
    assert.equal(blockedContributionResponse.status, 403);
  } finally {
    await stopTestServer(ctx);
  }
});

test("legacy first-party http media urls are normalized to https in API responses", async () => {
  const ctx = await startTestServer();

  async function registerUser(email, displayName) {
    const response = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email,
        password: "secret123",
        displayName,
      }),
    });
    assert.equal(response.status, 201);
    return response.json();
  }

  try {
    const alice = await registerUser("legacy-alice@rodnya.app", "Legacy Alice");
    const bob = await registerUser("legacy-bob@rodnya.app", "Legacy Bob");

    const legacyAlicePhoto =
      "http://api.rodnya-tree.ru/media/avatars/alice/avatar.png";
    const legacyBobPhoto =
      "http://api.rodnya-tree.ru/media/avatars/bob/avatar.png";
    const legacyPostImage =
      "http://api.rodnya-tree.ru/media/posts/post-image.png";
    const legacyStoryMedia =
      "http://api.rodnya-tree.ru/media/stories/story-image.png";
    const legacyStoryThumb =
      "http://api.rodnya-tree.ru/media/stories/story-thumb.png";
    const legacyChatImage =
      "http://api.rodnya-tree.ru/media/chat/chat-image.png";
    const legacyChatThumb =
      "http://api.rodnya-tree.ru/media/chat/chat-thumb.png";

    await ctx.store.updateProfile(alice.user.id, (profile) => ({
      ...profile,
      firstName: "Алиса",
      lastName: "Легаси",
      photoUrl: legacyAlicePhoto,
    }));
    await ctx.store.updateProfile(bob.user.id, (profile) => ({
      ...profile,
      firstName: "Боб",
      lastName: "Легаси",
      photoUrl: legacyBobPhoto,
    }));

    const aliceHeaders = {authorization: `Bearer ${alice.accessToken}`};
    const bobHeaders = {authorization: `Bearer ${bob.accessToken}`};

    const sessionResponse = await fetch(`${ctx.baseUrl}/v1/auth/session`, {
      headers: aliceHeaders,
    });
    assert.equal(sessionResponse.status, 200);
    const sessionPayload = await sessionResponse.json();
    assert.equal(
      sessionPayload.user.photoUrl,
      legacyAlicePhoto.replace(/^http:/, "https:"),
    );

    const bootstrapResponse = await fetch(
      `${ctx.baseUrl}/v1/profile/me/bootstrap`,
      {headers: aliceHeaders},
    );
    assert.equal(bootstrapResponse.status, 200);
    const bootstrapPayload = await bootstrapResponse.json();
    assert.equal(
      bootstrapPayload.profile.photoUrl,
      legacyAlicePhoto.replace(/^http:/, "https:"),
    );

    const treeResponse = await fetch(`${ctx.baseUrl}/v1/trees`, {
      method: "POST",
      headers: {
        ...aliceHeaders,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        name: "Legacy Media Tree",
        description: "Tree for URL normalization",
      }),
    });
    assert.equal(treeResponse.status, 201);
    const treePayload = await treeResponse.json();
    const treeId = treePayload.tree.id;

    const personsResponse = await fetch(`${ctx.baseUrl}/v1/trees/${treeId}/persons`, {
      headers: aliceHeaders,
    });
    assert.equal(personsResponse.status, 200);
    const personsPayload = await personsResponse.json();
    const alicePerson = personsPayload.persons.find(
      (person) => person.userId === alice.user.id,
    );
    assert.ok(alicePerson);
    assert.equal(
      alicePerson.photoUrl,
      legacyAlicePhoto.replace(/^http:/, "https:"),
    );

    const postCreateResponse = await fetch(`${ctx.baseUrl}/v1/posts`, {
      method: "POST",
      headers: {
        ...aliceHeaders,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        treeId,
        content: "Legacy media post",
        imageUrls: [legacyPostImage],
      }),
    });
    assert.equal(postCreateResponse.status, 201);
    const postCreatePayload = await postCreateResponse.json();
    assert.equal(
      postCreatePayload.authorPhotoUrl,
      legacyAlicePhoto.replace(/^http:/, "https:"),
    );
    assert.deepEqual(postCreatePayload.imageUrls, [
      legacyPostImage.replace(/^http:/, "https:"),
    ]);

    const postsFeedResponse = await fetch(`${ctx.baseUrl}/v1/posts?treeId=${treeId}`, {
      headers: aliceHeaders,
    });
    assert.equal(postsFeedResponse.status, 200);
    const postsFeedPayload = await postsFeedResponse.json();
    assert.equal(
      postsFeedPayload[0].authorPhotoUrl,
      legacyAlicePhoto.replace(/^http:/, "https:"),
    );
    assert.deepEqual(postsFeedPayload[0].imageUrls, [
      legacyPostImage.replace(/^http:/, "https:"),
    ]);

    const storyCreateResponse = await fetch(`${ctx.baseUrl}/v1/stories`, {
      method: "POST",
      headers: {
        ...aliceHeaders,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        treeId,
        type: "image",
        mediaUrl: legacyStoryMedia,
        thumbnailUrl: legacyStoryThumb,
      }),
    });
    assert.equal(storyCreateResponse.status, 201);
    const storyCreatePayload = await storyCreateResponse.json();
    assert.equal(
      storyCreatePayload.authorPhotoUrl,
      legacyAlicePhoto.replace(/^http:/, "https:"),
    );
    assert.equal(
      storyCreatePayload.mediaUrl,
      legacyStoryMedia.replace(/^http:/, "https:"),
    );
    assert.equal(
      storyCreatePayload.thumbnailUrl,
      legacyStoryThumb.replace(/^http:/, "https:"),
    );

    const storiesResponse = await fetch(`${ctx.baseUrl}/v1/stories?treeId=${treeId}`, {
      headers: aliceHeaders,
    });
    assert.equal(storiesResponse.status, 200);
    const storiesPayload = await storiesResponse.json();
    assert.equal(
      storiesPayload[0].mediaUrl,
      legacyStoryMedia.replace(/^http:/, "https:"),
    );
    assert.equal(
      storiesPayload[0].thumbnailUrl,
      legacyStoryThumb.replace(/^http:/, "https:"),
    );

    const directChatResponse = await fetch(`${ctx.baseUrl}/v1/chats/direct`, {
      method: "POST",
      headers: {
        ...aliceHeaders,
        "content-type": "application/json",
      },
      body: JSON.stringify({otherUserId: bob.user.id}),
    });
    assert.equal(directChatResponse.status, 200);
    const directChatPayload = await directChatResponse.json();
    const chatId = directChatPayload.chatId;

    const aliceChatsResponse = await fetch(`${ctx.baseUrl}/v1/chats`, {
      headers: aliceHeaders,
    });
    assert.equal(aliceChatsResponse.status, 200);
    const aliceChatsPayload = await aliceChatsResponse.json();
    assert.equal(
      aliceChatsPayload.chats[0].otherUserPhotoUrl,
      legacyBobPhoto.replace(/^http:/, "https:"),
    );

    const sendMessageResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${chatId}/messages`,
      {
        method: "POST",
        headers: {
          ...aliceHeaders,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          text: "Legacy image",
          attachments: [
            {
              type: "image",
              url: legacyChatImage,
              thumbnailUrl: legacyChatThumb,
              mimeType: "image/png",
            },
          ],
        }),
      },
    );
    assert.equal(sendMessageResponse.status, 201);
    const sendMessagePayload = await sendMessageResponse.json();
    assert.equal(
      sendMessagePayload.message.attachments[0].url,
      legacyChatImage.replace(/^http:/, "https:"),
    );
    assert.equal(
      sendMessagePayload.message.attachments[0].thumbnailUrl,
      legacyChatThumb.replace(/^http:/, "https:"),
    );

    const historyResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${chatId}/messages`,
      {
        headers: bobHeaders,
      },
    );
    assert.equal(historyResponse.status, 200);
    const historyPayload = await historyResponse.json();
    assert.equal(
      historyPayload.messages[0].attachments[0].url,
      legacyChatImage.replace(/^http:/, "https:"),
    );
    assert.equal(
      historyPayload.messages[0].attachments[0].thumbnailUrl,
      legacyChatThumb.replace(/^http:/, "https:"),
    );
  } finally {
    await stopTestServer(ctx);
  }
});

test("delete account cascades owned state and local media cleanup", async () => {
  const ctx = await startConfiguredTestServer();

  try {
    const registerOwnerResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "owner-delete@rodnya.app",
        password: "secret123",
        displayName: "Delete Owner",
      }),
    });
    assert.equal(registerOwnerResponse.status, 201);
    const owner = await registerOwnerResponse.json();
    const ownerHeaders = {authorization: `Bearer ${owner.accessToken}`};

    const registerPeerResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "peer-delete@rodnya.app",
        password: "secret123",
        displayName: "Delete Peer",
      }),
    });
    assert.equal(registerPeerResponse.status, 201);
    const peer = await registerPeerResponse.json();
    const peerHeaders = {authorization: `Bearer ${peer.accessToken}`};

    async function uploadMedia(bucket, relativePath) {
      const uploadResponse = await fetch(`${ctx.baseUrl}/v1/media/upload`, {
        method: "POST",
        headers: {
          ...ownerHeaders,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          bucket,
          path: relativePath,
          fileBase64:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7Z0uoAAAAASUVORK5CYII=",
          contentType: "image/png",
        }),
      });
      assert.equal(uploadResponse.status, 201);
      return uploadResponse.json();
    }

    const profilePhoto = await uploadMedia("avatars", `${owner.user.id}/profile.png`);
    const postImage = await uploadMedia("posts", `${owner.user.id}/post.png`);
    const chatImage = await uploadMedia("chat", `${owner.user.id}/chat.png`);

    const bootstrapResponse = await fetch(`${ctx.baseUrl}/v1/profile/me/bootstrap`, {
      method: "PUT",
      headers: {
        ...ownerHeaders,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        firstName: "Удаляемый",
        lastName: "Пользователь",
        photoUrl: profilePhoto.url,
      }),
    });
    assert.equal(bootstrapResponse.status, 200);

    const createTreeResponse = await fetch(`${ctx.baseUrl}/v1/trees`, {
      method: "POST",
      headers: {
        ...ownerHeaders,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        name: "Временное дерево",
        description: "Для cascade smoke",
        isPrivate: true,
      }),
    });
    assert.equal(createTreeResponse.status, 201);
    const createdTree = await createTreeResponse.json();

    const createPostResponse = await fetch(`${ctx.baseUrl}/v1/posts`, {
      method: "POST",
      headers: {
        ...ownerHeaders,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        treeId: createdTree.tree.id,
        content: "Пост для удаления",
        imageUrls: [postImage.url],
      }),
    });
    assert.equal(createPostResponse.status, 201);

    const directChatResponse = await fetch(`${ctx.baseUrl}/v1/chats/direct`, {
      method: "POST",
      headers: {
        ...ownerHeaders,
        "content-type": "application/json",
      },
      body: JSON.stringify({otherUserId: peer.user.id}),
    });
    assert.equal(directChatResponse.status, 200);
    const directChat = await directChatResponse.json();

    const sendMessageResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${directChat.chat.id}/messages`,
      {
        method: "POST",
        headers: {
          ...ownerHeaders,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          text: "Сообщение с картинкой",
          attachments: [
            {
              type: "image",
              url: chatImage.url,
              mimeType: "image/png",
              fileName: "chat.png",
            },
          ],
        }),
      },
    );
    assert.equal(sendMessageResponse.status, 201);

    const profileFilePath = path.join(
      ctx.tempDir,
      "uploads",
      "avatars",
      owner.user.id,
      "profile.png",
    );
    const postFilePath = path.join(
      ctx.tempDir,
      "uploads",
      "posts",
      owner.user.id,
      "post.png",
    );
    const chatFilePath = path.join(
      ctx.tempDir,
      "uploads",
      "chat",
      owner.user.id,
      "chat.png",
    );
    await assert.doesNotReject(fs.access(profileFilePath));
    await assert.doesNotReject(fs.access(postFilePath));
    await assert.doesNotReject(fs.access(chatFilePath));

    const deleteAccountResponse = await fetch(`${ctx.baseUrl}/v1/auth/account`, {
      method: "DELETE",
      headers: ownerHeaders,
    });
    assert.equal(deleteAccountResponse.status, 204);

    const deletedSessionResponse = await fetch(`${ctx.baseUrl}/v1/auth/session`, {
      headers: ownerHeaders,
    });
    assert.equal(deletedSessionResponse.status, 401);

    const peerChatsResponse = await fetch(`${ctx.baseUrl}/v1/chats`, {
      headers: peerHeaders,
    });
    assert.equal(peerChatsResponse.status, 200);
    const peerChatsPayload = await peerChatsResponse.json();
    assert.equal(peerChatsPayload.chats.length, 0);

    const snapshot = await ctx.store._read();
    assert.equal(
      snapshot.users.some((entry) => entry.id === owner.user.id),
      false,
    );
    assert.equal(
      snapshot.trees.some((entry) => entry.id === createdTree.tree.id),
      false,
    );
    assert.equal(
      snapshot.posts.some((entry) => entry.authorId === owner.user.id),
      false,
    );
    assert.equal(
      snapshot.messages.some((entry) => entry.senderId === owner.user.id),
      false,
    );
    assert.equal(
      snapshot.persons.some((entry) => entry.userId === owner.user.id),
      false,
    );
    const remainingPersonIds = new Set(snapshot.persons.map((entry) => entry.id));
    assert.equal(
      snapshot.relations.every(
        (entry) =>
          remainingPersonIds.has(entry.person1Id) &&
          remainingPersonIds.has(entry.person2Id),
      ),
      true,
    );

    await assert.rejects(fs.access(profileFilePath));
    await assert.rejects(fs.access(postFilePath));
    await assert.rejects(fs.access(chatFilePath));
  } finally {
    await stopTestServer(ctx);
  }
});

test("file store stays readable during queued writes", async () => {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "rodnya-store-"));
  const dataPath = path.join(tempDir, "dev-db.json");
  const store = new FileStore(dataPath);
  await store.initialize();

  const largeBio = "x".repeat(256 * 1024);

  try {
    const operations = [];
    for (let index = 0; index < 12; index += 1) {
      operations.push(
        store._write({
          users: [],
          sessions: [],
          trees: [],
          persons: [
            {
              id: `person-${index}`,
              treeId: "tree-1",
              name: `Person ${index}`,
              bio: `${largeBio}-${index}`,
            },
          ],
          relations: [],
          messages: [],
          relationRequests: [],
          treeInvitations: [],
          notifications: [],
          pushDevices: [],
          pushDeliveries: [],
        }),
      );
      operations.push(store._read());
    }

    const results = await Promise.all(operations);
    const readSnapshots = results.filter((value) => value && value.persons);
    assert.ok(readSnapshots.length >= 12);
    assert.ok(
      readSnapshots.every(
        (snapshot) =>
          Array.isArray(snapshot.persons) && snapshot.persons.length <= 1,
      ),
    );
  } finally {
    await fs.rm(tempDir, {recursive: true, force: true});
  }
});

test("google auth endpoint requires backend configuration", async () => {
  const ctx = await startTestServer();

  try {
    const response = await fetch(`${ctx.baseUrl}/v1/auth/google`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({idToken: "fake-token"}),
    });
    assert.equal(response.status, 503);
    const payload = await response.json();
    assert.match(payload.message, /Google sign-in/i);
  } finally {
    await stopTestServer(ctx);
  }
});

test("google auth creates a social account and reuses it on repeated login", async () => {
  const googleTokenVerifier = {
    async verifyIdToken(idToken) {
      assert.equal(idToken, "google-token-new-user");
      return {
        sub: "google-sub-new-user",
        email: "google-new@rodnya.app",
        email_verified: true,
        name: "Google New User",
        picture: "https://example.com/google-new-user.jpg",
      };
    },
  };
  const ctx = await startConfiguredTestServer({
    configOverrides: {
      googleWebClientId:
        "676171184233-hl6gauj8c1trtn25a8me7pvm4m4clndv.apps.googleusercontent.com",
    },
    googleTokenVerifier,
  });

  try {
    const firstResponse = await fetch(`${ctx.baseUrl}/v1/auth/google`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({idToken: "google-token-new-user"}),
    });
    assert.equal(firstResponse.status, 200);
    const firstPayload = await firstResponse.json();
    assert.ok(firstPayload.accessToken);
    assert.equal(firstPayload.user.email, "google-new@rodnya.app");
    assert.deepEqual(firstPayload.user.providerIds, ["google"]);
    assert.equal(firstPayload.user.displayName, "Google New User");

    const linkingStatusResponse = await fetch(
      `${ctx.baseUrl}/v1/profile/me/account-linking-status`,
      {
        headers: {authorization: `Bearer ${firstPayload.accessToken}`},
      },
    );
    assert.equal(linkingStatusResponse.status, 200);
    const linkingStatusPayload = await linkingStatusResponse.json();
    assert.deepEqual(linkingStatusPayload.linkedProviderIds, ["google"]);
    assert.ok(
      linkingStatusPayload.identities.some(
        (entry) => entry.provider === "google" && entry.emailMasked,
      ),
    );

    const secondResponse = await fetch(`${ctx.baseUrl}/v1/auth/google`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({idToken: "google-token-new-user"}),
    });
    assert.equal(secondResponse.status, 200);
    const secondPayload = await secondResponse.json();
    assert.equal(secondPayload.user.id, firstPayload.user.id);
    assert.deepEqual(secondPayload.user.providerIds, ["google"]);
  } finally {
    await stopTestServer(ctx);
  }
});

test("google auth links to an existing password account by verified email", async () => {
  const googleTokenVerifier = {
    async verifyIdToken() {
      return {
        sub: "google-sub-existing-email",
        email: "existing-google@rodnya.app",
        email_verified: true,
        name: "Existing Google",
      };
    },
  };
  const ctx = await startConfiguredTestServer({
    configOverrides: {
      googleWebClientId:
        "676171184233-hl6gauj8c1trtn25a8me7pvm4m4clndv.apps.googleusercontent.com",
    },
    googleTokenVerifier,
  });

  async function registerUser(email, displayName) {
    const response = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email,
        password: "secret123",
        displayName,
      }),
    });
    assert.equal(response.status, 201);
    return response.json();
  }

  try {
    const registered = await registerUser(
      "existing-google@rodnya.app",
      "Existing Email User",
    );
    const googleResponse = await fetch(`${ctx.baseUrl}/v1/auth/google`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({idToken: "google-token-existing-email"}),
    });
    assert.equal(googleResponse.status, 200);
    const googlePayload = await googleResponse.json();
    assert.equal(googlePayload.user.id, registered.user.id);
    assert.deepEqual(
      [...googlePayload.user.providerIds].sort(),
      ["google", "password"],
    );
  } finally {
    await stopTestServer(ctx);
  }
});

test("google link endpoint attaches google to the current account and enables later google login", async () => {
  const googleTokenVerifier = {
    async verifyIdToken(idToken) {
      assert.equal(idToken, "google-link-token");
      return {
        sub: "google-sub-linked-manually",
        email: "manual-link@rodnya.app",
        email_verified: false,
        name: "Manual Link Google",
      };
    },
  };
  const ctx = await startConfiguredTestServer({
    configOverrides: {
      googleWebClientId:
        "676171184233-hl6gauj8c1trtn25a8me7pvm4m4clndv.apps.googleusercontent.com",
    },
    googleTokenVerifier,
  });

  async function registerUser(email, displayName) {
    const response = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email,
        password: "secret123",
        displayName,
      }),
    });
    assert.equal(response.status, 201);
    return response.json();
  }

  try {
    const registered = await registerUser(
      "manual-link@rodnya.app",
      "Manual Link User",
    );
    const linkResponse = await fetch(`${ctx.baseUrl}/v1/auth/google/link`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${registered.accessToken}`,
      },
      body: JSON.stringify({idToken: "google-link-token"}),
    });
    assert.equal(linkResponse.status, 200);
    const linkPayload = await linkResponse.json();
    assert.equal(linkPayload.ok, true);
    assert.deepEqual(
      [...linkPayload.user.providerIds].sort(),
      ["google", "password"],
    );

    const googleLoginResponse = await fetch(`${ctx.baseUrl}/v1/auth/google`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({idToken: "google-link-token"}),
    });
    assert.equal(googleLoginResponse.status, 200);
    const googleLoginPayload = await googleLoginResponse.json();
    assert.equal(googleLoginPayload.user.id, registered.user.id);
    assert.deepEqual(
      [...googleLoginPayload.user.providerIds].sort(),
      ["google", "password"],
    );
  } finally {
    await stopTestServer(ctx);
  }
});

test("legacy phone verification and discovery routes are removed", async () => {
  const ctx = await startConfiguredTestServer();

  async function registerUser(email, displayName) {
    const response = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email,
        password: "secret123",
        displayName,
      }),
    });
    assert.equal(response.status, 201);
    return response.json();
  }

  try {
    const owner = await registerUser("phone-owner@rodnya.app", "Phone Owner");

    const requestResponse = await fetch(
      `${ctx.baseUrl}/v1/profile/me/phone-verification/request`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${owner.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          phoneNumber: "9990001122",
          countryCode: "+7",
        }),
      },
    );
    assert.equal(requestResponse.status, 404);

    const confirmResponse = await fetch(
      `${ctx.baseUrl}/v1/profile/me/phone-verification/confirm`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${owner.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          challengeId: "challenge-1",
          code: "123456",
        }),
      },
    );
    assert.equal(confirmResponse.status, 404);

    const discoverResponse = await fetch(
      `${ctx.baseUrl}/v1/users/discover-by-phones`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${owner.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          phoneNumbers: ["+7 999 000-11-22"],
        }),
      },
    );
    assert.equal(discoverResponse.status, 404);

    const verifyPhoneResponse = await fetch(
      `${ctx.baseUrl}/v1/profile/me/verify-phone`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${owner.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          phoneNumber: "+7 999 000-11-22",
        }),
      },
    );
    assert.equal(verifyPhoneResponse.status, 404);

    const searchByPhoneResponse = await fetch(
      `${ctx.baseUrl}/v1/users/search/by-field?field=phoneNumber&value=9990001122`,
      {
        headers: {
          authorization: `Bearer ${owner.accessToken}`,
        },
      },
    );
    assert.equal(searchByPhoneResponse.status, 410);
  } finally {
    await stopTestServer(ctx);
  }
});

test("MAX webapp flow supports pending link, link, and later login", async () => {
  const maxBotToken = "max-bot-token";
  const maxBotUsername = "RodnyaMaxBot";
  const ctx = await startConfiguredTestServer({
    configOverrides: {
      maxBotToken,
      maxBotUsername,
      publicAppUrl: "https://rodnya-tree.ru",
    },
  });

  async function registerUser(email, displayName) {
    const response = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email,
        password: "secret123",
        displayName,
      }),
    });
    assert.equal(response.status, 201);
    return response.json();
  }

  try {
    const owner = await registerUser("max-owner@rodnya.app", "MAX Owner");

    const linkStartResponse = await fetch(
      `${ctx.baseUrl}/v1/auth/max/start?intent=link`,
      {redirect: "manual"},
    );
    assert.equal(linkStartResponse.status, 302);
    const linkStartLocation = linkStartResponse.headers.get("location");
    assert.ok(linkStartLocation);
    assert.match(linkStartLocation, /https:\/\/max\.ru\/RodnyaMaxBot\?startapp=/);
    const linkStartParam = new URL(linkStartLocation).searchParams.get("startapp");
    assert.ok(linkStartParam);

    const maxUser = {
      id: "900100200",
      first_name: "Макс",
      last_name: "Роднин",
      username: "max_rodnya_user",
      language_code: "ru",
      photo_url: "https://cdn.max.test/avatar.png",
    };
    const linkCompleteResponse = await fetch(
      `${ctx.baseUrl}/v1/auth/max/complete`,
      {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({
          initData: buildMaxInitData({
            botToken: maxBotToken,
            startParam: linkStartParam,
            user: maxUser,
          }),
        }),
      },
    );
    assert.equal(linkCompleteResponse.status, 200);
    const linkCompletePayload = await linkCompleteResponse.json();
    assert.equal(linkCompletePayload.status, "pending_link");
    const linkResultCode = extractHashQueryParameters(
      linkCompletePayload.redirectUrl,
    ).get("maxAuthCode");
    assert.ok(linkResultCode);
    assert.equal(
      extractHashQueryParameters(linkCompletePayload.redirectUrl).get("maxIntent"),
      "link",
    );

    const exchangePendingResponse = await fetch(
      `${ctx.baseUrl}/v1/auth/max/exchange`,
      {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({code: linkResultCode}),
      },
    );
    assert.equal(exchangePendingResponse.status, 200);
    const exchangePendingPayload = await exchangePendingResponse.json();
    assert.equal(exchangePendingPayload.status, "pending_link");
    assert.ok(exchangePendingPayload.linkCode);

    const linkIdentityResponse = await fetch(`${ctx.baseUrl}/v1/auth/max/link`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${owner.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({code: exchangePendingPayload.linkCode}),
    });
    assert.equal(linkIdentityResponse.status, 200);
    const linkIdentityPayload = await linkIdentityResponse.json();
    assert.equal(linkIdentityPayload.ok, true);
    assert.deepEqual(
      [...linkIdentityPayload.user.providerIds].sort(),
      ["max", "password"],
    );

    const loginStartResponse = await fetch(`${ctx.baseUrl}/v1/auth/max/start`, {
      redirect: "manual",
    });
    assert.equal(loginStartResponse.status, 302);
    const loginStartLocation = loginStartResponse.headers.get("location");
    assert.ok(loginStartLocation);
    const loginStartParam = new URL(loginStartLocation).searchParams.get("startapp");
    assert.ok(loginStartParam);

    const loginCompleteResponse = await fetch(
      `${ctx.baseUrl}/v1/auth/max/complete`,
      {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({
          initData: buildMaxInitData({
            botToken: maxBotToken,
            startParam: loginStartParam,
            user: maxUser,
          }),
        }),
      },
    );
    assert.equal(loginCompleteResponse.status, 200);
    const loginCompletePayload = await loginCompleteResponse.json();
    assert.equal(loginCompletePayload.status, "authenticated");
    const loginResultCode = extractHashQueryParameters(
      loginCompletePayload.redirectUrl,
    ).get("maxAuthCode");
    assert.ok(loginResultCode);

    const exchangeAuthenticatedResponse = await fetch(
      `${ctx.baseUrl}/v1/auth/max/exchange`,
      {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({code: loginResultCode}),
      },
    );
    assert.equal(exchangeAuthenticatedResponse.status, 200);
    const exchangeAuthenticatedPayload = await exchangeAuthenticatedResponse.json();
    assert.equal(exchangeAuthenticatedPayload.status, "authenticated");
    assert.equal(
      exchangeAuthenticatedPayload.auth.user.id,
      owner.user.id,
    );
    assert.deepEqual(
      [...exchangeAuthenticatedPayload.auth.user.providerIds].sort(),
      ["max", "password"],
    );
  } finally {
    await stopTestServer(ctx);
  }
});

test("account linking status exposes trusted-channel discovery model", async () => {
  const ctx = await startConfiguredTestServer();

  async function registerUser(email, displayName) {
    const response = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email,
        password: "secret123",
        displayName,
      }),
    });
    assert.equal(response.status, 201);
    return response.json();
  }

  try {
    const owner = await registerUser("discover-owner@rodnya.app", "Discover Owner");

    const statusResponse = await fetch(
      `${ctx.baseUrl}/v1/profile/me/account-linking-status`,
      {
        headers: {
          authorization: `Bearer ${owner.accessToken}`,
        },
      },
    );
    assert.equal(statusResponse.status, 200);
    const statusPayload = await statusResponse.json();
    assert.equal(statusPayload.legacyPhoneVerification, false);
    assert.deepEqual(statusPayload.discoveryModes, [
      "username",
      "profile_code",
      "email",
      "invite_link",
      "claim_link",
      "qr",
    ]);
    assert.equal(statusPayload.linkedProviderIds.includes("password"), true);
    assert.equal(
      statusPayload.mergeStrategy.summary.includes("identity"),
      true,
    );
  } finally {
    await stopTestServer(ctx);
  }
});

test("user profile respects section visibility and self view still returns full data", async () => {
  const ctx = await startTestServer();

  async function registerUser(email, displayName) {
    const response = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email,
        password: "secret123",
        displayName,
      }),
    });
    assert.equal(response.status, 201);
    return response.json();
  }

  try {
    const owner = await registerUser("rich-owner@rodnya.app", "Rich Owner");
    const viewer = await registerUser("rich-viewer@rodnya.app", "Rich Viewer");

    const saveProfileResponse = await fetch(
      `${ctx.baseUrl}/v1/profile/me/bootstrap`,
      {
        method: "PUT",
        headers: {
          authorization: `Bearer ${owner.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          firstName: "Артем",
          lastName: "Кузнецов",
          username: "artem-rich",
          phoneNumber: "9990001122",
          countryCode: "+7",
          countryName: "Россия",
          city: "Москва",
          bio: "Люблю семейные архивы и длинные разговоры.",
          familyStatus: "Женат",
          aboutFamily: "Вечерами собираю семейные истории для детей.",
          education: "МГУ, исторический факультет",
          work: "Семейный бизнес",
          hometown: "Тула",
          languages: "Русский, английский",
          values: "Семья, доверие, память",
          religion: "Православие",
          interests: "Генеалогия, фотографии, поездки по родным местам",
          profileVisibility: {
            contacts: {scope: "private"},
            about: {scope: "shared_trees"},
            background: {scope: "public"},
            worldview: {scope: "private"},
          },
        }),
      },
    );
    assert.equal(saveProfileResponse.status, 200);

    const outsiderViewResponse = await fetch(
      `${ctx.baseUrl}/v1/users/${owner.user.id}/profile`,
      {
        headers: {authorization: `Bearer ${viewer.accessToken}`},
      },
    );
    assert.equal(outsiderViewResponse.status, 200);
    const outsiderView = await outsiderViewResponse.json();
    assert.equal(outsiderView.profile.bio, "");
    assert.equal(outsiderView.profile.familyStatus, "");
    assert.equal(outsiderView.profile.aboutFamily, "");
    assert.equal(outsiderView.profile.education, "МГУ, исторический факультет");
    assert.equal(outsiderView.profile.work, "Семейный бизнес");
    assert.equal(outsiderView.profile.hometown, "Тула");
    assert.equal(outsiderView.profile.languages, "Русский, английский");
    assert.equal(outsiderView.profile.values, "");
    assert.equal(outsiderView.profile.interests, "");
    assert.equal(outsiderView.profile.phoneNumber, "");
    assert.deepEqual(
      outsiderView.profile.hiddenProfileSections.sort(),
      ["about", "contacts", "worldview"],
    );
    assert.deepEqual(outsiderView.profile.profileVisibility, {
      contacts: {scope: "private"},
      about: {scope: "shared_trees"},
      background: {scope: "public"},
      worldview: {scope: "private"},
    });

    const db = await ctx.store._read();
    const timestamp = new Date().toISOString();
    db.trees.push({
      id: "tree-shared-profile",
      name: "Общее дерево",
      description: "",
      creatorId: owner.user.id,
      memberIds: [owner.user.id, viewer.user.id],
      members: [owner.user.id, viewer.user.id],
      createdAt: timestamp,
      updatedAt: timestamp,
      isPrivate: true,
      kind: "family",
      publicSlug: null,
      isCertified: false,
      certificationNote: null,
    });
    await ctx.store._write(db);

    const relativeViewResponse = await fetch(
      `${ctx.baseUrl}/v1/users/${owner.user.id}/profile`,
      {
        headers: {authorization: `Bearer ${viewer.accessToken}`},
      },
    );
    assert.equal(relativeViewResponse.status, 200);
    const relativeView = await relativeViewResponse.json();
    assert.equal(relativeView.profile.bio, "Люблю семейные архивы и длинные разговоры.");
    assert.equal(relativeView.profile.familyStatus, "Женат");
    assert.equal(
      relativeView.profile.aboutFamily,
      "Вечерами собираю семейные истории для детей.",
    );
    assert.equal(relativeView.profile.education, "МГУ, исторический факультет");
    assert.equal(relativeView.profile.hometown, "Тула");
    assert.equal(relativeView.profile.languages, "Русский, английский");
    assert.equal(relativeView.profile.values, "");
    assert.equal(relativeView.profile.interests, "");
    assert.equal(relativeView.profile.phoneNumber, "");
    assert.deepEqual(
      relativeView.profile.hiddenProfileSections.sort(),
      ["contacts", "worldview"],
    );

    const selfViewResponse = await fetch(
      `${ctx.baseUrl}/v1/users/${owner.user.id}/profile`,
      {
        headers: {authorization: `Bearer ${owner.accessToken}`},
      },
    );
    assert.equal(selfViewResponse.status, 200);
    const selfView = await selfViewResponse.json();
    assert.equal(selfView.profile.bio, "Люблю семейные архивы и длинные разговоры.");
    assert.equal(
      selfView.profile.aboutFamily,
      "Вечерами собираю семейные истории для детей.",
    );
    assert.equal(selfView.profile.hometown, "Тула");
    assert.equal(selfView.profile.languages, "Русский, английский");
    assert.equal(selfView.profile.values, "Семья, доверие, память");
    assert.equal(
      selfView.profile.interests,
      "Генеалогия, фотографии, поездки по родным местам",
    );
    assert.equal(selfView.profile.phoneNumber, "9990001122");
    assert.equal(selfView.profile.email, owner.user.email);
    assert.equal(selfView.profile.hiddenProfileSections.length, 0);
    assert.deepEqual(selfView.profile.profileVisibility, {
      contacts: {
        scope: "private",
        treeIds: [],
        branchRootPersonIds: [],
        userIds: [],
      },
      about: {
        scope: "shared_trees",
        treeIds: [],
        branchRootPersonIds: [],
        userIds: [],
      },
      background: {
        scope: "public",
        treeIds: [],
        branchRootPersonIds: [],
        userIds: [],
      },
      worldview: {
        scope: "private",
        treeIds: [],
        branchRootPersonIds: [],
        userIds: [],
      },
    });
  } finally {
    await stopTestServer(ctx);
  }
});

test("user profile supports specific tree, branch and specific user visibility targets", async () => {
  const ctx = await startTestServer();

  async function registerUser(email, displayName) {
    const response = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email,
        password: "secret123",
        displayName,
      }),
    });
    assert.equal(response.status, 201);
    return response.json();
  }

  try {
    const owner = await registerUser("specific-owner@rodnya.app", "Specific Owner");
    const treeViewer = await registerUser("specific-tree@rodnya.app", "Tree Viewer");
    const branchViewer = await registerUser("specific-branch@rodnya.app", "Branch Viewer");
    const userViewer = await registerUser("specific-user@rodnya.app", "User Viewer");

    const saveProfileResponse = await fetch(
      `${ctx.baseUrl}/v1/profile/me/bootstrap`,
      {
        method: "PUT",
        headers: {
          authorization: `Bearer ${owner.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          firstName: "Мария",
          lastName: "Орлова",
          username: "specific-owner",
          phoneNumber: "9990001133",
          countryCode: "+7",
          countryName: "Россия",
          city: "Казань",
          bio: "Обо мне знают только участники выбранного дерева.",
          familyStatus: "Замужем",
          aboutFamily: "В семье храню письма прадеда и показываю их только близким.",
          education: "КФУ",
          work: "Семейная мастерская",
          hometown: "Казань",
          languages: "Русский, татарский",
          values: "Вера и семья",
          religion: "Православие",
          interests: "Ручная работа и семейные праздники",
          profileVisibility: {
            contacts: {
              scope: "specific_branches",
              branchRootPersonIds: ["person-branch-root"],
            },
            about: {scope: "specific_trees", treeIds: ["tree-allowed"]},
            background: {scope: "public"},
            worldview: {scope: "specific_users", userIds: [userViewer.user.id]},
          },
        }),
      },
    );
    assert.equal(saveProfileResponse.status, 200);

    const db = await ctx.store._read();
    const timestamp = new Date().toISOString();
    db.trees.push(
      {
        id: "tree-allowed",
        name: "Нужное дерево",
        description: "",
        creatorId: owner.user.id,
        memberIds: [owner.user.id, treeViewer.user.id],
        members: [owner.user.id, treeViewer.user.id],
        createdAt: timestamp,
        updatedAt: timestamp,
        isPrivate: true,
        kind: "family",
        publicSlug: null,
        isCertified: false,
        certificationNote: null,
      },
      {
        id: "tree-other",
        name: "Другое дерево",
        description: "",
        creatorId: owner.user.id,
        memberIds: [owner.user.id],
        members: [owner.user.id],
        createdAt: timestamp,
        updatedAt: timestamp,
        isPrivate: true,
        kind: "family",
        publicSlug: null,
        isCertified: false,
        certificationNote: null,
      },
      {
        id: "tree-branch",
        name: "Ветка по ветке",
        description: "",
        creatorId: owner.user.id,
        memberIds: [owner.user.id, branchViewer.user.id],
        members: [owner.user.id, branchViewer.user.id],
        createdAt: timestamp,
        updatedAt: timestamp,
        isPrivate: true,
        kind: "family",
        publicSlug: null,
        isCertified: false,
        certificationNote: null,
      },
    );
    db.persons.push(
      {
        id: "person-owner-branch",
        treeId: "tree-branch",
        userId: owner.user.id,
        identityId: null,
        name: "Мария Орлова",
        maidenName: null,
        photoUrl: null,
        gender: "female",
        birthDate: null,
        birthPlace: null,
        deathDate: null,
        deathPlace: null,
        bio: "",
        isAlive: true,
        creatorId: owner.user.id,
        createdAt: timestamp,
        updatedAt: timestamp,
        notes: "",
      },
      {
        id: "person-branch-root",
        treeId: "tree-branch",
        userId: null,
        identityId: null,
        name: "Старшая ветка",
        maidenName: null,
        photoUrl: null,
        gender: "female",
        birthDate: null,
        birthPlace: null,
        deathDate: null,
        deathPlace: null,
        bio: "",
        isAlive: true,
        creatorId: owner.user.id,
        createdAt: timestamp,
        updatedAt: timestamp,
        notes: "",
      },
      {
        id: "person-branch-viewer",
        treeId: "tree-branch",
        userId: branchViewer.user.id,
        identityId: null,
        name: "Видимый Родственник",
        maidenName: null,
        photoUrl: null,
        gender: "male",
        birthDate: null,
        birthPlace: null,
        deathDate: null,
        deathPlace: null,
        bio: "",
        isAlive: true,
        creatorId: owner.user.id,
        createdAt: timestamp,
        updatedAt: timestamp,
        notes: "",
      },
    );
    db.relations.push({
      id: "relation-branch-root-child",
      treeId: "tree-branch",
      person1Id: "person-branch-root",
      person2Id: "person-branch-viewer",
      relation1to2: "parent",
      relation2to1: "child",
      isConfirmed: true,
      createdAt: timestamp,
      updatedAt: timestamp,
      createdBy: owner.user.id,
      marriageDate: null,
      divorceDate: null,
    });
    await ctx.store._write(db);

    const treeViewerResponse = await fetch(
      `${ctx.baseUrl}/v1/users/${owner.user.id}/profile`,
      {
        headers: {authorization: `Bearer ${treeViewer.accessToken}`},
      },
    );
    assert.equal(treeViewerResponse.status, 200);
    const treeViewerProfile = await treeViewerResponse.json();
    assert.equal(
      treeViewerProfile.profile.bio,
      "Обо мне знают только участники выбранного дерева.",
    );
    assert.equal(
      treeViewerProfile.profile.aboutFamily,
      "В семье храню письма прадеда и показываю их только близким.",
    );
    assert.equal(treeViewerProfile.profile.hometown, "Казань");
    assert.equal(treeViewerProfile.profile.languages, "Русский, татарский");
    assert.equal(treeViewerProfile.profile.values, "");
    assert.equal(treeViewerProfile.profile.interests, "");
    assert.deepEqual(
      treeViewerProfile.profile.hiddenProfileSections.sort(),
      ["contacts", "worldview"],
    );

    const branchViewerResponse = await fetch(
      `${ctx.baseUrl}/v1/users/${owner.user.id}/profile`,
      {
        headers: {authorization: `Bearer ${branchViewer.accessToken}`},
      },
    );
    assert.equal(branchViewerResponse.status, 200);
    const branchViewerProfile = await branchViewerResponse.json();
    assert.equal(branchViewerProfile.profile.phoneNumber, "9990001133");
    assert.equal(branchViewerProfile.profile.countryCode, "+7");
    assert.equal(branchViewerProfile.profile.city, "Казань");
    assert.equal(branchViewerProfile.profile.bio, "");
    assert.equal(branchViewerProfile.profile.values, "");
    assert.deepEqual(
      branchViewerProfile.profile.hiddenProfileSections.sort(),
      ["about", "worldview"],
    );

    const userViewerResponse = await fetch(
      `${ctx.baseUrl}/v1/users/${owner.user.id}/profile`,
      {
        headers: {authorization: `Bearer ${userViewer.accessToken}`},
      },
    );
    assert.equal(userViewerResponse.status, 200);
    const userViewerProfile = await userViewerResponse.json();
    assert.equal(userViewerProfile.profile.bio, "");
    assert.equal(userViewerProfile.profile.aboutFamily, "");
    assert.equal(userViewerProfile.profile.hometown, "Казань");
    assert.equal(userViewerProfile.profile.languages, "Русский, татарский");
    assert.equal(userViewerProfile.profile.values, "Вера и семья");
    assert.equal(
      userViewerProfile.profile.interests,
      "Ручная работа и семейные праздники",
    );
    assert.deepEqual(
      userViewerProfile.profile.hiddenProfileSections.sort(),
      ["about", "contacts"],
    );

    const selfViewResponse = await fetch(
      `${ctx.baseUrl}/v1/users/${owner.user.id}/profile`,
      {
        headers: {authorization: `Bearer ${owner.accessToken}`},
      },
    );
    assert.equal(selfViewResponse.status, 200);
    const selfView = await selfViewResponse.json();
    assert.deepEqual(selfView.profile.profileVisibility, {
      contacts: {
        scope: "specific_branches",
        treeIds: [],
        branchRootPersonIds: ["person-branch-root"],
        userIds: [],
      },
      about: {
        scope: "specific_trees",
        treeIds: ["tree-allowed"],
        branchRootPersonIds: [],
        userIds: [],
      },
      background: {
        scope: "public",
        treeIds: [],
        branchRootPersonIds: [],
        userIds: [],
      },
      worldview: {
        scope: "specific_users",
        treeIds: [],
        branchRootPersonIds: [],
        userIds: [userViewer.user.id],
      },
    });
  } finally {
    await stopTestServer(ctx);
  }
});

test("auth identity linking resolves by provider first, then email", async () => {
  const ctx = await startTestServer();

  async function registerUser(email, displayName) {
    const response = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email,
        password: "secret123",
        displayName,
      }),
    });
    assert.equal(response.status, 201);
    return response.json();
  }

  try {
    const owner = await registerUser("identity-owner@rodnya.app", "Owner");
    const secondary = await registerUser("identity-secondary@rodnya.app", "Secondary");

    const linkedOwner = await ctx.store.linkAuthIdentity(owner.user.id, {
      provider: "google",
      providerUserId: "google-sub-1",
      email: "identity-owner@rodnya.app",
      displayName: "Owner Google",
    });
    assert.ok(linkedOwner.providerIds.includes("google"));

    const providerResolved = await ctx.store.resolveAuthIdentityTarget({
      provider: "google",
      providerUserId: "google-sub-1",
      email: "other@rodnya.app",
      phoneNumber: "+7 999 999 99 99",
    });
    assert.equal(providerResolved.reason, "provider_identity");
    assert.equal(providerResolved.user.id, owner.user.id);

    const emailResolved = await ctx.store.resolveAuthIdentityTarget({
      provider: "vk",
      providerUserId: "vk-777",
      email: secondary.user.email,
    });
    assert.equal(emailResolved.reason, "email");
    assert.equal(emailResolved.user.id, secondary.user.id);

    const newAccountResolved = await ctx.store.resolveAuthIdentityTarget({
      provider: "max",
      providerUserId: "max-888",
      email: "brand-new@rodnya.app",
      phoneNumber: "+7 999 555 55 55",
    });
    assert.equal(newAccountResolved.reason, "new_account");
    assert.equal(newAccountResolved.user, null);

    const linkingStatusResponse = await fetch(
      `${ctx.baseUrl}/v1/profile/me/account-linking-status`,
      {
        headers: {authorization: `Bearer ${owner.accessToken}`},
      },
    );
    assert.equal(linkingStatusResponse.status, 200);
    const linkingStatusPayload = await linkingStatusResponse.json();
    assert.deepEqual(
      linkingStatusPayload.linkedProviderIds.sort(),
      ["google", "password"],
    );
    assert.equal(linkingStatusPayload.legacyPhoneVerification, false);
    assert.equal(linkingStatusPayload.mergeStrategy.order[0], "provider_identity");
    assert.equal(linkingStatusPayload.discoveryModes.includes("username"), true);
    assert.ok(Array.isArray(linkingStatusPayload.identities));
    assert.equal(linkingStatusPayload.identities.length, 2);
    assert.ok(
      linkingStatusPayload.identities.some(
        (entry) => entry.provider === "google" && entry.emailMasked,
      ),
    );
  } finally {
    await stopTestServer(ctx);
  }
});

test("telegram auth start, exchange and pending link flow work end-to-end", async () => {
  const telegramBotToken = "telegram-test-token";
  const telegramBotUsername = "RodnyaFamilyBot";
  const ctx = await startConfiguredTestServer({
    configOverrides: {
      publicAppUrl: "https://rodnya-tree.ru",
      publicApiUrl: "",
      telegramBotToken,
      telegramBotUsername,
      telegramLoginEnabled: true,
    },
  });

  function buildTelegramQuery(params) {
    const entries = Object.entries(params)
      .filter(([, value]) => value !== undefined && value !== null && String(value).trim() !== "")
      .sort(([leftKey], [rightKey]) => leftKey.localeCompare(rightKey));
    const dataCheckString = entries
      .map(([key, value]) => `${key}=${value}`)
      .join("\n");
    const secretKey = crypto.createHash("sha256").update(telegramBotToken, "utf8").digest();
    const hash = crypto
      .createHmac("sha256", secretKey)
      .update(dataCheckString, "utf8")
      .digest("hex");
    return new URLSearchParams({
      ...Object.fromEntries(entries),
      hash,
    }).toString();
  }

  function extractHashQueryParam(location, name) {
    const url = new URL(location);
    const fragment = url.hash.startsWith("#") ? url.hash.slice(1) : url.hash;
    const queryPart = fragment.includes("?") ? fragment.split("?").slice(1).join("?") : "";
    return new URLSearchParams(queryPart).get(name);
  }

  async function registerUser(email, displayName) {
    const response = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email,
        password: "secret123",
        displayName,
      }),
    });
    assert.equal(response.status, 201);
    return response.json();
  }

  try {
    const startResponse = await fetch(`${ctx.baseUrl}/v1/auth/telegram/start`);
    assert.equal(startResponse.status, 200);
    const startHtml = await startResponse.text();
    assert.match(startHtml, /RodnyaFamilyBot/);
    assert.match(startHtml, /telegram-widget/);

    const existingUser = await registerUser("tg-linked@rodnya.app", "TG Linked");
    await ctx.store.linkAuthIdentity(existingUser.user.id, {
      provider: "telegram",
      providerUserId: "100500",
      displayName: "TG Linked",
      metadata: {username: "linked_user"},
    });

    const linkedCallbackResponse = await fetch(
      `${ctx.baseUrl}/v1/auth/telegram/callback?${buildTelegramQuery({
        id: "100500",
        first_name: "TG",
        last_name: "Linked",
        username: "linked_user",
        auth_date: Math.floor(Date.now() / 1000),
      })}`,
      {redirect: "manual"},
    );
    assert.equal(linkedCallbackResponse.status, 302);
    const linkedLocation = linkedCallbackResponse.headers.get("location");
    assert.match(linkedLocation, /telegramAuthCode=/);
    const linkedAuthCode = extractHashQueryParam(linkedLocation, "telegramAuthCode");
    assert.ok(linkedAuthCode);

    const linkedExchangeResponse = await fetch(
      `${ctx.baseUrl}/v1/auth/telegram/exchange`,
      {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({code: linkedAuthCode}),
      },
    );
    assert.equal(linkedExchangeResponse.status, 200);
    const linkedExchangePayload = await linkedExchangeResponse.json();
    assert.equal(linkedExchangePayload.status, "authenticated");
    assert.equal(linkedExchangePayload.auth.user.id, existingUser.user.id);
    assert.ok(linkedExchangePayload.auth.user.providerIds.includes("telegram"));

    const linkedIntentCallbackResponse = await fetch(
      `${ctx.baseUrl}/v1/auth/telegram/callback?intent=link&${buildTelegramQuery({
        id: "100500",
        first_name: "TG",
        last_name: "Linked",
        username: "linked_user",
        auth_date: Math.floor(Date.now() / 1000),
      })}`,
      {redirect: "manual"},
    );
    assert.equal(linkedIntentCallbackResponse.status, 302);
    const linkedIntentLocation = linkedIntentCallbackResponse.headers.get("location");
    assert.equal(
      extractHashQueryParam(linkedIntentLocation, "telegramIntent"),
      "link",
    );
    const linkedIntentCode = extractHashQueryParam(
      linkedIntentLocation,
      "telegramAuthCode",
    );
    assert.ok(linkedIntentCode);

    const linkedIntentExchangeResponse = await fetch(
      `${ctx.baseUrl}/v1/auth/telegram/exchange`,
      {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({code: linkedIntentCode}),
      },
    );
    assert.equal(linkedIntentExchangeResponse.status, 200);
    const linkedIntentExchangePayload = await linkedIntentExchangeResponse.json();
    assert.equal(linkedIntentExchangePayload.status, "already_linked");
    assert.match(linkedIntentExchangePayload.message, /уже привязан/i);

    const pendingUser = await registerUser("tg-pending@rodnya.app", "TG Pending");
    const pendingCallbackResponse = await fetch(
      `${ctx.baseUrl}/v1/auth/telegram/callback?${buildTelegramQuery({
        id: "200600",
        first_name: "Rodnya",
        last_name: "Telegram",
        username: "rodnya_tg",
        auth_date: Math.floor(Date.now() / 1000),
      })}`,
      {redirect: "manual"},
    );
    assert.equal(pendingCallbackResponse.status, 302);
    const pendingLocation = pendingCallbackResponse.headers.get("location");
    const pendingAuthCode = extractHashQueryParam(
      pendingLocation,
      "telegramAuthCode",
    );
    assert.ok(pendingAuthCode);

    const pendingExchangeResponse = await fetch(
      `${ctx.baseUrl}/v1/auth/telegram/exchange`,
      {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({code: pendingAuthCode}),
      },
    );
    assert.equal(pendingExchangeResponse.status, 200);
    const pendingExchangePayload = await pendingExchangeResponse.json();
    assert.equal(pendingExchangePayload.status, "pending_link");
    assert.ok(pendingExchangePayload.linkCode);
    assert.match(pendingExchangePayload.message, /Telegram подтверждён/i);

    const linkResponse = await fetch(`${ctx.baseUrl}/v1/auth/telegram/link`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${pendingUser.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({code: pendingExchangePayload.linkCode}),
    });
    assert.equal(linkResponse.status, 200);
    const linkPayload = await linkResponse.json();
    assert.equal(linkPayload.ok, true);
    assert.ok(linkPayload.user.providerIds.includes("telegram"));

    const secondPendingCallbackResponse = await fetch(
      `${ctx.baseUrl}/v1/auth/telegram/callback?intent=link&${buildTelegramQuery({
        id: "300700",
        first_name: "Second",
        last_name: "Telegram",
        username: "second_tg",
        auth_date: Math.floor(Date.now() / 1000),
      })}`,
      {redirect: "manual"},
    );
    assert.equal(secondPendingCallbackResponse.status, 302);
    const secondPendingLocation = secondPendingCallbackResponse.headers.get("location");
    const secondPendingAuthCode = extractHashQueryParam(
      secondPendingLocation,
      "telegramAuthCode",
    );
    assert.ok(secondPendingAuthCode);

    const secondPendingExchangeResponse = await fetch(
      `${ctx.baseUrl}/v1/auth/telegram/exchange`,
      {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({code: secondPendingAuthCode}),
      },
    );
    assert.equal(secondPendingExchangeResponse.status, 200);
    const secondPendingExchangePayload = await secondPendingExchangeResponse.json();
    assert.equal(secondPendingExchangePayload.status, "pending_link");

    const secondLinkResponse = await fetch(`${ctx.baseUrl}/v1/auth/telegram/link`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${pendingUser.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({code: secondPendingExchangePayload.linkCode}),
    });
    assert.equal(secondLinkResponse.status, 409);
    const secondLinkPayload = await secondLinkResponse.json();
    assert.match(secondLinkPayload.message, /уже привязан другой Telegram/i);
  } finally {
    await stopTestServer(ctx);
  }
});

test("vk auth start, exchange and pending link flow work end-to-end", async () => {
  const vkAuthClient = {
    isEnabled: true,
    webAppId: "54549672",
    async exchangeCode({code, deviceId, state, codeVerifier, redirectUri}) {
      assert.ok(code);
      assert.ok(deviceId);
      assert.ok(state);
      assert.ok(codeVerifier);
      assert.match(redirectUri, /\/v1\/auth\/vk\/callback$/);
      return {access_token: `vk-token-${code}`};
    },
    async fetchUserInfo(accessToken) {
      switch (accessToken) {
        case "vk-token-existing-code":
          return {
            user: {
              user_id: "vk-existing",
              first_name: "VK",
              last_name: "Existing",
              email: "vk-linked@rodnya.app",
            },
          };
        case "vk-token-pending-code":
          return {
            user: {
              user_id: "vk-pending",
              first_name: "VK",
              last_name: "Pending",
            },
          };
        case "vk-token-phone-match-code":
          return {
            user: {
              user_id: "vk-phone-match",
              first_name: "VK",
              last_name: "Phone",
              phone: "+7 999 000 11 22",
            },
          };
        default:
          throw new Error(`Unexpected access token: ${accessToken}`);
      }
    },
  };
  const ctx = await startConfiguredTestServer({
    configOverrides: {
      publicAppUrl: "https://rodnya-tree.ru",
      publicApiUrl: "",
      vkWebAppId: "54549672",
      vkAuthEnabled: true,
    },
    vkAuthClient,
  });

  function extractHashQueryParam(location, name) {
    const url = new URL(location);
    const fragment = url.hash.startsWith("#") ? url.hash.slice(1) : url.hash;
    const queryPart = fragment.includes("?")
      ? fragment.split("?").slice(1).join("?")
      : "";
    return new URLSearchParams(queryPart).get(name);
  }

  async function registerUser(email, displayName) {
    const response = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email,
        password: "secret123",
        displayName,
      }),
    });
    assert.equal(response.status, 201);
    return response.json();
  }

  async function startVkFlow(intent = "login") {
    const query = intent === "link" ? "?intent=link" : "";
    const response = await fetch(`${ctx.baseUrl}/v1/auth/vk/start${query}`, {
      redirect: "manual",
    });
    assert.equal(response.status, 302);
    const location = response.headers.get("location");
    assert.ok(location);
    const url = new URL(location);
    assert.equal(url.hostname, "id.vk.ru");
    assert.equal(url.pathname, "/authorize");
    assert.equal(url.searchParams.get("client_id"), "54549672");
    assert.ok(url.searchParams.get("state"));
    assert.ok(url.searchParams.get("code_challenge"));
    return {
      state: url.searchParams.get("state"),
      redirectUri: url.searchParams.get("redirect_uri"),
    };
  }

  try {
    const existingUser = await registerUser("vk-linked@rodnya.app", "VK Linked");
    await ctx.store.linkAuthIdentity(existingUser.user.id, {
      provider: "vk",
      providerUserId: "vk-existing",
      email: "vk-linked@rodnya.app",
      displayName: "VK Existing",
    });

    const existingStart = await startVkFlow();
    assert.match(existingStart.redirectUri, /\/v1\/auth\/vk\/callback$/);
    const linkedCallbackResponse = await fetch(
      `${ctx.baseUrl}/v1/auth/vk/callback?state=${encodeURIComponent(existingStart.state)}&code=existing-code&device_id=device-1`,
      {redirect: "manual"},
    );
    assert.equal(linkedCallbackResponse.status, 302);
    const linkedLocation = linkedCallbackResponse.headers.get("location");
    assert.match(linkedLocation, /vkAuthCode=/);
    const linkedAuthCode = extractHashQueryParam(linkedLocation, "vkAuthCode");
    assert.ok(linkedAuthCode);

    const linkedExchangeResponse = await fetch(
      `${ctx.baseUrl}/v1/auth/vk/exchange`,
      {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({code: linkedAuthCode}),
      },
    );
    assert.equal(linkedExchangeResponse.status, 200);
    const linkedExchangePayload = await linkedExchangeResponse.json();
    assert.equal(linkedExchangePayload.status, "authenticated");
    assert.equal(linkedExchangePayload.auth.user.id, existingUser.user.id);
    assert.ok(linkedExchangePayload.auth.user.providerIds.includes("vk"));

    const linkedIntentStart = await startVkFlow("link");
    const linkedIntentCallbackResponse = await fetch(
      `${ctx.baseUrl}/v1/auth/vk/callback?state=${encodeURIComponent(linkedIntentStart.state)}&code=existing-code&device_id=device-2`,
      {redirect: "manual"},
    );
    assert.equal(linkedIntentCallbackResponse.status, 302);
    const linkedIntentLocation = linkedIntentCallbackResponse.headers.get("location");
    assert.equal(extractHashQueryParam(linkedIntentLocation, "vkIntent"), "link");
    const linkedIntentCode = extractHashQueryParam(linkedIntentLocation, "vkAuthCode");
    assert.ok(linkedIntentCode);

    const linkedIntentExchangeResponse = await fetch(
      `${ctx.baseUrl}/v1/auth/vk/exchange`,
      {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({code: linkedIntentCode}),
      },
    );
    assert.equal(linkedIntentExchangeResponse.status, 200);
    const linkedIntentExchangePayload = await linkedIntentExchangeResponse.json();
    assert.equal(linkedIntentExchangePayload.status, "already_linked");
    assert.match(linkedIntentExchangePayload.message, /уже привязан/i);

    const pendingUser = await registerUser("vk-pending@rodnya.app", "VK Pending");
    const pendingStart = await startVkFlow();
    const pendingCallbackResponse = await fetch(
      `${ctx.baseUrl}/v1/auth/vk/callback?state=${encodeURIComponent(pendingStart.state)}&code=pending-code&device_id=device-3`,
      {redirect: "manual"},
    );
    assert.equal(pendingCallbackResponse.status, 302);
    const pendingLocation = pendingCallbackResponse.headers.get("location");
    const pendingAuthCode = extractHashQueryParam(pendingLocation, "vkAuthCode");
    assert.ok(pendingAuthCode);

    const pendingExchangeResponse = await fetch(
      `${ctx.baseUrl}/v1/auth/vk/exchange`,
      {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({code: pendingAuthCode}),
      },
    );
    assert.equal(pendingExchangeResponse.status, 200);
    const pendingExchangePayload = await pendingExchangeResponse.json();
    assert.equal(pendingExchangePayload.status, "pending_link");
    assert.ok(pendingExchangePayload.linkCode);
    assert.match(pendingExchangePayload.message, /VK ID/i);

    const linkResponse = await fetch(`${ctx.baseUrl}/v1/auth/vk/link`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${pendingUser.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({code: pendingExchangePayload.linkCode}),
    });
    assert.equal(linkResponse.status, 200);
    const linkPayload = await linkResponse.json();
    assert.equal(linkPayload.ok, true);
    assert.ok(linkPayload.user.providerIds.includes("vk"));

    const owner = await registerUser("vk-owner@rodnya.app", "VK Owner");
    const outsider = await registerUser("vk-outsider@rodnya.app", "VK Outsider");

    const phoneMatchStart = await startVkFlow("link");
    const phoneMatchCallbackResponse = await fetch(
      `${ctx.baseUrl}/v1/auth/vk/callback?state=${encodeURIComponent(phoneMatchStart.state)}&code=phone-match-code&device_id=device-4`,
      {redirect: "manual"},
    );
    assert.equal(phoneMatchCallbackResponse.status, 302);
    const phoneMatchLocation = phoneMatchCallbackResponse.headers.get("location");
    const phoneMatchAuthCode = extractHashQueryParam(
      phoneMatchLocation,
      "vkAuthCode",
    );
    assert.ok(phoneMatchAuthCode);

    const phoneMatchExchangeResponse = await fetch(
      `${ctx.baseUrl}/v1/auth/vk/exchange`,
      {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({code: phoneMatchAuthCode}),
      },
    );
    assert.equal(phoneMatchExchangeResponse.status, 200);
    const phoneMatchExchangePayload = await phoneMatchExchangeResponse.json();
    assert.equal(phoneMatchExchangePayload.status, "pending_link");
    assert.ok(phoneMatchExchangePayload.linkCode);

    const conflictingLinkResponse = await fetch(`${ctx.baseUrl}/v1/auth/vk/link`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${outsider.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({code: phoneMatchExchangePayload.linkCode}),
    });
    assert.equal(conflictingLinkResponse.status, 200);
    const conflictingLinkPayload = await conflictingLinkResponse.json();
    assert.equal(conflictingLinkPayload.user.providerIds.includes("vk"), true);
  } finally {
    await stopTestServer(ctx);
  }
});

test("profile notes and media endpoints work for authenticated user", async () => {
  const ctx = await startTestServer();

  try {
    const registerResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "notes@rodnya.app",
        password: "secret123",
        displayName: "Notes User",
      }),
    });
    assert.equal(registerResponse.status, 201);
    const registered = await registerResponse.json();
    const token = registered.accessToken;
    const userId = registered.user.id;

    const createNoteResponse = await fetch(
      `${ctx.baseUrl}/v1/users/${userId}/profile-notes`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          title: "Семейная история",
          content: "Первая заметка профиля",
        }),
      },
    );
    assert.equal(createNoteResponse.status, 201);
    const createdNotePayload = await createNoteResponse.json();
    assert.equal(createdNotePayload.note.title, "Семейная история");

    const noteId = createdNotePayload.note.id;
    assert.ok(noteId);

    const listNotesResponse = await fetch(
      `${ctx.baseUrl}/v1/users/${userId}/profile-notes`,
      {
        headers: {authorization: `Bearer ${token}`},
      },
    );
    assert.equal(listNotesResponse.status, 200);
    const listedNotes = await listNotesResponse.json();
    assert.equal(listedNotes.notes.length, 1);

    const updateNoteResponse = await fetch(
      `${ctx.baseUrl}/v1/users/${userId}/profile-notes/${noteId}`,
      {
        method: "PATCH",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          title: "Обновлённая история",
          content: "Исправленный текст заметки",
        }),
      },
    );
    assert.equal(updateNoteResponse.status, 200);
    const updatedNotePayload = await updateNoteResponse.json();
    assert.equal(updatedNotePayload.note.title, "Обновлённая история");

    const uploadResponse = await fetch(`${ctx.baseUrl}/v1/media/upload`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        bucket: "avatars",
        path: `${userId}/avatar.txt`,
        contentType: "text/plain",
        fileBase64: Buffer.from("avatar").toString("base64"),
      }),
    });
    assert.equal(uploadResponse.status, 201);
    const uploadedMedia = await uploadResponse.json();
    assert.match(uploadedMedia.url, /\/media\/avatars\//);

    const mediaResponse = await fetch(uploadedMedia.url);
    assert.equal(mediaResponse.status, 200);
    assert.equal(await mediaResponse.text(), "avatar");

    const deleteMediaResponse = await fetch(`${ctx.baseUrl}/v1/media`, {
      method: "DELETE",
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({url: uploadedMedia.url}),
    });
    assert.equal(deleteMediaResponse.status, 204);

    const deleteNoteResponse = await fetch(
      `${ctx.baseUrl}/v1/users/${userId}/profile-notes/${noteId}`,
      {
        method: "DELETE",
        headers: {authorization: `Bearer ${token}`},
      },
    );
    assert.equal(deleteNoteResponse.status, 204);
  } finally {
    await stopTestServer(ctx);
  }
});

test("tree endpoints cover create tree, persons and relations", async () => {
  const ctx = await startTestServer();

  try {
    const registerResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "tree@rodnya.app",
        password: "secret123",
        displayName: "Иван Иванов",
      }),
    });
    assert.equal(registerResponse.status, 201);
    const registered = await registerResponse.json();
    const token = registered.accessToken;
    const userId = registered.user.id;

    const createTreeResponse = await fetch(`${ctx.baseUrl}/v1/trees`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        name: "Семья Ивановых",
        description: "Основное семейное дерево",
        isPrivate: true,
      }),
    });
    assert.equal(createTreeResponse.status, 201);
    const createdTreePayload = await createTreeResponse.json();
    assert.equal(createdTreePayload.tree.name, "Семья Ивановых");
    const treeId = createdTreePayload.tree.id;

    const listTreesResponse = await fetch(`${ctx.baseUrl}/v1/trees`, {
      headers: {authorization: `Bearer ${token}`},
    });
    assert.equal(listTreesResponse.status, 200);
    const listedTreesPayload = await listTreesResponse.json();
    assert.equal(listedTreesPayload.trees.length, 1);
    assert.equal(listedTreesPayload.trees[0].memberIds[0], userId);

    const selectableTreesResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/selectable`,
      {
        headers: {authorization: `Bearer ${token}`},
      },
    );
    assert.equal(selectableTreesResponse.status, 200);
    const selectableTrees = await selectableTreesResponse.json();
    assert.equal(selectableTrees.trees.length, 1);

    const personsResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/persons`,
      {
        headers: {authorization: `Bearer ${token}`},
      },
    );
    assert.equal(personsResponse.status, 200);
    const initialPersonsPayload = await personsResponse.json();
    assert.equal(initialPersonsPayload.persons.length, 1);
    assert.equal(initialPersonsPayload.persons[0].userId, userId);
    const creatorPersonId = initialPersonsPayload.persons[0].id;

    const createPersonResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/persons`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          firstName: "Мария",
          lastName: "Иванова",
          gender: "female",
        }),
      },
    );
    assert.equal(createPersonResponse.status, 201);
    const createdPersonPayload = await createPersonResponse.json();
    assert.equal(createdPersonPayload.person.name, "Иванова Мария");
    const childPersonId = createdPersonPayload.person.id;

    const createRelationResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/relations`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          person1Id: creatorPersonId,
          person2Id: childPersonId,
          relation1to2: "parent",
          isConfirmed: true,
        }),
      },
    );
    assert.equal(createRelationResponse.status, 201);
    const createdRelationPayload = await createRelationResponse.json();
    assert.equal(createdRelationPayload.relation.relation1to2, "parent");
    assert.equal(createdRelationPayload.relation.relation2to1, "child");

    const listRelationsResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/relations`,
      {
        headers: {authorization: `Bearer ${token}`},
      },
    );
    assert.equal(listRelationsResponse.status, 200);
    const listedRelationsPayload = await listRelationsResponse.json();
    assert.equal(listedRelationsPayload.relations.length, 1);
  } finally {
    await stopTestServer(ctx);
  }
});

test("tree history and relative gallery endpoints keep legacy photo alias", async () => {
  const ctx = await startTestServer();

  try {
    const registerResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "tree-history@rodnya.app",
        password: "secret123",
        displayName: "История Дерева",
      }),
    });
    assert.equal(registerResponse.status, 201);
    const registered = await registerResponse.json();
    const token = registered.accessToken;

    const createTreeResponse = await fetch(`${ctx.baseUrl}/v1/trees`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        name: "Дерево с историей",
        description: "Для relative gallery и history",
        isPrivate: true,
      }),
    });
    assert.equal(createTreeResponse.status, 201);
    const createdTree = await createTreeResponse.json();
    const treeId = createdTree.tree.id;

    const initialPersonsResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/persons`,
      {headers: {authorization: `Bearer ${token}`}},
    );
    assert.equal(initialPersonsResponse.status, 200);
    const initialPersonsPayload = await initialPersonsResponse.json();
    const creatorPersonId = initialPersonsPayload.persons[0].id;

    const createPersonResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/persons`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          firstName: "Анна",
          lastName: "Фотогеничная",
          gender: "female",
          photoUrl: "https://cdn.example.com/anna-primary.jpg",
        }),
      },
    );
    assert.equal(createPersonResponse.status, 201);
    const createdPersonPayload = await createPersonResponse.json();
    const personId = createdPersonPayload.person.id;
    assert.equal(
      createdPersonPayload.person.photoUrl,
      "https://cdn.example.com/anna-primary.jpg",
    );
    assert.equal(
      createdPersonPayload.person.primaryPhotoUrl,
      "https://cdn.example.com/anna-primary.jpg",
    );
    assert.equal(createdPersonPayload.person.photoGallery.length, 1);
    assert.equal(
      createdPersonPayload.person.photoGallery[0].isPrimary,
      true,
    );

    const addMediaResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/persons/${personId}/media`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          url: "https://cdn.example.com/anna-gallery.jpg",
          caption: "Портрет в галерее",
          isPrimary: true,
        }),
      },
    );
    assert.equal(addMediaResponse.status, 201);
    const addMediaPayload = await addMediaResponse.json();
    assert.equal(
      addMediaPayload.person.primaryPhotoUrl,
      "https://cdn.example.com/anna-gallery.jpg",
    );
    assert.equal(addMediaPayload.person.photoGallery.length, 2);
    assert.equal(addMediaPayload.media.url, "https://cdn.example.com/anna-gallery.jpg");
    const mediaId = addMediaPayload.media.id;

    const updateMediaResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/persons/${personId}/media/${mediaId}`,
      {
        method: "PATCH",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          url: "https://cdn.example.com/anna-gallery-updated.jpg",
          isPrimary: true,
          caption: "Обновлённый портрет",
        }),
      },
    );
    assert.equal(updateMediaResponse.status, 200);
    const updateMediaPayload = await updateMediaResponse.json();
    assert.equal(
      updateMediaPayload.person.photoUrl,
      "https://cdn.example.com/anna-gallery-updated.jpg",
    );
    assert.equal(
      updateMediaPayload.media.url,
      "https://cdn.example.com/anna-gallery-updated.jpg",
    );

    const createRelationResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/relations`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          person1Id: creatorPersonId,
          person2Id: personId,
          relation1to2: "sibling",
          isConfirmed: true,
        }),
      },
    );
    assert.equal(createRelationResponse.status, 201);
    const createdRelationPayload = await createRelationResponse.json();
    const relationId = createdRelationPayload.relation.id;

    const deleteRelationResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/relations/${relationId}`,
      {
        method: "DELETE",
        headers: {authorization: `Bearer ${token}`},
      },
    );
    assert.equal(deleteRelationResponse.status, 204);

    const deleteMediaResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/persons/${personId}/media/${mediaId}`,
      {
        method: "DELETE",
        headers: {authorization: `Bearer ${token}`},
      },
    );
    assert.equal(deleteMediaResponse.status, 200);
    const deleteMediaPayload = await deleteMediaResponse.json();
    assert.equal(deleteMediaPayload.deletedMediaId, mediaId);
    assert.equal(deleteMediaPayload.person.photoGallery.length, 1);
    assert.equal(
      deleteMediaPayload.person.primaryPhotoUrl,
      "https://cdn.example.com/anna-primary.jpg",
    );

    const historyResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/history?personId=${personId}`,
      {
        headers: {authorization: `Bearer ${token}`},
      },
    );
    assert.equal(historyResponse.status, 200);
    const historyPayload = await historyResponse.json();
    const historyTypes = historyPayload.records.map((record) => record.type);
    assert.ok(historyTypes.includes("person.created"));
    assert.ok(historyTypes.includes("person_media.created"));
    assert.ok(historyTypes.includes("person_media.updated"));
    assert.ok(historyTypes.includes("person_media.deleted"));
    assert.ok(historyTypes.includes("relation.created"));
    assert.ok(historyTypes.includes("relation.deleted"));

    const filteredHistoryResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/history?type=person_media.deleted`,
      {
        headers: {authorization: `Bearer ${token}`},
      },
    );
    assert.equal(filteredHistoryResponse.status, 200);
    const filteredHistoryPayload = await filteredHistoryResponse.json();
    assert.equal(filteredHistoryPayload.records.length, 1);
    assert.equal(filteredHistoryPayload.records[0].mediaId, mediaId);
  } finally {
    await stopTestServer(ctx);
  }
});

test("relation endpoints persist marriage and divorce dates", async () => {
  const ctx = await startTestServer();

  try {
    const registerResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "relations-dates@rodnya.app",
        password: "secret123",
        displayName: "Relation Dates",
      }),
    });
    assert.equal(registerResponse.status, 201);
    const registered = await registerResponse.json();
    const token = registered.accessToken;

    const createTreeResponse = await fetch(`${ctx.baseUrl}/v1/trees`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        name: "Даты брака",
        description: "Проверка дат в relation",
        isPrivate: true,
      }),
    });
    assert.equal(createTreeResponse.status, 201);
    const createdTreePayload = await createTreeResponse.json();
    const treeId = createdTreePayload.tree.id;

    const personsResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/persons`,
      {
        headers: {authorization: `Bearer ${token}`},
      },
    );
    assert.equal(personsResponse.status, 200);
    const initialPersonsPayload = await personsResponse.json();
    const creatorPersonId = initialPersonsPayload.persons[0].id;

    const spouseResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/persons`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          firstName: "Анна",
          lastName: "Смирнова",
          gender: "female",
        }),
      },
    );
    assert.equal(spouseResponse.status, 201);
    const spousePayload = await spouseResponse.json();
    const spousePersonId = spousePayload.person.id;

    const createRelationResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/relations`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          person1Id: creatorPersonId,
          person2Id: spousePersonId,
          relation1to2: "spouse",
          marriageDate: "2014-07-12T00:00:00.000Z",
          divorceDate: "2020-02-10T00:00:00.000Z",
          isConfirmed: true,
        }),
      },
    );
    assert.equal(createRelationResponse.status, 201);
    const createdRelationPayload = await createRelationResponse.json();
    assert.equal(
      createdRelationPayload.relation.marriageDate,
      "2014-07-12T00:00:00.000Z",
    );
    assert.equal(
      createdRelationPayload.relation.divorceDate,
      "2020-02-10T00:00:00.000Z",
    );

    const listRelationsResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/relations`,
      {
        headers: {authorization: `Bearer ${token}`},
      },
    );
    assert.equal(listRelationsResponse.status, 200);
    const listedRelationsPayload = await listRelationsResponse.json();
    assert.equal(listedRelationsPayload.relations.length, 1);
    assert.equal(
      listedRelationsPayload.relations[0].marriageDate,
      "2014-07-12T00:00:00.000Z",
    );
    assert.equal(
      listedRelationsPayload.relations[0].divorceDate,
      "2020-02-10T00:00:00.000Z",
    );
  } finally {
    await stopTestServer(ctx);
  }
});

test("public tree endpoints expose read-only tree data without auth", async () => {
  const ctx = await startTestServer();

  try {
    const registerResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "public-tree@rodnya.app",
        password: "secret123",
        displayName: "Публичный Автор",
      }),
    });
    assert.equal(registerResponse.status, 201);
    const registered = await registerResponse.json();
    const token = registered.accessToken;

    const createTreeResponse = await fetch(`${ctx.baseUrl}/v1/trees`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        name: "Открытое дерево",
        description: "Дерево для публичного просмотра",
        isPrivate: false,
      }),
    });
    assert.equal(createTreeResponse.status, 201);
    const createdTreePayload = await createTreeResponse.json();
    const treeId = createdTreePayload.tree.id;

    const initialPersonsResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/persons`,
      {headers: {authorization: `Bearer ${token}`}},
    );
    assert.equal(initialPersonsResponse.status, 200);
    const initialPersonsPayload = await initialPersonsResponse.json();
    const creatorPersonId = initialPersonsPayload.persons[0].id;

    const createPersonResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/persons`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          firstName: "Анна",
          lastName: "Публичная",
          gender: "female",
        }),
      },
    );
    assert.equal(createPersonResponse.status, 201);
    const createdPersonPayload = await createPersonResponse.json();
    const secondPersonId = createdPersonPayload.person.id;

    const relationResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/relations`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          person1Id: creatorPersonId,
          person2Id: secondPersonId,
          relation1to2: "sibling",
          isConfirmed: true,
        }),
      },
    );
    assert.equal(relationResponse.status, 201);

    const previewResponse = await fetch(
      `${ctx.baseUrl}/v1/public/trees/${treeId}`,
    );
    assert.equal(previewResponse.status, 200);
    const previewPayload = await previewResponse.json();
    assert.equal(previewPayload.tree.name, "Открытое дерево");
    assert.equal(previewPayload.tree.isPrivate, false);
    assert.equal(previewPayload.stats.peopleCount, 2);
    assert.equal(previewPayload.stats.relationsCount, 1);

    const personsResponse = await fetch(
      `${ctx.baseUrl}/v1/public/trees/${treeId}/persons`,
    );
    assert.equal(personsResponse.status, 200);
    const personsPayload = await personsResponse.json();
    assert.equal(personsPayload.persons.length, 2);

    const relationsResponse = await fetch(
      `${ctx.baseUrl}/v1/public/trees/${treeId}/relations`,
    );
    assert.equal(relationsResponse.status, 200);
    const relationsPayload = await relationsResponse.json();
    assert.equal(relationsPayload.relations.length, 1);

    const privatePreviewResponse = await fetch(
      `${ctx.baseUrl}/v1/public/trees/missing-tree`,
    );
    assert.equal(privatePreviewResponse.status, 404);
  } finally {
    await stopTestServer(ctx);
  }
});

test("tree delete removes owned trees and lets members leave invited trees", async () => {
  const ctx = await startTestServer();

  try {
    const ownerResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "tree-delete-owner@rodnya.app",
        password: "secret123",
        displayName: "Tree Delete Owner",
      }),
    });
    assert.equal(ownerResponse.status, 201);
    const owner = await ownerResponse.json();

    const inviteeResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "tree-delete-member@rodnya.app",
        password: "secret123",
        displayName: "Tree Delete Member",
      }),
    });
    assert.equal(inviteeResponse.status, 201);
    const invitee = await inviteeResponse.json();

    const createOwnedTreeResponse = await fetch(`${ctx.baseUrl}/v1/trees`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${owner.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        name: "Удаляемое дерево",
        description: "Будет удалено создателем",
        isPrivate: true,
      }),
    });
    assert.equal(createOwnedTreeResponse.status, 201);
    const ownedTreePayload = await createOwnedTreeResponse.json();
    const ownedTreeId = ownedTreePayload.tree.id;

    const createSharedTreeResponse = await fetch(`${ctx.baseUrl}/v1/trees`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${owner.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        name: "Общее дерево",
        description: "Из него участник выйдет",
        isPrivate: true,
      }),
    });
    assert.equal(createSharedTreeResponse.status, 201);
    const sharedTreePayload = await createSharedTreeResponse.json();
    const sharedTreeId = sharedTreePayload.tree.id;

    const createInvitationResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${sharedTreeId}/invitations`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${owner.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          recipientUserId: invitee.user.id,
          relationToTree: "родственник",
        }),
      },
    );
    assert.equal(createInvitationResponse.status, 201);
    const createdInvitation = await createInvitationResponse.json();

    const acceptInvitationResponse = await fetch(
      `${ctx.baseUrl}/v1/tree-invitations/${createdInvitation.invitation.invitationId}/respond`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${invitee.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({accept: true}),
      },
    );
    assert.equal(acceptInvitationResponse.status, 200);

    const leaveTreeResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${sharedTreeId}`,
      {
        method: "DELETE",
        headers: {
          authorization: `Bearer ${invitee.accessToken}`,
        },
      },
    );
    assert.equal(leaveTreeResponse.status, 200);
    const leavePayload = await leaveTreeResponse.json();
    assert.equal(leavePayload.action, "left");

    const inviteeTreesAfterLeaveResponse = await fetch(`${ctx.baseUrl}/v1/trees`, {
      headers: {authorization: `Bearer ${invitee.accessToken}`},
    });
    assert.equal(inviteeTreesAfterLeaveResponse.status, 200);
    const inviteeTreesAfterLeave = await inviteeTreesAfterLeaveResponse.json();
    assert.equal(inviteeTreesAfterLeave.trees.length, 0);

    const ownerSharedTreePersonsResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${sharedTreeId}/persons`,
      {
        headers: {authorization: `Bearer ${owner.accessToken}`},
      },
    );
    assert.equal(ownerSharedTreePersonsResponse.status, 200);
    const ownerSharedTreePersons = await ownerSharedTreePersonsResponse.json();
    assert.equal(
      ownerSharedTreePersons.persons.some(
        (person) => person.userId === invitee.user.id,
      ),
      false,
    );

    const deleteOwnedTreeResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${ownedTreeId}`,
      {
        method: "DELETE",
        headers: {
          authorization: `Bearer ${owner.accessToken}`,
        },
      },
    );
    assert.equal(deleteOwnedTreeResponse.status, 200);
    const deletePayload = await deleteOwnedTreeResponse.json();
    assert.equal(deletePayload.action, "deleted");

    const ownerTreesAfterDeleteResponse = await fetch(`${ctx.baseUrl}/v1/trees`, {
      headers: {authorization: `Bearer ${owner.accessToken}`},
    });
    assert.equal(ownerTreesAfterDeleteResponse.status, 200);
    const ownerTreesAfterDelete = await ownerTreesAfterDeleteResponse.json();
    assert.equal(ownerTreesAfterDelete.trees.length, 1);
    assert.equal(ownerTreesAfterDelete.trees[0].id, sharedTreeId);

    const deletedTreePersonsResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${ownedTreeId}/persons`,
      {
        headers: {authorization: `Bearer ${owner.accessToken}`},
      },
    );
    assert.equal(deletedTreePersonsResponse.status, 404);
  } finally {
    await stopTestServer(ctx);
  }
});

test("post endpoints cover feed, likes and comments", async () => {
  const ctx = await startTestServer();

  try {
    const aliceResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "posts-alice@rodnya.app",
        password: "secret123",
        displayName: "Alice Posts",
      }),
    });
    assert.equal(aliceResponse.status, 201);
    const alice = await aliceResponse.json();

    const bobResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "posts-bob@rodnya.app",
        password: "secret123",
        displayName: "Bob Posts",
      }),
    });
    assert.equal(bobResponse.status, 201);
    const bob = await bobResponse.json();

    const treeResponse = await fetch(`${ctx.baseUrl}/v1/trees`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${alice.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        name: "Семья Постовых",
        description: "Тестовое дерево для ленты",
      }),
    });
    assert.equal(treeResponse.status, 201);
    const treePayload = await treeResponse.json();
    const treeId = treePayload.tree.id;

    const inviteResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/invitations`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${alice.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          recipientUserId: bob.user.id,
          relationToTree: "Родственник",
        }),
      },
    );
    assert.equal(inviteResponse.status, 201);
    const invitationPayload = await inviteResponse.json();

    const acceptInviteResponse = await fetch(
      `${ctx.baseUrl}/v1/tree-invitations/${invitationPayload.invitation.invitationId}/respond`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${bob.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({accept: true}),
      },
    );
    assert.equal(acceptInviteResponse.status, 200);

    const createPostResponse = await fetch(`${ctx.baseUrl}/v1/posts`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${alice.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        treeId,
        content: "Первая новость семьи",
        imageUrls: ["https://cdn.example.test/family-photo.jpg"],
        scopeType: "wholeTree",
      }),
    });
    assert.equal(createPostResponse.status, 201);
    const createdPost = await createPostResponse.json();
    assert.equal(createdPost.treeId, treeId);
    assert.equal(createdPost.commentCount, 0);
    assert.deepEqual(createdPost.likedBy, []);

    const treeFeedResponse = await fetch(`${ctx.baseUrl}/v1/posts?treeId=${treeId}`, {
      headers: {authorization: `Bearer ${bob.accessToken}`},
    });
    assert.equal(treeFeedResponse.status, 200);
    const treeFeed = await treeFeedResponse.json();
    assert.equal(treeFeed.length, 1);
    assert.equal(treeFeed[0].authorId, alice.user.id);

    const likeResponse = await fetch(
      `${ctx.baseUrl}/v1/posts/${createdPost.id}/like`,
      {
        method: "POST",
        headers: {authorization: `Bearer ${bob.accessToken}`},
      },
    );
    assert.equal(likeResponse.status, 200);
    const likedPost = await likeResponse.json();
    assert.deepEqual(likedPost.likedBy, [bob.user.id]);

    const likeWithNullBodyResponse = await fetch(
      `${ctx.baseUrl}/v1/posts/${createdPost.id}/like`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${bob.accessToken}`,
          "content-type": "application/json",
        },
        body: "null",
      },
    );
    assert.equal(likeWithNullBodyResponse.status, 200);
    const likeWithNullBodyPayload = await likeWithNullBodyResponse.json();
    assert.deepEqual(likeWithNullBodyPayload.likedBy, []);

    const addCommentResponse = await fetch(
      `${ctx.baseUrl}/v1/posts/${createdPost.id}/comments`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${bob.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({content: "Поздравляю!"}),
      },
    );
    assert.equal(addCommentResponse.status, 201);
    const createdComment = await addCommentResponse.json();
    assert.equal(createdComment.postId, createdPost.id);
    assert.equal(createdComment.authorId, bob.user.id);

    const commentsResponse = await fetch(
      `${ctx.baseUrl}/v1/posts/${createdPost.id}/comments`,
      {
        headers: {authorization: `Bearer ${alice.accessToken}`},
      },
    );
    assert.equal(commentsResponse.status, 200);
    const comments = await commentsResponse.json();
    assert.equal(comments.length, 1);
    assert.equal(comments[0].content, "Поздравляю!");

    const authorFeedResponse = await fetch(
      `${ctx.baseUrl}/v1/posts?authorId=${alice.user.id}`,
      {
        headers: {authorization: `Bearer ${bob.accessToken}`},
      },
    );
    assert.equal(authorFeedResponse.status, 200);
    const authorFeed = await authorFeedResponse.json();
    assert.equal(authorFeed.length, 1);
    assert.equal(authorFeed[0].commentCount, 1);

    const deleteCommentResponse = await fetch(
      `${ctx.baseUrl}/v1/posts/${createdPost.id}/comments/${createdComment.id}`,
      {
        method: "DELETE",
        headers: {authorization: `Bearer ${alice.accessToken}`},
      },
    );
    assert.equal(deleteCommentResponse.status, 204);

    const deletePostResponse = await fetch(
      `${ctx.baseUrl}/v1/posts/${createdPost.id}`,
      {
        method: "DELETE",
        headers: {authorization: `Bearer ${alice.accessToken}`},
      },
    );
    assert.equal(deletePostResponse.status, 204);

    const feedAfterDeleteResponse = await fetch(
      `${ctx.baseUrl}/v1/posts?treeId=${treeId}`,
      {
        headers: {authorization: `Bearer ${alice.accessToken}`},
      },
    );
    assert.equal(feedAfterDeleteResponse.status, 200);
    const feedAfterDelete = await feedAfterDeleteResponse.json();
    assert.equal(feedAfterDelete.length, 0);
  } finally {
    await stopTestServer(ctx);
  }
});

test("story endpoints support create, view, expiry and delete", async () => {
  const ctx = await startTestServer();

  try {
    const aliceResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "stories-alice@rodnya.app",
        password: "secret123",
        displayName: "Alice Stories",
      }),
    });
    assert.equal(aliceResponse.status, 201);
    const alice = await aliceResponse.json();

    const bobResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "stories-bob@rodnya.app",
        password: "secret123",
        displayName: "Bob Stories",
      }),
    });
    assert.equal(bobResponse.status, 201);
    const bob = await bobResponse.json();

    const treeResponse = await fetch(`${ctx.baseUrl}/v1/trees`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${alice.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        name: "Семья Историй",
        description: "Тестовое дерево для stories",
      }),
    });
    assert.equal(treeResponse.status, 201);
    const treePayload = await treeResponse.json();
    const treeId = treePayload.tree.id;

    const inviteResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/invitations`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${alice.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          recipientUserId: bob.user.id,
          relationToTree: "Родственник",
        }),
      },
    );
    assert.equal(inviteResponse.status, 201);
    const invitationPayload = await inviteResponse.json();

    const acceptInviteResponse = await fetch(
      `${ctx.baseUrl}/v1/tree-invitations/${invitationPayload.invitation.invitationId}/respond`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${bob.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({accept: true}),
      },
    );
    assert.equal(acceptInviteResponse.status, 200);

    const createStoryResponse = await fetch(`${ctx.baseUrl}/v1/stories`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${alice.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        treeId,
        type: "text",
        text: "Доброе утро, семья",
      }),
    });
    assert.equal(createStoryResponse.status, 201);
    const createdStory = await createStoryResponse.json();
    assert.equal(createdStory.treeId, treeId);
    assert.equal(createdStory.type, "text");
    assert.deepEqual(createdStory.viewedBy, []);

    const expiredStoryResponse = await fetch(`${ctx.baseUrl}/v1/stories`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${alice.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        treeId,
        type: "text",
        text: "Старая история",
        expiresAt: "2020-01-01T00:00:00.000Z",
      }),
    });
    assert.equal(expiredStoryResponse.status, 201);

    const treeStoriesResponse = await fetch(
      `${ctx.baseUrl}/v1/stories?treeId=${treeId}`,
      {
        headers: {authorization: `Bearer ${bob.accessToken}`},
      },
    );
    assert.equal(treeStoriesResponse.status, 200);
    const treeStories = await treeStoriesResponse.json();
    assert.equal(treeStories.length, 1);
    assert.equal(treeStories[0].id, createdStory.id);

    const viewStoryResponse = await fetch(
      `${ctx.baseUrl}/v1/stories/${createdStory.id}/view`,
      {
        method: "POST",
        headers: {authorization: `Bearer ${bob.accessToken}`},
      },
    );
    assert.equal(viewStoryResponse.status, 200);
    const viewedStory = await viewStoryResponse.json();
    assert.deepEqual(viewedStory.viewedBy, [bob.user.id]);

    const authorViewStoryResponse = await fetch(
      `${ctx.baseUrl}/v1/stories/${createdStory.id}/view`,
      {
        method: "POST",
        headers: {authorization: `Bearer ${alice.accessToken}`},
      },
    );
    assert.equal(authorViewStoryResponse.status, 200);
    const authorViewedStory = await authorViewStoryResponse.json();
    assert.deepEqual(authorViewedStory.viewedBy, [bob.user.id]);

    const authorStoriesResponse = await fetch(
      `${ctx.baseUrl}/v1/stories?treeId=${treeId}&authorId=${alice.user.id}`,
      {
        headers: {authorization: `Bearer ${bob.accessToken}`},
      },
    );
    assert.equal(authorStoriesResponse.status, 200);
    const authorStories = await authorStoriesResponse.json();
    assert.equal(authorStories.length, 1);
    assert.deepEqual(authorStories[0].viewedBy, [bob.user.id]);

    const deleteStoryResponse = await fetch(
      `${ctx.baseUrl}/v1/stories/${createdStory.id}`,
      {
        method: "DELETE",
        headers: {authorization: `Bearer ${alice.accessToken}`},
      },
    );
    assert.equal(deleteStoryResponse.status, 204);

    const storiesAfterDeleteResponse = await fetch(
      `${ctx.baseUrl}/v1/stories?treeId=${treeId}`,
      {
        headers: {authorization: `Bearer ${alice.accessToken}`},
      },
    );
    assert.equal(storiesAfterDeleteResponse.status, 200);
    const storiesAfterDelete = await storiesAfterDeleteResponse.json();
    assert.equal(storiesAfterDelete.length, 0);
  } finally {
    await stopTestServer(ctx);
  }
});

test("chat endpoints cover preview list, history, send and mark as read", async () => {
  const ctx = await startTestServer();

  try {
    const registerAliceResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "alice@rodnya.app",
        password: "secret123",
        displayName: "Alice",
      }),
    });
    assert.equal(registerAliceResponse.status, 201);
    const alice = await registerAliceResponse.json();

    const registerBobResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "bob@rodnya.app",
        password: "secret123",
        displayName: "Bob",
      }),
    });
    assert.equal(registerBobResponse.status, 201);
    const bob = await registerBobResponse.json();

    const createChatResponse = await fetch(`${ctx.baseUrl}/v1/chats/direct`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${alice.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({otherUserId: bob.user.id}),
    });
    assert.equal(createChatResponse.status, 200);
    const directChat = await createChatResponse.json();
    assert.ok(directChat.chatId);

    const sendMessageResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${directChat.chatId}/messages`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${alice.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({text: "Привет, Боб!"}),
      },
    );
    assert.equal(sendMessageResponse.status, 201);
    const sentMessagePayload = await sendMessageResponse.json();
    assert.equal(sentMessagePayload.message.text, "Привет, Боб!");

    const aliceChatsResponse = await fetch(`${ctx.baseUrl}/v1/chats`, {
      headers: {authorization: `Bearer ${alice.accessToken}`},
    });
    assert.equal(aliceChatsResponse.status, 200);
    const aliceChats = await aliceChatsResponse.json();
    assert.equal(aliceChats.chats.length, 1);
    assert.equal(aliceChats.chats[0].otherUserId, bob.user.id);
    assert.equal(aliceChats.chats[0].unreadCount, 0);

    const bobChatsResponse = await fetch(`${ctx.baseUrl}/v1/chats`, {
      headers: {authorization: `Bearer ${bob.accessToken}`},
    });
    assert.equal(bobChatsResponse.status, 200);
    const bobChats = await bobChatsResponse.json();
    assert.equal(bobChats.chats.length, 1);
    assert.equal(bobChats.chats[0].unreadCount, 1);

    const unreadResponse = await fetch(`${ctx.baseUrl}/v1/chats/unread-count`, {
      headers: {authorization: `Bearer ${bob.accessToken}`},
    });
    assert.equal(unreadResponse.status, 200);
    const unreadPayload = await unreadResponse.json();
    assert.equal(unreadPayload.totalUnread, 1);

    const historyResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${directChat.chatId}/messages`,
      {
        headers: {authorization: `Bearer ${bob.accessToken}`},
      },
    );
    assert.equal(historyResponse.status, 200);
    const historyPayload = await historyResponse.json();
    assert.equal(historyPayload.messages.length, 1);
    assert.equal(historyPayload.messages[0].senderId, alice.user.id);

    const markReadResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${directChat.chatId}/read`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${bob.accessToken}`,
          "content-type": "application/json",
        },
        body: "{}",
      },
    );
    assert.equal(markReadResponse.status, 200);

    const unreadAfterReadResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/unread-count`,
      {
        headers: {authorization: `Bearer ${bob.accessToken}`},
      },
    );
    assert.equal(unreadAfterReadResponse.status, 200);
    const unreadAfterReadPayload = await unreadAfterReadResponse.json();
    assert.equal(unreadAfterReadPayload.totalUnread, 0);
  } finally {
    await stopTestServer(ctx);
  }
});

test("group chat endpoints create previews before first message and keep media payload", async () => {
  const ctx = await startTestServer();

  try {
    const aliceResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "group-alice@rodnya.app",
        password: "secret123",
        displayName: "Alice Group",
      }),
    });
    assert.equal(aliceResponse.status, 201);
    const alice = await aliceResponse.json();

    const bobResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "group-bob@rodnya.app",
        password: "secret123",
        displayName: "Bob Group",
      }),
    });
    assert.equal(bobResponse.status, 201);
    const bob = await bobResponse.json();

    const caraResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "group-cara@rodnya.app",
        password: "secret123",
        displayName: "Cara Group",
      }),
    });
    assert.equal(caraResponse.status, 201);
    const cara = await caraResponse.json();

    const createGroupResponse = await fetch(`${ctx.baseUrl}/v1/chats/groups`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${alice.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        title: "Семья Кузнецовых",
        participantIds: [bob.user.id, cara.user.id],
      }),
    });
    assert.equal(createGroupResponse.status, 201);
    const createdGroupPayload = await createGroupResponse.json();
    assert.equal(createdGroupPayload.chat.type, "group");
    assert.equal(createdGroupPayload.chat.title, "Семья Кузнецовых");

    const bobChatsResponse = await fetch(`${ctx.baseUrl}/v1/chats`, {
      headers: {authorization: `Bearer ${bob.accessToken}`},
    });
    assert.equal(bobChatsResponse.status, 200);
    const bobChatsPayload = await bobChatsResponse.json();
    assert.equal(bobChatsPayload.chats.length, 1);
    assert.equal(bobChatsPayload.chats[0].type, "group");
    assert.equal(bobChatsPayload.chats[0].title, "Семья Кузнецовых");
    assert.equal(bobChatsPayload.chats[0].lastMessage, "");

    const sendMessageResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${createdGroupPayload.chatId}/messages`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${alice.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          attachments: [
            {
              type: "image",
              url: "https://cdn.example.test/photo-1.jpg",
              mimeType: "image/jpeg",
              fileName: "photo-1.jpg",
              sizeBytes: 2048,
            },
          ],
          mediaUrls: ["https://cdn.example.test/photo-1.jpg"],
          imageUrl: "https://cdn.example.test/photo-1.jpg",
        }),
      },
    );
    assert.equal(sendMessageResponse.status, 201);
    const sentMessagePayload = await sendMessageResponse.json();
    assert.deepEqual(sentMessagePayload.message.mediaUrls, [
      "https://cdn.example.test/photo-1.jpg",
    ]);
    assert.equal(sentMessagePayload.message.attachments.length, 1);
    assert.equal(sentMessagePayload.message.attachments[0].type, "image");

    const historyResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${createdGroupPayload.chatId}/messages`,
      {
        headers: {authorization: `Bearer ${cara.accessToken}`},
      },
    );
    assert.equal(historyResponse.status, 200);
    const historyPayload = await historyResponse.json();
    assert.equal(historyPayload.chat.type, "group");
    assert.equal(historyPayload.messages.length, 1);
    assert.equal(historyPayload.messages[0].imageUrl, "https://cdn.example.test/photo-1.jpg");
    assert.equal(historyPayload.messages[0].attachments.length, 1);
    assert.equal(historyPayload.messages[0].attachments[0].fileName, "photo-1.jpg");

    const unreadResponse = await fetch(`${ctx.baseUrl}/v1/chats/unread-count`, {
      headers: {authorization: `Bearer ${bob.accessToken}`},
    });
    assert.equal(unreadResponse.status, 200);
    const unreadPayload = await unreadResponse.json();
    assert.equal(unreadPayload.totalUnread, 1);
  } finally {
    await stopTestServer(ctx);
  }
});

test("direct chat details accept reversed participant order and return canonical chat id", async () => {
  const ctx = await startTestServer();

  try {
    const register = async (email, displayName) => {
      const response = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({
          email,
          password: "secret123",
          displayName,
        }),
      });
      assert.equal(response.status, 201);
      return response.json();
    };

    const alice = await register("direct-details-alice@rodnya.app", "Alice");
    const bob = await register("direct-details-bob@rodnya.app", "Bob");

    const createChatResponse = await fetch(`${ctx.baseUrl}/v1/chats/direct`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${alice.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({otherUserId: bob.user.id}),
    });
    assert.equal(createChatResponse.status, 200);
    const createdChat = await createChatResponse.json();
    assert.equal(
      createdChat.chatId,
      [alice.user.id, bob.user.id].sort().join("_"),
    );

    const detailsResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${bob.user.id}_${alice.user.id}`,
      {
        headers: {authorization: `Bearer ${bob.accessToken}`},
      },
    );
    assert.equal(detailsResponse.status, 200);
    const detailsPayload = await detailsResponse.json();
    assert.equal(detailsPayload.chat.id, createdChat.chatId);
    assert.equal(detailsPayload.chat.type, "direct");
    assert.equal(detailsPayload.participants.length, 2);
  } finally {
    await stopTestServer(ctx);
  }
});

test("chat message edit and delete endpoints enforce ownership", async () => {
  const ctx = await startTestServer();

  try {
    const registerAliceResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "edit-alice@rodnya.app",
        password: "secret123",
        displayName: "Alice Edit",
      }),
    });
    assert.equal(registerAliceResponse.status, 201);
    const alice = await registerAliceResponse.json();

    const registerBobResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "edit-bob@rodnya.app",
        password: "secret123",
        displayName: "Bob Edit",
      }),
    });
    assert.equal(registerBobResponse.status, 201);
    const bob = await registerBobResponse.json();

    const createChatResponse = await fetch(`${ctx.baseUrl}/v1/chats/direct`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${alice.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({otherUserId: bob.user.id}),
    });
    assert.equal(createChatResponse.status, 200);
    const directChat = await createChatResponse.json();

    const sendMessageResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${directChat.chatId}/messages`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${alice.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({text: "Исходный текст"}),
      },
    );
    assert.equal(sendMessageResponse.status, 201);
    const sentMessagePayload = await sendMessageResponse.json();
    const messageId = sentMessagePayload.message.id;

    const editByOwnerResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${directChat.chatId}/messages/${messageId}`,
      {
        method: "PATCH",
        headers: {
          authorization: `Bearer ${alice.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({text: "Обновленный текст"}),
      },
    );
    assert.equal(editByOwnerResponse.status, 200);
    const editedPayload = await editByOwnerResponse.json();
    assert.equal(editedPayload.message.text, "Обновленный текст");

    const editByOtherResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${directChat.chatId}/messages/${messageId}`,
      {
        method: "PATCH",
        headers: {
          authorization: `Bearer ${bob.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({text: "Чужое редактирование"}),
      },
    );
    assert.equal(editByOtherResponse.status, 403);

    const deleteByOtherResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${directChat.chatId}/messages/${messageId}`,
      {
        method: "DELETE",
        headers: {
          authorization: `Bearer ${bob.accessToken}`,
        },
      },
    );
    assert.equal(deleteByOtherResponse.status, 403);

    const deleteByOwnerResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${directChat.chatId}/messages/${messageId}`,
      {
        method: "DELETE",
        headers: {
          authorization: `Bearer ${alice.accessToken}`,
        },
      },
    );
    assert.equal(deleteByOwnerResponse.status, 200);
    const deletePayload = await deleteByOwnerResponse.json();
    assert.equal(deletePayload.messageId, messageId);

    const historyResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${directChat.chatId}/messages`,
      {
        headers: {authorization: `Bearer ${alice.accessToken}`},
      },
    );
    assert.equal(historyResponse.status, 200);
    const historyPayload = await historyResponse.json();
    assert.equal(historyPayload.messages.length, 0);
  } finally {
    await stopTestServer(ctx);
  }
});

test("group chat details and participant management work for ordinary groups", async () => {
  const ctx = await startTestServer();

  try {
    const register = async (email, displayName) => {
      const response = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({
          email,
          password: "secret123",
          displayName,
        }),
      });
      assert.equal(response.status, 201);
      return response.json();
    };

    const alice = await register("group-details-alice@rodnya.app", "Alice");
    const bob = await register("group-details-bob@rodnya.app", "Bob");
    const cara = await register("group-details-cara@rodnya.app", "Cara");
    const dan = await register("group-details-dan@rodnya.app", "Dan");

    const createResponse = await fetch(`${ctx.baseUrl}/v1/chats/groups`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${alice.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        title: "Семейный совет",
        participantIds: [bob.user.id, cara.user.id],
      }),
    });
    assert.equal(createResponse.status, 201);
    const createdPayload = await createResponse.json();

    const detailsResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${createdPayload.chatId}`,
      {
        headers: {authorization: `Bearer ${bob.accessToken}`},
      },
    );
    assert.equal(detailsResponse.status, 200);
    const detailsPayload = await detailsResponse.json();
    assert.equal(detailsPayload.chat.type, "group");
    assert.equal(detailsPayload.chat.title, "Семейный совет");
    assert.equal(detailsPayload.participants.length, 3);

    const renameResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${createdPayload.chatId}`,
      {
        method: "PATCH",
        headers: {
          authorization: `Bearer ${alice.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({title: "Совет семьи"}),
      },
    );
    assert.equal(renameResponse.status, 200);
    const renamedPayload = await renameResponse.json();
    assert.equal(renamedPayload.chat.title, "Совет семьи");

    const addParticipantResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${createdPayload.chatId}/participants`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${alice.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({participantIds: [dan.user.id]}),
      },
    );
    assert.equal(addParticipantResponse.status, 200);
    const expandedPayload = await addParticipantResponse.json();
    assert.equal(expandedPayload.participants.length, 4);
    assert.ok(
      expandedPayload.participants.some((participant) => participant.userId === dan.user.id),
    );

    const removeParticipantResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${createdPayload.chatId}/participants/${cara.user.id}`,
      {
        method: "DELETE",
        headers: {
          authorization: `Bearer ${alice.accessToken}`,
        },
      },
    );
    assert.equal(removeParticipantResponse.status, 200);
    const reducedPayload = await removeParticipantResponse.json();
    assert.equal(reducedPayload.participants.length, 3);
    assert.ok(
      reducedPayload.participants.every((participant) => participant.userId !== cara.user.id),
    );
  } finally {
    await stopTestServer(ctx);
  }
});

test("tree graph snapshot syncs profile fields and normalizes family units", async () => {
  const ctx = await startTestServer();

  try {
    const aliceResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "graph-alice@rodnya.app",
        password: "secret123",
        displayName: "Артем Кузнецов",
      }),
    });
    assert.equal(aliceResponse.status, 201);
    const alice = await aliceResponse.json();

    const bobResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "graph-bob@rodnya.app",
        password: "secret123",
        displayName: "Анастасия Шульяк",
      }),
    });
    assert.equal(bobResponse.status, 201);
    const bob = await bobResponse.json();

    const createTreeResponse = await fetch(`${ctx.baseUrl}/v1/trees`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${alice.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        name: "Семья Кузнецовых",
        description: "Проверка graph snapshot",
        isPrivate: true,
      }),
    });
    assert.equal(createTreeResponse.status, 201);
    const createdTreePayload = await createTreeResponse.json();
    const treeId = createdTreePayload.tree.id;

    const initialPersonsResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/persons`,
      {
        headers: {authorization: `Bearer ${alice.accessToken}`},
      },
    );
    assert.equal(initialPersonsResponse.status, 200);
    const initialPersonsPayload = await initialPersonsResponse.json();
    const alicePersonId = initialPersonsPayload.persons[0].id;

    const updateProfileResponse = await fetch(`${ctx.baseUrl}/v1/profile/me`, {
      method: "PATCH",
      headers: {
        authorization: `Bearer ${alice.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        firstName: "Артем",
        lastName: "Кузнецов",
        middleName: "Андреевич",
        displayName: "Кузнецов Артем Андреевич",
        photoUrl: "https://cdn.example.com/artem-profile.jpg",
        gender: "male",
      }),
    });
    assert.equal(updateProfileResponse.status, 200);

    const inviteResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/invitations`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${alice.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          recipientUserId: bob.user.id,
        }),
      },
    );
    assert.equal(inviteResponse.status, 201);
    const invitePayload = await inviteResponse.json();

    const acceptInviteResponse = await fetch(
      `${ctx.baseUrl}/v1/tree-invitations/${invitePayload.invitation.invitationId}/respond`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${bob.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({accept: true}),
      },
    );
    assert.equal(acceptInviteResponse.status, 200);

    const createPerson = async (token, payload) => {
      const response = await fetch(`${ctx.baseUrl}/v1/trees/${treeId}/persons`, {
        method: "POST",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify(payload),
      });
      assert.equal(response.status, 201);
      return (await response.json()).person;
    };

    const createRelation = async (token, payload) => {
      const response = await fetch(`${ctx.baseUrl}/v1/trees/${treeId}/relations`, {
        method: "POST",
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
        },
        body: JSON.stringify(payload),
      });
      assert.equal(response.status, 201);
      return (await response.json()).relation;
    };

    const father = await createPerson(alice.accessToken, {
      firstName: "Геннадий",
      lastName: "Мочалкин",
      gender: "male",
    });
    const mother = await createPerson(alice.accessToken, {
      firstName: "Лидия",
      lastName: "Мочалкина",
      gender: "female",
    });
    const sibling = await createPerson(alice.accessToken, {
      firstName: "Дарья",
      lastName: "Кузнецова",
      gender: "female",
    });
    const spouse = await createPerson(bob.accessToken, {
      firstName: "Анастасия",
      lastName: "Шульяк",
      gender: "female",
      userId: bob.user.id,
    });
    const child = await createPerson(alice.accessToken, {
      firstName: "Павел",
      lastName: "Кузнецов",
      gender: "male",
    });

    await createRelation(alice.accessToken, {
      person1Id: father.id,
      person2Id: alicePersonId,
      relation1to2: "parent",
      isConfirmed: true,
    });
    await createRelation(alice.accessToken, {
      person1Id: mother.id,
      person2Id: alicePersonId,
      relation1to2: "parent",
      isConfirmed: true,
    });
    await createRelation(alice.accessToken, {
      person1Id: sibling.id,
      person2Id: alicePersonId,
      relation1to2: "sibling",
      isConfirmed: true,
    });
    await createRelation(alice.accessToken, {
      person1Id: alicePersonId,
      person2Id: spouse.id,
      relation1to2: "spouse",
      isConfirmed: true,
    });
    await createRelation(alice.accessToken, {
      person1Id: child.id,
      person2Id: alicePersonId,
      relation1to2: "child",
      isConfirmed: true,
    });

    const relationsResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/relations`,
      {
        headers: {authorization: `Bearer ${alice.accessToken}`},
      },
    );
    assert.equal(relationsResponse.status, 200);
    const relationsPayload = await relationsResponse.json();
    const siblingParentRelations = relationsPayload.relations.filter((relation) => {
      return (
        relation.relation1to2 === "parent" &&
        relation.person2Id === sibling.id
      );
    });
    assert.equal(siblingParentRelations.length, 2);
    assert.equal(
      new Set(siblingParentRelations.map((relation) => relation.parentSetId)).size,
      1,
    );

    const childParentRelations = relationsPayload.relations.filter((relation) => {
      return (
        relation.parentSetType === "biological" &&
        ((relation.person1Id === child.id && relation.relation1to2 === "child") ||
          (relation.person2Id === child.id && relation.relation1to2 === "parent"))
      );
    });
    assert.equal(childParentRelations.length, 2);
    assert.ok(
      childParentRelations.some(
        (relation) =>
          relation.person1Id === spouse.id || relation.person2Id === spouse.id,
      ),
    );

    const graphResponse = await fetch(`${ctx.baseUrl}/v1/trees/${treeId}/graph`, {
      headers: {authorization: `Bearer ${alice.accessToken}`},
    });
    assert.equal(graphResponse.status, 200);
    const graphPayload = await graphResponse.json();
    assert.equal(graphPayload.snapshot.viewerPersonId, alicePersonId);

    const aliceGraphPerson = graphPayload.snapshot.people.find(
      (person) => person.id === alicePersonId,
    );
    assert.equal(aliceGraphPerson.name, "Кузнецов Артем Андреевич");
    assert.equal(
      aliceGraphPerson.photoUrl,
      "https://cdn.example.com/artem-profile.jpg",
    );

    const siblingDescriptor = graphPayload.snapshot.viewerDescriptors.find(
      (descriptor) => descriptor.personId === sibling.id,
    );
    assert.ok(
      siblingDescriptor.primaryRelationLabel.toLowerCase().includes("сестр"),
    );

    const spouseUnit = graphPayload.snapshot.familyUnits.find((unit) => {
      return (
        unit.adultIds.includes(alicePersonId) &&
        unit.adultIds.includes(spouse.id) &&
        unit.childIds.includes(child.id)
      );
    });
    assert.ok(spouseUnit);

    const generationRows = graphPayload.snapshot.generationRows;
    assert.ok(generationRows.length >= 3);
    assert.ok(
      generationRows.some((row) => row.personIds.includes(child.id)),
    );
    assert.ok(
      generationRows.some(
        (row) =>
          row.personIds.includes(father.id) && row.personIds.includes(mother.id),
      ),
    );

    const branchBlock = graphPayload.snapshot.branchBlocks.find((block) => {
      return (
        block.memberPersonIds.includes(alicePersonId) &&
        block.memberPersonIds.includes(spouse.id) &&
        block.memberPersonIds.includes(child.id)
      );
    });
    assert.ok(branchBlock);
  } finally {
    await stopTestServer(ctx);
  }
});

test("tree graph snapshot backfills linked profile photo for stale tree persons", async () => {
  const ctx = await startTestServer();

  try {
    const registerResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "graph-stale@rodnya.app",
        password: "secret123",
        displayName: "Артем Кузнецов",
      }),
    });
    assert.equal(registerResponse.status, 201);
    const registered = await registerResponse.json();

    const createTreeResponse = await fetch(`${ctx.baseUrl}/v1/trees`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${registered.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        name: "Семья Кузнецовых",
        description: "Проверка stale linked person",
        isPrivate: true,
      }),
    });
    assert.equal(createTreeResponse.status, 201);
    const createdTreePayload = await createTreeResponse.json();
    const treeId = createdTreePayload.tree.id;

    const personsResponse = await fetch(`${ctx.baseUrl}/v1/trees/${treeId}/persons`, {
      headers: {authorization: `Bearer ${registered.accessToken}`},
    });
    assert.equal(personsResponse.status, 200);
    const personsPayload = await personsResponse.json();
    const personId = personsPayload.persons[0].id;

    const snapshot = await ctx.store._read();
    const linkedPerson = snapshot.persons.find((entry) => entry.id === personId);
    const linkedUser = snapshot.users.find((entry) => entry.id === registered.user.id);
    assert.ok(linkedPerson);
    assert.ok(linkedUser);

    linkedPerson.name = "Кузнецов Артем";
    linkedPerson.photoUrl = null;
    linkedPerson.primaryPhotoUrl = null;
    linkedPerson.photoGallery = [];
    linkedUser.profile = {
      ...linkedUser.profile,
      firstName: "Артем",
      middleName: "Андреевич",
      lastName: "Кузнецов",
      displayName: "Артем Андреевич Кузнецов",
      photoUrl: "https://cdn.example.com/artem-read-sync.jpg",
      gender: "male",
    };
    await ctx.store._write(snapshot);

    const refreshedPersonsResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/persons`,
      {
        headers: {authorization: `Bearer ${registered.accessToken}`},
      },
    );
    assert.equal(refreshedPersonsResponse.status, 200);
    const refreshedPersonsPayload = await refreshedPersonsResponse.json();
    const refreshedPerson = refreshedPersonsPayload.persons.find(
      (entry) => entry.id === personId,
    );
    assert.equal(
      refreshedPerson.primaryPhotoUrl,
      "https://cdn.example.com/artem-read-sync.jpg",
    );
    assert.equal(
      refreshedPerson.name,
      "Кузнецов Артем Андреевич",
    );

    const graphResponse = await fetch(`${ctx.baseUrl}/v1/trees/${treeId}/graph`, {
      headers: {authorization: `Bearer ${registered.accessToken}`},
    });
    assert.equal(graphResponse.status, 200);
    const graphPayload = await graphResponse.json();
    const graphPerson = graphPayload.snapshot.people.find((entry) => entry.id === personId);
    assert.equal(
      graphPerson.primaryPhotoUrl,
      "https://cdn.example.com/artem-read-sync.jpg",
    );
    assert.equal(
      graphPerson.name,
      "Кузнецов Артем Андреевич",
    );
  } finally {
    await stopTestServer(ctx);
  }
});

test("tree graph snapshot infers detailed Russian in-law labels for the viewer", async () => {
  const ctx = await startTestServer();

  try {
    const viewerResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "graph-inlaw-viewer@rodnya.app",
        password: "secret123",
        displayName: "Артем Кузнецов",
      }),
    });
    assert.equal(viewerResponse.status, 201);
    const viewer = await viewerResponse.json();

    const createTreeResponse = await fetch(`${ctx.baseUrl}/v1/trees`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${viewer.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        name: "Семья для свойств",
        isPrivate: true,
      }),
    });
    assert.equal(createTreeResponse.status, 201);
    const treePayload = await createTreeResponse.json();
    const treeId = treePayload.tree.id;

    const initialPersonsResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/persons`,
      {
        headers: {authorization: `Bearer ${viewer.accessToken}`},
      },
    );
    assert.equal(initialPersonsResponse.status, 200);
    const initialPersonsPayload = await initialPersonsResponse.json();
    const viewerPersonId = initialPersonsPayload.persons[0].id;

    const createPerson = async (payload) => {
      const response = await fetch(`${ctx.baseUrl}/v1/trees/${treeId}/persons`, {
        method: "POST",
        headers: {
          authorization: `Bearer ${viewer.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify(payload),
      });
      assert.equal(response.status, 201);
      return (await response.json()).person;
    };

    const createRelation = async (payload) => {
      const response = await fetch(`${ctx.baseUrl}/v1/trees/${treeId}/relations`, {
        method: "POST",
        headers: {
          authorization: `Bearer ${viewer.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify(payload),
      });
      assert.equal(response.status, 201);
      return (await response.json()).relation;
    };

    const wife = await createPerson({
      firstName: "Анна",
      lastName: "Иванова",
      gender: "female",
    });
    const fatherInLaw = await createPerson({
      firstName: "Иван",
      lastName: "Иванов",
      gender: "male",
    });
    const motherInLaw = await createPerson({
      firstName: "Мария",
      lastName: "Иванова",
      gender: "female",
    });
    const brotherInLaw = await createPerson({
      firstName: "Петр",
      lastName: "Иванов",
      gender: "male",
    });
    const sisterInLaw = await createPerson({
      firstName: "Ольга",
      lastName: "Иванова",
      gender: "female",
    });
    const svoyak = await createPerson({
      firstName: "Сергей",
      lastName: "Петров",
      gender: "male",
    });
    const sister = await createPerson({
      firstName: "Дарья",
      lastName: "Кузнецова",
      gender: "female",
    });
    const zyat = await createPerson({
      firstName: "Никита",
      lastName: "Смирнов",
      gender: "male",
    });
    const child = await createPerson({
      firstName: "Павел",
      lastName: "Кузнецов",
      gender: "male",
    });
    const daughterInLaw = await createPerson({
      firstName: "Елена",
      lastName: "Соколова",
      gender: "female",
    });
    const svat = await createPerson({
      firstName: "Виктор",
      lastName: "Соколов",
      gender: "male",
    });

    await createRelation({
      person1Id: viewerPersonId,
      person2Id: wife.id,
      relation1to2: "spouse",
      isConfirmed: true,
    });

    for (const childId of [wife.id, brotherInLaw.id, sisterInLaw.id]) {
      await createRelation({
        person1Id: fatherInLaw.id,
        person2Id: childId,
        relation1to2: "parent",
        isConfirmed: true,
      });
      await createRelation({
        person1Id: motherInLaw.id,
        person2Id: childId,
        relation1to2: "parent",
        isConfirmed: true,
      });
    }

    await createRelation({
      person1Id: sisterInLaw.id,
      person2Id: svoyak.id,
      relation1to2: "spouse",
      isConfirmed: true,
    });
    await createRelation({
      person1Id: sister.id,
      person2Id: zyat.id,
      relation1to2: "spouse",
      isConfirmed: true,
    });
    await createRelation({
      person1Id: viewerPersonId,
      person2Id: sister.id,
      relation1to2: "sibling",
      relation2to1: "sibling",
      isConfirmed: true,
    });
    await createRelation({
      person1Id: viewerPersonId,
      person2Id: child.id,
      relation1to2: "parent",
      isConfirmed: true,
    });
    await createRelation({
      person1Id: wife.id,
      person2Id: child.id,
      relation1to2: "parent",
      isConfirmed: true,
    });
    await createRelation({
      person1Id: child.id,
      person2Id: daughterInLaw.id,
      relation1to2: "spouse",
      isConfirmed: true,
    });
    await createRelation({
      person1Id: svat.id,
      person2Id: daughterInLaw.id,
      relation1to2: "parent",
      isConfirmed: true,
    });

    const graphResponse = await fetch(`${ctx.baseUrl}/v1/trees/${treeId}/graph`, {
      headers: {authorization: `Bearer ${viewer.accessToken}`},
    });
    assert.equal(graphResponse.status, 200);
    const graphPayload = await graphResponse.json();
    const labelsByPersonId = new Map(
      graphPayload.snapshot.viewerDescriptors.map((descriptor) => [
        descriptor.personId,
        descriptor.primaryRelationLabel,
      ]),
    );

    assert.equal(labelsByPersonId.get(fatherInLaw.id), "Тесть");
    assert.equal(labelsByPersonId.get(motherInLaw.id), "Теща");
    assert.equal(labelsByPersonId.get(brotherInLaw.id), "Шурин");
    assert.equal(labelsByPersonId.get(sisterInLaw.id), "Свояченица");
    assert.equal(labelsByPersonId.get(svoyak.id), "Свояк");
    assert.equal(labelsByPersonId.get(zyat.id), "Зять");
    assert.equal(labelsByPersonId.get(daughterInLaw.id), "Невестка");
    assert.equal(labelsByPersonId.get(svat.id), "Сват");
  } finally {
    await stopTestServer(ctx);
  }
});

test("tree graph snapshot repairs a missing primary parent from sibling-supported data", () => {
  const treeId = "tree-parent-repair";
  const viewerPersonId = "viewer-person";
  const fatherId = "father-person";
  const motherId = "mother-person";
  const siblingId = "sibling-person";

  const snapshot = buildTreeGraphSnapshot({
    treeId,
    viewerPersonId,
    persons: [
      {
        id: viewerPersonId,
        treeId,
        name: "Наталья Кузнецова",
        gender: "female",
      },
      {
        id: fatherId,
        treeId,
        name: "Мочалкин Геннадий",
        gender: "male",
      },
      {
        id: motherId,
        treeId,
        name: "Мочалкина Лидия",
        gender: "female",
      },
      {
        id: siblingId,
        treeId,
        name: "Мочалкин Евгений",
        gender: "male",
      },
    ],
    relations: [
      {
        id: "union-1",
        treeId,
        person1Id: fatherId,
        person2Id: motherId,
        relation1to2: "spouse",
        relation2to1: "spouse",
        isConfirmed: true,
      },
      {
        id: "parent-1",
        treeId,
        person1Id: fatherId,
        person2Id: viewerPersonId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
      {
        id: "parent-2",
        treeId,
        person1Id: fatherId,
        person2Id: siblingId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
      {
        id: "parent-3",
        treeId,
        person1Id: motherId,
        person2Id: siblingId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
    ],
  });

  const inferredRelation = snapshot.relations.find((relation) => {
    return relation.person1Id === motherId && relation.person2Id === viewerPersonId;
  });

  assert.ok(inferredRelation);
  assert.match(inferredRelation.id, /^inferred:/);
  const repairWarning = snapshot.warnings.find((warning) => {
    return warning.code === "auto_repaired_parent_link";
  });
  assert.ok(repairWarning);
  assert.ok(repairWarning.relationIds.includes(inferredRelation.id));
  assert.ok(repairWarning.personIds.includes(motherId));
  assert.ok(repairWarning.personIds.includes(viewerPersonId));

  const labelsByPersonId = new Map(
    snapshot.viewerDescriptors.map((descriptor) => [
      descriptor.personId,
      descriptor.primaryRelationLabel,
    ]),
  );
  assert.equal(labelsByPersonId.get(motherId), "Мать");
});

test("tree graph snapshot keeps spouse-only unions on the same generation row", () => {
  const treeId = "tree-generation-row-harmonization";
  const viewerPersonId = "viewer-person";
  const viewerPartnerId = "viewer-partner";
  const siblingId = "sibling-person";
  const siblingPartnerId = "sibling-partner";
  const childId = "child-person";
  const fatherId = "father-person";
  const motherId = "mother-person";
  const grandfatherId = "grandfather-person";
  const grandmotherId = "grandmother-person";

  const snapshot = buildTreeGraphSnapshot({
    treeId,
    viewerPersonId,
    persons: [
      {id: viewerPersonId, treeId, name: "Артем Кузнецов", gender: "male"},
      {id: viewerPartnerId, treeId, name: "Анастасия Шуфляк", gender: "female"},
      {id: siblingId, treeId, name: "Дарья Кузнецова", gender: "female"},
      {id: siblingPartnerId, treeId, name: "Сергей Понькин", gender: "male"},
      {id: childId, treeId, name: "Павел Понькин", gender: "male"},
      {id: fatherId, treeId, name: "Андрей Кузнецов", gender: "male"},
      {id: motherId, treeId, name: "Наталья Кузнецова", gender: "female"},
      {id: grandfatherId, treeId, name: "Анатолий Кузнецов", gender: "male"},
      {id: grandmotherId, treeId, name: "Валентина Кузнецова", gender: "female"},
    ],
    relations: [
      {
        id: "grand-union",
        treeId,
        person1Id: grandfatherId,
        person2Id: grandmotherId,
        relation1to2: "spouse",
        relation2to1: "spouse",
        isConfirmed: true,
      },
      {
        id: "grandfather-parent",
        treeId,
        person1Id: grandfatherId,
        person2Id: fatherId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetId: "grand-parents",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
      {
        id: "grandmother-parent",
        treeId,
        person1Id: grandmotherId,
        person2Id: fatherId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetId: "grand-parents",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
      {
        id: "parent-union",
        treeId,
        person1Id: fatherId,
        person2Id: motherId,
        relation1to2: "spouse",
        relation2to1: "spouse",
        isConfirmed: true,
      },
      {
        id: "father-viewer",
        treeId,
        person1Id: fatherId,
        person2Id: viewerPersonId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetId: "viewer-parents",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
      {
        id: "mother-viewer",
        treeId,
        person1Id: motherId,
        person2Id: viewerPersonId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetId: "viewer-parents",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
      {
        id: "father-sibling",
        treeId,
        person1Id: fatherId,
        person2Id: siblingId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetId: "viewer-parents",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
      {
        id: "mother-sibling",
        treeId,
        person1Id: motherId,
        person2Id: siblingId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetId: "viewer-parents",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
      {
        id: "viewer-union",
        treeId,
        person1Id: viewerPersonId,
        person2Id: viewerPartnerId,
        relation1to2: "partner",
        relation2to1: "partner",
        isConfirmed: true,
      },
      {
        id: "sibling-union",
        treeId,
        person1Id: siblingId,
        person2Id: siblingPartnerId,
        relation1to2: "spouse",
        relation2to1: "spouse",
        isConfirmed: true,
      },
      {
        id: "sibling-child",
        treeId,
        person1Id: siblingId,
        person2Id: childId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetId: "child-parents",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
      {
        id: "sibling-partner-child",
        treeId,
        person1Id: siblingPartnerId,
        person2Id: childId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetId: "child-parents",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
    ],
  });

  const rowByPersonId = new Map();
  for (const row of snapshot.generationRows) {
    for (const personId of row.personIds) {
      rowByPersonId.set(personId, row.row);
    }
  }

  assert.equal(rowByPersonId.get(viewerPartnerId), rowByPersonId.get(viewerPersonId));
  assert.equal(rowByPersonId.get(siblingPartnerId), rowByPersonId.get(siblingId));
  assert.equal(rowByPersonId.get(fatherId), rowByPersonId.get(motherId));
  assert.equal(rowByPersonId.get(grandfatherId), rowByPersonId.get(grandmotherId));
  assert.equal(rowByPersonId.get(childId), rowByPersonId.get(siblingId) + 1);
  assert.ok(rowByPersonId.get(viewerPartnerId) > rowByPersonId.get(grandfatherId));
});

test("tree graph snapshot merges sibling children with the same parents into one family unit", () => {
  const treeId = "tree-merged-sibling-family-unit";
  const firstChildId = "first-child";
  const secondChildId = "second-child";
  const fatherId = "father-person";
  const motherId = "mother-person";

  const snapshot = buildTreeGraphSnapshot({
    treeId,
    viewerPersonId: firstChildId,
    persons: [
      {id: firstChildId, treeId, name: "Наталья Кузнецова", gender: "female"},
      {id: secondChildId, treeId, name: "Евгений Мочалкин", gender: "male"},
      {id: fatherId, treeId, name: "Геннадий Мочалкин", gender: "male"},
      {id: motherId, treeId, name: "Лидия Мочалкина", gender: "female"},
    ],
    relations: [
      {
        id: "parent-first-father",
        treeId,
        person1Id: fatherId,
        person2Id: firstChildId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetId: "first-child-parents",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
      {
        id: "parent-first-mother",
        treeId,
        person1Id: motherId,
        person2Id: firstChildId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetId: "first-child-parents",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
      {
        id: "parent-second-father",
        treeId,
        person1Id: fatherId,
        person2Id: secondChildId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetId: "second-child-parents",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
      {
        id: "parent-second-mother",
        treeId,
        person1Id: motherId,
        person2Id: secondChildId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetId: "second-child-parents",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
      {
        id: "parent-union",
        treeId,
        person1Id: fatherId,
        person2Id: motherId,
        relation1to2: "spouse",
        relation2to1: "spouse",
        isConfirmed: true,
      },
    ],
  });

  const mergedUnit = snapshot.familyUnits.find((unit) => {
    return (
      unit.adultIds.includes(fatherId) &&
      unit.adultIds.includes(motherId) &&
      unit.childIds.includes(firstChildId) &&
      unit.childIds.includes(secondChildId)
    );
  });

  assert.ok(mergedUnit);
  assert.equal(mergedUnit.childIds.length, 2);
  assert.ok(
    snapshot.generationRows.some((row) => {
      return row.familyUnitIds.includes(mergedUnit.id);
    }),
  );
});

test("tree graph snapshot keeps paternal grandparents below great-grandparents", () => {
  const treeId = "tree-paternal-grandparents-below-great-grandparents";
  const alexanderId = "great-grandfather";
  const mariaId = "great-grandmother";
  const gennadyId = "maternal-grandfather";
  const lydiaId = "maternal-grandmother";
  const anatolyId = "paternal-grandfather";
  const valentinaId = "paternal-grandmother";
  const andreyId = "father-person";
  const nataliaId = "mother-person";
  const evgeniyId = "uncle-person";
  const artemId = "viewer-person";

  const snapshot = buildTreeGraphSnapshot({
    treeId,
    viewerPersonId: artemId,
    persons: [
      {id: alexanderId, treeId, name: "Супрунов Александр", gender: "male"},
      {id: mariaId, treeId, name: "Супрунова Мария", gender: "female"},
      {id: gennadyId, treeId, name: "Мочалкин Геннадий Иванович", gender: "male"},
      {id: lydiaId, treeId, name: "Мочалкина Лидия Александровна", gender: "female"},
      {id: anatolyId, treeId, name: "Кузнецов Анатолий Степанович", gender: "male"},
      {id: valentinaId, treeId, name: "Кузнецова Валентина", gender: "female"},
      {id: andreyId, treeId, name: "Кузнецов Андрей Анатольевич", gender: "male"},
      {id: nataliaId, treeId, name: "Кузнецова Наталья Геннадьевна", gender: "female"},
      {id: evgeniyId, treeId, name: "Мочалкин Евгений Геннадьевич", gender: "male"},
      {id: artemId, treeId, name: "Кузнецов Артем Андреевич", gender: "male"},
    ],
    relations: [
      {
        id: "suprunov-union",
        treeId,
        person1Id: alexanderId,
        person2Id: mariaId,
        relation1to2: "spouse",
        relation2to1: "spouse",
        isConfirmed: true,
      },
      {
        id: "maternal-grandparents-union",
        treeId,
        person1Id: gennadyId,
        person2Id: lydiaId,
        relation1to2: "spouse",
        relation2to1: "spouse",
        isConfirmed: true,
      },
      {
        id: "paternal-grandparents-union",
        treeId,
        person1Id: anatolyId,
        person2Id: valentinaId,
        relation1to2: "spouse",
        relation2to1: "spouse",
        isConfirmed: true,
      },
      {
        id: "parents-union",
        treeId,
        person1Id: andreyId,
        person2Id: nataliaId,
        relation1to2: "spouse",
        relation2to1: "spouse",
        isConfirmed: true,
      },
      {
        id: "alexander-lydia",
        treeId,
        person1Id: alexanderId,
        person2Id: lydiaId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetId: "lydia-parents",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
      {
        id: "maria-lydia",
        treeId,
        person1Id: mariaId,
        person2Id: lydiaId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetId: "lydia-parents",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
      {
        id: "anatoly-andrey",
        treeId,
        person1Id: anatolyId,
        person2Id: andreyId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetId: "andrey-parents",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
      {
        id: "valentina-andrey",
        treeId,
        person1Id: valentinaId,
        person2Id: andreyId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetId: "andrey-parents",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
      {
        id: "gennady-natalia",
        treeId,
        person1Id: gennadyId,
        person2Id: nataliaId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetId: "natalia-parents",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
      {
        id: "lydia-natalia",
        treeId,
        person1Id: lydiaId,
        person2Id: nataliaId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetId: "natalia-parents",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
      {
        id: "gennady-evgeniy",
        treeId,
        person1Id: gennadyId,
        person2Id: evgeniyId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetId: "evgeniy-parents",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
      {
        id: "lydia-evgeniy",
        treeId,
        person1Id: lydiaId,
        person2Id: evgeniyId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetId: "evgeniy-parents",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
      {
        id: "andrey-artem",
        treeId,
        person1Id: andreyId,
        person2Id: artemId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetId: "artem-parents",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
      {
        id: "natalia-artem",
        treeId,
        person1Id: nataliaId,
        person2Id: artemId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetId: "artem-parents",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
    ],
  });

  const rowByPersonId = new Map();
  for (const row of snapshot.generationRows) {
    for (const personId of row.personIds) {
      rowByPersonId.set(personId, row.row);
    }
  }

  assert.equal(rowByPersonId.get(alexanderId), rowByPersonId.get(mariaId));
  assert.equal(rowByPersonId.get(gennadyId), rowByPersonId.get(lydiaId));
  assert.equal(rowByPersonId.get(anatolyId), rowByPersonId.get(valentinaId));
  assert.equal(rowByPersonId.get(gennadyId), rowByPersonId.get(anatolyId));
  assert.equal(rowByPersonId.get(andreyId), rowByPersonId.get(nataliaId));
  assert.equal(rowByPersonId.get(nataliaId), rowByPersonId.get(evgeniyId));
  assert.equal(rowByPersonId.get(andreyId), rowByPersonId.get(gennadyId) + 1);
  assert.equal(rowByPersonId.get(artemId), rowByPersonId.get(andreyId) + 1);
  assert.ok(rowByPersonId.get(alexanderId) < rowByPersonId.get(anatolyId));
});

test("tree graph snapshot marks direct grandparent relations as blood relatives", () => {
  const treeId = "tree-direct-grandparents";
  const viewerPersonId = "viewer-person";
  const grandfatherId = "grandfather-person";
  const grandmotherId = "grandmother-person";

  const snapshot = buildTreeGraphSnapshot({
    treeId,
    viewerPersonId,
    persons: [
      {id: viewerPersonId, treeId, name: "Артем Кузнецов", gender: "male"},
      {id: grandfatherId, treeId, name: "Геннадий Мочалкин", gender: "male"},
      {id: grandmotherId, treeId, name: "Лидия Мочалкина", gender: "female"},
    ],
    relations: [
      {
        id: "grandfather-direct",
        treeId,
        person1Id: grandfatherId,
        person2Id: viewerPersonId,
        relation1to2: "grandparent",
        relation2to1: "grandchild",
        isConfirmed: true,
      },
      {
        id: "grandmother-direct",
        treeId,
        person1Id: grandmotherId,
        person2Id: viewerPersonId,
        relation1to2: "grandparent",
        relation2to1: "grandchild",
        isConfirmed: true,
      },
    ],
  });

  const descriptorsByPersonId = new Map(
    snapshot.viewerDescriptors.map((descriptor) => [descriptor.personId, descriptor]),
  );

  assert.equal(descriptorsByPersonId.get(grandfatherId)?.primaryRelationLabel, "Дедушка");
  assert.equal(descriptorsByPersonId.get(grandmotherId)?.primaryRelationLabel, "Бабушка");
  assert.equal(descriptorsByPersonId.get(grandfatherId)?.isBlood, true);
  assert.equal(descriptorsByPersonId.get(grandmotherId)?.isBlood, true);
});

test("graph warnings detect multiple primary parent sets for one child", () => {
  const treeId = "tree-multi-primary-parent-sets";
  const childId = "child-person";
  const fatherId = "father-person";
  const motherId = "mother-person";

  const warnings = buildGraphWarnings({
    persons: [
      {id: childId, treeId, name: "Артем Кузнецов", gender: "male"},
      {id: fatherId, treeId, name: "Андрей Кузнецов", gender: "male"},
      {id: motherId, treeId, name: "Наталья Кузнецова", gender: "female"},
    ],
    relations: [
      {
        id: "parent-primary-1",
        treeId,
        person1Id: fatherId,
        person2Id: childId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetId: "set-biological-1",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
      {
        id: "parent-primary-2",
        treeId,
        person1Id: motherId,
        person2Id: childId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetId: "set-biological-2",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
    ],
    familyUnits: [
      {
        id: "unit-primary-a",
        rootParentSetId: "set-biological-1",
        adultIds: [fatherId],
        childIds: [childId],
        relationIds: ["parent-primary-1"],
      },
      {
        id: "unit-primary-b",
        rootParentSetId: "set-biological-2",
        adultIds: [motherId],
        childIds: [childId],
        relationIds: ["parent-primary-2"],
      },
    ],
  });

  const warning = warnings.find((entry) => {
    return entry.code === "multiple_primary_parent_sets";
  });

  assert.ok(warning);
  assert.ok(warning.personIds.includes(childId));
  assert.ok(warning.relationIds.includes("parent-primary-1"));
  assert.ok(warning.relationIds.includes("parent-primary-2"));
});

test("tree graph snapshot warns about conflicting direct link categories", () => {
  const treeId = "tree-conflicting-direct-links";
  const viewerPersonId = "viewer-person";
  const otherPersonId = "other-person";

  const snapshot = buildTreeGraphSnapshot({
    treeId,
    viewerPersonId,
    persons: [
      {id: viewerPersonId, treeId, name: "Артем Кузнецов", gender: "male"},
      {id: otherPersonId, treeId, name: "Анастасия Шуляк", gender: "female"},
    ],
    relations: [
      {
        id: "relation-union",
        treeId,
        person1Id: viewerPersonId,
        person2Id: otherPersonId,
        relation1to2: "partner",
        relation2to1: "partner",
        isConfirmed: true,
      },
      {
        id: "relation-sibling",
        treeId,
        person1Id: viewerPersonId,
        person2Id: otherPersonId,
        relation1to2: "sibling",
        relation2to1: "sibling",
        isConfirmed: true,
      },
    ],
  });

  const warning = snapshot.warnings.find((entry) => {
    return entry.code === "conflicting_direct_links";
  });

  assert.ok(warning);
  assert.ok(warning.personIds.includes(viewerPersonId));
  assert.ok(warning.personIds.includes(otherPersonId));
  assert.ok(warning.relationIds.includes("relation-union"));
  assert.ok(warning.relationIds.includes("relation-sibling"));
});

test("tree graph snapshot infers male-side in-law and stepchild labels", () => {
  const treeId = "tree-male-inlaws";
  const viewerPersonId = "viewer-person";
  const husbandId = "husband-person";
  const fatherInLawId = "father-in-law";
  const motherInLawId = "mother-in-law";
  const brotherInLawId = "brother-in-law";
  const sisterInLawId = "sister-in-law";
  const stepSonId = "step-son";

  const snapshot = buildTreeGraphSnapshot({
    treeId,
    viewerPersonId,
    persons: [
      {id: viewerPersonId, treeId, name: "Мария Смирнова", gender: "female"},
      {id: husbandId, treeId, name: "Иван Смирнов", gender: "male"},
      {id: fatherInLawId, treeId, name: "Петр Смирнов", gender: "male"},
      {id: motherInLawId, treeId, name: "Анна Смирнова", gender: "female"},
      {id: brotherInLawId, treeId, name: "Олег Смирнов", gender: "male"},
      {id: sisterInLawId, treeId, name: "Елена Смирнова", gender: "female"},
      {id: stepSonId, treeId, name: "Максим Смирнов", gender: "male"},
    ],
    relations: [
      {
        id: "union-viewer",
        treeId,
        person1Id: viewerPersonId,
        person2Id: husbandId,
        relation1to2: "spouse",
        relation2to1: "spouse",
        isConfirmed: true,
      },
      {
        id: "parent-father",
        treeId,
        person1Id: fatherInLawId,
        person2Id: husbandId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
      {
        id: "parent-mother",
        treeId,
        person1Id: motherInLawId,
        person2Id: husbandId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
      {
        id: "sibling-brother",
        treeId,
        person1Id: husbandId,
        person2Id: brotherInLawId,
        relation1to2: "sibling",
        relation2to1: "sibling",
        isConfirmed: true,
      },
      {
        id: "sibling-sister",
        treeId,
        person1Id: husbandId,
        person2Id: sisterInLawId,
        relation1to2: "sibling",
        relation2to1: "sibling",
        isConfirmed: true,
      },
      {
        id: "child-step",
        treeId,
        person1Id: husbandId,
        person2Id: stepSonId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
    ],
  });

  const labelsByPersonId = new Map(
    snapshot.viewerDescriptors.map((descriptor) => [
      descriptor.personId,
      descriptor.primaryRelationLabel,
    ]),
  );

  assert.equal(labelsByPersonId.get(fatherInLawId), "Свекор");
  assert.equal(labelsByPersonId.get(motherInLawId), "Свекровь");
  assert.equal(labelsByPersonId.get(brotherInLawId), "Деверь");
  assert.equal(labelsByPersonId.get(sisterInLawId), "Золовка");
  assert.equal(labelsByPersonId.get(stepSonId), "Пасынок");
});

test("tree graph snapshot preserves direct custom relation labels", () => {
  const treeId = "tree-custom-direct";
  const viewerPersonId = "viewer-person";
  const godfatherId = "godfather-person";

  const snapshot = buildTreeGraphSnapshot({
    treeId,
    viewerPersonId,
    persons: [
      {id: viewerPersonId, treeId, name: "Артем Кузнецов", gender: "male"},
      {id: godfatherId, treeId, name: "Павел Иванов", gender: "male"},
    ],
    relations: [
      {
        id: "custom-relation",
        treeId,
        person1Id: godfatherId,
        person2Id: viewerPersonId,
        relation1to2: "other",
        relation2to1: "other",
        customRelationLabel1to2: "Кум",
        customRelationLabel2to1: "Кум",
        isConfirmed: true,
      },
    ],
  });

  const labelsByPersonId = new Map(
    snapshot.viewerDescriptors.map((descriptor) => [
      descriptor.personId,
      descriptor.primaryRelationLabel,
    ]),
  );

  assert.equal(labelsByPersonId.get(godfatherId), "Кум");
  const directRelation = snapshot.relations.find((relation) => relation.id === "custom-relation");
  assert.equal(directRelation?.customRelationLabel1to2, "Кум");
  assert.equal(directRelation?.customRelationLabel2to1, "Кум");
});

test("tree graph snapshot infers stepparent and aunt-uncle-by-marriage labels", () => {
  const treeId = "tree-affinal-extended";
  const viewerPersonId = "viewer-person";
  const fatherId = "father-person";
  const motherId = "mother-person";
  const stepMotherId = "step-mother";
  const auntId = "aunt-person";
  const auntSpouseId = "aunt-spouse";
  const uncleId = "uncle-person";
  const uncleSpouseId = "uncle-spouse";

  const snapshot = buildTreeGraphSnapshot({
    treeId,
    viewerPersonId,
    persons: [
      {id: viewerPersonId, treeId, name: "Артем Кузнецов", gender: "male"},
      {id: fatherId, treeId, name: "Андрей Кузнецов", gender: "male"},
      {id: motherId, treeId, name: "Наталья Кузнецова", gender: "female"},
      {id: stepMotherId, treeId, name: "Ольга Кузнецова", gender: "female"},
      {id: auntId, treeId, name: "Марина Кузнецова", gender: "female"},
      {id: auntSpouseId, treeId, name: "Сергей Кузнецов", gender: "male"},
      {id: uncleId, treeId, name: "Виктор Кузнецов", gender: "male"},
      {id: uncleSpouseId, treeId, name: "Ирина Кузнецова", gender: "female"},
    ],
    relations: [
      {
        id: "parent-father",
        treeId,
        person1Id: fatherId,
        person2Id: viewerPersonId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
      {
        id: "parent-mother",
        treeId,
        person1Id: motherId,
        person2Id: viewerPersonId,
        relation1to2: "parent",
        relation2to1: "child",
        parentSetType: "biological",
        isPrimaryParentSet: true,
        isConfirmed: true,
      },
      {
        id: "union-step",
        treeId,
        person1Id: fatherId,
        person2Id: stepMotherId,
        relation1to2: "spouse",
        relation2to1: "spouse",
        isConfirmed: true,
      },
      {
        id: "mother-sibling",
        treeId,
        person1Id: motherId,
        person2Id: auntId,
        relation1to2: "sibling",
        relation2to1: "sibling",
        isConfirmed: true,
      },
      {
        id: "aunt-union",
        treeId,
        person1Id: auntId,
        person2Id: auntSpouseId,
        relation1to2: "spouse",
        relation2to1: "spouse",
        isConfirmed: true,
      },
      {
        id: "father-sibling",
        treeId,
        person1Id: fatherId,
        person2Id: uncleId,
        relation1to2: "sibling",
        relation2to1: "sibling",
        isConfirmed: true,
      },
      {
        id: "uncle-union",
        treeId,
        person1Id: uncleId,
        person2Id: uncleSpouseId,
        relation1to2: "spouse",
        relation2to1: "spouse",
        isConfirmed: true,
      },
    ],
  });

  const labelsByPersonId = new Map(
    snapshot.viewerDescriptors.map((descriptor) => [
      descriptor.personId,
      descriptor.primaryRelationLabel,
    ]),
  );

  assert.equal(labelsByPersonId.get(stepMotherId), "Мачеха");
  assert.equal(labelsByPersonId.get(auntSpouseId), "Дядя");
  assert.equal(labelsByPersonId.get(uncleSpouseId), "Тетя");
});

test("tree graph snapshot infers extended collateral blood labels", async () => {
  const ctx = await startTestServer();

  try {
    const viewerResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "graph-blood-viewer@rodnya.app",
        password: "secret123",
        displayName: "Максим Орлов",
      }),
    });
    assert.equal(viewerResponse.status, 201);
    const viewer = await viewerResponse.json();

    const createTreeResponse = await fetch(`${ctx.baseUrl}/v1/trees`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${viewer.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        name: "Семья для боковых линий",
        isPrivate: true,
      }),
    });
    assert.equal(createTreeResponse.status, 201);
    const treePayload = await createTreeResponse.json();
    const treeId = treePayload.tree.id;

    const initialPersonsResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/persons`,
      {
        headers: {authorization: `Bearer ${viewer.accessToken}`},
      },
    );
    assert.equal(initialPersonsResponse.status, 200);
    const initialPersonsPayload = await initialPersonsResponse.json();
    const viewerPersonId = initialPersonsPayload.persons[0].id;

    const createPerson = async (payload) => {
      const response = await fetch(`${ctx.baseUrl}/v1/trees/${treeId}/persons`, {
        method: "POST",
        headers: {
          authorization: `Bearer ${viewer.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify(payload),
      });
      assert.equal(response.status, 201);
      return (await response.json()).person;
    };

    const createRelation = async (payload) => {
      const response = await fetch(`${ctx.baseUrl}/v1/trees/${treeId}/relations`, {
        method: "POST",
        headers: {
          authorization: `Bearer ${viewer.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify(payload),
      });
      assert.equal(response.status, 201);
      return (await response.json()).relation;
    };

    const greatGrandfather = await createPerson({
      firstName: "Степан",
      lastName: "Орлов",
      gender: "male",
    });
    const grandfather = await createPerson({
      firstName: "Алексей",
      lastName: "Орлов",
      gender: "male",
    });
    const granduncle = await createPerson({
      firstName: "Григорий",
      lastName: "Орлов",
      gender: "male",
    });
    const parent = await createPerson({
      firstName: "Игорь",
      lastName: "Орлов",
      gender: "male",
    });
    const sibling = await createPerson({
      firstName: "Роман",
      lastName: "Орлов",
      gender: "male",
    });
    const nephew = await createPerson({
      firstName: "Олег",
      lastName: "Орлов",
      gender: "male",
    });
    const grandnephew = await createPerson({
      firstName: "Лев",
      lastName: "Орлов",
      gender: "male",
    });
    const parentSibling = await createPerson({
      firstName: "Сергей",
      lastName: "Орлов",
      gender: "male",
    });
    const cousin = await createPerson({
      firstName: "Павел",
      lastName: "Орлов",
      gender: "male",
    });
    const cousinChild = await createPerson({
      firstName: "Кирилл",
      lastName: "Орлов",
      gender: "male",
    });
    const parentCousin = await createPerson({
      firstName: "Виктор",
      lastName: "Орлов",
      gender: "male",
    });

    const parentRelation = async (parentId, childId) =>
      createRelation({
        person1Id: parentId,
        person2Id: childId,
        relation1to2: "parent",
        isConfirmed: true,
      });

    await parentRelation(greatGrandfather.id, grandfather.id);
    await parentRelation(greatGrandfather.id, granduncle.id);
    await parentRelation(grandfather.id, parent.id);
    await parentRelation(grandfather.id, parentSibling.id);
    await parentRelation(parent.id, viewerPersonId);
    await parentRelation(parent.id, sibling.id);
    await parentRelation(sibling.id, nephew.id);
    await parentRelation(nephew.id, grandnephew.id);
    await parentRelation(parentSibling.id, cousin.id);
    await parentRelation(cousin.id, cousinChild.id);
    await parentRelation(granduncle.id, parentCousin.id);

    const graphResponse = await fetch(`${ctx.baseUrl}/v1/trees/${treeId}/graph`, {
      headers: {authorization: `Bearer ${viewer.accessToken}`},
    });
    assert.equal(graphResponse.status, 200);
    const graphPayload = await graphResponse.json();
    const labelsByPersonId = new Map(
      graphPayload.snapshot.viewerDescriptors.map((descriptor) => [
        descriptor.personId,
        descriptor.primaryRelationLabel,
      ]),
    );

    assert.equal(labelsByPersonId.get(granduncle.id), "Двоюродный дедушка");
    assert.equal(labelsByPersonId.get(parentCousin.id), "Двоюродный дядя");
    assert.equal(labelsByPersonId.get(cousin.id), "Двоюродный брат");
    assert.equal(labelsByPersonId.get(cousinChild.id), "Двоюродный племянник");
    assert.equal(labelsByPersonId.get(grandnephew.id), "Внучатый племянник");
  } finally {
    await stopTestServer(ctx);
  }
});

test("branch chat endpoint reuses branch thread and limits participants to that branch", async () => {
  const ctx = await startTestServer();

  try {
    const aliceResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "branch-alice@rodnya.app",
        password: "secret123",
        displayName: "Alice Branch",
      }),
    });
    assert.equal(aliceResponse.status, 201);
    const alice = await aliceResponse.json();

    const bobResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "branch-bob@rodnya.app",
        password: "secret123",
        displayName: "Bob Branch",
      }),
    });
    assert.equal(bobResponse.status, 201);
    const bob = await bobResponse.json();

    const createTreeResponse = await fetch(`${ctx.baseUrl}/v1/trees`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${alice.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        name: "Ветка Кузнецовых",
        description: "Проверка веточного чата",
        isPrivate: true,
      }),
    });
    assert.equal(createTreeResponse.status, 201);
    const createdTreePayload = await createTreeResponse.json();
    const treeId = createdTreePayload.tree.id;

    const personsResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/persons`,
      {
        headers: {authorization: `Bearer ${alice.accessToken}`},
      },
    );
    assert.equal(personsResponse.status, 200);
    const personsPayload = await personsResponse.json();
    const alicePersonId = personsPayload.persons[0].id;

    const inviteResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/invitations`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${alice.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          recipientUserId: bob.user.id,
        }),
      },
    );
    assert.equal(inviteResponse.status, 201);
    const invitePayload = await inviteResponse.json();

    const acceptInviteResponse = await fetch(
      `${ctx.baseUrl}/v1/tree-invitations/${invitePayload.invitation.invitationId}/respond`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${bob.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({accept: true}),
      },
    );
    assert.equal(acceptInviteResponse.status, 200);

    const bobPersonResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/persons`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${bob.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          firstName: "Боб",
          lastName: "Кузнецов",
          gender: "male",
          userId: bob.user.id,
        }),
      },
    );
    assert.equal(bobPersonResponse.status, 201);
    const bobPersonPayload = await bobPersonResponse.json();

    const relationResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/relations`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${alice.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          person1Id: alicePersonId,
          person2Id: bobPersonPayload.person.id,
          relation1to2: "spouse",
          isConfirmed: true,
        }),
      },
    );
    assert.equal(relationResponse.status, 201);

    const createBranchResponse = await fetch(`${ctx.baseUrl}/v1/chats/branches`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${alice.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        treeId,
        branchRootPersonIds: [alicePersonId],
        title: "Ветка Ивана",
      }),
    });
    assert.equal(createBranchResponse.status, 201);
    const createdBranchPayload = await createBranchResponse.json();
    assert.equal(createdBranchPayload.chat.type, "branch");
    assert.equal(createdBranchPayload.chat.title, "Ветка Ивана");
    assert.deepEqual(createdBranchPayload.chat.participantIds.sort(), [
      alice.user.id,
      bob.user.id,
    ].sort());

    const repeatedBranchResponse = await fetch(`${ctx.baseUrl}/v1/chats/branches`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${alice.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        treeId,
        branchRootPersonIds: [alicePersonId],
        title: "Ветка Ивана",
      }),
    });
    assert.equal(repeatedBranchResponse.status, 201);
    const repeatedBranchPayload = await repeatedBranchResponse.json();
    assert.equal(repeatedBranchPayload.chatId, createdBranchPayload.chatId);

    const bobChatsResponse = await fetch(`${ctx.baseUrl}/v1/chats`, {
      headers: {authorization: `Bearer ${bob.accessToken}`},
    });
    assert.equal(bobChatsResponse.status, 200);
    const bobChatsPayload = await bobChatsResponse.json();
    assert.equal(bobChatsPayload.chats.length, 1);
    assert.equal(bobChatsPayload.chats[0].type, "branch");
    assert.equal(bobChatsPayload.chats[0].title, "Ветка Ивана");
  } finally {
    await stopTestServer(ctx);
  }
});

test("relation requests and invite processing work on custom backend", async () => {
  const ctx = await startTestServer();

  try {
    const registerOwnerResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "owner@rodnya.app",
        password: "secret123",
        displayName: "Owner User",
      }),
    });
    assert.equal(registerOwnerResponse.status, 201);
    const owner = await registerOwnerResponse.json();

    const registerRecipientResponse = await fetch(
      `${ctx.baseUrl}/v1/auth/register`,
      {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({
          email: "recipient@rodnya.app",
          password: "secret123",
          displayName: "Recipient User",
        }),
      },
    );
    assert.equal(registerRecipientResponse.status, 201);
    const recipient = await registerRecipientResponse.json();

    const createTreeResponse = await fetch(`${ctx.baseUrl}/v1/trees`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${owner.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        name: "Дерево запросов",
        description: "Тест relation requests",
        isPrivate: true,
      }),
    });
    assert.equal(createTreeResponse.status, 201);
    const createdTree = await createTreeResponse.json();
    const treeId = createdTree.tree.id;

    const initialPersonsResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/persons`,
      {
        headers: {authorization: `Bearer ${owner.accessToken}`},
      },
    );
    assert.equal(initialPersonsResponse.status, 200);
    const initialPersons = await initialPersonsResponse.json();
    const ownerPersonId = initialPersons.persons[0].id;

    const createOfflinePersonResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/persons`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${owner.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          firstName: "Offline",
          lastName: "Relative",
          gender: "female",
        }),
      },
    );
    assert.equal(createOfflinePersonResponse.status, 201);
    const offlinePersonPayload = await createOfflinePersonResponse.json();
    const offlinePersonId = offlinePersonPayload.person.id;

    const sendDirectRequestResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/relation-requests`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${owner.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          recipientId: recipient.user.id,
          senderToRecipient: "sibling",
          message: "Подтверди родство",
        }),
      },
    );
    assert.equal(sendDirectRequestResponse.status, 201);
    const directRequestPayload = await sendDirectRequestResponse.json();

    const pendingResponse = await fetch(
      `${ctx.baseUrl}/v1/relation-requests/pending?treeId=${treeId}`,
      {
        headers: {authorization: `Bearer ${recipient.accessToken}`},
      },
    );
    assert.equal(pendingResponse.status, 200);
    const pendingPayload = await pendingResponse.json();
    assert.equal(pendingPayload.requests.length, 1);

    const acceptResponse = await fetch(
      `${ctx.baseUrl}/v1/relation-requests/${directRequestPayload.request.id}/respond`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${recipient.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({response: "accepted"}),
      },
    );
    assert.equal(acceptResponse.status, 200);
    const acceptedPayload = await acceptResponse.json();
    assert.equal(acceptedPayload.request.status, "accepted");
    assert.equal(acceptedPayload.relation.relation1to2, "sibling");
    assert.ok(acceptedPayload.person.identityId);
    const recipientIdentityId = acceptedPayload.person.identityId;
    const autoCreatedRecipientPersonId = acceptedPayload.person.id;

    const personsAfterAcceptResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/persons`,
      {
        headers: {authorization: `Bearer ${owner.accessToken}`},
      },
    );
    assert.equal(personsAfterAcceptResponse.status, 200);
    const personsAfterAccept = await personsAfterAcceptResponse.json();
    assert.equal(personsAfterAccept.persons.length, 3);
    assert.ok(
      personsAfterAccept.persons.some((person) => person.userId === recipient.user.id),
    );

    const relationsAfterAcceptResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/relations`,
      {
        headers: {authorization: `Bearer ${owner.accessToken}`},
      },
    );
    assert.equal(relationsAfterAcceptResponse.status, 200);
    const relationsAfterAccept = await relationsAfterAcceptResponse.json();
    assert.equal(relationsAfterAccept.relations.length, 1);
    assert.equal(relationsAfterAccept.relations[0].person1Id, ownerPersonId);

    const inviteProcessResponse = await fetch(
      `${ctx.baseUrl}/v1/invitations/pending/process`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${recipient.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          treeId,
          personId: offlinePersonId,
        }),
      },
    );
    assert.equal(inviteProcessResponse.status, 200);
    const inviteProcessPayload = await inviteProcessResponse.json();
    assert.equal(inviteProcessPayload.person.userId, recipient.user.id);
    assert.equal(inviteProcessPayload.person.id, offlinePersonId);
    assert.equal(inviteProcessPayload.person.identityId, recipientIdentityId);

    const personsAfterClaimResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/persons`,
      {
        headers: {authorization: `Bearer ${owner.accessToken}`},
      },
    );
    assert.equal(personsAfterClaimResponse.status, 200);
    const personsAfterClaim = await personsAfterClaimResponse.json();
    assert.equal(personsAfterClaim.persons.length, 2);
    assert.ok(
      personsAfterClaim.persons.some(
        (person) =>
          person.id === offlinePersonId &&
          person.userId === recipient.user.id &&
          person.identityId === recipientIdentityId,
      ),
    );
    assert.ok(
      personsAfterClaim.persons.every(
        (person) => person.id !== autoCreatedRecipientPersonId,
      ),
    );

    const relationsAfterClaimResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/relations`,
      {
        headers: {authorization: `Bearer ${owner.accessToken}`},
      },
    );
    assert.equal(relationsAfterClaimResponse.status, 200);
    const relationsAfterClaim = await relationsAfterClaimResponse.json();
    assert.equal(relationsAfterClaim.relations.length, 1);
    assert.equal(relationsAfterClaim.relations[0].person2Id, offlinePersonId);

    const createSecondTreeResponse = await fetch(`${ctx.baseUrl}/v1/trees`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${owner.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        name: "Дерево запросов 2",
        description: "Тест identity layer",
        isPrivate: true,
      }),
    });
    assert.equal(createSecondTreeResponse.status, 201);
    const secondTreePayload = await createSecondTreeResponse.json();
    const secondTreeId = secondTreePayload.tree.id;

    const createSecondOfflinePersonResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${secondTreeId}/persons`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${owner.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          firstName: "Offline",
          lastName: "Relative Clone",
          gender: "female",
        }),
      },
    );
    assert.equal(createSecondOfflinePersonResponse.status, 201);
    const secondOfflinePersonPayload = await createSecondOfflinePersonResponse.json();
    const secondOfflinePersonId = secondOfflinePersonPayload.person.id;

    const secondInviteProcessResponse = await fetch(
      `${ctx.baseUrl}/v1/invitations/pending/process`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${recipient.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          treeId: secondTreeId,
          personId: secondOfflinePersonId,
        }),
      },
    );
    assert.equal(secondInviteProcessResponse.status, 200);
    const secondInviteProcessPayload = await secondInviteProcessResponse.json();
    assert.equal(secondInviteProcessPayload.person.id, secondOfflinePersonId);
    assert.equal(secondInviteProcessPayload.person.userId, recipient.user.id);
    assert.equal(secondInviteProcessPayload.person.identityId, recipientIdentityId);

    const snapshot = await ctx.store._read();
    const recipientIdentity = snapshot.personIdentities.find(
      (entry) => entry.userId === recipient.user.id,
    );
    assert.ok(recipientIdentity);
    assert.equal(recipientIdentity.id, recipientIdentityId);
    assert.ok(recipientIdentity.personIds.includes(offlinePersonId));
    assert.ok(recipientIdentity.personIds.includes(secondOfflinePersonId));
  } finally {
    await stopTestServer(ctx);
  }
});

test("tree invitations support pending list and accept flow", async () => {
  const ctx = await startTestServer();

  try {
    const ownerResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "tree-owner@rodnya.app",
        password: "secret123",
        displayName: "Tree Owner",
      }),
    });
    assert.equal(ownerResponse.status, 201);
    const owner = await ownerResponse.json();

    const inviteeResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "tree-invitee@rodnya.app",
        password: "secret123",
        displayName: "Tree Invitee",
      }),
    });
    assert.equal(inviteeResponse.status, 201);
    const invitee = await inviteeResponse.json();

    const createTreeResponse = await fetch(`${ctx.baseUrl}/v1/trees`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${owner.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        name: "Приглашения в дерево",
        description: "Тест pending tree invites",
        isPrivate: true,
      }),
    });
    assert.equal(createTreeResponse.status, 201);
    const treePayload = await createTreeResponse.json();
    const treeId = treePayload.tree.id;

    const createInvitationResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/invitations`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${owner.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          recipientUserId: invitee.user.id,
          relationToTree: "родственник",
        }),
      },
    );
    assert.equal(createInvitationResponse.status, 201);
    const createdInvitation = await createInvitationResponse.json();
    assert.equal(createdInvitation.invitation.tree.id, treeId);

    const pendingInvitationsResponse = await fetch(
      `${ctx.baseUrl}/v1/tree-invitations/pending`,
      {
        headers: {authorization: `Bearer ${invitee.accessToken}`},
      },
    );
    assert.equal(pendingInvitationsResponse.status, 200);
    const pendingInvitations = await pendingInvitationsResponse.json();
    assert.equal(pendingInvitations.invitations.length, 1);
    assert.equal(pendingInvitations.invitations[0].tree.name, "Приглашения в дерево");

    const acceptInvitationResponse = await fetch(
      `${ctx.baseUrl}/v1/tree-invitations/${createdInvitation.invitation.invitationId}/respond`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${invitee.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({accept: true}),
      },
    );
    assert.equal(acceptInvitationResponse.status, 200);
    const acceptPayload = await acceptInvitationResponse.json();
    assert.equal(acceptPayload.accepted, true);

    const userTreesResponse = await fetch(`${ctx.baseUrl}/v1/trees`, {
      headers: {authorization: `Bearer ${invitee.accessToken}`},
    });
    assert.equal(userTreesResponse.status, 200);
    const userTreesPayload = await userTreesResponse.json();
    assert.equal(userTreesPayload.trees.length, 1);
    assert.equal(userTreesPayload.trees[0].id, treeId);
  } finally {
    await stopTestServer(ctx);
  }
});

test("notification feed tracks unread events from chat, relation requests and tree invites", async () => {
  const ctx = await startTestServer();

  try {
    const aliceResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "notify-alice@rodnya.app",
        password: "secret123",
        displayName: "Alice",
      }),
    });
    assert.equal(aliceResponse.status, 201);
    const alice = await aliceResponse.json();

    const bobResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "notify-bob@rodnya.app",
        password: "secret123",
        displayName: "Bob",
      }),
    });
    assert.equal(bobResponse.status, 201);
    const bob = await bobResponse.json();

    const createTreeResponse = await fetch(`${ctx.baseUrl}/v1/trees`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${alice.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        name: "Уведомления",
        description: "Тест уведомлений",
        isPrivate: true,
      }),
    });
    assert.equal(createTreeResponse.status, 201);
    const treePayload = await createTreeResponse.json();
    const treeId = treePayload.tree.id;

    const relationRequestResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/relation-requests`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${alice.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          recipientId: bob.user.id,
          senderToRecipient: "sibling",
        }),
      },
    );
    assert.equal(relationRequestResponse.status, 201);

    const treeInvitationResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treeId}/invitations`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${alice.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          recipientUserId: bob.user.id,
        }),
      },
    );
    assert.equal(treeInvitationResponse.status, 201);

    const directChatResponse = await fetch(`${ctx.baseUrl}/v1/chats/direct`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${alice.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({otherUserId: bob.user.id}),
    });
    assert.equal(directChatResponse.status, 200);
    const chatPayload = await directChatResponse.json();

    const sendMessageResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${chatPayload.chatId}/messages`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${alice.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({text: "Привет из уведомлений"}),
      },
    );
    assert.equal(sendMessageResponse.status, 201);

    const unreadCountResponse = await fetch(
      `${ctx.baseUrl}/v1/notifications/unread-count`,
      {
        headers: {authorization: `Bearer ${bob.accessToken}`},
      },
    );
    assert.equal(unreadCountResponse.status, 200);
    const unreadCount = await unreadCountResponse.json();
    assert.equal(unreadCount.totalUnread, 3);

    const notificationsResponse = await fetch(
      `${ctx.baseUrl}/v1/notifications?status=unread&limit=10`,
      {
        headers: {authorization: `Bearer ${bob.accessToken}`},
      },
    );
    assert.equal(notificationsResponse.status, 200);
    const notificationsPayload = await notificationsResponse.json();
    assert.equal(notificationsPayload.notifications.length, 3);
    assert.ok(
      notificationsPayload.notifications.some(
        (notification) => notification.type === "chat_message",
      ),
    );
    assert.ok(
      notificationsPayload.notifications.some(
        (notification) => notification.type === "relation_request",
      ),
    );
    assert.ok(
      notificationsPayload.notifications.some(
        (notification) => notification.type === "tree_invitation",
      ),
    );

    const readResponse = await fetch(
      `${ctx.baseUrl}/v1/notifications/${notificationsPayload.notifications[0].id}/read`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${bob.accessToken}`,
          "content-type": "application/json",
        },
        body: "{}",
      },
    );
    assert.equal(readResponse.status, 200);

    const unreadAfterReadResponse = await fetch(
      `${ctx.baseUrl}/v1/notifications/unread-count`,
      {
        headers: {authorization: `Bearer ${bob.accessToken}`},
      },
    );
    assert.equal(unreadAfterReadResponse.status, 200);
    const unreadAfterRead = await unreadAfterReadResponse.json();
    assert.equal(unreadAfterRead.totalUnread, 2);
  } finally {
    await stopTestServer(ctx);
  }
});

test("web push config exposes VAPID public key when enabled", async () => {
  const ctx = await startConfiguredTestServer({
    configOverrides: {
      webPushEnabled: true,
      webPushPublicKey: "public-vapid-key",
      webPushPrivateKey: "private-vapid-key",
    },
    pushGatewayFactory: ({store, config}) =>
      new PushGateway({
        store,
        config,
        webPushClient: {
          setVapidDetails() {},
          async sendNotification() {
            return {statusCode: 201};
          },
        },
      }),
  });

  try {
    const registerResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "webpush-config@rodnya.app",
        password: "secret123",
        displayName: "Web Push Config",
      }),
    });
    assert.equal(registerResponse.status, 201);
    const registered = await registerResponse.json();

    const configResponse = await fetch(`${ctx.baseUrl}/v1/push/web/config`, {
      headers: {authorization: `Bearer ${registered.accessToken}`},
    });
    assert.equal(configResponse.status, 200);
    const configPayload = await configResponse.json();
    assert.equal(configPayload.enabled, true);
    assert.equal(configPayload.publicKey, "public-vapid-key");
  } finally {
    await stopTestServer(ctx);
  }
});

test("web push delivery marks delivery as sent for subscribed browser", async () => {
  const sentNotifications = [];
  const fakeWebPushClient = {
    setVapidDetails() {},
    async sendNotification(subscription, payload) {
      sentNotifications.push({subscription, payload: JSON.parse(payload)});
      return {statusCode: 201};
    },
  };

  const ctx = await startConfiguredTestServer({
    configOverrides: {
      webPushEnabled: true,
      webPushPublicKey: "public-vapid-key",
      webPushPrivateKey: "private-vapid-key",
    },
    pushGatewayFactory: ({store, config}) =>
      new PushGateway({
        store,
        config,
        webPushClient: fakeWebPushClient,
      }),
  });

  try {
    const ownerResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "webpush-owner@rodnya.app",
        password: "secret123",
        displayName: "Web Push Owner",
      }),
    });
    assert.equal(ownerResponse.status, 201);
    const owner = await ownerResponse.json();

    const inviteeResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "webpush-invitee@rodnya.app",
        password: "secret123",
        displayName: "Web Push Invitee",
      }),
    });
    assert.equal(inviteeResponse.status, 201);
    const invitee = await inviteeResponse.json();

    const registerDeviceResponse = await fetch(
      `${ctx.baseUrl}/v1/push/devices`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${invitee.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          provider: "webpush",
          token: JSON.stringify({
            endpoint: "https://push.example.test/subscription-1",
            keys: {
              p256dh: "p256dh-key",
              auth: "auth-key",
            },
          }),
          platform: "web",
        }),
      },
    );
    assert.equal(registerDeviceResponse.status, 201);

    const createTreeResponse = await fetch(`${ctx.baseUrl}/v1/trees`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${owner.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        name: "Web Push Tree",
        description: "Проверка browser push",
        isPrivate: true,
      }),
    });
    assert.equal(createTreeResponse.status, 201);
    const treePayload = await createTreeResponse.json();

    const inviteResponse = await fetch(
      `${ctx.baseUrl}/v1/trees/${treePayload.tree.id}/invitations`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${owner.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          recipientUserId: invitee.user.id,
          relationToTree: "родственник",
        }),
      },
    );
    assert.equal(inviteResponse.status, 201);
    assert.equal(sentNotifications.length, 1);
    assert.equal(
      sentNotifications[0].subscription.endpoint,
      "https://push.example.test/subscription-1",
    );
    assert.equal(
      sentNotifications[0].payload.title,
      "Приглашение в семейное дерево",
    );
    assert.match(
      sentNotifications[0].payload.url,
      /notificationPayload=.*#\/notifications$/,
    );

    const deliveriesResponse = await fetch(
      `${ctx.baseUrl}/v1/push/deliveries?limit=10`,
      {
        headers: {authorization: `Bearer ${invitee.accessToken}`},
      },
    );
    assert.equal(deliveriesResponse.status, 200);
    const deliveriesPayload = await deliveriesResponse.json();
    assert.equal(deliveriesPayload.deliveries.length, 1);
    assert.equal(deliveriesPayload.deliveries[0].provider, "webpush");
    assert.equal(deliveriesPayload.deliveries[0].status, "sent");
    assert.ok(deliveriesPayload.deliveries[0].deliveredAt);
    assert.equal(deliveriesPayload.deliveries[0].lastError, null);
    assert.equal(deliveriesPayload.deliveries[0].responseCode, 201);
  } finally {
    await stopTestServer(ctx);
  }
});

test("websocket realtime and push queue work for chat delivery", async () => {
  const ctx = await startTestServer();

  try {
    const aliceResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "ws-alice@rodnya.app",
        password: "secret123",
        displayName: "Alice WS",
      }),
    });
    assert.equal(aliceResponse.status, 201);
    const alice = await aliceResponse.json();

    const bobResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "ws-bob@rodnya.app",
        password: "secret123",
        displayName: "Bob WS",
      }),
    });
    assert.equal(bobResponse.status, 201);
    const bob = await bobResponse.json();

    const pushDeviceResponse = await fetch(`${ctx.baseUrl}/v1/push/devices`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${bob.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        provider: "rustore",
        token: "rustore-test-token",
        platform: "android",
      }),
    });
    assert.equal(pushDeviceResponse.status, 201);

    const socket = new WebSocket(
      `${ctx.wsBaseUrl}/v1/realtime?accessToken=${bob.accessToken}`,
    );

    await new Promise((resolve, reject) => {
      socket.addEventListener("open", resolve, {once: true});
      socket.addEventListener("error", reject, {once: true});
    });

    const observedEvents = [];
    const eventPromise = new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        reject(new Error("Timed out waiting for realtime chat events"));
      }, 3000);

      socket.addEventListener("message", (event) => {
        const payload = JSON.parse(String(event.data));
        observedEvents.push(payload);

        const hasReady = observedEvents.some(
          (item) => item.type === "connection.ready",
        );
        const hasChatEvent = observedEvents.some(
          (item) => item.type === "chat.message.created",
        );
        const hasNotificationEvent = observedEvents.some(
          (item) =>
            item.type === "notification.created" &&
            item.notification?.type === "chat_message",
        );

        if (hasReady && hasChatEvent && hasNotificationEvent) {
          clearTimeout(timer);
          resolve(observedEvents);
        }
      });
    });

    const createChatResponse = await fetch(`${ctx.baseUrl}/v1/chats/direct`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${alice.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({otherUserId: bob.user.id}),
    });
    assert.equal(createChatResponse.status, 200);
    const chatPayload = await createChatResponse.json();

    const sendMessageResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${chatPayload.chatId}/messages`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${alice.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({text: "Realtime привет"}),
      },
    );
    assert.equal(sendMessageResponse.status, 201);

    const realtimeEvents = await eventPromise;
    assert.ok(
      realtimeEvents.some((item) => item.type === "connection.ready"),
    );
    assert.ok(
      realtimeEvents.some(
        (item) =>
          item.type === "chat.message.created" &&
          item.message?.text === "Realtime привет",
      ),
    );
    assert.ok(
      realtimeEvents.some(
        (item) =>
          item.type === "notification.created" &&
          item.notification?.type === "chat_message",
      ),
    );

    const deliveriesResponse = await fetch(
      `${ctx.baseUrl}/v1/push/deliveries?limit=10`,
      {
        headers: {authorization: `Bearer ${bob.accessToken}`},
      },
    );
    assert.equal(deliveriesResponse.status, 200);
    const deliveriesPayload = await deliveriesResponse.json();
    assert.ok(deliveriesPayload.deliveries.length >= 1);
    assert.ok(
      deliveriesPayload.deliveries.some(
        (delivery) =>
          delivery.provider === "rustore" && delivery.status === "queued",
      ),
    );

    socket.close();
  } finally {
    await stopTestServer(ctx);
  }
});

test("websocket realtime stays available when session touch fails in the background", async () => {
  const ctx = await startTestServer();

  try {
    const registerResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "ws-touch-failure@rodnya.app",
        password: "secret123",
        displayName: "WS Touch Failure",
      }),
    });
    assert.equal(registerResponse.status, 201);
    const registered = await registerResponse.json();

    let touchCalls = 0;
    ctx.store.touchSession = async () => {
      touchCalls += 1;
      throw new Error("touch_failed");
    };

    const socket = new WebSocket(
      `${ctx.wsBaseUrl}/v1/realtime?accessToken=${registered.accessToken}`,
    );
    const observedEvents = [];
    socket.addEventListener("message", (event) => {
      observedEvents.push(JSON.parse(String(event.data)));
    });

    await new Promise((resolve, reject) => {
      socket.addEventListener("open", resolve, {once: true});
      socket.addEventListener("error", reject, {once: true});
    });

    const startedAt = Date.now();
    let readyPayload = null;
    while (Date.now() - startedAt < 3000 && !readyPayload) {
      readyPayload = observedEvents.find((item) => item.type === "connection.ready") || null;
      if (!readyPayload) {
        await new Promise((resolve) => setTimeout(resolve, 25));
      }
    }
    assert.ok(readyPayload, "Timed out waiting for realtime connection.ready");

    assert.equal(readyPayload.userId, registered.user.id);
    await new Promise((resolve) => setTimeout(resolve, 25));
    assert.equal(touchCalls, 1);
    socket.close();
  } finally {
    await stopTestServer(ctx);
  }
});

test("chat message idempotency and auto-delete TTL work end-to-end", async () => {
  const ctx = await startTestServer();

  try {
    const aliceResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "ttl-alice@rodnya.app",
        password: "secret123",
        displayName: "Alice TTL",
      }),
    });
    assert.equal(aliceResponse.status, 201);
    const alice = await aliceResponse.json();

    const bobResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "ttl-bob@rodnya.app",
        password: "secret123",
        displayName: "Bob TTL",
      }),
    });
    assert.equal(bobResponse.status, 201);
    const bob = await bobResponse.json();

    const createChatResponse = await fetch(`${ctx.baseUrl}/v1/chats/direct`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${alice.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({otherUserId: bob.user.id}),
    });
    assert.equal(createChatResponse.status, 200);
    const chatPayload = await createChatResponse.json();

    const firstSendResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${chatPayload.chatId}/messages`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${alice.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          text: "Без дублей",
          clientMessageId: "local-1",
        }),
      },
    );
    assert.equal(firstSendResponse.status, 201);
    const firstSendPayload = await firstSendResponse.json();

    const retrySendResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${chatPayload.chatId}/messages`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${alice.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          text: "Без дублей",
          clientMessageId: "local-1",
        }),
      },
    );
    assert.equal(retrySendResponse.status, 200);
    const retrySendPayload = await retrySendResponse.json();
    assert.equal(retrySendPayload.message.id, firstSendPayload.message.id);

    const historyAfterRetryResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${chatPayload.chatId}/messages`,
      {
        headers: {authorization: `Bearer ${alice.accessToken}`},
      },
    );
    assert.equal(historyAfterRetryResponse.status, 200);
    const historyAfterRetry = await historyAfterRetryResponse.json();
    assert.equal(historyAfterRetry.messages.length, 1);

    const expiringMessageResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${chatPayload.chatId}/messages`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${alice.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          text: "Скоро исчезну",
          clientMessageId: "local-ttl",
          expiresInSeconds: 1,
        }),
      },
    );
    assert.equal(expiringMessageResponse.status, 201);

    await new Promise((resolve) => setTimeout(resolve, 1200));

    const historyAfterExpiryResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${chatPayload.chatId}/messages`,
      {
        headers: {authorization: `Bearer ${alice.accessToken}`},
      },
    );
    assert.equal(historyAfterExpiryResponse.status, 200);
    const historyAfterExpiry = await historyAfterExpiryResponse.json();
    assert.equal(historyAfterExpiry.messages.length, 1);
    assert.equal(historyAfterExpiry.messages[0].text, "Без дублей");
  } finally {
    await stopTestServer(ctx);
  }
});

test("presence, typing and read-state realtime updates reach chat participants", async () => {
  const ctx = await startTestServer();

  const waitFor = async (predicate, timeoutMs = 3000) => {
    const startedAt = Date.now();
    while (Date.now() - startedAt < timeoutMs) {
      const result = predicate();
      if (result) {
        return result;
      }
      await new Promise((resolve) => setTimeout(resolve, 25));
    }
    throw new Error("Timed out waiting for realtime condition");
  };

  try {
    const aliceResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "presence-alice@rodnya.app",
        password: "secret123",
        displayName: "Alice Presence",
      }),
    });
    assert.equal(aliceResponse.status, 201);
    const alice = await aliceResponse.json();

    const bobResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "presence-bob@rodnya.app",
        password: "secret123",
        displayName: "Bob Presence",
      }),
    });
    assert.equal(bobResponse.status, 201);
    const bob = await bobResponse.json();

    const createChatResponse = await fetch(`${ctx.baseUrl}/v1/chats/direct`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${alice.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({otherUserId: bob.user.id}),
    });
    assert.equal(createChatResponse.status, 200);
    const chatPayload = await createChatResponse.json();

    const bobSocket = new WebSocket(
      `${ctx.wsBaseUrl}/v1/realtime?accessToken=${bob.accessToken}`,
    );
    const bobEvents = [];
    bobSocket.addEventListener("message", (event) => {
      bobEvents.push(JSON.parse(String(event.data)));
    });
    await new Promise((resolve, reject) => {
      bobSocket.addEventListener("open", resolve, {once: true});
      bobSocket.addEventListener("error", reject, {once: true});
    });

    const aliceSocket = new WebSocket(
      `${ctx.wsBaseUrl}/v1/realtime?accessToken=${alice.accessToken}`,
    );
    const aliceEvents = [];
    aliceSocket.addEventListener("message", (event) => {
      aliceEvents.push(JSON.parse(String(event.data)));
    });
    await new Promise((resolve, reject) => {
      aliceSocket.addEventListener("open", resolve, {once: true});
      aliceSocket.addEventListener("error", reject, {once: true});
    });

    const aliceReadyPayload = await waitFor(() =>
      aliceEvents.find((item) => item.type === "connection.ready"),
    );
    assert.ok(aliceReadyPayload.onlineUserIds.includes(bob.user.id));

    const bobPresenceUpdate = await waitFor(() =>
      bobEvents.find(
        (item) =>
          item.type === "presence.updated" &&
          item.userId === alice.user.id &&
          item.isOnline === true,
      ),
    );
    assert.equal(bobPresenceUpdate.userId, alice.user.id);

    aliceSocket.send(
      JSON.stringify({
        action: "chat.typing.set",
        chatId: chatPayload.chatId,
        isTyping: true,
      }),
    );

    const typingPayload = await waitFor(() =>
      bobEvents.find(
        (item) =>
          item.type === "chat.typing.updated" &&
          item.chatId === chatPayload.chatId &&
          item.userId === alice.user.id &&
          item.isTyping === true,
      ),
    );
    assert.equal(typingPayload.chatId, chatPayload.chatId);

    const sendMessageResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${chatPayload.chatId}/messages`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${alice.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({text: "Отметь как прочитанное"}),
      },
    );
    assert.equal(sendMessageResponse.status, 201);

    const readResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${chatPayload.chatId}/read`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${bob.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({}),
      },
    );
    assert.equal(readResponse.status, 200);

    const readPayload = await waitFor(() =>
      aliceEvents.find(
        (item) =>
          item.type === "chat.read.updated" &&
          item.chatId === chatPayload.chatId &&
          item.userId === bob.user.id,
      ),
    );
    assert.equal(readPayload.userId, bob.user.id);

    aliceSocket.close();
    bobSocket.close();
  } finally {
    await stopTestServer(ctx);
  }
});

test("rustore push delivery sends notification through RuStore API", async () => {
  const observedRequests = [];
  const ctx = await startConfiguredTestServer({
    configOverrides: {
      rustorePushEnabled: true,
      rustorePushProjectId: "rustore-project-1",
      rustorePushServiceToken: "rustore-service-token",
      rustorePushApiBaseUrl: "https://vkpns.rustore.ru",
    },
    pushGatewayFactory: ({store, config}) =>
      new PushGateway({
        store,
        config,
        httpClient: async (url, options) => {
          observedRequests.push({
            url,
            method: options?.method,
            headers: options?.headers,
            body: JSON.parse(String(options?.body || "{}")),
          });
          return {
            ok: true,
            status: 200,
            text: async () => "{}",
          };
        },
      }),
  });

  try {
    const senderResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "rustore-sender@rodnya.app",
        password: "secret123",
        displayName: "Rustore Sender",
      }),
    });
    assert.equal(senderResponse.status, 201);
    const sender = await senderResponse.json();

    const recipientResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "rustore-recipient@rodnya.app",
        password: "secret123",
        displayName: "Rustore Recipient",
      }),
    });
    assert.equal(recipientResponse.status, 201);
    const recipient = await recipientResponse.json();

    const deviceResponse = await fetch(`${ctx.baseUrl}/v1/push/devices`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${recipient.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        provider: "rustore",
        token: "rustore-live-token",
        platform: "android",
      }),
    });
    assert.equal(deviceResponse.status, 201);

    const chatResponse = await fetch(`${ctx.baseUrl}/v1/chats/direct`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${sender.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({otherUserId: recipient.user.id}),
    });
    assert.equal(chatResponse.status, 200);
    const chat = await chatResponse.json();

    const sendMessageResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${chat.chatId}/messages`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${sender.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({text: "RuStore push check"}),
      },
    );
    assert.equal(sendMessageResponse.status, 201);

    assert.equal(observedRequests.length, 1);
    assert.equal(
      observedRequests[0].url,
      "https://vkpns.rustore.ru/v1/projects/rustore-project-1/messages:send",
    );
    assert.equal(observedRequests[0].method, "POST");
    assert.equal(
      observedRequests[0].headers.authorization,
      "Bearer rustore-service-token",
    );
    assert.equal(
      observedRequests[0].body.message.token,
      "rustore-live-token",
    );
    assert.equal(
      observedRequests[0].body.message.notification.title,
      "Rustore Sender",
    );
    assert.equal(
      observedRequests[0].body.message.notification.body,
      "RuStore push check",
    );
    assert.equal(
      observedRequests[0].body.message.data.type,
      "chat_message",
    );

    const deliveriesResponse = await fetch(
      `${ctx.baseUrl}/v1/push/deliveries?limit=10`,
      {
        headers: {authorization: `Bearer ${recipient.accessToken}`},
      },
    );
    assert.equal(deliveriesResponse.status, 200);
    const deliveriesPayload = await deliveriesResponse.json();
    assert.ok(
      deliveriesPayload.deliveries.some(
        (delivery) =>
          delivery.provider === "rustore" &&
          delivery.status === "sent" &&
          delivery.responseCode === 200,
      ),
    );
  } finally {
    await stopTestServer(ctx);
  }
});

test("reports, blocks and admin moderation endpoints work end-to-end", async () => {
  const ctx = await startConfiguredTestServer({
    configOverrides: {
      adminEmails: ["moderation@rodnya.app"],
    },
  });

  async function registerUser(email, displayName) {
    const response = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email,
        password: "secret123",
        displayName,
      }),
    });
    assert.equal(response.status, 201);
    return response.json();
  }

  try {
    const reporter = await registerUser("reporter@rodnya.app", "Reporter");
    const target = await registerUser("target@rodnya.app", "Target");
    const admin = await registerUser("moderation@rodnya.app", "Moderator");

    const createChatResponse = await fetch(`${ctx.baseUrl}/v1/chats/direct`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${reporter.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        otherUserId: target.user.id,
      }),
    });
    assert.equal(createChatResponse.status, 200);
    const chat = await createChatResponse.json();

    const blockResponse = await fetch(`${ctx.baseUrl}/v1/blocks`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${reporter.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        userId: target.user.id,
        reason: "spam",
      }),
    });
    assert.equal(blockResponse.status, 201);
    const blockPayload = await blockResponse.json();
    assert.equal(blockPayload.block.blockedUserId, target.user.id);
    assert.equal(blockPayload.block.blockedUserDisplayName, "Target");

    const listBlocksResponse = await fetch(`${ctx.baseUrl}/v1/blocks`, {
      headers: {authorization: `Bearer ${reporter.accessToken}`},
    });
    assert.equal(listBlocksResponse.status, 200);
    const blocksPayload = await listBlocksResponse.json();
    assert.equal(blocksPayload.blocks.length, 1);

    const blockedChatCreateResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/direct`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${reporter.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          otherUserId: target.user.id,
        }),
      },
    );
    assert.equal(blockedChatCreateResponse.status, 403);

    const blockedSendResponse = await fetch(
      `${ctx.baseUrl}/v1/chats/${chat.chatId}/messages`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${reporter.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({text: "Это сообщение не должно уйти"}),
      },
    );
    assert.equal(blockedSendResponse.status, 403);

    const reportResponse = await fetch(`${ctx.baseUrl}/v1/reports`, {
      method: "POST",
      headers: {
        authorization: `Bearer ${reporter.accessToken}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        targetType: "message",
        targetId: "msg-1",
        reason: "abuse",
        details: "Нежелательное сообщение",
      }),
    });
    assert.equal(reportResponse.status, 201);
    const reportPayload = await reportResponse.json();
    assert.equal(reportPayload.report.targetType, "message");
    assert.equal(reportPayload.report.status, "pending");

    const nonAdminReportsResponse = await fetch(
      `${ctx.baseUrl}/v1/admin/reports`,
      {
        headers: {authorization: `Bearer ${reporter.accessToken}`},
      },
    );
    assert.equal(nonAdminReportsResponse.status, 403);

    const adminReportsResponse = await fetch(`${ctx.baseUrl}/v1/admin/reports`, {
      headers: {authorization: `Bearer ${admin.accessToken}`},
    });
    assert.equal(adminReportsResponse.status, 200);
    const adminReportsPayload = await adminReportsResponse.json();
    assert.equal(adminReportsPayload.reports.length, 1);
    assert.equal(adminReportsPayload.reports[0].reporterDisplayName, "Reporter");

    const resolveResponse = await fetch(
      `${ctx.baseUrl}/v1/admin/reports/${adminReportsPayload.reports[0].id}/resolve`,
      {
        method: "POST",
        headers: {
          authorization: `Bearer ${admin.accessToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          status: "resolved",
          resolutionNote: "Проверено модератором",
        }),
      },
    );
    assert.equal(resolveResponse.status, 200);
    const resolvedPayload = await resolveResponse.json();
    assert.equal(resolvedPayload.report.status, "resolved");
    assert.ok(resolvedPayload.report.resolvedAt);

    const unblockResponse = await fetch(
      `${ctx.baseUrl}/v1/blocks/${blockPayload.block.id}`,
      {
        method: "DELETE",
        headers: {authorization: `Bearer ${reporter.accessToken}`},
      },
    );
    assert.equal(unblockResponse.status, 204);
  } finally {
    await stopTestServer(ctx);
  }
});

test("ready endpoint and auth rate limiting expose operational state", async () => {
  const ctx = await startConfiguredTestServer({
    configOverrides: {
      adminEmails: ["ops-admin@rodnya.app"],
      authRateLimitMax: 3,
      rateLimitWindowMs: 60_000,
    },
    runtimeInfo: {
      releaseLabel: "test-release-ops",
      startedAt: "2026-04-20T09:00:00.000Z",
      pid: 4242,
      nodeVersion: "v22.0.0-test",
    },
  });

  try {
    const healthResponse = await fetch(`${ctx.baseUrl}/health`);
    assert.equal(healthResponse.status, 200);
    assert.equal(healthResponse.headers.get("x-rodnya-release"), "test-release-ops");
    const healthPayload = await healthResponse.json();
    assert.equal(healthPayload.runtime.releaseLabel, "test-release-ops");
    assert.equal(healthPayload.runtime.pid, 4242);
    assert.equal(healthPayload.adminEmailsConfigured, 1);

    const readyResponse = await fetch(`${ctx.baseUrl}/ready`);
    assert.equal(readyResponse.status, 200);
    const readyPayload = await readyResponse.json();
    assert.equal(readyPayload.status, "ready");
    assert.equal(readyPayload.storage, "file-store");
    assert.equal(readyPayload.media, "local-filesystem");
    assert.equal(readyPayload.liveKitEnabled, false);
    assert.ok(Array.isArray(readyPayload.warnings));
    assert.equal(readyPayload.runtime.releaseLabel, "test-release-ops");
    assert.equal(readyPayload.runtime.realtime.onlineUsers, 0);
    assert.ok(readyPayload.requestId);

    const adminRegisterResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "ops-admin@rodnya.app",
        password: "secret123",
        displayName: "Ops Admin",
      }),
    });
    assert.equal(adminRegisterResponse.status, 201);
    const admin = await adminRegisterResponse.json();

    const runtimeResponse = await fetch(`${ctx.baseUrl}/v1/admin/runtime`, {
      headers: {authorization: `Bearer ${admin.accessToken}`},
    });
    assert.equal(runtimeResponse.status, 200);
    const runtimePayload = await runtimeResponse.json();
    assert.equal(runtimePayload.runtime.releaseLabel, "test-release-ops");
    assert.equal(runtimePayload.adminEmailsConfigured, 1);

    for (let index = 0; index < 2; index += 1) {
      const loginResponse = await fetch(`${ctx.baseUrl}/v1/auth/login`, {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({
          email: "missing@rodnya.app",
          password: "nope",
        }),
      });
      assert.equal(loginResponse.status, 401);
    }

    const throttledResponse = await fetch(`${ctx.baseUrl}/v1/auth/login`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "missing@rodnya.app",
        password: "nope",
      }),
    });
    assert.equal(throttledResponse.status, 429);
    assert.equal(throttledResponse.headers.get("x-ratelimit-limit"), "3");
    assert.ok(throttledResponse.headers.get("retry-after"));
    const throttledPayload = await throttledResponse.json();
    assert.ok(throttledPayload.requestId);
  } finally {
    await stopTestServer(ctx);
  }
});

test("ready endpoint prefers lightweight store health check when available", async () => {
  const ctx = await startConfiguredTestServer();

  try {
    let healthCheckCalls = 0;
    ctx.store.healthCheck = async () => {
      healthCheckCalls += 1;
    };
    ctx.store._read = async () => {
      throw new Error("ready_should_not_read_full_state");
    };

    const readyResponse = await fetch(`${ctx.baseUrl}/ready`);
    assert.equal(readyResponse.status, 200);
    const readyPayload = await readyResponse.json();
    assert.equal(readyPayload.status, "ready");
    assert.equal(healthCheckCalls, 1);
  } finally {
    await stopTestServer(ctx);
  }
});

test("auth session endpoint can serve from cached auth context", async () => {
  const ctx = await startTestServer();

  try {
    const registerResponse = await fetch(`${ctx.baseUrl}/v1/auth/register`, {
      method: "POST",
      headers: {"content-type": "application/json"},
      body: JSON.stringify({
        email: "cache-auth@rodnya.app",
        password: "secret123",
        displayName: "Cache Auth",
      }),
    });
    assert.equal(registerResponse.status, 201);
    const registered = await registerResponse.json();

    ctx.store._read = async () => {
      throw new Error("store_read_should_not_be_used");
    };

    const sessionResponse = await fetch(`${ctx.baseUrl}/v1/auth/session`, {
      headers: {authorization: `Bearer ${registered.accessToken}`},
    });
    assert.equal(sessionResponse.status, 200);
    const sessionPayload = await sessionResponse.json();
    assert.equal(sessionPayload.user.email, "cache-auth@rodnya.app");
  } finally {
    await stopTestServer(ctx);
  }
});
