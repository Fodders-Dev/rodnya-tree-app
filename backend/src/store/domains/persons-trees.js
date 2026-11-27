const path = require("node:path");
const crypto = require("node:crypto");
const {
  normalizePersonForScoring,
  scoreNormalizedPersons,
  scorePersonPair,
} = require("../../identity-matcher");
const {
  applyCanonicalProfileToPerson,
  applyIncludeRulesToBranch,
  attachStoryReactions,
  buildCanonicalPersonView,
  buildPersonRecord,
  buildUsersByIdMap,
  canonicalBloodType,
  createNotificationRecord,
  createPersonIdentityRecord,
  defaultPersonVisibility,
  ensureChatPins,
  ensureCirclesForTree,
  ensureDefaultCirclesForTree,
  fullNameFromPersonInput,
  isExpiredAt,
  mergePersonDataFromSource,
  mirrorBloodType,
  normalizeDatePrecision,
  normalizeIsoDate,
  normalizeNullableString,
  normalizeParticipantIds,
  normalizePersonPhotoGallery,
  normalizePersonVisibility,
  nowIso,
  personStewardUserIds,
  relationMirror,
  resolvePersonFamilySummary,
  upsertPersonAttributesForPerson,
} = require("../helpers");

module.exports = {
  // Targeted persister for the lockout fields. Lives separately from
  // the bulk user-update path so a failure here doesn't poison the
  // larger `_write` queue. Subclasses (PostgresStore) override to
  // skip the full state read and write only the touched columns.
  async _persistAuthFailureState(userId, updates) {
    const db = await this._read();
    const user = db.users.find((entry) => entry.id === userId);
    if (!user) return;
    if ("failedLoginCount" in updates) {
      user.failedLoginCount = updates.failedLoginCount;
    }
    if ("lockedUntil" in updates) {
      user.lockedUntil = updates.lockedUntil;
    }
    await this._write(db);
  },

  _hashResetToken(plaintext) {
    return crypto
      .createHash("sha256")
      .update(String(plaintext || ""))
      .digest("hex");
  },

  async createTree({
    creatorId,
    name,
    description,
    isPrivate,
    kind,
    includeRules = null,
    bindSemya = false,
  }) {
    // Phase 3.4-prep fix-1: pre-flight validation на includeRules
    // ДО touch'а DB. `applyIncludeRulesToBranch` throws на explicit
    // invalid type — нужно catch'нуть здесь, чтобы caller (POST
    // /v1/trees route) превратил в 400 БЕЗ partial side-effects
    // (tree уже push'нутый в db, person'а ещё нет, и т.д.).
    if (includeRules && typeof includeRules === "object") {
      const probeBranch = {
        includeRules: {
          type: "manual",
          manualPersonIds: [],
          anchorPersonId: null,
          maxHops: 5,
        },
      };
      applyIncludeRulesToBranch(probeBranch, includeRules);
    }

    const db = await this._read();
    const createdAt = nowIso();
    const normalizedKind = String(kind || "family").trim().toLowerCase() === "friends"
      ? "friends"
      : "family";
    const shouldBindSemya = Boolean(bindSemya) && normalizedKind === "family";
    const boundSemyaId = shouldBindSemya ? crypto.randomUUID() : null;
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
      // Phase B Ship 5: reverse-FK к семья. Null = tree «свободный»
      // (не bound к семье). createSemya / bindSemya sets к семья.id atomically.
      semyaId: boundSemyaId,
    };

    if (shouldBindSemya) {
      db.semyi = db.semyi || [];
      db.semyaMembers = db.semyaMembers || [];
      db.semyi.push({
        id: boundSemyaId,
        name: tree.name || "Моя семья",
        ownerId: creatorId,
        treeId: tree.id,
        description: null,
        createdAt,
        updatedAt: createdAt,
        deletedAt: null,
      });
      db.semyaMembers.push({
        id: crypto.randomUUID(),
        semyaId: boundSemyaId,
        userId: creatorId,
        role: "owner",
        joinedAt: createdAt,
        invitedByUserId: null,
        hasInviteGrant: true,
        hiddenAt: null,
      });
    }

    const creator = db.users.find((entry) => entry.id === creatorId);
    const creatorProfile = creator?.profile || {};
    const creatorIdentity = this._ensureUserIdentity(db, creatorId);
    const creatorPerson = buildPersonRecord({
      treeId: tree.id,
      creatorId,
      userId: creatorId,
      identityId: creatorIdentity?.id || null,
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
    ensureDefaultCirclesForTree(db, tree);
    db.persons.push(creatorPerson);
    if (creatorIdentity) {
      this._attachPersonToIdentity(db, creatorPerson, creatorIdentity, creatorId);
    } else {
      this._reconcilePersonIdentities(db);
    }

    // Phase 3.4-prep (DECISIONS.md 2026-05-10 ответ Q4):
    // если caller передал `includeRules`, применяем поверх default
    // manual rule, который ставит `_syncTreeToBranch`. Делаем после
    // `_attachPersonToIdentity`, чтобы branch уже существовал.
    if (includeRules && typeof includeRules === "object") {
      this._syncTreeToBranch(db, tree);
      const branch = (db.branches || []).find((b) => b.id === tree.id);
      if (branch) {
        applyIncludeRulesToBranch(branch, includeRules);
      }
    }
    this._appendTreeChangeRecord(db, {
      treeId: tree.id,
      actorId: creatorId,
      type: "person.created",
      personId: creatorPerson.id,
      details: {
        after: structuredClone(creatorPerson),
      },
    });
    upsertPersonAttributesForPerson(db, creatorPerson, creatorId);
    await this._write(db);
    return structuredClone(tree);
  },

  // SPEED-12: readSharedSnapshot() вместо _read() — чистое чтение
  // (.filter/.sort/.map с structuredClone на возврат каждого дерева),
  // db нигде не мутируется. Каждый вызывающий (posts/gatherings/polls/
  // stories/трасы, PostgresStore.listUserTrees делегирует сюда через
  // super) получает эффект без изменения сигнатуры. prefetchedDb —
  // опционален (см. listPersons/findPerson) — GET /v1/posts передаёт
  // уже прочитанный снимок, чтобы не делать три SELECT version подряд.
  async listUserTrees(userId, prefetchedDb = null) {
    const db = prefetchedDb || (await this.readSharedSnapshot());
    return db.trees
      .filter((tree) => this._userCanAccessTreeRecord(tree, userId, db))
      .sort((left, right) =>
        String(right.updatedAt || "").localeCompare(String(left.updatedAt || "")),
      )
      .map((tree) => structuredClone(tree));
  },

  async findTree(treeId) {
    const db = await this._read();
    const tree = db.trees.find((entry) => entry.id === treeId);
    return tree ? structuredClone(tree) : null;
  },

  async updateTree({
    treeId,
    actorUserId,
    name,
    description,
    isPrivate,
    publicSlug,
  }) {
    const normalizedTreeId = normalizeNullableString(treeId);
    const normalizedActorId = normalizeNullableString(actorUserId);
    if (!normalizedTreeId || !normalizedActorId) {
      return null;
    }

    const db = await this._read();
    const tree = (db.trees || []).find((entry) => entry.id === normalizedTreeId);
    if (!tree) {
      return null;
    }

    const activeSemya = tree.semyaId
      ? (db.semyi || []).find((s) => s.id === tree.semyaId && !s.deletedAt)
      : null;
    const hasSemyaMembers = Boolean(
      activeSemya &&
        (db.semyaMembers || []).some((m) => m.semyaId === activeSemya.id),
    );
    const isOwner = hasSemyaMembers
      ? this._isActiveSemyaOwnerForTree(db, tree.id, normalizedActorId)
      : tree.creatorId === normalizedActorId;
    if (!isOwner) {
      throw new Error("NOT_OWNER");
    }

    let mutated = false;
    if (name !== undefined && name !== null) {
      if (typeof name !== "string") {
        throw new Error("INVALID_NAME");
      }
      const trimmedName = name.trim();
      if (!trimmedName || trimmedName.length > 120) {
        throw new Error("INVALID_NAME");
      }
      if (trimmedName !== tree.name) {
        tree.name = trimmedName;
        mutated = true;
      }
    }

    if (description !== undefined) {
      const nextDesc =
        description === null ? "" : String(description).trim();
      const currentDesc = tree.description ?? "";
      if (nextDesc !== currentDesc) {
        tree.description = nextDesc;
        mutated = true;
      }
    }

    if (isPrivate !== undefined) {
      const nextPrivate = Boolean(isPrivate);
      if (nextPrivate !== (tree.isPrivate !== false)) {
        tree.isPrivate = nextPrivate;
        mutated = true;
      }
    }

    if (publicSlug !== undefined) {
      let nextSlug = null;
      if (publicSlug !== null && String(publicSlug).trim() !== "") {
        nextSlug = String(publicSlug).trim().toLowerCase();
        if (!/^[a-z0-9][a-z0-9-]{1,62}[a-z0-9]$/.test(nextSlug)) {
          throw new Error("INVALID_PUBLIC_SLUG");
        }
        const conflict = (db.trees || []).some(
          (entry) =>
            entry.id !== tree.id &&
            String(entry.publicSlug || "").trim().toLowerCase() === nextSlug,
        );
        if (conflict) {
          throw new Error("PUBLIC_SLUG_TAKEN");
        }
      }
      if ((tree.publicSlug || null) !== nextSlug) {
        tree.publicSlug = nextSlug;
        mutated = true;
      }
    }

    const timestamp = nowIso();
    let semyaSynced = false;
    if (activeSemya) {
      if (name !== undefined && name !== null && activeSemya.name !== tree.name) {
        activeSemya.name = tree.name;
        activeSemya.updatedAt = timestamp;
        semyaSynced = true;
      }
      if (description !== undefined) {
        const nextSemyaDesc = tree.description ? tree.description : null;
        if ((activeSemya.description ?? null) !== nextSemyaDesc) {
          activeSemya.description = nextSemyaDesc;
          activeSemya.updatedAt = timestamp;
          semyaSynced = true;
        }
      }
    }

    if (mutated || semyaSynced) {
      tree.updatedAt = timestamp;
      await this._write(db);
    }
    return structuredClone(tree);
  },

  _countActiveOwners(db, semyaId) {
    return (db.semyaMembers || []).filter(
      (m) => m.semyaId === semyaId && m.role === "owner" && !m.hiddenAt,
    ).length;
  },

  _lazyExpireInvitations(db, semyaId) {
    const now = Date.now();
    let mutated = false;
    for (const inv of db.semyaInvitations || []) {
      if (semyaId && inv.semyaId !== semyaId) continue;
      if (inv.status !== "pending") continue;
      const expiresAtMs = inv.expiresAt ? Date.parse(inv.expiresAt) : null;
      if (expiresAtMs && expiresAtMs <= now) {
        inv.status = "expired";
        inv.expiredAt = nowIso();
        mutated = true;
      }
    }
    return mutated;
  },

  async removeTreeForUser({treeId, userId}) {
    const db = await this._read();
    const treeIndex = db.trees.findIndex((entry) => entry.id === treeId);
    if (treeIndex < 0) {
      return null;
    }

    const tree = db.trees[treeIndex];
    tree.memberIds = Array.isArray(tree.memberIds) ? tree.memberIds : [];
    tree.members = Array.isArray(tree.members) ? tree.members : [];

    const useSemyaModel =
      String(process.env.RODNYA_FEDERATED_SEMYI_ENABLED || "")
        .trim()
        .toLowerCase() === "true";
    const boundSemya = tree.semyaId
      ? (db.semyi || []).find((s) => s.id === tree.semyaId && !s.deletedAt)
      : null;
    const activeSemyaMembership = boundSemya
      ? (db.semyaMembers || []).find(
          (m) =>
            m.semyaId === boundSemya.id &&
            m.userId === userId &&
            !m.hiddenAt,
        )
      : null;

    const isCreator = tree.creatorId === userId;
    const isMember = tree.memberIds.includes(userId) || tree.members.includes(userId);
    if (useSemyaModel && boundSemya) {
      if (!activeSemyaMembership) {
        return false;
      }
    } else if (!isCreator && !isMember) {
      return false;
    }

    const canDelete = boundSemya
      ? activeSemyaMembership?.role === "owner" ||
        (!useSemyaModel && !activeSemyaMembership && isCreator)
      : isCreator;

    if (canDelete) {
      if (boundSemya) {
        const deletedAt = nowIso();
        boundSemya.deletedAt = deletedAt;
        boundSemya.updatedAt = deletedAt;
        for (const m of db.semyaMembers || []) {
          if (m.semyaId === boundSemya.id && !m.hiddenAt) {
            m.hiddenAt = deletedAt;
          }
        }
      }
      db.trees.splice(treeIndex, 1);
      db.persons = db.persons.filter((entry) => entry.treeId !== treeId);
      db.relations = db.relations.filter((entry) => entry.treeId !== treeId);
      db.circles = db.circles.filter((entry) => entry.treeId !== treeId);
      db.circleMembers = db.circleMembers.filter(
        (entry) => entry.treeId !== treeId,
      );
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
      db.gatherings = (db.gatherings || []).filter((entry) => entry.treeId !== treeId);
      db.polls = (db.polls || []).filter((entry) => entry.treeId !== treeId);
      db.storyRequests = (db.storyRequests || []).filter((entry) => entry.treeId !== treeId);
      db.profileArticles = (db.profileArticles || []).filter((entry) => entry.treeId !== treeId);
      if (removedChatIds.length > 0) {
        const removedChatSet = new Set(removedChatIds);
        db.chatDrafts = (db.chatDrafts || []).filter((entry) => !removedChatSet.has(entry.chatId));
        db.chatPins = ensureChatPins(db).filter((entry) => !removedChatSet.has(entry.chatId));
      }
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
    if (activeSemyaMembership && !activeSemyaMembership.hiddenAt) {
      activeSemyaMembership.hiddenAt = nowIso();
    }
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
  },

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
  },

  /// Снимает привязку пользователя с person record. Имя/гендер/фото
  /// person'а НЕ трогаются — после нового additive-фикса в
  /// linkPersonToUser они и так не должны были быть переписаны;
  /// если до фикса перезаписались, владелец дерева может править их
  /// руками через обычный edit.
  ///
  /// Возвращает:
  ///   * `null` — нет дерева
  ///   * `undefined` — нет такого person'а в дереве
  ///   * `false` — caller (actorId) не имеет прав отвязывать в этом
  ///     дереве (он не владелец)
  ///   * person snapshot после отвязки — успех
  async unlinkUserFromPerson({treeId, personId, actorId}) {
    const db = await this._read();
    const tree = db.trees.find((entry) => entry.id === treeId);
    if (!tree) {
      return null;
    }
    const isSemyaOwner = Boolean(
      tree.semyaId &&
      (db.semyi || []).some((s) => s.id === tree.semyaId && !s.deletedAt) &&
      (db.semyaMembers || []).some(
        (m) =>
          m.semyaId === tree.semyaId &&
          m.userId === actorId &&
          m.role === "owner" &&
          !m.hiddenAt,
      ),
    );
    if (tree.creatorId !== actorId && !isSemyaOwner) {
      return false;
    }
    const person = db.persons.find(
      (entry) => entry.id === personId && entry.treeId === treeId,
    );
    if (!person) {
      return undefined;
    }
    if (!person.userId) {
      return structuredClone(person);
    }

    const detachedUserId = person.userId;
    person.userId = null;
    person.identityId = null;
    person.updatedAt = nowIso();

    // Если у юзера больше нет ни одной person-карточки в этом
    // дереве — он перестаёт быть «членом» дерева. Иначе у него в
    // available-trees висит дерево, в которое он зайти зайдёт, а
    // увидит пустоту: нет своего person'а, нет «Это вы» индикатора.
    // Юзер-репорт: «раз я Степу отвязал, он не должен видеть дерево».
    const stillHasPersonInTree = db.persons.some(
      (entry) => entry.treeId === treeId && entry.userId === detachedUserId,
    );
    if (!stillHasPersonInTree) {
      if (Array.isArray(tree.memberIds)) {
        tree.memberIds = tree.memberIds.filter(
          (entry) => entry !== detachedUserId,
        );
      }
      if (Array.isArray(tree.members)) {
        tree.members = tree.members.filter(
          (entry) => entry !== detachedUserId,
        );
      }
      if (tree.semyaId && detachedUserId !== tree.creatorId) {
        const now = nowIso();
        for (const membership of db.semyaMembers || []) {
          if (
            membership.semyaId === tree.semyaId &&
            membership.userId === detachedUserId &&
            !membership.hiddenAt &&
            membership.role !== "owner"
          ) {
            membership.hiddenAt = now;
          }
        }
      }
      tree.updatedAt = nowIso();
    }

    this._reconcilePersonIdentities(db);

    await this._write(db);
    return structuredClone(person);
  },

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
      // additive=true по той же причине что и в linkPersonToUser —
      // не затирать имя/гендер существующего person record.
      applyCanonicalProfileToPerson(existingPerson, user?.profile, {
        additive: true,
      });
      this._attachPersonToIdentity(db, existingPerson, canonicalIdentity, userId);
      tree.memberIds = Array.isArray(tree.memberIds) ? tree.memberIds : [];
      tree.members = Array.isArray(tree.members) ? tree.members : [];
      if (!tree.memberIds.includes(userId)) {
        tree.memberIds.push(userId);
      }
      if (!tree.members.includes(userId)) {
        tree.members.push(userId);
      }
      this._ensureSemyaMembershipForLegacyJoin(db, tree, userId);
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
      this._ensureSemyaMembershipForLegacyJoin(db, tree, userId);
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
    this._ensureSemyaMembershipForLegacyJoin(db, tree, userId);
    tree.updatedAt = nowIso();
    this._attachPersonToIdentity(db, person, canonicalIdentity, userId);
    this._reconcilePersonIdentities(db);

    await this._write(db);
    return structuredClone(person);
  },

  // SPEED-9 B: prefetchedDb — опциональный уже прочитанный блоб
  // (например, снимок requireTreeAccess из app.js). Без него — как
  // раньше, честный собственный _read().
  //
  // SPEED-10: usersById строится ОДИН раз на весь вызов (было: db.users
  // .find(...) внутри buildCanonicalPersonView на КАЖДОГО person — O(P×U)).
  async listPersons(treeId, prefetchedDb = null) {
    const db = prefetchedDb || (await this._read());
    const usersById = buildUsersByIdMap(db);
    return db.persons
      .filter((person) => person.treeId === treeId)
      .sort((left, right) => String(left.name || "").localeCompare(String(right.name || "")))
      .map((person) => buildCanonicalPersonView(db, person, {usersById}));
  },

  async findPerson(treeId, personId, prefetchedDb = null) {
    const db = prefetchedDb || (await this._read());
    return this._buildPersonViewFromGraph(db, treeId, personId);
  },

  async getPersonDossier(treeId, personId) {
    const db = await this._read();
    const personView = this._buildPersonViewFromGraph(db, treeId, personId);
    if (!personView) {
      return null;
    }

    const linkedUser = personView.userId
      ? db.users.find((entry) => entry.id === personView.userId) || null
      : null;

    return {
      person: personView,
      linkedProfile: linkedUser?.profile ? structuredClone(linkedUser.profile) : null,
    };
  },

  // SPEED-10: normCache — опциональная Map personId→normalizePersonForScoring
  // (см. identity-matcher.js), построенная и переиспользуемая вызывающим
  // на протяжении ОДНОГО listPendingMergeProposalsForUser: тот же person
  // проверяется тут МНОГОКРАТНО (кандидат в _ensureCrossTreeMergeProposals,
  // потом снова в _markStaleMergeProposals, потом снова в финальном
  // .filter()) — без кэша каждый раз заново гонял normalizeName/
  // normalizeNameTokens/normalizeIsoDate по обеим сторонам (scorePersonPair).
  // Без normCache — прежнее поведение (reviewMergeProposal и т.п.
  // одиночные вызовы, кэш ради одной пары не нужен).
  _scorePersonPairCached(left, right, normCache = null) {
    if (!normCache) {
      return scorePersonPair(left, right);
    }
    const leftKey = left?.id;
    const rightKey = right?.id;
    let leftNorm = leftKey && normCache.get(leftKey);
    if (!leftNorm) {
      leftNorm = normalizePersonForScoring(left);
      if (leftKey) normCache.set(leftKey, leftNorm);
    }
    let rightNorm = rightKey && normCache.get(rightKey);
    if (!rightNorm) {
      rightNorm = normalizePersonForScoring(right);
      if (rightKey) normCache.set(rightKey, rightNorm);
    }
    return scoreNormalizedPersons(leftNorm, rightNorm);
  },

  /// A-copy: чья карточка для зрителя — «own» (ваша/в вашем дереве),
  /// «shared» (уже общая — identity связана с несколькими) либо «other».
  _mergePersonOwnership(db, person, viewerUserId) {
    if (!person) return "other";
    const normalizedViewer = normalizeNullableString(viewerUserId);
    if (
      normalizedViewer &&
      personStewardUserIds(db, person).includes(normalizedViewer)
    ) {
      return "own";
    }
    const identityId = normalizeNullableString(person.identityId);
    if (identityId) {
      const linkedCount = db.persons.filter(
        (entry) => entry.identityId === identityId,
      ).length;
      if (linkedCount > 1) return "shared";
    }
    return "other";
  },

  _notifyReviewers(db, {type, title, body, reviewerUserIds, data}) {
    db.notifications = Array.isArray(db.notifications) ? db.notifications : [];
    const normalizedReviewerIds = normalizeParticipantIds(reviewerUserIds);
    for (const userId of normalizedReviewerIds) {
      const alreadyQueued = db.notifications.some((notification) => {
        return (
          notification.userId === userId &&
          notification.type === type &&
          !notification.readAt &&
          notification.data?.proposalId === data?.proposalId &&
          notification.data?.claimId === data?.claimId
        );
      });
      if (alreadyQueued) {
        continue;
      }
      db.notifications.push(
        createNotificationRecord({
          userId,
          type,
          title,
          body,
          data,
        }),
      );
    }
  },

  // D1: вместо boolean возвращает ЖУРНАЛ слияния — что именно переехало
  // и что поглотилось. По нему unmerge восстанавливает source-identity.
  // Чтение старого `mergeApplied: true` остаётся совместимым (unmerge на
  // легаси-boolean отвечает 409 — применённых слияний в проде ещё нет).
  _mergeIdentitiesForProposal(db, proposal) {
    const targetIdentityId = normalizeNullableString(proposal.toIdentityId);
    const sourceIdentityId = normalizeNullableString(proposal.candidateIdentityId);
    if (!targetIdentityId || !sourceIdentityId || targetIdentityId === sourceIdentityId) {
      // No-op слияние (одна identity) — журнал пустой, но валидный.
      return {
        movedPersonIds: [],
        movedAttributeIds: [],
        sourceIdentityId: sourceIdentityId || targetIdentityId || null,
        targetIdentityId: targetIdentityId || null,
        userIdAbsorbed: false,
        claimedByAbsorbed: false,
        appliedAt: nowIso(),
      };
    }

    const targetIdentity = db.personIdentities.find(
      (identity) => identity.id === targetIdentityId,
    );
    const sourceIdentity = db.personIdentities.find(
      (identity) => identity.id === sourceIdentityId,
    );
    if (!targetIdentity || !sourceIdentity) {
      return false;
    }
    if (
      targetIdentity.userId &&
      sourceIdentity.userId &&
      targetIdentity.userId !== sourceIdentity.userId
    ) {
      return false;
    }

    const movedPersonIds = [];
    for (const person of db.persons) {
      if (person.identityId === sourceIdentityId) {
        person.identityId = targetIdentityId;
        person.updatedAt = nowIso();
        movedPersonIds.push(person.id);
      }
    }
    const movedAttributeIds = [];
    for (const attribute of db.personAttributes || []) {
      if (attribute.identityId === sourceIdentityId) {
        attribute.identityId = targetIdentityId;
        attribute.updatedAt = nowIso();
        movedAttributeIds.push(attribute.id);
      }
    }

    const userIdAbsorbed =
      !targetIdentity.userId && Boolean(sourceIdentity.userId);
    const claimedByAbsorbed =
      !targetIdentity.claimedByUserId &&
      Boolean(sourceIdentity.claimedByUserId);

    targetIdentity.userId = targetIdentity.userId || sourceIdentity.userId || null;
    targetIdentity.claimedByUserId =
      targetIdentity.claimedByUserId || sourceIdentity.claimedByUserId || null;
    targetIdentity.personIds = normalizeParticipantIds([
      ...(targetIdentity.personIds || []),
      ...(sourceIdentity.personIds || []),
    ]);
    targetIdentity.stewardUserIds = normalizeParticipantIds([
      ...(targetIdentity.stewardUserIds || []),
      ...(sourceIdentity.stewardUserIds || []),
    ]);
    targetIdentity.isLiving =
      targetIdentity.isLiving === true || sourceIdentity.isLiving === true;
    targetIdentity.isPublicDiscoverable =
      targetIdentity.isPublicDiscoverable === true &&
      sourceIdentity.isPublicDiscoverable === true;
    targetIdentity.updatedAt = nowIso();
    sourceIdentity.personIds = [];
    sourceIdentity.mergedInto = targetIdentityId;
    sourceIdentity.isPublicDiscoverable = false;
    sourceIdentity.updatedAt = nowIso();

    this._reconcilePersonIdentities(db);
    return {
      movedPersonIds,
      movedAttributeIds,
      sourceIdentityId,
      targetIdentityId,
      userIdAbsorbed,
      claimedByAbsorbed,
      appliedAt: nowIso(),
    };
  },

  async createPerson({
    treeId,
    creatorId,
    personData,
    userId = null,
    sourcePersonId = null,
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
          ensureCirclesForTree(db, tree);
          upsertPersonAttributesForPerson(db, existingLinkedPerson, creatorId);
          await this._write(db);
        }
        return structuredClone(existingLinkedPerson);
      }
    }

    // Phase 0 cross-tree picker: if the caller picked an existing
    // relative from one of their other trees, we (a) ensure the
    // source has a PersonIdentity (creating one if it didn't),
    // and (b) inherit that identityId onto the new person so they
    // are correlated as "the same human" across trees. Phase 1
    // turns this hint into full edit-propagation; for now it just
    // tags the relationship.
    //
    // sourcePersonId is RESOLVED here, not at the route layer, so
    // a malicious client can't forge an identityId — the source
    // must live in a tree the caller has access to. The route
    // layer is responsible for that access check before calling.
    let sourcePerson = null;
    if (sourcePersonId) {
      sourcePerson = db.persons.find(
        (entry) => entry.id === sourcePersonId,
      ) || null;
      if (sourcePerson) {
        const sourceTree = db.trees.find(
          (entry) => entry.id === sourcePerson.treeId,
        );
        if (
          !sourceTree ||
          !this._userCanAccessTreeRecord(sourceTree, creatorId, db)
        ) {
          // Don't surface the existence of inaccessible persons —
          // treat as "source unknown" and proceed without the link.
          sourcePerson = null;
        }
      }
    }

    let canonicalIdentity = userId ? this._ensureUserIdentity(db, userId) : null;
    if (!canonicalIdentity && sourcePerson) {
      // Source has an identity already → reuse it. Otherwise
      // create a fresh PersonIdentity record and attach BOTH the
      // source and the new person to it, so they share a canonical
      // node in the unified graph.
      const identities = this._ensurePersonIdentityCollection(db);
      const existingIdentity = sourcePerson.identityId
        ? identities.find((entry) => entry.id === sourcePerson.identityId)
        : null;
      if (existingIdentity) {
        canonicalIdentity = existingIdentity;
      } else {
        canonicalIdentity = createPersonIdentityRecord({
          personIds: [sourcePerson.id],
        });
        identities.push(canonicalIdentity);
        sourcePerson.identityId = canonicalIdentity.id;
        sourcePerson.updatedAt = nowIso();
      }
    }

    // Pre-fill any fields the caller didn't supply from the source
    // record, so the picker can drop a partial `personData` and
    // still get a fully-populated relative. Caller-supplied fields
    // always win — no overwrites of user intent.
    const mergedPersonData = sourcePerson
      ? mergePersonDataFromSource(personData, sourcePerson)
      : personData;

    const person = buildPersonRecord({
      treeId,
      creatorId,
      personData: mergedPersonData,
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
      this._ensureSemyaMembershipForLegacyJoin(db, tree, userId);
    }
    tree.updatedAt = nowIso();
    if (canonicalIdentity) {
      this._attachPersonToIdentity(db, person, canonicalIdentity, userId);
    }
    // SPEED-14: the `else` branch here used to call _reconcilePersonIdentities(db)
    // and then call it AGAIN, unconditionally, a few lines below —
    // _appendTreeChangeRecord in between only pushes to db.treeChangeRecords
    // (verified — no persons/personIdentities interaction), so the first call
    // was a pure no-op duplicate of the second on every no-canonicalIdentity
    // create. Removed; the unconditional call below still covers both branches.
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
    ensureCirclesForTree(db, tree);
    upsertPersonAttributesForPerson(db, person, creatorId);

    await this._write(db);
    return structuredClone(person);
  },

  /// Bulk-copy persons from one tree to another, then bridge any
  /// source-tree relations that have at least one endpoint among
  /// the imported set. "Bridging" means translating the relation's
  /// endpoint personIds: if the source endpoint was just imported,
  /// use the new target id; if it wasn't imported but already
  /// exists in target via shared `identityId` (e.g. the user
  /// themselves on both trees), use that existing id; otherwise
  /// skip. The result is the natural answer to "I dragged my
  /// girlfriend's card from the Кузнецовых tree into Родня — why
  /// is she empty and disconnected from me?". Person data
  /// (name / photo / dates) is fully inherited via the existing
  /// `mergePersonDataFromSource` path.
  ///
  /// Idempotent on relations — if the same relation already exists
  /// between the bridged endpoints in target it isn't duplicated.
  /// Idempotent on persons too — picking someone who's already in
  /// target (via identityId) results in the existing target person
  /// being reused, not a duplicate row.
  async bulkImportPersonsToTree({
    sourceTreeId,
    sourcePersonIds,
    targetTreeId,
    actorId,
  }) {
    const db = await this._read();
    const sourceTree = db.trees.find((entry) => entry.id === sourceTreeId);
    const targetTree = db.trees.find((entry) => entry.id === targetTreeId);
    if (!sourceTree || !targetTree) return null;
    if (
      !this._userCanAccessTreeRecord(sourceTree, actorId, db) ||
      !this._userCanAccessTreeRecord(targetTree, actorId, db)
    ) {
      return null;
    }
    if (!Array.isArray(sourcePersonIds) || sourcePersonIds.length === 0) {
      return {persons: [], relations: []};
    }
    const requestedIds = Array.from(new Set(
      sourcePersonIds
        .map((value) => normalizeNullableString(value))
        .filter((value) => value),
    ));
    const sourcePersonRecords = requestedIds
      .map((id) => db.persons.find(
        (entry) => entry.id === id && entry.treeId === sourceTreeId,
      ))
      .filter(Boolean);

    // Map identityId → existing target personId. Built before we
    // start importing so the user-themselves card on target is
    // immediately discoverable as a relation endpoint.
    const targetPersonsByIdentity = new Map();
    for (const targetPerson of db.persons) {
      if (targetPerson.treeId !== targetTreeId) continue;
      const identity = normalizeNullableString(targetPerson.identityId);
      if (identity) {
        targetPersonsByIdentity.set(identity, targetPerson.id);
      }
    }

    const sourceToTargetMap = new Map();
    const importedPersons = [];

    for (const sourcePerson of sourcePersonRecords) {
      const identityId = normalizeNullableString(sourcePerson.identityId);
      if (identityId && targetPersonsByIdentity.has(identityId)) {
        // Already in target as the same human — skip the copy and
        // map the source id to the existing target id so any
        // source relation involving this person bridges to the
        // existing target card.
        sourceToTargetMap.set(
          sourcePerson.id,
          targetPersonsByIdentity.get(identityId),
        );
        continue;
      }

      // Ensure the source row has a canonical identity so the new
      // target row can share it. Reuse the existing one if any,
      // otherwise allocate.
      let canonicalIdentity = null;
      if (identityId) {
        const identities = this._ensurePersonIdentityCollection(db);
        canonicalIdentity = identities.find((entry) => entry.id === identityId);
      }
      if (!canonicalIdentity) {
        const identities = this._ensurePersonIdentityCollection(db);
        canonicalIdentity = createPersonIdentityRecord({
          personIds: [sourcePerson.id],
        });
        identities.push(canonicalIdentity);
        sourcePerson.identityId = canonicalIdentity.id;
        sourcePerson.updatedAt = nowIso();
      }

      const mergedData = mergePersonDataFromSource({}, sourcePerson);
      const newPerson = buildPersonRecord({
        treeId: targetTreeId,
        creatorId: actorId,
        identityId: canonicalIdentity.id,
        personData: mergedData,
      });
      db.persons.push(newPerson);
      this._attachPersonToIdentity(db, newPerson, canonicalIdentity, null);
      this._appendTreeChangeRecord(db, {
        treeId: targetTreeId,
        actorId,
        type: "person.created",
        personId: newPerson.id,
        details: {
          after: structuredClone(newPerson),
          importedFrom: {
            sourceTreeId,
            sourcePersonId: sourcePerson.id,
          },
        },
      });
      sourceToTargetMap.set(sourcePerson.id, newPerson.id);
      targetPersonsByIdentity.set(canonicalIdentity.id, newPerson.id);
      importedPersons.push(newPerson);
    }

    // Resolve a source personId to a target personId via either
    // (a) the just-imported map, or (b) identity bridge to a
    // pre-existing target person (the "user themselves" case).
    const bridgeToTarget = (sourcePersonId) => {
      if (!sourcePersonId) return null;
      if (sourceToTargetMap.has(sourcePersonId)) {
        return sourceToTargetMap.get(sourcePersonId);
      }
      const candidate = db.persons.find(
        (entry) =>
          entry.id === sourcePersonId && entry.treeId === sourceTreeId,
      );
      const identity = normalizeNullableString(candidate?.identityId);
      if (identity && targetPersonsByIdentity.has(identity)) {
        return targetPersonsByIdentity.get(identity);
      }
      return null;
    };

    const requestedIdSet = new Set(requestedIds);
    const importedRelations = [];
    const sourceRelations = db.relations.filter(
      (entry) => entry.treeId === sourceTreeId,
    );
    for (const sourceRelation of sourceRelations) {
      const involvesImported =
        requestedIdSet.has(sourceRelation.person1Id) ||
        requestedIdSet.has(sourceRelation.person2Id);
      if (!involvesImported) continue;
      const newP1 = bridgeToTarget(sourceRelation.person1Id);
      const newP2 = bridgeToTarget(sourceRelation.person2Id);
      if (!newP1 || !newP2 || newP1 === newP2) continue;

      const existingRelation = db.relations.find((entry) => {
        return (
          entry.treeId === targetTreeId &&
          ((entry.person1Id === newP1 && entry.person2Id === newP2) ||
            (entry.person1Id === newP2 && entry.person2Id === newP1))
        );
      });
      if (existingRelation) continue;

      const timestamp = nowIso();
      const newRelation = {
        id: crypto.randomUUID(),
        treeId: targetTreeId,
        person1Id: newP1,
        person2Id: newP2,
        relation1to2: sourceRelation.relation1to2,
        relation2to1: sourceRelation.relation2to1,
        isConfirmed: true,
        createdAt: timestamp,
        updatedAt: timestamp,
        createdBy: actorId,
        marriageDate: sourceRelation.marriageDate ?? null,
        divorceDate: sourceRelation.divorceDate ?? null,
        customRelationLabel1to2: sourceRelation.customRelationLabel1to2 || null,
        customRelationLabel2to1: sourceRelation.customRelationLabel2to1 || null,
        // Skip parent-set / union plumbing — those are derived
        // during normalization and re-derive correctly on next
        // read. Carrying them across trees would force us to also
        // import sibling parents to keep the set consistent, and
        // that's a bigger semantic call for a separate iteration.
        parentSetId: null,
        parentSetType: null,
        isPrimaryParentSet: null,
        unionId: null,
        unionType: null,
        unionStatus: null,
      };
      db.relations.push(newRelation);
      this._appendTreeChangeRecord(db, {
        treeId: targetTreeId,
        actorId,
        type: "relation.created",
        personIds: [newP1, newP2],
        relationId: newRelation.id,
        details: {
          after: structuredClone(newRelation),
          importedFrom: {
            sourceTreeId,
            sourceRelationId: sourceRelation.id,
          },
        },
      });
      importedRelations.push(newRelation);
    }

    targetTree.updatedAt = nowIso();
    ensureCirclesForTree(db, targetTree);
    this._reconcilePersonIdentities(db);
    await this._write(db);

    return {
      persons: importedPersons.map((entry) => structuredClone(entry)),
      relations: importedRelations.map((entry) => structuredClone(entry)),
    };
  },

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
    // F5: точность дат («знаю только год») нормализуется тем же путём,
    // что и сами даты; без даты точность не имеет смысла — exact.
    nextPerson.birthDatePrecision = nextPerson.birthDate
      ? normalizeDatePrecision(nextPerson.birthDatePrecision)
      : "exact";
    nextPerson.deathDatePrecision = nextPerson.deathDate
      ? normalizeDatePrecision(nextPerson.deathDatePrecision)
      : "exact";
    nextPerson.isAlive = nextPerson.deathDate === null;
    nextPerson.visibility = normalizePersonVisibility(
      nextPerson.visibility,
      defaultPersonVisibility({
        deathDate: nextPerson.deathDate,
        isAlive: nextPerson.isAlive,
      }),
    );
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
    ensureCirclesForTree(db, treeId);
    upsertPersonAttributesForPerson(db, person, actorId);

    // Phase 1.1 of the unified-graph migration: identity propagation.
    // When a person record updates, fan the canonical-fields part of
    // the change out to every OTHER person record that shares the
    // same identityId (typically: the same human entered into a
    // different tree by the same user via the cross-tree picker, OR
    // the same user's auto-card in their own tree).
    //
    // Tree-local fields (notes / familySummary / bio / visibility)
    // are deliberately NOT propagated — those are the editor's
    // annotation about how this person fits into THIS tree's
    // story. A field "describing the human" (name, dates, places,
    // photos, gender) is shared because it's the same human;
    // editorial fields are per-tree.
    //
    // Returns the list of (treeId, personId) tuples that were
    // touched so the route layer can include it in the response —
    // the Flutter client uses it to invalidate per-tree caches.
    const propagatedTo = this._propagateIdentityFields(
      db,
      person,
      previousPerson,
      actorId,
    );

    await this._write(db);
    const result = structuredClone(person);
    if (propagatedTo.length > 0) {
      // Hidden side-channel for the route layer. Decorating the
      // returned record with a non-enumerable-style hint keeps
      // existing callers (which deepEqual-check the return) happy
      // while letting the route surface the affected trees in
      // the JSON response. Plain property — `mapPerson` will
      // ignore it because it pulls a fixed schema.
      result._propagatedTo = propagatedTo;
    }
    return result;
  },

  _syncTreeToBranch(db, tree) {
    if (!tree) return;
    if (!Array.isArray(db.branches)) db.branches = [];
    const memberIds = Array.isArray(tree.memberIds)
      ? [...tree.memberIds]
      : Array.isArray(tree.members)
          ? [...tree.members]
          : [];
    let branch = db.branches.find((b) => b.id === tree.id);
    if (!branch) {
      branch = {
        id: tree.id,
        legacyTreeId: tree.id,
        ownerId: tree.creatorId,
        name: tree.name,
        description: tree.description || "",
        isPrivate: tree.isPrivate !== false,
        kind: tree.kind || "family",
        // Phase 3.1 (DECISIONS.md ответ D): includeRules с
        // полным shape (anchorPersonId / maxHops). Совпадает с
        // migration-utils.buildBranchFromTree — incremental mirror
        // и one-shot migration пишут идентичную форму.
        includeRules: {
          type: "manual",
          manualPersonIds: [],
          anchorPersonId: null,
          maxHops: 5,
        },
        memberIds,
        publicSlug: tree.publicSlug || null,
        isCertified: tree.isCertified === true,
        certificationNote: tree.certificationNote || null,
        createdAt: tree.createdAt,
        updatedAt: tree.updatedAt,
        deletedAt: null,
      };
      db.branches.push(branch);
      return;
    }
    branch.name = tree.name;
    branch.description = tree.description || "";
    branch.isPrivate = tree.isPrivate !== false;
    branch.kind = tree.kind || "family";
    branch.memberIds = memberIds;
    branch.publicSlug = tree.publicSlug || null;
    branch.isCertified = tree.isCertified === true;
    branch.certificationNote = tree.certificationNote || null;
    branch.updatedAt = tree.updatedAt;
    branch.deletedAt = null;
    // Phase 3.1 lazy-fill для existing branches без новых rule
    // полей. ??= triggers только на undefined/null — не overwrite'ит
    // user-set значения.
    if (!branch.includeRules || typeof branch.includeRules !== "object") {
      branch.includeRules = {
        type: "manual",
        manualPersonIds: [],
        anchorPersonId: null,
        maxHops: 5,
      };
    } else {
      branch.includeRules.anchorPersonId ??= null;
      branch.includeRules.maxHops ??= 5;
      if (!Array.isArray(branch.includeRules.manualPersonIds)) {
        branch.includeRules.manualPersonIds = [];
      }
    }
  },

  _buildBloodAdjacency(db) {
    const adjacency = new Map();
    const relations = Array.isArray(db.graphRelations)
      ? db.graphRelations
      : [];
    const ensure = (id) => {
      if (!adjacency.has(id)) adjacency.set(id, []);
      return adjacency.get(id);
    };
    // Adjacency uses the role-of-TARGET convention. For a relation
    // (p1, p2, relation1to2='parent') — p1 is parent of p2 — we
    // record:
    //   adjacency[p2] += {neighbor: p1, edgeType: 'parent'}
    //   adjacency[p1] += {neighbor: p2, edgeType: 'child'}
    // Walking p2 → p1 means I traversed an edge whose target is a
    // 'parent' (going UP / towards ancestor). Walking p1 → p2 means
    // I traversed an edge whose target is a 'child' (going DOWN /
    // towards descendant). This matches the convention in
    // _buildBranchVisiblePersonIds (line ~12420) so two engines
    // describe the same family the same way.
    //
    // If `relation2to1` is missing we derive it via `mirrorBloodType`
    // — the existing branch-visibility code does the same fallback
    // through `relationMirror`. Without this, half of legacy rows
    // (one-sided imports) silently drop out of the blood graph and
    // BFS returns "no path" for relatives that obviously share DNA.
    for (const relation of relations) {
      if (relation.deletedAt) continue;
      const r1 = canonicalBloodType(relation.relation1to2);
      const r2 =
        canonicalBloodType(relation.relation2to1) ||
        mirrorBloodType(relation.relation1to2);
      if (!r1 || !r2) continue;
      ensure(relation.person2Id).push({
        neighbor: relation.person1Id,
        edgeType: r1,
      });
      ensure(relation.person1Id).push({
        neighbor: relation.person2Id,
        edgeType: r2,
      });
    }
    return adjacency;
  },

  // Phase 3.4-prep (DECISIONS.md 2026-05-10 Q3): grantor-side список
  // grants выписанных текущим юзером. Симметричен `listMyGrantsForUser`
  // (grantee-side). Пагинируется не только активными — включаем
  // revoked за 30d window для audit visibility «недавно отозвал».
  async listMyIssuedGrants({userId, includeRevokedSinceDays = 30}) {
    const normalizedUser = normalizeNullableString(userId);
    if (!normalizedUser) return [];
    const db = await this._read();
    const cutoff = new Date(Date.now() - includeRevokedSinceDays * 86_400_000);
    return (db.graphPersonEditGrants || [])
      .filter((entry) => entry.grantorUserId === normalizedUser)
      .filter((entry) => {
        if (!entry.revokedAt) return true;
        const revoked = new Date(entry.revokedAt);
        return Number.isFinite(revoked.getTime()) && revoked >= cutoff;
      })
      .map((entry) => structuredClone(entry));
  },

  // Filter sensitive attribute fields (`field === "contacts"`)
  // when viewer isn't the graphPerson owner. Used by attributes
  // endpoint. Non-sensitive fields проходят без дополнительной
  // gate'и — посетитель уже прошёл `requireTreeAccess`, значит
  // имеет право видеть базовые поля person'а в этом дереве.
  filterSensitiveAttributesForViewer({
    db,
    graphPerson,
    viewerUserId,
    attributes,
  }) {
    if (!Array.isArray(attributes)) return [];
    return attributes.filter((attr) =>
      this._userCanSeeSensitiveAttributeField(
        db,
        graphPerson,
        viewerUserId,
        attr?.field,
      ),
    );
  },

  async deletePerson(treeId, personId, actorId = null) {
    // Ship Q4a (2026-05-28): soft-delete semantics. Previously hard-
    // delete via db.persons.filter (line 13052). Now moves person к
    // db.deletedPersons snapshot collection + filter-removes из
    // db.persons + db.relations (preserves 95 read sites unchanged
    // — Path 2 from design doc ec12804).
    //
    // External behavior identical:
    //   • DELETE returns true (was true)
    //   • Subsequent GET /v1/trees/.../persons returns без person
    //   • person.deleted tree-change event emitted с before snapshot
    //   • tree.memberIds + tree.members updated when applicable
    //   • relations cleaned up (snapshot retained в deletedPersons)
    //
    // New internal state:
    //   • db.deletedPersons row carries snapshot + relations + audit
    //   • hardDeleteScheduledAt = deletedAt + 30d (configurable)
    //   • earliestHardDelete = deletedAt + 3h (floor — protects vs
    //     immediate purge if user misclicks restore либо config bad)
    //
    // Restore (restorePerson) reverses: moves snapshot back к
    // db.persons + relations back к db.relations, clears tree-change
    // audit annotation. Idempotent — re-restore of already-restored
    // row = 404 «уже восстановлен».
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

    // Ship Q4a: write snapshot row to deletedPersons для 30d restore.
    // Find семья binding (if any) — affects permission gate in
    // restore endpoint (members of bound семя can restore).
    const tree = db.trees.find((entry) => entry.id === treeId);
    const boundSemyaId = tree?.semyaId
      ? (db.semyi || []).find(
          (s) => s.id === tree.semyaId && !s.deletedAt,
        )?.id || null
      : null;
    const nowIsoStr = nowIso();
    const retentionDays = Number(process.env.RODNYA_DELETED_PERSONS_RETENTION_DAYS) || 30;
    const floorHours = Number(process.env.RODNYA_DELETED_PERSONS_FLOOR_HOURS) || 3;
    const hardDeleteAt = new Date(
      Date.parse(nowIsoStr) + retentionDays * 24 * 3600 * 1000,
    ).toISOString();
    const earliestHardDelete = new Date(
      Date.parse(nowIsoStr) + floorHours * 3600 * 1000,
    ).toISOString();
    db.deletedPersons = Array.isArray(db.deletedPersons) ? db.deletedPersons : [];
    db.deletedPersons.push({
      id: crypto.randomUUID(),
      originalPersonId: personId,
      treeId,
      semyaId: boundSemyaId,
      snapshot: deletedPerson,
      relationsSnapshot: removedRelations,
      deletedAt: nowIsoStr,
      deletedByUserId: actorId,
      hardDeleteScheduledAt: hardDeleteAt,
      earliestHardDelete,
      restoredAt: null,
      restoredByUserId: null,
    });

    this._reconcilePersonIdentities(db);
    ensureCirclesForTree(db, treeId);

    await this._write(db);
    return true;
  },

  /// Ship Q4a (2026-05-28): list deleted persons for caller.
  /// Scoped by семя membership — caller sees deleted persons из
  /// семья where they're an active member, plus deletions they
  /// themselves performed (even если no longer member). Empty
  /// list if no matches либо storage incapable.
  async listDeletedPersonsForUser({userId}) {
    if (!userId || typeof userId !== "string") return [];
    const db = await this._read();
    const memberSemyaIds = new Set(
      (db.semyaMembers || [])
        .filter((m) => m.userId === userId && !m.hiddenAt)
        .map((m) => m.semyaId),
    );
    const rows = (db.deletedPersons || []).filter((entry) => {
      if (entry.restoredAt) return false;
      if (entry.deletedByUserId === userId) return true;
      if (entry.semyaId && memberSemyaIds.has(entry.semyaId)) return true;
      return false;
    });
    return rows
      .sort((a, b) =>
        String(b.deletedAt || "").localeCompare(String(a.deletedAt || "")),
      )
      .map((entry) => structuredClone(entry));
  },

  _assertCanManageDeletedPerson(
    db,
    row,
    actorUserId,
    {requireActiveSemya = false} = {},
  ) {
    const semyaId = row.semyaId || null;
    let activeSemyaExists = false;
    let activeMembership = null;
    let hasHiddenRow = false;
    if (semyaId) {
      const semya = (db.semyi || []).find((s) => s.id === semyaId);
      if (requireActiveSemya && semya?.deletedAt) {
        throw new Error("SEMYA_DELETED");
      }
      activeSemyaExists = Boolean(semya && !semya.deletedAt);
      const memberRows = (db.semyaMembers || []).filter(
        (m) => m.userId === actorUserId && m.semyaId === semyaId,
      );
      activeMembership = memberRows.find((m) => !m.hiddenAt) || null;
      hasHiddenRow = memberRows.some((m) => Boolean(m.hiddenAt));
    }
    if (hasHiddenRow || (activeSemyaExists && !activeMembership)) {
      throw new Error("FORBIDDEN");
    }

    const tree = (db.trees || []).find((entry) => entry.id === row.treeId);
    const hasLegacyTreeAccess = Boolean(
      tree &&
      (tree.creatorId === actorUserId ||
        (Array.isArray(tree.memberIds) && tree.memberIds.includes(actorUserId))),
    );
    const isOriginalActor = row.deletedByUserId === actorUserId;
    const claimedUserId = normalizeNullableString(row.snapshot?.userId);

    if (claimedUserId) {
      if (semyaId && !activeSemyaExists && !isOriginalActor && !activeMembership) {
        throw new Error("FORBIDDEN");
      }
      if (!semyaId && !isOriginalActor && !hasLegacyTreeAccess) {
        throw new Error("FORBIDDEN");
      }
      if (actorUserId === claimedUserId) {
        return;
      }
      const identityId = normalizeNullableString(row.snapshot?.identityId);
      const hasSoftDeleteGrant = (db.graphPersonEditGrants || []).some(
        (g) =>
          !g.revokedAt &&
          g.granteeUserId === actorUserId &&
          g.scope === "soft-delete" &&
          ((identityId && g.graphPersonId === identityId) ||
            g.graphPersonId === row.originalPersonId),
      );
      if (!hasSoftDeleteGrant) {
        throw new Error("FORBIDDEN");
      }
      return;
    }

    if (semyaId) {
      if (activeSemyaExists) {
        if (
          activeMembership.role !== "editor" &&
          activeMembership.role !== "owner"
        ) {
          throw new Error("FORBIDDEN");
        }
        return;
      }
      const canManageByMembership =
        Boolean(activeMembership) &&
        (activeMembership.role === "editor" || activeMembership.role === "owner");
      if (!isOriginalActor && !canManageByMembership) {
        throw new Error("FORBIDDEN");
      }
      return;
    }

    if (!isOriginalActor && !hasLegacyTreeAccess) {
      throw new Error("FORBIDDEN");
    }
  },

  /// Ship Q4a: restore person из deletedPersons → live db.persons.
  /// Restores person snapshot + relations snapshot. Updates
  /// tree.memberIds/members if person had userId. Emits
  /// person.restored tree-change event. Throws:
  ///   • DELETED_PERSON_NOT_FOUND (404)
  ///   • ALREADY_RESTORED (409)
  ///   • HARD_DELETE_ELAPSED (410 — past retention window)
  ///   • FORBIDDEN (403 — role/owner/grant check failed)
  ///   • SEMYA_DELETED (410 — parent семя soft-deleted, restore
  ///     would orphan person)
  async restorePerson({deletedPersonId, actorUserId}) {
    if (!deletedPersonId || typeof deletedPersonId !== "string") {
      throw new Error("INVALID_INPUT");
    }
    if (!actorUserId) throw new Error("INVALID_ACTOR");

    return this._mutate((db) => {
      const row = (db.deletedPersons || []).find(
        (entry) => entry.id === deletedPersonId,
      );
      if (!row) throw new Error("DELETED_PERSON_NOT_FOUND");
      if (row.restoredAt) throw new Error("ALREADY_RESTORED");
      const now = Date.now();
      if (
        row.hardDeleteScheduledAt &&
        Date.parse(row.hardDeleteScheduledAt) < now
      ) {
        throw new Error("HARD_DELETE_ELAPSED");
      }

      this._assertCanManageDeletedPerson(db, row, actorUserId, {
        requireActiveSemya: true,
      });

      const tree = (db.trees || []).find((entry) => entry.id === row.treeId);
      if (!tree) {
        throw new Error("TREE_NOT_FOUND");
      }

      db.persons = Array.isArray(db.persons) ? db.persons : [];
      db.persons.push(structuredClone(row.snapshot));
      if (Array.isArray(row.relationsSnapshot)) {
        db.relations = Array.isArray(db.relations) ? db.relations : [];
        for (const rel of row.relationsSnapshot) {
          db.relations.push(structuredClone(rel));
        }
      }

      if (row.snapshot?.userId) {
        const kickedSnapshotUser =
          tree.semyaId &&
          (db.semyaMembers || []).some(
            (m) =>
              m.semyaId === tree.semyaId &&
              m.userId === row.snapshot.userId &&
              Boolean(m.hiddenAt),
          );
        if (!kickedSnapshotUser) {
          tree.memberIds = Array.isArray(tree.memberIds) ? tree.memberIds : [];
          if (!tree.memberIds.includes(row.snapshot.userId)) {
            tree.memberIds.push(row.snapshot.userId);
          }
          tree.members = Array.isArray(tree.members) ? tree.members : [];
          if (!tree.members.includes(row.snapshot.userId)) {
            tree.members.push(row.snapshot.userId);
          }
          this._ensureSemyaMembershipForLegacyJoin(db, tree, row.snapshot.userId);
          tree.updatedAt = nowIso();
        }
      }

      row.restoredAt = nowIso();
      row.restoredByUserId = actorUserId;

      this._appendTreeChangeRecord(db, {
        treeId: row.treeId,
        actorId: actorUserId,
        type: "person.restored",
        personId: row.originalPersonId,
        details: {
          deletedPersonId: row.id,
          deletedAt: row.deletedAt,
        },
      });
      this._reconcilePersonIdentities(db);
      ensureCirclesForTree(db, row.treeId);

      return structuredClone(row);
    });
  },

  /// Ship Q4a: explicit hard-purge of deleted person (skip 30d wait).
  /// User-initiated GDPR-style erasure. 3h floor protection — even
  /// если user immediately tries to purge, must wait floor period.
  /// Throws:
  ///   • DELETED_PERSON_NOT_FOUND (404)
  ///   • FLOOR_NOT_MET (409 — earliestHardDelete > now)
  ///   • FORBIDDEN (403 — permission similar к restore)
  ///   • ALREADY_RESTORED (409 — restored row не purge-able)
  async hardDeletePerson({deletedPersonId, actorUserId}) {
    if (!deletedPersonId || typeof deletedPersonId !== "string") {
      throw new Error("INVALID_INPUT");
    }
    if (!actorUserId) throw new Error("INVALID_ACTOR");

    const db = await this._read();
    const idx = (db.deletedPersons || []).findIndex(
      (entry) => entry.id === deletedPersonId,
    );
    if (idx < 0) throw new Error("DELETED_PERSON_NOT_FOUND");
    const row = db.deletedPersons[idx];
    if (row.restoredAt) throw new Error("ALREADY_RESTORED");
    if (
      row.earliestHardDelete &&
      Date.parse(row.earliestHardDelete) > Date.now()
    ) {
      throw new Error("FLOOR_NOT_MET");
    }

    this._assertCanManageDeletedPerson(db, row, actorUserId, {
      requireActiveSemya: false,
    });

    db.deletedPersons.splice(idx, 1);
    await this._write(db);
    return {purged: true, deletedPersonId};
  },

  _findPersonRecordById(db, personId) {
    const id = String(personId || "").trim();
    if (!id) return null;
    return (
      (Array.isArray(db.persons) ? db.persons : []).find(
        (entry) => entry.id === id,
      ) || null
    );
  },

  // Lightweight by-id tree resolver — articles are addressed by
  // personId alone (person ids are globally unique). Returns null if
  // the person doesn't exist. Read-only; route permission gates use it
  // to obtain treeId before requireTreeAccess / requireGraphPersonEdit.
  async findPersonTreeId(personId) {
    const id = String(personId || "").trim();
    if (!id) return null;
    const db = await this._read();
    const person = this._findPersonRecordById(db, id);
    return person ? person.treeId : null;
  },

  async listPushDeliveries(userId, {limit = 50} = {}) {
    const db = await this._read();
    return db.pushDeliveries
      .filter((entry) => entry.userId === userId)
      .sort((left, right) =>
        String(right.createdAt || "").localeCompare(String(left.createdAt || "")),
      )
      .slice(0, limit)
      .map((entry) => structuredClone(entry));
  },

  // SPEED-9 B: db — опциональный уже прочитанный блоб (снимок
  // requireTreeAccess из того же HTTP-запроса, всегда моложе любой
  // мутации в этом обработчике — GET-хендлер /v1/stories не мутирует).
  // Просроченные истории по-прежнему чистятся ниже через this._write —
  // не трогаем этот побочный эффект, только источник db.
  async listStories({
    treeId = null,
    authorId = null,
    viewerUserId = null,
    includeArchive = false,
    db: prefetchedDb = null,
  } = {}) {
    const db = prefetchedDb || (await this._read());
    const now = Date.now();
    const visibleStories = [];

    for (const story of db.stories) {
      const expired = isExpiredAt(story.expiresAt, now);
      if (expired && (!includeArchive || !viewerUserId || story.authorId !== viewerUserId)) {
        continue;
      }
      visibleStories.push(story);
    }

    const circleCache = this._createCircleVisibilityCache();
    return visibleStories
      .filter((entry) => {
        if (treeId && entry.treeId !== treeId) {
          return false;
        }
        if (authorId && entry.authorId !== authorId) {
          return false;
        }
        if (
          !this._canUserViewCircleContent(db, {
            treeId: entry.treeId,
            circleId: entry.circleId,
            authorId: entry.authorId,
            viewerUserId,
          }, circleCache)
        ) {
          return false;
        }
        return true;
      })
      .sort((left, right) =>
        String(right.createdAt || "").localeCompare(String(left.createdAt || "")),
      )
      .map((entry) => attachStoryReactions(db, entry));
  },

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
  },

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
    if (chat.createdBy && normalizedParticipantId === chat.createdBy) {
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
  },
};
