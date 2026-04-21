const crypto = require("node:crypto");
const {Pool} = require("pg");

const {
  FileStore,
  EMPTY_DB,
  buildPersonRecord,
  cloneUserWithAuthState,
  createTreeChangeRecord,
  describeMessagePreview,
  normalizeDbState,
  normalizeParticipantIds,
  normalizeStoredCall,
  nowIso,
  parseDirectParticipantsFromChatId,
  SESSION_TOUCH_MIN_INTERVAL_MS,
  verifyPassword,
} = require("./store");

const DEFAULT_POSTGRES_CONNECTION_TIMEOUT_MS = 5_000;
const DEFAULT_POSTGRES_QUERY_TIMEOUT_MS = 15_000;
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
    this._authUsersTable = `${this._table}_auth_users`;
    this._authSessionsTable = `${this._table}_auth_sessions`;
    this._qualifiedAuthUsersTableName = `${quoteIdentifier(this._schema)}.${quoteIdentifier(this._authUsersTable)}`;
    this._qualifiedAuthSessionsTableName = `${quoteIdentifier(this._schema)}.${quoteIdentifier(this._authSessionsTable)}`;
    this._initializePromise = null;
    this.storageMode = "postgres";
    this.storageTarget = `${this._schema}.${this._table}:${this._rowId}`;
    this._writeQueueTimeoutMs = queryTimeoutMs > 0
      ? Math.max(queryTimeoutMs, DEFAULT_WRITE_QUEUE_TIMEOUT_MS)
      : DEFAULT_WRITE_QUEUE_TIMEOUT_MS;
    this._lastUsersProjectionHash = null;
    this._lastSessionsProjectionHash = null;
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
    await this._pool.query(`
      CREATE TABLE IF NOT EXISTS ${this._qualifiedAuthUsersTableName} (
        id TEXT PRIMARY KEY,
        email TEXT,
        user_data JSONB NOT NULL
      )
    `);
    await this._pool.query(`
      CREATE INDEX IF NOT EXISTS ${quoteIdentifier(`${this._authUsersTable}_email_idx`)}
        ON ${this._qualifiedAuthUsersTableName} (email)
    `);
    await this._pool.query(`
      CREATE TABLE IF NOT EXISTS ${this._qualifiedAuthSessionsTableName} (
        token TEXT PRIMARY KEY,
        refresh_token TEXT,
        user_id TEXT NOT NULL,
        created_at TEXT,
        session_data JSONB NOT NULL
      )
    `);
    await this._pool.query(`
      CREATE INDEX IF NOT EXISTS ${quoteIdentifier(`${this._authSessionsTable}_refresh_idx`)}
        ON ${this._qualifiedAuthSessionsTableName} (refresh_token)
    `);
    await this._pool.query(`
      CREATE INDEX IF NOT EXISTS ${quoteIdentifier(`${this._authSessionsTable}_user_idx`)}
        ON ${this._qualifiedAuthSessionsTableName} (user_id)
    `);
    await this._hydrateAuthProjectionTablesFromStateRow();
  }

  async _withProjectionClient(work) {
    if (typeof this._pool.connect !== "function") {
      return work(this._pool, false);
    }

    const client = await this._pool.connect();
    try {
      return await work(client, true);
    } finally {
      client.release();
    }
  }

  async _hydrateAuthProjectionTablesFromStateRow() {
    await this._withProjectionClient(async (client, useTransaction) => {
      try {
        if (useTransaction) {
          await client.query("BEGIN");
          await client.query("SET LOCAL statement_timeout = 0");
        }
        await client.query(`DELETE FROM ${this._qualifiedAuthUsersTableName}`);
        await client.query(
          `INSERT INTO ${this._qualifiedAuthUsersTableName} (id, email, user_data)
           SELECT
             user_entry->>'id',
             NULLIF(lower(COALESCE(user_entry->>'email', '')), ''),
             user_entry
             FROM ${this._qualifiedTableName},
                  LATERAL jsonb_array_elements(COALESCE(data->'users', '[]'::jsonb)) AS user_entry
            WHERE id = $1
              AND COALESCE(user_entry->>'id', '') <> ''`,
          [this._rowId],
        );
        await client.query(`DELETE FROM ${this._qualifiedAuthSessionsTableName}`);
        await client.query(
          `INSERT INTO ${this._qualifiedAuthSessionsTableName} (
             token,
             refresh_token,
             user_id,
             created_at,
             session_data
           )
           SELECT
             session_entry->>'token',
             NULLIF(COALESCE(session_entry->>'refreshToken', ''), ''),
             COALESCE(session_entry->>'userId', ''),
             NULLIF(COALESCE(session_entry->>'createdAt', ''), ''),
             session_entry
             FROM ${this._qualifiedTableName},
                  LATERAL jsonb_array_elements(COALESCE(data->'sessions', '[]'::jsonb)) AS session_entry
            WHERE id = $1
              AND COALESCE(session_entry->>'token', '') <> ''`,
          [this._rowId],
        );
        if (useTransaction) {
          await client.query("COMMIT");
        }
      } catch (error) {
        if (isProjectionHydrationFallbackError(error)) {
          if (useTransaction) {
            try {
              await client.query("ROLLBACK");
            } catch (_) {
              // ignore rollback failures for fallback path
            }
          }
          const result = await this._pool.query(
            `SELECT data FROM ${this._qualifiedTableName} WHERE id = $1`,
            [this._rowId],
          );
          const rawData = result.rows[0]?.data ?? EMPTY_DB;
          await this._replaceProjectedUsers(rawData.users);
          await this._replaceProjectedSessions(rawData.sessions);
          return;
        }
        if (useTransaction) {
          try {
            await client.query("ROLLBACK");
          } catch (_) {
            // ignore rollback failures, the original error is more useful
          }
        }
        throw error;
      }
    });
  }

  async _replaceProjectedUsers(users) {
    const normalizedUsers = Array.isArray(users) ? users : [];
    await this._pool.query(`DELETE FROM ${this._qualifiedAuthUsersTableName}`);
    try {
      await this._pool.query(
        `INSERT INTO ${this._qualifiedAuthUsersTableName} (id, email, user_data)
         SELECT
           user_entry->>'id',
           NULLIF(lower(COALESCE(user_entry->>'email', '')), ''),
           user_entry
           FROM jsonb_array_elements($1::jsonb) AS user_entry
          WHERE COALESCE(user_entry->>'id', '') <> ''`,
        [JSON.stringify(normalizedUsers)],
      );
    } catch (error) {
      if (!isProjectionArrayInsertFallbackError(error)) {
        throw error;
      }
      for (const user of normalizedUsers) {
        const userId = String(user?.id || "").trim();
        if (!userId) {
          continue;
        }
        const email = String(user?.email || "").trim().toLowerCase() || null;
        await this._pool.query(
          `INSERT INTO ${this._qualifiedAuthUsersTableName} (id, email, user_data)
           VALUES ($1, $2, $3::jsonb)`,
          [userId, email, JSON.stringify(user)],
        );
      }
    }
    this._lastUsersProjectionHash = computeProjectionHash(normalizedUsers);
  }

  async _replaceProjectedSessions(sessions) {
    const normalizedSessions = Array.isArray(sessions) ? sessions : [];
    await this._pool.query(`DELETE FROM ${this._qualifiedAuthSessionsTableName}`);
    try {
      await this._pool.query(
        `INSERT INTO ${this._qualifiedAuthSessionsTableName} (
           token,
           refresh_token,
           user_id,
           created_at,
           session_data
         )
         SELECT
           session_entry->>'token',
           NULLIF(COALESCE(session_entry->>'refreshToken', ''), ''),
           COALESCE(session_entry->>'userId', ''),
           NULLIF(COALESCE(session_entry->>'createdAt', ''), ''),
           session_entry
           FROM jsonb_array_elements($1::jsonb) AS session_entry
          WHERE COALESCE(session_entry->>'token', '') <> ''`,
        [JSON.stringify(normalizedSessions)],
      );
    } catch (error) {
      if (!isProjectionArrayInsertFallbackError(error)) {
        throw error;
      }
      for (const session of normalizedSessions) {
        const token = String(session?.token || "").trim();
        if (!token) {
          continue;
        }
        await this._pool.query(
          `INSERT INTO ${this._qualifiedAuthSessionsTableName} (
             token,
             refresh_token,
             user_id,
             created_at,
             session_data
           )
           VALUES ($1, $2, $3, $4, $5::jsonb)`,
          [
            token,
            String(session?.refreshToken || "").trim() || null,
            String(session?.userId || "").trim(),
            String(session?.createdAt || "").trim() || null,
            JSON.stringify(session),
          ],
        );
      }
    }
    this._lastSessionsProjectionHash = computeProjectionHash(normalizedSessions);
  }

  async _syncSessionsPathFromProjection() {
    await this._pool.query(
      `UPDATE ${this._qualifiedTableName}
          SET data = jsonb_set(
                data,
                '{sessions}',
                COALESCE(
                  (
                    SELECT jsonb_agg(session_data ORDER BY created_at NULLS FIRST, token)
                      FROM ${this._qualifiedAuthSessionsTableName}
                  ),
                  '[]'::jsonb
                ),
                true
              ),
              updated_at = NOW()
        WHERE id = $1`,
      [this._rowId],
    );
  }

  async _awaitReadConsistency() {
    try {
      await this._awaitWriteQueue();
    } catch (error) {
      if (error?.code !== "POSTGRES_WRITE_QUEUE_TIMEOUT") {
        throw error;
      }
      console.warn(
        "[backend] postgres-store continuing read while write queue is busy",
        JSON.stringify({
          table: `${this._schema}.${this._table}`,
          rowId: this._rowId,
          writeQueueTimeoutMs: this._writeQueueTimeoutMs,
        }),
      );
    }
  }

  async _selectProjectedSessionsForUser(userId) {
    const normalizedUserId = String(userId || "").trim();
    if (!normalizedUserId) {
      return [];
    }
    const result = await this._pool.query(
      `SELECT session_data
         FROM ${this._qualifiedAuthSessionsTableName}
        WHERE user_id = $1
        ORDER BY created_at NULLS FIRST, token`,
      [normalizedUserId],
    );
    return result.rows.map((row) => row.session_data).filter(Boolean);
  }

  async _upsertProjectedSession(session) {
    const token = String(session?.token || "").trim();
    if (!token) {
      return;
    }
    await this._pool.query(
      `INSERT INTO ${this._qualifiedAuthSessionsTableName} (
         token,
         refresh_token,
         user_id,
         created_at,
         session_data
       )
       VALUES ($1, $2, $3, $4, $5::jsonb)
       ON CONFLICT (token) DO UPDATE
       SET refresh_token = EXCLUDED.refresh_token,
           user_id = EXCLUDED.user_id,
           created_at = EXCLUDED.created_at,
           session_data = EXCLUDED.session_data`,
      [
        token,
        String(session?.refreshToken || "").trim() || null,
        String(session?.userId || "").trim(),
        String(session?.createdAt || "").trim() || null,
        JSON.stringify(session),
      ],
    );
  }

  async _selectSessionsArray() {
    await this.initialize();
    await this._awaitReadConsistency();
    return this._selectProjectedSessionsArray();
  }

  async _selectProjectedSessionsArray() {
    const result = await this._pool.query(
      `SELECT session_data
         FROM ${this._qualifiedAuthSessionsTableName}
        ORDER BY created_at NULLS FIRST, token`,
    );
    return result.rows.map((row) => row.session_data).filter(Boolean);
  }

  async _updateSessionsArray(sessions) {
    await this._replaceProjectedSessions(sessions);
  }

  async authenticate(email, password) {
    const normalizedEmail = String(email || "").trim().toLowerCase();
    if (!normalizedEmail) {
      return null;
    }
    await this.initialize();
    await this._awaitReadConsistency();
    const result = await this._pool.query(
      `SELECT user_data
         FROM ${this._qualifiedAuthUsersTableName}
        WHERE email = $1
        LIMIT 1`,
      [normalizedEmail],
    );
    const user = result.rows[0]?.user_data ?? null;

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

    await this.initialize();
    await this._awaitReadConsistency();
    const result = await this._pool.query(
      `SELECT user_data
         FROM ${this._qualifiedAuthUsersTableName}
        WHERE id = $1
        LIMIT 1`,
      [normalizedUserId],
    );
    const user = result.rows[0]?.user_data ?? null;
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

    await this.initialize();
    await this._awaitReadConsistency();
    const result = await this._pool.query(
      `SELECT user_data
         FROM ${this._qualifiedAuthUsersTableName}
        WHERE email = $1
        LIMIT 1`,
      [normalizedEmail],
    );
    const user = result.rows[0]?.user_data ?? null;
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
      const userSessions = await this._selectProjectedSessionsForUser(userId);
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
      for (const session of evictedSessions) {
        const sessionToken = String(session?.token || "").trim();
        if (!sessionToken) {
          continue;
        }
        await this._pool.query(
          `DELETE FROM ${this._qualifiedAuthSessionsTableName} WHERE token = $1`,
          [sessionToken],
        );
      }
      await this._upsertProjectedSession(createdSession);
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

    await this.initialize();
    await this._awaitReadConsistency();
    const result = await this._pool.query(
      `SELECT session_data
         FROM ${this._qualifiedAuthSessionsTableName}
        WHERE token = $1
        LIMIT 1`,
      [normalizedToken],
    );
    const session = result.rows[0]?.session_data ?? null;
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

    await this.initialize();
    await this._awaitReadConsistency();
    const result = await this._pool.query(
      `SELECT session_data
         FROM ${this._qualifiedAuthSessionsTableName}
        WHERE refresh_token = $1
        LIMIT 1`,
      [normalizedRefreshToken],
    );
    const session = result.rows[0]?.session_data ?? null;
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
      const result = await this._pool.query(
        `SELECT session_data
           FROM ${this._qualifiedAuthSessionsTableName}
          WHERE token = $1
          LIMIT 1`,
        [normalizedToken],
      );
      const storedSession = result.rows[0]?.session_data ?? null;
      if (!storedSession) {
        this._forgetSession(normalizedToken);
        return null;
      }

      const session = structuredClone(storedSession);
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
      await this._upsertProjectedSession(session);
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
      await this._pool.query(
        `DELETE FROM ${this._qualifiedAuthSessionsTableName} WHERE token = $1`,
        [normalizedToken],
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
      const result = await this._pool.query(
        `SELECT token
           FROM ${this._qualifiedAuthSessionsTableName}
          WHERE user_id = $1`,
        [normalizedUserId],
      );
      const deletedTokens = result.rows
        .map((row) => String(row?.token || "").trim())
        .filter(Boolean);
      if (deletedTokens.length > 0) {
        await this._pool.query(
          `DELETE FROM ${this._qualifiedAuthSessionsTableName} WHERE user_id = $1`,
          [normalizedUserId],
        );
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

  async createPerson({
    treeId,
    creatorId,
    personData,
    userId = null,
  }) {
    if (userId) {
      return super.createPerson({
        treeId,
        creatorId,
        personData,
        userId,
      });
    }

    const normalizedTreeId = String(treeId || "").trim();
    if (!normalizedTreeId) {
      return null;
    }

    const person = buildPersonRecord({
      treeId: normalizedTreeId,
      creatorId,
      personData,
      userId: null,
      identityId: null,
    });
    const treeUpdatedAt = person.updatedAt || nowIso();
    const changeRecord = createTreeChangeRecord({
      treeId: normalizedTreeId,
      actorId: creatorId,
      type: "person.created",
      personId: person.id,
      details: {
        after: structuredClone(person),
      },
    });

    const previousQueue = this._writeQueue.catch(() => {});
    const nextWrite = previousQueue.then(async () => {
      await this.initialize();
      const result = await this._pool.query(
        `UPDATE ${this._qualifiedTableName}
            SET data = jsonb_set(
                  jsonb_set(
                    jsonb_set(
                      data,
                      '{persons}',
                      COALESCE(data->'persons', '[]'::jsonb) || jsonb_build_array($2::jsonb),
                      true
                    ),
                    '{treeChangeRecords}',
                    COALESCE(data->'treeChangeRecords', '[]'::jsonb) || jsonb_build_array($3::jsonb),
                    true
                  ),
                  '{trees}',
                  COALESCE(
                    (
                      SELECT jsonb_agg(
                        CASE
                          WHEN COALESCE(tree_entry->>'id', '') = $4
                            THEN jsonb_set(tree_entry, '{updatedAt}', to_jsonb($5::text), true)
                          ELSE tree_entry
                        END
                      )
                        FROM jsonb_array_elements(COALESCE(data->'trees', '[]'::jsonb)) AS tree_entry
                    ),
                    '[]'::jsonb
                  ),
                  true
                ),
                updated_at = NOW()
          WHERE id = $1
            AND EXISTS (
              SELECT 1
                FROM jsonb_array_elements(COALESCE(data->'trees', '[]'::jsonb)) AS tree_entry
               WHERE COALESCE(tree_entry->>'id', '') = $4
            )
          RETURNING updated_at`,
        [
          this._rowId,
          JSON.stringify(person),
          JSON.stringify(changeRecord),
          normalizedTreeId,
          treeUpdatedAt,
        ],
      );
      if (result.rowCount === 0) {
        return null;
      }
      return structuredClone(person);
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

  async _selectStoredTreeInvitationsForUser(userId) {
    const normalizedUserId = String(userId || "").trim();
    if (!normalizedUserId) {
      return [];
    }
    const result = await this._pool.query(
      `SELECT invitation_entry AS invitation_data
         FROM ${this._qualifiedTableName},
              LATERAL jsonb_array_elements(COALESCE(data->'treeInvitations', '[]'::jsonb)) AS invitation_entry
        WHERE id = $1
          AND COALESCE(invitation_entry->>'userId', '') = $2
          AND COALESCE(invitation_entry->>'role', 'pending') = 'pending'
        ORDER BY COALESCE(invitation_entry->>'addedAt', '') DESC`,
      [this._rowId, normalizedUserId],
    );
    return result.rows.map((row) => row.invitation_data).filter(Boolean);
  }

  async listPendingTreeInvitations(userId) {
    await this.initialize();
    await this._awaitReadConsistency();
    return this._selectStoredTreeInvitationsForUser(userId);
  }

  async _selectStoredNotificationsForUser(userId, {status = null, limit = 50} = {}) {
    const normalizedUserId = String(userId || "").trim();
    if (!normalizedUserId) {
      return [];
    }
    const normalizedLimit = Number.isFinite(Number(limit))
      ? Math.max(0, Math.floor(Number(limit)))
      : 50;
    const normalizedStatus = String(status || "").trim().toLowerCase();
    const result = await this._pool.query(
      `SELECT notification_entry AS notification_data
         FROM ${this._qualifiedTableName},
              LATERAL jsonb_array_elements(COALESCE(data->'notifications', '[]'::jsonb)) AS notification_entry
        WHERE id = $1
          AND COALESCE(notification_entry->>'userId', '') = $2
          AND (
            $3 = ''
            OR ($3 = 'unread' AND COALESCE(notification_entry->>'readAt', '') = '')
            OR ($3 = 'read' AND COALESCE(notification_entry->>'readAt', '') <> '')
          )
        ORDER BY COALESCE(notification_entry->>'createdAt', '') DESC
        LIMIT $4`,
      [this._rowId, normalizedUserId, normalizedStatus, normalizedLimit],
    );
    return result.rows.map((row) => row.notification_data).filter(Boolean);
  }

  async listNotifications(userId, {status = null, limit = 50} = {}) {
    await this.initialize();
    await this._awaitReadConsistency();
    return this._selectStoredNotificationsForUser(userId, {status, limit});
  }

  async countUnreadNotifications(userId) {
    const normalizedUserId = String(userId || "").trim();
    if (!normalizedUserId) {
      return 0;
    }
    await this.initialize();
    await this._awaitReadConsistency();
    const result = await this._pool.query(
      `SELECT COUNT(*)::int AS total
         FROM ${this._qualifiedTableName},
              LATERAL jsonb_array_elements(COALESCE(data->'notifications', '[]'::jsonb)) AS notification_entry
        WHERE id = $1
          AND COALESCE(notification_entry->>'userId', '') = $2
          AND COALESCE(notification_entry->>'readAt', '') = ''`,
      [this._rowId, normalizedUserId],
    );
    return Number(result.rows[0]?.total || 0);
  }

  async _selectStoredChatsForUser(userId) {
    const normalizedUserId = String(userId || "").trim();
    if (!normalizedUserId) {
      return [];
    }
    const result = await this._pool.query(
      `SELECT chat_entry AS chat_data
         FROM ${this._qualifiedTableName},
              LATERAL jsonb_array_elements(COALESCE(data->'chats', '[]'::jsonb)) AS chat_entry
        WHERE id = $1
          AND EXISTS (
            SELECT 1
              FROM jsonb_array_elements_text(COALESCE(chat_entry->'participantIds', '[]'::jsonb)) AS participant_id(value)
             WHERE participant_id.value = $2
          )
        ORDER BY COALESCE(chat_entry->>'updatedAt', '') DESC`,
      [this._rowId, normalizedUserId],
    );
    return result.rows.map((row) => row.chat_data).filter(Boolean);
  }

  async _selectStoredMessagesForUser(userId) {
    const normalizedUserId = String(userId || "").trim();
    if (!normalizedUserId) {
      return [];
    }
    const nowTimestamp = nowIso();
    const result = await this._pool.query(
      `SELECT message_entry AS message_data
         FROM ${this._qualifiedTableName},
              LATERAL jsonb_array_elements(COALESCE(data->'messages', '[]'::jsonb)) AS message_entry
        WHERE id = $1
          AND EXISTS (
            SELECT 1
              FROM jsonb_array_elements_text(COALESCE(message_entry->'participants', '[]'::jsonb)) AS participant_id(value)
             WHERE participant_id.value = $2
          )
          AND (
            COALESCE(message_entry->>'expiresAt', '') = ''
            OR COALESCE(message_entry->>'expiresAt', '') > $3
          )
        ORDER BY COALESCE(message_entry->>'timestamp', '') DESC`,
      [this._rowId, normalizedUserId, nowTimestamp],
    );
    return result.rows.map((row) => row.message_data).filter(Boolean);
  }

  async _selectProjectedUsersByIds(userIds) {
    const normalizedUserIds = Array.from(
      new Set(
        (Array.isArray(userIds) ? userIds : [])
          .map((value) => String(value || "").trim())
          .filter(Boolean),
      ),
    );
    if (normalizedUserIds.length === 0) {
      return new Map();
    }
    const result = await this._pool.query(
      `SELECT id, user_data
         FROM ${this._qualifiedAuthUsersTableName}
        WHERE id = ANY($1::text[])`,
      [normalizedUserIds],
    );
    return new Map(
      result.rows
        .map((row) => [String(row?.id || row?.user_data?.id || "").trim(), row?.user_data])
        .filter(([userId, user]) => userId && user),
    );
  }

  async listChatPreviews(userId) {
    const normalizedUserId = String(userId || "").trim();
    if (!normalizedUserId) {
      return [];
    }
    await this.initialize();
    await this._awaitReadConsistency();
    try {
      const storedChats = await this._selectStoredChatsForUser(normalizedUserId);
      const storedMessages = await this._selectStoredMessagesForUser(normalizedUserId);
      const relatedChats = new Map();
      for (const chat of storedChats) {
        if (chat?.id) {
          relatedChats.set(String(chat.id).trim(), structuredClone(chat));
        }
      }

      const messagesByChatId = new Map();
      for (const message of storedMessages) {
        const rawChatId = String(message?.chatId || "").trim();
        const messageParticipants = normalizeParticipantIds(message?.participants);
        let resolvedChat = rawChatId ? relatedChats.get(rawChatId) || null : null;
        if (!resolvedChat && messageParticipants.length === 2) {
          const canonicalChatId = messageParticipants.join("_");
          resolvedChat = relatedChats.get(canonicalChatId) || {
            id: canonicalChatId,
            type: "direct",
            participantIds: messageParticipants,
            title: null,
            createdBy: messageParticipants[0] || null,
            treeId: null,
            branchRootPersonIds: [],
            createdAt: message?.timestamp || nowIso(),
            updatedAt: message?.timestamp || nowIso(),
          };
          relatedChats.set(canonicalChatId, resolvedChat);
        } else if (!resolvedChat) {
          const parsedDirectParticipants = parseDirectParticipantsFromChatId(rawChatId);
          if (parsedDirectParticipants.length === 2) {
            const canonicalChatId = parsedDirectParticipants.join("_");
            resolvedChat = relatedChats.get(canonicalChatId) || {
              id: canonicalChatId,
              type: "direct",
              participantIds: parsedDirectParticipants,
              title: null,
              createdBy: parsedDirectParticipants[0] || null,
              treeId: null,
              branchRootPersonIds: [],
              createdAt: message?.timestamp || nowIso(),
              updatedAt: message?.timestamp || nowIso(),
            };
            relatedChats.set(canonicalChatId, resolvedChat);
          }
        }
        if (!resolvedChat?.id) {
          continue;
        }
        const resolvedChatId = String(resolvedChat.id).trim();
        const bucket = messagesByChatId.get(resolvedChatId) || [];
        bucket.push(message);
        messagesByChatId.set(resolvedChatId, bucket);
      }

      const participantIds = new Set();
      for (const chat of relatedChats.values()) {
        for (const participantId of normalizeParticipantIds(chat?.participantIds)) {
          if (participantId && participantId !== normalizedUserId) {
            participantIds.add(participantId);
          }
        }
      }
      const usersById = await this._selectProjectedUsersByIds(Array.from(participantIds));
      const previews = [];
      for (const chat of relatedChats.values()) {
        const participants = normalizeParticipantIds(chat?.participantIds);
        const isGroup = chat?.type === "group" || chat?.type === "branch";
        const otherUserId = isGroup
          ? ""
          : participants.find((participantId) => participantId !== normalizedUserId) || "";
        const relevantMessages = (messagesByChatId.get(String(chat?.id || "").trim()) || [])
          .sort((left, right) =>
            String(right?.timestamp || "").localeCompare(String(left?.timestamp || "")),
          );
        const lastMessage = relevantMessages[0] || null;
        const preview = {
          chatId: String(chat?.id || "").trim(),
          userId: normalizedUserId,
          type: chat?.type || "direct",
          title: chat?.title || null,
          photoUrl: null,
          participantIds: participants,
          otherUserId,
          otherUserName: "Пользователь",
          otherUserPhotoUrl: null,
          lastMessage: lastMessage ? describeMessagePreview(lastMessage) : "",
          lastMessageTime:
            lastMessage?.timestamp || chat?.updatedAt || chat?.createdAt || "",
          unreadCount: relevantMessages.filter((message) => {
            return message?.senderId !== normalizedUserId && message?.isRead !== true;
          }).length,
          lastMessageSenderId: lastMessage?.senderId || "",
        };
        if (isGroup) {
          const otherParticipantNames = participants
            .filter((participantId) => participantId !== normalizedUserId)
            .map((participantId) => {
              const user = usersById.get(participantId);
              return user?.profile?.displayName || user?.email || "";
            })
            .filter(Boolean);
          preview.otherUserName =
            chat?.title ||
            (otherParticipantNames.length > 0
              ? otherParticipantNames.slice(0, 3).join(", ")
              : "Групповой чат");
        } else if (otherUserId) {
          const otherUser = usersById.get(otherUserId);
          if (otherUser) {
            preview.otherUserName =
              otherUser.profile?.displayName || otherUser.email || "Пользователь";
            preview.otherUserPhotoUrl = otherUser.profile?.photoUrl || null;
          }
        }
        previews.push(preview);
      }

      return previews
        .sort((left, right) =>
          String(right.lastMessageTime || "").localeCompare(String(left.lastMessageTime || "")),
        )
        .map((preview) => structuredClone(preview));
    } catch (error) {
      if (!isProjectionArrayTextFallbackError(error)) {
        throw error;
      }
      return super.listChatPreviews(normalizedUserId);
    }
  }

  async countUnreadChatMessages(userId) {
    const normalizedUserId = String(userId || "").trim();
    if (!normalizedUserId) {
      return 0;
    }
    await this.initialize();
    await this._awaitReadConsistency();
    try {
      const nowTimestamp = nowIso();
      const result = await this._pool.query(
        `SELECT COUNT(*)::int AS total
           FROM ${this._qualifiedTableName},
                LATERAL jsonb_array_elements(COALESCE(data->'messages', '[]'::jsonb)) AS message_entry
          WHERE id = $1
            AND EXISTS (
              SELECT 1
                FROM jsonb_array_elements_text(COALESCE(message_entry->'participants', '[]'::jsonb)) AS participant_id(value)
               WHERE participant_id.value = $2
            )
            AND COALESCE(message_entry->>'senderId', '') <> $2
            AND COALESCE(message_entry->>'isRead', 'false') <> 'true'
            AND (
              COALESCE(message_entry->>'expiresAt', '') = ''
              OR COALESCE(message_entry->>'expiresAt', '') > $3
            )`,
        [this._rowId, normalizedUserId, nowTimestamp],
      );
      return Number(result.rows[0]?.total || 0);
    } catch (error) {
      if (!isProjectionArrayTextFallbackError(error)) {
        throw error;
      }
      return super.countUnreadChatMessages(normalizedUserId);
    }
  }

  async findActiveCall({userId, chatId = null} = {}) {
    const normalizedUserId = String(userId || "").trim();
    const normalizedChatId = String(chatId || "").trim();
    if (!normalizedUserId) {
      return null;
    }
    await this.initialize();
    await this._awaitReadConsistency();
    try {
      const result = await this._pool.query(
        `SELECT call_entry AS call_data
           FROM ${this._qualifiedTableName},
                LATERAL jsonb_array_elements(COALESCE(data->'calls', '[]'::jsonb)) AS call_entry
          WHERE id = $1
            AND COALESCE(call_entry->>'state', '') IN ('active', 'ringing')
            AND (
              $3 = ''
              OR COALESCE(call_entry->>'chatId', '') = $3
            )
            AND EXISTS (
              SELECT 1
                FROM jsonb_array_elements_text(COALESCE(call_entry->'participantIds', '[]'::jsonb)) AS participant_id(value)
               WHERE participant_id.value = $2
            )
          ORDER BY
            CASE COALESCE(call_entry->>'state', '')
              WHEN 'active' THEN 0
              WHEN 'ringing' THEN 1
              ELSE 99
            END,
            COALESCE(call_entry->>'updatedAt', '') DESC
          LIMIT 1`,
        [this._rowId, normalizedUserId, normalizedChatId],
      );
      const call = normalizeStoredCall(result.rows[0]?.call_data ?? null);
      return call ? structuredClone(call) : null;
    } catch (error) {
      if (!isProjectionArrayTextFallbackError(error)) {
        throw error;
      }
      return super.findActiveCall({userId: normalizedUserId, chatId: normalizedChatId});
    }
  }

  async listUserTrees(userId) {
    const normalizedUserId = String(userId || "").trim();
    if (!normalizedUserId) {
      return [];
    }

    await this.initialize();
    await this._awaitReadConsistency();
    try {
      const result = await this._pool.query(
        `SELECT tree_entry AS tree_data
           FROM ${this._qualifiedTableName},
                LATERAL jsonb_array_elements(COALESCE(data->'trees', '[]'::jsonb)) AS tree_entry
          WHERE id = $1
            AND (
              COALESCE(tree_entry->>'creatorId', '') = $2
              OR EXISTS (
                SELECT 1
                  FROM jsonb_array_elements_text(COALESCE(tree_entry->'memberIds', '[]'::jsonb)) AS member_id(value)
                 WHERE member_id.value = $2
              )
            )
          ORDER BY COALESCE(tree_entry->>'updatedAt', '') DESC`,
        [this._rowId, normalizedUserId],
      );
      return result.rows
        .map((row) => row.tree_data)
        .filter(Boolean)
        .map((tree) => structuredClone(tree));
    } catch (error) {
      if (!isProjectionArrayTextFallbackError(error)) {
        throw error;
      }
      return super.listUserTrees(normalizedUserId);
    }
  }

  async findTree(treeId) {
    const normalizedTreeId = String(treeId || "").trim();
    if (!normalizedTreeId) {
      return null;
    }

    await this.initialize();
    await this._awaitReadConsistency();
    const result = await this._pool.query(
      `SELECT tree_entry AS tree_data
         FROM ${this._qualifiedTableName},
              LATERAL jsonb_array_elements(COALESCE(data->'trees', '[]'::jsonb)) AS tree_entry
        WHERE id = $1
          AND COALESCE(tree_entry->>'id', '') = $2
        LIMIT 1`,
      [this._rowId, normalizedTreeId],
    );
    const tree = result.rows[0]?.tree_data ?? null;
    return tree ? structuredClone(tree) : null;
  }

  async _read() {
    await this.initialize();
    await this._awaitReadConsistency();

    const result = await this._pool.query(
      `SELECT data FROM ${this._qualifiedTableName} WHERE id = $1`,
      [this._rowId],
    );
    const rawData = result.rows[0]?.data ?? EMPTY_DB;
    const normalizedState = normalizeDbState(rawData);
    normalizedState.sessions = await this._selectProjectedSessionsArray();
    this._lastUsersProjectionHash = computeProjectionHash(normalizedState.users);
    this._lastSessionsProjectionHash = computeProjectionHash(normalizedState.sessions);
    return normalizedState;
  }

  async _write(data) {
    const previousQueue = this._writeQueue.catch(() => {});
    const nextWrite = previousQueue.then(async () => {
      await this.initialize();
      const nextUsersHash = computeProjectionHash(data?.users);
      const nextSessionsHash = computeProjectionHash(data?.sessions);
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
      if (this._lastUsersProjectionHash !== nextUsersHash) {
        await this._replaceProjectedUsers(data.users);
      } else {
        this._lastUsersProjectionHash = nextUsersHash;
      }
      if (this._lastSessionsProjectionHash !== nextSessionsHash) {
        await this._replaceProjectedSessions(data.sessions);
      } else {
        this._lastSessionsProjectionHash = nextSessionsHash;
      }
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
