const crypto = require("node:crypto");
const {Pool} = require("pg");

const {
  FileStore,
  EMPTY_DB,
  cloneUserWithAuthState,
  normalizeDbState,
  nowIso,
  SESSION_TOUCH_MIN_INTERVAL_MS,
  verifyPassword,
} = require("./store");

const DEFAULT_POSTGRES_CONNECTION_TIMEOUT_MS = 5_000;
const DEFAULT_POSTGRES_QUERY_TIMEOUT_MS = 15_000;
const DEFAULT_POSTGRES_IDLE_TIMEOUT_MS = 30_000;
const DEFAULT_WRITE_QUEUE_TIMEOUT_MS = 15_000;
const DEFAULT_POSTGRES_POOL_MAX = 8;
const DEFAULT_POSTGRES_APPLICATION_NAME = "rodnya_backend";
const SHARED_POOL_REGISTRY = new Map();

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
        query_timeout: queryTimeoutMs,
        statement_timeout: queryTimeoutMs,
        keepAlive: true,
        max: poolMax,
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

class PostgresStore extends FileStore {
  constructor({
    connectionString,
    schema = "public",
    table = "rodnya_state",
    rowId = "default",
    pool = null,
    poolFactory = (options) => new Pool(options),
    connectionTimeoutMillis = DEFAULT_POSTGRES_CONNECTION_TIMEOUT_MS,
    queryTimeoutMs = DEFAULT_POSTGRES_QUERY_TIMEOUT_MS,
    idleTimeoutMillis = DEFAULT_POSTGRES_IDLE_TIMEOUT_MS,
    poolMax = DEFAULT_POSTGRES_POOL_MAX,
    applicationName = DEFAULT_POSTGRES_APPLICATION_NAME,
  }) {
    super(`postgres://${schema}.${table}/${rowId}`);

    if (!pool && !String(connectionString || "").trim()) {
      throw new Error(
        "RODNYA_POSTGRES_URL is required when RODNYA_BACKEND_STORAGE=postgres",
      );
    }

    this._poolRelease = null;
    if (pool) {
      this._pool = pool;
      this._ownsPool = false;
    } else {
      const sharedPool = acquireSharedPool({
        connectionString,
        connectionTimeoutMillis,
        queryTimeoutMs,
        idleTimeoutMillis,
        poolMax,
        applicationName,
        poolFactory,
      });
      this._pool = sharedPool.pool;
      this._poolRelease = sharedPool.release;
      this._ownsPool = false;
    }
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

  async _selectUserBySql(sql, params) {
    await this.initialize();
    await this._awaitWriteQueue();
    const result = await this._pool.query(sql, params);
    return result.rows[0]?.user_data ?? null;
  }

  async _selectSessionBySql(sql, params) {
    await this.initialize();
    await this._awaitWriteQueue();
    const result = await this._pool.query(sql, params);
    return result.rows[0]?.session_data ?? null;
  }

  async _selectSessionsArray() {
    const result = await this._pool.query(
      `SELECT COALESCE(data->'sessions', '[]'::jsonb) AS sessions
         FROM ${this._qualifiedTableName}
        WHERE id = $1`,
      [this._rowId],
    );
    return Array.isArray(result.rows[0]?.sessions) ? result.rows[0].sessions : [];
  }

  async _updateSessionsArray(sessions) {
    await this._pool.query(
      `UPDATE ${this._qualifiedTableName}
          SET data = jsonb_set(data, '{sessions}', $2::jsonb, true),
              updated_at = NOW()
        WHERE id = $1`,
      [this._rowId, JSON.stringify(Array.isArray(sessions) ? sessions : [])],
    );
  }

  async authenticate(email, password) {
    const normalizedEmail = String(email || "").trim().toLowerCase();
    if (!normalizedEmail) {
      return null;
    }
    const user = await this._selectUserBySql(
      `SELECT user_entry AS user_data
         FROM ${this._qualifiedTableName} AS state_row,
              LATERAL jsonb_array_elements(COALESCE(state_row.data->'users', '[]'::jsonb)) AS user_entry
        WHERE state_row.id = $1
          AND lower(COALESCE(user_entry->>'email', '')) = $2
        LIMIT 1`,
      [this._rowId, normalizedEmail],
    );

    if (!user || !verifyPassword(password, user)) {
      return null;
    }

    this._rememberUser(user);
    return cloneUserWithAuthState(user);
  }

  async findUserById(userId) {
    const normalizedUserId = String(userId || "").trim();
    if (!normalizedUserId) {
      return null;
    }
    const cachedUser = this._userCache.get(normalizedUserId);
    if (cachedUser) {
      return cloneUserWithAuthState(cachedUser);
    }

    const user = await this._selectUserBySql(
      `SELECT user_entry AS user_data
         FROM ${this._qualifiedTableName} AS state_row,
              LATERAL jsonb_array_elements(COALESCE(state_row.data->'users', '[]'::jsonb)) AS user_entry
        WHERE state_row.id = $1
          AND COALESCE(user_entry->>'id', '') = $2
        LIMIT 1`,
      [this._rowId, normalizedUserId],
    );
    if (user) {
      this._rememberUser(user);
    }
    return user ? cloneUserWithAuthState(user) : null;
  }

  async findUserByEmail(email) {
    const normalizedEmail = String(email || "").trim().toLowerCase();
    if (!normalizedEmail) {
      return null;
    }

    const user = await this._selectUserBySql(
      `SELECT user_entry AS user_data
         FROM ${this._qualifiedTableName} AS state_row,
              LATERAL jsonb_array_elements(COALESCE(state_row.data->'users', '[]'::jsonb)) AS user_entry
        WHERE state_row.id = $1
          AND lower(COALESCE(user_entry->>'email', '')) = $2
        LIMIT 1`,
      [this._rowId, normalizedEmail],
    );
    if (user) {
      this._rememberUser(user);
    }
    return user ? cloneUserWithAuthState(user) : null;
  }

  async createSession(userId) {
    const createdAt = nowIso();
    const token = crypto.randomBytes(32).toString("hex");
    const refreshToken = crypto.randomBytes(32).toString("hex");

    const previousQueue = this._writeQueue.catch(() => {});
    const nextWrite = previousQueue.then(async () => {
      await this.initialize();
      const sessions = await this._selectSessionsArray();
      const userSessions = sessions.filter((entry) => entry.userId === userId);
      const otherSessions = sessions.filter((entry) => entry.userId !== userId);
      const sessionsToKeep = userSessions.slice(-4);
      const evictedSessions = userSessions.slice(
        0,
        Math.max(0, userSessions.length - sessionsToKeep.length),
      );
      const createdSession = {
        token,
        refreshToken,
        userId,
        createdAt,
        lastSeenAt: createdAt,
      };
      const nextSessions = [
        ...otherSessions,
        ...sessionsToKeep,
        createdSession,
      ];
      await this._updateSessionsArray(nextSessions);
      return {createdSession, evictedSessions};
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

    const {createdSession, evictedSessions} = await nextWrite;
    for (const session of evictedSessions) {
      this._forgetSession(session?.token);
    }
    this._rememberSession(createdSession);
    return {token, refreshToken};
  }

  async findSession(token) {
    const normalizedToken = String(token || "").trim();
    if (!normalizedToken) {
      return null;
    }
    const cachedSession = this._sessionCache.get(normalizedToken);
    if (cachedSession) {
      return structuredClone(cachedSession);
    }

    const session = await this._selectSessionBySql(
      `SELECT session_entry AS session_data
         FROM ${this._qualifiedTableName} AS state_row,
              LATERAL jsonb_array_elements(COALESCE(state_row.data->'sessions', '[]'::jsonb)) AS session_entry
        WHERE state_row.id = $1
          AND COALESCE(session_entry->>'token', '') = $2
        LIMIT 1`,
      [this._rowId, normalizedToken],
    );
    if (session) {
      this._rememberSession(session);
    }
    return session ? structuredClone(session) : null;
  }

  async findSessionByRefreshToken(refreshToken) {
    const normalizedRefreshToken = String(refreshToken || "").trim();
    if (!normalizedRefreshToken) {
      return null;
    }

    const session = await this._selectSessionBySql(
      `SELECT session_entry AS session_data
         FROM ${this._qualifiedTableName} AS state_row,
              LATERAL jsonb_array_elements(COALESCE(state_row.data->'sessions', '[]'::jsonb)) AS session_entry
        WHERE state_row.id = $1
          AND COALESCE(session_entry->>'refreshToken', '') = $2
        LIMIT 1`,
      [this._rowId, normalizedRefreshToken],
    );
    if (session) {
      this._rememberSession(session);
    }
    return session ? structuredClone(session) : null;
  }

  async touchSession(token) {
    const normalizedToken = String(token || "").trim();
    if (!normalizedToken) {
      return null;
    }

    const nowMs = Date.now();
    const cachedTouchedAt = this._sessionTouchCache.get(normalizedToken);
    if (
      Number.isFinite(cachedTouchedAt) &&
      nowMs - cachedTouchedAt < SESSION_TOUCH_MIN_INTERVAL_MS
    ) {
      return null;
    }

    this._sessionTouchCache.set(normalizedToken, nowMs);
    const previousQueue = this._writeQueue.catch(() => {});
    const nextWrite = previousQueue.then(async () => {
      await this.initialize();
      const sessions = await this._selectSessionsArray();
      const sessionIndex = sessions.findIndex(
        (entry) => entry.token === normalizedToken,
      );
      if (sessionIndex < 0) {
        this._forgetSession(normalizedToken);
        return null;
      }

      const session = structuredClone(sessions[sessionIndex]);
      const lastSeenAtMs = new Date(session.lastSeenAt || 0).getTime();
      if (
        Number.isFinite(lastSeenAtMs) &&
        nowMs - lastSeenAtMs < SESSION_TOUCH_MIN_INTERVAL_MS
      ) {
        this._sessionTouchCache.set(normalizedToken, lastSeenAtMs);
        this._rememberSession(session);
        return session;
      }

      session.lastSeenAt = nowIso();
      sessions[sessionIndex] = session;
      await this._updateSessionsArray(sessions);
      return session;
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

    const touchedSession = await nextWrite;
    if (!touchedSession) {
      return null;
    }
    this._rememberSession(touchedSession);
    return structuredClone(touchedSession);
  }

  async deleteSession(token) {
    const normalizedToken = String(token || "").trim();
    if (!normalizedToken) {
      return;
    }

    const previousQueue = this._writeQueue.catch(() => {});
    const nextWrite = previousQueue.then(async () => {
      await this.initialize();
      const sessions = await this._selectSessionsArray();
      const nextSessions = sessions.filter(
        (entry) => entry.token !== normalizedToken,
      );
      if (nextSessions.length === sessions.length) {
        return;
      }
      await this._updateSessionsArray(nextSessions);
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

    this._forgetSession(normalizedToken);
    await nextWrite;
  }

  async deleteSessionsForUser(userId) {
    const normalizedUserId = String(userId || "").trim();
    if (!normalizedUserId) {
      return;
    }

    const previousQueue = this._writeQueue.catch(() => {});
    const nextWrite = previousQueue.then(async () => {
      await this.initialize();
      const sessions = await this._selectSessionsArray();
      const deletedTokens = sessions
        .filter((entry) => entry.userId === normalizedUserId)
        .map((entry) => entry.token);
      const nextSessions = sessions.filter(
        (entry) => entry.userId !== normalizedUserId,
      );
      if (nextSessions.length !== sessions.length) {
        await this._updateSessionsArray(nextSessions);
      }
      return deletedTokens;
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

    const deletedTokens = (await nextWrite) || [];
    for (const token of deletedTokens) {
      this._forgetSession(token);
    }
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
    if (this._poolRelease) {
      await this._poolRelease();
      this._poolRelease = null;
      return;
    }
    if (this._ownsPool) {
      await this._pool.end();
    }
  }
}

module.exports = {
  PostgresStore,
};
