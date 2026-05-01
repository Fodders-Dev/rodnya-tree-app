function registerPostRoutes(
  app,
  {
    store,
    requireAuth,
    requireTreeAccess,
    composeDisplayName,
    mapPost,
    mapComment,
  },
) {
  app.get("/v1/posts", requireAuth, async (req, res) => {
    const treeId = String(req.query.treeId || "").trim() || null;
    const authorId = String(req.query.authorId || "").trim() || null;
    const scope = String(req.query.scope || "").trim() || null;

    if (treeId) {
      const tree = await requireTreeAccess(req, res, treeId);
      if (!tree) {
        return;
      }
    }

    const accessibleTrees = await store.listUserTrees(req.auth.user.id);
    const accessibleTreeIds = new Set(accessibleTrees.map((tree) => tree.id));
    const posts = await store.listPosts({
      treeId,
      authorId,
      scope,
      viewerUserId: req.auth.user.id,
    });
    const visiblePosts = posts.filter((post) => accessibleTreeIds.has(post.treeId));
    const payload = await Promise.all(
      visiblePosts.map(async (post) => {
        const comments = await store.listPostComments(post.id);
        return mapPost(post, comments.length);
      }),
    );

    res.json(payload);
  });

  app.post("/v1/posts", requireAuth, async (req, res) => {
    const treeId = String(req.body?.treeId || "").trim();
    const content = String(req.body?.content || "");
    const imageUrls = Array.isArray(req.body?.imageUrls) ? req.body.imageUrls : [];
    const isPublic = req.body?.isPublic === true;
    const scopeType = String(req.body?.scopeType || "wholeTree").trim();
    const circleId = String(req.body?.circleId || "").trim() || null;
    const anchorPersonIds = Array.isArray(req.body?.anchorPersonIds)
      ? req.body.anchorPersonIds
      : [];

    if (!treeId) {
      res.status(400).json({message: "Нужен treeId"});
      return;
    }

    const tree = await requireTreeAccess(req, res, treeId);
    if (!tree) {
      return;
    }

    if (circleId) {
      const circle = await store.findCircle(tree.id, circleId);
      if (!circle) {
        res.status(400).json({message: "Круг не найден"});
        return;
      }
    }

    const treePersons = await store.listPersons(tree.id);
    const validPersonIds = new Set(treePersons.map((person) => person.id));
    const normalizedAnchorPersonIds = anchorPersonIds
      .map((value) => String(value || "").trim())
      .filter((value) => validPersonIds.has(value));

    const post = await store.createPost({
      treeId: tree.id,
      authorId: req.auth.user.id,
      authorName:
        req.auth.user.profile?.displayName ||
        composeDisplayName(req.auth.user.profile) ||
        req.auth.user.email ||
        "Аноним",
      authorPhotoUrl: req.auth.user.profile?.photoUrl || null,
      content,
      imageUrls,
      isPublic,
      scopeType,
      anchorPersonIds: normalizedAnchorPersonIds,
      circleId,
    });

    if (post === false) {
      res.status(400).json({message: "Пост не должен быть пустым"});
      return;
    }
    if (!post) {
      res.status(404).json({message: "Дерево не найдено"});
      return;
    }

    res.status(201).json(mapPost(post, 0));
  });

  app.delete("/v1/posts/:postId", requireAuth, async (req, res) => {
    const post = await store.findPost(req.params.postId);
    if (!post) {
      res.status(404).json({message: "Публикация не найдена"});
      return;
    }

    const tree = await requireTreeAccess(req, res, post.treeId);
    if (!tree) {
      return;
    }

    const deleted = await store.deletePost(req.params.postId, req.auth.user.id);
    if (deleted === false) {
      res.status(403).json({message: "Можно удалять только свои публикации"});
      return;
    }

    res.status(204).send();
  });

  app.post("/v1/posts/:postId/like", requireAuth, async (req, res) => {
    const post = await store.findPost(req.params.postId);
    if (!post) {
      res.status(404).json({message: "Публикация не найдена"});
      return;
    }

    const tree = await requireTreeAccess(req, res, post.treeId);
    if (!tree) {
      return;
    }

    const updated = await store.togglePostLike(req.params.postId, req.auth.user.id);
    const comments = await store.listPostComments(req.params.postId);
    res.json(mapPost(updated, comments.length));
  });

  app.get("/v1/posts/:postId/comments", requireAuth, async (req, res) => {
    const post = await store.findPost(req.params.postId);
    if (!post) {
      res.status(404).json({message: "Публикация не найдена"});
      return;
    }

    const tree = await requireTreeAccess(req, res, post.treeId);
    if (!tree) {
      return;
    }

    const comments = await store.listPostComments(req.params.postId);
    res.json(comments.map(mapComment));
  });

  app.post("/v1/posts/:postId/comments", requireAuth, async (req, res) => {
    const post = await store.findPost(req.params.postId);
    if (!post) {
      res.status(404).json({message: "Публикация не найдена"});
      return;
    }

    const tree = await requireTreeAccess(req, res, post.treeId);
    if (!tree) {
      return;
    }

    const comment = await store.addPostComment({
      postId: req.params.postId,
      authorId: req.auth.user.id,
      authorName:
        req.auth.user.profile?.displayName ||
        composeDisplayName(req.auth.user.profile) ||
        req.auth.user.email ||
        "Аноним",
      authorPhotoUrl: req.auth.user.profile?.photoUrl || null,
      content: req.body?.content,
    });

    if (comment === false) {
      res.status(400).json({message: "Комментарий не должен быть пустым"});
      return;
    }

    res.status(201).json(mapComment(comment));
  });

  app.delete(
    "/v1/posts/:postId/comments/:commentId",
    requireAuth,
    async (req, res) => {
      const post = await store.findPost(req.params.postId);
      if (!post) {
        res.status(404).json({message: "Публикация не найдена"});
        return;
      }

      const tree = await requireTreeAccess(req, res, post.treeId);
      if (!tree) {
        return;
      }

      const deleted = await store.deletePostComment({
        postId: req.params.postId,
        commentId: req.params.commentId,
        actorUserId: req.auth.user.id,
      });
      if (deleted === null) {
        res.status(404).json({message: "Комментарий не найден"});
        return;
      }
      if (deleted === false) {
        res
          .status(403)
          .json({message: "Недостаточно прав для удаления комментария"});
        return;
      }

      res.status(204).send();
    },
  );
}

module.exports = {
  registerPostRoutes,
};
