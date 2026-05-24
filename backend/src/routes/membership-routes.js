// Phase B Week 2 Ship 3: семья membership HTTP endpoints (4 routes).
//
// Per Phase B SHARED-TREE-PROPOSAL.md + ENTITY-DESIGN.md §2 + §3.
//
// Endpoints:
//   POST   /v1/semya/:id/membership              — add existing user
//   GET    /v1/semya/:id/memberships             — list members
//   PATCH  /v1/semya/:id/membership/:userId      — role либо grant change
//   DELETE /v1/semya/:id/membership/:userId      — kick либо self-leave
//
// Permission gates via `requireSemyaAccess`:
//   POST   — owner либо editor с hasInviteGrant
//   GET    — viewer+ (any member)
//   PATCH  — owner only (role/grant changes требуют owner)
//   DELETE — owner если kick others; self-leave permitted всеми
//
// Ship 3 не включает:
//   * invitation flow для new users (phone/email) — Ship 4
//   * tree binding compat shim — Week 3
//   * notification dispatch — Week 3

function registerMembershipRoutes(
  app,
  {store, requireAuth, requireSemyaAccess},
) {
  function mapMembership(membership) {
    if (!membership) return null;
    return {
      id: membership.id,
      semyaId: membership.semyaId,
      userId: membership.userId,
      role: membership.role,
      joinedAt: membership.joinedAt,
      invitedByUserId: membership.invitedByUserId ?? null,
      hasInviteGrant: membership.hasInviteGrant === true,
    };
  }

  // POST /v1/semya/:id/membership — add existing user as editor/viewer.
  // Idempotent (existing membership returns 200 with current row).
  app.post("/v1/semya/:id/membership", requireAuth, async (req, res) => {
    // Two valid actor roles: owner либо editor c hasInviteGrant=true.
    // First require viewer+ access, then verify invite power inline
    // (нет cleaner spot для compound check в existing middleware).
    const access = await requireSemyaAccess(req, res, req.params.id, {
      requiredRole: "viewer",
    });
    if (!access) return;
    const canInvite =
      access.membership.role === "owner" ||
      (access.membership.role === "editor" &&
        access.membership.hasInviteGrant === true);
    if (!canInvite) {
      res.status(403).json({
        message: "Только владелец либо редактор с правом приглашать",
      });
      return;
    }

    const userId = String(req.body?.userId || "").trim();
    const role = String(req.body?.role || "").trim();
    const hasInviteGrant = req.body?.hasInviteGrant === true;
    if (!userId) {
      res.status(400).json({message: "Нужен userId"});
      return;
    }
    if (role !== "editor" && role !== "viewer") {
      res.status(400).json({
        message: "role должен быть 'editor' либо 'viewer'",
      });
      return;
    }

    try {
      const outcome = await store.addMembership({
        semyaId: req.params.id,
        userId,
        role,
        invitedByUserId: req.auth.user.id,
        hasInviteGrant,
      });
      res
        .status(outcome.created ? 201 : 200)
        .json({membership: mapMembership(outcome.membership), created: outcome.created});
    } catch (error) {
      const code = error?.message;
      if (code === "USER_NOT_FOUND") {
        res.status(404).json({message: "Пользователь не найден"});
        return;
      }
      if (code === "SEMYA_NOT_FOUND") {
        res.status(404).json({message: "Семья не найдена"});
        return;
      }
      if (
        code === "INVALID_ROLE" ||
        code === "INVALID_USER_ID" ||
        code === "INVALID_SEMYA_ID"
      ) {
        res.status(400).json({message: "Некорректные параметры"});
        return;
      }
      throw error;
    }
  });

  // GET /v1/semya/:id/memberships — list members.
  app.get("/v1/semya/:id/memberships", requireAuth, async (req, res) => {
    const access = await requireSemyaAccess(req, res, req.params.id, {
      requiredRole: "viewer",
    });
    if (!access) return;
    const rows = await store.listMembershipsForSemya(req.params.id);
    res.json({memberships: rows.map(mapMembership)});
  });

  // PATCH /v1/semya/:id/membership/:userId — role либо invite-grant.
  // Owner-only mutation.
  app.patch(
    "/v1/semya/:id/membership/:userId",
    requireAuth,
    async (req, res) => {
      const access = await requireSemyaAccess(req, res, req.params.id, {
        requiredRole: "owner",
      });
      if (!access) return;

      const updates = {
        semyaId: req.params.id,
        targetUserId: req.params.userId,
        actorUserId: req.auth.user.id,
      };
      if (req.body?.role !== undefined) {
        updates.role = String(req.body.role).trim();
      }
      if (req.body?.hasInviteGrant !== undefined) {
        updates.hasInviteGrant = req.body.hasInviteGrant === true;
      }
      if (updates.role === undefined && updates.hasInviteGrant === undefined) {
        res.status(400).json({message: "Нечего обновлять"});
        return;
      }

      try {
        const updated = await store.updateMembership(updates);
        res.json({membership: mapMembership(updated)});
      } catch (error) {
        const code = error?.message;
        if (code === "MEMBERSHIP_NOT_FOUND") {
          res.status(404).json({message: "Участник семьи не найден"});
          return;
        }
        if (code === "SEMYA_NOT_FOUND") {
          res.status(404).json({message: "Семья не найдена"});
          return;
        }
        if (code === "NOT_OWNER") {
          res.status(403).json({
            message: "Изменение прав доступно только владельцу",
          });
          return;
        }
        if (code === "SELF_ROLE_CHANGE_FORBIDDEN") {
          res.status(409).json({
            message:
              "Свою роль изменить нельзя — попросите другого владельца",
          });
          return;
        }
        if (code === "LAST_OWNER_DEMOTE_FORBIDDEN") {
          res.status(409).json({
            message:
              "Нельзя понизить последнего владельца — повысьте другого участника сначала",
          });
          return;
        }
        if (code === "INVITE_GRANT_ONLY_EDITOR") {
          res.status(409).json({
            message:
              "Право приглашать настраивается только для редакторов",
          });
          return;
        }
        if (
          code === "INVALID_ROLE" ||
          code === "NO_CHANGES" ||
          code === "INVALID_USER_ID"
        ) {
          res.status(400).json({message: "Некорректные параметры"});
          return;
        }
        throw error;
      }
    },
  );

  // DELETE /v1/semya/:id/membership/:userId — kick либо self-leave.
  // Self-leave: any role can do it (если не последний owner).
  // Kick others: owner only.
  app.delete(
    "/v1/semya/:id/membership/:userId",
    requireAuth,
    async (req, res) => {
      // Для self-leave достаточно viewer+ access — store layer проверит
      // что target membership exists. Для kick — owner gate enforced в
      // store layer (NOT_OWNER error если actor not owner).
      const access = await requireSemyaAccess(req, res, req.params.id, {
        requiredRole: "viewer",
      });
      if (!access) return;

      try {
        const outcome = await store.removeMembership({
          semyaId: req.params.id,
          targetUserId: req.params.userId,
          actorUserId: req.auth.user.id,
        });
        res.json({
          membership: mapMembership(outcome.membership),
          wasSelfLeave: outcome.wasSelfLeave,
        });
      } catch (error) {
        const code = error?.message;
        if (code === "MEMBERSHIP_NOT_FOUND") {
          res.status(404).json({message: "Участник семьи не найден"});
          return;
        }
        if (code === "SEMYA_NOT_FOUND") {
          res.status(404).json({message: "Семья не найдена"});
          return;
        }
        if (code === "NOT_OWNER") {
          res.status(403).json({
            message: "Удалять других участников может только владелец",
          });
          return;
        }
        if (code === "LAST_OWNER_REMOVE_FORBIDDEN") {
          res.status(409).json({
            message:
              "Нельзя удалить последнего владельца — назначьте другого первым",
          });
          return;
        }
        if (code === "INVALID_USER_ID" || code === "INVALID_SEMYA_ID") {
          res.status(400).json({message: "Некорректные параметры"});
          return;
        }
        throw error;
      }
    },
  );
}

module.exports = {registerMembershipRoutes};
