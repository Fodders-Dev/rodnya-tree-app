// Phase 3.2 (DECISIONS.md 2026-05-10 ответ C + Q1/Q3):
// graph-person-level routes — edit grants CRUD, visibility update,
// и grantee-side grant listing.
//
// Все mutate-routes здесь — owner-only (никаких grants даже на
// visibility toggle), чтобы privacy-handle оставался под контролем
// настоящего человека, а не делегированного редактора. Граничный
// случай «owner удалил аккаунт → права переходят к ближайшему
// кровному родственнику» — out of scope, deferred к Phase 3.6.

function registerGraphPersonRoutes(app, {store, requireAuth}) {
  // ── Grants CRUD ────────────────────────────────────────────────

  app.post(
    "/v1/graph-persons/:graphPersonId/grants",
    requireAuth,
    async (req, res) => {
      const granteeUserId = String(req.body?.granteeUserId || "").trim();
      const scope = String(req.body?.scope || "").trim();
      if (!granteeUserId || !scope) {
        res.status(400).json({
          message: "Нужны granteeUserId и scope",
        });
        return;
      }

      try {
        const result = await store.addGraphPersonGrant({
          graphPersonId: req.params.graphPersonId,
          grantorUserId: req.auth.user.id,
          granteeUserId,
          scope,
        });
        if (!result) {
          res.status(404).json({message: "Карточка не найдена"});
          return;
        }
        const grantee = await store.findUserById(granteeUserId);
        res.status(result.created ? 201 : 200).json({
          grant: result.grant,
          grantee: grantee
            ? {
                id: grantee.id,
                displayName:
                  grantee.profile?.displayName || grantee.email || "",
                photoUrl: grantee.profile?.photoUrl || null,
              }
            : null,
        });
      } catch (error) {
        if (error?.message === "INVALID_SCOPE") {
          res.status(400).json({
            message:
              "scope должен быть 'edit', 'merge-consent' или 'soft-delete'",
          });
          return;
        }
        if (error?.message === "INVALID_INPUT") {
          res.status(400).json({message: "Некорректные параметры запроса"});
          return;
        }
        if (error?.message === "SELF_GRANT") {
          res.status(409).json({
            message: "Нельзя выписать право самому себе",
          });
          return;
        }
        if (error?.message === "NOT_OWNER") {
          res.status(403).json({
            message: "Только владелец карточки может выписывать права",
          });
          return;
        }
        throw error;
      }
    },
  );

  app.delete(
    "/v1/graph-persons/:graphPersonId/grants/:grantId",
    requireAuth,
    async (req, res) => {
      try {
        const grant = await store.revokeGraphPersonGrant({
          graphPersonId: req.params.graphPersonId,
          grantId: req.params.grantId,
          actorUserId: req.auth.user.id,
        });
        if (!grant) {
          res.status(404).json({message: "Право не найдено"});
          return;
        }
        res.json({grant});
      } catch (error) {
        if (error?.message === "NOT_OWNER") {
          res.status(403).json({
            message:
              "Только владелец карточки может отзывать выданные права",
          });
          return;
        }
        throw error;
      }
    },
  );

  app.get(
    "/v1/graph-persons/:graphPersonId/grants",
    requireAuth,
    async (req, res) => {
      try {
        const grants = await store.listGraphPersonGrants({
          graphPersonId: req.params.graphPersonId,
          viewerUserId: req.auth.user.id,
        });
        if (grants === null) {
          res.status(404).json({message: "Карточка не найдена"});
          return;
        }
        res.json({grants});
      } catch (error) {
        if (error?.message === "NOT_OWNER") {
          res.status(403).json({
            message:
              "Только владелец карточки может смотреть список выданных прав",
          });
          return;
        }
        throw error;
      }
    },
  );

  // ── Grantee-side: список собственных прав ─────────────────────

  // Phase 3.4-prep (DECISIONS.md 2026-05-10 Q3): grantor-side
  // список grants выписанных текущим viewer'ом. Симметричен
  // /v1/me/edit-grants. Без него Phase 3.4 outgoing-таб делал бы
  // N+1 round-trip per graphPerson; этот endpoint даёт flat list
  // в одном запросе. Включаем revoked-since-30d для audit transparency.
  app.get("/v1/me/issued-grants", requireAuth, async (req, res) => {
    const sinceDaysRaw = Number(req.query.includeRevokedSinceDays || 30);
    const sinceDays =
      Number.isFinite(sinceDaysRaw) && sinceDaysRaw > 0
        ? Math.min(Math.floor(sinceDaysRaw), 365)
        : 30;
    const grants = await store.listMyIssuedGrants({
      userId: req.auth.user.id,
      includeRevokedSinceDays: sinceDays,
    });

    const previewIds = Array.from(
      new Set(grants.map((entry) => entry.graphPersonId).filter(Boolean)),
    );
    const previews = await store.previewGraphPersonsByIds(previewIds, {
      viewerUserId: req.auth.user.id,
    });
    const previewById = new Map(previews.map((entry) => [entry.id, entry]));

    // Hydrate grantee profile previews для каждого grant'а.
    const granteeIds = Array.from(
      new Set(grants.map((entry) => entry.granteeUserId).filter(Boolean)),
    );
    const granteeById = new Map();
    for (const granteeId of granteeIds) {
      const user = await store.findUserById(granteeId);
      if (user) {
        granteeById.set(granteeId, {
          id: user.id,
          displayName: user.profile?.displayName || user.email || "",
          photoUrl: user.profile?.photoUrl || null,
        });
      }
    }

    res.json({
      grants: grants.map((grant) => ({
        ...grant,
        graphPerson: previewById.get(grant.graphPersonId) || null,
        grantee: granteeById.get(grant.granteeUserId) || null,
      })),
    });
  });

  app.get("/v1/me/edit-grants", requireAuth, async (req, res) => {
    const sinceDaysRaw = Number(req.query.includeRevokedSinceDays || 30);
    const sinceDays =
      Number.isFinite(sinceDaysRaw) && sinceDaysRaw > 0
        ? Math.min(Math.floor(sinceDaysRaw), 365)
        : 30;
    const grants = await store.listMyGrantsForUser({
      userId: req.auth.user.id,
      includeRevokedSinceDays: sinceDays,
    });

    const previewIds = Array.from(
      new Set(grants.map((entry) => entry.graphPersonId).filter(Boolean)),
    );
    const previews = await store.previewGraphPersonsByIds(previewIds);
    const previewById = new Map(previews.map((entry) => [entry.id, entry]));

    res.json({
      grants: grants.map((grant) => ({
        ...grant,
        graphPerson: previewById.get(grant.graphPersonId) || null,
      })),
    });
  });

  // ── Visibility (owner-only-всегда, никаких grants) ────────────

  app.patch(
    "/v1/graph-persons/:graphPersonId/visibility",
    requireAuth,
    async (req, res) => {
      const visibility = String(req.body?.visibility || "").trim();
      try {
        const updated = await store.setGraphPersonVisibility({
          graphPersonId: req.params.graphPersonId,
          visibility,
          actorUserId: req.auth.user.id,
        });
        if (!updated) {
          res.status(404).json({message: "Карточка не найдена"});
          return;
        }
        res.json({
          graphPerson: {
            id: updated.id,
            visibility: updated.visibility,
            visibilityOverride: updated.visibilityOverride,
            updatedAt: updated.updatedAt,
          },
        });
      } catch (error) {
        if (error?.message === "INVALID_VISIBILITY") {
          res.status(400).json({
            message:
              "visibility должен быть 'owner-only', 'connected-via-blood-graph' или 'public'",
          });
          return;
        }
        if (error?.message === "NOT_OWNER") {
          res.status(403).json({
            message: "Только владелец карточки может менять её приватность",
          });
          return;
        }
        throw error;
      }
    },
  );

  app.delete(
    "/v1/graph-persons/:graphPersonId/visibility-override",
    requireAuth,
    async (req, res) => {
      try {
        const updated = await store.clearGraphPersonVisibilityOverride({
          graphPersonId: req.params.graphPersonId,
          actorUserId: req.auth.user.id,
        });
        if (!updated) {
          res.status(404).json({message: "Карточка не найдена"});
          return;
        }
        res.json({
          graphPerson: {
            id: updated.id,
            visibility: updated.visibility,
            visibilityOverride: updated.visibilityOverride,
            updatedAt: updated.updatedAt,
          },
        });
      } catch (error) {
        if (error?.message === "NOT_OWNER") {
          res.status(403).json({
            message:
              "Только владелец карточки может сбрасывать override приватности",
          });
          return;
        }
        throw error;
      }
    },
  );
}

module.exports = {registerGraphPersonRoutes};
