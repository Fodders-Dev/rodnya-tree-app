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
