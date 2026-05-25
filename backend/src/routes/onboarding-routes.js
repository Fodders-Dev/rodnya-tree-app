// Phase 6 chunk 1: onboarding routes (PHASE-6-PROPOSAL.md §3.2 +
// DECISIONS.md 2026-05-13 state-based idempotency).
//
// POST /v1/onboarding/seed — bulk create profile + first relatives.
//   State-based idempotency: completed → return existing tree;
//   incomplete previous attempt → replace; absent → fresh seed.
//
// GET /v1/me/onboarding-state — current wizard progress.
// PATCH /v1/me/onboarding-state — update step (welcome/profile/
//   relatives/finish/done).

function registerOnboardingRoutes(app, {store, requireAuth}) {
  app.post("/v1/onboarding/seed", requireAuth, async (req, res) => {
    const profile = req.body?.profile;
    const relatives = Array.isArray(req.body?.relatives)
      ? req.body.relatives
      : [];

    if (!profile || typeof profile !== "object") {
      res.status(400).json({message: "Нужен profile"});
      return;
    }
    if (!profile.name || String(profile.name).trim().length === 0) {
      res.status(400).json({message: "Имя обязательно"});
      return;
    }

    const result = await store.seedOnboarding({
      userId: req.auth.user.id,
      payload: {profile, relatives},
    });

    if (result.error === "NO_USER" || result.error === "USER_NOT_FOUND") {
      res.status(404).json({message: "Пользователь не найден"});
      return;
    }
    if (result.error) {
      res.status(500).json({message: "Не удалось создать дерево"});
      return;
    }
    res.status(result.idempotent ? 200 : 201).json({
      treeId: result.treeId,
      personIds: result.personIds,
      idempotent: result.idempotent === true,
    });
  });

  app.get("/v1/me/onboarding-state", requireAuth, async (req, res) => {
    const state = await store.getOnboardingState({userId: req.auth.user.id});
    res.json({state});
  });

  app.patch("/v1/me/onboarding-state", requireAuth, async (req, res) => {
    const step = String(req.body?.currentStep || "").trim();
    if (!step) {
      res.status(400).json({message: "Нужен currentStep"});
      return;
    }
    const updated = await store.updateOnboardingState({
      userId: req.auth.user.id,
      currentStep: step,
    });
    if (!updated) {
      res.status(400).json({message: "Недопустимый step"});
      return;
    }
    res.json({state: updated});
  });

  // Ship Q1 (2026-05-25): explicit skip endpoint. User wants main
  // app access без завершения wizard'а. Backend sets skipped=true →
  // hasIncompleteOnboarding returns false → session
  // .requiresOnboarding=false → router guards не redirect к /setup.
  //
  // Wizard remains resumable via direct nav (home banner CTA).
  // Идempotent — re-call returns existing state без re-mutation.
  app.post(
    "/v1/me/onboarding-state/skip",
    requireAuth,
    async (req, res) => {
      const state = await store.skipOnboardingState({
        userId: req.auth.user.id,
      });
      if (!state) {
        res.status(400).json({message: "Не удалось обработать запрос"});
        return;
      }
      res.json({state});
    },
  );
}

module.exports = {registerOnboardingRoutes};
