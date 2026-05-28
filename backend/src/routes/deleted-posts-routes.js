// Ship Q4a (2026-05-28, Ship 30b): deletedPosts «корзина» HTTP
// endpoints. Mirror persons pattern (Ship 30 — deleted-persons-routes).
//
// Per PHASE-Q4A-SOFT-DELETE-DESIGN (ec12804) + 8 decisions locked
// 2026-05-28. Path 2 architecture — posts move к db.deletedPosts
// snapshot collection on delete, recoverable for 30d.
//
// Endpoints:
//   GET    /v1/me/deleted-posts                — caller's deleted posts
//   POST   /v1/deleted-posts/:id/restore       — restore (author либо semя owner)
//   DELETE /v1/deleted-posts/:id               — manual hard-purge (3h floor)
//
// Permission summary:
//   • GET — only own deleted posts (author === deletedByUserId)
//   • POST restore — author либо owner of семья bound к post's tree
//   • DELETE hard-purge — only author (per dispatch decision)

function registerDeletedPostsRoutes(
  app,
  {store, requireAuth},
) {
  function mapDeletedPost(row) {
    if (!row) return null;
    return {
      id: row.id,
      originalPostId: row.originalPostId,
      treeId: row.treeId,
      snapshot: row.snapshot,
      commentsSnapshot: row.commentsSnapshot ?? [],
      postReactionsSnapshot: row.postReactionsSnapshot ?? [],
      commentReactionsSnapshot: row.commentReactionsSnapshot ?? [],
      deletedAt: row.deletedAt,
      deletedByUserId: row.deletedByUserId ?? null,
      hardDeleteScheduledAt: row.hardDeleteScheduledAt,
      earliestHardDelete: row.earliestHardDelete,
      restoredAt: row.restoredAt ?? null,
      restoredByUserId: row.restoredByUserId ?? null,
    };
  }

  // GET /v1/me/deleted-posts — caller's soft-deleted posts.
  app.get("/v1/me/deleted-posts", requireAuth, async (req, res) => {
    const rows = await store.listDeletedPostsForUser({
      userId: req.auth.user.id,
    });
    res.json({deletedPosts: rows.map(mapDeletedPost)});
  });

  // POST /v1/deleted-posts/:id/restore — restore из snapshot.
  app.post(
    "/v1/deleted-posts/:id/restore",
    requireAuth,
    async (req, res) => {
      try {
        const restored = await store.restorePost({
          deletedPostId: req.params.id,
          actorUserId: req.auth.user.id,
        });
        res.json({restored: mapDeletedPost(restored)});
      } catch (error) {
        const code = error?.message;
        if (code === "DELETED_POST_NOT_FOUND") {
          res.status(404).json({message: "Удалённая публикация не найдена"});
          return;
        }
        if (code === "ALREADY_RESTORED") {
          res.status(409).json({message: "Уже восстановлена"});
          return;
        }
        if (code === "HARD_DELETE_ELAPSED") {
          res.status(410).json({
            message: "Срок восстановления истёк — публикация удалена навсегда",
          });
          return;
        }
        if (code === "FORBIDDEN") {
          res.status(403).json({
            message:
              "Восстановить может только автор либо владелец семьи",
          });
          return;
        }
        if (
          code === "INVALID_INPUT" ||
          code === "INVALID_ACTOR"
        ) {
          res.status(400).json({message: "Некорректные параметры"});
          return;
        }
        throw error;
      }
    },
  );

  // DELETE /v1/deleted-posts/:id — manual hard-purge.
  app.delete(
    "/v1/deleted-posts/:id",
    requireAuth,
    async (req, res) => {
      try {
        const result = await store.hardDeletePost({
          deletedPostId: req.params.id,
          actorUserId: req.auth.user.id,
        });
        res.json(result);
      } catch (error) {
        const code = error?.message;
        if (code === "DELETED_POST_NOT_FOUND") {
          res.status(404).json({message: "Удалённая публикация не найдена"});
          return;
        }
        if (code === "ALREADY_RESTORED") {
          res.status(409).json({
            message: "Публикация восстановлена — удалить нельзя",
          });
          return;
        }
        if (code === "FLOOR_NOT_MET") {
          res.status(409).json({
            message:
              "Подождите немного перед окончательным удалением (защита от случайного нажатия)",
          });
          return;
        }
        if (code === "FORBIDDEN") {
          res.status(403).json({
            message: "Удалить навсегда может только автор",
          });
          return;
        }
        if (
          code === "INVALID_INPUT" ||
          code === "INVALID_ACTOR"
        ) {
          res.status(400).json({message: "Некорректные параметры"});
          return;
        }
        throw error;
      }
    },
  );
}

module.exports = {registerDeletedPostsRoutes};
