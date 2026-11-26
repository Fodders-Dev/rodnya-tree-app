const crypto = require("node:crypto");
const {
  normalizeNullableString,
  normalizeOptionalIsoTimestamp,
  normalizeParticipantIds,
  nowIso,
} = require("./utils");

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

function createPostRecord({
  treeId,
  branchIds = null,
  authorId,
  authorName,
  authorPhotoUrl = null,
  content,
  imageUrls = [],
  isPublic = false,
  scopeType = "wholeTree",
  anchorPersonIds = [],
  circleId = null,
  clientRequestId = null,
}) {
  const timestamp = nowIso();
  // Phase 3.4: a post lives in one or more branches. Default is
  // the single legacy tree id (back-compat with old clients that
  // only know treeId), but callers can pass an explicit branchIds
  // array to publish a post into multiple branches at once
  // (e.g. one family photo published to "Моя кровь" AND
  // "Семья жены" so both feeds show it without copies).
  const normalizedBranchIds = Array.isArray(branchIds)
    ? Array.from(
        new Set(
          branchIds
            .map((value) => normalizeNullableString(value))
            .filter(Boolean),
        ),
      )
    : [];
  if (normalizedBranchIds.length === 0 && treeId) {
    normalizedBranchIds.push(treeId);
  }
  return {
    id: crypto.randomUUID(),
    treeId,
    branchIds: normalizedBranchIds,
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
    circleId: normalizeNullableString(circleId),
    // Идемпотентный ключ публикации (см. createPost): по нему повтор того
    // же запроса от того же автора схлопывается в уже созданный пост.
    clientRequestId: normalizeNullableString(clientRequestId),
  };
}

// Phase E1: a «Встреча» (Gathering) — a family-event invitation. Mirrors
// createPostRecord field-for-field where they overlap (treeId, branchIds,
// author*, scopeType, anchorPersonIds, circleId) so the same circle-on-
// tree audience + multi-branch fan-out machinery applies. Event-specific
// fields: title, description, startAt/endAt (ISO strings), isAllDay,
// place (free text). rsvps stays empty until E3.
function createGatheringRecord({
  treeId,
  branchIds = null,
  authorId,
  authorName,
  authorPhotoUrl = null,
  title,
  description = null,
  startAt = null,
  endAt = null,
  isAllDay = false,
  place = null,
  imageUrls = [],
  scopeType = "wholeTree",
  anchorPersonIds = [],
  circleId = null,
}) {
  const timestamp = nowIso();
  const normalizedBranchIds = Array.isArray(branchIds)
    ? Array.from(
        new Set(
          branchIds
            .map((value) => normalizeNullableString(value))
            .filter(Boolean),
        ),
      )
    : [];
  if (normalizedBranchIds.length === 0 && treeId) {
    normalizedBranchIds.push(treeId);
  }
  return {
    id: crypto.randomUUID(),
    treeId,
    branchIds: normalizedBranchIds,
    authorId,
    authorName: String(authorName || "Аноним").trim() || "Аноним",
    authorPhotoUrl: normalizeNullableString(authorPhotoUrl),
    title: String(title || "").trim(),
    description: normalizeNullableString(description),
    startAt: normalizeNullableString(startAt),
    endAt: normalizeNullableString(endAt),
    isAllDay: isAllDay === true,
    place: normalizeNullableString(place),
    // Dedup + trim, same as createPostRecord.
    imageUrls: Array.from(
      new Set(
        (Array.isArray(imageUrls) ? imageUrls : [])
          .map((value) => String(value || "").trim())
          .filter(Boolean),
      ),
    ),
    scopeType: scopeType === "branches" ? "branches" : "wholeTree",
    anchorPersonIds: normalizeParticipantIds(anchorPersonIds),
    circleId: normalizeNullableString(circleId),
    createdAt: timestamp,
    updatedAt: timestamp,
    rsvps: [], // Phase E3.
  };
}

// Phase E4: «Опрос» (Poll). Mirrors createGatheringRecord for the shared
// audience fields (treeId/branchIds/author*/scopeType/anchorPersonIds/
// circleId) + imageUrls (dedup-trim like posts). Poll-specific: question,
// options (each normalised to {id, text}, empties dropped), allowMultiple,
// closesAt. responses (votes) stay empty until someone votes.
function createPollRecord({
  treeId,
  branchIds = null,
  authorId,
  authorName,
  authorPhotoUrl = null,
  question,
  options = [],
  allowMultiple = false,
  closesAt = null,
  imageUrls = [],
  scopeType = "wholeTree",
  anchorPersonIds = [],
  circleId = null,
}) {
  const timestamp = nowIso();
  const normalizedBranchIds = Array.isArray(branchIds)
    ? Array.from(
        new Set(
          branchIds
            .map((value) => normalizeNullableString(value))
            .filter(Boolean),
        ),
      )
    : [];
  if (normalizedBranchIds.length === 0 && treeId) {
    normalizedBranchIds.push(treeId);
  }
  const normalizedOptions = (Array.isArray(options) ? options : [])
    .map((option) => {
      // Accept a bare string or {text} — keep any existing id.
      const text =
        typeof option === "string" ? option : String(option?.text || "");
      return {id: option?.id, text: text.trim()};
    })
    .filter((option) => option.text.length > 0)
    .map((option) => ({
      id: normalizeNullableString(option.id) || crypto.randomUUID(),
      text: option.text,
    }));
  return {
    id: crypto.randomUUID(),
    treeId,
    branchIds: normalizedBranchIds,
    authorId,
    authorName: String(authorName || "Аноним").trim() || "Аноним",
    authorPhotoUrl: normalizeNullableString(authorPhotoUrl),
    question: String(question || "").trim(),
    options: normalizedOptions,
    allowMultiple: allowMultiple === true,
    closesAt: normalizeNullableString(closesAt),
    imageUrls: Array.from(
      new Set(
        (Array.isArray(imageUrls) ? imageUrls : [])
          .map((value) => String(value || "").trim())
          .filter(Boolean),
      ),
    ),
    scopeType: scopeType === "branches" ? "branches" : "wholeTree",
    anchorPersonIds: normalizeParticipantIds(anchorPersonIds),
    circleId: normalizeNullableString(circleId),
    createdAt: timestamp,
    updatedAt: timestamp,
    responses: [], // Phase E4 votes.
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
  circleId = null,
  scopeType = "wholeTree",
  anchorPersonIds = [],
}) {
  const createdAt = nowIso();
  const normalizedExpiresAt =
    normalizeOptionalIsoTimestamp(expiresAt) ||
    new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
  const normalizedScope =
    String(scopeType || "wholeTree").trim() === "branches"
      ? "branches"
      : "wholeTree";
  const normalizedAnchorIds = Array.isArray(anchorPersonIds)
    ? anchorPersonIds
        .map((id) => String(id || "").trim())
        .filter(Boolean)
    : [];
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
    circleId: normalizeNullableString(circleId),
    scopeType: normalizedScope,
    anchorPersonIds: normalizedAnchorIds,
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
  parentCommentId = null,
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
    // Two-level threading: top-level comments have parentCommentId === null,
    // replies carry the id of the top-level comment they belong to. We keep
    // the model flat (no replies-to-replies) so the UI never needs more than
    // one indent level — same model Twitter / Instagram converged on.
    parentCommentId: parentCommentId
      ? String(parentCommentId).trim() || null
      : null,
  };
}

module.exports = {
  createProfileNote,
  createPostRecord,
  createGatheringRecord,
  createPollRecord,
  normalizeStoryType,
  createStoryRecord,
  createCommentRecord,
};
