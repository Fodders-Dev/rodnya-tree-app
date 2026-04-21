const fs = require("node:fs/promises");
const path = require("node:path");
const crypto = require("node:crypto");

const PROFILE_CONTRIBUTION_POLICIES = new Set([
  "disabled",
  "suggestions",
]);

const PROFILE_SUGGESTION_FIELDS = Object.freeze([
  "firstName",
  "lastName",
  "middleName",
  "maidenName",
  "photoUrl",
  "gender",
  "birthDate",
  "birthPlace",
  "countryName",
  "city",
  "bio",
  "familyStatus",
  "aboutFamily",
  "education",
  "work",
  "hometown",
  "languages",
  "values",
  "religion",
  "interests",
]);

const EMPTY_DB = {
  users: [],
  sessions: [],
  authHandoffs: [],
  trees: [],
  persons: [],
  personIdentities: [],
  relations: [],
  chats: [],
  calls: [],
  messages: [],
  relationRequests: [],
  treeInvitations: [],
  treeChangeRecords: [],
  notifications: [],
  posts: [],
  stories: [],
  comments: [],
  reports: [],
  blocks: [],
  profileContributions: [],
  pushDevices: [],
  pushDeliveries: [],
};

function normalizeDbState(parsed) {
  return {
    users: Array.isArray(parsed?.users) ? parsed.users : [],
    sessions: Array.isArray(parsed?.sessions) ? parsed.sessions : [],
    authHandoffs: Array.isArray(parsed?.authHandoffs) ? parsed.authHandoffs : [],
    trees: Array.isArray(parsed?.trees) ? parsed.trees : [],
    persons: Array.isArray(parsed?.persons) ? parsed.persons : [],
    personIdentities: Array.isArray(parsed?.personIdentities)
      ? parsed.personIdentities
      : [],
    relations: Array.isArray(parsed?.relations) ? parsed.relations : [],
    chats: Array.isArray(parsed?.chats) ? parsed.chats : [],
    calls: Array.isArray(parsed?.calls)
      ? parsed.calls.map((entry) => normalizeStoredCall(entry)).filter(Boolean)
      : [],
    messages: Array.isArray(parsed?.messages) ? parsed.messages : [],
    relationRequests: Array.isArray(parsed?.relationRequests)
      ? parsed.relationRequests
      : [],
    treeInvitations: Array.isArray(parsed?.treeInvitations)
      ? parsed.treeInvitations
      : [],
    treeChangeRecords: Array.isArray(parsed?.treeChangeRecords)
      ? parsed.treeChangeRecords
      : [],
    notifications: Array.isArray(parsed?.notifications)
      ? parsed.notifications
      : [],
    posts: Array.isArray(parsed?.posts) ? parsed.posts : [],
    stories: Array.isArray(parsed?.stories) ? parsed.stories : [],
    comments: Array.isArray(parsed?.comments) ? parsed.comments : [],
    reports: Array.isArray(parsed?.reports) ? parsed.reports : [],
    blocks: Array.isArray(parsed?.blocks) ? parsed.blocks : [],
    profileContributions: Array.isArray(parsed?.profileContributions)
      ? parsed.profileContributions
      : [],
    pushDevices: Array.isArray(parsed?.pushDevices) ? parsed.pushDevices : [],
    pushDeliveries: Array.isArray(parsed?.pushDeliveries)
      ? parsed.pushDeliveries
      : [],
  };
}

function nowIso() {
  return new Date().toISOString();
}

const SESSION_TOUCH_MIN_INTERVAL_MS = 60_000;

function normalizeOptionalIsoTimestamp(value) {
  const rawValue = String(value || "").trim();
  if (!rawValue) {
    return null;
  }

  const parsedDate = new Date(rawValue);
  if (Number.isNaN(parsedDate.getTime())) {
    return null;
  }

  return parsedDate.toISOString();
}

function isExpiredAt(value, referenceTimeMs = Date.now()) {
  const normalizedValue = normalizeOptionalIsoTimestamp(value);
  if (!normalizedValue) {
    return false;
  }
  return new Date(normalizedValue).getTime() <= referenceTimeMs;
}

function createProfileNote({title, content}) {
  const timestamp = nowIso();
  return {
    id: crypto.randomUUID(),
    title: String(title || "").trim(),
    content: String(content || "").trim(),
    createdAt: timestamp,
    updatedAt: timestamp,
  };
}

function createNotificationRecord({userId, type, title, body, data = {}}) {
  const timestamp = nowIso();
  return {
    id: crypto.randomUUID(),
    userId,
    type: String(type || "generic"),
    title: String(title || "").trim(),
    body: String(body || "").trim(),
    data: data && typeof data === "object" ? structuredClone(data) : {},
    createdAt: timestamp,
    readAt: null,
  };
}

function createPostRecord({
  treeId,
  authorId,
  authorName,
  authorPhotoUrl = null,
  content,
  imageUrls = [],
  isPublic = false,
  scopeType = "wholeTree",
  anchorPersonIds = [],
}) {
  const timestamp = nowIso();
  return {
    id: crypto.randomUUID(),
    treeId,
    authorId,
    authorName: String(authorName || "Аноним").trim() || "Аноним",
    authorPhotoUrl: normalizeNullableString(authorPhotoUrl),
    content: String(content || "").trim(),
    imageUrls: Array.from(
      new Set(
        (Array.isArray(imageUrls) ? imageUrls : [])
          .map((value) => String(value || "").trim())
          .filter(Boolean),
      ),
    ),
    createdAt: timestamp,
    updatedAt: timestamp,
    likedBy: [],
    isPublic: isPublic === true,
    scopeType: scopeType === "branches" ? "branches" : "wholeTree",
    anchorPersonIds: normalizeParticipantIds(anchorPersonIds),
  };
}

function normalizeStoryType(type) {
  const normalizedType = String(type || "text").trim().toLowerCase();
  if (normalizedType === "image" || normalizedType === "video") {
    return normalizedType;
  }
  return "text";
}

function createStoryRecord({
  treeId,
  authorId,
  authorName,
  authorPhotoUrl = null,
  type = "text",
  text = null,
  mediaUrl = null,
  thumbnailUrl = null,
  expiresAt = null,
}) {
  const createdAt = nowIso();
  const normalizedExpiresAt =
    normalizeOptionalIsoTimestamp(expiresAt) ||
    new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
  return {
    id: crypto.randomUUID(),
    treeId,
    authorId,
    authorName: String(authorName || "Аноним").trim() || "Аноним",
    authorPhotoUrl: normalizeNullableString(authorPhotoUrl),
    type: normalizeStoryType(type),
    text: normalizeNullableString(text),
    mediaUrl: normalizeNullableString(mediaUrl),
    thumbnailUrl: normalizeNullableString(thumbnailUrl),
    createdAt,
    updatedAt: createdAt,
    expiresAt: normalizedExpiresAt,
    viewedBy: [],
  };
}

function createCommentRecord({
  postId,
  authorId,
  authorName,
  authorPhotoUrl = null,
  content,
}) {
  const timestamp = nowIso();
  return {
    id: crypto.randomUUID(),
    postId,
    authorId,
    authorName: String(authorName || "Аноним").trim() || "Аноним",
    authorPhotoUrl: normalizeNullableString(authorPhotoUrl),
    content: String(content || "").trim(),
    createdAt: timestamp,
    updatedAt: timestamp,
    likedBy: [],
  };
}

function createPushDeviceRecord({
  userId,
  provider,
  token,
  platform = "unknown",
}) {
  const timestamp = nowIso();
  return {
    id: crypto.randomUUID(),
    userId,
    provider: String(provider || "unknown").trim(),
    token: String(token || "").trim(),
    platform: String(platform || "unknown").trim(),
    createdAt: timestamp,
    updatedAt: timestamp,
    lastSeenAt: timestamp,
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

function normalizeParticipantIds(participantIds) {
  return Array.from(
    new Set(
      (Array.isArray(participantIds) ? participantIds : [])
        .map((value) => String(value || "").trim())
        .filter(Boolean),
    ),
  ).sort((left, right) => left.localeCompare(right));
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
  createdBy = null,
  treeId = null,
  branchRootPersonIds = [],
}) {
  const timestamp = nowIso();
  return {
    id: id || crypto.randomUUID(),
    type: String(type || "direct").trim() || "direct",
    participantIds: normalizeParticipantIds(participantIds),
    title: normalizeNullableString(title),
    createdBy: normalizeNullableString(createdBy),
    treeId: normalizeNullableString(treeId),
    branchRootPersonIds: normalizeParticipantIds(branchRootPersonIds),
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

function describeMessagePreview(message) {
  const text = String(message?.text || "").trim();
  if (text) {
    return text;
  }

  const attachments = normalizeMessageAttachments(message);
  if (
    attachments.some((attachment) => attachment.presentation === "video_note")
  ) {
    return "Видеосообщение";
  }
  if (
    attachments.some((attachment) => attachment.presentation === "voice_note")
  ) {
    return "Голосовое";
  }
  const imageCount = attachments.filter((attachment) => attachment.type === "image")
    .length;
  if (imageCount > 1) {
    return `Фото (${imageCount})`;
  }
  if (attachments.some((attachment) => attachment.type === "video")) {
    return "Видео";
  }
  if (attachments.some((attachment) => attachment.type === "audio")) {
    return "Голосовое";
  }
  if (imageCount === 1) {
    return "Фото";
  }
  if (attachments.some((attachment) => attachment.type === "file")) {
    return "Файл";
  }

  return "";
}

function normalizeAttachmentPresentation(rawPresentation, rawType) {
  const normalizedPresentation = String(rawPresentation || "").trim().toLowerCase();
  if (
    normalizedPresentation === "default" ||
    normalizedPresentation === "voice_note" ||
    normalizedPresentation === "video_note"
  ) {
    return normalizedPresentation;
  }

  const normalizedType = String(rawType || "").trim().toLowerCase();
  if (normalizedType === "audio") {
    return "default";
  }
  if (normalizedType === "video") {
    return "default";
  }
  return "default";
}

function normalizeAttachmentType(rawType, url, mimeType) {
  const normalizedType = String(rawType || "").trim().toLowerCase();
  if (normalizedType === "image" ||
      normalizedType === "video" ||
      normalizedType === "audio" ||
      normalizedType === "file") {
    return normalizedType;
  }

  const normalizedMimeType = String(mimeType || "").trim().toLowerCase();
  if (normalizedMimeType.startsWith("image/")) {
    return "image";
  }
  if (normalizedMimeType.startsWith("video/")) {
    return "video";
  }
  if (normalizedMimeType.startsWith("audio/")) {
    return "audio";
  }

  const normalizedUrl = String(url || "").trim().toLowerCase();
  if (/\.(png|jpe?g|gif|webp)$/.test(normalizedUrl)) {
    return "image";
  }
  if (/\.(mp4|mov|webm)$/.test(normalizedUrl)) {
    return "video";
  }
  if (/\.(m4a|aac|mp3|wav|ogg)$/.test(normalizedUrl)) {
    return "audio";
  }

  return "file";
}

function normalizeMessageAttachments(message) {
  const explicitAttachments = Array.isArray(message?.attachments)
    ? message.attachments
        .map((attachment) => {
          const url = String(attachment?.url || "").trim();
          if (!url) {
            return null;
          }

          return {
            type: normalizeAttachmentType(
              attachment?.type,
              url,
              attachment?.mimeType,
            ),
            url,
            presentation: normalizeAttachmentPresentation(
              attachment?.presentation,
              attachment?.type,
            ),
            mimeType: attachment?.mimeType
              ? String(attachment.mimeType).trim()
              : null,
            fileName: attachment?.fileName
              ? String(attachment.fileName).trim()
              : null,
            sizeBytes: Number.isFinite(Number(attachment?.sizeBytes))
              ? Number(attachment.sizeBytes)
              : null,
            durationMs: Number.isFinite(Number(attachment?.durationMs))
              ? Number(attachment.durationMs)
              : null,
            width: Number.isFinite(Number(attachment?.width))
              ? Number(attachment.width)
              : null,
            height: Number.isFinite(Number(attachment?.height))
              ? Number(attachment.height)
              : null,
            thumbnailUrl: attachment?.thumbnailUrl
              ? String(attachment.thumbnailUrl).trim()
              : null,
          };
        })
        .filter(Boolean)
    : [];
  if (explicitAttachments.length > 0) {
    return explicitAttachments;
  }

  const legacyUrls = new Set();
  if (Array.isArray(message?.mediaUrls)) {
    for (const entry of message.mediaUrls) {
      const value = String(entry || "").trim();
      if (value) {
        legacyUrls.add(value);
      }
    }
  }
  const imageUrl = String(message?.imageUrl || "").trim();
  if (imageUrl) {
    legacyUrls.add(imageUrl);
  }

  return Array.from(legacyUrls).map((url) => ({
    type: normalizeAttachmentType("image", url, "image/jpeg"),
    url,
    presentation: "default",
    mimeType: "image/jpeg",
    fileName: null,
    sizeBytes: null,
    durationMs: null,
    width: null,
    height: null,
    thumbnailUrl: null,
  }));
}

function normalizeReplyReference(replyTo) {
  if (!replyTo || typeof replyTo !== "object") {
    return null;
  }

  const messageId = String(replyTo.messageId || replyTo.id || "").trim();
  if (!messageId) {
    return null;
  }

  return {
    messageId,
    senderId: String(replyTo.senderId || "").trim(),
    senderName: String(replyTo.senderName || "Участник").trim() || "Участник",
    text: String(replyTo.text || "").trim(),
  };
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
  mediaMode,
}) {
  const timestamp = nowIso();
  return {
    id: `call_${crypto.randomUUID()}`,
    chatId,
    initiatorId,
    recipientId,
    participantIds: normalizeParticipantIds([initiatorId, recipientId]),
    mediaMode: normalizeCallMediaMode(mediaMode),
    state: "ringing",
    roomName: null,
    sessionByUserId: {},
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
    createdAt: normalizeOptionalIsoTimestamp(call.createdAt) || nowIso(),
    updatedAt: normalizeOptionalIsoTimestamp(call.updatedAt) || nowIso(),
    acceptedAt: normalizeOptionalIsoTimestamp(call.acceptedAt),
    endedAt: normalizeOptionalIsoTimestamp(call.endedAt),
    endedReason: normalizeNullableString(call.endedReason),
    metrics: normalizeCallMetrics(call.metrics),
  };
}

function sameNormalizedIds(left, right) {
  const normalizedLeft = normalizeParticipantIds(left);
  const normalizedRight = normalizeParticipantIds(right);
  if (normalizedLeft.length !== normalizedRight.length) {
    return false;
  }

  return normalizedLeft.every((value, index) => value === normalizedRight[index]);
}

function isSpouseLikeRelation(relation) {
  return (
    relation?.relation1to2 === "spouse" ||
    relation?.relation2to1 === "spouse" ||
    relation?.relation1to2 === "partner" ||
    relation?.relation2to1 === "partner"
  );
}

function parentIdFromRelation(relation) {
  if (
    relation?.relation1to2 === "parent" ||
    relation?.relation2to1 === "child"
  ) {
    return relation.person1Id;
  }
  if (
    relation?.relation2to1 === "parent" ||
    relation?.relation1to2 === "child"
  ) {
    return relation.person2Id;
  }
  return null;
}

function childIdFromRelation(relation) {
  if (
    relation?.relation1to2 === "parent" ||
    relation?.relation2to1 === "child"
  ) {
    return relation.person2Id;
  }
  if (
    relation?.relation2to1 === "parent" ||
    relation?.relation1to2 === "child"
  ) {
    return relation.person1Id;
  }
  return null;
}

const PARENT_SET_TYPES = new Set([
  "biological",
  "adoptive",
  "foster",
  "guardian",
  "step",
  "unknown",
]);

const BLOOD_PARENT_SET_TYPES = new Set(["biological", "unknown"]);

const UNION_TYPES = new Set([
  "spouse",
  "partner",
  "friend",
  "single",
  "other",
]);

const UNION_STATUSES = new Set(["current", "past"]);

function buildSortedIdKey(values) {
  return (Array.isArray(values) ? values : [])
    .map((value) => String(value || "").trim())
    .filter(Boolean)
    .sort((left, right) => left.localeCompare(right))
    .join(":");
}

function extractSurnameFromName(name) {
  const parts = String(name || "")
    .trim()
    .split(/\s+/)
    .filter(Boolean);
  if (parts.length === 0) {
    return null;
  }
  return parts[0];
}

function normalizeParentSetType(value) {
  const normalized = String(value || "").trim().toLowerCase();
  return PARENT_SET_TYPES.has(normalized) ? normalized : "biological";
}

function isBloodParentSetType(value) {
  return BLOOD_PARENT_SET_TYPES.has(normalizeParentSetType(value));
}

function normalizeUnionType(value, {relationType = null} = {}) {
  const normalized = String(value || "").trim().toLowerCase();
  if (UNION_TYPES.has(normalized)) {
    return normalized;
  }

  const normalizedRelationType = String(relationType || "")
    .trim()
    .toLowerCase();
  if (normalizedRelationType === "spouse" || normalizedRelationType === "ex_spouse") {
    return "spouse";
  }
  if (normalizedRelationType === "partner" || normalizedRelationType === "ex_partner") {
    return "partner";
  }
  if (normalizedRelationType === "friend") {
    return "friend";
  }

  return "other";
}

function normalizeUnionStatus(value, {relationType = null, divorceDate = null} = {}) {
  const normalized = String(value || "").trim().toLowerCase();
  if (UNION_STATUSES.has(normalized)) {
    return normalized;
  }

  const normalizedRelationType = String(relationType || "")
    .trim()
    .toLowerCase();
  if (
    normalizedRelationType === "ex_spouse" ||
    normalizedRelationType === "ex_partner" ||
    normalizeOptionalIsoTimestamp(divorceDate)
  ) {
    return "past";
  }

  return "current";
}

function relationTypeForPerson(relation, personId) {
  const normalizedPersonId = String(personId || "").trim();
  if (!normalizedPersonId) {
    return null;
  }
  if (String(relation?.person1Id || "").trim() === normalizedPersonId) {
    return String(relation?.relation1to2 || "").trim() || null;
  }
  if (String(relation?.person2Id || "").trim() === normalizedPersonId) {
    return String(relation?.relation2to1 || "").trim() || null;
  }
  return null;
}

function relationCustomLabelForPerson(relation, personId) {
  const normalizedPersonId = String(personId || "").trim();
  if (!normalizedPersonId) {
    return null;
  }
  if (String(relation?.person1Id || "").trim() === normalizedPersonId) {
    return normalizeNullableString(relation?.customRelationLabel1to2);
  }
  if (String(relation?.person2Id || "").trim() === normalizedPersonId) {
    return normalizeNullableString(relation?.customRelationLabel2to1);
  }
  return null;
}

function isUnionRelationType(relationType) {
  switch (String(relationType || "").trim().toLowerCase()) {
    case "spouse":
    case "partner":
    case "friend":
    case "ex_spouse":
    case "ex_partner":
      return true;
    default:
      return false;
  }
}

function isUnionRelation(relation) {
  return (
    isUnionRelationType(relation?.relation1to2) ||
    isUnionRelationType(relation?.relation2to1)
  );
}

function isBloodDirectRelationType(relationType, parentSetType = null) {
  switch (String(relationType || "").trim().toLowerCase()) {
    case "parent":
    case "child":
      return isBloodParentSetType(parentSetType);
    case "sibling":
    case "cousin":
    case "uncle":
    case "aunt":
    case "nephew":
    case "niece":
    case "nibling":
    case "grandparent":
    case "grandchild":
    case "greatgrandparent":
    case "greatgrandchild":
      return true;
    default:
      return false;
  }
}

function isCurrentUnionRelation(relation) {
  if (!isUnionRelation(relation)) {
    return false;
  }
  return normalizeUnionStatus(relation?.unionStatus, {
    relationType: relation?.relation1to2 || relation?.relation2to1,
    divorceDate: relation?.divorceDate,
  }) === "current";
}

function buildLinkedPersonCanonicalPatchFromProfile(profile = {}) {
  const displayName = composeDisplayNameFromProfile(profile);
  const photoState = normalizePersonPhotoGallery([], {
    photoUrl: profile.photoUrl,
    primaryPhotoUrl: profile.photoUrl,
  });

  return {
    name: displayName || null,
    maidenName: normalizeNullableString(profile.maidenName),
    photoUrl: photoState.photoUrl,
    primaryPhotoUrl: photoState.primaryPhotoUrl,
    gender: String(profile.gender || "unknown").trim() || "unknown",
    birthDate: normalizeIsoDate(profile.birthDate),
    birthPlace: normalizeNullableString(profile.birthPlace),
  };
}

function applyCanonicalProfileToPerson(person, profile = {}, {
  touchUpdatedAt = true,
} = {}) {
  if (!person || !profile || typeof profile !== "object") {
    return person;
  }

  const patch = buildLinkedPersonCanonicalPatchFromProfile(profile);
  if (patch.name) {
    person.name = patch.name;
  }
  person.maidenName = patch.maidenName;
  if (patch.photoUrl) {
    person.photoUrl = patch.photoUrl;
    person.primaryPhotoUrl = patch.primaryPhotoUrl;
  }
  person.gender = patch.gender;
  person.birthDate = patch.birthDate;
  person.birthPlace = patch.birthPlace;
  if (touchUpdatedAt) {
    person.updatedAt = nowIso();
  }
  return person;
}

function buildCanonicalPersonView(db, person, {
  touchUpdatedAt = false,
} = {}) {
  const personView = structuredClone(person);
  if (!personView?.userId) {
    return personView;
  }

  const user = db.users.find((entry) => entry.id === personView.userId);
  if (!user?.profile) {
    return personView;
  }

  return applyCanonicalProfileToPerson(personView, user.profile, {
    touchUpdatedAt,
  });
}

function buildBranchVisiblePersonIds(persons, relations, branchRootPersonId) {
  const normalizedRootId = String(branchRootPersonId || "").trim();
  if (!normalizedRootId) {
    return new Set();
  }
  const treeId = Array.isArray(persons) && persons.length > 0 ? persons[0]?.treeId : null;
  if (!treeId) {
    return new Set([normalizedRootId]);
  }
  const snapshot = buildTreeGraphSnapshot({
    treeId,
    persons,
    relations,
    viewerPersonId: null,
  });
  const branchBlock = chooseBranchBlockForPerson(snapshot, normalizedRootId);
  return new Set(branchBlock?.memberPersonIds || [normalizedRootId]);
}

function relationMirror(relationType) {
  switch (String(relationType || "other")) {
    case "parent":
      return "child";
    case "child":
      return "parent";
    case "spouse":
      return "spouse";
    case "partner":
      return "partner";
    case "sibling":
      return "sibling";
    case "cousin":
      return "cousin";
    case "uncle":
      return "nibling";
    case "aunt":
      return "nibling";
    case "nephew":
      return "uncle";
    case "niece":
      return "aunt";
    case "nibling":
      return "uncle";
    case "grandparent":
      return "grandchild";
    case "grandchild":
      return "grandparent";
    case "greatGrandparent":
      return "greatGrandchild";
    case "greatGrandchild":
      return "greatGrandparent";
    case "parentInLaw":
      return "childInLaw";
    case "childInLaw":
      return "parentInLaw";
    case "siblingInLaw":
      return "siblingInLaw";
    case "inlaw":
      return "inlaw";
    case "stepparent":
      return "stepchild";
    case "stepchild":
      return "stepparent";
    case "ex_spouse":
      return "ex_spouse";
    case "ex_partner":
      return "ex_partner";
    case "friend":
      return "friend";
    case "colleague":
      return "colleague";
    default:
      return "other";
  }
}

function genderAwareWord(gender, {
  male,
  female,
  neutral,
}) {
  const normalizedGender = String(gender || "").trim().toLowerCase();
  if (normalizedGender === "male" && male) {
    return male;
  }
  if (normalizedGender === "female" && female) {
    return female;
  }
  return neutral || male || female || "";
}

function normalizeGenderValue(gender) {
  return String(gender || "").trim().toLowerCase();
}

function isMaleGender(gender) {
  return normalizeGenderValue(gender) === "male";
}

function isFemaleGender(gender) {
  return normalizeGenderValue(gender) === "female";
}

function addMapSetValue(map, key, value) {
  const normalizedKey = String(key || "").trim();
  const normalizedValue = String(value || "").trim();
  if (!normalizedKey || !normalizedValue) {
    return;
  }
  if (!map.has(normalizedKey)) {
    map.set(normalizedKey, new Set());
  }
  map.get(normalizedKey).add(normalizedValue);
}

function getMapSetValues(map, key) {
  return Array.from(map.get(String(key || "").trim()) || []);
}

function hasMapSetValue(map, key, value) {
  return Boolean(map.get(String(key || "").trim())?.has(String(value || "").trim()));
}

function describeDirectRelationLabel({
  relationType,
  gender = "unknown",
  parentSetType = "biological",
}) {
  const normalizedRelationType = String(relationType || "").trim().toLowerCase();
  const normalizedParentSetType = normalizeParentSetType(parentSetType);

  if (normalizedRelationType === "parent") {
    if (normalizedParentSetType === "adoptive") {
      return "Приемный родитель";
    }
    if (normalizedParentSetType === "guardian") {
      return "Опекун";
    }
    if (normalizedParentSetType === "foster") {
      return "Приемный родитель";
    }
    if (normalizedParentSetType === "step") {
      return genderAwareWord(gender, {
        male: "Отчим",
        female: "Мачеха",
        neutral: "Сводный родитель",
      });
    }
    return genderAwareWord(gender, {
      male: "Отец",
      female: "Мать",
      neutral: "Родитель",
    });
  }

  if (normalizedRelationType === "child") {
    if (normalizedParentSetType === "adoptive") {
      return "Приемный ребенок";
    }
    if (normalizedParentSetType === "guardian") {
      return "Подопечный";
    }
    if (normalizedParentSetType === "foster") {
      return "Приемный ребенок";
    }
    if (normalizedParentSetType === "step") {
      return genderAwareWord(gender, {
        male: "Пасынок",
        female: "Падчерица",
        neutral: "Сводный ребенок",
      });
    }
    return genderAwareWord(gender, {
      male: "Сын",
      female: "Дочь",
      neutral: "Ребенок",
    });
  }

  switch (normalizedRelationType) {
    case "sibling":
      return genderAwareWord(gender, {
        male: "Брат",
        female: "Сестра",
        neutral: "Сиблинг",
      });
    case "spouse":
      return genderAwareWord(gender, {
        male: "Муж",
        female: "Жена",
        neutral: "Супруг",
      });
    case "partner":
      return "Партнер";
    case "ex_spouse":
      return "Бывший супруг";
    case "ex_partner":
      return "Бывший партнер";
    case "friend":
      return "Друг";
    case "stepparent":
      return genderAwareWord(gender, {
        male: "Отчим",
        female: "Мачеха",
        neutral: "Сводный родитель",
      });
    case "stepchild":
      return genderAwareWord(gender, {
        male: "Пасынок",
        female: "Падчерица",
        neutral: "Сводный ребенок",
      });
    case "grandparent":
      return genderAwareWord(gender, {
        male: "Дедушка",
        female: "Бабушка",
        neutral: "Прародитель",
      });
    case "grandchild":
      return genderAwareWord(gender, {
        male: "Внук",
        female: "Внучка",
        neutral: "Внук/внучка",
      });
    case "uncle":
      return genderAwareWord(gender, {
        male: "Дядя",
        female: "Тетя",
        neutral: "Дядя/тетя",
      });
    case "aunt":
      return genderAwareWord(gender, {
        male: "Дядя",
        female: "Тетя",
        neutral: "Дядя/тетя",
      });
    case "nephew":
    case "niece":
    case "nibling":
      return genderAwareWord(gender, {
        male: "Племянник",
        female: "Племянница",
        neutral: "Племянник/племянница",
      });
    case "cousin":
      return genderAwareWord(gender, {
        male: "Двоюродный брат",
        female: "Двоюродная сестра",
        neutral: "Двоюродный родственник",
      });
    case "parentInLaw":
      return genderAwareWord(gender, {
        male: "Родитель супруга",
        female: "Родительница супруга",
        neutral: "Родитель супруга",
      });
    case "childInLaw":
      return genderAwareWord(gender, {
        male: "Зять",
        female: "Невестка",
        neutral: "Родня по браку",
      });
    case "siblingInLaw":
      return genderAwareWord(gender, {
        male: "Брат супруга",
        female: "Сестра супруга",
        neutral: "Сиблинг супруга",
      });
    case "inlaw":
      return "Родня по браку";
    case "colleague":
      return "Коллега";
    default:
      return "Родственник";
  }
}

function buildPathSummary(pathPersonIds, peopleById) {
  const labels = (Array.isArray(pathPersonIds) ? pathPersonIds : [])
    .map((personId) => {
      const person = peopleById.get(personId);
      return String(person?.name || "").trim() || personId;
    })
    .filter(Boolean);
  return labels.join(" -> ");
}

function collectAncestorDepths(startPersonId, parentsByChild) {
  const depths = new Map();
  const queue = [{personId: startPersonId, depth: 0}];

  while (queue.length > 0) {
    const current = queue.shift();
    if (!current) {
      continue;
    }
    const previousDepth = depths.get(current.personId);
    if (previousDepth !== undefined && previousDepth <= current.depth) {
      continue;
    }
    depths.set(current.personId, current.depth);
    for (const parentId of parentsByChild.get(current.personId) || []) {
      queue.push({
        personId: parentId,
        depth: current.depth + 1,
      });
    }
  }

  return depths;
}

function ordinalCousinLabel(degree) {
  switch (degree) {
    case 1:
      return "Двоюродный";
    case 2:
      return "Троюродный";
    case 3:
      return "Четвероюродный";
    default:
      return "Дальний";
  }
}

function ordinalCousinPrefix(degree, gender) {
  switch (degree) {
    case 1:
      return genderAwareWord(gender, {
        male: "Двоюродный",
        female: "Двоюродная",
        neutral: "Двоюродный",
      });
    case 2:
      return genderAwareWord(gender, {
        male: "Троюродный",
        female: "Троюродная",
        neutral: "Троюродный",
      });
    case 3:
      return genderAwareWord(gender, {
        male: "Четвероюродный",
        female: "Четвероюродная",
        neutral: "Четвероюродный",
      });
    default:
      return genderAwareWord(gender, {
        male: "Дальний",
        female: "Дальняя",
        neutral: "Дальний",
      });
  }
}

function buildAncestorLabel(depth, gender) {
  if (depth === 1) {
    return genderAwareWord(gender, {
      male: "Отец",
      female: "Мать",
      neutral: "Родитель",
    });
  }
  if (depth === 2) {
    return genderAwareWord(gender, {
      male: "Дедушка",
      female: "Бабушка",
      neutral: "Прародитель",
    });
  }
  if (depth === 3) {
    return genderAwareWord(gender, {
      male: "Прадедушка",
      female: "Прабабушка",
      neutral: "Предок",
    });
  }
  return "Предок";
}

function buildDescendantLabel(depth, gender) {
  if (depth === 1) {
    return genderAwareWord(gender, {
      male: "Сын",
      female: "Дочь",
      neutral: "Ребенок",
    });
  }
  if (depth === 2) {
    return genderAwareWord(gender, {
      male: "Внук",
      female: "Внучка",
      neutral: "Внук/внучка",
    });
  }
  if (depth === 3) {
    return genderAwareWord(gender, {
      male: "Правнук",
      female: "Правнучка",
      neutral: "Правнук/правнучка",
    });
  }
  return "Потомок";
}

function buildUncleAuntLabel(gender, prefix = null) {
  const value = genderAwareWord(gender, {
    male: "дядя",
    female: "тетя",
    neutral: "дядя/тетя",
  });
  if (!prefix) {
    return value.charAt(0).toUpperCase() + value.slice(1);
  }
  return `${prefix} ${value}`.trim();
}

function buildNephewNieceLabel(gender, prefix = null) {
  const value = genderAwareWord(gender, {
    male: "племянник",
    female: "племянница",
    neutral: "племянник/племянница",
  });
  if (!prefix) {
    return value.charAt(0).toUpperCase() + value.slice(1);
  }
  return `${prefix} ${value}`.trim();
}

function buildGrandUncleAuntLabel(gender) {
  return genderAwareWord(gender, {
    male: "Двоюродный дедушка",
    female: "Двоюродная бабушка",
    neutral: "Двоюродный дедушка/бабушка",
  });
}

function buildGrandNephewNieceLabel(gender) {
  return genderAwareWord(gender, {
    male: "Внучатый племянник",
    female: "Внучатая племянница",
    neutral: "Внучатый племянник/племянница",
  });
}

function buildCousinOlderGenerationLabel(cousinDegree, gender) {
  const prefix = ordinalCousinPrefix(cousinDegree, gender);
  return genderAwareWord(gender, {
    male: `${prefix} дядя`,
    female: `${prefix} тетя`,
    neutral: `${prefix} дядя/тетя`,
  });
}

function buildCousinYoungerGenerationLabel(cousinDegree, gender) {
  const prefix = ordinalCousinPrefix(cousinDegree, gender);
  return genderAwareWord(gender, {
    male: `${prefix} племянник`,
    female: `${prefix} племянница`,
    neutral: `${prefix} племянник/племянница`,
  });
}

function buildBloodRelationshipLabel({
  viewerDepth,
  targetDepth,
  targetGender,
}) {
  if (viewerDepth === 0 && targetDepth === 0) {
    return "Это вы";
  }

  if (targetDepth === 0 && viewerDepth > 0) {
    return buildAncestorLabel(viewerDepth, targetGender);
  }

  if (viewerDepth === 0 && targetDepth > 0) {
    return buildDescendantLabel(targetDepth, targetGender);
  }

  if (viewerDepth === 1 && targetDepth === 1) {
    return genderAwareWord(targetGender, {
      male: "Брат",
      female: "Сестра",
      neutral: "Сиблинг",
    });
  }

  if (viewerDepth === 1 && targetDepth === 2) {
    return genderAwareWord(targetGender, {
      male: "Племянник",
      female: "Племянница",
      neutral: "Племянник/племянница",
    });
  }

  if (viewerDepth === 1 && targetDepth === 3) {
    return buildGrandNephewNieceLabel(targetGender);
  }

  if (viewerDepth === 2 && targetDepth === 1) {
    return buildUncleAuntLabel(targetGender);
  }

  if (viewerDepth === 3 && targetDepth === 1) {
    return buildGrandUncleAuntLabel(targetGender);
  }

  if (viewerDepth > 1 && targetDepth > 1) {
    const cousinDegree = Math.min(viewerDepth, targetDepth) - 1;
    const removed = Math.abs(viewerDepth - targetDepth);
    if (removed === 0) {
      return `${ordinalCousinPrefix(cousinDegree, targetGender)} ${genderAwareWord(targetGender, {
        male: "брат",
        female: "сестра",
        neutral: "родственник",
      })}`.trim();
    }
    if (removed === 1) {
      if (viewerDepth < targetDepth) {
        return buildCousinYoungerGenerationLabel(cousinDegree, targetGender);
      }
      return buildCousinOlderGenerationLabel(cousinDegree, targetGender);
    }
  }

  return "Кровный родственник";
}

function computeBloodRelationshipDescriptor(
  viewerPersonId,
  targetPersonId,
  bloodParentsByChild,
  peopleById,
) {
  if (!viewerPersonId || !targetPersonId) {
    return null;
  }

  const viewerAncestors = collectAncestorDepths(viewerPersonId, bloodParentsByChild);
  const targetAncestors = collectAncestorDepths(targetPersonId, bloodParentsByChild);
  let bestMatch = null;

  for (const [ancestorId, viewerDepth] of viewerAncestors.entries()) {
    if (!targetAncestors.has(ancestorId)) {
      continue;
    }
    const targetDepth = targetAncestors.get(ancestorId);
    const candidate = {
      ancestorId,
      viewerDepth,
      targetDepth,
      totalDepth: viewerDepth + targetDepth,
      maxDepth: Math.max(viewerDepth, targetDepth),
    };
    if (
      !bestMatch ||
      candidate.totalDepth < bestMatch.totalDepth ||
      (candidate.totalDepth === bestMatch.totalDepth &&
        candidate.maxDepth < bestMatch.maxDepth)
    ) {
      bestMatch = candidate;
    }
  }

  if (!bestMatch) {
    return null;
  }

  const target = peopleById.get(targetPersonId);
  return {
    ancestorId: bestMatch.ancestorId,
    isBlood: true,
    label: buildBloodRelationshipLabel({
      viewerDepth: bestMatch.viewerDepth,
      targetDepth: bestMatch.targetDepth,
      targetGender: target?.gender,
    }),
    viewerDepth: bestMatch.viewerDepth,
    targetDepth: bestMatch.targetDepth,
  };
}

function collectBloodSiblingIds(personId, bloodParentsByChild, bloodChildrenByParent) {
  const siblingIds = new Set();
  for (const parentId of getMapSetValues(bloodParentsByChild, personId)) {
    for (const childId of getMapSetValues(bloodChildrenByParent, parentId)) {
      if (childId !== personId) {
        siblingIds.add(childId);
      }
    }
  }
  return Array.from(siblingIds);
}

function collectKnownSiblingIds(
  personId,
  bloodParentsByChild,
  bloodChildrenByParent,
  siblingsByPerson,
) {
  const siblingIds = new Set(
    collectBloodSiblingIds(personId, bloodParentsByChild, bloodChildrenByParent),
  );
  for (const siblingId of getMapSetValues(siblingsByPerson, personId)) {
    if (siblingId !== personId) {
      siblingIds.add(siblingId);
    }
  }
  return Array.from(siblingIds);
}

function buildParentInLawLabel({spouseGender, targetGender}) {
  if (isFemaleGender(spouseGender)) {
    return genderAwareWord(targetGender, {
      male: "Тесть",
      female: "Теща",
      neutral: "Родитель жены",
    });
  }
  if (isMaleGender(spouseGender)) {
    return genderAwareWord(targetGender, {
      male: "Свекор",
      female: "Свекровь",
      neutral: "Родитель мужа",
    });
  }
  return genderAwareWord(targetGender, {
    male: "Родитель супруга",
    female: "Родительница супруга",
    neutral: "Родитель супруга",
  });
}

function buildSiblingInLawLabel({spouseGender, targetGender}) {
  if (isFemaleGender(spouseGender)) {
    return genderAwareWord(targetGender, {
      male: "Шурин",
      female: "Свояченица",
      neutral: "Родня жены",
    });
  }
  if (isMaleGender(spouseGender)) {
    return genderAwareWord(targetGender, {
      male: "Деверь",
      female: "Золовка",
      neutral: "Родня мужа",
    });
  }
  return genderAwareWord(targetGender, {
    male: "Брат супруга",
    female: "Сестра супруга",
    neutral: "Сиблинг супруга",
  });
}

function buildChildInLawLabel(targetGender) {
  return genderAwareWord(targetGender, {
    male: "Зять",
    female: "Невестка",
    neutral: "Родня по браку",
  });
}

function buildMatchmakerLabel(targetGender) {
  return genderAwareWord(targetGender, {
    male: "Сват",
    female: "Сватья",
    neutral: "Сват",
  });
}

function buildAffinalInheritedLabel(baseLabel, targetGender) {
  const normalizedLabel = String(baseLabel || "").trim().toLowerCase();
  if (!normalizedLabel) {
    return null;
  }
  if (
    normalizedLabel === "дядя" ||
    normalizedLabel === "тетя" ||
    normalizedLabel.startsWith("двоюродный дяд") ||
    normalizedLabel.startsWith("двоюродная тет")
  ) {
    if (normalizedLabel.startsWith("двоюрод")) {
      return buildCousinOlderGenerationLabel(1, targetGender);
    }
    return buildUncleAuntLabel(targetGender);
  }
  if (
    normalizedLabel.startsWith("двоюродный дед") ||
    normalizedLabel.startsWith("двоюродная баб")
  ) {
    return buildGrandUncleAuntLabel(targetGender);
  }
  return null;
}

function computeAffinityRelationshipDescriptor({
  viewerPersonId,
  targetPersonId,
  peopleById,
  parentsByChild,
  childrenByParent,
  bloodParentsByChild,
  bloodChildrenByParent,
  currentUnionPartnersByPerson,
  siblingsByPerson,
}) {
  const viewer = peopleById.get(viewerPersonId);
  const target = peopleById.get(targetPersonId);
  if (!viewer || !target) {
    return null;
  }

  const viewerPartners = getMapSetValues(currentUnionPartnersByPerson, viewerPersonId);
  for (const spouseId of viewerPartners) {
    const spouse = peopleById.get(spouseId);
    if (!spouse) {
      continue;
    }
    if (hasMapSetValue(parentsByChild, spouseId, targetPersonId)) {
      return {
        label: buildParentInLawLabel({
          spouseGender: spouse.gender,
          targetGender: target.gender,
        }),
        isBlood: false,
      };
    }

    const spouseSiblingIds = collectKnownSiblingIds(
      spouseId,
      bloodParentsByChild,
      bloodChildrenByParent,
      siblingsByPerson,
    );
    if (spouseSiblingIds.includes(targetPersonId)) {
      return {
        label: buildSiblingInLawLabel({
          spouseGender: spouse.gender,
          targetGender: target.gender,
        }),
        isBlood: false,
      };
    }

    if (
      hasMapSetValue(childrenByParent, spouseId, targetPersonId) &&
      !hasMapSetValue(childrenByParent, viewerPersonId, targetPersonId)
    ) {
      return {
        label: describeDirectRelationLabel({
          relationType: "stepchild",
          gender: target.gender,
          parentSetType: "step",
        }),
        isBlood: false,
      };
    }

    for (const spouseSiblingId of spouseSiblingIds) {
      const spouseSibling = peopleById.get(spouseSiblingId);
      if (!spouseSibling) {
        continue;
      }
      if (
        hasMapSetValue(currentUnionPartnersByPerson, spouseSiblingId, targetPersonId) &&
        isMaleGender(target.gender) &&
        isFemaleGender(spouseSibling.gender)
      ) {
        return {
          label: "Свояк",
          isBlood: false,
        };
      }
    }
  }

  for (const parentId of getMapSetValues(parentsByChild, viewerPersonId)) {
    if (
      hasMapSetValue(currentUnionPartnersByPerson, parentId, targetPersonId) &&
      !hasMapSetValue(parentsByChild, viewerPersonId, targetPersonId)
    ) {
      return {
        label: describeDirectRelationLabel({
          relationType: "stepparent",
          gender: target.gender,
          parentSetType: "step",
        }),
        isBlood: false,
      };
    }
  }

  for (const childId of getMapSetValues(childrenByParent, viewerPersonId)) {
    if (hasMapSetValue(currentUnionPartnersByPerson, childId, targetPersonId)) {
      return {
        label: buildChildInLawLabel(target.gender),
        isBlood: false,
      };
    }

    for (const childPartnerId of getMapSetValues(currentUnionPartnersByPerson, childId)) {
      if (
        childPartnerId !== viewerPersonId &&
        hasMapSetValue(parentsByChild, childPartnerId, targetPersonId)
      ) {
        return {
          label: buildMatchmakerLabel(target.gender),
          isBlood: false,
        };
      }
    }
  }

  for (const siblingId of collectKnownSiblingIds(
    viewerPersonId,
    bloodParentsByChild,
    bloodChildrenByParent,
    siblingsByPerson,
  )) {
    if (hasMapSetValue(currentUnionPartnersByPerson, siblingId, targetPersonId)) {
      return {
        label: buildChildInLawLabel(target.gender),
        isBlood: false,
      };
    }
  }

  for (const partnerId of getMapSetValues(currentUnionPartnersByPerson, targetPersonId)) {
    const partnerBloodDescriptor = computeBloodRelationshipDescriptor(
      viewerPersonId,
      partnerId,
      bloodParentsByChild,
      peopleById,
    );
    const inheritedLabel = buildAffinalInheritedLabel(
      partnerBloodDescriptor?.label,
      target.gender,
    );
    if (inheritedLabel) {
      return {
        label: inheritedLabel,
        isBlood: false,
      };
    }
  }

  return null;
}

function relationTypeAlongPath(directRelations, fromPersonId, toPersonId) {
  const relation = directRelations.get(buildSortedIdKey([fromPersonId, toPersonId]));
  if (!relation) {
    return null;
  }
  return String(relationTypeForPerson(relation, toPersonId) || "")
    .trim()
    .toLowerCase() || null;
}

function buildSparsePathRelationshipDescriptor({
  targetPersonId,
  primaryPathPersonIds,
  directRelations,
  peopleById,
}) {
  if (!Array.isArray(primaryPathPersonIds) || primaryPathPersonIds.length < 2) {
    return null;
  }

  const target = peopleById.get(String(targetPersonId || "").trim());
  if (!target) {
    return null;
  }

  const edgeTypes = [];
  for (let index = 0; index < primaryPathPersonIds.length - 1; index += 1) {
    const relationType = relationTypeAlongPath(
      directRelations,
      primaryPathPersonIds[index],
      primaryPathPersonIds[index + 1],
    );
    if (!relationType) {
      return null;
    }
    edgeTypes.push(relationType);
  }

  if (edgeTypes.length === 2 && edgeTypes[0] === "parent" && edgeTypes[1] === "sibling") {
    return {
      label: buildUncleAuntLabel(target.gender),
      isBlood: true,
    };
  }

  if (
    edgeTypes.length === 3 &&
    edgeTypes[0] === "parent" &&
    edgeTypes[1] === "sibling" &&
    edgeTypes[2] === "child"
  ) {
    return {
      label: genderAwareWord(target.gender, {
        male: "Двоюродный брат",
        female: "Двоюродная сестра",
        neutral: "Двоюродный родственник",
      }),
      isBlood: true,
    };
  }

  if (
    edgeTypes.length === 2 &&
    edgeTypes[0] === "sibling" &&
    edgeTypes[1] === "child"
  ) {
    return {
      label: buildNephewNieceLabel(target.gender),
      isBlood: true,
    };
  }

  if (
    edgeTypes.length === 3 &&
    edgeTypes[0] === "sibling" &&
    edgeTypes[1] === "child" &&
    edgeTypes[2] === "child"
  ) {
    return {
      label: buildGrandNephewNieceLabel(target.gender),
      isBlood: true,
    };
  }

  if (
    edgeTypes.length === 3 &&
    edgeTypes[0] === "parent" &&
    edgeTypes[1] === "parent" &&
    edgeTypes[2] === "sibling"
  ) {
    return {
      label: buildGrandUncleAuntLabel(target.gender),
      isBlood: true,
    };
  }

  const lastEdgeType = edgeTypes[edgeTypes.length - 1];
  const olderGenerationChain = edgeTypes.slice(0, -1);
  if (
    isUnionRelationType(lastEdgeType) &&
    olderGenerationChain.length >= 2 &&
    olderGenerationChain[olderGenerationChain.length - 1] === "sibling" &&
    olderGenerationChain.slice(0, -1).every((relationType) => relationType === "parent")
  ) {
    const parentDepth = olderGenerationChain.length - 1;
    if (parentDepth === 1) {
      return {
        label: buildUncleAuntLabel(target.gender),
        isBlood: false,
      };
    }
    if (parentDepth === 2) {
      return {
        label: buildGrandUncleAuntLabel(target.gender),
        isBlood: false,
      };
    }
  }

  return null;
}

function buildFamilyUnitLabel({adultIds, peopleById}) {
  const adults = (Array.isArray(adultIds) ? adultIds : [])
    .map((personId) => peopleById.get(personId))
    .filter(Boolean);

  if (adults.length === 0) {
    return "Семья";
  }

  const surnames = Array.from(
    new Set(
      adults
        .map((person) => extractSurnameFromName(person.name))
        .filter(Boolean),
    ),
  );
  if (surnames.length === 1) {
    return `Ветка ${surnames[0]}`;
  }

  if (adults.length === 1) {
    return `Семья ${adults[0].name}`;
  }

  return `Семья ${adults[0].name} и ${adults[1].name}`;
}

function buildBranchLabel({rootUnit, peopleById}) {
  if (!rootUnit) {
    return "Семья";
  }
  return buildFamilyUnitLabel({
    adultIds: rootUnit.adultIds,
    peopleById,
  });
}

function comparePathCost(left, right) {
  if (!left && !right) {
    return 0;
  }
  if (!left) {
    return 1;
  }
  if (!right) {
    return -1;
  }
  if (left.nonBlood !== right.nonBlood) {
    return left.nonBlood - right.nonBlood;
  }
  if (left.length !== right.length) {
    return left.length - right.length;
  }
  return left.pastUnion - right.pastUnion;
}

function buildTraversalGraph(relations) {
  const adjacency = new Map();
  const parentsByChild = new Map();
  const bloodParentsByChild = new Map();
  const childrenByParent = new Map();
  const bloodChildrenByParent = new Map();
  const currentUnionPartnersByPerson = new Map();
  const anyUnionPartnersByPerson = new Map();
  const siblingsByPerson = new Map();
  const directRelations = new Map();

  for (const relation of Array.isArray(relations) ? relations : []) {
    const pairKey = buildSortedIdKey([relation.person1Id, relation.person2Id]);
    if (pairKey) {
      directRelations.set(pairKey, relation);
    }

    const parentId = parentIdFromRelation(relation);
    const childId = childIdFromRelation(relation);
    if (parentId && childId) {
      addMapSetValue(parentsByChild, childId, parentId);
      addMapSetValue(childrenByParent, parentId, childId);
      if (isBloodParentSetType(relation.parentSetType)) {
        addMapSetValue(bloodParentsByChild, childId, parentId);
        addMapSetValue(bloodChildrenByParent, parentId, childId);
      }
      if (!adjacency.has(parentId)) {
        adjacency.set(parentId, []);
      }
      if (!adjacency.has(childId)) {
        adjacency.set(childId, []);
      }
      adjacency.get(parentId).push({
        toId: childId,
        kind: "child",
        isBlood: isBloodParentSetType(relation.parentSetType),
        isPast: false,
      });
      adjacency.get(childId).push({
        toId: parentId,
        kind: "parent",
        isBlood: isBloodParentSetType(relation.parentSetType),
        isPast: false,
      });
    }

    if (isUnionRelation(relation)) {
      const isPast = normalizeUnionStatus(relation.unionStatus, {
        relationType: relation.relation1to2 || relation.relation2to1,
        divorceDate: relation.divorceDate,
      }) === "past";
      addMapSetValue(anyUnionPartnersByPerson, relation.person1Id, relation.person2Id);
      addMapSetValue(anyUnionPartnersByPerson, relation.person2Id, relation.person1Id);
      if (!isPast) {
        addMapSetValue(currentUnionPartnersByPerson, relation.person1Id, relation.person2Id);
        addMapSetValue(currentUnionPartnersByPerson, relation.person2Id, relation.person1Id);
      }
      if (!adjacency.has(relation.person1Id)) {
        adjacency.set(relation.person1Id, []);
      }
      if (!adjacency.has(relation.person2Id)) {
        adjacency.set(relation.person2Id, []);
      }
      adjacency.get(relation.person1Id).push({
        toId: relation.person2Id,
        kind: "union",
        isBlood: false,
        isPast,
      });
      adjacency.get(relation.person2Id).push({
        toId: relation.person1Id,
        kind: "union",
        isBlood: false,
        isPast,
      });
    }

    if (
      String(relation.relation1to2 || "").trim().toLowerCase() === "sibling" &&
      String(relation.relation2to1 || "").trim().toLowerCase() === "sibling"
    ) {
      addMapSetValue(siblingsByPerson, relation.person1Id, relation.person2Id);
      addMapSetValue(siblingsByPerson, relation.person2Id, relation.person1Id);
      if (!adjacency.has(relation.person1Id)) {
        adjacency.set(relation.person1Id, []);
      }
      if (!adjacency.has(relation.person2Id)) {
        adjacency.set(relation.person2Id, []);
      }
      adjacency.get(relation.person1Id).push({
        toId: relation.person2Id,
        kind: "sibling",
        isBlood: true,
        isPast: false,
      });
      adjacency.get(relation.person2Id).push({
        toId: relation.person1Id,
        kind: "sibling",
        isBlood: true,
        isPast: false,
      });
    }
  }

  return {
    adjacency,
    parentsByChild,
    bloodParentsByChild,
    childrenByParent,
    bloodChildrenByParent,
    currentUnionPartnersByPerson,
    anyUnionPartnersByPerson,
    siblingsByPerson,
    directRelations,
  };
}

function buildBestPathIndex(startPersonId, adjacency) {
  const costs = new Map();
  const pathCounts = new Map();
  const predecessors = new Map();
  costs.set(startPersonId, {
    nonBlood: 0,
    length: 0,
    pastUnion: 0,
  });
  pathCounts.set(startPersonId, 1);
  const pending = [{
    personId: startPersonId,
    cost: {
      nonBlood: 0,
      length: 0,
      pastUnion: 0,
    },
  }];

  while (pending.length > 0) {
    pending.sort((left, right) => comparePathCost(left.cost, right.cost));
    const current = pending.shift();
    if (!current) {
      continue;
    }
    const previousBest = costs.get(current.personId);
    if (previousBest && comparePathCost(current.cost, previousBest) > 0) {
      continue;
    }

    for (const edge of adjacency.get(current.personId) || []) {
      const nextCost = {
        nonBlood: current.cost.nonBlood + (edge.isBlood ? 0 : 1),
        length: current.cost.length + 1,
        pastUnion: current.cost.pastUnion + (edge.isPast ? 1 : 0),
      };
      const existingCost = costs.get(edge.toId);
      const comparison = comparePathCost(nextCost, existingCost);
      if (comparison < 0 || existingCost === undefined) {
        costs.set(edge.toId, nextCost);
        if (edge.toId !== startPersonId) {
          predecessors.set(edge.toId, current.personId);
        }
        pathCounts.set(edge.toId, pathCounts.get(current.personId) || 1);
        pending.push({
          personId: edge.toId,
          cost: nextCost,
        });
      } else if (comparison === 0) {
        pathCounts.set(
          edge.toId,
          (pathCounts.get(edge.toId) || 0) + (pathCounts.get(current.personId) || 1),
        );
      }
    }
  }

  return {
    costs,
    pathCounts,
    predecessors,
  };
}

function reconstructPersonPath(targetPersonId, predecessors) {
  const path = [];
  const seen = new Set();
  let currentId = targetPersonId;
  while (currentId && !seen.has(currentId)) {
    path.unshift(currentId);
    seen.add(currentId);
    currentId = predecessors.get(currentId);
  }
  return path;
}

function normalizeTreeGraph(treeId, persons = [], relations = []) {
  const normalizedPeople = (Array.isArray(persons) ? persons : [])
    .filter((person) => person.treeId === treeId)
    .map((person) => structuredClone(person));
  const normalizedRelations = (Array.isArray(relations) ? relations : [])
    .filter((relation) => relation.treeId === treeId)
    .map((relation) => {
      const normalizedRelation = structuredClone(relation);
      const normalizedParentId = parentIdFromRelation(normalizedRelation);
      const normalizedChildId = childIdFromRelation(normalizedRelation);
      if (normalizedParentId && normalizedChildId) {
        normalizedRelation.parentSetType = normalizeParentSetType(
          normalizedRelation.parentSetType,
        );
        normalizedRelation.parentSetId =
          normalizeNullableString(normalizedRelation.parentSetId) || null;
        normalizedRelation.isPrimaryParentSet =
          normalizedRelation.isPrimaryParentSet !== false;
      } else {
        normalizedRelation.parentSetType = null;
        normalizedRelation.parentSetId = null;
        normalizedRelation.isPrimaryParentSet = null;
      }

      if (isUnionRelation(normalizedRelation)) {
        const relationType =
          normalizedRelation.relation1to2 || normalizedRelation.relation2to1;
        normalizedRelation.unionType = normalizeUnionType(
          normalizedRelation.unionType,
          {relationType},
        );
        normalizedRelation.unionStatus = normalizeUnionStatus(
          normalizedRelation.unionStatus,
          {
            relationType,
            divorceDate: normalizedRelation.divorceDate,
          },
        );
        normalizedRelation.unionId =
          normalizeNullableString(normalizedRelation.unionId) ||
          `union:${treeId}:${buildSortedIdKey([
            normalizedRelation.person1Id,
            normalizedRelation.person2Id,
          ])}:${normalizedRelation.unionType}:${normalizedRelation.unionStatus}`;
      } else {
        normalizedRelation.unionType = null;
        normalizedRelation.unionStatus = null;
        normalizedRelation.unionId = null;
      }

      return normalizedRelation;
    });

  const relationGroups = new Map();
  for (const relation of normalizedRelations) {
    const childId = childIdFromRelation(relation);
    if (!childId) {
      continue;
    }
    const groupKey = `${childId}:${relation.parentSetType}`;
    if (!relationGroups.has(groupKey)) {
      relationGroups.set(groupKey, []);
    }
    relationGroups.get(groupKey).push(relation);
  }

  for (const [groupKey, groupRelations] of relationGroups.entries()) {
    const [childId, parentSetType] = groupKey.split(":");
    const explicitIds = Array.from(
      new Set(
        groupRelations
          .map((relation) => normalizeNullableString(relation.parentSetId))
          .filter(Boolean),
      ),
    );

    if (explicitIds.length === 0) {
      const uniqueParentIds = Array.from(
        new Set(groupRelations.map((relation) => parentIdFromRelation(relation)).filter(Boolean)),
      );
      if (uniqueParentIds.length <= 2) {
        const sharedId = `ps:${treeId}:${childId}:${parentSetType}:primary`;
        for (const relation of groupRelations) {
          relation.parentSetId = sharedId;
          relation.isPrimaryParentSet = true;
        }
      } else {
        let index = 0;
        for (const relation of groupRelations) {
          index += 1;
          relation.parentSetId = `ps:${treeId}:${childId}:${parentSetType}:${index}`;
          relation.isPrimaryParentSet = index === 1;
        }
      }
      continue;
    }

    const primaryId =
      groupRelations.find((relation) => relation.isPrimaryParentSet)?.parentSetId ||
      explicitIds[0];
    const primaryParentIds = new Set(
      groupRelations
        .filter((relation) => relation.parentSetId === primaryId)
        .map((relation) => parentIdFromRelation(relation))
        .filter(Boolean),
    );
    let generatedIndex = explicitIds.length;
    for (const relation of groupRelations) {
      if (relation.parentSetId) {
        relation.isPrimaryParentSet = relation.parentSetId === primaryId;
        continue;
      }
      const parentId = parentIdFromRelation(relation);
      if (primaryParentIds.has(parentId) || primaryParentIds.size < 2) {
        relation.parentSetId = primaryId;
        relation.isPrimaryParentSet = true;
        if (parentId) {
          primaryParentIds.add(parentId);
        }
      } else {
        generatedIndex += 1;
        relation.parentSetId =
          `ps:${treeId}:${childId}:${parentSetType}:${generatedIndex}`;
        relation.isPrimaryParentSet = false;
      }
    }
  }

  return {
    people: normalizedPeople,
    relations: normalizedRelations,
  };
}

function buildDisplayTreeRelations(treeId, relations = []) {
  const normalizedRelations = (Array.isArray(relations) ? relations : []).map((relation) =>
    structuredClone(relation),
  );
  const anyUnionPartnersByPerson = new Map();
  const primaryParentGroups = new Map();
  const childIdsByParentAndType = new Map();
  const existingParentRelationKeys = new Set();

  for (const relation of normalizedRelations) {
    if (isUnionRelation(relation)) {
      addMapSetValue(anyUnionPartnersByPerson, relation.person1Id, relation.person2Id);
      addMapSetValue(anyUnionPartnersByPerson, relation.person2Id, relation.person1Id);
    }

    const parentId = parentIdFromRelation(relation);
    const childId = childIdFromRelation(relation);
    if (!parentId || !childId) {
      continue;
    }
    const normalizedParentSetType = normalizeParentSetType(relation.parentSetType);
    existingParentRelationKeys.add(`${parentId}:${childId}:${normalizedParentSetType}`);
    if (relation.isPrimaryParentSet === false || !isBloodParentSetType(normalizedParentSetType)) {
      continue;
    }
    const groupKey = `${childId}:${normalizedParentSetType}`;
    if (!primaryParentGroups.has(groupKey)) {
      primaryParentGroups.set(groupKey, []);
    }
    primaryParentGroups.get(groupKey).push(relation);
    addMapSetValue(
      childIdsByParentAndType,
      `${parentId}:${normalizedParentSetType}`,
      childId,
    );
  }

  const inferredRelations = [];
  for (const groupRelations of primaryParentGroups.values()) {
    const uniqueParentIds = Array.from(
      new Set(groupRelations.map((relation) => parentIdFromRelation(relation)).filter(Boolean)),
    );
    if (uniqueParentIds.length !== 1) {
      continue;
    }

    const knownParentId = uniqueParentIds[0];
    const childId = childIdFromRelation(groupRelations[0]);
    const parentSetType = normalizeParentSetType(groupRelations[0].parentSetType);
    if (!knownParentId || !childId || !parentSetType) {
      continue;
    }

    const candidateSupport = new Map();
    for (const siblingChildId of getMapSetValues(
      childIdsByParentAndType,
      `${knownParentId}:${parentSetType}`,
    )) {
      if (siblingChildId === childId) {
        continue;
      }
      const siblingRelations =
        primaryParentGroups.get(`${siblingChildId}:${parentSetType}`) || [];
      const siblingParentIds = Array.from(
        new Set(
          siblingRelations
            .map((relation) => parentIdFromRelation(relation))
            .filter(Boolean),
        ),
      );
      if (siblingParentIds.length !== 2 || !siblingParentIds.includes(knownParentId)) {
        continue;
      }
      const candidateParentId = siblingParentIds.find((id) => id !== knownParentId);
      if (
        !candidateParentId ||
        !hasMapSetValue(anyUnionPartnersByPerson, knownParentId, candidateParentId)
      ) {
        continue;
      }
      candidateSupport.set(
        candidateParentId,
        (candidateSupport.get(candidateParentId) || 0) + 1,
      );
    }

    if (candidateSupport.size !== 1) {
      continue;
    }
    const [[candidateParentId]] = Array.from(candidateSupport.entries());
    const inferredKey = `${candidateParentId}:${childId}:${parentSetType}`;
    if (existingParentRelationKeys.has(inferredKey)) {
      continue;
    }

    const templateRelation = groupRelations[0];
    inferredRelations.push({
      ...structuredClone(templateRelation),
      id: `inferred:${treeId}:${candidateParentId}:${childId}:${parentSetType}`,
      person1Id: candidateParentId,
      person2Id: childId,
      relation1to2: "parent",
      relation2to1: "child",
      isConfirmed: true,
      customRelationLabel1to2: null,
      customRelationLabel2to1: null,
      parentSetType,
      parentSetId: templateRelation.parentSetId,
      isPrimaryParentSet: true,
      unionType: null,
      unionStatus: null,
      unionId: null,
      inferredDisplayOnly: true,
    });
    existingParentRelationKeys.add(inferredKey);
  }

  return [...normalizedRelations, ...inferredRelations];
}

function buildFamilyUnits(treeId, persons = [], relations = []) {
  const normalizedGraph = normalizeTreeGraph(treeId, persons, relations);
  const displayRelations = buildDisplayTreeRelations(
    treeId,
    normalizedGraph.relations,
  );
  const peopleById = new Map(
    normalizedGraph.people.map((person) => [String(person.id || "").trim(), person]),
  );
  const familyUnits = [];
  const representedUnionIds = new Set();
  const parentSetGroups = new Map();

  for (const relation of displayRelations) {
    const parentId = parentIdFromRelation(relation);
    const childId = childIdFromRelation(relation);
    if (!parentId || !childId || !relation.parentSetId) {
      continue;
    }
    if (!parentSetGroups.has(relation.parentSetId)) {
      parentSetGroups.set(relation.parentSetId, {
        id: relation.parentSetId,
        parentSetType: relation.parentSetType,
        isPrimaryParentSet: relation.isPrimaryParentSet !== false,
        adultIds: new Set(),
        childIds: new Set(),
        relationIds: new Set(),
      });
    }
    const group = parentSetGroups.get(relation.parentSetId);
    group.adultIds.add(parentId);
    group.childIds.add(childId);
    group.relationIds.add(relation.id);
    if (relation.isPrimaryParentSet === false) {
      group.isPrimaryParentSet = false;
    }
  }

  const mergedParentFamilyGroups = new Map();

  for (const group of parentSetGroups.values()) {
    const adultIds = Array.from(group.adultIds).sort((left, right) =>
      left.localeCompare(right),
    );
    const childIds = Array.from(group.childIds).sort((left, right) =>
      left.localeCompare(right),
    );
    const matchingUnion = adultIds.length >= 2
      ? displayRelations.find((relation) => {
          return (
            relation.unionId &&
            buildSortedIdKey([relation.person1Id, relation.person2Id]) ===
              buildSortedIdKey(adultIds)
          );
        })
      : null;
    const mergeKey = [
      buildSortedIdKey(adultIds),
      matchingUnion?.unionId || `single:${buildSortedIdKey(adultIds)}`,
      normalizeParentSetType(group.parentSetType),
      group.isPrimaryParentSet ? "primary" : "secondary",
    ].join("|");

    if (!mergedParentFamilyGroups.has(mergeKey)) {
      mergedParentFamilyGroups.set(mergeKey, {
        rootParentSetIds: new Set(),
        adultIds: new Set(),
        childIds: new Set(),
        relationIds: new Set(),
        unionId: matchingUnion?.unionId || null,
        unionType:
          matchingUnion?.unionType || (adultIds.length > 1 ? "other" : "single"),
        unionStatus: matchingUnion?.unionStatus || "current",
        parentSetType: group.parentSetType,
        isPrimaryParentSet: group.isPrimaryParentSet,
      });
    }

    const mergedGroup = mergedParentFamilyGroups.get(mergeKey);
    mergedGroup.rootParentSetIds.add(group.id);
    for (const adultId of adultIds) {
      mergedGroup.adultIds.add(adultId);
    }
    for (const childId of childIds) {
      mergedGroup.childIds.add(childId);
    }
    for (const relationId of group.relationIds) {
      mergedGroup.relationIds.add(relationId);
    }
  }

  for (const mergedGroup of mergedParentFamilyGroups.values()) {
    const adultIds = Array.from(mergedGroup.adultIds).sort((left, right) =>
      left.localeCompare(right),
    );
    const childIds = Array.from(mergedGroup.childIds).sort((left, right) =>
      left.localeCompare(right),
    );
    const relationIds = Array.from(mergedGroup.relationIds).sort((left, right) =>
      left.localeCompare(right),
    );
    const rootParentSetIds = Array.from(mergedGroup.rootParentSetIds).sort(
      (left, right) => left.localeCompare(right),
    );
    const rootParentSetId = rootParentSetIds[0] || null;

    if (mergedGroup.unionId) {
      representedUnionIds.add(mergedGroup.unionId);
    }

    familyUnits.push({
      id:
        rootParentSetIds.length <= 1
          ? `family:${rootParentSetId}`
          : `family:merged:${treeId}:${buildSortedIdKey(rootParentSetIds)}`,
      rootParentSetId,
      adultIds,
      childIds,
      relationIds,
      unionId: mergedGroup.unionId,
      unionType: mergedGroup.unionType,
      unionStatus: mergedGroup.unionStatus,
      parentSetType: mergedGroup.parentSetType,
      isPrimaryParentSet: mergedGroup.isPrimaryParentSet,
      label: buildFamilyUnitLabel({adultIds, peopleById}),
    });
  }

  for (const relation of displayRelations) {
    if (!isUnionRelation(relation) || !relation.unionId) {
      continue;
    }
    if (representedUnionIds.has(relation.unionId)) {
      continue;
    }
    representedUnionIds.add(relation.unionId);
    const adultIds = [relation.person1Id, relation.person2Id].sort((left, right) =>
      left.localeCompare(right),
    );
    familyUnits.push({
      id: `family:${relation.unionId}`,
      rootParentSetId: null,
      adultIds,
      childIds: [],
      relationIds: [relation.id],
      unionId: relation.unionId,
      unionType: relation.unionType,
      unionStatus: relation.unionStatus,
      parentSetType: null,
      isPrimaryParentSet: false,
      label: buildFamilyUnitLabel({adultIds, peopleById}),
    });
  }

  const coveredPersonIds = new Set(
    familyUnits.flatMap((unit) => [...unit.adultIds, ...unit.childIds]),
  );
  for (const person of normalizedGraph.people) {
    if (coveredPersonIds.has(person.id)) {
      continue;
    }
    familyUnits.push({
      id: `family:solo:${person.id}`,
      rootParentSetId: null,
      adultIds: [person.id],
      childIds: [],
      relationIds: [],
      unionId: null,
      unionType: "single",
      unionStatus: "current",
      parentSetType: null,
      isPrimaryParentSet: false,
      label: buildFamilyUnitLabel({
        adultIds: [person.id],
        peopleById,
      }),
    });
  }

  return familyUnits;
}

function buildGenerationRows(persons, relations, familyUnits) {
  const normalizedPersons = Array.isArray(persons) ? persons : [];
  const normalizedRelations = Array.isArray(relations) ? relations : [];
  const parentsByChild = new Map();
  const siblingIdsByPerson = new Map();

  for (const relation of normalizedRelations) {
    if (
      String(relation.relation1to2 || "").trim().toLowerCase() === "sibling" &&
      String(relation.relation2to1 || "").trim().toLowerCase() === "sibling"
    ) {
      addMapSetValue(siblingIdsByPerson, relation.person1Id, relation.person2Id);
      addMapSetValue(siblingIdsByPerson, relation.person2Id, relation.person1Id);
    }

    const parentId = parentIdFromRelation(relation);
    const childId = childIdFromRelation(relation);
    if (!parentId || !childId || relation.isPrimaryParentSet === false) {
      continue;
    }
    if (!parentsByChild.has(childId)) {
      parentsByChild.set(childId, new Set());
    }
    parentsByChild.get(childId).add(parentId);
  }

  const levels = new Map();
  const visiting = new Set();
  const resolveLevel = (personId) => {
    if (levels.has(personId)) {
      return levels.get(personId);
    }
    if (visiting.has(personId)) {
      return 0;
    }
    visiting.add(personId);
    const parents = Array.from(parentsByChild.get(personId) || []);
    const level =
      parents.length === 0
        ? 0
        : Math.max(...parents.map((parentId) => resolveLevel(parentId))) + 1;
    visiting.delete(personId);
    levels.set(personId, level);
    return level;
  };

  for (const person of normalizedPersons) {
    resolveLevel(person.id);
  }

  const normalizedFamilyUnits = Array.isArray(familyUnits) ? familyUnits : [];
  const maxIterations = normalizedPersons.length + normalizedFamilyUnits.length + 8;
  let changed = true;
  let iteration = 0;
  while (changed && iteration < maxIterations) {
    changed = false;
    iteration += 1;

    for (const unit of normalizedFamilyUnits) {
      const adultIds = (Array.isArray(unit?.adultIds) ? unit.adultIds : []).filter(Boolean);
      const childIds = (Array.isArray(unit?.childIds) ? unit.childIds : []).filter(Boolean);
      if (adultIds.length === 0 && childIds.length === 0) {
        continue;
      }

      let desiredAdultLevel = null;
      if (childIds.length > 0) {
        desiredAdultLevel = Math.max(
          0,
          Math.min(...childIds.map((personId) => levels.get(personId) ?? 0)) - 1,
        );
      } else if (adultIds.length > 0) {
        desiredAdultLevel = Math.max(
          ...adultIds.map((personId) => levels.get(personId) ?? 0),
        );
      }

      if (desiredAdultLevel !== null) {
        for (const adultId of adultIds) {
          if ((levels.get(adultId) ?? 0) !== desiredAdultLevel) {
            levels.set(adultId, desiredAdultLevel);
            changed = true;
          }
        }
      }

      if (desiredAdultLevel !== null && childIds.length > 0) {
        const desiredChildLevel = desiredAdultLevel + 1;
        for (const childId of childIds) {
          if ((levels.get(childId) ?? 0) !== desiredChildLevel) {
            levels.set(childId, desiredChildLevel);
            changed = true;
          }
        }
      }
    }

    for (const [personId, siblingIds] of siblingIdsByPerson.entries()) {
      const targetLevel = Math.max(
        levels.get(personId) ?? 0,
        ...Array.from(siblingIds).map((siblingId) => levels.get(siblingId) ?? 0),
      );
      if ((levels.get(personId) ?? 0) !== targetLevel) {
        levels.set(personId, targetLevel);
        changed = true;
      }
      for (const siblingId of siblingIds) {
        if ((levels.get(siblingId) ?? 0) !== targetLevel) {
          levels.set(siblingId, targetLevel);
          changed = true;
        }
      }
    }
  }

  const minLevel = Math.min(0, ...Array.from(levels.values()));
  if (minLevel < 0) {
    for (const [personId, level] of levels.entries()) {
      levels.set(personId, level - minLevel);
    }
  }

  const maxLevel = Math.max(0, ...Array.from(levels.values()));
  const rows = [];
  for (let row = 0; row <= maxLevel; row += 1) {
    const personIds = normalizedPersons
      .filter((person) => levels.get(person.id) === row)
      .map((person) => person.id);
    const familyUnitIds = (Array.isArray(familyUnits) ? familyUnits : [])
      .filter((unit) =>
        unit.adultIds.some((personId) => personIds.includes(personId)) ||
        unit.childIds.some((personId) => personIds.includes(personId)),
      )
      .map((unit) => unit.id);
    let label = `Поколение ${row + 1}`;
    if (maxLevel === 0) {
      label = "Семья";
    } else if (row === 0) {
      label = "Старшее поколение";
    } else if (row === maxLevel) {
      label = "Младшее поколение";
    }
    rows.push({
      row,
      label,
      personIds,
      familyUnitIds: Array.from(new Set(familyUnitIds)),
    });
  }

  return rows;
}

function describeParentSetTypeLabelRu(parentSetType) {
  switch (normalizeParentSetType(parentSetType)) {
    case "biological":
      return "биологические родители";
    case "adoptive":
      return "усыновители";
    case "foster":
      return "приемная семья";
    case "guardian":
      return "опекуны";
    case "step":
      return "неродные родители";
    case "unknown":
      return "родители";
    default:
      return "родители";
  }
}

function buildGraphWarnings({
  persons = [],
  relations = [],
  familyUnits = [],
}) {
  const normalizedPersons = Array.isArray(persons) ? persons : [];
  const normalizedRelations = Array.isArray(relations) ? relations : [];
  const normalizedFamilyUnits = Array.isArray(familyUnits) ? familyUnits : [];
  const peopleById = new Map(
    normalizedPersons.map((person) => [String(person.id || "").trim(), person]),
  );
  const warnings = [];
  const emittedWarningIds = new Set();
  const pushWarning = (warning) => {
    const warningId = String(warning?.id || "").trim();
    if (!warningId || emittedWarningIds.has(warningId)) {
      return;
    }
    emittedWarningIds.add(warningId);
    warnings.push({
      id: warningId,
      code: String(warning.code || "").trim() || "graph_warning",
      severity: String(warning.severity || "").trim() || "warning",
      message: String(warning.message || "").trim() || "Дерево требует проверки.",
      hint: normalizeNullableString(warning.hint),
      personIds: Array.from(
        new Set((Array.isArray(warning.personIds) ? warning.personIds : []).filter(Boolean)),
      ),
      familyUnitIds: Array.from(
        new Set(
          (Array.isArray(warning.familyUnitIds) ? warning.familyUnitIds : []).filter(Boolean),
        ),
      ),
      relationIds: Array.from(
        new Set((Array.isArray(warning.relationIds) ? warning.relationIds : []).filter(Boolean)),
      ),
    });
  };

  const primaryParentGroups = new Map();
  for (const relation of normalizedRelations) {
    const parentId = parentIdFromRelation(relation);
    const childId = childIdFromRelation(relation);
    if (!parentId || !childId || relation.isPrimaryParentSet === false) {
      continue;
    }
    const normalizedParentSetType = normalizeParentSetType(relation.parentSetType) || "unknown";
    const normalizedParentSetId =
      normalizeNullableString(relation.parentSetId) ||
      `implicit:${childId}:${normalizedParentSetType}`;
    const groupKey = `${childId}:${normalizedParentSetType}`;
    if (!primaryParentGroups.has(groupKey)) {
      primaryParentGroups.set(groupKey, new Map());
    }
    const groupEntries = primaryParentGroups.get(groupKey);
    if (!groupEntries.has(normalizedParentSetId)) {
      groupEntries.set(normalizedParentSetId, {
        parentIds: new Set(),
        relationIds: new Set(),
      });
    }
    const groupEntry = groupEntries.get(normalizedParentSetId);
    groupEntry.parentIds.add(parentId);
    groupEntry.relationIds.add(relation.id);
  }

  for (const [groupKey, groupEntries] of primaryParentGroups.entries()) {
    if (groupEntries.size <= 1) {
      continue;
    }
    const [childId, parentSetType] = groupKey.split(":");
    const childName =
      peopleById.get(childId)?.name || peopleById.get(childId)?.displayName || childId;
    const allParentIds = [];
    const allRelationIds = [];
    const parentSetIds = new Set(groupEntries.keys());
    for (const entry of groupEntries.values()) {
      allParentIds.push(...Array.from(entry.parentIds));
      allRelationIds.push(...Array.from(entry.relationIds));
    }
    const familyUnitIds = normalizedFamilyUnits
      .filter((unit) => unit.rootParentSetId && parentSetIds.has(unit.rootParentSetId))
      .map((unit) => unit.id);
    pushWarning({
      id: `warning:primary-parent-set:${groupKey}`,
      code: "multiple_primary_parent_sets",
      severity: "warning",
      message: `У ${childName} несколько основных наборов родителей (${describeParentSetTypeLabelRu(
        parentSetType,
      )}).`,
      hint: "Оставьте только один основной набор, а остальные связи переведите в дополнительные.",
      personIds: [childId, ...allParentIds],
      familyUnitIds,
      relationIds: allRelationIds,
    });
  }

  for (const relation of normalizedRelations) {
    if (relation.inferredDisplayOnly !== true) {
      continue;
    }
    const parentId = parentIdFromRelation(relation);
    const childId = childIdFromRelation(relation);
    if (!parentId || !childId) {
      continue;
    }
    const parentName =
      peopleById.get(parentId)?.name || peopleById.get(parentId)?.displayName || parentId;
    const childName =
      peopleById.get(childId)?.name || peopleById.get(childId)?.displayName || childId;
    const familyUnitIds = normalizedFamilyUnits
      .filter((unit) => Array.isArray(unit.relationIds) && unit.relationIds.includes(relation.id))
      .map((unit) => unit.id);
    pushWarning({
      id: `warning:auto-parent-repair:${relation.id}`,
      code: "auto_repaired_parent_link",
      severity: "info",
      message: `Связь ${parentName} -> ${childName} достроена автоматически по данным дерева.`,
      hint: "Проверьте, что этот родитель относится к правильному набору родителей.",
      personIds: [parentId, childId],
      familyUnitIds,
      relationIds: [relation.id],
    });
  }

  const pairRelations = new Map();
  for (const relation of normalizedRelations) {
    const leftId = String(relation.person1Id || "").trim();
    const rightId = String(relation.person2Id || "").trim();
    if (!leftId || !rightId) {
      continue;
    }
    const pairKey = buildSortedIdKey([leftId, rightId]);
    if (!pairRelations.has(pairKey)) {
      pairRelations.set(pairKey, []);
    }
    pairRelations.get(pairKey).push(relation);
  }

  const relationCategoryForWarning = (relation) => {
    if (parentIdFromRelation(relation) && childIdFromRelation(relation)) {
      return "parentChild";
    }
    if (isUnionRelation(relation)) {
      return "union";
    }
    if (relation?.relation1to2 === "sibling" || relation?.relation2to1 === "sibling") {
      return "sibling";
    }
    return null;
  };

  for (const [pairKey, pairEntries] of pairRelations.entries()) {
    const categories = new Set(
      pairEntries.map(relationCategoryForWarning).filter(Boolean),
    );
    if (categories.size <= 1) {
      continue;
    }
    const [personAId, personBId] = pairKey.split(":");
    const personAName =
      peopleById.get(personAId)?.name || peopleById.get(personAId)?.displayName || personAId;
    const personBName =
      peopleById.get(personBId)?.name || peopleById.get(personBId)?.displayName || personBId;
    pushWarning({
      id: `warning:conflicting-direct-links:${pairKey}`,
      code: "conflicting_direct_links",
      severity: "warning",
      message: `Между ${personAName} и ${personBName} есть конфликтующие прямые связи.`,
      hint: "Для одной пары людей оставьте только один прямой тип связи: родитель, сиблинг или союз.",
      personIds: [personAId, personBId],
      relationIds: pairEntries.map((relation) => relation.id),
      familyUnitIds: normalizedFamilyUnits
        .filter((unit) =>
          unit.adultIds.includes(personAId) ||
          unit.adultIds.includes(personBId) ||
          unit.childIds.includes(personAId) ||
          unit.childIds.includes(personBId),
        )
        .map((unit) => unit.id),
    });
  }

  return warnings;
}

function resolveBranchBlocks(treeId, persons = [], relations = [], familyUnits = null) {
  const normalizedGraph = normalizeTreeGraph(treeId, persons, relations);
  const resolvedFamilyUnits = Array.isArray(familyUnits)
    ? familyUnits
    : buildFamilyUnits(treeId, normalizedGraph.people, normalizedGraph.relations);
  const peopleById = new Map(
    normalizedGraph.people.map((person) => [String(person.id || "").trim(), person]),
  );
  const adultUnitsByPersonId = new Map();

  for (const unit of resolvedFamilyUnits) {
    for (const adultId of unit.adultIds) {
      if (!adultUnitsByPersonId.has(adultId)) {
        adultUnitsByPersonId.set(adultId, []);
      }
      adultUnitsByPersonId.get(adultId).push(unit.id);
    }
  }

  return resolvedFamilyUnits.map((rootUnit) => {
    const visitedUnitIds = new Set([rootUnit.id]);
    const memberPersonIds = new Set([...rootUnit.adultIds, ...rootUnit.childIds]);
    const queue = [rootUnit.id];

    while (queue.length > 0) {
      const currentUnitId = queue.shift();
      const currentUnit = resolvedFamilyUnits.find((unit) => unit.id === currentUnitId);
      if (!currentUnit) {
        continue;
      }
      for (const childId of currentUnit.childIds) {
        memberPersonIds.add(childId);
        for (const descendantUnitId of adultUnitsByPersonId.get(childId) || []) {
          if (visitedUnitIds.has(descendantUnitId)) {
            continue;
          }
          visitedUnitIds.add(descendantUnitId);
          queue.push(descendantUnitId);
          const descendantUnit = resolvedFamilyUnits.find((unit) => unit.id === descendantUnitId);
          for (const adultId of descendantUnit?.adultIds || []) {
            memberPersonIds.add(adultId);
          }
          for (const descendantChildId of descendantUnit?.childIds || []) {
            memberPersonIds.add(descendantChildId);
          }
        }
      }
    }

    return {
      id: `branch:${rootUnit.id}`,
      rootUnitId: rootUnit.id,
      label: buildBranchLabel({rootUnit, peopleById}),
      memberPersonIds: Array.from(memberPersonIds).sort((left, right) =>
        left.localeCompare(right),
      ),
    };
  });
}

function chooseBranchBlockForPerson(snapshot, personId) {
  if (!snapshot || !personId) {
    return null;
  }

  const normalizedPersonId = String(personId || "").trim();
  const familyUnits = Array.isArray(snapshot.familyUnits) ? snapshot.familyUnits : [];
  const branchBlocks = Array.isArray(snapshot.branchBlocks) ? snapshot.branchBlocks : [];
  const candidateUnit =
    familyUnits.find((unit) => unit.adultIds.includes(normalizedPersonId)) ||
    familyUnits.find(
      (unit) =>
        unit.childIds.includes(normalizedPersonId) && unit.isPrimaryParentSet === true,
    ) ||
    familyUnits.find((unit) => unit.childIds.includes(normalizedPersonId)) ||
    familyUnits.find((unit) => unit.adultIds.includes(normalizedPersonId));
  if (!candidateUnit) {
    return null;
  }
  return (
    branchBlocks.find((branchBlock) => branchBlock.rootUnitId === candidateUnit.id) ||
    null
  );
}

function computeViewerKinships(treeId, persons = [], relations = [], viewerPersonId = null) {
  const normalizedViewerId = String(viewerPersonId || "").trim();
  if (!normalizedViewerId) {
    return [];
  }

  const normalizedGraph = normalizeTreeGraph(treeId, persons, relations);
  const peopleById = new Map(
    normalizedGraph.people.map((person) => [String(person.id || "").trim(), person]),
  );
  if (!peopleById.has(normalizedViewerId)) {
    return [];
  }

  const traversal = buildTraversalGraph(normalizedGraph.relations);
  const pathIndex = buildBestPathIndex(normalizedViewerId, traversal.adjacency);
  const descriptors = [];

  for (const person of normalizedGraph.people) {
    const personId = String(person.id || "").trim();
    if (!personId) {
      continue;
    }

    if (personId === normalizedViewerId) {
      descriptors.push({
        personId,
        primaryRelationLabel: "Это вы",
        isBlood: true,
        alternatePathCount: 0,
        pathSummary: person.name || personId,
        primaryPathPersonIds: [personId],
      });
      continue;
    }

    const directRelation =
      traversal.directRelations.get(buildSortedIdKey([normalizedViewerId, personId])) || null;
    const bloodDescriptor = computeBloodRelationshipDescriptor(
      normalizedViewerId,
      personId,
      traversal.bloodParentsByChild,
      peopleById,
    );
    const affinityDescriptor = computeAffinityRelationshipDescriptor({
      viewerPersonId: normalizedViewerId,
      targetPersonId: personId,
      peopleById,
      parentsByChild: traversal.parentsByChild,
      childrenByParent: traversal.childrenByParent,
      bloodParentsByChild: traversal.bloodParentsByChild,
      bloodChildrenByParent: traversal.bloodChildrenByParent,
      currentUnionPartnersByPerson: traversal.currentUnionPartnersByPerson,
      siblingsByPerson: traversal.siblingsByPerson,
    });
    let primaryRelationLabel = null;
    let isBlood = false;

    if (directRelation) {
      const customDirectLabel = relationCustomLabelForPerson(directRelation, personId);
      const relationType = relationTypeForPerson(directRelation, personId);
      if (customDirectLabel) {
        primaryRelationLabel = customDirectLabel;
        isBlood = false;
      } else if (relationType && relationType !== "other") {
        const shouldPreferAffinityLabel =
          relationType === "parentInLaw" ||
          relationType === "childInLaw" ||
          relationType === "siblingInLaw" ||
          relationType === "inlaw";
        primaryRelationLabel = shouldPreferAffinityLabel
          ? affinityDescriptor?.label || describeDirectRelationLabel({
              relationType,
              gender: person.gender,
              parentSetType: directRelation.parentSetType,
            })
          : describeDirectRelationLabel({
              relationType,
              gender: person.gender,
              parentSetType: directRelation.parentSetType,
            });
        isBlood = isBloodDirectRelationType(
          relationType,
          directRelation.parentSetType,
        );
      }
    }

    if (!primaryRelationLabel && bloodDescriptor?.label) {
      primaryRelationLabel = bloodDescriptor.label;
      isBlood = bloodDescriptor.isBlood;
    }

    if (!primaryRelationLabel && affinityDescriptor?.label) {
      primaryRelationLabel = affinityDescriptor.label;
      isBlood = false;
    }

    const bestCost = pathIndex.costs.get(personId) || null;
    const primaryPathPersonIds = reconstructPersonPath(
      personId,
      pathIndex.predecessors,
    );
    const alternatePathCount = Math.max(
      0,
      (pathIndex.pathCounts.get(personId) || 1) - 1,
    );
    if (!primaryRelationLabel && primaryPathPersonIds.length > 1) {
      const sparsePathDescriptor = buildSparsePathRelationshipDescriptor({
        targetPersonId: personId,
        primaryPathPersonIds,
        directRelations: traversal.directRelations,
        peopleById,
      });
      if (sparsePathDescriptor?.label) {
        primaryRelationLabel = sparsePathDescriptor.label;
        isBlood = sparsePathDescriptor.isBlood === true;
      }
    }
    if (!primaryRelationLabel && bestCost) {
      primaryRelationLabel =
        bestCost.nonBlood === 0 ? "Кровный родственник" : "Родня по браку";
      isBlood = bestCost.nonBlood === 0;
    }

    if (!primaryRelationLabel) {
      continue;
    }

    descriptors.push({
      personId,
      primaryRelationLabel,
      isBlood,
      alternatePathCount,
      pathSummary: buildPathSummary(primaryPathPersonIds, peopleById),
      primaryPathPersonIds,
    });
  }

  return descriptors;
}

function buildTreeGraphSnapshot({
  treeId,
  persons = [],
  relations = [],
  viewerPersonId = null,
}) {
  const normalizedGraph = normalizeTreeGraph(treeId, persons, relations);
  const displayRelations = buildDisplayTreeRelations(
    treeId,
    normalizedGraph.relations,
  );
  const familyUnits = buildFamilyUnits(
    treeId,
    normalizedGraph.people,
    displayRelations,
  );
  const branchBlocks = resolveBranchBlocks(
    treeId,
    normalizedGraph.people,
    displayRelations,
    familyUnits,
  );
  const generationRows = buildGenerationRows(
    normalizedGraph.people,
    displayRelations,
    familyUnits,
  );
  const warnings = buildGraphWarnings({
    persons: normalizedGraph.people,
    relations: displayRelations,
    familyUnits,
  });

  return {
    treeId,
    viewerPersonId: String(viewerPersonId || "").trim() || null,
    people: normalizedGraph.people,
    relations: displayRelations,
    familyUnits,
    viewerDescriptors: computeViewerKinships(
      treeId,
      normalizedGraph.people,
      displayRelations,
      viewerPersonId,
    ),
    branchBlocks,
    generationRows,
    warnings,
  };
}

function fullNameFromPersonInput(person = {}) {
  const parts = [person.lastName, person.firstName, person.middleName]
    .map((value) => String(value || "").trim())
    .filter(Boolean);

  if (parts.length > 0) {
    return parts.join(" ");
  }

  return String(person.name || "").trim();
}

function composeDisplayNameFromProfile(profile = {}) {
  return fullNameFromPersonInput({
    firstName: profile.firstName,
    lastName: profile.lastName,
    middleName: profile.middleName,
    name: profile.displayName,
  });
}

function normalizeNullableString(value) {
  const normalized = String(value || "").trim();
  return normalized ? normalized : null;
}

function normalizeProfileContributionPolicy(value) {
  const normalized = String(value || "").trim().toLowerCase();
  return PROFILE_CONTRIBUTION_POLICIES.has(normalized)
    ? normalized
    : "suggestions";
}

function normalizePrimaryTrustedChannel(value) {
  const normalized = normalizeAuthProvider(value);
  if (
    normalized === "google" ||
    normalized === "telegram" ||
    normalized === "vk" ||
    normalized === "max"
  ) {
    return normalized;
  }
  return null;
}

function resolvePersonFamilySummary(person = {}) {
  return (
    normalizeNullableString(person.familySummary) ||
    normalizeNullableString(person.notes) ||
    normalizeNullableString(person.bio)
  );
}

function normalizeProfileContributionFields(fields = {}) {
  if (!fields || typeof fields !== "object" || Array.isArray(fields)) {
    return {};
  }

  const normalized = {};
  for (const fieldName of PROFILE_SUGGESTION_FIELDS) {
    if (!Object.prototype.hasOwnProperty.call(fields, fieldName)) {
      continue;
    }

    switch (fieldName) {
      case "birthDate":
        normalized[fieldName] = normalizeIsoDate(fields[fieldName]);
        break;
      case "photoUrl":
        normalized[fieldName] = normalizeNullableString(fields[fieldName]);
        break;
      default:
        normalized[fieldName] = normalizeNullableString(fields[fieldName]) || "";
        break;
    }
  }

  return normalized;
}

function normalizeCountryDialCode(value) {
  const digits = String(value || "").replace(/\D+/g, "");
  return digits ? `+${digits}` : null;
}

function normalizePhoneNumber(value, countryCode = null) {
  const rawValue = String(value || "").trim();
  if (!rawValue) {
    return null;
  }

  const hasLeadingPlus = rawValue.startsWith("+");
  let digits = rawValue.replace(/\D+/g, "");
  if (!digits) {
    return null;
  }

  const normalizedCountryCode = normalizeCountryDialCode(countryCode);
  const countryDigits = normalizedCountryCode
    ? normalizedCountryCode.replace(/\D+/g, "")
    : "";

  if (hasLeadingPlus) {
    return `+${digits}`;
  }

  if (digits.length === 11 && digits.startsWith("8")) {
    digits = `7${digits.slice(1)}`;
  }

  if (digits.length === 10 && countryDigits) {
    digits = `${countryDigits}${digits}`;
  }

  if (digits.length <= 6) {
    return null;
  }

  return `+${digits}`;
}

const SUPPORTED_AUTH_PROVIDERS = new Set([
  "password",
  "google",
  "telegram",
  "vk",
  "max",
]);

function normalizeAuthProvider(value) {
  const normalized = String(value || "").trim().toLowerCase();
  return SUPPORTED_AUTH_PROVIDERS.has(normalized) ? normalized : null;
}

function createPasswordAuthIdentity(email, timestamp = nowIso()) {
  const normalizedEmail = normalizeNullableString(email)?.toLowerCase();
  if (!normalizedEmail) {
    return null;
  }

  return {
    provider: "password",
    providerUserId: normalizedEmail,
    linkedAt: timestamp,
    lastUsedAt: timestamp,
    email: normalizedEmail,
    phoneNumber: null,
    normalizedPhoneNumber: null,
    displayName: null,
    metadata: {},
  };
}

function createAuthHandoffRecord({
  type,
  payload = {},
  userId = null,
  expiresAt = null,
}) {
  const createdAt = nowIso();
  const normalizedExpiresAt =
    normalizeOptionalIsoTimestamp(expiresAt) ||
    new Date(Date.now() + 10 * 60 * 1000).toISOString();
  return {
    code: crypto.randomBytes(24).toString("hex"),
    type: normalizeNullableString(type),
    userId: normalizeNullableString(userId),
    payload:
      payload && typeof payload === "object" ? structuredClone(payload) : {},
    createdAt,
    expiresAt: normalizedExpiresAt,
  };
}

function normalizeAuthIdentityRecord(identity) {
  const provider = normalizeAuthProvider(identity?.provider);
  const rawProviderUserId = String(identity?.providerUserId || "").trim();
  if (!provider || !rawProviderUserId) {
    return null;
  }

  const normalizedEmail = normalizeNullableString(identity?.email)?.toLowerCase();
  const phoneNumber = normalizeNullableString(identity?.phoneNumber);
  const normalizedPhoneNumber = normalizePhoneNumber(
    identity?.normalizedPhoneNumber || phoneNumber,
  );
  const providerUserId =
    provider === "password" && normalizedEmail
      ? normalizedEmail
      : rawProviderUserId;

  return {
    provider,
    providerUserId,
    linkedAt: normalizeOptionalIsoTimestamp(identity?.linkedAt) || nowIso(),
    lastUsedAt: normalizeOptionalIsoTimestamp(identity?.lastUsedAt),
    email: normalizedEmail,
    phoneNumber,
    normalizedPhoneNumber,
    displayName: normalizeNullableString(identity?.displayName),
    metadata:
      identity?.metadata && typeof identity.metadata === "object"
        ? structuredClone(identity.metadata)
        : {},
  };
}

function listAuthIdentitiesForUser(user) {
  const identities = [];
  const seenKeys = new Set();

  const addIdentity = (identity) => {
    const normalizedIdentity = normalizeAuthIdentityRecord(identity);
    if (!normalizedIdentity) {
      return;
    }

    const identityKey =
      `${normalizedIdentity.provider}:${normalizedIdentity.providerUserId}`;
    if (seenKeys.has(identityKey)) {
      return;
    }

    seenKeys.add(identityKey);
    identities.push(normalizedIdentity);
  };

  if (Array.isArray(user?.authIdentities)) {
    for (const identity of user.authIdentities) {
      addIdentity(identity);
    }
  }

  if (user?.passwordHash && user?.email) {
    addIdentity(createPasswordAuthIdentity(user.email, user.createdAt || nowIso()));
  }

  return identities.sort((left, right) => {
    if (left.provider === "password" && right.provider !== "password") {
      return -1;
    }
    if (right.provider === "password" && left.provider !== "password") {
      return 1;
    }
    return String(left.linkedAt).localeCompare(String(right.linkedAt));
  });
}

function deriveProviderIdsForUser(user) {
  const providerIds = Array.isArray(user?.providerIds)
    ? user.providerIds
      .map((value) => normalizeAuthProvider(value))
      .filter(Boolean)
    : [];

  for (const identity of listAuthIdentitiesForUser(user)) {
    providerIds.push(identity.provider);
  }

  if (user?.passwordHash) {
    providerIds.push("password");
  }

  return Array.from(new Set(providerIds));
}

function cloneUserWithAuthState(user) {
  const clonedUser = structuredClone(user);
  clonedUser.authIdentities = listAuthIdentitiesForUser(clonedUser);
  clonedUser.providerIds = deriveProviderIdsForUser(clonedUser);
  return clonedUser;
}

function normalizeIsoDate(value) {
  if (!value) {
    return null;
  }

  const parsed = new Date(String(value));
  if (Number.isNaN(parsed.getTime())) {
    return null;
  }

  return parsed.toISOString();
}

function createTreeInvitationRecord({
  treeId,
  userId,
  addedBy = null,
  relationToTree = null,
}) {
  const timestamp = nowIso();
  return {
    id: crypto.randomUUID(),
    treeId,
    userId,
    role: "pending",
    addedAt: timestamp,
    addedBy,
    acceptedAt: null,
    relationToTree: normalizeNullableString(relationToTree),
  };
}

function normalizePersonMediaType(type, contentType = null) {
  const normalizedType = String(type || "").trim().toLowerCase();
  if (normalizedType === "image" || normalizedType === "video") {
    return normalizedType;
  }

  const normalizedContentType = String(contentType || "")
    .trim()
    .toLowerCase();
  if (normalizedContentType.startsWith("video/")) {
    return "video";
  }

  return "image";
}

function normalizePersonPhotoGallery(photoGallery, {
  photoUrl = null,
  primaryPhotoUrl = null,
} = {}) {
  const entries = [];
  const seenIds = new Set();
  const seenUrls = new Set();

  const addEntry = (rawEntry) => {
    if (typeof rawEntry === "string") {
      rawEntry = {url: rawEntry};
    }

    if (!rawEntry || typeof rawEntry !== "object") {
      return;
    }

    const normalizedUrl = normalizeNullableString(rawEntry.url);
    if (!normalizedUrl || seenUrls.has(normalizedUrl)) {
      return;
    }

    let mediaId = normalizeNullableString(rawEntry.id);
    if (mediaId && seenIds.has(mediaId)) {
      mediaId = null;
    }
    if (!mediaId) {
      mediaId = crypto.randomUUID();
    }

    seenIds.add(mediaId);
    seenUrls.add(normalizedUrl);

    const createdAt =
      normalizeOptionalIsoTimestamp(rawEntry.createdAt) || nowIso();
    const updatedAt =
      normalizeOptionalIsoTimestamp(rawEntry.updatedAt) || createdAt;

    entries.push({
      id: mediaId,
      url: normalizedUrl,
      thumbnailUrl: normalizeNullableString(rawEntry.thumbnailUrl),
      type: normalizePersonMediaType(
        rawEntry.type || rawEntry.mediaType,
        rawEntry.contentType,
      ),
      contentType: normalizeNullableString(rawEntry.contentType),
      caption: normalizeNullableString(rawEntry.caption),
      createdAt,
      updatedAt,
      isPrimary: rawEntry.isPrimary === true,
    });
  };

  if (Array.isArray(photoGallery)) {
    for (const entry of photoGallery) {
      addEntry(entry);
    }
  }

  const requestedPrimary =
    normalizeNullableString(primaryPhotoUrl) ||
    normalizeNullableString(photoUrl) ||
    entries.find((entry) => entry.isPrimary === true)?.url ||
    null;

  if (requestedPrimary && !seenUrls.has(requestedPrimary)) {
    addEntry({url: requestedPrimary, isPrimary: true});
  }

  const resolvedPrimary =
    requestedPrimary && seenUrls.has(requestedPrimary)
      ? requestedPrimary
      : entries[0]?.url || null;

  if (resolvedPrimary) {
    const primaryIndex = entries.findIndex((entry) => entry.url === resolvedPrimary);
    if (primaryIndex > 0) {
      const [primaryEntry] = entries.splice(primaryIndex, 1);
      entries.unshift(primaryEntry);
    }
  }

  for (const entry of entries) {
    entry.isPrimary = resolvedPrimary !== null && entry.url === resolvedPrimary;
  }

  return {
    primaryPhotoUrl: resolvedPrimary,
    photoUrl: resolvedPrimary,
    photoGallery: entries,
  };
}

function createTreeChangeRecord({
  treeId,
  actorId = null,
  type,
  personId = null,
  personIds = [],
  relationId = null,
  mediaId = null,
  details = {},
}) {
  const normalizedPersonIds = Array.from(
    new Set(
      [
        personId,
        ...(Array.isArray(personIds) ? personIds : []),
      ]
        .map((value) => String(value || "").trim())
        .filter(Boolean),
    ),
  );

  return {
    id: crypto.randomUUID(),
    treeId,
    actorId: normalizeNullableString(actorId),
    type: String(type || "unknown").trim() || "unknown",
    personId: normalizeNullableString(personId) || normalizedPersonIds[0] || null,
    personIds: normalizedPersonIds,
    relationId: normalizeNullableString(relationId),
    mediaId: normalizeNullableString(mediaId),
    createdAt: nowIso(),
    details:
      details && typeof details === "object" ? structuredClone(details) : {},
  };
}

function buildPersonRecord({
  treeId,
  creatorId,
  userId = null,
  identityId = null,
  personData = {},
}) {
  const createdAt = nowIso();
  const birthDate = normalizeIsoDate(personData.birthDate);
  const deathDate = normalizeIsoDate(personData.deathDate);
  const familySummary = resolvePersonFamilySummary(personData);
  const photoState = normalizePersonPhotoGallery(personData.photoGallery, {
    photoUrl: personData.photoUrl,
    primaryPhotoUrl: personData.primaryPhotoUrl,
  });

  return {
    id: crypto.randomUUID(),
    treeId,
    userId,
    identityId: normalizeNullableString(identityId),
    name: fullNameFromPersonInput(personData),
    maidenName: normalizeNullableString(personData.maidenName),
    photoUrl: photoState.photoUrl,
    primaryPhotoUrl: photoState.primaryPhotoUrl,
    photoGallery: photoState.photoGallery,
    gender: String(personData.gender || "unknown"),
    birthDate,
    birthPlace: normalizeNullableString(personData.birthPlace),
    deathDate,
    deathPlace: normalizeNullableString(personData.deathPlace),
    familySummary,
    bio: normalizeNullableString(personData.bio),
    isAlive: deathDate === null,
    creatorId,
    createdAt,
    updatedAt: createdAt,
    notes: normalizeNullableString(personData.notes),
  };
}

function createPersonIdentityRecord({
  id = crypto.randomUUID(),
  userId = null,
  personIds = [],
} = {}) {
  const createdAt = nowIso();
  return {
    id,
    userId: normalizeNullableString(userId),
    personIds: normalizeParticipantIds(personIds),
    createdAt,
    updatedAt: createdAt,
  };
}

function pickPersonValue(currentValue, fallbackValue) {
  if (currentValue === null || currentValue === undefined) {
    return fallbackValue ?? currentValue;
  }

  if (typeof currentValue === "string" && currentValue.trim().length === 0) {
    return fallbackValue ?? currentValue;
  }

  return currentValue;
}

function relationDedupKey(relation) {
  const leftId = String(relation.person1Id || "");
  const rightId = String(relation.person2Id || "");
  const leftToRight = String(relation.relation1to2 || "other");
  const rightToLeft = String(relation.relation2to1 || "other");

  if (leftId <= rightId) {
    return `${relation.treeId}:${leftId}:${rightId}:${leftToRight}:${rightToLeft}`;
  }

  return `${relation.treeId}:${rightId}:${leftId}:${rightToLeft}:${leftToRight}`;
}

function hashPassword(password, salt = crypto.randomBytes(16).toString("hex")) {
  const derivedKey = crypto.scryptSync(password, salt, 64).toString("hex");
  return {
    salt,
    passwordHash: derivedKey,
  };
}

function verifyPassword(password, user) {
  if (!user?.passwordHash || !user?.passwordSalt) {
    return false;
  }

  const derivedKey = crypto
    .scryptSync(password, user.passwordSalt, 64)
    .toString("hex");

  return crypto.timingSafeEqual(
    Buffer.from(derivedKey, "hex"),
    Buffer.from(user.passwordHash, "hex"),
  );
}

class FileStore {
  constructor(dataPath) {
    this.dataPath = dataPath;
    this.storageMode = "file-store";
    this.storageTarget = dataPath;
    this._writeQueue = Promise.resolve();
    this._sessionTouchCache = new Map();
  }

  async initialize() {
    await fs.mkdir(path.dirname(this.dataPath), {recursive: true});

    try {
      await fs.access(this.dataPath);
    } catch {
      await fs.writeFile(
        this.dataPath,
        JSON.stringify(EMPTY_DB, null, 2),
        "utf8",
      );
    }
  }

  async _read() {
    await this.initialize();
    await this._writeQueue;
    const raw = await fs.readFile(this.dataPath, "utf8");
    const parsed = JSON.parse(raw);
    return normalizeDbState(parsed);
  }

  async _write(data) {
    this._writeQueue = this._writeQueue.then(async () => {
      const directoryPath = path.dirname(this.dataPath);
      const tempPath = path.join(
        directoryPath,
        `${path.basename(this.dataPath)}.${crypto.randomUUID()}.tmp`,
      );

      await fs.writeFile(tempPath, JSON.stringify(data, null, 2), "utf8");
      await fs.rename(tempPath, this.dataPath);
    });
    return this._writeQueue;
  }

  _appendTreeChangeRecord(db, {
    treeId,
    actorId = null,
    type,
    personId = null,
    personIds = [],
    relationId = null,
    mediaId = null,
    details = {},
  }) {
    const record = createTreeChangeRecord({
      treeId,
      actorId,
      type,
      personId,
      personIds,
      relationId,
      mediaId,
      details,
    });
    db.treeChangeRecords.push(record);
    return record;
  }

  _ensurePersonIdentityCollection(db) {
    db.personIdentities = Array.isArray(db.personIdentities)
      ? db.personIdentities
      : [];
    return db.personIdentities;
  }

  _reconcilePersonIdentities(db) {
    const identities = this._ensurePersonIdentityCollection(db);
    const validUserIds = new Set(
      db.users
        .map((entry) => normalizeNullableString(entry.id))
        .filter(Boolean),
    );
    const personIdsByIdentity = new Map();

    for (const person of db.persons) {
      const identityId = normalizeNullableString(person.identityId);
      if (!identityId) {
        person.identityId = null;
        continue;
      }

      person.identityId = identityId;
      if (!personIdsByIdentity.has(identityId)) {
        personIdsByIdentity.set(identityId, []);
      }
      personIdsByIdentity.get(identityId).push(person.id);
    }

    const seenIdentityIds = new Set();
    db.personIdentities = identities.reduce((result, entry) => {
      const identityId = normalizeNullableString(entry?.id);
      if (!identityId || seenIdentityIds.has(identityId)) {
        return result;
      }

      seenIdentityIds.add(identityId);
      const linkedUserId = normalizeNullableString(entry?.userId);
      const normalizedUserId = linkedUserId && validUserIds.has(linkedUserId)
        ? linkedUserId
        : null;
      const personIds = normalizeParticipantIds(
        personIdsByIdentity.get(identityId) || [],
      );

      if (!normalizedUserId && personIds.length === 0) {
        return result;
      }

      result.push({
        id: identityId,
        userId: normalizedUserId,
        personIds,
        createdAt: entry?.createdAt || nowIso(),
        updatedAt: entry?.updatedAt || nowIso(),
      });
      return result;
    }, []);

    const identitiesByUserId = new Map(
      db.personIdentities
        .filter((entry) => entry.userId)
        .map((entry) => [entry.userId, entry.id]),
    );
    for (const user of db.users) {
      const normalizedIdentityId = normalizeNullableString(user.identityId);
      const ownedIdentityId = identitiesByUserId.get(user.id) || null;
      if (
        normalizedIdentityId &&
        db.personIdentities.some(
          (entry) =>
            entry.id === normalizedIdentityId && entry.userId === user.id,
        )
      ) {
        user.identityId = normalizedIdentityId;
        continue;
      }

      user.identityId = ownedIdentityId;
    }
  }

  _ensureUserIdentity(db, userId) {
    const user = db.users.find((entry) => entry.id === userId);
    if (!user) {
      return null;
    }

    const identities = this._ensurePersonIdentityCollection(db);
    const normalizedIdentityId = normalizeNullableString(user.identityId);
    let identity = normalizedIdentityId
      ? identities.find((entry) => entry.id === normalizedIdentityId)
      : null;

    if (!identity) {
      identity = identities.find((entry) => entry.userId === userId);
    }

    if (!identity) {
      identity = createPersonIdentityRecord({
        id: normalizedIdentityId || crypto.randomUUID(),
        userId,
      });
      identities.push(identity);
    }

    identity.userId = userId;
    identity.updatedAt = nowIso();
    user.identityId = identity.id;
    user.updatedAt = nowIso();
    return identity;
  }

  _attachPersonToIdentity(db, person, identity, userId = null) {
    if (!person || !identity) {
      return false;
    }

    const normalizedUserId = normalizeNullableString(userId || person.userId);
    if (normalizedUserId) {
      if (person.userId && person.userId !== normalizedUserId) {
        return false;
      }
      if (identity.userId && identity.userId !== normalizedUserId) {
        return false;
      }
      person.userId = normalizedUserId;
      identity.userId = normalizedUserId;
      const user = db.users.find((entry) => entry.id === normalizedUserId);
      if (user) {
        user.identityId = identity.id;
        user.updatedAt = nowIso();
      }
    }

    person.identityId = identity.id;
    person.updatedAt = nowIso();
    identity.updatedAt = nowIso();
    this._reconcilePersonIdentities(db);
    return true;
  }

  _mergePersonIntoClaimTarget(db, {
    treeId,
    preferredPerson,
    duplicatePerson,
    userId,
    actorId = userId,
  }) {
    if (
      !preferredPerson ||
      !duplicatePerson ||
      preferredPerson.id === duplicatePerson.id
    ) {
      return preferredPerson;
    }

    const beforePreferred = structuredClone(preferredPerson);
    const removedDuplicate = structuredClone(duplicatePerson);
    const mergedPhotoState = normalizePersonPhotoGallery(
      [
        ...(Array.isArray(preferredPerson.photoGallery)
          ? preferredPerson.photoGallery
          : []),
        ...(Array.isArray(duplicatePerson.photoGallery)
          ? duplicatePerson.photoGallery
          : []),
      ],
      {
        photoUrl: preferredPerson.photoUrl || duplicatePerson.photoUrl,
        primaryPhotoUrl:
          preferredPerson.primaryPhotoUrl ||
          duplicatePerson.primaryPhotoUrl ||
          preferredPerson.photoUrl ||
          duplicatePerson.photoUrl,
      },
    );

    preferredPerson.name = pickPersonValue(
      preferredPerson.name,
      duplicatePerson.name,
    );
    preferredPerson.maidenName = pickPersonValue(
      preferredPerson.maidenName,
      duplicatePerson.maidenName,
    );
    preferredPerson.birthDate = pickPersonValue(
      preferredPerson.birthDate,
      duplicatePerson.birthDate,
    );
    preferredPerson.birthPlace = pickPersonValue(
      preferredPerson.birthPlace,
      duplicatePerson.birthPlace,
    );
    preferredPerson.deathDate = pickPersonValue(
      preferredPerson.deathDate,
      duplicatePerson.deathDate,
    );
    preferredPerson.deathPlace = pickPersonValue(
      preferredPerson.deathPlace,
      duplicatePerson.deathPlace,
    );
    preferredPerson.bio = pickPersonValue(preferredPerson.bio, duplicatePerson.bio);
    preferredPerson.notes = pickPersonValue(
      preferredPerson.notes,
      duplicatePerson.notes,
    );
    preferredPerson.creatorId = pickPersonValue(
      preferredPerson.creatorId,
      duplicatePerson.creatorId,
    );
    preferredPerson.photoUrl = mergedPhotoState.photoUrl;
    preferredPerson.primaryPhotoUrl = mergedPhotoState.primaryPhotoUrl;
    preferredPerson.photoGallery = mergedPhotoState.photoGallery;
    preferredPerson.userId = userId;
    preferredPerson.identityId = normalizeNullableString(
      preferredPerson.identityId || duplicatePerson.identityId,
    );
    preferredPerson.isAlive = preferredPerson.deathDate == null;
    preferredPerson.updatedAt = nowIso();

    for (const relation of db.relations) {
      if (relation.treeId !== treeId) {
        continue;
      }
      if (relation.person1Id === duplicatePerson.id) {
        relation.person1Id = preferredPerson.id;
      }
      if (relation.person2Id === duplicatePerson.id) {
        relation.person2Id = preferredPerson.id;
      }
    }
    db.relations = db.relations.reduce((result, relation) => {
      if (
        relation.treeId === treeId &&
        relation.person1Id === relation.person2Id
      ) {
        return result;
      }

      const dedupKey = relationDedupKey(relation);
      if (result.some((entry) => relationDedupKey(entry) === dedupKey)) {
        return result;
      }

      result.push(relation);
      return result;
    }, []);

    for (const post of db.posts) {
      if (post.treeId !== treeId) {
        continue;
      }
      post.anchorPersonIds = normalizeParticipantIds(
        (post.anchorPersonIds || []).map((personId) =>
          personId === duplicatePerson.id ? preferredPerson.id : personId,
        ),
      );
    }

    for (const chat of db.chats) {
      if (chat.treeId !== treeId) {
        continue;
      }
      chat.branchRootPersonIds = normalizeParticipantIds(
        (chat.branchRootPersonIds || []).map((personId) =>
          personId === duplicatePerson.id ? preferredPerson.id : personId,
        ),
      );
    }

    for (const request of db.relationRequests) {
      if (request.treeId !== treeId) {
        continue;
      }
      if (request.targetPersonId === duplicatePerson.id) {
        request.targetPersonId = preferredPerson.id;
      }
      if (request.offlineRelativeId === duplicatePerson.id) {
        request.offlineRelativeId = preferredPerson.id;
      }
    }

    for (const record of db.treeChangeRecords) {
      if (record.treeId !== treeId) {
        continue;
      }
      if (record.personId === duplicatePerson.id) {
        record.personId = preferredPerson.id;
      }
      record.personIds = normalizeParticipantIds(
        (record.personIds || []).map((personId) =>
          personId === duplicatePerson.id ? preferredPerson.id : personId,
        ),
      );
    }

    db.persons = db.persons.filter((entry) => entry.id !== duplicatePerson.id);
    this._appendTreeChangeRecord(db, {
      treeId,
      actorId,
      type: "person.merged",
      personId: preferredPerson.id,
      personIds: [preferredPerson.id, duplicatePerson.id],
      details: {
        before: beforePreferred,
        mergedFrom: removedDuplicate,
        after: structuredClone(preferredPerson),
      },
    });
    this._reconcilePersonIdentities(db);
    return preferredPerson;
  }

  async createUser({
    email,
    password = null,
    displayName,
    authIdentity = null,
    photoUrl = null,
  }) {
    const db = await this._read();
    const normalizedEmail = String(email || "").trim().toLowerCase();

    if (db.users.some((user) => user.email === normalizedEmail)) {
      throw new Error("EMAIL_ALREADY_EXISTS");
    }

    const createdAt = nowIso();
    const hasPassword = typeof password === "string" && password.length > 0;
    const passwordCredentials = hasPassword ? hashPassword(password) : null;
    const userId = crypto.randomUUID();

    const nameParts = String(displayName || "")
      .trim()
      .split(/\s+/)
      .filter(Boolean);
    const authIdentities = [];
    if (hasPassword) {
      const passwordAuthIdentity = createPasswordAuthIdentity(
        normalizedEmail,
        createdAt,
      );
      if (passwordAuthIdentity) {
        authIdentities.push(passwordAuthIdentity);
      }
    }

    const normalizedAuthIdentity = normalizeAuthIdentityRecord(authIdentity);
    if (normalizedAuthIdentity) {
      authIdentities.push(normalizedAuthIdentity);
    }

    const user = {
      id: userId,
      identityId: null,
      email: normalizedEmail,
      passwordHash: passwordCredentials?.passwordHash || null,
      passwordSalt: passwordCredentials?.salt || null,
      providerIds: [],
      authIdentities,
      createdAt,
      updatedAt: createdAt,
      profile: {
        id: userId,
        email: normalizedEmail,
        displayName: String(displayName || "").trim(),
        firstName: nameParts[0] || "",
        lastName: nameParts.length > 1 ? nameParts[nameParts.length - 1] : "",
        middleName:
          nameParts.length > 2 ? nameParts.slice(1, -1).join(" ") : "",
        username: "",
        phoneNumber: "",
        normalizedPhoneNumber: null,
        countryCode: null,
        countryName: null,
        city: "",
        photoUrl: String(photoUrl || "").trim() || null,
        gender: "unknown",
        maidenName: "",
        birthDate: null,
        birthPlace: null,
        bio: "",
        familyStatus: "",
        aboutFamily: "",
        education: "",
        work: "",
        hometown: "",
        languages: "",
        values: "",
        religion: "",
        interests: "",
        profileContributionPolicy: "suggestions",
        primaryTrustedChannel: normalizePrimaryTrustedChannel(
          normalizedAuthIdentity?.provider,
        ),
        createdAt,
        updatedAt: createdAt,
      },
      profileNotes: [],
    };
    user.providerIds = deriveProviderIdsForUser(user);

    db.users.push(user);
    await this._write(db);
    return cloneUserWithAuthState(user);
  }

  async authenticate(email, password) {
    const db = await this._read();
    const normalizedEmail = String(email || "").trim().toLowerCase();
    const user = db.users.find((entry) => entry.email === normalizedEmail);

    if (!user || !verifyPassword(password, user)) {
      return null;
    }

    return cloneUserWithAuthState(user);
  }

  async findUserById(userId) {
    const db = await this._read();
    const user = db.users.find((entry) => entry.id === userId);
    return user ? cloneUserWithAuthState(user) : null;
  }

  async findUserByEmail(email) {
    const db = await this._read();
    const normalizedEmail = String(email || "").trim().toLowerCase();
    if (!normalizedEmail) {
      return null;
    }

    const user = db.users.find((entry) => entry.email === normalizedEmail);
    return user ? cloneUserWithAuthState(user) : null;
  }

  async findUserByAuthIdentity(provider, providerUserId) {
    const db = await this._read();
    const normalizedProvider = normalizeAuthProvider(provider);
    const normalizedProviderUserId = String(providerUserId || "").trim();
    if (!normalizedProvider || !normalizedProviderUserId) {
      return null;
    }

    const user = db.users.find((entry) =>
      listAuthIdentitiesForUser(entry).some(
        (identity) =>
          identity.provider === normalizedProvider &&
          identity.providerUserId === normalizedProviderUserId,
      ),
    );
    return user ? cloneUserWithAuthState(user) : null;
  }

  async createSession(userId) {
    const db = await this._read();
    const createdAt = nowIso();
    const token = crypto.randomBytes(32).toString("hex");
    const refreshToken = crypto.randomBytes(32).toString("hex");

    // Keep last 5 sessions for this user to allow multiple devices
    const userSessions = db.sessions.filter((s) => s.userId === userId);
    const otherSessions = db.sessions.filter((s) => s.userId !== userId);
    
    const sessionsToKeep = userSessions.slice(-4); // Keep 4 previous, total 5 after push
    
    db.sessions = [
      ...otherSessions,
      ...sessionsToKeep,
      {
        token,
        refreshToken,
        userId,
        createdAt,
        lastSeenAt: createdAt,
      }
    ];

    await this._write(db);
    return {
      token,
      refreshToken,
    };
  }

  async findSessionByRefreshToken(refreshToken) {
    const db = await this._read();
    const session = db.sessions.find((entry) => entry.refreshToken === refreshToken);
    return session ? structuredClone(session) : null;
  }

  _cleanupExpiredAuthHandoffs(db) {
    const beforeLength = Array.isArray(db.authHandoffs) ? db.authHandoffs.length : 0;
    db.authHandoffs = (Array.isArray(db.authHandoffs) ? db.authHandoffs : []).filter(
      (entry) => !isExpiredAt(entry?.expiresAt),
    );
    return db.authHandoffs.length !== beforeLength;
  }

  async createAuthHandoff({type, payload = {}, userId = null, expiresAt = null}) {
    const db = await this._read();
    this._cleanupExpiredAuthHandoffs(db);
    const handoff = createAuthHandoffRecord({
      type,
      payload,
      userId,
      expiresAt,
    });
    db.authHandoffs.push(handoff);
    await this._write(db);
    return structuredClone(handoff);
  }

  async consumeAuthHandoff(code, {type = null} = {}) {
    const db = await this._read();
    this._cleanupExpiredAuthHandoffs(db);
    const normalizedCode = String(code || "").trim();
    const index = db.authHandoffs.findIndex((entry) => {
      if (entry.code !== normalizedCode) {
        return false;
      }
      if (type && entry.type !== type) {
        return false;
      }
      return true;
    });
    if (index < 0) {
      if (this._cleanupExpiredAuthHandoffs(db)) {
        await this._write(db);
      }
      return null;
    }

    const [handoff] = db.authHandoffs.splice(index, 1);
    await this._write(db);
    return structuredClone(handoff);
  }

  async findSession(token) {
    const db = await this._read();
    const session = db.sessions.find((entry) => entry.token === token);
    return session ? structuredClone(session) : null;
  }

  async touchSession(token) {
    const normalizedToken = String(token || "").trim();
    if (!normalizedToken) {
      return null;
    }

    const nowMs = Date.now();
    const cachedTouchedAt = this._sessionTouchCache.get(normalizedToken);
    if (
      Number.isFinite(cachedTouchedAt) &&
      nowMs - cachedTouchedAt < SESSION_TOUCH_MIN_INTERVAL_MS
    ) {
      return null;
    }

    this._sessionTouchCache.set(normalizedToken, nowMs);
    const db = await this._read();
    const session = db.sessions.find((entry) => entry.token === normalizedToken);
    if (!session) {
      this._sessionTouchCache.delete(normalizedToken);
      return null;
    }

    const lastSeenAtMs = new Date(session.lastSeenAt || 0).getTime();
    if (
      Number.isFinite(lastSeenAtMs) &&
      nowMs - lastSeenAtMs < SESSION_TOUCH_MIN_INTERVAL_MS
    ) {
      this._sessionTouchCache.set(normalizedToken, lastSeenAtMs);
      return structuredClone(session);
    }

    session.lastSeenAt = nowIso();
    try {
      await this._write(db);
    } catch (error) {
      this._sessionTouchCache.delete(normalizedToken);
      throw error;
    }
    return structuredClone(session);
  }

  async deleteSession(token) {
    const db = await this._read();
    db.sessions = db.sessions.filter((entry) => entry.token !== token);
    this._sessionTouchCache.delete(token);
    await this._write(db);
  }

  async deleteSessionsForUser(userId) {
    const db = await this._read();
    const deletedTokens = db.sessions
      .filter((entry) => entry.userId === userId)
      .map((entry) => entry.token);
    db.sessions = db.sessions.filter((entry) => entry.userId !== userId);
    for (const token of deletedTokens) {
      this._sessionTouchCache.delete(token);
    }
    await this._write(db);
  }

  async listUserAuthIdentities(userId) {
    const db = await this._read();
    const user = db.users.find((entry) => entry.id === userId);
    if (!user) {
      return null;
    }

    return listAuthIdentitiesForUser(user).map((identity) => structuredClone(identity));
  }

  async linkAuthIdentity(userId, identityPayload) {
    const db = await this._read();
    const user = db.users.find((entry) => entry.id === userId);
    if (!user) {
      return null;
    }

    const normalizedIdentity = normalizeAuthIdentityRecord(identityPayload);
    if (!normalizedIdentity) {
      throw new Error("INVALID_AUTH_IDENTITY");
    }

    const alreadyLinkedOwner = db.users.find((entry) => {
      if (entry.id === userId) {
        return false;
      }

      return listAuthIdentitiesForUser(entry).some(
        (identity) =>
          identity.provider === normalizedIdentity.provider &&
          identity.providerUserId === normalizedIdentity.providerUserId,
      );
    });
    if (alreadyLinkedOwner) {
      throw new Error("AUTH_IDENTITY_ALREADY_LINKED");
    }

    const now = nowIso();
    const nextAuthIdentities = listAuthIdentitiesForUser(user);
    const existingIdentityIndex = nextAuthIdentities.findIndex(
      (identity) =>
        identity.provider === normalizedIdentity.provider &&
        identity.providerUserId === normalizedIdentity.providerUserId,
    );
    const existingProviderIndex = nextAuthIdentities.findIndex(
      (identity) => identity.provider === normalizedIdentity.provider,
    );
    if (
      existingProviderIndex >= 0 &&
      existingIdentityIndex < 0 &&
      normalizedIdentity.provider !== "password"
    ) {
      throw new Error("AUTH_PROVIDER_ALREADY_LINKED_FOR_USER");
    }
    const nextIdentity = {
      ...normalizedIdentity,
      linkedAt:
        existingIdentityIndex >= 0
          ? nextAuthIdentities[existingIdentityIndex].linkedAt
          : normalizedIdentity.linkedAt || now,
      lastUsedAt: now,
    };

    if (existingIdentityIndex >= 0) {
      nextAuthIdentities[existingIdentityIndex] = nextIdentity;
    } else {
      nextAuthIdentities.push(nextIdentity);
    }

    user.authIdentities = nextAuthIdentities;
    user.providerIds = deriveProviderIdsForUser(user);
    user.profile = {
      ...user.profile,
      primaryTrustedChannel:
        normalizePrimaryTrustedChannel(user.profile?.primaryTrustedChannel) ||
        normalizePrimaryTrustedChannel(normalizedIdentity.provider),
    };
    user.updatedAt = now;

    await this._write(db);
    return cloneUserWithAuthState(user);
  }

  async resolveAuthIdentityTarget({
    provider,
    providerUserId,
    email = null,
    phoneNumber = null,
  }) {
    const linkedUser = await this.findUserByAuthIdentity(provider, providerUserId);
    if (linkedUser) {
      return {
        reason: "provider_identity",
        user: linkedUser,
      };
    }

    const emailMatchedUser = await this.findUserByEmail(email);
    if (emailMatchedUser) {
      return {
        reason: "email",
        user: emailMatchedUser,
      };
    }

    return {
      reason: "new_account",
      user: null,
    };
  }

  async updateProfile(userId, updater) {
    const db = await this._read();
    const user = db.users.find((entry) => entry.id === userId);
    if (!user) {
      return null;
    }

    const previousProfile = user.profile || {};
    const nextProfile = updater(structuredClone(user.profile));
    const nextPhoneNumber = String(nextProfile?.phoneNumber || "").trim();
    const nextCountryCode = nextProfile?.countryCode ?? user.profile?.countryCode;
    const normalizedPhoneNumber = normalizePhoneNumber(
      nextPhoneNumber,
      nextCountryCode,
    );
    user.profile = {
      ...user.profile,
      ...nextProfile,
      phoneNumber: nextPhoneNumber,
      normalizedPhoneNumber,
      birthPlace:
        nextProfile && Object.prototype.hasOwnProperty.call(nextProfile, "birthPlace")
          ? normalizeNullableString(nextProfile.birthPlace)
          : normalizeNullableString(user.profile?.birthPlace),
      profileContributionPolicy:
        nextProfile &&
        Object.prototype.hasOwnProperty.call(
          nextProfile,
          "profileContributionPolicy",
        )
          ? normalizeProfileContributionPolicy(nextProfile.profileContributionPolicy)
          : normalizeProfileContributionPolicy(
              user.profile?.profileContributionPolicy,
            ),
      primaryTrustedChannel:
        nextProfile &&
        Object.prototype.hasOwnProperty.call(
          nextProfile,
          "primaryTrustedChannel",
        )
          ? normalizePrimaryTrustedChannel(nextProfile.primaryTrustedChannel)
          : normalizePrimaryTrustedChannel(user.profile?.primaryTrustedChannel),
      id: user.id,
      email: user.email,
      updatedAt: nowIso(),
    };
    user.updatedAt = nowIso();

    const touchedTreeIds = new Set();
    for (const person of db.persons) {
      if (person.userId !== userId) {
        continue;
      }
      applyCanonicalProfileToPerson(person, user.profile);
      if (person.treeId) {
        touchedTreeIds.add(person.treeId);
      }
    }
    for (const tree of db.trees) {
      if (touchedTreeIds.has(tree.id)) {
        tree.updatedAt = nowIso();
      }
    }

    await this._write(db);
    return structuredClone(user);
  }

  async deleteUser(userId) {
    const db = await this._read();
    const existingUser = db.users.find((entry) => entry.id === userId);
    if (!existingUser) {
      return null;
    }

    const timestamp = nowIso();
    const removedTreeIds = new Set();
    db.trees = db.trees.reduce((trees, tree) => {
      const nextMemberIds = normalizeParticipantIds(
        (tree.memberIds || tree.members || []).filter(
          (memberId) => memberId !== userId,
        ),
      );

      if (tree.creatorId === userId && nextMemberIds.length === 0) {
        removedTreeIds.add(tree.id);
        return trees;
      }

      const creatorId =
        tree.creatorId === userId ? nextMemberIds[0] || null : tree.creatorId;
      const membersChanged =
        nextMemberIds.length !== (tree.memberIds || tree.members || []).length ||
        creatorId !== tree.creatorId;

      trees.push({
        ...tree,
        creatorId,
        memberIds: nextMemberIds,
        members: nextMemberIds,
        updatedAt: membersChanged ? timestamp : tree.updatedAt,
      });
      return trees;
    }, []);

    const removedPersonIds = new Set(
      db.persons
        .filter(
          (entry) => entry.userId === userId || removedTreeIds.has(entry.treeId),
        )
        .map((entry) => entry.id),
    );

    db.users = db.users.filter((entry) => entry.id !== userId);
    db.sessions = db.sessions.filter((entry) => entry.userId !== userId);
    db.authHandoffs = (db.authHandoffs || []).filter((entry) => entry.userId !== userId);
    db.persons = db.persons.filter((entry) => !removedPersonIds.has(entry.id));
    db.relations = db.relations.filter((entry) => {
      return (
        !removedTreeIds.has(entry.treeId) &&
        !removedPersonIds.has(entry.person1Id) &&
        !removedPersonIds.has(entry.person2Id)
      );
    });

    const nextPosts = [];
    const removedPostIds = new Set();
    for (const post of db.posts) {
      if (post.authorId === userId || removedTreeIds.has(post.treeId)) {
        removedPostIds.add(post.id);
        continue;
      }

      nextPosts.push({
        ...post,
        anchorPersonIds: normalizeParticipantIds(
          (post.anchorPersonIds || []).filter(
            (personId) => !removedPersonIds.has(personId),
          ),
        ),
      });
    }
    db.posts = nextPosts;
    db.stories = db.stories.filter((story) => {
      return !(
        story.authorId === userId ||
        removedTreeIds.has(story.treeId)
      );
    });

    const removedCommentIds = new Set();
    db.comments = db.comments.filter((entry) => {
      const shouldRemove =
        entry.authorId === userId || removedPostIds.has(entry.postId);
      if (shouldRemove) {
        removedCommentIds.add(entry.id);
      }
      return !shouldRemove;
    });

    const removedRelationRequestIds = new Set();
    db.relationRequests = db.relationRequests.filter((entry) => {
      const shouldRemove =
        entry.senderId === userId ||
        entry.recipientId === userId ||
        removedTreeIds.has(entry.treeId);
      if (shouldRemove) {
        removedRelationRequestIds.add(entry.id);
      }
      return !shouldRemove;
    });

    const removedInvitationIds = new Set();
    db.treeInvitations = db.treeInvitations.filter((entry) => {
      const shouldRemove =
        entry.userId === userId || removedTreeIds.has(entry.treeId);
      if (shouldRemove) {
        removedInvitationIds.add(entry.id);
      }
      return !shouldRemove;
    });

    const nextChats = [];
    const removedChatIds = new Set();
    for (const chat of db.chats) {
      if (chat.treeId && removedTreeIds.has(chat.treeId)) {
        removedChatIds.add(chat.id);
        continue;
      }

      const nextParticipantIds = normalizeParticipantIds(
        (chat.participantIds || []).filter((entry) => entry !== userId),
      );
      const nextBranchRootPersonIds = normalizeParticipantIds(
        (chat.branchRootPersonIds || []).filter(
          (entry) => !removedPersonIds.has(entry),
        ),
      );
      const shouldKeep = chat.type === "direct"
        ? nextParticipantIds.length === 2
        : nextParticipantIds.length >= 2;

      if (!shouldKeep) {
        removedChatIds.add(chat.id);
        continue;
      }

      nextChats.push({
        ...chat,
        participantIds: nextParticipantIds,
        branchRootPersonIds: nextBranchRootPersonIds,
      });
    }
    db.chats = nextChats;
    const activeChatIds = new Set(nextChats.map((chat) => chat.id));
    db.messages = db.messages.filter((entry) => {
      return (
        entry.senderId !== userId &&
        (!Array.isArray(entry.participants) ||
          !entry.participants.includes(userId)) &&
        activeChatIds.has(entry.chatId)
      );
    });

    db.notifications = db.notifications.filter((entry) => {
      if (entry.userId === userId) {
        return false;
      }

      const data = entry.data && typeof entry.data === "object" ? entry.data : {};
      if (
        data.userId === userId ||
        data.senderId === userId ||
        data.recipientId === userId ||
        data.actorId === userId ||
        data.targetUserId === userId ||
        data.authorId === userId ||
        data.ownerId === userId
      ) {
        return false;
      }

      if (
        (data.chatId && removedChatIds.has(data.chatId)) ||
        (data.treeId && removedTreeIds.has(data.treeId)) ||
        (data.postId && removedPostIds.has(data.postId)) ||
        (data.commentId && removedCommentIds.has(data.commentId)) ||
        (data.requestId && removedRelationRequestIds.has(data.requestId)) ||
        (data.invitationId && removedInvitationIds.has(data.invitationId))
      ) {
        return false;
      }

      return true;
    });

    db.reports = db.reports.filter((entry) => {
      return (
        entry.reporterId !== userId &&
        entry.resolvedBy !== userId &&
        !(
          entry.targetType === "user" &&
          entry.targetId === userId
        ) &&
        !(
          entry.targetType === "post" &&
          removedPostIds.has(entry.targetId)
        ) &&
        !(
          entry.targetType === "comment" &&
          removedCommentIds.has(entry.targetId)
        ) &&
        !(
          entry.targetType === "tree" &&
          removedTreeIds.has(entry.targetId)
        ) &&
        !(
          entry.targetType === "chat" &&
          removedChatIds.has(entry.targetId)
        )
      );
    });
    db.blocks = db.blocks.filter((entry) => {
      return entry.blockerId !== userId && entry.blockedUserId !== userId;
    });
    db.pushDevices = db.pushDevices.filter((entry) => entry.userId !== userId);
    const activeNotificationIds = new Set(db.notifications.map((entry) => entry.id));
    db.pushDeliveries = db.pushDeliveries.filter((entry) => {
      return (
        entry.userId !== userId &&
        (!entry.notificationId || activeNotificationIds.has(entry.notificationId))
      );
    });
    this._reconcilePersonIdentities(db);
    await this._write(db);
    return {
      userId,
      removedTreeIds: Array.from(removedTreeIds),
      removedPersonIds: Array.from(removedPersonIds),
      removedChatIds: Array.from(removedChatIds),
      removedPostIds: Array.from(removedPostIds),
    };
  }

  async listOwnedMediaUrls(userId) {
    const db = await this._read();
    return collectOwnedMediaUrlsForUser(db, userId);
  }

  async createTree({creatorId, name, description, isPrivate, kind}) {
    const db = await this._read();
    const createdAt = nowIso();
    const normalizedKind = String(kind || "family").trim().toLowerCase() === "friends"
      ? "friends"
      : "family";
    const tree = {
      id: crypto.randomUUID(),
      name: String(name || "").trim(),
      description: String(description || "").trim(),
      creatorId,
      memberIds: [creatorId],
      members: [creatorId],
      createdAt,
      updatedAt: createdAt,
      isPrivate: isPrivate !== false,
      kind: normalizedKind,
      publicSlug: null,
      isCertified: false,
      certificationNote: null,
    };

    const creator = db.users.find((entry) => entry.id === creatorId);
    const creatorProfile = creator?.profile || {};
    const creatorPerson = buildPersonRecord({
      treeId: tree.id,
      creatorId,
      userId: creatorId,
      personData: {
        firstName: creatorProfile.firstName,
        lastName: creatorProfile.lastName,
        middleName: creatorProfile.middleName,
        name: creatorProfile.displayName,
        maidenName: creatorProfile.maidenName,
        photoUrl: creatorProfile.photoUrl,
        gender: creatorProfile.gender,
        birthDate: creatorProfile.birthDate,
      },
    });

    db.trees.push(tree);
    db.persons.push(creatorPerson);
    this._appendTreeChangeRecord(db, {
      treeId: tree.id,
      actorId: creatorId,
      type: "person.created",
      personId: creatorPerson.id,
      details: {
        after: structuredClone(creatorPerson),
      },
    });
    await this._write(db);
    return structuredClone(tree);
  }

  async listUserTrees(userId) {
    const db = await this._read();
    return db.trees
      .filter((tree) => {
        return (
          tree.creatorId === userId ||
          (Array.isArray(tree.memberIds) && tree.memberIds.includes(userId))
        );
      })
      .sort((left, right) =>
        String(right.updatedAt || "").localeCompare(String(left.updatedAt || "")),
      )
      .map((tree) => structuredClone(tree));
  }

  async findTree(treeId) {
    const db = await this._read();
    const tree = db.trees.find((entry) => entry.id === treeId);
    return tree ? structuredClone(tree) : null;
  }

  async removeTreeForUser({treeId, userId}) {
    const db = await this._read();
    const treeIndex = db.trees.findIndex((entry) => entry.id === treeId);
    if (treeIndex < 0) {
      return null;
    }

    const tree = db.trees[treeIndex];
    tree.memberIds = Array.isArray(tree.memberIds) ? tree.memberIds : [];
    tree.members = Array.isArray(tree.members) ? tree.members : [];

    const isCreator = tree.creatorId === userId;
    const isMember = tree.memberIds.includes(userId) || tree.members.includes(userId);
    if (!isCreator && !isMember) {
      return false;
    }

    if (isCreator) {
      db.trees.splice(treeIndex, 1);
      db.persons = db.persons.filter((entry) => entry.treeId !== treeId);
      db.relations = db.relations.filter((entry) => entry.treeId !== treeId);
      const removedChatIds = db.chats
        .filter((entry) => entry.treeId === treeId)
        .map((entry) => entry.id);
      db.chats = db.chats.filter((entry) => entry.treeId !== treeId);
      db.messages = db.messages.filter(
        (entry) => !removedChatIds.includes(entry.chatId),
      );
      db.relationRequests = db.relationRequests.filter(
        (entry) => entry.treeId !== treeId,
      );
      db.treeInvitations = db.treeInvitations.filter(
        (entry) => entry.treeId !== treeId,
      );
      const removedPostIds = db.posts
        .filter((entry) => entry.treeId === treeId)
        .map((entry) => entry.id);
      db.posts = db.posts.filter((entry) => entry.treeId !== treeId);
      db.stories = db.stories.filter((entry) => entry.treeId !== treeId);
      db.comments = db.comments.filter(
        (entry) => !removedPostIds.includes(entry.postId),
      );
      db.notifications = db.notifications.filter(
        (entry) => entry.data?.treeId !== treeId,
      );

      const creator = db.users.find((entry) => entry.id === userId);
      if (creator && Array.isArray(creator.creatorOfTreeIds)) {
        creator.creatorOfTreeIds = creator.creatorOfTreeIds.filter(
          (entry) => entry !== treeId,
        );
        creator.updatedAt = nowIso();
      }

      await this._write(db);
      return {
        action: "deleted",
        tree: structuredClone(tree),
      };
    }

    tree.memberIds = tree.memberIds.filter((entry) => entry !== userId);
    tree.members = tree.members.filter((entry) => entry !== userId);
    tree.updatedAt = nowIso();

    for (const person of db.persons) {
      if (person.treeId === treeId && person.userId === userId) {
        person.userId = null;
        person.updatedAt = nowIso();
      }
    }

    db.relationRequests = db.relationRequests.filter((entry) => {
      return !(
        entry.treeId === treeId &&
        (entry.senderId === userId || entry.recipientId === userId)
      );
    });
    db.treeInvitations = db.treeInvitations.filter((entry) => {
      return !(entry.treeId === treeId && entry.userId === userId);
    });
    db.notifications = db.notifications.filter((entry) => {
      return !(
        entry.userId === userId &&
        entry.data?.treeId === treeId
      );
    });

    await this._write(db);
    return {
      action: "left",
      tree: structuredClone(tree),
    };
  }

  async findPublicTreeByRouteId(publicTreeId) {
    const db = await this._read();
    const normalizedRouteId = String(publicTreeId || "").trim();
    if (!normalizedRouteId) {
      return null;
    }

    const tree = db.trees.find((entry) => {
      if (entry.isPrivate !== false) {
        return false;
      }

      const publicRouteId = String(entry.publicSlug || entry.id || "").trim();
      return publicRouteId === normalizedRouteId;
    });

    return tree ? structuredClone(tree) : null;
  }

  async ensureTreeMembership(treeId, userId) {
    const db = await this._read();
    const tree = db.trees.find((entry) => entry.id === treeId);
    if (!tree) {
      return null;
    }

    tree.memberIds = Array.isArray(tree.memberIds) ? tree.memberIds : [];
    tree.members = Array.isArray(tree.members) ? tree.members : [];

    let changed = false;
    if (!tree.memberIds.includes(userId)) {
      tree.memberIds.push(userId);
      changed = true;
    }
    if (!tree.members.includes(userId)) {
      tree.members.push(userId);
      changed = true;
    }

    if (changed) {
      tree.updatedAt = nowIso();
      await this._write(db);
    }

    return structuredClone(tree);
  }

  async linkPersonToUser({treeId, personId, userId}) {
    const db = await this._read();
    const tree = db.trees.find((entry) => entry.id === treeId);
    if (!tree) {
      return null;
    }

    const person = db.persons.find(
      (entry) => entry.id === personId && entry.treeId === treeId,
    );
    if (!person) {
      return undefined;
    }

    if (person.userId && person.userId !== userId) {
      return false;
    }

    const user = db.users.find((entry) => entry.id === userId);
    if (!user) {
      return null;
    }

    const canonicalIdentity = this._ensureUserIdentity(db, userId);
    if (!canonicalIdentity) {
      return null;
    }

    const existingLinkedPerson = db.persons.find(
      (entry) =>
        entry.treeId === treeId &&
        entry.userId === userId &&
        entry.id !== person.id,
    );
    if (existingLinkedPerson) {
      this._mergePersonIntoClaimTarget(db, {
        treeId,
        preferredPerson: person,
        duplicatePerson: existingLinkedPerson,
        userId,
        actorId: userId,
      });
    }

    person.userId = userId;
    applyCanonicalProfileToPerson(person, user.profile);
    if (!this._attachPersonToIdentity(db, person, canonicalIdentity, userId)) {
      return false;
    }

    tree.memberIds = Array.isArray(tree.memberIds) ? tree.memberIds : [];
    tree.members = Array.isArray(tree.members) ? tree.members : [];
    if (!tree.memberIds.includes(userId)) {
      tree.memberIds.push(userId);
    }
    if (!tree.members.includes(userId)) {
      tree.members.push(userId);
    }
    tree.updatedAt = nowIso();
    this._reconcilePersonIdentities(db);

    await this._write(db);
    return structuredClone(person);
  }

  async ensureUserPersonInTree({treeId, userId, creatorId = userId}) {
    const db = await this._read();
    const tree = db.trees.find((entry) => entry.id === treeId);
    if (!tree) {
      return null;
    }

    const canonicalIdentity = this._ensureUserIdentity(db, userId);
    if (!canonicalIdentity) {
      return null;
    }

    const existingPerson = db.persons.find(
      (entry) => entry.treeId === treeId && entry.userId === userId,
    );
    if (existingPerson) {
      const user = db.users.find((entry) => entry.id === userId);
      applyCanonicalProfileToPerson(existingPerson, user?.profile);
      this._attachPersonToIdentity(db, existingPerson, canonicalIdentity, userId);
      tree.memberIds = Array.isArray(tree.memberIds) ? tree.memberIds : [];
      tree.members = Array.isArray(tree.members) ? tree.members : [];
      if (!tree.memberIds.includes(userId)) {
        tree.memberIds.push(userId);
      }
      if (!tree.members.includes(userId)) {
        tree.members.push(userId);
      }
      tree.updatedAt = nowIso();
      this._reconcilePersonIdentities(db);
      await this._write(db);
      return structuredClone(existingPerson);
    }

    const existingIdentityPerson = db.persons.find(
      (entry) =>
        entry.treeId === treeId &&
        entry.identityId === canonicalIdentity.id &&
        (!entry.userId || entry.userId === userId),
    );
    if (existingIdentityPerson) {
      const user = db.users.find((entry) => entry.id === userId);
      existingIdentityPerson.userId = userId;
      applyCanonicalProfileToPerson(existingIdentityPerson, user?.profile);
      this._attachPersonToIdentity(
        db,
        existingIdentityPerson,
        canonicalIdentity,
        userId,
      );
      tree.memberIds = Array.isArray(tree.memberIds) ? tree.memberIds : [];
      tree.members = Array.isArray(tree.members) ? tree.members : [];
      if (!tree.memberIds.includes(userId)) {
        tree.memberIds.push(userId);
      }
      if (!tree.members.includes(userId)) {
        tree.members.push(userId);
      }
      tree.updatedAt = nowIso();
      this._reconcilePersonIdentities(db);
      await this._write(db);
      return structuredClone(existingIdentityPerson);
    }

    const user = db.users.find((entry) => entry.id === userId);
    if (!user) {
      return null;
    }

    const profile = user.profile || {};
    const person = buildPersonRecord({
      treeId,
      creatorId,
      userId,
      identityId: canonicalIdentity.id,
      personData: {
        firstName: profile.firstName,
        lastName: profile.lastName,
        middleName: profile.middleName,
        name: profile.displayName,
        maidenName: profile.maidenName,
        photoUrl: profile.photoUrl,
        gender: profile.gender,
        birthDate: profile.birthDate,
        birthPlace: profile.birthPlace,
      },
    });
    applyCanonicalProfileToPerson(person, profile);

    db.persons.push(person);
    tree.memberIds = Array.isArray(tree.memberIds) ? tree.memberIds : [];
    tree.members = Array.isArray(tree.members) ? tree.members : [];
    if (!tree.memberIds.includes(userId)) {
      tree.memberIds.push(userId);
    }
    if (!tree.members.includes(userId)) {
      tree.members.push(userId);
    }
    tree.updatedAt = nowIso();
    this._attachPersonToIdentity(db, person, canonicalIdentity, userId);
    this._reconcilePersonIdentities(db);

    await this._write(db);
    return structuredClone(person);
  }

  async listPersons(treeId) {
    const db = await this._read();
    return db.persons
      .filter((person) => person.treeId === treeId)
      .sort((left, right) => String(left.name || "").localeCompare(String(right.name || "")))
      .map((person) => buildCanonicalPersonView(db, person));
  }

  async findPerson(treeId, personId) {
    const db = await this._read();
    const person = db.persons.find(
      (entry) => entry.id === personId && entry.treeId === treeId,
    );
    return person ? buildCanonicalPersonView(db, person) : null;
  }

  async findPersonByUserId(treeId, userId) {
    const db = await this._read();
    const person = db.persons.find(
      (entry) => entry.treeId === treeId && entry.userId === userId,
    );
    return person ? buildCanonicalPersonView(db, person) : null;
  }

  async getPersonDossier(treeId, personId) {
    const db = await this._read();
    const person = db.persons.find(
      (entry) => entry.id === personId && entry.treeId === treeId,
    );
    if (!person) {
      return null;
    }

    const linkedUser = person.userId
      ? db.users.find((entry) => entry.id === person.userId) || null
      : null;

    return {
      person: buildCanonicalPersonView(db, person),
      linkedProfile: linkedUser?.profile ? structuredClone(linkedUser.profile) : null,
    };
  }

  async createPerson({
    treeId,
    creatorId,
    personData,
    userId = null,
  }) {
    const db = await this._read();
    const tree = db.trees.find((entry) => entry.id === treeId);
    if (!tree) {
      return null;
    }

    if (userId) {
      const existingLinkedPerson = db.persons.find(
        (entry) => entry.treeId === treeId && entry.userId === userId,
      );
      if (existingLinkedPerson) {
        const canonicalIdentity = this._ensureUserIdentity(db, userId);
        if (canonicalIdentity) {
          this._attachPersonToIdentity(
            db,
            existingLinkedPerson,
            canonicalIdentity,
            userId,
          );
          await this._write(db);
        }
        return structuredClone(existingLinkedPerson);
      }
    }

    const canonicalIdentity = userId ? this._ensureUserIdentity(db, userId) : null;
    const person = buildPersonRecord({
      treeId,
      creatorId,
      personData,
      userId,
      identityId: canonicalIdentity?.id || null,
    });
    db.persons.push(person);

    if (userId) {
      tree.memberIds = Array.isArray(tree.memberIds) ? tree.memberIds : [];
      tree.members = Array.isArray(tree.members) ? tree.members : [];
      if (!tree.memberIds.includes(userId)) {
        tree.memberIds.push(userId);
      }
      if (!tree.members.includes(userId)) {
        tree.members.push(userId);
      }
    }
    tree.updatedAt = nowIso();
    if (canonicalIdentity) {
      this._attachPersonToIdentity(db, person, canonicalIdentity, userId);
    }
    this._appendTreeChangeRecord(db, {
      treeId,
      actorId: creatorId,
      type: "person.created",
      personId: person.id,
      details: {
        after: structuredClone(person),
      },
    });
    this._reconcilePersonIdentities(db);

    await this._write(db);
    return structuredClone(person);
  }

  async updatePerson(treeId, personId, personData, actorId = null) {
    const db = await this._read();
    const person = db.persons.find(
      (entry) => entry.id === personId && entry.treeId === treeId,
    );
    if (!person) {
      return null;
    }

    const previousPerson = structuredClone(person);
    const nextPerson = {
      ...person,
      ...personData,
    };
    nextPerson.userId = person.userId;
    nextPerson.identityId = person.identityId;
    nextPerson.treeId = person.treeId;
    nextPerson.creatorId = person.creatorId;
    nextPerson.name = fullNameFromPersonInput(nextPerson);
    nextPerson.maidenName = normalizeNullableString(nextPerson.maidenName);
    nextPerson.birthPlace = normalizeNullableString(nextPerson.birthPlace);
    nextPerson.deathPlace = normalizeNullableString(nextPerson.deathPlace);
    nextPerson.familySummary = resolvePersonFamilySummary(nextPerson);
    nextPerson.bio = normalizeNullableString(nextPerson.bio);
    nextPerson.notes = normalizeNullableString(nextPerson.notes);
    nextPerson.birthDate = normalizeIsoDate(nextPerson.birthDate);
    nextPerson.deathDate = normalizeIsoDate(nextPerson.deathDate);
    nextPerson.isAlive = nextPerson.deathDate === null;
    const photoState = normalizePersonPhotoGallery(nextPerson.photoGallery, {
      photoUrl: nextPerson.photoUrl,
      primaryPhotoUrl: nextPerson.primaryPhotoUrl,
    });
    nextPerson.photoUrl = photoState.photoUrl;
    nextPerson.primaryPhotoUrl = photoState.primaryPhotoUrl;
    nextPerson.photoGallery = photoState.photoGallery;
    if (person.userId) {
      const linkedUser = db.users.find((entry) => entry.id === person.userId);
      if (linkedUser?.profile) {
        applyCanonicalProfileToPerson(nextPerson, linkedUser.profile, {
          touchUpdatedAt: false,
        });
      }
    }
    nextPerson.updatedAt = nowIso();

    Object.assign(person, nextPerson);
    const tree = db.trees.find((entry) => entry.id === treeId);
    if (tree) {
      tree.updatedAt = nowIso();
    }
    this._appendTreeChangeRecord(db, {
      treeId,
      actorId,
      type: "person.updated",
      personId: person.id,
      details: {
        before: previousPerson,
        after: structuredClone(person),
      },
    });
    await this._write(db);
    return structuredClone(person);
  }

  async deletePerson(treeId, personId, actorId = null) {
    const db = await this._read();
    const person = db.persons.find(
      (entry) => entry.id === personId && entry.treeId === treeId,
    );
    if (!person) {
      return null;
    }

    const deletedPerson = structuredClone(person);
    const removedRelations = db.relations
      .filter(
        (entry) =>
          entry.treeId === treeId &&
          (entry.person1Id === personId || entry.person2Id === personId),
      )
      .map((entry) => structuredClone(entry));
    db.persons = db.persons.filter((entry) => entry.id !== personId);
    db.relations = db.relations.filter(
      (entry) =>
        entry.treeId !== treeId ||
        (entry.person1Id !== personId && entry.person2Id !== personId),
    );

    if (person.userId) {
      const remainingLinkedPerson = db.persons.find(
        (entry) => entry.treeId === treeId && entry.userId === person.userId,
      );
      if (!remainingLinkedPerson) {
        const tree = db.trees.find((entry) => entry.id === treeId);
        if (tree) {
          tree.memberIds = (tree.memberIds || []).filter(
            (memberId) => memberId !== person.userId,
          );
          tree.members = (tree.members || []).filter(
            (memberId) => memberId !== person.userId,
          );
          tree.updatedAt = nowIso();
        }
      }
    }

    for (const relation of removedRelations) {
      this._appendTreeChangeRecord(db, {
        treeId,
        actorId,
        type: "relation.deleted",
        personIds: [relation.person1Id, relation.person2Id],
        relationId: relation.id,
        details: {
          before: relation,
        },
      });
    }

    this._appendTreeChangeRecord(db, {
      treeId,
      actorId,
      type: "person.deleted",
      personId,
      details: {
        before: deletedPerson,
      },
    });
    this._reconcilePersonIdentities(db);

    await this._write(db);
    return true;
  }

  async addPersonMedia({
    treeId,
    personId,
    actorId = null,
    media = {},
  }) {
    const db = await this._read();
    const person = db.persons.find(
      (entry) => entry.id === personId && entry.treeId === treeId,
    );
    if (!person) {
      return null;
    }

    const timestamp = nowIso();
    const requestedUrl = media.url || media.mediaUrl || media.photoUrl;
    const photoState = normalizePersonPhotoGallery([
      ...(Array.isArray(person.photoGallery) ? person.photoGallery : []),
      {
        id: media.id,
        url: requestedUrl,
        thumbnailUrl: media.thumbnailUrl,
        type: media.type,
        contentType: media.contentType,
        caption: media.caption,
        createdAt: timestamp,
        updatedAt: timestamp,
        isPrimary: media.isPrimary === true,
      },
    ], {
      photoUrl: media.isPrimary === true
        ? requestedUrl
        : person.photoUrl,
      primaryPhotoUrl: media.isPrimary === true
        ? requestedUrl
        : person.primaryPhotoUrl,
    });

    person.photoUrl = photoState.photoUrl;
    person.primaryPhotoUrl = photoState.primaryPhotoUrl;
    person.photoGallery = photoState.photoGallery;
    person.updatedAt = timestamp;

    const storedMedia = person.photoGallery.find((entry) => entry.url === requestedUrl)
      || person.photoGallery[0];
    const tree = db.trees.find((entry) => entry.id === treeId);
    if (tree) {
      tree.updatedAt = timestamp;
    }
    this._appendTreeChangeRecord(db, {
      treeId,
      actorId,
      type: "person_media.created",
      personId,
      mediaId: storedMedia?.id || null,
      details: {
        after: storedMedia ? structuredClone(storedMedia) : null,
      },
    });
    await this._write(db);
    return {
      person: structuredClone(person),
      media: storedMedia ? structuredClone(storedMedia) : null,
    };
  }

  async updatePersonMedia({
    treeId,
    personId,
    mediaId,
    actorId = null,
    updates = {},
  }) {
    const db = await this._read();
    const person = db.persons.find(
      (entry) => entry.id === personId && entry.treeId === treeId,
    );
    if (!person) {
      return null;
    }

    const currentGallery = Array.isArray(person.photoGallery)
      ? person.photoGallery.map((entry) => structuredClone(entry))
      : [];
    const targetIndex = currentGallery.findIndex((entry) => entry.id === mediaId);
    if (targetIndex < 0) {
      return false;
    }

    const previousMedia = structuredClone(currentGallery[targetIndex]);
    const timestamp = nowIso();
    currentGallery[targetIndex] = {
      ...currentGallery[targetIndex],
      ...updates,
      id: currentGallery[targetIndex].id,
      updatedAt: timestamp,
    };
    const updatedUrl = currentGallery[targetIndex].url;

    const requestedPrimaryUrl = updates.isPrimary === true
      ? updatedUrl
      : updates.isPrimary === false && person.primaryPhotoUrl === previousMedia.url
          ? currentGallery.find((entry) => entry.id !== mediaId)?.url || null
          : person.primaryPhotoUrl === previousMedia.url
              ? updatedUrl
              : person.primaryPhotoUrl;
    const photoState = normalizePersonPhotoGallery(currentGallery, {
      photoUrl: requestedPrimaryUrl,
      primaryPhotoUrl: requestedPrimaryUrl,
    });

    person.photoUrl = photoState.photoUrl;
    person.primaryPhotoUrl = photoState.primaryPhotoUrl;
    person.photoGallery = photoState.photoGallery;
    person.updatedAt = timestamp;

    const updatedMedia =
      person.photoGallery.find((entry) => entry.id === mediaId) || null;
    const tree = db.trees.find((entry) => entry.id === treeId);
    if (tree) {
      tree.updatedAt = timestamp;
    }
    this._appendTreeChangeRecord(db, {
      treeId,
      actorId,
      type: "person_media.updated",
      personId,
      mediaId,
      details: {
        before: previousMedia,
        after: updatedMedia ? structuredClone(updatedMedia) : null,
      },
    });
    await this._write(db);
    return {
      person: structuredClone(person),
      media: updatedMedia ? structuredClone(updatedMedia) : null,
    };
  }

  async deletePersonMedia({
    treeId,
    personId,
    mediaId,
    actorId = null,
  }) {
    const db = await this._read();
    const person = db.persons.find(
      (entry) => entry.id === personId && entry.treeId === treeId,
    );
    if (!person) {
      return null;
    }

    const currentGallery = Array.isArray(person.photoGallery)
      ? person.photoGallery.map((entry) => structuredClone(entry))
      : [];
    const removedMedia = currentGallery.find((entry) => entry.id === mediaId);
    if (!removedMedia) {
      return false;
    }

    const nextGallery = currentGallery.filter((entry) => entry.id !== mediaId);
    const nextPrimaryUrl =
      person.primaryPhotoUrl === removedMedia.url
        ? nextGallery[0]?.url || null
        : person.primaryPhotoUrl;
    const photoState = normalizePersonPhotoGallery(nextGallery, {
      photoUrl: nextPrimaryUrl,
      primaryPhotoUrl: nextPrimaryUrl,
    });
    const timestamp = nowIso();
    person.photoUrl = photoState.photoUrl;
    person.primaryPhotoUrl = photoState.primaryPhotoUrl;
    person.photoGallery = photoState.photoGallery;
    person.updatedAt = timestamp;

    const tree = db.trees.find((entry) => entry.id === treeId);
    if (tree) {
      tree.updatedAt = timestamp;
    }
    this._appendTreeChangeRecord(db, {
      treeId,
      actorId,
      type: "person_media.deleted",
      personId,
      mediaId,
      details: {
        before: removedMedia,
      },
    });
    await this._write(db);
    return {
      person: structuredClone(person),
      deletedMedia: structuredClone(removedMedia),
    };
  }

  async listRelations(treeId) {
    const db = await this._read();
    const treePersons = db.persons.filter((person) => person.treeId === treeId);
    return normalizeTreeGraph(treeId, treePersons, db.relations).relations;
  }

  async getTreeGraphSnapshot(treeId, {viewerUserId = null} = {}) {
    const db = await this._read();
    const treePersons = db.persons
      .filter((person) => person.treeId === treeId)
      .map((person) => buildCanonicalPersonView(db, person));
    if (treePersons.length === 0 && !db.trees.some((tree) => tree.id === treeId)) {
      return null;
    }

    const viewerPerson = viewerUserId
      ? db.persons.find(
          (person) => person.treeId === treeId && person.userId === viewerUserId,
        )
      : null;

    return buildTreeGraphSnapshot({
      treeId,
      persons: treePersons,
      relations: db.relations,
      viewerPersonId: viewerPerson?.id || null,
    });
  }

  async listTreeChangeRecords(treeId, {
    personId = null,
    type = null,
    actorId = null,
  } = {}) {
    const db = await this._read();
    return db.treeChangeRecords
      .filter((record) => {
        if (record.treeId !== treeId) {
          return false;
        }
        if (personId) {
          const personIds = Array.isArray(record.personIds)
            ? record.personIds
            : [];
          if (record.personId !== personId && !personIds.includes(personId)) {
            return false;
          }
        }
        if (type && record.type !== type) {
          return false;
        }
        if (actorId && record.actorId !== actorId) {
          return false;
        }
        return true;
      })
      .sort((left, right) =>
        String(right.createdAt || "").localeCompare(String(left.createdAt || "")),
      )
      .map((record) => structuredClone(record));
  }

  async upsertRelation({
    treeId,
    person1Id,
    person2Id,
    relation1to2,
    relation2to1,
    customRelationLabel1to2 = undefined,
    customRelationLabel2to1 = undefined,
    isConfirmed = true,
    marriageDate = undefined,
    divorceDate = undefined,
    createdBy = null,
    parentSetId = undefined,
    parentSetType = "biological",
    isPrimaryParentSet = undefined,
    unionId = undefined,
    unionType = undefined,
    unionStatus = undefined,
  }) {
    const db = await this._read();
    const person1Exists = db.persons.some(
      (entry) => entry.id === person1Id && entry.treeId === treeId,
    );
    const person2Exists = db.persons.some(
      (entry) => entry.id === person2Id && entry.treeId === treeId,
    );
    if (!person1Exists || !person2Exists) {
      return null;
    }

    const resolvedRelation2to1 =
      relation2to1 || relationMirror(relation1to2);
    const normalizedRelation1to2 = String(relation1to2 || "other");
    const normalizedRelation2to1 = String(resolvedRelation2to1 || "other");
    const normalizedCustomRelationLabel1to2 =
      customRelationLabel1to2 === undefined
        ? undefined
        : normalizeNullableString(customRelationLabel1to2);
    const normalizedCustomRelationLabel2to1 =
      customRelationLabel2to1 === undefined
        ? undefined
        : normalizeNullableString(customRelationLabel2to1);
    const resolvedMarriageDate =
      marriageDate === undefined
        ? undefined
        : normalizeOptionalIsoTimestamp(marriageDate);
    const resolvedDivorceDate =
      divorceDate === undefined
        ? undefined
        : normalizeOptionalIsoTimestamp(divorceDate);
    const treeRelations = db.relations.filter((entry) => entry.treeId === treeId);
    const findRelationRecord = (leftId, rightId) => {
      return db.relations.find((entry) => {
        return (
          entry.treeId === treeId &&
          ((entry.person1Id === leftId && entry.person2Id === rightId) ||
            (entry.person1Id === rightId && entry.person2Id === leftId))
        );
      });
    };
    const getPrimaryParentRelations = (childId) => {
      return treeRelations.filter((entry) => {
        return (
          childIdFromRelation(entry) === childId &&
          entry.isPrimaryParentSet !== false
        );
      });
    };
    const getCurrentUnionPartners = (personId) => {
      const partnerIds = new Set();
      for (const relation of treeRelations) {
        if (!isCurrentUnionRelation(relation)) {
          continue;
        }
        if (relation.person1Id === personId) {
          partnerIds.add(relation.person2Id);
        } else if (relation.person2Id === personId) {
          partnerIds.add(relation.person1Id);
        }
      }
      return Array.from(partnerIds);
    };

    const normalizedParentId =
      normalizedRelation1to2 === "parent" || normalizedRelation2to1 === "child"
        ? person1Id
        : normalizedRelation1to2 === "child" || normalizedRelation2to1 === "parent"
          ? person2Id
          : null;
    const normalizedChildId =
      normalizedRelation1to2 === "parent" || normalizedRelation2to1 === "child"
        ? person2Id
        : normalizedRelation1to2 === "child" || normalizedRelation2to1 === "parent"
          ? person1Id
          : null;
    const resolvedParentSetType = normalizedParentId
      ? normalizeParentSetType(parentSetType)
      : null;
    let resolvedParentSetId =
      normalizeNullableString(parentSetId) || null;
    let resolvedIsPrimaryParentSet =
      normalizedParentId && isPrimaryParentSet !== false;

    if (normalizedParentId && normalizedChildId && !resolvedParentSetId) {
      const existingParentRelations = treeRelations.filter((entry) => {
        return (
          childIdFromRelation(entry) === normalizedChildId &&
          normalizeParentSetType(entry.parentSetType) === resolvedParentSetType
        );
      });
      const primaryGroupId =
        existingParentRelations.find((entry) => entry.isPrimaryParentSet !== false)
          ?.parentSetId || null;
      const primaryParentIds = new Set(
        existingParentRelations
          .filter((entry) => entry.parentSetId === primaryGroupId)
          .map((entry) => parentIdFromRelation(entry))
          .filter(Boolean),
      );
      if (primaryGroupId && (primaryParentIds.has(normalizedParentId) || primaryParentIds.size < 2)) {
        resolvedParentSetId = primaryGroupId;
        resolvedIsPrimaryParentSet = true;
      } else if (!primaryGroupId) {
        resolvedParentSetId =
          `ps:${treeId}:${normalizedChildId}:${resolvedParentSetType}:primary`;
        resolvedIsPrimaryParentSet = true;
      } else {
        resolvedParentSetId =
          `ps:${treeId}:${normalizedChildId}:${resolvedParentSetType}:${crypto.randomUUID()}`;
        resolvedIsPrimaryParentSet = false;
      }
    }

    const resolvedUnionType = isUnionRelationType(normalizedRelation1to2) ||
        isUnionRelationType(normalizedRelation2to1)
      ? normalizeUnionType(unionType, {
          relationType: normalizedRelation1to2,
        })
      : null;
    const resolvedUnionStatus = resolvedUnionType
      ? normalizeUnionStatus(unionStatus, {
          relationType: normalizedRelation1to2,
          divorceDate: resolvedDivorceDate,
        })
      : null;
    const resolvedUnionId = resolvedUnionType
      ? normalizeNullableString(unionId) ||
        `union:${treeId}:${buildSortedIdKey([person1Id, person2Id])}:${resolvedUnionType}:${resolvedUnionStatus}`
      : null;

    const upsertRawRelation = ({
      leftId,
      rightId,
      leftToRight,
      rightToLeft,
      trackChange = true,
      relationCreatedBy = createdBy,
      rawParentSetId = resolvedParentSetId,
      rawParentSetType = resolvedParentSetType,
      rawIsPrimaryParentSet = resolvedIsPrimaryParentSet,
      rawUnionId = resolvedUnionId,
      rawUnionType = resolvedUnionType,
      rawUnionStatus = resolvedUnionStatus,
      rawMarriageDate = resolvedMarriageDate,
      rawDivorceDate = resolvedDivorceDate,
      rawCustomRelationLabel1to2 = normalizedCustomRelationLabel1to2,
      rawCustomRelationLabel2to1 = normalizedCustomRelationLabel2to1,
    }) => {
      const existingRelation = findRelationRecord(leftId, rightId);
      const timestamp = nowIso();
      if (existingRelation) {
        const previousRelation = structuredClone(existingRelation);
        if (
          existingRelation.person1Id === leftId &&
          existingRelation.person2Id === rightId
        ) {
          existingRelation.relation1to2 = leftToRight;
          existingRelation.relation2to1 = rightToLeft;
          if (rawCustomRelationLabel1to2 !== undefined) {
            existingRelation.customRelationLabel1to2 =
              rawCustomRelationLabel1to2 || null;
          }
          if (rawCustomRelationLabel2to1 !== undefined) {
            existingRelation.customRelationLabel2to1 =
              rawCustomRelationLabel2to1 || null;
          }
        } else {
          existingRelation.relation1to2 = rightToLeft;
          existingRelation.relation2to1 = leftToRight;
          if (rawCustomRelationLabel1to2 !== undefined) {
            existingRelation.customRelationLabel2to1 =
              rawCustomRelationLabel1to2 || null;
          }
          if (rawCustomRelationLabel2to1 !== undefined) {
            existingRelation.customRelationLabel1to2 =
              rawCustomRelationLabel2to1 || null;
          }
        }
        existingRelation.isConfirmed = isConfirmed === true;
        if (rawMarriageDate !== undefined) {
          existingRelation.marriageDate = rawMarriageDate;
        }
        if (rawDivorceDate !== undefined) {
          existingRelation.divorceDate = rawDivorceDate;
        }
        existingRelation.parentSetId = rawParentSetId || null;
        existingRelation.parentSetType = rawParentSetType || null;
        existingRelation.isPrimaryParentSet =
          rawParentSetType ? rawIsPrimaryParentSet !== false : null;
        existingRelation.unionId = rawUnionId || null;
        existingRelation.unionType = rawUnionType || null;
        existingRelation.unionStatus = rawUnionStatus || null;
        existingRelation.updatedAt = timestamp;
        if (trackChange) {
          this._appendTreeChangeRecord(db, {
            treeId,
            actorId: relationCreatedBy,
            type: "relation.updated",
            personIds: [existingRelation.person1Id, existingRelation.person2Id],
            relationId: existingRelation.id,
            details: {
              before: previousRelation,
              after: structuredClone(existingRelation),
            },
          });
        }
        return existingRelation;
      }

      const relation = {
        id: crypto.randomUUID(),
        treeId,
        person1Id: leftId,
        person2Id: rightId,
        relation1to2: leftToRight,
        relation2to1: rightToLeft,
        isConfirmed: isConfirmed === true,
        createdAt: timestamp,
        updatedAt: timestamp,
        createdBy: relationCreatedBy,
        marriageDate: rawMarriageDate ?? null,
        divorceDate: rawDivorceDate ?? null,
        customRelationLabel1to2: rawCustomRelationLabel1to2 || null,
        customRelationLabel2to1: rawCustomRelationLabel2to1 || null,
        parentSetId: rawParentSetId || null,
        parentSetType: rawParentSetType || null,
        isPrimaryParentSet:
          rawParentSetType ? rawIsPrimaryParentSet !== false : null,
        unionId: rawUnionId || null,
        unionType: rawUnionType || null,
        unionStatus: rawUnionStatus || null,
      };
      db.relations.push(relation);
      treeRelations.push(relation);
      if (trackChange) {
        this._appendTreeChangeRecord(db, {
          treeId,
          actorId: relationCreatedBy,
          type: "relation.created",
          personIds: [leftId, rightId],
          relationId: relation.id,
          details: {
            after: structuredClone(relation),
          },
        });
      }
      return relation;
    };

    const relation = upsertRawRelation({
      leftId: person1Id,
      rightId: person2Id,
      leftToRight: normalizedRelation1to2,
      rightToLeft: normalizedRelation2to1,
    });

    if (normalizedParentId && normalizedChildId && resolvedParentSetId) {
      const groupParentIds = new Set(
        treeRelations
          .filter((entry) => entry.parentSetId === resolvedParentSetId)
          .map((entry) => parentIdFromRelation(entry))
          .filter(Boolean),
      );
      if (groupParentIds.size === 1) {
        const soleParentId = Array.from(groupParentIds)[0];
        const currentPartners = getCurrentUnionPartners(soleParentId);
        if (currentPartners.length === 1) {
          const partnerId = currentPartners[0];
          if (!groupParentIds.has(partnerId)) {
            upsertRawRelation({
              leftId: partnerId,
              rightId: normalizedChildId,
              leftToRight: "parent",
              rightToLeft: "child",
              trackChange: false,
              rawParentSetId: resolvedParentSetId,
              rawParentSetType: resolvedParentSetType,
              rawIsPrimaryParentSet: resolvedIsPrimaryParentSet,
              rawUnionId: null,
              rawUnionType: null,
              rawUnionStatus: null,
              rawMarriageDate: undefined,
              rawDivorceDate: undefined,
            });
          }
        }
      }
    }

    if (
      normalizedRelation1to2 === "sibling" &&
      normalizedRelation2to1 === "sibling"
    ) {
      const person1Parents = getPrimaryParentRelations(person1Id);
      const person2Parents = getPrimaryParentRelations(person2Id);
      if (person1Parents.length === 0 && person2Parents.length > 0) {
        for (const parentRelation of person2Parents) {
          const sourceParentId = parentIdFromRelation(parentRelation);
          if (!sourceParentId) {
            continue;
          }
          upsertRawRelation({
            leftId: sourceParentId,
            rightId: person1Id,
            leftToRight: "parent",
            rightToLeft: "child",
            trackChange: false,
            rawParentSetId: parentRelation.parentSetId,
            rawParentSetType: normalizeParentSetType(parentRelation.parentSetType),
            rawIsPrimaryParentSet: parentRelation.isPrimaryParentSet !== false,
            rawUnionId: null,
            rawUnionType: null,
            rawUnionStatus: null,
            rawMarriageDate: undefined,
            rawDivorceDate: undefined,
          });
        }
      } else if (person2Parents.length === 0 && person1Parents.length > 0) {
        for (const parentRelation of person1Parents) {
          const sourceParentId = parentIdFromRelation(parentRelation);
          if (!sourceParentId) {
            continue;
          }
          upsertRawRelation({
            leftId: sourceParentId,
            rightId: person2Id,
            leftToRight: "parent",
            rightToLeft: "child",
            trackChange: false,
            rawParentSetId: parentRelation.parentSetId,
            rawParentSetType: normalizeParentSetType(parentRelation.parentSetType),
            rawIsPrimaryParentSet: parentRelation.isPrimaryParentSet !== false,
            rawUnionId: null,
            rawUnionType: null,
            rawUnionStatus: null,
            rawMarriageDate: undefined,
            rawDivorceDate: undefined,
          });
        }
      }
    }

    const tree = db.trees.find((entry) => entry.id === treeId);
    if (tree) {
      tree.updatedAt = nowIso();
    }
    await this._write(db);
    return structuredClone(relation);
  }

  async deleteRelation(treeId, relationId, actorId = null) {
    const db = await this._read();
    const relation = db.relations.find(
      (entry) => entry.id === relationId && entry.treeId === treeId,
    );
    if (!relation) {
      return null;
    }

    const deletedRelation = structuredClone(relation);
    db.relations = db.relations.filter((entry) => entry.id !== relationId);
    const tree = db.trees.find((entry) => entry.id === treeId);
    if (tree) {
      tree.updatedAt = nowIso();
    }
    this._appendTreeChangeRecord(db, {
      treeId,
      actorId,
      type: "relation.deleted",
      personIds: [relation.person1Id, relation.person2Id],
      relationId,
      details: {
        before: deletedRelation,
      },
    });
    await this._write(db);
    return deletedRelation;
  }

  async getDirectRelationBetween(treeId, person1Id, person2Id) {
    const db = await this._read();
    const relation = db.relations.find((entry) => {
      return (
        entry.treeId === treeId &&
        ((entry.person1Id === person1Id && entry.person2Id === person2Id) ||
          (entry.person1Id === person2Id && entry.person2Id === person1Id))
      );
    });

    if (!relation) {
      return null;
    }

    if (relation.person1Id === person1Id && relation.person2Id === person2Id) {
      return relation.relation1to2;
    }

    return relation.relation2to1;
  }

  async listOfflineProfilesByCreator(treeId, creatorId) {
    const db = await this._read();
    return db.persons
      .filter(
        (person) =>
          person.treeId === treeId &&
          person.creatorId === creatorId &&
          !person.userId,
      )
      .sort((left, right) =>
        String(left.name || "").localeCompare(String(right.name || "")),
      )
      .map((person) => structuredClone(person));
  }

  async findSpouseId(treeId, personId) {
    const db = await this._read();
    const relation = db.relations.find((entry) => {
      if (entry.treeId !== treeId) {
        return false;
      }

      const involvesPerson =
        entry.person1Id === personId || entry.person2Id === personId;
      const isSpouseRelation =
        entry.relation1to2 === "spouse" ||
        entry.relation2to1 === "spouse" ||
        entry.relation1to2 === "partner" ||
        entry.relation2to1 === "partner";

      return involvesPerson && isSpouseRelation;
    });

    if (!relation) {
      return null;
    }

    return relation.person1Id === personId ? relation.person2Id : relation.person1Id;
  }

  async createRelationRequest({
    treeId,
    senderId,
    recipientId,
    senderToRecipient,
    targetPersonId = null,
    message = null,
  }) {
    const db = await this._read();
    const tree = db.trees.find((entry) => entry.id === treeId);
    if (!tree) {
      return null;
    }

    const sender = db.users.find((entry) => entry.id === senderId);
    const recipient = db.users.find((entry) => entry.id === recipientId);
    if (!sender || !recipient) {
      return undefined;
    }

    if (senderId === recipientId) {
      return false;
    }

    if (targetPersonId) {
      const targetPerson = db.persons.find(
        (entry) => entry.id === targetPersonId && entry.treeId === treeId,
      );
      if (!targetPerson) {
        return "TARGET_PERSON_NOT_FOUND";
      }
    }

    const duplicate = db.relationRequests.find((entry) => {
      return (
        entry.treeId === treeId &&
        entry.senderId === senderId &&
        entry.recipientId === recipientId &&
        entry.status === "pending" &&
        String(entry.targetPersonId || "") === String(targetPersonId || "")
      );
    });
    if (duplicate) {
      return "DUPLICATE";
    }

    const timestamp = nowIso();
    const request = {
      id: crypto.randomUUID(),
      treeId,
      senderId,
      recipientId,
      senderToRecipient: String(senderToRecipient || "other"),
      targetPersonId: targetPersonId || null,
      offlineRelativeId: targetPersonId || null,
      createdAt: timestamp,
      updatedAt: timestamp,
      respondedAt: null,
      status: "pending",
      message: normalizeNullableString(message),
    };

    db.relationRequests.push(request);
    tree.updatedAt = nowIso();
    await this._write(db);
    return structuredClone(request);
  }

  async listRelationRequests({
    treeId = null,
    senderId = null,
    recipientId = null,
    status = null,
  } = {}) {
    const db = await this._read();
    return db.relationRequests
      .filter((entry) => {
        if (treeId && entry.treeId !== treeId) {
          return false;
        }
        if (senderId && entry.senderId !== senderId) {
          return false;
        }
        if (recipientId && entry.recipientId !== recipientId) {
          return false;
        }
        if (status && entry.status !== status) {
          return false;
        }
        return true;
      })
      .sort((left, right) =>
        String(right.createdAt || "").localeCompare(String(left.createdAt || "")),
      )
      .map((entry) => structuredClone(entry));
  }

  async findRelationRequest(requestId) {
    const db = await this._read();
    const request = db.relationRequests.find((entry) => entry.id === requestId);
    return request ? structuredClone(request) : null;
  }

  async respondToRelationRequest(requestId, status) {
    const db = await this._read();
    const request = db.relationRequests.find((entry) => entry.id === requestId);
    if (!request) {
      return null;
    }

    request.status = String(status || request.status || "pending");
    request.respondedAt = nowIso();
    request.updatedAt = request.respondedAt;
    await this._write(db);
    return structuredClone(request);
  }

  async createTreeInvitation({
    treeId,
    userId,
    addedBy = null,
    relationToTree = null,
  }) {
    const db = await this._read();
    const tree = db.trees.find((entry) => entry.id === treeId);
    if (!tree) {
      return null;
    }

    const user = db.users.find((entry) => entry.id === userId);
    if (!user) {
      return undefined;
    }

    const isMember =
      tree.creatorId === userId ||
      (Array.isArray(tree.memberIds) && tree.memberIds.includes(userId));
    if (isMember) {
      return false;
    }

    const duplicate = db.treeInvitations.find((entry) => {
      return (
        entry.treeId === treeId &&
        entry.userId === userId &&
        entry.role === "pending"
      );
    });
    if (duplicate) {
      return "DUPLICATE";
    }

    const invitation = createTreeInvitationRecord({
      treeId,
      userId,
      addedBy,
      relationToTree,
    });
    db.treeInvitations.push(invitation);
    tree.updatedAt = nowIso();
    await this._write(db);
    return structuredClone(invitation);
  }

  async listPendingTreeInvitations(userId) {
    const db = await this._read();
    return db.treeInvitations
      .filter((entry) => entry.userId === userId && entry.role === "pending")
      .sort((left, right) =>
        String(right.addedAt || "").localeCompare(String(left.addedAt || "")),
      )
      .map((entry) => structuredClone(entry));
  }

  async findTreeInvitation(invitationId) {
    const db = await this._read();
    const invitation = db.treeInvitations.find((entry) => entry.id === invitationId);
    return invitation ? structuredClone(invitation) : null;
  }

  async respondToTreeInvitation(invitationId, accept) {
    const db = await this._read();
    const invitationIndex = db.treeInvitations.findIndex(
      (entry) => entry.id === invitationId,
    );
    if (invitationIndex < 0) {
      return null;
    }

    const invitation = db.treeInvitations[invitationIndex];
    const tree = db.trees.find((entry) => entry.id === invitation.treeId);
    if (!tree) {
      return undefined;
    }

    if (accept) {
      tree.memberIds = Array.isArray(tree.memberIds) ? tree.memberIds : [];
      tree.members = Array.isArray(tree.members) ? tree.members : [];
      if (!tree.memberIds.includes(invitation.userId)) {
        tree.memberIds.push(invitation.userId);
      }
      if (!tree.members.includes(invitation.userId)) {
        tree.members.push(invitation.userId);
      }
      tree.updatedAt = nowIso();
    }

    db.treeInvitations.splice(invitationIndex, 1);
    await this._write(db);
    return {
      invitation: structuredClone(invitation),
      tree: structuredClone(tree),
      accepted: accept === true,
    };
  }

  async createNotification({userId, type, title, body, data}) {
    const db = await this._read();
    const user = db.users.find((entry) => entry.id === userId);
    if (!user) {
      return null;
    }

    const notification = createNotificationRecord({
      userId,
      type,
      title,
      body,
      data,
    });
    db.notifications.push(notification);
    await this._write(db);
    return structuredClone(notification);
  }

  async registerPushDevice({userId, provider, token, platform}) {
    const db = await this._read();
    const user = db.users.find((entry) => entry.id === userId);
    if (!user) {
      return null;
    }

    const normalizedProvider = String(provider || "").trim();
    const normalizedToken = String(token || "").trim();
    if (!normalizedProvider || !normalizedToken) {
      return false;
    }

    const existingDevice = db.pushDevices.find((entry) => {
      return (
        entry.userId === userId &&
        entry.provider === normalizedProvider &&
        entry.token === normalizedToken
      );
    });

    if (existingDevice) {
      existingDevice.platform = String(platform || existingDevice.platform || "unknown");
      existingDevice.updatedAt = nowIso();
      existingDevice.lastSeenAt = existingDevice.updatedAt;
      await this._write(db);
      return structuredClone(existingDevice);
    }

    const device = createPushDeviceRecord({
      userId,
      provider: normalizedProvider,
      token: normalizedToken,
      platform,
    });
    db.pushDevices.push(device);
    await this._write(db);
    return structuredClone(device);
  }

  async listPushDevices(userId) {
    const db = await this._read();
    return db.pushDevices
      .filter((entry) => entry.userId === userId)
      .sort((left, right) =>
        String(right.updatedAt || "").localeCompare(String(left.updatedAt || "")),
      )
      .map((entry) => structuredClone(entry));
  }

  async deletePushDevice(deviceId, userId) {
    const db = await this._read();
    const initialLength = db.pushDevices.length;
    db.pushDevices = db.pushDevices.filter((entry) => {
      return !(entry.id === deviceId && entry.userId === userId);
    });

    if (db.pushDevices.length === initialLength) {
      return false;
    }

    db.pushDeliveries = db.pushDeliveries.filter((entry) => entry.deviceId !== deviceId);
    await this._write(db);
    return true;
  }

  async createPushDelivery({
    notificationId,
    userId,
    deviceId,
    provider,
    status = "queued",
  }) {
    const db = await this._read();
    const delivery = createPushDeliveryRecord({
      notificationId,
      userId,
      deviceId,
      provider,
      status,
    });
    db.pushDeliveries.push(delivery);
    await this._write(db);
    return structuredClone(delivery);
  }

  async listPushDeliveries(userId, {limit = 50} = {}) {
    const db = await this._read();
    return db.pushDeliveries
      .filter((entry) => entry.userId === userId)
      .sort((left, right) =>
        String(right.createdAt || "").localeCompare(String(left.createdAt || "")),
      )
      .slice(0, limit)
      .map((entry) => structuredClone(entry));
  }

  async updatePushDelivery(
    deliveryId,
    {
      status,
      deliveredAt,
      lastError,
      responseCode,
    } = {},
  ) {
    const db = await this._read();
    const delivery = db.pushDeliveries.find((entry) => entry.id === deliveryId);
    if (!delivery) {
      return null;
    }

    if (status !== undefined) {
      delivery.status = String(status || delivery.status).trim();
    }
    if (deliveredAt !== undefined) {
      delivery.deliveredAt = deliveredAt || null;
    }
    if (lastError !== undefined) {
      delivery.lastError = lastError ? String(lastError) : null;
    }
    if (responseCode !== undefined) {
      const normalizedCode = Number(responseCode);
      delivery.responseCode = Number.isFinite(normalizedCode)
        ? normalizedCode
        : null;
    }
    delivery.updatedAt = nowIso();
    await this._write(db);
    return structuredClone(delivery);
  }

  async listNotifications(userId, {status = null, limit = 50} = {}) {
    const db = await this._read();
    return db.notifications
      .filter((entry) => {
        if (entry.userId !== userId) {
          return false;
        }
        if (status === "unread" && entry.readAt) {
          return false;
        }
        if (status === "read" && !entry.readAt) {
          return false;
        }
        return true;
      })
      .sort((left, right) =>
        String(right.createdAt || "").localeCompare(String(left.createdAt || "")),
      )
      .slice(0, limit)
      .map((entry) => structuredClone(entry));
  }

  async countUnreadNotifications(userId) {
    const db = await this._read();
    return db.notifications.filter((entry) => entry.userId === userId && !entry.readAt)
      .length;
  }

  async markNotificationRead(notificationId, userId) {
    const db = await this._read();
    const notification = db.notifications.find(
      (entry) => entry.id === notificationId && entry.userId === userId,
    );
    if (!notification) {
      return null;
    }

    if (!notification.readAt) {
      notification.readAt = nowIso();
      await this._write(db);
    }
    return structuredClone(notification);
  }

  async listUserBlocks(userId) {
    const db = await this._read();
    return db.blocks
      .filter((entry) => entry.blockerId === userId)
      .sort((left, right) =>
        String(right.createdAt || "").localeCompare(String(left.createdAt || "")),
      )
      .map((entry) => structuredClone(entry));
  }

  async createUserBlock({
    blockerId,
    blockedUserId,
    reason = null,
    metadata = {},
  }) {
    const db = await this._read();
    const normalizedBlockerId = String(blockerId || "").trim();
    const normalizedBlockedUserId = String(blockedUserId || "").trim();
    if (!normalizedBlockerId || !normalizedBlockedUserId) {
      return false;
    }
    if (normalizedBlockerId === normalizedBlockedUserId) {
      return false;
    }

    const blocker = db.users.find((entry) => entry.id === normalizedBlockerId);
    const blockedUser = db.users.find((entry) => entry.id === normalizedBlockedUserId);
    if (!blocker || !blockedUser) {
      return null;
    }

    const existingBlock = db.blocks.find((entry) => {
      return (
        entry.blockerId === normalizedBlockerId &&
        entry.blockedUserId === normalizedBlockedUserId
      );
    });
    if (existingBlock) {
      if (reason != null || (metadata && Object.keys(metadata).length > 0)) {
        existingBlock.reason = normalizeNullableString(reason) || existingBlock.reason;
        existingBlock.metadata = metadata && typeof metadata === "object"
          ? structuredClone(metadata)
          : existingBlock.metadata || {};
        existingBlock.updatedAt = nowIso();
        await this._write(db);
      }
      return structuredClone(existingBlock);
    }

    const block = createBlockRecord({
      blockerId: normalizedBlockerId,
      blockedUserId: normalizedBlockedUserId,
      reason,
      metadata,
    });
    db.blocks.push(block);
    await this._write(db);
    return structuredClone(block);
  }

  async deleteUserBlock({blockId, blockerId}) {
    const db = await this._read();
    const index = db.blocks.findIndex((entry) => {
      return entry.id === blockId && entry.blockerId === blockerId;
    });
    if (index < 0) {
      return null;
    }

    const [removed] = db.blocks.splice(index, 1);
    await this._write(db);
    return structuredClone(removed);
  }

  async isUserBlockedBetween(userIdA, userIdB) {
    const db = await this._read();
    return db.blocks.some((entry) => {
      return (
        (entry.blockerId === userIdA && entry.blockedUserId === userIdB) ||
        (entry.blockerId === userIdB && entry.blockedUserId === userIdA)
      );
    });
  }

  async createReport({
    reporterId,
    targetType,
    targetId,
    reason,
    details = null,
    metadata = {},
  }) {
    const db = await this._read();
    const normalizedReporterId = String(reporterId || "").trim();
    const normalizedTargetType = String(targetType || "").trim();
    const normalizedTargetId = String(targetId || "").trim();
    if (!normalizedReporterId || !normalizedTargetType || !normalizedTargetId) {
      return false;
    }

    if (!db.users.some((entry) => entry.id === normalizedReporterId)) {
      return null;
    }

    const report = createReportRecord({
      reporterId: normalizedReporterId,
      targetType: normalizedTargetType,
      targetId: normalizedTargetId,
      reason,
      details,
      metadata,
    });
    db.reports.push(report);
    await this._write(db);
    return structuredClone(report);
  }

  async listReports({status = null} = {}) {
    const db = await this._read();
    const normalizedStatus = normalizeNullableString(status);
    return db.reports
      .filter((entry) => {
        if (!normalizedStatus) {
          return true;
        }
        return entry.status === normalizedStatus;
      })
      .sort((left, right) =>
        String(right.createdAt || "").localeCompare(String(left.createdAt || "")),
      )
      .map((entry) => structuredClone(entry));
  }

  async resolveReport({
    reportId,
    resolvedBy,
    status,
    resolutionNote = null,
  }) {
    const db = await this._read();
    const report = db.reports.find((entry) => entry.id === reportId);
    if (!report) {
      return null;
    }

    report.status = String(status || "resolved").trim() || "resolved";
    report.resolvedBy = String(resolvedBy || "").trim() || null;
    report.resolutionNote = normalizeNullableString(resolutionNote);
    report.resolvedAt = nowIso();
    report.updatedAt = report.resolvedAt;
    await this._write(db);
    return structuredClone(report);
  }

  async listPosts({treeId = null, authorId = null, scope = null} = {}) {
    const db = await this._read();
    return db.posts
      .filter((entry) => {
        if (treeId && entry.treeId !== treeId) {
          return false;
        }
        if (authorId && entry.authorId !== authorId) {
          return false;
        }
        if (scope === "branches" && entry.scopeType !== "branches") {
          return false;
        }
        return true;
      })
      .sort((left, right) =>
        String(right.createdAt || "").localeCompare(String(left.createdAt || "")),
      )
      .map((entry) => structuredClone(entry));
  }

  async listStories({treeId = null, authorId = null} = {}) {
    const db = await this._read();
    const now = Date.now();
    const activeStories = [];
    let removedExpiredStories = false;

    for (const story of db.stories) {
      if (isExpiredAt(story.expiresAt, now)) {
        removedExpiredStories = true;
        continue;
      }
      activeStories.push(story);
    }

    if (removedExpiredStories) {
      db.stories = activeStories;
      await this._write(db);
    }

    return activeStories
      .filter((entry) => {
        if (treeId && entry.treeId !== treeId) {
          return false;
        }
        if (authorId && entry.authorId !== authorId) {
          return false;
        }
        return true;
      })
      .sort((left, right) =>
        String(right.createdAt || "").localeCompare(String(left.createdAt || "")),
      )
      .map((entry) => structuredClone(entry));
  }

  async findStory(storyId) {
    const db = await this._read();
    const story = db.stories.find((entry) => entry.id === storyId);
    if (!story) {
      return null;
    }
    if (isExpiredAt(story.expiresAt)) {
      db.stories = db.stories.filter((entry) => entry.id !== storyId);
      await this._write(db);
      return null;
    }
    return structuredClone(story);
  }

  async createStory({
    treeId,
    authorId,
    authorName,
    authorPhotoUrl = null,
    type = "text",
    text = null,
    mediaUrl = null,
    thumbnailUrl = null,
    expiresAt = null,
  }) {
    const db = await this._read();
    db.stories = db.stories.filter((entry) => !isExpiredAt(entry.expiresAt));

    const tree = db.trees.find((entry) => entry.id === treeId);
    const user = db.users.find((entry) => entry.id === authorId);
    if (!tree || !user) {
      return null;
    }

    const story = createStoryRecord({
      treeId,
      authorId,
      authorName,
      authorPhotoUrl,
      type,
      text,
      mediaUrl,
      thumbnailUrl,
      expiresAt,
    });
    if (story.type === "text" && !story.text) {
      return false;
    }
    if ((story.type === "image" || story.type === "video") && !story.mediaUrl) {
      return false;
    }

    db.stories.push(story);
    await this._write(db);
    return structuredClone(story);
  }

  async markStoryViewed(storyId, userId) {
    const db = await this._read();
    db.stories = db.stories.filter((entry) => !isExpiredAt(entry.expiresAt));
    const story = db.stories.find((entry) => entry.id === storyId);
    if (!story) {
      await this._write(db);
      return null;
    }

    if (story.authorId === userId) {
      return structuredClone(story);
    }

    story.viewedBy = Array.isArray(story.viewedBy) ? story.viewedBy : [];
    if (!story.viewedBy.includes(userId)) {
      story.viewedBy.push(userId);
      story.updatedAt = nowIso();
      await this._write(db);
    }
    return structuredClone(story);
  }

  async deleteStory(storyId, actorUserId) {
    const db = await this._read();
    const storyIndex = db.stories.findIndex((entry) => entry.id === storyId);
    if (storyIndex < 0) {
      return null;
    }

    const story = db.stories[storyIndex];
    if (story.authorId !== actorUserId) {
      return false;
    }

    db.stories.splice(storyIndex, 1);
    await this._write(db);
    return structuredClone(story);
  }

  async findPost(postId) {
    const db = await this._read();
    const post = db.posts.find((entry) => entry.id === postId);
    return post ? structuredClone(post) : null;
  }

  async createPost({
    treeId,
    authorId,
    authorName,
    authorPhotoUrl = null,
    content,
    imageUrls = [],
    isPublic = false,
    scopeType = "wholeTree",
    anchorPersonIds = [],
  }) {
    const db = await this._read();
    const tree = db.trees.find((entry) => entry.id === treeId);
    const user = db.users.find((entry) => entry.id === authorId);
    if (!tree || !user) {
      return null;
    }

    const post = createPostRecord({
      treeId,
      authorId,
      authorName,
      authorPhotoUrl,
      content,
      imageUrls,
      isPublic,
      scopeType,
      anchorPersonIds,
    });
    if (!post.content && post.imageUrls.length === 0) {
      return false;
    }

    db.posts.push(post);
    await this._write(db);
    return structuredClone(post);
  }

  async deletePost(postId, actorUserId) {
    const db = await this._read();
    const postIndex = db.posts.findIndex((entry) => entry.id === postId);
    if (postIndex < 0) {
      return null;
    }

    const post = db.posts[postIndex];
    if (post.authorId !== actorUserId) {
      return false;
    }

    db.posts.splice(postIndex, 1);
    db.comments = db.comments.filter((entry) => entry.postId !== postId);
    await this._write(db);
    return structuredClone(post);
  }

  async togglePostLike(postId, userId) {
    const db = await this._read();
    const post = db.posts.find((entry) => entry.id === postId);
    if (!post) {
      return null;
    }

    post.likedBy = Array.isArray(post.likedBy) ? post.likedBy : [];
    if (post.likedBy.includes(userId)) {
      post.likedBy = post.likedBy.filter((entry) => entry !== userId);
    } else {
      post.likedBy.push(userId);
    }
    post.updatedAt = nowIso();
    await this._write(db);
    return structuredClone(post);
  }

  async listPostComments(postId) {
    const db = await this._read();
    return db.comments
      .filter((entry) => entry.postId === postId)
      .sort((left, right) =>
        String(left.createdAt || "").localeCompare(String(right.createdAt || "")),
      )
      .map((entry) => structuredClone(entry));
  }

  async addPostComment({
    postId,
    authorId,
    authorName,
    authorPhotoUrl = null,
    content,
  }) {
    const db = await this._read();
    const post = db.posts.find((entry) => entry.id === postId);
    const user = db.users.find((entry) => entry.id === authorId);
    if (!post || !user) {
      return null;
    }

    const comment = createCommentRecord({
      postId,
      authorId,
      authorName,
      authorPhotoUrl,
      content,
    });
    if (!comment.content) {
      return false;
    }

    db.comments.push(comment);
    await this._write(db);
    return structuredClone(comment);
  }

  async deletePostComment({postId, commentId, actorUserId}) {
    const db = await this._read();
    const commentIndex = db.comments.findIndex((entry) => {
      return entry.id === commentId && entry.postId === postId;
    });
    if (commentIndex < 0) {
      return null;
    }

    const comment = db.comments[commentIndex];
    const post = db.posts.find((entry) => entry.id === postId);
    if (!post) {
      return null;
    }

    const canDelete =
      comment.authorId === actorUserId || post.authorId === actorUserId;
    if (!canDelete) {
      return false;
    }

    db.comments.splice(commentIndex, 1);
    await this._write(db);
    return structuredClone(comment);
  }

  _findStoredChat(db, chatId) {
    return db.chats.find((entry) => entry.id === chatId) || null;
  }

  _resolveChat(db, chatId) {
    const normalizedChatId = String(chatId || "").trim();
    const storedChat = this._findStoredChat(db, normalizedChatId);
    if (storedChat) {
      return storedChat;
    }

    const directParticipants = parseDirectParticipantsFromChatId(
      normalizedChatId,
    );
    if (directParticipants.length === 2) {
      const canonicalChatId = directParticipants.join("_");
      const storedCanonicalChat = this._findStoredChat(db, canonicalChatId);
      if (storedCanonicalChat) {
        return storedCanonicalChat;
      }
      const relatedMessages = db.messages
        .filter((entry) => {
          return (
            entry.chatId === normalizedChatId ||
            entry.chatId === canonicalChatId
          );
        })
        .sort((left, right) =>
          String(left.timestamp || "").localeCompare(String(right.timestamp || "")),
        );
      const firstTimestamp = relatedMessages[0]?.timestamp || nowIso();
      const lastTimestamp =
        relatedMessages[relatedMessages.length - 1]?.timestamp || firstTimestamp;
      return {
        id: canonicalChatId,
        type: "direct",
        participantIds: directParticipants,
        title: null,
        createdBy: directParticipants[0],
        treeId: null,
        branchRootPersonIds: [],
        createdAt: firstTimestamp,
        updatedAt: lastTimestamp,
      };
    }

    return null;
  }

  _resolveEquivalentChatIds(chatId, resolvedChat = null) {
    const relatedChatIds = new Set();
    const normalizedChatId = String(chatId || "").trim();
    if (normalizedChatId) {
      relatedChatIds.add(normalizedChatId);
    }

    const directParticipants = parseDirectParticipantsFromChatId(normalizedChatId);
    if (directParticipants.length === 2) {
      relatedChatIds.add(directParticipants.join("_"));
    }

    if (resolvedChat?.id) {
      relatedChatIds.add(String(resolvedChat.id).trim());
    }

    return relatedChatIds;
  }

  async findChat(chatId) {
    const db = await this._read();
    const chat = this._resolveChat(db, chatId);
    return chat ? structuredClone(chat) : null;
  }

  _buildChatDetails(db, chat) {
    const normalizedChat = structuredClone(chat);
    const participantIds = normalizeParticipantIds(chat.participantIds || []);
    const participants = participantIds
      .map((participantId) => {
        const user = db.users.find((entry) => entry.id === participantId);
        if (!user) {
          return null;
        }
        return {
          userId: user.id,
          displayName:
            user.profile?.displayName ||
            composeDisplayNameFromProfile(user.profile) ||
            user.email ||
            "Пользователь",
          photoUrl: user.profile?.photoUrl || null,
        };
      })
      .filter(Boolean);
    const branchRoots = Array.isArray(chat.branchRootPersonIds)
      ? chat.branchRootPersonIds
          .map((personId) => {
            const person = db.persons.find((entry) => {
              return entry.id === personId && entry.treeId === chat.treeId;
            });
            if (!person) {
              return null;
            }
            return {
              personId: person.id,
              name: person.name || "Без имени",
              photoUrl: person.photoUrl || null,
            };
          })
          .filter(Boolean)
      : [];

    return {
      chat: normalizedChat,
      participants,
      branchRoots,
    };
  }

  async getChatDetails(chatId) {
    const db = await this._read();
    const chat = this._resolveChat(db, chatId);
    if (!chat) {
      return null;
    }
    return this._buildChatDetails(db, chat);
  }

  async ensureDirectChat(userIdA, userIdB) {
    const db = await this._read();
    const participantIds = normalizeParticipantIds([userIdA, userIdB]);
    if (participantIds.length !== 2) {
      return null;
    }

    const missingUser = participantIds.some((participantId) => {
      return !db.users.some((entry) => entry.id === participantId);
    });
    if (missingUser) {
      return undefined;
    }

    const chatId = participantIds.join("_");
    let chat = this._findStoredChat(db, chatId);
    if (!chat) {
      chat = createChatRecord({
        id: chatId,
        type: "direct",
        participantIds,
        createdBy: participantIds[0],
      });
      db.chats.push(chat);
      await this._write(db);
    }

    return structuredClone(chat);
  }

  async createGroupChat({
    title,
    participantIds,
    createdBy,
    treeId = null,
    branchRootPersonIds = [],
  }) {
    const db = await this._read();
    const normalizedParticipants = normalizeParticipantIds([
      createdBy,
      ...(Array.isArray(participantIds) ? participantIds : []),
    ]);

    if (!normalizedParticipants.includes(createdBy) ||
        normalizedParticipants.length < 3) {
      return false;
    }

    const missingUser = normalizedParticipants.some((participantId) => {
      return !db.users.some((entry) => entry.id === participantId);
    });
    if (missingUser) {
      return null;
    }

    const chat = createChatRecord({
      id: `chat_${crypto.randomUUID()}`,
      type: "group",
      participantIds: normalizedParticipants,
      title,
      createdBy,
      treeId,
      branchRootPersonIds,
    });
    db.chats.push(chat);
    await this._write(db);
    return structuredClone(chat);
  }

  async updateGroupChat(chatId, {title}) {
    const db = await this._read();
    const chat = this._findStoredChat(db, chatId);
    if (!chat) {
      return null;
    }
    if (chat.type !== "group") {
      return false;
    }

    const normalizedTitle = normalizeNullableString(title);
    if (!normalizedTitle) {
      return undefined;
    }

    chat.title = normalizedTitle;
    chat.updatedAt = nowIso();
    await this._write(db);
    return structuredClone(chat);
  }

  async addGroupParticipants(chatId, participantIds) {
    const db = await this._read();
    const chat = this._findStoredChat(db, chatId);
    if (!chat) {
      return null;
    }
    if (chat.type !== "group") {
      return false;
    }

    const nextParticipantIds = normalizeParticipantIds([
      ...(chat.participantIds || []),
      ...(Array.isArray(participantIds) ? participantIds : []),
    ]);
    if (nextParticipantIds.length <= normalizeParticipantIds(chat.participantIds).length) {
      return undefined;
    }

    const missingUser = nextParticipantIds.some((participantId) => {
      return !db.users.some((entry) => entry.id === participantId);
    });
    if (missingUser) {
      return null;
    }

    chat.participantIds = nextParticipantIds;
    chat.updatedAt = nowIso();
    await this._write(db);
    return structuredClone(chat);
  }

  async removeGroupParticipant(chatId, participantId) {
    const db = await this._read();
    const chat = this._findStoredChat(db, chatId);
    if (!chat) {
      return null;
    }
    if (chat.type !== "group") {
      return false;
    }

    const normalizedParticipantId = String(participantId || "").trim();
    if (!normalizedParticipantId) {
      return undefined;
    }

    const currentParticipantIds = normalizeParticipantIds(chat.participantIds || []);
    if (!currentParticipantIds.includes(normalizedParticipantId)) {
      return undefined;
    }

    const nextParticipantIds = currentParticipantIds.filter((entry) => {
      return entry !== normalizedParticipantId;
    });
    if (nextParticipantIds.length < 3) {
      return undefined;
    }

    chat.participantIds = nextParticipantIds;
    chat.updatedAt = nowIso();
    await this._write(db);
    return structuredClone(chat);
  }

  async createBranchChat({
    treeId,
    branchRootPersonIds,
    createdBy,
    title,
  }) {
    const db = await this._read();
    const tree = db.trees.find((entry) => entry.id === treeId);
    if (!tree) {
      return null;
    }

    const treePersons = db.persons.filter((entry) => entry.treeId === treeId);
    const personIds = new Set(treePersons.map((entry) => entry.id));
    const normalizedRoots = normalizeParticipantIds(branchRootPersonIds).filter(
      (personId) => personIds.has(personId),
    );
    if (normalizedRoots.length === 0) {
      return null;
    }

    const treeRelations = db.relations.filter((entry) => entry.treeId === treeId);
    const snapshot = buildTreeGraphSnapshot({
      treeId,
      persons: treePersons,
      relations: treeRelations,
      viewerPersonId: null,
    });
    const branchBlock =
      chooseBranchBlockForPerson(snapshot, normalizedRoots[0]) || null;
    const visiblePersonIds = new Set(
      branchBlock?.memberPersonIds || normalizedRoots,
    );

    const participantIds = normalizeParticipantIds([
      createdBy,
      ...treePersons
        .filter((entry) => visiblePersonIds.has(entry.id))
        .map((entry) => String(entry.userId || "").trim())
        .filter(Boolean),
    ]);
    if (!participantIds.includes(createdBy) || participantIds.length < 2) {
      return false;
    }

    const normalizedTitle = normalizeNullableString(title);
    const existingChat = db.chats.find((entry) => {
      return (
        entry.type === "branch" &&
        entry.treeId === treeId &&
        sameNormalizedIds(entry.branchRootPersonIds || [], normalizedRoots)
      );
    });
    if (existingChat) {
      let hasChanges = false;
      if (!sameNormalizedIds(existingChat.participantIds || [], participantIds)) {
        existingChat.participantIds = participantIds;
        hasChanges = true;
      }
      if (normalizedTitle && normalizedTitle !== existingChat.title) {
        existingChat.title = normalizedTitle;
        hasChanges = true;
      }
      if (hasChanges) {
        existingChat.updatedAt = nowIso();
        await this._write(db);
      }
      return structuredClone(existingChat);
    }

    const chat = createChatRecord({
      id: `chat_${crypto.randomUUID()}`,
      type: "branch",
      participantIds,
      title: normalizedTitle,
      createdBy,
      treeId,
      branchRootPersonIds:
        branchBlock?.rootUnitId ? normalizedRoots : normalizedRoots,
    });
    db.chats.push(chat);
    await this._write(db);
    return structuredClone(chat);
  }

  async listChatMessages(chatId) {
    const db = await this._read();
    const purgedChatIds = this._purgeExpiredMessages(db);
    if (purgedChatIds.size > 0) {
      this._syncChatUpdatedAt(db, purgedChatIds);
      await this._write(db);
    }
    const chat = this._resolveChat(db, chatId);
    if (!chat) {
      return [];
    }
    const relatedChatIds = this._resolveEquivalentChatIds(chatId, chat);
    return db.messages
      .filter((message) => relatedChatIds.has(String(message.chatId || "").trim()))
      .sort((left, right) =>
        String(right.timestamp || "").localeCompare(String(left.timestamp || "")),
      )
      .map((message) => structuredClone(message));
  }

  async addChatMessage({
    chatId,
    senderId,
    text,
    attachments = [],
    mediaUrls = [],
    imageUrl = null,
    clientMessageId = null,
    expiresAt = null,
    replyTo = null,
  }) {
    const db = await this._read();
    const purgedChatIds = this._purgeExpiredMessages(db);
    let chat = this._resolveChat(db, chatId);
    if (!chat) {
      return null;
    }

    if (!db.chats.some((entry) => entry.id === chat.id)) {
      db.chats.push(chat);
    }

    const participants = normalizeParticipantIds(chat.participantIds);
    if (!participants.includes(senderId) || participants.length < 2) {
      return null;
    }

    const sender = db.users.find((entry) => entry.id === senderId);
    const normalizedText = String(text || "").trim();
    const normalizedAttachments = normalizeMessageAttachments({
      attachments,
      mediaUrls,
      imageUrl,
    });
    const normalizedMediaUrls = normalizedAttachments.map((entry) => entry.url);
    const normalizedImageUrl =
      normalizedAttachments.find((entry) => entry.type === "image")?.url ||
      normalizedAttachments[0]?.url ||
      null;
    const normalizedClientMessageId = String(clientMessageId || "").trim() || null;
    const normalizedExpiresAt = normalizeOptionalIsoTimestamp(expiresAt);
    const normalizedReplyTo = normalizeReplyReference(replyTo);
    if (!normalizedText && normalizedAttachments.length === 0) {
      return false;
    }

    const relatedChatIds = this._resolveEquivalentChatIds(chatId, chat);

    if (normalizedClientMessageId) {
      const existingMessage = db.messages.find(
        (entry) =>
          relatedChatIds.has(String(entry.chatId || "").trim()) &&
          entry.senderId === senderId &&
          entry.clientMessageId === normalizedClientMessageId,
      );
      if (existingMessage) {
        return {
          ...structuredClone(existingMessage),
          _deduplicated: true,
        };
      }
    }

    const timestamp = nowIso();
    const message = {
      id: crypto.randomUUID(),
      chatId: chat.id,
      senderId,
      text: normalizedText,
      timestamp,
      isRead: false,
      participants,
      senderName: sender?.profile?.displayName || "Пользователь",
      attachments: normalizedAttachments,
      imageUrl: normalizedImageUrl,
      mediaUrls: normalizedMediaUrls.length > 0 ? normalizedMediaUrls : null,
      clientMessageId: normalizedClientMessageId,
      expiresAt: normalizedExpiresAt,
      replyTo: normalizedReplyTo,
    };

    const storedChat = db.chats.find((entry) => entry.id === chat.id);
    if (storedChat) {
      storedChat.updatedAt = timestamp;
    }

    db.messages.push(message);
    if (purgedChatIds.size > 0) {
      purgedChatIds.add(chat.id);
      this._syncChatUpdatedAt(db, purgedChatIds);
    }
    await this._write(db);
    return structuredClone(message);
  }

  async updateChatMessage({
    chatId,
    messageId,
    userId,
    text,
  }) {
    const db = await this._read();
    const purgedChatIds = this._purgeExpiredMessages(db);
    const chat = this._resolveChat(db, chatId);
    if (!chat || !chat.participantIds.includes(userId)) {
      return false;
    }
    const relatedChatIds = this._resolveEquivalentChatIds(chatId, chat);

    const message = db.messages.find(
      (entry) =>
        entry.id === messageId &&
        relatedChatIds.has(String(entry.chatId || "").trim()),
    );
    if (!message) {
      return null;
    }
    if (message.senderId !== userId) {
      return undefined;
    }

    const normalizedText = String(text || "").trim();
    const attachments = normalizeMessageAttachments(message);
    if (!normalizedText && attachments.length === 0) {
      return "EMPTY_MESSAGE";
    }

    message.text = normalizedText;
    message.updatedAt = nowIso();
    const storedChat = db.chats.find((entry) => entry.id === chat.id);
    if (storedChat) {
      storedChat.updatedAt = message.updatedAt;
    }
    if (purgedChatIds.size > 0) {
      purgedChatIds.add(chat.id);
      this._syncChatUpdatedAt(db, purgedChatIds);
    }
    await this._write(db);
    return structuredClone(message);
  }

  async deleteChatMessage({
    chatId,
    messageId,
    userId,
  }) {
    const db = await this._read();
    const purgedChatIds = this._purgeExpiredMessages(db);
    const chat = this._resolveChat(db, chatId);
    if (!chat || !chat.participantIds.includes(userId)) {
      return false;
    }
    const relatedChatIds = this._resolveEquivalentChatIds(chatId, chat);

    const messageIndex = db.messages.findIndex(
      (entry) =>
        entry.id === messageId &&
        relatedChatIds.has(String(entry.chatId || "").trim()),
    );
    if (messageIndex === -1) {
      return null;
    }

    const message = db.messages[messageIndex];
    if (message.senderId !== userId) {
      return undefined;
    }

    db.messages.splice(messageIndex, 1);
    const storedChat = db.chats.find((entry) => entry.id === chat.id);
    if (storedChat) {
      storedChat.updatedAt = nowIso();
    }
    purgedChatIds.add(chat.id);
    this._syncChatUpdatedAt(db, purgedChatIds);
    await this._write(db);
    return structuredClone(message);
  }

  async markChatAsRead(chatId, userId) {
    const db = await this._read();
    const purgedChatIds = this._purgeExpiredMessages(db);
    const chat = this._resolveChat(db, chatId);
    if (!chat || !chat.participantIds.includes(userId)) {
      return false;
    }
    const relatedChatIds = this._resolveEquivalentChatIds(chatId, chat);

    let changed = false;

    for (const message of db.messages) {
      if (
        relatedChatIds.has(String(message.chatId || "").trim()) &&
        message.senderId !== userId &&
        message.isRead !== true
      ) {
        message.isRead = true;
        changed = true;
      }
    }

    if (purgedChatIds.size > 0) {
      this._syncChatUpdatedAt(db, purgedChatIds);
    }

    if (changed || purgedChatIds.size > 0) {
      await this._write(db);
    }

    return changed;
  }

  async createCallInvite({
    chatId,
    initiatorId,
    recipientId,
    mediaMode,
  }) {
    const db = await this._read();
    const chat = this._resolveChat(db, chatId);
    if (!chat) {
      return null;
    }

    const participantIds = normalizeParticipantIds(chat.participantIds || []);
    if (
      chat.type !== "direct" ||
      participantIds.length !== 2 ||
      !participantIds.includes(initiatorId) ||
      !participantIds.includes(recipientId)
    ) {
      return false;
    }

    const hasBusyCall = db.calls
      .map((entry) => normalizeStoredCall(entry))
      .filter(Boolean)
      .some((call) => {
        if (!isCallBusyState(call.state)) {
          return false;
        }
        return (
          call.participantIds.includes(initiatorId) ||
          call.participantIds.includes(recipientId)
        );
      });
    if (hasBusyCall) {
      return "BUSY";
    }

    const call = createCallRecord({
      chatId,
      initiatorId,
      recipientId,
      mediaMode,
    });
    db.calls.push(call);
    await this._write(db);
    return structuredClone(call);
  }

  async findCall(callId) {
    const db = await this._read();
    const call = db.calls
      .map((entry) => normalizeStoredCall(entry))
      .find((entry) => entry && entry.id === callId);
    return call ? structuredClone(call) : null;
  }

  async findActiveCall({userId, chatId = null} = {}) {
    const normalizedUserId = String(userId || "").trim();
    const normalizedChatId = String(chatId || "").trim();
    if (!normalizedUserId) {
      return null;
    }

    const db = await this._read();
    const statePriority = {
      active: 0,
      ringing: 1,
    };
    const activeCalls = db.calls
      .map((entry) => normalizeStoredCall(entry))
      .filter((call) => {
        if (!call || !isCallBusyState(call.state)) {
          return false;
        }
        if (!call.participantIds.includes(normalizedUserId)) {
          return false;
        }
        if (normalizedChatId && call.chatId !== normalizedChatId) {
          return false;
        }
        return true;
      })
      .sort((left, right) => {
        const leftPriority = statePriority[left.state] ?? 99;
        const rightPriority = statePriority[right.state] ?? 99;
        if (leftPriority != rightPriority) {
          return leftPriority - rightPriority;
        }
        return new Date(right.updatedAt) - new Date(left.updatedAt);
      });

    return activeCalls.length > 0 ? structuredClone(activeCalls[0]) : null;
  }

  async listRingingCalls() {
    const db = await this._read();
    return db.calls
      .map((entry) => normalizeStoredCall(entry))
      .filter((call) => call && call.state === "ringing")
      .map((call) => structuredClone(call));
  }

  async acceptCall({
    callId,
    userId,
    roomName,
    sessionByUserId,
  }) {
    const db = await this._read();
    const storedCall = db.calls.find((entry) => String(entry?.id || "") === callId);
    const call = normalizeStoredCall(storedCall);
    if (!storedCall || !call) {
      return null;
    }
    if (call.recipientId !== userId) {
      return false;
    }
    if (call.state !== "ringing") {
      return undefined;
    }

    const timestamp = nowIso();
    storedCall.metrics = normalizeCallMetrics(storedCall.metrics);
    storedCall.state = "active";
    storedCall.roomName = normalizeNullableString(roomName);
    storedCall.sessionByUserId = normalizeCallSessionMap(sessionByUserId);
    storedCall.acceptedAt = timestamp;
    storedCall.updatedAt = timestamp;
    storedCall.endedAt = null;
    storedCall.endedReason = null;
    storedCall.metrics.acceptLatencyMs = Math.max(
      0,
      new Date(timestamp).getTime() - new Date(call.createdAt).getTime(),
    );
    storedCall.metrics.connectedParticipantIds = [];
    storedCall.metrics.lastWebhookEvent = null;
    await this._write(db);
    return structuredClone(normalizeStoredCall(storedCall));
  }

  async markCallRoomJoinFailure({callId, reason = null}) {
    const db = await this._read();
    const storedCall = db.calls.find((entry) => String(entry?.id || "") === callId);
    const call = normalizeStoredCall(storedCall);
    if (!storedCall || !call) {
      return null;
    }

    storedCall.metrics = normalizeCallMetrics(storedCall.metrics);
    storedCall.metrics.roomJoinFailureCount += 1;
    storedCall.metrics.lastRoomJoinFailureReason = normalizeNullableString(reason);
    storedCall.updatedAt = nowIso();
    await this._write(db);
    return structuredClone(normalizeStoredCall(storedCall));
  }

  async rejectCall({callId, userId}) {
    const db = await this._read();
    const storedCall = db.calls.find((entry) => String(entry?.id || "") === callId);
    const call = normalizeStoredCall(storedCall);
    if (!storedCall || !call) {
      return null;
    }
    if (call.recipientId !== userId) {
      return false;
    }
    if (call.state !== "ringing") {
      return undefined;
    }

    const timestamp = nowIso();
    storedCall.state = "rejected";
    storedCall.updatedAt = timestamp;
    storedCall.endedAt = timestamp;
    storedCall.endedReason = "rejected";
    await this._write(db);
    return structuredClone(normalizeStoredCall(storedCall));
  }

  async cancelCall({callId, userId}) {
    const db = await this._read();
    const storedCall = db.calls.find((entry) => String(entry?.id || "") === callId);
    const call = normalizeStoredCall(storedCall);
    if (!storedCall || !call) {
      return null;
    }
    if (call.initiatorId !== userId) {
      return false;
    }
    if (call.state !== "ringing") {
      return undefined;
    }

    const timestamp = nowIso();
    storedCall.state = "cancelled";
    storedCall.updatedAt = timestamp;
    storedCall.endedAt = timestamp;
    storedCall.endedReason = "cancelled";
    await this._write(db);
    return structuredClone(normalizeStoredCall(storedCall));
  }

  async markCallMissed({callId, reason = "missed"}) {
    const db = await this._read();
    const storedCall = db.calls.find((entry) => String(entry?.id || "") === callId);
    const call = normalizeStoredCall(storedCall);
    if (!storedCall || !call) {
      return null;
    }
    if (call.state !== "ringing") {
      return undefined;
    }

    const timestamp = nowIso();
    storedCall.state = "missed";
    storedCall.updatedAt = timestamp;
    storedCall.endedAt = timestamp;
    storedCall.endedReason = normalizeNullableString(reason) || "missed";
    await this._write(db);
    return structuredClone(normalizeStoredCall(storedCall));
  }

  async hangupCall({callId, userId}) {
    const db = await this._read();
    const storedCall = db.calls.find((entry) => String(entry?.id || "") === callId);
    const call = normalizeStoredCall(storedCall);
    if (!storedCall || !call) {
      return null;
    }
    if (!call.participantIds.includes(userId)) {
      return false;
    }
    if (call.state !== "active") {
      return undefined;
    }

    const timestamp = nowIso();
    storedCall.state = "ended";
    storedCall.updatedAt = timestamp;
    storedCall.endedAt = timestamp;
    storedCall.endedReason = "hangup";
    await this._write(db);
    return structuredClone(normalizeStoredCall(storedCall));
  }

  async applyCallWebhook({roomName, event, participantIdentity = null}) {
    const normalizedRoomName = String(roomName || "").trim();
    if (!normalizedRoomName) {
      return null;
    }

    const db = await this._read();
    const storedCall = db.calls.find((entry) => {
      return normalizeNullableString(entry?.roomName) === normalizedRoomName;
    });
    const call = normalizeStoredCall(storedCall);
    if (!storedCall || !call || isCallTerminalState(call.state)) {
      return call ? structuredClone(call) : null;
    }

    const normalizedEvent = String(event || "").trim();
    const normalizedParticipantIdentity = String(participantIdentity || "").trim();
    const timestamp = nowIso();
    storedCall.metrics = normalizeCallMetrics(storedCall.metrics);
    storedCall.metrics.lastWebhookEvent = normalizedEvent || null;

    if (normalizedEvent === "participant_joined" && call.state === "active") {
      if (normalizedParticipantIdentity) {
        const wasConnected = storedCall.metrics.connectedParticipantIds.includes(
          normalizedParticipantIdentity,
        );
        if (wasConnected) {
          storedCall.metrics.reconnectCount += 1;
        } else {
          storedCall.metrics.connectedParticipantIds = normalizeParticipantIds([
            ...storedCall.metrics.connectedParticipantIds,
            normalizedParticipantIdentity,
          ]);
        }
      }
      storedCall.updatedAt = timestamp;
      await this._write(db);
      return structuredClone(normalizeStoredCall(storedCall));
    }

    if (normalizedEvent === "participant_connection_aborted" && call.state === "ringing") {
      storedCall.state = "missed";
      storedCall.updatedAt = timestamp;
      storedCall.endedAt = timestamp;
      storedCall.endedReason = normalizedParticipantIdentity || "missed";
      await this._write(db);
      return structuredClone(normalizeStoredCall(storedCall));
    }

    if (normalizedEvent === "participant_left" || normalizedEvent === "room_finished") {
      if (normalizedParticipantIdentity) {
        storedCall.metrics.connectedParticipantIds =
          storedCall.metrics.connectedParticipantIds.filter(
            (value) => value !== normalizedParticipantIdentity,
          );
      }
      storedCall.state = "ended";
      storedCall.updatedAt = timestamp;
      storedCall.endedAt = timestamp;
      storedCall.endedReason = normalizedParticipantIdentity || normalizedEvent;
      await this._write(db);
      return structuredClone(normalizeStoredCall(storedCall));
    }

    if (normalizedEvent) {
      storedCall.updatedAt = timestamp;
      await this._write(db);
      return structuredClone(normalizeStoredCall(storedCall));
    }

    return structuredClone(call);
  }

  async listChatPreviews(userId) {
    const db = await this._read();
    const purgedChatIds = this._purgeExpiredMessages(db);
    if (purgedChatIds.size > 0) {
      this._syncChatUpdatedAt(db, purgedChatIds);
      await this._write(db);
    }
    const previews = new Map();
    const relatedChats = new Map();

    for (const chat of db.chats) {
      if (Array.isArray(chat.participantIds) && chat.participantIds.includes(userId)) {
        relatedChats.set(chat.id, chat);
      }
    }

    for (const message of db.messages) {
      const resolvedChat = this._resolveChat(db, message.chatId);
      if (!resolvedChat || !resolvedChat.participantIds.includes(userId)) {
        continue;
      }
      relatedChats.set(resolvedChat.id, resolvedChat);
    }

    for (const chat of relatedChats.values()) {
      const participants = normalizeParticipantIds(chat.participantIds);
      const isGroup = chat.type === "group" || chat.type === "branch";
      const otherUserId = isGroup
        ? ""
        : participants.find((participant) => participant !== userId) || "";
      const preview = {
        chatId: chat.id,
        userId,
        type: chat.type || "direct",
        title: chat.title || null,
        photoUrl: null,
        participantIds: participants,
        otherUserId,
        otherUserName: "Пользователь",
        otherUserPhotoUrl: null,
        lastMessage: "",
        lastMessageTime: chat.updatedAt || chat.createdAt || "",
        unreadCount: 0,
        lastMessageSenderId: "",
      };

      const relevantMessages = db.messages
        .filter((message) => message.chatId === chat.id)
        .sort((left, right) =>
          String(right.timestamp || "").localeCompare(String(left.timestamp || "")),
        );
      const lastMessage = relevantMessages[0] || null;
      if (lastMessage) {
        preview.lastMessage = describeMessagePreview(lastMessage);
        preview.lastMessageTime = lastMessage.timestamp;
        preview.lastMessageSenderId = lastMessage.senderId;
      }

      preview.unreadCount = relevantMessages.filter((message) => {
        return message.senderId !== userId && message.isRead !== true;
      }).length;

      if (isGroup) {
        const otherParticipantNames = participants
          .filter((participantId) => participantId !== userId)
          .map((participantId) => {
            const participant = db.users.find((entry) => entry.id === participantId);
            return participant?.profile?.displayName || participant?.email || "";
          })
          .filter(Boolean);
        preview.otherUserName =
          chat.title ||
          (otherParticipantNames.length > 0
            ? otherParticipantNames.slice(0, 3).join(", ")
            : "Групповой чат");
      } else {
        const otherUser = db.users.find((entry) => entry.id === otherUserId);
        if (otherUser) {
          preview.otherUserName =
            otherUser.profile?.displayName || otherUser.email || "Пользователь";
          preview.otherUserPhotoUrl = otherUser.profile?.photoUrl || null;
        }
      }

      previews.set(chat.id, preview);
    }

    return Array.from(previews.values())
      .sort((left, right) =>
        String(right.lastMessageTime || "").localeCompare(
          String(left.lastMessageTime || ""),
        ),
      )
      .map((preview) => structuredClone(preview));
  }

  async listRelatedChatParticipantIds(userId) {
    const db = await this._read();
    const relatedParticipantIds = new Set();

    for (const chat of db.chats) {
      if (!Array.isArray(chat.participantIds) || !chat.participantIds.includes(userId)) {
        continue;
      }
      for (const participantId of chat.participantIds) {
        if (participantId && participantId !== userId) {
          relatedParticipantIds.add(participantId);
        }
      }
    }

    return Array.from(relatedParticipantIds);
  }

  _purgeExpiredMessages(db) {
    const expiredChatIds = new Set();
    const referenceTimeMs = Date.now();
    db.messages = db.messages.filter((message) => {
      if (isExpiredAt(message.expiresAt, referenceTimeMs)) {
        if (message.chatId) {
          expiredChatIds.add(message.chatId);
        }
        return false;
      }
      return true;
    });
    return expiredChatIds;
  }

  _syncChatUpdatedAt(db, chatIds) {
    for (const chatId of chatIds) {
      const chat = db.chats.find((entry) => entry.id === chatId);
      if (!chat) {
        continue;
      }
      const relatedChatIds = this._resolveEquivalentChatIds(chatId, chat);

      const latestMessage = db.messages
        .filter((entry) => relatedChatIds.has(String(entry.chatId || "").trim()))
        .sort((left, right) =>
          String(right.timestamp || "").localeCompare(String(left.timestamp || "")),
        )[0];

      chat.updatedAt = latestMessage?.timestamp || chat.createdAt || chat.updatedAt;
    }
  }

  async createProfileContribution({
    treeId,
    personId,
    authorUserId,
    message = null,
    fields = {},
  }) {
    const db = await this._read();
    db.profileContributions = Array.isArray(db.profileContributions)
      ? db.profileContributions
      : [];

    const person = db.persons.find(
      (entry) => entry.id === personId && entry.treeId === treeId,
    );
    if (!person || !person.userId) {
      return null;
    }

    const targetUser = db.users.find((entry) => entry.id === person.userId);
    if (!targetUser) {
      return null;
    }
    if (
      normalizeProfileContributionPolicy(
        targetUser.profile?.profileContributionPolicy,
      ) !== "suggestions"
    ) {
      return false;
    }

    const normalizedFields = normalizeProfileContributionFields(fields);
    if (Object.keys(normalizedFields).length === 0) {
      return undefined;
    }

    const contribution = {
      id: crypto.randomUUID(),
      treeId,
      personId,
      targetUserId: person.userId,
      authorUserId: normalizeNullableString(authorUserId),
      message: normalizeNullableString(message),
      fields: normalizedFields,
      status: "pending",
      createdAt: nowIso(),
      updatedAt: nowIso(),
      respondedAt: null,
      responderUserId: null,
    };

    db.profileContributions.unshift(contribution);
    await this._write(db);
    return structuredClone(contribution);
  }

  async listProfileContributions(targetUserId, {status = null} = {}) {
    const db = await this._read();
    db.profileContributions = Array.isArray(db.profileContributions)
      ? db.profileContributions
      : [];

    return db.profileContributions
      .filter((entry) => {
        if (entry.targetUserId !== targetUserId) {
          return false;
        }
        if (status && entry.status !== status) {
          return false;
        }
        return true;
      })
      .sort((left, right) =>
        String(right.createdAt || "").localeCompare(String(left.createdAt || "")),
      )
      .map((entry) => structuredClone(entry));
  }

  async respondToProfileContribution(targetUserId, contributionId, {
    accept,
  }) {
    const db = await this._read();
    db.profileContributions = Array.isArray(db.profileContributions)
      ? db.profileContributions
      : [];

    const contribution = db.profileContributions.find(
      (entry) =>
        entry.id === contributionId &&
        entry.targetUserId === targetUserId &&
        entry.status === "pending",
    );
    if (!contribution) {
      return null;
    }

    let updatedUser = null;
    if (accept === true) {
      updatedUser = await this.updateProfile(targetUserId, (profile) => {
        const nextProfile = {
          ...profile,
          ...normalizeProfileContributionFields(contribution.fields),
        };
        nextProfile.displayName =
          composeDisplayNameFromProfile(nextProfile) || profile.displayName || "";
        return nextProfile;
      });
    }

    const nextDb = accept === true ? await this._read() : db;
    nextDb.profileContributions = Array.isArray(nextDb.profileContributions)
      ? nextDb.profileContributions
      : [];
    const storedContribution = nextDb.profileContributions.find(
      (entry) => entry.id === contributionId,
    );
    if (!storedContribution) {
      return null;
    }

    storedContribution.status = accept === true ? "accepted" : "rejected";
    storedContribution.respondedAt = nowIso();
    storedContribution.updatedAt = storedContribution.respondedAt;
    storedContribution.responderUserId = targetUserId;
    await this._write(nextDb);

    return {
      contribution: structuredClone(storedContribution),
      user: updatedUser,
    };
  }

  async listProfileNotes(userId) {
    const db = await this._read();
    const user = db.users.find((entry) => entry.id === userId);
    if (!user) {
      return null;
    }

    const notes = Array.isArray(user.profileNotes) ? user.profileNotes : [];
    return notes
      .slice()
      .sort((left, right) => {
        return String(right.createdAt || "").localeCompare(
          String(left.createdAt || ""),
        );
      })
      .map((note) => structuredClone(note));
  }

  async addProfileNote(userId, {title, content}) {
    const db = await this._read();
    const user = db.users.find((entry) => entry.id === userId);
    if (!user) {
      return null;
    }

    const note = createProfileNote({title, content});
    user.profileNotes = Array.isArray(user.profileNotes) ? user.profileNotes : [];
    user.profileNotes.unshift(note);
    user.updatedAt = nowIso();
    await this._write(db);
    return structuredClone(note);
  }

  async updateProfileNote(userId, noteId, {title, content}) {
    const db = await this._read();
    const user = db.users.find((entry) => entry.id === userId);
    if (!user) {
      return null;
    }

    user.profileNotes = Array.isArray(user.profileNotes) ? user.profileNotes : [];
    const note = user.profileNotes.find((entry) => entry.id === noteId);
    if (!note) {
      return undefined;
    }

    note.title = String(title || note.title || "").trim();
    note.content = String(content || note.content || "").trim();
    note.updatedAt = nowIso();
    user.updatedAt = nowIso();
    await this._write(db);
    return structuredClone(note);
  }

  async deleteProfileNote(userId, noteId) {
    const db = await this._read();
    const user = db.users.find((entry) => entry.id === userId);
    if (!user) {
      return null;
    }

    user.profileNotes = Array.isArray(user.profileNotes) ? user.profileNotes : [];
    const initialLength = user.profileNotes.length;
    user.profileNotes = user.profileNotes.filter((entry) => entry.id !== noteId);
    if (user.profileNotes.length === initialLength) {
      return false;
    }

    user.updatedAt = nowIso();
    await this._write(db);
    return true;
  }

  async searchUsers({query, limit}) {
    const db = await this._read();
    const normalizedQuery = String(query || "").trim().toLowerCase();
    if (!normalizedQuery) {
      return [];
    }

    return db.users
      .filter((user) => {
        const profile = user.profile || {};
        return (
          String(user.email || "").toLowerCase().includes(normalizedQuery) ||
          String(profile.displayName || "")
            .toLowerCase()
            .includes(normalizedQuery) ||
          String(profile.username || "")
            .toLowerCase()
            .includes(normalizedQuery) ||
          String(profile.firstName || "")
            .toLowerCase()
            .includes(normalizedQuery) ||
          String(profile.lastName || "")
            .toLowerCase()
            .includes(normalizedQuery) ||
          String(profile.middleName || "")
            .toLowerCase()
            .includes(normalizedQuery) ||
          String(profile.maidenName || "")
            .toLowerCase()
            .includes(normalizedQuery) ||
          String(profile.birthPlace || "")
            .toLowerCase()
            .includes(normalizedQuery)
        );
      })
      .slice(0, limit)
      .map((user) => structuredClone(user));
  }

  async searchUsersByField({field, value, limit}) {
    const db = await this._read();
    const normalizedValue = String(value || "").trim().toLowerCase();
    if (!normalizedValue) {
      return [];
    }

    return db.users
      .filter((user) => {
        if (field === "email") {
          return String(user.email || "").toLowerCase() === normalizedValue;
        }

        return (
          String(user.profile?.[field] || "").toLowerCase() === normalizedValue
        );
      })
      .slice(0, limit)
      .map((user) => structuredClone(user));
  }

}

module.exports = {
  EMPTY_DB,
  FileStore,
  buildTreeGraphSnapshot,
  buildGraphWarnings,
  buildBranchVisiblePersonIds,
  normalizeDbState,
  normalizePhoneNumber,
};
