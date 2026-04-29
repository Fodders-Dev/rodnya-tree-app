function registerNotificationRoutes(
  app,
  {store, requireAuth, mapNotification},
) {
  app.get("/v1/notifications", requireAuth, async (req, res) => {
    const status = req.query.status ? String(req.query.status) : null;
    const limit = Math.min(
      Math.max(1, Number.parseInt(String(req.query.limit || "50"), 10) || 50),
      200,
    );
    const notifications = await store.listNotifications(req.auth.user.id, {
      status,
      limit,
    });

    res.json({
      notifications: notifications.map(mapNotification),
    });
  });

  app.get("/v1/notifications/unread-count", requireAuth, async (req, res) => {
    const totalUnread = await store.countUnreadNotifications(req.auth.user.id);
    res.json({totalUnread});
  });

  app.post(
    "/v1/notifications/:notificationId/read",
    requireAuth,
    async (req, res) => {
      const notification = await store.markNotificationRead(
        req.params.notificationId,
        req.auth.user.id,
      );
      if (!notification) {
        res.status(404).json({message: "Уведомление не найдено"});
        return;
      }

      res.json({
        notification: mapNotification(notification),
      });
    },
  );
}

module.exports = {
  registerNotificationRoutes,
};
