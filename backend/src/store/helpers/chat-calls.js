const crypto = require("node:crypto");
const {
  normalizeMessageAttachments,
} = require("../../chat-utils");
const {
  normalizeNullableString,
  normalizeOptionalIsoTimestamp,
  normalizeOptionalString,
  normalizeParticipantIds,
  nowIso,
} = require("./utils");

function deriveSessionPublicId(token, instanceId = "") {
  const normalizedToken = String(token || "").trim();
  if (!normalizedToken) {
    return "";
  }
  const normalizedInstanceId = String(instanceId || "").trim();
  const hasher = crypto.createHash("sha256").update(normalizedToken);
  if (normalizedInstanceId) {
    hasher.update(":");
    hasher.update(normalizedInstanceId);
  }
  return hasher.digest("base64url").slice(0, 22);
}

function normalizeSessionDeviceContext(context = {}) {
  const source = context && typeof context === "object" ? context : {};
  return {
    instanceId: normalizeOptionalString(source.instanceId, 80),
    deviceName: normalizeOptionalString(source.deviceName, 80),
    platform: normalizeOptionalString(source.platform, 40),
    // Additive alongside platform/appVersion — old sessions/clients simply
    // lack it, callers already treat every field here as nullable.
    osVersion: normalizeOptionalString(source.osVersion, 40),
    appVersion: normalizeOptionalString(source.appVersion, 40),
  };
}

function buildCallParticipantIdentity(userId, sessionPublicId) {
  const normalizedUserId = String(userId || "").trim();
  const normalizedSessionId = String(sessionPublicId || "").trim();
  if (!normalizedUserId) {
    return "";
  }
  if (!normalizedSessionId) {
    return normalizedUserId;
  }
  return `${normalizedUserId}#${normalizedSessionId}`;
}

function normalizeChatMessageCall(value) {
  if (!value || typeof value !== "object") {
    return null;
  }
  const callId = String(value.callId || "").trim();
  if (!callId) {
    return null;
  }
  const allowedStates = new Set([
    "ringing",
    "active",
    "ended",
    "rejected",
    "cancelled",
    "missed",
    "failed",
  ]);
  const rawState = String(value.state || "").trim().toLowerCase();
  const state = allowedStates.has(rawState) ? rawState : "ended";
  const mediaModeRaw = String(value.mediaMode || "").trim().toLowerCase();
  const mediaMode = mediaModeRaw === "video" ? "video" : "audio";
  const durationCandidate = Number(value.durationMs);
  const durationMs = Number.isFinite(durationCandidate) && durationCandidate > 0
    ? Math.floor(durationCandidate)
    : null;
  const initiatorId = String(value.initiatorId || "").trim() || null;
  const direction = value.direction === "incoming" ? "incoming" : "outgoing";
  return {
    callId,
    state,
    mediaMode,
    durationMs,
    initiatorId,
    direction,
  };
}

function parseCallParticipantIdentity(identity) {
  const normalized = String(identity || "").trim();
  if (!normalized) {
    return {userId: "", sessionPublicId: ""};
  }
  const hashIndex = normalized.indexOf("#");
  if (hashIndex < 0) {
    return {userId: normalized, sessionPublicId: ""};
  }
  return {
    userId: normalized.slice(0, hashIndex),
    sessionPublicId: normalized.slice(hashIndex + 1),
  };
}

function collectMediaUrl(urlSet, value) {
  const normalizedValue = String(value || "").trim();
  if (normalizedValue) {
    urlSet.add(normalizedValue);
  }
}

function collectMessageMediaUrls(urlSet, message) {
  const attachments = normalizeMessageAttachments(message);
  for (const attachment of attachments) {
    collectMediaUrl(urlSet, attachment?.url);
    collectMediaUrl(urlSet, attachment?.thumbnailUrl);
  }

  if (Array.isArray(message?.mediaUrls)) {
    for (const mediaUrl of message.mediaUrls) {
      collectMediaUrl(urlSet, mediaUrl);
    }
  }

  collectMediaUrl(urlSet, message?.imageUrl);
}

function collectOwnedMediaUrlsForUser(db, userId) {
  const ownedMediaUrls = new Set();
  const user = db.users.find((entry) => entry.id === userId);
  collectMediaUrl(ownedMediaUrls, user?.profile?.photoUrl);

  for (const person of db.persons) {
    if (person.userId === userId) {
      collectMediaUrl(ownedMediaUrls, person.photoUrl);
      collectMediaUrl(ownedMediaUrls, person.primaryPhotoUrl);
      if (Array.isArray(person.photoGallery)) {
        for (const mediaEntry of person.photoGallery) {
          collectMediaUrl(ownedMediaUrls, mediaEntry?.url);
          collectMediaUrl(ownedMediaUrls, mediaEntry?.thumbnailUrl);
        }
      }
    }
  }

  for (const post of db.posts) {
    if (post.authorId !== userId) {
      continue;
    }
    collectMediaUrl(ownedMediaUrls, post.authorPhotoUrl);
    if (Array.isArray(post.imageUrls)) {
      for (const imageUrl of post.imageUrls) {
        collectMediaUrl(ownedMediaUrls, imageUrl);
      }
    }
  }

  for (const story of db.stories) {
    if (story.authorId !== userId) {
      continue;
    }
    collectMediaUrl(ownedMediaUrls, story.authorPhotoUrl);
    collectMediaUrl(ownedMediaUrls, story.mediaUrl);
    collectMediaUrl(ownedMediaUrls, story.thumbnailUrl);
  }

  for (const comment of db.comments) {
    if (comment.authorId === userId) {
      collectMediaUrl(ownedMediaUrls, comment.authorPhotoUrl);
    }
  }

  for (const message of db.messages) {
    if (message.senderId === userId) {
      collectMessageMediaUrls(ownedMediaUrls, message);
    }
  }

  return Array.from(ownedMediaUrls);
}

function createChatRecord({
  id = null,
  type = "direct",
  participantIds = [],
  title = null,
  photoUrl = null,
  createdBy = null,
  treeId = null,
  branchRootPersonIds = [],
  memberPrefs = {},
}) {
  const timestamp = nowIso();
  return {
    id: id || crypto.randomUUID(),
    type: String(type || "direct").trim() || "direct",
    participantIds: normalizeParticipantIds(participantIds),
    title: normalizeNullableString(title),
    photoUrl: normalizeNullableString(photoUrl),
    createdBy: normalizeNullableString(createdBy),
    treeId: normalizeNullableString(treeId),
    branchRootPersonIds: normalizeParticipantIds(branchRootPersonIds),
    memberPrefs:
      memberPrefs && typeof memberPrefs === "object"
        ? structuredClone(memberPrefs)
        : {},
    createdAt: timestamp,
    updatedAt: timestamp,
  };
}

function parseDirectParticipantsFromChatId(chatId) {
  const participants = String(chatId || "")
    .split("_")
    .map((value) => value.trim())
    .filter(Boolean);

  return participants.length === 2 ? normalizeParticipantIds(participants) : [];
}

function normalizeCallMediaMode(value) {
  return String(value || "").trim().toLowerCase() === "video"
    ? "video"
    : "audio";
}

function normalizeCallState(value) {
  const normalizedState = String(value || "").trim().toLowerCase();
  switch (normalizedState) {
    case "ringing":
    case "active":
    case "rejected":
    case "cancelled":
    case "ended":
    case "missed":
    case "failed":
      return normalizedState;
    default:
      return "ringing";
  }
}

function isCallTerminalState(state) {
  return (
    state === "rejected" ||
    state === "cancelled" ||
    state === "ended" ||
    state === "missed" ||
    state === "failed"
  );
}

function isCallBusyState(state) {
  return state === "ringing" || state === "active";
}

function normalizeCallSession(session) {
  if (!session || typeof session !== "object") {
    return null;
  }

  const roomName = String(session.roomName || "").trim();
  const url = String(session.url || "").trim();
  const token = String(session.token || "").trim();
  const participantIdentity = String(session.participantIdentity || "").trim();
  if (!roomName || !url || !token || !participantIdentity) {
    return null;
  }

  return {
    roomName,
    url,
    token,
    participantIdentity,
    participantName: normalizeNullableString(session.participantName),
    createdAt: normalizeOptionalIsoTimestamp(session.createdAt) || nowIso(),
  };
}

function normalizeCallSessionMap(value) {
  if (!value || typeof value !== "object") {
    return {};
  }

  return Object.entries(value).reduce((accumulator, [userId, session]) => {
    const normalizedUserId = String(userId || "").trim();
    const normalizedSession = normalizeCallSession(session);
    if (normalizedUserId && normalizedSession) {
      accumulator[normalizedUserId] = normalizedSession;
    }
    return accumulator;
  }, {});
}

// Group late-join: who has joined the call and on which device session, as
// {userId -> sessionPublicId}. Replaces the scalar acceptedBy* (which only
// ever tracked the FIRST accepter); the scalars are kept filled by the first
// joiner for back-compat with in-flight records and old clients.
function normalizeJoinedSessionMap(value) {
  if (!value || typeof value !== "object") {
    return {};
  }

  return Object.entries(value).reduce((accumulator, [userId, sessionId]) => {
    const normalizedUserId = String(userId || "").trim();
    const normalizedSessionId = normalizeNullableString(sessionId);
    if (normalizedUserId && normalizedSessionId) {
      accumulator[normalizedUserId] = normalizedSessionId;
    }
    return accumulator;
  }, {});
}

function normalizeNonNegativeInteger(value, fallback = 0) {
  const normalizedFallback =
    Number.isFinite(Number(fallback)) && Number(fallback) >= 0
      ? Math.floor(Number(fallback))
      : 0;
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) {
    return normalizedFallback;
  }
  return Math.floor(parsed);
}

function normalizeNullableDurationMs(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) {
    return null;
  }
  return Math.floor(parsed);
}

function normalizeCallMetrics(value) {
  const source = value && typeof value === "object" ? value : {};
  return {
    acceptLatencyMs: normalizeNullableDurationMs(source.acceptLatencyMs),
    roomJoinFailureCount: normalizeNonNegativeInteger(
      source.roomJoinFailureCount,
    ),
    reconnectCount: normalizeNonNegativeInteger(source.reconnectCount),
    connectedParticipantIds: normalizeParticipantIds(
      source.connectedParticipantIds,
    ),
    lastRoomJoinFailureReason: normalizeNullableString(
      source.lastRoomJoinFailureReason,
    ),
    lastWebhookEvent: normalizeNullableString(source.lastWebhookEvent),
  };
}

function createCallRecord({
  chatId,
  initiatorId,
  recipientId,
  participantIds = null,
  mediaMode,
  originatedBySessionId = null,
}) {
  const timestamp = nowIso();
  const normalizedParticipantIds = normalizeParticipantIds(
    participantIds || [initiatorId, recipientId],
  );
  const normalizedRecipientId =
    normalizeNullableString(recipientId) ||
    normalizedParticipantIds.find((participantId) => participantId !== initiatorId) ||
    "";
  return {
    id: `call_${crypto.randomUUID()}`,
    chatId,
    initiatorId,
    recipientId: normalizedRecipientId,
    participantIds: normalizedParticipantIds,
    mediaMode: normalizeCallMediaMode(mediaMode),
    state: "ringing",
    roomName: null,
    sessionByUserId: {},
    joinedSessionByUserId: {},
    originatedBySessionId: normalizeNullableString(originatedBySessionId),
    acceptedByUserId: null,
    acceptedBySessionId: null,
    createdAt: timestamp,
    updatedAt: timestamp,
    acceptedAt: null,
    endedAt: null,
    endedReason: null,
    metrics: normalizeCallMetrics(null),
  };
}

function normalizeStoredCall(call) {
  if (!call || typeof call !== "object") {
    return null;
  }

  const initiatorId = String(call.initiatorId || "").trim();
  const recipientId = String(call.recipientId || "").trim();
  const chatId = String(call.chatId || "").trim();
  if (!initiatorId || !recipientId || !chatId) {
    return null;
  }

  return {
    id: String(call.id || `call_${crypto.randomUUID()}`),
    chatId,
    initiatorId,
    recipientId,
    participantIds: normalizeParticipantIds(
      call.participantIds || [initiatorId, recipientId],
    ),
    mediaMode: normalizeCallMediaMode(call.mediaMode),
    state: normalizeCallState(call.state),
    roomName: normalizeNullableString(call.roomName),
    sessionByUserId: normalizeCallSessionMap(call.sessionByUserId),
    joinedSessionByUserId: normalizeJoinedSessionMap(call.joinedSessionByUserId),
    originatedBySessionId: normalizeNullableString(call.originatedBySessionId),
    acceptedByUserId: normalizeNullableString(call.acceptedByUserId),
    acceptedBySessionId: normalizeNullableString(call.acceptedBySessionId),
    createdAt: normalizeOptionalIsoTimestamp(call.createdAt) || nowIso(),
    updatedAt: normalizeOptionalIsoTimestamp(call.updatedAt) || nowIso(),
    acceptedAt: normalizeOptionalIsoTimestamp(call.acceptedAt),
    endedAt: normalizeOptionalIsoTimestamp(call.endedAt),
    endedReason: normalizeNullableString(call.endedReason),
    metrics: normalizeCallMetrics(call.metrics),
  };
}

function createChatDraftRecord({userId, chatId, text}) {
  const timestamp = nowIso();
  return {
    userId: String(userId || "").trim(),
    chatId: String(chatId || "").trim(),
    text: String(text || ""),
    updatedAt: timestamp,
  };
}

function createChatPinRecord({chatId, message, pinnedBy}) {
  const attachments = normalizeMessageAttachments(message);
  return {
    chatId: String(chatId || "").trim(),
    messageId: String(message?.id || "").trim(),
    senderId: String(message?.senderId || "").trim(),
    senderName: String(message?.senderName || "Участник").trim() || "Участник",
    text: String(message?.text || ""),
    attachmentCount: attachments.length,
    pinnedAt: nowIso(),
    pinnedBy: String(pinnedBy || "").trim(),
  };
}

function insertDescendingLimited(items, entry, compareEntries, limit) {
  if (!Number.isFinite(limit) || limit <= 0) {
    return;
  }

  let insertIndex = items.findIndex(
    (existingEntry) => compareEntries(entry, existingEntry) < 0,
  );
  if (insertIndex < 0) {
    insertIndex = items.length;
  }

  if (insertIndex >= limit && items.length >= limit) {
    return;
  }

  items.splice(insertIndex, 0, entry);
  if (items.length > limit) {
    items.length = limit;
  }
}

function compareChatMessagesDescending(left, right) {
  const timestampCompare = String(right?.timestamp || "").localeCompare(
    String(left?.timestamp || ""),
  );
  if (timestampCompare !== 0) {
    return timestampCompare;
  }

  return String(right?.id || "").localeCompare(String(left?.id || ""));
}

function normalizeChatSearchQuery(value) {
  return String(value || "")
    .trim()
    .toLocaleLowerCase("ru-RU")
    .split(/\s+/)
    .map((term) => term.trim())
    .filter(Boolean)
    .slice(0, 8);
}

function normalizeSearchText(value) {
  return String(value || "").toLocaleLowerCase("ru-RU");
}

function chatMessageSearchHaystack(message) {
  const attachmentText = normalizeMessageAttachments(message)
    .map((attachment) =>
      [
        attachment.fileName,
        attachment.mimeType,
        attachment.presentation === "voice_note" ? "голосовое" : "",
      ]
        .map((value) => String(value || "").trim())
        .filter(Boolean)
        .join(" "),
    )
    .filter(Boolean)
    .join(" ");
  return normalizeSearchText(
    [message?.text, message?.senderName, attachmentText]
      .map((value) => String(value || "").trim())
      .filter(Boolean)
      .join("\n"),
  );
}

function buildChatSearchSnippet(message, terms) {
  const text = String(message?.text || "").trim();
  const fallback = normalizeMessageAttachments(message).some(
    (attachment) => attachment.presentation === "voice_note",
  )
    ? "Голосовое сообщение"
    : String(message?.senderName || "Сообщение").trim();
  const source = text || fallback;
  if (!source) {
    return "";
  }

  const normalizedSource = normalizeSearchText(source);
  const firstIndex = terms
    .map((term) => normalizedSource.indexOf(term))
    .filter((index) => index >= 0)
    .sort((left, right) => left - right)[0];
  if (!Number.isFinite(firstIndex)) {
    return source.length > 180 ? `${source.slice(0, 179).trimEnd()}…` : source;
  }

  const start = Math.max(0, firstIndex - 70);
  const end = Math.min(source.length, firstIndex + 110);
  const prefix = start > 0 ? "…" : "";
  const suffix = end < source.length ? "…" : "";
  return `${prefix}${source.slice(start, end).trim()}${suffix}`;
}

function normalizeReactionEmoji(value) {
  const emoji = String(value || "").trim();
  if (!emoji) {
    return null;
  }
  return Array.from(emoji).slice(0, 16).join("");
}

function ensureMessageReactions(db) {
  db.messageReactions = Array.isArray(db.messageReactions)
    ? db.messageReactions
    : [];
  return db.messageReactions;
}

function ensureChatPins(db) {
  db.chatPins = Array.isArray(db.chatPins) ? db.chatPins : [];
  return db.chatPins;
}

function aggregateMessageReactions(db, messageId) {
  const normalizedMessageId = String(messageId || "").trim();
  if (!normalizedMessageId) {
    return [];
  }

  const grouped = new Map();
  for (const reaction of ensureMessageReactions(db)) {
    if (String(reaction?.messageId || "").trim() !== normalizedMessageId) {
      continue;
    }
    const emoji = normalizeReactionEmoji(reaction?.emoji);
    const userId = String(reaction?.userId || "").trim();
    if (!emoji || !userId) {
      continue;
    }
    const existing = grouped.get(emoji) || {
      emoji,
      userIds: [],
      count: 0,
    };
    if (!existing.userIds.includes(userId)) {
      existing.userIds.push(userId);
      existing.count = existing.userIds.length;
    }
    grouped.set(emoji, existing);
  }

  return Array.from(grouped.values()).sort((left, right) =>
    String(left.emoji || "").localeCompare(String(right.emoji || "")),
  );
}

function attachMessageReactions(db, message) {
  const clone = structuredClone(message);
  clone.reactions = aggregateMessageReactions(db, clone.id);
  return clone;
}

function isMessageReadByUser(message, userId) {
  const readBy = normalizeParticipantIds(message?.readBy);
  if (readBy.length > 0) {
    return readBy.includes(userId);
  }
  return message?.isRead === true;
}

module.exports = {
  deriveSessionPublicId,
  normalizeSessionDeviceContext,
  buildCallParticipantIdentity,
  normalizeChatMessageCall,
  parseCallParticipantIdentity,
  collectMediaUrl,
  collectMessageMediaUrls,
  collectOwnedMediaUrlsForUser,
  createChatRecord,
  parseDirectParticipantsFromChatId,
  normalizeCallMediaMode,
  normalizeCallState,
  isCallTerminalState,
  isCallBusyState,
  normalizeCallSession,
  normalizeCallSessionMap,
  normalizeJoinedSessionMap,
  normalizeNonNegativeInteger,
  normalizeNullableDurationMs,
  normalizeCallMetrics,
  createCallRecord,
  normalizeStoredCall,
  createChatDraftRecord,
  createChatPinRecord,
  insertDescendingLimited,
  compareChatMessagesDescending,
  normalizeChatSearchQuery,
  normalizeSearchText,
  chatMessageSearchHaystack,
  buildChatSearchSnippet,
  normalizeReactionEmoji,
  ensureMessageReactions,
  ensureChatPins,
  aggregateMessageReactions,
  attachMessageReactions,
  isMessageReadByUser,
};
