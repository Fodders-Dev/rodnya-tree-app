const {Pool} = require("pg");

const {FileStore, EMPTY_DB, normalizeDbState} = require("./store");

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
    table = "lineage_state",
    rowId = "default",
    pool = null,
  }) {
    super(`postgres://${schema}.${table}/${rowId}`);

    if (!pool && !String(connectionString || "").trim()) {
      throw new Error(
        "LINEAGE_POSTGRES_URL is required when LINEAGE_BACKEND_STORAGE=postgres",
      );
    }

    this._pool = pool ?? new Pool({connectionString});
    this._ownsPool = pool == null;
    this._schema = String(schema || "public").trim() || "public";
    this._table = String(table || "lineage_state").trim() || "lineage_state";
    this._rowId = String(rowId || "default").trim() || "default";
    this._qualifiedTableName = `${quoteIdentifier(this._schema)}.${quoteIdentifier(this._table)}`;
    this._initializePromise = null;
    this.storageMode = "postgres";
    this.storageTarget = `${this._schema}.${this._table}:${this._rowId}`;
  }

  async initialize() {
    if (!this._initializePromise) {
      this._initializePromise = this._bootstrap();
    }
    await this._initializePromise;
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
    await this._writeQueue;

    const result = await this._pool.query(
      `SELECT data FROM ${this._qualifiedTableName} WHERE id = $1`,
      [this._rowId],
    );
    const rawData = result.rows[0]?.data ?? EMPTY_DB;
    return normalizeDbState(rawData);
  }

  async _write(data) {
    this._writeQueue = this._writeQueue.then(async () => {
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

    return this._writeQueue;
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
