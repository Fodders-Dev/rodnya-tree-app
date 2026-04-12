const {FileStore} = require("./store");

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
    case "postgresql":
      throw new Error(
        "LINEAGE_BACKEND_STORAGE=postgres is not implemented yet. Add a PostgresStore adapter before enabling it.",
      );
    default:
      throw new Error(
        `Unsupported LINEAGE_BACKEND_STORAGE value: ${storageBackend}`,
      );
  }
}

module.exports = {
  createStore,
};
