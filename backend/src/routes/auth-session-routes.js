function registerAuthSessionRoutes(
  app,
  {
    store,
    mediaStorage,
    requireAuth,
    authResponse,
    sanitizeProfile,
    computeProfileStatus,
  },
) {
  app.post("/v1/auth/register", async (req, res) => {
    const {email, password, displayName} = req.body || {};

    if (!email || !password || !displayName) {
      res.status(400).json({message: "Нужны email, password и displayName"});
      return;
    }

    try {
      const user = await store.createUser({email, password, displayName});
      const sessionTokens = await store.createSession(user.id);
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

    const sessionTokens = await store.createSession(user.id);
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

    const nextSessionTokens = await store.createSession(user.id);
    res.json(authResponse(user, nextSessionTokens));
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
    await store.deleteSession(req.auth.token);
    res.json({ok: true});
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
