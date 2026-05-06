function registerAuthSessionRoutes(
  app,
  {
    store,
    mediaStorage,
    requireAuth,
    authResponse,
    sanitizeProfile,
    computeProfileStatus,
    readDeviceContext,
    realtimeHub = null,
    deriveSessionPublicId,
  },
) {
  app.post("/v1/auth/register", async (req, res) => {
    const {email, password, displayName} = req.body || {};

    if (!email || !password || !displayName) {
      res.status(400).json({message: "Нужны email, password и displayName"});
      return;
    }

    // ── Input shape validation ────────────────────────────────────────
    // Without these caps an attacker can:
    //   * register accounts with bogus 64KB display names → DB bloat,
    //     UI breakage in chat list / push notifications;
    //   * register trivially-cracked passwords that still pass scrypt
    //     ("a" / "1");
    //   * smuggle CRLF / control characters into displayName which
    //     end up in email subjects / push titles unescaped;
    //   * register a structurally invalid email → orphan account that
    //     can never reset password.
    const trimmedEmail = String(email).trim();
    const trimmedDisplayName = String(displayName);
    const passwordValue = String(password);

    if (trimmedEmail.length > 254) {
      res.status(400).json({
        message: "Email слишком длинный (максимум 254 символа).",
      });
      return;
    }
    // Pragmatic format check — handle 99% of real addresses without
    // trying to be a full RFC-5322 parser. Format failures here just
    // save us a downstream bounce / orphan-account.
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmedEmail)) {
      res
        .status(400)
        .json({message: "Email указан в некорректном формате."});
      return;
    }
    if (passwordValue.length < 8) {
      res
        .status(400)
        .json({message: "Пароль должен быть минимум 8 символов."});
      return;
    }
    if (passwordValue.length > 1024) {
      // Upper bound to keep scrypt's wall-clock bounded — attacker
      // could otherwise submit a 1 MB password and pin a libuv
      // thread for a second per request. 1024 chars is more than
      // any realistic password manager generates.
      res.status(400).json({message: "Пароль слишком длинный."});
      return;
    }
    // Reject control characters (CR, LF, NUL, etc.) so display names
    // can't break headers / push titles when surfaced.
    // eslint-disable-next-line no-control-regex
    if (/[\x00-\x1f\x7f]/.test(trimmedDisplayName)) {
      res.status(400).json({
        message: "Имя содержит недопустимые символы.",
      });
      return;
    }
    if (trimmedDisplayName.trim().length === 0) {
      res.status(400).json({message: "Имя не может быть пустым."});
      return;
    }
    if (trimmedDisplayName.length > 120) {
      res.status(400).json({
        message: "Имя слишком длинное (максимум 120 символов).",
      });
      return;
    }

    try {
      const user = await store.createUser({
        email: trimmedEmail,
        password: passwordValue,
        displayName: trimmedDisplayName,
      });
      const deviceContext = readDeviceContext(req);
      const sessionTokens = await store.createSession(user.id, deviceContext);
      res.status(201).json(authResponse(user, sessionTokens));
    } catch (error) {
      if (error.message === "EMAIL_ALREADY_EXISTS") {
        res.status(409).json({message: "Этот email уже зарегистрирован"});
        return;
      }
      res.status(500).json({message: "Не удалось зарегистрировать пользователя"});
    }
  });

  app.post("/v1/auth/login", async (req, res) => {
    const {email, password} = req.body || {};
    if (!email || !password) {
      res.status(400).json({message: "Нужны email и password"});
      return;
    }

    const user = await store.authenticate(email, password);
    if (!user) {
      res.status(401).json({message: "Неверный email или пароль"});
      return;
    }

    const deviceContext = readDeviceContext(req);
    const sessionTokens = await store.createSession(user.id, deviceContext);
    res.json(authResponse(user, sessionTokens));
  });

  app.post("/v1/auth/refresh", async (req, res) => {
    const {refreshToken} = req.body || {};
    if (!refreshToken) {
      res.status(400).json({message: "Нужен refreshToken"});
      return;
    }

    const session = await store.findSessionByRefreshToken(refreshToken);
    if (!session) {
      res.status(401).json({message: "Сессия по refreshToken не найдена"});
      return;
    }

    const user = await store.findUserById(session.userId);
    if (!user) {
      res.status(401).json({message: "Пользователь сессии не найден"});
      return;
    }

    if (session.token) {
      await store.deleteSession(session.token);
    }

    // Inherit prior device context so refresh keeps the same device identity.
    const requestDeviceContext = readDeviceContext(req);
    const inheritedDeviceContext = {
      instanceId:
        requestDeviceContext.instanceId || session.instanceId || null,
      deviceName:
        requestDeviceContext.deviceName || session.deviceName || null,
      platform: requestDeviceContext.platform || session.platform || null,
      appVersion:
        requestDeviceContext.appVersion || session.appVersion || null,
    };
    const nextSessionTokens = await store.createSession(
      user.id,
      inheritedDeviceContext,
    );
    res.json(authResponse(user, nextSessionTokens));
  });

  function describeSession(session, currentSessionPublicId) {
    const publicId = deriveSessionPublicId(
      session.token,
      session.instanceId || "",
    );
    return {
      sessionPublicId: publicId,
      deviceName: session.deviceName || null,
      platform: session.platform || null,
      appVersion: session.appVersion || null,
      createdAt: session.createdAt || null,
      lastSeenAt: session.lastSeenAt || null,
      isCurrent: publicId === currentSessionPublicId,
    };
  }

  app.get("/v1/auth/sessions", requireAuth, async (req, res) => {
    const sessions = await store.listSessionsForUser(req.auth.user.id);
    res.json({
      sessions: sessions.map((session) =>
        describeSession(session, req.auth.sessionPublicId),
      ),
      currentSessionPublicId: req.auth.sessionPublicId,
    });
  });

  app.patch("/v1/auth/sessions/:publicId", requireAuth, async (req, res) => {
    const publicId = String(req.params.publicId || "").trim();
    if (!publicId) {
      res.status(400).json({message: "Нужен идентификатор сессии"});
      return;
    }
    const session = await store.findSessionByPublicId(
      req.auth.user.id,
      publicId,
    );
    if (!session) {
      res.status(404).json({message: "Сессия не найдена"});
      return;
    }
    const deviceName =
      req.body && Object.prototype.hasOwnProperty.call(req.body, "deviceName")
        ? req.body.deviceName
        : undefined;
    if (deviceName === undefined) {
      res.status(400).json({message: "Нужно поле deviceName"});
      return;
    }
    const updated = await store.updateSessionMetadata(session.token, {
      deviceName,
    });
    if (!updated) {
      res.status(404).json({message: "Сессия не найдена"});
      return;
    }
    res.json({session: describeSession(updated, req.auth.sessionPublicId)});
  });

  app.delete("/v1/auth/sessions/:publicId", requireAuth, async (req, res) => {
    const publicId = String(req.params.publicId || "").trim();
    if (!publicId) {
      res.status(400).json({message: "Нужен идентификатор сессии"});
      return;
    }
    if (publicId === req.auth.sessionPublicId) {
      res.status(400).json({
        message:
          "Чтобы выйти из текущей сессии, используйте /v1/auth/logout",
      });
      return;
    }
    const session = await store.findSessionByPublicId(
      req.auth.user.id,
      publicId,
    );
    if (!session) {
      res.status(404).json({message: "Сессия не найдена"});
      return;
    }
    await store.deleteSession(session.token);

    if (typeof store.unbindPushDevicesForSession === "function") {
      try {
        await store.unbindPushDevicesForSession({
          userId: req.auth.user.id,
          sessionPublicId: publicId,
        });
      } catch (error) {
        // push cleanup is best-effort; ignore
      }
    }

    if (realtimeHub && typeof realtimeHub.disconnectSession === "function") {
      realtimeHub.disconnectSession(req.auth.user.id, publicId, {
        reason: "session.revoked.remote",
      });
    }

    if (realtimeHub && typeof realtimeHub.publishToUser === "function") {
      realtimeHub.publishToUser(req.auth.user.id, {
        type: "session.list.changed",
        revokedSessionPublicId: publicId,
      });
    }

    res.status(204).send();
  });

  app.get("/v1/auth/session", requireAuth, async (req, res) => {
    const user = await store.findUserById(req.auth.user.id);
    const profile = sanitizeProfile(user.profile);
    res.json({
      session: {
        accessToken: req.auth.token,
        refreshToken: req.auth.session.refreshToken,
        userId: user.id,
      },
      user: {
        id: user.id,
        identityId: user.identityId || null,
        email: user.email,
        displayName: profile.displayName,
        photoUrl: profile.photoUrl,
        providerIds: user.providerIds || ["password"],
      },
      profileStatus: computeProfileStatus(user.profile),
    });
  });

  app.post("/v1/auth/logout", requireAuth, async (req, res) => {
    const sessionPublicId = req.auth.sessionPublicId;
    await store.deleteSession(req.auth.token);
    if (
      sessionPublicId &&
      typeof store.unbindPushDevicesForSession === "function"
    ) {
      try {
        await store.unbindPushDevicesForSession({
          userId: req.auth.user.id,
          sessionPublicId,
        });
      } catch (_) {
        // best-effort
      }
    }
    res.json({ok: true});
  });

  const QR_LOGIN_TTL_MS = 60_000;

  app.post("/v1/auth/qr/start", async (req, res) => {
    const deviceContext = readDeviceContext(req);
    if (!deviceContext.instanceId) {
      res.status(400).json({
        message:
          "Нужен заголовок X-Client-Instance-Id, чтобы привязать сессию к устройству",
      });
      return;
    }
    const expiresAt = new Date(Date.now() + QR_LOGIN_TTL_MS).toISOString();
    const handoff = await store.createAuthHandoff({
      type: "qr_login",
      payload: {
        deviceInfo: deviceContext,
        status: "pending",
      },
      expiresAt,
    });
    res.status(201).json({
      token: handoff.code,
      expiresAt,
    });
  });

  app.get("/v1/auth/qr/poll", async (req, res) => {
    const token = String(req.query?.token || "").trim();
    if (!token) {
      res.status(400).json({message: "Нужен token"});
      return;
    }
    const handoff = await store.findAuthHandoff(token, {type: "qr_login"});
    if (!handoff) {
      res.status(410).json({status: "expired"});
      return;
    }
    const status = String(handoff.payload?.status || "pending");
    if (status !== "approved") {
      res.json({status});
      return;
    }
    const consumed = await store.consumeAuthHandoff(token, {type: "qr_login"});
    if (!consumed) {
      res.status(410).json({status: "expired"});
      return;
    }
    res.json({
      status: "approved",
      auth: consumed.payload?.auth || null,
    });
  });

  app.post("/v1/auth/qr/approve", requireAuth, async (req, res) => {
    const token = String(req.body?.token || "").trim();
    if (!token) {
      res.status(400).json({message: "Нужен token"});
      return;
    }
    const handoff = await store.findAuthHandoff(token, {type: "qr_login"});
    if (!handoff) {
      res.status(410).json({message: "QR-код истёк или не найден"});
      return;
    }
    if (handoff.payload?.status === "approved") {
      res.status(409).json({message: "QR-код уже подтверждён"});
      return;
    }

    const storedDeviceInfo =
      handoff.payload?.deviceInfo && typeof handoff.payload.deviceInfo === "object"
        ? handoff.payload.deviceInfo
        : {};
    if (!storedDeviceInfo.instanceId) {
      res.status(400).json({
        message: "QR-код не содержит данных устройства",
      });
      return;
    }

    const sessionTokens = await store.createSession(req.auth.user.id, {
      instanceId: storedDeviceInfo.instanceId,
      deviceName: storedDeviceInfo.deviceName || null,
      platform: storedDeviceInfo.platform || null,
      appVersion: storedDeviceInfo.appVersion || null,
    });
    const user = await store.findUserById(req.auth.user.id);
    const auth = authResponse(user, sessionTokens);

    await store.updateAuthHandoffPayload(
      token,
      {status: "approved", auth, approvedAt: new Date().toISOString()},
      {type: "qr_login"},
    );

    if (realtimeHub && typeof realtimeHub.publishToUser === "function") {
      realtimeHub.publishToUser(req.auth.user.id, {
        type: "session.list.changed",
        addedSessionPublicId: deriveSessionPublicId(
          sessionTokens.token,
          storedDeviceInfo.instanceId,
        ),
      });
    }

    res.json({
      ok: true,
      sessionPublicId: deriveSessionPublicId(
        sessionTokens.token,
        storedDeviceInfo.instanceId,
      ),
    });
  });

  app.post("/v1/auth/password-reset", async (req, res) => {
    const {email} = req.body || {};
    res.status(202).json({
      ok: true,
      email: email ? String(email).trim().toLowerCase() : null,
      message: "Password reset flow is stubbed in minimal backend",
    });
  });

  app.delete("/v1/auth/account", requireAuth, async (req, res) => {
    const ownedMediaUrls = typeof store.listOwnedMediaUrls === "function"
      ? await store.listOwnedMediaUrls(req.auth.user.id)
      : [];
    await store.deleteUser(req.auth.user.id);

    const mediaCleanupFailures = [];
    for (const mediaUrl of ownedMediaUrls) {
      try {
        await mediaStorage.deleteObjectByUrl(mediaUrl);
      } catch (error) {
        if (
          error?.message === "INVALID_MEDIA_PATH" ||
          error?.message === "UNSUPPORTED_MEDIA_URL" ||
          error instanceof TypeError
        ) {
          continue;
        }

        mediaCleanupFailures.push({
          url: mediaUrl,
          message: error?.message || "unknown_error",
        });
      }
    }

    if (mediaCleanupFailures.length > 0) {
      console.error(
        "[backend] account media cleanup warnings",
        JSON.stringify({
          requestId: req.requestId,
          userId: req.auth.user.id,
          failures: mediaCleanupFailures,
        }),
      );
    }

    res.status(204).send();
  });
}

module.exports = {
  registerAuthSessionRoutes,
};
