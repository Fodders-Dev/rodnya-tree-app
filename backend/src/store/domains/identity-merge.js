const fs = require("node:fs/promises");
const path = require("node:path");
const crypto = require("node:crypto");
const {
  findCrossTreeIdentitySuggestions,
  normalizedBirthYear,
} = require("../../identity-matcher");
const {
  backfillPersonIdentities,
} = require("../../migration-utils");
const {
  PERSON_ATTRIBUTE_FIELDS,
} = require("../constants");
const {
  cloneUserWithAuthState,
  composeDisplayNameFromProfile,
  createPersonIdentityRecord,
  dbHasPersonsWithoutIdentity,
  defaultPersonVisibility,
  deriveProviderIdsForUser,
  ensureAutoCirclesForTree,
  extractBirthYear,
  identityStewardUserIds,
  listAuthIdentitiesForUser,
  normalizeAuthIdentityRecord,
  normalizeAuthProvider,
  normalizeIsoDate,
  normalizeNullableString,
  normalizeParticipantIds,
  normalizePersonPhotoGallery,
  normalizePersonVisibility,
  normalizePrimaryTrustedChannel,
  nowIso,
  personStewardUserIds,
  pickPersonValue,
  relationDedupKey,
  safeMergePersonPreview,
  sameNormalizedIds,
  upsertPersonAttributesForPerson,
} = require("../helpers");

module.exports = {
  _ensurePersonIdentityCollection(db) {
    db.personIdentities = Array.isArray(db.personIdentities)
      ? db.personIdentities
      : [];
    return db.personIdentities;
  },

  // SPEED-14: backfillPersonIdentities hashes EVERY persons+personIdentities
  // record in the ENTIRE db twice (stableSerialize+sha256, before/after —
  // see its own comment in migration-utils.js) just to detect whether it
  // changed anything. On a write-path call (createPerson/deletePerson/
  // linkPersonToUser/... — 19 callers of this method across store.js) that
  // runs on EVERY person mutation, even though in steady state (prod: all
  // persons already carry an identityId) it is a guaranteed no-op — the
  // exact pattern SPEED-8c/13 already gated the same way for
  // ensureAutoCirclesForTree / the merge-proposals materialize path. Gating
  // ONLY this inner call (not the whole method) is the safe cut: the loop
  // below — which syncs db.personIdentities[].personIds/steward/isLiving
  // from db.persons, the thing callers actually rely on after a mutation —
  // still runs unconditionally every time, so no caller loses the sync it
  // depends on. See docs/speed_measurement.md SPEED-14 for the profile that
  // found this (~16% self-time on a synthetic write-path benchmark) and the
  // audit of why skipping backfillPersonIdentities alone cannot desync
  // personIds (it only ever CREATES an identity for a person that has none;
  // dbHasPersonsWithoutIdentity(db) is exactly "does such a person exist").
  _reconcilePersonIdentities(db) {
    if (dbHasPersonsWithoutIdentity(db)) {
      backfillPersonIdentities(db);
    }
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
      const claimedByUserId = normalizeNullableString(
        entry?.claimedByUserId || normalizedUserId,
      );
      const linkedPersons = personIds
        .map((personId) => db.persons.find((person) => person.id === personId))
        .filter(Boolean);
      const hasLivingPerson = linkedPersons.some(
        (person) => person.isAlive !== false,
      );

      if (!normalizedUserId && !claimedByUserId && personIds.length === 0) {
        return result;
      }

      const nextIdentity = {
        ...entry,
        id: identityId,
        userId: normalizedUserId || claimedByUserId,
        claimedByUserId,
        primaryPersonId:
          normalizeNullableString(entry?.primaryPersonId) || personIds[0] || null,
        personIds,
        isLiving:
          entry?.isLiving === undefined ? hasLivingPerson : entry.isLiving === true,
        isPublicDiscoverable: entry?.isPublicDiscoverable === true,
        mergedInto: normalizeNullableString(entry?.mergedInto),
        stewardUserIds: [],
        createdAt: entry?.createdAt || nowIso(),
        updatedAt: entry?.updatedAt || nowIso(),
      };
      nextIdentity.stewardUserIds = identityStewardUserIds(db, nextIdentity);
      result.push({
        ...nextIdentity,
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
      const currentIdentityValue = user.identityId;
      if (
        normalizedIdentityId &&
        db.personIdentities.some(
          (entry) =>
            entry.id === normalizedIdentityId && entry.userId === user.id,
        )
      ) {
        if (currentIdentityValue !== normalizedIdentityId) {
          user.identityId = normalizedIdentityId;
        }
        continue;
      }

      if (ownedIdentityId) {
        if (currentIdentityValue !== ownedIdentityId) {
          user.identityId = ownedIdentityId;
        }
        continue;
      }

      if (normalizedIdentityId !== null) {
        user.identityId = null;
      }
    }

    // BUG3 follow-up: ретро-бэкфилл аватара профиля для УЖЕ-привязанных
    // аккаунтов из фото связанной граф-персоны (поставленного ДО
    // регистрации). Идём здесь, после реконсиляции связей, чтобы линки
    // были актуальны. Покрывает и существующие связи (Анастасия и пр.).
    this._backfillUserAvatarsFromPersons(db);
  },

  // Заполняет пустой profile.photoUrl фотом связанной граф-персоны.
  // fillIfEmpty — загруженный пользователем аватар НЕ перетираем.
  // Идемпотентно (трогает только пустые). Связь резолвится и напрямую
  // (person.userId), и через identity (claimedByUserId/userId). Один проход
  // O(persons + identities + users).
  _backfillUserAvatarsFromPersons(db) {
    const persons = Array.isArray(db.persons) ? db.persons : [];
    if (persons.length === 0 || !Array.isArray(db.users)) {
      return;
    }
    const personPhoto = (person) =>
      normalizeNullableString(person?.primaryPhotoUrl || person?.photoUrl);

    const photoByUserId = new Map();
    const photoByIdentityId = new Map();
    for (const person of persons) {
      const photo = personPhoto(person);
      if (!photo) {
        continue;
      }
      const directUserId = normalizeNullableString(person.userId);
      if (directUserId && !photoByUserId.has(directUserId)) {
        photoByUserId.set(directUserId, photo);
      }
      const identityId = normalizeNullableString(person.identityId);
      if (identityId && !photoByIdentityId.has(identityId)) {
        photoByIdentityId.set(identityId, photo);
      }
    }

    const photoByLinkedUserViaIdentity = new Map();
    for (const identity of Array.isArray(db.personIdentities)
      ? db.personIdentities
      : []) {
      const linkedUserId = normalizeNullableString(
        identity?.claimedByUserId || identity?.userId,
      );
      const photo = photoByIdentityId.get(normalizeNullableString(identity?.id));
      if (linkedUserId && photo && !photoByLinkedUserViaIdentity.has(linkedUserId)) {
        photoByLinkedUserViaIdentity.set(linkedUserId, photo);
      }
    }

    for (const user of db.users) {
      if (!user) {
        continue;
      }
      if (!user.profile) {
        user.profile = {};
      }
      if (normalizeNullableString(user.profile.photoUrl)) {
        continue; // существующий аватар не перетираем
      }
      const photo =
        photoByUserId.get(user.id) ||
        photoByLinkedUserViaIdentity.get(user.id) ||
        null;
      if (photo) {
        user.profile.photoUrl = photo;
      }
    }
  },

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
    identity.claimedByUserId = normalizeNullableString(
      identity.claimedByUserId || userId,
    );
    identity.updatedAt = nowIso();
    user.identityId = identity.id;
    user.updatedAt = nowIso();
    return identity;
  },

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
        // BUG 3: при привязке аккаунта к граф-персоне бэкфиллим пустой
        // аватар профиля из фото персоны (поставленного ДО регистрации).
        // fillIfEmpty — существующий аватар НЕ перетираем. Это единая
        // точка всех путей линковки (claim-approve / join / auto-link).
        if (!user.profile) {
          user.profile = {};
        }
        const personPhoto = normalizeNullableString(
          person.primaryPhotoUrl || person.photoUrl,
        );
        if (personPhoto && !normalizeNullableString(user.profile.photoUrl)) {
          user.profile.photoUrl = personPhoto;
        }
      }
    }

    person.identityId = identity.id;
    person.updatedAt = nowIso();
    identity.updatedAt = nowIso();
    this._reconcilePersonIdentities(db);
    return true;
  },

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

    for (const sr of db.storyRequests || []) {
      if (sr.treeId === treeId && sr.personId === duplicatePerson.id) {
        sr.personId = preferredPerson.id;
      }
    }
    for (const cm of db.circleMembers || []) {
      if (cm.treeId === treeId && cm.personId === duplicatePerson.id) {
        cm.personId = preferredPerson.id;
      }
    }
    for (const dp of db.deletedPersons || []) {
      if (dp.treeId === treeId && dp.originalPersonId === duplicatePerson.id) {
        dp.originalPersonId = preferredPerson.id;
      }
    }

    this._rewriteTreeChangeRecordsForMerge(db, {
      treeId,
      duplicatePersonId: duplicatePerson.id,
      preferredPersonId: preferredPerson.id,
    });

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
  },

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
    if (user) {
      this._rememberUser(user);
    }
    return user ? cloneUserWithAuthState(user) : null;
  },

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
    this._rememberUser(user);
    return cloneUserWithAuthState(user);
  },

  async unlinkAuthIdentity(userId, provider) {
    const normalizedProvider = normalizeAuthProvider(provider);
    if (
      !normalizedProvider ||
      normalizedProvider === "password" ||
      !["google", "telegram", "vk", "max"].includes(normalizedProvider)
    ) {
      return {error: "INVALID_PROVIDER"};
    }

    let rememberedUser = null;
    const result = await this._mutate((db, skip) => {
      const user = db.users.find((entry) => entry.id === userId);
      if (!user) {
        return skip({error: "USER_NOT_FOUND"});
      }

      const identities = listAuthIdentitiesForUser(user);
      const isLinkedInIdentities = identities.some(
        (identity) => identity.provider === normalizedProvider,
      );
      const existingProviderIds = Array.isArray(user.providerIds)
        ? user.providerIds.map((item) => normalizeAuthProvider(item)).filter(Boolean)
        : [];
      if (!isLinkedInIdentities && !existingProviderIds.includes(normalizedProvider)) {
        return skip({error: "PROVIDER_NOT_LINKED"});
      }

      const hasPassword = Boolean(user.passwordHash && user.passwordSalt);
      const remainingOAuthIdentities = identities.filter(
        (identity) =>
          identity.provider !== "password" &&
          identity.provider !== normalizedProvider,
      );
      const remainingOAuthIds = Array.from(
        new Set([
          ...remainingOAuthIdentities.map((identity) => identity.provider),
          ...existingProviderIds.filter(
            (item) => item !== "password" && item !== normalizedProvider,
          ),
        ]),
      );
      if (!hasPassword && remainingOAuthIds.length === 0) {
        return skip({error: "LAST_LOGIN_METHOD"});
      }

      user.authIdentities = identities.filter(
        (identity) => identity.provider !== normalizedProvider,
      );
      // Reset providerIds before deriveProviderIdsForUser to avoid keeping
      // the removed provider via the legacy union inside deriveProviderIdsForUser.
      user.providerIds = [];
      user.providerIds = deriveProviderIdsForUser(user);

      const currentPrimary = normalizePrimaryTrustedChannel(
        user.profile?.primaryTrustedChannel,
      );
      if (currentPrimary === normalizedProvider) {
        user.profile = {
          ...user.profile,
          primaryTrustedChannel:
            normalizePrimaryTrustedChannel(remainingOAuthIds[0]) || null,
        };
      }
      user.updatedAt = nowIso();
      rememberedUser = user;
      return {
        provider: normalizedProvider,
        providerIds: [...user.providerIds],
        linkedProviderIds: user.authIdentities
          .filter((entry) => entry.provider !== "password")
          .map((entry) => entry.provider),
        primaryTrustedChannel: user.profile?.primaryTrustedChannel || null,
      };
    });

    if (rememberedUser && !result?.error) {
      this._rememberUser(rememberedUser);
    }
    return result;
  },

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
      // Ship Bug B (2026-05-26): block silent cross-provider merge.
      // Pre-fix: any email match triggered linkAuthIdentity → Bob's
      // Google would silently link к Alice's account because
      // emails matched. Account-takeover risk если email reused.
      //
      // Post-fix: refuse merge — return `email_provider_mismatch`
      // reason без user object. Route layer translates to 409 с
      // existing provider list так что user может log in via their
      // actual existing provider (then add new one через authenticated
      // /v1/auth/{provider}/link endpoint).
      //
      // Note: behavior strictly safer than Q2 spec literal — even
      // when the new attempt's provider TYPE matches an existing
      // identity (different providerUserId), мы refuse because the
      // exact provider+sub combo не matched в `findUserByAuthIdentity`
      // above. Scenario: Alice has google linked with alice-sub;
      // Bob attempts google login с different sub but same email —
      // we refuse merge (audit-aligned).
      const identities = listAuthIdentitiesForUser(emailMatchedUser);
      const existingProviders = Array.from(
        new Set(identities.map((entry) => entry.provider)),
      );
      return {
        reason: "email_provider_mismatch",
        user: null,
        existingProviders,
        email: emailMatchedUser.email || null,
      };
    }

    return {
      reason: "new_account",
      user: null,
    };
  },

  _userCanAccessTreeRecord(tree, userId, db = null) {
    const normalizedUserId = normalizeNullableString(userId);
    if (!tree || !normalizedUserId) {
      return false;
    }
    const useSemyaModel =
      String(process.env.RODNYA_FEDERATED_SEMYI_ENABLED || "")
        .trim()
        .toLowerCase() === "true";
    if (useSemyaModel && tree.semyaId && db) {
      const semya = (db.semyi || []).find((entry) => entry.id === tree.semyaId);
      if (semya) {
        if (semya.deletedAt) {
          return false;
        }
        return (db.semyaMembers || []).some(
          (m) =>
            m.semyaId === semya.id &&
            m.userId === normalizedUserId &&
            !m.hiddenAt,
        );
      }
    }
    const memberIds = Array.isArray(tree.memberIds) ? tree.memberIds : [];
    const members = Array.isArray(tree.members) ? tree.members : [];
    return (
      tree.creatorId === normalizedUserId ||
      memberIds.includes(normalizedUserId) ||
      members.includes(normalizedUserId)
    );
  },

  _isPersonSteward(db, person, userId) {
    return personStewardUserIds(db, person).includes(userId);
  },

  async findCrossTreeSuggestionsForPerson({
    userId,
    treeId,
    personId,
    limit = 10,
    // SPEED-8d: route-хендлер identity-suggestions ниже по коду сам
    // вызывает filterLegacyPersonsByGraphVisibility на результате —
    // без этого параметра обе функции читали бы блоб независимо
    // (2 полных _read() на один HTTP-запрос; на PostgresStore это
    // structuredClone всего состояния + версия/сессии round-trip
    // ДВАЖДЫ). Caller передаёт уже прочитанный db, чтобы _read()
    // на запрос был один.
    db: prefetchedDb = null,
  }) {
    const db = prefetchedDb || (await this._read());
    const normalizedUserId = normalizeNullableString(userId);
    if (!normalizedUserId) return [];

    const sourcePerson = db.persons.find(
      (entry) => entry.id === personId && entry.treeId === treeId,
    );
    if (!sourcePerson) return [];

    const accessibleTrees = db.trees.filter((tree) =>
      this._userCanAccessTreeRecord(tree, normalizedUserId, db),
    );
    if (accessibleTrees.length <= 1) {
      // Only one accessible tree → nothing cross-tree to suggest.
      return [];
    }

    // Build the per-user dismissal set for this source person.
    const dismissedTargetPersonIds = new Set(
      (db.dismissedIdentitySuggestions || [])
        .filter(
          (entry) =>
            entry.userId === normalizedUserId &&
            entry.sourcePersonId === personId,
        )
        .map((entry) => entry.dismissedTargetPersonId),
    );

    return findCrossTreeIdentitySuggestions({
      sourcePerson,
      accessibleTrees,
      persons: db.persons,
      dismissedTargetPersonIds,
      limit,
    });
  },

  async dismissIdentitySuggestion({
    userId,
    sourcePersonId,
    dismissedTargetPersonId,
  }) {
    const db = await this._read();
    const normalizedUserId = normalizeNullableString(userId);
    const normalizedSource = normalizeNullableString(sourcePersonId);
    const normalizedTarget = normalizeNullableString(dismissedTargetPersonId);
    if (!normalizedUserId || !normalizedSource || !normalizedTarget) {
      return false;
    }
    db.dismissedIdentitySuggestions = Array.isArray(
      db.dismissedIdentitySuggestions,
    )
      ? db.dismissedIdentitySuggestions
      : [];
    // Idempotent: don't pile up duplicate dismissal records.
    const exists = db.dismissedIdentitySuggestions.some(
      (entry) =>
        entry.userId === normalizedUserId &&
        entry.sourcePersonId === normalizedSource &&
        entry.dismissedTargetPersonId === normalizedTarget,
    );
    if (exists) return true;
    db.dismissedIdentitySuggestions.push({
      userId: normalizedUserId,
      sourcePersonId: normalizedSource,
      dismissedTargetPersonId: normalizedTarget,
      dismissedAt: nowIso(),
    });
    await this._write(db);
    return true;
  },

  // Manually link two persons under one PersonIdentity. Used when
  // the user confirms a 💡-surfaced suggestion. Idempotent: if both
  // already share an identity, no-op; if one has identity and the
  // other doesn't, the unidentified one inherits; if neither has,
  // a new identity is created and both join.
  //
  // Caller is responsible for verifying that BOTH persons live in
  // trees the userId can access — this method assumes authorization
  // has already happened at the route layer.
  async linkPersonsByIdentity({
    sourceTreeId,
    sourcePersonId,
    targetTreeId,
    targetPersonId,
    actorId = null,
  }) {
    const db = await this._read();
    const sourcePerson = db.persons.find(
      (entry) => entry.id === sourcePersonId && entry.treeId === sourceTreeId,
    );
    const targetPerson = db.persons.find(
      (entry) => entry.id === targetPersonId && entry.treeId === targetTreeId,
    );
    if (!sourcePerson || !targetPerson) return null;

    // Same identity already → no-op.
    const sourceIdentityId = normalizeNullableString(sourcePerson.identityId);
    const targetIdentityId = normalizeNullableString(targetPerson.identityId);
    if (
      sourceIdentityId &&
      targetIdentityId &&
      sourceIdentityId === targetIdentityId
    ) {
      return {sourcePerson, targetPerson, identityId: sourceIdentityId};
    }

    const identities = this._ensurePersonIdentityCollection(db);
    const sourceIdentity = sourceIdentityId
      ? identities.find((entry) => entry.id === sourceIdentityId) || null
      : null;
    const targetIdentity = targetIdentityId
      ? identities.find((entry) => entry.id === targetIdentityId) || null
      : null;

    // Conflict guard: if BOTH identities are claimed by different
    // user accounts, that's a destructive merge (would collapse
    // two real humans' canonical records). Refuse and let the
    // route surface 409 — the user must reconcile via explicit
    // merge proposals (`mergeProposals`) instead.
    const sourceUserClaim = normalizeNullableString(sourceIdentity?.userId);
    const targetUserClaim = normalizeNullableString(targetIdentity?.userId);
    if (
      sourceUserClaim &&
      targetUserClaim &&
      sourceUserClaim !== targetUserClaim
    ) {
      throw new Error("CONFLICTING_IDENTITIES");
    }

    // Pick the canonical identity. Prefer the one that's claimed
    // by a user (it's the "real human"); else either; else create.
    let identity = null;
    if (sourceUserClaim) {
      identity = sourceIdentity;
    } else if (targetUserClaim) {
      identity = targetIdentity;
    } else if (sourceIdentity) {
      identity = sourceIdentity;
    } else if (targetIdentity) {
      identity = targetIdentity;
    }
    if (!identity) {
      identity = createPersonIdentityRecord({
        personIds: [sourcePersonId, targetPersonId],
      });
      identities.push(identity);
    }

    // The OTHER identity (the one we didn't pick) gets retired —
    // its persons reattach to the canonical identity. Without
    // this, both identities would dangle in db.personIdentities
    // and `_reconcilePersonIdentities` would re-split them on
    // the next read. We mark `mergedInto` for audit, then drop
    // the row from the live collection.
    const retiredIdentity = identity === sourceIdentity ? targetIdentity : sourceIdentity;
    if (retiredIdentity && retiredIdentity.id !== identity.id) {
      retiredIdentity.mergedInto = identity.id;
      retiredIdentity.updatedAt = nowIso();
      // Reattach any persons that were on the retired identity.
      for (const otherPerson of db.persons) {
        if (otherPerson.identityId === retiredIdentity.id) {
          otherPerson.identityId = identity.id;
          otherPerson.updatedAt = nowIso();
        }
      }
      // Drop the retired record from the live collection.
      const retiredIdx = identities.findIndex(
        (entry) => entry.id === retiredIdentity.id,
      );
      if (retiredIdx >= 0) {
        identities.splice(retiredIdx, 1);
      }
    }

    // Attach both — _attachPersonToIdentity also re-runs the
    // PersonIdentity reconciliation pass so personIds stays
    // consistent.
    this._attachPersonToIdentity(db, sourcePerson, identity, sourcePerson.userId);
    this._attachPersonToIdentity(db, targetPerson, identity, targetPerson.userId);

    // Audit trail on both trees so each tree's history shows the
    // explicit linking.
    const linkDetails = {
      identityId: identity.id,
      linkedToPersonId: targetPersonId,
      linkedToTreeId: targetTreeId,
    };
    this._appendTreeChangeRecord(db, {
      treeId: sourceTreeId,
      actorId,
      type: "person.identity-linked",
      personId: sourcePersonId,
      details: linkDetails,
    });
    this._appendTreeChangeRecord(db, {
      treeId: targetTreeId,
      actorId,
      type: "person.identity-linked",
      personId: targetPersonId,
      details: {
        identityId: identity.id,
        linkedToPersonId: sourcePersonId,
        linkedToTreeId: sourceTreeId,
      },
    });

    await this._write(db);
    return {
      sourcePerson: structuredClone(sourcePerson),
      targetPerson: structuredClone(targetPerson),
      identityId: identity.id,
    };
  },

  // ── Phase 1.3: edit-time conflict surfacing ─────────────────────────
  // List unresolved identity-field conflicts visible to the user.
  // Auth model: target-side. The user sees a row when it lives on a
  // tree they can access — i.e. "someone's edit on another tree
  // wants to overwrite YOUR copy of mom's name". Source-side
  // visibility isn't useful (the user knows what they wrote) and
  // would also leak conflict existence into trees the user
  // doesn't necessarily have access to.
  async listIdentityConflicts({userId, treeId = null, personId = null}) {
    const db = await this._read();
    const normalizedUserId = normalizeNullableString(userId);
    if (!normalizedUserId) return [];

    const accessibleTreeIds = new Set(
      db.trees
        .filter((tree) =>
          this._userCanAccessTreeRecord(tree, normalizedUserId, db),
        )
        .map((tree) => tree.id),
    );

    return (db.identityFieldConflicts || [])
      .filter((entry) => !entry.resolvedAt)
      .filter((entry) => accessibleTreeIds.has(entry.targetTreeId))
      .filter((entry) => !treeId || entry.targetTreeId === treeId)
      .filter((entry) => !personId || entry.targetPersonId === personId)
      .map((entry) => structuredClone(entry));
  },

  // Apply the user's resolution. `keep` leaves the target value
  // alone and just marks the row resolved (subsequent propagation
  // sees the resolved row, treats it as muted, and stops nagging
  // about this exact pair). `overwrite` writes sourceValue onto
  // the target person AND refreshes lastPropagatedFields[field]
  // — without that refresh the very next propagation would re-
  // diff `current vs lastWritten` and fire a fresh conflict.
  async resolveIdentityConflict({conflictId, choice, actorId}) {
    if (choice !== "keep" && choice !== "overwrite") {
      throw new Error("INVALID_CHOICE");
    }
    const normalizedActorId = normalizeNullableString(actorId);
    if (!normalizedActorId) {
      throw new Error("FORBIDDEN");
    }
    const db = await this._read();
    if (!Array.isArray(db.identityFieldConflicts)) {
      db.identityFieldConflicts = [];
    }
    const conflict = db.identityFieldConflicts.find(
      (entry) => entry.id === conflictId,
    );
    if (!conflict) return null;
    if (conflict.resolvedAt) {
      // Already resolved — return current state. Idempotent so
      // double-clicks on the resolve button don't 500.
      const targetPerson = db.persons.find(
        (entry) =>
          entry.id === conflict.targetPersonId &&
          entry.treeId === conflict.targetTreeId,
      );
      return {
        conflict: structuredClone(conflict),
        person: targetPerson ? structuredClone(targetPerson) : null,
      };
    }

    const targetTree = db.trees.find(
      (entry) => entry.id === conflict.targetTreeId,
    );
    if (
      !targetTree ||
      !this._userCanAccessTreeRecord(targetTree, normalizedActorId, db)
    ) {
      throw new Error("FORBIDDEN");
    }
    const targetPerson = db.persons.find(
      (entry) =>
        entry.id === conflict.targetPersonId &&
        entry.treeId === conflict.targetTreeId,
    );
    if (!targetPerson) {
      // Target gone (deleted between conflict creation and now).
      // Drop the row; UI will refetch and stop showing the badge.
      db.identityFieldConflicts = db.identityFieldConflicts.filter(
        (entry) => entry.id !== conflictId,
      );
      await this._write(db);
      return null;
    }

    const nowTs = nowIso();
    if (choice === "overwrite") {
      const previousPersonSnapshot = structuredClone(targetPerson);
      targetPerson[conflict.field] = structuredClone(conflict.sourceValue);
      if (
        !targetPerson.lastPropagatedFields ||
        typeof targetPerson.lastPropagatedFields !== "object"
      ) {
        targetPerson.lastPropagatedFields = {};
      }
      targetPerson.lastPropagatedFields[conflict.field] = structuredClone(
        conflict.sourceValue,
      );
      targetPerson.updatedAt = nowTs;
      targetTree.updatedAt = nowTs;

      this._appendTreeChangeRecord(db, {
        treeId: conflict.targetTreeId,
        actorId: normalizedActorId,
        type: "person.updated",
        personId: conflict.targetPersonId,
        details: {
          before: previousPersonSnapshot,
          after: structuredClone(targetPerson),
          identityConflictResolution: {
            conflictId,
            field: conflict.field,
            choice: "overwrite",
            sourceTreeId: conflict.sourceTreeId,
            sourcePersonId: conflict.sourcePersonId,
          },
        },
      });
      upsertPersonAttributesForPerson(db, targetPerson, normalizedActorId);
    }

    conflict.resolvedAt = nowTs;
    conflict.resolvedBy = normalizedActorId;
    conflict.resolution = choice;

    await this._write(db);
    return {
      conflict: structuredClone(conflict),
      person: structuredClone(targetPerson),
    };
  },

  _mergeProposalStillActionable(db, proposal, normCache = null) {
    if (!proposal || proposal.status !== "pending") {
      return false;
    }
    const fromPerson = db.persons.find(
      (person) => person.id === proposal.fromPersonId,
    );
    const candidatePerson = db.persons.find(
      (person) => person.id === proposal.candidatePersonId,
    );
    if (!fromPerson || !candidatePerson) {
      return false;
    }
    if (
      fromPerson.id === candidatePerson.id ||
      fromPerson.treeId === candidatePerson.treeId
    ) {
      return false;
    }
    const fromTree = db.trees.find((tree) => tree.id === fromPerson.treeId);
    const candidateTree = db.trees.find(
      (tree) => tree.id === candidatePerson.treeId,
    );
    if (!fromTree || !candidateTree) {
      return false;
    }
    const fromIdentityId = normalizeNullableString(fromPerson.identityId);
    const candidateIdentityId = normalizeNullableString(candidatePerson.identityId);
    if (
      !fromIdentityId ||
      !candidateIdentityId ||
      fromIdentityId === candidateIdentityId
    ) {
      return false;
    }
    return Boolean(this._scorePersonPairCached(fromPerson, candidatePerson, normCache));
  },

  // SPEED-13: dryRun — вычислить БЫ ли этот вызов что-то поменял, НЕ
  // мутируя `db` (нужно для listPendingMergeProposalsForUser над
  // замороженным readSharedSnapshot() — присвоение поля на frozen-объекте
  // в store.js молча no-op'ается, sloppy-mode, но мы не хотим полагаться
  // на это, см. _ensureCrossTreeMergeProposals). Контрольный поток и
  // порядок обхода — те же, что и в обычном режиме, только запись статуса
  // пропускается.
  _markStaleMergeProposals(db, normCache = null, {dryRun = false} = {}) {
    let changed = false;
    const mergeProposals = Array.isArray(db.mergeProposals)
      ? db.mergeProposals
      : [];
    if (!dryRun) {
      db.mergeProposals = mergeProposals;
    }
    for (const proposal of mergeProposals) {
      if (
        proposal.status === "pending" &&
        !this._mergeProposalStillActionable(db, proposal, normCache)
      ) {
        if (!dryRun) {
          proposal.status = "stale";
          proposal.resolvedAt = nowIso();
        }
        changed = true;
      }
    }
    return changed;
  },

  _mergeProposalPersonContext(db, person, viewerUserId) {
    if (!person) {
      return "Карточка удалена";
    }
    const tree = db.trees.find((entry) => entry.id === person.treeId);
    if (!tree) {
      return "Дерево удалено";
    }
    if (this._userCanAccessTreeRecord(tree, viewerUserId, db)) {
      const treeName =
        String(tree.name || "Без названия").trim() || "Без названия";
      return `Дерево: ${treeName}`;
    }
    return "Другое приватное дерево";
  },

  _mergeProposalView(db, proposal, viewerUserId = null) {
    const fromPerson = db.persons.find(
      (person) => person.id === proposal.fromPersonId,
    );
    const candidatePerson = db.persons.find(
      (person) => person.id === proposal.candidatePersonId,
    );
    // K1: зритель должен видеть СВОЙ статус (баннер на home обязан гаснуть
    // после голоса, хотя предложение остаётся pending до консенсуса) и
    // ПОИМЁННЫЙ статус остальных ответственных («Вы ✓ · Наталья — ждём»).
    // Имена резолвим как в Phase B (c49676f): userId → profile.displayName,
    // нет имени → displayName опускаем (клиент фолбэчит сам).
    const reviewerIds = normalizeParticipantIds(proposal.reviewerUserIds);
    const reviews = Array.isArray(proposal.reviews) ? proposal.reviews : [];
    const status = proposal.status || "pending";
    const myReview = viewerUserId
      ? reviews.find((entry) => entry.userId === viewerUserId)
      : null;
    const reviewers = reviewerIds.map((reviewerUserId) => {
      const user = db.users.find((entry) => entry.id === reviewerUserId);
      const profile = user?.profile || {};
      const displayName =
        normalizeNullableString(profile.displayName) ||
        composeDisplayNameFromProfile(profile) ||
        null;
      const review = reviews.find((entry) => entry.userId === reviewerUserId);
      return {
        userId: reviewerUserId,
        ...(displayName ? {displayName} : {}),
        decision: review ? review.decision : null,
        isViewer: Boolean(viewerUserId) && reviewerUserId === viewerUserId,
      };
    });
    return {
      id: proposal.id,
      status,
      matchScore: Number(proposal.matchScore || 0),
      confidence: proposal.matchScore >= 0.9 ? "high" : "medium",
      matchSignals:
        proposal.matchSignals && typeof proposal.matchSignals === "object"
          ? structuredClone(proposal.matchSignals)
          : {},
      reasons: Array.isArray(proposal.reasons) ? proposal.reasons : [],
      personA: safeMergePersonPreview(fromPerson, {
        contextLabel: this._mergeProposalPersonContext(
          db,
          fromPerson,
          viewerUserId,
        ),
        ownership: this._mergePersonOwnership(db, fromPerson, viewerUserId),
      }),
      personB: safeMergePersonPreview(candidatePerson, {
        contextLabel: this._mergeProposalPersonContext(
          db,
          candidatePerson,
          viewerUserId,
        ),
        ownership: this._mergePersonOwnership(db, candidatePerson, viewerUserId),
      }),
      requiredReviewCount: reviewerIds.length,
      reviewCount: reviews.filter((entry) => entry.decision === "accepted")
        .length,
      myDecision: myReview ? myReview.decision : null,
      awaitingMyDecision:
        status === "pending" &&
        Boolean(viewerUserId) &&
        reviewerIds.includes(viewerUserId) &&
        !myReview,
      reviewers,
      createdAt: proposal.createdAt,
      resolvedAt: proposal.resolvedAt || null,
    };
  },

  // SPEED-10: normCache — см. _scorePersonPairCached. Этот метод — сам
  // главный потребитель: цикл stewardPersons × allPersons без кэша
  // renormализовал ОБОИХ persons на КАЖДУЮ пару, хотя allPersons — тот же
  // фиксированный набор на протяжении всего двойного цикла (и candidatePerson
  // повторно перебирается для каждого fromPerson) — см. docs/speed_measurement.md
  // SPEED-10 (profile: normalizeIsoDate/normalizeName/normalizeNameTokens
  // суммарно ~16% self-time одного бёрста).
  //
  // SPEED-13: dryRun — вычислить, изменился бы ли результат, НЕ мутируя
  // `db` (ни `db.mergeProposals`, ни персон, ни personIdentities) — нужно
  // для listPendingMergeProposalsForUser, чтобы решить, надо ли вообще
  // материализовывать (_mutate), не трогая замороженный readSharedSnapshot().
  // На фростженном `db` .push() на массиве бросил бы TypeError безусловно,
  // а присвоение поля объекта — sloppy-mode no-op (см. SPEED-12
  // «_writableCirclesViewForTree»); dryRun просто не делает эти вызовы, а не
  // полагается на no-op. Контрольный поток (обход пар, early-return по
  // limit, что считается «changed») — БУКВАЛЬНО тот же, только без
  // побочных эффектов — двух независимых реализаций нет, разойтись нечему.
  //
  // dryRun ТАКЖЕ гейтит _reconcilePersonIdentities: она вызывается только
  // если dbHasPersonsWithoutIdentity(db) — на проде(steady state) persons
  // уже с identityId, backfillPersonIdentities внутри неё дважды хэширует
  // ВСЮ базу (stableSerialize+sha256) без единого реального изменения —
  // см. docs/speed_measurement.md SPEED-10/12 профиль и dbHasPersonsWithoutIdentity
  // выше. Гейт действует и вне dryRun (реальная материализация внутри
  // _mutate тоже не должна дважды хэшировать уже согласованную базу) —
  // ВНЕ dryRun вызывающий обязан передавать МУТИРУЕМЫЙ db (см. _mutate);
  // dryRun-пути гарантированно видят dbHasPersonsWithoutIdentity(db) ===
  // false, потому что listPendingMergeProposalsForUser проверяет тот же
  // гейт ДО того, как решить, пробовать ли dryRun вообще (иначе backfill
  // был бы нужен, а мутировать замороженный db нельзя).
  _ensureCrossTreeMergeProposals(
    db,
    userId,
    {limit = 50, normCache = null, dryRun = false} = {},
  ) {
    const normalizedUserId = normalizeNullableString(userId);
    if (!normalizedUserId) {
      return false;
    }
    const mergeProposals = Array.isArray(db.mergeProposals)
      ? db.mergeProposals
      : [];
    if (!dryRun) {
      db.mergeProposals = mergeProposals;
      if (dbHasPersonsWithoutIdentity(db)) {
        this._reconcilePersonIdentities(db);
      }
    }

    const accessibleTreeIds = new Set(
      db.trees
        .filter((tree) =>
          this._userCanAccessTreeRecord(tree, normalizedUserId, db),
        )
        .map((tree) => tree.id),
    );
    const stewardPersons = db.persons.filter((person) => {
      return (
        accessibleTreeIds.has(person.treeId) &&
        this._isPersonSteward(db, person, normalizedUserId)
      );
    });
    if (stewardPersons.length === 0) {
      return false;
    }

    let changed = false;
    let createdCount = 0;
    const allPersons = Array.isArray(db.persons) ? db.persons : [];
    for (const fromPerson of stewardPersons) {
      for (const candidatePerson of allPersons) {
        if (
          fromPerson.id === candidatePerson.id ||
          fromPerson.treeId === candidatePerson.treeId ||
          normalizeNullableString(fromPerson.identityId) ===
            normalizeNullableString(candidatePerson.identityId)
        ) {
          continue;
        }

        const match = this._scorePersonPairCached(fromPerson, candidatePerson, normCache);
        if (!match) {
          continue;
        }

        const proposalPersonIds = [fromPerson.id, candidatePerson.id].sort(
          (left, right) => left.localeCompare(right),
        );
        const proposalId = `merge:${proposalPersonIds[0]}:${proposalPersonIds[1]}`;
        const existing = mergeProposals.find(
          (proposal) => proposal.id === proposalId,
        );
        if (existing && existing.status !== "pending") {
          continue;
        }

        const fromIdentity = db.personIdentities.find(
          (identity) => identity.id === fromPerson.identityId,
        );
        const candidateIdentity = db.personIdentities.find(
          (identity) => identity.id === candidatePerson.identityId,
        );
        const reviewerUserIds = normalizeParticipantIds([
          ...personStewardUserIds(db, fromPerson),
          ...personStewardUserIds(db, candidatePerson),
          ...identityStewardUserIds(db, fromIdentity),
          ...identityStewardUserIds(db, candidateIdentity),
        ]);
        if (!reviewerUserIds.includes(normalizedUserId)) {
          continue;
        }

        const matchSignals = {
          name: true,
          birthYear:
            normalizedBirthYear(fromPerson.birthDate) &&
            normalizedBirthYear(fromPerson.birthDate) ===
              normalizedBirthYear(candidatePerson.birthDate),
        };
        if (!existing) {
          if (!dryRun) {
            mergeProposals.push({
              id: proposalId,
              fromPersonId: fromPerson.id,
              toIdentityId: normalizeNullableString(fromPerson.identityId),
              candidatePersonId: candidatePerson.id,
              candidateIdentityId: normalizeNullableString(candidatePerson.identityId),
              matchScore: match.score,
              matchSignals,
              reasons: match.reasons,
              status: "pending",
              proposedByUserId: null,
              reviewerUserIds,
              reviews: [],
              createdAt: nowIso(),
              resolvedAt: null,
            });
            this._notifyReviewers(db, {
              type: "merge_proposal",
              title: "Возможное совпадение",
              body: "Проверьте, не описывают ли две карточки одного человека.",
              reviewerUserIds,
              data: {proposalId, kind: "cross_tree_merge"},
            });
          }
          changed = true;
          createdCount += 1;
        } else {
          // SPEED-10: раньше этот путь безусловно ставил changed=true —
          // на дереве, где хотя бы одна pending-пара уже существует (что
          // после первого прохода почти всегда так), КАЖДЫЙ вызов
          // listPendingMergeProposalsForUser безусловно писал блоб целиком
          // (полный JSON.stringify + fs.rename на GET-путь), даже когда
          // recompute дал ТЕ ЖЕ значения. Итоговые поля existing — те же
          // самые независимо от этой проверки; меняется только то, нужен
          // ли _write. См. docs/speed_measurement.md SPEED-10.
          const matchSignalsChanged =
            Boolean(existing.matchSignals?.name) !== Boolean(matchSignals.name) ||
            Boolean(existing.matchSignals?.birthYear) !== Boolean(matchSignals.birthYear);
          const reasonsChanged =
            !Array.isArray(existing.reasons) ||
            existing.reasons.length !== match.reasons.length ||
            existing.reasons.some((reason, index) => reason !== match.reasons[index]);
          const somethingChanged =
            existing.matchScore !== match.score ||
            matchSignalsChanged ||
            reasonsChanged ||
            !sameNormalizedIds(existing.reviewerUserIds, reviewerUserIds);

          if (!dryRun) {
            existing.matchScore = match.score;
            existing.matchSignals = matchSignals;
            existing.reasons = match.reasons;
            existing.reviewerUserIds = reviewerUserIds;
          }
          if (somethingChanged) {
            changed = true;
          }
        }

        if (createdCount >= limit) {
          return changed;
        }
      }
    }
    return changed;
  },

  // SPEED-13: единственное место, где merge-proposals реально ПИШУТСЯ —
  // атомарный RMW через _mutate (свежий _read() внутри applyFn,
  // _ensureCrossTreeMergeProposals/_markStaleMergeProposals без dryRun —
  // те же функции, что и раньше, просто вызванные не напрямую на «голом»
  // _read()+условный _write(), а через store-wide _mutateQueue). Backfill
  // внутри _ensureCrossTreeMergeProposals сам гейтится
  // dbHasPersonsWithoutIdentity НА ЭТОМ свежем db — если снимок в
  // listPendingMergeProposalsForUser ниже был дирти, а к моменту _mutate
  // кто-то её уже почистил (или наоборот), решение всегда принимается по
  // самым свежим данным, не по устаревшему dry-run.
  // Возвращает {db, normCache}: db — для ответа (даже если _write не
  // случился — свежепрочитанный db точнее устаревшего снимка), normCache —
  // чтобы финальный .filter() в listPendingMergeProposalsForUser не
  // renormализовал персон этого db заново (SPEED-10 инвариант).
  async _materializeMergeProposals(normalizedUserId, limit) {
    const normCache = new Map();
    const db = await this._mutate((data, skip) => {
      let changed = this._ensureCrossTreeMergeProposals(data, normalizedUserId, {
        limit,
        normCache,
      });
      changed = this._markStaleMergeProposals(data, normCache) || changed;
      return changed ? data : skip(data);
    });
    return {db, normCache};
  },

  // SPEED-10: normCache — одна Map на весь вызов, разделяемая
  // _ensureCrossTreeMergeProposals/_markStaleMergeProposals/финальным
  // .filter() ниже — те же persons проверяются во ВСЕХ трёх местах
  // (кандидаты → staleness-рефреш → staleness-рецепт для reviewer-набора),
  // без кэша каждый раз заново нормализовался. См. _scorePersonPairCached.
  //
  // SPEED-13: раньше КАЖДЫЙ вызов честно читал блоб (_read(), клон на
  // Postgres) и безусловно гонял _reconcilePersonIdentities (двойной
  // hashSnapshot всей базы — см. dbHasPersonsWithoutIdentity выше), даже
  // когда пересчёт не находил ни одного изменения (обычный случай в
  // steady state). Теперь: 1) читаем ОБЩИЙ замороженный снимок
  // (prefetchedDb, если маршрут его уже прочитал — SPEED-9B/11 — иначе
  // readSharedSnapshot(), без клона на попадании кэша); 2) если в базе
  // ЕСТЬ person без identityId — снимок нельзя безопасно использовать для
  // подсчёта (backfill обязателен, а мутировать заморозку нельзя) —
  // сразу материализуем; 3) иначе — dryRun-прогон ПРЯМО по замороженному
  // снимку (0 доп. чтений блоба, 0 записей), и материализуем через
  // _mutate ТОЛЬКО если dryRun говорит, что что-то реально изменилось
  // (новое предложение / выросший score / протухшая пара). Ответ клиенту
  // строится либо из результата материализации (если она случилась),
  // либо прямо из снимка — форма и порядок те же самые (см.
  // speed13-merge-proposals.test.js).
  async listPendingMergeProposalsForUser(
    userId,
    {limit = 50} = {},
    prefetchedDb = null,
  ) {
    const normalizedUserId = normalizeNullableString(userId);
    const snapshot = prefetchedDb || (await this.readSharedSnapshot());

    let db = snapshot;
    let normCache = new Map();

    if (dbHasPersonsWithoutIdentity(snapshot)) {
      ({db, normCache} = await this._materializeMergeProposals(
        normalizedUserId,
        limit,
      ));
    } else {
      let wouldChange = this._ensureCrossTreeMergeProposals(
        snapshot,
        normalizedUserId,
        {limit, normCache, dryRun: true},
      );
      wouldChange =
        this._markStaleMergeProposals(snapshot, normCache, {dryRun: true}) ||
        wouldChange;
      if (wouldChange) {
        ({db, normCache} = await this._materializeMergeProposals(
          normalizedUserId,
          limit,
        ));
      }
    }

    return db.mergeProposals
      .filter(
        (proposal) =>
          proposal.status === "pending" &&
          normalizeParticipantIds(proposal.reviewerUserIds).includes(
            normalizedUserId,
          ) &&
          this._mergeProposalStillActionable(db, proposal, normCache),
      )
      .sort((left, right) =>
        String(right.createdAt || "").localeCompare(String(left.createdAt || "")),
      )
      .slice(0, Math.max(0, Math.min(Number(limit) || 50, 100)))
      .map((proposal) =>
        structuredClone(this._mergeProposalView(db, proposal, normalizedUserId)),
      );
  },

  async reviewMergeProposal({proposalId, reviewerUserId, decision, reason = null}) {
    const db = await this._read();
    db.mergeProposals = Array.isArray(db.mergeProposals)
      ? db.mergeProposals
      : [];
    const proposal = db.mergeProposals.find((entry) => entry.id === proposalId);
    if (!proposal) {
      return null;
    }
    if (!normalizeParticipantIds(proposal.reviewerUserIds).includes(reviewerUserId)) {
      return false;
    }
    if (proposal.status !== "pending") {
      return structuredClone(
        this._mergeProposalView(db, proposal, reviewerUserId),
      );
    }
    if (!this._mergeProposalStillActionable(db, proposal)) {
      proposal.status = "stale";
      proposal.resolvedAt = nowIso();
      await this._write(db);
      return structuredClone(
        this._mergeProposalView(db, proposal, reviewerUserId),
      );
    }

    const normalizedDecision =
      String(decision || "").trim().toLowerCase() === "accept"
        ? "accepted"
        : "rejected";
    proposal.reviews = (Array.isArray(proposal.reviews) ? proposal.reviews : [])
      .filter((review) => review.userId !== reviewerUserId);
    proposal.reviews.push({
      userId: reviewerUserId,
      decision: normalizedDecision,
      reason: normalizeNullableString(reason),
      at: nowIso(),
    });

    if (normalizedDecision === "rejected") {
      proposal.status = "rejected";
      proposal.resolvedAt = nowIso();
    } else {
      const acceptedReviewerIds = new Set(
        proposal.reviews
          .filter((review) => review.decision === "accepted")
          .map((review) => review.userId),
      );
      const allAccepted = normalizeParticipantIds(proposal.reviewerUserIds)
        .every((userId) => acceptedReviewerIds.has(userId));
      if (allAccepted) {
        proposal.status = "accepted";
        proposal.mergeApplied = this._mergeIdentitiesForProposal(db, proposal);
        proposal.resolvedAt = nowIso();
      }
    }
    await this._write(db);
    return structuredClone(
      this._mergeProposalView(db, proposal, reviewerUserId),
    );
  },

  // D1: разъединение применённого слияния по журналу. Карточки в
  // деревьях не меняются — распадается только связка «это один человек».
  // Возвраты: null — нет предложения; false — актор не ответственный;
  // {error: 'legacy'} — слияние применено до журнала (легаси boolean);
  // {error: 'not_applied'} — нечего разъединять; иначе — view.
  async unmergeMergeProposal({proposalId, actorUserId}) {
    const db = await this._read();
    const proposal = (db.mergeProposals || []).find(
      (entry) => entry.id === proposalId,
    );
    if (!proposal) {
      return null;
    }
    if (
      !normalizeParticipantIds(proposal.reviewerUserIds).includes(
        normalizeNullableString(actorUserId),
      )
    ) {
      return false;
    }
    if (proposal.status !== "accepted" || !proposal.mergeApplied) {
      return {error: "not_applied"};
    }
    const journal = proposal.mergeApplied;
    if (journal === true || typeof journal !== "object") {
      // Слияние времён boolean-флага — журнала нет, честно отказываем.
      return {error: "legacy"};
    }

    const sourceIdentityId = normalizeNullableString(journal.sourceIdentityId);
    const targetIdentityId = normalizeNullableString(journal.targetIdentityId);
    const sourceIdentity = sourceIdentityId
      ? db.personIdentities.find((entry) => entry.id === sourceIdentityId)
      : null;
    const targetIdentity = targetIdentityId
      ? db.personIdentities.find((entry) => entry.id === targetIdentityId)
      : null;

    // Persons, удалённые с момента слияния, пропускаем молча.
    const survivingPersonIds = normalizeParticipantIds(
      journal.movedPersonIds,
    ).filter((personId) =>
      db.persons.some((person) => person.id === personId),
    );
    for (const person of db.persons) {
      if (survivingPersonIds.includes(person.id)) {
        person.identityId = sourceIdentityId;
        person.updatedAt = nowIso();
      }
    }
    const movedAttributeIds = new Set(
      Array.isArray(journal.movedAttributeIds) ? journal.movedAttributeIds : [],
    );
    for (const attribute of db.personAttributes || []) {
      if (movedAttributeIds.has(attribute.id)) {
        attribute.identityId = sourceIdentityId;
        attribute.updatedAt = nowIso();
      }
    }

    if (sourceIdentity) {
      sourceIdentity.mergedInto = null;
      sourceIdentity.personIds = survivingPersonIds;
      // Осознанный дефолт: в публичный поиск не возвращаем — пусть
      // включают сами.
      sourceIdentity.isPublicDiscoverable = false;
      sourceIdentity.updatedAt = nowIso();
    }
    if (targetIdentity) {
      targetIdentity.personIds = normalizeParticipantIds(
        (targetIdentity.personIds || []).filter(
          (personId) => !survivingPersonIds.includes(personId),
        ),
      );
      if (journal.userIdAbsorbed === true) {
        targetIdentity.userId = null;
      }
      if (journal.claimedByAbsorbed === true) {
        targetIdentity.claimedByUserId = null;
      }
      targetIdentity.updatedAt = nowIso();
    }

    // История сохраняется: повторный матч сможет предложить заново.
    proposal.status = "unmerged";
    proposal.unmergedAt = nowIso();
    proposal.unmergedByUserId = normalizeNullableString(actorUserId);

    this._reconcilePersonIdentities(db);
    await this._write(db);
    return structuredClone(
      this._mergeProposalView(db, proposal, actorUserId),
    );
  },

  async listPersonAttributes({treeId, personId}) {
    const db = await this._read();
    const person = db.persons.find(
      (entry) => entry.treeId === treeId && entry.id === personId,
    );
    if (!person) {
      return null;
    }
    const changed = upsertPersonAttributesForPerson(db, person, person.creatorId);
    if (changed) {
      await this._write(db);
    }
    return (db.personAttributes || [])
      .filter(
        (entry) =>
          entry.identityId === person.identityId &&
          entry.sourcePersonId === person.id &&
          entry.status !== "archived",
      )
      .map((entry) => structuredClone(entry));
  },

  async updatePersonAttributeVisibility({
    treeId,
    personId,
    actorUserId,
    attributes = [],
    cardVisibility = undefined,
  }) {
    const db = await this._read();
    const person = db.persons.find(
      (entry) => entry.treeId === treeId && entry.id === personId,
    );
    if (!person) {
      return null;
    }
    if (!this._isPersonSteward(db, person, actorUserId)) {
      return false;
    }

    if (cardVisibility !== undefined) {
      person.visibility = normalizePersonVisibility(
        cardVisibility,
        defaultPersonVisibility(person),
      );
      person.updatedAt = nowIso();
    }
    upsertPersonAttributesForPerson(db, person, actorUserId);
    for (const item of Array.isArray(attributes) ? attributes : []) {
      const field = String(item?.field || "").trim();
      if (!PERSON_ATTRIBUTE_FIELDS.includes(field)) {
        continue;
      }
      const attribute = db.personAttributes.find(
        (entry) =>
          entry.identityId === person.identityId &&
          entry.sourcePersonId === person.id &&
          entry.field === field &&
          entry.status !== "archived",
      );
      if (!attribute) {
        continue;
      }
      attribute.visibility = normalizePersonVisibility(item.visibility);
      attribute.updatedAt = nowIso();
    }
    await this._write(db);
    return this.listPersonAttributes({treeId, personId});
  },

  _identityClaimView(claim, db = null) {
    let personName = null;
    let treeId = null;
    let treeName = null;
    if (db) {
      const person = (Array.isArray(db.persons) ? db.persons : []).find(
        (entry) => entry.id === claim.personId,
      );
      if (person) {
        personName =
          normalizeNullableString(person.displayName) ||
          normalizeNullableString(person.name) ||
          null;
        treeId = normalizeNullableString(person.treeId) || null;
        if (treeId) {
          const tree = (Array.isArray(db.trees) ? db.trees : []).find(
            (entry) => entry.id === treeId,
          );
          treeName = normalizeNullableString(tree?.name) || null;
        }
      }
    }
    return {
      id: claim.id,
      identityId: claim.identityId,
      personId: claim.personId,
      claimantUserId: claim.claimantUserId,
      status: claim.status,
      reviewerUserIds: normalizeParticipantIds(claim.reviewerUserIds),
      reviews: Array.isArray(claim.reviews)
        ? claim.reviews.map((entry) => structuredClone(entry))
        : [],
      createdAt: claim.createdAt,
      resolvedAt: claim.resolvedAt || null,
      ...(personName ? {personName} : {}),
      ...(treeId ? {treeId} : {}),
      ...(treeName ? {treeName} : {}),
    };
  },

  _approveIdentityClaim(db, claim) {
    const identity = db.personIdentities.find(
      (entry) => entry.id === claim.identityId,
    );
    const person = db.persons.find((entry) => entry.id === claim.personId);
    if (!identity || !person) {
      return false;
    }
    return this._attachPersonToIdentity(
      db,
      person,
      identity,
      claim.claimantUserId,
    );
  },

  async createIdentityClaim({treeId, personId, claimantUserId, evidence = null}) {
    const db = await this._read();
    db.identityClaims = Array.isArray(db.identityClaims)
      ? db.identityClaims
      : [];
    const person = db.persons.find(
      (entry) => entry.treeId === treeId && entry.id === personId,
    );
    if (!person) {
      return null;
    }
    this._reconcilePersonIdentities(db);
    const identity = db.personIdentities.find(
      (entry) => entry.id === person.identityId,
    );
    if (!identity) {
      return null;
    }
    const existing = db.identityClaims.find(
      (claim) =>
        claim.identityId === identity.id &&
        claim.claimantUserId === claimantUserId &&
        claim.status === "pending",
    );
    if (existing) {
      return structuredClone(this._identityClaimView(existing));
    }

    const reviewerUserIds = normalizeParticipantIds([
      ...identityStewardUserIds(db, identity),
      ...personStewardUserIds(db, person),
    ]).filter((userId) => userId !== claimantUserId);
    const timestamp = nowIso();
    const claim = {
      id: crypto.randomUUID(),
      identityId: identity.id,
      personId: person.id,
      claimantUserId,
      evidence: normalizeNullableString(evidence),
      status: reviewerUserIds.length === 0 ? "approved" : "pending",
      reviewerUserIds,
      reviews: [],
      createdAt: timestamp,
      resolvedAt: reviewerUserIds.length === 0 ? timestamp : null,
    };
    db.identityClaims.push(claim);
    if (claim.status === "approved") {
      this._approveIdentityClaim(db, claim);
    } else {
      this._notifyReviewers(db, {
        type: "identity_claim",
        title: "Запрос подтверждения личности",
        body: "Пользователь просит связать профиль с карточкой в дереве.",
        reviewerUserIds,
        data: {claimId: claim.id, personId: person.id},
      });
    }
    await this._write(db);
    return structuredClone(this._identityClaimView(claim, db));
  },

  async listPendingIdentityClaimsForUser(userId) {
    const db = await this._read();
    db.identityClaims = Array.isArray(db.identityClaims)
      ? db.identityClaims
      : [];
    return (db.identityClaims || [])
      .filter(
        (claim) =>
          claim.status === "pending" &&
          normalizeParticipantIds(claim.reviewerUserIds).includes(userId),
      )
      .sort((left, right) =>
        String(right.createdAt || "").localeCompare(String(left.createdAt || "")),
      )
      .map((claim) => structuredClone(this._identityClaimView(claim, db)));
  },

  async listMyIdentityClaims(userId) {
    const db = await this._read();
    db.identityClaims = Array.isArray(db.identityClaims)
      ? db.identityClaims
      : [];
    return (db.identityClaims || [])
      .filter((claim) => claim.claimantUserId === userId)
      .sort((left, right) =>
        String(right.createdAt || "").localeCompare(String(left.createdAt || "")),
      )
      .map((claim) => structuredClone(this._identityClaimView(claim, db)));
  },

  async cancelIdentityClaim({claimId, actorUserId}) {
    return this._mutate((db, skip) => {
      db.identityClaims = Array.isArray(db.identityClaims)
        ? db.identityClaims
        : [];
      const claim = db.identityClaims.find((entry) => entry.id === claimId);
      if (!claim) {
        return skip(null);
      }
      if (claim.claimantUserId !== actorUserId) {
        return skip({error: "FORBIDDEN"});
      }
      if (claim.status !== "pending") {
        return skip({error: "CONFLICT"});
      }
      claim.status = "canceled";
      claim.resolvedAt = nowIso();
      return {claim: structuredClone(this._identityClaimView(claim, db))};
    });
  },

  async reviewIdentityClaim({claimId, reviewerUserId, decision, reason = null}) {
    const db = await this._read();
    db.identityClaims = Array.isArray(db.identityClaims)
      ? db.identityClaims
      : [];
    const claim = db.identityClaims.find((entry) => entry.id === claimId);
    if (!claim) {
      return null;
    }
    if (!normalizeParticipantIds(claim.reviewerUserIds).includes(reviewerUserId)) {
      return false;
    }
    if (claim.status === "canceled") {
      return {error: "CONFLICT"};
    }
    if (claim.status !== "pending") {
      return structuredClone(this._identityClaimView(claim, db));
    }
    const normalizedDecision =
      String(decision || "").trim().toLowerCase() === "approve"
        ? "approved"
        : "denied";
    claim.reviews = (Array.isArray(claim.reviews) ? claim.reviews : [])
      .filter((review) => review.userId !== reviewerUserId);
    claim.reviews.push({
      userId: reviewerUserId,
      decision: normalizedDecision,
      reason: normalizeNullableString(reason),
      at: nowIso(),
    });
    if (normalizedDecision === "denied") {
      claim.status = "denied";
      claim.resolvedAt = nowIso();
    } else {
      const approvedReviewerIds = new Set(
        claim.reviews
          .filter((review) => review.decision === "approved")
          .map((review) => review.userId),
      );
      if (
        normalizeParticipantIds(claim.reviewerUserIds).every((userId) =>
          approvedReviewerIds.has(userId),
        )
      ) {
        claim.status = "approved";
        claim.resolvedAt = nowIso();
        this._approveIdentityClaim(db, claim);
      }
    }
    await this._write(db);
    return structuredClone(this._identityClaimView(claim));
  },

  async setIdentityDiscoverability({userId, isPublicDiscoverable}) {
    const db = await this._read();
    const identity = this._ensureUserIdentity(db, userId);
    if (!identity) {
      return null;
    }
    identity.isPublicDiscoverable = isPublicDiscoverable === true;
    identity.updatedAt = nowIso();
    await this._write(db);
    return structuredClone({
      identityId: identity.id,
      isPublicDiscoverable: identity.isPublicDiscoverable,
    });
  },

  async searchPublicIdentities({query, birthYear = null, limit = 20} = {}) {
    const db = await this._read();
    const normalizedQuery = String(query || "").trim().toLowerCase();
    const normalizedBirthYear = normalizeNullableString(birthYear);
    if (normalizedQuery.length < 2 && !normalizedBirthYear) {
      return [];
    }
    return (db.personIdentities || [])
      .filter((identity) => identity.isPublicDiscoverable === true)
      .map((identity) => {
        const primaryPerson =
          db.persons.find((person) => person.id === identity.primaryPersonId) ||
          db.persons.find((person) =>
            normalizeParticipantIds(identity.personIds).includes(person.id),
          );
        return {identity, primaryPerson};
      })
      .filter(({primaryPerson}) => {
        if (!primaryPerson) {
          return false;
        }
        const name = String(primaryPerson.name || "").toLowerCase();
        const year = extractBirthYear(primaryPerson.birthDate);
        if (normalizedBirthYear && year !== normalizedBirthYear) {
          return false;
        }
        return !normalizedQuery || name.includes(normalizedQuery);
      })
      .slice(0, Math.max(0, Math.min(Number(limit) || 20, 50)))
      .map(({identity, primaryPerson}) => ({
        identityId: identity.id,
        name: String(primaryPerson.name || "Без имени").trim() || "Без имени",
        birthYear: extractBirthYear(primaryPerson.birthDate),
      }));
  },
};
