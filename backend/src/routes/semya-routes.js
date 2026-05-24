// Phase B Week 2 Ship 2: семья HTTP endpoints (5 routes).
//
// Per Phase B SHARED-TREE-PROPOSAL.md + ENTITY-DESIGN.md §1, §6.
//
// Endpoints:
//   POST   /v1/semya               — create семья (wraps existing tree)
//   GET    /v1/me/semya            — list мои семьи
//   GET    /v1/semya/:id           — детали (viewer+ access)
//   PATCH  /v1/semya/:id           — rename / re-describe (owner)
//   DELETE /v1/semya/:id           — soft-delete (owner, 90d hard-delete window)
//
// Permission gates via `requireSemyaAccess(req, res, semyaId, {requiredRole})`
// — viewer < editor < owner hierarchy enforced.
//
// NB: Permission middleware live в app.js — экспорт через
// `registerSemyaRoutes` параметр (mirror requireTreeAccess pattern для
// kinship-checks / tree routes).
//
// Ship 2 не включает:
//   * membership endpoints (Ship 3 — add/remove members, role transitions)
//   * invitation flow (Ship 4 — create/accept/revoke invitations)
//   * tree binding compat shim (Week 3 — tree.семьяId field + dual-write)
//   * notification dispatch (Week 3 — broadcast scope to семья members)
//
// Создание семья через POST /v1/semya требует уже-существующий tree.
// Auto-create tree + семья atomically — future onboarding flow scope.

function registerSemyaRoutes(
  app,
  {store, requireAuth, requireSemyaAccess},
) {
  function mapSemya(semya) {
    if (!semya) return null;
    return {
      id: semya.id,
      name: semya.name,
      ownerId: semya.ownerId,
      treeId: semya.treeId,
      description: semya.description ?? null,
      createdAt: semya.createdAt,
      updatedAt: semya.updatedAt,
      deletedAt: semya.deletedAt ?? null,
    };
  }

  // POST /v1/semya — create семья referencing existing tree.
  // Caller (req.auth.user) becomes owner — atomic membership row
  // created в store.createSemya. Treeid validation в store layer
  // (one-tree-per-семья invariant + tree-existence check).
  app.post("/v1/semya", requireAuth, async (req, res) => {
    const name = String(req.body?.name || "").trim();
    const treeId = String(req.body?.treeId || "").trim();
    const description = req.body?.description
      ? String(req.body.description).trim()
      : null;

    if (!name) {
      res.status(400).json({message: "Нужно название семьи"});
      return;
    }
    if (!treeId) {
      res.status(400).json({message: "Нужен treeId"});
      return;
    }

    // Per ENTITY-DESIGN §3.1: caller must own / be member of tree
    // чтобы bind его к новой семье. Без этой проверки кто угодно
    // мог бы «adopt» чужое дерево созданием семья поверх. Tree
    // membership check delegated to existing tree.creatorId /
    // tree.memberIds — pre-Phase B model (dual-write compat shim
    // придёт в Week 3).
    const tree = await store.findTree(treeId);
    if (!tree) {
      res.status(404).json({message: "Дерево не найдено"});
      return;
    }
    const treeMemberIds = Array.isArray(tree.memberIds) ? tree.memberIds : [];
    const ownsOrMembers =
      tree.creatorId === req.auth.user.id ||
      treeMemberIds.includes(req.auth.user.id);
    if (!ownsOrMembers) {
      res.status(403).json({message: "Это не ваше дерево"});
      return;
    }

    try {
      const semya = await store.createSemya({
        ownerId: req.auth.user.id,
        name,
        treeId,
        description,
      });
      res.status(201).json({semya: mapSemya(semya)});
    } catch (error) {
      const code = error?.message;
      if (code === "TREE_ALREADY_BOUND") {
        res.status(409).json({
          message: "У этого дерева уже есть семья",
        });
        return;
      }
      if (
        code === "INVALID_NAME" ||
        code === "INVALID_TREE_ID" ||
        code === "INVALID_OWNER_ID"
      ) {
        res.status(400).json({message: "Некорректные параметры"});
        return;
      }
      if (code === "TREE_NOT_FOUND" || code === "OWNER_NOT_FOUND") {
        res.status(404).json({message: "Связанные данные не найдены"});
        return;
      }
      throw error;
    }
  });

  // GET /v1/me/semya — list семья membership of current user.
  app.get("/v1/me/semya", requireAuth, async (req, res) => {
    const semyi = await store.listSemyiForUser(req.auth.user.id);
    res.json({semyi: semyi.map(mapSemya)});
  });

  // GET /v1/semya/:id — details (viewer+ access).
  app.get("/v1/semya/:id", requireAuth, async (req, res) => {
    const access = await requireSemyaAccess(req, res, req.params.id, {
      requiredRole: "viewer",
    });
    if (!access) return;
    res.json({semya: mapSemya(access.semya), membership: access.membership});
  });

  // PATCH /v1/semya/:id — rename / re-describe (owner only).
  app.patch("/v1/semya/:id", requireAuth, async (req, res) => {
    const access = await requireSemyaAccess(req, res, req.params.id, {
      requiredRole: "owner",
    });
    if (!access) return;

    const updates = {semyaId: req.params.id, actorUserId: req.auth.user.id};
    if (req.body?.name !== undefined) {
      updates.name = req.body.name;
    }
    if (req.body?.description !== undefined) {
      updates.description = req.body.description;
    }
    if (updates.name === undefined && updates.description === undefined) {
      res.status(400).json({message: "Нечего обновлять"});
      return;
    }

    try {
      const updated = await store.updateSemya(updates);
      res.json({semya: mapSemya(updated)});
    } catch (error) {
      const code = error?.message;
      if (code === "SEMYA_NOT_FOUND") {
        // requireSemyaAccess уже отсеял этот case; покрываем race
        // (concurrent delete) — return 404.
        res.status(404).json({message: "Семья не найдена"});
        return;
      }
      if (code === "NOT_OWNER") {
        res.status(403).json({message: "Только владелец может изменить семью"});
        return;
      }
      if (code === "INVALID_NAME") {
        res.status(400).json({message: "Некорректное название"});
        return;
      }
      throw error;
    }
  });

  // DELETE /v1/semya/:id — soft-delete (owner). Hard-delete через
  // background job через 90d window (Q5 — restore via hardDelete
  // pattern). Members lose access immediately (memberships hidden).
  // Notifications к members — Week 3 broadcast work, не Ship 2 scope.
  app.delete("/v1/semya/:id", requireAuth, async (req, res) => {
    const access = await requireSemyaAccess(req, res, req.params.id, {
      requiredRole: "owner",
    });
    if (!access) return;

    try {
      const deleted = await store.softDeleteSemya({
        semyaId: req.params.id,
        actorUserId: req.auth.user.id,
      });
      res.json({semya: mapSemya(deleted)});
    } catch (error) {
      const code = error?.message;
      if (code === "SEMYA_NOT_FOUND") {
        res.status(404).json({message: "Семья не найдена"});
        return;
      }
      if (code === "NOT_OWNER") {
        res.status(403).json({message: "Только владелец может удалить семью"});
        return;
      }
      throw error;
    }
  });
}

module.exports = {registerSemyaRoutes};
