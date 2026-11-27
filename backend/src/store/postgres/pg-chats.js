const crypto = require("node:crypto");
const {
  isProjectionHydrationFallbackError,
  isProjectionArrayTextFallbackError,
  computeProjectionHash,
  quoteIdentifier,
  normalizeStateVersion,
} = require("./pool");
const {
  FileStore,
  EMPTY_DB,
  buildChatSearchSnippet,
  chatMessageSearchHaystack,
  createChatDraftRecord,
  createChatPinRecord,
  describeMessagePreview,
  normalizeChatMessageCall,
  normalizeChatSearchQuery,
  normalizeDbState,
  normalizeNullableString,
  normalizeOptionalIsoTimestamp,
  normalizeParticipantIds,
  normalizeReactionEmoji,
  nowIso,
  parseDirectParticipantsFromChatId,
} = require("../../store");
const {
  normalizeMessageAttachments,
  normalizeReplyReference,
} = require("../../chat-utils");

module.exports = {
  // ── SPEED-6: чат-таблицы ─────────────────────────────────────────────
  // Сообщения/реакции/черновики/пины уезжают из JSONB-блоба в таблицы:
  // отправка = один INSERT вне глобальной _mutateQueue, история — индексная
  // страница, dedup — уникальный индекс. Записи ЧАТОВ остаются в блобе
  // (звонки, deleteUser, merge персон читают их внутри _mutate-applyFn),
  // но зеркалятся в projection-таблицу — access-check на send-пути стал
  // индексным SELECT вместо чтения всего блоба.
  async _createChatTables() {
    await this._pool.query(`
      CREATE TABLE IF NOT EXISTS ${this._qualifiedChatMessagesTableName} (
        id TEXT PRIMARY KEY,
        chat_id TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        ts TEXT NOT NULL,
        client_message_id TEXT NOT NULL DEFAULT '',
        expires_at TEXT NOT NULL DEFAULT '',
        haystack TEXT NOT NULL DEFAULT '',
        dedup_key TEXT NOT NULL,
        message_data JSONB NOT NULL
      )
    `);
    await this._pool.query(`
      CREATE INDEX IF NOT EXISTS ${quoteIdentifier(`${this._chatMessagesTable}_page_idx`)}
        ON ${this._qualifiedChatMessagesTableName} (chat_id, ts, id)
    `);
    await this._pool.query(`
      CREATE INDEX IF NOT EXISTS ${quoteIdentifier(`${this._chatMessagesTable}_sender_idx`)}
        ON ${this._qualifiedChatMessagesTableName} (sender_id)
    `);
    // Жёсткая гарантия dedup по (chatId, senderId, clientMessageId):
    // dedup_key = "chat|sender|clientMessageId" для сообщений с client-id,
    // иначе просто id строки (уникален сам по себе). Полный (не партиальный)
    // уникальный индекс — партиальные индексы ломают pg-mem, а вычисляемый
    // ключ переносим на любой движок.
    await this._pool.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS ${quoteIdentifier(`${this._chatMessagesTable}_dedup_idx`)}
        ON ${this._qualifiedChatMessagesTableName} (dedup_key)
    `);
    await this._pool.query(`
      CREATE INDEX IF NOT EXISTS ${quoteIdentifier(`${this._chatMessagesTable}_expires_idx`)}
        ON ${this._qualifiedChatMessagesTableName} (expires_at)
    `);
    await this._pool.query(`
      CREATE TABLE IF NOT EXISTS ${this._qualifiedChatReactionsTableName} (
        message_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        emoji TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (message_id, user_id, emoji)
      )
    `);
    await this._pool.query(`
      CREATE TABLE IF NOT EXISTS ${this._qualifiedChatDraftsTableName} (
        user_id TEXT NOT NULL,
        chat_id TEXT NOT NULL,
        draft_data JSONB NOT NULL,
        PRIMARY KEY (user_id, chat_id)
      )
    `);
    await this._pool.query(`
      CREATE TABLE IF NOT EXISTS ${this._qualifiedChatPinsTableName} (
        chat_id TEXT PRIMARY KEY,
        message_id TEXT NOT NULL,
        pin_data JSONB NOT NULL
      )
    `);
    await this._pool.query(`
      CREATE TABLE IF NOT EXISTS ${this._qualifiedChatsProjectionTableName} (
        id TEXT PRIMARY KEY,
        chat_data JSONB NOT NULL
      )
    `);
    await this._pool.query(`
      CREATE TABLE IF NOT EXISTS ${this._qualifiedChatParticipantsTableName} (
        chat_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        PRIMARY KEY (chat_id, user_id)
      )
    `);
    await this._pool.query(`
      CREATE INDEX IF NOT EXISTS ${quoteIdentifier(`${this._chatParticipantsTable}_user_idx`)}
        ON ${this._qualifiedChatParticipantsTableName} (user_id)
    `);
    await this._pool.query(`
      CREATE TABLE IF NOT EXISTS ${this._qualifiedChatBackupsTableName} (
        id TEXT PRIMARY KEY,
        backup_data JSONB NOT NULL
      )
    `);
  },

  _canonicalChatIdFor(chatId) {
    const normalized = String(chatId || "").trim();
    const directParticipants = parseDirectParticipantsFromChatId(normalized);
    return directParticipants.length === 2
      ? directParticipants.join("_")
      : normalized;
  },

  _equivalentChatIdList(chatId, resolvedChatId = null) {
    const ids = new Set();
    const normalized = String(chatId || "").trim();
    if (normalized) {
      ids.add(normalized);
    }
    const canonical = this._canonicalChatIdFor(normalized);
    if (canonical) {
      ids.add(canonical);
    }
    const resolved = String(resolvedChatId || "").trim();
    if (resolved) {
      ids.add(resolved);
    }
    return Array.from(ids);
  },

  _chatMessageRowValues(message) {
    const id = String(message?.id || "").trim();
    const chatId = String(message?.chatId || "").trim();
    const senderId = String(message?.senderId || "").trim();
    const clientMessageId = normalizeNullableString(message?.clientMessageId) || "";
    const dedupKey = clientMessageId
      ? `${chatId}|${senderId}|${clientMessageId}`
      : id;
    return [
      id,
      chatId,
      senderId,
      String(message?.timestamp || "").trim(),
      clientMessageId,
      normalizeOptionalIsoTimestamp(message?.expiresAt) || "",
      // Переводы строк из haystack схлопываем в пробелы: семантика поиска
      // (подстрока в пределах терма) не меняется, а LIKE-движки (в т.ч.
      // pg-mem) не спотыкаются о многострочность.
      chatMessageSearchHaystack(message).replace(/\s+/g, " "),
      dedupKey,
      JSON.stringify(message),
    ];
  },

  async _insertChatMessageRow(message) {
    await this._pool.query(
      `INSERT INTO ${this._qualifiedChatMessagesTableName}
         (id, chat_id, sender_id, ts, client_message_id, expires_at, haystack, dedup_key, message_data)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb)`,
      this._chatMessageRowValues(message),
    );
  },

  // Receipt/edit-пути делают SELECT→изменение→полная перезапись message_data.
  // В FileStore их сериализовала глобальная _mutateQueue; здесь — узкая
  // очередь ТОЛЬКО для таких RMW строк сообщений (два конкурентных
  // delivered-ack'а иначе теряют друг друга). Отправка (чистый INSERT) в
  // очереди не участвует — ack-путь остаётся неблокирующим.
  _enqueueChatRowMutation(operation) {
    this._chatRowMutationQueue = (this._chatRowMutationQueue || Promise.resolve())
      .then(operation, operation);
    return this._chatRowMutationQueue;
  },

  async _updateChatMessageRow(message) {
    const values = this._chatMessageRowValues(message);
    await this._pool.query(
      `UPDATE ${this._qualifiedChatMessagesTableName}
          SET chat_id = $2,
              sender_id = $3,
              ts = $4,
              client_message_id = $5,
              expires_at = $6,
              haystack = $7,
              dedup_key = $8,
              message_data = $9::jsonb
        WHERE id = $1`,
      values,
    );
  },

  // Одноразовая (идемпотентная) миграция чат-коллекций из блоба в таблицы.
  // ── SPEED-7: notifications + pushDeliveries ──────────────────────────
  // Обе коллекции — только-пишущие с точки зрения чужих _mutate-applyFn
  // (никто их не читает внутри applyFn), поэтому в отличие от чатов их можно
  // вынести целиком, без projection. NULL-колонок нет (pg-mem не дружит с
  // параметризованным NULL): read_at='' = непрочитано, silent 0/1.
  /// Находка репетиции на прод-дампе: на проде с апреля 2026 живёт
  /// таблица rodnya_state_notifications СТАРОЙ схемы (notification_id PK,
  /// без type/silent/coalesce_key) — артефакт раннего эксперимента, никем
  /// не читается (актуальные уведомления жили в блобе). CREATE IF NOT
  /// EXISTS молча пропускал создание, а CREATE INDEX падал на
  /// несуществующей колонке id и валил бут. Несовместимую таблицу
  /// переименовываем (сохраняем, не дропаем) и создаём заново.
  // PK-констрейнты новых таблиц имеют ЯВНЫЕ имена (<t>_pk, не дефолтный
  // _pkey): после эвакуации+DROP легаси-таблицы pg-mem (а потенциально и
  // осиротевшие объекты на реальном PG) держат старое имя «..._pkey».
  async _renameIfIncompatibleTable(qualifiedName, bareName, probeColumn) {
    try {
      await this._pool.query(
        `SELECT ${probeColumn} FROM ${qualifiedName} LIMIT 1`,
      );
      return; // таблица есть и совместима
    } catch (error) {
      const message = String(error?.message || "").toLowerCase();
      const isColumnMismatch =
        error?.code === "42703" ||
        (message.includes("column") && message.includes("does not exist"));
      if (!isColumnMismatch) {
        // Таблицы нет (или иная причина) — CREATE IF NOT EXISTS разберётся.
        return;
      }
    }
    // Эвакуация содержимого в backup-таблицу + DROP. Не RENAME (тянет имя
    // PK-констрейнта — CREATE новой таблицы падает на «_pkey already
    // exists») и не CTAS (pg-mem его не парсит): только простые операции.
    console.warn(
      "[backend] incompatible legacy table evacuated before SPEED-7 DDL",
      JSON.stringify({table: bareName}),
    );
    const legacyRows = await this._pool.query(
      `SELECT * FROM ${qualifiedName}`,
    );
    await this._pool.query(
      `INSERT INTO ${this._qualifiedNotificationBackupsTableName} (id, backup_data)
       VALUES ($1, $2::jsonb)
       ON CONFLICT (id) DO NOTHING`,
      [
        `legacy-table-${bareName}`,
        JSON.stringify({savedAt: nowIso(), rows: legacyRows.rows}),
      ],
    );
    await this._pool.query(`DROP TABLE ${qualifiedName}`);
  },

  async _migrateChatCollectionsToTables(bootRow) {
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
        // Состояние недоступно (БД лежит) — это не «миграция сломалась», а
        // общий деградированный режим: _read будет сервить sidecar-кэш, а
        // табличные чат-методы честно упадут той же ошибкой соединения.
        // Следующий бут повторит попытку.
        console.warn(
          "[backend] chat collections migration skipped — state unavailable",
          JSON.stringify({message: error?.message || String(error)}),
        );
        return null;
      }
    }
    try {
      if (state?.migrationStatus?.chatCollectionsToTables === MARKER) {
        return {state, version};
      }

      const messages = Array.isArray(state.messages) ? state.messages : [];
      const reactions = Array.isArray(state.messageReactions)
        ? state.messageReactions
        : [];
      const drafts = Array.isArray(state.chatDrafts) ? state.chatDrafts : [];
      const pins = Array.isArray(state.chatPins) ? state.chatPins : [];

      await this._pool.query(
        `INSERT INTO ${this._qualifiedChatBackupsTableName} (id, backup_data)
         VALUES ($1, $2::jsonb)
         ON CONFLICT (id) DO NOTHING`,
        [
          `pre-migration-${MARKER}`,
          JSON.stringify({
            savedAt: nowIso(),
            messages,
            messageReactions: reactions,
            chatDrafts: drafts,
            chatPins: pins,
          }),
        ],
      );

      // Канонизировать можно ТОЛЬКО настоящие direct-alias'ы: id групповых
      // и branch-чатов (`chat_<uuid>`) тоже парсится на 2 части и сортировка
      // переставила бы их местами, оторвав сообщения от чата. Правило: id
      // сохранённого чата не трогаем, id с префиксом chat_ не трогаем.
      const storedChatIds = new Set(
        (Array.isArray(state.chats) ? state.chats : [])
          .map((chat) => String(chat?.id || "").trim())
          .filter(Boolean),
      );
      const canonicalizeMigratedChatId = (rawChatId) => {
        const normalized = String(rawChatId || "").trim();
        if (storedChatIds.has(normalized) || normalized.startsWith("chat_")) {
          return normalized;
        }
        return this._canonicalChatIdFor(normalized);
      };

      const seenMessageIds = new Set();
      let skippedMessages = 0;
      for (const message of messages) {
        const messageId = String(message?.id || "").trim();
        if (!messageId || seenMessageIds.has(messageId)) {
          skippedMessages += 1;
          continue;
        }
        seenMessageIds.add(messageId);
        const canonicalMessage = {
          ...message,
          chatId: canonicalizeMigratedChatId(message?.chatId),
        };
        // Targetless ON CONFLICT: легаси-дубликат по dedup_key (одинаковый
        // clientMessageId в раздельных когда-то alias-чатах) не должен
        // ронять бут — молча оставляем первый, остальное есть в бэкапе.
        await this._pool.query(
          `INSERT INTO ${this._qualifiedChatMessagesTableName}
             (id, chat_id, sender_id, ts, client_message_id, expires_at, haystack, dedup_key, message_data)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb)
           ON CONFLICT DO NOTHING`,
          this._chatMessageRowValues(canonicalMessage),
        );
      }
      for (const reaction of reactions) {
        const messageId = String(reaction?.messageId || "").trim();
        const userId = String(reaction?.userId || "").trim();
        const emoji = normalizeReactionEmoji(reaction?.emoji);
        if (!messageId || !userId || !emoji) {
          continue;
        }
        await this._pool.query(
          `INSERT INTO ${this._qualifiedChatReactionsTableName}
             (message_id, user_id, emoji, created_at)
           VALUES ($1, $2, $3, $4)
           ON CONFLICT (message_id, user_id, emoji) DO NOTHING`,
          [messageId, userId, emoji, String(reaction?.createdAt || nowIso())],
        );
      }
      let skippedDrafts = 0;
      for (const draft of drafts) {
        const userId = String(draft?.userId || "").trim();
        const chatId = canonicalizeMigratedChatId(draft?.chatId);
        if (!userId || !chatId || !String(draft?.text || "").trim()) {
          skippedDrafts += 1;
          continue;
        }
        await this._pool.query(
          `INSERT INTO ${this._qualifiedChatDraftsTableName}
             (user_id, chat_id, draft_data)
           VALUES ($1, $2, $3::jsonb)
           ON CONFLICT (user_id, chat_id) DO NOTHING`,
          [userId, chatId, JSON.stringify({...draft, chatId})],
        );
      }
      let skippedPins = 0;
      for (const pin of pins) {
        const chatId = canonicalizeMigratedChatId(pin?.chatId);
        const messageId = String(pin?.messageId || "").trim();
        if (!chatId || !messageId) {
          skippedPins += 1;
          continue;
        }
        await this._pool.query(
          `INSERT INTO ${this._qualifiedChatPinsTableName}
             (chat_id, message_id, pin_data)
           VALUES ($1, $2, $3::jsonb)
           ON CONFLICT (chat_id) DO NOTHING`,
          [chatId, messageId, JSON.stringify({...pin, chatId})],
        );
      }

      const nextState = {
        ...state,
        messages: [],
        messageReactions: [],
        chatDrafts: [],
        chatPins: [],
        migrationStatus: {
          ...(state.migrationStatus || {}),
          chatCollectionsToTables: MARKER,
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
      // Sidecar-кэш обязан пережить границу миграции, иначе fallback-чтение
      // при недоступной БД воскресит домиграционный блоб (с сообщениями и
      // без маркера) и следующая мутация затрёт им состояние.
      await this._persistSnapshotCache(this._cachedState);
      console.log(
        "[backend] chat collections migrated to tables",
        JSON.stringify({
          messages: seenMessageIds.size,
          reactions: reactions.length,
          drafts: drafts.length,
          pins: pins.length,
          skipped: {
            messages: skippedMessages,
            drafts: skippedDrafts,
            pins: skippedPins,
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
      // Миграция обязана завершиться до обслуживания запросов: table-оверрайды
      // читают ТОЛЬКО таблицы, и старт с недомигрированными данными означал бы
      // split-brain (сообщения в блобе, чтение из пустых таблиц). Роняем бут —
      // systemd перезапустит, ошибка видна в journalctl.
      console.error(
        "[backend] chat collections migration FAILED — refusing to serve",
        JSON.stringify({message: error?.message || String(error)}),
      );
      throw error;
    }
  },

  // Зеркало db.chats → projection-таблица (+ таблица участников для
  // индексного membership-чека). Полная перезаливка — чатов немного, а
  // DELETE+INSERT в один приём проще инкрементального диффа. Вызывается на
  // буте и из _write при изменении хэша коллекции.
  async _replaceChatProjection(chats) {
    const normalizedChats = (Array.isArray(chats) ? chats : []).filter(
      (chat) => String(chat?.id || "").trim(),
    );
    // Транзакция (как у auth-гидратации): без неё конкурентный findChat в
    // окне DELETE→INSERT видел бы пустую projection и валил access-check
    // существующих чатов. На пулах без connect (pg-mem) — plain-фолбэк.
    await this._withProjectionClient(async (client, useTransaction) => {
      try {
        if (useTransaction) {
          await client.query("BEGIN");
          await client.query("SET LOCAL statement_timeout = 0");
        }
        await client.query(`DELETE FROM ${this._qualifiedChatsProjectionTableName}`);
        await client.query(`DELETE FROM ${this._qualifiedChatParticipantsTableName}`);
        for (const chat of normalizedChats) {
          const chatId = String(chat.id).trim();
          await client.query(
            `INSERT INTO ${this._qualifiedChatsProjectionTableName} (id, chat_data)
             VALUES ($1, $2::jsonb)
             ON CONFLICT (id) DO UPDATE SET chat_data = EXCLUDED.chat_data`,
            [chatId, JSON.stringify(chat)],
          );
          for (const participantId of normalizeParticipantIds(chat.participantIds)) {
            await client.query(
              `INSERT INTO ${this._qualifiedChatParticipantsTableName} (chat_id, user_id)
               VALUES ($1, $2)
               ON CONFLICT (chat_id, user_id) DO NOTHING`,
              [chatId, participantId],
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
            // исходная ошибка важнее
          }
        }
        throw error;
      }
    });
    this._lastChatsProjectionHash = computeProjectionHash(normalizedChats);
    this._chatsProjectionDirty = false;
  },

  // SPEED-9 C-boot: опциональный уже прочитанный/актуальный state от
  // предыдущего шага буста — без него прежнее поведение (собственный
  // SELECT). Эта проекция не пишет блоб, поэтому ничего не возвращает.
  async _hydrateChatProjectionFromState(bootState) {
    try {
      let state = bootState;
      if (!state) {
        const result = await this._pool.query(
          `SELECT data FROM ${this._qualifiedTableName} WHERE id = $1`,
          [this._rowId],
        );
        const rawData = result.rows[0]?.data ?? EMPTY_DB;
        state = normalizeDbState(
          typeof rawData === "string" ? JSON.parse(rawData) : rawData,
        );
      }
      await this._replaceChatProjection(state.chats);
    } catch (error) {
      // Деградация вместо падения (БД могла мигнуть): dirty-флаг переводит
      // резолв чатов на блоб через super.findChat, а первый успешный _write
      // (хэш стартует null → mismatch) перезальёт projection и снимет флаг.
      this._chatsProjectionDirty = true;
      console.warn(
        "[backend] postgres-store skipped chat projection hydration",
        JSON.stringify({message: error?.message || String(error)}),
      );
    }
  },

  // SPEED-9 C-boot: опциональный {state, version} от единого чтения в
  // начале _bootstrap() — без него прежнее поведение (собственный SELECT).
  // На успехе возвращает {state, version} строки ПОСЛЕ этого шага; на
  // ошибке — исходный bootRow без изменений (мы его не портили, только
  // не смогли обновить), либо null, если своего снимка тоже не было.
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
    const placeholders = normalizedUserIds.map((_, index) => `$${index + 1}`);
    const result = await this._pool.query(
      `SELECT id, user_data
         FROM ${this._qualifiedAuthUsersTableName}
        WHERE id IN (${placeholders.join(", ")})`,
      normalizedUserIds,
    );
    return new Map(
      result.rows
        .map((row) => [String(row?.id || row?.user_data?.id || "").trim(), row?.user_data])
        .filter(([userId, user]) => userId && user),
    );
  },

  _isProjectedMessageReadByUser(message, userId) {
    const readBy = normalizeParticipantIds(message?.readBy);
    if (readBy.length > 0) {
      return readBy.includes(userId);
    }
    return message?.isRead === true;
  },

  _chatMessageFromRow(row) {
    const data = row?.message_data;
    if (data == null) {
      return null;
    }
    return typeof data === "string" ? JSON.parse(data) : data;
  },

  _chatJsonFromRow(row, column) {
    const data = row?.[column];
    if (data == null) {
      return null;
    }
    return typeof data === "string" ? JSON.parse(data) : data;
  },

  _escapeLikePattern(value) {
    return String(value || "").replace(/[\\%_]/g, (match) => `\\${match}`);
  },

  async _selectChatProjectionById(chatId) {
    const normalized = String(chatId || "").trim();
    if (!normalized) {
      return null;
    }
    const result = await this._pool.query(
      `SELECT chat_data FROM ${this._qualifiedChatsProjectionTableName} WHERE id = $1`,
      [normalized],
    );
    return this._chatJsonFromRow(result.rows[0], "chat_data");
  },

  async _selectLatestChatMessage(equivalentChatIds, nowTimestamp) {
    const ids = equivalentChatIds.filter(Boolean);
    if (ids.length === 0) {
      return null;
    }
    const placeholders = ids.map((_, index) => `$${index + 1}`);
    const result = await this._pool.query(
      `SELECT ts, id, message_data
         FROM ${this._qualifiedChatMessagesTableName}
        WHERE chat_id IN (${placeholders.join(", ")})
          AND (expires_at = '' OR expires_at > $${ids.length + 1})
        ORDER BY ts DESC, id DESC
        LIMIT 1`,
      [...ids, nowTimestamp],
    );
    return result.rows[0] || null;
  },

  // Аналог FileStore._resolveChat поверх таблиц: сохранённый чат из
  // projection (с updatedAt, доведённым до timestamp последнего сообщения —
  // на PG-пути блобный chat.updatedAt на send не бампится), либо
  // синтезированный виртуальный direct-чат из канонического `a_b` id.
  async _resolveChatFromTables(chatId) {
    const normalizedChatId = String(chatId || "").trim();
    if (!normalizedChatId) {
      return null;
    }
    if (this._chatsProjectionDirty) {
      // Projection не догидратировалась на буте — правду о чатах даёт блоб.
      const blobChat = await FileStore.prototype.findChat.call(this, normalizedChatId);
      return blobChat ? {chat: blobChat, stored: true} : null;
    }
    const nowTimestamp = nowIso();
    let chat = await this._selectChatProjectionById(normalizedChatId);
    let stored = Boolean(chat);
    if (!chat) {
      const directParticipants = parseDirectParticipantsFromChatId(normalizedChatId);
      if (directParticipants.length !== 2) {
        return null;
      }
      const canonicalChatId = directParticipants.join("_");
      if (canonicalChatId !== normalizedChatId) {
        chat = await this._selectChatProjectionById(canonicalChatId);
        stored = Boolean(chat);
      }
      if (!chat) {
        const latestRow = await this._selectLatestChatMessage(
          this._equivalentChatIdList(normalizedChatId, canonicalChatId),
          nowTimestamp,
        );
        const latestMessage = this._chatMessageFromRow(latestRow);
        const firstTimestamp = latestMessage ? null : nowIso();
        let earliestTimestamp = firstTimestamp;
        if (latestRow) {
          const ids = this._equivalentChatIdList(normalizedChatId, canonicalChatId);
          const placeholders = ids.map((_, index) => `$${index + 1}`);
          const earliest = await this._pool.query(
            `SELECT ts
               FROM ${this._qualifiedChatMessagesTableName}
              WHERE chat_id IN (${placeholders.join(", ")})
                AND (expires_at = '' OR expires_at > $${ids.length + 1})
              ORDER BY ts ASC, id ASC
              LIMIT 1`,
            [...ids, nowTimestamp],
          );
          earliestTimestamp = earliest.rows[0]?.ts || nowIso();
        }
        return {
          chat: {
            id: canonicalChatId,
            type: "direct",
            participantIds: directParticipants,
            title: null,
            createdBy: directParticipants[0],
            treeId: null,
            branchRootPersonIds: [],
            createdAt: earliestTimestamp || nowIso(),
            updatedAt: latestRow?.ts || earliestTimestamp || nowIso(),
          },
          stored: false,
        };
      }
    }

    const equivalentIds = this._equivalentChatIdList(normalizedChatId, chat.id);
    const latestRow = await this._selectLatestChatMessage(equivalentIds, nowTimestamp);
    if (
      latestRow?.ts &&
      String(latestRow.ts).localeCompare(String(chat.updatedAt || "")) > 0
    ) {
      chat = {...chat, updatedAt: latestRow.ts};
    }
    return {chat, stored};
  },

  async findChat(chatId) {
    await this.initialize();
    // Барьер write-queue тут не нужен: данные живут в чат-таблицах, чьи
    // писатели — прямой SQL, а не блоб-очередь; HTTP-порядок запросов даёт
    // нужную последовательность. Ожидание блоб-очереди (нотификации/пуш-логи
    // фан-аута) добавляло до ~300мс на access под бёрстом.
    try {
      const resolved = await this._resolveChatFromTables(chatId);
      return resolved ? structuredClone(resolved.chat) : null;
    } catch (error) {
      // Записи чатов живут и в блобе — при недоступности projection-таблиц
      // (например, урезанный тестовый движок) корректен старый путь.
      console.warn(
        "[backend] postgres findChat fell back to state read",
        JSON.stringify({message: error?.message || String(error)}),
      );
      return FileStore.prototype.findChat.call(this, chatId);
    }
  },

  async isUserBlockedBetween(userIdA, userIdB) {
    await this.initialize();
    // Барьер write-queue тут не нужен: данные живут в чат-таблицах, чьи
    // писатели — прямой SQL, а не блоб-очередь; HTTP-порядок запросов даёт
    // нужную последовательность. Ожидание блоб-очереди (нотификации/пуш-логи
    // фан-аута) добавляло до ~300мс на access под бёрстом.
    try {
      const result = await this._pool.query(
        `SELECT 1 AS blocked
           FROM ${this._qualifiedTableName},
                LATERAL jsonb_array_elements(COALESCE(data->'blocks', '[]'::jsonb)) AS block_entry
          WHERE id = $1
            AND (
              (COALESCE(block_entry->>'blockerId', '') = $2 AND COALESCE(block_entry->>'blockedUserId', '') = $3)
              OR (COALESCE(block_entry->>'blockerId', '') = $3 AND COALESCE(block_entry->>'blockedUserId', '') = $2)
            )
          LIMIT 1`,
        [this._rowId, String(userIdA || ""), String(userIdB || "")],
      );
      return result.rows.length > 0;
    } catch (error) {
      if (!isProjectionArrayTextFallbackError(error) && !isProjectionHydrationFallbackError(error)) {
        throw error;
      }
      return FileStore.prototype.isUserBlockedBetween.call(this, userIdA, userIdB);
    }
  },

  async _aggregateReactionsByMessageIds(messageIds) {
    const ids = Array.from(
      new Set(
        (Array.isArray(messageIds) ? messageIds : [])
          .map((value) => String(value || "").trim())
          .filter(Boolean),
      ),
    );
    const aggregated = new Map();
    if (ids.length === 0) {
      return aggregated;
    }
    const placeholders = ids.map((_, index) => `$${index + 1}`);
    const result = await this._pool.query(
      `SELECT message_id, user_id, emoji, created_at
         FROM ${this._qualifiedChatReactionsTableName}
        WHERE message_id IN (${placeholders.join(", ")})
        ORDER BY created_at ASC`,
      ids,
    );
    for (const row of result.rows) {
      const messageId = String(row?.message_id || "").trim();
      const userId = String(row?.user_id || "").trim();
      const emoji = normalizeReactionEmoji(row?.emoji);
      if (!messageId || !userId || !emoji) {
        continue;
      }
      const grouped = aggregated.get(messageId) || new Map();
      const existing = grouped.get(emoji) || {emoji, userIds: [], count: 0};
      if (!existing.userIds.includes(userId)) {
        existing.userIds.push(userId);
        existing.count = existing.userIds.length;
      }
      grouped.set(emoji, existing);
      aggregated.set(messageId, grouped);
    }
    const finalized = new Map();
    for (const [messageId, grouped] of aggregated) {
      finalized.set(
        messageId,
        Array.from(grouped.values()).sort((left, right) =>
          String(left.emoji || "").localeCompare(String(right.emoji || "")),
        ),
      );
    }
    return finalized;
  },

  _attachTableReactions(message, reactionsByMessageId) {
    const clone = structuredClone(message);
    clone.reactions = reactionsByMessageId.get(String(message?.id || "").trim()) || [];
    return clone;
  },

  // Физическая зачистка протухших сообщений (аналог _schedulePurgeSweep):
  // read-пути фильтруют expires_at прямо в SQL, а фактический DELETE с
  // каскадом реакций/пинов гоняем фоном не чаще раза в минуту.
  _scheduleChatTablePurgeSweep() {
    if (this._chatPurgeSweepScheduled) {
      return;
    }
    const now = Date.now();
    if (this._lastChatPurgeSweepAt && now - this._lastChatPurgeSweepAt < 60_000) {
      return;
    }
    this._chatPurgeSweepScheduled = true;
    Promise.resolve()
      .then(async () => {
        const nowTimestamp = nowIso();
        const deleted = await this._pool.query(
          `DELETE FROM ${this._qualifiedChatMessagesTableName}
            WHERE expires_at <> '' AND expires_at <= $1
            RETURNING id`,
          [nowTimestamp],
        );
        const deletedIds = deleted.rows
          .map((row) => String(row?.id || "").trim())
          .filter(Boolean);
        if (deletedIds.length > 0) {
          const placeholders = deletedIds.map((_, index) => `$${index + 1}`);
          await this._pool.query(
            `DELETE FROM ${this._qualifiedChatReactionsTableName}
              WHERE message_id IN (${placeholders.join(", ")})`,
            deletedIds,
          );
          await this._pool.query(
            `DELETE FROM ${this._qualifiedChatPinsTableName}
              WHERE message_id IN (${placeholders.join(", ")})`,
            deletedIds,
          );
        }
      })
      .catch((error) => {
        console.warn(
          "[backend] chat table purge sweep failed",
          error?.message || error,
        );
      })
      .then(() => {
        this._chatPurgeSweepScheduled = false;
        this._lastChatPurgeSweepAt = Date.now();
      });
  },

  // Фоновая материализация виртуального direct-чата в блоб (и через
  // hash-синк — в projection). НЕ на ack-пути: сообщение уже в таблице,
  // access и превью работают и без сохранённой записи чата.
  _scheduleDirectChatMaterialize(chat) {
    const record = {
      id: String(chat?.id || "").trim(),
      type: "direct",
      participantIds: normalizeParticipantIds(chat?.participantIds),
      title: null,
      photoUrl: null,
      createdBy: chat?.createdBy || null,
      treeId: null,
      branchRootPersonIds: [],
      createdAt: chat?.createdAt || nowIso(),
      updatedAt: chat?.updatedAt || nowIso(),
    };
    if (!record.id || record.participantIds.length !== 2) {
      return;
    }
    Promise.resolve()
      .then(() =>
        this._mutate((db, skip) => {
          if (db.chats.some((entry) => entry.id === record.id)) {
            return skip(undefined);
          }
          db.chats.push(record);
          return undefined;
        }),
      )
      .catch((error) => {
        console.warn(
          "[backend] direct chat materialize failed",
          error?.message || error,
        );
      });
  },

  async addChatMessage({
    chatId,
    senderId,
    text,
    attachments = [],
    mediaUrls = [],
    imageUrl = null,
    clientMessageId = null,
    expiresAt = null,
    replyTo = null,
    call = null,
  }) {
    await this.initialize();
    // Барьер write-queue тут не нужен: данные живут в чат-таблицах, чьи
    // писатели — прямой SQL, а не блоб-очередь; HTTP-порядок запросов даёт
    // нужную последовательность. Ожидание блоб-очереди (нотификации/пуш-логи
    // фан-аута) добавляло до ~300мс на access под бёрстом.
    const resolved = await this._resolveChatFromTables(chatId);
    if (!resolved) {
      return null;
    }
    const {chat, stored} = resolved;

    const participants = normalizeParticipantIds(chat.participantIds);
    if (!participants.includes(senderId) || participants.length < 2) {
      return null;
    }

    const normalizedText = String(text || "").trim();
    const normalizedAttachments = normalizeMessageAttachments({
      attachments,
      mediaUrls,
      imageUrl,
    });
    const normalizedMediaUrls = normalizedAttachments.map((entry) => entry.url);
    const normalizedImageUrl =
      normalizedAttachments.find((entry) => entry.type === "image")?.url ||
      normalizedAttachments[0]?.url ||
      null;
    const normalizedClientMessageId = String(clientMessageId || "").trim() || null;
    const normalizedExpiresAt = normalizeOptionalIsoTimestamp(expiresAt);
    const normalizedReplyTo = normalizeReplyReference(replyTo);
    const normalizedCall = normalizeChatMessageCall(call);
    if (!normalizedText && normalizedAttachments.length === 0 && !normalizedCall) {
      return false;
    }

    const equivalentIds = this._equivalentChatIdList(chatId, chat.id);

    const findExistingByClientId = async () => {
      if (!normalizedClientMessageId) {
        return null;
      }
      const placeholders = equivalentIds.map((_, index) => `$${index + 1}`);
      const result = await this._pool.query(
        `SELECT id, message_data
           FROM ${this._qualifiedChatMessagesTableName}
          WHERE chat_id IN (${placeholders.join(", ")})
            AND sender_id = $${equivalentIds.length + 1}
            AND client_message_id = $${equivalentIds.length + 2}
          LIMIT 1`,
        [...equivalentIds, senderId, normalizedClientMessageId],
      );
      return this._chatMessageFromRow(result.rows[0]);
    };

    const existingMessage = await findExistingByClientId();
    if (existingMessage) {
      const reactions = await this._aggregateReactionsByMessageIds([existingMessage.id]);
      return {
        ...this._attachTableReactions(existingMessage, reactions),
        _deduplicated: true,
      };
    }

    const senderUsers = await this._selectProjectedUsersByIds([senderId]);
    const sender = senderUsers.get(String(senderId || "").trim()) || null;

    const timestamp = nowIso();
    const message = {
      id: crypto.randomUUID(),
      chatId: chat.id,
      senderId,
      text: normalizedText,
      timestamp,
      isRead: false,
      participants,
      deliveredTo: [senderId],
      readBy: [senderId],
      senderName: sender?.profile?.displayName || "Пользователь",
      attachments: normalizedAttachments,
      imageUrl: normalizedImageUrl,
      mediaUrls: normalizedMediaUrls.length > 0 ? normalizedMediaUrls : null,
      clientMessageId: normalizedClientMessageId,
      expiresAt: normalizedExpiresAt,
      replyTo: normalizedReplyTo,
    };
    if (normalizedCall) {
      message.call = normalizedCall;
    }

    try {
      await this._insertChatMessageRow(message);
    } catch (error) {
      // Гонка одинаковых clientMessageId упирается в уникальный dedup-индекс —
      // возвращаем уже сохранённое сообщение, как это делает FileStore.
      const isUniqueViolation =
        error?.code === "23505" ||
        String(error?.message || "").toLowerCase().includes("duplicate key");
      if (!isUniqueViolation || !normalizedClientMessageId) {
        throw error;
      }
      const racedMessage = await findExistingByClientId();
      if (!racedMessage) {
        throw error;
      }
      const reactions = await this._aggregateReactionsByMessageIds([racedMessage.id]);
      return {
        ...this._attachTableReactions(racedMessage, reactions),
        _deduplicated: true,
      };
    }

    if (!stored) {
      this._scheduleDirectChatMaterialize({...chat, updatedAt: timestamp});
    }
    this._scheduleChatTablePurgeSweep();

    const result = structuredClone(message);
    result.reactions = [];
    return result;
  },

  async listChatMessages(
    chatId,
    {limit = null, beforeId = null, afterId = null, clearedBefore = null} = {},
  ) {
    await this.initialize();
    // Барьер write-queue тут не нужен: данные живут в чат-таблицах, чьи
    // писатели — прямой SQL, а не блоб-очередь; HTTP-порядок запросов даёт
    // нужную последовательность. Ожидание блоб-очереди (нотификации/пуш-логи
    // фан-аута) добавляло до ~300мс на access под бёрстом.
    const resolved = await this._resolveChatFromTables(chatId);
    if (!resolved) {
      return [];
    }
    const equivalentIds = this._equivalentChatIdList(chatId, resolved.chat.id);
    const nowTimestamp = nowIso();
    const placeholders = equivalentIds.map((_, index) => `$${index + 1}`);
    const baseParams = [...equivalentIds, nowTimestamp];
    let scopeSql = `chat_id IN (${placeholders.join(", ")})
          AND (expires_at = '' OR expires_at > $${equivalentIds.length + 1})`;
    const normalizedClearedBefore = normalizeOptionalIsoTimestamp(clearedBefore);
    if (normalizedClearedBefore) {
      baseParams.push(normalizedClearedBefore);
      scopeSql += `\n          AND ts > $${baseParams.length}`;
    }

    const normalizedBeforeId = normalizeNullableString(beforeId);
    const normalizedAfterId = normalizeNullableString(afterId);
    let cursorCondition = "";
    const params = [...baseParams];
    if (normalizedBeforeId || normalizedAfterId) {
      const cursorId = normalizedBeforeId || normalizedAfterId;
      const cursorResult = await this._pool.query(
        `SELECT ts, id
           FROM ${this._qualifiedChatMessagesTableName}
          WHERE ${scopeSql}
            AND id = $${baseParams.length + 1}
          LIMIT 1`,
        [...baseParams, cursorId],
      );
      const cursorRow = cursorResult.rows[0];
      if (!cursorRow) {
        // Неизвестный курсор => пустая страница (клиентский reconcile
        // кэша опирается ровно на эту семантику FileStore).
        return [];
      }
      params.push(cursorRow.ts, cursorRow.id);
      const tsParam = `$${params.length - 1}`;
      const idParam = `$${params.length}`;
      cursorCondition = normalizedBeforeId
        ? `AND (ts < ${tsParam} OR (ts = ${tsParam} AND id < ${idParam}))`
        : `AND (ts > ${tsParam} OR (ts = ${tsParam} AND id > ${idParam}))`;
    }

    const normalizedLimit = Number.isFinite(Number(limit))
      ? Math.max(0, Math.floor(Number(limit)))
      : null;
    const limitSql = normalizedLimit === null ? "" : `LIMIT ${normalizedLimit}`;
    const result = await this._pool.query(
      `SELECT message_data
         FROM ${this._qualifiedChatMessagesTableName}
        WHERE ${scopeSql}
          ${cursorCondition}
        ORDER BY ts DESC, id DESC
        ${limitSql}`,
      params,
    );
    const messages = result.rows
      .map((row) => this._chatMessageFromRow(row))
      .filter(Boolean);
    const reactions = await this._aggregateReactionsByMessageIds(
      messages.map((message) => message.id),
    );
    this._scheduleChatTablePurgeSweep();
    return messages.map((message) => this._attachTableReactions(message, reactions));
  },

  async _selectChatMessageInScope({chatId, resolvedChatId, messageId, nowTimestamp}) {
    const normalizedMessageId = String(messageId || "").trim();
    if (!normalizedMessageId) {
      return null;
    }
    const equivalentIds = this._equivalentChatIdList(chatId, resolvedChatId);
    const placeholders = equivalentIds.map((_, index) => `$${index + 1}`);
    const result = await this._pool.query(
      `SELECT message_data
         FROM ${this._qualifiedChatMessagesTableName}
        WHERE chat_id IN (${placeholders.join(", ")})
          AND (expires_at = '' OR expires_at > $${equivalentIds.length + 1})
          AND id = $${equivalentIds.length + 2}
        LIMIT 1`,
      [...equivalentIds, nowTimestamp, normalizedMessageId],
    );
    return this._chatMessageFromRow(result.rows[0]);
  },

  async updateChatMessage({chatId, messageId, userId, text}) {
    await this.initialize();
    // Барьер write-queue тут не нужен: данные живут в чат-таблицах, чьи
    // писатели — прямой SQL, а не блоб-очередь; HTTP-порядок запросов даёт
    // нужную последовательность. Ожидание блоб-очереди (нотификации/пуш-логи
    // фан-аута) добавляло до ~300мс на access под бёрстом.
    const resolved = await this._resolveChatFromTables(chatId);
    if (!resolved || !resolved.chat.participantIds.includes(userId)) {
      return false;
    }
    return this._enqueueChatRowMutation(async () => {
      const message = await this._selectChatMessageInScope({
        chatId,
        resolvedChatId: resolved.chat.id,
        messageId,
        nowTimestamp: nowIso(),
      });
      if (!message) {
        return null;
      }
      if (message.senderId !== userId) {
        return undefined;
      }

      const normalizedText = String(text || "").trim();
      const attachments = normalizeMessageAttachments(message);
      if (!normalizedText && attachments.length === 0) {
        return "EMPTY_MESSAGE";
      }

      message.text = normalizedText;
      message.updatedAt = nowIso();
      await this._updateChatMessageRow(message);
      const reactions = await this._aggregateReactionsByMessageIds([message.id]);
      return this._attachTableReactions(message, reactions);
    });
  },

  async deleteChatMessage({chatId, messageId, userId}) {
    await this.initialize();
    // Барьер write-queue тут не нужен: данные живут в чат-таблицах, чьи
    // писатели — прямой SQL, а не блоб-очередь; HTTP-порядок запросов даёт
    // нужную последовательность. Ожидание блоб-очереди (нотификации/пуш-логи
    // фан-аута) добавляло до ~300мс на access под бёрстом.
    const resolved = await this._resolveChatFromTables(chatId);
    if (!resolved || !resolved.chat.participantIds.includes(userId)) {
      return false;
    }
    const message = await this._selectChatMessageInScope({
      chatId,
      resolvedChatId: resolved.chat.id,
      messageId,
      nowTimestamp: nowIso(),
    });
    if (!message) {
      return null;
    }
    if (message.senderId !== userId) {
      return undefined;
    }

    await this._pool.query(
      `DELETE FROM ${this._qualifiedChatMessagesTableName} WHERE id = $1`,
      [message.id],
    );
    await this._pool.query(
      `DELETE FROM ${this._qualifiedChatReactionsTableName} WHERE message_id = $1`,
      [message.id],
    );
    const pinDelete = await this._pool.query(
      `DELETE FROM ${this._qualifiedChatPinsTableName}
        WHERE message_id = $1
        RETURNING chat_id`,
      [message.id],
    );

    // Как в FileStore: после удаления реакции сообщения уже вычищены,
    // возвращается пустой агрегат.
    const deletedMessage = structuredClone(message);
    deletedMessage.reactions = [];
    if (pinDelete.rows.length > 0) {
      deletedMessage._clearedPinnedMessage = true;
    }
    return deletedMessage;
  },

  async toggleChatMessageReaction({chatId, messageId, userId, emoji}) {
    await this.initialize();
    // Барьер write-queue тут не нужен: данные живут в чат-таблицах, чьи
    // писатели — прямой SQL, а не блоб-очередь; HTTP-порядок запросов даёт
    // нужную последовательность. Ожидание блоб-очереди (нотификации/пуш-логи
    // фан-аута) добавляло до ~300мс на access под бёрстом.
    const resolved = await this._resolveChatFromTables(chatId);
    if (!resolved || !resolved.chat.participantIds.includes(userId)) {
      return false;
    }
    const message = await this._selectChatMessageInScope({
      chatId,
      resolvedChatId: resolved.chat.id,
      messageId,
      nowTimestamp: nowIso(),
    });
    if (!message) {
      return null;
    }

    const normalizedEmoji = normalizeReactionEmoji(emoji);
    if (!normalizedEmoji) {
      return "INVALID_EMOJI";
    }

    const existing = await this._pool.query(
      `SELECT 1 AS present
         FROM ${this._qualifiedChatReactionsTableName}
        WHERE message_id = $1 AND user_id = $2 AND emoji = $3
        LIMIT 1`,
      [message.id, userId, normalizedEmoji],
    );
    let added = false;
    if (existing.rows.length > 0) {
      await this._pool.query(
        `DELETE FROM ${this._qualifiedChatReactionsTableName}
          WHERE message_id = $1 AND user_id = $2 AND emoji = $3`,
        [message.id, userId, normalizedEmoji],
      );
    } else {
      await this._pool.query(
        `INSERT INTO ${this._qualifiedChatReactionsTableName}
           (message_id, user_id, emoji, created_at)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (message_id, user_id, emoji) DO NOTHING`,
        [message.id, userId, normalizedEmoji, nowIso()],
      );
      added = true;
    }

    const reactions = await this._aggregateReactionsByMessageIds([message.id]);
    return {
      chatId: message.chatId || resolved.chat.id,
      messageId: message.id,
      reactions: reactions.get(message.id) || [],
      added,
    };
  },

  async markChatMessageDelivered({chatId, messageId, userIds = []}) {
    await this.initialize();
    // Барьер write-queue тут не нужен: данные живут в чат-таблицах, чьи
    // писатели — прямой SQL, а не блоб-очередь; HTTP-порядок запросов даёт
    // нужную последовательность. Ожидание блоб-очереди (нотификации/пуш-логи
    // фан-аута) добавляло до ~300мс на access под бёрстом.
    const resolved = await this._resolveChatFromTables(chatId);
    if (!resolved) {
      return false;
    }
    return this._enqueueChatRowMutation(async () => {
      const message = await this._selectChatMessageInScope({
        chatId,
        resolvedChatId: resolved.chat.id,
        messageId,
        nowTimestamp: nowIso(),
      });
      if (!message) {
        return null;
      }

      const participantIds = normalizeParticipantIds(resolved.chat.participantIds);
      const recipientIds = normalizeParticipantIds(userIds).filter(
        (userId) => participantIds.includes(userId) && userId !== message.senderId,
      );
      if (recipientIds.length === 0) {
        return {
          chatId: message.chatId || resolved.chat.id,
          messageId: message.id,
          deliveredTo: normalizeParticipantIds(message.deliveredTo),
          changedUserIds: [],
        };
      }

      const deliveredTo = normalizeParticipantIds(message.deliveredTo);
      let changed = false;
      for (const userId of recipientIds) {
        if (!deliveredTo.includes(userId)) {
          deliveredTo.push(userId);
          changed = true;
        }
      }
      message.deliveredTo = deliveredTo;
      if (changed) {
        await this._updateChatMessageRow(message);
      }

      return {
        chatId: message.chatId || resolved.chat.id,
        messageId: message.id,
        deliveredTo: normalizeParticipantIds(message.deliveredTo),
        changedUserIds: changed ? recipientIds : [],
      };
    });
  },

  async markChatAsRead(chatId, userId) {
    await this.initialize();
    // Барьер write-queue тут не нужен: данные живут в чат-таблицах, чьи
    // писатели — прямой SQL, а не блоб-очередь; HTTP-порядок запросов даёт
    // нужную последовательность. Ожидание блоб-очереди (нотификации/пуш-логи
    // фан-аута) добавляло до ~300мс на access под бёрстом.
    const resolved = await this._resolveChatFromTables(chatId);
    if (!resolved || !resolved.chat.participantIds.includes(userId)) {
      return false;
    }
    const equivalentIds = this._equivalentChatIdList(chatId, resolved.chat.id);
    return this._enqueueChatRowMutation(async () => {
      const nowTimestamp = nowIso();
      const placeholders = equivalentIds.map((_, index) => `$${index + 1}`);
      const result = await this._pool.query(
        `SELECT message_data
           FROM ${this._qualifiedChatMessagesTableName}
          WHERE chat_id IN (${placeholders.join(", ")})
            AND (expires_at = '' OR expires_at > $${equivalentIds.length + 1})
            AND sender_id <> $${equivalentIds.length + 2}`,
        [...equivalentIds, nowTimestamp, userId],
      );

      let changed = false;
      const readMessageIds = [];
      for (const row of result.rows) {
        const message = this._chatMessageFromRow(row);
        if (!message) {
          continue;
        }
        let messageChanged = false;
        const deliveredTo = normalizeParticipantIds(message.deliveredTo);
        if (!deliveredTo.includes(userId)) {
          deliveredTo.push(userId);
          message.deliveredTo = deliveredTo;
          messageChanged = true;
        }
        const readBy = normalizeParticipantIds(message.readBy);
        if (!readBy.includes(userId)) {
          readBy.push(userId);
          message.readBy = readBy;
          readMessageIds.push(message.id);
          messageChanged = true;
        }
        if (message.isRead !== true) {
          message.isRead = true;
          messageChanged = true;
        }
        if (messageChanged) {
          changed = true;
          await this._updateChatMessageRow(message);
        }
      }

      return {
        changed,
        chatId: resolved.chat.id,
        userId,
        messageIds: readMessageIds,
      };
    });
  },

  async getChatDraft({userId, chatId}) {
    await this.initialize();
    // Барьер write-queue тут не нужен: данные живут в чат-таблицах, чьи
    // писатели — прямой SQL, а не блоб-очередь; HTTP-порядок запросов даёт
    // нужную последовательность. Ожидание блоб-очереди (нотификации/пуш-логи
    // фан-аута) добавляло до ~300мс на access под бёрстом.
    const resolved = await this._resolveChatFromTables(chatId);
    if (!resolved || !this._canAccessChatDraft(resolved.chat, userId)) {
      return null;
    }
    const result = await this._pool.query(
      `SELECT draft_data
         FROM ${this._qualifiedChatDraftsTableName}
        WHERE user_id = $1 AND chat_id = $2
        LIMIT 1`,
      [String(userId || "").trim(), resolved.chat.id],
    );
    const draft = this._chatJsonFromRow(result.rows[0], "draft_data");
    return draft ? structuredClone(draft) : null;
  },

  async listChatDrafts(userId) {
    await this.initialize();
    // Барьер write-queue тут не нужен: данные живут в чат-таблицах, чьи
    // писатели — прямой SQL, а не блоб-очередь; HTTP-порядок запросов даёт
    // нужную последовательность. Ожидание блоб-очереди (нотификации/пуш-логи
    // фан-аута) добавляло до ~300мс на access под бёрстом.
    const normalizedUserId = String(userId || "").trim();
    if (!normalizedUserId) {
      return [];
    }
    const result = await this._pool.query(
      `SELECT draft_data
         FROM ${this._qualifiedChatDraftsTableName}
        WHERE user_id = $1`,
      [normalizedUserId],
    );
    const drafts = [];
    for (const row of result.rows) {
      const draft = this._chatJsonFromRow(row, "draft_data");
      if (!draft || !String(draft.text || "").trim()) {
        continue;
      }
      const resolved = await this._resolveChatFromTables(draft.chatId);
      if (!resolved || !this._canAccessChatDraft(resolved.chat, normalizedUserId)) {
        continue;
      }
      drafts.push(draft);
    }
    return drafts
      .sort((left, right) =>
        String(right.updatedAt || "").localeCompare(String(left.updatedAt || "")),
      )
      .map((draft) => structuredClone(draft));
  },

  async saveChatDraft({userId, chatId, text}) {
    await this.initialize();
    // Барьер write-queue тут не нужен: данные живут в чат-таблицах, чьи
    // писатели — прямой SQL, а не блоб-очередь; HTTP-порядок запросов даёт
    // нужную последовательность. Ожидание блоб-очереди (нотификации/пуш-логи
    // фан-аута) добавляло до ~300мс на access под бёрстом.
    const resolved = await this._resolveChatFromTables(chatId);
    if (!resolved || !this._canAccessChatDraft(resolved.chat, userId)) {
      return null;
    }
    const normalizedUserId = String(userId || "").trim();
    const normalizedText = String(text || "");
    if (!normalizedText.trim()) {
      await this._pool.query(
        `DELETE FROM ${this._qualifiedChatDraftsTableName}
          WHERE user_id = $1 AND chat_id = $2`,
        [normalizedUserId, resolved.chat.id],
      );
      return null;
    }
    const draft = createChatDraftRecord({
      userId: normalizedUserId,
      chatId: resolved.chat.id,
      text: normalizedText,
    });
    await this._pool.query(
      `INSERT INTO ${this._qualifiedChatDraftsTableName} (user_id, chat_id, draft_data)
       VALUES ($1, $2, $3::jsonb)
       ON CONFLICT (user_id, chat_id) DO UPDATE SET draft_data = EXCLUDED.draft_data`,
      [normalizedUserId, resolved.chat.id, JSON.stringify(draft)],
    );
    return structuredClone(draft);
  },

  async _selectChatPin(equivalentChatIds) {
    const ids = equivalentChatIds.filter(Boolean);
    if (ids.length === 0) {
      return null;
    }
    const placeholders = ids.map((_, index) => `$${index + 1}`);
    const result = await this._pool.query(
      `SELECT chat_id, message_id, pin_data
         FROM ${this._qualifiedChatPinsTableName}
        WHERE chat_id IN (${placeholders.join(", ")})
        LIMIT 1`,
      ids,
    );
    return result.rows[0] || null;
  },

  async getChatPinnedMessage({userId, chatId}) {
    await this.initialize();
    // Барьер write-queue тут не нужен: данные живут в чат-таблицах, чьи
    // писатели — прямой SQL, а не блоб-очередь; HTTP-порядок запросов даёт
    // нужную последовательность. Ожидание блоб-очереди (нотификации/пуш-логи
    // фан-аута) добавляло до ~300мс на access под бёрстом.
    const resolved = await this._resolveChatFromTables(chatId);
    if (!resolved || !this._canAccessChatPin(resolved.chat, userId)) {
      return null;
    }
    const equivalentIds = this._equivalentChatIdList(chatId, resolved.chat.id);
    const pinRow = await this._selectChatPin(equivalentIds);
    if (!pinRow) {
      return null;
    }
    const pin = this._chatJsonFromRow(pinRow, "pin_data") || {};
    const message = await this._selectChatMessageInScope({
      chatId,
      resolvedChatId: resolved.chat.id,
      messageId: pinRow.message_id,
      nowTimestamp: nowIso(),
    });
    if (!message) {
      await this._pool.query(
        `DELETE FROM ${this._qualifiedChatPinsTableName} WHERE message_id = $1`,
        [pinRow.message_id],
      );
      return null;
    }
    const freshPin = {
      ...createChatPinRecord({
        chatId: resolved.chat.id,
        message,
        pinnedBy: pin.pinnedBy || userId,
      }),
      pinnedAt: pin.pinnedAt || nowIso(),
    };
    return structuredClone(freshPin);
  },

  async pinChatMessage({userId, chatId, messageId}) {
    await this.initialize();
    // Барьер write-queue тут не нужен: данные живут в чат-таблицах, чьи
    // писатели — прямой SQL, а не блоб-очередь; HTTP-порядок запросов даёт
    // нужную последовательность. Ожидание блоб-очереди (нотификации/пуш-логи
    // фан-аута) добавляло до ~300мс на access под бёрстом.
    const resolved = await this._resolveChatFromTables(chatId);
    if (!resolved || !this._canAccessChatPin(resolved.chat, userId)) {
      return false;
    }
    const message = await this._selectChatMessageInScope({
      chatId,
      resolvedChatId: resolved.chat.id,
      messageId,
      nowTimestamp: nowIso(),
    });
    if (!message) {
      return null;
    }
    const equivalentIds = this._equivalentChatIdList(chatId, resolved.chat.id);
    const placeholders = equivalentIds.map((_, index) => `$${index + 1}`);
    await this._pool.query(
      `DELETE FROM ${this._qualifiedChatPinsTableName}
        WHERE chat_id IN (${placeholders.join(", ")})`,
      equivalentIds,
    );
    const pin = createChatPinRecord({
      chatId: resolved.chat.id,
      message,
      pinnedBy: userId,
    });
    await this._pool.query(
      `INSERT INTO ${this._qualifiedChatPinsTableName} (chat_id, message_id, pin_data)
       VALUES ($1, $2, $3::jsonb)
       ON CONFLICT (chat_id) DO UPDATE
         SET message_id = EXCLUDED.message_id,
             pin_data = EXCLUDED.pin_data`,
      [resolved.chat.id, pin.messageId, JSON.stringify(pin)],
    );
    return structuredClone(pin);
  },

  async clearChatPinnedMessage({userId, chatId}) {
    await this.initialize();
    // Барьер write-queue тут не нужен: данные живут в чат-таблицах, чьи
    // писатели — прямой SQL, а не блоб-очередь; HTTP-порядок запросов даёт
    // нужную последовательность. Ожидание блоб-очереди (нотификации/пуш-логи
    // фан-аута) добавляло до ~300мс на access под бёрстом.
    const resolved = await this._resolveChatFromTables(chatId);
    if (!resolved || !this._canAccessChatPin(resolved.chat, userId)) {
      return false;
    }
    const equivalentIds = this._equivalentChatIdList(chatId, resolved.chat.id);
    const placeholders = equivalentIds.map((_, index) => `$${index + 1}`);
    await this._pool.query(
      `DELETE FROM ${this._qualifiedChatPinsTableName}
        WHERE chat_id IN (${placeholders.join(", ")})`,
      equivalentIds,
    );
    return true;
  },

  async searchChatMessages({
    userId,
    query,
    chatId = null,
    limit = 50,
  } = {}) {
    await this.initialize();
    // Барьер write-queue тут не нужен: данные живут в чат-таблицах, чьи
    // писатели — прямой SQL, а не блоб-очередь; HTTP-порядок запросов даёт
    // нужную последовательность. Ожидание блоб-очереди (нотификации/пуш-логи
    // фан-аута) добавляло до ~300мс на access под бёрстом.
    const normalizedUserId = String(userId || "").trim();
    const terms = normalizeChatSearchQuery(query);
    if (!normalizedUserId || terms.length === 0) {
      return [];
    }
    const normalizedLimit = Math.min(
      Math.max(1, Number.parseInt(String(limit || "50"), 10) || 50),
      100,
    );

    const normalizedChatId = normalizeNullableString(chatId);
    let scopeIds = null;
    if (normalizedChatId) {
      const resolved = await this._resolveChatFromTables(normalizedChatId);
      if (
        !resolved ||
        !normalizeParticipantIds(resolved.chat.participantIds).includes(normalizedUserId)
      ) {
        return [];
      }
      scopeIds = this._equivalentChatIdList(normalizedChatId, resolved.chat.id);
    }

    const params = [];
    const conditions = [];
    for (const term of terms) {
      params.push(`%${this._escapeLikePattern(term)}%`);
      conditions.push(`haystack LIKE $${params.length}`);
    }
    params.push(nowIso());
    conditions.push(`(expires_at = '' OR expires_at > $${params.length})`);
    if (scopeIds) {
      const placeholders = scopeIds.map((id) => {
        params.push(id);
        return `$${params.length}`;
      });
      conditions.push(`chat_id IN (${placeholders.join(", ")})`);
    } else {
      // Constrain global search in SQL to chats where the caller is an active
      // participant (or virtual direct-chat pairs) so global >1000 matches from
      // unrelated users never truncate this user's search results.
      const userChats = await this._selectChatsForUserFromTables(normalizedUserId);
      const userChatScopeIds = [];
      for (const chat of userChats) {
        const cid = String(chat?.id || "").trim();
        if (!cid) continue;
        userChatScopeIds.push(cid);
        if (chat.type === "direct") {
          for (const eq of this._equivalentChatIdList(cid, cid)) {
            if (!userChatScopeIds.includes(eq)) {
              userChatScopeIds.push(eq);
            }
          }
        }
      }
      const escUser = this._escapeLikePattern(normalizedUserId);
      params.push(`${escUser}_%`);
      const p1 = `$${params.length}`;
      params.push(`%_${escUser}`);
      const p2 = `$${params.length}`;
      const directCond = `(chat_id NOT LIKE 'chat_%' AND (chat_id LIKE ${p1} OR chat_id LIKE ${p2}))`;
      if (userChatScopeIds.length > 0) {
        const placeholders = userChatScopeIds.map((id) => {
          params.push(id);
          return `$${params.length}`;
        });
        conditions.push(`(chat_id IN (${placeholders.join(", ")}) OR ${directCond})`);
      } else {
        conditions.push(directCond);
      }
    }

    const result = await this._pool.query(
      `SELECT message_data
         FROM ${this._qualifiedChatMessagesTableName}
        WHERE ${conditions.join(" AND ")}
        ORDER BY ts DESC, id DESC
        LIMIT 1000`,
      params,
    );

    const chatCache = new Map();
    const results = [];
    for (const row of result.rows) {
      if (results.length >= normalizedLimit) {
        break;
      }
      const message = this._chatMessageFromRow(row);
      const messageChatId = String(message?.chatId || "").trim();
      if (!message || !messageChatId) {
        continue;
      }
      if (!chatCache.has(messageChatId)) {
        chatCache.set(
          messageChatId,
          await this._selectChatProjectionById(messageChatId),
        );
      }
      const chat = chatCache.get(messageChatId);
      const participantIds = chat
        ? normalizeParticipantIds(chat.participantIds)
        : parseDirectParticipantsFromChatId(messageChatId);
      if (!participantIds.includes(normalizedUserId)) {
        continue;
      }
      if (chat) {
        const prefs = this._getChatMemberPrefs(chat, normalizedUserId);
        if (
          prefs.clearedBefore &&
          String(message?.timestamp || "").localeCompare(prefs.clearedBefore) <= 0
        ) {
          continue;
        }
      }
      results.push({
        messageId: message.id,
        chatId: messageChatId,
        senderId: message.senderId || "",
        senderName: message.senderName || "Участник",
        text: message.text || "",
        snippet: buildChatSearchSnippet(message, terms),
        matchedAt: message.timestamp,
      });
    }
    return structuredClone(results);
  },

  async _selectChatsForUserFromTables(userId) {
    const result = await this._pool.query(
      `SELECT p.chat_data
         FROM ${this._qualifiedChatsProjectionTableName} p
         JOIN ${this._qualifiedChatParticipantsTableName} m
           ON m.chat_id = p.id
        WHERE m.user_id = $1`,
      [String(userId || "").trim()],
    );
    return result.rows
      .map((row) => this._chatJsonFromRow(row, "chat_data"))
      .filter((chat) => chat && String(chat.id || "").trim());
  },

  async _selectChatMessagesForPreviews(userId, chatIds) {
    const normalizedUserId = String(userId || "").trim();
    const params = [];
    const scopeParts = [];
    if (chatIds.length > 0) {
      const placeholders = chatIds.map((id) => {
        params.push(id);
        return `$${params.length}`;
      });
      scopeParts.push(`chat_id IN (${placeholders.join(", ")})`);
    }
    // Виртуальные direct-чаты без сохранённой записи: канонический id
    // содержит userId как первый или второй компонент.
    params.push(`${this._escapeLikePattern(normalizedUserId)}_%`);
    scopeParts.push(`chat_id LIKE $${params.length}`);
    params.push(`%_${this._escapeLikePattern(normalizedUserId)}`);
    scopeParts.push(`chat_id LIKE $${params.length}`);
    params.push(nowIso());
    const result = await this._pool.query(
      `SELECT message_data
         FROM ${this._qualifiedChatMessagesTableName}
        WHERE (${scopeParts.join(" OR ")})
          AND (expires_at = '' OR expires_at > $${params.length})
        ORDER BY ts DESC, id DESC`,
      params,
    );
    return result.rows
      .map((row) => this._chatMessageFromRow(row))
      .filter(Boolean);
  },

  async listChatPreviews(userId) {
    const normalizedUserId = String(userId || "").trim();
    if (!normalizedUserId) {
      return [];
    }
    await this.initialize();
    // Барьер write-queue тут не нужен: данные живут в чат-таблицах, чьи
    // писатели — прямой SQL, а не блоб-очередь; HTTP-порядок запросов даёт
    // нужную последовательность. Ожидание блоб-очереди (нотификации/пуш-логи
    // фан-аута) добавляло до ~300мс на access под бёрстом.
    const storedChats = await this._selectChatsForUserFromTables(normalizedUserId);
    const relatedChats = new Map();
    for (const chat of storedChats) {
      relatedChats.set(String(chat.id).trim(), structuredClone(chat));
    }
    const storedMessages = await this._selectChatMessagesForPreviews(
      normalizedUserId,
      Array.from(relatedChats.keys()),
    );

    const messagesByChatId = new Map();
    for (const message of storedMessages) {
      const rawChatId = String(message?.chatId || "").trim();
      const messageParticipants = normalizeParticipantIds(message?.participants);
      let resolvedChat = rawChatId ? relatedChats.get(rawChatId) || null : null;
      if (!resolvedChat) {
        const parsedDirectParticipants = parseDirectParticipantsFromChatId(rawChatId);
        const directParticipants =
          messageParticipants.length === 2
            ? messageParticipants
            : parsedDirectParticipants;
        if (
          directParticipants.length === 2 &&
          directParticipants.includes(normalizedUserId)
        ) {
          const canonicalChatId = directParticipants.join("_");
          resolvedChat = relatedChats.get(canonicalChatId) || {
            id: canonicalChatId,
            type: "direct",
            participantIds: directParticipants,
            title: null,
            createdBy: directParticipants[0] || null,
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
      if (!participants.includes(normalizedUserId)) {
        continue;
      }
      const chatId = String(chat?.id || "").trim();
      const prefs = this._getChatMemberPrefs(chat, normalizedUserId);
      const allChatMessages = (messagesByChatId.get(chatId) || []).sort(
        (left, right) =>
          String(right?.timestamp || "").localeCompare(String(left?.timestamp || "")),
      );
      const relevantMessages = prefs.clearedBefore
        ? allChatMessages.filter(
            (message) =>
              String(message?.timestamp || "").localeCompare(prefs.clearedBefore) > 0,
          )
        : allChatMessages;
      if (
        prefs.hiddenAt &&
        !relevantMessages.some(
          (message) =>
            String(message?.timestamp || "").localeCompare(prefs.hiddenAt) > 0,
        )
      ) {
        continue;
      }
      const isGroup = chat?.type === "group" || chat?.type === "branch";
      const otherUserId = isGroup
        ? ""
        : participants.find((participantId) => participantId !== normalizedUserId) || "";
      const lastMessage = relevantMessages[0] || null;
      const preview = {
        chatId,
        userId: normalizedUserId,
        type: chat?.type || "direct",
        title: chat?.title || null,
        photoUrl: isGroup ? chat?.photoUrl || null : null,
        participantIds: participants,
        otherUserId,
        otherUserName: "Пользователь",
        otherUserPhotoUrl: null,
        lastMessage: lastMessage ? describeMessagePreview(lastMessage) : "",
        lastMessageTime:
          lastMessage?.timestamp || chat?.updatedAt || chat?.createdAt || "",
        unreadCount: relevantMessages.filter((message) => {
          return message?.senderId !== normalizedUserId &&
            !this._isProjectedMessageReadByUser(message, normalizedUserId);
        }).length,
        lastMessageSenderId: lastMessage?.senderId || "",
        isArchived: prefs.isArchived,
        notificationLevel: prefs.notificationLevel,
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

    this._scheduleChatTablePurgeSweep();
    return previews
      .sort((left, right) =>
        String(right.lastMessageTime || "").localeCompare(String(left.lastMessageTime || "")),
      )
      .map((preview) => structuredClone(preview));
  },

  async countUnreadChatMessages(userId) {
    const normalizedUserId = String(userId || "").trim();
    if (!normalizedUserId) {
      return 0;
    }
    await this.initialize();
    // Барьер write-queue тут не нужен: данные живут в чат-таблицах, чьи
    // писатели — прямой SQL, а не блоб-очередь; HTTP-порядок запросов даёт
    // нужную последовательность. Ожидание блоб-очереди (нотификации/пуш-логи
    // фан-аута) добавляло до ~300мс на access под бёрстом.
    const storedChats = await this._selectChatsForUserFromTables(normalizedUserId);
    const chatIds = storedChats.map((chat) => String(chat.id).trim());
    const clearedBeforeByChatId = new Map();
    for (const chat of storedChats) {
      const prefs = this._getChatMemberPrefs(chat, normalizedUserId);
      if (prefs.clearedBefore) {
        clearedBeforeByChatId.set(String(chat.id).trim(), prefs.clearedBefore);
      }
    }
    const messages = await this._selectChatMessagesForPreviews(
      normalizedUserId,
      chatIds,
    );
    const chatIdSet = new Set(chatIds);
    let total = 0;
    for (const message of messages) {
      if (message?.senderId === normalizedUserId) {
        continue;
      }
      const messageChatId = String(message?.chatId || "").trim();
      const participants = normalizeParticipantIds(message?.participants);
      const directParticipants = parseDirectParticipantsFromChatId(messageChatId);
      const isMember =
        chatIdSet.has(messageChatId) ||
        participants.includes(normalizedUserId) ||
        directParticipants.includes(normalizedUserId);
      if (!isMember) {
        continue;
      }
      const canonicalDirectId =
        directParticipants.length === 2 ? directParticipants.join("_") : "";
      const clearedBefore =
        clearedBeforeByChatId.get(messageChatId) ||
        (canonicalDirectId ? clearedBeforeByChatId.get(canonicalDirectId) : null);
      if (
        clearedBefore &&
        String(message?.timestamp || "").localeCompare(clearedBefore) <= 0
      ) {
        continue;
      }
      if (!this._isProjectedMessageReadByUser(message, normalizedUserId)) {
        total += 1;
      }
    }
    return total;
  },

  async _purgeChatRowsFromTables(chatIds) {
    const normalizedIds = Array.from(
      new Set(
        (Array.isArray(chatIds) ? chatIds : [])
          .map((id) => String(id || "").trim())
          .filter(Boolean),
      ),
    );
    if (normalizedIds.length === 0) {
      return;
    }
    const placeholders = normalizedIds.map((_, index) => `$${index + 1}`);
    const deleted = await this._pool.query(
      `DELETE FROM ${this._qualifiedChatMessagesTableName}
        WHERE chat_id IN (${placeholders.join(", ")})
        RETURNING id`,
      normalizedIds,
    );
    const deletedIds = deleted.rows
      .map((row) => String(row?.id || "").trim())
      .filter(Boolean);
    if (deletedIds.length > 0) {
      const idPlaceholders = deletedIds.map((_, index) => `$${index + 1}`);
      await this._pool.query(
        `DELETE FROM ${this._qualifiedChatReactionsTableName}
          WHERE message_id IN (${idPlaceholders.join(", ")})`,
        deletedIds,
      );
    }
    await this._pool.query(
      `DELETE FROM ${this._qualifiedChatDraftsTableName}
        WHERE chat_id IN (${placeholders.join(", ")})`,
      normalizedIds,
    );
    await this._pool.query(
      `DELETE FROM ${this._qualifiedChatPinsTableName}
        WHERE chat_id IN (${placeholders.join(", ")})`,
      normalizedIds,
    );
  },

  async _deleteUserChatDraftsFromTable(chatIds, userId) {
    const normalizedIds = Array.from(
      new Set(
        (Array.isArray(chatIds) ? chatIds : [])
          .map((id) => String(id || "").trim())
          .filter(Boolean),
      ),
    );
    const normalizedUserId = String(userId || "").trim();
    if (normalizedIds.length === 0 || !normalizedUserId) {
      return;
    }
    const placeholders = normalizedIds.map((_, index) => `$${index + 1}`);
    await this._pool.query(
      `DELETE FROM ${this._qualifiedChatDraftsTableName}
        WHERE chat_id IN (${placeholders.join(", ")})
          AND user_id = $${normalizedIds.length + 1}`,
      [...normalizedIds, normalizedUserId],
    );
  },

  async deleteOrHideChatForUser(chatId, userId, options = {}) {
    await this.initialize();
    const result = await FileStore.prototype.deleteOrHideChatForUser.call(
      this,
      chatId,
      userId,
      options,
    );
    if (!result || result.error) {
      return result;
    }
    const eqIds = this._equivalentChatIdList(chatId, result.chatId || chatId);
    if (result.action === "deleted") {
      await this._purgeChatRowsFromTables(eqIds);
    } else if (result.action === "hidden" || result.action === "left") {
      await this._deleteUserChatDraftsFromTable(eqIds, userId);
    }
    return result;
  },

  async leaveGroupChat(chatId, userId) {
    await this.initialize();
    const result = await FileStore.prototype.leaveGroupChat.call(
      this,
      chatId,
      userId,
    );
    if (!result || typeof result !== "object") {
      return result;
    }
    const eqIds = this._equivalentChatIdList(chatId, result.id || chatId);
    if (result.deleted === true) {
      await this._purgeChatRowsFromTables(eqIds);
    } else {
      await this._deleteUserChatDraftsFromTable(eqIds, userId);
    }
    return result;
  },

};
