const path = require("node:path");
const crypto = require("node:crypto");
const {
  composeDisplayNameFromProfile,
  nowIso,
} = require("../helpers");

module.exports = {
  async createSemya({ownerId, name, treeId, description = null}) {
    if (!ownerId || typeof ownerId !== "string") {
      throw new Error("INVALID_OWNER_ID");
    }
    if (!name || typeof name !== "string" || !name.trim()) {
      throw new Error("INVALID_NAME");
    }
    if (!treeId || typeof treeId !== "string") {
      throw new Error("INVALID_TREE_ID");
    }

    const db = await this._read();
    const owner = db.users.find((entry) => entry.id === ownerId);
    if (!owner) {
      throw new Error("OWNER_NOT_FOUND");
    }
    const tree = db.trees.find((entry) => entry.id === treeId);
    if (!tree) {
      throw new Error("TREE_NOT_FOUND");
    }
    // One-tree-per-семья invariant (§3.1).
    const existingForTree = (db.semyi || []).find(
      (entry) => entry.treeId === treeId && !entry.deletedAt,
    );
    if (existingForTree) {
      throw new Error("TREE_ALREADY_BOUND");
    }

    const createdAt = nowIso();
    const semya = {
      id: crypto.randomUUID(),
      name: name.trim(),
      ownerId,
      treeId,
      description: description ? String(description).trim() : null,
      createdAt,
      updatedAt: createdAt,
      deletedAt: null,
    };
    const ownerMembership = {
      id: crypto.randomUUID(),
      semyaId: semya.id,
      userId: ownerId,
      role: "owner",
      joinedAt: createdAt,
      invitedByUserId: null,
      hasInviteGrant: true,
      hiddenAt: null,
    };

    db.semyi.push(semya);
    db.semyaMembers.push(ownerMembership);

    for (const memberIdRaw of Array.isArray(tree.memberIds) ? tree.memberIds : []) {
      const memberId = String(memberIdRaw || "").trim();
      if (!memberId || memberId === ownerId) {
        continue;
      }
      const exists = db.semyaMembers.some(
        (entry) => entry.semyaId === semya.id && entry.userId === memberId,
      );
      if (!exists) {
        db.semyaMembers.push({
          id: crypto.randomUUID(),
          semyaId: semya.id,
          userId: memberId,
          role: "viewer",
          joinedAt: createdAt,
          invitedByUserId: ownerId,
          hasInviteGrant: false,
          hiddenAt: null,
        });
      }
    }

    // Phase B Ship 5: reverse-FK + dual-write. Write tree.semyaId
    // atomically с семья record так чтобы requireTreeAccess (когда
    // feature flag ON) могла O(1) lookup семья без index walk.
    // Owner уже в tree.memberIds[] (createTree always seeds
    // memberIds: [creatorId]), поэтому не дублируем здесь.
    tree.semyaId = semya.id;

    await this._write(db);
    return structuredClone(semya);
  },

  // Phase B: легаси-пути вступления в дерево (accept tree-инвайта,
  // identity-attach, person-create-with-userId, restore из корзины)
  // писали только tree.memberIds. Для дерева, привязанного к семье,
  // этого мало: с RODNYA_FEDERATED_SEMYI_ENABLED=true доступ решает
  // ИСКЛЮЧИТЕЛЬНО членство в семье — без dual-write новый участник
  // ловил бы 403 сразу после флипа. Роль viewer — как в миграции
  // (решение Q1: безопасный дефолт, owner повышает вручную).
  _ensureSemyaMembershipForLegacyJoin(db, tree, userId, {allowUnhide = false} = {}) {
    const normalizedUserId = String(userId || "").trim();
    const semyaId = String(tree?.semyaId || "").trim();
    if (!normalizedUserId || !semyaId) {
      return;
    }
    const semya = (db.semyi || []).find((entry) => entry.id === semyaId);
    if (!semya) {
      return;
    }
    if (semya.deletedAt) {
      throw new Error("SEMYA_DELETED");
    }
    db.semyaMembers = Array.isArray(db.semyaMembers) ? db.semyaMembers : [];
    const existing = db.semyaMembers.find(
      (entry) =>
        entry.semyaId === semyaId && entry.userId === normalizedUserId,
    );
    if (existing) {
      if (existing.hiddenAt) {
        if (!allowUnhide) {
          throw new Error("KICKED_FROM_SEMYA");
        }
        existing.hiddenAt = null;
      }
      return;
    }
    db.semyaMembers.push({
      id: crypto.randomUUID(),
      semyaId,
      userId: normalizedUserId,
      role: "viewer",
      joinedAt: nowIso(),
      invitedByUserId: null,
      hasInviteGrant: false,
      hiddenAt: null,
    });
  },

  _isActiveSemyaOwnerForTree(db, treeId, actorUserId) {
    const normalizedActorId = String(actorUserId || "").trim();
    const normalizedTreeId = String(treeId || "").trim();
    if (!normalizedActorId || !normalizedTreeId || !db) {
      return false;
    }
    const tree = (db.trees || []).find((t) => t.id === normalizedTreeId);
    if (!tree?.semyaId) {
      return false;
    }
    const semya = (db.semyi || []).find(
      (s) => s.id === tree.semyaId && !s.deletedAt,
    );
    if (!semya) {
      return false;
    }
    return (db.semyaMembers || []).some(
      (m) =>
        m.semyaId === semya.id &&
        m.userId === normalizedActorId &&
        m.role === "owner" &&
        !m.hiddenAt,
    );
  },

  async findSemyaById(semyaId) {
    if (!semyaId || typeof semyaId !== "string") {
      return null;
    }
    const db = await this._read();
    const semya = (db.semyi || []).find((entry) => entry.id === semyaId);
    return semya ? structuredClone(semya) : null;
  },

  async listMembershipsForSemya(semyaId) {
    if (!semyaId || typeof semyaId !== "string") {
      return [];
    }
    const db = await this._read();
    return (db.semyaMembers || [])
      .filter((m) => m.semyaId === semyaId && !m.hiddenAt)
      .sort((left, right) =>
        String(left.joinedAt || "").localeCompare(String(right.joinedAt || "")),
      )
      .map((entry) => structuredClone(entry));
  },

  // SPEED-9 B: prefetchedDb — опциональный уже прочитанный блоб
  // (requireTreeAccess в app.js передаёт свой снимок, чтобы не читать
  // блоб дважды за один HTTP-запрос). Без него поведение прежнее.
  async findMembership(semyaId, userId, prefetchedDb = null) {
    if (!semyaId || !userId) {
      return null;
    }
    const db = prefetchedDb || (await this._read());
    const row = (db.semyaMembers || []).find(
      (m) => m.semyaId === semyaId && m.userId === userId && !m.hiddenAt,
    );
    return row ? structuredClone(row) : null;
  },

  async updateSemya({semyaId, actorUserId, name, description}) {
    if (!semyaId || typeof semyaId !== "string") {
      throw new Error("INVALID_SEMYA_ID");
    }
    if (!actorUserId) {
      throw new Error("INVALID_ACTOR");
    }

    const db = await this._read();
    const semya = (db.semyi || []).find(
      (entry) => entry.id === semyaId && !entry.deletedAt,
    );
    if (!semya) {
      throw new Error("SEMYA_NOT_FOUND");
    }
    // Owner-only mutation (Q2 — name editable by owner only).
    const actorMembership = (db.semyaMembers || []).find(
      (m) =>
        m.semyaId === semyaId &&
        m.userId === actorUserId &&
        m.role === "owner" &&
        !m.hiddenAt,
    );
    if (!actorMembership) {
      throw new Error("NOT_OWNER");
    }

    let mutated = false;
    const boundTree = semya.treeId
      ? (db.trees || []).find((entry) => entry.id === semya.treeId)
      : null;

    if (name !== undefined && name !== null) {
      if (typeof name !== "string" || !name.trim()) {
        throw new Error("INVALID_NAME");
      }
      const trimmed = name.trim();
      if (trimmed !== semya.name) {
        semya.name = trimmed;
        mutated = true;
      }
      if (boundTree && boundTree.name !== semya.name) {
        boundTree.name = semya.name;
        mutated = true;
      }
    }
    if (description !== undefined) {
      // null clears, string sets, no-op для same value
      const next = description === null ? null : String(description).trim();
      const current = semya.description ?? null;
      if (next !== current) {
        semya.description = next;
        mutated = true;
      }
      if (boundTree) {
        const nextTreeDesc = semya.description ?? "";
        if ((boundTree.description ?? "") !== nextTreeDesc) {
          boundTree.description = nextTreeDesc;
          mutated = true;
        }
      }
    }

    if (mutated) {
      const timestamp = nowIso();
      semya.updatedAt = timestamp;
      if (boundTree) {
        boundTree.updatedAt = timestamp;
      }
      await this._write(db);
    }
    return structuredClone(semya);
  },

  async addMembership({
    semyaId,
    userId,
    role,
    invitedByUserId,
    hasInviteGrant = false,
  }) {
    if (!semyaId || typeof semyaId !== "string") {
      throw new Error("INVALID_SEMYA_ID");
    }
    if (!userId || typeof userId !== "string") {
      throw new Error("INVALID_USER_ID");
    }
    if (role !== "editor" && role !== "viewer") {
      throw new Error("INVALID_ROLE");
    }

    const db = await this._read();
    const semya = (db.semyi || []).find(
      (entry) => entry.id === semyaId && !entry.deletedAt,
    );
    if (!semya) {
      throw new Error("SEMYA_NOT_FOUND");
    }
    const user = (db.users || []).find((entry) => entry.id === userId);
    if (!user) {
      throw new Error("USER_NOT_FOUND");
    }
    // Idempotent — если already member (любой role), return existing.
    const existing = (db.semyaMembers || []).find(
      (m) => m.semyaId === semyaId && m.userId === userId && !m.hiddenAt,
    );
    if (existing) {
      return {created: false, membership: structuredClone(existing)};
    }
    // hasInviteGrant only meaningful для editor (ENTITY-DESIGN §3.4).
    const grant = role === "editor" ? !!hasInviteGrant : false;
    const createdAt = nowIso();
    const membership = {
      id: crypto.randomUUID(),
      semyaId,
      userId,
      role,
      joinedAt: createdAt,
      invitedByUserId: invitedByUserId || null,
      hasInviteGrant: grant,
      hiddenAt: null,
    };
    db.semyaMembers.push(membership);
    // Phase B Ship 5: dual-write к tree.memberIds[] для backward
    // compat пока legacy tree-routes (requireTreeAccess pre-Phase-B
    // path) sunset не закроется (Week 8 staged rollout). Без этого
    // existing endpoints не видели бы новых членов семьи.
    const tree = (db.trees || []).find((t) => t.id === semya.treeId);
    if (tree) {
      tree.memberIds = Array.isArray(tree.memberIds) ? tree.memberIds : [];
      if (!tree.memberIds.includes(userId)) {
        tree.memberIds.push(userId);
      }
      // Legacy `tree.members` alias — same content, preserved.
      tree.members = Array.isArray(tree.members) ? tree.members : [];
      if (!tree.members.includes(userId)) {
        tree.members.push(userId);
      }
    }
    await this._write(db);
    return {created: true, membership: structuredClone(membership)};
  },

  async updateMembership({
    semyaId,
    targetUserId,
    actorUserId,
    role,
    hasInviteGrant,
  }) {
    if (!semyaId || typeof semyaId !== "string") {
      throw new Error("INVALID_SEMYA_ID");
    }
    if (!targetUserId || typeof targetUserId !== "string") {
      throw new Error("INVALID_USER_ID");
    }
    if (!actorUserId) {
      throw new Error("INVALID_ACTOR");
    }
    if (role !== undefined && !["owner", "editor", "viewer"].includes(role)) {
      throw new Error("INVALID_ROLE");
    }
    if (role === undefined && hasInviteGrant === undefined) {
      throw new Error("NO_CHANGES");
    }

    const db = await this._read();
    const semya = (db.semyi || []).find(
      (entry) => entry.id === semyaId && !entry.deletedAt,
    );
    if (!semya) {
      throw new Error("SEMYA_NOT_FOUND");
    }
    const actor = (db.semyaMembers || []).find(
      (m) =>
        m.semyaId === semyaId &&
        m.userId === actorUserId &&
        m.role === "owner" &&
        !m.hiddenAt,
    );
    if (!actor) {
      throw new Error("NOT_OWNER");
    }
    const target = (db.semyaMembers || []).find(
      (m) =>
        m.semyaId === semyaId && m.userId === targetUserId && !m.hiddenAt,
    );
    if (!target) {
      throw new Error("MEMBERSHIP_NOT_FOUND");
    }

    let mutated = false;
    if (role !== undefined && role !== target.role) {
      // Self role change blocked (ENTITY-DESIGN §2.1 «Owner → editor
      // требует ≥1 другой active owner»; self-promotion uncommon
      // case but blocked для symmetry, requires другой owner).
      if (targetUserId === actorUserId) {
        throw new Error("SELF_ROLE_CHANGE_FORBIDDEN");
      }
      // Demote owner → editor/viewer requires ≥1 другой owner remaining.
      if (target.role === "owner" && role !== "owner") {
        if (this._countActiveOwners(db, semyaId) <= 1) {
          throw new Error("LAST_OWNER_DEMOTE_FORBIDDEN");
        }
      }
      target.role = role;
      // Clear invite grant when not editor (ENTITY-DESIGN §3.4).
      if (role !== "editor") {
        target.hasInviteGrant = false;
      }
      mutated = true;
    }
    if (hasInviteGrant !== undefined) {
      const targetRole = target.role; // after possible role change
      if (targetRole !== "editor") {
        // Owner implicitly имеет invite power; viewer cannot invite.
        // Toggle nonsensical для non-editor — reject explicitly.
        throw new Error("INVITE_GRANT_ONLY_EDITOR");
      }
      const next = !!hasInviteGrant;
      if (target.hasInviteGrant !== next) {
        target.hasInviteGrant = next;
        mutated = true;
      }
    }

    if (mutated) {
      semya.updatedAt = nowIso();
      await this._write(db);
    }
    return structuredClone(target);
  },

  async removeMembership({semyaId, targetUserId, actorUserId}) {
    if (!semyaId || typeof semyaId !== "string") {
      throw new Error("INVALID_SEMYA_ID");
    }
    if (!targetUserId || typeof targetUserId !== "string") {
      throw new Error("INVALID_USER_ID");
    }
    if (!actorUserId) {
      throw new Error("INVALID_ACTOR");
    }

    const db = await this._read();
    const semya = (db.semyi || []).find(
      (entry) => entry.id === semyaId && !entry.deletedAt,
    );
    if (!semya) {
      throw new Error("SEMYA_NOT_FOUND");
    }
    const target = (db.semyaMembers || []).find(
      (m) =>
        m.semyaId === semyaId && m.userId === targetUserId && !m.hiddenAt,
    );
    if (!target) {
      throw new Error("MEMBERSHIP_NOT_FOUND");
    }
    const actorIsSelf = targetUserId === actorUserId;
    if (!actorIsSelf) {
      // Kick others — owner only.
      const actor = (db.semyaMembers || []).find(
        (m) =>
          m.semyaId === semyaId &&
          m.userId === actorUserId &&
          m.role === "owner" &&
          !m.hiddenAt,
      );
      if (!actor) {
        throw new Error("NOT_OWNER");
      }
    }
    // At-least-one-owner invariant. Both kick + self-leave paths check.
    if (target.role === "owner" && this._countActiveOwners(db, semyaId) <= 1) {
      throw new Error("LAST_OWNER_REMOVE_FORBIDDEN");
    }

    const removedAt = nowIso();
    target.hiddenAt = removedAt;
    semya.updatedAt = removedAt;
    // Phase B Ship 5: dual-write cleanup tree.memberIds[] так чтобы
    // legacy tree-routes (pre-Phase-B path) тоже видели removal.
    // NB: tree.creatorId preserved — никогда не «kick'аем» creator
    // из legacy field, иначе tree-routes гасят весь access. После
    // semya.deletedAt (Q4 orphan policy) tree becomes inaccessible
    // через семья model только.
    const tree = (db.trees || []).find((t) => t.id === semya.treeId);
    if (tree && targetUserId !== tree.creatorId) {
      if (Array.isArray(tree.memberIds)) {
        tree.memberIds = tree.memberIds.filter((id) => id !== targetUserId);
      }
      if (Array.isArray(tree.members)) {
        tree.members = tree.members.filter((id) => id !== targetUserId);
      }
    }
    await this._write(db);
    return {membership: structuredClone(target), wasSelfLeave: actorIsSelf};
  },

  async createInvitation({
    semyaId,
    inviterUserId,
    recipientUserId = null,
    recipientEmail = null,
    recipientPhone = null,
    personId = null,
    role,
    expiresInDays = 30,
  }) {
    if (!semyaId || typeof semyaId !== "string") {
      throw new Error("INVALID_SEMYA_ID");
    }
    if (!inviterUserId) {
      throw new Error("INVALID_INVITER");
    }
    if (role !== "editor" && role !== "viewer") {
      throw new Error("INVALID_ROLE");
    }
    const normalizedPersonId =
      personId && typeof personId === "string" ? personId.trim() : null;
    const hasRecipient =
      (recipientUserId && typeof recipientUserId === "string") ||
      (recipientEmail && typeof recipientEmail === "string") ||
      (recipientPhone && typeof recipientPhone === "string") ||
      Boolean(normalizedPersonId);
    if (!hasRecipient) {
      throw new Error("MISSING_RECIPIENT");
    }

    const db = await this._read();
    const semya = (db.semyi || []).find(
      (entry) => entry.id === semyaId && !entry.deletedAt,
    );
    if (!semya) {
      throw new Error("SEMYA_NOT_FOUND");
    }
    // Validate personId if provided — must belong to bound tree, be alive,
    // and not already linked to a different user.
    if (normalizedPersonId) {
      const targetPerson = (db.persons || []).find(
        (p) => p.id === normalizedPersonId && p.treeId === semya.treeId,
      );
      if (!targetPerson) {
        throw new Error("PERSON_NOT_FOUND");
      }
      if (
        targetPerson.isAlive === false ||
        Boolean(targetPerson.deathDate && String(targetPerson.deathDate).trim())
      ) {
        throw new Error("PERSON_DECEASED");
      }
      if (
        targetPerson.userId &&
        (!recipientUserId || targetPerson.userId !== recipientUserId)
      ) {
        throw new Error("PERSON_ALREADY_CLAIMED");
      }
    }
    // Validate recipientUserId if provided.
    if (recipientUserId) {
      const recipient = (db.users || []).find((u) => u.id === recipientUserId);
      if (!recipient) {
        throw new Error("RECIPIENT_NOT_FOUND");
      }
      // Если recipient already member → no point creating invitation.
      const existingMembership = (db.semyaMembers || []).find(
        (m) =>
          m.semyaId === semyaId &&
          m.userId === recipientUserId &&
          !m.hiddenAt,
      );
      if (existingMembership) {
        throw new Error("ALREADY_MEMBER");
      }
    }

    // Lazy-expire previous invitations for этого семья перед
    // duplicate-check (так stale pending не блокирует resend).
    this._lazyExpireInvitations(db, semyaId);

    // Idempotent re-create — if existing pending invitation для same
    // (semyaId, recipient / personId) → return it.
    let existing = null;
    if (recipientUserId) {
      existing = (db.semyaInvitations || []).find(
        (inv) =>
          inv.semyaId === semyaId &&
          inv.recipientUserId === recipientUserId &&
          (inv.personId || null) === normalizedPersonId &&
          inv.status === "pending",
      );
    } else if (recipientEmail) {
      const targetEmail = recipientEmail.toLowerCase().trim();
      existing = (db.semyaInvitations || []).find(
        (inv) =>
          inv.semyaId === semyaId &&
          (inv.recipientEmail || "").toLowerCase() === targetEmail &&
          (inv.personId || null) === normalizedPersonId &&
          inv.status === "pending",
      );
    } else if (recipientPhone) {
      const targetPhone = recipientPhone.replace(/\s+/g, "");
      existing = (db.semyaInvitations || []).find(
        (inv) =>
          inv.semyaId === semyaId &&
          (inv.recipientPhone || "").replace(/\s+/g, "") === targetPhone &&
          (inv.personId || null) === normalizedPersonId &&
          inv.status === "pending",
      );
    } else if (normalizedPersonId) {
      existing = (db.semyaInvitations || []).find(
        (inv) =>
          inv.semyaId === semyaId &&
          inv.personId === normalizedPersonId &&
          !inv.recipientUserId &&
          !inv.recipientEmail &&
          !inv.recipientPhone &&
          inv.status === "pending",
      );
    }
    if (existing) {
      return {created: false, invitation: structuredClone(existing)};
    }

    const createdAt = nowIso();
    const expiresAt = new Date(
      Date.now() + Math.max(1, expiresInDays) * 24 * 60 * 60 * 1000,
    ).toISOString();
    const invitation = {
      id: crypto.randomUUID(),
      // Token = uuid (32-char URL-safe). Sufficient entropy для
      // shareable link capability. Treat как Bearer secret.
      token: crypto.randomUUID() + crypto.randomUUID().replace(/-/g, ""),
      semyaId,
      inviterUserId,
      recipientUserId: recipientUserId || null,
      recipientEmail: recipientEmail
        ? String(recipientEmail).toLowerCase().trim()
        : null,
      recipientPhone: recipientPhone
        ? String(recipientPhone).trim()
        : null,
      personId: normalizedPersonId,
      role,
      createdAt,
      expiresAt,
      status: "pending",
      acceptedAt: null,
      declinedAt: null,
      declinedByUserId: null,
      revokedAt: null,
      revokedByUserId: null,
      expiredAt: null,
    };
    db.semyaInvitations.push(invitation);
    await this._write(db);
    return {created: true, invitation: structuredClone(invitation)};
  },

  async getInvitationPreview(token) {
    if (!token || typeof token !== "string") {
      return null;
    }
    const db = await this._read();
    this._lazyExpireInvitations(db, null);
    const inv = (db.semyaInvitations || []).find((entry) => entry.token === token);
    if (!inv) {
      return null;
    }
    const semya = (db.semyi || []).find((s) => s.id === inv.semyaId) || null;
    const inviter =
      (db.users || []).find((u) => u.id === inv.inviterUserId) || null;
    const inviterName =
      inviter?.profile?.displayName ||
      composeDisplayNameFromProfile(inviter?.profile) ||
      null;
    let targetPersonName = null;
    if (inv.personId && semya?.treeId) {
      const person = (db.persons || []).find(
        (p) => p.id === inv.personId && p.treeId === semya.treeId,
      );
      targetPersonName = person?.name || null;
    }
    return {
      id: inv.id,
      semyaId: inv.semyaId,
      role: inv.role,
      status: inv.status,
      createdAt: inv.createdAt,
      expiresAt: inv.expiresAt,
      acceptedAt: inv.acceptedAt ?? null,
      declinedAt: inv.declinedAt ?? null,
      revokedAt: inv.revokedAt ?? null,
      expiredAt: inv.expiredAt ?? null,
      semyaName: semya?.deletedAt ? null : (semya?.name || null),
      semyaDeleted: Boolean(semya?.deletedAt || !semya),
      inviterName,
      targetPersonName,
      personId: inv.personId ?? null,
      hasRecipientUser: Boolean(inv.recipientUserId),
    };
  },

  async findInvitationByToken(token) {
    if (!token || typeof token !== "string") {
      return null;
    }
    const db = await this._read();
    this._lazyExpireInvitations(db, null);
    const found = (db.semyaInvitations || []).find((inv) => inv.token === token);
    return found ? structuredClone(found) : null;
  },

  async listInvitationsForSemya(semyaId) {
    if (!semyaId || typeof semyaId !== "string") {
      return [];
    }
    const db = await this._read();
    this._lazyExpireInvitations(db, semyaId);
    return (db.semyaInvitations || [])
      .filter((inv) => inv.semyaId === semyaId)
      .sort((a, b) =>
        String(b.createdAt || "").localeCompare(String(a.createdAt || "")),
      )
      .map((entry) => structuredClone(entry));
  },

  async acceptInvitation({token, acceptingUserId}) {
    if (!token || typeof token !== "string") {
      throw new Error("INVALID_TOKEN");
    }
    if (!acceptingUserId) {
      throw new Error("INVALID_ACTOR");
    }

    return this._mutate((db) => {
      this._lazyExpireInvitations(db, null);
      const invitation = (db.semyaInvitations || []).find(
        (inv) => inv.token === token,
      );
      if (!invitation) {
        throw new Error("INVITATION_NOT_FOUND");
      }
      if (invitation.status !== "pending") {
        throw new Error("INVITATION_NOT_PENDING");
      }
      if (
        invitation.recipientUserId &&
        invitation.recipientUserId !== acceptingUserId
      ) {
        throw new Error("WRONG_RECIPIENT");
      }

      const semya = (db.semyi || []).find(
        (entry) => entry.id === invitation.semyaId && !entry.deletedAt,
      );
      if (!semya) {
        throw new Error("SEMYA_NOT_FOUND");
      }

      const now = nowIso();
      invitation.status = "accepted";
      invitation.acceptedAt = now;

      db.semyaMembers = Array.isArray(db.semyaMembers) ? db.semyaMembers : [];
      const existingMembership = db.semyaMembers.find(
        (m) =>
          m.semyaId === invitation.semyaId &&
          m.userId === acceptingUserId,
      );
      let membership;
      if (existingMembership) {
        if (existingMembership.hiddenAt) {
          existingMembership.hiddenAt = null;
          existingMembership.role = invitation.role;
          existingMembership.joinedAt = now;
          existingMembership.invitedByUserId = invitation.inviterUserId;
          existingMembership.hasInviteGrant = false;
        }
        membership = existingMembership;
      } else {
        membership = {
          id: crypto.randomUUID(),
          semyaId: invitation.semyaId,
          userId: acceptingUserId,
          role: invitation.role,
          joinedAt: now,
          invitedByUserId: invitation.inviterUserId,
          hasInviteGrant: false,
          hiddenAt: null,
        };
        db.semyaMembers.push(membership);
      }

      const boundTree = (db.trees || []).find((t) => t.id === semya.treeId);
      if (boundTree) {
        boundTree.memberIds = Array.isArray(boundTree.memberIds)
          ? boundTree.memberIds
          : [];
        if (!boundTree.memberIds.includes(acceptingUserId)) {
          boundTree.memberIds.push(acceptingUserId);
        }
        boundTree.members = Array.isArray(boundTree.members)
          ? boundTree.members
          : [];
        if (!boundTree.members.includes(acceptingUserId)) {
          boundTree.members.push(acceptingUserId);
        }
        boundTree.updatedAt = now;
      }

      semya.updatedAt = now;
      return {
        invitation: structuredClone(invitation),
        membership: structuredClone(membership),
      };
    });
  },

  async declineInvitation({token, actingUserId}) {
    if (!token || typeof token !== "string") {
      throw new Error("INVALID_TOKEN");
    }
    if (!actingUserId) {
      throw new Error("INVALID_ACTOR");
    }

    return this._mutate((db) => {
      this._lazyExpireInvitations(db, null);
      const invitation = (db.semyaInvitations || []).find(
        (inv) => inv.token === token,
      );
      if (!invitation) {
        throw new Error("INVITATION_NOT_FOUND");
      }
      if (invitation.status !== "pending") {
        throw new Error("INVITATION_NOT_PENDING");
      }
      if (
        invitation.recipientUserId &&
        invitation.recipientUserId !== actingUserId
      ) {
        throw new Error("WRONG_RECIPIENT");
      }
      const now = nowIso();
      invitation.status = "declined";
      invitation.declinedAt = now;
      invitation.declinedByUserId = actingUserId;
      return structuredClone(invitation);
    });
  },

  async revokeInvitation({invitationId, actingUserId, semyaId = null}) {
    if (!invitationId || typeof invitationId !== "string") {
      throw new Error("INVALID_INVITATION_ID");
    }
    if (!actingUserId) {
      throw new Error("INVALID_ACTOR");
    }

    const db = await this._read();
    const invitation = (db.semyaInvitations || []).find(
      (inv) => inv.id === invitationId,
    );
    if (!invitation || (semyaId && invitation.semyaId !== semyaId)) {
      throw new Error("INVITATION_NOT_FOUND");
    }
    // Per Ship 4 spec: revoker = inviter либо semya owner.
    const isInviter = invitation.inviterUserId === actingUserId;
    let isOwner = false;
    if (!isInviter) {
      isOwner = !!(db.semyaMembers || []).find(
        (m) =>
          m.semyaId === invitation.semyaId &&
          m.userId === actingUserId &&
          m.role === "owner" &&
          !m.hiddenAt,
      );
    }
    if (!isInviter && !isOwner) {
      throw new Error("NOT_INVITER_OR_OWNER");
    }
    if (invitation.status !== "pending") {
      throw new Error("INVITATION_NOT_PENDING");
    }

    const now = nowIso();
    invitation.status = "revoked";
    invitation.revokedAt = now;
    invitation.revokedByUserId = actingUserId;

    await this._write(db);
    return structuredClone(invitation);
  },

  async createBrowseToken({semyaId, createdByUserId, expiresInDays = 30}) {
    if (!semyaId || typeof semyaId !== "string") {
      throw new Error("INVALID_SEMYA_ID");
    }
    if (!createdByUserId) {
      throw new Error("INVALID_ACTOR");
    }

    const db = await this._read();
    const semya = (db.semyi || []).find(
      (entry) => entry.id === semyaId && !entry.deletedAt,
    );
    if (!semya) {
      throw new Error("SEMYA_NOT_FOUND");
    }

    const createdAt = nowIso();
    const expiresAt = new Date(
      Date.now() + Math.max(1, expiresInDays) * 24 * 60 * 60 * 1000,
    ).toISOString();
    const token = {
      id: crypto.randomUUID(),
      // Capability secret — same 2× uuid construction как invitation
      // tokens. Logging plaintext запрещено (see semya-browse-routes
      // comment).
      token: crypto.randomUUID() + crypto.randomUUID().replace(/-/g, ""),
      semyaId,
      createdByUserId,
      createdAt,
      expiresAt,
      revokedAt: null,
      lastUsedAt: null,
    };
    db.semyaBrowseTokens.push(token);
    await this._write(db);
    return structuredClone(token);
  },

  async findBrowseTokenByValue(tokenValue) {
    if (!tokenValue || typeof tokenValue !== "string") {
      return null;
    }
    const db = await this._read();
    const found = (db.semyaBrowseTokens || []).find(
      (t) => t.token === tokenValue,
    );
    return found ? structuredClone(found) : null;
  },

  async findBrowseTokenById(tokenId) {
    if (!tokenId || typeof tokenId !== "string") {
      return null;
    }
    const db = await this._read();
    const found = (db.semyaBrowseTokens || []).find((t) => t.id === tokenId);
    return found ? structuredClone(found) : null;
  },

  async listBrowseTokensForSemya(semyaId) {
    if (!semyaId || typeof semyaId !== "string") {
      return [];
    }
    const db = await this._read();
    return (db.semyaBrowseTokens || [])
      .filter((t) => t.semyaId === semyaId)
      .sort((a, b) =>
        String(b.createdAt || "").localeCompare(String(a.createdAt || "")),
      )
      .map((t) => structuredClone(t));
  },

  // Touches lastUsedAt (best-effort analytics — does NOT throw).
  // Called from GET /v1/browse/:token on resolve.
  async touchBrowseTokenLastUsed(tokenId) {
    if (!tokenId) return;
    try {
      const db = await this._read();
      const found = (db.semyaBrowseTokens || []).find((t) => t.id === tokenId);
      if (!found) return;
      found.lastUsedAt = nowIso();
      await this._write(db);
    } catch (_) {
      // best-effort
    }
  },

  async revokeBrowseToken({tokenId, actingUserId, semyaId = null}) {
    if (!tokenId || typeof tokenId !== "string") {
      throw new Error("INVALID_TOKEN_ID");
    }
    if (!actingUserId) {
      throw new Error("INVALID_ACTOR");
    }

    const db = await this._read();
    const token = (db.semyaBrowseTokens || []).find((t) => t.id === tokenId);
    if (!token || (semyaId && token.semyaId !== semyaId)) {
      throw new Error("TOKEN_NOT_FOUND");
    }
    if (token.revokedAt) {
      throw new Error("TOKEN_ALREADY_REVOKED");
    }
    // Revoker = token creator либо семья owner (per Артёма spec).
    const isCreator = token.createdByUserId === actingUserId;
    let isOwner = false;
    if (!isCreator) {
      isOwner = !!(db.semyaMembers || []).find(
        (m) =>
          m.semyaId === token.semyaId &&
          m.userId === actingUserId &&
          m.role === "owner" &&
          !m.hiddenAt,
      );
    }
    if (!isCreator && !isOwner) {
      throw new Error("NOT_CREATOR_OR_OWNER");
    }

    token.revokedAt = nowIso();
    await this._write(db);
    return structuredClone(token);
  },

  async addHidePerson({semyaId, userId, personId}) {
    if (!semyaId || typeof semyaId !== "string") {
      throw new Error("INVALID_SEMYA_ID");
    }
    if (!userId || typeof userId !== "string") {
      throw new Error("INVALID_USER_ID");
    }
    if (!personId || typeof personId !== "string") {
      throw new Error("INVALID_PERSON_ID");
    }

    const db = await this._read();
    // Idempotent: existing row → no-op (composite-key unique).
    const existing = (db.semyaMemberHiddenPersons || []).find(
      (h) =>
        h.semyaId === semyaId &&
        h.userId === userId &&
        h.personId === personId,
    );
    if (existing) {
      return {created: false, hide: structuredClone(existing)};
    }
    const hide = {
      semyaId,
      userId,
      personId,
      hiddenAt: nowIso(),
    };
    db.semyaMemberHiddenPersons.push(hide);
    await this._write(db);
    return {created: true, hide: structuredClone(hide)};
  },

  async removeHidePerson({semyaId, userId, personId}) {
    if (!semyaId || typeof semyaId !== "string") {
      throw new Error("INVALID_SEMYA_ID");
    }
    if (!userId || typeof userId !== "string") {
      throw new Error("INVALID_USER_ID");
    }
    if (!personId || typeof personId !== "string") {
      throw new Error("INVALID_PERSON_ID");
    }

    const db = await this._read();
    const before = (db.semyaMemberHiddenPersons || []).length;
    db.semyaMemberHiddenPersons = (db.semyaMemberHiddenPersons || []).filter(
      (h) =>
        !(
          h.semyaId === semyaId &&
          h.userId === userId &&
          h.personId === personId
        ),
    );
    const removed = db.semyaMemberHiddenPersons.length < before;
    if (removed) {
      await this._write(db);
    }
    return {removed};
  },

  // Soft-delete семья per ENTITY-DESIGN §1.1 lifecycle + Q4 orphan
  // policy. Sets `deletedAt` and hides все memberships (their listings
  // exclude). Persons + relations preserved (orphan), identity links
  // preserve через personIdentities (twin persons в других семей
  // continue работать). Hard-delete background job extends Phase 3.6
  // pattern (90d window — Q5 answer).
  // Notification dispatch к members — async, deferred к Week 3 broadcast
  // scope work (Ship 2 строго CRUD).
  async softDeleteSemya({semyaId, actorUserId}) {
    if (!semyaId || typeof semyaId !== "string") {
      throw new Error("INVALID_SEMYA_ID");
    }
    if (!actorUserId) {
      throw new Error("INVALID_ACTOR");
    }

    const db = await this._read();
    const semya = (db.semyi || []).find(
      (entry) => entry.id === semyaId && !entry.deletedAt,
    );
    if (!semya) {
      throw new Error("SEMYA_NOT_FOUND");
    }
    const actorMembership = (db.semyaMembers || []).find(
      (m) =>
        m.semyaId === semyaId &&
        m.userId === actorUserId &&
        m.role === "owner" &&
        !m.hiddenAt,
    );
    if (!actorMembership) {
      throw new Error("NOT_OWNER");
    }

    const deletedAt = nowIso();
    const retentionDays = Number(process.env.RODNYA_SEMYA_RETENTION_DAYS) || 90;
    semya.deletedAt = deletedAt;
    semya.deletedByUserId = actorUserId;
    semya.hardDeleteScheduledAt = new Date(
      Date.parse(deletedAt) + retentionDays * 86_400_000,
    ).toISOString();
    semya.updatedAt = deletedAt;

    // Memberships hidden — listSemyiForUser + findMembership exclude
    // hidden rows, поэтому members перестают видеть семья в их list.
    // Membership records preserved (audit trail).
    for (const m of db.semyaMembers || []) {
      if (m.semyaId === semyaId && !m.hiddenAt) {
        m.hiddenAt = deletedAt;
      }
    }

    await this._write(db);
    return structuredClone(semya);
  },

  async restoreSemya({semyaId, actorUserId}) {
    if (!semyaId || typeof semyaId !== "string") {
      throw new Error("INVALID_SEMYA_ID");
    }
    if (!actorUserId) {
      throw new Error("INVALID_ACTOR");
    }

    const db = await this._read();
    const semya = (db.semyi || []).find((entry) => entry.id === semyaId);
    if (!semya) {
      throw new Error("SEMYA_NOT_FOUND");
    }
    if (!semya.deletedAt) {
      throw new Error("SEMYA_NOT_DELETED");
    }

    const retentionDays = Number(process.env.RODNYA_SEMYA_RETENTION_DAYS) || 90;
    const scheduledMs = semya.hardDeleteScheduledAt
      ? Date.parse(semya.hardDeleteScheduledAt)
      : Date.parse(semya.deletedAt) + retentionDays * 86_400_000;
    if (Number.isFinite(scheduledMs) && Date.now() > scheduledMs) {
      throw new Error("RETENTION_EXPIRED");
    }

    const originalDeletedAt = semya.deletedAt;
    const hasMemberships = (db.semyaMembers || []).some(
      (m) => m.semyaId === semyaId,
    );
    const isOwner = hasMemberships
      ? (db.semyaMembers || []).some(
          (m) =>
            m.semyaId === semyaId &&
            m.userId === actorUserId &&
            m.role === "owner" &&
            m.hiddenAt === originalDeletedAt,
        )
      : semya.ownerId === actorUserId;
    if (!isOwner) {
      throw new Error("NOT_OWNER");
    }

    const restoredAt = nowIso();
    semya.deletedAt = null;
    semya.deletedByUserId = null;
    semya.hardDeleteScheduledAt = null;
    semya.updatedAt = restoredAt;

    for (const m of db.semyaMembers || []) {
      if (m.semyaId === semyaId && m.hiddenAt === originalDeletedAt) {
        m.hiddenAt = null;
      }
    }

    await this._write(db);
    return structuredClone(semya);
  },

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
    this._ensureSemyaMembershipForLegacyJoin(db, tree, userId);

    if (changed) {
      tree.updatedAt = nowIso();
    await this._write(db);
    this._forgetUser(userId);
    for (const entry of db.sessions) {
      if (entry.userId === userId) {
        this._forgetSession(entry.token);
      }
    }
  }

    return structuredClone(tree);
  },

  /// Ship Q4a: list deleted persons in specific семя. Permission —
  /// caller must be active member.
  async listDeletedPersonsForSemya({semyaId, userId}) {
    if (!semyaId || typeof semyaId !== "string") return [];
    if (!userId) return [];
    const db = await this._read();
    const isMember = (db.semyaMembers || []).some(
      (m) => m.userId === userId && m.semyaId === semyaId && !m.hiddenAt,
    );
    if (!isMember) {
      throw new Error("NOT_MEMBER");
    }
    return (db.deletedPersons || [])
      .filter((entry) => entry.semyaId === semyaId && !entry.restoredAt)
      .sort((a, b) =>
        String(b.deletedAt || "").localeCompare(String(a.deletedAt || "")),
      )
      .map((entry) => structuredClone(entry));
  },
};
