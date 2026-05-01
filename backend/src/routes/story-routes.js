function registerStoryRoutes(
  app,
  {store, requireAuth, requireTreeAccess, composeDisplayName, mapStory},
) {
  app.get("/v1/stories", requireAuth, async (req, res) => {
    const treeId = String(req.query.treeId || "").trim() || null;
    const authorId = String(req.query.authorId || "").trim() || null;

    if (treeId) {
      const tree = await requireTreeAccess(req, res, treeId);
      if (!tree) {
        return;
      }
    }

    const accessibleTrees = await store.listUserTrees(req.auth.user.id);
    const accessibleTreeIds = new Set(accessibleTrees.map((tree) => tree.id));
    const stories = await store.listStories({
      treeId,
      authorId,
      viewerUserId: req.auth.user.id,
    });
    const visibleStories = stories.filter((story) =>
      accessibleTreeIds.has(story.treeId),
    );

    res.json(visibleStories.map(mapStory));
  });

  app.post("/v1/stories", requireAuth, async (req, res) => {
    const treeId = String(req.body?.treeId || "").trim();
    const type = String(req.body?.type || "text").trim();
    const text = req.body?.text;
    const mediaUrl = req.body?.mediaUrl;
    const thumbnailUrl = req.body?.thumbnailUrl;
    const expiresAt = req.body?.expiresAt;
    const circleId = String(req.body?.circleId || "").trim() || null;

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

    const story = await store.createStory({
      treeId: tree.id,
      authorId: req.auth.user.id,
      authorName:
        req.auth.user.profile?.displayName ||
        composeDisplayName(req.auth.user.profile) ||
        req.auth.user.email ||
        "Аноним",
      authorPhotoUrl: req.auth.user.profile?.photoUrl || null,
      type,
      text,
      mediaUrl,
      thumbnailUrl,
      expiresAt,
      circleId,
    });

    if (story === false) {
      res.status(400).json({
        message: "Story должна содержать текст или media в зависимости от типа",
      });
      return;
    }
    if (!story) {
      res.status(404).json({message: "Дерево не найдено"});
      return;
    }

    res.status(201).json(mapStory(story));
  });

  app.post("/v1/stories/:storyId/view", requireAuth, async (req, res) => {
    const story = await store.findStory(req.params.storyId);
    if (!story) {
      res.status(404).json({message: "Story не найдена"});
      return;
    }

    const tree = await requireTreeAccess(req, res, story.treeId);
    if (!tree) {
      return;
    }

    const updatedStory = await store.markStoryViewed(
      req.params.storyId,
      req.auth.user.id,
    );
    if (!updatedStory) {
      res.status(404).json({message: "Story не найдена"});
      return;
    }

    res.json(mapStory(updatedStory));
  });

  app.delete("/v1/stories/:storyId", requireAuth, async (req, res) => {
    const story = await store.findStory(req.params.storyId);
    if (!story) {
      res.status(404).json({message: "Story не найдена"});
      return;
    }

    const tree = await requireTreeAccess(req, res, story.treeId);
    if (!tree) {
      return;
    }

    const deletedStory = await store.deleteStory(req.params.storyId, req.auth.user.id);
    if (deletedStory === false) {
      res.status(403).json({message: "Можно удалять только свои stories"});
      return;
    }
    if (!deletedStory) {
      res.status(404).json({message: "Story не найдена"});
      return;
    }

    res.status(204).send();
  });
}

module.exports = {
  registerStoryRoutes,
};
