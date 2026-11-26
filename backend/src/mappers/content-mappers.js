const {
  normalizePublicUrl,
  normalizePublicUrlList,
} = require("../profile-utils");

function mapPost(post, commentCount = 0) {
  // Phase 3.4: surface branchIds so the Flutter feed can render
  // the "this post was published to N branches" affordance and
  // group/dedup posts visible to the user via more than one
  // branch. Always derive a non-empty list — fall back to
  // [treeId] for posts created before the field existed.
  const branchIds = Array.isArray(post.branchIds) && post.branchIds.length > 0
    ? post.branchIds
    : (post.treeId ? [post.treeId] : []);
  return {
    id: post.id,
    treeId: post.treeId,
    branchIds,
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
    circleId: post.circleId || null,
    anchorPersonIds: Array.isArray(post.anchorPersonIds)
      ? post.anchorPersonIds
      : [],
    reactions: Array.isArray(post.reactions) ? post.reactions : [],
  };
}

// Phase E1: serialize a Gathering for the API. Mirrors mapPost (branch
// fallback, public-url normalization, Array.isArray guards) plus the
// event-specific fields.
function mapGathering(gathering) {
  const branchIds =
    Array.isArray(gathering.branchIds) && gathering.branchIds.length > 0
      ? gathering.branchIds
      : (gathering.treeId ? [gathering.treeId] : []);
  return {
    id: gathering.id,
    treeId: gathering.treeId,
    branchIds,
    authorId: gathering.authorId,
    authorName: gathering.authorName || "Аноним",
    authorPhotoUrl: normalizePublicUrl(gathering.authorPhotoUrl || null),
    title: gathering.title || "",
    description: gathering.description || null,
    startAt: gathering.startAt || null,
    endAt: gathering.endAt || null,
    isAllDay: gathering.isAllDay === true,
    place: gathering.place || null,
    imageUrls: normalizePublicUrlList(gathering.imageUrls),
    scopeType: gathering.scopeType === "branches" ? "branches" : "wholeTree",
    circleId: gathering.circleId || null,
    anchorPersonIds: Array.isArray(gathering.anchorPersonIds)
      ? gathering.anchorPersonIds
      : [],
    rsvps: Array.isArray(gathering.rsvps) ? gathering.rsvps : [],
    createdAt: gathering.createdAt,
    updatedAt: gathering.updatedAt,
  };
}

// Phase E4: serialize a Poll. Mirrors mapGathering (branch fallback,
// public-url normalization) plus poll-specific fields. options +
// responses are returned as-is (public tallies, not anonymous).
function mapPoll(poll) {
  const branchIds =
    Array.isArray(poll.branchIds) && poll.branchIds.length > 0
      ? poll.branchIds
      : (poll.treeId ? [poll.treeId] : []);
  return {
    id: poll.id,
    treeId: poll.treeId,
    branchIds,
    authorId: poll.authorId,
    authorName: poll.authorName || "Аноним",
    authorPhotoUrl: normalizePublicUrl(poll.authorPhotoUrl || null),
    question: poll.question || "",
    options: Array.isArray(poll.options) ? poll.options : [],
    allowMultiple: poll.allowMultiple === true,
    closesAt: poll.closesAt || null,
    imageUrls: normalizePublicUrlList(poll.imageUrls),
    scopeType: poll.scopeType === "branches" ? "branches" : "wholeTree",
    circleId: poll.circleId || null,
    anchorPersonIds: Array.isArray(poll.anchorPersonIds)
      ? poll.anchorPersonIds
      : [],
    responses: Array.isArray(poll.responses) ? poll.responses : [],
    createdAt: poll.createdAt,
    updatedAt: poll.updatedAt,
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
    circleId: story.circleId || null,
    scopeType: story.scopeType === "branches" ? "branches" : "wholeTree",
    anchorPersonIds: Array.isArray(story.anchorPersonIds)
      ? story.anchorPersonIds
      : [],
    reactions: Array.isArray(story.reactions) ? story.reactions : [],
  };
}

function mapComment(comment) {
  const likedBy = Array.isArray(comment.likedBy) ? comment.likedBy : [];
  const parentCommentId =
    comment.parentCommentId === undefined || comment.parentCommentId === null
      ? null
      : String(comment.parentCommentId).trim() || null;
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
    reactions: Array.isArray(comment.reactions) ? comment.reactions : [],
    parentCommentId,
  };
}


module.exports = {
  mapPost,
  mapGathering,
  mapPoll,
  mapStory,
  mapComment,
};
