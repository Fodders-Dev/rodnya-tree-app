const {Pool} = require("pg");

const DEFAULT_POSTGRES_CONNECTION_TIMEOUT_MS = 5_000;
const DEFAULT_POSTGRES_QUERY_TIMEOUT_MS = 15_000;
const DEFAULT_POSTGRES_READ_QUERY_TIMEOUT_MS = 60_000;
const DEFAULT_POSTGRES_READ_RETRY_COUNT = 1;
const DEFAULT_POSTGRES_READ_RETRY_DELAY_MS = 250;
const DEFAULT_POSTGRES_IDLE_TIMEOUT_MS = 30_000;
const DEFAULT_WRITE_QUEUE_TIMEOUT_MS = 15_000;
const DEFAULT_POSTGRES_POOL_MAX = 64;
const DEFAULT_POSTGRES_APPLICATION_NAME = "rodnya_backend";
const SHARED_POOL_REGISTRY = new Map();

function isProjectionHydrationFallbackError(error) {
  const message = String(error?.message || "").toLowerCase();
  return message.includes('column "data" does not exist');
}

function isProjectionArrayInsertFallbackError(error) {
  const message = String(error?.message || "").toLowerCase();
  return message.includes("jsonb_array_elements(jsonb) does not exist");
}

function isProjectionArrayTextFallbackError(error) {
  const message = String(error?.message || "").toLowerCase();
  return message.includes("jsonb_array_elements_text(jsonb) does not exist");
}

function computeProjectionHash(value) {
  return JSON.stringify(Array.isArray(value) ? value : []);
}

function quoteIdentifier(value) {
  const normalized = String(value || "").trim();
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(normalized)) {
    throw new Error(`Invalid PostgreSQL identifier: ${value}`);
  }
  return `"${normalized}"`;
}

function buildSharedPoolKey({
  connectionString,
  connectionTimeoutMillis,
  queryTimeoutMs,
  idleTimeoutMillis,
  poolMax,
  applicationName,
}) {
  return JSON.stringify({
    connectionString: String(connectionString || "").trim(),
    connectionTimeoutMillis,
    queryTimeoutMs,
    idleTimeoutMillis,
    poolMax,
    applicationName: String(applicationName || DEFAULT_POSTGRES_APPLICATION_NAME).trim() ||
      DEFAULT_POSTGRES_APPLICATION_NAME,
  });
}

function acquireSharedPool({
  connectionString,
  connectionTimeoutMillis,
  queryTimeoutMs,
  idleTimeoutMillis,
  poolMax,
  applicationName,
  poolFactory,
}) {
  const registryKey = buildSharedPoolKey({
    connectionString,
    connectionTimeoutMillis,
    queryTimeoutMs,
    idleTimeoutMillis,
    poolMax,
    applicationName,
  });
  let entry = SHARED_POOL_REGISTRY.get(registryKey);
  if (!entry) {
    entry = {
      refs: 0,
      pool: poolFactory({
        connectionString,
        connectionTimeoutMillis,
        idleTimeoutMillis,
        keepAlive: true,
        max: poolMax,
        query_timeout: queryTimeoutMs > 0 ? queryTimeoutMs : undefined,
        statement_timeout: queryTimeoutMs > 0 ? queryTimeoutMs : undefined,
        application_name:
          String(applicationName || DEFAULT_POSTGRES_APPLICATION_NAME).trim() ||
          DEFAULT_POSTGRES_APPLICATION_NAME,
      }),
    };
    SHARED_POOL_REGISTRY.set(registryKey, entry);
  }
  entry.refs += 1;

  let released = false;
  return {
    pool: entry.pool,
    async release() {
      if (released) {
        return;
      }
      released = true;
      entry.refs = Math.max(0, entry.refs - 1);
      if (entry.refs === 0) {
        SHARED_POOL_REGISTRY.delete(registryKey);
        await entry.pool.end();
      }
    },
  };
}

function normalizeStateVersion(raw) {
  if (raw === null || raw === undefined) {
    return null;
  }
  const numeric = Number(raw);
  return Number.isFinite(numeric) ? numeric : null;
}

module.exports = {
  Pool,
  DEFAULT_POSTGRES_CONNECTION_TIMEOUT_MS,
  DEFAULT_POSTGRES_QUERY_TIMEOUT_MS,
  DEFAULT_POSTGRES_READ_QUERY_TIMEOUT_MS,
  DEFAULT_POSTGRES_READ_RETRY_COUNT,
  DEFAULT_POSTGRES_READ_RETRY_DELAY_MS,
  DEFAULT_POSTGRES_IDLE_TIMEOUT_MS,
  DEFAULT_WRITE_QUEUE_TIMEOUT_MS,
  DEFAULT_POSTGRES_POOL_MAX,
  DEFAULT_POSTGRES_APPLICATION_NAME,
  SHARED_POOL_REGISTRY,
  isProjectionHydrationFallbackError,
  isProjectionArrayInsertFallbackError,
  isProjectionArrayTextFallbackError,
  computeProjectionHash,
  quoteIdentifier,
  buildSharedPoolKey,
  acquireSharedPool,
  normalizeStateVersion,
};
