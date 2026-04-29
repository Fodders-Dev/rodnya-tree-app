function registerSafetyRoutes(app, {store, requireAuth, mapBlock, mapReport}) {
  app.get("/v1/blocks", requireAuth, async (req, res) => {
    const blocks = await store.listUserBlocks(req.auth.user.id);
    const mappedBlocks = [];
    for (const block of blocks) {
      const blockedUser = await store.findUserById(block.blockedUserId);
      mappedBlocks.push(mapBlock(block, blockedUser));
    }

    res.json({
      blocks: mappedBlocks,
    });
  });

  app.post("/v1/blocks", requireAuth, async (req, res) => {
    const blockedUserId = String(req.body?.userId || "").trim();
    if (!blockedUserId) {
      res.status(400).json({message: "Нужен userId"});
      return;
    }

    const block = await store.createUserBlock({
      blockerId: req.auth.user.id,
      blockedUserId,
      reason: req.body?.reason,
      metadata: req.body?.metadata,
    });
    if (block === false) {
      res.status(400).json({message: "Нельзя заблокировать этого пользователя"});
      return;
    }
    if (block === null) {
      res.status(404).json({message: "Пользователь для блокировки не найден"});
      return;
    }

    const blockedUser = await store.findUserById(block.blockedUserId);
    res.status(201).json({
      block: mapBlock(block, blockedUser),
    });
  });

  app.delete("/v1/blocks/:blockId", requireAuth, async (req, res) => {
    const removed = await store.deleteUserBlock({
      blockId: req.params.blockId,
      blockerId: req.auth.user.id,
    });
    if (!removed) {
      res.status(404).json({message: "Блокировка не найдена"});
      return;
    }

    res.status(204).end();
  });

  app.post("/v1/reports", requireAuth, async (req, res) => {
    const targetType = String(req.body?.targetType || "").trim();
    const targetId = String(req.body?.targetId || "").trim();
    if (!targetType || !targetId) {
      res.status(400).json({message: "Нужны targetType и targetId"});
      return;
    }

    const report = await store.createReport({
      reporterId: req.auth.user.id,
      targetType,
      targetId,
      reason: req.body?.reason,
      details: req.body?.details,
      metadata: req.body?.metadata,
    });
    if (report === false) {
      res.status(400).json({message: "Некорректные параметры жалобы"});
      return;
    }
    if (report === null) {
      res.status(404).json({message: "Отправитель жалобы не найден"});
      return;
    }

    res.status(201).json({
      report: mapReport(report, req.auth.user),
    });
  });
}

module.exports = {
  registerSafetyRoutes,
};
