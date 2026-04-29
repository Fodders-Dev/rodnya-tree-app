function registerUserRoutes(
  app,
  {
    store,
    requireAuth,
    sanitizeUserProfilePreview,
    sanitizeProfile,
    computeProfileStatus,
    buildProfileViewerContext,
  },
) {
  app.get("/v1/users/search", requireAuth, async (req, res) => {
    const query = String(req.query.query || "");
    const limit = Number(req.query.limit || 10);
    const users = await store.searchUsers({query, limit});

    res.json({
      users: users.map((user) => sanitizeUserProfilePreview(user)),
    });
  });

  app.get("/v1/users/search/by-field", requireAuth, async (req, res) => {
    const field = String(req.query.field || "");
    const value = String(req.query.value || "");
    const limit = Number(req.query.limit || 10);

    if (!field || !value) {
      res.status(400).json({message: "Нужны field и value"});
      return;
    }

    if (field === "phoneNumber") {
      res.status(410).json({
        message:
          "Поиск по номеру отключён. Ищите родственников по username, email, invite link или claim link.",
        nextAction: "search_by_username_or_invite",
      });
      return;
    }

    const users = await store.searchUsersByField({field, value, limit});
    res.json({
      users: users.map((user) => sanitizeUserProfilePreview(user)),
    });
  });

  app.get("/v1/users/:userId/profile", requireAuth, async (req, res) => {
    const user = await store.findUserById(req.params.userId);
    if (!user) {
      res.status(404).json({message: "Пользователь не найден"});
      return;
    }

    const viewerContext = await buildProfileViewerContext(
      req.auth.user.id,
      user.id,
    );
    const isSelfProfile = req.auth.user.id === user.id;
    res.json({
      profile: sanitizeProfile(user.profile, viewerContext),
      profileStatus: isSelfProfile ? computeProfileStatus(user.profile) : null,
    });
  });

  app.patch("/v1/users/:userId/profile", requireAuth, async (req, res) => {
    if (req.params.userId !== req.auth.user.id) {
      res.status(403).json({message: "Изменение чужого профиля запрещено"});
      return;
    }

    const updatedUser = await store.updateProfile(req.auth.user.id, (profile) => ({
      ...profile,
      ...req.body,
    }));

    res.json({
      profile: sanitizeProfile(updatedUser.profile),
      profileStatus: computeProfileStatus(updatedUser.profile),
    });
  });
}

module.exports = {
  registerUserRoutes,
};
