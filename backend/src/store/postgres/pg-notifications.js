const {
  quoteIdentifier,
  normalizeStateVersion,
} = require("./pool");
const {
  FileStore,
  EMPTY_DB,
  computeNotificationCoalesceKey,
  decodeNotificationCursor,
  encodeNotificationCursor,
  createNotificationRecord,
  createPushDeliveryRecord,
  normalizeDbState,
  nowIso,
} = require("../../store");

module.exports = {
  async _createNotificationTables() {
    await this._pool.query(`
      CREATE TABLE IF NOT EXISTS ${this._qualifiedNotificationBackupsTableName} (
        id TEXT PRIMARY KEY,
        backup_data JSONB NOT NULL
      )
    `);
    await this._renameIfIncompatibleTable(
      this._qualifiedNotificationsTableName,
      this._notificationsTable,
      "id",
    );
    await this._renameIfIncompatibleTable(
      this._qualifiedPushDeliveriesTableName,
      this._pushDeliveriesTable,
      "id",
    );
    await this._pool.query(`
      CREATE TABLE IF NOT EXISTS ${this._qualifiedNotificationsTableName} (
        id TEXT,
        user_id TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'generic',
        created_at TEXT NOT NULL,
        read_at TEXT NOT NULL DEFAULT '',
        silent INT NOT NULL DEFAULT 0,
        coalesce_key TEXT NOT NULL DEFAULT '',
        notification_data JSONB NOT NULL,
        CONSTRAINT ${quoteIdentifier(`${this._notificationsTable}_pk`)} PRIMARY KEY (id)
      )
    `);
    await this._pool.query(`
      CREATE INDEX IF NOT EXISTS ${quoteIdentifier(`${this._notificationsTable}_page_idx`)}
        ON ${this._qualifiedNotificationsTableName} (user_id, created_at, id)
    `);
    await this._pool.query(`
      CREATE INDEX IF NOT EXISTS ${quoteIdentifier(`${this._notificationsTable}_unread_idx`)}
        ON ${this._qualifiedNotificationsTableName} (user_id, read_at)
    `);
    // НЕ уникальный: несколько ПРОЧИТАННЫХ записей с одним ключом легальны,
    // коалесинг применяется только к непрочитанным (SELECT → UPDATE/INSERT).
    await this._pool.query(`
      CREATE INDEX IF NOT EXISTS ${quoteIdentifier(`${this._notificationsTable}_coalesce_idx`)}
        ON ${this._qualifiedNotificationsTableName} (user_id, coalesce_key)
    `);
    await this._pool.query(`
      CREATE TABLE IF NOT EXISTS ${this._qualifiedPushDeliveriesTableName} (
        id TEXT,
        notification_id TEXT NOT NULL DEFAULT '',
        user_id TEXT NOT NULL,
        device_id TEXT NOT NULL DEFAULT '',
        provider TEXT NOT NULL DEFAULT 'unknown',
        status TEXT NOT NULL DEFAULT 'queued',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        delivery_data JSONB NOT NULL,
        CONSTRAINT ${quoteIdentifier(`${this._pushDeliveriesTable}_pk`)} PRIMARY KEY (id)
      )
    `);
    await this._pool.query(`
      CREATE INDEX IF NOT EXISTS ${quoteIdentifier(`${this._pushDeliveriesTable}_user_idx`)}
        ON ${this._qualifiedPushDeliveriesTableName} (user_id, created_at)
    `);
    await this._pool.query(`
      CREATE INDEX IF NOT EXISTS ${quoteIdentifier(`${this._pushDeliveriesTable}_device_idx`)}
        ON ${this._qualifiedPushDeliveriesTableName} (device_id)
    `);
  },

  _notificationRowValues(notification) {
    const record = notification || {};
    return [
      String(record.id || "").trim(),
      String(record.userId || "").trim(),
      String(record.type || "generic").trim() || "generic",
      String(record.createdAt || "").trim(),
      String(record.readAt || "").trim(),
      record.silent === true ? 1 : 0,
      computeNotificationCoalesceKey(record),
      JSON.stringify(record),
    ];
  },

  _pushDeliveryRowValues(delivery) {
    const record = delivery || {};
    return [
      String(record.id || "").trim(),
      String(record.notificationId || "").trim(),
      String(record.userId || "").trim(),
      String(record.deviceId || "").trim(),
      String(record.provider || "unknown").trim() || "unknown",
      String(record.status || "queued").trim() || "queued",
      String(record.createdAt || "").trim(),
      String(record.updatedAt || record.createdAt || "").trim(),
      JSON.stringify(record),
    ];
  },

  // Маркер — migrationStatus.notificationsToTables; исходные массивы целиком
  // сохраняются в backup-таблицу (план отката — scripts/
  // restore-notifications-to-blob.js), после чего вычищаются из блоба.
  //
  // SPEED-9 C-boot: принимает опциональный {state, version} — уже
  // прочитанный/актуальный снимок от предыдущего шага буста (см.
  // _bootstrap()). Без аргумента — прежнее поведение, собственный SELECT
  // (защищает любой другой вызов этого метода и «БД моргнула»-тесты).
  // На успехе ВСЕГДА возвращает {state, version}, отражающий то, что
  // реально лежит в строке ПОСЛЕ этого шага — так следующий шаг в цепочке
  // не читает блоб заново.
  async _migrateNotificationCollectionsToTables(bootRow) {
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
        // Состояние недоступно (БД лежит) — общий деградированный режим, не
        // провал миграции: следующий бут повторит попытку (как SPEED-6).
        console.warn(
          "[backend] notification collections migration skipped — state unavailable",
          JSON.stringify({message: error?.message || String(error)}),
        );
        return null;
      }
    }
    try {
      if (state?.migrationStatus?.notificationsToTables === MARKER) {
        this._notificationTablesReady = true;
        return {state, version};
      }

      const notifications = Array.isArray(state.notifications)
        ? state.notifications
        : [];
      const pushDeliveries = Array.isArray(state.pushDeliveries)
        ? state.pushDeliveries
        : [];

      await this._pool.query(
        `INSERT INTO ${this._qualifiedNotificationBackupsTableName} (id, backup_data)
         VALUES ($1, $2::jsonb)
         ON CONFLICT (id) DO NOTHING`,
        [
          `pre-migration-${MARKER}`,
          JSON.stringify({
            savedAt: nowIso(),
            notifications,
            pushDeliveries,
          }),
        ],
      );

      let skippedNotifications = 0;
      for (const notification of notifications) {
        const rowValues = this._notificationRowValues(notification);
        if (!rowValues[0] || !rowValues[1] || !rowValues[3]) {
          // Без id/userId/createdAt запись не адресуема ни одним
          // рантайм-путём — оставляем только в бэкапе.
          skippedNotifications += 1;
          continue;
        }
        await this._pool.query(
          `INSERT INTO ${this._qualifiedNotificationsTableName}
             (id, user_id, type, created_at, read_at, silent, coalesce_key, notification_data)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb)
           ON CONFLICT DO NOTHING`,
          rowValues,
        );
      }
      let skippedDeliveries = 0;
      for (const delivery of pushDeliveries) {
        const rowValues = this._pushDeliveryRowValues(delivery);
        if (!rowValues[0] || !rowValues[2] || !rowValues[6]) {
          skippedDeliveries += 1;
          continue;
        }
        await this._pool.query(
          `INSERT INTO ${this._qualifiedPushDeliveriesTableName}
             (id, notification_id, user_id, device_id, provider, status, created_at, updated_at, delivery_data)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb)
           ON CONFLICT DO NOTHING`,
          rowValues,
        );
      }

      const nextState = {
        ...state,
        notifications: [],
        pushDeliveries: [],
        migrationStatus: {
          ...(state.migrationStatus || {}),
          notificationsToTables: MARKER,
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
      // Sidecar-кэш обязан пережить границу миграции (см. SPEED-6): иначе
      // fallback-чтение воскресит домиграционный блоб без маркера.
      await this._persistSnapshotCache(this._cachedState);
      this._notificationTablesReady = true;
      console.log(
        "[backend] notification collections migrated to tables",
        JSON.stringify({
          notifications: notifications.length,
          pushDeliveries: pushDeliveries.length,
          skipped: {
            notifications: skippedNotifications,
            pushDeliveries: skippedDeliveries,
          },
        }),
      );
      return {
        state: this._cachedState,
        version: normalizeStateVersion(
          updateResult?.rows?.[0]?.version,
        ),
      };
    } catch (error) {
      // Оверрайды читают ТОЛЬКО таблицы — старт с недомигрированными данными
      // означал бы split-brain. Роняем бут (как SPEED-6).
      console.error(
        "[backend] notification collections migration FAILED — refusing to serve",
        JSON.stringify({message: error?.message || String(error)}),
      );
      throw error;
    }
  },

  // Маркер — migrationStatus.chatCollectionsToTables в самом блобе; исходные
  // массивы целиком сохраняются в backup-таблицу (план отката — scripts/
  // restore-chat-collections-to-blob.js), после чего вычищаются из блоба.
  // chatId сообщений канонизируется (a_b с сортировкой) прямо при переносе,
  // чтобы рантайм-запросы работали по одному id вместо alias-набора.
  //
  // SPEED-9 C-boot: опциональный {state, version} от предыдущего шага
  // буста — без него прежнее поведение (собственный SELECT). На успехе
  // возвращает {state, version}, отражающий строку ПОСЛЕ этого шага.
  async listPushDevices(userId) {
    const normalizedUserId = String(userId || "").trim();
    if (!normalizedUserId) {
      return [];
    }
    await this.initialize();
    await this._awaitReadConsistency();
    try {
      return await this._selectPushDevicesForUser(normalizedUserId);
    } catch (error) {
      // Движок без jsonb_array_elements (pg-mem в тестах) или иная
      // неожиданность — падать на пути доставки пуша нельзя: честный
      // фолбэк на медленное, но верное чтение блоба.
      console.warn(
        "[backend] push devices SQL read failed — falling back to blob",
        JSON.stringify({message: error?.message || String(error)}),
      );
      return FileStore.prototype.listPushDevices.call(this, userId);
    }
  },

  async _selectPushDevicesForUser(normalizedUserId) {
    const result = await this._pool.query(
      // Развёртка массива — в подзапросе, а не LATERAL: pg-mem не
      // резолвит внешнюю колонку внутри LATERAL, а такая форма работает
      // и на нём, и на реальном Postgres (значит путь покрыт тестом).
      `SELECT device_entry AS device_data
         FROM (
           SELECT jsonb_array_elements(
                    COALESCE(data->'pushDevices', '[]'::jsonb)
                  ) AS device_entry
             FROM ${this._qualifiedTableName}
            WHERE id = $1
         ) AS devices
        WHERE COALESCE(device_entry->>'userId', '') = $2
        ORDER BY COALESCE(device_entry->>'updatedAt', '') DESC`,
      [this._rowId, normalizedUserId],
    );
    return result.rows
      .map((row) => {
        const record = row.device_data;
        if (!record) return null;
        return typeof record === "string" ? JSON.parse(record) : record;
      })
      .filter(Boolean);
  },

  // ── SPEED-7: notifications/pushDeliveries поверх таблиц ─────────────
  // После бут-миграции блоб этих коллекций не содержит; блоб-массивы —
  // «транзитная очередь» для унаследованных inline-путей (_notifyReviewers,
  // article_block_conflict), которую _write дренирует в таблицы.

  _rowToNotification(row) {
    const record = row?.notification_data;
    if (!record) {
      return null;
    }
    const parsed = typeof record === "string" ? JSON.parse(record) : record;
    // Колонка read_at — источник истины прочитанности: массовые пометки
    // обновляют ТОЛЬКО её (не перезаписывая notification_data, чтобы не
    // затирать конкурентный коалесинг-бамп — ревью, P1). Здесь колонка
    // доводится в JSONB-представление, если SELECT её принёс.
    const columnReadAt =
      row.read_at !== undefined ? String(row.read_at || "") : "";
    if (columnReadAt !== "" && !parsed.readAt) {
      parsed.readAt = columnReadAt;
    }
    return parsed;
  },

  async createNotification({userId, type, title, body, data, silent = false}) {
    await this.initialize();
    if (!this._notificationTablesReady) {
      return FileStore.prototype.createNotification.call(this, {userId, type, title, body, data, silent});
    }
    const user = await this.findUserById(userId);
    if (!user) {
      return null;
    }
    const notification = createNotificationRecord({
      userId,
      type,
      title,
      body,
      data,
      silent,
    });
    await this._pool.query(
      `INSERT INTO ${this._qualifiedNotificationsTableName}
         (id, user_id, type, created_at, read_at, silent, coalesce_key, notification_data)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb)`,
      this._notificationRowValues(notification),
    );
    // TOCTOU с deleteUser (ревью, P2): в FileStore проверка юзера и вставка
    // атомарны внутри _mutate; здесь между findUserById и INSERT юзера могли
    // удалить — компенсирующая перепроверка убирает свежую сироту.
    const userStillExists = await this.findUserById(userId);
    if (!userStillExists) {
      await this._pool.query(
        `DELETE FROM ${this._qualifiedNotificationsTableName} WHERE id = $1`,
        [notification.id],
      );
      return null;
    }
    return structuredClone(notification);
  },

  async listNotifications(userId, {status = null, limit = 50} = {}) {
    const normalizedUserId = String(userId || "").trim();
    if (!normalizedUserId) {
      return [];
    }
    const normalizedLimit = Number.isFinite(Number(limit))
      ? Math.max(0, Math.floor(Number(limit)))
      : 50;
    if (normalizedLimit === 0) {
      return [];
    }
    const normalizedStatus = String(status || "").trim().toLowerCase();
    await this.initialize();
    if (!this._notificationTablesReady) {
      return FileStore.prototype.listNotifications.call(this, userId, {status, limit});
    }
    await this._awaitReadConsistency();
    const result = await this._pool.query(
      `SELECT notification_data, read_at
         FROM ${this._qualifiedNotificationsTableName}
        WHERE user_id = $1
          AND (
            $2 = ''
            OR ($2 = 'unread' AND read_at = '')
            OR ($2 = 'read' AND read_at <> '')
          )
        ORDER BY created_at DESC, id DESC
        LIMIT $3`,
      [normalizedUserId, normalizedStatus, normalizedLimit],
    );
    return result.rows
      .map((row) => this._rowToNotification(row))
      .filter(Boolean);
  },

  async countUnreadNotifications(userId) {
    const normalizedUserId = String(userId || "").trim();
    if (!normalizedUserId) {
      return 0;
    }
    await this.initialize();
    if (!this._notificationTablesReady) {
      return FileStore.prototype.countUnreadNotifications.call(this, userId);
    }
    await this._awaitReadConsistency();
    const result = await this._pool.query(
      `SELECT COUNT(*)::int AS total
         FROM ${this._qualifiedNotificationsTableName}
        WHERE user_id = $1
          AND read_at = ''`,
      [normalizedUserId],
    );
    return Number(result.rows[0]?.total || 0);
  },

  async markNotificationRead(notificationId, userId) {
    const normalizedId = String(notificationId || "").trim();
    const normalizedUserId = String(userId || "").trim();
    if (!normalizedId || !normalizedUserId) {
      return null;
    }
    await this.initialize();
    if (!this._notificationTablesReady) {
      return FileStore.prototype.markNotificationRead.call(this, notificationId, userId);
    }
    await this._awaitReadConsistency();
    const result = await this._pool.query(
      `SELECT notification_data, read_at
         FROM ${this._qualifiedNotificationsTableName}
        WHERE id = $1 AND user_id = $2
        LIMIT 1`,
      [normalizedId, normalizedUserId],
    );
    const row = result.rows[0];
    if (!row) {
      return null;
    }
    const notification = this._rowToNotification(row);
    if (String(row.read_at || "") !== "") {
      // Уже прочитано — как FileStore: вернуть запись без повторной записи.
      return structuredClone(notification);
    }
    notification.readAt = nowIso();
    await this._pool.query(
      `UPDATE ${this._qualifiedNotificationsTableName}
          SET read_at = $2,
              notification_data = $3::jsonb
        WHERE id = $1`,
      [normalizedId, notification.readAt, JSON.stringify(notification)],
    );
    return structuredClone(notification);
  },

  async markNotificationsReadByDataKey({
    userId,
    dataKey,
    dataValue,
    types = null,
  }) {
    if (!userId || !dataKey) return 0;
    const normalizedUserId = String(userId).trim();
    const normalizedValue = dataValue == null ? null : String(dataValue);
    const typeFilter = Array.isArray(types) && types.length > 0
      ? new Set(types.map((entry) => String(entry)))
      : null;
    await this.initialize();
    if (!this._notificationTablesReady) {
      return FileStore.prototype.markNotificationsReadByDataKey.call(this, {userId, dataKey, dataValue, types});
    }
    await this._awaitReadConsistency();
    // data-фильтр — в JS по полной записи (byte-parity с FileStore, без
    // jsonb-путей в WHERE — pg-mem их поддерживает выборочно).
    const result = await this._pool.query(
      `SELECT id, notification_data
         FROM ${this._qualifiedNotificationsTableName}
        WHERE user_id = $1
          AND read_at = ''`,
      [normalizedUserId],
    );
    const now = nowIso();
    let markedCount = 0;
    for (const row of result.rows) {
      const notification = this._rowToNotification(row);
      if (!notification) continue;
      if (typeFilter && !typeFilter.has(String(notification.type || ""))) {
        continue;
      }
      const data = notification.data || {};
      const candidate = data[dataKey];
      if (candidate == null) continue;
      if (String(candidate) !== normalizedValue) continue;
      notification.readAt = now;
      await this._pool.query(
        `UPDATE ${this._qualifiedNotificationsTableName}
            SET read_at = $2,
                notification_data = $3::jsonb
          WHERE id = $1`,
        [String(row.id), now, JSON.stringify(notification)],
      );
      markedCount += 1;
    }
    return markedCount;
  },

  async markAllNotificationsRead(userId) {
    const normalizedUserId = String(userId || "").trim();
    if (!normalizedUserId) return 0;
    await this.initialize();
    if (!this._notificationTablesReady) {
      return FileStore.prototype.markAllNotificationsRead.call(this, userId);
    }
    await this._awaitReadConsistency();
    // ОДИН UPDATE только колонки read_at: перезапись notification_data из
    // JS-снапшота затирала бы конкурентный коалесинг-бамп (ревью, P1) —
    // JSONB доводится колонкой в _rowToNotification при чтении.
    const result = await this._pool.query(
      `UPDATE ${this._qualifiedNotificationsTableName}
          SET read_at = $2
        WHERE user_id = $1
          AND read_at = ''
        RETURNING id`,
      [normalizedUserId, nowIso()],
    );
    return result.rows.length;
  },

  async listNotificationsPage(userId, {status = null, limit = 50, cursor = null} = {}) {
    const normalizedUserId = String(userId || "").trim();
    const normalizedLimit = Math.min(
      200,
      Math.max(1, Math.floor(Number(limit) || 50)),
    );
    if (!normalizedUserId) {
      return {notifications: [], nextCursor: null};
    }
    await this.initialize();
    if (!this._notificationTablesReady) {
      return FileStore.prototype.listNotificationsPage.call(this, userId, {status, limit, cursor});
    }
    await this._awaitReadConsistency();
    const normalizedStatus = String(status || "").trim().toLowerCase();
    const decodedCursor = decodeNotificationCursor(cursor);
    // Keyset вместо OFFSET; кортежное сравнение разложено в OR — pg-mem
    // row-value сравнения не поддерживает.
    const params = [normalizedUserId, normalizedStatus, normalizedLimit + 1];
    let cursorClause = "";
    if (decodedCursor) {
      params.push(decodedCursor.createdAt, decodedCursor.id);
      cursorClause = `AND (created_at < $4 OR (created_at = $4 AND id < $5))`;
    }
    const result = await this._pool.query(
      `SELECT notification_data, read_at
         FROM ${this._qualifiedNotificationsTableName}
        WHERE user_id = $1
          AND (
            $2 = ''
            OR ($2 = 'unread' AND read_at = '')
            OR ($2 = 'read' AND read_at <> '')
          )
          ${cursorClause}
        ORDER BY created_at DESC, id DESC
        LIMIT $3`,
      params,
    );
    const rows = result.rows
      .map((row) => this._rowToNotification(row))
      .filter(Boolean);
    const hasMore = rows.length > normalizedLimit;
    const pageItems = hasMore ? rows.slice(0, normalizedLimit) : rows;
    const last = pageItems[pageItems.length - 1];
    return {
      notifications: pageItems,
      nextCursor:
        hasMore && last
          ? encodeNotificationCursor(String(last.createdAt || ""), String(last.id || ""))
          : null,
    };
  },

  /// Табличная реализация коалесинга (движок планов из store.js): hit по
  /// (user_id, coalesce_key) среди unread → бамп, miss → INSERT. Гонка двух
  /// конкурентных реакций может дать дубль вместо бампа — как и у прежних
  /// голых _read/_write пар; не хуже (см. дизайн-док, «намеренные отличия»).
  async _applyNotificationCoalescePlan(plan) {
    if (!plan) {
      return null;
    }
    await this.initialize();
    if (!this._notificationTablesReady) {
      return FileStore.prototype._applyNotificationCoalescePlan.call(this, plan);
    }
    const coalesceKey = computeNotificationCoalesceKey({
      type: plan.type,
      data: plan.keyData,
    });
    const existingResult = await this._pool.query(
      `SELECT id, notification_data
         FROM ${this._qualifiedNotificationsTableName}
        WHERE user_id = $1
          AND coalesce_key = $2
          AND read_at = ''
        ORDER BY created_at DESC, id DESC
        LIMIT 1`,
      [String(plan.userId || "").trim(), coalesceKey],
    );
    const existingRow = existingResult.rows[0];
    if (existingRow) {
      const existing = this._rowToNotification(existingRow);
      plan.patchExisting(existing);
      existing.createdAt = nowIso();
      existing.readAt = null;
      const updated = await this._pool.query(
        `UPDATE ${this._qualifiedNotificationsTableName}
            SET created_at = $2,
                read_at = '',
                notification_data = $3::jsonb
          WHERE id = $1
            AND read_at = ''`,
        [String(existingRow.id), existing.createdAt, JSON.stringify(existing)],
      );
      // Гвард read_at='': конкурентный markNotificationRead успел пометить
      // запись прочитанной между SELECT и UPDATE — бамп не должен тихо
      // «распрочитывать» её (ревью, P2). 0 строк → падаем в miss-ветку:
      // «после прочтения — новая запись».
      if (Number(updated.rowCount || 0) > 0) {
        return structuredClone(existing);
      }
    }
    const notification = plan.buildRecord();
    await this._pool.query(
      `INSERT INTO ${this._qualifiedNotificationsTableName}
         (id, user_id, type, created_at, read_at, silent, coalesce_key, notification_data)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb)
       ON CONFLICT DO NOTHING`,
      this._notificationRowValues(notification),
    );
    return structuredClone(notification);
  },

  async createPushDelivery({
    notificationId,
    userId,
    deviceId,
    provider,
    status = "queued",
  }) {
    await this.initialize();
    if (!this._notificationTablesReady) {
      return FileStore.prototype.createPushDelivery.call(this, {notificationId, userId, deviceId, provider, status});
    }
    const delivery = createPushDeliveryRecord({
      notificationId,
      userId,
      deviceId,
      provider,
      status,
    });
    await this._pool.query(
      `INSERT INTO ${this._qualifiedPushDeliveriesTableName}
         (id, notification_id, user_id, device_id, provider, status, created_at, updated_at, delivery_data)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb)`,
      this._pushDeliveryRowValues(delivery),
    );
    return structuredClone(delivery);
  },

  async listPushDeliveries(userId, {limit = 50} = {}) {
    const normalizedUserId = String(userId || "").trim();
    if (!normalizedUserId) {
      return [];
    }
    await this.initialize();
    if (!this._notificationTablesReady) {
      return FileStore.prototype.listPushDeliveries.call(this, userId, {limit});
    }
    await this._awaitReadConsistency();
    const result = await this._pool.query(
      `SELECT delivery_data
         FROM ${this._qualifiedPushDeliveriesTableName}
        WHERE user_id = $1
        ORDER BY created_at DESC, id DESC
        LIMIT $2`,
      [normalizedUserId, Math.max(0, Math.floor(Number(limit) || 50))],
    );
    return result.rows
      .map((row) => {
        const record = row?.delivery_data;
        if (!record) return null;
        return typeof record === "string" ? JSON.parse(record) : record;
      })
      .filter(Boolean);
  },

  async updatePushDelivery(
    deliveryId,
    {status, deliveredAt, lastError, responseCode} = {},
  ) {
    const normalizedId = String(deliveryId || "").trim();
    if (!normalizedId) {
      return null;
    }
    await this.initialize();
    if (!this._notificationTablesReady) {
      return FileStore.prototype.updatePushDelivery.call(this, deliveryId, {status, deliveredAt, lastError, responseCode});
    }
    const result = await this._pool.query(
      `SELECT delivery_data
         FROM ${this._qualifiedPushDeliveriesTableName}
        WHERE id = $1
        LIMIT 1`,
      [normalizedId],
    );
    const rawRecord = result.rows[0]?.delivery_data;
    if (!rawRecord) {
      return null;
    }
    const delivery =
      typeof rawRecord === "string" ? JSON.parse(rawRecord) : rawRecord;
    if (status !== undefined) {
      delivery.status = String(status || delivery.status).trim();
    }
    if (deliveredAt !== undefined) {
      delivery.deliveredAt = deliveredAt || null;
    }
    if (lastError !== undefined) {
      delivery.lastError = lastError ? String(lastError) : null;
    }
    if (responseCode !== undefined) {
      const normalizedCode = Number(responseCode);
      delivery.responseCode = Number.isFinite(normalizedCode)
        ? normalizedCode
        : null;
    }
    delivery.updatedAt = nowIso();
    await this._pool.query(
      `UPDATE ${this._qualifiedPushDeliveriesTableName}
          SET status = $2,
              updated_at = $3,
              delivery_data = $4::jsonb
        WHERE id = $1`,
      [
        normalizedId,
        String(delivery.status || "queued"),
        delivery.updatedAt,
        JSON.stringify(delivery),
      ],
    );
    return structuredClone(delivery);
  },

  /// Drain «транзитной очереди»: унаследованные FileStore-пути, пушащие в
  /// db.notifications/db.pushDeliveries внутри своих applyFn/голых write'ов
  /// (_notifyReviewers, article_block_conflict, будущие), доезжают в таблицы
  /// здесь. Для типов с coalesce-ключом hit по unread = skip (семантика
  /// `continue` в _notifyReviewers). Возвращает состояние с пустыми
  /// транзит-массивами — в блоб и кэш они не попадают.

  // ── SPEED-8b: журнал изменений дерева + аудит hard-delete ─────────────
  // treeChangeRecords (журнал «история дерева», 1.5 МБ текста на проде) и
  // hardDeleteAudit — append-only коллекции, которые никто не читает внутри
  // _mutate-applyFn. Записи рождаются в блобе (db.treeChangeRecords.push из
  // мутаций FileStore) и на _write дренируются в таблицу; правки старых
  // записей (слияние дублей, псевдонимизация, ретенция) — хуки FileStore,
  // которые здесь ставят табличную операцию в очередь; _write применяет её
  // после UPSERT. NULL-колонок нет (pg-mem): пустая строка = null.
  async _drainTransientNotificationCollections(data) {
    if (!this._notificationTablesReady) {
      // До подтверждённой миграции блоб — единственный источник правды.
      return data;
    }
    const notifications = Array.isArray(data?.notifications)
      ? data.notifications
      : [];
    const pushDeliveries = Array.isArray(data?.pushDeliveries)
      ? data.pushDeliveries
      : [];
    if (notifications.length === 0 && pushDeliveries.length === 0) {
      return data;
    }
    try {
    for (const notification of notifications) {
      const rowValues = this._notificationRowValues(notification);
      if (!rowValues[0] || !rowValues[1] || !rowValues[3]) {
        continue;
      }
      const coalesceKey = rowValues[6];
      if (coalesceKey) {
        const existing = await this._pool.query(
          `SELECT id
             FROM ${this._qualifiedNotificationsTableName}
            WHERE user_id = $1
              AND coalesce_key = $2
              AND read_at = ''
            LIMIT 1`,
          [rowValues[1], coalesceKey],
        );
        if (existing.rows[0]) {
          continue;
        }
      }
      await this._pool.query(
        `INSERT INTO ${this._qualifiedNotificationsTableName}
           (id, user_id, type, created_at, read_at, silent, coalesce_key, notification_data)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb)
         ON CONFLICT DO NOTHING`,
        rowValues,
      );
    }
    for (const delivery of pushDeliveries) {
      const rowValues = this._pushDeliveryRowValues(delivery);
      if (!rowValues[0] || !rowValues[2] || !rowValues[6]) {
        continue;
      }
      await this._pool.query(
        `INSERT INTO ${this._qualifiedPushDeliveriesTableName}
           (id, notification_id, user_id, device_id, provider, status, created_at, updated_at, delivery_data)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb)
         ON CONFLICT DO NOTHING`,
        rowValues,
      );
    }
    } catch (error) {
      // Best-effort: сбой INSERT'а уведомления не должен ронять бизнес-
      // мутацию, которая его породила. Транзит НЕ обнуляем — блоб запишется
      // с массивами, следующий _write повторит drain (дедуп по id).
      console.warn(
        "[backend] notification drain failed — keeping transit in blob",
        JSON.stringify({message: error?.message || String(error)}),
      );
      return data;
    }
    return {...data, notifications: [], pushDeliveries: []};
  },

  // ── SPEED-6: чат-методы поверх таблиц ────────────────────────────────
  // Сообщения/реакции/черновики/пины читаются и пишутся ТОЛЬКО в таблицах
  // (после бут-миграции блоб их не содержит), записи чатов — из
  // projection-таблицы (источник истины — блоб, синк по хэшу в _write).
  // Семантика 1-в-1 повторяет FileStore-методы store.js; про намеренные
  // отличия — docs/speed6_messages_table_design.md.

};
