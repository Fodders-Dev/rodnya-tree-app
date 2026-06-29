const fs = require("node:fs/promises");
const path = require("node:path");

function normalizeRuntimeInfo(runtimeInfo) {
  return {
    startedAt:
      String(runtimeInfo?.startedAt || "").trim() || new Date().toISOString(),
    releaseLabel: String(runtimeInfo?.releaseLabel || "").trim() || null,
    pid:
      Number.isFinite(runtimeInfo?.pid) && runtimeInfo.pid > 0
        ? runtimeInfo.pid
        : process.pid,
    nodeVersion:
      String(runtimeInfo?.nodeVersion || "").trim() || process.version,
  };
}

function resolveStorageMode({store, config}) {
  const configuredStorageBackend = String(config?.storageBackend || "")
    .trim()
    .toLowerCase();
  return (
    String(
      store?.storageMode ||
        (configuredStorageBackend === "file" ? "file-store" : "") ||
        configuredStorageBackend ||
        "unknown",
    ).trim() || "unknown"
  );
}

function resolveMediaMode({mediaStorage, config}) {
  return (
    String(mediaStorage?.mediaMode || config?.mediaBackend || "unknown").trim() ||
    "unknown"
  );
}

function createOperationalStatus({
  store,
  config,
  realtimeHub = null,
  mediaStorage = null,
  liveKitService = null,
  vkAuthClient = null,
  maxAuthClient = null,
  runtimeInfo = null,
}) {
  const storageMode = resolveStorageMode({store, config});
  const mediaMode = resolveMediaMode({mediaStorage, config});
  const normalizedRuntimeInfo = normalizeRuntimeInfo(runtimeInfo);

  function buildRuntimeSnapshot() {
    const startedAtDate = new Date(normalizedRuntimeInfo.startedAt);
    const startedAtMs = Number.isNaN(startedAtDate.getTime())
      ? Date.now()
      : startedAtDate.getTime();
    const uptimeSeconds = Math.max(
      0,
      Math.round((Date.now() - startedAtMs) / 1000),
    );
    return {
      startedAt: new Date(startedAtMs).toISOString(),
      uptimeSeconds,
      pid: normalizedRuntimeInfo.pid,
      nodeVersion: normalizedRuntimeInfo.nodeVersion,
      releaseLabel: normalizedRuntimeInfo.releaseLabel,
      recentErrors:
        typeof runtimeInfo?.listRecentErrors === "function"
          ? runtimeInfo.listRecentErrors()
          : [],
      realtime:
        typeof realtimeHub?.describeRuntimeStats === "function"
          ? realtimeHub.describeRuntimeStats()
          : {
              onlineUsers: 0,
              activeSockets: 0,
              wsAttached: false,
            },
    };
  }

  function buildOperationalWarnings() {
    const warnings = [];
    if (storageMode === "file-store") {
      warnings.push(
        "file-store backend is acceptable for dev and smoke, but not the final production target",
      );
    }
    if (mediaMode === "local-filesystem") {
      warnings.push(
        "local filesystem media storage is acceptable for dev and smoke, but not the final production target",
      );
    }
    if (!Array.isArray(config.adminEmails) || config.adminEmails.length === 0) {
      warnings.push(
        "admin emails are not configured; moderator-only runtime/admin views stay unavailable",
      );
    }
    return warnings;
  }

  function buildStatusPayload(
    status,
    {requestId, ready = true, message = null} = {},
  ) {
    return {
      status,
      service: "rodnya-minimal-backend",
      ready,
      message,
      storage: storageMode,
      media: mediaMode,
      publicApiUrl: config.publicApiUrl || null,
      publicAppUrl: config.publicAppUrl || null,
      rustorePushEnabled: config.rustorePushEnabled === true,
      fcmPushEnabled: config.fcmPushEnabled === true,
      webPushEnabled: config.webPushEnabled === true,
      liveKitEnabled: liveKitService?.isConfigured === true,
      // Ship Q3a (2026-05-26): full provider availability surface.
      // Existing flat vkAuthEnabled / maxAuthEnabled preserved для
      // backward compat (deploy smoke contract). Plus new googleAuth
      // Enabled + telegramAuthEnabled flat fields + grouped object
      // `authProviders` для idiomatic frontend reading. Frontend uses
      // grouped form, ops dashboards / scripts могут поднимать flat.
      vkAuthEnabled: vkAuthClient?.isEnabled === true,
      maxAuthEnabled: maxAuthClient?.isEnabled === true,
      googleAuthEnabled: config.googleAuthEnabled === true,
      telegramAuthEnabled: config.telegramLoginEnabled === true,
      authProviders: {
        google: config.googleAuthEnabled === true,
        vk: vkAuthClient?.isEnabled === true,
        telegram: config.telegramLoginEnabled === true,
        max: maxAuthClient?.isEnabled === true,
      },
      adminEmailsConfigured: Array.isArray(config.adminEmails)
        ? config.adminEmails.length
        : 0,
      warnings: buildOperationalWarnings(),
      runtime: buildRuntimeSnapshot(),
      requestId,
    };
  }

  async function ensureReady() {
    if (typeof store?.healthCheck === "function") {
      await store.healthCheck();
    } else {
      if (storageMode === "file-store") {
        const dataDir = path.dirname(config.dataPath);
        await fs.mkdir(dataDir, {recursive: true});
        await fs.access(dataDir);
      }
      if (typeof store?.initialize === "function") {
        await store.initialize();
      }
      if (typeof store?._read === "function") {
        await store._read();
      }
    }
    await mediaStorage.ensureReady();
  }

  return {
    normalizedRuntimeInfo,
    buildStatusPayload,
    ensureReady,
  };
}

module.exports = {
  createOperationalStatus,
  normalizeRuntimeInfo,
  resolveMediaMode,
  resolveStorageMode,
};
