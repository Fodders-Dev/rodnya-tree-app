const {
  quoteIdentifier,
  normalizeStateVersion,
} = require("./pool");
const {
  FileStore,
  EMPTY_DB,
  ensureCirclesForTree,
  normalizeDbState,
  nowIso,
} = require("../../store");

module.exports = {
  async _createDeletedPersonsTables() {
    await this._pool.query(`
      CREATE TABLE IF NOT EXISTS ${this._qualifiedDeletedPersonsBackupsTableName} (
        id TEXT PRIMARY KEY,
        backup_data JSONB NOT NULL
      )
    `);
    await this._pool.query(`
      CREATE TABLE IF NOT EXISTS ${this._qualifiedDeletedPersonsTableName} (
        id TEXT,
        original_person_id TEXT NOT NULL DEFAULT '',
        tree_id TEXT NOT NULL DEFAULT '',
        semya_id TEXT NOT NULL DEFAULT '',
        deleted_by_user_id TEXT NOT NULL DEFAULT '',
        deleted_at TEXT NOT NULL DEFAULT '',
        hard_delete_scheduled_at TEXT NOT NULL DEFAULT '',
        earliest_hard_delete TEXT NOT NULL DEFAULT '',
        restored_at TEXT NOT NULL DEFAULT '',
        restored_by_user_id TEXT NOT NULL DEFAULT '',
        row_data JSONB NOT NULL,
        CONSTRAINT ${quoteIdentifier(`${this._deletedPersonsTable}_pk`)} PRIMARY KEY (id)
      )
    `);
    await this._pool.query(`
      CREATE INDEX IF NOT EXISTS ${quoteIdentifier(`${this._deletedPersonsTable}_semya_idx`)}
        ON ${this._qualifiedDeletedPersonsTableName} (semya_id)
    `);
    await this._pool.query(`
      CREATE INDEX IF NOT EXISTS ${quoteIdentifier(`${this._deletedPersonsTable}_actor_idx`)}
        ON ${this._qualifiedDeletedPersonsTableName} (deleted_by_user_id)
    `);
  },

  _deletedPersonRowValues(entry) {
    const row = entry && typeof entry === "object" ? entry : {};
    return [
      String(row.id || "").trim(),
      String(row.originalPersonId || "").trim(),
      String(row.treeId || "").trim(),
      String(row.semyaId || "").trim(),
      String(row.deletedByUserId || "").trim(),
      String(row.deletedAt || "").trim(),
      String(row.hardDeleteScheduledAt || "").trim(),
      String(row.earliestHardDelete || "").trim(),
      String(row.restoredAt || "").trim(),
      String(row.restoredByUserId || "").trim(),
      JSON.stringify(row),
    ];
  },

  _rowToDeletedPerson(row) {
    const raw = row?.row_data;
    if (!raw) return null;
    return typeof raw === "string" ? JSON.parse(raw) : raw;
  },

  async _insertDeletedPersonRows(rows) {
    let inserted = 0;
    let skipped = 0;
    for (const entry of rows) {
      const values = this._deletedPersonRowValues(entry);
      if (!values[0]) {
        skipped += 1;
        continue;
      }
      await this._pool.query(
        `INSERT INTO ${this._qualifiedDeletedPersonsTableName}
           (id, original_person_id, tree_id, semya_id, deleted_by_user_id, deleted_at,
            hard_delete_scheduled_at, earliest_hard_delete, restored_at, restored_by_user_id, row_data)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11::jsonb)
         ON CONFLICT DO NOTHING`,
        values,
      );
      inserted += 1;
    }
    return {inserted, skipped};
  },

  // Маркер — migrationStatus.deletedPersonsToTables. Тот же контракт, что
  // и у treeChangeRecords: опциональный {state, version} от предыдущего
  // шага буста; на успехе возвращает {state, version} ПОСЛЕ своей записи.
  async _migrateDeletedPersonsToTables(bootRow) {
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
          "[backend] deleted persons migration skipped — state unavailable",
          JSON.stringify({message: error?.message || String(error)}),
        );
        return null;
      }
    }
    try {
      if (state?.migrationStatus?.deletedPersonsToTables === MARKER) {
        this._deletedPersonsTablesReady = true;
        return {state, version};
      }
      const rows = Array.isArray(state.deletedPersons) ? state.deletedPersons : [];
      await this._pool.query(
        `INSERT INTO ${this._qualifiedDeletedPersonsBackupsTableName} (id, backup_data)
         VALUES ($1, $2::jsonb)
         ON CONFLICT (id) DO NOTHING`,
        [`pre-migration-${MARKER}`, JSON.stringify({savedAt: nowIso(), deletedPersons: rows})],
      );
      const inserted = await this._insertDeletedPersonRows(rows);
      const nextState = {
        ...state,
        deletedPersons: [],
        migrationStatus: {
          ...(state.migrationStatus || {}),
          deletedPersonsToTables: MARKER,
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
      this._deletedPersonsTablesReady = true;
      console.log(
        "[backend] deleted persons migrated to tables",
        JSON.stringify({rows: inserted.inserted, skipped: inserted.skipped}),
      );
      return {
        state: this._cachedState,
        version: normalizeStateVersion(
          updateResult?.rows?.[0]?.version,
        ),
      };
    } catch (error) {
      console.warn(
        "[backend] deleted persons migration failed — blob stays source of truth",
        JSON.stringify({message: error?.message || String(error)}),
      );
      return {state, version};
    }
  },

  _queueDeletedPersonOp(op) {
    if (!this._deletedPersonsTablesReady) return;
    this._pendingDeletedPersonsOps.push(op);
  },

  async _applyDeletedPersonOp(op) {
    if (op.kind === "restore") {
      // row_data должен остаться консистентен с колонками — restorePerson/
      // hardDeletePerson читают ТОЛЬКО row_data (это то, что уходит клиенту),
      // а не отдельные restored_at/restored_by_user_id колонки (те служат
      // только фильтрам WHERE restored_at = ''). Без этого повторный SELECT
      // видел бы restoredAt: null в JSON при уже заполненной колонке —
      // ALREADY_RESTORED никогда бы не сработал.
      const current = await this._pool.query(
        `SELECT row_data FROM ${this._qualifiedDeletedPersonsTableName} WHERE id = $1`,
        [op.id],
      );
      const row = this._rowToDeletedPerson(current.rows[0]);
      if (!row) return;
      const nextRow = {
        ...row,
        restoredAt: op.restoredAt,
        restoredByUserId: op.restoredByUserId || null,
      };
      await this._pool.query(
        `UPDATE ${this._qualifiedDeletedPersonsTableName}
            SET restored_at = $2, restored_by_user_id = $3, row_data = $4::jsonb
          WHERE id = $1`,
        [op.id, op.restoredAt, op.restoredByUserId || "", JSON.stringify(nextRow)],
      );
    }
  },

  /// Дренаж на записи: новые строки корзины из блоба → в таблицу.
  async _drainDeletedPersonsCollection(data) {
    if (!this._deletedPersonsTablesReady) {
      return data;
    }
    const rows = Array.isArray(data?.deletedPersons) ? data.deletedPersons : [];
    if (rows.length === 0) {
      return data;
    }
    try {
      await this._insertDeletedPersonRows(rows);
    } catch (error) {
      console.warn(
        "[backend] deleted persons drain failed — array stays in blob for retry",
        JSON.stringify({message: error?.message || String(error)}),
      );
      return data;
    }
    return {...data, deletedPersons: []};
  },

  async _applyPendingDeletedPersonsOps(ops) {
    if (!this._deletedPersonsTablesReady || !Array.isArray(ops) || ops.length === 0) {
      return;
    }
    for (let i = 0; i < ops.length; i += 1) {
      try {
        await this._applyDeletedPersonOp(ops[i]);
      } catch (error) {
        console.warn(
          "[backend] deleted persons post-write op failed",
          JSON.stringify({message: error?.message || String(error)}),
        );
        this._pendingDeletedPersonsOps.unshift(...ops.slice(i));
        return;
      }
    }
  },

  async listDeletedPersonsForUser({userId}) {
    if (!userId || typeof userId !== "string") return [];
    await this.initialize();
    if (!this._deletedPersonsTablesReady) {
      return FileStore.prototype.listDeletedPersonsForUser.call(this, {userId});
    }
    await this._awaitReadConsistency();
    // Членство семьи по-прежнему в блобе — семья-scoping (не сама корзина)
    // остаётся один _read(), как и раньше, но теперь без 245 КБ мёртвого
    // груза в каждом чтении блоба.
    const db = await this._read();
    const memberSemyaIds = new Set(
      (db.semyaMembers || [])
        .filter((m) => m.userId === userId && !m.hiddenAt)
        .map((m) => m.semyaId),
    );
    const result = await this._pool.query(
      `SELECT row_data, semya_id, deleted_by_user_id, deleted_at
         FROM ${this._qualifiedDeletedPersonsTableName}
        WHERE restored_at = ''`,
    );
    const rows = result.rows
      .filter(
        (row) =>
          row.deleted_by_user_id === userId ||
          (row.semya_id && memberSemyaIds.has(row.semya_id)),
      )
      .sort((a, b) => String(b.deleted_at || "").localeCompare(String(a.deleted_at || "")));
    return rows.map((row) => this._rowToDeletedPerson(row)).filter(Boolean);
  },

  async listDeletedPersonsForSemya({semyaId, userId}) {
    if (!semyaId || typeof semyaId !== "string") return [];
    if (!userId) return [];
    await this.initialize();
    if (!this._deletedPersonsTablesReady) {
      return FileStore.prototype.listDeletedPersonsForSemya.call(this, {semyaId, userId});
    }
    await this._awaitReadConsistency();
    const db = await this._read();
    const isMember = (db.semyaMembers || []).some(
      (m) => m.userId === userId && m.semyaId === semyaId && !m.hiddenAt,
    );
    if (!isMember) {
      throw new Error("NOT_MEMBER");
    }
    const result = await this._pool.query(
      `SELECT row_data
         FROM ${this._qualifiedDeletedPersonsTableName}
        WHERE semya_id = $1 AND restored_at = ''
        ORDER BY deleted_at DESC`,
      [semyaId],
    );
    return result.rows.map((row) => this._rowToDeletedPerson(row)).filter(Boolean);
  },

  async restorePerson({deletedPersonId, actorUserId}) {
    if (!deletedPersonId || typeof deletedPersonId !== "string") {
      throw new Error("INVALID_INPUT");
    }
    if (!actorUserId) throw new Error("INVALID_ACTOR");
    await this.initialize();
    if (!this._deletedPersonsTablesReady) {
      return FileStore.prototype.restorePerson.call(this, {deletedPersonId, actorUserId});
    }
    return this._runOnMutateQueue(async () => {
      await this._awaitReadConsistency();
      const rowResult = await this._pool.query(
        `SELECT row_data FROM ${this._qualifiedDeletedPersonsTableName} WHERE id = $1`,
        [deletedPersonId],
      );
      const row = this._rowToDeletedPerson(rowResult.rows[0]);
      if (!row) throw new Error("DELETED_PERSON_NOT_FOUND");
      if (row.restoredAt) throw new Error("ALREADY_RESTORED");
      if (
        row.hardDeleteScheduledAt &&
        Date.parse(row.hardDeleteScheduledAt) < Date.now()
      ) {
        throw new Error("HARD_DELETE_ELAPSED");
      }

      const db = await this._read();
      this._assertCanManageDeletedPerson(db, row, actorUserId, {
        requireActiveSemya: true,
      });

      const tree = (db.trees || []).find((entry) => entry.id === row.treeId);
      if (!tree) {
        throw new Error("TREE_NOT_FOUND");
      }

      db.persons = Array.isArray(db.persons) ? db.persons : [];
      db.persons.push(structuredClone(row.snapshot));
      if (Array.isArray(row.relationsSnapshot)) {
        db.relations = Array.isArray(db.relations) ? db.relations : [];
        for (const rel of row.relationsSnapshot) {
          db.relations.push(structuredClone(rel));
        }
      }

      if (row.snapshot?.userId) {
        const kickedSnapshotUser =
          tree.semyaId &&
          (db.semyaMembers || []).some(
            (m) =>
              m.semyaId === tree.semyaId &&
              m.userId === row.snapshot.userId &&
              Boolean(m.hiddenAt),
          );
        if (!kickedSnapshotUser) {
          tree.memberIds = Array.isArray(tree.memberIds) ? tree.memberIds : [];
          if (!tree.memberIds.includes(row.snapshot.userId)) {
            tree.memberIds.push(row.snapshot.userId);
          }
          tree.members = Array.isArray(tree.members) ? tree.members : [];
          if (!tree.members.includes(row.snapshot.userId)) {
            tree.members.push(row.snapshot.userId);
          }
          this._ensureSemyaMembershipForLegacyJoin(db, tree, row.snapshot.userId);
          tree.updatedAt = nowIso();
        }
      }

      const restoredAt = nowIso();
      this._appendTreeChangeRecord(db, {
        treeId: row.treeId,
        actorId: actorUserId,
        type: "person.restored",
        personId: row.originalPersonId,
        details: {
          deletedPersonId: row.id,
          deletedAt: row.deletedAt,
        },
      });
      this._reconcilePersonIdentities(db);
      ensureCirclesForTree(db, row.treeId);

      this._queueDeletedPersonOp({
        kind: "restore",
        id: deletedPersonId,
        restoredAt,
        restoredByUserId: actorUserId,
      });
      await this._write(db);
      return structuredClone({...row, restoredAt, restoredByUserId: actorUserId});
    });
  },

  async hardDeletePerson({deletedPersonId, actorUserId}) {
    if (!deletedPersonId || typeof deletedPersonId !== "string") {
      throw new Error("INVALID_INPUT");
    }
    if (!actorUserId) throw new Error("INVALID_ACTOR");
    await this.initialize();
    if (!this._deletedPersonsTablesReady) {
      return FileStore.prototype.hardDeletePerson.call(this, {deletedPersonId, actorUserId});
    }
    await this._awaitReadConsistency();
    const rowResult = await this._pool.query(
      `SELECT row_data FROM ${this._qualifiedDeletedPersonsTableName} WHERE id = $1`,
      [deletedPersonId],
    );
    const row = this._rowToDeletedPerson(rowResult.rows[0]);
    if (!row) throw new Error("DELETED_PERSON_NOT_FOUND");
    if (row.restoredAt) throw new Error("ALREADY_RESTORED");
    if (
      row.earliestHardDelete &&
      Date.parse(row.earliestHardDelete) > Date.now()
    ) {
      throw new Error("FLOOR_NOT_MET");
    }

    const db = await this._read();
    this._assertCanManageDeletedPerson(db, row, actorUserId, {
      requireActiveSemya: false,
    });

    // В отличие от FileStore (splice из блоба + полный _write) — точечный
    // DELETE, без чтения/записи всего блоба ради удаления одной корзинной
    // строки.
    await this._pool.query(
      `DELETE FROM ${this._qualifiedDeletedPersonsTableName} WHERE id = $1`,
      [deletedPersonId],
    );
    return {purged: true, deletedPersonId};
  },

  // ── SPEED-15: clientDiagnostics в таблице ───────────────────────────
  // Ring-buffer на 500 записей (34 КБ/30 записей на проде), читается ТОЛЬКО
  // /v1/admin/client-diagnostics. Append-only и никогда не участвует в
  // _mutate-applyFn — оверрайды полностью на SQL, блоб-массив после
  // миграции больше никто не пополняет (в отличие от deletedPersons здесь
  // не нужен дренаж «новых записей из унаследованного пути»).
};
