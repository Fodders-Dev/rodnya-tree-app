const {
  normalizeReactionEmoji,
} = require("./chat-calls");

function ensurePostReactions(db) {
  db.postReactions = Array.isArray(db.postReactions) ? db.postReactions : [];
  return db.postReactions;
}

function ensurePostCommentReactions(db) {
  db.postCommentReactions = Array.isArray(db.postCommentReactions)
    ? db.postCommentReactions
    : [];
  return db.postCommentReactions;
}

function _aggregateReactionsByKey(entries, keyField, targetId) {
  const normalizedTarget = String(targetId || "").trim();
  if (!normalizedTarget) {
    return [];
  }
  const grouped = new Map();
  for (const reaction of entries) {
    if (String(reaction?.[keyField] || "").trim() !== normalizedTarget) {
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

function aggregatePostReactions(db, postId) {
  return _aggregateReactionsByKey(ensurePostReactions(db), "postId", postId);
}

function aggregatePostCommentReactions(db, commentId) {
  return _aggregateReactionsByKey(
    ensurePostCommentReactions(db),
    "commentId",
    commentId,
  );
}

function attachPostReactions(db, post) {
  if (!post) return post;
  const clone = structuredClone(post);
  clone.reactions = aggregatePostReactions(db, clone.id);
  return clone;
}

function attachCommentReactions(db, comment) {
  if (!comment) return comment;
  const clone = structuredClone(comment);
  clone.reactions = aggregatePostCommentReactions(db, clone.id);
  return clone;
}

// SPEED-9 D: общий хвост listPostComments/listPostCommentsForPosts —
// сортировка + hydrate authorPhotoUrl + реакции. Вынесено, чтобы
// батч-версия (один _read() на страницу постов) давала БУКВАЛЬНО ту же
// форму на каждый пост, что и одиночный вызов — не две копии одной и
// той же логики, расходящиеся со временем.
function buildUsersByIdMap(db) {
  return new Map(
    (Array.isArray(db.users) ? db.users : []).map((user) => [
      String(user?.id || "").trim(),
      user,
    ]),
  );
}

function hydrateAndSortPostComments(db, entries, usersById) {
  return entries
    .slice()
    .sort((left, right) =>
      String(left.createdAt || "").localeCompare(String(right.createdAt || "")),
    )
    .map((entry) => {
      const hydrated = structuredClone(entry);
      if (!String(hydrated.authorPhotoUrl || "").trim()) {
        const author = usersById.get(String(hydrated.authorId || "").trim());
        const photoUrl = author?.profile?.photoUrl;
        if (String(photoUrl || "").trim()) {
          hydrated.authorPhotoUrl = String(photoUrl).trim();
        }
      }
      return attachCommentReactions(db, hydrated);
    });
}

function ensureStoryReactions(db) {
  db.storyReactions = Array.isArray(db.storyReactions) ? db.storyReactions : [];
  return db.storyReactions;
}

function aggregateStoryReactions(db, storyId) {
  return _aggregateReactionsByKey(ensureStoryReactions(db), "storyId", storyId);
}

function attachStoryReactions(db, story) {
  if (!story) return story;
  const clone = structuredClone(story);
  clone.reactions = aggregateStoryReactions(db, clone.id);
  return clone;
}

/// Resolve the user's primary person-card in a given tree. Smart-set
/// computation needs an anchor on the graph — we look for the first
/// person on the tree whose `userId` matches. Returns null if the
/// user isn't on the tree at all (guest, viewer, or hasn't claimed
/// their card yet).
function _resolveAnchorPerson(db, treeId, userId) {
  const normalizedUserId = String(userId || "").trim();
  if (!normalizedUserId) return null;
  return (
    (Array.isArray(db.persons) ? db.persons : []).find(
      (person) => person.treeId === treeId && person.userId === normalizedUserId,
    ) || null
  );
}

module.exports = {
  ensurePostReactions,
  ensurePostCommentReactions,
  _aggregateReactionsByKey,
  aggregatePostReactions,
  aggregatePostCommentReactions,
  attachPostReactions,
  attachCommentReactions,
  buildUsersByIdMap,
  hydrateAndSortPostComments,
  ensureStoryReactions,
  aggregateStoryReactions,
  attachStoryReactions,
  _resolveAnchorPerson,
};
