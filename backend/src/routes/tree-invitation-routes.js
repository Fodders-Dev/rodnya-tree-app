function registerTreeInvitationRoutes(
  app,
  {
    store,
    requireAuth,
    requireTreeAccess,
    createAndDispatchNotification,
    mapTree,
    mapTreeInvitation,
  },
) {
  app.get("/v1/tree-invitations/pending", requireAuth, async (req, res) => {
    const invitations = await store.listPendingTreeInvitations(req.auth.user.id);
    const treeCache = new Map();
    await Promise.all(
      Array.from(
        new Set(
          invitations
            .map((invitation) => String(invitation?.treeId || "").trim())
            .filter(Boolean),
        ),
      ).map(async (treeId) => {
        treeCache.set(treeId, await store.findTree(treeId));
      }),
    );

    res.json({
      invitations: invitations.map((invitation) =>
        mapTreeInvitation(invitation, treeCache.get(invitation.treeId) || null),
      ),
    });
  });

  app.post(
    "/v1/trees/:treeId/invitations",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) {
        return;
      }

      const recipientUserId = String(req.body?.recipientUserId || "").trim();
      const recipientEmail = String(req.body?.recipientEmail || "")
        .trim()
        .toLowerCase();
      const relationToTree = req.body?.relationToTree;

      if (!recipientUserId && !recipientEmail) {
        res.status(400).json({message: "Нужен recipientUserId или recipientEmail"});
        return;
      }

      let targetUserId = recipientUserId;
      if (!targetUserId && recipientEmail) {
        const users = await store.searchUsersByField({
          field: "email",
          value: recipientEmail,
          limit: 1,
        });
        if (!users.length) {
          res.status(404).json({message: "Пользователь с таким email не найден"});
          return;
        }
        targetUserId = users[0].id;
      }

      const invitation = await store.createTreeInvitation({
        treeId: tree.id,
        userId: targetUserId,
        addedBy: req.auth.user.id,
        relationToTree,
      });

      if (invitation === null) {
        res.status(404).json({message: "Семейное дерево не найдено"});
        return;
      }
      if (invitation === undefined) {
        res.status(404).json({message: "Приглашаемый пользователь не найден"});
        return;
      }
      if (invitation === false) {
        res.status(409).json({
          message: "Этот пользователь уже состоит в семейном дереве",
        });
        return;
      }
      if (invitation === "DUPLICATE") {
        res.status(409).json({
          message: "Для этого пользователя уже есть активное приглашение",
        });
        return;
      }

      // Друзья-полиш FR1: копия пуша зависит от вида дерева. tree.kind
      // приходит из store.findTree (raw record) — "friends" для круга.
      const isFriendsTree = tree.kind === "friends";
      await createAndDispatchNotification({
        userId: targetUserId,
        type: "tree_invitation",
        title: isFriendsTree
          ? "Приглашение в круг друзей"
          : "Приглашение в семейное дерево",
        body: isFriendsTree
          ? `Вас пригласили в круг «${tree.name}»`
          : `Вас пригласили в дерево «${tree.name}»`,
        data: {
          invitationId: invitation.id,
          treeId: tree.id,
          treeName: tree.name,
          invitedBy: req.auth.user.id,
        },
      });

      res.status(201).json({
        invitation: mapTreeInvitation(invitation, tree),
      });
    },
  );

  app.post(
    "/v1/tree-invitations/:invitationId/respond",
    requireAuth,
    async (req, res) => {
      const accept = req.body?.accept == true;
      const invitation = await store.findTreeInvitation(req.params.invitationId);
      if (!invitation) {
        res.status(404).json({message: "Приглашение не найдено"});
        return;
      }

      if (invitation.userId !== req.auth.user.id) {
        res.status(403).json({message: "Нельзя отвечать на чужое приглашение"});
        return;
      }

      const result = await store.respondToTreeInvitation(
        req.params.invitationId,
        accept,
      );
      if (result === null) {
        res.status(404).json({message: "Приглашение не найдено"});
        return;
      }
      if (result === undefined) {
        res.status(404).json({message: "Семейное дерево не найдено"});
        return;
      }

      if (result.accepted && result.invitation.addedBy) {
        const acceptedFriendsTree = result.tree.kind === "friends";
        await createAndDispatchNotification({
          userId: result.invitation.addedBy,
          type: "tree_invitation_accepted",
          title: "Приглашение принято",
          body: acceptedFriendsTree
            ? `Пользователь принял приглашение в круг «${result.tree.name}»`
            : `Пользователь принял приглашение в дерево «${result.tree.name}»`,
          data: {
            treeId: result.tree.id,
            treeName: result.tree.name,
            invitationId: result.invitation.id,
            memberUserId: result.invitation.userId,
          },
        });
      }

      res.json({
        ok: true,
        accepted: result.accepted,
        tree: mapTree(result.tree),
        invitation: mapTreeInvitation(result.invitation, result.tree),
      });
    },
  );
}

module.exports = {
  registerTreeInvitationRoutes,
};
