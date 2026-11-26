const path = require("node:path");
const crypto = require("node:crypto");
const {
  normalizeNullableString,
  normalizeOptionalString,
  nowIso,
} = require("./utils");

function createNotificationRecord({
  userId,
  type,
  title,
  body,
  data = {},
  silent = false,
}) {
  const timestamp = nowIso();
  return {
    id: crypto.randomUUID(),
    userId,
    type: String(type || "generic"),
    title: String(title || "").trim(),
    body: String(body || "").trim(),
    data: data && typeof data === "object" ? structuredClone(data) : {},
    // Phase 6.5+: silent notifications carry data-only signals
    // (e.g. `tree_mutated` для auto-refresh). Client filters эти
    // на foreground display path; push gateway propagates flag в
    // payload так что service worker / device handlers могут skip
    // banner. Default false — backwards-compat для all existing
    // dispatch callers.
    silent: silent === true,
    createdAt: timestamp,
    readAt: null,
  };
}

function createPushDeviceRecord({
  userId,
  provider,
  token,
  platform = "unknown",
  sessionPublicId = null,
  instanceId = null,
}) {
  const timestamp = nowIso();
  return {
    id: crypto.randomUUID(),
    userId,
    provider: String(provider || "unknown").trim(),
    token: String(token || "").trim(),
    platform: String(platform || "unknown").trim(),
    sessionPublicId: normalizeOptionalString(sessionPublicId, 32),
    instanceId: normalizeOptionalString(instanceId, 80),
    createdAt: timestamp,
    updatedAt: timestamp,
    lastSeenAt: timestamp,
  };
}

/// SPEED-7: вычислимый ключ коалесинга уведомления. Единая точка правды
/// для обоих сторов: FileStore схлопывает по нему в массиве, PostgresStore —
/// SELECT'ом по колонке coalesce_key (индекс user_id+coalesce_key), той же
/// функцией ключ заполняется при INSERT и в бут-миграции. Пустая строка =
/// тип без коалесинга. Сравнение полей — через строкование (id всегда
/// строки-uuid; прежние строгие === для них эквивалентны).
function encodeNotificationCursor(createdAt, id) {
  return Buffer.from(`${createdAt}|${id}`, "utf8").toString("base64url");
}

function decodeNotificationCursor(rawCursor) {
  const normalized = String(rawCursor || "").trim();
  if (!normalized) return null;
  try {
    const decoded = Buffer.from(normalized, "base64url").toString("utf8");
    const separatorIndex = decoded.lastIndexOf("|");
    if (separatorIndex <= 0) return null;
    return {
      createdAt: decoded.slice(0, separatorIndex),
      id: decoded.slice(separatorIndex + 1),
    };
  } catch (_) {
    return null;
  }
}

function computeNotificationCoalesceKey(notification) {
  const record = notification || {};
  const type = String(record.type || "").trim();
  const data = record.data && typeof record.data === "object" ? record.data : {};
  const part = (value) => String(value ?? "").trim();
  switch (type) {
    case "story_reaction":
      return `${type}|${part(data.storyId)}|${part(data.actorUserId)}`;
    case "post_reaction":
      return `${type}|${part(data.postId)}|${part(data.actorUserId)}`;
    case "comment_reaction":
      return `${type}|${part(data.commentId)}|${part(data.actorUserId)}`;
    case "comment_reply":
      return `${type}|${part(data.parentCommentId)}|${part(data.actorUserId)}`;
    case "merge_proposal":
    case "identity_claim":
      return `${type}|${part(data.proposalId)}|${part(data.claimId)}`;
    default:
      return "";
  }
}

/// SPEED-7: «план» коалесцирующего уведомления — guard'ы, ключ и оба
/// исхода (бамп существующей unread-записи / создание новой) описаны
/// ДАННЫМИ, чтобы массивная (FileStore) и табличная (PostgresStore)
/// реализации _applyNotificationCoalescePlan не дублировали тексты.
function buildStoryReactionNotificationPlan({
  storyId,
  storyAuthorId,
  actorUserId,
  actorName,
  emoji,
  storySnippet,
}) {
  if (
    !storyAuthorId ||
    !actorUserId ||
    String(storyAuthorId).trim() === String(actorUserId).trim()
  ) {
    return null;
  }
  return {
    userId: storyAuthorId,
    type: "story_reaction",
    keyData: {storyId, actorUserId},
    patchExisting(existing) {
      existing.data = {...existing.data, emoji};
      existing.body = `${actorName || "Кто-то"} отреагировал ${emoji}`;
    },
    buildRecord() {
      return createNotificationRecord({
        userId: storyAuthorId,
        type: "story_reaction",
        title: actorName
          ? `${actorName} отреагировал ${emoji}`
          : `Реакция ${emoji} на историю`,
        body: storySnippet || "",
        data: {storyId, actorUserId, emoji},
      });
    },
  };
}

function buildPostReactionNotificationPlan({
  postId,
  postAuthorId,
  actorUserId,
  actorName,
  emoji,
  postSnippet,
}) {
  if (
    !postAuthorId ||
    !actorUserId ||
    String(postAuthorId).trim() === String(actorUserId).trim()
  ) {
    return null;
  }
  return {
    userId: postAuthorId,
    type: "post_reaction",
    keyData: {postId, actorUserId},
    patchExisting(existing) {
      existing.data = {...existing.data, emoji};
      existing.body = `${actorName || "Кто-то"} отреагировал ${emoji}`;
    },
    buildRecord() {
      return createNotificationRecord({
        userId: postAuthorId,
        type: "post_reaction",
        title: actorName
          ? `${actorName} отреагировал ${emoji}`
          : `Новая реакция ${emoji}`,
        body: postSnippet || "",
        data: {postId, actorUserId, emoji},
      });
    },
  };
}

function buildCommentReactionNotificationPlan({
  postId,
  commentId,
  commentAuthorId,
  actorUserId,
  actorName,
  emoji,
  commentSnippet,
}) {
  if (
    !commentAuthorId ||
    !actorUserId ||
    String(commentAuthorId).trim() === String(actorUserId).trim()
  ) {
    return null;
  }
  return {
    userId: commentAuthorId,
    type: "comment_reaction",
    keyData: {commentId, actorUserId},
    patchExisting(existing) {
      existing.data = {...existing.data, emoji};
      existing.body = `${actorName || "Кто-то"} отреагировал ${emoji}`;
    },
    buildRecord() {
      return createNotificationRecord({
        userId: commentAuthorId,
        type: "comment_reaction",
        title: actorName
          ? `${actorName} отреагировал ${emoji}`
          : `Новая реакция ${emoji}`,
        body: commentSnippet || "",
        data: {postId, commentId, actorUserId, emoji},
      });
    },
  };
}

function buildCommentReplyNotificationPlan({
  postId,
  parentCommentId,
  parentCommentAuthorId,
  replyCommentId,
  actorUserId,
  actorName,
  replySnippet,
}) {
  if (
    !parentCommentAuthorId ||
    !actorUserId ||
    String(parentCommentAuthorId).trim() === String(actorUserId).trim()
  ) {
    return null;
  }
  const trimmedSnippet = String(replySnippet || "").trim();
  return {
    userId: parentCommentAuthorId,
    type: "comment_reply",
    keyData: {parentCommentId, actorUserId},
    patchExisting(existing) {
      existing.data = {...existing.data, replyCommentId};
      existing.body = trimmedSnippet || existing.body || "";
    },
    buildRecord() {
      return createNotificationRecord({
        userId: parentCommentAuthorId,
        type: "comment_reply",
        title: actorName
          ? `${actorName} ответил на ваш комментарий`
          : "Новый ответ на комментарий",
        body: trimmedSnippet,
        data: {postId, parentCommentId, replyCommentId, actorUserId},
      });
    },
  };
}

function createPushDeliveryRecord({
  notificationId,
  userId,
  deviceId,
  provider,
  status = "queued",
}) {
  const timestamp = nowIso();
  return {
    id: crypto.randomUUID(),
    notificationId,
    userId,
    deviceId,
    provider: String(provider || "unknown").trim(),
    status: String(status || "queued").trim(),
    createdAt: timestamp,
    updatedAt: timestamp,
    deliveredAt: null,
    lastError: null,
    responseCode: null,
  };
}

function createReportRecord({
  reporterId,
  targetType,
  targetId,
  reason,
  details = null,
  metadata = {},
}) {
  const timestamp = nowIso();
  return {
    id: crypto.randomUUID(),
    reporterId,
    targetType: String(targetType || "").trim(),
    targetId: String(targetId || "").trim(),
    reason: String(reason || "other").trim() || "other",
    details: normalizeNullableString(details),
    metadata: metadata && typeof metadata === "object" ? structuredClone(metadata) : {},
    status: "pending",
    resolutionNote: null,
    resolvedAt: null,
    resolvedBy: null,
    createdAt: timestamp,
    updatedAt: timestamp,
  };
}

function createBlockRecord({
  blockerId,
  blockedUserId,
  reason = null,
  metadata = {},
}) {
  const timestamp = nowIso();
  return {
    id: crypto.randomUUID(),
    blockerId,
    blockedUserId,
    reason: normalizeNullableString(reason),
    metadata: metadata && typeof metadata === "object" ? structuredClone(metadata) : {},
    createdAt: timestamp,
    updatedAt: timestamp,
  };
}

module.exports = {
  createNotificationRecord,
  createPushDeviceRecord,
  encodeNotificationCursor,
  decodeNotificationCursor,
  computeNotificationCoalesceKey,
  buildStoryReactionNotificationPlan,
  buildPostReactionNotificationPlan,
  buildCommentReactionNotificationPlan,
  buildCommentReplyNotificationPlan,
  createPushDeliveryRecord,
  createReportRecord,
  createBlockRecord,
};
