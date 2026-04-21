const {Pool} = require("pg");

const {FileStore, EMPTY_DB, normalizeDbState} = require("./store");

const DEFAULT_POSTGRES_CONNECTION_TIMEOUT_MS = 5_000;
const DEFAULT_POSTGRES_QUERY_TIMEOUT_MS = 15_000;
const DEFAULT_POSTGRES_IDLE_TIMEOUT_MS = 30_000;
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
    idleTimeoutMillis = DEFAULT_POSTGRES_IDLE_TIMEOUT_MS,
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
        query_timeout: queryTimeoutMs,
        statement_timeout: queryTimeoutMs,
        keepAlive: true,
      });
    this._ownsPool = pool == null;
    this._schema = String(schema || "public").trim() || "public";
    this._table = String(table || "rodnya_state").trim() || "rodnya_state";
    this._rowId = String(rowId || "default").trim() || "default";
    this._qualifiedTableName = `${quoteIdentifier(this._schema)}.${quoteIdentifier(this._table)}`;
    this._initializePromise = null;
    this.storageMode = "postgres";
    this.storageTarget = `${this._schema}.${this._table}:${this._rowId}`;
    this._writeQueueTimeoutMs = queryTimeoutMs > 0
      ? Math.max(queryTimeoutMs, DEFAULT_WRITE_QUEUE_TIMEOUT_MS)
      : DEFAULT_WRITE_QUEUE_TIMEOUT_MS;
  }

  async initialize() {
    if (!this._initializePromise) {
      this._initializePromise = this._bootstrap();
    }
    await this._initializePromise;
  }

  async healthCheck() {
    await this.initialize();
    await this._pool.query("SELECT 1");
  }

  async _bootstrap() {
    await this._pool.query(
      `CREATE SCHEMA IF NOT EXISTS ${quoteIdentifier(this._schema)}`,
    );

    await this._pool.query(`
      CREATE TABLE IF NOT EXISTS ${this._qualifiedTableName} (
        id TEXT PRIMARY KEY,
        data JSONB NOT NULL,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
    await this._pool.query(
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
    await this._awaitWriteQueue();

    const result = await this._pool.query(
      `SELECT data FROM ${this._qualifiedTableName} WHERE id = $1`,
      [this._rowId],
    );
    const rawData = result.rows[0]?.data ?? EMPTY_DB;
    return normalizeDbState(rawData);
  }

  async _write(data) {
    const previousQueue = this._writeQueue.catch(() => {});
    const nextWrite = previousQueue.then(async () => {
      await this.initialize();
      await this._pool.query(
        `
          INSERT INTO ${this._qualifiedTableName} (id, data, updated_at)
          VALUES ($1, $2::jsonb, NOW())
          ON CONFLICT (id) DO UPDATE
          SET data = EXCLUDED.data,
              updated_at = NOW()
        `,
        [this._rowId, JSON.stringify(data)],
      );
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
