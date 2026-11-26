const path = require("node:path");
const crypto = require("node:crypto");
const {
  createArticleBlockRecord,
  createNotificationRecord,
  normalizeArticleBlockContent,
  normalizeNullableString,
  normalizePersonPhotoGallery,
  nowIso,
} = require("../helpers");

module.exports = {
  // Resolve {person, treeId, semyaId}. semyaId = person's tree's bound
  // active семья (null when standalone tree). Throws PERSON_NOT_FOUND.
  _resolveArticleContext(db, personId) {
    const person = this._findPersonRecordById(db, personId);
    if (!person) throw new Error("PERSON_NOT_FOUND");
    const treeId = person.treeId;
    const tree = (db.trees || []).find((entry) => entry.id === treeId);
    const semyaId =
      tree?.semyaId &&
      (db.semyi || []).some((s) => s.id === tree.semyaId && !s.deletedAt)
        ? tree.semyaId
        : null;
    return {person, treeId, semyaId};
  },

  // Find existing article or create+persist an empty one. Returns the
  // live object (caller is inside a read/write cycle).
  _ensureProfileArticle(db, personId, ctx) {
    db.profileArticles = Array.isArray(db.profileArticles)
      ? db.profileArticles
      : [];
    let article = db.profileArticles.find(
      (entry) => entry.personId === personId,
    );
    if (!article) {
      const timestamp = nowIso();
      article = {
        id: crypto.randomUUID(),
        personId,
        treeId: ctx.treeId,
        semyaId: ctx.semyaId,
        blocks: [],
        createdAt: timestamp,
        updatedAt: timestamp,
      };
      db.profileArticles.push(article);
    }
    return article;
  },

  // GET — returns the article. Synthesizes an empty shape if none yet
  // (NOT persisted on read). Throws PERSON_NOT_FOUND.
  async getProfileArticle({personId}) {
    const id = String(personId || "").trim();
    if (!id) throw new Error("INVALID_INPUT");
    const db = await this._read();
    const ctx = this._resolveArticleContext(db, id);
    const article = (db.profileArticles || []).find(
      (entry) => entry.personId === id,
    );
    if (article) return structuredClone(article);
    return {
      id: null,
      personId: id,
      treeId: ctx.treeId,
      semyaId: ctx.semyaId,
      blocks: [],
      createdAt: null,
      updatedAt: null,
    };
  },

  async appendArticleBlock({personId, type, content, actorUserId}) {
    const id = String(personId || "").trim();
    if (!id) throw new Error("INVALID_INPUT");
    if (!actorUserId) throw new Error("INVALID_ACTOR");
    const db = await this._read();
    const ctx = this._resolveArticleContext(db, id);
    // Validates shape (throws) BEFORE we touch db — no empty-article
    // side effect on a rejected block.
    const block = createArticleBlockRecord({type, content, actorUserId});
    const article = this._ensureProfileArticle(db, id, ctx);
    article.blocks.push(block);
    article.updatedAt = block.createdAt;
    this._appendTreeChangeRecord(db, {
      treeId: ctx.treeId,
      actorId: actorUserId,
      type: "article.block-added",
      personId: id,
      details: {blockId: block.id, blockType: block.type},
    });
    await this._write(db);
    return structuredClone(block);
  },

  // PATCH one block. Optional baseUpdatedAt = the updatedAt the editor
  // loaded; if the block changed since (another author wrote), it's a
  // conflict. Per Q3 (locked 2026-05-28): last-write-wins — apply the
  // write, keep prior content in the audit `before` snapshot, notify
  // the previous author. Returns {block, conflict}.
  async updateArticleBlock({
    personId,
    blockId,
    content,
    actorUserId,
    baseUpdatedAt = null,
  }) {
    const id = String(personId || "").trim();
    const bId = String(blockId || "").trim();
    if (!id || !bId) throw new Error("INVALID_INPUT");
    if (!actorUserId) throw new Error("INVALID_ACTOR");
    const db = await this._read();
    const ctx = this._resolveArticleContext(db, id);
    const article = (db.profileArticles || []).find(
      (entry) => entry.personId === id,
    );
    const block = article?.blocks?.find((b) => b.id === bId);
    if (!block) throw new Error("ARTICLE_BLOCK_NOT_FOUND");

    const nextContent = normalizeArticleBlockContent(block.type, content);
    const beforeContent = structuredClone(block.content);
    const priorAuthor = block.authorUserId;
    const conflict =
      baseUpdatedAt != null &&
      String(baseUpdatedAt) !== String(block.updatedAt);

    const timestamp = nowIso();
    block.content = nextContent;
    block.authorUserId = normalizeNullableString(actorUserId);
    block.updatedAt = timestamp;
    article.updatedAt = timestamp;

    this._appendTreeChangeRecord(db, {
      treeId: ctx.treeId,
      actorId: actorUserId,
      type: "article.block-updated",
      personId: id,
      details: {
        blockId: bId,
        blockType: block.type,
        before: beforeContent,
        conflict,
      },
    });

    // Q3: notify previous author when their text was overwritten.
    if (conflict && priorAuthor && priorAuthor !== actorUserId) {
      db.notifications = Array.isArray(db.notifications)
        ? db.notifications
        : [];
      db.notifications.push(
        createNotificationRecord({
          userId: priorAuthor,
          type: "article_block_conflict",
          title: "Ваш текст в карточке изменили",
          body:
            "Другой родственник отредактировал абзац, который вы писали. " +
            "Прежняя версия сохранена в истории изменений.",
          data: {personId: id, blockId: bId, treeId: ctx.treeId},
          silent: false,
        }),
      );
    }

    await this._write(db);
    return {block: structuredClone(block), conflict};
  },

  async removeArticleBlock({personId, blockId, actorUserId}) {
    const id = String(personId || "").trim();
    const bId = String(blockId || "").trim();
    if (!id || !bId) throw new Error("INVALID_INPUT");
    if (!actorUserId) throw new Error("INVALID_ACTOR");
    const db = await this._read();
    const ctx = this._resolveArticleContext(db, id);
    const article = (db.profileArticles || []).find(
      (entry) => entry.personId === id,
    );
    const blockIdx = article
      ? article.blocks.findIndex((b) => b.id === bId)
      : -1;
    if (!article || blockIdx < 0) {
      throw new Error("ARTICLE_BLOCK_NOT_FOUND");
    }
    const [removed] = article.blocks.splice(blockIdx, 1);
    article.updatedAt = nowIso();
    this._appendTreeChangeRecord(db, {
      treeId: ctx.treeId,
      actorId: actorUserId,
      type: "article.block-removed",
      personId: id,
      details: {
        blockId: bId,
        blockType: removed?.type || null,
        before: removed?.content ?? null,
      },
    });
    await this._write(db);
    return {removed: true, blockId: bId};
  },

  // Reorder blocks to match orderedBlockIds. Unknown ids ignored;
  // blocks omitted from the list keep their relative order at the end
  // (defensive — never drops a block on a stale client list).
  async reorderArticleBlocks({personId, orderedBlockIds, actorUserId}) {
    const id = String(personId || "").trim();
    if (!id) throw new Error("INVALID_INPUT");
    if (!actorUserId) throw new Error("INVALID_ACTOR");
    if (!Array.isArray(orderedBlockIds)) throw new Error("INVALID_INPUT");
    const db = await this._read();
    const ctx = this._resolveArticleContext(db, id);
    const article = (db.profileArticles || []).find(
      (entry) => entry.personId === id,
    );
    if (!article) throw new Error("ARTICLE_NOT_FOUND");
    const byId = new Map(article.blocks.map((b) => [b.id, b]));
    const seen = new Set();
    const reordered = [];
    for (const wantId of orderedBlockIds) {
      const b = byId.get(String(wantId));
      if (b && !seen.has(b.id)) {
        reordered.push(b);
        seen.add(b.id);
      }
    }
    for (const b of article.blocks) {
      if (!seen.has(b.id)) reordered.push(b);
    }
    article.blocks = reordered;
    article.updatedAt = nowIso();
    this._appendTreeChangeRecord(db, {
      treeId: ctx.treeId,
      actorId: actorUserId,
      type: "article.reordered",
      personId: id,
      details: {order: reordered.map((b) => b.id)},
    });
    await this._write(db);
    return structuredClone(article);
  },

  // History — filtered treeChangeRecords (proposal §9.3 reuse).
  // Newest first. Throws PERSON_NOT_FOUND.
  async getArticleHistory({personId}) {
    const id = String(personId || "").trim();
    if (!id) throw new Error("INVALID_INPUT");
    const db = await this._read();
    this._resolveArticleContext(db, id); // PERSON_NOT_FOUND guard
    return (db.treeChangeRecords || [])
      .filter(
        (r) =>
          r.personId === id &&
          typeof r.type === "string" &&
          r.type.startsWith("article."),
      )
      .sort((a, b) =>
        String(b.createdAt || "").localeCompare(String(a.createdAt || "")),
      )
      .map((r) => structuredClone(r));
  },

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

    // Snapshot for Phase 1.1 photo propagation — captured BEFORE
    // we mutate person.* below. The propagator diffs against this
    // to detect what fields changed and replicates them onto any
    // linked records sharing identityId.
    const previousPersonSnapshot = structuredClone(person);
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
    // Phase 1.1 propagation: photo fields fan out to linked
    // records on other trees so the user's "I added a photo on
    // mom in tree A" actually shows up on mom in tree B too.
    // Without this, only the explicit `updatePerson` path
    // propagates — uploads silently stay tree-local.
    const propagatedTo = this._propagateIdentityFields(
      db,
      person,
      previousPersonSnapshot,
      actorId,
    );
    await this._write(db);
    return {
      person: structuredClone(person),
      media: storedMedia ? structuredClone(storedMedia) : null,
      propagatedTo,
    };
  },

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

    const previousPersonSnapshot = structuredClone(person);
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
    const propagatedTo = this._propagateIdentityFields(
      db,
      person,
      previousPersonSnapshot,
      actorId,
    );
    await this._write(db);
    return {
      person: structuredClone(person),
      media: updatedMedia ? structuredClone(updatedMedia) : null,
      propagatedTo,
    };
  },

  async deletePersonMedia({
    treeId,
    personId,
    mediaId,
    fallbackUrl = null,
    actorId = null,
  }) {
    const db = await this._read();
    const person = db.persons.find(
      (entry) => entry.id === personId && entry.treeId === treeId,
    );
    if (!person) {
      return null;
    }

    const previousPersonSnapshot = structuredClone(person);
    const currentGallery = Array.isArray(person.photoGallery)
      ? person.photoGallery.map((entry) => structuredClone(entry))
      : [];

    // Primary lookup by ID; fall back to URL for clients with stale synthetic IDs.
    let removedMedia = currentGallery.find((entry) => entry.id === mediaId);
    if (!removedMedia && fallbackUrl) {
      const normalizedFallback = String(fallbackUrl).trim().toLowerCase();
      removedMedia = currentGallery.find(
        (entry) => String(entry.url || "").trim().toLowerCase() === normalizedFallback,
      );
    }
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
    const propagatedTo = this._propagateIdentityFields(
      db,
      person,
      previousPersonSnapshot,
      actorId,
    );
    await this._write(db);
    return {
      person: structuredClone(person),
      deletedMedia: structuredClone(removedMedia),
      propagatedTo,
    };
  },
};
