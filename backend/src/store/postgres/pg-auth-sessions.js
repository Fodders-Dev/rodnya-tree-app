const crypto = require("node:crypto");
const path = require("node:path");
const {
  isProjectionHydrationFallbackError,
  isProjectionArrayInsertFallbackError,
  computeProjectionHash,
  normalizeStateVersion,
} = require("./pool");
const {
  EMPTY_DB,
  cloneUserWithAuthState,
  deriveSessionPublicId,
  normalizeDbState,
  normalizeSessionDeviceContext,
  nowIso,
  SESSION_TOUCH_MIN_INTERVAL_MS,
  verifyPassword,
} = require("../../store");
const {backfillPersonIdentities} = require("../../migration-utils");

module.exports = {
  async _backfillPersonIdentitiesInStateRow(bootRow) {
    try {
      let normalized;
      let version = bootRow ? bootRow.version ?? null : null;
      if (bootRow && bootRow.state) {
        normalized = bootRow.state;
      } else {
        const result = await this._pool.query(
          `SELECT data FROM ${this._qualifiedTableName} WHERE id = $1`,
          [this._rowId],
        );
        const rawData = result.rows[0]?.data ?? EMPTY_DB;
        normalized = normalizeDbState(rawData);
      }
      const migration = backfillPersonIdentities(normalized);
      if (!migration.changed) {
        this._cachedState = normalized;
        return {state: normalized, version};
      }

      const updateResult = await this._pool.query(
        `UPDATE ${this._qualifiedTableName}
            SET data = $2::jsonb,
                updated_at = NOW(),
                version = version + 1
          WHERE id = $1
          RETURNING version`,
        [this._rowId, JSON.stringify(migration.snapshot)],
      );
      this._cachedState = normalizeDbState(migration.snapshot);
      return {
        state: this._cachedState,
        version: normalizeStateVersion(
          updateResult?.rows?.[0]?.version,
        ),
      };
    } catch (error) {
      console.warn(
        "[backend] postgres-store skipped person identity backfill",
        JSON.stringify({
          table: `${this._schema}.${this._table}`,
          rowId: this._rowId,
          message: error?.message || String(error),
        }),
      );
      return bootRow || null;
    }
  },

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
  },

  // SPEED-9 C-boot: primary-путь ниже — чистый SQL (LATERAL по data->'users'
  // / data->'sessions'), блоб в JS никогда не тянет — на реальном Postgres
  // не входит в счёт «SELECT+parse блоба» вообще. Опциональный bootState
  // используется ТОЛЬКО в fallback-ветке (когда LATERAL недоступен —
  // сегодня это исключительно pg-mem-ограничение в тестах, см.
  // docs/speed_measurement.md), чтобы и там не делать отдельный SELECT.
  async _hydrateAuthProjectionTablesFromStateRow(bootState) {
    // SPEED-15: once migrationStatus.sessionsOutOfBlob is set, data->
    // 'sessions' in the row is permanently `[]` — this function used to
    // rebuild the auth-sessions projection FROM the blob on EVERY boot
    // (belt-and-suspenders against drift), which would now DELETE every
    // live session on each restart/deploy. bootState is the row this SAME
    // boot already read (SPEED-9 C-boot cursor) when available; on the
    // degraded no-cursor path fall back to a cheap scalar marker read
    // instead of skipping the check (default = rebuild, today's behavior,
    // if even that fails).
    let sessionsOutOfBlob =
      bootState?.migrationStatus?.sessionsOutOfBlob === "complete-v1";
    let skipSessionsRebuild = false;
    if (!bootState) {
      try {
        const markerResult = await this._pool.query(
          `SELECT data->'migrationStatus'->>'sessionsOutOfBlob' AS marker
             FROM ${this._qualifiedTableName} WHERE id = $1`,
          [this._rowId],
        );
        sessionsOutOfBlob = markerResult.rows[0]?.marker === "complete-v1";
      } catch (error) {
        // Never fall back to `false` on a transient DB error: wiping
        // auth_sessions against a SPEED-15 empty-sessions blob would log out
        // every active user in production.
        console.warn(
          "[backend] postgres-store failed to verify sessionsOutOfBlob marker — skipping auth_sessions rebuild",
          JSON.stringify({message: error?.message || String(error)}),
        );
        skipSessionsRebuild = true;
      }
    }
    this._sessionsOutOfBlob = sessionsOutOfBlob;
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
        if (!sessionsOutOfBlob && !skipSessionsRebuild) {
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
        }
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
          let rawData = bootState;
          if (!rawData) {
            const result = await this._pool.query(
              `SELECT data FROM ${this._qualifiedTableName} WHERE id = $1`,
              [this._rowId],
            );
            rawData = result.rows[0]?.data ?? EMPTY_DB;
          }
          await this._replaceProjectedUsers(rawData.users);
          if (!sessionsOutOfBlob && !skipSessionsRebuild) {
            await this._replaceProjectedSessions(rawData.sessions);
          }
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
  },

  async _replaceProjectedUsers(users) {
    const normalizedUsers = Array.isArray(users) ? users : [];
    await this._withProjectionClient(async (client, useTransaction) => {
      try {
        if (useTransaction) {
          await client.query("BEGIN");
          await client.query("SET LOCAL statement_timeout = 0");
        }
        await client.query(`DELETE FROM ${this._qualifiedAuthUsersTableName}`);
        try {
          await client.query(
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
            await client.query(
              `INSERT INTO ${this._qualifiedAuthUsersTableName} (id, email, user_data)
               VALUES ($1, $2, $3::jsonb)`,
              [userId, email, JSON.stringify(user)],
            );
          }
        }
        if (useTransaction) {
          await client.query("COMMIT");
        }
      } catch (error) {
        if (useTransaction) {
          try {
            await client.query("ROLLBACK");
          } catch (_) {
            // original error is more informative
          }
        }
        throw error;
      }
    });
    this._lastUsersProjectionHash = computeProjectionHash(normalizedUsers);
  },

  async _replaceProjectedSessions(sessions) {
    const normalizedSessions = Array.isArray(sessions) ? sessions : [];
    await this._withProjectionClient(async (client, useTransaction) => {
      try {
        if (useTransaction) {
          await client.query("BEGIN");
          await client.query("SET LOCAL statement_timeout = 0");
        }
        await client.query(`DELETE FROM ${this._qualifiedAuthSessionsTableName}`);
        try {
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
            await client.query(
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
        if (useTransaction) {
          await client.query("COMMIT");
        }
      } catch (error) {
        if (useTransaction) {
          try {
            await client.query("ROLLBACK");
          } catch (_) {
            // original error is more informative
          }
        }
        throw error;
      }
    });
    this._lastSessionsProjectionHash = computeProjectionHash(normalizedSessions);
  },

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
              updated_at = NOW(),
              version = version + 1
        WHERE id = $1`,
      [this._rowId],
    );
  },

  async _awaitReadConsistency() {
    try {
      await this._awaitWriteQueue(this._stateWriteQueue);
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
  },

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
  },

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
  },

  async _selectSessionsArray() {
    await this.initialize();
    return this._selectProjectedSessionsArray();
  },

  async _selectProjectedSessionsArray() {
    const result = await this._pool.query(
      `SELECT session_data
         FROM ${this._qualifiedAuthSessionsTableName}
        ORDER BY created_at NULLS FIRST, token`,
    );
    return result.rows.map((row) => row.session_data).filter(Boolean);
  },

  async _updateSessionsArray(sessions) {
    await this._replaceProjectedSessions(sessions);
  },

  // ── SPEED-15: sessions полностью вне блоба ──────────────────────────
  // _read() уже подменяет data.sessions содержимым auth_sessions на КАЖДОМ
  // пути (SPEED-6 проекция + SPEED-8a кэш) — то, что лежит в самой JSONB-
  // колонке, никогда не читается назад НИГДЕ на PostgresStore. Единственный
  // потребитель блобовых sessions — _hydrateAuthProjectionTablesFromStateRow
  // на буте (перестраивает таблицу ИЗ блоба «на всякий случай» при старте
  // процесса); он уже проверяет этот же маркер и пропускает перестройку
  // (см. выше), иначе обнулённый блоб стёр бы все сессии на первом же
  // рестарте после миграции.
  async _createSessionsBackupsTable() {
    await this._pool.query(`
      CREATE TABLE IF NOT EXISTS ${this._qualifiedSessionsBackupsTableName} (
        id TEXT PRIMARY KEY,
        backup_data JSONB NOT NULL
      )
    `);
  },

  async _migrateSessionsOutOfBlob(bootRow) {
    const MARKER = "complete-v1";
    let state = null;
    let version = bootRow ? bootRow.version ?? null : null;
    if (bootRow && bootRow.state) {
      state = bootRow.state;
    } else {
      try {
        const result = await this._pool.query(
          `SELECT data FROM ${this._qualifiedTableName} WHERE id = $1`,
          [this._rowId],
        );
        const rawData = result.rows[0]?.data ?? EMPTY_DB;
        state = normalizeDbState(
          typeof rawData === "string" ? JSON.parse(rawData) : rawData,
        );
      } catch (error) {
        console.warn(
          "[backend] sessions-out-of-blob migration skipped — state unavailable",
          JSON.stringify({message: error?.message || String(error)}),
        );
        return null;
      }
    }
    try {
      if (state?.migrationStatus?.sessionsOutOfBlob === MARKER) {
        this._sessionsOutOfBlob = true;
        return {state, version};
      }
      const sessions = Array.isArray(state.sessions) ? state.sessions : [];
      // Бэкап — на случай отката до кода без этой миграции (см.
      // scripts/restore-sessions-to-blob.js). Проекционная таблица уже
      // отражает эти же данные (_hydrateAuthProjectionTablesFromStateRow
      // чуть раньше в этом же буте прогнала блоб → таблицу как обычно,
      // маркер тогда ещё не стоял) — здесь только фиксируем bind-снимок и
      // чистим блоб.
      await this._pool.query(
        `INSERT INTO ${this._qualifiedSessionsBackupsTableName} (id, backup_data)
         VALUES ($1, $2::jsonb)
         ON CONFLICT (id) DO NOTHING`,
        [`pre-migration-${MARKER}`, JSON.stringify({savedAt: nowIso(), sessions})],
      );
      const nextState = {
        ...state,
        sessions: [],
        migrationStatus: {
          ...(state.migrationStatus || {}),
          sessionsOutOfBlob: MARKER,
        },
      };
      const updateResult = await this._pool.query(
        `UPDATE ${this._qualifiedTableName}
            SET data = $2::jsonb,
                updated_at = NOW(),
                version = version + 1
          WHERE id = $1
          RETURNING version`,
        [this._rowId, JSON.stringify(nextState)],
      );
      // Кэш обязан помнить РЕАЛЬНЫЕ сессии (как и везде — _read() накладывает
      // их поверх кэша из проекции), иначе первый _read() увидел бы
      // sessions: [] из этого объекта раньше, чем успеет их подменить.
      this._cachedState = normalizeDbState({...nextState, sessions});
      await this._persistSnapshotCache(this._cachedState);
      this._sessionsOutOfBlob = true;
      console.log(
        "[backend] sessions migrated out of blob",
        JSON.stringify({sessions: sessions.length}),
      );
      return {
        state: this._cachedState,
        version: normalizeStateVersion(
          updateResult?.rows?.[0]?.version,
        ),
      };
    } catch (error) {
      console.warn(
        "[backend] sessions-out-of-blob migration failed — blob stays source of truth",
        JSON.stringify({message: error?.message || String(error)}),
      );
      return {state, version};
    }
  },

  async authenticate(email, password) {
    const normalizedEmail = String(email || "").trim().toLowerCase();
    if (!normalizedEmail) {
      return null;
    }
    await this.initialize();
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
  },

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
  },

  async findUserByEmail(email) {
    const normalizedEmail = String(email || "").trim().toLowerCase();
    if (!normalizedEmail) {
      return null;
    }

    await this.initialize();
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
  },

  _logWriteFailure(error) {
    console.error(
      "[backend] postgres-store write failed",
      JSON.stringify({
        table: `${this._schema}.${this._table}`,
        rowId: this._rowId,
        message: String(error?.message || error || "unknown_error"),
      }),
    );
  },

  _enqueueWrite(queueName, operation) {
    const previousQueue = this[queueName].catch(() => {});
    const nextWrite = (async () => {
      await this._awaitWriteQueue(previousQueue);
      return operation();
    })();

    this[queueName] = nextWrite.catch((error) => {
      this._logWriteFailure(error);
      throw error;
    });
    if (queueName === "_stateWriteQueue") {
      this._writeQueue = this[queueName];
    }

    return nextWrite;
  },

  async createSession(userId, deviceContext = {}) {
    const createdAt = nowIso();
    const token = crypto.randomBytes(32).toString("hex");
    const refreshToken = crypto.randomBytes(32).toString("hex");
    const normalizedDeviceContext = normalizeSessionDeviceContext(deviceContext);
    const incomingInstanceId = normalizedDeviceContext.instanceId;

    const nextWrite = this._enqueueWrite("_sessionWriteQueue", async () => {
      await this.initialize();
      const userSessions = await this._selectProjectedSessionsForUser(userId);

      const supersededInstanceMatches = incomingInstanceId
        ? userSessions.filter((s) => s.instanceId === incomingInstanceId)
        : [];
      const remainingAfterInstanceMatch = incomingInstanceId
        ? userSessions.filter((s) => s.instanceId !== incomingInstanceId)
        : userSessions;

      const sessionsToKeep = remainingAfterInstanceMatch.slice(-4);
      const overflowEvicted = remainingAfterInstanceMatch.slice(
        0,
        Math.max(
          0,
          remainingAfterInstanceMatch.length - sessionsToKeep.length,
        ),
      );
      const evictedSessions = [
        ...supersededInstanceMatches,
        ...overflowEvicted,
      ];

      const createdSession = {
        token,
        refreshToken,
        userId,
        createdAt,
        lastSeenAt: createdAt,
        ...normalizedDeviceContext,
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

    const {createdSession, evictedSessions} = await nextWrite;
    for (const session of evictedSessions) {
      this._forgetSession(session?.token);
    }
    this._rememberSession(createdSession);
    return {
      token,
      refreshToken,
      session: structuredClone(createdSession),
      evictedTokens: evictedSessions
        .map((entry) => String(entry?.token || "").trim())
        .filter(Boolean),
    };
  },

  async listSessionsForUser(userId) {
    const normalizedUserId = String(userId || "").trim();
    if (!normalizedUserId) {
      return [];
    }
    await this.initialize();
    const sessions = await this._selectProjectedSessionsForUser(normalizedUserId);
    return sessions
      .map((session) => structuredClone(session))
      .sort((left, right) => {
        const leftAt = String(left.lastSeenAt || left.createdAt || "");
        const rightAt = String(right.lastSeenAt || right.createdAt || "");
        return rightAt.localeCompare(leftAt);
      });
  },

  async findSessionByPublicId(userId, publicId) {
    const normalizedUserId = String(userId || "").trim();
    const normalizedPublicId = String(publicId || "").trim();
    if (!normalizedUserId || !normalizedPublicId) {
      return null;
    }
    const sessions = await this.listSessionsForUser(normalizedUserId);
    for (const session of sessions) {
      const candidate = deriveSessionPublicId(
        session.token,
        session.instanceId || "",
      );
      if (candidate === normalizedPublicId) {
        return session;
      }
    }
    return null;
  },

  async updateSessionMetadata(token, patch = {}) {
    const normalizedToken = String(token || "").trim();
    if (!normalizedToken) {
      return null;
    }

    const nextWrite = this._enqueueWrite("_sessionWriteQueue", async () => {
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
        return null;
      }
      const session = structuredClone(storedSession);
      const allowedKeys = ["deviceName", "platform", "osVersion", "appVersion"];
      for (const key of allowedKeys) {
        if (patch[key] === undefined) continue;
        const normalized = String(patch[key] ?? "").trim();
        session[key] = normalized || null;
      }
      await this._upsertProjectedSession(session);
      return session;
    });

    const updated = await nextWrite;
    if (!updated) {
      return null;
    }
    this._rememberSession(updated);
    return structuredClone(updated);
  },

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
  },

  async findSessionByRefreshToken(refreshToken) {
    const normalizedRefreshToken = String(refreshToken || "").trim();
    if (!normalizedRefreshToken) {
      return null;
    }

    await this.initialize();
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
  },

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
    const nextWrite = this._enqueueWrite("_sessionWriteQueue", async () => {
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

    const touchedSession = await nextWrite;
    if (!touchedSession) {
      return null;
    }
    this._rememberSession(touchedSession);
    return structuredClone(touchedSession);
  },

  async deleteSession(token) {
    const normalizedToken = String(token || "").trim();
    if (!normalizedToken) {
      return null;
    }

    const nextWrite = this._enqueueWrite("_sessionWriteQueue", async () => {
      await this.initialize();
      const selectResult = await this._pool.query(
        `SELECT session_data
           FROM ${this._qualifiedAuthSessionsTableName}
          WHERE token = $1
          LIMIT 1`,
        [normalizedToken],
      );
      const removed = selectResult.rows[0]?.session_data ?? null;
      await this._pool.query(
        `DELETE FROM ${this._qualifiedAuthSessionsTableName} WHERE token = $1`,
        [normalizedToken],
      );
      return removed;
    });

    this._forgetSession(normalizedToken);
    const removed = await nextWrite;
    return removed ? structuredClone(removed) : null;
  },

  async deleteSessionsForUser(userId) {
    const normalizedUserId = String(userId || "").trim();
    if (!normalizedUserId) {
      return;
    }

    const nextWrite = this._enqueueWrite("_sessionWriteQueue", async () => {
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

    const deletedTokens = (await nextWrite) || [];
    for (const token of deletedTokens) {
      this._forgetSession(token);
    }
  },

};
