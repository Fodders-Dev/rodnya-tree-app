const fs = require("node:fs/promises");
const path = require("node:path");
const crypto = require("node:crypto");

const EMPTY_DB = {
  users: [],
  sessions: [],
  trees: [],
  persons: [],
  personIdentities: [],
  relations: [],
  chats: [],
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
  pushDevices: [],
  pushDeliveries: [],
};

function normalizeDbState(parsed) {
  return {
    users: Array.isArray(parsed?.users) ? parsed.users : [],
    sessions: Array.isArray(parsed?.sessions) ? parsed.sessions : [],
    trees: Array.isArray(parsed?.trees) ? parsed.trees : [],
    persons: Array.isArray(parsed?.persons) ? parsed.persons : [],
    personIdentities: Array.isArray(parsed?.personIdentities)
      ? parsed.personIdentities
      : [],
    relations: Array.isArray(parsed?.relations) ? parsed.relations : [],
    chats: Array.isArray(parsed?.chats) ? parsed.chats : [],
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
    pushDevices: Array.isArray(parsed?.pushDevices) ? parsed.pushDevices : [],
    pushDeliveries: Array.isArray(parsed?.pushDeliveries)
      ? parsed.pushDeliveries
      : [],
  };
}

function nowIso() {
  return new Date().toISOString();
}

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

  async createUser({email, password, displayName}) {
    const db = await this._read();
    const normalizedEmail = String(email || "").trim().toLowerCase();

    if (db.users.some((user) => user.email === normalizedEmail)) {
      throw new Error("EMAIL_ALREADY_EXISTS");
    }

    const createdAt = nowIso();
    const {salt, passwordHash} = hashPassword(password);
    const userId = crypto.randomUUID();

    const nameParts = String(displayName || "")
      .trim()
      .split(/\s+/)
      .filter(Boolean);

    const user = {
      id: userId,
      identityId: null,
      email: normalizedEmail,
      passwordHash,
      passwordSalt: salt,
      providerIds: ["password"],
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
        countryCode: null,
        countryName: null,
        city: "",
        photoUrl: null,
        isPhoneVerified: false,
        gender: "unknown",
        maidenName: "",
        birthDate: null,
        createdAt,
        updatedAt: createdAt,
      },
      profileNotes: [],
    };

    db.users.push(user);
    await this._write(db);
    return structuredClone(user);
  }

  async authenticate(email, password) {
    const db = await this._read();
    const normalizedEmail = String(email || "").trim().toLowerCase();
    const user = db.users.find((entry) => entry.email === normalizedEmail);

    if (!user || !verifyPassword(password, user)) {
      return null;
    }

    return structuredClone(user);
  }

  async findUserById(userId) {
    const db = await this._read();
    const user = db.users.find((entry) => entry.id === userId);
    return user ? structuredClone(user) : null;
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

  async findSession(token) {
    const db = await this._read();
    const session = db.sessions.find((entry) => entry.token === token);
    return session ? structuredClone(session) : null;
  }

  async touchSession(token) {
    const db = await this._read();
    const session = db.sessions.find((entry) => entry.token === token);
    if (!session) {
      return null;
    }

    session.lastSeenAt = nowIso();
    await this._write(db);
    return structuredClone(session);
  }

  async deleteSession(token) {
    const db = await this._read();
    db.sessions = db.sessions.filter((entry) => entry.token !== token);
    await this._write(db);
  }

  async deleteSessionsForUser(userId) {
    const db = await this._read();
    db.sessions = db.sessions.filter((entry) => entry.userId !== userId);
    await this._write(db);
  }

  async updateProfile(userId, updater) {
    const db = await this._read();
    const user = db.users.find((entry) => entry.id === userId);
    if (!user) {
      return null;
    }

    const nextProfile = updater(structuredClone(user.profile));
    user.profile = {
      ...user.profile,
      ...nextProfile,
      id: user.id,
      email: user.email,
      updatedAt: nowIso(),
    };
    user.updatedAt = nowIso();

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
    if (!person.photoUrl && user.profile?.photoUrl) {
      const photoState = normalizePersonPhotoGallery(person.photoGallery, {
        photoUrl: user.profile.photoUrl,
        primaryPhotoUrl: person.primaryPhotoUrl || user.profile.photoUrl,
      });
      person.photoUrl = photoState.photoUrl;
      person.primaryPhotoUrl = photoState.primaryPhotoUrl;
      person.photoGallery = photoState.photoGallery;
    }
    if (!person.name) {
      person.name = composeDisplayNameFromProfile(user.profile);
    }
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
      existingIdentityPerson.userId = userId;
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
        notes: profile.bio,
      },
    });

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
      .map((person) => structuredClone(person));
  }

  async findPerson(treeId, personId) {
    const db = await this._read();
    const person = db.persons.find(
      (entry) => entry.id === personId && entry.treeId === treeId,
    );
    return person ? structuredClone(person) : null;
  }

  async findPersonByUserId(treeId, userId) {
    const db = await this._read();
    const person = db.persons.find(
      (entry) => entry.treeId === treeId && entry.userId === userId,
    );
    return person ? structuredClone(person) : null;
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
    return db.relations
      .filter((relation) => relation.treeId === treeId)
      .map((relation) => structuredClone(relation));
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
    isConfirmed = true,
    marriageDate = undefined,
    divorceDate = undefined,
    createdBy = null,
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

    const existingRelation = db.relations.find((entry) => {
      return (
        entry.treeId === treeId &&
        ((entry.person1Id === person1Id && entry.person2Id === person2Id) ||
          (entry.person1Id === person2Id && entry.person2Id === person1Id))
      );
    });

    const resolvedRelation2to1 =
      relation2to1 || relationMirror(relation1to2);
    const resolvedMarriageDate =
      marriageDate === undefined
        ? undefined
        : normalizeOptionalIsoTimestamp(marriageDate);
    const resolvedDivorceDate =
      divorceDate === undefined
        ? undefined
        : normalizeOptionalIsoTimestamp(divorceDate);

    if (existingRelation) {
      const previousRelation = structuredClone(existingRelation);
      if (
        existingRelation.person1Id === person1Id &&
        existingRelation.person2Id === person2Id
      ) {
        existingRelation.relation1to2 = String(relation1to2 || "other");
        existingRelation.relation2to1 = String(resolvedRelation2to1 || "other");
      } else {
        existingRelation.relation1to2 = String(resolvedRelation2to1 || "other");
        existingRelation.relation2to1 = String(relation1to2 || "other");
      }
      existingRelation.isConfirmed = isConfirmed === true;
      if (resolvedMarriageDate !== undefined) {
        existingRelation.marriageDate = resolvedMarriageDate;
      }
      if (resolvedDivorceDate !== undefined) {
        existingRelation.divorceDate = resolvedDivorceDate;
      }
      existingRelation.updatedAt = nowIso();
      const tree = db.trees.find((entry) => entry.id === treeId);
      if (tree) {
        tree.updatedAt = nowIso();
      }
      this._appendTreeChangeRecord(db, {
        treeId,
        actorId: createdBy,
        type: "relation.updated",
        personIds: [existingRelation.person1Id, existingRelation.person2Id],
        relationId: existingRelation.id,
        details: {
          before: previousRelation,
          after: structuredClone(existingRelation),
        },
      });
      await this._write(db);
      return structuredClone(existingRelation);
    }

    const timestamp = nowIso();
    const relation = {
      id: crypto.randomUUID(),
      treeId,
      person1Id,
      person2Id,
      relation1to2: String(relation1to2 || "other"),
      relation2to1: String(resolvedRelation2to1 || "other"),
      isConfirmed: isConfirmed === true,
      createdAt: timestamp,
      updatedAt: timestamp,
      createdBy,
      marriageDate: resolvedMarriageDate ?? null,
      divorceDate: resolvedDivorceDate ?? null,
    };

    db.relations.push(relation);
    const tree = db.trees.find((entry) => entry.id === treeId);
    if (tree) {
      tree.updatedAt = nowIso();
    }
    this._appendTreeChangeRecord(db, {
      treeId,
      actorId: createdBy,
      type: "relation.created",
      personIds: [person1Id, person2Id],
      relationId: relation.id,
      details: {
        after: structuredClone(relation),
      },
    });
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
    const storedChat = this._findStoredChat(db, chatId);
    if (storedChat) {
      return storedChat;
    }

    const directParticipants = parseDirectParticipantsFromChatId(chatId);
    if (directParticipants.length === 2) {
      const relatedMessages = db.messages
        .filter((entry) => entry.chatId === chatId)
        .sort((left, right) =>
          String(left.timestamp || "").localeCompare(String(right.timestamp || "")),
        );
      const firstTimestamp = relatedMessages[0]?.timestamp || nowIso();
      const lastTimestamp =
        relatedMessages[relatedMessages.length - 1]?.timestamp || firstTimestamp;
      return {
        id: chatId,
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
    const childrenByParent = new Map();
    const spousesByPerson = new Map();
    for (const relation of treeRelations) {
      const parentId = parentIdFromRelation(relation);
      const childId = childIdFromRelation(relation);
      if (parentId && childId) {
        if (!childrenByParent.has(parentId)) {
          childrenByParent.set(parentId, new Set());
        }
        childrenByParent.get(parentId).add(childId);
      }
      if (isSpouseLikeRelation(relation)) {
        if (!spousesByPerson.has(relation.person1Id)) {
          spousesByPerson.set(relation.person1Id, new Set());
        }
        if (!spousesByPerson.has(relation.person2Id)) {
          spousesByPerson.set(relation.person2Id, new Set());
        }
        spousesByPerson.get(relation.person1Id).add(relation.person2Id);
        spousesByPerson.get(relation.person2Id).add(relation.person1Id);
      }
    }

    const visiblePersonIds = new Set(normalizedRoots);
    const queue = [...normalizedRoots];
    while (queue.length > 0) {
      const currentId = queue.shift();
      for (const spouseId of spousesByPerson.get(currentId) || []) {
        if (!visiblePersonIds.has(spouseId)) {
          visiblePersonIds.add(spouseId);
          queue.push(spouseId);
        }
      }
      for (const childId of childrenByParent.get(currentId) || []) {
        if (!visiblePersonIds.has(childId)) {
          visiblePersonIds.add(childId);
          queue.push(childId);
        }
      }
    }

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
      branchRootPersonIds: normalizedRoots,
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
    return db.messages
      .filter((message) => message.chatId === chatId)
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

    if (normalizedClientMessageId) {
      const existingMessage = db.messages.find(
        (entry) =>
          entry.chatId === chatId &&
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
      chatId,
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

    const message = db.messages.find(
      (entry) => entry.id === messageId && entry.chatId === chatId,
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

    const messageIndex = db.messages.findIndex(
      (entry) => entry.id === messageId && entry.chatId === chatId,
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

    let changed = false;

    for (const message of db.messages) {
      if (
        message.chatId === chatId &&
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

      const latestMessage = db.messages
        .filter((entry) => entry.chatId === chatId)
        .sort((left, right) =>
          String(right.timestamp || "").localeCompare(String(left.timestamp || "")),
        )[0];

      chat.updatedAt = latestMessage?.timestamp || chat.createdAt || chat.updatedAt;
    }
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
          String(profile.phoneNumber || "")
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
  normalizeDbState,
};
