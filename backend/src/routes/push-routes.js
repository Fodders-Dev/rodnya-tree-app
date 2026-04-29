function registerPushRoutes(
  app,
  {store, config, requireAuth, mapPushDevice, mapPushDelivery},
) {
  app.get("/v1/push/devices", requireAuth, async (req, res) => {
    const devices = await store.listPushDevices(req.auth.user.id);
    res.json({
      devices: devices.map(mapPushDevice),
    });
  });

  app.get("/v1/push/web/config", requireAuth, async (req, res) => {
    res.json({
      enabled: Boolean(config.webPushEnabled),
      publicKey: config.webPushEnabled ? config.webPushPublicKey : null,
    });
  });

  app.post("/v1/push/devices", requireAuth, async (req, res) => {
    const provider = String(req.body?.provider || "").trim();
    const token = String(req.body?.token || "").trim();
    const platform = String(req.body?.platform || "unknown").trim();

    if (!provider || !token) {
      res.status(400).json({message: "Нужны provider и token"});
      return;
    }

    const device = await store.registerPushDevice({
      userId: req.auth.user.id,
      provider,
      token,
      platform,
    });

    if (device === null) {
      res.status(404).json({message: "Пользователь не найден"});
      return;
    }
    if (device === false) {
      res.status(400).json({message: "Недопустимые provider или token"});
      return;
    }

    res.status(201).json({
      device: mapPushDevice(device),
    });
  });

  app.delete("/v1/push/devices/:deviceId", requireAuth, async (req, res) => {
    const deleted = await store.deletePushDevice(
      req.params.deviceId,
      req.auth.user.id,
    );
    if (!deleted) {
      res.status(404).json({message: "Устройство не найдено"});
      return;
    }

    res.status(204).send();
  });

  app.get("/v1/push/deliveries", requireAuth, async (req, res) => {
    const limit = Number(req.query.limit || 50);
    const deliveries = await store.listPushDeliveries(req.auth.user.id, {
      limit,
    });
    res.json({
      deliveries: deliveries.map(mapPushDelivery),
    });
  });
}

module.exports = {
  registerPushRoutes,
};
