// Phase B Week 3 Ship 8: hide-filter endpoints (privacy-critical).
//
// Per ENTITY-DESIGN.md §1.3 + SHARED-TREE-PROPOSAL §3.3.
//
// Endpoints:
//   GET    /v1/me/semya/:id/hide-filter
//          — caller's currently hidden personIds для этой семя
//   PATCH  /v1/me/semya/:id/hide-filter
//          Body: {add?: [personId], remove?: [personId]}
//          — batched add/remove. Idempotent: existing add = no-op,
//          unknown remove = no-op.
//
// Filter integration в tree-routes GET /v1/trees/:treeId/persons
// (separate edit) — после requireTreeAccess passes, route reads
// caller's hide list для tree.semyaId и filters persons array.
// Filter applies whenever caller has hide rows для bound семя,
// regardless of useSemyaModel flag (orphan hides harmless если
// flag OFF — список просто пустой для нон-семя contexts).
//
// Privacy invariants (per SHARED-TREE-PROPOSAL §3.3):
//   * Hide affects ONLY caller's view. Other members see person.
//   * Не mutates canonical tree.
//   * Cross-семя: twin person в другой семе НЕ auto-hidden.
//   * No notification dispatch (silent local action).

function registerSemyaHideFilterRoutes(
  app,
  {store, requireAuth, requireSemyaAccess},
) {
  app.get("/v1/me/semya/:id/hide-filter", requireAuth, async (req, res) => {
    const access = await requireSemyaAccess(req, res, req.params.id, {
      requiredRole: "viewer",
    });
    if (!access) return;
    const hiddenPersonIds = await store.listHiddenPersonIdsForCaller(
      req.params.id,
      req.auth.user.id,
    );
    res.json({
      semyaId: req.params.id,
      userId: req.auth.user.id,
      hiddenPersonIds,
    });
  });

  app.patch(
    "/v1/me/semya/:id/hide-filter",
    requireAuth,
    async (req, res) => {
      const access = await requireSemyaAccess(req, res, req.params.id, {
        requiredRole: "viewer",
      });
      if (!access) return;

      const rawAdd = Array.isArray(req.body?.add) ? req.body.add : [];
      const rawRemove = Array.isArray(req.body?.remove) ? req.body.remove : [];
      const addIds = Array.from(
        new Set(
          rawAdd
            .map((v) => (typeof v === "string" ? v.trim() : ""))
            .filter((v) => v),
        ),
      );
      const removeIds = Array.from(
        new Set(
          rawRemove
            .map((v) => (typeof v === "string" ? v.trim() : ""))
            .filter((v) => v),
        ),
      );

      if (addIds.length === 0 && removeIds.length === 0) {
        res.status(400).json({
          message: "Нужны add либо remove personId-ы",
        });
        return;
      }

      // Apply removes first (idempotent — unknown ids no-op),
      // then adds (idempotent — existing no-op). Both atomic
      // per-personId через store.
      let addedCount = 0;
      let removedCount = 0;
      try {
        for (const personId of removeIds) {
          const outcome = await store.removeHidePerson({
            semyaId: req.params.id,
            userId: req.auth.user.id,
            personId,
          });
          if (outcome.removed) removedCount += 1;
        }
        for (const personId of addIds) {
          const outcome = await store.addHidePerson({
            semyaId: req.params.id,
            userId: req.auth.user.id,
            personId,
          });
          if (outcome.created) addedCount += 1;
        }
      } catch (error) {
        const code = error?.message;
        if (
          code === "INVALID_PERSON_ID" ||
          code === "INVALID_USER_ID" ||
          code === "INVALID_SEMYA_ID"
        ) {
          res.status(400).json({message: "Некорректные параметры"});
          return;
        }
        throw error;
      }

      const hiddenPersonIds = await store.listHiddenPersonIdsForCaller(
        req.params.id,
        req.auth.user.id,
      );
      res.json({
        semyaId: req.params.id,
        userId: req.auth.user.id,
        hiddenPersonIds,
        addedCount,
        removedCount,
      });
    },
  );
}

module.exports = {registerSemyaHideFilterRoutes};
