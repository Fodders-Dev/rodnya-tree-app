const {
  aggregateStoryReactions,
  attachStoryReactions,
  computeUpcomingAnniversary,
  createGatheringRecord,
  createPollRecord,
  createStoryRecord,
  ensureCirclesForTree,
  ensureStoryReactions,
  isExpiredAt,
  normalizeNullableString,
  normalizeReactionEmoji,
  nowIso,
} = require("../helpers");

module.exports = {
  // ── Phase 6.3: «Эта неделя в семье» digest ─────────────────────────
  // Aggregates the next-N-days events for a single branch: upcoming
  // birthdays of living members, memorial anniversaries of those
  // who passed, recent posts, and persons added in the last N days.
  // Computed on read — no separate index. Cheap on small branches
  // (≤200 persons each) and the alternative (a per-branch event
  // table the tree code already maintains client-side via
  // event_service.dart) was a duplicate computation; better to
  // serve a uniform shape from the server so both home + sidebar
  // can render the same payload.
  async getBranchDigest({treeId, days = 7, viewerUserId = null}) {
    const db = await this._read();
    const tree = db.trees.find((entry) => entry.id === treeId);
    if (!tree) return null;
    const now = new Date();
    const horizonDays = Math.max(1, Math.min(Number(days) || 7, 31));
    const horizonMs = horizonDays * 86400_000;
    const horizonEnd = new Date(now.getTime() + horizonMs);

    const treePersons = db.persons.filter(
      (entry) => entry.treeId === treeId,
    );

    const birthdays = [];
    const memorials = [];
    for (const person of treePersons) {
      const event = computeUpcomingAnniversary(
        person.birthDate,
        now,
        horizonDays,
      );
      if (event && (person.isAlive !== false) && !person.deathDate) {
        birthdays.push({
          personId: person.id,
          name: person.name,
          photoUrl: person.primaryPhotoUrl || person.photoUrl || null,
          birthDate: person.birthDate,
          daysUntil: event.daysUntil,
          age: event.yearsSince,
          eventDate: event.date.toISOString(),
        });
      }
      if (person.deathDate) {
        const memorial = computeUpcomingAnniversary(
          person.deathDate,
          now,
          horizonDays,
        );
        if (memorial) {
          memorials.push({
            personId: person.id,
            name: person.name,
            photoUrl: person.primaryPhotoUrl || person.photoUrl || null,
            deathDate: person.deathDate,
            daysUntil: memorial.daysUntil,
            yearsSince: memorial.yearsSince,
            eventDate: memorial.date.toISOString(),
          });
        }
      }
    }
    birthdays.sort((a, b) => a.daysUntil - b.daysUntil);
    memorials.sort((a, b) => a.daysUntil - b.daysUntil);

    // Recent posts on this branch (back-compat: branchIds OR
    // legacy treeId — same gate as listPosts).
    const recentPostsCutoffMs = now.getTime() - horizonMs;
    const circleCache = this._createCircleVisibilityCache();
    const recentPosts = db.posts
      .filter((post) => {
        const branchIds = Array.isArray(post.branchIds)
          ? post.branchIds
          : [];
        const inBranch = branchIds.includes(treeId) || post.treeId === treeId;
        if (!inBranch) return false;
        if (!this._canUserViewCirclePost(db, post, viewerUserId, circleCache)) return false;
        const created = post.createdAt
          ? new Date(post.createdAt).getTime()
          : 0;
        return Number.isFinite(created) && created >= recentPostsCutoffMs;
      })
      .sort((left, right) =>
        String(right.createdAt || "").localeCompare(
          String(left.createdAt || ""),
        ),
      )
      .slice(0, 8)
      .map((post) => ({
        postId: post.id,
        authorId: post.authorId,
        authorName: post.authorName,
        authorPhotoUrl: post.authorPhotoUrl || null,
        content: post.content,
        imageUrls: Array.isArray(post.imageUrls) ? post.imageUrls : [],
        createdAt: post.createdAt,
      }));

    // Newly-added persons on this branch — surfacing them on the
    // home digest is what makes the user feel "the family is
    // growing" rather than just "I added someone".
    const newPersons = treePersons
      .filter((person) => {
        const created = person.createdAt
          ? new Date(person.createdAt).getTime()
          : 0;
        return Number.isFinite(created) && created >= recentPostsCutoffMs;
      })
      .sort((left, right) =>
        String(right.createdAt || "").localeCompare(
          String(left.createdAt || ""),
        ),
      )
      .slice(0, 8)
      .map((person) => ({
        personId: person.id,
        name: person.name,
        photoUrl: person.primaryPhotoUrl || person.photoUrl || null,
        createdAt: person.createdAt,
      }));

    return {
      treeId,
      treeName: tree.name,
      horizonDays,
      generatedAt: now.toISOString(),
      birthdays,
      memorials,
      recentPosts,
      newPersons,
    };
  },

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
    return attachStoryReactions(db, story);
  },

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
    circleId = null,
    scopeType = "wholeTree",
    anchorPersonIds = [],
  }) {
    const db = await this._read();
    db.stories = db.stories.filter((entry) => !isExpiredAt(entry.expiresAt));

    const tree = db.trees.find((entry) => entry.id === treeId);
    const user = db.users.find((entry) => entry.id === authorId);
    if (!tree || !user) {
      return null;
    }
    const {allTreeCircle} = ensureCirclesForTree(db, tree);
    const normalizedCircleId = normalizeNullableString(circleId) || allTreeCircle?.id;
    const targetCircle = db.circles.find(
      (entry) => entry.treeId === treeId && entry.id === normalizedCircleId,
    );
    if (!targetCircle) {
      return null;
    }

    // Validate that submitted anchorPersonIds actually live on this
    // tree — drop stragglers silently rather than 400ing, so the
    // client can be a bit sloppy.
    const treePersonIds = new Set(
      db.persons
        .filter((p) => p.treeId === treeId)
        .map((p) => String(p.id || "")),
    );
    const sanitizedAnchorIds = Array.isArray(anchorPersonIds)
      ? anchorPersonIds
          .map((id) => String(id || "").trim())
          .filter((id) => treePersonIds.has(id))
      : [];

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
      circleId: targetCircle.id,
      scopeType,
      anchorPersonIds: sanitizedAnchorIds,
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
  },

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
  },

  async deleteStory(storyId, actorUserId) {
    const db = await this._read();
    const storyIndex = db.stories.findIndex((entry) => entry.id === storyId);
    if (storyIndex < 0) {
      return null;
    }

    const story = db.stories[storyIndex];
    const canDelete =
      story.authorId === actorUserId ||
      this._isActiveSemyaOwnerForTree(db, story.treeId, actorUserId);
    if (!canDelete) {
      return false;
    }

    db.stories.splice(storyIndex, 1);
    db.storyReactions = ensureStoryReactions(db).filter(
      (entry) => String(entry?.storyId || "").trim() !== storyId,
    );
    await this._write(db);
    return structuredClone(story);
  },

  async toggleStoryReaction({storyId, userId, emoji}) {
    const db = await this._read();
    db.stories = db.stories.filter((entry) => !isExpiredAt(entry.expiresAt));
    const story = db.stories.find((entry) => entry.id === storyId);
    if (!story) {
      return null;
    }
    const normalizedEmoji = normalizeReactionEmoji(emoji);
    if (!normalizedEmoji) {
      return "INVALID_EMOJI";
    }
    const reactions = ensureStoryReactions(db);
    const existingIndex = reactions.findIndex(
      (entry) =>
        String(entry?.storyId || "").trim() === story.id &&
        String(entry?.userId || "").trim() === userId &&
        normalizeReactionEmoji(entry?.emoji) === normalizedEmoji,
    );
    let added = false;
    if (existingIndex >= 0) {
      reactions.splice(existingIndex, 1);
    } else {
      reactions.push({
        storyId: story.id,
        userId,
        emoji: normalizedEmoji,
        createdAt: nowIso(),
      });
      added = true;
    }
    story.updatedAt = nowIso();
    await this._write(db);
    return {
      storyId: story.id,
      authorId: story.authorId,
      reactions: aggregateStoryReactions(db, story.id),
      added,
    };
  },

  async findGathering(gatheringId) {
    const db = await this._read();
    return db.gatherings.find((entry) => entry.id === gatheringId) || null;
  },

  // SPEED-9 B: db — опциональный уже прочитанный блоб (снимок
  // requireTreeAccess). Без него — собственный _read(), как раньше.
  async listGatherings({treeId = null, viewerUserId = null, db: prefetchedDb = null} = {}) {
    const db = prefetchedDb || (await this._read());
    const circleCache = this._createCircleVisibilityCache();
    return db.gatherings
      .filter((entry) => {
        // Same tree/branch match posts use: if a treeId filter is set,
        // the gathering matches when the requested tree is in its
        // branchIds OR equals its legacy treeId.
        if (treeId) {
          const branchIds = Array.isArray(entry.branchIds)
            ? entry.branchIds
            : [];
          const inBranches = branchIds.includes(treeId);
          const matchesLegacyTreeId = entry.treeId === treeId;
          if (!inBranches && !matchesLegacyTreeId) {
            return false;
          }
        }
        // Circle-on-tree visibility — identical gate to posts.
        if (!this._canUserViewCirclePost(db, entry, viewerUserId, circleCache)) {
          return false;
        }
        return true;
      })
      .sort((left, right) =>
        // Soonest gathering first (posts sort newest-first; an event
        // list is more useful in chronological-upcoming order).
        String(left.startAt || "").localeCompare(String(right.startAt || "")),
      );
  },

  async createGathering({
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
    const db = await this._read();
    const tree = db.trees.find((entry) => entry.id === treeId);
    const user = db.users.find((entry) => entry.id === authorId);
    if (!tree || !user) {
      return null;
    }
    const {allTreeCircle} = ensureCirclesForTree(db, tree);
    const normalizedCircleId =
      normalizeNullableString(circleId) || allTreeCircle?.id;
    const targetCircle = db.circles.find(
      (entry) => entry.treeId === treeId && entry.id === normalizedCircleId,
    );
    if (!targetCircle) {
      return null;
    }

    // Phase 3.4-style multi-branch: validate every branchId resolves to
    // a tree the author can access (mirror createPost).
    let resolvedBranchIds = null;
    if (Array.isArray(branchIds) && branchIds.length > 0) {
      const accessibleTreeIds = new Set(
        db.trees
          .filter((entry) =>
            this._userCanAccessTreeRecord(entry, authorId, db),
          )
          .map((entry) => entry.id),
      );
      resolvedBranchIds = Array.from(
        new Set(
          branchIds
            .map((value) => normalizeNullableString(value))
            .filter((value) => value && accessibleTreeIds.has(value)),
        ),
      );
      if (!resolvedBranchIds.includes(treeId)) {
        resolvedBranchIds.unshift(treeId);
      }
    }

    const gathering = createGatheringRecord({
      treeId,
      branchIds: resolvedBranchIds,
      authorId,
      authorName,
      authorPhotoUrl,
      title,
      description,
      startAt,
      endAt,
      isAllDay,
      place,
      imageUrls,
      scopeType,
      anchorPersonIds,
      circleId: targetCircle.id,
    });
    // A gathering needs at least a name and a start time.
    if (!gathering.title || !gathering.startAt) {
      return false;
    }

    db.gatherings.push(gathering);
    await this._write(db);
    return gathering;
  },

  async deleteGathering(gatheringId, actorUserId) {
    const db = await this._read();
    const index = db.gatherings.findIndex((entry) => entry.id === gatheringId);
    if (index < 0) {
      return null;
    }
    const gathering = db.gatherings[index];
    const canDelete =
      gathering.authorId === actorUserId ||
      this._isActiveSemyaOwnerForTree(db, gathering.treeId, actorUserId);
    if (!canDelete) {
      return false; // Author or active Semya owner may delete (route maps → 403).
    }
    const [removed] = db.gatherings.splice(index, 1);
    await this._write(db);
    return removed;
  },

  // Phase E3: UPSERT a viewer's RSVP on a gathering (last-write-wins per
  // userId), mirroring togglePostLike's read → mutate → write → return
  // pattern. Public tallies — the row carries userId (not anonymous).
  // headcount = extra people the responder brings (besides themselves).
  async setGatheringRsvp({
    gatheringId,
    userId,
    status,
    headcount = 0,
    note = null,
  }) {
    const db = await this._read();
    const gathering = db.gatherings.find((entry) => entry.id === gatheringId);
    if (!gathering) {
      return null;
    }
    gathering.rsvps = Array.isArray(gathering.rsvps) ? gathering.rsvps : [];
    const numericHeadcount = Number(headcount);
    const normalizedHeadcount =
        Number.isFinite(numericHeadcount) && numericHeadcount > 0
            ? Math.floor(numericHeadcount)
            : 0;
    const timestamp = nowIso();
    const existing = gathering.rsvps.find((entry) => entry.userId === userId);
    if (existing) {
      existing.status = status;
      existing.headcount = normalizedHeadcount;
      existing.note = normalizeNullableString(note);
      existing.respondedAt = timestamp;
    } else {
      gathering.rsvps.push({
        userId,
        status,
        headcount: normalizedHeadcount,
        note: normalizeNullableString(note),
        respondedAt: timestamp,
      });
    }
    gathering.updatedAt = timestamp;
    await this._write(db);
    return gathering;
  },

  async findPoll(pollId) {
    const db = await this._read();
    return db.polls.find((entry) => entry.id === pollId) || null;
  },

  // SPEED-9 B: db — опциональный уже прочитанный блоб (снимок
  // requireTreeAccess). Без него — собственный _read(), как раньше.
  async listPolls({treeId = null, viewerUserId = null, db: prefetchedDb = null} = {}) {
    const db = prefetchedDb || (await this._read());
    const circleCache = this._createCircleVisibilityCache();
    return db.polls
      .filter((entry) => {
        if (treeId) {
          const branchIds = Array.isArray(entry.branchIds)
            ? entry.branchIds
            : [];
          const inBranches = branchIds.includes(treeId);
          const matchesLegacyTreeId = entry.treeId === treeId;
          if (!inBranches && !matchesLegacyTreeId) {
            return false;
          }
        }
        if (!this._canUserViewCirclePost(db, entry, viewerUserId, circleCache)) {
          return false;
        }
        return true;
      })
      .sort((left, right) =>
        // Newest poll first (no startAt to order by, unlike gatherings).
        String(right.createdAt || "").localeCompare(
          String(left.createdAt || ""),
        ),
      );
  },

  async createPoll({
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
    const db = await this._read();
    const tree = db.trees.find((entry) => entry.id === treeId);
    const user = db.users.find((entry) => entry.id === authorId);
    if (!tree || !user) {
      return null;
    }
    const {allTreeCircle} = ensureCirclesForTree(db, tree);
    const normalizedCircleId =
      normalizeNullableString(circleId) || allTreeCircle?.id;
    const targetCircle = db.circles.find(
      (entry) => entry.treeId === treeId && entry.id === normalizedCircleId,
    );
    if (!targetCircle) {
      return null;
    }

    let resolvedBranchIds = null;
    if (Array.isArray(branchIds) && branchIds.length > 0) {
      const accessibleTreeIds = new Set(
        db.trees
          .filter((entry) =>
            this._userCanAccessTreeRecord(entry, authorId, db),
          )
          .map((entry) => entry.id),
      );
      resolvedBranchIds = Array.from(
        new Set(
          branchIds
            .map((value) => normalizeNullableString(value))
            .filter((value) => value && accessibleTreeIds.has(value)),
        ),
      );
      if (!resolvedBranchIds.includes(treeId)) {
        resolvedBranchIds.unshift(treeId);
      }
    }

    const poll = createPollRecord({
      treeId,
      branchIds: resolvedBranchIds,
      authorId,
      authorName,
      authorPhotoUrl,
      question,
      options,
      allowMultiple,
      closesAt,
      imageUrls,
      scopeType,
      anchorPersonIds,
      circleId: targetCircle.id,
    });
    // A poll needs a question and at least two options.
    if (!poll.question || poll.options.length < 2) {
      return false;
    }

    db.polls.push(poll);
    await this._write(db);
    return poll;
  },

  async resolvePollAudienceUserIds(pollId) {
    const db = await this._read();
    const poll = db.polls.find((entry) => entry.id === pollId);
    if (!poll) return [];
    const branchIds = new Set(
      Array.isArray(poll.branchIds) && poll.branchIds.length > 0
        ? poll.branchIds
        : [poll.treeId].filter(Boolean),
    );
    const circleCache = this._createCircleVisibilityCache();
    const audienceUserIds = new Set();
    for (const branchId of branchIds) {
      const tree = db.trees.find((entry) => entry.id === branchId);
      if (!tree) continue;
      const memberIds = this._listAccessibleTreeUserIds(db, tree);
      for (const memberId of memberIds) {
        if (!memberId || memberId === poll.authorId) continue;
        if (!this._canUserViewCirclePost(db, poll, memberId, circleCache)) {
          continue;
        }
        audienceUserIds.add(memberId);
      }
    }
    return Array.from(audienceUserIds);
  },

  async deletePoll(pollId, actorUserId) {
    const db = await this._read();
    const index = db.polls.findIndex((entry) => entry.id === pollId);
    if (index < 0) {
      return null;
    }
    const poll = db.polls[index];
    const canDelete =
      poll.authorId === actorUserId ||
      this._isActiveSemyaOwnerForTree(db, poll.treeId, actorUserId);
    if (!canDelete) {
      return false; // Author or active Semya owner may delete (route maps → 403).
    }
    const [removed] = db.polls.splice(index, 1);
    await this._write(db);
    return removed;
  },

  // UPSERT a viewer's vote (last-write-wins per userId), cloned from
  // setGatheringRsvp. Filters optionIds to existing option ids and, for a
  // single-choice poll, truncates to one.
  async submitPollResponse({pollId, userId, optionIds = []}) {
    const db = await this._read();
    const poll = db.polls.find((entry) => entry.id === pollId);
    if (!poll) {
      return null;
    }
    if (poll.closesAt) {
      const closesAtMs = Date.parse(poll.closesAt);
      if (Number.isFinite(closesAtMs) && closesAtMs <= Date.now()) {
        return "POLL_CLOSED";
      }
    }
    poll.responses = Array.isArray(poll.responses) ? poll.responses : [];
    const validOptionIds = new Set(
      (Array.isArray(poll.options) ? poll.options : []).map((o) => o.id),
    );
    let cleaned = Array.from(
      new Set(
        (Array.isArray(optionIds) ? optionIds : [])
          .map((id) => String(id || "").trim())
          .filter((id) => validOptionIds.has(id)),
      ),
    );
    if (cleaned.length === 0) {
      return false; // nothing valid chosen (route maps → 400)
    }
    // Single-choice → the server keeps only the first pick.
    if (poll.allowMultiple !== true) {
      cleaned = cleaned.slice(0, 1);
    }
    const timestamp = nowIso();
    const existing = poll.responses.find((entry) => entry.userId === userId);
    if (existing) {
      existing.optionIds = cleaned;
      existing.respondedAt = timestamp;
    } else {
      poll.responses.push({
        userId,
        optionIds: cleaned,
        respondedAt: timestamp,
      });
    }
    poll.updatedAt = timestamp;
    await this._write(db);
    return poll;
  },
};
