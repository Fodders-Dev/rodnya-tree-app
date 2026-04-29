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

    const linkedPerson = await store.linkPersonToUser({
      treeId,
      personId,
      userId: req.auth.user.id,
    });

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
