// Phase 6 chunk 1: kinship-checks (BFS «мы родственники?» bilateral
// consent). DECISIONS.md 2026-05-13 + PHASE-6-PROPOSAL.md §2.5/§2.6.
//
// State machine: pending → accepted | rejected | expired (14d timeout)
// | revoked (Phase 6.5, initiator action).
// On accept — store computes findBloodRelation(maxDepth=4) + stores
// result. Permission gates: initiator (create + list-issued + revoke),
// target (respond + list-received).
//
// Notification types (5):
//   kinship_check_received — target gets on create.
//   kinship_check_confirmed — initiator gets on accept.
//   kinship_check_declined — initiator gets on reject.
//   kinship_check_expired — initiator gets on auto-expire (lazy
//     dispatched at endpoint when sweep triggers).
//   kinship_check_revoked — target gets on initiator revoke (Phase 6.5).

function registerKinshipChecksRoutes(
  app,
  {store, requireAuth, createAndDispatchNotification},
) {
  function mapCheck(check) {
    if (!check) return null;
    return {
      id: check.id,
      initiatorUserId: check.initiatorUserId,
      targetUserId: check.targetUserId,
      status: check.status,
      createdAt: check.createdAt,
      expiresAt: check.expiresAt,
      respondedAt: check.respondedAt,
      // Phase 6.5: initiator revocation timestamp. null до revoke.
      revokedAt: check.revokedAt ?? null,
      result: check.result,
    };
  }

  // POST /v1/kinship-checks — initiator creates pending request.
  app.post("/v1/kinship-checks", requireAuth, async (req, res) => {
    const targetUserId = String(req.body?.targetUserId || "").trim();
    if (!targetUserId) {
      res.status(400).json({message: "Нужен targetUserId"});
      return;
    }

    const outcome = await store.createKinshipCheck({
      initiatorUserId: req.auth.user.id,
      targetUserId,
    });

    if (outcome.error === "INVALID_INPUT") {
      res.status(400).json({message: "Некорректные параметры"});
      return;
    }
    if (outcome.error === "SELF_CHECK_FORBIDDEN") {
      res.status(409).json({
        message: "Нельзя проверить родство с самим собой",
      });
      return;
    }
    if (outcome.error === "TARGET_NOT_FOUND") {
      res.status(404).json({message: "Пользователь не найден"});
      return;
    }
    if (outcome.error === "REJECTION_COOLDOWN") {
      res.status(429).json({
        message:
          "Этот пользователь недавно отклонил ваш запрос. Попробуйте позже.",
        retryAfterMs: outcome.retryAfterMs,
      });
      return;
    }

    // Dispatch notification only on first creation, not idempotent
    // re-call (avoid notification spam).
    if (outcome.created) {
      await createAndDispatchNotification({
        userId: targetUserId,
        type: "kinship_check_received",
        title: "Запрос на подтверждение родственной связи",
        body:
          "Кто-то хочет узнать, родственники ли вы. Подтвердите или " +
          "отклоните запрос.",
        data: {
          kinshipCheckId: outcome.check.id,
          initiatorUserId: req.auth.user.id,
        },
      });
    }

    res
      .status(outcome.created ? 201 : 200)
      .json({check: mapCheck(outcome.check), created: outcome.created});
  });

  // GET /v1/me/kinship-checks/received — pending/accepted/rejected/
  //   expired for target user.
  app.get("/v1/me/kinship-checks/received", requireAuth, async (req, res) => {
    const status = req.query.status ? String(req.query.status) : null;
    const checks = await store.listKinshipChecksForUser({
      userId: req.auth.user.id,
      role: "target",
      status,
    });
    res.json({checks: checks.map(mapCheck)});
  });

  // GET /v1/me/kinship-checks/issued — outgoing (initiator) history.
  app.get("/v1/me/kinship-checks/issued", requireAuth, async (req, res) => {
    const status = req.query.status ? String(req.query.status) : null;
    const checks = await store.listKinshipChecksForUser({
      userId: req.auth.user.id,
      role: "initiator",
      status,
    });
    res.json({checks: checks.map(mapCheck)});
  });

  // POST /v1/kinship-checks/:checkId/respond — target accepts/rejects.
  app.post(
    "/v1/kinship-checks/:checkId/respond",
    requireAuth,
    async (req, res) => {
      const decision = String(req.body?.decision || "").trim();
      if (!["accepted", "rejected"].includes(decision)) {
        res.status(400).json({
          message: "decision должен быть 'accepted' либо 'rejected'",
        });
        return;
      }

      // Find first to verify permission.
      const existing = await store.findKinshipCheck({
        checkId: req.params.checkId,
      });
      if (!existing) {
        res.status(404).json({message: "Запрос не найден"});
        return;
      }
      if (existing.targetUserId !== req.auth.user.id) {
        res.status(403).json({
          message: "Нельзя отвечать на чужой запрос",
        });
        return;
      }
      if (existing.status !== "pending") {
        res.status(409).json({
          message: "Этот запрос уже обработан",
          currentStatus: existing.status,
        });
        return;
      }

      const outcome = await store.respondToKinshipCheck({
        checkId: req.params.checkId,
        decision,
      });
      if (outcome.error === "NOT_FOUND") {
        res.status(404).json({message: "Запрос не найден"});
        return;
      }
      if (outcome.error === "NOT_PENDING") {
        res.status(409).json({
          message: "Этот запрос уже обработан",
          currentStatus: outcome.currentStatus,
        });
        return;
      }
      if (outcome.error) {
        res.status(500).json({message: "Не удалось обработать запрос"});
        return;
      }

      // Notify initiator.
      await createAndDispatchNotification({
        userId: existing.initiatorUserId,
        type:
          decision === "accepted"
            ? "kinship_check_confirmed"
            : "kinship_check_declined",
        title:
          decision === "accepted"
            ? "Связь подтверждена"
            : "Запрос отклонён",
        body:
          decision === "accepted"
            ? "Вам подтвердили запрос. Откройте Родню, чтобы увидеть " +
              "результат проверки."
            : "Получатель отклонил ваш запрос на подтверждение " +
              "родственной связи.",
        data: {
          kinshipCheckId: outcome.check.id,
          targetUserId: existing.targetUserId,
          status: decision,
        },
      });

      res.json({check: mapCheck(outcome.check)});
    },
  );

  // POST /v1/kinship-checks/:checkId/revoke — initiator cancels own
  // pending request. Phase 6.5 PHASE-6-PROPOSAL.md §2.6 + DECISIONS
  // 2026-05-22.
  app.post(
    "/v1/kinship-checks/:checkId/revoke",
    requireAuth,
    async (req, res) => {
      // Pre-validate в routes layer (mirror respond pattern). Store
      // re-validates как defense-in-depth.
      const existing = await store.findKinshipCheck({
        checkId: req.params.checkId,
      });
      if (!existing) {
        res.status(404).json({message: "Запрос не найден"});
        return;
      }
      if (existing.initiatorUserId !== req.auth.user.id) {
        res.status(403).json({
          message: "Нельзя отозвать чужой запрос",
        });
        return;
      }
      if (existing.status !== "pending") {
        res.status(409).json({
          message: "Этот запрос уже обработан либо отозван",
          currentStatus: existing.status,
        });
        return;
      }

      const outcome = await store.revokeKinshipCheck({
        checkId: req.params.checkId,
        initiatorUserId: req.auth.user.id,
      });
      if (outcome.error === "NOT_FOUND") {
        res.status(404).json({message: "Запрос не найден"});
        return;
      }
      if (outcome.error === "NOT_INITIATOR") {
        res.status(403).json({message: "Нельзя отозвать чужой запрос"});
        return;
      }
      if (outcome.error === "NOT_PENDING") {
        res.status(409).json({
          message: "Этот запрос уже обработан либо отозван",
          currentStatus: outcome.currentStatus,
        });
        return;
      }
      if (outcome.error) {
        res.status(500).json({message: "Не удалось отозвать запрос"});
        return;
      }

      // Notify target: «Запрос отозван». Mirror respond dispatch
      // shape для consistency с других kinship_check_* types.
      await createAndDispatchNotification({
        userId: existing.targetUserId,
        type: "kinship_check_revoked",
        title: "Запрос отозван",
        body:
          "Отправитель отозвал запрос на подтверждение родственной " +
          "связи.",
        data: {
          kinshipCheckId: outcome.check.id,
          initiatorUserId: existing.initiatorUserId,
          status: "revoked",
        },
      });

      res.json({check: mapCheck(outcome.check)});
    },
  );
}

module.exports = {registerKinshipChecksRoutes};
