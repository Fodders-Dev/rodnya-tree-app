function registerProfileRoutes(
  app,
  {
    store,
    requireAuth,
    requireOwnUser,
    sanitizeProfile,
    computeProfileStatus,
    composeDisplayName,
    mapProfileContribution,
    mapProfileNote,
    mapLinkedAuthIdentity,
    buildTrustedChannels,
    resolvePrimaryTrustedChannelProvider,
    buildTrustedChannelSummary,
  },
) {
  app.get("/v1/profile/me/account-linking-status", requireAuth, async (req, res) => {
    const user = await store.findUserById(req.auth.user.id);
    const authIdentities = await store.listUserAuthIdentities(req.auth.user.id);
    const profile = user?.profile || {};
    const linkedProviderIds = user?.providerIds || ["password"];
    const trustedChannels = buildTrustedChannels({
      linkedProviderIds,
      authIdentities,
      profile,
    });
    const primaryTrustedChannelProvider = resolvePrimaryTrustedChannelProvider({
      linkedProviderIds,
      profile,
    });
    const trustedChannelSummary = buildTrustedChannelSummary(trustedChannels);

    res.json({
      linkedProviderIds,
      identities: Array.isArray(authIdentities)
        ? authIdentities.map(mapLinkedAuthIdentity)
        : [],
      trustedChannels,
      primaryTrustedChannel: primaryTrustedChannelProvider
        ? trustedChannels.find(
            (entry) => entry.provider === primaryTrustedChannelProvider,
          ) || null
        : null,
      verificationSummary: trustedChannelSummary,
      legacyPhoneVerification: false,
      mergeStrategy: {
        order: [
          "provider_identity",
          "email",
          "invitation_claim",
          "manual_merge",
        ],
        summary:
          "Сначала ищем точное совпадение identity провайдера, затем совпадение email. Для остального используем приглашения, claim link и ручную привязку.",
      },
      discoveryModes: [
        "username",
        "profile_code",
        "email",
        "invite_link",
        "claim_link",
        "qr",
      ],
    });
  });

  app.get("/v1/profile/me/bootstrap", requireAuth, async (req, res) => {
    res.json({
      profile: sanitizeProfile(req.auth.user.profile),
      profileStatus: computeProfileStatus(req.auth.user.profile),
    });
  });

  app.put("/v1/profile/me/bootstrap", requireAuth, async (req, res) => {
    const updatedUser = await store.updateProfile(req.auth.user.id, (profile) => ({
      ...profile,
      ...req.body,
      displayName: composeDisplayName({
        ...profile,
        ...req.body,
        displayName:
          req.body.displayName !== undefined
            ? req.body.displayName
            : profile.displayName,
      }),
    }));

    res.json({
      profile: sanitizeProfile(updatedUser.profile),
      profileStatus: computeProfileStatus(updatedUser.profile),
    });
  });

  app.patch("/v1/profile/me", requireAuth, async (req, res) => {
    const updatedUser = await store.updateProfile(req.auth.user.id, (profile) => ({
      ...profile,
      ...req.body,
    }));
    const sanitizedProfile = sanitizeProfile(updatedUser.profile);

    const newPhotoUrl = sanitizedProfile.photoUrl;
    if (newPhotoUrl && req.body?.photoUrl) {
      await store.syncUserPhotoToTreePersons(req.auth.user.id, newPhotoUrl).catch(
        (err) => console.warn("[profile] could not sync photo to tree persons:", err),
      );
    }

    res.json({
      user: {
        id: updatedUser.id,
        identityId: updatedUser.identityId || null,
        email: updatedUser.email,
        displayName: sanitizedProfile.displayName,
        photoUrl: sanitizedProfile.photoUrl,
      },
      profileStatus: computeProfileStatus(updatedUser.profile),
    });
  });

  app.get("/v1/profile/me/contributions", requireAuth, async (req, res) => {
    const status = String(req.query.status || "").trim() || null;
    const contributions = await store.listProfileContributions(
      req.auth.user.id,
      {status},
    );
    const authorIds = Array.from(
      new Set(
        contributions
          .map((entry) => String(entry.authorUserId || "").trim())
          .filter(Boolean),
      ),
    );
    const authors = new Map();
    await Promise.all(
      authorIds.map(async (authorId) => {
        const user = await store.findUserById(authorId);
        if (user) {
          authors.set(authorId, user);
        }
      }),
    );

    res.json({
      contributions: contributions.map((entry) => {
        const author = authors.get(entry.authorUserId);
        return mapProfileContribution({
          ...entry,
          authorDisplayName:
            author?.profile?.displayName || author?.email || "Пользователь",
          authorPhotoUrl: author?.profile?.photoUrl || null,
        });
      }),
    });
  });

  app.post(
    "/v1/profile/me/contributions/:contributionId/accept",
    requireAuth,
    async (req, res) => {
      const result = await store.respondToProfileContribution(
        req.auth.user.id,
        req.params.contributionId,
        {accept: true},
      );
      if (!result) {
        res.status(404).json({message: "Предложение не найдено"});
        return;
      }

      res.json({
        contribution: mapProfileContribution(result.contribution),
        profile: sanitizeProfile(result.user?.profile || req.auth.user.profile),
      });
    },
  );

  app.post(
    "/v1/profile/me/contributions/:contributionId/reject",
    requireAuth,
    async (req, res) => {
      const result = await store.respondToProfileContribution(
        req.auth.user.id,
        req.params.contributionId,
        {accept: false},
      );
      if (!result) {
        res.status(404).json({message: "Предложение не найдено"});
        return;
      }

      res.json({
        contribution: mapProfileContribution(result.contribution),
      });
    },
  );

  app.get("/v1/users/:userId/profile-notes", requireAuth, async (req, res) => {
    if (!requireOwnUser(req, res)) {
      return;
    }

    const notes = await store.listProfileNotes(req.params.userId);
    if (notes === null) {
      res.status(404).json({message: "Пользователь не найден"});
      return;
    }

    res.json({
      notes: notes.map(mapProfileNote),
    });
  });

  app.post("/v1/users/:userId/profile-notes", requireAuth, async (req, res) => {
    if (!requireOwnUser(req, res)) {
      return;
    }

    const {title, content} = req.body || {};
    if (!String(title || "").trim() || !String(content || "").trim()) {
      res.status(400).json({message: "Нужны title и content"});
      return;
    }

    const note = await store.addProfileNote(req.params.userId, {
      title,
      content,
    });
    if (note === null) {
      res.status(404).json({message: "Пользователь не найден"});
      return;
    }

    res.status(201).json({note: mapProfileNote(note)});
  });

  app.patch(
    "/v1/users/:userId/profile-notes/:noteId",
    requireAuth,
    async (req, res) => {
      if (!requireOwnUser(req, res)) {
        return;
      }

      const note = await store.updateProfileNote(
        req.params.userId,
        req.params.noteId,
        {
          title: req.body?.title,
          content: req.body?.content,
        },
      );

      if (note === null) {
        res.status(404).json({message: "Пользователь не найден"});
        return;
      }
      if (note === undefined) {
        res.status(404).json({message: "Заметка не найдена"});
        return;
      }

      res.json({note: mapProfileNote(note)});
    },
  );

  app.delete(
    "/v1/users/:userId/profile-notes/:noteId",
    requireAuth,
    async (req, res) => {
      if (!requireOwnUser(req, res)) {
        return;
      }

      const deleted = await store.deleteProfileNote(
        req.params.userId,
        req.params.noteId,
      );
      if (deleted === null) {
        res.status(404).json({message: "Пользователь не найден"});
        return;
      }
      if (deleted === false) {
        res.status(404).json({message: "Заметка не найдена"});
        return;
      }

      res.status(204).send();
    },
  );
}

module.exports = {
  registerProfileRoutes,
};
