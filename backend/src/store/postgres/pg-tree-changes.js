const crypto = require("node:crypto");
const {
  quoteIdentifier,
  normalizeStateVersion,
} = require("./pool");
const {
  FileStore,
  EMPTY_DB,
  normalizeDbState,
  stripTreeChangeRecordDetails,
  nowIso,
} = require("../../store");

module.exports = {
  async _createTreeChangeTables() {
    await this._pool.query(`
      CREATE TABLE IF NOT EXISTS ${this._qualifiedTreeChangeBackupsTableName} (
        id TEXT PRIMARY KEY,
        backup_data JSONB NOT NULL
      )
    `);
    await this._pool.query(`
      CREATE TABLE IF NOT EXISTS ${this._qualifiedTreeChangeRecordsTableName} (
        id TEXT,
        tree_id TEXT NOT NULL,
        actor_id TEXT NOT NULL DEFAULT '',
        type TEXT NOT NULL DEFAULT 'unknown',
        person_id TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        record_data JSONB NOT NULL,
        CONSTRAINT ${quoteIdentifier(`${this._treeChangeRecordsTable}_pk`)} PRIMARY KEY (id)
      )
    `);
    await this._pool.query(`
      CREATE INDEX IF NOT EXISTS ${quoteIdentifier(`${this._treeChangeRecordsTable}_tree_idx`)}
        ON ${this._qualifiedTreeChangeRecordsTableName} (tree_id, created_at)
    `);
    await this._pool.query(`
      CREATE INDEX IF NOT EXISTS ${quoteIdentifier(`${this._treeChangeRecordsTable}_person_idx`)}
        ON ${this._qualifiedTreeChangeRecordsTableName} (person_id)
    `);
    await this._pool.query(`
      CREATE INDEX IF NOT EXISTS ${quoteIdentifier(`${this._treeChangeRecordsTable}_actor_idx`)}
        ON ${this._qualifiedTreeChangeRecordsTableName} (actor_id)
    `);
    await this._pool.query(`
      CREATE TABLE IF NOT EXISTS ${this._qualifiedHardDeleteAuditTableName} (
        id TEXT,
        hard_deleted_at TEXT NOT NULL DEFAULT '',
        audit_data JSONB NOT NULL,
        CONSTRAINT ${quoteIdentifier(`${this._hardDeleteAuditTable}_pk`)} PRIMARY KEY (id)
      )
    `);
    await this._pool.query(`
      CREATE INDEX IF NOT EXISTS ${quoteIdentifier(`${this._hardDeleteAuditTable}_at_idx`)}
        ON ${this._qualifiedHardDeleteAuditTableName} (hard_deleted_at)
    `);
  },

  _treeChangeRowValues(record) {
    const entry = record || {};
    return [
      String(entry.id || "").trim(),
      String(entry.treeId || "").trim(),
      String(entry.actorId || "").trim(),
      String(entry.type || "unknown").trim() || "unknown",
      String(entry.personId || "").trim(),
      String(entry.createdAt || "").trim(),
      JSON.stringify(entry),
    ];
  },

  _hardDeleteAuditRowValues(entry) {
    const record = entry && typeof entry === "object" ? entry : {};
    // У записей аудита нет собственного id — ключ нужен только таблице
    // (дедуп повторного дренажа). Не отдаём его наружу.
    const id = String(record.auditRowId || "").trim() || crypto.randomUUID();
    return [
      id,
      String(record.hardDeletedAt || "").trim(),
      JSON.stringify({...record, auditRowId: id}),
    ];
  },

  _rowToTreeChangeRecord(row) {
    const raw = row?.record_data;
    if (!raw) return null;
    return typeof raw === "string" ? JSON.parse(raw) : raw;
  },

  async _insertTreeChangeRecordRows(records) {
    let inserted = 0;
    let skipped = 0;
    for (const record of records) {
      const values = this._treeChangeRowValues(record);
      if (!values[0] || !values[1] || !values[5]) {
        skipped += 1;
        continue;
      }
      await this._pool.query(
        `INSERT INTO ${this._qualifiedTreeChangeRecordsTableName}
           (id, tree_id, actor_id, type, person_id, created_at, record_data)
         VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb)
         ON CONFLICT DO NOTHING`,
        values,
      );
      inserted += 1;
    }
    return {inserted, skipped};
  },

  async _insertHardDeleteAuditRows(entries) {
    let inserted = 0;
    for (const entry of entries) {
      if (!entry || typeof entry !== "object") continue;
      await this._pool.query(
        `INSERT INTO ${this._qualifiedHardDeleteAuditTableName}
           (id, hard_deleted_at, audit_data)
         VALUES ($1, $2, $3::jsonb)
         ON CONFLICT DO NOTHING`,
        this._hardDeleteAuditRowValues(entry),
      );
      inserted += 1;
    }
    return inserted;
  },

  // Маркер — migrationStatus.treeChangeRecordsToTables; массивы целиком
  // сохраняются в backup-таблицу (откат — scripts/
  // restore-tree-change-records-to-blob.js), после чего вычищаются из блоба.
  // SPEED-9 C-boot: опциональный {state, version} от предыдущего шага
  // буста — без него прежнее поведение (собственный SELECT). На успехе
  // возвращает {state, version} строки ПОСЛЕ этого шага; при неудаче
  // самой миграции (второй catch — намеренно НЕ бросает, в отличие от
  // чата/notifications) возвращает вход без изменений — блоб не писали.
  async _migrateTreeChangeCollectionsToTables(bootRow) {
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
          "[backend] tree change collections migration skipped — state unavailable",
          JSON.stringify({message: error?.message || String(error)}),
        );
        return null;
      }
    }
    try {
      if (state?.migrationStatus?.treeChangeRecordsToTables === MARKER) {
        this._treeChangeTablesReady = true;
        return {state, version};
      }
      const records = Array.isArray(state.treeChangeRecords)
        ? state.treeChangeRecords
        : [];
      const audit = Array.isArray(state.hardDeleteAudit)
        ? state.hardDeleteAudit
        : [];
      await this._pool.query(
        `INSERT INTO ${this._qualifiedTreeChangeBackupsTableName} (id, backup_data)
         VALUES ($1, $2::jsonb)
         ON CONFLICT (id) DO NOTHING`,
        [
          `pre-migration-${MARKER}`,
          JSON.stringify({savedAt: nowIso(), treeChangeRecords: records, hardDeleteAudit: audit}),
        ],
      );
      const inserted = await this._insertTreeChangeRecordRows(records);
      const auditInserted = await this._insertHardDeleteAuditRows(audit);
      const nextState = {
        ...state,
        treeChangeRecords: [],
        hardDeleteAudit: [],
        migrationStatus: {
          ...(state.migrationStatus || {}),
          treeChangeRecordsToTables: MARKER,
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
      // Sidecar-кэш обязан пережить границу миграции (см. SPEED-6).
      await this._persistSnapshotCache(this._cachedState);
      this._treeChangeTablesReady = true;
      console.log(
        "[backend] tree change collections migrated to tables",
        JSON.stringify({
          records: inserted.inserted,
          recordsSkipped: inserted.skipped,
          hardDeleteAudit: auditInserted,
        }),
      );
      return {
        state: this._cachedState,
        version: normalizeStateVersion(
          updateResult?.rows?.[0]?.version,
        ),
      };
    } catch (error) {
      console.warn(
        "[backend] tree change collections migration failed — blob stays source of truth",
        JSON.stringify({message: error?.message || String(error)}),
      );
      return {state, version};
    }
  },

  _queueTreeChangeOp(op) {
    if (!this._treeChangeTablesReady) return;
    this._pendingTreeChangeOps.push(op);
  },

  async _applyTreeChangeOp(op) {
    const table = this._qualifiedTreeChangeRecordsTableName;
    if (op.kind === "merge") {
      const result = await this._pool.query(
        `SELECT id, record_data FROM ${table} WHERE tree_id = $1`,
        [op.treeId],
      );
      for (const row of result.rows) {
        const record = this._rowToTreeChangeRecord(row);
        if (!record) continue;
        const scratch = {treeChangeRecords: [record]};
        FileStore.prototype._rewriteTreeChangeRecordsForMerge.call(this, scratch, op);
        await this._pool.query(
          `UPDATE ${table}
              SET person_id = $2, record_data = $3::jsonb
            WHERE id = $1`,
          [row.id, String(record.personId || ""), JSON.stringify(record)],
        );
      }
      return;
    }
    if (op.kind === "pseudonymize") {
      const result = await this._pool.query(
        `SELECT id, record_data FROM ${table} WHERE actor_id = $1`,
        [op.userId],
      );
      for (const row of result.rows) {
        const record = this._rowToTreeChangeRecord(row);
        if (!record) continue;
        record.actorId = "deleted-user";
        record.actorName = null;
        await this._pool.query(
          `UPDATE ${table}
              SET actor_id = 'deleted-user', record_data = $2::jsonb
            WHERE id = $1`,
          [row.id, JSON.stringify(record)],
        );
      }
      return;
    }
    if (op.kind === "strip") {
      // article.* не трогаем (провенанс биографий); срез — только старым.
      const result = await this._pool.query(
        `SELECT id, record_data FROM ${table}
          WHERE created_at < $1 AND type NOT LIKE 'article.%'`,
        [op.cutoffIso],
      );
      let stripped = 0;
      for (const row of result.rows) {
        const record = this._rowToTreeChangeRecord(row);
        if (!stripTreeChangeRecordDetails(record, {cutoffTs: op.cutoffTs})) {
          continue;
        }
        await this._pool.query(
          `UPDATE ${table} SET record_data = $2::jsonb WHERE id = $1`,
          [row.id, JSON.stringify(record)],
        );
        stripped += 1;
      }
      if (stripped) {
        console.log(
          "[backend] tree change details stripped (tables)",
          JSON.stringify({stripped, cutoff: op.cutoffIso}),
        );
      }
      return;
    }
    if (op.kind === "pruneAudit") {
      const result = await this._pool.query(
        `DELETE FROM ${this._qualifiedHardDeleteAuditTableName}
          WHERE hard_deleted_at <> '' AND hard_deleted_at < $1`,
        [op.cutoffIso],
      );
      if (result.rowCount) {
        console.log(
          "[backend] hard delete audit pruned (tables)",
          JSON.stringify({pruned: result.rowCount, cutoff: op.cutoffIso}),
        );
      }
    }
  },

  /// Дренаж на записи: новые записи журнала/аудита из массивов блоба → в
  /// таблицы. Ошибка = best-effort: массивы остаются в блобе, следующий _write повторит.
  async _drainTreeChangeCollections(data) {
    if (!this._treeChangeTablesReady) {
      return data;
    }
    const records = Array.isArray(data?.treeChangeRecords)
      ? data.treeChangeRecords
      : [];
    const audit = Array.isArray(data?.hardDeleteAudit) ? data.hardDeleteAudit : [];
    if (records.length === 0 && audit.length === 0) {
      return data;
    }
    try {
      if (records.length) {
        await this._insertTreeChangeRecordRows(records);
      }
      if (audit.length) {
        await this._insertHardDeleteAuditRows(audit);
      }
    } catch (error) {
      console.warn(
        "[backend] tree change drain failed — arrays stay in blob for retry",
        JSON.stringify({message: error?.message || String(error)}),
      );
      return data;
    }
    return {...data, treeChangeRecords: [], hardDeleteAudit: []};
  },

  async _applyPendingTreeChangeOps(ops) {
    if (!this._treeChangeTablesReady || !Array.isArray(ops) || ops.length === 0) {
      return;
    }
    for (let i = 0; i < ops.length; i += 1) {
      try {
        await this._applyTreeChangeOp(ops[i]);
      } catch (error) {
        console.warn(
          "[backend] tree change post-write op failed",
          JSON.stringify({message: error?.message || String(error)}),
        );
        this._pendingTreeChangeOps.unshift(...ops.slice(i));
        return;
      }
    }
  },

  // ── хуки FileStore → таблицы ──
  _rewriteTreeChangeRecordsForMerge(db, op) {
    FileStore.prototype._rewriteTreeChangeRecordsForMerge.call(this, db, op);
    this._queueTreeChangeOp({kind: "merge", ...op});
  },

  _pseudonymizeTreeChangeActor(db, userId) {
    FileStore.prototype._pseudonymizeTreeChangeActor.call(this, db, userId);
    this._queueTreeChangeOp({kind: "pseudonymize", userId});
  },

  _stripTreeChangeDetails(db, {cutoffTs, dryRun = false}) {
    const blobStripped = FileStore.prototype._stripTreeChangeDetails.call(this, db, {cutoffTs, dryRun});
    if (!dryRun) {
      this._queueTreeChangeOp({
        kind: "strip",
        cutoffTs,
        cutoffIso: new Date(cutoffTs).toISOString(),
      });
    }
    // Табличная часть считается при применении (лог «stripped (tables)»).
    return blobStripped;
  },

  _pruneHardDeleteAudit(db, {cutoffTs, dryRun = false}) {
    const result = FileStore.prototype._pruneHardDeleteAudit.call(this, db, {cutoffTs, dryRun});
    if (!dryRun) {
      this._queueTreeChangeOp({
        kind: "pruneAudit",
        cutoffIso: new Date(cutoffTs).toISOString(),
      });
    }
    return result;
  },

  // ── чтения ──
  async listTreeChangeRecords(treeId, {personId = null, type = null, actorId = null} = {}) {
    await this.initialize();
    if (!this._treeChangeTablesReady) {
      return FileStore.prototype.listTreeChangeRecords.call(this, treeId, {personId, type, actorId});
    }
    await this._awaitReadConsistency();
    const normalizedTreeId = String(treeId || "").trim();
    if (!normalizedTreeId) return [];
    const params = [normalizedTreeId];
    let extra = "";
    if (type) {
      params.push(String(type));
      extra += ` AND type = $${params.length}`;
    }
    if (actorId) {
      params.push(String(actorId));
      extra += ` AND actor_id = $${params.length}`;
    }
    const result = await this._pool.query(
      `SELECT record_data
         FROM ${this._qualifiedTreeChangeRecordsTableName}
        WHERE tree_id = $1${extra}
        ORDER BY created_at DESC, id DESC`,
      params,
    );
    const wantedPerson = personId ? String(personId) : null;
    return result.rows
      .map((row) => this._rowToTreeChangeRecord(row))
      .filter((record) => {
        if (!record) return false;
        if (!wantedPerson) return true;
        const ids = Array.isArray(record.personIds) ? record.personIds : [];
        return record.personId === wantedPerson || ids.includes(wantedPerson);
      });
  },

  async getArticleHistory({personId}) {
    const id = String(personId || "").trim();
    if (!id) throw new Error("INVALID_INPUT");
    await this.initialize();
    if (!this._treeChangeTablesReady) {
      return FileStore.prototype.getArticleHistory.call(this, {personId});
    }
    const db = await this._read();
    this._resolveArticleContext(db, id); // PERSON_NOT_FOUND guard
    const result = await this._pool.query(
      `SELECT record_data
         FROM ${this._qualifiedTreeChangeRecordsTableName}
        WHERE person_id = $1 AND type LIKE 'article.%'
        ORDER BY created_at DESC, id DESC`,
      [id],
    );
    return result.rows.map((row) => this._rowToTreeChangeRecord(row)).filter(Boolean);
  },

  // ── SPEED-15: корзина deletedPersons в таблице ──────────────────────
  // 245 КБ / 220 записей на проде (15% блоба) — снапшоты персон+связей на
  // 30-дневное восстановление, читаемые ТОЛЬКО экраном «Корзина». Новые
  // строки по-прежнему рождаются в блобе (deletePerson не переопределён —
  // FileStore.deletePerson делает db.deletedPersons.push внутри своего
  // _read()+_write()) и дренируются в таблицу на _write, как treeChangeRe-
  // cords. НО в отличие от журнала — не append-only: restorePerson мутирует
  // строку (restoredAt), hardDeletePerson удаляет её, поэтому чтения
  // (list*/restore/hardDelete) полностью переопределены на SQL, а не
  // делегируют FileStore-логику по пустому после дренажа блоб-массиву.
};
