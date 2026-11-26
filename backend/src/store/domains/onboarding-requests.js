const path = require("node:path");
const crypto = require("node:crypto");
const {
  enforceSafeMediaOrLinkUrl,
} = require("../../input-guards");
const {
  CONNECTED_VISIBILITY_MAX_HOPS,
  KINSHIP_CHECK_TTL_MS,
  KINSHIP_REJECTION_COOLDOWN_MS,
  STORY_REQUEST_MAX_PENDING_PER_INITIATOR,
  STORY_REQUEST_TTL_MS,
} = require("../constants");
const {
  createArticleBlockRecord,
  normalizeArticleBlockContent,
  normalizeNullableString,
  nowIso,
} = require("../helpers");

module.exports = {
  /// State-based idempotent seed (DECISIONS.md 2026-05-13). User
  /// retry на network fail → returns existing tree. Incomplete
  /// previous attempt → replaced (transaction rollback).
  ///
  /// payload = {
  ///   profile: {name, gender, birthDate},
  ///   relatives: [{name, gender, birthDate, relationToMe}],
  /// }
  /// relationToMe ∈ {'mother','father','sibling','child','grandmother','grandfather'}.
  async seedOnboarding({userId, payload}) {
    const normalizedUser = normalizeNullableString(userId);
    if (!normalizedUser) return {error: "NO_USER"};
    const db = await this._read();
    const user = db.users.find((u) => u.id === normalizedUser);
    if (!user) return {error: "USER_NOT_FOUND"};

    // State-based idempotency check.
    const existingState = (db.onboardingStates || []).find(
      (s) => s.userId === normalizedUser,
    );
    if (existingState && existingState.completed === true) {
      // Idempotent re-call — return existing tree.
      return {
        treeId: existingState.treeId,
        personIds: existingState.personIds || [],
        idempotent: true,
      };
    }

    // Incomplete previous attempt → replace. Wipe previous tree's
    // persons + relations to avoid ghost tree.
    if (existingState && existingState.treeId) {
      const prevTreeId = existingState.treeId;
      db.persons = (db.persons || []).filter((p) => p.treeId !== prevTreeId);
      db.relations = (db.relations || []).filter(
        (r) => r.treeId !== prevTreeId,
      );
      db.trees = (db.trees || []).filter((t) => t.id !== prevTreeId);
    }

    // Apply profile to user record (additive — не затирать существующее).
    const profile = payload?.profile || {};
    user.profile = user.profile || {};
    if (profile.name) user.profile.displayName = String(profile.name).trim();
    if (profile.gender) user.profile.gender = String(profile.gender);
    if (profile.birthDate) {
      user.profile.birthDate = String(profile.birthDate);
    }

    // Create tree.
    const treeId = crypto.randomUUID();
    const now = nowIso();
    const tree = {
      id: treeId,
      name: "Моя семья",
      description: "",
      creatorId: normalizedUser,
      memberIds: [normalizedUser],
      members: [normalizedUser],
      createdAt: now,
      updatedAt: now,
      isPrivate: true,
    };
    db.trees = db.trees || [];
    db.trees.push(tree);

    // Create self-person.
    const selfIdentity = this._ensureUserIdentity(db, normalizedUser);
    const selfPerson = {
      id: crypto.randomUUID(),
      treeId,
      userId: normalizedUser,
      identityId: selfIdentity?.id || null,
      name: String(profile.name || user.profile?.displayName || "").trim(),
      gender: String(profile.gender || "unknown"),
      birthDate: profile.birthDate || null,
      isAlive: true,
      createdAt: now,
      updatedAt: now,
      creatorId: normalizedUser,
    };
    db.persons = db.persons || [];
    db.persons.push(selfPerson);

    // Create relatives + relations.
    const relatives = Array.isArray(payload?.relatives) ? payload.relatives : [];
    const createdPersonIds = [selfPerson.id];
    db.relations = db.relations || [];
    for (const rel of relatives) {
      const relativeId = crypto.randomUUID();
      const relativePerson = {
        id: relativeId,
        treeId,
        userId: null,
        identityId: null, // No identity-matching during wizard (Q9).
        name: String(rel.name || "").trim(),
        gender: String(rel.gender || "unknown"),
        birthDate: rel.birthDate || null,
        isAlive: true,
        createdAt: now,
        updatedAt: now,
        creatorId: normalizedUser,
      };
      db.persons.push(relativePerson);
      createdPersonIds.push(relativeId);

      // Encode relation per relationToMe (relative → self).
      const relationToMe = String(rel.relationToMe || "other");
      const relationPair = this._inferRelationPair(relationToMe);
      if (relationPair) {
        db.relations.push({
          id: crypto.randomUUID(),
          treeId,
          person1Id: relativeId,
          person2Id: selfPerson.id,
          relation1to2: relationPair.relativeToSelf,
          relation2to1: relationPair.selfToRelative,
          isConfirmed: true,
          createdAt: now,
          createdBy: normalizedUser,
        });
      }
    }

    // Persist onboarding state.
    db.onboardingStates = db.onboardingStates || [];
    const stateIndex = db.onboardingStates.findIndex(
      (s) => s.userId === normalizedUser,
    );
    const state = {
      userId: normalizedUser,
      completed: true,
      currentStep: "done",
      treeId,
      personIds: createdPersonIds,
      completedAt: now,
      updatedAt: now,
    };
    if (stateIndex >= 0) {
      db.onboardingStates[stateIndex] = state;
    } else {
      db.onboardingStates.push(state);
    }

    await this._write(db);
    // Write-through: seedOnboarding записывает финальное состояние
    // wizard'а (`completed: true`) через собственный code path, не
    // через `updateOnboardingState`. Без явной синхронизации
    // hasIncompleteOnboarding после login возвращает stale `true`
    // (regression caught by auth-onboarding-redirect.test.js
    // "login after seed completes → requiresOnboarding=false").
    // Идемпотентный early-return выше cache не трогает — он опирается
    // на уже кэшированное `false` от предыдущего seed.
    this._onboardingIncompleteCache.set(normalizedUser, false);
    return {treeId, personIds: createdPersonIds, idempotent: false};
  },

  // SPEED-12: readSharedSnapshot() — чистый lookup, ничего не пишет.
  async getOnboardingState({userId}) {
    const normalizedUser = normalizeNullableString(userId);
    if (!normalizedUser) return null;
    const db = await this.readSharedSnapshot();
    const state = (db.onboardingStates || []).find(
      (s) => s.userId === normalizedUser,
    );
    if (!state) {
      return {
        userId: normalizedUser,
        completed: false,
        currentStep: "welcome",
        treeId: null,
        personIds: [],
        // Ship Q1: skipped state default false. Field added for
        // mama-unblock — user может попросить «Пропустить» wizard,
        // backend marks skipped=true чтобы `hasIncompleteOnboarding`
        // returns false (session.requiresOnboarding=false → no
        // forced redirect). Wizard остаётся resumable.
        skipped: false,
        skippedAt: null,
      };
    }
    // Backward-compat: existing pre-Q1 records без skipped field —
    // default к false без mutating storage.
    return {
      ...structuredClone(state),
      skipped: state.skipped === true,
      skippedAt: state.skippedAt ?? null,
    };
  },

  /// Phase 6 chunk 4a: distinguishes «mid-wizard user» from «legacy
  /// user без onboarding record». Returns true ТОЛЬКО для existing
  /// `onboardingStates` row с `completed=false`. Legacy users
  /// (no record) → false (existing tree → no redirect).
  ///
  /// `getOnboardingState` нельзя re-use потому что он fills default
  /// `{completed: false}` для missing records — would incorrectly
  /// flag every legacy user as needing wizard.
  async hasIncompleteOnboarding({userId}) {
    const normalizedUser = normalizeNullableString(userId);
    if (!normalizedUser) return false;
    // Cached lookup keeps `/v1/auth/session` на cache-only hot path.
    // Endpoint вызывается клиентом на каждом router-tick'е; лишний
    // `_read` нарушает invariant api.test.js:13345 «auth session
    // endpoint can serve from cached auth context». Cache is
    // write-through через `updateOnboardingState` и invalidated в
    // `_forgetUser`; cache miss → fall back to `_read` (legacy users
    // ИЛИ users существовавшие ДО первого reader'а, например после
    // restart процесса).
    const cached = this._onboardingIncompleteCache.get(normalizedUser);
    if (cached !== undefined) {
      return cached;
    }
    const db = await this._read();
    const state = (db.onboardingStates || []).find(
      (s) => s.userId === normalizedUser,
    );
    // Ship Q1: skipped users treated как «not requiring onboarding»
    // (session.requiresOnboarding=false). Wizard accessible via direct
    // nav (banner CTA на home), но не блокирует main app navigation.
    // Без этого мама stuck в wizard — issue #1 reported 2026-05-25.
    const result = state
      ? state.completed !== true && state.skipped !== true
      : false;
    this._onboardingIncompleteCache.set(normalizedUser, result);
    return result;
  },

  async updateOnboardingState({userId, currentStep}) {
    const normalizedUser = normalizeNullableString(userId);
    const normalizedStep = String(currentStep || "").trim();
    const validSteps = ["welcome", "profile", "relatives", "finish", "done"];
    if (!normalizedUser || !validSteps.includes(normalizedStep)) {
      return null;
    }
    const db = await this._read();
    db.onboardingStates = db.onboardingStates || [];
    const idx = db.onboardingStates.findIndex(
      (s) => s.userId === normalizedUser,
    );
    const now = nowIso();
    if (idx >= 0) {
      db.onboardingStates[idx].currentStep = normalizedStep;
      db.onboardingStates[idx].updatedAt = now;
      if (normalizedStep === "done") {
        db.onboardingStates[idx].completed = true;
        // Ship Q1: completion overrides skip — wizard finished, clear
        // skipped flag чтобы state semantics consistent (skipped=true
        // означает «I haven't done wizard yet, deferred»; completed=true
        // implies wizard finished, regardless of prior skip).
        db.onboardingStates[idx].skipped = false;
        db.onboardingStates[idx].skippedAt = null;
      }
    } else {
      db.onboardingStates.push({
        userId: normalizedUser,
        completed: normalizedStep === "done",
        currentStep: normalizedStep,
        treeId: null,
        personIds: [],
        updatedAt: now,
        skipped: false,
        skippedAt: null,
      });
    }
    await this._write(db);
    const persisted = db.onboardingStates.find(
      (s) => s.userId === normalizedUser,
    );
    // Write-through: keep `_onboardingIncompleteCache` consistent с
    // нового состояния (см. комментарий в `hasIncompleteOnboarding`).
    this._onboardingIncompleteCache.set(
      normalizedUser,
      persisted.completed !== true && persisted.skipped !== true,
    );
    return structuredClone(persisted);
  },

  /// Ship Q1 (2026-05-25): user explicitly defers wizard. Sets
  /// skipped=true, skippedAt=now atomically. Idempotent — re-calling
  /// no-ops если already skipped. completed=true takes precedence
  /// (skipping after completion = no-op, completion stays).
  ///
  /// Effect: `hasIncompleteOnboarding` returns false → session
  /// .requiresOnboarding=false → main app accessible. Wizard
  /// resumable via direct nav (home banner CTA).
  async skipOnboardingState({userId}) {
    const normalizedUser = normalizeNullableString(userId);
    if (!normalizedUser) return null;
    const db = await this._read();
    db.onboardingStates = db.onboardingStates || [];
    const idx = db.onboardingStates.findIndex(
      (s) => s.userId === normalizedUser,
    );
    const now = nowIso();
    let state;
    if (idx >= 0) {
      // No-op если уже completed (completion takes precedence)
      if (db.onboardingStates[idx].completed === true) {
        state = db.onboardingStates[idx];
      } else {
        if (db.onboardingStates[idx].skipped !== true) {
          db.onboardingStates[idx].skipped = true;
          db.onboardingStates[idx].skippedAt = now;
          db.onboardingStates[idx].updatedAt = now;
          await this._write(db);
        }
        state = db.onboardingStates[idx];
      }
    } else {
      // No prior record — create one с skipped=true, step=welcome
      state = {
        userId: normalizedUser,
        completed: false,
        currentStep: "welcome",
        treeId: null,
        personIds: [],
        updatedAt: now,
        skipped: true,
        skippedAt: now,
      };
      db.onboardingStates.push(state);
      await this._write(db);
    }
    this._onboardingIncompleteCache.set(
      normalizedUser,
      state.completed !== true && state.skipped !== true,
    );
    return structuredClone(state);
  },

  /// On-read expiry mutation — sweeps pending → expired когда now >
  /// expiresAt. Notifications dispatched at endpoint layer (store
  /// returns ids of newly-expired для caller to notify).
  _sweepExpiredKinshipChecks(db) {
    const now = Date.now();
    const newlyExpired = [];
    for (const check of db.kinshipChecks || []) {
      if (check.status !== "pending") continue;
      const expiresAt = new Date(check.expiresAt || 0).getTime();
      if (Number.isFinite(expiresAt) && now > expiresAt) {
        check.status = "expired";
        check.expiredAt = nowIso();
        newlyExpired.push(check.id);
      }
    }
    return newlyExpired;
  },

  async createKinshipCheck({initiatorUserId, targetUserId}) {
    const normalizedInitiator = normalizeNullableString(initiatorUserId);
    const normalizedTarget = normalizeNullableString(targetUserId);
    if (!normalizedInitiator || !normalizedTarget) {
      return {error: "INVALID_INPUT"};
    }
    if (normalizedInitiator === normalizedTarget) {
      return {error: "SELF_CHECK_FORBIDDEN"};
    }
    const db = await this._read();
    const targetUser = db.users.find((u) => u.id === normalizedTarget);
    if (!targetUser) return {error: "TARGET_NOT_FOUND"};

    // Lazy expiry sweep before duplicate/cooldown checks.
    this._sweepExpiredKinshipChecks(db);

    // Idempotency: same pending pair → return existing.
    const existingPending = (db.kinshipChecks || []).find(
      (c) =>
        c.initiatorUserId === normalizedInitiator &&
        c.targetUserId === normalizedTarget &&
        c.status === "pending",
    );
    if (existingPending) {
      await this._write(db); // persist sweep results
      return {check: structuredClone(existingPending), created: false};
    }

    // Anti-harassment: 30d cooldown after rejection.
    const lastRejected = (db.kinshipChecks || [])
      .filter(
        (c) =>
          c.initiatorUserId === normalizedInitiator &&
          c.targetUserId === normalizedTarget &&
          c.status === "rejected",
      )
      .sort(
        (a, b) =>
          new Date(b.respondedAt || 0).getTime() -
          new Date(a.respondedAt || 0).getTime(),
      )[0];
    if (lastRejected) {
      const elapsed =
        Date.now() - new Date(lastRejected.respondedAt || 0).getTime();
      if (elapsed < KINSHIP_REJECTION_COOLDOWN_MS) {
        return {
          error: "REJECTION_COOLDOWN",
          retryAfterMs: KINSHIP_REJECTION_COOLDOWN_MS - elapsed,
        };
      }
    }

    const now = nowIso();
    const check = {
      id: crypto.randomUUID(),
      initiatorUserId: normalizedInitiator,
      targetUserId: normalizedTarget,
      status: "pending",
      createdAt: now,
      expiresAt: new Date(
        Date.now() + KINSHIP_CHECK_TTL_MS,
      ).toISOString(),
      respondedAt: null,
      expiredAt: null,
      // Phase 6.5: initiator revocation timestamp. Stays null до
      // initiator вызывает /v1/kinship-checks/:id/revoke.
      revokedAt: null,
      result: null,
    };
    db.kinshipChecks = db.kinshipChecks || [];
    db.kinshipChecks.push(check);
    await this._write(db);
    return {check: structuredClone(check), created: true};
  },

  async findKinshipCheck({checkId}) {
    const normalizedId = normalizeNullableString(checkId);
    if (!normalizedId) return null;
    const db = await this._read();
    const newlyExpired = this._sweepExpiredKinshipChecks(db);
    if (newlyExpired.length > 0) {
      await this._write(db);
    }
    const check = (db.kinshipChecks || []).find((c) => c.id === normalizedId);
    if (!check) return null;
    return structuredClone(check);
  },

  /// Respond to pending check. Decision ∈ {'accepted','rejected'}.
  /// On accept — compute BFS via findBloodRelation(maxDepth=4) +
  /// store result. On reject — mark rejected.
  /// Permission: only target can respond. Caller must verify
  /// req.auth.user.id === check.targetUserId.
  async respondToKinshipCheck({checkId, decision}) {
    const normalizedId = normalizeNullableString(checkId);
    const normalizedDecision = String(decision || "").trim();
    if (!normalizedId || !["accepted", "rejected"].includes(normalizedDecision)) {
      return {error: "INVALID_INPUT"};
    }
    const db = await this._read();
    this._sweepExpiredKinshipChecks(db);
    const check = (db.kinshipChecks || []).find((c) => c.id === normalizedId);
    if (!check) return {error: "NOT_FOUND"};
    if (check.status !== "pending") {
      return {error: "NOT_PENDING", currentStatus: check.status};
    }

    const now = nowIso();
    check.status = normalizedDecision;
    check.respondedAt = now;

    if (normalizedDecision === "accepted") {
      // Compute BFS на 4 hops cap (Q10 decision).
      const initiatorSelfId = this._selfGraphPersonIdForUser(
        db,
        check.initiatorUserId,
      );
      const targetSelfId = this._selfGraphPersonIdForUser(
        db,
        check.targetUserId,
      );
      if (!initiatorSelfId || !targetSelfId) {
        check.result = {found: false, label: "Не удалось определить связь", degree: 0};
      } else {
        const path = this._findBloodRelationBetween(
          db,
          initiatorSelfId,
          targetSelfId,
          {maxDepth: CONNECTED_VISIBILITY_MAX_HOPS},
        );
        if (path === null) {
          check.result = {
            found: false,
            label: "Связь не найдена",
            degree: 0,
            chain: [],
            edges: [],
          };
        } else {
          check.result = {
            found: true,
            label: path.label,
            degree: path.degree,
            chain: path.chain,
            edges: path.edges,
          };
        }
      }
    }

    await this._write(db);
    return {check: structuredClone(check)};
  },

  /// Phase 6.5: initiator revokes own pending request. Permission:
  /// only initiator. Pre-condition: status === "pending". State
  /// transition: pending → revoked (final). On success — caller
  /// (route handler) dispatches `kinship_check_revoked` notification
  /// к target.
  ///
  /// Errors: INVALID_INPUT, NOT_FOUND, NOT_INITIATOR, NOT_PENDING.
  /// Re-revoke (status='revoked') returns NOT_PENDING с
  /// currentStatus='revoked' — guards против double notification
  /// dispatch при network retry.
  async revokeKinshipCheck({checkId, initiatorUserId}) {
    const normalizedId = normalizeNullableString(checkId);
    const normalizedInitiator = normalizeNullableString(initiatorUserId);
    if (!normalizedId || !normalizedInitiator) {
      return {error: "INVALID_INPUT"};
    }
    const db = await this._read();
    this._sweepExpiredKinshipChecks(db);
    const check = (db.kinshipChecks || []).find((c) => c.id === normalizedId);
    if (!check) return {error: "NOT_FOUND"};
    if (check.initiatorUserId !== normalizedInitiator) {
      return {error: "NOT_INITIATOR"};
    }
    if (check.status !== "pending") {
      return {error: "NOT_PENDING", currentStatus: check.status};
    }

    const now = nowIso();
    check.status = "revoked";
    check.revokedAt = now;

    await this._write(db);
    return {check: structuredClone(check)};
  },

  // Pure in-memory — safe inside _mutate's applyFn (no nested store calls).
  // Transitions pending→expired past `expiresAt`, THEN separately claims
  // one-shot notify duty for any expired-but-not-yet-notified request
  // (covers both a fresh transition above and a prior crash that persisted
  // status=expired but died before the caller dispatched the notification).
  // Returns the claimed requests (route dispatches `story_request_expired`
  // for each) — mutates `expiredNotifiedAt` atomically so the claim can
  // never be taken twice.
  _sweepExpiredStoryRequests(db) {
    const now = Date.now();
    const toNotify = [];
    for (const request of db.storyRequests || []) {
      if (request.status === "pending") {
        const expiresAt = new Date(request.expiresAt || 0).getTime();
        if (Number.isFinite(expiresAt) && now > expiresAt) {
          request.status = "expired";
          request.updatedAt = nowIso();
        }
      }
      if (request.status === "expired" && !request.expiredNotifiedAt) {
        request.expiredNotifiedAt = nowIso();
        toNotify.push(request);
      }
    }
    return toNotify;
  },

  /// Create a pending story request. Cheap shape validation happens
  /// BEFORE touching the DB (mirrors createKinshipCheck) so a malformed
  /// call never enters the _mutate queue. DB-dependent checks (person/
  /// tree exist, target membership, duplicate, rate-limit) run inside
  /// _mutate against a fresh read.
  ///
  /// Errors: INVALID_INPUT, SELF_REQUEST_FORBIDDEN, INVALID_QUESTION,
  /// PERSON_NOT_FOUND, TARGET_NOT_IN_TREE, DUPLICATE_PENDING,
  /// TOO_MANY_PENDING. Route layer separately gates edit permission via
  /// requireGraphPersonEdit BEFORE calling this (§1: "инициатор обязан
  /// иметь право редактировать персону").
  async createStoryRequest({treeId, personId, requesterUserId, targetUserId, question}) {
    const normalizedTreeId = normalizeNullableString(treeId);
    const normalizedPersonId = normalizeNullableString(personId);
    const normalizedRequester = normalizeNullableString(requesterUserId);
    const normalizedTarget = normalizeNullableString(targetUserId);
    if (!normalizedTreeId || !normalizedPersonId || !normalizedRequester || !normalizedTarget) {
      return {error: "INVALID_INPUT"};
    }
    if (normalizedRequester === normalizedTarget) {
      return {error: "SELF_REQUEST_FORBIDDEN"};
    }
    const questionText = String(question?.text || "").trim();
    if (questionText.length < 3 || questionText.length > 500) {
      return {error: "INVALID_QUESTION"};
    }
    const themeKey = normalizeNullableString(question?.themeKey);
    const sourceQuestionId = normalizeNullableString(question?.sourceQuestionId);
    // Дубль — это ТОТ ЖЕ вопрос той же паре про того же человека, а не любой
    // открытый вопрос к ней: два разных вопроса бабушке за один вечер —
    // нормальный сценарий, от спама защищает лимит открытых (TOO_MANY_PENDING).
    const questionKey = questionText.toLowerCase().replace(/\s+/g, " ");

    return this._mutate((db, skip) => {
      const newlyExpired = this._sweepExpiredStoryRequests(db);
      // Bundles a validation failure with whatever the sweep above did —
      // skip() (no persist) only when NOTHING changed; otherwise the sweep's
      // transitions/notify-claims still need to land even though THIS call
      // is rejected.
      const fail = (error) => {
        const payload = {
          error,
          newlyExpired: newlyExpired.map((r) => structuredClone(r)),
        };
        return newlyExpired.length > 0 ? payload : skip(payload);
      };

      const tree = (db.trees || []).find((t) => t.id === normalizedTreeId);
      const person = this._findPersonRecordById(db, normalizedPersonId);
      if (!tree || !person || person.treeId !== normalizedTreeId) {
        return fail("PERSON_NOT_FOUND");
      }
      if (!this._isUserInTreeOrSemya(db, tree, normalizedTarget)) {
        return fail("TARGET_NOT_IN_TREE");
      }

      db.storyRequests = db.storyRequests || [];
      const duplicate = db.storyRequests.find(
        (r) =>
          r.treeId === normalizedTreeId &&
          r.personId === normalizedPersonId &&
          r.requesterUserId === normalizedRequester &&
          r.targetUserId === normalizedTarget &&
          r.status === "pending" &&
          String(r.question?.text || "").toLowerCase().replace(/\s+/g, " ") === questionKey,
      );
      if (duplicate) {
        return fail("DUPLICATE_PENDING");
      }
      const pendingCount = db.storyRequests.filter(
        (r) => r.requesterUserId === normalizedRequester && r.status === "pending",
      ).length;
      if (pendingCount >= STORY_REQUEST_MAX_PENDING_PER_INITIATOR) {
        return fail("TOO_MANY_PENDING");
      }

      const now = nowIso();
      const request = {
        id: `sreq_${crypto.randomUUID()}`,
        treeId: normalizedTreeId,
        personId: normalizedPersonId,
        requesterUserId: normalizedRequester,
        targetUserId: normalizedTarget,
        question: {text: questionText, themeKey, sourceQuestionId},
        status: "pending",
        answer: null,
        createdAt: now,
        updatedAt: now,
        expiresAt: new Date(Date.now() + STORY_REQUEST_TTL_MS).toISOString(),
        respondedAt: null,
        // One-shot guard for the lazy-expiry notification — see
        // _sweepExpiredStoryRequests.
        expiredNotifiedAt: null,
      };
      db.storyRequests.push(request);
      return {
        request: structuredClone(request),
        newlyExpired: newlyExpired.map((r) => structuredClone(r)),
      };
    });
  },

  /// Visible ONLY to the requester or the target — returns request: null
  /// for both "not found" and "found but not yours" (indistinguishable on
  /// purpose: a third tree member must not learn a request between two
  /// other members even exists).
  async findStoryRequest({requestId, viewerUserId}) {
    const normalizedId = normalizeNullableString(requestId);
    const normalizedViewer = normalizeNullableString(viewerUserId);
    if (!normalizedId || !normalizedViewer) {
      return {request: null, newlyExpired: []};
    }
    return this._mutate((db, skip) => {
      const newlyExpired = this._sweepExpiredStoryRequests(db);
      const request = (db.storyRequests || []).find((r) => r.id === normalizedId);
      const visible =
        request &&
        (request.requesterUserId === normalizedViewer || request.targetUserId === normalizedViewer);
      const result = {
        request: visible ? structuredClone(request) : null,
        newlyExpired: newlyExpired.map((r) => structuredClone(r)),
      };
      return newlyExpired.length > 0 ? result : skip(result);
    });
  },

  /// Target answers a pending request: appends a block to the hero's
  /// article AND flips the request to 'answered' in the SAME _mutate
  /// transaction (no nested store calls — inlines the equivalent of
  /// appendArticleBlock's body using the same pure helpers it uses:
  /// _resolveArticleContext / _ensureProfileArticle / createArticleBlockRecord).
  ///
  /// Permission note (§1, deliberate): the REQUESTER needed edit rights on
  /// the person at creation time (checked at the route layer); the TARGET
  /// does NOT need their own edit grant to answer — the pending request
  /// itself IS the one-time permission slip Артём approved to write this
  /// one block. Don't add a requireGraphPersonEdit check here for the
  /// target; that would break the whole feature for anonymous-card /
  /// no-grant addressees the request is specifically meant to reach.
  ///
  /// Errors: INVALID_INPUT, NOT_FOUND, NOT_TARGET, NOT_PENDING, INVALID_ANSWER.
  async answerStoryRequest({requestId, actorUserId, answer}) {
    const normalizedId = normalizeNullableString(requestId);
    const normalizedActor = normalizeNullableString(actorUserId);
    if (!normalizedId || !normalizedActor) {
      return {error: "INVALID_INPUT"};
    }
    const kind = String(answer?.kind || "").trim();
    if (!["audio", "text", "photo"].includes(kind)) {
      return {error: "INVALID_ANSWER"};
    }

    return this._mutate((db, skip) => {
      const newlyExpired = this._sweepExpiredStoryRequests(db);
      const fail = (error) => {
        const payload = {
          error,
          newlyExpired: newlyExpired.map((r) => structuredClone(r)),
        };
        return newlyExpired.length > 0 ? payload : skip(payload);
      };

      const request = (db.storyRequests || []).find((r) => r.id === normalizedId);
      if (!request) return fail("NOT_FOUND");
      if (request.targetUserId !== normalizedActor) return fail("NOT_TARGET");
      if (request.status !== "pending") return fail("NOT_PENDING");

      const tree = (db.trees || []).find((t) => t.id === request.treeId);
      const heroPerson = this._findPersonRecordById(db, request.personId);
      if (!tree || !heroPerson || heroPerson.treeId !== request.treeId) {
        return fail("NOT_FOUND");
      }
      if (!this._isUserInTreeOrSemya(db, tree, normalizedActor)) {
        return fail("FORBIDDEN_NOT_MEMBER");
      }
      const isBlockedPair = (db.userBlocks || []).some(
        (b) =>
          (b.blockerId === request.requesterUserId && b.blockedId === normalizedActor) ||
          (b.blockerId === normalizedActor && b.blockedId === request.requesterUserId),
      );
      if (isBlockedPair) {
        return fail("FORBIDDEN_BLOCKED");
      }

      // Map the answer's wire shape → an article block type/content. MVP-1
      // decision §0.3/§0.4: audio stores no transcript (речь не
      // расшифровывается), video is out of scope (no `video` block type
      // exists yet — don't add one here).
      let blockType;
      let blockContent;
      if (kind === "audio") {
        const url = normalizeNullableString(answer?.mediaUrl);
        if (!url || !enforceSafeMediaOrLinkUrl(url, {allowEmpty: false}).ok) {
          return fail("INVALID_ANSWER");
        }
        const duration = Number(answer?.durationSec);
        if (Number.isFinite(duration) && (duration < 0 || duration > 36000)) {
          return fail("INVALID_ANSWER");
        }
        blockType = "audio";
        blockContent = {url, durationSec: answer?.durationSec, transcript: null};
      } else if (kind === "text") {
        const text = String(answer?.text || "").trim();
        if (!text || text.length > 20000) return fail("INVALID_ANSWER");
        blockType = "paragraph";
        blockContent = {spans: [text]};
      } else {
        const url = normalizeNullableString(answer?.mediaUrl);
        const caption = normalizeNullableString(answer?.caption);
        if (
          !url ||
          !enforceSafeMediaOrLinkUrl(url, {allowEmpty: false}).ok ||
          (caption && caption.length > 1000)
        ) {
          return fail("INVALID_ANSWER");
        }
        blockType = "photo";
        blockContent = {url, caption};
      }

      let block;
      let ctx;
      try {
        ctx = this._resolveArticleContext(db, request.personId);
        block = createArticleBlockRecord({
          type: blockType,
          content: blockContent,
          actorUserId: normalizedActor,
        });
      } catch (error) {
        if (error?.message === "PERSON_NOT_FOUND") return fail("NOT_FOUND");
        return fail("INVALID_ANSWER");
      }
      // Additive, sits NEXT TO `content` (not inside it) — §1: normalizeArticleBlockContent
      // stays untouched, existing blocks without `source` are unaffected.
      // Lets the «Истории» section sign the block «На вопрос {Имя}, {дата}».
      block.source = {
        requestId: request.id,
        question: structuredClone(request.question),
        askedByUserId: request.requesterUserId,
        askedAt: request.createdAt,
      };

      const article = this._ensureProfileArticle(db, request.personId, ctx);
      article.blocks.push(block);
      article.updatedAt = block.createdAt;
      this._appendTreeChangeRecord(db, {
        treeId: ctx.treeId,
        actorId: normalizedActor,
        type: "article.block-added",
        personId: request.personId,
        details: {blockId: block.id, blockType: block.type, storyRequestId: request.id},
      });

      const now = nowIso();
      request.status = "answered";
      request.answer = {
        articleBlockId: block.id,
        kind,
        answeredByUserId: normalizedActor,
        answeredAt: now,
      };
      request.respondedAt = now;
      request.updatedAt = now;

      return {
        request: structuredClone(request),
        block: structuredClone(block),
        newlyExpired: newlyExpired.map((r) => structuredClone(r)),
      };
    });
  },

  /// Target declines a pending request. Errors: INVALID_INPUT, NOT_FOUND,
  /// NOT_TARGET, NOT_PENDING.
  async declineStoryRequest({requestId, actorUserId}) {
    const normalizedId = normalizeNullableString(requestId);
    const normalizedActor = normalizeNullableString(actorUserId);
    if (!normalizedId || !normalizedActor) {
      return {error: "INVALID_INPUT"};
    }
    return this._mutate((db, skip) => {
      const newlyExpired = this._sweepExpiredStoryRequests(db);
      const fail = (error) => {
        const payload = {
          error,
          newlyExpired: newlyExpired.map((r) => structuredClone(r)),
        };
        return newlyExpired.length > 0 ? payload : skip(payload);
      };
      const request = (db.storyRequests || []).find((r) => r.id === normalizedId);
      if (!request) return fail("NOT_FOUND");
      if (request.targetUserId !== normalizedActor) return fail("NOT_TARGET");
      if (request.status !== "pending") return fail("NOT_PENDING");

      const now = nowIso();
      request.status = "declined";
      request.respondedAt = now;
      request.updatedAt = now;
      return {
        request: structuredClone(request),
        newlyExpired: newlyExpired.map((r) => structuredClone(r)),
      };
    });
  },

  /// Initiator revokes own pending request. Errors: INVALID_INPUT,
  /// NOT_FOUND, NOT_INITIATOR, NOT_PENDING. Deliberately does NOT set
  /// `respondedAt` — that field means "the addressee acted"; a revoke is
  /// the initiator's own action, so only `updatedAt` moves.
  async revokeStoryRequest({requestId, actorUserId}) {
    const normalizedId = normalizeNullableString(requestId);
    const normalizedActor = normalizeNullableString(actorUserId);
    if (!normalizedId || !normalizedActor) {
      return {error: "INVALID_INPUT"};
    }
    return this._mutate((db, skip) => {
      const newlyExpired = this._sweepExpiredStoryRequests(db);
      const fail = (error) => {
        const payload = {
          error,
          newlyExpired: newlyExpired.map((r) => structuredClone(r)),
        };
        return newlyExpired.length > 0 ? payload : skip(payload);
      };
      const request = (db.storyRequests || []).find((r) => r.id === normalizedId);
      if (!request) return fail("NOT_FOUND");
      if (request.requesterUserId !== normalizedActor) return fail("NOT_INITIATOR");
      if (request.status !== "pending") return fail("NOT_PENDING");

      request.status = "revoked";
      request.updatedAt = nowIso();
      return {
        request: structuredClone(request),
        newlyExpired: newlyExpired.map((r) => structuredClone(r)),
      };
    });
  },
};
