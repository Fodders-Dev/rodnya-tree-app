const crypto = require("node:crypto");
const {
  _resolveAnchorPerson,
  aggregatePostCommentReactions,
  aggregatePostReactions,
  attachCommentReactions,
  attachPostReactions,
  buildUsersByIdMap,
  computeNotificationCoalesceKey,
  createCommentRecord,
  createPostRecord,
  ensureCirclesForAllTrees,
  ensureCirclesForTree,
  ensurePostCommentReactions,
  ensurePostReactions,
  hydrateAndSortPostComments,
  normalizeChatSearchQuery,
  normalizeNullableString,
  normalizeReactionEmoji,
  normalizeSearchText,
  nowIso,
  relationMirror,
} = require("../helpers");

module.exports = {
  _userIdentityIdsInTree(db, treeId, userId) {
    const normalizedUserId = normalizeNullableString(userId);
    if (!normalizedUserId) {
      return new Set();
    }
    return new Set(
      (Array.isArray(db.persons) ? db.persons : [])
        .filter(
          (person) => person.treeId === treeId && person.userId === normalizedUserId,
        )
        .map((person) => normalizeNullableString(person.identityId))
        .filter(Boolean),
    );
  },

  async canUserViewScopedItem({item, userId, db: prefetchedDb = null} = {}) {
    if (!item) return false;
    const normalizedUserId = normalizeNullableString(userId);
    if (!normalizedUserId) return false;
    const db = prefetchedDb || (await this.readSharedSnapshot());
    const branchIds = new Set(
      [item.treeId, ...(Array.isArray(item.branchIds) ? item.branchIds : [])]
        .map((id) => normalizeNullableString(id))
        .filter(Boolean),
    );
    let hasAccessibleTree = false;
    for (const branchId of branchIds) {
      const tree = (db.trees || []).find((entry) => entry.id === branchId);
      if (tree && this._userCanAccessTreeRecord(tree, normalizedUserId, db)) {
        hasAccessibleTree = true;
        break;
      }
    }
    if (!hasAccessibleTree) {
      return false;
    }
    return this._canUserViewCirclePost(db, item, normalizedUserId);
  },

  // Ленты (posts/stories/gatherings/polls) НЕ зовут ensureCirclesForAllTrees:
  // круги нужного дерева лениво сверяет _canUserViewCircleContent, а сверка
  // всех деревьев на каждое чтение — лишний CPU и запись блоба из читающего
  // пути в обход _mutate (lost-update). Хранимое состояние кругов чинят
  // мутации графа и listCircles/findCircle.
  // SPEED-12: db — опциональный уже прочитанный снимок (обычно
  // readSharedSnapshot() из GET /v1/posts, где accessibleTrees и
  // listPostCommentsForPosts читают тот же db). Read-only путь —
  // _canUserViewCirclePost уже безопасен на заморожённом db через
  // _writableCirclesViewForTree (SPEED-11), так что снимок сюда
  // передавать можно без нового overlay'я.
  async listPosts({
    treeId = null,
    authorId = null,
    scope = null,
    viewerUserId = null,
    db: prefetchedDb = null,
  } = {}) {
    const db = prefetchedDb || (await this.readSharedSnapshot());
    const circleCache = this._createCircleVisibilityCache();
    return db.posts
      .filter((entry) => {
        // Phase 3.4 multi-branch visibility. If `treeId` filter is
        // set, the post matches when the requested tree is in
        // post.branchIds (preferred) OR matches post.treeId (back-
        // compat for posts created before 3.4). Without a treeId
        // filter the tree gate is skipped entirely (cross-branch
        // feed query) and visibility falls to the circle/scope
        // checks below.
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
        if (authorId && entry.authorId !== authorId) {
          return false;
        }
        if (scope === "branches" && entry.scopeType !== "branches") {
          return false;
        }
        if (!this._canUserViewCirclePost(db, entry, viewerUserId, circleCache)) {
          return false;
        }
        return true;
      })
      .sort((left, right) => {
        // S2: tie-break по id — стабильный порядок при равных createdAt
        // обязателен для курсорной пагинации (иначе пост на границе
        // страницы может выпасть или задвоиться).
        const byCreatedAt = String(right.createdAt || "").localeCompare(
          String(left.createdAt || ""),
        );
        if (byCreatedAt !== 0) {
          return byCreatedAt;
        }
        return String(right.id || "").localeCompare(String(left.id || ""));
      })
      .map((entry) => attachPostReactions(db, entry));
  },

  /// SPEED-7: общий движок коалесцирующих уведомлений — hit по
  /// coalesce-ключу среди НЕпрочитанных бампает запись (createdAt=now,
  /// readAt сброс + патч плана), miss создаёт новую. PostgresStore
  /// переопределяет табличной реализацией; тексты живут в plan-builder'ах.
  async _applyNotificationCoalescePlan(plan) {
    if (!plan) {
      return null;
    }
    const coalesceKey = computeNotificationCoalesceKey({
      type: plan.type,
      data: plan.keyData,
    });
    const db = await this._read();
    db.notifications = Array.isArray(db.notifications)
      ? db.notifications
      : [];
    const existing = db.notifications.find(
      (entry) =>
        entry.userId === plan.userId &&
        !entry.readAt &&
        computeNotificationCoalesceKey(entry) === coalesceKey,
    );
    if (existing) {
      plan.patchExisting(existing);
      existing.createdAt = nowIso();
      existing.readAt = null;
      await this._write(db);
      return structuredClone(existing);
    }
    const notification = plan.buildRecord();
    db.notifications.push(notification);
    await this._write(db);
    return structuredClone(notification);
  },

  /// Substring search across post content + author name. Query is
  /// tokenised using the same Russian-locale shape as chat search,
  /// AND-matched against the lowercased haystack so multi-word
  /// queries like "детский сад" only match posts containing both
  /// terms. Filters to trees the requesting user can access. Returns
  /// the posts ordered newest-first up to `limit`.
  async searchPosts({userId, query, treeId = null, limit = 50} = {}) {
    const db = await this._read();
    const normalizedUserId = String(userId || "").trim();
    const terms = normalizeChatSearchQuery(query);
    if (!normalizedUserId || terms.length === 0) {
      return [];
    }
    const normalizedLimit = Math.min(
      Math.max(1, Number.parseInt(String(limit || "50"), 10) || 50),
      100,
    );
    const normalizedTreeId = normalizeNullableString(treeId);

    // Resolve which trees the user can read content from. Mirrors
    // listPosts visibility — filter happens up front so we don't
    // even score posts the viewer can't open.
    const accessibleTreeIds = new Set(
      (Array.isArray(db.trees) ? db.trees : [])
        .filter((tree) =>
          this._userCanAccessTreeRecord(tree, normalizedUserId, db),
        )
        .map((tree) => tree.id),
    );
    if (normalizedTreeId && !accessibleTreeIds.has(normalizedTreeId)) {
      return [];
    }

    const circleCache = this._createCircleVisibilityCache();
    const candidates = (Array.isArray(db.posts) ? db.posts : [])
      .filter((post) => {
        // Phase 3.4: a post is visible if ANY of its branchIds is
        // accessible to the viewer (multi-branch publishing), or
        // its legacy treeId is — back-compat for posts created
        // before the branchIds field existed.
        const branchIds = Array.isArray(post.branchIds) ? post.branchIds : [];
        const hasAccessibleBranch = branchIds.some((bid) =>
          accessibleTreeIds.has(bid),
        );
        const hasAccessibleLegacyTree = accessibleTreeIds.has(post.treeId);
        if (!hasAccessibleBranch && !hasAccessibleLegacyTree) return false;
        if (normalizedTreeId) {
          const matchesBranch = branchIds.includes(normalizedTreeId);
          const matchesLegacyTreeId = post.treeId === normalizedTreeId;
          if (!matchesBranch && !matchesLegacyTreeId) return false;
        }
        return this._canUserViewCirclePost(db, post, normalizedUserId, circleCache);
      })
      .sort((left, right) =>
        String(right.createdAt || "").localeCompare(
          String(left.createdAt || ""),
        ),
      );

    const results = [];
    for (const post of candidates) {
      if (results.length >= normalizedLimit) break;
      const haystack = normalizeSearchText(
        [post.content, post.authorName].filter(Boolean).join(" "),
      );
      if (terms.every((term) => haystack.includes(term))) {
        results.push(attachPostReactions(db, post));
      }
    }
    return results;
  },

  async findPost(postId) {
    const db = await this._read();
    const post = db.posts.find((entry) => entry.id === postId);
    return post ? attachPostReactions(db, post) : null;
  },

  async createPost({
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
    const db = await this._read();
    const tree = db.trees.find((entry) => entry.id === treeId);
    const user = db.users.find((entry) => entry.id === authorId);
    if (!tree || !user) {
      return null;
    }

    // Идемпотентность как у sendMessage (clientMessageId): клиентский
    // таймаут НЕ отменяет уже летящий запрос, и ретрай без ключа
    // публиковал бы второй экземпляр поста. Повтор от того же автора
    // возвращает уже созданный пост; _deduplicated подсказывает роуту
    // не рассылать уведомления второй раз.
    const normalizedClientRequestId = normalizeNullableString(clientRequestId);
    if (normalizedClientRequestId) {
      const existing = db.posts.find(
        (entry) =>
          entry.authorId === authorId &&
          entry.clientRequestId === normalizedClientRequestId,
      );
      if (existing) {
        return {...attachPostReactions(db, existing), _deduplicated: true};
      }
    }
    const {allTreeCircle} = ensureCirclesForTree(db, tree);
    const normalizedCircleId = normalizeNullableString(circleId) || allTreeCircle?.id;
    const targetCircle = db.circles.find(
      (entry) => entry.treeId === treeId && entry.id === normalizedCircleId,
    );
    if (!targetCircle) {
      return null;
    }

    // Phase 3.4 multi-branch: validate every requested branchId
    // resolves to a tree the author can access. Without this, an
    // author could publish into someone else's branch by passing
    // a branchId they don't own. The treeId in the URL stays the
    // primary tree (visibility / circle membership inherits from
    // it); branchIds extend the audience to additional branches
    // the author also belongs to.
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
      // Always include the primary treeId; the route already
      // verified caller has access to it.
      if (!resolvedBranchIds.includes(treeId)) {
        resolvedBranchIds.unshift(treeId);
      }
    }

    const post = createPostRecord({
      treeId,
      branchIds: resolvedBranchIds,
      authorId,
      authorName,
      authorPhotoUrl,
      content,
      imageUrls,
      isPublic,
      scopeType,
      anchorPersonIds,
      circleId: targetCircle.id,
      clientRequestId: normalizedClientRequestId,
    });
    if (!post.content && post.imageUrls.length === 0) {
      return false;
    }

    db.posts.push(post);
    await this._write(db);
    return attachPostReactions(db, post);
  },

  async deletePost(postId, actorUserId) {
    // Ship Q4a (2026-05-28, Ship 30b): soft-delete semantics для
    // posts. Mirror persons pattern (Ship 30) — move snapshot к
    // db.deletedPosts вместо splice. External behavior identical:
    //   • 204 status returned by route
    //   • Post not visible in subsequent listings
    //   • Comments + reactions cleared from active state
    //
    // Snapshot captures full state для restore:
    //   • Post body, media, audience, branchIds
    //   • All comments (postId-scoped)
    //   • postReactions + postCommentReactions (для restored comments)
    //
    // Snapshot row carries: hardDeleteScheduledAt (deletedAt + 30d),
    // earliestHardDelete (deletedAt + 3h floor), deletedByUserId.
    // Restore (restorePost) reverses: push back к db.posts, db.comments,
    // и reaction collections. Phase 3.6 sweep prunes after retention.
    const db = await this._read();
    const postIndex = db.posts.findIndex((entry) => entry.id === postId);
    if (postIndex < 0) {
      return null;
    }

    const post = db.posts[postIndex];
    const canDelete =
      post.authorId === actorUserId ||
      this._isActiveSemyaOwnerForTree(db, post.treeId, actorUserId);
    if (!canDelete) {
      return false;
    }

    const snapshotPost = structuredClone(post);
    const snapshotComments = db.comments
      .filter((entry) => entry.postId === postId)
      .map((entry) => structuredClone(entry));
    const snapshotPostReactions = ensurePostReactions(db)
      .filter((entry) => String(entry?.postId || "").trim() === postId)
      .map((entry) => structuredClone(entry));
    const removedCommentIds = snapshotComments.map((c) => c.id);
    const removedCommentIdSet = new Set(removedCommentIds);
    const snapshotCommentReactions = removedCommentIds.length > 0
      ? ensurePostCommentReactions(db)
          .filter((entry) =>
            removedCommentIdSet.has(String(entry?.commentId || "").trim()),
          )
          .map((entry) => structuredClone(entry))
      : [];

    db.posts.splice(postIndex, 1);
    db.comments = db.comments.filter((entry) => entry.postId !== postId);
    // Cleanup reaction rows so they don't outlive their post / comment.
    db.postReactions = ensurePostReactions(db).filter(
      (entry) => String(entry?.postId || "").trim() !== postId,
    );
    if (removedCommentIds.length > 0) {
      db.postCommentReactions = ensurePostCommentReactions(db).filter(
        (entry) =>
          !removedCommentIdSet.has(String(entry?.commentId || "").trim()),
      );
    }

    // Ship Q4a: write snapshot row to deletedPosts для 30d restore.
    const nowIsoStr = nowIso();
    const retentionDays = Number(process.env.RODNYA_DELETED_POSTS_RETENTION_DAYS) || 30;
    const floorHours = Number(process.env.RODNYA_DELETED_POSTS_FLOOR_HOURS) || 3;
    const hardDeleteAt = new Date(
      Date.parse(nowIsoStr) + retentionDays * 24 * 3600 * 1000,
    ).toISOString();
    const earliestHardDelete = new Date(
      Date.parse(nowIsoStr) + floorHours * 3600 * 1000,
    ).toISOString();
    db.deletedPosts = Array.isArray(db.deletedPosts) ? db.deletedPosts : [];
    db.deletedPosts.push({
      id: crypto.randomUUID(),
      originalPostId: postId,
      treeId: post.treeId,
      snapshot: snapshotPost,
      commentsSnapshot: snapshotComments,
      postReactionsSnapshot: snapshotPostReactions,
      commentReactionsSnapshot: snapshotCommentReactions,
      deletedAt: nowIsoStr,
      deletedByUserId: actorUserId,
      hardDeleteScheduledAt: hardDeleteAt,
      earliestHardDelete,
      restoredAt: null,
      restoredByUserId: null,
    });

    await this._write(db);
    return structuredClone(post);
  },

  /// Ship Q4a (2026-05-28, Ship 30b): list caller's deleted posts.
  /// Returns rows где caller был author (deletedByUserId match —
  /// они одинаковые because только author может delete own post per
  /// route gate at line 287).
  async listDeletedPostsForUser({userId}) {
    if (!userId || typeof userId !== "string") return [];
    const db = await this._read();
    return (db.deletedPosts || [])
      .filter((entry) => !entry.restoredAt && entry.deletedByUserId === userId)
      .sort((a, b) =>
        String(b.deletedAt || "").localeCompare(String(a.deletedAt || "")),
      )
      .map((entry) => structuredClone(entry));
  },

  /// Ship Q4a (2026-05-28, Ship 30b): restore post snapshot →
  /// db.posts + comments + reactions. Permission: original author
  /// либо семья owner of post's tree (если tree bound к семья).
  /// Throws:
  ///   • DELETED_POST_NOT_FOUND (404)
  ///   • ALREADY_RESTORED (409)
  ///   • HARD_DELETE_ELAPSED (410)
  ///   • FORBIDDEN (403)
  async restorePost({deletedPostId, actorUserId}) {
    if (!deletedPostId || typeof deletedPostId !== "string") {
      throw new Error("INVALID_INPUT");
    }
    if (!actorUserId) throw new Error("INVALID_ACTOR");

    const db = await this._read();
    const row = (db.deletedPosts || []).find(
      (entry) => entry.id === deletedPostId,
    );
    if (!row) throw new Error("DELETED_POST_NOT_FOUND");
    if (row.restoredAt) throw new Error("ALREADY_RESTORED");
    if (
      row.hardDeleteScheduledAt &&
      Date.parse(row.hardDeleteScheduledAt) < Date.now()
    ) {
      throw new Error("HARD_DELETE_ELAPSED");
    }

    // Permission: actor was original deleter (= author per route gate, still
    // active in bound semya) либо active owner of семья bound к post's tree.
    const isOriginalActor = row.deletedByUserId === actorUserId;
    let isSemyaOwner = false;
    let allowedAsOriginal = isOriginalActor;
    const tree = (db.trees || []).find((t) => t.id === row.treeId);
    if (tree?.semyaId) {
      const semya = (db.semyi || []).find(
        (s) => s.id === tree.semyaId && !s.deletedAt,
      );
      if (semya) {
        const memberRows = (db.semyaMembers || []).filter(
          (m) => m.semyaId === semya.id && m.userId === actorUserId,
        );
        const activeMem = memberRows.find((m) => !m.hiddenAt);
        isSemyaOwner = activeMem?.role === "owner";
        if (!activeMem) {
          allowedAsOriginal = false;
        }
      }
    }
    if (!allowedAsOriginal && !isSemyaOwner) {
      throw new Error("FORBIDDEN");
    }

    // Restore snapshot к live state.
    db.posts = Array.isArray(db.posts) ? db.posts : [];
    db.posts.push(structuredClone(row.snapshot));
    if (Array.isArray(row.commentsSnapshot)) {
      db.comments = Array.isArray(db.comments) ? db.comments : [];
      for (const c of row.commentsSnapshot) {
        db.comments.push(structuredClone(c));
      }
    }
    if (Array.isArray(row.postReactionsSnapshot)) {
      db.postReactions = ensurePostReactions(db);
      for (const r of row.postReactionsSnapshot) {
        db.postReactions.push(structuredClone(r));
      }
    }
    if (Array.isArray(row.commentReactionsSnapshot)) {
      db.postCommentReactions = ensurePostCommentReactions(db);
      for (const r of row.commentReactionsSnapshot) {
        db.postCommentReactions.push(structuredClone(r));
      }
    }

    row.restoredAt = nowIso();
    row.restoredByUserId = actorUserId;

    await this._write(db);
    return structuredClone(row);
  },

  /// Ship Q4a (2026-05-28, Ship 30b): manual hard-purge с 3h floor.
  /// Throws:
  ///   • DELETED_POST_NOT_FOUND (404)
  ///   • ALREADY_RESTORED (409)
  ///   • FLOOR_NOT_MET (409)
  ///   • FORBIDDEN (403)
  async hardDeletePost({deletedPostId, actorUserId}) {
    if (!deletedPostId || typeof deletedPostId !== "string") {
      throw new Error("INVALID_INPUT");
    }
    if (!actorUserId) throw new Error("INVALID_ACTOR");

    const db = await this._read();
    const idx = (db.deletedPosts || []).findIndex(
      (entry) => entry.id === deletedPostId,
    );
    if (idx < 0) throw new Error("DELETED_POST_NOT_FOUND");
    const row = db.deletedPosts[idx];
    if (row.restoredAt) throw new Error("ALREADY_RESTORED");
    if (
      row.earliestHardDelete &&
      Date.parse(row.earliestHardDelete) > Date.now()
    ) {
      throw new Error("FLOOR_NOT_MET");
    }

    // Manual hard-purge: only author (per dispatch — «Manual
    // hard-delete post: only author»).
    if (row.deletedByUserId !== actorUserId) {
      throw new Error("FORBIDDEN");
    }

    db.deletedPosts.splice(idx, 1);
    await this._write(db);
    return {purged: true, deletedPostId};
  },

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
    return attachPostReactions(db, post);
  },

  /// Audience presets — pre-computed smart-set personId lists for the
  /// current user in a given tree. Lets the picker offer "Моя семья",
  /// "Близкие" as one-tap shortcuts instead of forcing the user to
  /// build a custom branch list. Resolved at request time so the
  /// numbers stay in sync with the current tree state.
  ///
  /// Returns null when the user has no person-card in the tree (anchor
  /// can't be resolved). The route handler turns that into a graceful
  /// empty-presets response so the UI degrades to "Всё дерево" only.
  async computeAudiencePresets({treeId, userId}) {
    const db = await this._read();
    const tree = db.trees.find((entry) => entry.id === treeId);
    if (!tree) {
      return null;
    }
    const treePersons = db.persons.filter(
      (person) => person.treeId === treeId,
    );
    const anchor = _resolveAnchorPerson(db, treeId, userId);
    if (!anchor) {
      return {
        anchorPersonId: null,
        presets: [],
      };
    }

    // Build adjacency: personId → list of {otherId, relType}
    const treePersonIds = new Set(treePersons.map((p) => p.id));
    const treeRelations = db.relations.filter(
      (rel) =>
        treePersonIds.has(String(rel.person1Id || "")) &&
        treePersonIds.has(String(rel.person2Id || "")),
    );
    // adjacency[p] entries describe roles OTHERS play toward p, e.g.
    // {otherId: dadId, relType: "parent"} means "dad is my parent".
    // For a relation (person1, person2, relation1to2='parent') —
    // person1 is parent of person2 — we record:
    //   adjacency[person2] += {otherId: person1, relType: 'parent'}
    //   adjacency[person1] += {otherId: person2, relType: 'child'}
    // So we always use the mirror relation when populating.
    const adjacency = new Map();
    for (const id of treePersonIds) {
      adjacency.set(id, []);
    }
    for (const rel of treeRelations) {
      const a = String(rel.person1Id || "");
      const b = String(rel.person2Id || "");
      const aToB = String(rel.relation1to2 || "").trim().toLowerCase();
      const bToA =
        String(rel.relation2to1 || "").trim().toLowerCase() ||
        relationMirror(aToB);
      if (a && b && aToB) {
        // person2 sees person1 in role `aToB`.
        adjacency.get(b).push({otherId: a, relType: aToB});
      }
      if (a && b && bToA) {
        // person1 sees person2 in role `bToA`.
        adjacency.get(a).push({otherId: b, relType: bToA});
      }
    }

    const neighborsByType = (personId, types) => {
      const set = new Set(
        types.map((t) => String(t).toLowerCase()),
      );
      return (adjacency.get(personId) || [])
        .filter((edge) => set.has(edge.relType))
        .map((edge) => edge.otherId);
    };

    // core_family: anchor + parents + spouse/partner + siblings +
    // siblings' partners + nieces/nephews (siblings' children) +
    // children + children's partners.
    const coreSet = new Set([anchor.id]);
    const parents = neighborsByType(anchor.id, ["parent"]);
    parents.forEach((id) => coreSet.add(id));
    const partners = neighborsByType(anchor.id, ["spouse", "partner"]);
    partners.forEach((id) => coreSet.add(id));
    const siblings = neighborsByType(anchor.id, ["sibling"]);
    siblings.forEach((sib) => {
      coreSet.add(sib);
      neighborsByType(sib, ["spouse", "partner"]).forEach((id) =>
        coreSet.add(id),
      );
      neighborsByType(sib, ["child"]).forEach((id) => coreSet.add(id));
    });
    const children = neighborsByType(anchor.id, ["child"]);
    children.forEach((kid) => {
      coreSet.add(kid);
      neighborsByType(kid, ["spouse", "partner"]).forEach((id) =>
        coreSet.add(id),
      );
    });

    // close: core_family + grandparents + grandparents' partners +
    // aunts/uncles + first cousins + grandchildren.
    const closeSet = new Set(coreSet);
    parents.forEach((p) => {
      neighborsByType(p, ["parent"]).forEach((gp) => {
        closeSet.add(gp);
        neighborsByType(gp, ["spouse", "partner"]).forEach((id) =>
          closeSet.add(id),
        );
      });
      neighborsByType(p, ["sibling"]).forEach((auntUncle) => {
        closeSet.add(auntUncle);
        neighborsByType(auntUncle, ["spouse", "partner"]).forEach((id) =>
          closeSet.add(id),
        );
        neighborsByType(auntUncle, ["child"]).forEach((cousin) =>
          closeSet.add(cousin),
        );
      });
    });
    children.forEach((kid) => {
      neighborsByType(kid, ["child"]).forEach((id) => closeSet.add(id));
    });

    return {
      anchorPersonId: anchor.id,
      presets: [
        {
          key: "core_family",
          label: "Моя семья",
          description: "Родители, партнёр, сёстры/братья и племянники",
          personIds: Array.from(coreSet),
        },
        {
          key: "close",
          label: "Близкие",
          description: "Семья и круг тех, с кем общаетесь чаще остальных",
          personIds: Array.from(closeSet),
        },
      ],
    };
  },

  async togglePostReaction({postId, userId, emoji}) {
    const db = await this._read();
    const post = db.posts.find((entry) => entry.id === postId);
    if (!post) {
      return null;
    }
    const normalizedEmoji = normalizeReactionEmoji(emoji);
    if (!normalizedEmoji) {
      return "INVALID_EMOJI";
    }
    const reactions = ensurePostReactions(db);
    const existingIndex = reactions.findIndex(
      (entry) =>
        String(entry?.postId || "").trim() === post.id &&
        String(entry?.userId || "").trim() === userId &&
        normalizeReactionEmoji(entry?.emoji) === normalizedEmoji,
    );
    let added = false;
    if (existingIndex >= 0) {
      reactions.splice(existingIndex, 1);
    } else {
      reactions.push({
        postId: post.id,
        userId,
        emoji: normalizedEmoji,
        createdAt: nowIso(),
      });
      added = true;
    }
    post.updatedAt = nowIso();
    await this._write(db);
    return {
      postId: post.id,
      reactions: aggregatePostReactions(db, post.id),
      added,
    };
  },

  async togglePostCommentReaction({postId, commentId, userId, emoji}) {
    const db = await this._read();
    const comment = db.comments.find(
      (entry) => entry.id === commentId && entry.postId === postId,
    );
    if (!comment) {
      return null;
    }
    const normalizedEmoji = normalizeReactionEmoji(emoji);
    if (!normalizedEmoji) {
      return "INVALID_EMOJI";
    }
    const reactions = ensurePostCommentReactions(db);
    const existingIndex = reactions.findIndex(
      (entry) =>
        String(entry?.commentId || "").trim() === comment.id &&
        String(entry?.userId || "").trim() === userId &&
        normalizeReactionEmoji(entry?.emoji) === normalizedEmoji,
    );
    let added = false;
    if (existingIndex >= 0) {
      reactions.splice(existingIndex, 1);
    } else {
      reactions.push({
        commentId: comment.id,
        userId,
        emoji: normalizedEmoji,
        createdAt: nowIso(),
      });
      added = true;
    }
    await this._write(db);
    return {
      commentId: comment.id,
      postId: comment.postId,
      reactions: aggregatePostCommentReactions(db, comment.id),
      added,
    };
  },

  async listPostComments(postId, {db: prefetchedDb = null} = {}) {
    const db = prefetchedDb || (await this._read());
    const usersById = buildUsersByIdMap(db);
    const entries = db.comments.filter((entry) => entry.postId === postId);
    return hydrateAndSortPostComments(db, entries, usersById);
  },

  /// SPEED-9 D: батч-сиблинг listPostComments — один _read() на СПИСОК
  /// постов вместо одного на каждый. До этого GET /v1/posts делал
  /// Promise.all(page.map(post => listPostComments(post.id))) — K
  /// независимых _read() на странице из K постов (на PostgresStore
  /// каждый — structuredClone всего состояния + 2 SQL round-trip'а,
  /// см. docs/speed_measurement.md SPEED-9). Возвращает Map<postId,
  /// comments[]>, где comments[] для каждого postId побайтово совпадает
  /// с тем, что вернул бы listPostComments(postId) на том же db —
  /// общий hydrateAndSortPostComments гарантирует это, а не просто
  /// "похожую" реализацию.
  async listPostCommentsForPosts(postIds, {db: prefetchedDb = null} = {}) {
    const db = prefetchedDb || (await this._read());
    const usersById = buildUsersByIdMap(db);
    const idSet = new Set(postIds);
    const entriesByPost = new Map();
    for (const id of idSet) {
      entriesByPost.set(id, []);
    }
    for (const entry of db.comments) {
      if (idSet.has(entry.postId)) {
        entriesByPost.get(entry.postId).push(entry);
      }
    }
    const result = new Map();
    for (const [postId, entries] of entriesByPost) {
      result.set(postId, hydrateAndSortPostComments(db, entries, usersById));
    }
    return result;
  },

  /// Lookup a single comment scoped to a post. Used by the route layer
  /// to fan out reply notifications without re-fetching the whole list.
  async findPostComment({postId, commentId}) {
    const db = await this._read();
    const trimmedId = String(commentId || "").trim();
    if (!trimmedId) return null;
    const comment = db.comments.find(
      (entry) => entry.id === trimmedId && entry.postId === postId,
    );
    return comment ? structuredClone(comment) : null;
  },

  async addPostComment({
    postId,
    authorId,
    authorName,
    authorPhotoUrl = null,
    content,
    parentCommentId = null,
  }) {
    const db = await this._read();
    const post = db.posts.find((entry) => entry.id === postId);
    const user = db.users.find((entry) => entry.id === authorId);
    if (!post || !user) {
      return null;
    }

    // Resolve parent for two-level threading. If the caller pointed at a
    // reply, climb to the top-level comment so the chain stays flat. If
    // the parent doesn't exist (or belongs to another post), treat the
    // comment as top-level rather than rejecting — kinder UX in the
    // race-condition where the parent was deleted between fetch and post.
    let resolvedParentId = null;
    if (parentCommentId) {
      const parent = db.comments.find(
        (entry) =>
          entry.id === String(parentCommentId).trim() &&
          entry.postId === postId,
      );
      if (parent) {
        resolvedParentId = parent.parentCommentId
          ? String(parent.parentCommentId).trim() || parent.id
          : parent.id;
      }
    }

    const comment = createCommentRecord({
      postId,
      authorId,
      authorName,
      authorPhotoUrl,
      content,
      parentCommentId: resolvedParentId,
    });
    if (!comment.content) {
      return false;
    }

    db.comments.push(comment);
    await this._write(db);
    return attachCommentReactions(db, comment);
  },

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
      comment.authorId === actorUserId ||
      post.authorId === actorUserId ||
      this._isActiveSemyaOwnerForTree(db, post.treeId, actorUserId);
    if (!canDelete) {
      return false;
    }

    db.comments.splice(commentIndex, 1);
    db.postCommentReactions = ensurePostCommentReactions(db).filter(
      (entry) => String(entry?.commentId || "").trim() !== commentId,
    );
    await this._write(db);
    return structuredClone(comment);
  },
};
