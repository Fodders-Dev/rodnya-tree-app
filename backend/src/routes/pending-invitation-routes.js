function registerPendingInvitationRoutes(
  app,
  {store, requireAuth, requireTreeAccess, mapTree, mapPerson},
) {
  app.post(
    "/v1/trees/:treeId/persons/:personId/claim-token",
    requireAuth,
    async (req, res) => {
      if (typeof requireTreeAccess !== "function") {
        res.status(500).json({message: "Конфигурация доступа не инициализирована"});
        return;
      }
      const tree = await requireTreeAccess(req, res, req.params.treeId, {
        requiredRole: "editor",
      });
      if (!tree) {
        return;
      }
      if (
        req.semyaMembership &&
        req.semyaMembership.role !== "owner" &&
        req.semyaMembership.hasInviteGrant !== true
      ) {
        res.status(403).json({
          message:
            "Только владелец семьи или редактор с правом приглашать может выдать токен привязки",
        });
        return;
      }

      try {
        const issued = await store.issuePersonClaimToken({
          treeId: tree.id,
          personId: req.params.personId,
          actorUserId: req.auth.user.id,
        });
        res.status(201).json(issued);
      } catch (error) {
        const code = error?.message;
        if (code === "NOT_FOUND") {
          res.status(404).json({message: "Профиль или дерево не найдены"});
          return;
        }
        if (code === "ALREADY_CLAIMED") {
          res.status(409).json({
            message: "Этот профиль уже связан с другим пользователем",
          });
          return;
        }
        if (code === "PERSON_DECEASED") {
          res.status(400).json({
            message: "Нельзя привязать аккаунт к карточке ушедшего человека",
          });
          return;
        }
        throw error;
      }
    },
  );

  app.post("/v1/invitations/pending/process", requireAuth, async (req, res) => {
    const treeId = String(req.body?.treeId || "").trim();
    const personId = String(req.body?.personId || "").trim();
    const claimToken = String(req.body?.claimToken || "").trim() || null;
    const requireClaimToken =
      String(process.env.RODNYA_REQUIRE_PERSON_CLAIM_TOKEN || "")
        .trim()
        .toLowerCase() === "true";

    if (!treeId || !personId) {
      res.status(400).json({message: "Нужны treeId и personId"});
      return;
    }

    let linkedPerson;
    try {
      linkedPerson = await store.linkPersonToUser({
        treeId,
        personId,
        userId: req.auth.user.id,
        claimToken,
        requireClaimToken,
      });
    } catch (error) {
      const code = error?.message;
      if (code === "PERSON_DECEASED") {
        res.status(400).json({
          message: "Нельзя привязать аккаунт к карточке ушедшего человека",
        });
        return;
      }
      if (code === "BLOCKED") {
        res.status(403).json({
          message: "Привязка невозможна из-за блокировки между пользователями",
        });
        return;
      }
      if (code === "INVALID_CLAIM_TOKEN") {
        res.status(403).json({
          message: "Недействительный токен привязки профиля",
        });
        return;
      }
      if (code === "CLAIM_TOKEN_EXPIRED") {
        res.status(410).json({
          message: "Срок действия ссылки привязки профиля истёк",
        });
        return;
      }
      if (code === "KICKED_FROM_SEMYA") {
        res.status(403).json({
          message: "Вы были исключены из этой семьи — попросите новое приглашение",
        });
        return;
      }
      if (code === "SEMYA_DELETED") {
        res.status(410).json({message: "Семья удалена"});
        return;
      }
      throw error;
    }

    if (linkedPerson === null) {
      res.status(404).json({message: "Семейное дерево или пользователь не найдены"});
      return;
    }
    if (linkedPerson === undefined) {
      res.status(404).json({message: "Профиль приглашения не найден"});
      return;
    }
    if (linkedPerson === false) {
      res.status(409).json({
        message: "Этот профиль уже связан с другим пользователем",
      });
      return;
    }

    const tree = await store.findTree(treeId);
    res.json({
      ok: true,
      tree: tree ? mapTree(tree) : null,
      person: mapPerson(linkedPerson),
    });
  });
}

module.exports = {
  registerPendingInvitationRoutes,
};
