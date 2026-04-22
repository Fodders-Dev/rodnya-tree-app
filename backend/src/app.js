const express = require("express");
const cors = require("cors");
const crypto = require("node:crypto");
const fs = require("node:fs/promises");
const path = require("node:path");

const {
  computeProfileStatus,
  composeDisplayName,
  normalizeProfileContributionPolicy,
  normalizePrimaryTrustedChannel,
  normalizePublicUrl,
  normalizePublicUrlList,
  sanitizeProfile,
  sanitizeUserProfilePreview,
} = require("./profile-utils");
const {PushGateway} = require("./push-gateway");
const {createMediaStorage} = require("./media-storage");
const {createGoogleTokenVerifier} = require("./google-auth");
const {
  buildVkAuthorizeUrl,
  createVkAuthClient,
  createVkPkcePair,
} = require("./vk-auth");
const {createMaxAuthClient, parseMaxStartParam} = require("./max-auth");
const {createLiveKitService} = require("./livekit-service");
const {buildBranchVisiblePersonIds} = require("./store");

const DEFAULT_CALL_INVITE_TIMEOUT_MS = 30_000;

function createApp({
  store,
  config,
  realtimeHub = null,
  pushGateway = null,
  mediaStorage = null,
  googleTokenVerifier = null,
  vkAuthClient = null,
  maxAuthClient = null,
  liveKitService = null,
  runtimeInfo = null,
}) {
  const app = express();
  const resolvedPushGateway =
    pushGateway ?? new PushGateway({store, config});
  const resolvedMediaStorage = mediaStorage ?? createMediaStorage(config);
  const resolvedGoogleTokenVerifier =
    googleTokenVerifier ?? createGoogleTokenVerifier(config);
  const resolvedVkAuthClient = vkAuthClient ?? createVkAuthClient(config);
  const resolvedMaxAuthClient = maxAuthClient ?? createMaxAuthClient(config);
  const resolvedLiveKitService = liveKitService ?? createLiveKitService(config);
  const rateLimitState = new Map();
  const configuredStorageBackend = String(config?.storageBackend || "")
    .trim()
    .toLowerCase();
  const storageMode = String(
    store?.storageMode ||
      (configuredStorageBackend === "file" ? "file-store" : "") ||
      configuredStorageBackend ||
      "unknown",
  ).trim() || "unknown";
  const mediaMode = String(
    resolvedMediaStorage?.mediaMode ||
      config?.mediaBackend ||
      "unknown",
  ).trim() || "unknown";
  const normalizedRuntimeInfo = {
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
  const ringTimeoutTimers = new Map();
  const configuredCallInviteTimeoutMs = Number(config?.callInviteTimeoutMs);
  const callInviteTimeoutMs =
    Number.isFinite(configuredCallInviteTimeoutMs) &&
    configuredCallInviteTimeoutMs > 0
      ? Math.floor(configuredCallInviteTimeoutMs)
      : DEFAULT_CALL_INVITE_TIMEOUT_MS;

  function clearCallInviteTimeout(callId) {
    const normalizedCallId = String(callId || "").trim();
    if (!normalizedCallId) {
      return;
    }
    const existingTimer = ringTimeoutTimers.get(normalizedCallId);
    if (existingTimer) {
      clearTimeout(existingTimer);
      ringTimeoutTimers.delete(normalizedCallId);
    }
  }

  function publishCallState(call) {
    if (!call || typeof call !== "object") {
      return;
    }

    for (const participantId of call.participantIds || []) {
      realtimeHub?.publishToUser(participantId, {
        type: "call.state.updated",
        call: mapCallRecord(call, {viewerUserId: participantId}),
      });
    }
  }

  function scheduleCallInviteTimeout(call) {
    if (
      !call ||
      typeof call !== "object" ||
      call.state !== "ringing" ||
      callInviteTimeoutMs <= 0
    ) {
      return;
    }

    clearCallInviteTimeout(call.id);
    const createdAtMs = new Date(call.createdAt || 0).getTime();
    const elapsedMs = Number.isFinite(createdAtMs)
      ? Math.max(0, Date.now() - createdAtMs)
      : 0;
    const delayMs = Math.max(250, callInviteTimeoutMs - elapsedMs);
    const timer = setTimeout(async () => {
      ringTimeoutTimers.delete(call.id);
      try {
        const expiredCall =
          typeof store.markCallMissed === "function"
            ? await store.markCallMissed({
                callId: call.id,
                reason: "missed",
              })
            : null;
        if (!expiredCall) {
          return;
        }
        logCallEvent("invite.missed", expiredCall, {
          timeoutMs: callInviteTimeoutMs,
        });
        publishCallState(expiredCall);
      } catch (error) {
        console.error(
          "[backend] call timeout",
          JSON.stringify({
            callId: call.id || null,
            message: String(error?.message || error || "unknown_error"),
          }),
        );
      }
    }, delayMs);
    if (typeof timer?.unref === "function") {
      timer.unref();
    }
    ringTimeoutTimers.set(call.id, timer);
  }

  function isCallInviteExpired(call) {
    if (
      !call ||
      typeof call !== "object" ||
      call.state !== "ringing" ||
      callInviteTimeoutMs <= 0
    ) {
      return false;
    }

    const createdAtMs = new Date(call.createdAt || 0).getTime();
    if (!Number.isFinite(createdAtMs) || createdAtMs <= 0) {
      return false;
    }
    return Date.now() - createdAtMs >= callInviteTimeoutMs;
  }

  async function expireRingingCallIfNeeded(call, {
    reason = "missed",
    eventType = "invite.missed",
    extra = {},
  } = {}) {
    if (!isCallInviteExpired(call)) {
      return call;
    }

    const expiredCall =
      typeof store.markCallMissed === "function"
        ? await store.markCallMissed({
            callId: call.id,
            reason,
          })
        : null;
    if (!expiredCall) {
      return store.findCall(call.id);
    }
    if (expiredCall.state === "ringing") {
      return expiredCall;
    }

    clearCallInviteTimeout(expiredCall.id);
    logCallEvent(eventType, expiredCall, {
      timeoutMs: callInviteTimeoutMs,
      lazyExpired: true,
      ...extra,
    });
    publishCallState(expiredCall);
    return expiredCall;
  }

  async function findFreshCall(callId, {viewerUserId = null} = {}) {
    const call = await store.findCall(callId);
    if (!call) {
      return null;
    }
    const expiredCall = await expireRingingCallIfNeeded(call, {
      reason: "missed",
      eventType: "invite.missed",
      extra: {
        viewerUserId,
        source: "find_call",
      },
    });
    return expiredCall || call;
  }

  async function findFreshActiveCall({userId, chatId = null} = {}) {
    const activeCall = await store.findActiveCall({userId, chatId});
    if (!activeCall) {
      return null;
    }
    const expiredCall = await expireRingingCallIfNeeded(activeCall, {
      reason: "missed",
      eventType: "invite.missed",
      extra: {
        viewerUserId: userId,
        chatId: chatId || activeCall.chatId,
        source: "find_active_call",
      },
    });
    if (!expiredCall || expiredCall.state === "ringing") {
      return expiredCall || activeCall;
    }
    return store.findActiveCall({userId, chatId});
  }

  async function reconcileUserBusyCall(userId, {chatId = null} = {}) {
    const busyCall = await store.findActiveCall({userId, chatId});
    if (!busyCall) {
      return null;
    }
    const expiredCall = await expireRingingCallIfNeeded(busyCall, {
      reason: "missed",
      eventType: "invite.missed",
      extra: {
        viewerUserId: userId,
        chatId: chatId || busyCall.chatId,
        source: "pre_invite_reconcile",
      },
    });
    return expiredCall || busyCall;
  }

  async function restoreRingingCallTimeouts() {
    if (typeof store.listRingingCalls !== "function") {
      return;
    }
    try {
      const ringingCalls = await store.listRingingCalls();
      for (const call of ringingCalls) {
        scheduleCallInviteTimeout(call);
      }
    } catch (error) {
      console.error(
        "[backend] restore ringing calls",
        JSON.stringify({
          message: String(error?.message || error || "unknown_error"),
        }),
      );
    }
  }

  void restoreRingingCallTimeouts();

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

  function buildStatusPayload(status, {requestId, ready = true, message = null} = {}) {
    const warnings = buildOperationalWarnings();
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
      webPushEnabled: config.webPushEnabled === true,
      liveKitEnabled: resolvedLiveKitService.isConfigured === true,
      vkAuthEnabled: resolvedVkAuthClient.isEnabled === true,
      maxAuthEnabled: resolvedMaxAuthClient.isEnabled === true,
      adminEmailsConfigured: Array.isArray(config.adminEmails)
        ? config.adminEmails.length
        : 0,
      warnings,
      runtime: buildRuntimeSnapshot(),
      requestId,
    };
  }

  function scheduleSessionTouch(res, token, {requestId, userId} = {}) {
    if (typeof store?.touchSession !== "function") {
      return;
    }

    let started = false;
    const runTouch = () => {
      if (started) {
        return;
      }
      started = true;
      void Promise.resolve()
        .then(() => store.touchSession(token))
        .catch((error) => {
          console.warn(
            "[backend] touch session failed",
            JSON.stringify({
              requestId: requestId || null,
              userId: userId || null,
              message: String(error?.message || error || "unknown_error"),
            }),
          );
        });
    };

    res.once("finish", runTouch);
    res.once("close", runTouch);
  }

  app.set("trust proxy", true);
  app.use(cors({origin: config.corsOrigin}));
  app.use((req, res, next) => {
    const forwardedRequestId = String(req.get("x-request-id") || "").trim();
    req.requestId = forwardedRequestId || crypto.randomUUID();
    req.startedAt = Date.now();
    res.setHeader("x-request-id", req.requestId);
    if (normalizedRuntimeInfo.releaseLabel) {
      res.setHeader("x-rodnya-release", normalizedRuntimeInfo.releaseLabel);
    }
    next();
  });
  app.use((req, res, next) => {
    const pathName = req.path || req.originalUrl || "/";
    if (pathName === "/health" || pathName === "/ready") {
      next();
      return;
    }

    const startedAt = Date.now();
    res.on("finish", () => {
      const durationMs = Date.now() - startedAt;
      const shouldLog =
        res.statusCode >= 400 ||
        req.method !== "GET" ||
        durationMs >= 1000 ||
        pathName.startsWith("/v1/admin/");
      if (!shouldLog) {
        return;
      }

      console.log(
        "[backend] request",
        JSON.stringify({
          requestId: req.requestId,
          method: req.method,
          path: pathName,
          statusCode: res.statusCode,
          durationMs,
          ip: req.ip,
        }),
      );
    });
    next();
  });
  app.post(
    "/v1/livekit/webhook",
    express.text({type: "*/*"}),
    async (req, res) => {
      try {
        const authHeader =
          String(req.get("Authorization") || "").trim() ||
          String(req.get("Authorize") || "").trim() ||
          String(req.get("x-livekit-signature") || "").trim();
        const body =
          typeof req.body === "string" ? req.body : JSON.stringify(req.body || {});
        const event = await resolvedLiveKitService.receiveWebhook(body, authHeader);
        const roomName = String(event?.room?.name || event?.room?.sid || "").trim();
        const participantIdentity = String(
          event?.participant?.identity || "",
        ).trim();
        const call = await store.applyCallWebhook({
          roomName,
          event: event?.event,
          participantIdentity,
        });
        if (call) {
          if (call.state === "ringing") {
            scheduleCallInviteTimeout(call);
          } else {
            clearCallInviteTimeout(call.id);
          }
          logCallEvent("webhook.processed", call, {
            webhookEvent: String(event?.event || "").trim() || null,
            participantIdentity: participantIdentity || null,
            roomName: roomName || null,
          });
          publishCallState(call);
        }
        res.json({ok: true});
      } catch (error) {
        res.status(401).json({message: "Webhook verification failed"});
      }
    },
  );
  // Some legacy/mobile clients still send JSON literal `null` on bodyless POSTs
  // such as like/view/read actions. Accept it and let handlers validate fields.
  app.use(express.json({limit: "50mb", strict: false}));
  app.get(/^\/media\/(.+)$/, async (req, res) => {
    try {
      await resolvedMediaStorage.handleGetRequest(req, res);
    } catch (error) {
      if (
        error?.message === "INVALID_MEDIA_PATH" ||
        error?.message === "UNSUPPORTED_MEDIA_URL"
      ) {
        res.status(400).json({message: "Недопустимый media path"});
        return;
      }
      if (error?.message === "MEDIA_FILE_NOT_FOUND") {
        res.status(404).json({message: "Media файл не найден"});
        return;
      }
      if (!res.headersSent) {
        res.status(502).json({message: "Не удалось открыть media файл"});
      }
    }
  });
  app.get(/^\/storage\/(.+)$/, async (req, res) => {
    try {
      await resolvedMediaStorage.handlePublicGetRequest(req, res);
    } catch (error) {
      if (
        error?.message === "INVALID_MEDIA_PATH" ||
        error?.message === "UNSUPPORTED_MEDIA_URL"
      ) {
        res.status(400).json({message: "Недопустимый media path"});
        return;
      }
      if (error?.message === "MEDIA_FILE_NOT_FOUND") {
        res.status(404).json({message: "Media файл не найден"});
        return;
      }
      if (!res.headersSent) {
        res.status(502).json({message: "Не удалось открыть media файл"});
      }
    }
  });
  app.use((req, res, next) => {
    const policy = (() => {
      const pathName = req.path || "/";
      if (pathName === "/health" || pathName === "/ready") {
        return null;
      }
      if (pathName.startsWith("/media/")) {
        return null;
      }
      if (pathName.startsWith("/storage/")) {
        return null;
      }
      if (
        pathName === "/v1/auth/login" ||
        pathName === "/v1/auth/register" ||
        pathName === "/v1/auth/password-reset"
      ) {
        return {bucket: "auth", limit: config.authRateLimitMax};
      }
      if (pathName === "/v1/media/upload") {
        return {bucket: "upload", limit: config.uploadRateLimitMax};
      }
      if (pathName === "/v1/reports" || pathName.startsWith("/v1/blocks")) {
        return {bucket: "safety", limit: config.safetyRateLimitMax};
      }
      if (!["GET", "HEAD", "OPTIONS"].includes(req.method)) {
        return {bucket: "mutation", limit: config.mutationRateLimitMax};
      }
      return {bucket: "default", limit: config.defaultRateLimitMax};
    })();

    if (!policy || !Number.isFinite(policy.limit) || policy.limit <= 0) {
      next();
      return;
    }

    const now = Date.now();
    const windowMs = Number.isFinite(config.rateLimitWindowMs) &&
        config.rateLimitWindowMs > 0
      ? config.rateLimitWindowMs
      : 60_000;
    const actorId = String(req.ip || "unknown").trim() || "unknown";
    const key = `${policy.bucket}:${actorId}`;
    const current = rateLimitState.get(key);
    const activeBucket = current && current.resetAt > now
      ? current
      : {count: 0, resetAt: now + windowMs};
    activeBucket.count += 1;
    rateLimitState.set(key, activeBucket);

    if (Math.random() < 0.01 && rateLimitState.size > 2000) {
      for (const [bucketKey, bucket] of rateLimitState.entries()) {
        if (!bucket || bucket.resetAt <= now) {
          rateLimitState.delete(bucketKey);
        }
      }
    }

    res.setHeader("x-ratelimit-limit", String(policy.limit));
    res.setHeader(
      "x-ratelimit-remaining",
      String(Math.max(0, policy.limit - activeBucket.count)),
    );
    res.setHeader(
      "x-ratelimit-reset",
      String(Math.ceil(activeBucket.resetAt / 1000)),
    );

    if (activeBucket.count > policy.limit) {
      const retryAfterSeconds = Math.max(
        1,
        Math.ceil((activeBucket.resetAt - now) / 1000),
      );
      res.setHeader("retry-after", String(retryAfterSeconds));
      res.status(429).json({
        message: "Слишком много запросов. Повторите попытку позже.",
        requestId: req.requestId,
      });
      return;
    }

    next();
  });

  app.get("/health", async (req, res) => {
    res.json(
      buildStatusPayload("ok", {
        requestId: req.requestId,
      }),
    );
  });

  app.get("/ready", async (req, res) => {
    try {
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
      await resolvedMediaStorage.ensureReady();
      res.json(
        buildStatusPayload("ready", {
          requestId: req.requestId,
        }),
      );
    } catch (error) {
      res.status(503).json({
        ...buildStatusPayload("not_ready", {
          requestId: req.requestId,
          ready: false,
          message: "Backend storage paths are not accessible",
        }),
        errorCode: String(error?.code || error?.message || "NOT_READY"),
      });
    }
  });

  async function requirePublicTree(req, res, publicTreeId) {
    const tree = await store.findPublicTreeByRouteId(publicTreeId);
    if (!tree) {
      res.status(404).json({message: "Публичное дерево не найдено"});
      return null;
    }
    return tree;
  }

  async function requireAuth(req, res, next) {
    const header = req.headers.authorization || "";
    const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";

    if (!token) {
      res.status(401).json({message: "Требуется Bearer token"});
      return;
    }

    const session = await store.findSession(token);
    if (!session) {
      res.status(401).json({message: "Сессия не найдена или истекла"});
      return;
    }

    const user = await store.findUserById(session.userId);
    if (!user) {
      res.status(401).json({message: "Пользователь сессии не найден"});
      return;
    }

    req.auth = {token, session, user};
    scheduleSessionTouch(res, token, {
      requestId: req.requestId,
      userId: user.id,
    });
    next();
  }

  function requireOwnUser(req, res) {
    if (req.params.userId !== req.auth.user.id) {
      res.status(403).json({message: "Доступ к чужим данным запрещен"});
      return false;
    }
    return true;
  }

  function mapProfileNote(note) {
    return {
      id: note.id,
      title: note.title,
      content: note.content,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
    };
  }

  function mapTree(tree) {
    return {
      id: tree.id,
      name: tree.name,
      description: tree.description,
      creatorId: tree.creatorId,
      memberIds: Array.isArray(tree.memberIds) ? tree.memberIds : [],
      members: Array.isArray(tree.members) ? tree.members : [],
      createdAt: tree.createdAt,
      updatedAt: tree.updatedAt,
      isPrivate: tree.isPrivate !== false,
      kind: tree.kind === "friends" ? "friends" : "family",
      publicSlug: tree.publicSlug || null,
      isCertified: tree.isCertified === true,
      certificationNote: tree.certificationNote || null,
    };
  }

  function mapPerson(person) {
    const familySummary =
      person.familySummary || person.notes || person.bio || null;
    return {
      id: person.id,
      treeId: person.treeId,
      userId: person.userId,
      identityId: person.identityId || null,
      name: person.name,
      maidenName: person.maidenName,
      photoUrl: normalizePublicUrl(person.photoUrl),
      primaryPhotoUrl: normalizePublicUrl(
        person.primaryPhotoUrl || person.photoUrl || null,
      ),
      photoGallery: Array.isArray(person.photoGallery)
        ? person.photoGallery.map((entry) => ({
            id: entry.id,
            url: normalizePublicUrl(entry.url),
            thumbnailUrl: normalizePublicUrl(entry.thumbnailUrl || null),
            type: entry.type || "image",
            contentType: entry.contentType || null,
            caption: entry.caption || null,
            createdAt: entry.createdAt || null,
            updatedAt: entry.updatedAt || null,
            isPrimary: entry.isPrimary === true,
          }))
        : [],
      gender: person.gender,
      birthDate: person.birthDate,
      birthPlace: person.birthPlace,
      deathDate: person.deathDate,
      deathPlace: person.deathPlace,
      familySummary,
      bio: familySummary,
      isAlive: person.isAlive !== false,
      creatorId: person.creatorId,
      createdAt: person.createdAt,
      updatedAt: person.updatedAt,
      notes: familySummary,
      details: person.details || null,
    };
  }

  function mapProfileContribution(contribution) {
    const fields =
      contribution?.fields && typeof contribution.fields === "object"
        ? contribution.fields
        : {};
    return {
      id: contribution.id,
      treeId: contribution.treeId,
      personId: contribution.personId,
      targetUserId: contribution.targetUserId,
      authorUserId: contribution.authorUserId || null,
      authorDisplayName: contribution.authorDisplayName || null,
      authorPhotoUrl: normalizePublicUrl(contribution.authorPhotoUrl || null),
      message: contribution.message || null,
      fields,
      status: contribution.status || "pending",
      createdAt: contribution.createdAt || null,
      updatedAt: contribution.updatedAt || null,
      respondedAt: contribution.respondedAt || null,
      responderUserId: contribution.responderUserId || null,
    };
  }

  function mapRelation(relation) {
    return {
      id: relation.id,
      treeId: relation.treeId,
      person1Id: relation.person1Id,
      person2Id: relation.person2Id,
      relation1to2: relation.relation1to2,
      relation2to1: relation.relation2to1,
      isConfirmed: relation.isConfirmed === true,
      createdAt: relation.createdAt,
      updatedAt: relation.updatedAt,
      createdBy: relation.createdBy,
      marriageDate: relation.marriageDate || null,
      divorceDate: relation.divorceDate || null,
      customRelationLabel1to2: relation.customRelationLabel1to2 || null,
      customRelationLabel2to1: relation.customRelationLabel2to1 || null,
      parentSetId: relation.parentSetId || null,
      parentSetType: relation.parentSetType || null,
      isPrimaryParentSet:
        typeof relation.isPrimaryParentSet === "boolean"
          ? relation.isPrimaryParentSet
          : null,
      unionId: relation.unionId || null,
      unionType: relation.unionType || null,
      unionStatus: relation.unionStatus || null,
    };
  }

  function mapTreeGraphSnapshot(snapshot) {
    return {
      treeId: snapshot.treeId,
      viewerPersonId: snapshot.viewerPersonId || null,
      people: Array.isArray(snapshot.people) ? snapshot.people.map(mapPerson) : [],
      relations: Array.isArray(snapshot.relations)
        ? snapshot.relations.map(mapRelation)
        : [],
      familyUnits: Array.isArray(snapshot.familyUnits)
        ? snapshot.familyUnits.map((unit) => ({
            id: unit.id,
            rootParentSetId: unit.rootParentSetId || null,
            adultIds: Array.isArray(unit.adultIds) ? unit.adultIds : [],
            childIds: Array.isArray(unit.childIds) ? unit.childIds : [],
            relationIds: Array.isArray(unit.relationIds) ? unit.relationIds : [],
            unionId: unit.unionId || null,
            unionType: unit.unionType || null,
            unionStatus: unit.unionStatus || null,
            parentSetType: unit.parentSetType || null,
            isPrimaryParentSet: unit.isPrimaryParentSet === true,
            label: unit.label || "Семья",
          }))
        : [],
      viewerDescriptors: Array.isArray(snapshot.viewerDescriptors)
        ? snapshot.viewerDescriptors.map((descriptor) => ({
            personId: descriptor.personId,
            primaryRelationLabel: descriptor.primaryRelationLabel || null,
            isBlood: descriptor.isBlood === true,
            alternatePathCount: Number(descriptor.alternatePathCount || 0),
            pathSummary: descriptor.pathSummary || null,
            primaryPathPersonIds: Array.isArray(descriptor.primaryPathPersonIds)
              ? descriptor.primaryPathPersonIds
              : [],
          }))
        : [],
      branchBlocks: Array.isArray(snapshot.branchBlocks)
        ? snapshot.branchBlocks.map((branchBlock) => ({
            id: branchBlock.id,
            rootUnitId: branchBlock.rootUnitId,
            label: branchBlock.label || "Семья",
            memberPersonIds: Array.isArray(branchBlock.memberPersonIds)
              ? branchBlock.memberPersonIds
              : [],
          }))
        : [],
      generationRows: Array.isArray(snapshot.generationRows)
        ? snapshot.generationRows.map((row) => ({
            row: Number(row.row || 0),
            label: row.label || null,
            personIds: Array.isArray(row.personIds) ? row.personIds : [],
            familyUnitIds: Array.isArray(row.familyUnitIds) ? row.familyUnitIds : [],
          }))
        : [],
      warnings: Array.isArray(snapshot.warnings)
        ? snapshot.warnings.map((warning) => ({
            id: warning.id,
            code: warning.code || "graph_warning",
            severity: warning.severity || "warning",
            message: warning.message || "Дерево требует проверки.",
            hint: warning.hint || null,
            personIds: Array.isArray(warning.personIds) ? warning.personIds : [],
            familyUnitIds: Array.isArray(warning.familyUnitIds)
              ? warning.familyUnitIds
              : [],
            relationIds: Array.isArray(warning.relationIds) ? warning.relationIds : [],
          }))
        : [],
    };
  }

  function mapTreeChangeRecord(record) {
    return {
      id: record.id,
      treeId: record.treeId,
      actorId: record.actorId || null,
      type: record.type,
      personId: record.personId || null,
      personIds: Array.isArray(record.personIds) ? record.personIds : [],
      relationId: record.relationId || null,
      mediaId: record.mediaId || null,
      createdAt: record.createdAt,
      details:
        record.details && typeof record.details === "object"
          ? record.details
          : {},
    };
  }

  function mapRelationRequest(request) {
    return {
      id: request.id,
      treeId: request.treeId,
      senderId: request.senderId,
      recipientId: request.recipientId,
      senderToRecipient: request.senderToRecipient,
      relationType: request.senderToRecipient,
      targetPersonId: request.targetPersonId || request.offlineRelativeId || null,
      offlineRelativeId:
        request.offlineRelativeId || request.targetPersonId || null,
      createdAt: request.createdAt,
      updatedAt: request.updatedAt,
      respondedAt: request.respondedAt || null,
      status: request.status || "pending",
      message: request.message || null,
    };
  }

  function mapTreeInvitation(invitation, tree = null) {
    return {
      invitationId: invitation.id,
      treeId: invitation.treeId,
      userId: invitation.userId,
      role: invitation.role || "pending",
      addedAt: invitation.addedAt,
      addedBy: invitation.addedBy || null,
      acceptedAt: invitation.acceptedAt || null,
      relationToTree: invitation.relationToTree || null,
      tree: tree ? mapTree(tree) : null,
      invitedBy: invitation.addedBy || null,
    };
  }

  function truncateText(value, maxLength = 280) {
    const text = String(value || "").trim();
    if (!text) {
      return null;
    }
    if (text.length <= maxLength) {
      return text;
    }
    return `${text.slice(0, Math.max(0, maxLength - 1)).trimEnd()}…`;
  }

  function normalizeSmallPublicUrl(value) {
    const rawValue = String(value || "").trim();
    if (!rawValue || rawValue.length > 2048) {
      return null;
    }
    return normalizePublicUrl(rawValue);
  }

  function sanitizeNotificationData(data) {
    if (!data || typeof data !== "object" || Array.isArray(data)) {
      return {};
    }

    const allowedKeys = [
      "invitationId",
      "treeId",
      "treeName",
      "invitedBy",
      "memberUserId",
      "requestId",
      "senderId",
      "recipientId",
      "relationType",
      "status",
      "chatId",
      "chatType",
      "chatTitle",
      "senderName",
      "messageId",
      "callId",
      "mediaMode",
    ];

    const sanitized = {};
    for (const key of allowedKeys) {
      if (!(key in data)) {
        continue;
      }
      const value = data[key];
      if (value == null) {
        sanitized[key] = null;
        continue;
      }
      if (
        typeof value === "string" ||
        typeof value === "number" ||
        typeof value === "boolean"
      ) {
        sanitized[key] =
          typeof value === "string" ? truncateText(value, 280) || "" : value;
      }
    }

    return sanitized;
  }

  function mapNotification(notification) {
    return {
      id: notification.id,
      userId: notification.userId,
      type: notification.type,
      title: truncateText(notification.title, 160),
      body: truncateText(notification.body, 280),
      data: sanitizeNotificationData(notification.data),
      createdAt: notification.createdAt,
      readAt: notification.readAt || null,
      isRead: Boolean(notification.readAt),
    };
  }

  function resolveUserDisplayName(user) {
    if (!user) {
      return "Пользователь";
    }

    return composeDisplayName(user.profile) ||
      sanitizeProfile(user.profile).displayName ||
      user.email ||
      "Пользователь";
  }

  function mapBlock(block, blockedUser = null) {
    return {
      id: block.id,
      blockerId: block.blockerId,
      blockedUserId: block.blockedUserId,
      blockedUserDisplayName: resolveUserDisplayName(blockedUser),
      blockedUserPhotoUrl: sanitizeProfile(blockedUser?.profile).photoUrl || null,
      reason: block.reason || null,
      metadata: block.metadata || {},
      createdAt: block.createdAt,
      updatedAt: block.updatedAt,
    };
  }

  function mapReport(report, reporter = null) {
    return {
      id: report.id,
      reporterId: report.reporterId,
      reporterDisplayName: resolveUserDisplayName(reporter),
      targetType: report.targetType,
      targetId: report.targetId,
      reason: report.reason,
      details: report.details || null,
      metadata: report.metadata || {},
      status: report.status || "pending",
      resolutionNote: report.resolutionNote || null,
      resolvedAt: report.resolvedAt || null,
      resolvedBy: report.resolvedBy || null,
      createdAt: report.createdAt,
      updatedAt: report.updatedAt,
    };
  }

  function mapPushDevice(device) {
    return {
      id: device.id,
      userId: device.userId,
      provider: device.provider,
      platform: device.platform,
      createdAt: device.createdAt,
      updatedAt: device.updatedAt,
      lastSeenAt: device.lastSeenAt,
    };
  }

  function mapPushDelivery(delivery) {
    return {
      id: delivery.id,
      notificationId: delivery.notificationId,
      userId: delivery.userId,
      deviceId: delivery.deviceId,
      provider: delivery.provider,
      status: delivery.status,
      createdAt: delivery.createdAt,
      updatedAt: delivery.updatedAt,
      deliveredAt: delivery.deliveredAt || null,
      lastError: delivery.lastError || null,
      responseCode: delivery.responseCode ?? null,
    };
  }

  function mapPost(post, commentCount = 0) {
    return {
      id: post.id,
      treeId: post.treeId,
      authorId: post.authorId,
      authorName: post.authorName || "Аноним",
      authorPhotoUrl: normalizePublicUrl(post.authorPhotoUrl || null),
      content: post.content || "",
      imageUrls: normalizePublicUrlList(post.imageUrls),
      createdAt: post.createdAt,
      likedBy: Array.isArray(post.likedBy) ? post.likedBy : [],
      commentCount: Number(commentCount || 0),
      isPublic: post.isPublic === true,
      scopeType: post.scopeType === "branches" ? "branches" : "wholeTree",
      anchorPersonIds: Array.isArray(post.anchorPersonIds)
        ? post.anchorPersonIds
        : [],
    };
  }

  function mapStory(story) {
    return {
      id: story.id,
      treeId: story.treeId,
      authorId: story.authorId,
      authorName: story.authorName || "Аноним",
      authorPhotoUrl: normalizePublicUrl(story.authorPhotoUrl || null),
      type: story.type || "text",
      text: story.text || null,
      mediaUrl: normalizePublicUrl(story.mediaUrl || null),
      thumbnailUrl: normalizePublicUrl(story.thumbnailUrl || null),
      createdAt: story.createdAt,
      updatedAt: story.updatedAt || story.createdAt,
      expiresAt: story.expiresAt,
      viewedBy: Array.isArray(story.viewedBy) ? story.viewedBy : [],
    };
  }

  function mapComment(comment) {
    const likedBy = Array.isArray(comment.likedBy) ? comment.likedBy : [];
    return {
      id: comment.id,
      postId: comment.postId,
      authorId: comment.authorId,
      authorName: comment.authorName || "Аноним",
      authorPhotoUrl: normalizePublicUrl(comment.authorPhotoUrl || null),
      content: comment.content || "",
      createdAt: comment.createdAt,
      likeCount: likedBy.length,
      likedBy,
    };
  }

  function mapChatMessage(message) {
    const explicitAttachments = Array.isArray(message.attachments)
      ? message.attachments
          .filter((attachment) => String(attachment?.url || "").trim())
          .map((attachment) => ({
            type: String(attachment.type || "file"),
            url: normalizePublicUrl(String(attachment.url || "").trim()),
            presentation: String(attachment.presentation || "default"),
            mimeType: attachment.mimeType || null,
            fileName: attachment.fileName || null,
            sizeBytes: Number.isFinite(Number(attachment.sizeBytes))
              ? Number(attachment.sizeBytes)
              : null,
            durationMs: Number.isFinite(Number(attachment.durationMs))
              ? Number(attachment.durationMs)
              : null,
            width: Number.isFinite(Number(attachment.width))
              ? Number(attachment.width)
              : null,
            height: Number.isFinite(Number(attachment.height))
              ? Number(attachment.height)
              : null,
            thumbnailUrl: normalizePublicUrl(attachment.thumbnailUrl || null),
          }))
      : [];
    const attachments = explicitAttachments.length > 0
      ? explicitAttachments
      : [
          ...new Set(
            [
              ...(Array.isArray(message.mediaUrls) ? message.mediaUrls : []),
              message.imageUrl,
            ]
              .map((value) => String(value || "").trim())
              .filter(Boolean),
          ),
        ].map((url) => ({
          type: "image",
          url: normalizePublicUrl(url),
          presentation: "default",
          mimeType: "image/jpeg",
          fileName: null,
          sizeBytes: null,
          durationMs: null,
          width: null,
          height: null,
          thumbnailUrl: null,
        }));
    return {
      id: message.id,
      chatId: message.chatId,
      senderId: message.senderId,
      text: message.text,
      timestamp: message.timestamp,
      updatedAt: message.updatedAt || null,
      isRead: message.isRead === true,
      attachments,
      imageUrl: normalizePublicUrl(message.imageUrl || null),
      mediaUrls: normalizePublicUrlList(message.mediaUrls),
      participants: Array.isArray(message.participants)
        ? message.participants
        : [],
      senderName: message.senderName,
      clientMessageId: message.clientMessageId || null,
      expiresAt: message.expiresAt || null,
      replyTo: message.replyTo || null,
    };
  }

  function mapChatRecord(chat) {
    return {
      id: chat.id,
      type: chat.type || "direct",
      title: chat.title || null,
      participantIds: Array.isArray(chat.participantIds)
        ? chat.participantIds
        : [],
      createdBy: chat.createdBy || null,
      treeId: chat.treeId || null,
      branchRootPersonIds: Array.isArray(chat.branchRootPersonIds)
        ? chat.branchRootPersonIds
        : [],
      createdAt: chat.createdAt,
      updatedAt: chat.updatedAt,
    };
  }

  function mapCallSession(session) {
    if (!session || typeof session !== "object") {
      return null;
    }
    return {
      roomName: String(session.roomName || "").trim(),
      url: String(session.url || "").trim(),
      token: String(session.token || "").trim(),
      participantIdentity: String(session.participantIdentity || "").trim(),
      participantName: session.participantName || null,
      createdAt: session.createdAt || null,
    };
  }

  function mapCallMetrics(metrics) {
    if (!metrics || typeof metrics !== "object") {
      return {
        acceptLatencyMs: null,
        roomJoinFailureCount: 0,
        reconnectCount: 0,
        lastRoomJoinFailureReason: null,
        lastWebhookEvent: null,
      };
    }
    return {
      acceptLatencyMs: Number.isFinite(Number(metrics.acceptLatencyMs))
        ? Math.max(0, Math.floor(Number(metrics.acceptLatencyMs)))
        : null,
      roomJoinFailureCount: Number.isFinite(Number(metrics.roomJoinFailureCount))
        ? Math.max(0, Math.floor(Number(metrics.roomJoinFailureCount)))
        : 0,
      reconnectCount: Number.isFinite(Number(metrics.reconnectCount))
        ? Math.max(0, Math.floor(Number(metrics.reconnectCount)))
        : 0,
      lastRoomJoinFailureReason: metrics.lastRoomJoinFailureReason || null,
      lastWebhookEvent: metrics.lastWebhookEvent || null,
    };
  }

  function logCallEvent(eventType, call, extra = {}) {
    if (!call || typeof call !== "object") {
      return;
    }

    const metrics = mapCallMetrics(call.metrics);
    console.log(
      "[backend] call",
      JSON.stringify({
        eventType,
        callId: call.id || null,
        chatId: call.chatId || null,
        mediaMode: call.mediaMode || null,
        state: call.state || null,
        createdAt: call.createdAt || null,
        acceptedAt: call.acceptedAt || null,
        endedAt: call.endedAt || null,
        endedReason: call.endedReason || null,
        acceptLatencyMs: metrics.acceptLatencyMs,
        roomJoinFailureCount: metrics.roomJoinFailureCount,
        reconnectCount: metrics.reconnectCount,
        lastRoomJoinFailureReason: metrics.lastRoomJoinFailureReason,
        lastWebhookEvent: metrics.lastWebhookEvent,
        ...extra,
      }),
    );
  }

  function mapCallRecord(call, {viewerUserId = null} = {}) {
    return {
      id: call.id,
      chatId: call.chatId,
      initiatorId: call.initiatorId,
      recipientId: call.recipientId,
      participantIds: Array.isArray(call.participantIds)
        ? call.participantIds
        : [],
      mediaMode: call.mediaMode || "audio",
      state: call.state || "ringing",
      roomName: call.roomName || null,
      createdAt: call.createdAt,
      updatedAt: call.updatedAt,
      acceptedAt: call.acceptedAt || null,
      endedAt: call.endedAt || null,
      endedReason: call.endedReason || null,
      metrics: mapCallMetrics(call.metrics),
      session:
        viewerUserId && call.sessionByUserId
          ? mapCallSession(call.sessionByUserId[viewerUserId])
          : null,
    };
  }

  function mapChatParticipant(participant) {
    return {
      userId: participant.userId,
      displayName: participant.displayName || "Пользователь",
      photoUrl: normalizePublicUrl(participant.photoUrl || null),
    };
  }

  function mapChatBranchRoot(branchRoot) {
    return {
      personId: branchRoot.personId,
      name: branchRoot.name || "Без имени",
      photoUrl: normalizePublicUrl(branchRoot.photoUrl || null),
    };
  }

  function mapChatPreview(preview) {
    return {
      id: `${preview.chatId}_${preview.userId}`,
      chatId: preview.chatId,
      userId: preview.userId,
      type: preview.type || "direct",
      title: truncateText(preview.title, 160),
      photoUrl: normalizeSmallPublicUrl(preview.photoUrl || null),
      participantIds: Array.isArray(preview.participantIds)
        ? preview.participantIds
        : [],
      otherUserId: preview.otherUserId,
      otherUserName: truncateText(preview.otherUserName || "Пользователь", 120),
      otherUserPhotoUrl: normalizeSmallPublicUrl(preview.otherUserPhotoUrl || null),
      lastMessage: truncateText(preview.lastMessage || "", 280) || "",
      lastMessageTime: preview.lastMessageTime,
      unreadCount: Number(preview.unreadCount || 0),
      lastMessageSenderId: preview.lastMessageSenderId || "",
    };
  }

  async function requireTreeAccess(req, res, treeId) {
    const tree = await store.findTree(treeId);
    if (!tree) {
      res.status(404).json({message: "Семейное дерево не найдено"});
      return null;
    }

    const memberIds = Array.isArray(tree.memberIds) ? tree.memberIds : [];
    const hasAccess =
      tree.creatorId === req.auth.user.id || memberIds.includes(req.auth.user.id);

    if (!hasAccess) {
      res.status(403).json({message: "Доступ к дереву запрещён"});
      return null;
    }

    return tree;
  }

  async function requireChatAccess(req, res, chatId) {
    const chat = await store.findChat(chatId);
    if (!chat) {
      res.status(404).json({message: "Чат не найден"});
      return null;
    }

    const participantIds = Array.isArray(chat.participantIds)
      ? chat.participantIds
      : [];
    if (!participantIds.includes(req.auth.user.id)) {
      res.status(403).json({message: "Доступ к чату запрещён"});
      return null;
    }

    return chat;
  }

  async function requireCallAccess(req, res, callId) {
    const call = await findFreshCall(callId, {
      viewerUserId: req.auth.user.id,
    });
    if (!call) {
      res.status(404).json({message: "Звонок не найден"});
      return null;
    }

    if (!(call.participantIds || []).includes(req.auth.user.id)) {
      res.status(403).json({message: "Доступ к звонку запрещён"});
      return null;
    }

    return call;
  }

  function requireAdmin(req, res) {
    const adminEmails = Array.isArray(config.adminEmails) ? config.adminEmails : [];
    const currentEmail = String(req.auth?.user?.email || "").trim().toLowerCase();
    const isAdmin = Boolean(currentEmail) && adminEmails.includes(currentEmail);

    if (!isAdmin) {
      res.status(403).json({message: "Нужны права модератора"});
      return false;
    }

    return true;
  }

  function escapeHtml(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function resolvePublicApiUrl(req) {
    return String(config.publicApiUrl || "").trim() ||
      `${req.protocol}://${req.get("host")}`;
  }

  function resolvePublicAppUrl() {
    return String(config.publicAppUrl || "https://rodnya-tree.ru")
      .trim()
      .replace(/\/$/, "");
  }

  function buildTelegramIdentityFromAuth(authData) {
    return {
      provider: "telegram",
      providerUserId: String(authData.id),
      displayName: [
        authData.first_name,
        authData.last_name,
      ].map((value) => String(value || "").trim()).filter(Boolean).join(" "),
      metadata: {
        username: authData.username || null,
        photoUrl: authData.photo_url || null,
        authDate: authData.auth_date || null,
      },
    };
  }

  function verifyTelegramLoginPayload(query) {
    if (!config.telegramLoginEnabled) {
      throw new Error("TELEGRAM_LOGIN_DISABLED");
    }

    const hash = String(query?.hash || "").trim();
    const authDate = Number(query?.auth_date || 0);
    const telegramUserId = String(query?.id || "").trim();
    if (!hash || !telegramUserId || !Number.isFinite(authDate) || authDate <= 0) {
      throw new Error("INVALID_TELEGRAM_PAYLOAD");
    }

    const nowSeconds = Math.floor(Date.now() / 1000);
    if (Math.abs(nowSeconds - authDate) > 10 * 60) {
      throw new Error("TELEGRAM_AUTH_EXPIRED");
    }

    const signedFields = new Set([
      "auth_date",
      "first_name",
      "id",
      "last_name",
      "photo_url",
      "username",
    ]);
    const dataCheckString = Object.entries(query || {})
      .filter(([key, value]) =>
        signedFields.has(key) &&
        value !== undefined &&
        value !== null &&
        String(value).trim() !== "",
      )
      .sort(([leftKey], [rightKey]) => leftKey.localeCompare(rightKey))
      .map(([key, value]) => `${key}=${value}`)
      .join("\n");

    const secretKey = crypto
      .createHash("sha256")
      .update(config.telegramBotToken, "utf8")
      .digest();
    const computedHash = crypto
      .createHmac("sha256", secretKey)
      .update(dataCheckString, "utf8")
      .digest("hex");

    const providedHashBuffer = Buffer.from(hash, "hex");
    const computedHashBuffer = Buffer.from(computedHash, "hex");
    if (
      providedHashBuffer.length !== computedHashBuffer.length ||
      !crypto.timingSafeEqual(providedHashBuffer, computedHashBuffer)
    ) {
      throw new Error("INVALID_TELEGRAM_SIGNATURE");
    }

    return {
      id: telegramUserId,
      first_name: query.first_name ? String(query.first_name) : "",
      last_name: query.last_name ? String(query.last_name) : "",
      username: query.username ? String(query.username) : "",
      photo_url: query.photo_url ? String(query.photo_url) : "",
      auth_date: authDate,
    };
  }

  function telegramAuthRedirectUrl(code, {intent = "login"} = {}) {
    const query = new URLSearchParams({
      telegramAuthCode: code,
      ...(intent === "link" ? {telegramIntent: "link"} : {}),
    });
    return `${resolvePublicAppUrl()}/#/login?${query.toString()}`;
  }

  function renderTelegramLoginPage({botUsername, authUrl}) {
    return `<!DOCTYPE html>
<html lang="ru">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Вход через Telegram</title>
    <style>
      body {
        margin: 0;
        min-height: 100vh;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        background: linear-gradient(180deg, #eaf5f2 0%, #f8faf8 100%);
        display: grid;
        place-items: center;
        color: #163229;
      }
      .card {
        width: min(92vw, 420px);
        background: rgba(255,255,255,0.92);
        border-radius: 28px;
        padding: 28px;
        box-shadow: 0 20px 60px rgba(16, 61, 51, 0.16);
      }
      h1 { margin: 0 0 12px; font-size: 28px; }
      p { margin: 0 0 20px; line-height: 1.5; color: #446158; }
    </style>
  </head>
  <body>
    <div class="card">
      <h1>Вход через Telegram</h1>
      <p>Подтвердите аккаунт в Telegram. Если Telegram уже привязан к Родне, вход завершится автоматически.</p>
      <script async src="https://telegram.org/js/telegram-widget.js?22"
        data-telegram-login="${escapeHtml(botUsername)}"
        data-size="large"
        data-radius="18"
        data-auth-url="${escapeHtml(authUrl)}"
        data-request-access="write">
      </script>
    </div>
  </body>
</html>`;
  }

  function maskEmailAddress(value) {
    const normalizedValue = String(value || "").trim().toLowerCase();
    const atIndex = normalizedValue.indexOf("@");
    if (atIndex <= 0) {
      return null;
    }

    const localPart = normalizedValue.slice(0, atIndex);
    const domainPart = normalizedValue.slice(atIndex + 1);
    if (!localPart || !domainPart) {
      return null;
    }

    const visibleLocal =
      localPart.length <= 2
        ? `${localPart[0]}*`
        : `${localPart.slice(0, 2)}***`;
    return `${visibleLocal}@${domainPart}`;
  }

  function maskPhoneNumber(value) {
    const normalizedValue = String(value || "").replace(/\D+/g, "");
    if (normalizedValue.length < 7) {
      return null;
    }

    return `+${normalizedValue.slice(0, 2)}***${normalizedValue.slice(-2)}`;
  }

  function secondsUntil(value) {
    const timestamp = new Date(String(value || "")).getTime();
    if (!Number.isFinite(timestamp)) {
      return 0;
    }
    return Math.max(0, Math.ceil((timestamp - Date.now()) / 1000));
  }

  function mapLinkedAuthIdentity(identity) {
    return {
      provider: identity.provider,
      linkedAt: identity.linkedAt,
      lastUsedAt: identity.lastUsedAt || null,
      emailMasked: maskEmailAddress(identity.email),
      phoneMasked: maskPhoneNumber(
        identity.normalizedPhoneNumber || identity.phoneNumber,
      ),
      displayName: identity.displayName || null,
    };
  }

  function trustedChannelLabel(provider) {
    switch (provider) {
      case "google":
        return "Google";
      case "telegram":
        return "Telegram";
      case "vk":
        return "VK ID";
      case "max":
        return "MAX";
      case "password":
      default:
        return "Email и пароль";
    }
  }

  function trustedChannelDescription(provider) {
    switch (provider) {
      case "google":
        return "Подтверждённый вход через Google-аккаунт.";
      case "telegram":
        return "Подтверждённая связь через Telegram.";
      case "vk":
        return "Подтверждённый профиль через VK ID.";
      case "max":
        return "Подтверждённая связь через MAX.";
      case "password":
      default:
        return "Резервный вход по email и паролю.";
    }
  }

  function trustedChannelVerificationLabel(provider) {
    switch (provider) {
      case "google":
        return "Аккаунт подтверждён через Google";
      case "telegram":
        return "Связь подтверждена через Telegram";
      case "vk":
        return "Аккаунт подтверждён через VK";
      case "max":
        return "Основной канал подтверждён через MAX";
      case "password":
      default:
        return "Доступ защищён email и паролем";
    }
  }

  function resolvePrimaryTrustedChannelProvider({
    linkedProviderIds = [],
    profile = {},
  } = {}) {
    const preferredProvider = normalizePrimaryTrustedChannel(
      profile?.primaryTrustedChannel,
    );
    if (
      preferredProvider &&
      Array.isArray(linkedProviderIds) &&
      linkedProviderIds.includes(preferredProvider)
    ) {
      return preferredProvider;
    }

    for (const provider of ["telegram", "vk", "max", "google"]) {
      if (linkedProviderIds.includes(provider)) {
        return provider;
      }
    }

    return null;
  }

  function buildTrustedChannels({
    linkedProviderIds = [],
    authIdentities = [],
    profile = {},
  } = {}) {
    const mappedIdentities = Array.isArray(authIdentities)
      ? authIdentities.map(mapLinkedAuthIdentity)
      : [];
    const identityByProvider = new Map();
    for (const identity of mappedIdentities) {
      if (identity?.provider && !identityByProvider.has(identity.provider)) {
        identityByProvider.set(identity.provider, identity);
      }
    }

    const primaryProvider = resolvePrimaryTrustedChannelProvider({
      linkedProviderIds,
      profile,
    });

    return ["password", "google", "telegram", "vk", "max"].map((provider) => {
      const identity = identityByProvider.get(provider) || null;
      const isLinked = linkedProviderIds.includes(provider);
      const isTrustedChannel = isLinked && provider !== "password";
      return {
        provider,
        label: trustedChannelLabel(provider),
        description: trustedChannelDescription(provider),
        verificationLabel: trustedChannelVerificationLabel(provider),
        isLinked,
        isTrustedChannel,
        isLoginMethod: isLinked,
        isPrimary: primaryProvider === provider,
        linkedAt: identity?.linkedAt || null,
        lastUsedAt: identity?.lastUsedAt || null,
        emailMasked: identity?.emailMasked || null,
        phoneMasked: identity?.phoneMasked || null,
        displayName: identity?.displayName || null,
      };
    });
  }

  function buildTrustedChannelSummary(trustedChannels = []) {
    const primaryChannel = trustedChannels.find(
      (entry) => entry.isPrimary === true && entry.isTrustedChannel === true,
    );
    if (primaryChannel) {
      return {
        title: primaryChannel.verificationLabel,
        detail: `Основной канал: ${primaryChannel.label}`,
      };
    }

    const firstTrustedChannel = trustedChannels.find(
      (entry) => entry.isTrustedChannel === true,
    );
    if (firstTrustedChannel) {
      return {
        title: firstTrustedChannel.verificationLabel,
        detail: "Можно выбрать этот канал основным в настройках профиля.",
      };
    }

    return {
      title: "Подтверждённый канал пока не выбран",
      detail:
        "Привяжите VK, Telegram, Google или MAX, чтобы подтвердить канал связи и входа.",
    };
  }

  function authResponse(user, sessionTokens) {
    const profile = sanitizeProfile(user.profile);
    const profileStatus = computeProfileStatus(user.profile);
    return {
      accessToken: sessionTokens.token,
      refreshToken: sessionTokens.refreshToken,
      user: {
        id: user.id,
        identityId: user.identityId || null,
        email: user.email,
        displayName: profile.displayName,
        photoUrl: profile.photoUrl,
        providerIds: user.providerIds || ["password"],
      },
      profileStatus,
    };
  }

  function resolveGoogleDisplayName(payload) {
    const explicitName = String(payload?.name || "").trim();
    if (explicitName) {
      return explicitName;
    }

    return [
      String(payload?.given_name || "").trim(),
      String(payload?.family_name || "").trim(),
    ].filter(Boolean).join(" ");
  }

  function buildGoogleIdentityFromPayload(payload) {
    const providerUserId = String(payload?.sub || "").trim();
    if (!providerUserId) {
      throw new Error("GOOGLE_ID_TOKEN_INVALID");
    }

    const email = String(payload?.email || "").trim().toLowerCase() || null;
    const displayName = resolveGoogleDisplayName(payload);
    const picture = String(payload?.picture || "").trim() || null;
    const emailVerified =
      payload?.email_verified === true ||
      String(payload?.email_verified || "").trim().toLowerCase() === "true";

    return {
      provider: "google",
      providerUserId,
      email,
      displayName: displayName || null,
      metadata: {
        emailVerified,
        givenName: String(payload?.given_name || "").trim() || null,
        familyName: String(payload?.family_name || "").trim() || null,
        picture,
      },
    };
  }

  function resolveVkDisplayName(user) {
    const explicitName = [
      String(user?.first_name || "").trim(),
      String(user?.last_name || "").trim(),
    ].filter(Boolean).join(" ");

    if (explicitName) {
      return explicitName;
    }

    return String(user?.email || "").trim() || null;
  }

  function buildVkIdentityFromUserInfo(userInfo) {
    const user = userInfo?.user && typeof userInfo.user === "object"
      ? userInfo.user
      : {};
    const providerUserId =
      String(user?.user_id || userInfo?.user_id || "").trim();
    if (!providerUserId) {
      throw new Error("VK_USER_INFO_INVALID");
    }

    const email = String(user?.email || "").trim().toLowerCase() || null;
    const phoneNumber = String(user?.phone || "").trim() || null;
    const displayName = resolveVkDisplayName(user);
    const avatar = String(user?.avatar || "").trim() || null;

    return {
      provider: "vk",
      providerUserId,
      email,
      phoneNumber,
      displayName,
      metadata: {
        firstName: String(user?.first_name || "").trim() || null,
        lastName: String(user?.last_name || "").trim() || null,
        avatar,
        email,
        phoneNumber,
      },
    };
  }

  function vkAuthRedirectUrl(code, {intent = "login"} = {}) {
    const query = new URLSearchParams({
      vkAuthCode: code,
      ...(intent === "link" ? {vkIntent: "link"} : {}),
    });
    return `${resolvePublicAppUrl()}/#/login?${query.toString()}`;
  }

  function buildMaxIdentityFromLaunch(launchData) {
    const user = launchData?.user && typeof launchData.user === "object"
      ? launchData.user
      : {};
    const providerUserId = String(user?.id || "").trim();
    if (!providerUserId) {
      throw new Error("MAX_USER_INFO_INVALID");
    }

    return {
      provider: "max",
      providerUserId,
      displayName: [
        String(user?.first_name || "").trim(),
        String(user?.last_name || "").trim(),
      ].filter(Boolean).join(" ") || String(user?.username || "").trim() || null,
      metadata: {
        firstName: String(user?.first_name || "").trim() || null,
        lastName: String(user?.last_name || "").trim() || null,
        username: String(user?.username || "").trim() || null,
        photoUrl: String(user?.photo_url || "").trim() || null,
        languageCode: String(user?.language_code || "").trim() || null,
        authDate: launchData?.authDate || null,
      },
    };
  }

  function maxAuthRedirectUrl(code, {intent = "login"} = {}) {
    const query = new URLSearchParams({
      maxAuthCode: code,
      ...(intent === "link" ? {maxIntent: "link"} : {}),
    });
    return `${resolvePublicAppUrl()}/#/login?${query.toString()}`;
  }

  async function resolveSharedTreeIdsForUsers(viewerUserId, targetUserId) {
    const normalizedViewerUserId = String(viewerUserId || "").trim();
    const normalizedTargetUserId = String(targetUserId || "").trim();
    if (!normalizedViewerUserId || !normalizedTargetUserId) {
      return [];
    }
    if (normalizedViewerUserId === normalizedTargetUserId) {
      return [];
    }

    const [viewerTrees, targetTrees] = await Promise.all([
      store.listUserTrees(normalizedViewerUserId),
      store.listUserTrees(normalizedTargetUserId),
    ]);

    const targetTreeIds = new Set(
      (Array.isArray(targetTrees) ? targetTrees : [])
        .map((tree) => String(tree?.id || "").trim())
        .filter(Boolean),
    );

    return (Array.isArray(viewerTrees) ? viewerTrees : [])
      .map((tree) => String(tree?.id || "").trim())
      .filter((treeId) => treeId && targetTreeIds.has(treeId));
  }

  async function buildProfileViewerContext(viewerUserId, targetUserId) {
    const normalizedViewerUserId = String(viewerUserId || "").trim();
    const normalizedTargetUserId = String(targetUserId || "").trim();
    if (!normalizedViewerUserId || !normalizedTargetUserId) {
      return null;
    }
    if (normalizedViewerUserId === normalizedTargetUserId) {
      return {
        viewerUserId: normalizedViewerUserId,
        targetUserId: normalizedTargetUserId,
        sharedTreeIds: [],
        branchRootMatches: [],
      };
    }

    const sharedTreeIds = await resolveSharedTreeIdsForUsers(
      normalizedViewerUserId,
      normalizedTargetUserId,
    );
    const branchRootMatches = new Set();
    for (const treeId of sharedTreeIds) {
      const [persons, relations] = await Promise.all([
        store.listPersons(treeId),
        store.listRelations(treeId),
      ]);
      const viewerPersonIds = (Array.isArray(persons) ? persons : [])
        .filter(
          (person) =>
            String(person?.userId || "").trim() === normalizedViewerUserId,
        )
        .map((person) => String(person?.id || "").trim())
        .filter(Boolean);
      if (viewerPersonIds.length === 0) {
        continue;
      }

      for (const person of Array.isArray(persons) ? persons : []) {
        const rootPersonId = String(person?.id || "").trim();
        if (!rootPersonId) {
          continue;
        }
        const visibleIds = buildBranchVisiblePersonIds(
          persons,
          relations,
          rootPersonId,
        );
        if (viewerPersonIds.some((personId) => visibleIds.has(personId))) {
          branchRootMatches.add(rootPersonId);
        }
      }
    }

    return {
      viewerUserId: normalizedViewerUserId,
      targetUserId: normalizedTargetUserId,
      sharedTreeIds,
      branchRootMatches: Array.from(branchRootMatches),
    };
  }

  async function buildPersonDossierPayload({
    treeId,
    personId,
    viewerUserId,
  }) {
    const dossier = await store.getPersonDossier(treeId, personId);
    if (!dossier) {
      return null;
    }

    const mappedPerson = mapPerson(dossier.person);
    const linkedUserId = String(dossier.person?.userId || "").trim();
    const viewerContext = linkedUserId
      ? await buildProfileViewerContext(viewerUserId, linkedUserId)
      : null;
    const linkedProfile = dossier.linkedProfile
      ? sanitizeProfile(dossier.linkedProfile, viewerContext)
      : null;
    const contributionPolicy = normalizeProfileContributionPolicy(
      linkedProfile?.profileContributionPolicy,
    );

    let mode = "offline";
    if (mappedPerson.isAlive === false) {
      mode = "memorial";
    } else if (linkedUserId && linkedUserId === viewerUserId) {
      mode = "self";
    } else if (linkedUserId) {
      mode = "linked";
    }

    return {
      person: mappedPerson,
      linkedProfile,
      mode,
      permissions: {
        canEditFamilyFields: true,
        canSuggestOwnerFields:
          Boolean(linkedUserId) &&
          linkedUserId !== viewerUserId &&
          mappedPerson.isAlive !== false &&
          contributionPolicy === "suggestions",
      },
      hiddenSections: linkedProfile?.hiddenProfileSections || [],
    };
  }

  async function createAndDispatchNotification({
    userId,
    type,
    title,
    body,
    data,
  }) {
    const notification = await store.createNotification({
      userId,
      type,
      title,
      body,
      data,
    });

    if (!notification) {
      return null;
    }

    const mappedNotification = mapNotification(notification);
    realtimeHub?.publishToUser(userId, {
      type: "notification.created",
      notification: mappedNotification,
    });
    await resolvedPushGateway.dispatchNotification(notification);

    return mappedNotification;
  }

  app.post("/v1/auth/register", async (req, res) => {
    const {email, password, displayName} = req.body || {};

    if (!email || !password || !displayName) {
      res.status(400).json({message: "Нужны email, password и displayName"});
      return;
    }

    try {
      const user = await store.createUser({email, password, displayName});
      const sessionTokens = await store.createSession(user.id);
      res.status(201).json(authResponse(user, sessionTokens));
    } catch (error) {
      if (error.message === "EMAIL_ALREADY_EXISTS") {
        res.status(409).json({message: "Этот email уже зарегистрирован"});
        return;
      }
      res.status(500).json({message: "Не удалось зарегистрировать пользователя"});
    }
  });

  app.post("/v1/auth/login", async (req, res) => {
    const {email, password} = req.body || {};
    if (!email || !password) {
      res.status(400).json({message: "Нужны email и password"});
      return;
    }

    const user = await store.authenticate(email, password);
    if (!user) {
      res.status(401).json({message: "Неверный email или пароль"});
      return;
    }

    const sessionTokens = await store.createSession(user.id);
    res.json(authResponse(user, sessionTokens));
  });

  app.post("/v1/auth/refresh", async (req, res) => {
    const {refreshToken} = req.body || {};
    if (!refreshToken) {
      res.status(400).json({message: "Нужен refreshToken"});
      return;
    }

    const session = await store.findSessionByRefreshToken(refreshToken);
    if (!session) {
      res.status(401).json({message: "Сессия по refreshToken не найдена"});
      return;
    }

    const user = await store.findUserById(session.userId);
    if (!user) {
      res.status(401).json({message: "Пользователь сессии не найден"});
      return;
    }

    // Удаляем старую сессию (используем токен старой сессии, если он есть)
    if (session.token) {
      await store.deleteSession(session.token);
    }

    const nextSessionTokens = await store.createSession(user.id);
    res.json(authResponse(user, nextSessionTokens));
  });

  app.get("/v1/auth/session", requireAuth, async (req, res) => {
    const user = await store.findUserById(req.auth.user.id);
    const profile = sanitizeProfile(user.profile);
    res.json({
      session: {
        accessToken: req.auth.token,
        refreshToken: req.auth.session.refreshToken,
        userId: user.id,
      },
      user: {
        id: user.id,
        identityId: user.identityId || null,
        email: user.email,
        displayName: profile.displayName,
        photoUrl: profile.photoUrl,
        providerIds: user.providerIds || ["password"],
      },
      profileStatus: computeProfileStatus(user.profile),
    });
  });

  app.get("/v1/profile/me/account-linking-status", requireAuth, async (req, res) => {
    const user = await store.findUserById(req.auth.user.id);
    const authIdentities = await store.listUserAuthIdentities(req.auth.user.id);
    const profile = user?.profile || {};
    const linkedProviderIds = user?.providerIds || ["password"];
    const trustedChannels = buildTrustedChannels({
      linkedProviderIds,
      authIdentities,
      profile,
    });
    const primaryTrustedChannelProvider = resolvePrimaryTrustedChannelProvider({
      linkedProviderIds,
      profile,
    });
    const trustedChannelSummary = buildTrustedChannelSummary(trustedChannels);

    res.json({
      linkedProviderIds,
      identities: Array.isArray(authIdentities)
        ? authIdentities.map(mapLinkedAuthIdentity)
        : [],
      trustedChannels,
      primaryTrustedChannel: primaryTrustedChannelProvider
        ? trustedChannels.find(
            (entry) => entry.provider === primaryTrustedChannelProvider,
          ) || null
        : null,
      verificationSummary: trustedChannelSummary,
      legacyPhoneVerification: false,
      mergeStrategy: {
        order: [
          "provider_identity",
          "email",
          "invitation_claim",
          "manual_merge",
        ],
        summary:
          "Сначала ищем точное совпадение identity провайдера, затем совпадение email. Для остального используем приглашения, claim link и ручную привязку.",
      },
      discoveryModes: [
        "username",
        "profile_code",
        "email",
        "invite_link",
        "claim_link",
        "qr",
      ],
    });
  });

  app.post("/v1/auth/logout", requireAuth, async (req, res) => {
    await store.deleteSession(req.auth.token);
    res.json({ok: true});
  });

  app.post("/v1/auth/password-reset", async (req, res) => {
    const {email} = req.body || {};
    res.status(202).json({
      ok: true,
      email: email ? String(email).trim().toLowerCase() : null,
      message: "Password reset flow is stubbed in minimal backend",
    });
  });

  app.delete("/v1/auth/account", requireAuth, async (req, res) => {
    const ownedMediaUrls = typeof store.listOwnedMediaUrls === "function"
      ? await store.listOwnedMediaUrls(req.auth.user.id)
      : [];
    await store.deleteUser(req.auth.user.id);

    const mediaCleanupFailures = [];
    for (const mediaUrl of ownedMediaUrls) {
      try {
        await resolvedMediaStorage.deleteObjectByUrl(mediaUrl);
      } catch (error) {
        if (
          error?.message === "INVALID_MEDIA_PATH" ||
          error?.message === "UNSUPPORTED_MEDIA_URL" ||
          error instanceof TypeError
        ) {
          continue;
        }

        mediaCleanupFailures.push({
          url: mediaUrl,
          message: error?.message || "unknown_error",
        });
      }
    }

    if (mediaCleanupFailures.length > 0) {
      console.error(
        "[backend] account media cleanup warnings",
        JSON.stringify({
          requestId: req.requestId,
          userId: req.auth.user.id,
          failures: mediaCleanupFailures,
        }),
      );
    }

    res.status(204).send();
  });

  app.post("/v1/auth/google", async (req, res) => {
    const idToken = String(req.body?.idToken || "").trim();
    if (!idToken) {
      res.status(400).json({message: "Нужен Google idToken"});
      return;
    }

    try {
      const googlePayload = await resolvedGoogleTokenVerifier.verifyIdToken(
        idToken,
      );
      const googleIdentity = buildGoogleIdentityFromPayload(googlePayload);
      const emailVerified =
        googleIdentity.metadata?.emailVerified === true;
      const verifiedEmail = emailVerified ? googleIdentity.email : null;

      const resolution = await store.resolveAuthIdentityTarget({
        provider: googleIdentity.provider,
        providerUserId: googleIdentity.providerUserId,
        email: verifiedEmail,
      });

      let user = null;
      if (resolution?.user?.id) {
        user = await store.linkAuthIdentity(resolution.user.id, googleIdentity);
      } else {
        if (!verifiedEmail) {
          res.status(409).json({
            message:
              "Google аккаунт не вернул подтверждённый email. Пока завершите вход через email и пароль, затем привяжите Google.",
          });
          return;
        }

        user = await store.createUser({
          email: verifiedEmail,
          displayName: googleIdentity.displayName || verifiedEmail,
          password: null,
          authIdentity: googleIdentity,
          photoUrl: googleIdentity.metadata?.picture || null,
        });
      }

      const sessionTokens = await store.createSession(user.id);
      res.json(authResponse(user, sessionTokens));
    } catch (error) {
      if (error?.message === "GOOGLE_AUTH_NOT_CONFIGURED") {
        res.status(503).json({
          message:
            "Google sign-in пока не настроен на backend. Добавьте RODNYA_GOOGLE_WEB_CLIENT_ID.",
        });
        return;
      }
      if (
        error?.message === "GOOGLE_ID_TOKEN_REQUIRED" ||
        error?.message === "GOOGLE_ID_TOKEN_INVALID"
      ) {
        res.status(400).json({message: "Не удалось разобрать Google idToken"});
        return;
      }
      if (error?.message === "AUTH_IDENTITY_ALREADY_LINKED") {
        res.status(409).json({
          message: "Этот Google уже привязан к другому аккаунту Родни.",
        });
        return;
      }
      if (error?.message === "AUTH_PROVIDER_ALREADY_LINKED_FOR_USER") {
        res.status(409).json({
          message:
            "К этому аккаунту уже привязан другой Google-аккаунт.",
        });
        return;
      }
      if (error?.message === "EMAIL_ALREADY_EXISTS") {
        res.status(409).json({
          message:
            "Этот email уже зарегистрирован. Войдите через email и пароль, затем привяжите Google.",
        });
        return;
      }

      console.error("[backend] google auth failed", error);
      res.status(401).json({
        message: "Не удалось проверить вход через Google.",
      });
    }
  });

  app.post("/v1/auth/google/link", requireAuth, async (req, res) => {
    const idToken = String(req.body?.idToken || "").trim();
    if (!idToken) {
      res.status(400).json({message: "Нужен Google idToken"});
      return;
    }

    try {
      const googlePayload = await resolvedGoogleTokenVerifier.verifyIdToken(
        idToken,
      );
      const googleIdentity = buildGoogleIdentityFromPayload(googlePayload);
      const updatedUser = await store.linkAuthIdentity(
        req.auth.user.id,
        googleIdentity,
      );
      res.json({
        ok: true,
        user: {
          id: updatedUser.id,
          identityId: updatedUser.identityId || null,
          email: updatedUser.email,
          providerIds: updatedUser.providerIds || ["password"],
        },
      });
    } catch (error) {
      if (error?.message === "GOOGLE_AUTH_NOT_CONFIGURED") {
        res.status(503).json({
          message:
            "Google sign-in пока не настроен на backend. Добавьте RODNYA_GOOGLE_WEB_CLIENT_ID.",
        });
        return;
      }
      if (
        error?.message === "GOOGLE_ID_TOKEN_REQUIRED" ||
        error?.message === "GOOGLE_ID_TOKEN_INVALID"
      ) {
        res.status(400).json({message: "Не удалось разобрать Google idToken"});
        return;
      }
      if (error?.message === "AUTH_IDENTITY_ALREADY_LINKED") {
        res.status(409).json({
          message: "Этот Google уже привязан к другому аккаунту Родни.",
        });
        return;
      }
      if (error?.message === "AUTH_PROVIDER_ALREADY_LINKED_FOR_USER") {
        res.status(409).json({
          message:
            "К этому аккаунту уже привязан другой Google-аккаунт.",
        });
        return;
      }
      if (error?.message === "INVALID_AUTH_IDENTITY") {
        res.status(400).json({message: "Некорректные данные Google identity"});
        return;
      }

      console.error("[backend] google link failed", error);
      res.status(401).json({
        message: "Не удалось привязать Google к аккаунту.",
      });
    }
  });

  app.get("/v1/auth/vk/start", async (req, res) => {
    if (!resolvedVkAuthClient.isEnabled) {
      res.status(503).send("VK ID login is not configured.");
      return;
    }

    const intent = String(req.query?.intent || "").trim().toLowerCase() === "link"
      ? "link"
      : "login";
    const callbackUrl = `${resolvePublicApiUrl(req).replace(/\/$/, "")}/v1/auth/vk/callback`;
    const {codeVerifier, codeChallenge} = createVkPkcePair();
    const authFlowHandoff = await store.createAuthHandoff({
      type: "vk_auth_flow",
      payload: {
        intent,
        codeVerifier,
        redirectUri: callbackUrl,
      },
    });

    res.setHeader("cache-control", "no-store");
    res.redirect(
      302,
      buildVkAuthorizeUrl({
        appId: resolvedVkAuthClient.webAppId,
        redirectUri: callbackUrl,
        state: authFlowHandoff.code,
        codeChallenge,
      }),
    );
  });

  app.get("/v1/auth/vk/callback", async (req, res) => {
    try {
      if (!resolvedVkAuthClient.isEnabled) {
        throw new Error("VK_AUTH_NOT_CONFIGURED");
      }

      const providerError = String(req.query?.error || "").trim();
      if (providerError) {
        const error = new Error(providerError);
        error.description = String(req.query?.error_description || "").trim();
        throw error;
      }

      const state = String(req.query?.state || "").trim();
      const code = String(req.query?.code || "").trim();
      const deviceId = String(
        req.query?.device_id || req.query?.deviceId || "",
      ).trim();
      if (!state || !code || !deviceId) {
        throw new Error("VK_AUTH_CALLBACK_INVALID");
      }

      const authFlowHandoff = await store.consumeAuthHandoff(state, {
        type: "vk_auth_flow",
      });
      if (!authFlowHandoff) {
        throw new Error("VK_AUTH_STATE_INVALID");
      }

      const intent = String(authFlowHandoff.payload?.intent || "").trim().toLowerCase() === "link"
        ? "link"
        : "login";
      const callbackUrl = String(authFlowHandoff.payload?.redirectUri || "").trim() ||
        `${resolvePublicApiUrl(req).replace(/\/$/, "")}/v1/auth/vk/callback`;
      const codeVerifier = String(authFlowHandoff.payload?.codeVerifier || "").trim();
      if (!codeVerifier) {
        throw new Error("VK_AUTH_STATE_INVALID");
      }

      const vkTokenResult = await resolvedVkAuthClient.exchangeCode({
        code,
        deviceId,
        state,
        codeVerifier,
        redirectUri: callbackUrl,
      });
      const vkUserInfo = await resolvedVkAuthClient.fetchUserInfo(
        vkTokenResult.access_token,
      );
      const vkIdentity = buildVkIdentityFromUserInfo(vkUserInfo);
      const linkedUser = await store.findUserByAuthIdentity(
        vkIdentity.provider,
        vkIdentity.providerUserId,
      );

      if (linkedUser) {
        if (intent === "link") {
          const authHandoff = await store.createAuthHandoff({
            type: "vk_auth_result",
            userId: linkedUser.id,
            payload: {
              status: "already_linked",
              message:
                "Этот VK ID уже привязан к аккаунту Родни. Если это ваш аккаунт, входите через VK ID с экрана входа.",
            },
          });
          res.redirect(302, vkAuthRedirectUrl(authHandoff.code, {intent}));
          return;
        }

        const refreshedUser = await store.linkAuthIdentity(
          linkedUser.id,
          vkIdentity,
        );
        const sessionTokens = await store.createSession(refreshedUser.id);
        const authHandoff = await store.createAuthHandoff({
          type: "vk_auth_result",
          userId: refreshedUser.id,
          payload: {
            status: "authenticated",
            auth: authResponse(refreshedUser, sessionTokens),
          },
        });
        res.redirect(302, vkAuthRedirectUrl(authHandoff.code, {intent}));
        return;
      }

      const resolution = await store.resolveAuthIdentityTarget({
        provider: vkIdentity.provider,
        providerUserId: vkIdentity.providerUserId,
        email: vkIdentity.email,
        phoneNumber: vkIdentity.phoneNumber,
      });

      const vkProfile = {
        firstName: vkIdentity.metadata?.firstName || "",
        lastName: vkIdentity.metadata?.lastName || "",
        email: vkIdentity.email || "",
        phoneNumber: vkIdentity.phoneNumber || "",
        photoUrl: vkIdentity.metadata?.avatar || "",
      };

      if (intent === "link") {
        const pendingLinkHandoff = await store.createAuthHandoff({
          type: "vk_pending_link",
          payload: {
            vkIdentity,
            vkProfile,
            resolvedUserId: resolution?.user?.id || null,
            resolutionReason: resolution?.reason || "new_account",
          },
        });
        const authHandoff = await store.createAuthHandoff({
          type: "vk_auth_result",
          payload: {
            status: "pending_link",
            linkCode: pendingLinkHandoff.code,
            vkProfile,
            message:
              "VK ID подтверждён. После возвращения мы привяжем его к текущему аккаунту Родни, если не найдём конфликт по подтверждённому номеру или email.",
          },
        });
        res.redirect(302, vkAuthRedirectUrl(authHandoff.code, {intent}));
        return;
      }

      if (resolution?.user?.id) {
        const user = await store.linkAuthIdentity(resolution.user.id, vkIdentity);
        const sessionTokens = await store.createSession(user.id);
        const authHandoff = await store.createAuthHandoff({
          type: "vk_auth_result",
          userId: user.id,
          payload: {
            status: "authenticated",
            auth: authResponse(user, sessionTokens),
          },
        });
        res.redirect(302, vkAuthRedirectUrl(authHandoff.code, {intent}));
        return;
      }

      if (!vkIdentity.email) {
        const pendingLinkHandoff = await store.createAuthHandoff({
          type: "vk_pending_link",
          payload: {
            vkIdentity,
            vkProfile,
            resolvedUserId: null,
            resolutionReason: resolution?.reason || "new_account",
          },
        });
        const authHandoff = await store.createAuthHandoff({
          type: "vk_auth_result",
          payload: {
            status: "pending_link",
            linkCode: pendingLinkHandoff.code,
            vkProfile,
            message:
              "VK ID не вернул email для безопасного создания нового аккаунта. Войдите в существующий аккаунт Родни и привяжите VK ID оттуда.",
          },
        });
        res.redirect(302, vkAuthRedirectUrl(authHandoff.code, {intent}));
        return;
      }

      const user = await store.createUser({
        email: vkIdentity.email,
        displayName: vkIdentity.displayName || vkIdentity.email,
        password: null,
        authIdentity: vkIdentity,
        photoUrl: vkIdentity.metadata?.avatar || null,
      });
      const sessionTokens = await store.createSession(user.id);
      const authHandoff = await store.createAuthHandoff({
        type: "vk_auth_result",
        userId: user.id,
        payload: {
          status: "authenticated",
          auth: authResponse(user, sessionTokens),
        },
      });
      res.redirect(302, vkAuthRedirectUrl(authHandoff.code, {intent}));
    } catch (error) {
      console.error("[backend] vk auth callback failed", error);
      const appUrl = resolvePublicAppUrl();
      const normalizedMessage = (() => {
        switch (error?.message) {
          case "VK_AUTH_NOT_CONFIGURED":
            return "VK ID login пока не настроен";
          case "VK_AUTH_STATE_INVALID":
            return "VK ID login устарел. Повторите попытку.";
          case "VK_AUTH_CALLBACK_INVALID":
          case "VK_AUTH_CODE_REQUIRED":
            return "VK ID не вернул код авторизации. Повторите попытку.";
          case "EMAIL_ALREADY_EXISTS":
            return "Этот email уже зарегистрирован. Войдите в Родню и привяжите VK ID оттуда.";
          case "invalid_request":
          case "access_denied":
            return error?.description || "Вход через VK ID отменён.";
          default:
            return "Не удалось завершить вход через VK ID";
        }
      })();
      res.redirect(
        302,
        `${appUrl}/#/login?vkAuthError=${encodeURIComponent(normalizedMessage)}`,
      );
    }
  });

  app.post("/v1/auth/vk/exchange", async (req, res) => {
    const code = String(req.body?.code || "").trim();
    if (!code) {
      res.status(400).json({message: "Нужен code"});
      return;
    }

    const handoff = await store.consumeAuthHandoff(code, {
      type: "vk_auth_result",
    });
    if (!handoff) {
      res.status(404).json({message: "VK ID handoff не найден или уже использован"});
      return;
    }

    res.json(handoff.payload || {});
  });

  app.post("/v1/auth/vk/link", requireAuth, async (req, res) => {
    const code = String(req.body?.code || "").trim();
    if (!code) {
      res.status(400).json({message: "Нужен code"});
      return;
    }

    const handoff = await store.consumeAuthHandoff(code, {
      type: "vk_pending_link",
    });
    if (!handoff) {
      res.status(404).json({message: "VK ID link code не найден или уже использован"});
      return;
    }

    const resolvedUserId = String(handoff.payload?.resolvedUserId || "").trim();
    if (resolvedUserId && resolvedUserId !== req.auth.user.id) {
      res.status(409).json({
        message:
          "Этот VK ID уже совпал с другим аккаунтом Родни по подтверждённому номеру или email. Войдите в тот аккаунт и привяжите VK ID там.",
      });
      return;
    }

    try {
      const updatedUser = await store.linkAuthIdentity(
        req.auth.user.id,
        handoff.payload?.vkIdentity || {},
      );
      res.json({
        ok: true,
        user: {
          id: updatedUser.id,
          identityId: updatedUser.identityId || null,
          email: updatedUser.email,
          providerIds: updatedUser.providerIds || ["password"],
        },
      });
    } catch (error) {
      if (error?.message === "AUTH_IDENTITY_ALREADY_LINKED") {
        res.status(409).json({
          message:
            "Этот VK ID уже привязан к другому аккаунту Родни.",
        });
        return;
      }
      if (error?.message === "AUTH_PROVIDER_ALREADY_LINKED_FOR_USER") {
        res.status(409).json({
          message:
            "К этому аккаунту уже привязан другой VK ID. Сначала отвяжите его или используйте уже связанный вход.",
        });
        return;
      }
      if (error?.message === "INVALID_AUTH_IDENTITY") {
        res.status(400).json({message: "Некорректные данные VK ID"});
        return;
      }
      throw error;
    }
  });

  app.get("/v1/auth/telegram/start", async (req, res) => {
    if (!config.telegramLoginEnabled) {
      res.status(503).send("Telegram login is not configured.");
      return;
    }

    const callbackUrl = `${resolvePublicApiUrl(req).replace(/\/$/, "")}/v1/auth/telegram/callback`;
    res.setHeader("cache-control", "no-store");
    res.type("html").send(
      renderTelegramLoginPage({
        botUsername: config.telegramBotUsername,
        authUrl: callbackUrl,
      }),
    );
  });

  app.get("/v1/auth/telegram/callback", async (req, res) => {
    try {
      const intent = String(req.query?.intent || "").trim().toLowerCase() === "link"
        ? "link"
        : "login";
      const telegramAuth = verifyTelegramLoginPayload(req.query || {});
      const telegramIdentity = buildTelegramIdentityFromAuth(telegramAuth);
      const linkedUser = await store.findUserByAuthIdentity(
        telegramIdentity.provider,
        telegramIdentity.providerUserId,
      );

      if (linkedUser) {
        if (intent === "link") {
          const authHandoff = await store.createAuthHandoff({
            type: "telegram_auth_result",
            userId: linkedUser.id,
            payload: {
              status: "already_linked",
              message:
                "Этот Telegram уже привязан к аккаунту Родни. Если это ваш аккаунт, входите через Telegram с экрана входа.",
            },
          });
          res.redirect(302, telegramAuthRedirectUrl(authHandoff.code, {intent}));
          return;
        }

        const refreshedUser = await store.linkAuthIdentity(
          linkedUser.id,
          telegramIdentity,
        );
        const sessionTokens = await store.createSession(refreshedUser.id);
        const authHandoff = await store.createAuthHandoff({
          type: "telegram_auth_result",
          userId: refreshedUser.id,
          payload: {
            status: "authenticated",
            auth: authResponse(refreshedUser, sessionTokens),
          },
        });
        res.redirect(302, telegramAuthRedirectUrl(authHandoff.code, {intent}));
        return;
      }

      const pendingLinkHandoff = await store.createAuthHandoff({
        type: "telegram_pending_link",
        payload: {
          telegramIdentity,
          telegramProfile: {
            id: telegramAuth.id,
            firstName: telegramAuth.first_name || "",
            lastName: telegramAuth.last_name || "",
            username: telegramAuth.username || "",
            photoUrl: telegramAuth.photo_url || "",
          },
        },
      });

      const authHandoff = await store.createAuthHandoff({
        type: "telegram_auth_result",
        payload: {
          status: "pending_link",
          linkCode: pendingLinkHandoff.code,
          telegramProfile: {
            firstName: telegramAuth.first_name || "",
            lastName: telegramAuth.last_name || "",
            username: telegramAuth.username || "",
            photoUrl: telegramAuth.photo_url || "",
          },
          message:
            "Telegram подтверждён. Теперь войдите в существующий аккаунт Родни, чтобы привязать Telegram и не создать дубль.",
        },
      });

      res.redirect(302, telegramAuthRedirectUrl(authHandoff.code, {intent}));
    } catch (error) {
      console.error("[backend] telegram auth callback failed", error);
      const appUrl = resolvePublicAppUrl();
      const normalizedMessage = (() => {
        switch (error?.message) {
          case "TELEGRAM_LOGIN_DISABLED":
            return "Telegram login is not configured";
          case "INVALID_TELEGRAM_SIGNATURE":
            return "Не удалось проверить подпись Telegram";
          case "TELEGRAM_AUTH_EXPIRED":
            return "Telegram login устарел. Повторите попытку.";
          default:
            return "Не удалось завершить вход через Telegram";
        }
      })();
      res.redirect(
        302,
        `${appUrl}/#/login?telegramAuthError=${encodeURIComponent(normalizedMessage)}`,
      );
    }
  });

  app.post("/v1/auth/telegram/exchange", async (req, res) => {
    const code = String(req.body?.code || "").trim();
    if (!code) {
      res.status(400).json({message: "Нужен code"});
      return;
    }

    const handoff = await store.consumeAuthHandoff(code, {
      type: "telegram_auth_result",
    });
    if (!handoff) {
      res.status(404).json({message: "Telegram handoff не найден или уже использован"});
      return;
    }

    res.json(handoff.payload || {});
  });

  app.post("/v1/auth/telegram/link", requireAuth, async (req, res) => {
    const code = String(req.body?.code || "").trim();
    if (!code) {
      res.status(400).json({message: "Нужен code"});
      return;
    }

    const handoff = await store.consumeAuthHandoff(code, {
      type: "telegram_pending_link",
    });
    if (!handoff) {
      res.status(404).json({message: "Telegram link code не найден или уже использован"});
      return;
    }

    try {
      const updatedUser = await store.linkAuthIdentity(
        req.auth.user.id,
        handoff.payload?.telegramIdentity || {},
      );
      res.json({
        ok: true,
        user: {
          id: updatedUser.id,
          identityId: updatedUser.identityId || null,
          email: updatedUser.email,
          providerIds: updatedUser.providerIds || ["password"],
        },
      });
    } catch (error) {
      if (error?.message === "AUTH_IDENTITY_ALREADY_LINKED") {
        res.status(409).json({
          message:
            "Этот Telegram уже привязан к другому аккаунту Родни.",
        });
        return;
      }
      if (error?.message === "AUTH_PROVIDER_ALREADY_LINKED_FOR_USER") {
        res.status(409).json({
          message:
            "К этому аккаунту уже привязан другой Telegram. Сначала отвяжите его или используйте уже связанный вход.",
        });
        return;
      }
      if (error?.message === "INVALID_AUTH_IDENTITY") {
        res.status(400).json({message: "Некорректные данные Telegram identity"});
        return;
      }
      throw error;
    }
  });

  app.get("/v1/auth/max/start", async (req, res) => {
    if (!resolvedMaxAuthClient.isEnabled) {
      res.status(503).send("MAX login is not configured.");
      return;
    }

    const intent = String(req.query?.intent || "").trim().toLowerCase() === "link"
      ? "link"
      : "login";
    const authFlowHandoff = await store.createAuthHandoff({
      type: "max_auth_flow",
      payload: {intent},
    });

    res.setHeader("cache-control", "no-store");
    res.redirect(
      302,
      resolvedMaxAuthClient.buildStartUrl({
        intent,
        flowCode: authFlowHandoff.code,
      }),
    );
  });

  app.post("/v1/auth/max/complete", async (req, res) => {
    try {
      if (!resolvedMaxAuthClient.isEnabled) {
        throw new Error("MAX_AUTH_NOT_CONFIGURED");
      }

      const launchData = resolvedMaxAuthClient.verifyInitData(
        String(req.body?.initData || "").trim(),
      );
      const {intent, flowCode} = parseMaxStartParam(launchData.startParam);
      const authFlowHandoff = await store.consumeAuthHandoff(flowCode, {
        type: "max_auth_flow",
      });
      if (!authFlowHandoff) {
        throw new Error("MAX_AUTH_STATE_INVALID");
      }

      const effectiveIntent = String(authFlowHandoff.payload?.intent || "").trim().toLowerCase() === "link"
        ? "link"
        : intent;
      const maxIdentity = buildMaxIdentityFromLaunch(launchData);
      const linkedUser = await store.findUserByAuthIdentity(
        maxIdentity.provider,
        maxIdentity.providerUserId,
      );

      if (linkedUser) {
        if (effectiveIntent === "link") {
          const authHandoff = await store.createAuthHandoff({
            type: "max_auth_result",
            userId: linkedUser.id,
            payload: {
              status: "already_linked",
              message:
                "Этот MAX уже привязан к аккаунту Родни. Если это ваш аккаунт, входите через MAX с экрана входа.",
            },
          });
          res.json({
            ok: true,
            redirectUrl: maxAuthRedirectUrl(authHandoff.code, {
              intent: effectiveIntent,
            }),
            status: "already_linked",
            handoffCode: authHandoff.code,
          });
          return;
        }

        const refreshedUser = await store.linkAuthIdentity(
          linkedUser.id,
          maxIdentity,
        );
        const sessionTokens = await store.createSession(refreshedUser.id);
        const authHandoff = await store.createAuthHandoff({
          type: "max_auth_result",
          userId: refreshedUser.id,
          payload: {
            status: "authenticated",
            auth: authResponse(refreshedUser, sessionTokens),
          },
        });
        res.json({
          ok: true,
          redirectUrl: maxAuthRedirectUrl(authHandoff.code, {
            intent: effectiveIntent,
          }),
          status: "authenticated",
          handoffCode: authHandoff.code,
        });
        return;
      }

      const maxProfile = {
        firstName: maxIdentity.metadata?.firstName || "",
        lastName: maxIdentity.metadata?.lastName || "",
        username: maxIdentity.metadata?.username || "",
        photoUrl: maxIdentity.metadata?.photoUrl || "",
      };
      const pendingLinkHandoff = await store.createAuthHandoff({
        type: "max_pending_link",
        payload: {
          maxIdentity,
          maxProfile,
        },
      });
      const authHandoff = await store.createAuthHandoff({
        type: "max_auth_result",
        payload: {
          status: "pending_link",
          linkCode: pendingLinkHandoff.code,
          maxProfile,
          message:
            "MAX подтверждён. Теперь войдите или создайте аккаунт Родни, и мы привяжем MAX без дубля профиля.",
        },
      });
      res.json({
        ok: true,
        redirectUrl: maxAuthRedirectUrl(authHandoff.code, {
          intent: effectiveIntent,
        }),
        status: "pending_link",
        handoffCode: authHandoff.code,
      });
    } catch (error) {
      const normalizedMessage = (() => {
        switch (error?.message) {
          case "MAX_AUTH_NOT_CONFIGURED":
            return "MAX login пока не настроен";
          case "MAX_INIT_DATA_REQUIRED":
          case "MAX_INIT_DATA_INVALID":
          case "MAX_INIT_DATA_DUPLICATE_KEYS":
          case "MAX_INIT_DATA_HASH_REQUIRED":
          case "MAX_INIT_DATA_SIGNATURE_INVALID":
            return "Не удалось проверить подпись MAX";
          case "MAX_INIT_DATA_AUTH_DATE_INVALID":
          case "MAX_INIT_DATA_EXPIRED":
            return "MAX login устарел. Повторите попытку.";
          case "MAX_AUTH_STATE_INVALID":
          case "MAX_AUTH_START_PARAM_INVALID":
            return "MAX login устарел. Запустите flow ещё раз из Родни.";
          default:
            return "Не удалось завершить вход через MAX";
        }
      })();
      const statusCode =
        error?.message === "MAX_AUTH_NOT_CONFIGURED"
          ? 503
          : error?.message === "MAX_AUTH_STATE_INVALID"
            ? 410
            : 401;
      res.status(statusCode).json({
        message: normalizedMessage,
        errorCode: String(error?.message || "MAX_AUTH_FAILED"),
      });
    }
  });

  app.post("/v1/auth/max/exchange", async (req, res) => {
    const code = String(req.body?.code || "").trim();
    if (!code) {
      res.status(400).json({message: "Нужен code"});
      return;
    }

    const handoff = await store.consumeAuthHandoff(code, {
      type: "max_auth_result",
    });
    if (!handoff) {
      res.status(404).json({message: "MAX handoff не найден или уже использован"});
      return;
    }

    res.json(handoff.payload || {});
  });

  app.post("/v1/auth/max/link", requireAuth, async (req, res) => {
    const code = String(req.body?.code || "").trim();
    if (!code) {
      res.status(400).json({message: "Нужен code"});
      return;
    }

    const handoff = await store.consumeAuthHandoff(code, {
      type: "max_pending_link",
    });
    if (!handoff) {
      res.status(404).json({message: "MAX link code не найден или уже использован"});
      return;
    }

    try {
      const updatedUser = await store.linkAuthIdentity(
        req.auth.user.id,
        handoff.payload?.maxIdentity || {},
      );
      res.json({
        ok: true,
        user: {
          id: updatedUser.id,
          identityId: updatedUser.identityId || null,
          email: updatedUser.email,
          providerIds: updatedUser.providerIds || ["password"],
        },
      });
    } catch (error) {
      if (error?.message === "AUTH_IDENTITY_ALREADY_LINKED") {
        res.status(409).json({
          message: "Этот MAX уже привязан к другому аккаунту Родни.",
        });
        return;
      }
      if (error?.message === "AUTH_PROVIDER_ALREADY_LINKED_FOR_USER") {
        res.status(409).json({
          message:
            "К этому аккаунту уже привязан другой MAX. Сначала отвяжите его или используйте уже связанный вход.",
        });
        return;
      }
      if (error?.message === "INVALID_AUTH_IDENTITY") {
        res.status(400).json({message: "Некорректные данные MAX identity"});
        return;
      }
      throw error;
    }
  });

  app.get("/v1/profile/me/bootstrap", requireAuth, async (req, res) => {
    res.json({
      profile: sanitizeProfile(req.auth.user.profile),
      profileStatus: computeProfileStatus(req.auth.user.profile),
    });
  });

  app.put("/v1/profile/me/bootstrap", requireAuth, async (req, res) => {
    const updatedUser = await store.updateProfile(req.auth.user.id, (profile) => ({
      ...profile,
      ...req.body,
      displayName: composeDisplayName({
        ...profile,
        ...req.body,
        displayName:
          req.body.displayName !== undefined
            ? req.body.displayName
            : profile.displayName,
      }),
    }));

    res.json({
      profile: sanitizeProfile(updatedUser.profile),
      profileStatus: computeProfileStatus(updatedUser.profile),
    });
  });

  app.patch("/v1/profile/me", requireAuth, async (req, res) => {
    const updatedUser = await store.updateProfile(req.auth.user.id, (profile) => ({
      ...profile,
      ...req.body,
    }));
    const sanitizedProfile = sanitizeProfile(updatedUser.profile);

    res.json({
      user: {
        id: updatedUser.id,
        identityId: updatedUser.identityId || null,
        email: updatedUser.email,
        displayName: sanitizedProfile.displayName,
        photoUrl: sanitizedProfile.photoUrl,
      },
      profileStatus: computeProfileStatus(updatedUser.profile),
    });
  });

  app.get("/v1/profile/me/contributions", requireAuth, async (req, res) => {
    const status = String(req.query.status || "").trim() || null;
    const contributions = await store.listProfileContributions(
      req.auth.user.id,
      {status},
    );
    const authorIds = Array.from(
      new Set(
        contributions
          .map((entry) => String(entry.authorUserId || "").trim())
          .filter(Boolean),
      ),
    );
    const authors = new Map();
    await Promise.all(
      authorIds.map(async (authorId) => {
        const user = await store.findUserById(authorId);
        if (user) {
          authors.set(authorId, user);
        }
      }),
    );

    res.json({
      contributions: contributions.map((entry) => {
        const author = authors.get(entry.authorUserId);
        return mapProfileContribution({
          ...entry,
          authorDisplayName:
            author?.profile?.displayName || author?.email || "Пользователь",
          authorPhotoUrl: author?.profile?.photoUrl || null,
        });
      }),
    });
  });

  app.post(
    "/v1/profile/me/contributions/:contributionId/accept",
    requireAuth,
    async (req, res) => {
      const result = await store.respondToProfileContribution(
        req.auth.user.id,
        req.params.contributionId,
        {accept: true},
      );
      if (!result) {
        res.status(404).json({message: "Предложение не найдено"});
        return;
      }

      res.json({
        contribution: mapProfileContribution(result.contribution),
        profile: sanitizeProfile(result.user?.profile || req.auth.user.profile),
      });
    },
  );

  app.post(
    "/v1/profile/me/contributions/:contributionId/reject",
    requireAuth,
    async (req, res) => {
      const result = await store.respondToProfileContribution(
        req.auth.user.id,
        req.params.contributionId,
        {accept: false},
      );
      if (!result) {
        res.status(404).json({message: "Предложение не найдено"});
        return;
      }

      res.json({
        contribution: mapProfileContribution(result.contribution),
      });
    },
  );

  app.get("/v1/users/:userId/profile-notes", requireAuth, async (req, res) => {
    if (!requireOwnUser(req, res)) {
      return;
    }

    const notes = await store.listProfileNotes(req.params.userId);
    if (notes === null) {
      res.status(404).json({message: "Пользователь не найден"});
      return;
    }

    res.json({
      notes: notes.map(mapProfileNote),
    });
  });

  app.post("/v1/users/:userId/profile-notes", requireAuth, async (req, res) => {
    if (!requireOwnUser(req, res)) {
      return;
    }

    const {title, content} = req.body || {};
    if (!String(title || "").trim() || !String(content || "").trim()) {
      res.status(400).json({message: "Нужны title и content"});
      return;
    }

    const note = await store.addProfileNote(req.params.userId, {
      title,
      content,
    });
    if (note === null) {
      res.status(404).json({message: "Пользователь не найден"});
      return;
    }

    res.status(201).json({note: mapProfileNote(note)});
  });

  app.patch(
    "/v1/users/:userId/profile-notes/:noteId",
    requireAuth,
    async (req, res) => {
      if (!requireOwnUser(req, res)) {
        return;
      }

      const note = await store.updateProfileNote(
        req.params.userId,
        req.params.noteId,
        {
          title: req.body?.title,
          content: req.body?.content,
        },
      );

      if (note === null) {
        res.status(404).json({message: "Пользователь не найден"});
        return;
      }
      if (note === undefined) {
        res.status(404).json({message: "Заметка не найдена"});
        return;
      }

      res.json({note: mapProfileNote(note)});
    },
  );

  app.delete(
    "/v1/users/:userId/profile-notes/:noteId",
    requireAuth,
    async (req, res) => {
      if (!requireOwnUser(req, res)) {
        return;
      }

      const deleted = await store.deleteProfileNote(
        req.params.userId,
        req.params.noteId,
      );
      if (deleted === null) {
        res.status(404).json({message: "Пользователь не найден"});
        return;
      }
      if (deleted === false) {
        res.status(404).json({message: "Заметка не найдена"});
        return;
      }

      res.status(204).send();
    },
  );

  app.post("/v1/media/upload", requireAuth, async (req, res) => {
    const {bucket, path: mediaPath, fileBase64, contentType} = req.body || {};

    if (!bucket || !mediaPath || !fileBase64) {
      res.status(400).json({
        message: "Нужны bucket, path и fileBase64",
      });
      return;
    }

    try {
      const fileBuffer = Buffer.from(String(fileBase64), "base64");
      if (fileBuffer.length === 0) {
        res.status(400).json({message: "Пустой fileBase64 payload"});
        return;
      }

      const uploadResult = await resolvedMediaStorage.saveObject({
        req,
        bucket,
        relativePath: mediaPath,
        contentType,
        fileBuffer,
      });

      res.status(201).json(uploadResult);
    } catch (error) {
      if (error.message === "INVALID_MEDIA_PATH") {
        res.status(400).json({message: "Недопустимый media path"});
        return;
      }
      res.status(500).json({message: "Не удалось сохранить файл"});
    }
  });

  app.delete("/v1/media", requireAuth, async (req, res) => {
    const urlValue = String(req.body?.url || "").trim();
    if (!urlValue) {
      res.status(400).json({message: "Нужен url"});
      return;
    }

    try {
      await resolvedMediaStorage.deleteObjectByUrl(urlValue);
      res.status(204).send();
    } catch (error) {
      if (
        error.message === "INVALID_MEDIA_PATH" ||
        error.message === "UNSUPPORTED_MEDIA_URL" ||
        error instanceof TypeError
      ) {
        res.status(400).json({message: "Недопустимый media URL"});
        return;
      }
      res.status(500).json({message: "Не удалось удалить файл"});
    }
  });

  app.get("/v1/stories", requireAuth, async (req, res) => {
    const treeId = String(req.query.treeId || "").trim() || null;
    const authorId = String(req.query.authorId || "").trim() || null;

    if (treeId) {
      const tree = await requireTreeAccess(req, res, treeId);
      if (!tree) {
        return;
      }
    }

    const accessibleTrees = await store.listUserTrees(req.auth.user.id);
    const accessibleTreeIds = new Set(accessibleTrees.map((tree) => tree.id));
    const stories = await store.listStories({treeId, authorId});
    const visibleStories = stories.filter((story) => accessibleTreeIds.has(story.treeId));

    res.json(visibleStories.map(mapStory));
  });

  app.post("/v1/stories", requireAuth, async (req, res) => {
    const treeId = String(req.body?.treeId || "").trim();
    const type = String(req.body?.type || "text").trim();
    const text = req.body?.text;
    const mediaUrl = req.body?.mediaUrl;
    const thumbnailUrl = req.body?.thumbnailUrl;
    const expiresAt = req.body?.expiresAt;

    if (!treeId) {
      res.status(400).json({message: "Нужен treeId"});
      return;
    }

    const tree = await requireTreeAccess(req, res, treeId);
    if (!tree) {
      return;
    }

    const story = await store.createStory({
      treeId: tree.id,
      authorId: req.auth.user.id,
      authorName:
        req.auth.user.profile?.displayName ||
        composeDisplayName(req.auth.user.profile) ||
        req.auth.user.email ||
        "Аноним",
      authorPhotoUrl: req.auth.user.profile?.photoUrl || null,
      type,
      text,
      mediaUrl,
      thumbnailUrl,
      expiresAt,
    });

    if (story === false) {
      res.status(400).json({
        message: "Story должна содержать текст или media в зависимости от типа",
      });
      return;
    }
    if (!story) {
      res.status(404).json({message: "Дерево не найдено"});
      return;
    }

    res.status(201).json(mapStory(story));
  });

  app.post("/v1/stories/:storyId/view", requireAuth, async (req, res) => {
    const story = await store.findStory(req.params.storyId);
    if (!story) {
      res.status(404).json({message: "Story не найдена"});
      return;
    }

    const tree = await requireTreeAccess(req, res, story.treeId);
    if (!tree) {
      return;
    }

    const updatedStory = await store.markStoryViewed(
      req.params.storyId,
      req.auth.user.id,
    );
    if (!updatedStory) {
      res.status(404).json({message: "Story не найдена"});
      return;
    }

    res.json(mapStory(updatedStory));
  });

  app.delete("/v1/stories/:storyId", requireAuth, async (req, res) => {
    const story = await store.findStory(req.params.storyId);
    if (!story) {
      res.status(404).json({message: "Story не найдена"});
      return;
    }

    const tree = await requireTreeAccess(req, res, story.treeId);
    if (!tree) {
      return;
    }

    const deletedStory = await store.deleteStory(req.params.storyId, req.auth.user.id);
    if (deletedStory === false) {
      res.status(403).json({message: "Можно удалять только свои stories"});
      return;
    }
    if (!deletedStory) {
      res.status(404).json({message: "Story не найдена"});
      return;
    }

    res.status(204).send();
  });

  app.get("/v1/posts", requireAuth, async (req, res) => {
    const treeId = String(req.query.treeId || "").trim() || null;
    const authorId = String(req.query.authorId || "").trim() || null;
    const scope = String(req.query.scope || "").trim() || null;

    if (treeId) {
      const tree = await requireTreeAccess(req, res, treeId);
      if (!tree) {
        return;
      }
    }

    const accessibleTrees = await store.listUserTrees(req.auth.user.id);
    const accessibleTreeIds = new Set(accessibleTrees.map((tree) => tree.id));
    const posts = await store.listPosts({treeId, authorId, scope});
    const visiblePosts = posts.filter((post) => accessibleTreeIds.has(post.treeId));
    const payload = await Promise.all(
      visiblePosts.map(async (post) => {
        const comments = await store.listPostComments(post.id);
        return mapPost(post, comments.length);
      }),
    );

    res.json(payload);
  });

  app.post("/v1/posts", requireAuth, async (req, res) => {
    const treeId = String(req.body?.treeId || "").trim();
    const content = String(req.body?.content || "");
    const imageUrls = Array.isArray(req.body?.imageUrls) ? req.body.imageUrls : [];
    const isPublic = req.body?.isPublic === true;
    const scopeType = String(req.body?.scopeType || "wholeTree").trim();
    const anchorPersonIds = Array.isArray(req.body?.anchorPersonIds)
      ? req.body.anchorPersonIds
      : [];

    if (!treeId) {
      res.status(400).json({message: "Нужен treeId"});
      return;
    }

    const tree = await requireTreeAccess(req, res, treeId);
    if (!tree) {
      return;
    }

    const treePersons = await store.listPersons(tree.id);
    const validPersonIds = new Set(treePersons.map((person) => person.id));
    const normalizedAnchorPersonIds = anchorPersonIds
      .map((value) => String(value || "").trim())
      .filter((value) => validPersonIds.has(value));

    const post = await store.createPost({
      treeId: tree.id,
      authorId: req.auth.user.id,
      authorName:
        req.auth.user.profile?.displayName ||
        composeDisplayName(req.auth.user.profile) ||
        req.auth.user.email ||
        "Аноним",
      authorPhotoUrl: req.auth.user.profile?.photoUrl || null,
      content,
      imageUrls,
      isPublic,
      scopeType,
      anchorPersonIds: normalizedAnchorPersonIds,
    });

    if (post === false) {
      res.status(400).json({message: "Пост не должен быть пустым"});
      return;
    }
    if (!post) {
      res.status(404).json({message: "Дерево не найдено"});
      return;
    }

    res.status(201).json(mapPost(post, 0));
  });

  app.delete("/v1/posts/:postId", requireAuth, async (req, res) => {
    const post = await store.findPost(req.params.postId);
    if (!post) {
      res.status(404).json({message: "Публикация не найдена"});
      return;
    }

    const tree = await requireTreeAccess(req, res, post.treeId);
    if (!tree) {
      return;
    }

    const deleted = await store.deletePost(req.params.postId, req.auth.user.id);
    if (deleted === false) {
      res.status(403).json({message: "Можно удалять только свои публикации"});
      return;
    }

    res.status(204).send();
  });

  app.post("/v1/posts/:postId/like", requireAuth, async (req, res) => {
    const post = await store.findPost(req.params.postId);
    if (!post) {
      res.status(404).json({message: "Публикация не найдена"});
      return;
    }

    const tree = await requireTreeAccess(req, res, post.treeId);
    if (!tree) {
      return;
    }

    const updated = await store.togglePostLike(req.params.postId, req.auth.user.id);
    const comments = await store.listPostComments(req.params.postId);
    res.json(mapPost(updated, comments.length));
  });

  app.get("/v1/posts/:postId/comments", requireAuth, async (req, res) => {
    const post = await store.findPost(req.params.postId);
    if (!post) {
      res.status(404).json({message: "Публикация не найдена"});
      return;
    }

    const tree = await requireTreeAccess(req, res, post.treeId);
    if (!tree) {
      return;
    }

    const comments = await store.listPostComments(req.params.postId);
    res.json(comments.map(mapComment));
  });

  app.post("/v1/posts/:postId/comments", requireAuth, async (req, res) => {
    const post = await store.findPost(req.params.postId);
    if (!post) {
      res.status(404).json({message: "Публикация не найдена"});
      return;
    }

    const tree = await requireTreeAccess(req, res, post.treeId);
    if (!tree) {
      return;
    }

    const comment = await store.addPostComment({
      postId: req.params.postId,
      authorId: req.auth.user.id,
      authorName:
        req.auth.user.profile?.displayName ||
        composeDisplayName(req.auth.user.profile) ||
        req.auth.user.email ||
        "Аноним",
      authorPhotoUrl: req.auth.user.profile?.photoUrl || null,
      content: req.body?.content,
    });

    if (comment === false) {
      res.status(400).json({message: "Комментарий не должен быть пустым"});
      return;
    }

    res.status(201).json(mapComment(comment));
  });

  app.delete(
    "/v1/posts/:postId/comments/:commentId",
    requireAuth,
    async (req, res) => {
      const post = await store.findPost(req.params.postId);
      if (!post) {
        res.status(404).json({message: "Публикация не найдена"});
        return;
      }

      const tree = await requireTreeAccess(req, res, post.treeId);
      if (!tree) {
        return;
      }

      const deleted = await store.deletePostComment({
        postId: req.params.postId,
        commentId: req.params.commentId,
        actorUserId: req.auth.user.id,
      });
      if (deleted === null) {
        res.status(404).json({message: "Комментарий не найден"});
        return;
      }
      if (deleted === false) {
        res.status(403).json({message: "Недостаточно прав для удаления комментария"});
        return;
      }

      res.status(204).send();
    },
  );

  app.post("/v1/trees", requireAuth, async (req, res) => {
    const {name, description, isPrivate, kind} = req.body || {};
    if (!String(name || "").trim()) {
      res.status(400).json({message: "Нужно название дерева"});
      return;
    }

    const tree = await store.createTree({
      creatorId: req.auth.user.id,
      name,
      description,
      isPrivate,
      kind,
    });

    res.status(201).json({tree: mapTree(tree)});
  });

  app.get("/v1/trees", requireAuth, async (req, res) => {
    const trees = await store.listUserTrees(req.auth.user.id);
    res.json({
      trees: trees.map(mapTree),
    });
  });

  app.delete("/v1/trees/:treeId", requireAuth, async (req, res) => {
    const tree = await store.findTree(req.params.treeId);
    if (!tree) {
      res.status(404).json({message: "Дерево не найдено"});
      return;
    }

    const memberIds = Array.isArray(tree.memberIds) ? tree.memberIds : [];
    const members = Array.isArray(tree.members) ? tree.members : [];
    const hasAccess =
      tree.creatorId === req.auth.user.id ||
      memberIds.includes(req.auth.user.id) ||
      members.includes(req.auth.user.id);
    if (!hasAccess) {
      res.status(403).json({message: "Доступ к дереву запрещён"});
      return;
    }

    const result = await store.removeTreeForUser({
      treeId: req.params.treeId,
      userId: req.auth.user.id,
    });
    if (result === null) {
      res.status(404).json({message: "Дерево не найдено"});
      return;
    }
    if (result === false) {
      res.status(403).json({message: "Доступ к дереву запрещён"});
      return;
    }

    res.json({
      action: result.action,
      tree: mapTree(result.tree),
    });
  });

  app.get("/v1/public/trees/:publicTreeId", async (req, res) => {
    const tree = await requirePublicTree(req, res, req.params.publicTreeId);
    if (!tree) {
      return;
    }

    const [persons, relations] = await Promise.all([
      store.listPersons(tree.id),
      store.listRelations(tree.id),
    ]);

    res.json({
      tree: mapTree(tree),
      stats: {
        peopleCount: persons.length,
        relationsCount: relations.length,
      },
    });
  });

  app.get("/v1/public/trees/:publicTreeId/persons", async (req, res) => {
    const tree = await requirePublicTree(req, res, req.params.publicTreeId);
    if (!tree) {
      return;
    }

    const persons = await store.listPersons(tree.id);
    res.json({
      tree: mapTree(tree),
      persons: persons.map(mapPerson),
    });
  });

  app.get("/v1/public/trees/:publicTreeId/relations", async (req, res) => {
    const tree = await requirePublicTree(req, res, req.params.publicTreeId);
    if (!tree) {
      return;
    }

    const relations = await store.listRelations(tree.id);
    res.json({
      tree: mapTree(tree),
      relations: relations.map(mapRelation),
    });
  });

  app.get("/v1/trees/selectable", requireAuth, async (req, res) => {
    const trees = await store.listUserTrees(req.auth.user.id);
    res.json({
      trees: trees.map((tree) => ({
        id: tree.id,
        name: tree.name,
        createdAt: tree.createdAt,
      })),
    });
  });

  app.get("/v1/trees/:treeId/persons", requireAuth, async (req, res) => {
    const tree = await requireTreeAccess(req, res, req.params.treeId);
    if (!tree) {
      return;
    }

    const persons = await store.listPersons(tree.id);
    res.json({
      persons: persons.map(mapPerson),
    });
  });

  app.post("/v1/trees/:treeId/persons", requireAuth, async (req, res) => {
    const tree = await requireTreeAccess(req, res, req.params.treeId);
    if (!tree) {
      return;
    }

    const requestedUserId = req.body?.userId;
    if (requestedUserId && requestedUserId !== req.auth.user.id) {
      res.status(403).json({
        message: "Нельзя привязать к профилю другого пользователя",
      });
      return;
    }

    const person = await store.createPerson({
      treeId: tree.id,
      creatorId: req.auth.user.id,
      userId: requestedUserId || null,
      personData: req.body || {},
    });

    if (!person) {
      res.status(404).json({message: "Семейное дерево не найдено"});
      return;
    }

    res.status(201).json({person: mapPerson(person)});
  });

  app.get(
    "/v1/trees/:treeId/persons/:personId",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) {
        return;
      }

      const person = await store.findPerson(tree.id, req.params.personId);
      if (!person) {
        res.status(404).json({message: "Человек не найден"});
        return;
      }

      res.json({person: mapPerson(person)});
    },
  );

  app.get(
    "/v1/trees/:treeId/persons/:personId/dossier",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) {
        return;
      }

      const dossier = await buildPersonDossierPayload({
        treeId: tree.id,
        personId: req.params.personId,
        viewerUserId: req.auth.user.id,
      });
      if (!dossier) {
        res.status(404).json({message: "Человек не найден"});
        return;
      }

      res.json({dossier});
    },
  );

  app.patch(
    "/v1/trees/:treeId/persons/:personId",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) {
        return;
      }

      const person = await store.updatePerson(
        tree.id,
        req.params.personId,
        req.body || {},
        req.auth.user.id,
      );
      if (!person) {
        res.status(404).json({message: "Человек не найден"});
        return;
      }

      res.json({person: mapPerson(person)});
    },
  );

  app.post(
    "/v1/trees/:treeId/persons/:personId/profile-contributions",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) {
        return;
      }

      const contribution = await store.createProfileContribution({
        treeId: tree.id,
        personId: req.params.personId,
        authorUserId: req.auth.user.id,
        message: req.body?.message,
        fields: req.body?.fields,
      });
      if (contribution === null) {
        res.status(404).json({message: "Человек не найден"});
        return;
      }
      if (contribution === false) {
        res.status(403).json({
          message: "Пользователь не принимает предложения по профилю.",
        });
        return;
      }
      if (contribution === undefined) {
        res.status(400).json({message: "Нет данных для предложения правки"});
        return;
      }

      const author = await store.findUserById(req.auth.user.id);
      res.status(201).json({
        contribution: mapProfileContribution({
          ...contribution,
          authorDisplayName:
            author?.profile?.displayName || author?.email || "Пользователь",
          authorPhotoUrl: author?.profile?.photoUrl || null,
        }),
      });
    },
  );

  app.delete(
    "/v1/trees/:treeId/persons/:personId",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) {
        return;
      }

      const deleted = await store.deletePerson(
        tree.id,
        req.params.personId,
        req.auth.user.id,
      );
      if (!deleted) {
        res.status(404).json({message: "Человек не найден"});
        return;
      }

      res.status(204).send();
    },
  );

  app.post(
    "/v1/trees/:treeId/persons/:personId/media",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) {
        return;
      }

      const url =
        req.body?.url || req.body?.mediaUrl || req.body?.photoUrl || null;
      if (!url) {
        res.status(400).json({message: "Нужен url media-файла"});
        return;
      }

      const result = await store.addPersonMedia({
        treeId: tree.id,
        personId: req.params.personId,
        actorId: req.auth.user.id,
        media: req.body || {},
      });
      if (!result) {
        res.status(404).json({message: "Человек не найден"});
        return;
      }

      res.status(201).json({
        person: mapPerson(result.person),
        media: result.media,
      });
    },
  );

  app.patch(
    "/v1/trees/:treeId/persons/:personId/media/:mediaId",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) {
        return;
      }

      const result = await store.updatePersonMedia({
        treeId: tree.id,
        personId: req.params.personId,
        mediaId: req.params.mediaId,
        actorId: req.auth.user.id,
        updates: req.body || {},
      });
      if (result === null) {
        res.status(404).json({message: "Человек не найден"});
        return;
      }
      if (result === false) {
        res.status(404).json({message: "Media элемент не найден"});
        return;
      }

      res.json({
        person: mapPerson(result.person),
        media: result.media,
      });
    },
  );

  app.delete(
    "/v1/trees/:treeId/persons/:personId/media/:mediaId",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) {
        return;
      }

      const result = await store.deletePersonMedia({
        treeId: tree.id,
        personId: req.params.personId,
        mediaId: req.params.mediaId,
        actorId: req.auth.user.id,
      });
      if (result === null) {
        res.status(404).json({message: "Человек не найден"});
        return;
      }
      if (result === false) {
        res.status(404).json({message: "Media элемент не найден"});
        return;
      }

      res.json({
        person: mapPerson(result.person),
        deletedMediaId: result.deletedMedia?.id || req.params.mediaId,
      });
    },
  );

  app.get("/v1/trees/:treeId/history", requireAuth, async (req, res) => {
    const tree = await requireTreeAccess(req, res, req.params.treeId);
    if (!tree) {
      return;
    }

    const personId = String(req.query.personId || "").trim() || null;
    const type = String(req.query.type || "").trim() || null;
    const actorId = String(req.query.actorId || "").trim() || null;
    const records = await store.listTreeChangeRecords(tree.id, {
      personId,
      type,
      actorId,
    });

    res.json({
      records: records.map(mapTreeChangeRecord),
    });
  });

  app.get("/v1/trees/:treeId/relations", requireAuth, async (req, res) => {
    const tree = await requireTreeAccess(req, res, req.params.treeId);
    if (!tree) {
      return;
    }

    const relations = await store.listRelations(tree.id);
    res.json({
      relations: relations.map(mapRelation),
    });
  });

  app.get("/v1/trees/:treeId/graph", requireAuth, async (req, res) => {
    const tree = await requireTreeAccess(req, res, req.params.treeId);
    if (!tree) {
      return;
    }

    const snapshot = await store.getTreeGraphSnapshot(tree.id, {
      viewerUserId: req.auth.user.id,
    });
    if (!snapshot) {
      res.status(404).json({message: "Дерево не найдено"});
      return;
    }

    res.json({
      snapshot: mapTreeGraphSnapshot(snapshot),
    });
  });

  app.post("/v1/trees/:treeId/relations", requireAuth, async (req, res) => {
    const tree = await requireTreeAccess(req, res, req.params.treeId);
    if (!tree) {
      return;
    }

    const {
      person1Id,
      person2Id,
      relation1to2,
      relation2to1,
      customRelationLabel1to2,
      customRelationLabel2to1,
      isConfirmed,
      marriageDate,
      divorceDate,
      parentSetId,
      parentSetType,
      isPrimaryParentSet,
      unionId,
      unionType,
      unionStatus,
    } =
      req.body || {};
    if (!person1Id || !person2Id || !relation1to2) {
      res.status(400).json({
        message: "Нужны person1Id, person2Id и relation1to2",
      });
      return;
    }

    const relation = await store.upsertRelation({
      treeId: tree.id,
      person1Id: String(person1Id),
      person2Id: String(person2Id),
      relation1to2: String(relation1to2),
      relation2to1: relation2to1 ? String(relation2to1) : undefined,
      customRelationLabel1to2:
        customRelationLabel1to2 === undefined || customRelationLabel1to2 === null
          ? customRelationLabel1to2
          : String(customRelationLabel1to2),
      customRelationLabel2to1:
        customRelationLabel2to1 === undefined || customRelationLabel2to1 === null
          ? customRelationLabel2to1
          : String(customRelationLabel2to1),
      isConfirmed: isConfirmed !== false,
      marriageDate:
        marriageDate === undefined || marriageDate === null
          ? marriageDate
          : String(marriageDate),
      divorceDate:
        divorceDate === undefined || divorceDate === null
          ? divorceDate
          : String(divorceDate),
      parentSetId:
        parentSetId === undefined || parentSetId === null
          ? parentSetId
          : String(parentSetId),
      parentSetType:
        parentSetType === undefined || parentSetType === null
          ? parentSetType
          : String(parentSetType),
      isPrimaryParentSet,
      unionId:
        unionId === undefined || unionId === null ? unionId : String(unionId),
      unionType:
        unionType === undefined || unionType === null
          ? unionType
          : String(unionType),
      unionStatus:
        unionStatus === undefined || unionStatus === null
          ? unionStatus
          : String(unionStatus),
      createdBy: req.auth.user.id,
    });

    if (!relation) {
      res.status(404).json({
        message: "Один или оба человека не найдены в дереве",
      });
      return;
    }

    res.status(201).json({relation: mapRelation(relation)});
  });

  app.delete(
    "/v1/trees/:treeId/relations/:relationId",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) {
        return;
      }

      const deletedRelation = await store.deleteRelation(
        tree.id,
        req.params.relationId,
        req.auth.user.id,
      );
      if (!deletedRelation) {
        res.status(404).json({message: "Связь не найдена"});
        return;
      }

      res.status(204).send();
    },
  );

  app.get("/v1/tree-invitations/pending", requireAuth, async (req, res) => {
    const invitations = await store.listPendingTreeInvitations(req.auth.user.id);
    const treeCache = new Map();

    for (const invitation of invitations) {
      if (!treeCache.has(invitation.treeId)) {
        treeCache.set(invitation.treeId, await store.findTree(invitation.treeId));
      }
    }

    res.json({
      invitations: invitations.map((invitation) =>
        mapTreeInvitation(invitation, treeCache.get(invitation.treeId) || null),
      ),
    });
  });

  app.post(
    "/v1/trees/:treeId/invitations",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) {
        return;
      }

      const recipientUserId = String(req.body?.recipientUserId || "").trim();
      const recipientEmail = String(req.body?.recipientEmail || "").trim().toLowerCase();
      const relationToTree = req.body?.relationToTree;

      if (!recipientUserId && !recipientEmail) {
        res.status(400).json({message: "Нужен recipientUserId или recipientEmail"});
        return;
      }

      let targetUserId = recipientUserId;
      if (!targetUserId && recipientEmail) {
        const users = await store.searchUsersByField({
          field: "email",
          value: recipientEmail,
          limit: 1,
        });
        if (!users.length) {
          res.status(404).json({message: "Пользователь с таким email не найден"});
          return;
        }
        targetUserId = users[0].id;
      }

      const invitation = await store.createTreeInvitation({
        treeId: tree.id,
        userId: targetUserId,
        addedBy: req.auth.user.id,
        relationToTree,
      });

      if (invitation === null) {
        res.status(404).json({message: "Семейное дерево не найдено"});
        return;
      }
      if (invitation === undefined) {
        res.status(404).json({message: "Приглашаемый пользователь не найден"});
        return;
      }
      if (invitation === false) {
        res.status(409).json({
          message: "Этот пользователь уже состоит в семейном дереве",
        });
        return;
      }
      if (invitation === "DUPLICATE") {
        res.status(409).json({
          message: "Для этого пользователя уже есть активное приглашение",
        });
        return;
      }

      await createAndDispatchNotification({
        userId: targetUserId,
        type: "tree_invitation",
        title: "Приглашение в семейное дерево",
        body: `Вас пригласили в дерево «${tree.name}»`,
        data: {
          invitationId: invitation.id,
          treeId: tree.id,
          treeName: tree.name,
          invitedBy: req.auth.user.id,
        },
      });

      res.status(201).json({
        invitation: mapTreeInvitation(invitation, tree),
      });
    },
  );

  app.post(
    "/v1/tree-invitations/:invitationId/respond",
    requireAuth,
    async (req, res) => {
      const accept = req.body?.accept == true;
      const invitation = await store.findTreeInvitation(req.params.invitationId);
      if (!invitation) {
        res.status(404).json({message: "Приглашение не найдено"});
        return;
      }

      if (invitation.userId !== req.auth.user.id) {
        res.status(403).json({message: "Нельзя отвечать на чужое приглашение"});
        return;
      }

      const result = await store.respondToTreeInvitation(
        req.params.invitationId,
        accept,
      );
      if (result === null) {
        res.status(404).json({message: "Приглашение не найдено"});
        return;
      }
      if (result === undefined) {
        res.status(404).json({message: "Семейное дерево не найдено"});
        return;
      }

      if (result.accepted && result.invitation.addedBy) {
        await createAndDispatchNotification({
          userId: result.invitation.addedBy,
          type: "tree_invitation_accepted",
          title: "Приглашение принято",
          body: `Пользователь принял приглашение в дерево «${result.tree.name}»`,
          data: {
            treeId: result.tree.id,
            treeName: result.tree.name,
            invitationId: result.invitation.id,
            memberUserId: result.invitation.userId,
          },
        });
      }

      res.json({
        ok: true,
        accepted: result.accepted,
        tree: mapTree(result.tree),
        invitation: mapTreeInvitation(result.invitation, result.tree),
      });
    },
  );

  app.get(
    "/v1/trees/:treeId/relation-requests",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) {
        return;
      }

      const requests = await store.listRelationRequests({
        treeId: tree.id,
        senderId: req.query.senderId ? String(req.query.senderId) : null,
        recipientId: req.query.recipientId ? String(req.query.recipientId) : null,
        status: req.query.status ? String(req.query.status) : null,
      });

      res.json({
        requests: requests.map(mapRelationRequest),
      });
    },
  );

  app.get("/v1/relation-requests/pending", requireAuth, async (req, res) => {
    const requests = await store.listRelationRequests({
      treeId: req.query.treeId ? String(req.query.treeId) : null,
      recipientId: req.auth.user.id,
      status: "pending",
    });

    res.json({
      requests: requests.map(mapRelationRequest),
    });
  });

  app.post(
    "/v1/trees/:treeId/relation-requests",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) {
        return;
      }

      const recipientId = String(req.body?.recipientId || "").trim();
      const senderToRecipient = String(
        req.body?.senderToRecipient || req.body?.relationType || "other",
      ).trim();
      const targetPersonId = String(
        req.body?.targetPersonId || req.body?.offlineRelativeId || "",
      ).trim();
      const message = req.body?.message;

      if (!recipientId) {
        res.status(400).json({message: "Нужен recipientId"});
        return;
      }

      const request = await store.createRelationRequest({
        treeId: tree.id,
        senderId: req.auth.user.id,
        recipientId,
        senderToRecipient,
        targetPersonId: targetPersonId || null,
        message,
      });

      if (request === null) {
        res.status(404).json({message: "Семейное дерево не найдено"});
        return;
      }
      if (request === undefined) {
        res.status(404).json({message: "Отправитель или получатель не найден"});
        return;
      }
      if (request === false) {
        res.status(400).json({message: "Нельзя отправить запрос самому себе"});
        return;
      }
      if (request === "TARGET_PERSON_NOT_FOUND") {
        res.status(404).json({message: "Офлайн-профиль для приглашения не найден"});
        return;
      }
      if (request === "DUPLICATE") {
        res.status(409).json({message: "Похожий запрос уже ожидает ответа"});
        return;
      }

      await createAndDispatchNotification({
        userId: recipientId,
        type: "relation_request",
        title: "Новый запрос на родство",
        body: "Вам отправили запрос на подтверждение родственной связи",
        data: {
          requestId: request.id,
          treeId: request.treeId,
          senderId: request.senderId,
          relationType: request.senderToRecipient,
        },
      });

      res.status(201).json({request: mapRelationRequest(request)});
    },
  );

  app.post(
    "/v1/relation-requests/:requestId/respond",
    requireAuth,
    async (req, res) => {
      const responseStatus = String(req.body?.response || "").trim();
      if (!responseStatus) {
        res.status(400).json({message: "Нужен response"});
        return;
      }

      const request = await store.findRelationRequest(req.params.requestId);
      if (!request) {
        res.status(404).json({message: "Запрос не найден"});
        return;
      }

      if (request.recipientId !== req.auth.user.id) {
        res.status(403).json({message: "Нельзя отвечать на чужой запрос"});
        return;
      }

      if (request.status !== "pending") {
        res.status(409).json({message: "Этот запрос уже обработан"});
        return;
      }

      if (!["accepted", "rejected", "canceled"].includes(responseStatus)) {
        res.status(400).json({message: "Недопустимый статус ответа"});
        return;
      }

      let recipientPerson = null;
      let senderPerson = null;
      let relation = null;

      if (responseStatus === "accepted") {
        if (request.targetPersonId) {
          const linkedPerson = await store.linkPersonToUser({
            treeId: request.treeId,
            personId: request.targetPersonId,
            userId: req.auth.user.id,
          });

          if (linkedPerson === null || linkedPerson === undefined) {
            res.status(404).json({message: "Профиль для привязки не найден"});
            return;
          }
          if (linkedPerson === false) {
            res.status(409).json({
              message: "Этот профиль уже связан с другим пользователем",
            });
            return;
          }

          recipientPerson = linkedPerson;
        } else {
          recipientPerson = await store.ensureUserPersonInTree({
            treeId: request.treeId,
            userId: req.auth.user.id,
          });
        }

        senderPerson = await store.ensureUserPersonInTree({
          treeId: request.treeId,
          userId: request.senderId,
          creatorId: request.senderId,
        });

        if (!recipientPerson || !senderPerson) {
          res.status(404).json({
            message: "Не удалось подготовить участников родственной связи",
          });
          return;
        }

        relation = await store.upsertRelation({
          treeId: request.treeId,
          person1Id: senderPerson.id,
          person2Id: recipientPerson.id,
          relation1to2: request.senderToRecipient,
          isConfirmed: true,
          createdBy: request.senderId,
        });
      }

      const updatedRequest = await store.respondToRelationRequest(
        request.id,
        responseStatus,
      );

      await createAndDispatchNotification({
        userId: request.senderId,
        type:
          responseStatus === "accepted"
            ? "relation_request_accepted"
            : "relation_request_updated",
        title:
          responseStatus === "accepted"
            ? "Запрос на родство принят"
            : "Запрос на родство обновлён",
        body:
          responseStatus === "accepted"
            ? "Ваш запрос на родство был принят"
            : "Получатель обработал ваш запрос на родство",
        data: {
          requestId: request.id,
          treeId: request.treeId,
          recipientId: request.recipientId,
          status: responseStatus,
        },
      });

      res.json({
        request: mapRelationRequest(updatedRequest),
        person: recipientPerson ? mapPerson(recipientPerson) : null,
        relation: relation ? mapRelation(relation) : null,
      });
    },
  );

  app.get("/v1/chats", requireAuth, async (req, res) => {
    const limit = Math.min(
      Math.max(1, Number.parseInt(String(req.query.limit || "100"), 10) || 100),
      200,
    );
    const previews = await store.listChatPreviews(req.auth.user.id);
    res.json({
      chats: previews.slice(0, limit).map(mapChatPreview),
    });
  });

  app.get("/v1/chats/unread-count", requireAuth, async (req, res) => {
    const previews = await store.listChatPreviews(req.auth.user.id);
    const totalUnread = previews.reduce((sum, preview) => {
      return sum + Number(preview.unreadCount || 0);
    }, 0);

    res.json({
      totalUnread,
    });
  });

  app.get("/v1/blocks", requireAuth, async (req, res) => {
    const blocks = await store.listUserBlocks(req.auth.user.id);
    const mappedBlocks = [];
    for (const block of blocks) {
      const blockedUser = await store.findUserById(block.blockedUserId);
      mappedBlocks.push(mapBlock(block, blockedUser));
    }

    res.json({
      blocks: mappedBlocks,
    });
  });

  app.post("/v1/blocks", requireAuth, async (req, res) => {
    const blockedUserId = String(req.body?.userId || "").trim();
    if (!blockedUserId) {
      res.status(400).json({message: "Нужен userId"}); 
      return;
    }

    const block = await store.createUserBlock({
      blockerId: req.auth.user.id,
      blockedUserId,
      reason: req.body?.reason,
      metadata: req.body?.metadata,
    });
    if (block === false) {
      res.status(400).json({message: "Нельзя заблокировать этого пользователя"});
      return;
    }
    if (block === null) {
      res.status(404).json({message: "Пользователь для блокировки не найден"});
      return;
    }

    const blockedUser = await store.findUserById(block.blockedUserId);
    res.status(201).json({
      block: mapBlock(block, blockedUser),
    });
  });

  app.delete("/v1/blocks/:blockId", requireAuth, async (req, res) => {
    const removed = await store.deleteUserBlock({
      blockId: req.params.blockId,
      blockerId: req.auth.user.id,
    });
    if (!removed) {
      res.status(404).json({message: "Блокировка не найдена"});
      return;
    }

    res.status(204).end();
  });

  app.post("/v1/reports", requireAuth, async (req, res) => {
    const targetType = String(req.body?.targetType || "").trim();
    const targetId = String(req.body?.targetId || "").trim();
    if (!targetType || !targetId) {
      res.status(400).json({message: "Нужны targetType и targetId"});
      return;
    }

    const report = await store.createReport({
      reporterId: req.auth.user.id,
      targetType,
      targetId,
      reason: req.body?.reason,
      details: req.body?.details,
      metadata: req.body?.metadata,
    });
    if (report === false) {
      res.status(400).json({message: "Некорректные параметры жалобы"});
      return;
    }
    if (report === null) {
      res.status(404).json({message: "Отправитель жалобы не найден"});
      return;
    }

    res.status(201).json({
      report: mapReport(report, req.auth.user),
    });
  });

  app.get("/v1/admin/runtime", requireAuth, async (req, res) => {
    if (!requireAdmin(req, res)) {
      return;
    }

    res.json(
      buildStatusPayload("ok", {
        requestId: req.requestId,
      }),
    );
  });

  app.get("/v1/admin/reports", requireAuth, async (req, res) => {
    if (!requireAdmin(req, res)) {
      return;
    }

    const status = String(req.query?.status || "").trim() || null;
    const reports = await store.listReports({status});
    const mappedReports = [];
    for (const report of reports) {
      const reporter = await store.findUserById(report.reporterId);
      mappedReports.push(mapReport(report, reporter));
    }

    res.json({
      reports: mappedReports,
    });
  });

  app.post("/v1/admin/reports/:reportId/resolve", requireAuth, async (req, res) => {
    if (!requireAdmin(req, res)) {
      return;
    }

    const status = String(req.body?.status || "resolved").trim() || "resolved";
    const report = await store.resolveReport({
      reportId: req.params.reportId,
      resolvedBy: req.auth.user.id,
      status,
      resolutionNote: req.body?.resolutionNote,
    });
    if (!report) {
      res.status(404).json({message: "Жалоба не найдена"});
      return;
    }

    const reporter = await store.findUserById(report.reporterId);
    res.json({
      report: mapReport(report, reporter),
    });
  });

  app.post("/v1/chats/direct", requireAuth, async (req, res) => {
    const otherUserId = String(req.body?.otherUserId || "").trim();
    if (!otherUserId) {
      res.status(400).json({message: "Нужен otherUserId"});
      return;
    }

    const otherUser = await store.findUserById(otherUserId);
    if (!otherUser) {
      res.status(404).json({message: "Собеседник не найден"});
      return;
    }

    const isBlocked = await store.isUserBlockedBetween(
      req.auth.user.id,
      otherUserId,
    );
    if (isBlocked) {
      res.status(403).json({
        message: "Личный чат недоступен: один из пользователей заблокирован",
      });
      return;
    }

    const chat = await store.ensureDirectChat(req.auth.user.id, otherUserId);
    if (chat === null) {
      res.status(400).json({message: "Не удалось создать личный чат"});
      return;
    }
    if (chat === undefined) {
      res.status(404).json({message: "Один из участников не найден"});
      return;
    }

    res.json({
      chatId: chat.id,
      chat: mapChatRecord(chat),
    });
  });

  app.post("/v1/chats/groups", requireAuth, async (req, res) => {
    const participantIds = Array.isArray(req.body?.participantIds)
      ? req.body.participantIds
      : [];
    const title = req.body?.title;
    const treeId = req.body?.treeId;

    const chat = await store.createGroupChat({
      title,
      participantIds,
      createdBy: req.auth.user.id,
      treeId,
    });
    if (chat === false) {
      res.status(400).json({
        message: "Для группового чата нужно выбрать минимум двух участников",
      });
      return;
    }
    if (chat === null) {
      res.status(404).json({message: "Один или несколько участников не найдены"});
      return;
    }

    const mappedChat = mapChatRecord(chat);
    for (const participantId of chat.participantIds) {
      realtimeHub?.publishToUser(participantId, {
        type: "chat.created",
        chatId: chat.id,
        chat: mappedChat,
      });
    }

    res.status(201).json({
      chatId: chat.id,
      chat: mappedChat,
    });
  });

  app.post("/v1/chats/branches", requireAuth, async (req, res) => {
    const treeId = String(req.body?.treeId || "").trim();
    const branchRootPersonIds = Array.isArray(req.body?.branchRootPersonIds)
      ? req.body.branchRootPersonIds
      : [];
    const title = req.body?.title;

    if (!treeId) {
      res.status(400).json({message: "Нужен treeId"});
      return;
    }

    const tree = await requireTreeAccess(req, res, treeId);
    if (!tree) {
      return;
    }

    const chat = await store.createBranchChat({
      treeId: tree.id,
      branchRootPersonIds,
      createdBy: req.auth.user.id,
      title,
    });
    if (chat === false) {
      res.status(400).json({
        message: "В этой ветке пока нет других участников с аккаунтами",
      });
      return;
    }
    if (chat === null) {
      res.status(404).json({message: "Ветка не найдена в выбранном дереве"});
      return;
    }

    const mappedChat = mapChatRecord(chat);
    for (const participantId of chat.participantIds) {
      realtimeHub?.publishToUser(participantId, {
        type: "chat.created",
        chatId: chat.id,
        chat: mappedChat,
      });
    }

    res.status(201).json({
      chatId: chat.id,
      chat: mappedChat,
    });
  });

  app.get("/v1/chats/:chatId", requireAuth, async (req, res) => {
    const chat = await requireChatAccess(req, res, req.params.chatId);
    if (!chat) {
      return;
    }

    const resolvedChatId = chat.id;
    const details = await store.getChatDetails(resolvedChatId);
    if (!details) {
      res.status(404).json({message: "Чат не найден"});
      return;
    }

    res.json({
      chat: mapChatRecord(details.chat),
      participants: details.participants.map(mapChatParticipant),
      branchRoots: details.branchRoots.map(mapChatBranchRoot),
    });
  });

  app.patch("/v1/chats/:chatId", requireAuth, async (req, res) => {
    const chat = await requireChatAccess(req, res, req.params.chatId);
    if (!chat) {
      return;
    }
    const resolvedChatId = chat.id;

    const updatedChat = await store.updateGroupChat(resolvedChatId, {
      title: req.body?.title,
    });
    if (updatedChat === false) {
      res.status(400).json({message: "Менять можно только обычный групповой чат"});
      return;
    }
    if (updatedChat === undefined) {
      res.status(400).json({message: "Нужно указать название чата"});
      return;
    }
    if (!updatedChat) {
      res.status(404).json({message: "Чат не найден"});
      return;
    }

    const details = await store.getChatDetails(updatedChat.id);
    if (!details) {
      res.status(404).json({message: "Чат не найден"});
      return;
    }
    const mappedChat = mapChatRecord(details.chat);
    for (const participantId of details.chat.participantIds || []) {
      realtimeHub?.publishToUser(participantId, {
        type: "chat.updated",
        chatId: details.chat.id,
        chat: mappedChat,
      });
    }

    res.json({
      chat: mappedChat,
      participants: details.participants.map(mapChatParticipant),
      branchRoots: details.branchRoots.map(mapChatBranchRoot),
    });
  });

  app.post("/v1/chats/:chatId/participants", requireAuth, async (req, res) => {
    const chat = await requireChatAccess(req, res, req.params.chatId);
    if (!chat) {
      return;
    }
    const resolvedChatId = chat.id;

    const participantIds = Array.isArray(req.body?.participantIds)
      ? req.body.participantIds
      : [];
    const updatedChat = await store.addGroupParticipants(
      resolvedChatId,
      participantIds,
    );
    if (updatedChat === false) {
      res.status(400).json({message: "Менять можно только обычный групповой чат"});
      return;
    }
    if (updatedChat === undefined) {
      res.status(400).json({message: "Нужны новые участники"});
      return;
    }
    if (!updatedChat) {
      res.status(404).json({message: "Один или несколько участников не найдены"});
      return;
    }

    const details = await store.getChatDetails(updatedChat.id);
    if (!details) {
      res.status(404).json({message: "Чат не найден"});
      return;
    }
    const mappedChat = mapChatRecord(details.chat);
    for (const participantId of details.chat.participantIds || []) {
      realtimeHub?.publishToUser(participantId, {
        type: "chat.updated",
        chatId: details.chat.id,
        chat: mappedChat,
      });
    }

    res.json({
      chat: mappedChat,
      participants: details.participants.map(mapChatParticipant),
      branchRoots: details.branchRoots.map(mapChatBranchRoot),
    });
  });

  app.delete(
    "/v1/chats/:chatId/participants/:participantId",
    requireAuth,
    async (req, res) => {
      const chat = await requireChatAccess(req, res, req.params.chatId);
      if (!chat) {
        return;
      }
      const resolvedChatId = chat.id;

      const updatedChat = await store.removeGroupParticipant(
        resolvedChatId,
        req.params.participantId,
      );
      if (updatedChat === false) {
        res.status(400).json({message: "Менять можно только обычный групповой чат"});
        return;
      }
      if (updatedChat === undefined) {
        res.status(400).json({
          message: "Нельзя удалить этого участника из группового чата",
        });
        return;
      }
      if (!updatedChat) {
        res.status(404).json({message: "Чат не найден"});
        return;
      }

      const details = await store.getChatDetails(updatedChat.id);
      if (!details) {
        res.status(404).json({message: "Чат не найден"});
        return;
      }
      const mappedChat = mapChatRecord(details.chat);
      const affectedParticipantIds = new Set([
        ...((chat.participantIds || []).map((entry) => String(entry || "").trim())),
        ...(details.chat.participantIds || []).map((entry) => String(entry || "").trim()),
      ]);
      for (const participantId of affectedParticipantIds) {
        if (!participantId) {
          continue;
        }
        realtimeHub?.publishToUser(participantId, {
          type: "chat.updated",
          chatId: details.chat.id,
          chat: mappedChat,
        });
      }

      res.json({
        chat: mappedChat,
        participants: details.participants.map(mapChatParticipant),
        branchRoots: details.branchRoots.map(mapChatBranchRoot),
      });
    },
  );

  app.get("/v1/chats/:chatId/messages", requireAuth, async (req, res) => {
    const chat = await requireChatAccess(req, res, req.params.chatId);
    if (!chat) {
      return;
    }
    const resolvedChatId = chat.id;

    const messages = await store.listChatMessages(resolvedChatId);
    res.json({
      chat: mapChatRecord(chat),
      messages: messages.map(mapChatMessage),
    });
  });

  app.post("/v1/chats/:chatId/messages", requireAuth, async (req, res) => {
    const chat = await requireChatAccess(req, res, req.params.chatId);
    if (!chat) {
      return;
    }
    const resolvedChatId = chat.id;

    if (chat.type === "direct") {
      const otherParticipantId = (Array.isArray(chat.participantIds)
        ? chat.participantIds
        : []
      ).find((participantId) => participantId !== req.auth.user.id);
      if (otherParticipantId) {
        const isBlocked = await store.isUserBlockedBetween(
          req.auth.user.id,
          otherParticipantId,
        );
        if (isBlocked) {
          res.status(403).json({
            message:
              "Отправка сообщений недоступна: один из пользователей заблокирован",
          });
          return;
        }
      }
    }

    const text = String(req.body?.text || "").trim();
    const attachments = Array.isArray(req.body?.attachments)
      ? req.body.attachments
      : [];
    const mediaUrls = Array.isArray(req.body?.mediaUrls) ? req.body.mediaUrls : [];
    const imageUrl = req.body?.imageUrl;
    const clientMessageId = String(req.body?.clientMessageId || "").trim() || null;
    const expiresInSeconds = Number(req.body?.expiresInSeconds || 0);
    const expiresAt = expiresInSeconds > 0
      ? new Date(Date.now() + expiresInSeconds * 1000).toISOString()
      : req.body?.expiresAt;
    if (
      !text &&
      attachments.length === 0 &&
      mediaUrls.length === 0 &&
      !String(imageUrl || "").trim()
    ) {
      res.status(400).json({message: "Нужен text или вложение"});
      return;
    }

    const message = await store.addChatMessage({
      chatId: resolvedChatId,
      senderId: req.auth.user.id,
      text,
      attachments,
      mediaUrls,
      imageUrl,
      clientMessageId,
      expiresAt,
      replyTo: req.body?.replyTo,
    });

    if (message === false) {
      res.status(400).json({message: "Сообщение не должно быть пустым"});
      return;
    }
    if (!message) {
      res.status(400).json({message: "Не удалось отправить сообщение"});
      return;
    }

    const mappedMessage = mapChatMessage(message);
    const isDeduplicated = message._deduplicated === true;
    const recipientIds = (chat.participantIds || []).filter(
      (participantId) => participantId !== req.auth.user.id,
    );
    if (!isDeduplicated) {
      for (const recipientId of recipientIds) {
        const firstAttachment = Array.isArray(mappedMessage.attachments)
          ? mappedMessage.attachments.find((attachment) =>
              String(attachment?.url || "").trim(),
            )
          : null;
        await createAndDispatchNotification({
          userId: recipientId,
          type: "chat_message",
          title:
            chat.type === "group" || chat.type === "branch"
              ? chat.title || message.senderName || "Групповой чат"
              : message.senderName || "Новое сообщение",
          body:
            message.text ||
            (firstAttachment?.presentation === "video_note"
              ? "Видеосообщение"
              : firstAttachment?.presentation === "voice_note"
                ? "Голосовое"
                : firstAttachment?.type === "video"
              ? "Видео"
              : firstAttachment?.type === "audio"
                ? "Голосовое"
                : firstAttachment?.type === "file"
                  ? "Файл"
                  : (Array.isArray(message.mediaUrls) && message.mediaUrls.length > 0)
                    ? "Фото"
                    : "Новое сообщение"),
          data: {
            chatId: message.chatId,
            chatType: chat.type || "direct",
            chatTitle: chat.title || null,
            senderId: message.senderId,
            senderName: message.senderName,
            messageId: message.id,
            attachments: mappedMessage.attachments,
          },
        });
      }

      for (const participantId of chat.participantIds || []) {
        realtimeHub?.publishToUser(participantId, {
          type: "chat.message.created",
          chatId: message.chatId,
          chat: mapChatRecord(chat),
          message: mappedMessage,
        });
      }
    }

    res.status(isDeduplicated ? 200 : 201).json({message: mappedMessage});
  });

  app.patch("/v1/chats/:chatId/messages/:messageId", requireAuth, async (req, res) => {
    const chat = await requireChatAccess(req, res, req.params.chatId);
    if (!chat) {
      return;
    }
    const resolvedChatId = chat.id;

    const message = await store.updateChatMessage({
      chatId: resolvedChatId,
      messageId: req.params.messageId,
      userId: req.auth.user.id,
      text: req.body?.text,
    });

    if (message === false) {
      res.status(404).json({message: "Чат не найден"});
      return;
    }
    if (message === null) {
      res.status(404).json({message: "Сообщение не найдено"});
      return;
    }
    if (message === undefined) {
      res.status(403).json({message: "Можно редактировать только свои сообщения"});
      return;
    }
    if (message === "EMPTY_MESSAGE") {
      res.status(400).json({message: "Сообщение не должно быть пустым"});
      return;
    }

    const mappedMessage = mapChatMessage(message);
    for (const participantId of chat.participantIds || []) {
      realtimeHub?.publishToUser(participantId, {
        type: "chat.message.updated",
        chatId: message.chatId,
        chat: mapChatRecord(chat),
        message: mappedMessage,
      });
    }

    res.json({message: mappedMessage});
  });

  app.delete("/v1/chats/:chatId/messages/:messageId", requireAuth, async (req, res) => {
    const chat = await requireChatAccess(req, res, req.params.chatId);
    if (!chat) {
      return;
    }
    const resolvedChatId = chat.id;

    const message = await store.deleteChatMessage({
      chatId: resolvedChatId,
      messageId: req.params.messageId,
      userId: req.auth.user.id,
    });

    if (message === false) {
      res.status(404).json({message: "Чат не найден"});
      return;
    }
    if (message === null) {
      res.status(404).json({message: "Сообщение не найдено"});
      return;
    }
    if (message === undefined) {
      res.status(403).json({message: "Можно удалять только свои сообщения"});
      return;
    }

    for (const participantId of chat.participantIds || []) {
      realtimeHub?.publishToUser(participantId, {
        type: "chat.message.deleted",
        chatId: message.chatId,
        chat: mapChatRecord(chat),
        messageId: message.id,
      });
    }

    res.json({ok: true, messageId: message.id});
  });

  app.post("/v1/chats/:chatId/read", requireAuth, async (req, res) => {
    const chat = await requireChatAccess(req, res, req.params.chatId);
    if (!chat) {
      return;
    }
    const resolvedChatId = chat.id;

    await store.markChatAsRead(resolvedChatId, req.auth.user.id);
    for (const participantId of chat.participantIds || []) {
      realtimeHub?.publishToUser(participantId, {
        type: "chat.read.updated",
        chatId: resolvedChatId,
        chat: mapChatRecord(chat),
        userId: req.auth.user.id,
      });
    }
    res.json({ok: true});
  });

  app.post("/v1/calls", requireAuth, async (req, res) => {
    if (!resolvedLiveKitService.isConfigured) {
      res.status(503).json({message: "Звонки пока не настроены на сервере"});
      return;
    }

    const requestedChatId = String(req.body?.chatId || "").trim();
    const mediaMode = String(req.body?.mediaMode || "audio").trim().toLowerCase() === "video"
      ? "video"
      : "audio";
    if (!requestedChatId) {
      res.status(400).json({message: "Нужен chatId"});
      return;
    }

    const chat = await requireChatAccess(req, res, requestedChatId);
    if (!chat) {
      return;
    }
    const chatId = chat.id;
    const participantIds = Array.isArray(chat.participantIds)
      ? chat.participantIds
      : [];
    if (chat.type !== "direct" || participantIds.length !== 2) {
      res.status(400).json({message: "Пока поддерживаются только личные звонки"});
      return;
    }

    const recipientId = participantIds.find((entry) => entry !== req.auth.user.id);
    if (!recipientId) {
      res.status(400).json({message: "Не удалось определить собеседника"});
      return;
    }

    await reconcileUserBusyCall(req.auth.user.id);
    await reconcileUserBusyCall(recipientId);

    const call = await store.createCallInvite({
      chatId,
      initiatorId: req.auth.user.id,
      recipientId,
      mediaMode,
    });
    if (call === null) {
      res.status(404).json({message: "Чат не найден"});
      return;
    }
    if (call === false) {
      res.status(400).json({message: "Пока поддерживаются только личные звонки"});
      return;
    }
    if (call === "BUSY") {
      logCallEvent(
        "invite.busy",
        {
          id: null,
          chatId,
          mediaMode,
          state: "busy",
          createdAt: null,
          acceptedAt: null,
          endedAt: null,
          endedReason: "busy",
          metrics: null,
        },
        {
          initiatorId: req.auth.user.id,
          recipientId,
        },
      );
      res.status(409).json({message: "Пользователь уже участвует в другом звонке"});
      return;
    }

    const callerName =
      req.auth.user.profile?.displayName ||
      req.auth.user.displayName ||
      "Участник";
    await createAndDispatchNotification({
      userId: recipientId,
      type: "call_invite",
      title: callerName,
      body: mediaMode === "video" ? "Видеозвонок" : "Аудиозвонок",
      data: {
        chatId,
        callId: call.id,
        mediaMode,
      },
    });

    for (const participantId of call.participantIds || []) {
      realtimeHub?.publishToUser(participantId, {
        type: "call.invite.created",
        call: mapCallRecord(call, {viewerUserId: participantId}),
      });
    }

    logCallEvent("invite.created", call, {
      initiatorId: call.initiatorId,
      recipientId: call.recipientId,
    });
    scheduleCallInviteTimeout(call);

    res.status(201).json({
      call: mapCallRecord(call, {viewerUserId: req.auth.user.id}),
    });
  });

  app.get("/v1/calls/active", requireAuth, async (req, res) => {
    const chatId = String(req.query?.chatId || "").trim();
    const activeCall = await findFreshActiveCall({
      userId: req.auth.user.id,
      chatId: chatId || null,
    });
    res.json({
      call: activeCall
        ? mapCallRecord(activeCall, {viewerUserId: req.auth.user.id})
        : null,
    });
  });

  app.get("/v1/calls/:callId", requireAuth, async (req, res) => {
    const call = await requireCallAccess(req, res, req.params.callId);
    if (!call) {
      return;
    }

    res.json({
      call: mapCallRecord(call, {viewerUserId: req.auth.user.id}),
    });
  });

  app.post("/v1/calls/:callId/accept", requireAuth, async (req, res) => {
    if (!resolvedLiveKitService.isConfigured) {
      res.status(503).json({message: "Звонки пока не настроены на сервере"});
      return;
    }

    const call = await requireCallAccess(req, res, req.params.callId);
    if (!call) {
      return;
    }
    if (call.recipientId !== req.auth.user.id) {
      res.status(403).json({message: "Только получатель может принять звонок"});
      return;
    }
    if (call.state !== "ringing") {
      res.status(409).json({message: "Звонок уже недоступен для принятия"});
      return;
    }

    const initiator = await store.findUserById(call.initiatorId);
    const recipient = await store.findUserById(call.recipientId);
    const roomName = call.roomName || `call_${call.id}`;
    try {
      await resolvedLiveKitService.ensureRoom(roomName);
      const sessionByUserId = {
        [call.initiatorId]: await resolvedLiveKitService.createSession({
          roomName,
          participantIdentity: call.initiatorId,
          participantName:
            initiator?.profile?.displayName ||
            initiator?.displayName ||
            "Участник",
          metadata: {
            callId: call.id,
            chatId: call.chatId,
            userId: call.initiatorId,
            mediaMode: call.mediaMode,
          },
        }),
        [call.recipientId]: await resolvedLiveKitService.createSession({
          roomName,
          participantIdentity: call.recipientId,
          participantName:
            recipient?.profile?.displayName ||
            recipient?.displayName ||
            "Участник",
          metadata: {
            callId: call.id,
            chatId: call.chatId,
            userId: call.recipientId,
            mediaMode: call.mediaMode,
          },
        }),
      };
      const acceptedCall = await store.acceptCall({
        callId: call.id,
        userId: req.auth.user.id,
        roomName,
        sessionByUserId,
      });
      if (!acceptedCall) {
        res.status(409).json({message: "Не удалось принять звонок"});
        return;
      }
      clearCallInviteTimeout(acceptedCall.id);

      publishCallState(acceptedCall);

      logCallEvent("accept.succeeded", acceptedCall, {
        viewerUserId: req.auth.user.id,
      });

      res.json({
        call: mapCallRecord(acceptedCall, {viewerUserId: req.auth.user.id}),
      });
    } catch (error) {
      const failedCall =
        typeof store.markCallRoomJoinFailure === "function"
          ? await store.markCallRoomJoinFailure({
              callId: call.id,
              reason: error?.message || "room_prepare_failed",
            })
          : call;
      logCallEvent("accept.failed", failedCall || call, {
        viewerUserId: req.auth.user.id,
        error: String(error?.message || error || "room_prepare_failed"),
      });
      res.status(502).json({message: "Не удалось подготовить комнату звонка"});
    }
  });

  app.post("/v1/calls/:callId/reject", requireAuth, async (req, res) => {
    const call = await requireCallAccess(req, res, req.params.callId);
    if (!call) {
      return;
    }
    const rejectedCall = await store.rejectCall({
      callId: call.id,
      userId: req.auth.user.id,
    });
    if (rejectedCall === null) {
      res.status(404).json({message: "Звонок не найден"});
      return;
    }
    if (rejectedCall === false) {
      res.status(403).json({message: "Только получатель может отклонить звонок"});
      return;
    }
    if (rejectedCall === undefined) {
      res.status(409).json({message: "Звонок уже неактуален"});
      return;
    }
    clearCallInviteTimeout(rejectedCall.id);
    publishCallState(rejectedCall);
    logCallEvent("reject.completed", rejectedCall, {
      viewerUserId: req.auth.user.id,
    });
    res.json({call: mapCallRecord(rejectedCall, {viewerUserId: req.auth.user.id})});
  });

  app.post("/v1/calls/:callId/cancel", requireAuth, async (req, res) => {
    const call = await requireCallAccess(req, res, req.params.callId);
    if (!call) {
      return;
    }
    const cancelledCall = await store.cancelCall({
      callId: call.id,
      userId: req.auth.user.id,
    });
    if (cancelledCall === null) {
      res.status(404).json({message: "Звонок не найден"});
      return;
    }
    if (cancelledCall === false) {
      res.status(403).json({message: "Только инициатор может отменить звонок"});
      return;
    }
    if (cancelledCall === undefined) {
      res.status(409).json({message: "Звонок уже неактуален"});
      return;
    }
    clearCallInviteTimeout(cancelledCall.id);
    publishCallState(cancelledCall);
    logCallEvent("cancel.completed", cancelledCall, {
      viewerUserId: req.auth.user.id,
    });
    res.json({call: mapCallRecord(cancelledCall, {viewerUserId: req.auth.user.id})});
  });

  app.post("/v1/calls/:callId/hangup", requireAuth, async (req, res) => {
    const call = await requireCallAccess(req, res, req.params.callId);
    if (!call) {
      return;
    }
    const endedCall = await store.hangupCall({
      callId: call.id,
      userId: req.auth.user.id,
    });
    if (endedCall === null) {
      res.status(404).json({message: "Звонок не найден"});
      return;
    }
    if (endedCall === false) {
      res.status(403).json({message: "Доступ к звонку запрещён"});
      return;
    }
    if (endedCall === undefined) {
      res.status(409).json({message: "Звонок уже завершён"});
      return;
    }
    clearCallInviteTimeout(endedCall.id);
    publishCallState(endedCall);
    logCallEvent("hangup.completed", endedCall, {
      viewerUserId: req.auth.user.id,
    });
    res.json({call: mapCallRecord(endedCall, {viewerUserId: req.auth.user.id})});
  });

  app.get("/v1/users/search", requireAuth, async (req, res) => {
    const query = String(req.query.query || "");
    const limit = Number(req.query.limit || 10);
    const users = await store.searchUsers({query, limit});

    res.json({
      users: users.map((user) => sanitizeUserProfilePreview(user)),
    });
  });

  app.get("/v1/users/search/by-field", requireAuth, async (req, res) => {
    const field = String(req.query.field || "");
    const value = String(req.query.value || "");
    const limit = Number(req.query.limit || 10);

    if (!field || !value) {
      res.status(400).json({message: "Нужны field и value"});
      return;
    }

    if (field === "phoneNumber") {
      res.status(410).json({
        message:
          "Поиск по номеру отключён. Ищите родственников по username, email, invite link или claim link.",
        nextAction: "search_by_username_or_invite",
      });
      return;
    }

    const users = await store.searchUsersByField({field, value, limit});
    res.json({
      users: users.map((user) => sanitizeUserProfilePreview(user)),
    });
  });

  app.get("/v1/users/:userId/profile", requireAuth, async (req, res) => {
    const user = await store.findUserById(req.params.userId);
    if (!user) {
      res.status(404).json({message: "Пользователь не найден"});
      return;
    }

    const viewerContext = await buildProfileViewerContext(
      req.auth.user.id,
      user.id,
    );
    const isSelfProfile = req.auth.user.id === user.id;
    res.json({
      profile: sanitizeProfile(user.profile, viewerContext),
      profileStatus: isSelfProfile ? computeProfileStatus(user.profile) : null,
    });
  });

  app.patch("/v1/users/:userId/profile", requireAuth, async (req, res) => {
    if (req.params.userId !== req.auth.user.id) {
      res.status(403).json({message: "Изменение чужого профиля запрещено"});
      return;
    }

    const updatedUser = await store.updateProfile(req.auth.user.id, (profile) => ({
      ...profile,
      ...req.body,
    }));

    res.json({
      profile: sanitizeProfile(updatedUser.profile),
      profileStatus: computeProfileStatus(updatedUser.profile),
    });
  });

  app.get("/v1/notifications", requireAuth, async (req, res) => {
    const status = req.query.status ? String(req.query.status) : null;
    const limit = Math.min(
      Math.max(1, Number.parseInt(String(req.query.limit || "50"), 10) || 50),
      200,
    );
    const notifications = await store.listNotifications(req.auth.user.id, {
      status,
      limit,
    });

    res.json({
      notifications: notifications.map(mapNotification),
    });
  });

  app.get("/v1/notifications/unread-count", requireAuth, async (req, res) => {
    const totalUnread = await store.countUnreadNotifications(req.auth.user.id);
    res.json({totalUnread});
  });

  app.post(
    "/v1/notifications/:notificationId/read",
    requireAuth,
    async (req, res) => {
      const notification = await store.markNotificationRead(
        req.params.notificationId,
        req.auth.user.id,
      );
      if (!notification) {
        res.status(404).json({message: "Уведомление не найдено"});
        return;
      }

      res.json({
        notification: mapNotification(notification),
      });
    },
  );

  app.get("/v1/push/devices", requireAuth, async (req, res) => {
    const devices = await store.listPushDevices(req.auth.user.id);
    res.json({
      devices: devices.map(mapPushDevice),
    });
  });

  app.get("/v1/push/web/config", requireAuth, async (req, res) => {
    res.json({
      enabled: Boolean(config.webPushEnabled),
      publicKey: config.webPushEnabled ? config.webPushPublicKey : null,
    });
  });

  app.post("/v1/push/devices", requireAuth, async (req, res) => {
    const provider = String(req.body?.provider || "").trim();
    const token = String(req.body?.token || "").trim();
    const platform = String(req.body?.platform || "unknown").trim();

    if (!provider || !token) {
      res.status(400).json({message: "Нужны provider и token"});
      return;
    }

    const device = await store.registerPushDevice({
      userId: req.auth.user.id,
      provider,
      token,
      platform,
    });

    if (device === null) {
      res.status(404).json({message: "Пользователь не найден"});
      return;
    }
    if (device === false) {
      res.status(400).json({message: "Недопустимые provider или token"});
      return;
    }

    res.status(201).json({
      device: mapPushDevice(device),
    });
  });

  app.delete("/v1/push/devices/:deviceId", requireAuth, async (req, res) => {
    const deleted = await store.deletePushDevice(
      req.params.deviceId,
      req.auth.user.id,
    );
    if (!deleted) {
      res.status(404).json({message: "Устройство не найдено"});
      return;
    }

    res.status(204).send();
  });

  app.get("/v1/push/deliveries", requireAuth, async (req, res) => {
    const limit = Number(req.query.limit || 50);
    const deliveries = await store.listPushDeliveries(req.auth.user.id, {
      limit,
    });
    res.json({
      deliveries: deliveries.map(mapPushDelivery),
    });
  });

  app.post("/v1/invitations/pending/process", requireAuth, async (req, res) => {
    const treeId = String(req.body?.treeId || "").trim();
    const personId = String(req.body?.personId || "").trim();

    if (!treeId || !personId) {
      res.status(400).json({message: "Нужны treeId и personId"});
      return;
    }

    const linkedPerson = await store.linkPersonToUser({
      treeId,
      personId,
      userId: req.auth.user.id,
    });

    if (linkedPerson === null) {
      res.status(404).json({message: "Семейное дерево или пользователь не найдены"});
      return;
    }
    if (linkedPerson === undefined) {
      res.status(404).json({message: "Профиль приглашения не найден"});
      return;
    }
    if (linkedPerson === false) {
      res.status(409).json({
        message: "Этот профиль уже связан с другим пользователем",
      });
      return;
    }

    const tree = await store.findTree(treeId);
    res.json({
      ok: true,
      tree: tree ? mapTree(tree) : null,
      person: mapPerson(linkedPerson),
    });
  });

  app.use((req, res) => {
    res.status(404).json({
      message: "Route not found",
      requestId: req.requestId,
    });
  });

  app.use((error, req, res, next) => {
    if (typeof runtimeInfo?.captureError === "function") {
      runtimeInfo.captureError("express", error, {
        requestId: req.requestId,
        method: req.method,
        path: req.originalUrl || req.path || "/",
      });
    }
    console.error(
      "[backend] unhandled-error",
      JSON.stringify({
        requestId: req.requestId,
        method: req.method,
        path: req.originalUrl || req.path || "/",
        name: error?.name || "Error",
        message: error?.message || String(error),
        stack: error?.stack || null,
      }),
    );

    if (res.headersSent) {
      next(error);
      return;
    }

    res.status(500).json({
      message: "Внутренняя ошибка backend",
      requestId: req.requestId,
    });
  });

  return app;
}

module.exports = {
  createApp,
};
