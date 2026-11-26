const crypto = require("node:crypto");
const {
  quoteIdentifier,
  normalizeStateVersion,
} = require("./pool");
const {
  FileStore,
  EMPTY_DB,
  normalizeDbState,
  normalizeNullableString,
  nowIso,
} = require("../../store");

module.exports = {
  async _createClientDiagnosticsTables() {
    await this._pool.query(`
      CREATE TABLE IF NOT EXISTS ${this._qualifiedClientDiagnosticsBackupsTableName} (
        id TEXT PRIMARY KEY,
        backup_data JSONB NOT NULL
      )
    `);
    await this._pool.query(`
      CREATE TABLE IF NOT EXISTS ${this._qualifiedClientDiagnosticsTableName} (
        id TEXT,
        user_id TEXT NOT NULL DEFAULT '',
        type TEXT NOT NULL DEFAULT 'client_event',
        created_at TEXT NOT NULL DEFAULT '',
        row_data JSONB NOT NULL,
        CONSTRAINT ${quoteIdentifier(`${this._clientDiagnosticsTable}_pk`)} PRIMARY KEY (id)
      )
    `);
    await this._pool.query(`
      CREATE INDEX IF NOT EXISTS ${quoteIdentifier(`${this._clientDiagnosticsTable}_created_idx`)}
        ON ${this._qualifiedClientDiagnosticsTableName} (created_at)
    `);
    await this._pool.query(`
      CREATE INDEX IF NOT EXISTS ${quoteIdentifier(`${this._clientDiagnosticsTable}_user_idx`)}
        ON ${this._qualifiedClientDiagnosticsTableName} (user_id)
    `);
    await this._pool.query(`
      CREATE INDEX IF NOT EXISTS ${quoteIdentifier(`${this._clientDiagnosticsTable}_type_idx`)}
        ON ${this._qualifiedClientDiagnosticsTableName} (type)
    `);
  },

  async _migrateClientDiagnosticsToTables(bootRow) {
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
          "[backend] client diagnostics migration skipped — state unavailable",
          JSON.stringify({message: error?.message || String(error)}),
        );
        return null;
      }
    }
    try {
      if (state?.migrationStatus?.clientDiagnosticsToTables === MARKER) {
        this._clientDiagnosticsTablesReady = true;
        return {state, version};
      }
      const rows = Array.isArray(state.clientDiagnostics) ? state.clientDiagnostics : [];
      await this._pool.query(
        `INSERT INTO ${this._qualifiedClientDiagnosticsBackupsTableName} (id, backup_data)
         VALUES ($1, $2::jsonb)
         ON CONFLICT (id) DO NOTHING`,
        [`pre-migration-${MARKER}`, JSON.stringify({savedAt: nowIso(), clientDiagnostics: rows})],
      );
      let inserted = 0;
      for (const entry of rows) {
        const id = String(entry?.id || "").trim();
        if (!id) continue;
        await this._pool.query(
          `INSERT INTO ${this._qualifiedClientDiagnosticsTableName}
             (id, user_id, type, created_at, row_data)
           VALUES ($1, $2, $3, $4, $5::jsonb)
           ON CONFLICT DO NOTHING`,
          [
            id,
            String(entry.userId || "").trim(),
            String(entry.type || "client_event").trim() || "client_event",
            String(entry.createdAt || "").trim(),
            JSON.stringify(entry),
          ],
        );
        inserted += 1;
      }
      const nextState = {
        ...state,
        clientDiagnostics: [],
        migrationStatus: {
          ...(state.migrationStatus || {}),
          clientDiagnosticsToTables: MARKER,
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
      this._cachedState = normalizeDbState(nextState);
      await this._persistSnapshotCache(this._cachedState);
      this._clientDiagnosticsTablesReady = true;
      console.log(
        "[backend] client diagnostics migrated to tables",
        JSON.stringify({rows: inserted}),
      );
      return {
        state: this._cachedState,
        version: normalizeStateVersion(
          updateResult?.rows?.[0]?.version,
        ),
      };
    } catch (error) {
      console.warn(
        "[backend] client diagnostics migration failed — blob stays source of truth",
        JSON.stringify({message: error?.message || String(error)}),
      );
      return {state, version};
    }
  },

  async createClientDiagnostic({
    userId,
    sessionId = null,
    type,
    message = "",
    platform = null,
    appVersion = null,
    context = {},
    error = null,
    stackTrace = null,
  }) {
    await this.initialize();
    if (!this._clientDiagnosticsTablesReady) {
      return FileStore.prototype.createClientDiagnostic.call(this, {
        userId,
        sessionId,
        type,
        message,
        platform,
        appVersion,
        context,
        error,
        stackTrace,
      });
    }
    const event = {
      id: `diag_${crypto.randomUUID()}`,
      userId: normalizeNullableString(userId),
      sessionId: normalizeNullableString(sessionId),
      type: normalizeNullableString(type) || "client_event",
      message: normalizeNullableString(message) || "",
      platform,
      appVersion,
      context: context && typeof context === "object" ? context : {},
      error,
      stackTrace,
      createdAt: nowIso(),
    };
    await this._pool.query(
      `INSERT INTO ${this._qualifiedClientDiagnosticsTableName}
         (id, user_id, type, created_at, row_data)
       VALUES ($1, $2, $3, $4, $5::jsonb)`,
      [event.id, event.userId || "", event.type, event.createdAt, JSON.stringify(event)],
    );
    // Тот же ring-buffer cap, что и в FileStore (slice(-500)) — точечный
    // DELETE вместо чтения всего блоба ради обрезки массива.
    await this._pool.query(
      `DELETE FROM ${this._qualifiedClientDiagnosticsTableName}
        WHERE id NOT IN (
          SELECT id FROM ${this._qualifiedClientDiagnosticsTableName}
          ORDER BY created_at DESC, id DESC
          LIMIT 500
        )`,
    );
    return structuredClone(event);
  },

  async listClientDiagnostics({type = null, userId = null, limit = 100} = {}) {
    await this.initialize();
    if (!this._clientDiagnosticsTablesReady) {
      return FileStore.prototype.listClientDiagnostics.call(this, {type, userId, limit});
    }
    await this._awaitReadConsistency();
    const normalizedType = normalizeNullableString(type);
    const normalizedUserId = normalizeNullableString(userId);
    const cappedLimit = Math.min(Math.max(Number(limit) || 100, 1), 500);
    const params = [];
    let where = "";
    if (normalizedType) {
      params.push(normalizedType);
      where += ` AND type = $${params.length}`;
    }
    if (normalizedUserId) {
      params.push(normalizedUserId);
      where += ` AND user_id = $${params.length}`;
    }
    params.push(cappedLimit);
    const result = await this._pool.query(
      `SELECT row_data
         FROM ${this._qualifiedClientDiagnosticsTableName}
        WHERE TRUE ${where}
        ORDER BY created_at DESC, id DESC
        LIMIT $${params.length}`,
      params,
    );
    return result.rows
      .map((row) => {
        const raw = row.row_data;
        return typeof raw === "string" ? JSON.parse(raw) : raw;
      })
      .filter(Boolean);
  },

};
