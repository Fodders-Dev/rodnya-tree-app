const crypto = require("node:crypto");
const fs = require("node:fs/promises");
const path = require("node:path");
const {Pool} = require("pg");

const {
  FileStore,
  EMPTY_DB,
  computeNotificationCoalesceKey,
  decodeNotificationCursor,
  encodeNotificationCursor,
  createNotificationRecord,
  createPushDeliveryRecord,
  buildChatSearchSnippet,
  buildPersonRecord,
  chatMessageSearchHaystack,
  cloneUserWithAuthState,
  collectMessageMediaUrls,
  createChatDraftRecord,
  createChatPinRecord,
  createPersonIdentityRecord,
  deepFreezeState,
  deriveSessionPublicId,
  describeMessagePreview,
  ensureCirclesForTree,
  isMessageReadByUser,
  normalizeChatMessageCall,
  normalizeChatSearchQuery,
  normalizeDbState,
  stripTreeChangeRecordDetails,
  isHardDeleteAuditEntryExpired,
  normalizeNullableString,
  normalizeOptionalIsoTimestamp,
  normalizeParticipantIds,
  normalizeReactionEmoji,
  normalizeSessionDeviceContext,
  normalizeStoredCall,
  nowIso,
  parseDirectParticipantsFromChatId,
  SESSION_TOUCH_MIN_INTERVAL_MS,
  verifyPassword,
} = require("./store");
const {
  normalizeMessageAttachments,
  normalizeReplyReference,
} = require("./chat-utils");
const {backfillPersonIdentities} = require("./migration-utils");


const {
  DEFAULT_POSTGRES_CONNECTION_TIMEOUT_MS,
  DEFAULT_POSTGRES_QUERY_TIMEOUT_MS,
  DEFAULT_POSTGRES_READ_QUERY_TIMEOUT_MS,
  DEFAULT_POSTGRES_READ_RETRY_COUNT,
  DEFAULT_POSTGRES_READ_RETRY_DELAY_MS,
  DEFAULT_POSTGRES_IDLE_TIMEOUT_MS,
  DEFAULT_WRITE_QUEUE_TIMEOUT_MS,
  DEFAULT_POSTGRES_POOL_MAX,
  DEFAULT_POSTGRES_APPLICATION_NAME,
  quoteIdentifier,
  acquireSharedPool,
  normalizeStateVersion,
} = require("./store/postgres/pool");
const pgChatsMethods = require("./store/postgres/pg-chats");
const pgNotificationsMethods = require("./store/postgres/pg-notifications");
const pgAuthSessionsMethods = require("./store/postgres/pg-auth-sessions");
const pgCascadesFastpathsMethods = require("./store/postgres/pg-cascades-fastpaths");
const pgTreeChangesMethods = require("./store/postgres/pg-tree-changes");
const pgDeletedPersonsMethods = require("./store/postgres/pg-deleted-persons");
const pgDiagnosticsMethods = require("./store/postgres/pg-diagnostics");
const pgSnapshotCacheMethods = require("./store/postgres/pg-snapshot-cache");

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
    readQueryTimeoutMs = DEFAULT_POSTGRES_READ_QUERY_TIMEOUT_MS,
    readRetryCount = DEFAULT_POSTGRES_READ_RETRY_COUNT,
    readRetryDelayMs = DEFAULT_POSTGRES_READ_RETRY_DELAY_MS,
    writeQueueTimeoutMs = null,
    idleTimeoutMillis = DEFAULT_POSTGRES_IDLE_TIMEOUT_MS,
    poolMax = DEFAULT_POSTGRES_POOL_MAX,
    applicationName = DEFAULT_POSTGRES_APPLICATION_NAME,
    snapshotCachePath = null,
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
    // SPEED-6: горячие чат-коллекции живут в собственных таблицах, а не в
    // JSONB-блобе — send = INSERT, access-check = индексный SELECT.
    this._chatMessagesTable = `${this._table}_chat_messages`;
    this._chatReactionsTable = `${this._table}_chat_reactions`;
    this._chatDraftsTable = `${this._table}_chat_drafts`;
    this._chatPinsTable = `${this._table}_chat_pins`;
    this._chatsProjectionTable = `${this._table}_chats_projection`;
    this._chatParticipantsTable = `${this._table}_chat_participants`;
    this._chatBackupsTable = `${this._table}_chat_backups`;
    this._qualifiedChatMessagesTableName = `${quoteIdentifier(this._schema)}.${quoteIdentifier(this._chatMessagesTable)}`;
    this._qualifiedChatReactionsTableName = `${quoteIdentifier(this._schema)}.${quoteIdentifier(this._chatReactionsTable)}`;
    this._qualifiedChatDraftsTableName = `${quoteIdentifier(this._schema)}.${quoteIdentifier(this._chatDraftsTable)}`;
    this._qualifiedChatPinsTableName = `${quoteIdentifier(this._schema)}.${quoteIdentifier(this._chatPinsTable)}`;
    this._qualifiedChatsProjectionTableName = `${quoteIdentifier(this._schema)}.${quoteIdentifier(this._chatsProjectionTable)}`;
    this._qualifiedChatParticipantsTableName = `${quoteIdentifier(this._schema)}.${quoteIdentifier(this._chatParticipantsTable)}`;
    this._qualifiedChatBackupsTableName = `${quoteIdentifier(this._schema)}.${quoteIdentifier(this._chatBackupsTable)}`;
    // SPEED-7: notifications и pushDeliveries уезжают из блоба целиком —
    // фан-аут уведомлений = INSERT'ы вместо whole-blob RMW на каждую запись.
    this._notificationsTable = `${this._table}_notifications`;
    this._pushDeliveriesTable = `${this._table}_push_deliveries`;
    this._notificationBackupsTable = `${this._table}_notification_backups`;
    // SPEED-8b: журнал изменений дерева + аудит hard-delete — в таблицах.
    this._treeChangeRecordsTable = `${this._table}_tree_change_records`;
    this._hardDeleteAuditTable = `${this._table}_hard_delete_audit`;
    this._treeChangeBackupsTable = `${this._table}_tree_change_backups`;
    this._qualifiedTreeChangeRecordsTableName = `${quoteIdentifier(this._schema)}.${quoteIdentifier(this._treeChangeRecordsTable)}`;
    this._qualifiedHardDeleteAuditTableName = `${quoteIdentifier(this._schema)}.${quoteIdentifier(this._hardDeleteAuditTable)}`;
    this._qualifiedTreeChangeBackupsTableName = `${quoteIdentifier(this._schema)}.${quoteIdentifier(this._treeChangeBackupsTable)}`;
    this._qualifiedNotificationsTableName = `${quoteIdentifier(this._schema)}.${quoteIdentifier(this._notificationsTable)}`;
    this._qualifiedPushDeliveriesTableName = `${quoteIdentifier(this._schema)}.${quoteIdentifier(this._pushDeliveriesTable)}`;
    this._qualifiedNotificationBackupsTableName = `${quoteIdentifier(this._schema)}.${quoteIdentifier(this._notificationBackupsTable)}`;
    // SPEED-15: корзина deletedPersons (245 КБ/220 записей на проде) — в
    // таблице. Не append-only (restore мутирует строку, hard-delete удаляет
    // её), поэтому в отличие от treeChangeRecords нужна не только «дренаж
    // новых записей», но и операционная очередь (см. _queueDeletedPersonOp).
    this._deletedPersonsTable = `${this._table}_deleted_persons`;
    this._deletedPersonsBackupsTable = `${this._table}_deleted_persons_backups`;
    this._qualifiedDeletedPersonsTableName = `${quoteIdentifier(this._schema)}.${quoteIdentifier(this._deletedPersonsTable)}`;
    this._qualifiedDeletedPersonsBackupsTableName = `${quoteIdentifier(this._schema)}.${quoteIdentifier(this._deletedPersonsBackupsTable)}`;
    this._deletedPersonsTablesReady = false;
    this._pendingDeletedPersonsOps = [];
    // SPEED-15: clientDiagnostics (ring-buffer на 500 записей) — в таблице.
    // Append-only + собственный cap, читается только /v1/admin — createClient
    // Diagnostic/listClientDiagnostics полностью переезжают на SQL, блоб-
    // массив после миграции больше никто не пополняет (см. оверрайды ниже).
    this._clientDiagnosticsTable = `${this._table}_client_diagnostics`;
    this._clientDiagnosticsBackupsTable = `${this._table}_client_diagnostics_backups`;
    this._qualifiedClientDiagnosticsTableName = `${quoteIdentifier(this._schema)}.${quoteIdentifier(this._clientDiagnosticsTable)}`;
    this._qualifiedClientDiagnosticsBackupsTableName = `${quoteIdentifier(this._schema)}.${quoteIdentifier(this._clientDiagnosticsBackupsTable)}`;
    this._clientDiagnosticsTablesReady = false;
    // SPEED-15: sessions уже не читаются из блоба ни на одном пути _read()
    // (проекционная таблица SPEED-6/8a — единственный источник при чтении);
    // маркер sessionsOutOfBlob останавливает и запись блоба, и повторное
    // затирание проекции блобом на буте (см. _hydrateAuthProjectionTables
    // FromStateRow и _migrateSessionsOutOfBlob).
    this._sessionsBackupsTable = `${this._table}_sessions_backups`;
    this._qualifiedSessionsBackupsTableName = `${quoteIdentifier(this._schema)}.${quoteIdentifier(this._sessionsBackupsTable)}`;
    this._sessionsOutOfBlob = false;
    // SPEED-7: гейт готовности — false, пока бут-миграция не подтвердила
    // маркер. При транзиентно недоступном состоянии миграция скипается, и
    // ВСЕ notification-оверрайды делегируют в FileStore-путь по блобу:
    // иначе тихая пустая лента + drain обнулил бы массивы ДО миграции и
    // write-once бэкап отката навсегда запомнил бы пустоту (ревью, P1).
    this._notificationTablesReady = false;
    this._treeChangeTablesReady = false;
    // Табличные операции, поставленные хуками из _mutate-applyFn (там
    // нельзя await'ить SQL); применяет _write после UPSERT, по порядку.
    this._pendingTreeChangeOps = [];
    this._lastChatsProjectionHash = null;
    this._chatPurgeSweepScheduled = false;
    this._chatsProjectionDirty = false;
    this._chatRowMutationQueue = Promise.resolve();
    this._initializePromise = null;
    this._cachedState = null;
    // SPEED-8a: version строки rodnya_state, которой соответствует
    // _cachedState. null = кэш не подтверждён (после буста из sidecar,
    // после fallback'а, после fake-pool без version) → _read идёт в БД.
    this._cachedVersion = null;
    // SPEED-11: single-flight для «проверка версии» (SELECT version FROM) —
    // конкурентный бёрст readSharedSnapshot() на попадании кэша ждёт ОДИН
    // общий SQL, а не по одному на каждый вызов. Не даёт временного окна:
    // очищается сразу после разрешения, следующий вызов (даже сразу после)
    // идёт в БД заново — только конкурентность схлопывается, не свежесть.
    this._versionQueryPromise = null;
    // SPEED-11: single-flight для «промах — перечитать и закоммитить кэш»
    // (_refreshSharedSnapshotOnMiss) — без этого конкурентный бёрст
    // промахов (например, сразу после чужой записи) делал бы N честных
    // SELECT+structuredClone+_syncGraphFromLegacy+sidecar-запись вместо
    // одного. _cachedState сам служит «замороженным разделяемым снимком»
    // (см. _commitCachedState) — отдельного поля под него не нужно.
    this._cacheRefreshPromise = null;
    // SPEED-11: обёртка без db.sessions (_buildSharedSnapshotView) поверх
    // _cachedState, кэшированная по ССЫЛКЕ на исходное состояние — контракт
    // readSharedSnapshot() («попадание отдаёт ОДИН И ТОТ ЖЕ объект») не
    // выполнялся бы, если строить {...state} заново на каждый вызов (это
    // дёшево по CPU, но ломает === для вызывающих, которые полагаются на
    // идентичность — ровно как req.storeSnapshot в app.js должен быть
    // одним объектом на весь HTTP-запрос). _cachedState ВСЕГДА переприсва-
    // ивается целиком, никогда не мутируется на месте (см. _commitCachedState
    // и аудит SPEED-11 в docs/speed_measurement.md) — поэтому сравнение по
    // ссылке (_sharedSnapshotViewSource === state) само по себе и есть
    // инвалидация: как только _cachedState заменился (запись/промах/прайм),
    // ссылка перестаёт совпадать и обёртка перестраивается.
    this._sharedSnapshotView = null;
    this._sharedSnapshotViewSource = null;
    this._snapshotLoadPromise = null;
    this.storageMode = "postgres";
    this.storageTarget = `${this._schema}.${this._table}:${this._rowId}`;
    const normalizedWriteQueueTimeoutMs = Number(writeQueueTimeoutMs);
    this._writeQueueTimeoutMs =
      Number.isFinite(normalizedWriteQueueTimeoutMs) &&
      normalizedWriteQueueTimeoutMs > 0
        ? Math.floor(normalizedWriteQueueTimeoutMs)
        : queryTimeoutMs > 0
          ? Math.max(queryTimeoutMs, DEFAULT_WRITE_QUEUE_TIMEOUT_MS)
          : DEFAULT_WRITE_QUEUE_TIMEOUT_MS;
    this._readQueryTimeoutMs =
      Number.isFinite(Number(readQueryTimeoutMs)) && Number(readQueryTimeoutMs) > 0
        ? Math.floor(Number(readQueryTimeoutMs))
        : 0;
    this._readRetryCount =
      Number.isFinite(Number(readRetryCount)) && Number(readRetryCount) >= 0
        ? Math.floor(Number(readRetryCount))
        : DEFAULT_POSTGRES_READ_RETRY_COUNT;
    this._readRetryDelayMs =
      Number.isFinite(Number(readRetryDelayMs)) && Number(readRetryDelayMs) >= 0
        ? Math.floor(Number(readRetryDelayMs))
        : DEFAULT_POSTGRES_READ_RETRY_DELAY_MS;
    this._snapshotCachePath = String(snapshotCachePath || "").trim() || null;
    this._snapshotCacheHydrationPromise = null;
    this._stateWriteQueue = Promise.resolve();
    this._sessionWriteQueue = Promise.resolve();
    this._writeQueue = this._stateWriteQueue;
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
    // SPEED-8a: монотонная версия строки. Инкрементится КАЖДЫМ писателем
    // (UPSERT в _write и все точечные UPDATE ниже — статический тест в
    // postgres-store.test.js это сторожит); _read() сверяет её с кэшем.
    try {
      await this._pool.query(`
        ALTER TABLE ${this._qualifiedTableName}
          ADD COLUMN IF NOT EXISTS version BIGINT NOT NULL DEFAULT 0
      `);
    } catch (error) {
      // Кэш — оптимизация: без колонки _selectStateVersion вернёт null и
      // каждое чтение честно пойдёт в БД. Но молчать нельзя — это
      // потеря ×10 на всех горячих путях.
      console.warn(
        "[backend] postgres-store version column unavailable — read cache disabled",
        JSON.stringify({
          table: `${this._schema}.${this._table}`,
          message: String(error?.message || error || "unknown_error").slice(0, 200),
        }),
      );
    }
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
    try {
      await this._pool.query(`
        CREATE INDEX IF NOT EXISTS ${quoteIdentifier(`${this._table}_messages_fts_idx`)}
          ON ${this._qualifiedTableName}
          USING GIN (to_tsvector('russian', COALESCE(data->>'messages', '')))
      `);
    } catch (error) {
      const message = String(error?.message || "").toLowerCase();
      if (
        !message.includes("to_tsvector") &&
        !message.includes("text search configuration")
      ) {
        throw error;
      }
      console.warn(
        "[backend] postgres-store skipped message fts index",
        JSON.stringify({
          table: `${this._schema}.${this._table}`,
          rowId: this._rowId,
          message: error?.message || String(error),
        }),
      );
    }
    await this._createChatTables();
    await this._createNotificationTables();
    await this._createTreeChangeTables();
    await this._createDeletedPersonsTables();
    await this._createClientDiagnosticsTables();
    await this._createSessionsBackupsTable();

    // SPEED-9 C-boot (docs/speed9_proposal.md §5): раньше КАЖДЫЙ из шагов
    // ниже делал свой собственный SELECT data FROM + normalizeDbState —
    // ≥5 полных чтений+парсингов блоба на КАЖДЫЙ рестарт процесса, хотя
    // на уже мигрированном проде каждому шагу нужно только увидеть один
    // и тот же маркер migrationStatus.*ToTables = "complete-v1". Теперь
    // строка читается ОДИН раз, и разобранное состояние прокидывается
    // через все шаги опциональным параметром. Свежесть: любой шаг,
    // который РЕАЛЬНО записал строку (backfill что-то изменил / миграция
    // выполнилась), возвращает {state, version} уже ПОСЛЕ своей записи —
    // следующий шаг видит актуальные данные, не читая блоб заново.
    // Если общий снимок недоступен (БД моргнула ровно в этот момент) —
    // деградация 1:1 к поведению до этого чанка: каждый шаг вызывается
    // без аргумента и сам делает свой SELECT, сам решает, что делать при
    // неудаче (см. postgres-notification-tables.test.js «скип миграции
    // (БД моргнула)» — этот путь проверяет ровно старое поведение).
    const bootRow = await this._readBootStateRow();
    if (bootRow) {
      let cursor = await this._backfillPersonIdentitiesInStateRow(bootRow);
      await this._hydrateAuthProjectionTablesFromStateRow(cursor?.state);
      cursor = await this._migrateChatCollectionsToTables(cursor);
      cursor = await this._migrateNotificationCollectionsToTables(cursor);
      cursor = await this._migrateTreeChangeCollectionsToTables(cursor);
      cursor = await this._migrateDeletedPersonsToTables(cursor);
      cursor = await this._migrateClientDiagnosticsToTables(cursor);
      cursor = await this._migrateSessionsOutOfBlob(cursor);
      await this._hydrateChatProjectionFromState(cursor?.state);
      // Прогрев кэша: первый настоящий _read() после буста должен сразу
      // попасть в кэш вместо гарантированного промаха (_cachedVersion до
      // этого чанка оставался null весь бут независимо от того, менялись
      // ли данные — см. SPEED-8a). Валидно ТОЛЬКО когда version реально
      // подтверждена (либо version строки на момент чтения, если никто
      // не писал, либо RETURNING с последней записи) — иначе, как и
      // раньше, первый _read() честно перечитает БД.
      if (
        cursor &&
        cursor.state &&
        cursor.version !== null &&
        cursor.version !== undefined
      ) {
        // Как на промахе _read(): зеркало графа синхронизируется с
        // легаси-коллекциями ДО попадания состояния в кэш — иначе первые
        // попадания отдавали бы несинхронизированный граф до ближайшей
        // записи (Phase 3.1c; идемпотентно, O(N) после SPEED-9 A).
        const primed = structuredClone(cursor.state);
        this._syncGraphFromLegacy(primed);
        this._commitCachedState(primed, cursor.version);
      }
    } else {
      await this._backfillPersonIdentitiesInStateRow();
      await this._hydrateAuthProjectionTablesFromStateRow();
      await this._migrateChatCollectionsToTables();
      await this._migrateNotificationCollectionsToTables();
      await this._migrateTreeChangeCollectionsToTables();
      await this._migrateDeletedPersonsToTables();
      await this._migrateClientDiagnosticsToTables();
      await this._migrateSessionsOutOfBlob();
      await this._hydrateChatProjectionFromState();
    }
  }

  // SPEED-9 C-boot: единственное чтение строки состояния для всего буста
  // (см. комментарий в _bootstrap()). Любая ошибка чтения — null целиком:
  // вызывающий уходит в старый режим независимых чтений на каждом шаге
  // (защита от «БД моргнула»).
  async _readBootStateRow() {
    try {
      // ПОРЯДОК ВАЖЕН: сначала version, потом data. Если чужая запись
      // проскочит между двумя запросами, кэш получит НОВЫЕ данные под
      // СТАРОЙ версией — первый _read() увидит несовпадение и честно
      // перечитает (одно лишнее чтение). Обратный порядок (data, потом
      // version) дал бы старые данные под новой версией — устаревший кэш
      // до следующей записи, молча ломая SPEED-8a-инвариант. Версия —
      // отдельный дешёвый запрос (_selectStateVersion гасит ошибку в
      // null → кэш просто не прогреется), а не второй SELECT блоба.
      const version = await this._selectStateVersion();
      const result = await this._pool.query(
        `SELECT data FROM ${this._qualifiedTableName} WHERE id = $1`,
        [this._rowId],
      );
      const rawData = result.rows[0]?.data ?? EMPTY_DB;
      const state = normalizeDbState(
        typeof rawData === "string" ? JSON.parse(rawData) : rawData,
      );
      return {state, version};
    } catch (error) {
      console.warn(
        "[backend] postgres-store bootstrap snapshot read failed — steps will read individually",
        JSON.stringify({
          table: `${this._schema}.${this._table}`,
          rowId: this._rowId,
          message: error?.message || String(error),
        }),
      );
      return null;
    }
  }


  static _normalizeStateVersion(raw) {
    return normalizeStateVersion(raw);
  }

  async close() {
    await Promise.allSettled([this._stateWriteQueue, this._sessionWriteQueue]);
    // SPEED-14: the sidecar snapshot write is now backgrounded (see
    // _persistSnapshotCache) — drain it before tearing down the pool so a
    // graceful shutdown doesn't drop the last write's fallback-cache copy.
    await this._flushSnapshotCacheWrites();
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

Object.assign(
  PostgresStore.prototype,
  pgChatsMethods,
  pgNotificationsMethods,
  pgAuthSessionsMethods,
  pgCascadesFastpathsMethods,
  pgTreeChangesMethods,
  pgDeletedPersonsMethods,
  pgDiagnosticsMethods,
  pgSnapshotCacheMethods,
);

module.exports = {
  PostgresStore,
};
