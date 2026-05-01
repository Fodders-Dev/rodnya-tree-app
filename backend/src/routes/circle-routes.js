function mapCircle(circle) {
  return {
    id: circle.id,
    treeId: circle.treeId,
    kind: circle.kind || "custom",
    name: circle.name || "Круг",
    description: circle.description || null,
    createdBy: circle.createdBy || null,
    isSystem: circle.isSystem === true,
    anchorPersonId: circle.anchorPersonId || null,
    anchorPersonIds: Array.isArray(circle.anchorPersonIds)
      ? circle.anchorPersonIds
      : [],
    memberCount: Number(circle.memberCount || 0),
    createdAt: circle.createdAt,
    updatedAt: circle.updatedAt || circle.createdAt,
  };
}

function registerCircleRoutes(app, {store, requireAuth, requireTreeAccess}) {
  app.get("/v1/trees/:treeId/circles", requireAuth, async (req, res) => {
    const tree = await requireTreeAccess(req, res, req.params.treeId);
    if (!tree) {
      return;
    }

    const circles = await store.listCircles(tree.id);
    res.json({circles: (circles || []).map(mapCircle)});
  });

  app.post("/v1/trees/:treeId/circles", requireAuth, async (req, res) => {
    const tree = await requireTreeAccess(req, res, req.params.treeId);
    if (!tree) {
      return;
    }

    const name = String(req.body?.name || "").trim();
    if (!name) {
      res.status(400).json({message: "Нужно название круга"});
      return;
    }

    const circle = await store.createCircle({
      treeId: tree.id,
      name,
      description: req.body?.description,
      createdBy: req.auth.user.id,
    });
    res.status(201).json(mapCircle(circle));
  });

  app.patch("/v1/trees/:treeId/circles/:circleId", requireAuth, async (req, res) => {
    const tree = await requireTreeAccess(req, res, req.params.treeId);
    if (!tree) {
      return;
    }

    const updated = await store.updateCircle({
      treeId: tree.id,
      circleId: req.params.circleId,
      name: req.body?.name,
      description: req.body?.description,
    });
    if (updated === null) {
      res.status(404).json({message: "Круг не найден"});
      return;
    }
    if (updated === false) {
      res.status(403).json({message: "Системный круг нельзя изменить"});
      return;
    }

    res.json(mapCircle(updated));
  });

  app.put(
    "/v1/trees/:treeId/circles/:circleId/members",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) {
        return;
      }

      const updated = await store.replaceCircleMembers({
        treeId: tree.id,
        circleId: req.params.circleId,
        identityIds: Array.isArray(req.body?.identityIds)
          ? req.body.identityIds
          : [],
        personIds: Array.isArray(req.body?.personIds) ? req.body.personIds : [],
      });
      if (updated === null) {
        res.status(404).json({message: "Круг не найден"});
        return;
      }
      if (updated === false) {
        res.status(403).json({message: "Состав системного круга нельзя изменить"});
        return;
      }

      res.json(mapCircle(updated));
    },
  );

  app.get(
    "/v1/trees/:treeId/circles/:circleId/members",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) {
        return;
      }

      const members = await store.listCircleMembers(tree.id, req.params.circleId);
      if (members === null) {
        res.status(404).json({message: "Круг не найден"});
        return;
      }

      res.json({members});
    },
  );

  app.delete(
    "/v1/trees/:treeId/circles/:circleId",
    requireAuth,
    async (req, res) => {
      const tree = await requireTreeAccess(req, res, req.params.treeId);
      if (!tree) {
        return;
      }

      const deleted = await store.deleteCircle({
        treeId: tree.id,
        circleId: req.params.circleId,
      });
      if (deleted === null) {
        res.status(404).json({message: "Круг не найден"});
        return;
      }
      if (deleted === false) {
        res.status(403).json({message: "Системный круг нельзя удалить"});
        return;
      }

      res.status(204).send();
    },
  );
}

module.exports = {
  registerCircleRoutes,
};
