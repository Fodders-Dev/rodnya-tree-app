const path = require("node:path");
const crypto = require("node:crypto");
const {
  CONNECTED_VISIBILITY_MAX_HOPS,
  LOGIN_LOCKOUT_DURATION_MS,
  MAX_LOGIN_FAILURES_BEFORE_LOCKOUT,
  PASSWORD_RESET_MIN_ISSUE_INTERVAL_MS,
  PASSWORD_RESET_TOKEN_TTL_MS,
  SENSITIVE_ATTRIBUTE_FIELDS,
  SESSION_TOUCH_MIN_INTERVAL_MS,
} = require("../constants");
const {
  applyCanonicalProfileToPerson,
  buildAutoCircleSpecsForTree,
  buildCanonicalPersonView,
  cloneUserWithAuthState,
  collectOwnedMediaUrlsForUser,
  composeDisplayNameFromProfile,
  createAuthHandoffRecord,
  createPasswordAuthIdentity,
  createProfileNote,
  deriveProviderIdsForUser,
  deriveSessionPublicId,
  dummyVerifyForTimingParity,
  ensureChatPins,
  ensureCirclesForTree,
  hashPassword,
  hashPasswordAsync,
  isCallTerminalState,
  isExpiredAt,
  listAuthIdentitiesForUser,
  normalizeAuthIdentityRecord,
  normalizeCallMetrics,
  normalizeCallSession,
  normalizeCallSessionMap,
  normalizeJoinedSessionMap,
  normalizeNullableString,
  normalizeOptionalString,
  normalizeParticipantIds,
  normalizePhoneNumber,
  normalizePrimaryTrustedChannel,
  normalizeProfileContributionFields,
  normalizeProfileContributionPolicy,
  normalizeSessionDeviceContext,
  normalizeStoredCall,
  nowIso,
  verifyPasswordAsync,
} = require("../helpers");

module.exports = {
  async createUser({
    email,
    password = null,
    displayName,
    authIdentity = null,
    photoUrl = null,
    // Согласие при регистрации: версия документов, которую пользователь
    // принял чекбоксом (аддитивно — старые клиенты не шлют, поле null).
    consentDocVersion = null,
  }) {
    const db = await this._read();
    const normalizedEmail = String(email || "").trim().toLowerCase();

    if (db.users.some((user) => user.email === normalizedEmail)) {
      throw new Error("EMAIL_ALREADY_EXISTS");
    }

    const createdAt = nowIso();
    const hasPassword = typeof password === "string" && password.length > 0;
    const passwordCredentials = hasPassword ? hashPassword(password) : null;
    const userId = crypto.randomUUID();

    const nameParts = String(displayName || "")
      .trim()
      .split(/\s+/)
      .filter(Boolean);
    const authIdentities = [];
    if (hasPassword) {
      const passwordAuthIdentity = createPasswordAuthIdentity(
        normalizedEmail,
        createdAt,
      );
      if (passwordAuthIdentity) {
        authIdentities.push(passwordAuthIdentity);
      }
    }

    const normalizedAuthIdentity = normalizeAuthIdentityRecord(authIdentity);
    if (normalizedAuthIdentity) {
      authIdentities.push(normalizedAuthIdentity);
    }

    const normalizedConsentVersion =
      normalizeNullableString(consentDocVersion);
    const user = {
      id: userId,
      identityId: null,
      email: normalizedEmail,
      passwordHash: passwordCredentials?.passwordHash || null,
      passwordSalt: passwordCredentials?.salt || null,
      providerIds: [],
      authIdentities,
      createdAt,
      updatedAt: createdAt,
      // Факт согласия с Соглашением/ПДн: когда и какая версия документов.
      consentAt: normalizedConsentVersion ? createdAt : null,
      consentDocVersion: normalizedConsentVersion,
      profile: {
        id: userId,
        email: normalizedEmail,
        displayName: String(displayName || "").trim(),
        firstName: nameParts[0] || "",
        lastName: nameParts.length > 1 ? nameParts[nameParts.length - 1] : "",
        middleName:
          nameParts.length > 2 ? nameParts.slice(1, -1).join(" ") : "",
        username: "",
        phoneNumber: "",
        normalizedPhoneNumber: null,
        countryCode: null,
        countryName: null,
        city: "",
        photoUrl: String(photoUrl || "").trim() || null,
        gender: "unknown",
        maidenName: "",
        birthDate: null,
        birthPlace: null,
        bio: "",
        familyStatus: "",
        aboutFamily: "",
        education: "",
        work: "",
        hometown: "",
        languages: "",
        values: "",
        religion: "",
        interests: "",
        profileContributionPolicy: "suggestions",
        primaryTrustedChannel: normalizePrimaryTrustedChannel(
          normalizedAuthIdentity?.provider,
        ),
        createdAt,
        updatedAt: createdAt,
      },
      profileNotes: [],
    };
    user.providerIds = deriveProviderIdsForUser(user);

    db.users.push(user);
    await this._write(db);
    this._rememberUser(user);
    return cloneUserWithAuthState(user);
  },

  async authenticate(email, password) {
    const db = await this._read();
    const normalizedEmail = String(email || "").trim().toLowerCase();
    const user = db.users.find((entry) => entry.email === normalizedEmail);

    // Always run a real scrypt+timingSafeEqual hop. If the user
    // doesn't exist, run it against a dummy salt so the response
    // takes the same wall-clock time as a real verify — closes the
    // user-enumeration timing oracle. If the user exists, run the
    // real async verify on the libuv thread pool so the event loop
    // stays responsive under concurrent logins (the previous
    // synchronous scrypt blocked for ~150 ms per request).
    if (!user) {
      await dummyVerifyForTimingParity(String(password || ""));
      return null;
    }

    // ── Per-account lockout check ────────────────────────────────
    // Rejected before we even compute the hash, so a locked account
    // can't be used as a CPU sink either. We still run the dummy
    // verify so the wall-clock matches the unknown-email branch
    // and an attacker can't tell "locked" from "not registered" by
    // timing.
    const lockedUntil = user.lockedUntil
        ? Date.parse(user.lockedUntil)
        : null;
    if (lockedUntil && Number.isFinite(lockedUntil) && lockedUntil > Date.now()) {
      await dummyVerifyForTimingParity(String(password || ""));
      return null;
    }

    const isValid = await verifyPasswordAsync(password, user);
    if (!isValid) {
      // Bump failure counter and persist. If we've crossed the
      // threshold, set lockedUntil so the next attempt short-circuits.
      const nextCount = (Number(user.failedLoginCount) || 0) + 1;
      const updates = {failedLoginCount: nextCount};
      if (nextCount >= MAX_LOGIN_FAILURES_BEFORE_LOCKOUT) {
        const unlockAt = Date.now() + LOGIN_LOCKOUT_DURATION_MS;
        updates.lockedUntil = new Date(unlockAt).toISOString();
      }
      try {
        await this._persistAuthFailureState(user.id, updates);
      } catch (error) {
        // Persistence is best-effort — never fail the auth response
        // because the failure counter couldn't be written. The
        // attacker still doesn't get in; we just lose one increment.
        console.error(
          "[backend] failed to persist login-failure state",
          JSON.stringify({userId: user.id, message: error?.message}),
        );
      }
      return null;
    }

    // Successful sign-in resets the failure state.
    if (user.failedLoginCount || user.lockedUntil) {
      try {
        await this._persistAuthFailureState(user.id, {
          failedLoginCount: 0,
          lockedUntil: null,
        });
      } catch (error) {
        // Reset is best-effort. Leaving a stale `lockedUntil` in the
        // past does no harm because the date check ignores expired
        // entries.
        console.error(
          "[backend] failed to clear login-failure state",
          JSON.stringify({userId: user.id, message: error?.message}),
        );
      }
    }

    this._rememberUser(user);
    return cloneUserWithAuthState(user);
  },

  /// Mark the user's last-seen timestamp. Called by the realtime hub when
  /// the user's last socket disconnects, so clients can render "был(а) N
  /// минут назад" in chat subtitles. Idempotent and resilient: errors
  /// don't propagate (the broadcast itself is more important than the
  /// timestamp persistence).
  async markUserSeenAt(userId, {when} = {}) {
    const normalizedUserId = String(userId || "").trim();
    if (!normalizedUserId) {
      return;
    }
    const timestamp =
      when instanceof Date ? when.toISOString() : when || nowIso();
    try {
      const updatedUser = await this._mutate((db, skip) => {
        const user = db.users.find((entry) => entry.id === normalizedUserId);
        if (!user) {
          return skip(null);
        }
        user.lastSeenAt = timestamp;
        return user;
      });
      if (updatedUser) {
        this._rememberUser(updatedUser);
      }
    } catch (_) {
      // Last-seen is a best-effort UX hint, not auth state.
    }
  },

  async findUserById(userId) {
    const normalizedUserId = String(userId || "").trim();
    if (!normalizedUserId) {
      return null;
    }
    const cachedUser = this._userCache.get(normalizedUserId);
    if (cachedUser) {
      return cloneUserWithAuthState(cachedUser);
    }
    const db = await this._read();
    const user = db.users.find((entry) => entry.id === normalizedUserId);
    if (user) {
      this._rememberUser(user);
    }
    return user ? cloneUserWithAuthState(user) : null;
  },

  async createSession(userId, deviceContext = {}) {
    const db = await this._read();
    const createdAt = nowIso();
    const token = crypto.randomBytes(32).toString("hex");
    const refreshToken = crypto.randomBytes(32).toString("hex");

    const userSessions = db.sessions.filter((s) => s.userId === userId);
    const otherSessions = db.sessions.filter((s) => s.userId !== userId);

    const normalizedDeviceContext = normalizeSessionDeviceContext(deviceContext);
    const incomingInstanceId = normalizedDeviceContext.instanceId;

    // If the same client instance re-authenticates, evict its previous session.
    // Otherwise keep last 5 sessions for this user.
    const supersededInstanceMatches = incomingInstanceId
      ? userSessions.filter((s) => s.instanceId === incomingInstanceId)
      : [];
    const remainingAfterInstanceMatch = incomingInstanceId
      ? userSessions.filter((s) => s.instanceId !== incomingInstanceId)
      : userSessions;

    const sessionsToKeep = remainingAfterInstanceMatch.slice(-4);
    const overflowEvicted = remainingAfterInstanceMatch.slice(
      0,
      Math.max(0, remainingAfterInstanceMatch.length - sessionsToKeep.length),
    );
    const evictedSessions = [...supersededInstanceMatches, ...overflowEvicted];

    const createdSession = {
      token,
      refreshToken,
      userId,
      createdAt,
      lastSeenAt: createdAt,
      ...normalizedDeviceContext,
    };

    db.sessions = [
      ...otherSessions,
      ...sessionsToKeep,
      createdSession,
    ];

    await this._write(db);
    for (const session of evictedSessions) {
      this._forgetSession(session?.token);
    }
    this._rememberSession(createdSession);
    return {
      token,
      refreshToken,
      session: structuredClone(createdSession),
      evictedTokens: evictedSessions
        .map((entry) => String(entry?.token || "").trim())
        .filter(Boolean),
    };
  },

  async listSessionsForUser(userId) {
    const normalizedUserId = String(userId || "").trim();
    if (!normalizedUserId) {
      return [];
    }
    const db = await this._read();
    return db.sessions
      .filter((entry) => entry.userId === normalizedUserId)
      .map((entry) => structuredClone(entry))
      .sort((left, right) => {
        const leftAt = String(left.lastSeenAt || left.createdAt || "");
        const rightAt = String(right.lastSeenAt || right.createdAt || "");
        return rightAt.localeCompare(leftAt);
      });
  },

  async findSessionByPublicId(userId, publicId) {
    const normalizedUserId = String(userId || "").trim();
    const normalizedPublicId = String(publicId || "").trim();
    if (!normalizedUserId || !normalizedPublicId) {
      return null;
    }
    const sessions = await this.listSessionsForUser(normalizedUserId);
    for (const session of sessions) {
      const candidate = deriveSessionPublicId(
        session.token,
        session.instanceId || "",
      );
      if (candidate === normalizedPublicId) {
        return session;
      }
    }
    return null;
  },

  async updateSessionMetadata(token, patch = {}) {
    const normalizedToken = String(token || "").trim();
    if (!normalizedToken) {
      return null;
    }
    const db = await this._read();
    const session = db.sessions.find((entry) => entry.token === normalizedToken);
    if (!session) {
      return null;
    }
    const allowedPatch = {};
    if (patch.deviceName !== undefined) {
      allowedPatch.deviceName = normalizeOptionalString(patch.deviceName, 80);
    }
    if (patch.platform !== undefined) {
      allowedPatch.platform = normalizeOptionalString(patch.platform, 40);
    }
    if (patch.osVersion !== undefined) {
      allowedPatch.osVersion = normalizeOptionalString(patch.osVersion, 40);
    }
    if (patch.appVersion !== undefined) {
      allowedPatch.appVersion = normalizeOptionalString(patch.appVersion, 40);
    }
    Object.assign(session, allowedPatch);
    await this._write(db);
    this._rememberSession(session);
    return structuredClone(session);
  },

  async findSessionByRefreshToken(refreshToken) {
    const db = await this._read();
    const session = db.sessions.find((entry) => entry.refreshToken === refreshToken);
    if (session) {
      this._rememberSession(session);
    }
    return session ? structuredClone(session) : null;
  },

  _cleanupExpiredPasswordResetTokens(db) {
    if (!Array.isArray(db.passwordResetTokens)) {
      db.passwordResetTokens = [];
      return false;
    }
    const beforeLength = db.passwordResetTokens.length;
    const nowMs = Date.now();
    db.passwordResetTokens = db.passwordResetTokens.filter((entry) => {
      const expiresMs = Date.parse(entry?.expiresAt || "");
      if (Number.isFinite(expiresMs) && expiresMs <= nowMs) {
        return false;
      }
      // Drop already-consumed tokens older than 1 hour — keep them
      // briefly for audit, then GC. We don't want a "consumed" row
      // pinning memory forever.
      if (entry?.consumedAt) {
        const consumedMs = Date.parse(entry.consumedAt);
        if (
          Number.isFinite(consumedMs) &&
          consumedMs + 60 * 60 * 1000 <= nowMs
        ) {
          return false;
        }
      }
      return true;
    });
    return db.passwordResetTokens.length !== beforeLength;
  },

  // Returns the plaintext token to embed in the reset URL. The
  // CALLER is responsible for getting it into the email and never
  // storing it elsewhere — once we return, the plaintext is gone
  // from the server.
  //
  // Returns null if the user is rate-limited (too many resets in
  // the last hour). Caller should still treat it as success to the
  // outside world — anti-enumeration.
  async issuePasswordResetToken(userId) {
    const db = await this._read();
    this._cleanupExpiredPasswordResetTokens(db);

    const normalizedUserId = normalizeNullableString(userId);
    if (!normalizedUserId) {
      return null;
    }
    const user = db.users.find((entry) => entry.id === normalizedUserId);
    if (!user) {
      return null;
    }

    const nowMs = Date.now();
    const recentForUser = db.passwordResetTokens.find((entry) => {
      if (entry.userId !== normalizedUserId) return false;
      if (entry.consumedAt) return false;
      const createdMs = Date.parse(entry.createdAt || "");
      if (!Number.isFinite(createdMs)) return false;
      return (
        nowMs - createdMs <
        PASSWORD_RESET_MIN_ISSUE_INTERVAL_MS
      );
    });
    if (recentForUser) {
      // Don't issue a new token — the one we already sent within
      // the last hour is still valid. Returning null here lets the
      // route choose its anti-enumeration response (it returns
      // 202 anyway).
      return null;
    }

    const plaintext = crypto.randomBytes(32).toString("base64url");
    const tokenHash = this._hashResetToken(plaintext);
    const createdAt = nowIso();
    const expiresAt = new Date(
      nowMs + PASSWORD_RESET_TOKEN_TTL_MS,
    ).toISOString();

    db.passwordResetTokens.push({
      id: crypto.randomUUID(),
      userId: normalizedUserId,
      tokenHash,
      createdAt,
      expiresAt,
      consumedAt: null,
    });
    await this._write(db);

    return {
      plaintext,
      expiresAt,
      ttlSeconds: Math.floor(PASSWORD_RESET_TOKEN_TTL_MS / 1000),
    };
  },

  // Look up a reset token by its plaintext (re-hashed here), and
  // mark it consumed atomically. Returns the user id if the token
  // was valid and not previously used, null otherwise.
  //
  // We DO NOT update the password here — the caller does that
  // explicitly via `updateUserPassword` so the route can validate
  // the new password's shape (length etc.) BEFORE consuming the
  // token. Otherwise a malformed-password attempt would burn a
  // valid token and force the user to re-request.
  async consumePasswordResetToken(plaintextToken) {
    const db = await this._read();
    this._cleanupExpiredPasswordResetTokens(db);

    const trimmed = String(plaintextToken || "").trim();
    if (!trimmed) return null;

    const tokenHash = this._hashResetToken(trimmed);
    const index = db.passwordResetTokens.findIndex(
      (entry) =>
        entry.tokenHash === tokenHash &&
        !entry.consumedAt &&
        !isExpiredAt(entry?.expiresAt),
    );
    if (index < 0) {
      // Cleanup may have changed the array — flush even on miss.
      await this._write(db);
      return null;
    }
    const record = db.passwordResetTokens[index];
    record.consumedAt = nowIso();
    await this._write(db);
    return record.userId;
  },

  async findUserByEmail(emailRaw) {
    const db = await this._read();
    const normalized = String(emailRaw || "").trim().toLowerCase();
    if (!normalized) return null;
    const user = db.users.find((entry) => entry.email === normalized);
    return user ? structuredClone(user) : null;
  },

  // Used by the password-reset confirm route. Async-hashes via
  // libuv thread pool — same scrypt cost as login verify, so the
  // event loop stays responsive under concurrent resets.
  async updateUserPassword(
    userId,
    newPlaintextPassword,
    {exceptToken = null} = {},
  ) {
    const existingUser = await this.findUserById(userId);
    if (!existingUser) return false;

    const credentials = await hashPasswordAsync(
      String(newPlaintextPassword || ""),
    );
    const normalizedExceptToken = String(exceptToken || "").trim() || null;
    let userSessionTokens = [];
    let rememberedUser = null;
    const updated = await this._mutate((db, skip) => {
      const user = db.users.find((entry) => entry.id === userId);
      if (!user) return skip(false);

      user.passwordHash = credentials.passwordHash;
      user.passwordSalt = credentials.salt;
      user.failedLoginCount = 0;
      user.lockedUntil = null;
      user.updatedAt = nowIso();
      const identities = listAuthIdentitiesForUser(user);
      if (!identities.some((entry) => entry.provider === "password")) {
        identities.push(createPasswordAuthIdentity(user));
      }
      user.authIdentities = identities;
      user.providerIds = deriveProviderIdsForUser(user);
      rememberedUser = user;

      const currentSessions = Array.isArray(db.sessions) ? db.sessions : [];
      userSessionTokens = currentSessions
        .filter(
          (session) =>
            session.userId === userId &&
            (!normalizedExceptToken || session.token !== normalizedExceptToken),
        )
        .map((session) => session.token);
      db.sessions = currentSessions.filter(
        (session) =>
          session.userId !== userId ||
          (normalizedExceptToken && session.token === normalizedExceptToken),
      );

      if (Array.isArray(db.passwordResetTokens)) {
        db.passwordResetTokens = db.passwordResetTokens.filter((entry) => {
          if (entry.userId !== userId) return true;
          if (entry.consumedAt) return true;
          return false;
        });
      }
      return true;
    });
    if (!updated) return false;
    if (rememberedUser) {
      this._rememberUser(rememberedUser);
    } else {
      this._forgetUser(userId);
    }
    for (const token of userSessionTokens) {
      this._forgetSession(token);
    }
    return true;
  },

  async changeUserPassword({
    userId,
    currentPassword = null,
    newPassword,
    exceptToken = null,
  }) {
    const existingUser = await this.findUserById(userId);
    if (!existingUser) {
      return {error: "USER_NOT_FOUND"};
    }
    const hasPassword = Boolean(
      existingUser.passwordHash && existingUser.passwordSalt,
    );
    if (hasPassword) {
      if (!currentPassword) {
        return {error: "CURRENT_PASSWORD_REQUIRED"};
      }
      const matches = await verifyPasswordAsync(
        String(currentPassword),
        existingUser,
      );
      if (!matches) {
        return {error: "INVALID_CURRENT_PASSWORD"};
      }
      if (String(currentPassword) === String(newPassword)) {
        return {error: "SAME_PASSWORD"};
      }
    } else if (!String(existingUser.email || "").trim()) {
      return {error: "EMAIL_REQUIRED"};
    }

    const updated = await this.updateUserPassword(userId, newPassword, {
      exceptToken,
    });
    if (!updated) {
      return {error: "UPDATE_FAILED"};
    }
    const updatedUser = await this.findUserById(userId);
    return {
      hasPassword: true,
      providerIds: deriveProviderIdsForUser(updatedUser || existingUser),
    };
  },

  _cleanupExpiredAuthHandoffs(db) {
    const beforeLength = Array.isArray(db.authHandoffs) ? db.authHandoffs.length : 0;
    db.authHandoffs = (Array.isArray(db.authHandoffs) ? db.authHandoffs : []).filter(
      (entry) => !isExpiredAt(entry?.expiresAt),
    );
    return db.authHandoffs.length !== beforeLength;
  },

  async createAuthHandoff({type, payload = {}, userId = null, expiresAt = null}) {
    const db = await this._read();
    this._cleanupExpiredAuthHandoffs(db);
    const handoff = createAuthHandoffRecord({
      type,
      payload,
      userId,
      expiresAt,
    });
    db.authHandoffs.push(handoff);
    await this._write(db);
    return structuredClone(handoff);
  },

  async consumeAuthHandoff(code, {type = null} = {}) {
    const db = await this._read();
    this._cleanupExpiredAuthHandoffs(db);
    const normalizedCode = String(code || "").trim();
    const index = db.authHandoffs.findIndex((entry) => {
      if (entry.code !== normalizedCode) {
        return false;
      }
      if (type && entry.type !== type) {
        return false;
      }
      return true;
    });
    if (index < 0) {
      if (this._cleanupExpiredAuthHandoffs(db)) {
        await this._write(db);
      }
      return null;
    }

    const [handoff] = db.authHandoffs.splice(index, 1);
    await this._write(db);
    return structuredClone(handoff);
  },

  async findAuthHandoff(code, {type = null} = {}) {
    const db = await this._read();
    const cleaned = this._cleanupExpiredAuthHandoffs(db);
    if (cleaned) {
      await this._write(db);
    }
    const normalizedCode = String(code || "").trim();
    if (!normalizedCode) {
      return null;
    }
    const handoff = db.authHandoffs.find((entry) => {
      if (entry.code !== normalizedCode) {
        return false;
      }
      if (type && entry.type !== type) {
        return false;
      }
      return true;
    });
    return handoff ? structuredClone(handoff) : null;
  },

  async updateAuthHandoffPayload(code, patch = {}, {type = null} = {}) {
    const db = await this._read();
    this._cleanupExpiredAuthHandoffs(db);
    const normalizedCode = String(code || "").trim();
    if (!normalizedCode) {
      return null;
    }
    const handoff = db.authHandoffs.find((entry) => {
      if (entry.code !== normalizedCode) {
        return false;
      }
      if (type && entry.type !== type) {
        return false;
      }
      return true;
    });
    if (!handoff) {
      return null;
    }
    handoff.payload = {
      ...(handoff.payload && typeof handoff.payload === "object"
        ? handoff.payload
        : {}),
      ...(patch && typeof patch === "object" ? patch : {}),
    };
    await this._write(db);
    return structuredClone(handoff);
  },

  async findSession(token) {
    const normalizedToken = String(token || "").trim();
    if (!normalizedToken) {
      return null;
    }
    const cachedSession = this._sessionCache.get(normalizedToken);
    if (cachedSession) {
      return structuredClone(cachedSession);
    }
    const db = await this._read();
    const session = db.sessions.find((entry) => entry.token === normalizedToken);
    if (session) {
      this._rememberSession(session);
    }
    return session ? structuredClone(session) : null;
  },

  async touchSession(token) {
    const normalizedToken = String(token || "").trim();
    if (!normalizedToken) {
      return null;
    }

    const nowMs = Date.now();
    const cachedTouchedAt = this._sessionTouchCache.get(normalizedToken);
    if (
      Number.isFinite(cachedTouchedAt) &&
      nowMs - cachedTouchedAt < SESSION_TOUCH_MIN_INTERVAL_MS
    ) {
      return null;
    }

    this._sessionTouchCache.set(normalizedToken, nowMs);
    const db = await this._read();
    const session = db.sessions.find((entry) => entry.token === normalizedToken);
    if (!session) {
      this._forgetSession(normalizedToken);
      return null;
    }

    const lastSeenAtMs = new Date(session.lastSeenAt || 0).getTime();
    if (
      Number.isFinite(lastSeenAtMs) &&
      nowMs - lastSeenAtMs < SESSION_TOUCH_MIN_INTERVAL_MS
    ) {
      this._sessionTouchCache.set(normalizedToken, lastSeenAtMs);
      this._rememberSession(session);
      return structuredClone(session);
    }

    session.lastSeenAt = nowIso();
    try {
      await this._write(db);
    } catch (error) {
      this._forgetSession(normalizedToken);
      throw error;
    }
    this._rememberSession(session);
    return structuredClone(session);
  },

  async deleteSession(token) {
    const normalizedToken = String(token || "").trim();
    if (!normalizedToken) {
      return null;
    }
    const db = await this._read();
    const removedSession = db.sessions.find(
      (entry) => entry.token === normalizedToken,
    );
    db.sessions = db.sessions.filter((entry) => entry.token !== normalizedToken);
    this._forgetSession(normalizedToken);
    await this._write(db);
    return removedSession ? structuredClone(removedSession) : null;
  },

  async deleteSessionsForUser(userId) {
    const db = await this._read();
    const deletedTokens = db.sessions
      .filter((entry) => entry.userId === userId)
      .map((entry) => entry.token);
    db.sessions = db.sessions.filter((entry) => entry.userId !== userId);
    for (const token of deletedTokens) {
      this._forgetSession(token);
    }
    await this._write(db);
  },

  // SPEED-12: readSharedSnapshot() — единственный вызывающий
  // (GET /v1/profile/me/account-linking-status) read-only, identity
  // клонируется на возврат.
  async listUserAuthIdentities(userId) {
    const db = await this.readSharedSnapshot();
    const user = db.users.find((entry) => entry.id === userId);
    if (!user) {
      return null;
    }

    return listAuthIdentitiesForUser(user).map((identity) => structuredClone(identity));
  },

  async updateProfile(userId, updater) {
    const db = await this._read();
    const user = db.users.find((entry) => entry.id === userId);
    if (!user) {
      return null;
    }

    const previousProfile = user.profile || {};
    const nextProfile = updater(structuredClone(user.profile));
    const nextPhoneNumber = String(nextProfile?.phoneNumber || "").trim();
    const nextCountryCode = nextProfile?.countryCode ?? user.profile?.countryCode;
    const normalizedPhoneNumber = normalizePhoneNumber(
      nextPhoneNumber,
      nextCountryCode,
    );
    user.profile = {
      ...user.profile,
      ...nextProfile,
      phoneNumber: nextPhoneNumber,
      normalizedPhoneNumber,
      birthPlace:
        nextProfile && Object.prototype.hasOwnProperty.call(nextProfile, "birthPlace")
          ? normalizeNullableString(nextProfile.birthPlace)
          : normalizeNullableString(user.profile?.birthPlace),
      profileContributionPolicy:
        nextProfile &&
        Object.prototype.hasOwnProperty.call(
          nextProfile,
          "profileContributionPolicy",
        )
          ? normalizeProfileContributionPolicy(nextProfile.profileContributionPolicy)
          : normalizeProfileContributionPolicy(
              user.profile?.profileContributionPolicy,
            ),
      primaryTrustedChannel:
        nextProfile &&
        Object.prototype.hasOwnProperty.call(
          nextProfile,
          "primaryTrustedChannel",
        )
          ? normalizePrimaryTrustedChannel(nextProfile.primaryTrustedChannel)
          : normalizePrimaryTrustedChannel(user.profile?.primaryTrustedChannel),
      id: user.id,
      email: user.email,
      updatedAt: nowIso(),
    };
    user.updatedAt = nowIso();

    const touchedTreeIds = new Set();
    for (const person of db.persons) {
      if (person.userId !== userId) {
        continue;
      }
      applyCanonicalProfileToPerson(person, user.profile);
      if (person.treeId) {
        touchedTreeIds.add(person.treeId);
      }
    }
    for (const tree of db.trees) {
      if (touchedTreeIds.has(tree.id)) {
        tree.updatedAt = nowIso();
      }
    }

    await this._write(db);
    this._rememberUser(user);
    return structuredClone(user);
  },

  async deleteUser(userId) {
    // SPEED-2/STORE-RACE: аккаунт-удаление через _mutate. Иначе фоновый
    // фан-аут отправки сообщения (createNotification / markChatMessageDelivered
    // на _mutate) мог прочитать снапшот с ещё живой сессией и записать её
    // обратно, ВОСКРЕСИВ только что удалённую сессию (raw _read/_write не
    // сериализован против _mutate). Кеш-очистка — ПОСЛЕ персиста.
    let deletedSessionTokens = [];
    const result = await this._mutate((db, skip) => {
    const existingUser = db.users.find((entry) => entry.id === userId);
    if (!existingUser) {
      return skip(null);
    }
    deletedSessionTokens = db.sessions
      .filter((entry) => entry.userId === userId)
      .map((entry) => entry.token);

    const timestamp = nowIso();
    const removedTreeIds = new Set();
    db.trees = db.trees.reduce((trees, tree) => {
      const nextMemberIds = normalizeParticipantIds(
        (tree.memberIds || tree.members || []).filter(
          (memberId) => memberId !== userId,
        ),
      );

      const semyaHasOtherActiveMember =
        tree.semyaId &&
        (db.semyaMembers || []).some(
          (m) =>
            m.semyaId === tree.semyaId &&
            m.userId !== userId &&
            !m.hiddenAt,
        );
      if (
        tree.creatorId === userId &&
        nextMemberIds.length === 0 &&
        !semyaHasOtherActiveMember
      ) {
        removedTreeIds.add(tree.id);
        return trees;
      }

      const creatorId =
        tree.creatorId === userId ? nextMemberIds[0] || null : tree.creatorId;
      const membersChanged =
        nextMemberIds.length !== (tree.memberIds || tree.members || []).length ||
        creatorId !== tree.creatorId;

      trees.push({
        ...tree,
        creatorId,
        memberIds: nextMemberIds,
        members: nextMemberIds,
        updatedAt: membersChanged ? timestamp : tree.updatedAt,
      });
      return trees;
    }, []);

    const removedPersonIds = new Set(
      db.persons
        .filter(
          (entry) => entry.userId === userId || removedTreeIds.has(entry.treeId),
        )
        .map((entry) => entry.id),
    );

    db.users = db.users.filter((entry) => entry.id !== userId);
    db.sessions = db.sessions.filter((entry) => entry.userId !== userId);
    db.authHandoffs = (db.authHandoffs || []).filter((entry) => entry.userId !== userId);
    // GDPR cleanup: drop any pending or consumed password-reset
    // tokens for this user. We keep no audit trail across the
    // delete since the user record itself is gone.
    db.passwordResetTokens = (db.passwordResetTokens || []).filter(
      (entry) => entry.userId !== userId,
    );
    // Drop this user's identity-suggestion dismissals.
    db.dismissedIdentitySuggestions = (
      db.dismissedIdentitySuggestions || []
    ).filter((entry) => entry.userId !== userId);
    db.persons = db.persons.filter((entry) => !removedPersonIds.has(entry.id));
    db.relations = db.relations.filter((entry) => {
      return (
        !removedTreeIds.has(entry.treeId) &&
        !removedPersonIds.has(entry.person1Id) &&
        !removedPersonIds.has(entry.person2Id)
      );
    });
    db.circles = db.circles.filter((entry) => !removedTreeIds.has(entry.treeId));
    db.circleMembers = db.circleMembers.filter(
      (entry) =>
        !removedTreeIds.has(entry.treeId) &&
        !removedPersonIds.has(entry.personId),
    );

    const nextPosts = [];
    const removedPostIds = new Set();
    for (const post of db.posts) {
      if (post.authorId === userId || removedTreeIds.has(post.treeId)) {
        removedPostIds.add(post.id);
        continue;
      }

      nextPosts.push({
        ...post,
        anchorPersonIds: normalizeParticipantIds(
          (post.anchorPersonIds || []).filter(
            (personId) => !removedPersonIds.has(personId),
          ),
        ),
      });
    }
    db.posts = nextPosts;
    db.stories = db.stories.filter((story) => {
      return !(
        story.authorId === userId ||
        removedTreeIds.has(story.treeId)
      );
    });

    const removedCommentIds = new Set();
    db.comments = db.comments.filter((entry) => {
      const shouldRemove =
        entry.authorId === userId || removedPostIds.has(entry.postId);
      if (shouldRemove) {
        removedCommentIds.add(entry.id);
      }
      return !shouldRemove;
    });

    const removedRelationRequestIds = new Set();
    db.relationRequests = db.relationRequests.filter((entry) => {
      const shouldRemove =
        entry.senderId === userId ||
        entry.recipientId === userId ||
        removedTreeIds.has(entry.treeId);
      if (shouldRemove) {
        removedRelationRequestIds.add(entry.id);
      }
      return !shouldRemove;
    });

    const removedInvitationIds = new Set();
    db.treeInvitations = db.treeInvitations.filter((entry) => {
      const shouldRemove =
        entry.userId === userId || removedTreeIds.has(entry.treeId);
      if (shouldRemove) {
        removedInvitationIds.add(entry.id);
      }
      return !shouldRemove;
    });

    const nextChats = [];
    const removedChatIds = new Set();
    for (const chat of db.chats) {
      if (chat.treeId && removedTreeIds.has(chat.treeId)) {
        removedChatIds.add(chat.id);
        continue;
      }

      const nextParticipantIds = normalizeParticipantIds(
        (chat.participantIds || []).filter((entry) => entry !== userId),
      );
      const nextBranchRootPersonIds = normalizeParticipantIds(
        (chat.branchRootPersonIds || []).filter(
          (entry) => !removedPersonIds.has(entry),
        ),
      );
      const shouldKeep = chat.type === "direct"
        ? nextParticipantIds.length === 2
        : nextParticipantIds.length >= 2;

      if (!shouldKeep) {
        removedChatIds.add(chat.id);
        continue;
      }

      nextChats.push({
        ...chat,
        participantIds: nextParticipantIds,
        branchRootPersonIds: nextBranchRootPersonIds,
      });
    }
    db.chats = nextChats;
    const activeChatIds = new Set(nextChats.map((chat) => chat.id));
    db.messages = db.messages.filter((entry) => {
      return (
        entry.senderId !== userId &&
        (!Array.isArray(entry.participants) ||
          !entry.participants.includes(userId)) &&
        activeChatIds.has(entry.chatId)
      );
    });
    db.chatDrafts = db.chatDrafts.filter((entry) => {
      return entry.userId !== userId && activeChatIds.has(entry.chatId);
    });
    const activeMessageIds = new Set(
      db.messages.map((entry) => String(entry?.id || "").trim()).filter(Boolean),
    );
    db.chatPins = ensureChatPins(db).filter((entry) => {
      return (
        activeChatIds.has(entry.chatId) &&
        activeMessageIds.has(String(entry?.messageId || "").trim()) &&
        entry.pinnedBy !== userId
      );
    });

    db.notifications = db.notifications.filter((entry) => {
      if (entry.userId === userId) {
        return false;
      }

      const data = entry.data && typeof entry.data === "object" ? entry.data : {};
      if (
        data.userId === userId ||
        data.senderId === userId ||
        data.recipientId === userId ||
        data.actorId === userId ||
        data.targetUserId === userId ||
        data.authorId === userId ||
        data.ownerId === userId
      ) {
        return false;
      }

      if (
        (data.chatId && removedChatIds.has(data.chatId)) ||
        (data.treeId && removedTreeIds.has(data.treeId)) ||
        (data.postId && removedPostIds.has(data.postId)) ||
        (data.commentId && removedCommentIds.has(data.commentId)) ||
        (data.requestId && removedRelationRequestIds.has(data.requestId)) ||
        (data.invitationId && removedInvitationIds.has(data.invitationId))
      ) {
        return false;
      }

      return true;
    });

    db.reports = db.reports.filter((entry) => {
      return (
        entry.reporterId !== userId &&
        entry.resolvedBy !== userId &&
        !(
          entry.targetType === "user" &&
          entry.targetId === userId
        ) &&
        !(
          entry.targetType === "post" &&
          removedPostIds.has(entry.targetId)
        ) &&
        !(
          entry.targetType === "comment" &&
          removedCommentIds.has(entry.targetId)
        ) &&
        !(
          entry.targetType === "tree" &&
          removedTreeIds.has(entry.targetId)
        ) &&
        !(
          entry.targetType === "chat" &&
          removedChatIds.has(entry.targetId)
        )
      );
    });
    db.blocks = db.blocks.filter((entry) => {
      return entry.blockerId !== userId && entry.blockedUserId !== userId;
    });
    db.pushDevices = db.pushDevices.filter((entry) => entry.userId !== userId);
    const activeNotificationIds = new Set(db.notifications.map((entry) => entry.id));
    db.pushDeliveries = db.pushDeliveries.filter((entry) => {
      return (
        entry.userId !== userId &&
        (!entry.notificationId || activeNotificationIds.has(entry.notificationId))
      );
    });

    // ── GDPR completeness sweep ──────────────────────────────────────
    // Every record that ties the deleted user's id to user-visible
    // surface must be either removed or anonymized. The original
    // deleteUser missed reactions on OTHER users' content
    // ("Иван reacted ❤️" stayed visible after Иван's account was
    // deleted) and a few audit-side records that name the user.
    if (Array.isArray(db.postReactions)) {
      db.postReactions = db.postReactions.filter((entry) => {
        return entry.userId !== userId && !removedPostIds.has(entry.postId);
      });
    }
    if (Array.isArray(db.postCommentReactions)) {
      db.postCommentReactions = db.postCommentReactions.filter((entry) => {
        return (
          entry.userId !== userId &&
          !removedCommentIds.has(entry.commentId)
        );
      });
    }
    if (Array.isArray(db.storyReactions)) {
      db.storyReactions = db.storyReactions.filter(
        (entry) => entry.userId !== userId,
      );
    }
    if (Array.isArray(db.messageReactions)) {
      db.messageReactions = db.messageReactions.filter((entry) => {
        return (
          entry.userId !== userId &&
          (!entry.messageId || activeMessageIds.has(String(entry.messageId).trim()))
        );
      });
    }
    if (Array.isArray(db.profileContributions)) {
      db.profileContributions = db.profileContributions.filter((entry) => {
        return (
          entry.authorUserId !== userId &&
          entry.contributorId !== userId &&
          entry.targetUserId !== userId &&
          !removedTreeIds.has(entry.treeId) &&
          !removedPersonIds.has(entry.personId)
        );
      });
    }
    if (Array.isArray(db.mergeProposals)) {
      const nextMergeProposals = [];
      for (const entry of db.mergeProposals) {
        if (
          entry.proposedByUserId === userId ||
          entry.proposerId === userId ||
          removedTreeIds.has(entry.treeId) ||
          removedTreeIds.has(entry.fromTreeId) ||
          removedTreeIds.has(entry.candidateTreeId) ||
          removedPersonIds.has(entry.fromPersonId) ||
          removedPersonIds.has(entry.candidatePersonId)
        ) {
          continue;
        }
        const hasReviewerRefs =
          Array.isArray(entry.reviewerUserIds) || Array.isArray(entry.reviews);
        if (!hasReviewerRefs) {
          nextMergeProposals.push(entry);
          continue;
        }
        const nextReviewerIds = normalizeParticipantIds(
          (entry.reviewerUserIds || []).filter((id) => id !== userId),
        );
        const nextReviews = Array.isArray(entry.reviews)
          ? entry.reviews.filter((r) => r.userId !== userId)
          : entry.reviews;
        if (
          (entry.status || "pending") === "pending" &&
          nextReviewerIds.length === 0
        ) {
          continue;
        }
        nextMergeProposals.push({
          ...entry,
          reviewerUserIds: nextReviewerIds,
          ...(Array.isArray(nextReviews) ? {reviews: nextReviews} : {}),
        });
      }
      db.mergeProposals = nextMergeProposals;
    }
    if (Array.isArray(db.identityClaims)) {
      const nextIdentityClaims = [];
      for (const entry of db.identityClaims) {
        if (
          entry.claimantUserId === userId ||
          entry.claimerId === userId ||
          removedTreeIds.has(entry.treeId) ||
          removedPersonIds.has(entry.personId)
        ) {
          continue;
        }
        const hasReviewerRefs =
          Array.isArray(entry.reviewerUserIds) || Array.isArray(entry.reviews);
        if (!hasReviewerRefs) {
          nextIdentityClaims.push(entry);
          continue;
        }
        const nextReviewerIds = normalizeParticipantIds(
          (entry.reviewerUserIds || []).filter((id) => id !== userId),
        );
        const nextReviews = Array.isArray(entry.reviews)
          ? entry.reviews.filter((r) => r.userId !== userId)
          : entry.reviews;
        nextIdentityClaims.push({
          ...entry,
          reviewerUserIds: nextReviewerIds,
          ...(Array.isArray(nextReviews) ? {reviews: nextReviews} : {}),
        });
      }
      db.identityClaims = nextIdentityClaims;
    }
    if (Array.isArray(db.storyRequests)) {
      db.storyRequests = db.storyRequests.filter(
        (entry) =>
          entry.requesterUserId !== userId &&
          entry.targetUserId !== userId &&
          !removedTreeIds.has(entry.treeId),
      );
    }
    if (Array.isArray(db.kinshipChecks)) {
      db.kinshipChecks = db.kinshipChecks.filter(
        (entry) =>
          entry.initiatorUserId !== userId && entry.targetUserId !== userId,
      );
    }
    if (Array.isArray(db.gatherings)) {
      db.gatherings = db.gatherings
        .filter(
          (entry) =>
            entry.authorId !== userId && !removedTreeIds.has(entry.treeId),
        )
        .map((entry) =>
          Array.isArray(entry.rsvps)
            ? {
                ...entry,
                rsvps: entry.rsvps.filter((r) => r.userId !== userId),
              }
            : entry,
        );
    }
    if (Array.isArray(db.polls)) {
      db.polls = db.polls
        .filter(
          (entry) =>
            entry.authorId !== userId && !removedTreeIds.has(entry.treeId),
        )
        .map((entry) =>
          Array.isArray(entry.responses)
            ? {
                ...entry,
                responses: entry.responses.filter((r) => r.userId !== userId),
              }
            : entry,
        );
    }
    if (Array.isArray(db.graphPersonEditGrants)) {
      db.graphPersonEditGrants = db.graphPersonEditGrants.filter(
        (entry) =>
          entry.grantorUserId !== userId && entry.granteeUserId !== userId,
      );
    }
    const removedSemyaIds = new Set();
    if (Array.isArray(db.semyaMembers)) {
      db.semyaMembers = db.semyaMembers.filter(
        (entry) => entry.userId !== userId,
      );
    }
    if (Array.isArray(db.semyi)) {
      for (const semya of db.semyi) {
        if (removedTreeIds.has(semya.treeId)) {
          semya.deletedAt = semya.deletedAt || timestamp;
          semya.updatedAt = timestamp;
          removedSemyaIds.add(semya.id);
          for (const member of db.semyaMembers || []) {
            if (member.semyaId === semya.id && !member.hiddenAt) {
              member.hiddenAt = timestamp;
            }
          }
          continue;
        }
        if (semya.deletedAt) {
          continue;
        }
        const activeMembers = (db.semyaMembers || [])
          .filter((m) => m.semyaId === semya.id && !m.hiddenAt)
          .sort((a, b) =>
            String(a.joinedAt || "").localeCompare(String(b.joinedAt || "")),
          );
        if (activeMembers.length === 0) {
          semya.deletedAt = timestamp;
          semya.updatedAt = timestamp;
          removedSemyaIds.add(semya.id);
          continue;
        }
        const activeOwners = activeMembers.filter((m) => m.role === "owner");
        if (activeOwners.length === 0) {
          const successor =
            activeMembers.find((m) => m.role === "editor") || activeMembers[0];
          successor.role = "owner";
          successor.hasInviteGrant = true;
          semya.ownerId = successor.userId;
          semya.updatedAt = timestamp;
          const boundTree = (db.trees || []).find(
            (t) => t.id === semya.treeId,
          );
          if (
            boundTree &&
            (boundTree.creatorId === userId || !boundTree.creatorId)
          ) {
            boundTree.creatorId = successor.userId;
            boundTree.updatedAt = timestamp;
          }
        } else if (semya.ownerId === userId) {
          semya.ownerId = activeOwners[0].userId;
          semya.updatedAt = timestamp;
        }
      }
    }
    if (Array.isArray(db.semyaInvitations)) {
      db.semyaInvitations = db.semyaInvitations.filter(
        (entry) =>
          entry.recipientUserId !== userId &&
          !removedSemyaIds.has(entry.semyaId) &&
          !(entry.inviterUserId === userId && entry.status === "pending"),
      );
    }
    if (Array.isArray(db.semyaBrowseTokens)) {
      db.semyaBrowseTokens = db.semyaBrowseTokens.filter(
        (entry) =>
          entry.createdByUserId !== userId &&
          !removedSemyaIds.has(entry.semyaId),
      );
    }
    if (Array.isArray(db.semyaMemberHiddenPersons)) {
      db.semyaMemberHiddenPersons = db.semyaMemberHiddenPersons.filter(
        (entry) =>
          entry.userId !== userId &&
          !removedSemyaIds.has(entry.semyaId) &&
          !removedPersonIds.has(entry.personId),
      );
    }
    if (Array.isArray(db.onboardingStates)) {
      db.onboardingStates = db.onboardingStates.filter(
        (entry) => entry.userId !== userId,
      );
      this._onboardingIncompleteCache?.delete(userId);
    }
    if (Array.isArray(db.deletedPersons)) {
      db.deletedPersons = db.deletedPersons.filter(
        (entry) =>
          entry.deletedByUserId !== userId &&
          entry.snapshot?.userId !== userId &&
          !removedTreeIds.has(entry.treeId) &&
          !removedSemyaIds.has(entry.semyaId),
      );
    }
    if (Array.isArray(db.deletedPosts)) {
      db.deletedPosts = db.deletedPosts.filter(
        (entry) =>
          entry.deletedByUserId !== userId &&
          entry.snapshot?.authorId !== userId &&
          !removedTreeIds.has(entry.treeId),
      );
    }
    if (Array.isArray(db.profileArticles)) {
      db.profileArticles = db.profileArticles.filter(
        (entry) =>
          !removedTreeIds.has(entry.treeId) &&
          !removedPersonIds.has(entry.personId),
      );
    }
    if (Array.isArray(db.calls)) {
      // Drop calls where the deleted user was the only initiator,
      // and scrub the user from participant lists of group calls.
      const filteredCalls = [];
      for (const call of db.calls) {
        if (call.initiatorId === userId) continue;
        if (Array.isArray(call.participantIds)) {
          call.participantIds = call.participantIds.filter(
            (id) => id !== userId,
          );
          if (call.participantIds.length === 0) continue;
        }
        filteredCalls.push(call);
      }
      db.calls = filteredCalls;
    }
    // Anonymize rather than delete — change records are an audit
    // log; preserving them as "deleted user changed X" keeps the
    // tree's history intact while removing the personal identifier.
    // Right-to-erasure under GDPR allows pseudonymization for
    // legitimate-interest audit logs (recital 26).
    this._pseudonymizeTreeChangeActor(db, userId);
    if (Array.isArray(db.identityFieldConflicts)) {
      // Phase 1.3: drop conflict rows that touch trees or persons
      // we just removed (the surface they referred to is gone),
      // and pseudonymize `resolvedBy` on the rest — same GDPR
      // tradeoff as treeChangeRecords above.
      db.identityFieldConflicts = db.identityFieldConflicts.filter(
        (entry) =>
          !removedTreeIds.has(entry.targetTreeId) &&
          !removedTreeIds.has(entry.sourceTreeId) &&
          !removedPersonIds.has(entry.targetPersonId) &&
          !removedPersonIds.has(entry.sourcePersonId),
      );
      for (const entry of db.identityFieldConflicts) {
        if (entry.resolvedBy === userId) {
          entry.resolvedBy = "deleted-user";
        }
      }
    }

    this._reconcilePersonIdentities(db);
    return {
      userId,
      removedTreeIds: Array.from(removedTreeIds),
      removedSemyaIds: Array.from(removedSemyaIds),
      removedPersonIds: Array.from(removedPersonIds),
      removedChatIds: Array.from(removedChatIds),
      removedPostIds: Array.from(removedPostIds),
      // SPEED-7: точные множества для табличного notification-каскада
      // PostgresStore — реконструкция дифом блоба до/после гонялась бы с
      // конкурентными удалениями других пользователей.
      removedCommentIds: Array.from(removedCommentIds),
      removedRelationRequestIds: Array.from(removedRelationRequestIds),
      removedInvitationIds: Array.from(removedInvitationIds),
    };
    });
    if (result === null) {
      return null;
    }
    this._forgetUser(userId);
    for (const token of deletedSessionTokens) {
      this._forgetSession(token);
    }
    return result;
  },

  async listOwnedMediaUrls(userId) {
    const db = await this._read();
    return collectOwnedMediaUrlsForUser(db, userId);
  },

  async listSemyiForUser(userId) {
    if (!userId || typeof userId !== "string") {
      return [];
    }
    const db = await this._read();
    const memberSemyaIds = new Set(
      (db.semyaMembers || [])
        .filter((m) => m.userId === userId && !m.hiddenAt)
        .map((m) => m.semyaId),
    );
    return (db.semyi || [])
      .filter((entry) => !entry.deletedAt && memberSemyaIds.has(entry.id))
      .sort((left, right) =>
        String(right.updatedAt || "").localeCompare(
          String(left.updatedAt || ""),
        ),
      )
      .map((entry) => structuredClone(entry));
  },

  // Ship FE9 (2026-05-27): list invitations addressed к caller — used
  // by onboarding wizard к surface «У вас есть приглашение от семьи X»
  // CTA. Returns only `pending` status invitations matched по userId
  // либо email (с lazy expiry sweep). Each row enriched с denormalized
  // semya name to spare frontend extra round-trip.
  //
  // Matching logic:
  //   • recipientUserId == userId — explicit user-targeted invitation
  //   • recipientEmail == email AND recipientUserId == null —
  //     email-only invitation matches after user registered с тем же
  //     email (typical post-registration flow для invitations sent
  //     before user existed)
  //
  // Phone matches not supported здесь (phone-based invitations rare).
  async listPendingInvitationsForUser({userId, email}) {
    if (!userId || typeof userId !== "string") {
      return [];
    }
    const normalizedEmail = (email || "").toLowerCase().trim();
    const db = await this._read();
    this._lazyExpireInvitations(db, null);
    const matching = (db.semyaInvitations || []).filter((inv) => {
      if (inv.status !== "pending") return false;
      if (inv.recipientUserId === userId) return true;
      if (!inv.recipientUserId && normalizedEmail) {
        const invEmail = (inv.recipientEmail || "").toLowerCase().trim();
        if (invEmail && invEmail === normalizedEmail) return true;
      }
      return false;
    });
    // Enrich с семя name. Soft-deleted semya excluded (their pending
    // invitations stale — recipient cannot accept anyway).
    const enriched = [];
    for (const inv of matching) {
      const semya = (db.semyi || []).find(
        (s) => s.id === inv.semyaId && !s.deletedAt,
      );
      if (!semya) continue;
      const clone = structuredClone(inv);
      clone.semyaName = semya.name;
      enriched.push(clone);
    }
    return enriched.sort((a, b) =>
      String(b.createdAt || "").localeCompare(String(a.createdAt || "")),
    );
  },

  async issuePersonClaimToken({treeId, personId, actorUserId}) {
    const normalizedTreeId = normalizeNullableString(treeId);
    const normalizedPersonId = normalizeNullableString(personId);
    const normalizedActorId = normalizeNullableString(actorUserId);
    if (!normalizedTreeId || !normalizedPersonId || !normalizedActorId) {
      throw new Error("NOT_FOUND");
    }

    return this._mutate((db) => {
      const tree = (db.trees || []).find(
        (entry) => entry.id === normalizedTreeId,
      );
      const person = (db.persons || []).find(
        (entry) =>
          entry.id === normalizedPersonId && entry.treeId === normalizedTreeId,
      );
      if (!tree || !person) {
        throw new Error("NOT_FOUND");
      }
      if (person.userId) {
        throw new Error("ALREADY_CLAIMED");
      }
      if (
        person.isAlive === false ||
        Boolean(normalizeNullableString(person.deathDate))
      ) {
        throw new Error("PERSON_DECEASED");
      }

      const token = crypto.randomBytes(24).toString("base64url");
      const now = nowIso();
      const expiresAt = new Date(Date.now() + 30 * 86_400_000).toISOString();
      person.inviteClaimToken = token;
      person.inviteClaimCreatedBy = normalizedActorId;
      person.inviteClaimExpiresAt = expiresAt;
      person.updatedAt = now;
      return {
        claimToken: token,
        expiresAt,
        treeId: tree.id,
        personId: person.id,
      };
    });
  },

  async linkPersonToUser({
    treeId,
    personId,
    userId,
    claimToken = null,
    requireClaimToken = false,
    bypassClaimToken = false,
  }) {
    const db = await this._read();
    const tree = db.trees.find((entry) => entry.id === treeId);
    if (!tree) {
      return null;
    }

    const person = db.persons.find(
      (entry) => entry.id === personId && entry.treeId === treeId,
    );
    if (!person) {
      return undefined;
    }

    if (person.userId && person.userId !== userId) {
      return false;
    }

    const user = db.users.find((entry) => entry.id === userId);
    if (!user) {
      return null;
    }

    if (
      person.isAlive === false ||
      Boolean(normalizeNullableString(person.deathDate))
    ) {
      throw new Error("PERSON_DECEASED");
    }

    const creatorCheckIds = new Set(
      [tree.creatorId, person.creatorId]
        .map((id) => normalizeNullableString(id))
        .filter((id) => id && id !== userId),
    );
    const isBlockedByCreator = (db.blocks || []).some((entry) => {
      const blocker = normalizeNullableString(
        entry.blockerId ?? entry.blockerUserId,
      );
      const blocked = normalizeNullableString(
        entry.blockedUserId ?? entry.blockedId,
      );
      if (!blocker || !blocked) return false;
      return (
        (blocker === userId && creatorCheckIds.has(blocked)) ||
        (blocked === userId && creatorCheckIds.has(blocker))
      );
    });
    if (isBlockedByCreator) {
      throw new Error("BLOCKED");
    }

    if (!bypassClaimToken) {
      const storedToken = normalizeNullableString(person.inviteClaimToken);
      const providedToken = normalizeNullableString(claimToken);
      if (requireClaimToken || storedToken || providedToken) {
        if (!storedToken || !providedToken) {
          throw new Error("INVALID_CLAIM_TOKEN");
        }
        if (
          person.inviteClaimExpiresAt &&
          Date.parse(person.inviteClaimExpiresAt) < Date.now()
        ) {
          throw new Error("CLAIM_TOKEN_EXPIRED");
        }
        const storedBuf = Buffer.from(storedToken, "utf8");
        const providedBuf = Buffer.from(providedToken, "utf8");
        if (
          storedBuf.length !== providedBuf.length ||
          !crypto.timingSafeEqual(storedBuf, providedBuf)
        ) {
          throw new Error("INVALID_CLAIM_TOKEN");
        }
      }
    }

    const canonicalIdentity = this._ensureUserIdentity(db, userId);
    if (!canonicalIdentity) {
      return null;
    }

    const existingLinkedPerson = db.persons.find(
      (entry) =>
        entry.treeId === treeId &&
        entry.userId === userId &&
        entry.id !== person.id,
    );
    if (existingLinkedPerson) {
      this._mergePersonIntoClaimTarget(db, {
        treeId,
        preferredPerson: person,
        duplicatePerson: existingLinkedPerson,
        userId,
        actorId: userId,
      });
    }

    person.userId = userId;
    person.inviteClaimToken = null;
    person.inviteClaimCreatedBy = null;
    person.inviteClaimExpiresAt = null;
    // additive=true: НЕ перезатирать имя/гендер/birthDate/фото
    // существующего слота в дереве. Если владелец дерева заполнил
    // поля под этого человека, они остаются как есть. Если что-то
    // пусто — заполняем из профиля нового пользователя.
    applyCanonicalProfileToPerson(person, user.profile, {additive: true});
    if (!this._attachPersonToIdentity(db, person, canonicalIdentity, userId)) {
      return false;
    }

    tree.memberIds = Array.isArray(tree.memberIds) ? tree.memberIds : [];
    tree.members = Array.isArray(tree.members) ? tree.members : [];
    if (!tree.memberIds.includes(userId)) {
      tree.memberIds.push(userId);
    }
    if (!tree.members.includes(userId)) {
      tree.members.push(userId);
    }
    this._ensureSemyaMembershipForLegacyJoin(db, tree, userId);
    // Invited user joined a family tree via person-card link — mark incomplete onboarding skipped.
    db.onboardingStates = db.onboardingStates || [];
    const onboardingIdx = db.onboardingStates.findIndex((s) => s.userId === userId);
    if (onboardingIdx >= 0 && !db.onboardingStates[onboardingIdx].completed) {
      db.onboardingStates[onboardingIdx] = {
        ...db.onboardingStates[onboardingIdx],
        skipped: true,
        skippedAt: db.onboardingStates[onboardingIdx].skippedAt || nowIso(),
        updatedAt: nowIso(),
      };
      this._onboardingIncompleteCache?.set(userId, false);
    }
    tree.updatedAt = nowIso();
    this._reconcilePersonIdentities(db);

    await this._write(db);
    return structuredClone(person);
  },

  async findPersonByUserId(treeId, userId) {
    const db = await this._read();
    const person = db.persons.find(
      (entry) => entry.treeId === treeId && entry.userId === userId,
    );
    if (!person) return null;
    return this._buildPersonViewFromGraph(db, treeId, person.id);
  },

  // Phase 0 of the unified-graph migration: when the user adds a
  // relative on tree T2, surface relatives they ALREADY entered on
  // any of their other trees so they don't have to re-type the same
  // person. The picker calls this with a name fragment; we walk the
  // user's accessible trees and rank persons by:
  //   1. Whether the person's tree is the currently-open one
  //      (excluded entirely — caller passes excludeTreeId so the
  //      picker doesn't suggest someone already on this tree).
  //   2. Substring match against displayName (case-insensitive).
  // Limit defaults to 20 — UI only shows ~6 at a time, but we
  // overfetch so the user can keep typing without round-tripping.
  //
  // Privacy: scoped to the caller's accessible trees only. We never
  // leak other users' graphs through this endpoint — that's a
  // future Phase 4 feature with explicit consent.
  // SPEED-12: db — опциональный уже прочитанный снимок (GET
  // /v1/persons/search читает один раз и передаёт тот же db в
  // filterLegacyPersonsByGraphVisibility ниже по цепочке). Read-only:
  // buildCanonicalPersonView клонирует person на возврат, db не трогает.
  async searchPersonsForUser({
    userId,
    query = "",
    excludeTreeId = null,
    limit = 20,
    db: prefetchedDb = null,
  } = {}) {
    const db = prefetchedDb || (await this.readSharedSnapshot());
    const normalizedUserId = normalizeNullableString(userId);
    if (!normalizedUserId) {
      return [];
    }

    const accessibleTrees = db.trees.filter((tree) =>
      this._userCanAccessTreeRecord(tree, normalizedUserId, db),
    );
    if (accessibleTrees.length === 0) {
      return [];
    }

    const treeById = new Map(accessibleTrees.map((tree) => [tree.id, tree]));
    const normalizedExcludeTreeId = normalizeNullableString(excludeTreeId);
    const trimmedQuery = String(query || "").trim().toLowerCase();
    const safeLimit = Math.min(
      Math.max(Number(limit) || 20, 1),
      50,
    );

    const matches = [];
    for (const person of db.persons) {
      if (!treeById.has(person.treeId)) {
        continue;
      }
      if (
        normalizedExcludeTreeId &&
        person.treeId === normalizedExcludeTreeId
      ) {
        continue;
      }

      const haystack = String(person.name || "").toLowerCase();
      if (trimmedQuery && !haystack.includes(trimmedQuery)) {
        continue;
      }

      matches.push({
        person,
        tree: treeById.get(person.treeId),
        // Names that START with the query rank before mid-string
        // matches — closer to how iOS/Android contacts pickers feel.
        rank: trimmedQuery && haystack.startsWith(trimmedQuery) ? 0 : 1,
      });

      if (matches.length >= safeLimit * 4) {
        // Cap the inner walk so pathological queries (huge graph,
        // empty query) don't hold the event loop. We still pick the
        // best `safeLimit` after sort; the rest get dropped.
        break;
      }
    }

    matches.sort((left, right) => {
      if (left.rank !== right.rank) {
        return left.rank - right.rank;
      }
      return String(left.person.name || "").localeCompare(
        String(right.person.name || ""),
      );
    });

    return matches.slice(0, safeLimit).map(({person, tree}) => ({
      ...buildCanonicalPersonView(db, person),
      treeName: tree.name || "",
    }));
  },

  // D1: применённые слияния, видимые зрителю — секция «Объединённые
  // ранее» на экране «Один человек?». Только те, где зритель был
  // ответственным.
  async listMergedProposalsForUser(userId, {limit = 50} = {}) {
    const normalizedUserId = normalizeNullableString(userId);
    const db = await this._read();
    return (db.mergeProposals || [])
      .filter(
        (proposal) =>
          proposal.status === "accepted" &&
          Boolean(proposal.mergeApplied) &&
          normalizeParticipantIds(proposal.reviewerUserIds).includes(
            normalizedUserId,
          ),
      )
      .sort((left, right) =>
        String(right.resolvedAt || right.createdAt || "").localeCompare(
          String(left.resolvedAt || left.createdAt || ""),
        ),
      )
      .slice(0, Math.max(0, Math.min(Number(limit) || 50, 100)))
      .map((proposal) =>
        structuredClone(this._mergeProposalView(db, proposal, normalizedUserId)),
      );
  },

  // /v1/me/edit-grants: каждый grantee видит свои active + revoked
  // за последние N дней (default 30 — DECISIONS.md 2026-05-10 Q3
  // намеренно совпадает с hardDeleteScheduledAt window). Старее —
  // в audit-only state, не отдаём в UI.
  async listMyGrantsForUser({userId, includeRevokedSinceDays = 30}) {
    const normalizedUser = normalizeNullableString(userId);
    if (!normalizedUser) return [];
    const db = await this._read();
    const cutoff = new Date(Date.now() - includeRevokedSinceDays * 86_400_000);
    return (db.graphPersonEditGrants || [])
      .filter((entry) => entry.granteeUserId === normalizedUser)
      .filter((entry) => {
        if (!entry.revokedAt) return true;
        const revoked = new Date(entry.revokedAt);
        return Number.isFinite(revoked.getTime()) && revoked >= cutoff;
      })
      .map((entry) => structuredClone(entry));
  },

  // Helper: кто owner данного graphPerson? Если узел представляет
  // user-аккаунт — это он. Иначе — кто его создал в графе
  // (e.g. deceased ancestor добавил юзер X).
  _graphPersonOwnerUserId(graphPerson) {
    if (!graphPerson) return null;
    return graphPerson.userId || graphPerson.createdBy || null;
  },

  // Какой graphPerson «представляет» данного user-аккаунта? Это
  // его self-node, идентичен `users[userId].identityId`.
  // Используется как стартовая точка blood-BFS для visibility check.
  _selfGraphPersonIdForUser(db, userId) {
    const normalizedUserId = normalizeNullableString(userId);
    if (!normalizedUserId) return null;
    const user = (db.users || []).find((entry) => entry.id === normalizedUserId);
    if (!user) return null;
    const identityId = normalizeNullableString(user.identityId);
    if (!identityId) return null;
    const graphPerson = (db.graphPersons || []).find(
      (entry) => entry.id === identityId && !entry.deletedAt,
    );
    return graphPerson ? graphPerson.id : null;
  },

  // ответ A: «может ли viewer видеть этот graphPerson»? Owner и
  // grants — всегда yes. Иначе — visibility level + (для
  // connected-via-blood-graph) BFS до MAX hops.
  // Вызывается из cross-tree picker / identity-suggestions /
  // /v1/graph/relation chain hydration / future /me/extended-family.
  //
  // `context` — опциональный кэш для batch-вызовов (SPEED-8d): когда
  // caller проверяет ОДНОГО и того же viewer'а по многим graphPerson
  // за один запрос (filterLegacyPersonsByGraphVisibility), он может
  // один раз посчитать viewerSelfGraphPersonId и adjacency и передать
  // их сюда — тогда single-call путь (без context) остаётся байт-в-
  // байт таким же, каким был: при context===null поведение НИЧЕМ не
  // отличается от прежнего (свежий _selfGraphPersonIdForUser + свежая
  // _buildBloodAdjacency внутри _findBloodRelationBetween).
  _userCanSeeGraphPerson(db, graphPerson, viewerUserId, context = null) {
    if (!graphPerson || graphPerson.deletedAt) return false;
    const normalizedViewer = normalizeNullableString(viewerUserId);
    if (!normalizedViewer) return false;

    const owner = this._graphPersonOwnerUserId(graphPerson);
    if (owner === normalizedViewer) return true;

    // Любой active edit/view grant даёт visibility — без этого
    // owner-only узел нельзя показать даже granted-юзеру, который
    // должен его редактировать.
    const hasGrant = (db.graphPersonEditGrants || []).some(
      (entry) =>
        entry.graphPersonId === graphPerson.id &&
        entry.granteeUserId === normalizedViewer &&
        !entry.revokedAt,
    );
    if (hasGrant) return true;

    const visibility = this._effectiveGraphPersonVisibility(graphPerson);
    if (visibility === "public") return true;
    if (visibility === "owner-only") return false;

    // connected-via-blood-graph (default).
    const viewerSelfId =
      context && Object.prototype.hasOwnProperty.call(context, "viewerSelfGraphPersonId")
        ? context.viewerSelfGraphPersonId
        : this._selfGraphPersonIdForUser(db, normalizedViewer);
    if (!viewerSelfId) return false;
    if (viewerSelfId === graphPerson.id) return true;

    const path = this._findBloodRelationBetween(
      db,
      viewerSelfId,
      graphPerson.id,
      {
        maxDepth: CONNECTED_VISIBILITY_MAX_HOPS,
        adjacency: context ? context.adjacency : null,
      },
    );
    return path !== null;
  },

  // ответ C: «может ли viewer редактировать этот graphPerson»?
  // Default — только owner. `scope` отделяет «edit canonical
  // fields» / «approve merge-proposal» / «soft-delete», грант
  // выписывается под конкретный scope.
  _userCanEditGraphPerson(db, graphPerson, viewerUserId, scope = "edit") {
    if (!graphPerson || graphPerson.deletedAt) return false;
    const normalizedViewer = normalizeNullableString(viewerUserId);
    if (!normalizedViewer) return false;

    const owner = this._graphPersonOwnerUserId(graphPerson);
    if (owner === normalizedViewer) return true;

    return (db.graphPersonEditGrants || []).some(
      (entry) =>
        entry.graphPersonId === graphPerson.id &&
        entry.granteeUserId === normalizedViewer &&
        entry.scope === scope &&
        !entry.revokedAt,
    );
  },

  // ответ A.3: sensitive attribute fields (category=contacts —
  // содержит телефон, e-mail, адрес) — owner-only ВСЕГДА,
  // независимо от node visibility. Public-узел всё равно не
  // показывает домашний телефон.
  //
  // Контракт: для не-sensitive field возвращает true БЕЗ
  // дополнительного visibility check. Visibility-уровень gate
  // на cross-tree READ paths делается отдельно (в
  // filterLegacyPersonsByGraphVisibility); этот метод —
  // category-only filter поверх уже-passed access path. Иначе
  // tree-creator после claim чужим юзером терял бы read-access
  // на собственные дерево-attributes (он не owner graphPerson'а
  // больше, но он tree-creator, и через requireTreeAccess уже
  // прошёл).
  _userCanSeeSensitiveAttributeField(db, graphPerson, viewerUserId, attributeField) {
    if (!SENSITIVE_ATTRIBUTE_FIELDS.has(String(attributeField || ""))) {
      return true;
    }
    if (!graphPerson) return false;
    const normalizedViewer = normalizeNullableString(viewerUserId);
    if (!normalizedViewer) return false;
    const owner = this._graphPersonOwnerUserId(graphPerson);
    return owner === normalizedViewer;
  },

  // SPEED-10: `cache` — опциональный объект {circles, identities} (см.
  // _createCircleVisibilityCache), построенный ОДИН раз вызывающим циклом
  // (listPosts/listStories/listGatherings/listPolls/getBranchDigest/
  // searchPosts). Без него ensureCirclesForTree(db, treeId) заново
  // пересобирает ВСЕ авто-круги дерева — BFS-обход persons×relations
  // (buildAutoCircleSpecsForTree) — на КАЖДЫЙ элемент ленты, хотя treeId
  // (и db) внутри одного вызова не меняются; аналогично
  // _userIdentityIdsInTree сканирует db.persons заново на каждый элемент.
  // db.circles уже содержит нужные записи после первого вызова
  // (ensureCirclesForTree идемпотентна на неизменном db), так что
  // повторные вызовы с тем же treeId в рамках одного db-снимка дают ТОТ
  // ЖЕ результат — см. docs/speed_measurement.md SPEED-10. Без `cache` —
  // прежнее поведение (одиночные вызовы вроде createPost/createStory, где
  // строить кэш ради одного circleId незачем).
  _canUserViewCircleContent(
    db,
    {treeId, circleId: rawCircleId = null, authorId = null, viewerUserId = null},
    cache = null,
  ) {
    const normalizedViewerUserId = normalizeNullableString(viewerUserId);
    if (!normalizedViewerUserId || !treeId) {
      return true;
    }
    if (authorId === normalizedViewerUserId) {
      return true;
    }

    // SPEED-11: no-op unless `db` is the frozen shared snapshot
    // (readSharedSnapshot) — see _writableCirclesViewForTree above.
    const effectiveDb = this._writableCirclesViewForTree(db, treeId, cache);

    const explicitCircleId = normalizeNullableString(rawCircleId);
    let allTreeCircle;
    if (cache) {
      if (!cache.circles.has(treeId)) {
        cache.circles.set(treeId, ensureCirclesForTree(effectiveDb, treeId));
      }
      ({allTreeCircle} = cache.circles.get(treeId));
    } else {
      ({allTreeCircle} = ensureCirclesForTree(effectiveDb, treeId));
    }
    const circleId = explicitCircleId || allTreeCircle?.id;
    const circle = effectiveDb.circles.find(
      (entry) => entry.treeId === treeId && entry.id === circleId,
    );
    if (!circle) {
      return !explicitCircleId;
    }
    if (circle.kind === "all_tree") {
      return true;
    }

    let viewerIdentityIds;
    if (cache) {
      const identityCacheKey = `${treeId}\x00${normalizedViewerUserId}`;
      if (!cache.identities.has(identityCacheKey)) {
        cache.identities.set(
          identityCacheKey,
          this._userIdentityIdsInTree(effectiveDb, treeId, normalizedViewerUserId),
        );
      }
      viewerIdentityIds = cache.identities.get(identityCacheKey);
    } else {
      viewerIdentityIds = this._userIdentityIdsInTree(
        effectiveDb,
        treeId,
        normalizedViewerUserId,
      );
    }
    if (viewerIdentityIds.size === 0) {
      return false;
    }

    return effectiveDb.circleMembers.some((entry) => {
      return (
        entry.treeId === treeId &&
        entry.circleId === circle.id &&
        viewerIdentityIds.has(normalizeNullableString(entry.identityId))
      );
    });
  },

  _canUserViewCirclePost(db, post, viewerUserId, cache = null) {
    if (!post) {
      return true;
    }
    // Audience model: a post is visible if the viewer is in the
    // audience of ANY branch the post was published to. The primary
    // branch (post.treeId) honors the post's targeted circle
    // (post.circleId), so circle-targeted posts stay scoped on the
    // tree the author chose. Additional branches in post.branchIds
    // (Phase 3.4 multi-branch fan-out) are checked at the all_tree
    // level — circles are per-tree by construction, so when an
    // author fans a post out across branches they implicitly accept
    // the broader (all-members) audience for the extra branches.
    //
    // Earlier this only checked post.treeId, which silently dropped
    // posts for viewers who belonged to a secondary branch but not
    // the primary one. User-visible bug: post in branchIds=[A, B],
    // viewer in B only, post.treeId=A → viewer never sees it even
    // though the author fan-out targeted B explicitly.
    const normalizedViewerUserId = normalizeNullableString(viewerUserId);
    if (!normalizedViewerUserId) {
      return true;
    }
    if (post.authorId === normalizedViewerUserId) {
      return true;
    }
    const primaryTree = (db.trees || []).find(
      (entry) => entry.id === post.treeId,
    );
    if (
      primaryTree &&
      this._userCanAccessTreeRecord(primaryTree, normalizedViewerUserId, db) &&
      this._canUserViewCircleContent(db, {
        treeId: post.treeId,
        circleId: post.circleId,
        authorId: post.authorId,
        viewerUserId: normalizedViewerUserId,
      }, cache)
    ) {
      return true;
    }
    const branchIds = Array.isArray(post.branchIds) ? post.branchIds : [];
    for (const branchId of branchIds) {
      if (!branchId || branchId === post.treeId) continue;
      const branchTree = (db.trees || []).find(
        (entry) => entry.id === branchId,
      );
      if (
        branchTree &&
        this._userCanAccessTreeRecord(branchTree, normalizedViewerUserId, db) &&
        this._canUserViewCircleContent(db, {
          treeId: branchId,
          circleId: null,
          authorId: post.authorId,
          viewerUserId: normalizedViewerUserId,
        }, cache)
      ) {
        return true;
      }
    }
    return false;
  },

  _listAccessibleTreeUserIds(db, tree) {
    if (!tree) return [];
    const useSemyaModel =
      String(process.env.RODNYA_FEDERATED_SEMYI_ENABLED || "")
        .trim()
        .toLowerCase() === "true";
    if (useSemyaModel && tree.semyaId) {
      const semya = (db.semyi || []).find(
        (entry) => entry.id === tree.semyaId && !entry.deletedAt,
      );
      if (semya) {
        return Array.from(
          new Set(
            (db.semyaMembers || [])
              .filter((m) => m.semyaId === semya.id && !m.hiddenAt)
              .map((m) => normalizeNullableString(m.userId))
              .filter(Boolean),
          ),
        );
      }
    }
    return Array.from(
      new Set(
        [tree.creatorId, ...(Array.isArray(tree.memberIds) ? tree.memberIds : [])]
          .map((id) => normalizeNullableString(id))
          .filter(Boolean),
      ),
    );
  },

  /// Phase 6.5+ auto-refresh: tree-mutation audience. Used by route
  /// layer для dispatch `tree_mutated` silent notification после
  /// person/relation mutations. Returns userIds (minus actor) что
  /// must refetch tree state.
  ///
  /// Composition (union, deduplicated, actor excluded):
  ///   1. Tree owner (`tree.creatorId`).
  ///   2. Tree members (`tree.memberIds`) — co-editors / branch
  ///      collaborators.
  ///   3. Edit-grant holders на graphPersons в этой tree
  ///      (`graphPersonEditGrants` rows where `revokedAt=null`).
  ///   4. Identity-linked users — `graphPerson.userId !== null`
  ///      means пользователь claimed identity; они owners своих
  ///      cards across trees.
  ///
  /// Privacy fence rationale: `tree_mutated` payload carries только
  /// `{treeId, kind, actorUserId}` — НЕ personId либо diff. Recipient
  /// does GET tree, backend filters visible content per Phase 3.1/
  /// 3.4 visibility rules. Audience being broader does NOT leak
  /// content; broader audience = more refresh pings но zero
  /// information disclosure beyond «something changed».
  async resolveTreeAudienceUserIds(treeId, {excludeUserId = null} = {}) {
    const normalizedTreeId = String(treeId || "").trim();
    if (!normalizedTreeId) return [];
    const normalizedExcluded = excludeUserId
      ? String(excludeUserId).trim()
      : "";
    const db = await this._read();
    const tree = (db.trees || []).find((t) => t.id === normalizedTreeId);
    if (!tree) return [];

    const audience = new Set();
    if (tree.creatorId && tree.creatorId !== normalizedExcluded) {
      audience.add(tree.creatorId);
    }
    const memberIds = Array.isArray(tree.memberIds)
      ? tree.memberIds
      : Array.isArray(tree.members)
          ? tree.members
          : [];
    for (const memberId of memberIds) {
      if (!memberId || memberId === normalizedExcluded) continue;
      audience.add(memberId);
    }

    // GraphPersons на этой tree — derive presence через legacyPersonIds
    // lookup: graphPerson belongs to tree iff any of its legacy person
    // ids lives в db.persons с этим treeId. (graphPerson не carries
    // `legacyTreeIds` directly — это поле живёт только на graphRelation
    // и personIdentity.) Filter is identity-linked owners + edit-grant
    // anchors.
    const personsByTree = new Map();
    for (const p of db.persons || []) {
      if (p.treeId !== normalizedTreeId) continue;
      personsByTree.set(p.id, p);
    }
    const treeGraphPersonIds = new Set();
    for (const gp of db.graphPersons || []) {
      if (gp.deletedAt) continue;
      const legacyPersonIds = Array.isArray(gp.legacyPersonIds)
        ? gp.legacyPersonIds
        : [];
      const inTree = legacyPersonIds.some((id) => personsByTree.has(id));
      if (!inTree) continue;
      treeGraphPersonIds.add(gp.id);
      if (gp.userId && gp.userId !== normalizedExcluded) {
        audience.add(gp.userId);
      }
    }

    for (const grant of db.graphPersonEditGrants || []) {
      if (grant.revokedAt) continue;
      if (!treeGraphPersonIds.has(grant.graphPersonId)) continue;
      if (!grant.granteeUserId) continue;
      if (grant.granteeUserId === normalizedExcluded) continue;
      audience.add(grant.granteeUserId);
    }

    // Phase B Ship 9: extension к семя members когда tree bound
    // (tree.semyaId set). Strictly ADDITIVE — Set union semantics
    // never reduces existing audience. См. SHIP-9-AUDIENCE-DIFF.md
    // для full safety analysis. Edge: pre-Ship-5 семьи without
    // dual-write, либо seyma membership drift из tree.memberIds —
    // catches missing recipients. Soft-deleted семья memberships
    // (hiddenAt set by softDeleteSemya) excluded автоматически.
    if (tree.semyaId) {
      for (const m of db.semyaMembers || []) {
        if (m.semyaId !== tree.semyaId) continue;
        if (m.hiddenAt) continue;
        if (!m.userId) continue;
        if (m.userId === normalizedExcluded) continue;
        audience.add(m.userId);
      }
    }

    return Array.from(audience);
  },

  /// Audience = union of `tree.memberIds` across every branch the
  /// post was fanned out to. Returns the recipient userIds (minus
  /// the author) so the route layer can iterate and call
  /// `createAndDispatchNotification` — that's where push +
  /// realtime + in-app row all converge. Doing the dispatch
  /// inline in `createPost` would bypass push fan-out (the store
  /// has no access to the gateway), which was the original bug
  /// users reported as "уведомления на телефоне не работают".
  async resolvePostAudienceUserIds(postId) {
    const db = await this._read();
    const post = db.posts.find((entry) => entry.id === postId);
    if (!post) return [];
    const branchIds = new Set(
      Array.isArray(post.branchIds) && post.branchIds.length > 0
        ? post.branchIds
        : [post.treeId].filter(Boolean),
    );
    const circleCache = this._createCircleVisibilityCache();
    const audienceUserIds = new Set();
    for (const branchId of branchIds) {
      const tree = db.trees.find((entry) => entry.id === branchId);
      if (!tree) continue;
      const memberIds = this._listAccessibleTreeUserIds(db, tree);
      for (const memberId of memberIds) {
        if (!memberId || memberId === post.authorId) continue;
        if (!this._canUserViewCirclePost(db, post, memberId, circleCache)) {
          continue;
        }
        audienceUserIds.add(memberId);
      }
    }
    return Array.from(audienceUserIds);
  },

  // Audience = union of tree.memberIds across every branch the gathering
  // was fanned out to, minus the author. Clone of
  // resolvePostAudienceUserIds so the route layer can dispatch
  // gathering_created push/realtime/inbox the same way.
  async resolveGatheringAudienceUserIds(gatheringId) {
    const db = await this._read();
    const gathering = db.gatherings.find((entry) => entry.id === gatheringId);
    if (!gathering) return [];
    const branchIds = new Set(
      Array.isArray(gathering.branchIds) && gathering.branchIds.length > 0
        ? gathering.branchIds
        : [gathering.treeId].filter(Boolean),
    );
    const circleCache = this._createCircleVisibilityCache();
    const audienceUserIds = new Set();
    for (const branchId of branchIds) {
      const tree = db.trees.find((entry) => entry.id === branchId);
      if (!tree) continue;
      const memberIds = this._listAccessibleTreeUserIds(db, tree);
      for (const memberId of memberIds) {
        if (!memberId || memberId === gathering.authorId) continue;
        if (!this._canUserViewCirclePost(db, gathering, memberId, circleCache)) {
          continue;
        }
        audienceUserIds.add(memberId);
      }
    }
    return Array.from(audienceUserIds);
  },

  // BUG 3: фото граф-персоны (person.photoUrl), поставленное человеку ДО
  // регистрации, и аватар user-аккаунта (profile.photoUrl) — разные поля.
  // Чат/звонок резолвят аватар из user-профиля (пустой у только что
  // вошедшего) → плейсхолдер «А», хотя на дереве фото есть. Фолбэк: если
  // у user аватара нет, берём фото СВЯЗАННОЙ граф-персоны — по прямой
  // связи person.userId и через identity.claimedByUserId/userId (обе
  // надёжно покрывают линк user→person).
  _resolveAvatarUrlForUser(db, userId, profilePhotoUrl) {
    const direct = normalizeNullableString(profilePhotoUrl);
    if (direct) {
      return direct;
    }
    const normalizedUserId = normalizeNullableString(userId);
    if (!normalizedUserId) {
      return null;
    }
    const persons = Array.isArray(db.persons) ? db.persons : [];
    const personPhoto = (person) =>
      normalizeNullableString(person?.primaryPhotoUrl || person?.photoUrl);

    for (const person of persons) {
      if (person && person.userId === normalizedUserId) {
        const photo = personPhoto(person);
        if (photo) {
          return photo;
        }
      }
    }

    const identities = Array.isArray(db.personIdentities)
      ? db.personIdentities
      : [];
    const linkedIdentityIds = new Set(
      identities
        .filter(
          (identity) =>
            normalizeNullableString(identity?.claimedByUserId) ===
              normalizedUserId ||
            normalizeNullableString(identity?.userId) === normalizedUserId,
        )
        .map((identity) => identity.id),
    );
    if (linkedIdentityIds.size > 0) {
      for (const person of persons) {
        if (person && linkedIdentityIds.has(person.identityId)) {
          const photo = personPhoto(person);
          if (photo) {
            return photo;
          }
        }
      }
    }
    return null;
  },

  // Group late-join: merge a participant's freshly-minted session into the
  // call (sessionByUserId + joinedSessionByUserId). Works on an ACTIVE call
  // (does NOT require state==='ringing'), and on the FIRST joiner flips
  // ringing -> active (filling the scalar back-compat fields). Idempotent per
  // (user, session): re-adding the same pair just re-writes the same values.
  async addCallParticipantSession({callId, userId, sessionId, session}) {
    return this._mutate((db, skip) => {
      const storedCall = db.calls.find((entry) => String(entry?.id || "") === callId);
      const call = normalizeStoredCall(storedCall);
      if (!storedCall || !call) {
        return skip(null);
      }
      const normalizedUserId = String(userId || "").trim();
      if (!normalizedUserId || !call.participantIds.includes(normalizedUserId)) {
        return skip(false);
      }
      if (isCallTerminalState(call.state)) {
        return skip(undefined);
      }

      const timestamp = nowIso();
      const normalizedSessionId = normalizeNullableString(sessionId);
      const normalizedSession = normalizeCallSession(session);

      storedCall.metrics = normalizeCallMetrics(storedCall.metrics);
      storedCall.sessionByUserId = normalizeCallSessionMap(storedCall.sessionByUserId);
      storedCall.joinedSessionByUserId = normalizeJoinedSessionMap(
        storedCall.joinedSessionByUserId,
      );

      if (normalizedSession) {
        storedCall.sessionByUserId[normalizedUserId] = normalizedSession;
        if (!normalizeNullableString(storedCall.roomName)) {
          storedCall.roomName = normalizedSession.roomName;
        }
      }
      if (normalizedSessionId) {
        storedCall.joinedSessionByUserId[normalizedUserId] = normalizedSessionId;
      }

      if (call.state === "ringing") {
        // First joiner makes the call active. Scalars are set once (the first
        // joiner wins) so old clients still resolve the owning session.
        storedCall.state = "active";
        storedCall.acceptedAt = storedCall.acceptedAt || timestamp;
        storedCall.endedAt = null;
        storedCall.endedReason = null;
        if (!normalizeNullableString(storedCall.acceptedByUserId)) {
          storedCall.acceptedByUserId = normalizedUserId;
          storedCall.acceptedBySessionId = normalizedSessionId;
        }
        if (
          storedCall.metrics.acceptLatencyMs === null ||
          storedCall.metrics.acceptLatencyMs === undefined
        ) {
          storedCall.metrics.acceptLatencyMs = Math.max(
            0,
            new Date(timestamp).getTime() - new Date(call.createdAt).getTime(),
          );
        }
      }

      storedCall.updatedAt = timestamp;
      return structuredClone(normalizeStoredCall(storedCall));
    });
  },

  async createProfileContribution({
    treeId,
    personId,
    authorUserId,
    message = null,
    fields = {},
  }) {
    const db = await this._read();
    db.profileContributions = Array.isArray(db.profileContributions)
      ? db.profileContributions
      : [];

    const person = db.persons.find(
      (entry) => entry.id === personId && entry.treeId === treeId,
    );
    if (!person || !person.userId) {
      return null;
    }

    const targetUser = db.users.find((entry) => entry.id === person.userId);
    if (!targetUser) {
      return null;
    }
    if (
      normalizeProfileContributionPolicy(
        targetUser.profile?.profileContributionPolicy,
      ) !== "suggestions"
    ) {
      return false;
    }

    const normalizedFields = normalizeProfileContributionFields(fields);
    if (Object.keys(normalizedFields).length === 0) {
      return undefined;
    }

    const contribution = {
      id: crypto.randomUUID(),
      treeId,
      personId,
      targetUserId: person.userId,
      authorUserId: normalizeNullableString(authorUserId),
      message: normalizeNullableString(message),
      fields: normalizedFields,
      status: "pending",
      createdAt: nowIso(),
      updatedAt: nowIso(),
      respondedAt: null,
      responderUserId: null,
    };

    db.profileContributions.unshift(contribution);
    await this._write(db);
    return structuredClone(contribution);
  },

  // SPEED-12: readSharedSnapshot() — read-only список, entry клонируется
  // на возврат. Локальная const вместо `db.profileContributions =`
  // (старый идиом переприсваивал поле на db) — на заморожённом снимке
  // присваивание в sloppy-mode тихо no-op'ается; локальная переменная
  // не зависит от того, заморожен db или нет.
  async listProfileContributions(targetUserId, {status = null} = {}) {
    const db = await this.readSharedSnapshot();
    const profileContributions = Array.isArray(db.profileContributions)
      ? db.profileContributions
      : [];

    return profileContributions
      .filter((entry) => {
        if (entry.targetUserId !== targetUserId) {
          return false;
        }
        if (status && entry.status !== status) {
          return false;
        }
        return true;
      })
      .sort((left, right) =>
        String(right.createdAt || "").localeCompare(String(left.createdAt || "")),
      )
      .map((entry) => structuredClone(entry));
  },

  async respondToProfileContribution(targetUserId, contributionId, {
    accept,
  }) {
    const db = await this._read();
    db.profileContributions = Array.isArray(db.profileContributions)
      ? db.profileContributions
      : [];

    const contribution = db.profileContributions.find(
      (entry) =>
        entry.id === contributionId &&
        entry.targetUserId === targetUserId &&
        entry.status === "pending",
    );
    if (!contribution) {
      return null;
    }

    let updatedUser = null;
    if (accept === true) {
      updatedUser = await this.updateProfile(targetUserId, (profile) => {
        const nextProfile = {
          ...profile,
          ...normalizeProfileContributionFields(contribution.fields),
        };
        nextProfile.displayName =
          composeDisplayNameFromProfile(nextProfile) || profile.displayName || "";
        return nextProfile;
      });
    }

    const nextDb = accept === true ? await this._read() : db;
    nextDb.profileContributions = Array.isArray(nextDb.profileContributions)
      ? nextDb.profileContributions
      : [];
    const storedContribution = nextDb.profileContributions.find(
      (entry) => entry.id === contributionId,
    );
    if (!storedContribution) {
      return null;
    }

    storedContribution.status = accept === true ? "accepted" : "rejected";
    storedContribution.respondedAt = nowIso();
    storedContribution.updatedAt = storedContribution.respondedAt;
    storedContribution.responderUserId = targetUserId;
    await this._write(nextDb);

    return {
      contribution: structuredClone(storedContribution),
      user: updatedUser,
    };
  },

  async listProfileNotes(userId) {
    const db = await this._read();
    const user = db.users.find((entry) => entry.id === userId);
    if (!user) {
      return null;
    }

    const notes = Array.isArray(user.profileNotes) ? user.profileNotes : [];
    return notes
      .slice()
      .sort((left, right) => {
        return String(right.createdAt || "").localeCompare(
          String(left.createdAt || ""),
        );
      })
      .map((note) => structuredClone(note));
  },

  async addProfileNote(userId, {title, content}) {
    const db = await this._read();
    const user = db.users.find((entry) => entry.id === userId);
    if (!user) {
      return null;
    }

    const note = createProfileNote({title, content});
    user.profileNotes = Array.isArray(user.profileNotes) ? user.profileNotes : [];
    user.profileNotes.unshift(note);
    user.updatedAt = nowIso();
    await this._write(db);
    return structuredClone(note);
  },

  async updateProfileNote(userId, noteId, {title, content}) {
    const db = await this._read();
    const user = db.users.find((entry) => entry.id === userId);
    if (!user) {
      return null;
    }

    user.profileNotes = Array.isArray(user.profileNotes) ? user.profileNotes : [];
    const note = user.profileNotes.find((entry) => entry.id === noteId);
    if (!note) {
      return undefined;
    }

    note.title = String(title || note.title || "").trim();
    note.content = String(content || note.content || "").trim();
    note.updatedAt = nowIso();
    user.updatedAt = nowIso();
    await this._write(db);
    return structuredClone(note);
  },

  async deleteProfileNote(userId, noteId) {
    const db = await this._read();
    const user = db.users.find((entry) => entry.id === userId);
    if (!user) {
      return null;
    }

    user.profileNotes = Array.isArray(user.profileNotes) ? user.profileNotes : [];
    const initialLength = user.profileNotes.length;
    user.profileNotes = user.profileNotes.filter((entry) => entry.id !== noteId);
    if (user.profileNotes.length === initialLength) {
      return false;
    }

    user.updatedAt = nowIso();
    await this._write(db);
    return true;
  },

  async searchUsers({query, limit}) {
    const db = await this._read();
    const normalizedQuery = String(query || "").trim().toLowerCase();
    if (!normalizedQuery) {
      return [];
    }

    return db.users
      .filter((user) => {
        const profile = user.profile || {};
        return (
          String(user.email || "").toLowerCase().includes(normalizedQuery) ||
          String(profile.displayName || "")
            .toLowerCase()
            .includes(normalizedQuery) ||
          String(profile.username || "")
            .toLowerCase()
            .includes(normalizedQuery) ||
          String(profile.firstName || "")
            .toLowerCase()
            .includes(normalizedQuery) ||
          String(profile.lastName || "")
            .toLowerCase()
            .includes(normalizedQuery) ||
          String(profile.middleName || "")
            .toLowerCase()
            .includes(normalizedQuery) ||
          String(profile.maidenName || "")
            .toLowerCase()
            .includes(normalizedQuery) ||
          String(profile.birthPlace || "")
            .toLowerCase()
            .includes(normalizedQuery)
        );
      })
      .slice(0, limit)
      .map((user) => structuredClone(user));
  },

  async searchUsersByField({field, value, limit}) {
    const db = await this._read();
    const normalizedValue = String(value || "").trim().toLowerCase();
    if (!normalizedValue) {
      return [];
    }

    return db.users
      .filter((user) => {
        if (field === "email") {
          return String(user.email || "").toLowerCase() === normalizedValue;
        }

        return (
          String(user.profile?.[field] || "").toLowerCase() === normalizedValue
        );
      })
      .slice(0, limit)
      .map((user) => structuredClone(user));
  },

  async listKinshipChecksForUser({userId, role, status}) {
    const normalizedUser = normalizeNullableString(userId);
    if (!normalizedUser) return [];
    const normalizedRole = role === "target" ? "target" : "initiator";
    const db = await this._read();
    const newlyExpired = this._sweepExpiredKinshipChecks(db);
    if (newlyExpired.length > 0) await this._write(db);

    const field =
      normalizedRole === "target" ? "targetUserId" : "initiatorUserId";
    let filtered = (db.kinshipChecks || []).filter(
      (c) => c[field] === normalizedUser,
    );
    if (status) {
      filtered = filtered.filter((c) => c.status === String(status));
    }
    return filtered.map((c) => structuredClone(c));
  },

  // Target must be a member of the person's tree — either legacy
  // (tree.creatorId / tree.memberIds) or, when the tree is bound to a
  // семья (federated model), an active (non-hidden) семья member. Checked
  // directly against `db` (no store-method call) so it stays safe inside
  // `_mutate`'s applyFn.
  _isUserInTreeOrSemya(db, tree, userId) {
    if (!tree || !userId) return false;
    const useSemyaModel =
      String(process.env.RODNYA_FEDERATED_SEMYI_ENABLED || "")
        .trim()
        .toLowerCase() === "true";
    if (tree.semyaId) {
      const semya = (db.semyi || []).find((s) => s.id === tree.semyaId);
      if (semya?.deletedAt) {
        return false;
      }
      if (semya) {
        const activeMem = (db.semyaMembers || []).some(
          (m) => m.semyaId === semya.id && m.userId === userId && !m.hiddenAt,
        );
        if (useSemyaModel) {
          return activeMem;
        }
        const hiddenMem = (db.semyaMembers || []).some(
          (m) => m.semyaId === semya.id && m.userId === userId && Boolean(m.hiddenAt),
        );
        if (hiddenMem) {
          return false;
        }
        if (activeMem) {
          return true;
        }
      }
    }
    const memberIds = Array.isArray(tree.memberIds) ? tree.memberIds : [];
    return tree.creatorId === userId || memberIds.includes(userId);
  },

  /// role: 'received' (target) | 'issued' (requester). Route validates
  /// role presence/value (400 without role); unknown role defensively
  /// falls back to 'received' here, mirroring listKinshipChecksForUser.
  async listStoryRequestsForUser({userId, role, status}) {
    const normalizedUser = normalizeNullableString(userId);
    if (!normalizedUser) return {requests: [], newlyExpired: []};
    const field = role === "issued" ? "requesterUserId" : "targetUserId";
    const normalizedStatus = status ? String(status) : null;

    return this._mutate((db, skip) => {
      const newlyExpired = this._sweepExpiredStoryRequests(db);
      let filtered = (db.storyRequests || []).filter((r) => r[field] === normalizedUser);
      if (normalizedStatus) {
        filtered = filtered.filter((r) => r.status === normalizedStatus);
      }
      const result = {
        requests: filtered.map((r) => structuredClone(r)),
        newlyExpired: newlyExpired.map((r) => structuredClone(r)),
      };
      return newlyExpired.length > 0 ? result : skip(result);
    });
  },
};
