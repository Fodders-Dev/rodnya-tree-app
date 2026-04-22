const fs = require("node:fs/promises");
const path = require("node:path");
const {Pool} = require("pg");

const {FileStore, EMPTY_DB, normalizeDbState} = require("./store");

const DEFAULT_POSTGRES_CONNECTION_TIMEOUT_MS = 5_000;
const DEFAULT_POSTGRES_QUERY_TIMEOUT_MS = 15_000;
const DEFAULT_POSTGRES_READ_QUERY_TIMEOUT_MS = 60_000;
const DEFAULT_POSTGRES_READ_RETRY_COUNT = 1;
const DEFAULT_POSTGRES_READ_RETRY_DELAY_MS = 250;
const DEFAULT_POSTGRES_IDLE_TIMEOUT_MS = 30_000;
const DEFAULT_POSTGRES_POOL_MAX = 8;
const DEFAULT_POSTGRES_APPLICATION_NAME = "rodnya_backend";
const DEFAULT_WRITE_QUEUE_TIMEOUT_MS = 15_000;

function quoteIdentifier(value) {
  const normalized = String(value || "").trim();
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(normalized)) {
    throw new Error(`Invalid PostgreSQL identifier: ${value}`);
  }
  return `"${normalized}"`;
}

class PostgresStore extends FileStore {
  constructor({
    connectionString,
    schema = "public",
    table = "rodnya_state",
    rowId = "default",
    pool = null,
    connectionTimeoutMillis = DEFAULT_POSTGRES_CONNECTION_TIMEOUT_MS,
    queryTimeoutMs = DEFAULT_POSTGRES_QUERY_TIMEOUT_MS,
    readQueryTimeoutMs = DEFAULT_POSTGRES_READ_QUERY_TIMEOUT_MS,
    readRetryCount = DEFAULT_POSTGRES_READ_RETRY_COUNT,
    readRetryDelayMs = DEFAULT_POSTGRES_READ_RETRY_DELAY_MS,
    idleTimeoutMillis = DEFAULT_POSTGRES_IDLE_TIMEOUT_MS,
    poolMax = DEFAULT_POSTGRES_POOL_MAX,
    applicationName = DEFAULT_POSTGRES_APPLICATION_NAME,
    snapshotCachePath = null,
  }) {
    super(`postgres://${schema}.${table}/${rowId}`);

    if (!pool && !String(connectionString || "").trim()) {
      throw new Error(
        "RODNYA_POSTGRES_URL is required when RODNYA_BACKEND_STORAGE=postgres",
      );
    }

    this._pool =
      pool ??
      new Pool({
        connectionString,
        connectionTimeoutMillis,
        idleTimeoutMillis,
        max:
          Number.isFinite(Number(poolMax)) && Number(poolMax) > 0
            ? Math.floor(Number(poolMax))
            : DEFAULT_POSTGRES_POOL_MAX,
        application_name:
          String(applicationName || DEFAULT_POSTGRES_APPLICATION_NAME).trim() ||
          DEFAULT_POSTGRES_APPLICATION_NAME,
        keepAlive: true,
      });
    this._ownsPool = pool == null;
    this._schema = String(schema || "public").trim() || "public";
    this._table = String(table || "rodnya_state").trim() || "rodnya_state";
    this._rowId = String(rowId || "default").trim() || "default";
    this._qualifiedTableName = `${quoteIdentifier(this._schema)}.${quoteIdentifier(this._table)}`;
    this._initializePromise = null;
    this._cachedState = null;
    this._snapshotLoadPromise = null;
    this.storageMode = "postgres";
    this.storageTarget = `${this._schema}.${this._table}:${this._rowId}`;
    this._queryTimeoutMs =
      Number.isFinite(Number(queryTimeoutMs)) && Number(queryTimeoutMs) > 0
        ? Math.floor(Number(queryTimeoutMs))
        : 0;
    this._writeQueueTimeoutMs = queryTimeoutMs > 0
      ? Math.max(queryTimeoutMs, DEFAULT_WRITE_QUEUE_TIMEOUT_MS)
      : DEFAULT_WRITE_QUEUE_TIMEOUT_MS;
    this._readQueryTimeoutMs =
      Number.isFinite(Number(readQueryTimeoutMs)) && Number(readQueryTimeoutMs) > 0
        ? Math.floor(Number(readQueryTimeoutMs))
        : 0;
    this._readRetryCount =
      Number.isFinite(Number(readRetryCount)) && Number(readRetryCount) >= 0
        ? Math.floor(Number(readRetryCount))
        : DEFAULT_POSTGRES_READ_RETRY_COUNT;
    this._readRetryDelayMs =
      Number.isFinite(Number(readRetryDelayMs)) && Number(readRetryDelayMs) >= 0
        ? Math.floor(Number(readRetryDelayMs))
        : DEFAULT_POSTGRES_READ_RETRY_DELAY_MS;
    this._snapshotCachePath = String(snapshotCachePath || "").trim() || null;
    this._snapshotCacheHydrationPromise = null;
  }

  async initialize() {
    if (!this._initializePromise) {
      this._initializePromise = this._bootstrap();
    }
    await this._initializePromise;
  }

  async _bootstrap() {
    await this._runPoolQuery(
      `CREATE SCHEMA IF NOT EXISTS ${quoteIdentifier(this._schema)}`,
    );

    await this._runPoolQuery(`
      CREATE TABLE IF NOT EXISTS ${this._qualifiedTableName} (
        id TEXT PRIMARY KEY,
        data JSONB NOT NULL,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
    await this._runPoolQuery(
      `
        INSERT INTO ${this._qualifiedTableName} (id, data)
        VALUES ($1, $2::jsonb)
        ON CONFLICT (id) DO NOTHING
      `,
      [this._rowId, JSON.stringify(EMPTY_DB)],
    );
  }

  async _read() {
    await this.initialize();
    await this._hydrateCachedStateFromSnapshotCache();
    try {
      await this._awaitWriteQueue();
    } catch (error) {
      return this._serveCachedSnapshotFallback(error, {
        phase: "await_write_queue",
      });
    }
    if (this._cachedState) {
      return structuredClone(this._cachedState);
    }

    try {
      const snapshot = await this._loadSnapshot();
      return structuredClone(snapshot);
    } catch (error) {
      return this._serveCachedSnapshotFallback(error, {
        phase: "load_snapshot",
      });
    }
  }

  async _write(data) {
    const previousQueue = this._writeQueue.catch(() => {});
    const nextWrite = previousQueue.then(async () => {
      await this.initialize();
      await this._runPoolQuery(
        `
          INSERT INTO ${this._qualifiedTableName} (id, data, updated_at)
          VALUES ($1, $2::jsonb, NOW())
          ON CONFLICT (id) DO UPDATE
          SET data = EXCLUDED.data,
              updated_at = NOW()
        `,
        [this._rowId, JSON.stringify(data)],
      );
      this._cachedState = normalizeDbState(data);
      await this._persistSnapshotCache(this._cachedState);
    });
    this._writeQueue = nextWrite.catch((error) => {
      console.error(
        "[backend] postgres-store write failed",
        JSON.stringify({
          table: `${this._schema}.${this._table}`,
          rowId: this._rowId,
          message: String(error?.message || error || "unknown_error"),
        }),
      );
      throw error;
    });

    return nextWrite;
  }

  async _runPoolQuery(text, values = undefined) {
    if (typeof this._pool.connect !== "function" || this._queryTimeoutMs <= 0) {
      if (values === undefined) {
        return this._pool.query(text);
      }
      return this._pool.query(text, values);
    }

    return this._pool.query({
      text,
      values,
      query_timeout: this._queryTimeoutMs,
    });
  }

  async _loadSnapshot() {
    if (this._snapshotLoadPromise) {
      return this._snapshotLoadPromise;
    }

    this._snapshotLoadPromise = this._readSnapshotWithRetry()
      .then(async (snapshot) => {
        this._cachedState = snapshot;
        await this._persistSnapshotCache(snapshot);
        return snapshot;
      })
      .finally(() => {
        this._snapshotLoadPromise = null;
      });

    return this._snapshotLoadPromise;
  }

  async _readSnapshotWithRetry() {
    let lastError = null;
    const attempts = Math.max(1, this._readRetryCount + 1);
    for (let attempt = 0; attempt < attempts; attempt += 1) {
      try {
        return await this._readSnapshotFromDatabase();
      } catch (error) {
        lastError = error;
        if (!this._isRetriableReadError(error) || attempt >= attempts - 1) {
          break;
        }
        if (this._readRetryDelayMs > 0) {
          await new Promise((resolve) => setTimeout(resolve, this._readRetryDelayMs));
        }
      }
    }
    throw lastError;
  }

  async _readSnapshotFromDatabase() {
    const queryText = `SELECT data FROM ${this._qualifiedTableName} WHERE id = $1`;
    const queryValues = [this._rowId];

    if (typeof this._pool.connect !== "function") {
      const result = await this._pool.query(queryText, queryValues);
      const rawData = result.rows[0]?.data ?? EMPTY_DB;
      return normalizeDbState(rawData);
    }

    const client = await this._pool.connect();
    try {
      if (this._readQueryTimeoutMs > 0) {
        await client.query("BEGIN");
        await client.query(
          `SET LOCAL statement_timeout = ${this._readQueryTimeoutMs}`,
        );
      }
      const result = await client.query({
        text: queryText,
        values: queryValues,
        query_timeout: this._readQueryTimeoutMs > 0
          ? this._readQueryTimeoutMs
          : undefined,
      });
      if (this._readQueryTimeoutMs > 0) {
        await client.query("COMMIT");
      }
      const rawData = result.rows[0]?.data ?? EMPTY_DB;
      return normalizeDbState(rawData);
    } catch (error) {
      if (this._readQueryTimeoutMs > 0) {
        try {
          await client.query("ROLLBACK");
        } catch (_) {
          // Ignore rollback failures after read timeout.
        }
      }
      throw error;
    } finally {
      client.release();
    }
  }

  _isRetriableReadError(error) {
    const message = String(error?.message || "").toLowerCase();
    const code = String(error?.code || "").trim().toUpperCase();
    return (
      code === "POSTGRES_WRITE_QUEUE_TIMEOUT" ||
      message.includes("query read timeout") ||
      message.includes("statement timeout") ||
      message.includes("write queue timed out") ||
      message.includes("connection timeout") ||
      code === "57014" ||
      code === "ETIMEDOUT"
    );
  }

  _serveCachedSnapshotFallback(error, {phase} = {}) {
    if (!this._cachedState || !this._isRetriableReadError(error)) {
      throw error;
    }

    console.warn(
      "[backend] postgres-store serving cached snapshot",
      JSON.stringify({
        table: `${this._schema}.${this._table}`,
        rowId: this._rowId,
        phase: String(phase || "read"),
        message: String(error?.message || error || "unknown_error"),
      }),
    );
    return structuredClone(this._cachedState);
  }

  async _hydrateCachedStateFromSnapshotCache() {
    if (this._cachedState || !this._snapshotCachePath) {
      return;
    }
    if (!this._snapshotCacheHydrationPromise) {
      this._snapshotCacheHydrationPromise = fs.readFile(
        this._snapshotCachePath,
        "utf8",
      )
        .then((rawSnapshot) => {
          const parsedSnapshot = JSON.parse(rawSnapshot);
          this._cachedState = normalizeDbState(parsedSnapshot);
        })
        .catch((error) => {
          if (error?.code === "ENOENT") {
            return;
          }
          console.warn(
            "[backend] postgres-store snapshot cache hydrate failed",
            JSON.stringify({
              table: `${this._schema}.${this._table}`,
              rowId: this._rowId,
              path: this._snapshotCachePath,
              message: String(error?.message || error || "unknown_error"),
            }),
          );
        })
        .finally(() => {
          this._snapshotCacheHydrationPromise = null;
        });
    }
    await this._snapshotCacheHydrationPromise;
  }

  async _persistSnapshotCache(snapshot) {
    if (!this._snapshotCachePath || !snapshot) {
      return;
    }
    try {
      await fs.mkdir(path.dirname(this._snapshotCachePath), {recursive: true});
      await fs.writeFile(
        this._snapshotCachePath,
        JSON.stringify(snapshot),
        "utf8",
      );
    } catch (error) {
      console.warn(
        "[backend] postgres-store snapshot cache persist failed",
        JSON.stringify({
          table: `${this._schema}.${this._table}`,
          rowId: this._rowId,
          path: this._snapshotCachePath,
          message: String(error?.message || error || "unknown_error"),
        }),
      );
    }
  }

  async _awaitWriteQueue() {
    const pendingWrite = this._writeQueue.catch(() => {});
    if (this._writeQueueTimeoutMs <= 0) {
      await pendingWrite;
      return;
    }

    let timer = null;
    try {
      await Promise.race([
        pendingWrite,
        new Promise((_, reject) => {
          timer = setTimeout(() => {
            const error = new Error("Postgres write queue timed out");
            error.code = "POSTGRES_WRITE_QUEUE_TIMEOUT";
            reject(error);
          }, this._writeQueueTimeoutMs);
          if (typeof timer?.unref === "function") {
            timer.unref();
          }
        }),
      ]);
    } finally {
      if (timer) {
        clearTimeout(timer);
      }
    }
  }

  async close() {
    await this._writeQueue;
    if (this._ownsPool) {
      await this._pool.end();
    }
  }
}

module.exports = {
  PostgresStore,
};
