const fs = require("node:fs/promises");
const {
  isProjectionArrayTextFallbackError,
  normalizeStateVersion,
} = require("./pool");
const {
  FileStore,
  buildPersonRecord,
  collectMessageMediaUrls,
  createPersonIdentityRecord,
  stripTreeChangeRecordDetails,
  normalizeParticipantIds,
  normalizeStoredCall,
  nowIso,
  parseDirectParticipantsFromChatId,
} = require("../../store");

module.exports = {
  _runOnMutateQueue(operation) {
    if (!this._mutateQueue) {
      this._mutateQueue = Promise.resolve();
    }
    const run = this._mutateQueue.then(() => operation());
    this._mutateQueue = run.then(
      () => undefined,
      () => undefined,
    );
    return run;
  },

  async _mutate(applyFn) {
    try {
      return await FileStore.prototype._mutate.call(this, applyFn);
    } catch (error) {
      this._pendingTreeChangeOps.length = 0;
      this._pendingDeletedPersonsOps.length = 0;
      throw error;
    }
  },

  async updateUserPassword(userId, newPlaintextPassword) {
    const updated = await FileStore.prototype.updateUserPassword.call(this, userId, newPlaintextPassword);
    if (updated) {
      await this.deleteSessionsForUser(userId);
    }
    return updated;
  },

  async createPerson({
    treeId,
    creatorId,
    personData,
    userId = null,
    sourcePersonId = null,
  }) {
    if (userId || sourcePersonId) {
      return FileStore.prototype.createPerson.call(this, {
        treeId,
        creatorId,
        personData,
        userId,
        sourcePersonId,
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
    });
    const identity = createPersonIdentityRecord({personIds: [person.id]});
    person.identityId = identity.id;

    return this._runOnMutateQueue(() =>
      this._enqueueWrite("_stateWriteQueue", async () => {
      await this.initialize();
      const preUpdateCachedVersion = this._cachedVersion;
      const result = await this._pool.query(
        `UPDATE ${this._qualifiedTableName}
            SET data = jsonb_set(
                  jsonb_set(
                    data,
                    '{persons}',
                    COALESCE(data->'persons', '[]'::jsonb) || jsonb_build_array($2::jsonb),
                    true
                  ),
                  '{personIdentities}',
                  COALESCE(data->'personIdentities', '[]'::jsonb) || jsonb_build_array($4::jsonb),
                  true
                ),
                updated_at = NOW(),
                version = version + 1
          WHERE id = $1
            AND EXISTS (
              SELECT 1
                FROM jsonb_array_elements(COALESCE(data->'trees', '[]'::jsonb)) AS tree_entry
               WHERE COALESCE(tree_entry->>'id', '') = $3
            )
          RETURNING version`,
        [
          this._rowId,
          JSON.stringify(person),
          normalizedTreeId,
          JSON.stringify(identity),
        ],
      );
      if (result.rowCount === 0) {
        return null;
      }
      // SPEED-14: this scoped UPDATE bypasses _write() entirely (that's the
      // whole point — no full-blob read/serialize/sidecar for the common
      // "add a relative" case), so it never told the SPEED-8a/11 read cache
      // about the row's new version. Left alone, the very next _read() in
      // the SAME request (e.g. the route handler's dispatchTreeMutation →
      // resolveTreeAudienceUserIds, called right after this method returns)
      // sees _cachedVersion pointing at the OLD row version and pays a full
      // cache-miss reload (SELECT ~1-2MB + parse + normalize + graph-sync +
      // structuredClone + sidecar write) — confirmed via a fake-pool probe,
      // see docs/speed_measurement.md SPEED-14; this was the dominant cost
      // of POST /v1/trees/:id/persons.
      //
      // Patch the cache in place ONLY when we can PROVE nothing else wrote
      // to the row between our last known-good cache fill and this blind
      // append: preUpdateCachedVersion === writtenVersion - 1 means no
      // interleaving writer landed in between (version is monotonic and
      // every writer increments it by exactly 1, invariant guarded
      // elsewhere — see postgres-store.test.js). If that doesn't hold (cache
      // was cold, or some other write raced us) we do NOT guess — leave the
      // cache exactly as this method left it before SPEED-14 (pointing at
      // the old version), which self-corrects via an honest reload on the
      // next _read(), same as today.
      const writtenVersion = normalizeStateVersion(
        result?.rows?.[0]?.version,
      );
      if (
        this._cachedState &&
        writtenVersion !== null &&
        preUpdateCachedVersion !== null &&
        preUpdateCachedVersion === writtenVersion - 1
      ) {
        // Ревью SPEED-14: тот же путь, что у промаха _read()/_write —
        // клон (кэш заморожен, а _syncGraphFromLegacy пушит в graphPersons/
        // branchPersonViews/graphRelations), добавить человека и
        // идентичность, синхронизировать зеркало графа (Phase 3.1c). Без
        // sync прогретый кэш отдавал бы новую персону без graph-зеркала до
        // следующего промаха, которого при совпадающей версии уже не будет.
        // O(N) sync дешевле старого промаха (SELECT + parse + тот же sync).
        const patchedState = structuredClone(this._cachedState);
        patchedState.persons = [...(patchedState.persons || []), person];
        patchedState.personIdentities = [
          ...(patchedState.personIdentities || []),
          identity,
        ];
        this._syncGraphFromLegacy(patchedState);
        this._commitCachedState(patchedState, writtenVersion);
        // Same fallback fs cache as every other writer — backgrounded, see
        // _persistSnapshotCache.
        this._persistSnapshotCache(this._cachedState);
      }
      return structuredClone(person);
      }),
    );
  },

  async deletePerson(treeId, personId, actorId = null) {
    const normalizedTreeId = String(treeId || "").trim();
    const normalizedPersonId = String(personId || "").trim();
    if (!normalizedTreeId || !normalizedPersonId) {
      return null;
    }

    return FileStore.prototype.deletePerson.call(this, normalizedTreeId, normalizedPersonId, actorId);
  },

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
  },

  async listPendingTreeInvitations(userId) {
    await this.initialize();
    await this._awaitReadConsistency();
    return this._selectStoredTreeInvitationsForUser(userId);
  },

  /// Горячий путь фан-аута пушей: каждый dispatchNotification звал
  /// listPushDevices → FileStore._read(), а на PostgresStore это ПОЛНЫЙ
  /// цикл блоба (SELECT ~1МБ + JSON.parse + _syncGraphFromLegacy +
  /// structuredClone + запись sidecar-кэша) — блокировка event-loop на
  /// сотни мс. В логах это видно как `fanout=534ms`, за которым СЛЕДУЮЩАЯ
  /// отправка ждёт в `access=467ms`. Сами устройства остаются в блобе
  /// (их пишет registerPushDevice), но ЧТЕНИЕ — точечный LATERAL-запрос,
  /// как у treeInvitations: ни парсинга блоба, ни клона, ни диска.
  async listOwnedMediaUrls(userId) {
    const urls = new Set(await FileStore.prototype.listOwnedMediaUrls.call(this, userId));
    const result = await this._pool.query(
      `SELECT message_data
         FROM ${this._qualifiedChatMessagesTableName}
        WHERE sender_id = $1`,
      [String(userId || "").trim()],
    );
    for (const row of result.rows) {
      const message = this._chatMessageFromRow(row);
      if (!message) {
        continue;
      }
      collectMessageMediaUrls(urls, message);
    }
    return Array.from(urls);
  },

  async deleteUser(userId) {
    await this.initialize();
    const normalizedUserId = String(userId || "").trim();
    const beforeResult = await this._pool.query(
      `SELECT chat_id FROM ${this._qualifiedChatParticipantsTableName} WHERE user_id = $1`,
      [normalizedUserId],
    );
    const beforeChatIds = beforeResult.rows
      .map((row) => String(row?.chat_id || "").trim())
      .filter(Boolean);
    const result = await FileStore.prototype.deleteUser.call(this, userId);
    if (result === null) {
      // Юзера не было (skip в applyFn) — каскадить нечего.
      return result;
    }

    // Блобная часть уже вычистила записи чатов (projection пересинкан в
    // _write); зеркалим табличную часть семантики FileStore.deleteUser.
    const survivingChatIds = new Set();
    if (beforeChatIds.length > 0) {
      const placeholders = beforeChatIds.map((_, index) => `$${index + 1}`);
      const surviving = await this._pool.query(
        `SELECT id FROM ${this._qualifiedChatsProjectionTableName}
          WHERE id IN (${placeholders.join(", ")})`,
        beforeChatIds,
      );
      for (const row of surviving.rows) {
        survivingChatIds.add(String(row?.id || "").trim());
      }
    }
    const removedChatIds = beforeChatIds.filter((id) => !survivingChatIds.has(id));

    const deletedMessageIds = new Set();
    const collectDeleted = (rows) => {
      for (const row of rows) {
        const id = String(row?.id || "").trim();
        if (id) {
          deletedMessageIds.add(id);
        }
      }
    };
    const bySender = await this._pool.query(
      `DELETE FROM ${this._qualifiedChatMessagesTableName}
        WHERE sender_id = $1
        RETURNING id`,
      [normalizedUserId],
    );
    collectDeleted(bySender.rows);
    if (removedChatIds.length > 0) {
      const placeholders = removedChatIds.map((_, index) => `$${index + 1}`);
      const byChat = await this._pool.query(
        `DELETE FROM ${this._qualifiedChatMessagesTableName}
          WHERE chat_id IN (${placeholders.join(", ")})
          RETURNING id`,
        removedChatIds,
      );
      collectDeleted(byChat.rows);
    }
    // Как FileStore: удаляются ВСЕ сообщения, в чьём participants-снапшоте
    // есть пользователь (включая чужие сообщения в выживших групповых чатах),
    // плюс стороны виртуальных direct-чатов. Полный скан — deleteUser редкий
    // и не на горячем пути; LIKE-эвристика пропускала групповые снапшоты.
    const candidates = await this._pool.query(
      `SELECT id, message_data
         FROM ${this._qualifiedChatMessagesTableName}`,
    );
    const participantMessageIds = [];
    for (const row of candidates.rows) {
      const message = this._chatMessageFromRow(row);
      const participants = normalizeParticipantIds(message?.participants);
      if (
        participants.includes(normalizedUserId) ||
        parseDirectParticipantsFromChatId(String(message?.chatId || "")).includes(
          normalizedUserId,
        )
      ) {
        participantMessageIds.push(String(row.id).trim());
      }
    }
    if (participantMessageIds.length > 0) {
      const placeholders = participantMessageIds.map((_, index) => `$${index + 1}`);
      const byParticipants = await this._pool.query(
        `DELETE FROM ${this._qualifiedChatMessagesTableName}
          WHERE id IN (${placeholders.join(", ")})
          RETURNING id`,
        participantMessageIds,
      );
      collectDeleted(byParticipants.rows);
    }

    await this._pool.query(
      `DELETE FROM ${this._qualifiedChatReactionsTableName} WHERE user_id = $1`,
      [normalizedUserId],
    );
    if (deletedMessageIds.size > 0) {
      const ids = Array.from(deletedMessageIds);
      const placeholders = ids.map((_, index) => `$${index + 1}`);
      await this._pool.query(
        `DELETE FROM ${this._qualifiedChatReactionsTableName}
          WHERE message_id IN (${placeholders.join(", ")})`,
        ids,
      );
      await this._pool.query(
        `DELETE FROM ${this._qualifiedChatPinsTableName}
          WHERE message_id IN (${placeholders.join(", ")})`,
        ids,
      );
    }
    await this._pool.query(
      `DELETE FROM ${this._qualifiedChatDraftsTableName} WHERE user_id = $1`,
      [normalizedUserId],
    );
    if (removedChatIds.length > 0) {
      const placeholders = removedChatIds.map((_, index) => `$${index + 1}`);
      await this._pool.query(
        `DELETE FROM ${this._qualifiedChatDraftsTableName}
          WHERE chat_id IN (${placeholders.join(", ")})`,
        removedChatIds,
      );
      await this._pool.query(
        `DELETE FROM ${this._qualifiedChatPinsTableName}
          WHERE chat_id IN (${placeholders.join(", ")})`,
        removedChatIds,
      );
    }
    // Пины, поставленные удаляемым пользователем (FileStore выкидывает их).
    const pins = await this._pool.query(
      `SELECT chat_id, pin_data FROM ${this._qualifiedChatPinsTableName}`,
    );
    for (const row of pins.rows) {
      const pin = this._chatJsonFromRow(row, "pin_data");
      if (String(pin?.pinnedBy || "").trim() === normalizedUserId) {
        await this._pool.query(
          `DELETE FROM ${this._qualifiedChatPinsTableName} WHERE chat_id = $1`,
          [String(row.chat_id).trim()],
        );
      }
    }

    // ── SPEED-7: каскад notifications/push_deliveries ──────────────────
    // Множества «умерших» сущностей — ИЗ РЕЗУЛЬТАТА super.deleteUser
    // (вычислены внутри _mutate-applyFn): реконструкция дифом блоба
    // до/после приписывала бы каскаду конкурентные удаления ДРУГИХ
    // пользователей и убивала их уведомления (находка ревью, P0).
    const asSet = (list) =>
      new Set(
        (Array.isArray(list) ? list : [])
          .map((entry) => String(entry || "").trim())
          .filter(Boolean),
      );
    const removedIds = {
      chats: asSet(result?.removedChatIds),
      trees: asSet(result?.removedTreeIds),
      semyi: asSet(result?.removedSemyaIds),
      posts: asSet(result?.removedPostIds),
      comments: asSet(result?.removedCommentIds),
      relationRequests: asSet(result?.removedRelationRequestIds),
      treeInvitations: asSet(result?.removedInvitationIds),
    };

    // Полный скан: та же семантика, что у массивного фильтра FileStore
    // (deleteUser редкий, таблица сотни строк — дешевле, чем jsonb-WHERE,
    // который pg-mem поддерживает выборочно). DELETE — точечно по id:
    // уведомление, вставленное конкурентно ПОСЛЕ скана, не удаляется —
    // узкое окно записи-сироты со ссылкой на умершую сущность (createNotification
    // для самого юзера уже отбит findUserById по auth-проекции).
    const allNotifications = await this._pool.query(
      `SELECT id, user_id, notification_data
         FROM ${this._qualifiedNotificationsTableName}`,
    );
    const notificationIdsToDelete = [];
    const survivingNotificationIds = new Set();
    for (const row of allNotifications.rows) {
      const rowId = String(row?.id || "").trim();
      const notification = this._rowToNotification(row) || {};
      const data =
        notification.data && typeof notification.data === "object"
          ? notification.data
          : {};
      const doomed =
        String(row?.user_id || "").trim() === normalizedUserId ||
        data.userId === userId ||
        data.senderId === userId ||
        data.recipientId === userId ||
        data.actorId === userId ||
        data.targetUserId === userId ||
        data.authorId === userId ||
        data.ownerId === userId ||
        (data.chatId && removedIds.chats.has(data.chatId)) ||
        (data.treeId && removedIds.trees.has(data.treeId)) ||
        (data.postId && removedIds.posts.has(data.postId)) ||
        (data.commentId && removedIds.comments.has(data.commentId)) ||
        (data.requestId && removedIds.relationRequests.has(data.requestId)) ||
        (data.invitationId && removedIds.treeInvitations.has(data.invitationId));
      if (doomed) {
        notificationIdsToDelete.push(rowId);
      } else {
        survivingNotificationIds.add(rowId);
      }
    }
    for (const id of notificationIdsToDelete) {
      await this._pool.query(
        `DELETE FROM ${this._qualifiedNotificationsTableName} WHERE id = $1`,
        [id],
      );
    }

    // Повторный точечный проход закрывает GDPR-окно: уведомление про
    // юзера, вставленное конкурентно ПОСЛЕ основного скана (ревью, P1).
    // Прямые записи юзера — одним DELETE; ссылки в data.* — вторым сканом.
    await this._pool.query(
      `DELETE FROM ${this._qualifiedNotificationsTableName} WHERE user_id = $1`,
      [normalizedUserId],
    );
    const lateRows = await this._pool.query(
      `SELECT id, notification_data
         FROM ${this._qualifiedNotificationsTableName}`,
    );
    for (const row of lateRows.rows) {
      const notification = this._rowToNotification(row) || {};
      const data =
        notification.data && typeof notification.data === "object"
          ? notification.data
          : {};
      const referencesUser =
        data.userId === userId ||
        data.senderId === userId ||
        data.recipientId === userId ||
        data.actorId === userId ||
        data.targetUserId === userId ||
        data.authorId === userId ||
        data.ownerId === userId;
      if (referencesUser) {
        await this._pool.query(
          `DELETE FROM ${this._qualifiedNotificationsTableName} WHERE id = $1`,
          [String(row.id)],
        );
        survivingNotificationIds.delete(String(row.id));
      }
    }

    const allDeliveries = await this._pool.query(
      `SELECT id, user_id, notification_id
         FROM ${this._qualifiedPushDeliveriesTableName}`,
    );
    for (const row of allDeliveries.rows) {
      const ownerId = String(row?.user_id || "").trim();
      const notificationId = String(row?.notification_id || "").trim();
      const doomed =
        ownerId === normalizedUserId ||
        (notificationId && !survivingNotificationIds.has(notificationId));
      if (doomed) {
        await this._pool.query(
          `DELETE FROM ${this._qualifiedPushDeliveriesTableName} WHERE id = $1`,
          [String(row.id)],
        );
      }
    }

    if (this._sessionsOutOfBlob) {
      await this.deleteSessionsForUser(userId);
    }
    if (this._deletedPersonsTablesReady) {
      await this._pool.query(
        `DELETE FROM ${this._qualifiedDeletedPersonsTableName}
          WHERE deleted_by_user_id = $1`,
        [normalizedUserId],
      );
      if (removedIds.trees.size > 0) {
        const treeIds = Array.from(removedIds.trees);
        const placeholders = treeIds.map((_, idx) => `$${idx + 1}`);
        await this._pool.query(
          `DELETE FROM ${this._qualifiedDeletedPersonsTableName}
            WHERE tree_id IN (${placeholders.join(", ")})`,
          treeIds,
        );
      }
      if (removedIds.semyi.size > 0) {
        const semyaIds = Array.from(removedIds.semyi);
        const placeholders = semyaIds.map((_, idx) => `$${idx + 1}`);
        await this._pool.query(
          `DELETE FROM ${this._qualifiedDeletedPersonsTableName}
            WHERE semya_id IN (${placeholders.join(", ")})`,
          semyaIds,
        );
      }
      const remainingDeletedPersons = await this._pool.query(
        `SELECT id, row_data FROM ${this._qualifiedDeletedPersonsTableName}`,
      );
      const snapshotUserRowIds = remainingDeletedPersons.rows
        .filter((row) => {
          const parsed = this._rowToDeletedPerson(row);
          return String(parsed?.snapshot?.userId || "").trim() === normalizedUserId;
        })
        .map((row) => String(row.id || "").trim())
        .filter(Boolean);
      if (snapshotUserRowIds.length > 0) {
        const placeholders = snapshotUserRowIds.map((_, idx) => `$${idx + 1}`);
        await this._pool.query(
          `DELETE FROM ${this._qualifiedDeletedPersonsTableName}
            WHERE id IN (${placeholders.join(", ")})`,
          snapshotUserRowIds,
        );
      }
    }
    if (this._clientDiagnosticsTablesReady) {
      await this._pool.query(
        `DELETE FROM ${this._qualifiedClientDiagnosticsTableName}
          WHERE user_id = $1`,
        [normalizedUserId],
      );
    }

    return result;
  },

  async removeTreeForUser({treeId, userId}) {
    await this.initialize();
    const normalizedTreeId = String(treeId || "").trim();
    const projected = await this._pool.query(
      `SELECT id, chat_data FROM ${this._qualifiedChatsProjectionTableName}`,
    );
    const treeChatIds = [];
    for (const row of projected.rows) {
      const chat = this._chatJsonFromRow(row, "chat_data");
      if (String(chat?.treeId || "").trim() === normalizedTreeId) {
        treeChatIds.push(String(row.id).trim());
      }
    }

    const result = await FileStore.prototype.removeTreeForUser.call(this, {treeId, userId});

    if (result?.action === "deleted" && treeChatIds.length > 0) {
      const placeholders = treeChatIds.map((_, index) => `$${index + 1}`);
      const deleted = await this._pool.query(
        `DELETE FROM ${this._qualifiedChatMessagesTableName}
          WHERE chat_id IN (${placeholders.join(", ")})
          RETURNING id`,
        treeChatIds,
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
        treeChatIds,
      );
      await this._pool.query(
        `DELETE FROM ${this._qualifiedChatPinsTableName}
          WHERE chat_id IN (${placeholders.join(", ")})`,
        treeChatIds,
      );
    }

    // SPEED-7: зеркалим notification-каскад FileStore. Hard-delete дерева —
    // все уведомления с data.treeId; выход участника — только его
    // собственные с этим treeId. Скан+JS-фильтр (см. deleteUser).
    if (result) {
      const treeDeleted = result.action === "deleted";
      const rows = await this._pool.query(
        `SELECT id, user_id, notification_data
           FROM ${this._qualifiedNotificationsTableName}`,
      );
      const normalizedUserId = String(userId || "").trim();
      for (const row of rows.rows) {
        const notification = this._rowToNotification(row) || {};
        const dataTreeId = String(notification?.data?.treeId || "").trim();
        if (dataTreeId !== normalizedTreeId) {
          continue;
        }
        if (!treeDeleted && String(row?.user_id || "").trim() !== normalizedUserId) {
          continue;
        }
        await this._pool.query(
          `DELETE FROM ${this._qualifiedNotificationsTableName} WHERE id = $1`,
          [String(row.id)],
        );
      }
    }
    return result;
  },

  async deletePushDevice(deviceId, userId) {
    await this.initialize();
    const result = await FileStore.prototype.deletePushDevice.call(this, deviceId, userId);
    // SPEED-7: блобный каскад по deliveries стал no-op (массив пуст) —
    // чистим таблицу. Только при фактическом удалении устройства.
    if (result) {
      await this._pool.query(
        `DELETE FROM ${this._qualifiedPushDeliveriesTableName}
          WHERE device_id = $1`,
        [String(deviceId || "").trim()],
      );
    }
    return result;
  },

  async unbindPushDevicesForSession({userId, sessionPublicId}) {
    await this.initialize();
    const result = await FileStore.prototype.unbindPushDevicesForSession.call(this, {
      userId,
      sessionPublicId,
    });
    // Источник истины — ФАКТИЧЕСКИ удалённые устройства из super (пре-снапшот
    // блоба мог устареть между чтением и мутацией — находка ревью).
    const deviceIds = (Array.isArray(result) ? result : [])
      .map((entry) => String(entry?.id || "").trim())
      .filter(Boolean);
    for (const deviceId of deviceIds) {
      await this._pool.query(
        `DELETE FROM ${this._qualifiedPushDeliveriesTableName}
          WHERE device_id = $1`,
        [deviceId],
      );
    }
    return result;
  },

  async hardDeleteExpired(options = {}) {
    const summary = await FileStore.prototype.hardDeleteExpired.call(this, options);
    // SPEED-7: retention таблиц — те же три окна notifications + TTL/cap
    // pushDeliveries, что в _sweepUnboundedLogs (блобные массивы после
    // миграции пусты, их счётчики в summary нулевые). ISO-строки
    // сравниваются лексикографически; пустой/непарсибельный created_at не
    // трогаем (гвард <> '' + сам формат cutoff).
    const {now = new Date(), dryRun = false, logRetention = {}} = options || {};
    const startedAt = now instanceof Date ? now : new Date(now);
    const nowTs = startedAt.getTime();
    const HOUR = 3_600_000;
    const DAY = 86_400_000;
    const cutoffIso = (ms) => new Date(nowTs - ms).toISOString();
    const counts = {
      notificationsSilent: 0,
      notificationsRead: 0,
      notificationsUnread: 0,
      pushDeliveries: 0,
    };
    if (this._notificationTablesReady) {
      const sweepNotifications = async (whereSql, params, key) => {
        if (dryRun) {
          const counted = await this._pool.query(
            `SELECT COUNT(*)::int AS total
               FROM ${this._qualifiedNotificationsTableName}
              WHERE created_at <> '' AND ${whereSql}`,
            params,
          );
          counts[key] += Number(counted.rows[0]?.total || 0);
          return;
        }
        const deleted = await this._pool.query(
          `DELETE FROM ${this._qualifiedNotificationsTableName}
            WHERE created_at <> '' AND ${whereSql}
            RETURNING id`,
          params,
        );
        counts[key] += deleted.rows.length;
      };
      const notifSilentMs =
        Math.max(0, Number(logRetention.notifSilentHours ?? 48)) * HOUR;
      const notifReadMs =
        Math.max(0, Number(logRetention.notifReadDays ?? 30)) * DAY;
      const notifUnreadMs =
        Math.max(0, Number(logRetention.notifUnreadDays ?? 365)) * DAY;
      if (notifSilentMs > 0) {
        await sweepNotifications(
          `silent = 1 AND created_at < $1`,
          [cutoffIso(notifSilentMs)],
          "notificationsSilent",
        );
      }
      if (notifReadMs > 0) {
        await sweepNotifications(
          `silent = 0 AND read_at <> '' AND read_at < $1`,
          [cutoffIso(notifReadMs)],
          "notificationsRead",
        );
      }
      if (notifUnreadMs > 0) {
        await sweepNotifications(
          `silent = 0 AND read_at = '' AND created_at < $1`,
          [cutoffIso(notifUnreadMs)],
          "notificationsUnread",
        );
      }

      const deliveriesDays = Number(logRetention.pushDeliveriesDays ?? 7);
      const deliveriesTtlMs = Math.max(0, deliveriesDays) * DAY;
      if (deliveriesTtlMs > 0) {
        if (dryRun) {
          const counted = await this._pool.query(
            `SELECT COUNT(*)::int AS total
               FROM ${this._qualifiedPushDeliveriesTableName}
              WHERE created_at <> '' AND created_at < $1`,
            [cutoffIso(deliveriesTtlMs)],
          );
          counts.pushDeliveries += Number(counted.rows[0]?.total || 0);
        } else {
          const deleted = await this._pool.query(
            `DELETE FROM ${this._qualifiedPushDeliveriesTableName}
              WHERE created_at <> '' AND created_at < $1
              RETURNING id`,
            [cutoffIso(deliveriesTtlMs)],
          );
          counts.pushDeliveries += deleted.rows.length;
        }
      }
      const rawCap = Number(logRetention.pushDeliveriesMax ?? 2000);
      const deliveriesCap =
        Number.isFinite(rawCap) && rawCap > 0 ? Math.floor(rawCap) : null;
      if (deliveriesCap !== null) {
        const counted = await this._pool.query(
          `SELECT COUNT(*)::int AS total
             FROM ${this._qualifiedPushDeliveriesTableName}`,
        );
        const overflow = Number(counted.rows[0]?.total || 0) - deliveriesCap;
        if (overflow > 0) {
          if (dryRun) {
            counts.pushDeliveries += overflow;
          } else {
            const oldest = await this._pool.query(
              `SELECT id
                 FROM ${this._qualifiedPushDeliveriesTableName}
                ORDER BY created_at ASC, id ASC
                LIMIT $1`,
              [overflow],
            );
            for (const row of oldest.rows) {
              await this._pool.query(
                `DELETE FROM ${this._qualifiedPushDeliveriesTableName} WHERE id = $1`,
                [String(row.id)],
              );
              counts.pushDeliveries += 1;
            }
          }
        }
      }

      if (summary && summary.logRetention) {
        summary.logRetention.notificationsSilent =
          Number(summary.logRetention.notificationsSilent || 0) +
          counts.notificationsSilent;
        summary.logRetention.notificationsRead =
          Number(summary.logRetention.notificationsRead || 0) +
          counts.notificationsRead;
        summary.logRetention.notificationsUnread =
          Number(summary.logRetention.notificationsUnread || 0) +
          counts.notificationsUnread;
        summary.logRetention.pushDeliveries =
          Number(summary.logRetention.pushDeliveries || 0) +
          counts.pushDeliveries;
      }
    }

    if (dryRun && this._treeChangeTablesReady) {
      const detailDays = Number(logRetention.treeChangeDetailDays ?? 30);
      const detailMs = Math.max(0, detailDays) * DAY;
      if (detailMs > 0) {
        const cutoffTs = nowTs - detailMs;
        const detailRows = await this._pool.query(
          `SELECT id, record_data
             FROM ${this._qualifiedTreeChangeRecordsTableName}
            WHERE created_at < $1 AND type NOT LIKE 'article.%'`,
          [new Date(cutoffTs).toISOString()],
        );
        let strippable = 0;
        for (const row of detailRows.rows) {
          const record = this._rowToTreeChangeRecord(row);
          if (record && stripTreeChangeRecordDetails(structuredClone(record), {cutoffTs})) {
            strippable += 1;
          }
        }
        if (summary?.logRetention) {
          summary.logRetention.treeChangeDetailsStripped =
            Number(summary.logRetention.treeChangeDetailsStripped || 0) + strippable;
        }
      }
      const auditRetentionDays =
        options.auditRetentionDays === undefined || options.auditRetentionDays === null
          ? 90
          : Number(options.auditRetentionDays);
      if (Number.isFinite(auditRetentionDays) && auditRetentionDays > 0) {
        const auditCutoffIso = new Date(
          nowTs - auditRetentionDays * DAY,
        ).toISOString();
        const auditCount = await this._pool.query(
          `SELECT COUNT(*)::int AS total
             FROM ${this._qualifiedHardDeleteAuditTableName}
            WHERE hard_deleted_at <> '' AND hard_deleted_at < $1`,
          [auditCutoffIso],
        );
        if (summary?.deleted) {
          summary.deleted.auditPruned =
            Number(summary.deleted.auditPruned || 0) +
            Number(auditCount.rows[0]?.total || 0);
        }
      }
    }

    // SPEED-16: super() above swept `db.deletedPersons` — but SPEED-15 moved
    // that collection out of the blob into `_deletedPersonsTable`, and every
    // `_write` drains the array back to `[]` (`_drainDeletedPersonsCollection`).
    // So on a migrated store the array-based sweep always finds zero rows and
    // the corbeille's 30-day "удалил → удалено" contract (DECISIONS.md
    // 2026-05-18) silently stopped being enforced the moment a row moved to
    // the table. Mirror the identical hybrid-eligibility formula (explicit
    // hardDeleteScheduledAt wins, else deletedAt+retention fallback, floored
    // by earliestHardDelete, restoredAt rows excluded) against the table
    // instead, sharing whatever's left of maxPerRun after the graph/branch/
    // identity sweep above. Runs OUTSIDE `_mutate` (like the notifications
    // sweep just above) — it's plain SQL against a dedicated table, not a
    // blob-wide read-modify-write, so it can't race the `_mutate` queue.
    // Before the table exists (migration not yet run) this stays a no-op —
    // super()'s array-based sweep already handles that case correctly.
    if (this._deletedPersonsTablesReady) {
      if (!dryRun && Array.isArray(summary._sweptSemyaIds) && summary._sweptSemyaIds.length > 0) {
        const semyaIds = summary._sweptSemyaIds;
        const placeholders = semyaIds.map((_, idx) => `$${idx + 1}`).join(", ");
        await this._pool.query(
          `DELETE FROM ${this._qualifiedDeletedPersonsTableName}
            WHERE semya_id IN (${placeholders})`,
          semyaIds,
        );
      }
      const GRAPH_SWEEP_KEYS = [
        "graphPersons",
        "graphRelations",
        "branches",
        "personIdentities",
        "branchPersonViews",
        "deletedPersons",
        "deletedPosts",
        "semyi",
      ];
      const graphDeletedSoFar = GRAPH_SWEEP_KEYS.reduce(
        (sum, key) => sum + (Number(summary.deleted?.[key]) || 0),
        0,
      );
      // Mirror FileStore's own default-parameter semantics (undefined/null
      // → default; an explicit 0 is honoured, not coerced back to default).
      const effectiveMaxPerRun =
        options.maxPerRun === undefined || options.maxPerRun === null
          ? 10_000
          : Number(options.maxPerRun);
      const effectiveRetentionDays =
        options.retentionDays === undefined || options.retentionDays === null
          ? 30
          : Number(options.retentionDays);
      const remainingBudget = Math.max(
        0,
        Math.floor(effectiveMaxPerRun) - graphDeletedSoFar,
      );
      const tableSweep = await this._sweepDeletedPersonsHardDeleteTable({
        startedAt,
        nowTs,
        retentionDays: effectiveRetentionDays,
        // Reuse the SAME runId super() already settled on (generated inside
        // FileStore when the caller didn't pass one) so both halves of one
        // hard-delete run share a single audit runId.
        runId: summary.runId,
        dryRun,
        budget: remainingBudget,
      });
      if (summary.deleted) {
        summary.deleted.deletedPersons =
          Number(summary.deleted.deletedPersons || 0) + tableSweep.deletedCount;
      }
      if (tableSweep.sampleIds.length) {
        const existingSamples = Array.isArray(summary.sampleIds?.deletedPerson)
          ? summary.sampleIds.deletedPerson
          : [];
        summary.sampleIds = summary.sampleIds || {};
        summary.sampleIds.deletedPerson = [
          ...existingSamples,
          ...tableSweep.sampleIds,
        ].slice(0, 5);
      }
      // Re-derive capHit over the COMBINED total (graph sweep + table sweep)
      // — a run that exhausts the shared budget entirely in the table sweep
      // must still surface capHit so the next scheduled run knows to keep
      // going, same signal super() emits for its own collections.
      const combinedTotal = graphDeletedSoFar + tableSweep.deletedCount;
      summary.capHit =
        effectiveMaxPerRun > 0 && combinedTotal >= Math.floor(effectiveMaxPerRun);
    }
    return summary;
  },

  // SPEED-16: eligibility mirror of FileStore.hardDeleteExpired's deletedPersons
  // block, against `_deletedPersonsTable` instead of `db.deletedPersons`. ISO
  // timestamp columns compare correctly lexicographically (all produced via
  // `.toISOString()` — fixed-width, UTC, zero-padded), same idiom already used
  // by the audit self-prune and the notifications sweep above.
  async _sweepDeletedPersonsHardDeleteTable({
    startedAt,
    nowTs,
    retentionDays,
    runId,
    dryRun,
    budget,
  }) {
    if (!(budget > 0)) {
      return {deletedCount: 0, sampleIds: []};
    }
    const nowIso = startedAt.toISOString();
    const retentionMs = Math.max(0, Number(retentionDays) || 0) * 86_400_000;
    const fallbackCutoffIso = new Date(nowTs - retentionMs).toISOString();
    // restored_at = '' — excludes rows a user pulled back out of the trash.
    // hard_delete_scheduled_at wins when set (Path A); otherwise fall back to
    // deleted_at + retention (Path B, same as isEligible() in FileStore).
    // earliest_hard_delete is the floor — never purge before it, guards
    // against a misconfigured/short retention env var.
    const eligibleWhere = `
        restored_at = ''
        AND deleted_at <> ''
        AND (
          (hard_delete_scheduled_at <> '' AND hard_delete_scheduled_at < $1)
          OR (hard_delete_scheduled_at = '' AND deleted_at < $2)
        )
        AND (earliest_hard_delete = '' OR earliest_hard_delete <= $1)
    `;
    // Select the budget-capped candidate set first, then delete row-by-row.
    // NOT `DELETE ... WHERE id IN (SELECT ... LIMIT $n)`: pg-mem silently
    // drops the LIMIT once it's inside an IN-subquery and deletes every
    // eligible row regardless of budget (verified against pg-mem directly —
    // plain `SELECT ... LIMIT` is honoured, the nested form is not), which
    // would blow the maxPerRun budget on prod's real Postgres semantics vs.
    // what the pg-mem test suite could ever catch. The same select-then-
    // delete-by-id shape is already used a few dozen lines up for the
    // pushDeliveries overflow cap.
    const candidates = await this._pool.query(
      `SELECT id, deleted_at, hard_delete_scheduled_at
         FROM ${this._qualifiedDeletedPersonsTableName}
        WHERE ${eligibleWhere}
        ORDER BY deleted_at ASC, id ASC
        LIMIT $3`,
      [nowIso, fallbackCutoffIso, budget],
    );
    if (dryRun) {
      return {
        deletedCount: candidates.rows.length,
        sampleIds: candidates.rows.slice(0, 5).map((row) => row.id),
      };
    }
    const auditEntries = [];
    const deletedIds = [];
    for (const row of candidates.rows) {
      const delResult = await this._pool.query(
        `DELETE FROM ${this._qualifiedDeletedPersonsTableName}
          WHERE id = $1 AND restored_at = ''
          RETURNING id`,
        [row.id],
      );
      const wasDeleted =
        Array.isArray(delResult?.rows)
          ? delResult.rows.length > 0
          : Number(delResult?.rowCount || 0) > 0;
      if (!wasDeleted) {
        continue;
      }
      deletedIds.push(row.id);
      auditEntries.push({
        runId,
        entityType: "deletedPerson",
        entityId: row.id,
        deletedAt: row.deleted_at || null,
        scheduledAt: row.hard_delete_scheduled_at || null,
        hardDeletedAt: nowIso,
      });
    }
    if (auditEntries.length) {
      await this._insertHardDeleteAuditRows(auditEntries);
    }
    return {
      deletedCount: deletedIds.length,
      sampleIds: deletedIds.slice(0, 5),
    };
  },

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
      return FileStore.prototype.findActiveCall.call(this, {userId: normalizedUserId, chatId: normalizedChatId});
    }
  },

  async listUserTrees(userId) {
    const normalizedUserId = String(userId || "").trim();
    if (!normalizedUserId) {
      return [];
    }

    const useSemyaModel =
      String(process.env.RODNYA_FEDERATED_SEMYI_ENABLED || "")
        .trim()
        .toLowerCase() === "true";
    await this.initialize();
    await this._awaitReadConsistency();
    if (useSemyaModel) {
      return FileStore.prototype.listUserTrees.call(this, normalizedUserId);
    }
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
      return FileStore.prototype.listUserTrees.call(this, normalizedUserId);
    }
  },

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
  },

};
