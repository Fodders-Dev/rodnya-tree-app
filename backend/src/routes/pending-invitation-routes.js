function registerPendingInvitationRoutes(
  app,
  {store, requireAuth, mapTree, mapPerson},
) {
  app.post("/v1/invitations/pending/process", requireAuth, async (req, res) => {
    const treeId = String(req.body?.treeId || "").trim();
    const personId = String(req.body?.personId || "").trim();

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
      });
    } catch (error) {
      const code = error?.message;
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
