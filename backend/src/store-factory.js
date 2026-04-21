const {FileStore} = require("./store");
const {PostgresStore} = require("./postgres-store");

async function createStore(config) {
  const storageBackend = String(config?.storageBackend || "file")
    .trim()
    .toLowerCase();

  switch (storageBackend) {
    case "file":
    case "file-store": {
      const store = new FileStore(config.dataPath);
      await store.initialize();
      store.storageMode = "file-store";
      store.storageTarget = config.dataPath;
      return store;
    }
    case "postgres":
    case "postgresql": {
      const store = new PostgresStore({
        connectionString: config.postgresUrl,
        schema: config.postgresSchema,
        table: config.postgresStateTable,
        rowId: config.postgresStateRowId,
        pool: config.postgresPool || config._pool || null,
        poolMax: config.postgresPoolMax,
        applicationName: config.postgresApplicationName,
      });
      await store.initialize();
      return store;
    }
    default:
      throw new Error(
        `Unsupported RODNYA_BACKEND_STORAGE value: ${storageBackend}`,
      );
  }
}

module.exports = {
  createStore,
};
