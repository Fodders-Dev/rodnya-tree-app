const {
  composeDisplayName,
  normalizePublicUrl,
  sanitizeProfile,
  sanitizeUserProfilePreview,
} = require("../profile-utils");

function truncateText(value, maxLength = 280) {
  if (value === null || value === undefined) {
    return null;
  }
  const rawText =
    typeof value === "string"
      ? value
      : typeof value === "number" || typeof value === "boolean"
        ? String(value)
        : "";
  if (!rawText) {
    return null;
  }
  const sampledText =
    rawText.length > maxLength * 4
      ? rawText.slice(0, maxLength * 4)
      : rawText;
  const text = sampledText.trim();
  if (!text) {
    return null;
  }
  if (text.length <= maxLength) {
    return text;
  }
  return `${text.slice(0, Math.max(0, maxLength - 1)).trimEnd()}…`;
}

function normalizeSmallPublicUrl(value) {
  if (value === null || value === undefined) {
    return null;
  }
  const rawValue = typeof value === "string" ? value : "";
  if (!rawValue || rawValue.length > 4096) {
    return null;
  }
  const normalizedValue = rawValue.trim();
  if (!normalizedValue || normalizedValue.length > 2048) {
    return null;
  }
  return normalizePublicUrl(normalizedValue);
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
    // Post / comment / story reaction notifications carry the
    // target id, the actor that reacted, and the emoji so the
    // client can deep-link to the right surface and render the
    // right glyph in the inbox.
    "postId",
    "commentId",
    "storyId",
    "actorUserId",
    "emoji",
    // Threaded comment replies carry the parent + reply ids so the
    // notifications screen can deep-link straight to the relevant
    // comment thread.
    "parentCommentId",
    "replyCommentId",
    // Post-creation fan-out (audience-mode): the author id powers
    // the avatar / display name on the notification card; the
    // branchIds tell the client which slice of the user's
    // audience the post was published into so the inbox can
    // render an «в Семья Кузнецовых» badge.
    "authorId",
    // Story requests, profile articles, kinship checks, semya & calls
    "personId",
    "articleBlockId",
    "kinshipCheckId",
    "initiatorUserId",
    "targetUserId",
    "semyaId",
    "inviterUserId",
    "acceptedByUserId",
    "role",
    "gatheringId",
    "pollId",
    "fromUserId",
    "kind",
    "blockId",
    "callState",
  ];

  // Array-valued data fields. Sanitized member-by-member as
  // strings; anything non-string in the array is dropped so a
  // forged client can't sneak object payloads through.
  const allowedStringArrayKeys = [
    "branchIds",
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
  for (const key of allowedStringArrayKeys) {
    if (!(key in data)) continue;
    const value = data[key];
    if (!Array.isArray(value)) continue;
    sanitized[key] = value
      .filter((entry) => typeof entry === "string")
      .map((entry) => truncateText(entry, 280) || "")
      .filter((entry) => entry.length > 0);
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
    // Phase 6.5+ silent flag — clients filter on display path.
    silent: notification.silent === true,
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
    sessionPublicId: device.sessionPublicId || null,
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


module.exports = {
  truncateText,
  normalizeSmallPublicUrl,
  sanitizeNotificationData,
  mapNotification,
  resolveUserDisplayName,
  mapBlock,
  mapReport,
  mapPushDevice,
  mapPushDelivery,
};
