const fs = require("node:fs/promises");
const path = require("node:path");
const {
  computeProjectionHash,
  normalizeStateVersion,
} = require("./pool");
const {
  FileStore,
  EMPTY_DB,
  deepFreezeState,
  ensureCirclesForTree,
  normalizeDbState,
} = require("../../store");
const {backfillPersonIdentities} = require("../../migration-utils");

module.exports = {
  async _read() {
    await this.initialize();
    await this._hydrateCachedStateFromSnapshotCache();

    try {
      await this._awaitReadConsistency();
      // SPEED-8a: если version строки совпала с версией кэша — мир не
      // менялся, отдаём клон кэша (≈десятки мс вместо SELECT ~1 МБ +
      // parse + graph-sync + sidecar). Сессии накладываем свежими: их
      // проекционная таблица живёт отдельно от блоба.
      const currentVersion = await this._selectStateVersion();
      if (
        currentVersion !== null &&
        this._cachedState &&
        this._cachedVersion === currentVersion
      ) {
        const cachedState = structuredClone(this._cachedState);
        cachedState.sessions = await this._selectProjectedSessionsArray();
        this._lastSessionsProjectionHash = computeProjectionHash(cachedState.sessions);
        return cachedState;
      }
      const loaded = await this._loadSnapshot();
      const normalizedState = structuredClone(loaded.state);
      normalizedState.sessions = await this._selectProjectedSessionsArray();
      this._lastUsersProjectionHash = computeProjectionHash(normalizedState.users);
      this._lastSessionsProjectionHash = computeProjectionHash(normalizedState.sessions);
      this._syncGraphFromLegacy(normalizedState);
      this._commitCachedState(
        structuredClone(normalizedState),
        loaded.version,
      );
      await this._persistSnapshotCache(this._cachedState);
      return normalizedState;
    } catch (error) {
      return this._serveCachedSnapshotFallback(error, {phase: "read"});
    }
  },

  async _write(data) {
    // Phase 3.1c: mirror legacy → graph on the OUT-bound side too,
    // so the persisted snapshot already has the graph rows that
    // mirror whatever legacy mutation the caller just made. Safe
    // to call before _enqueueWrite — sync is idempotent and doesn't
    // touch I/O. (FileStore._write does the same; PostgresStore
    // overrides _write entirely so we have to mirror the call here.)
    if (data && typeof data === "object") {
      this._syncGraphFromLegacy(data);
    }
    return this._enqueueWrite("_stateWriteQueue", async () => {
      await this.initialize();
      // store-race guard: read the freshest persisted calls inside this
      // serialized write link and keep any terminal call terminal, so a write
      // built on a stale pre-teardown snapshot can't resurrect an ended call
      // (inherited FileStore._preserveTerminalCalls; same invariant as file).
      // SPEED-14: _preserveTerminalCalls only ever reads `.calls` off
      // whatever we hand it — it never looks at any other field — but this
      // used to fetch the ENTIRE ~1-2MB row (`SELECT data FROM ...`) just to
      // reach that one array, on EVERY single write app-wide (createPerson/
      // deletePerson/linkPersonToUser/createAuthHandoff included). Extracting
      // `data->'calls'` server-side (same COALESCE(data->'calls', '[]') idiom
      // already used for the real-time calls lookup a few hundred lines up)
      // gets the same array without transmitting or parsing the rest of the
      // blob.
      try {
        const currentResult = await this._pool.query(
          `SELECT data->'calls' AS calls FROM ${this._qualifiedTableName} WHERE id = $1`,
          [this._rowId],
        );
        const currentCalls = currentResult.rows?.[0]?.calls;
        const parsedCalls =
          typeof currentCalls === "string"
            ? JSON.parse(currentCalls)
            : currentCalls;
        this._preserveTerminalCalls(data, parsedCalls);
      } catch (_) {
        // First write / row absent — nothing persisted to preserve.
      }
      const treeChangeOps = this._pendingTreeChangeOps.splice(0);
      const deletedPersonOps = this._pendingDeletedPersonsOps.splice(0);
      data = await this._drainTransientNotificationCollections(data);
      data = await this._drainTreeChangeCollections(data);
      data = await this._drainDeletedPersonsCollection(data);
      const nextUsersHash = computeProjectionHash(data?.users);
      const nextSessionsHash = computeProjectionHash(data?.sessions);
      const nextChatsHash = computeProjectionHash(data?.chats);
      // SPEED-15: с маркером sessionsOutOfBlob сессии в JSONB-колонке не
      // нужны вообще — _read() на КАЖДОМ пути (попадание кэша и промах)
      // подменяет data.sessions содержимым проекционной таблицы, так что
      // то, что лежит в самой колонке, никогда не читается назад.
      const blobPayload =
        this._sessionsOutOfBlob && data && typeof data === "object"
          ? {...data, sessions: []}
          : data;
      const upsertResult = await this._pool.query(
        `
          INSERT INTO ${this._qualifiedTableName} (id, data, updated_at, version)
          VALUES ($1, $2::jsonb, NOW(), 1)
          ON CONFLICT (id) DO UPDATE
          SET data = EXCLUDED.data,
              updated_at = NOW(),
              version = ${this._qualifiedTableName}.version + 1
          RETURNING version
        `,
        [this._rowId, JSON.stringify(blobPayload)],
      );
      const writtenVersion = normalizeStateVersion(
        upsertResult?.rows?.[0]?.version,
      );
      await this._applyPendingTreeChangeOps(treeChangeOps);
      await this._applyPendingDeletedPersonsOps(deletedPersonOps);
      if (this._lastUsersProjectionHash !== nextUsersHash) {
        await this._replaceProjectedUsers(data.users);
      } else {
        this._lastUsersProjectionHash = nextUsersHash;
      }
      if (!this._sessionsOutOfBlob) {
        if (this._lastSessionsProjectionHash !== nextSessionsHash) {
          await this._replaceProjectedSessions(data.sessions);
        } else {
          this._lastSessionsProjectionHash = nextSessionsHash;
        }
      }
      if (this._lastChatsProjectionHash !== nextChatsHash) {
        await this._replaceChatProjection(data?.chats);
      } else {
        this._lastChatsProjectionHash = nextChatsHash;
      }
      // Клон: `data` остаётся у вызывающего и может мутировать дальше —
      // кэш, который теперь отдаётся на каждом чтении (и на каждом
      // попадании readSharedSnapshot() — БЕЗ повторного клона, см.
      // _commitCachedState), обязан быть своим. Кэш = только что
      // записанное состояние под его версией: следующее чтение после
      // записи не перечитывает блоб. Без RETURNING (fake-pool) версия
      // неизвестна → кэш не подтверждён → честное чтение.
      this._commitCachedState(structuredClone(normalizeDbState(data)), writtenVersion);
      await this._persistSnapshotCache(this._cachedState);
    });
  },

  // SPEED-11: единственная точка, где _cachedState получает НОВОЕ значение
  // одновременно с ПОДТВЕРЖДЁННОЙ версией строки — замораживает состояние
  // (deepFreezeState, store.js) РОВНО ОДИН РАЗ здесь же, так что
  // readSharedSnapshot() на попадании кэша отдаёт эту же ссылку без клона
  // и без повторного обхода дерева (deepFreezeState на уже замороженном
  // значении — O(1), см. её ранний возврат). Бут-миграции
  // (_migrateChatCollectionsToTables/_migrateNotificationCollectionsToTables/
  // _migrateTreeChangeCollectionsToTables/_backfillPersonIdentitiesInStateRow)
  // присваивают this._cachedState НАПРЯМУЮ, в обход этого метода, — они
  // никогда не подтверждают версию (см. комментарий у _cachedVersion в
  // конструкторе), поэтому их состояние в любом случае будет замещено
  // первым же честным _read()/readSharedSnapshot() ниже; замораживать его
  // там бессмысленно и означало бы трогать код миграций без необходимости
  // (вне периметра SPEED-11).
  _commitCachedState(state, version) {
    if (
      this._cachedState &&
      this._cachedVersion !== null &&
      version !== null &&
      version < this._cachedVersion
    ) {
      return this._cachedState;
    }
    deepFreezeState(state);
    this._cachedState = state;
    this._cachedVersion = version;
    return state;
  },

  // SPEED-11: single-flight обёртка над _selectStateVersion() специально
  // для readSharedSnapshot() — на бёрсте параллельных GET (10-12 запросов
  // за один вход клиента, см. docs/speed_measurement.md) все конкурентные
  // попадания в кэш ждут ОДИН общий SELECT version вместо одного на
  // каждый вызов. Промис вычищается сразу после разрешения (успех ИЛИ
  // ошибка) — следующий вызов (даже в следующем тике) идёт в БД заново,
  // так что это схлопывает только конкурентность ВНУТРИ одного всплеска,
  // не кэширует свежесть на будущее (тот же паттерн, что и у _loadSnapshot
  // ниже).
  _sharedVersionCheck() {
    if (this._versionQueryPromise) {
      return this._versionQueryPromise;
    }
    this._versionQueryPromise = this._selectStateVersion().finally(() => {
      this._versionQueryPromise = null;
    });
    return this._versionQueryPromise;
  },

  // SPEED-11: промах readSharedSnapshot() — честная перезагрузка блоба,
  // схлопнутая в один общий полёт на конкурентный бёрст промахов (иначе N
  // параллельных промахов делали бы N SELECT+normalizeDbState+граф-синк+
  // sidecar-запись, хотя итог для всех N одинаков). _loadSnapshot() уже
  // single-flight'ит сам SQL (её собственный _snapshotLoadPromise) — этот
  // промис достраивает поверх граф-синк + freeze + коммит кэша + sidecar,
  // которые _loadSnapshot() не делает и которые дороги при повторе на
  // большом снимке (deepFreezeState — O(размера состояния) на первом,
  // ещё НЕзамороженном значении).
  //
  // Зеркалит промах-ветку _read() один в один (кроме db.sessions — см.
  // readSharedSnapshot), включая обновление _lastUsersProjectionHash:
  // без него следующий _write() решил бы, что таблица-проекция
  // пользователей разошлась с блобом, и лишний раз переписала бы её.
  // _lastSessionsProjectionHash сознательно НЕ трогаем — readSharedSnapshot()
  // не читает db.sessions вообще, это и есть половина экономии SPEED-11.
  async _refreshSharedSnapshotOnMiss() {
    if (this._cacheRefreshPromise) {
      return this._cacheRefreshPromise;
    }
    this._cacheRefreshPromise = (async () => {
      const loaded = await this._loadSnapshot();
      const normalizedState = structuredClone(loaded.state);
      this._lastUsersProjectionHash = computeProjectionHash(normalizedState.users);
      this._syncGraphFromLegacy(normalizedState);
      this._commitCachedState(
        structuredClone(normalizedState),
        loaded.version,
      );
      await this._persistSnapshotCache(this._cachedState);
      return this._cachedState;
    })().finally(() => {
      this._cacheRefreshPromise = null;
    });
    return this._cacheRefreshPromise;
  },

  // SPEED-11: как _read(), но БЕЗ клона на попадании кэша и БЕЗ SQL
  // сессий — для GET-маршрутов, которым нужен блоб только чтобы передать
  // его дальше как prefetchedDb/db (requireTreeAccess в app.js кладёт
  // результат на req.storeSnapshot; шесть маршрутов бёрста входа —
  // persons/person/graph/gatherings/polls/stories — прокидывают его в
  // findMembership/listPersons/findPerson/listHiddenPersonIdsForCaller/
  // getTreeGraphSnapshot/listGatherings/listPolls/listStories). Ни один
  // из них не читает db.sessions и не мутирует db — полный аудит
  // (включая ensureCirclesForTree/backfillPersonIdentities под
  // капотом _canUserViewCircleContent) в docs/speed_measurement.md,
  // раздел SPEED-11.
  //
  // На попадании кэша единственный SQL — проверка версии (single-flight,
  // см. _sharedVersionCheck); 0 structuredClone (~480 КБ на прод-блобе),
  // 0 SELECT session_data. На промахе — честная перезагрузка, тоже
  // single-flight (_refreshSharedSnapshotOnMiss). Возвращаемое значение
  // ВСЕГДА глубоко заморожено и без db.sessions (см. _buildSharedSnapshotView
  // в store.js) — вызывающий, который попробует мутировать снимок или
  // прочитать .sessions, получит явную ошибку вместо тихого искажения
  // общего для всех запросов состояния.
  async readSharedSnapshot() {
    await this.initialize();
    await this._hydrateCachedStateFromSnapshotCache();

    try {
      await this._awaitReadConsistency();
      const currentVersion = await this._sharedVersionCheck();
      if (
        currentVersion !== null &&
        this._cachedState &&
        this._cachedVersion === currentVersion
      ) {
        return this._sharedSnapshotViewFor(deepFreezeState(this._cachedState));
      }

      const refreshed = await this._refreshSharedSnapshotOnMiss();
      return this._sharedSnapshotViewFor(refreshed);
    } catch (error) {
      const fallback = this._serveCachedSnapshotFallback(error, {phase: "read"});
      return this._sharedSnapshotViewFor(deepFreezeState(fallback));
    }
  },

  // SPEED-11: _buildSharedSnapshotView (store.js) строит {...state} заново
  // на каждый вызов — дёшево по CPU (shallow-spread верхнего уровня), но
  // отдавало бы РАЗНЫЙ объект-обёртку на каждый readSharedSnapshot(), даже
  // когда `state` (== this._cachedState) не менялся. Это ломает контракт
  // «попадание отдаёт ОДИН И ТОТ ЖЕ объект» — важно не само по себе, а
  // потому что requireTreeAccess (app.js) кладёт результат на
  // req.storeSnapshot ОДИН раз и полагается на то, что это один и тот же
  // объект для ВСЕХ store-методов в рамках HTTP-запроса. Кэшируем обёртку
  // по ССЫЛКЕ на исходное состояние: `state` меняется только через
  // _commitCachedState (полная переприсвоение, никогда мутация на месте),
  // так что сравнение по ссылке — само по себе корректная инвалидация без
  // отдельного счётчика версий.
  _sharedSnapshotViewFor(state) {
    if (this._sharedSnapshotView && this._sharedSnapshotViewSource === state) {
      return this._sharedSnapshotView;
    }
    const view = this._buildSharedSnapshotView(state);
    this._sharedSnapshotViewSource = state;
    this._sharedSnapshotView = view;
    return view;
  },

  async _loadSnapshot() {
    if (this._snapshotLoadPromise) {
      return this._snapshotLoadPromise;
    }

    this._snapshotLoadPromise = this._readSnapshotWithRetry()
      .then((row) => ({
        state: normalizeDbState(row.data),
        version: row.version,
      }))
      .finally(() => {
        this._snapshotLoadPromise = null;
      });

    return this._snapshotLoadPromise;
  },

  /// Строка снимка → {data, version}. version = null, если колонки нет
  /// (fake-pool в тестах, БД до миграции) — тогда кэш просто не работает.
  _snapshotRowFromResult(result) {
    const row = result?.rows?.[0];
    return {
      data: row?.data ?? EMPTY_DB,
      version: normalizeStateVersion(row?.version),
    };
  },

  /// Дешёвая проверка «мир изменился?»: только version, без блоба.
  /// Любая ошибка → null → полное чтение (кэш никогда не маскирует БД).
  async _selectStateVersion() {
    try {
      const result = await this._pool.query(
        `SELECT version FROM ${this._qualifiedTableName} WHERE id = $1`,
        [this._rowId],
      );
      return normalizeStateVersion(result?.rows?.[0]?.version);
    } catch (_) {
      return null;
    }
  },

  async _readSnapshotWithRetry() {
    let lastError = null;
    const attempts = Math.max(1, this._readRetryCount + 1);
    for (let attempt = 0; attempt < attempts; attempt += 1) {
      try {
        return await this._readSnapshotFromDatabase();
      } catch (error) {
        lastError = error;
        if (!this._isRetriableReadError(error) || attempt >= attempts - 1) {
          break;
        }
        if (this._readRetryDelayMs > 0) {
          await new Promise((resolve) => setTimeout(resolve, this._readRetryDelayMs));
        }
      }
    }
    throw lastError;
  },

  async _readSnapshotFromDatabase() {
    const queryText = `SELECT data, version FROM ${this._qualifiedTableName} WHERE id = $1`;
    const queryValues = [this._rowId];

    if (typeof this._pool.connect !== "function") {
      const result = await this._pool.query(queryText, queryValues);
      return this._snapshotRowFromResult(result);
    }

    const client = await this._pool.connect();
    try {
      if (this._readQueryTimeoutMs > 0) {
        await client.query("BEGIN");
        await client.query(
          `SET LOCAL statement_timeout = ${this._readQueryTimeoutMs}`,
        );
      }
      const result = await client.query({
        text: queryText,
        values: queryValues,
        query_timeout: this._readQueryTimeoutMs > 0
          ? this._readQueryTimeoutMs
          : undefined,
      });
      if (this._readQueryTimeoutMs > 0) {
        await client.query("COMMIT");
      }
      return this._snapshotRowFromResult(result);
    } catch (error) {
      if (this._readQueryTimeoutMs > 0) {
        try {
          await client.query("ROLLBACK");
        } catch (_) {
          // Ignore rollback failures after read timeout.
        }
      }
      throw error;
    } finally {
      client.release();
    }
  },

  _isRetriableReadError(error) {
    const message = String(error?.message || "").toLowerCase();
    const code = String(error?.code || "").trim().toUpperCase();
    return (
      code === "POSTGRES_WRITE_QUEUE_TIMEOUT" ||
      message.includes("query read timeout") ||
      message.includes("statement timeout") ||
      message.includes("write queue timed out") ||
      message.includes("connection timeout") ||
      code === "57014" ||
      code === "ETIMEDOUT"
    );
  },

  _serveCachedSnapshotFallback(error, {phase} = {}) {
    if (!this._cachedState || !this._isRetriableReadError(error)) {
      throw error;
    }

    console.warn(
      "[backend] postgres-store serving cached snapshot",
      JSON.stringify({
        table: `${this._schema}.${this._table}`,
        rowId: this._rowId,
        phase: String(phase || "read"),
        message: String(error?.message || error || "unknown_error"),
      }),
    );
    return structuredClone(this._cachedState);
  },

  async _hydrateCachedStateFromSnapshotCache() {
    if (this._cachedState || !this._snapshotCachePath) {
      return;
    }
    if (!this._snapshotCacheHydrationPromise) {
      this._snapshotCacheHydrationPromise = fs.readFile(
        this._snapshotCachePath,
        "utf8",
      )
        .then((rawSnapshot) => {
          const parsedSnapshot = JSON.parse(rawSnapshot);
          this._cachedState = normalizeDbState(parsedSnapshot);
        })
        .catch((error) => {
          if (error?.code === "ENOENT") {
            return;
          }
          console.warn(
            "[backend] postgres-store snapshot cache hydrate failed",
            JSON.stringify({
              table: `${this._schema}.${this._table}`,
              rowId: this._rowId,
              path: this._snapshotCachePath,
              message: String(error?.message || error || "unknown_error"),
            }),
          );
        })
        .finally(() => {
          this._snapshotCacheHydrationPromise = null;
        });
    }
    await this._snapshotCacheHydrationPromise;
  },

  // SPEED-14: the sidecar snapshot file is a boot/outage fallback ONLY —
  // _hydrateCachedStateFromSnapshotCache() reads it once at boot before the
  // first real _read(), and _serveCachedSnapshotFallback() reaches for it
  // only when a live DB read/write fails. Nothing on the hot read/write path
  // ever trusts it for correctness (that's _cachedState/_cachedVersion,
  // SPEED-8a/11) — so it never needs to block the response the caller is
  // building. Every _persistSnapshotCache() call site (_write, the boot
  // migrations, the read-miss refill) used to `await` a full
  // JSON.stringify(~1-2MB) + fs.writeFile + implicit fsync-on-close of the
  // ENTIRE state on every single write/miss, all before the client got its
  // answer — e.g. createPerson/deletePerson/linkPersonToUser/
  // createAuthHandoff's own _write() call, or the cache-miss _read() a
  // request like dispatchTreeMutation triggers right after a write. Now the
  // call schedules the write and returns immediately; the actual fs work
  // happens in the background on _snapshotCacheWriteChain.
  //
  // Coalesced, not merely queued: if a newer snapshot arrives while a
  // write is still in flight, only the LATEST one is persisted next — we
  // never need to burn a disk write on an intermediate snapshot nobody will
  // ever read (the sidecar is a point-in-time fallback, not a log). If the
  // process crashes before a scheduled write lands, the worst case is a
  // stale (or, on first boot, missing) sidecar — bootstrap already treats
  // "no valid sidecar" as normal (falls back to an honest DB read), so this
  // trades "always fresh on disk" for "fresh soon, never blocks", which is
  // exactly the tradeoff a read-only fallback cache should make.
  //
  // close()/_flushSnapshotCacheWrites() await the chain, so graceful
  // shutdown and tests that assert on the sidecar's final contents still
  // see it land.
  _persistSnapshotCache(snapshot) {
    if (!this._snapshotCachePath || !snapshot) {
      return;
    }
    this._pendingSnapshotCacheWrite = snapshot;
    if (!this._snapshotCacheWriteChain) {
      this._snapshotCacheWriteChain = this._drainSnapshotCacheWrites();
    }
  },

  async _drainSnapshotCacheWrites() {
    while (this._pendingSnapshotCacheWrite) {
      const next = this._pendingSnapshotCacheWrite;
      this._pendingSnapshotCacheWrite = null;
      // eslint-disable-next-line no-await-in-loop
      await this._writeSnapshotCacheFile(next);
    }
    this._snapshotCacheWriteChain = null;
  },

  async _writeSnapshotCacheFile(snapshot) {
    try {
      await fs.mkdir(path.dirname(this._snapshotCachePath), {recursive: true});
      await fs.writeFile(
        this._snapshotCachePath,
        JSON.stringify(snapshot),
        "utf8",
      );
    } catch (error) {
      console.warn(
        "[backend] postgres-store snapshot cache persist failed",
        JSON.stringify({
          table: `${this._schema}.${this._table}`,
          rowId: this._rowId,
          path: this._snapshotCachePath,
          message: String(error?.message || error || "unknown_error"),
        }),
      );
    }
  },

  // Test/shutdown hook: wait for any in-flight or still-pending sidecar
  // write to land. Purely additive — nothing on the request path calls
  // this; it exists so close() can shut down cleanly and so tests can
  // assert on the sidecar file's final contents without racing the
  // background write.
  async _flushSnapshotCacheWrites() {
    while (this._snapshotCacheWriteChain) {
      // eslint-disable-next-line no-await-in-loop
      await this._snapshotCacheWriteChain;
    }
  },

  async _awaitWriteQueue(queuePromise = this._stateWriteQueue) {
    const pendingWrite = queuePromise.catch(() => {});
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
  },

};
