const test = require("node:test");
const assert = require("node:assert/strict");

const {
  createOperationalStatus,
  normalizeRuntimeInfo,
  resolveMediaMode,
  resolveStorageMode,
} = require("../src/operational-status");

test("normalizeRuntimeInfo keeps configured release metadata", () => {
  const runtimeInfo = normalizeRuntimeInfo({
    startedAt: "2026-04-20T09:00:00.000Z",
    releaseLabel: "release-1",
    pid: 4242,
    nodeVersion: "v22.0.0-test",
  });

  assert.deepEqual(runtimeInfo, {
    startedAt: "2026-04-20T09:00:00.000Z",
    releaseLabel: "release-1",
    pid: 4242,
    nodeVersion: "v22.0.0-test",
  });
});

test("operational status resolves storage and media modes from runtime dependencies", () => {
  assert.equal(
    resolveStorageMode({
      store: {storageMode: "postgres"},
      config: {storageBackend: "file"},
    }),
    "postgres",
  );
  assert.equal(
    resolveStorageMode({
      store: {},
      config: {storageBackend: "file"},
    }),
    "file-store",
  );
  assert.equal(
    resolveMediaMode({
      mediaStorage: {mediaMode: "s3"},
      config: {mediaBackend: "local-filesystem"},
    }),
    "s3",
  );
});

test("operational status payload preserves deploy smoke contract", () => {
  const status = createOperationalStatus({
    store: {storageMode: "file-store"},
    config: {
      adminEmails: ["ops@rodnya.app"],
      mediaBackend: "local-filesystem",
      publicApiUrl: "https://api.rodnya-tree.ru",
      publicAppUrl: "https://rodnya-tree.ru",
      rustorePushEnabled: true,
      webPushEnabled: false,
    },
    realtimeHub: {
      describeRuntimeStats: () => ({
        onlineUsers: 2,
        activeSockets: 3,
        wsAttached: true,
      }),
    },
    mediaStorage: {mediaMode: "s3", ensureReady: async () => {}},
    liveKitService: {isConfigured: false},
    vkAuthClient: {isEnabled: true},
    maxAuthClient: {isEnabled: true},
    runtimeInfo: {
      startedAt: "2026-04-20T09:00:00.000Z",
      releaseLabel: "release-ops",
      pid: 4242,
      nodeVersion: "v22.0.0-test",
    },
  });

  const payload = status.buildStatusPayload("ready", {
    requestId: "request-1",
  });

  assert.equal(payload.status, "ready");
  assert.equal(payload.storage, "file-store");
  assert.equal(payload.media, "s3");
  assert.equal(payload.adminEmailsConfigured, 1);
  assert.equal(payload.vkAuthEnabled, true);
  assert.equal(payload.maxAuthEnabled, true);
  assert.equal(payload.runtime.releaseLabel, "release-ops");
  assert.equal(payload.runtime.pid, 4242);
  assert.equal(payload.runtime.realtime.onlineUsers, 2);
  assert.equal(payload.requestId, "request-1");
});

// ── Ship Q3a (2026-05-26): backend auth provider capability gate ──
//
// Finishes UX audit 2026-05-25 Critical #3 — frontend can now hide
// ANY unconfigured social-login button (not just Google as Q3 did).
// `authProviders` grouped object is the idiomatic frontend shape;
// flat googleAuthEnabled + telegramAuthEnabled added for ops parity
// с existing vk/max flat fields.

test("Q3a: buildStatusPayload exposes all 4 auth providers", () => {
  const status = createOperationalStatus({
    store: {storageMode: "file-store"},
    config: {
      adminEmails: [],
      mediaBackend: "local-filesystem",
      googleAuthEnabled: true,
      telegramLoginEnabled: true,
    },
    realtimeHub: null,
    mediaStorage: {mediaMode: "s3", ensureReady: async () => {}},
    liveKitService: {isConfigured: false},
    vkAuthClient: {isEnabled: true},
    maxAuthClient: {isEnabled: false},
    runtimeInfo: {
      startedAt: "2026-05-26T00:00:00.000Z",
      releaseLabel: "q3a-test",
      pid: 1,
      nodeVersion: "v22.0.0-test",
    },
  });

  const payload = status.buildStatusPayload("ready", {requestId: "r"});

  // Flat fields — backward-compat ops dashboards.
  assert.equal(payload.googleAuthEnabled, true);
  assert.equal(payload.telegramAuthEnabled, true);
  assert.equal(payload.vkAuthEnabled, true);
  assert.equal(payload.maxAuthEnabled, false);

  // Grouped object — primary frontend reader path.
  assert.ok(payload.authProviders, "authProviders object missing");
  assert.equal(payload.authProviders.google, true);
  assert.equal(payload.authProviders.telegram, true);
  assert.equal(payload.authProviders.vk, true);
  assert.equal(payload.authProviders.max, false);
});

test("Q3a: providers default to false when config flags absent", () => {
  const status = createOperationalStatus({
    store: {storageMode: "file-store"},
    config: {adminEmails: [], mediaBackend: "local-filesystem"},
    mediaStorage: {mediaMode: "local-filesystem", ensureReady: async () => {}},
    runtimeInfo: {
      startedAt: "2026-05-26T00:00:00.000Z",
      releaseLabel: null,
      pid: 1,
      nodeVersion: "v22.0.0-test",
    },
  });

  const payload = status.buildStatusPayload("ready", {requestId: "r"});

  assert.equal(payload.authProviders.google, false);
  assert.equal(payload.authProviders.telegram, false);
  assert.equal(payload.authProviders.vk, false);
  assert.equal(payload.authProviders.max, false);
  assert.equal(payload.googleAuthEnabled, false);
  assert.equal(payload.telegramAuthEnabled, false);
});
