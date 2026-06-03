// Phase B Week 2 Ship 4: семья invitation HTTP endpoints (3 routes).
//
// Per ENTITY-DESIGN.md §1.4 + SHARED-TREE-PROPOSAL.md §3.2 (invitations).
//
// Endpoints:
//   POST   /v1/semya/:id/invitation                — create pending (owner либо editor с grant)
//   POST   /v1/invitation/:token/accept            — recipient accepts → membership atomic
//   DELETE /v1/semya/:id/invitation/:invitationId  — revoke (inviter либо owner)
//
// State machine: pending → accepted | revoked | expired.
// Expiry: lazy on read (mirror Phase 6.5 kinship-checks).
//
// Notification dispatch:
//   * On create — recipient notified когда recipientUserId matches
//     registered user (push device available). Email-addressed
//     invitations теперь auto-send тёплое accept-link письмо через
//     emailSender (FE7 2026-06-03 — раньше «Phase B+1 wires email
//     backend», теперь wired). Best-effort: сбой почты не ломает
//     создание приглашения.
//   * On accept — inviter notified.
//
// Ship 4 не включал (статус на 2026-06-03):
//   * Email auto-dispatch — DONE (FE7, см. POST create ниже).
//   * SMS auto-dispatch — всё ещё нужен SMS-провайдер.
//   * Invitation expiry background sweep (lazy на read covers Day 1).
//   * GET /list invitations endpoint — DONE (FE3).

const {composeDisplayNameFromProfile} = require("../store");

function registerSemyaInvitationRoutes(
  app,
  {
    store,
    config,
    requireAuth,
    requireSemyaAccess,
    createAndDispatchNotification,
    emailSender,
  },
) {
  function mapInvitation(invitation) {
    if (!invitation) return null;
    const base = {
      id: invitation.id,
      token: invitation.token,
      semyaId: invitation.semyaId,
      inviterUserId: invitation.inviterUserId,
      recipientUserId: invitation.recipientUserId ?? null,
      recipientEmail: invitation.recipientEmail ?? null,
      recipientPhone: invitation.recipientPhone ?? null,
      role: invitation.role,
      status: invitation.status,
      createdAt: invitation.createdAt,
      expiresAt: invitation.expiresAt,
      acceptedAt: invitation.acceptedAt ?? null,
      revokedAt: invitation.revokedAt ?? null,
      revokedByUserId: invitation.revokedByUserId ?? null,
      expiredAt: invitation.expiredAt ?? null,
    };
    // Ship FE9 (2026-05-27): listPendingInvitationsForUser enriches
    // с semyaName (denormalized для frontend wizard CTA copy «семья
    // {name}» — saves extra GET /v1/semya/:id round-trip).
    if (invitation.semyaName !== undefined) {
      base.semyaName = invitation.semyaName;
    }
    return base;
  }

  // FE3 (2026-05-26): list-endpoint addition. Originally Ship 4
  // deferred это к Phase B+1 — но frontend FE3 invitation-list
  // screen needs cross-device sync (locally-persisted списки уязвимы
  // к device wipe / re-install). Backend store.listInvitationsForSemya
  // уже существовал; здесь только thin route wrapper.
  //
  // Permission: viewer+ allowed (matches POST/DELETE access tier для
  // соответствия с requireSemyaAccess) — outsider не может probe.
  // Список возвращает ВСЕ статусы (pending/accepted/revoked/expired)
  // — UI фильтрует по необходимости.
  app.get("/v1/semya/:id/invitations", requireAuth, async (req, res) => {
    const access = await requireSemyaAccess(req, res, req.params.id, {
      requiredRole: "viewer",
    });
    if (!access) return;
    const rows = await store.listInvitationsForSemya(req.params.id);
    res.json({invitations: rows.map(mapInvitation)});
  });

  // Ship FE9 (2026-05-27): «my pending семя invitations» endpoint
  // для onboarding wizard. Returns pending invitations addressed
  // explicitly к caller (recipientUserId) либо к caller's email
  // (recipientEmail match для invitations sent before user existed).
  //
  // Auth: requireAuth only — anyone authenticated can ask «what's
  // waiting for me?». Soft-deleted семья invitations filtered out
  // (store layer enforces).
  //
  // Response: {invitations: [{...mapInvitation, semyaName}]}.
  app.get("/v1/me/pending-invitations", requireAuth, async (req, res) => {
    const userId = req.auth.user.id;
    const email = req.auth.user.email || "";
    const rows = await store.listPendingInvitationsForUser({userId, email});
    res.json({invitations: rows.map(mapInvitation)});
  });

  // POST /v1/semya/:id/invitation — owner либо editor c grant
  // creates pending invitation. Idempotent на (semyaId + recipient).
  app.post("/v1/semya/:id/invitation", requireAuth, async (req, res) => {
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

    const recipientUserId = req.body?.recipientUserId
      ? String(req.body.recipientUserId).trim()
      : null;
    const recipientEmail = req.body?.recipientEmail
      ? String(req.body.recipientEmail).trim()
      : null;
    const recipientPhone = req.body?.recipientPhone
      ? String(req.body.recipientPhone).trim()
      : null;
    const role = String(req.body?.role || "").trim();
    const expiresInDays =
      typeof req.body?.expiresInDays === "number"
        ? Math.max(1, Math.min(90, Math.floor(req.body.expiresInDays)))
        : 30;

    if (role !== "editor" && role !== "viewer") {
      res.status(400).json({
        message: "role должен быть 'editor' либо 'viewer'",
      });
      return;
    }
    if (!recipientUserId && !recipientEmail && !recipientPhone) {
      res.status(400).json({
        message:
          "Нужен recipientUserId, recipientEmail либо recipientPhone",
      });
      return;
    }

    try {
      const outcome = await store.createInvitation({
        semyaId: req.params.id,
        inviterUserId: req.auth.user.id,
        recipientUserId,
        recipientEmail,
        recipientPhone,
        role,
        expiresInDays,
      });

      // Dispatch только на первое создание, не idempotent re-call.
      if (outcome.created && recipientUserId) {
        await createAndDispatchNotification({
          userId: recipientUserId,
          type: "semya_invitation_received",
          title: "Приглашение в семью",
          body: "Вас пригласили в семью на Rodnya — откройте, чтобы принять.",
          data: {
            invitationId: outcome.invitation.id,
            semyaId: req.params.id,
            inviterUserId: req.auth.user.id,
            role,
          },
        });
      }

      // FE7 (2026-06-03): email-addressed приглашение → тёплое письмо
      // со ссылкой-принять. Только на первое создание (не idempotent
      // re-POST) и только когда есть recipientEmail. Best-effort,
      // fire-and-forget — email-фейл НЕ должен 500-ить создание
      // приглашения (mirror password-reset).
      if (
        outcome.created &&
        recipientEmail &&
        emailSender &&
        typeof emailSender.sendSemyaInvitationEmail === "function"
      ) {
        try {
          const baseAppUrl = String(
            config?.publicAppUrl || "https://rodnya-tree.ru",
          )
            .trim()
            .replace(/\/+$/u, "");
          const acceptUrl = `${baseAppUrl}/invite/${encodeURIComponent(
            outcome.invitation.token,
          )}`;

          // Роут сам семью не грузит — резолвим имя по semyaId.
          let semyaName = "";
          try {
            const semya = await store.findSemyaById(req.params.id);
            semyaName = semya?.name || "";
          } catch (_) {
            semyaName = "";
          }

          // inviterName — displayName (как /v1/auth/session), с
          // composed-fallback (firstName+lastName) если displayName пуст.
          let inviterName = "";
          try {
            const inviter = await store.findUserById(req.auth.user.id);
            inviterName =
              inviter?.profile?.displayName ||
              composeDisplayNameFromProfile(inviter?.profile) ||
              "";
          } catch (_) {
            inviterName = "";
          }

          await emailSender.sendSemyaInvitationEmail({
            to: recipientEmail,
            acceptUrl,
            semyaName,
            inviterName,
            role,
          });
        } catch (emailErr) {
          // Best-effort — приглашение уже создано; не бабблим.
          // eslint-disable-next-line no-console
          console.error(
            "[semya] invitation email dispatch failed",
            emailErr,
          );
        }
      }

      res
        .status(outcome.created ? 201 : 200)
        .json({invitation: mapInvitation(outcome.invitation), created: outcome.created});
    } catch (error) {
      const code = error?.message;
      if (code === "ALREADY_MEMBER") {
        res.status(409).json({
          message: "Пользователь уже состоит в этой семье",
        });
        return;
      }
      if (code === "RECIPIENT_NOT_FOUND") {
        res.status(404).json({message: "Получатель не найден"});
        return;
      }
      if (code === "SEMYA_NOT_FOUND") {
        res.status(404).json({message: "Семья не найдена"});
        return;
      }
      if (
        code === "INVALID_ROLE" ||
        code === "MISSING_RECIPIENT" ||
        code === "INVALID_SEMYA_ID" ||
        code === "INVALID_INVITER"
      ) {
        res.status(400).json({message: "Некорректные параметры"});
        return;
      }
      throw error;
    }
  });

  // POST /v1/invitation/:token/accept — recipient accepts.
  // Atomic accept + membership create. Token = capability, любой
  // authenticated user с valid token may accept (if no
  // recipientUserId set либо matching userId).
  app.post("/v1/invitation/:token/accept", requireAuth, async (req, res) => {
    try {
      const outcome = await store.acceptInvitation({
        token: req.params.token,
        acceptingUserId: req.auth.user.id,
      });

      // Notify inviter inviting accepted.
      try {
        await createAndDispatchNotification({
          userId: outcome.invitation.inviterUserId,
          type: "semya_invitation_accepted",
          title: "Приглашение принято",
          body: "Ваш приглашённый принял приглашение в семью.",
          data: {
            invitationId: outcome.invitation.id,
            semyaId: outcome.invitation.semyaId,
            acceptedByUserId: req.auth.user.id,
          },
        });
      } catch (notifyErr) {
        // Best-effort — accept succeeded, notification failure не
        // ломает response.
        // eslint-disable-next-line no-console
        console.error("[semya] invitation accept notify failed", notifyErr);
      }

      res.json({
        invitation: mapInvitation(outcome.invitation),
        membership: {
          id: outcome.membership.id,
          semyaId: outcome.membership.semyaId,
          userId: outcome.membership.userId,
          role: outcome.membership.role,
          joinedAt: outcome.membership.joinedAt,
        },
      });
    } catch (error) {
      const code = error?.message;
      if (code === "INVITATION_NOT_FOUND") {
        res.status(404).json({message: "Приглашение не найдено"});
        return;
      }
      if (code === "INVITATION_NOT_PENDING") {
        res.status(409).json({
          message: "Это приглашение уже не действует",
        });
        return;
      }
      if (code === "WRONG_RECIPIENT") {
        res.status(403).json({
          message: "Это приглашение адресовано другому пользователю",
        });
        return;
      }
      if (code === "SEMYA_NOT_FOUND") {
        res.status(404).json({message: "Семья не найдена"});
        return;
      }
      if (code === "INVALID_TOKEN") {
        res.status(400).json({message: "Некорректный токен"});
        return;
      }
      throw error;
    }
  });

  // DELETE /v1/semya/:id/invitation/:invitationId — revoke pending.
  // Inviter либо semya owner only.
  app.delete(
    "/v1/semya/:id/invitation/:invitationId",
    requireAuth,
    async (req, res) => {
      // Permission gate в store layer (NOT_INVITER_OR_OWNER) — мы
      // здесь требуем только viewer+ к семья (защита от outsider
      // probing invitation IDs).
      const access = await requireSemyaAccess(req, res, req.params.id, {
        requiredRole: "viewer",
      });
      if (!access) return;

      try {
        const invitation = await store.revokeInvitation({
          invitationId: req.params.invitationId,
          actingUserId: req.auth.user.id,
        });
        res.json({invitation: mapInvitation(invitation)});
      } catch (error) {
        const code = error?.message;
        if (code === "INVITATION_NOT_FOUND") {
          res.status(404).json({message: "Приглашение не найдено"});
          return;
        }
        if (code === "NOT_INVITER_OR_OWNER") {
          res.status(403).json({
            message: "Отозвать можно только своё приглашение либо приглашения вашей семьи",
          });
          return;
        }
        if (code === "INVITATION_NOT_PENDING") {
          res.status(409).json({
            message: "Это приглашение уже не действует",
          });
          return;
        }
        if (code === "INVALID_INVITATION_ID") {
          res.status(400).json({message: "Некорректные параметры"});
          return;
        }
        throw error;
      }
    },
  );
}

module.exports = {registerSemyaInvitationRoutes};
