const {createConfig} = require("./config");
const {createStore} = require("./store-factory");
const {createMediaStorage} = require("./media-storage");
const {createApp} = require("./app");
const {RealtimeHub} = require("./realtime-hub");
const {PushGateway} = require("./push-gateway");

async function startServer() {
  const config = createConfig();
  const store = await createStore(config);
  const mediaStorage = createMediaStorage(config);

  const realtimeHub = new RealtimeHub({store});
  const pushGateway = new PushGateway({store, config});
  const app = createApp({
    store,
    config,
    realtimeHub,
    pushGateway,
    mediaStorage,
  });
  const server = app.listen(config.port, "127.0.0.1", () => {
    console.log(
      `[lineage-backend] listening on http://127.0.0.1:${config.port}`,
    );
    console.log(`[lineage-backend] data path: ${config.dataPath}`);
    console.log(`[lineage-backend] media root: ${config.mediaRootPath}`);
    console.log(
      `[lineage-backend] storage mode: ${store.storageMode || config.storageBackend || "unknown"}`,
    );
    console.log(
      `[lineage-backend] media mode: ${mediaStorage.mediaMode || config.mediaBackend || "unknown"}`,
    );
  });
  realtimeHub.attach(server);

  return {app, server, store, config, realtimeHub, pushGateway, mediaStorage};
}

if (require.main === module) {
  startServer().catch((error) => {
    console.error("[lineage-backend] failed to start", error);
    process.exitCode = 1;
  });
}

module.exports = {
  startServer,
};
