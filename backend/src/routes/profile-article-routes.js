// Profile Phase 1 (2026-05-28): article-style biography CRUD endpoints.
//
// Per PROFILE-UX-REDESIGN-PROPOSAL (674c6ea) + 8 decisions locked
// 2026-05-28. Article = ordered content blocks attached to a person,
// stored in db.profileArticles (separate collection). Multi-author:
// per-block authorUserId + last-write-wins (Q3); full history reuses
// treeChangeRecords (`article.*`).
//
// Endpoints:
//   GET    /v1/persons/:personId/article                  — read (member)
//   POST   /v1/persons/:personId/article/blocks           — append block
//   PATCH  /v1/persons/:personId/article/blocks/:blockId  — edit block
//   DELETE /v1/persons/:personId/article/blocks/:blockId  — remove block
//   PUT    /v1/persons/:personId/article/blocks/order     — reorder
//   GET    /v1/persons/:personId/article/history          — audit log
//
// Permission model — single source of truth, NO parallel rule:
//   • Reads gated by requireTreeAccess (any member / tree-accessor).
//   • Writes gated by requireGraphPersonEdit(...,'edit') — THE canonical
//     person-edit gate. "If you can edit the person, you can edit their
//     article." Handles семья roles (viewer read-only), standalone trees,
//     anonymous persons, and the graph-person grant model uniformly.

function registerProfileArticleRoutes(
  app,
  {store, requireAuth, requireTreeAccess, requireGraphPersonEdit},
) {
  // Resolve the person's treeId for the permission gate. Returns null
  // (and sends 404) when the person doesn't exist.
  async function resolveTreeIdOr404(req, res) {
    const treeId = await store.findPersonTreeId(req.params.personId);
    if (!treeId) {
      res.status(404).json({message: "Человек не найден"});
      return null;
    }
    return treeId;
  }

  // Map store-thrown string codes → HTTP. Returns true if handled.
  function handleArticleError(res, error) {
    const code = error?.message;
    if (code === "PERSON_NOT_FOUND") {
      res.status(404).json({message: "Человек не найден"});
      return true;
    }
    if (code === "ARTICLE_BLOCK_NOT_FOUND" || code === "ARTICLE_NOT_FOUND") {
      res.status(404).json({message: "Фрагмент биографии не найден"});
      return true;
    }
    if (code === "INVALID_BLOCK_TYPE") {
      res.status(400).json({message: "Неизвестный тип блока"});
      return true;
    }
    if (code === "INVALID_BLOCK_CONTENT") {
      res.status(400).json({message: "Некорректное содержимое блока"});
      return true;
    }
    if (code === "INVALID_INPUT" || code === "INVALID_ACTOR") {
      res.status(400).json({message: "Некорректные параметры"});
      return true;
    }
    return false;
  }

  // GET — read article. Tree access (read) is sufficient.
  app.get("/v1/persons/:personId/article", requireAuth, async (req, res) => {
    const treeId = await resolveTreeIdOr404(req, res);
    if (!treeId) return;
    const tree = await requireTreeAccess(req, res, treeId);
    if (!tree) return;
    try {
      const article = await store.getProfileArticle({
        personId: req.params.personId,
      });
      res.json({article});
    } catch (error) {
      if (handleArticleError(res, error)) return;
      throw error;
    }
  });

  // POST — append a block.
  app.post(
    "/v1/persons/:personId/article/blocks",
    requireAuth,
    async (req, res) => {
      const treeId = await resolveTreeIdOr404(req, res);
      if (!treeId) return;
      const ctx = await requireGraphPersonEdit(
        req,
        res,
        treeId,
        req.params.personId,
        "edit",
      );
      if (!ctx) return;
      try {
        const block = await store.appendArticleBlock({
          personId: req.params.personId,
          type: req.body?.type,
          content: req.body?.content,
          actorUserId: req.auth.user.id,
        });
        res.status(201).json({block});
      } catch (error) {
        if (handleArticleError(res, error)) return;
        throw error;
      }
    },
  );

  // PATCH — edit one block. body: {content, baseUpdatedAt?}.
  app.patch(
    "/v1/persons/:personId/article/blocks/:blockId",
    requireAuth,
    async (req, res) => {
      const treeId = await resolveTreeIdOr404(req, res);
      if (!treeId) return;
      const ctx = await requireGraphPersonEdit(
        req,
        res,
        treeId,
        req.params.personId,
        "edit",
      );
      if (!ctx) return;
      try {
        const result = await store.updateArticleBlock({
          personId: req.params.personId,
          blockId: req.params.blockId,
          content: req.body?.content,
          actorUserId: req.auth.user.id,
          baseUpdatedAt: req.body?.baseUpdatedAt ?? null,
        });
        res.json(result);
      } catch (error) {
        if (handleArticleError(res, error)) return;
        throw error;
      }
    },
  );

  // DELETE — remove one block.
  app.delete(
    "/v1/persons/:personId/article/blocks/:blockId",
    requireAuth,
    async (req, res) => {
      const treeId = await resolveTreeIdOr404(req, res);
      if (!treeId) return;
      const ctx = await requireGraphPersonEdit(
        req,
        res,
        treeId,
        req.params.personId,
        "edit",
      );
      if (!ctx) return;
      try {
        const result = await store.removeArticleBlock({
          personId: req.params.personId,
          blockId: req.params.blockId,
          actorUserId: req.auth.user.id,
        });
        res.json(result);
      } catch (error) {
        if (handleArticleError(res, error)) return;
        throw error;
      }
    },
  );

  // PUT — reorder blocks. body: {order: [blockId, ...]}.
  app.put(
    "/v1/persons/:personId/article/blocks/order",
    requireAuth,
    async (req, res) => {
      const treeId = await resolveTreeIdOr404(req, res);
      if (!treeId) return;
      const ctx = await requireGraphPersonEdit(
        req,
        res,
        treeId,
        req.params.personId,
        "edit",
      );
      if (!ctx) return;
      try {
        const article = await store.reorderArticleBlocks({
          personId: req.params.personId,
          orderedBlockIds: req.body?.order,
          actorUserId: req.auth.user.id,
        });
        res.json({article});
      } catch (error) {
        if (handleArticleError(res, error)) return;
        throw error;
      }
    },
  );

  // GET — change history (read access).
  app.get(
    "/v1/persons/:personId/article/history",
    requireAuth,
    async (req, res) => {
      const treeId = await resolveTreeIdOr404(req, res);
      if (!treeId) return;
      const tree = await requireTreeAccess(req, res, treeId);
      if (!tree) return;
      try {
        const history = await store.getArticleHistory({
          personId: req.params.personId,
        });
        res.json({history});
      } catch (error) {
        if (handleArticleError(res, error)) return;
        throw error;
      }
    },
  );
}

module.exports = {registerProfileArticleRoutes};
