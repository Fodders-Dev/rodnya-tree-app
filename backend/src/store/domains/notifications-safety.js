const crypto = require("node:crypto");
const {
  buildCommentReactionNotificationPlan,
  buildCommentReplyNotificationPlan,
  buildPostReactionNotificationPlan,
  buildStoryReactionNotificationPlan,
  createBlockRecord,
  createNotificationRecord,
  createPushDeliveryRecord,
  createPushDeviceRecord,
  createReportRecord,
  decodeNotificationCursor,
  encodeNotificationCursor,
  normalizeNullableString,
  normalizeOptionalString,
  nowIso,
} = require("../helpers");

module.exports = {
  async createNotification({userId, type, title, body, data, silent = false}) {
    return this._mutate((db, skip) => {
      const user = db.users.find((entry) => entry.id === userId);
      if (!user) {
        return skip(null);
      }

      const notification = createNotificationRecord({
        userId,
        type,
        title,
        body,
        data,
        silent,
      });
      db.notifications.push(notification);
      return structuredClone(notification);
    });
  },

  async registerPushDevice({
    userId,
    provider,
    token,
    platform,
    sessionPublicId = null,
    instanceId = null,
  }) {
    const db = await this._read();
    const user = db.users.find((entry) => entry.id === userId);
    if (!user) {
      return null;
    }

    const normalizedProvider = String(provider || "").trim();
    const normalizedToken = String(token || "").trim();
    if (!normalizedProvider || !normalizedToken) {
      return false;
    }

    const normalizedSessionPublicId = normalizeOptionalString(sessionPublicId, 32);
    const normalizedInstanceId = normalizeOptionalString(instanceId, 80);

    const existingDevice = db.pushDevices.find((entry) => {
      return (
        entry.userId === userId &&
        entry.provider === normalizedProvider &&
        entry.token === normalizedToken
      );
    });

    if (existingDevice) {
      existingDevice.platform = String(platform || existingDevice.platform || "unknown");
      existingDevice.updatedAt = nowIso();
      existingDevice.lastSeenAt = existingDevice.updatedAt;
      if (normalizedSessionPublicId) {
        existingDevice.sessionPublicId = normalizedSessionPublicId;
      }
      if (normalizedInstanceId) {
        existingDevice.instanceId = normalizedInstanceId;
      }
      await this._write(db);
      return structuredClone(existingDevice);
    }

    const device = createPushDeviceRecord({
      userId,
      provider: normalizedProvider,
      token: normalizedToken,
      platform,
      sessionPublicId: normalizedSessionPublicId,
      instanceId: normalizedInstanceId,
    });
    db.pushDevices.push(device);
    await this._write(db);
    return structuredClone(device);
  },

  async unbindPushDevicesForSession({userId, sessionPublicId}) {
    const normalizedUserId = String(userId || "").trim();
    const normalizedSessionPublicId = String(sessionPublicId || "").trim();
    if (!normalizedUserId || !normalizedSessionPublicId) {
      return [];
    }
    const db = await this._read();
    const removed = [];
    db.pushDevices = db.pushDevices.filter((entry) => {
      if (
        entry.userId === normalizedUserId &&
        entry.sessionPublicId === normalizedSessionPublicId
      ) {
        removed.push(structuredClone(entry));
        return false;
      }
      return true;
    });
    if (removed.length === 0) {
      return [];
    }
    const removedIds = new Set(removed.map((entry) => entry.id));
    db.pushDeliveries = db.pushDeliveries.filter(
      (entry) => !removedIds.has(entry.deviceId),
    );
    await this._write(db);
    return removed;
  },

  async listPushDevices(userId) {
    const db = await this._read();
    return db.pushDevices
      .filter((entry) => entry.userId === userId)
      .sort((left, right) =>
        String(right.updatedAt || "").localeCompare(String(left.updatedAt || "")),
      )
      .map((entry) => structuredClone(entry));
  },

  async deletePushDevice(deviceId, userId) {
    return this._mutate((db, skip) => {
      const initialLength = db.pushDevices.length;
      db.pushDevices = db.pushDevices.filter((entry) => {
        return !(entry.id === deviceId && entry.userId === userId);
      });

      if (db.pushDevices.length === initialLength) {
        return skip(false);
      }

      db.pushDeliveries = db.pushDeliveries.filter((entry) => entry.deviceId !== deviceId);
      return true;
    });
  },

  async createPushDelivery({
    notificationId,
    userId,
    deviceId,
    provider,
    status = "queued",
  }) {
    const db = await this._read();
    const delivery = createPushDeliveryRecord({
      notificationId,
      userId,
      deviceId,
      provider,
      status,
    });
    db.pushDeliveries.push(delivery);
    await this._write(db);
    return structuredClone(delivery);
  },

  async updatePushDelivery(
    deliveryId,
    {
      status,
      deliveredAt,
      lastError,
      responseCode,
    } = {},
  ) {
    const db = await this._read();
    const delivery = db.pushDeliveries.find((entry) => entry.id === deliveryId);
    if (!delivery) {
      return null;
    }

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
    await this._write(db);
    return structuredClone(delivery);
  },

  async listNotifications(userId, {status = null, limit = 50} = {}) {
    const db = await this._read();
    const normalizedLimit = Number.isFinite(Number(limit))
      ? Math.max(0, Number(limit))
      : 50;
    if (normalizedLimit === 0) {
      return [];
    }

    const notifications = [];
    for (let index = db.notifications.length - 1; index >= 0; index -= 1) {
      const entry = db.notifications[index];
      if (entry.userId !== userId) {
        continue;
      }
      if (status === "unread" && entry.readAt) {
        continue;
      }
      if (status === "read" && !entry.readAt) {
        continue;
      }

      notifications.push(entry);
      if (notifications.length >= normalizedLimit) {
        break;
      }
    }

    return notifications.map((entry) => structuredClone(entry));
  },

  async countUnreadNotifications(userId) {
    const db = await this._read();
    return db.notifications.filter((entry) => entry.userId === userId && !entry.readAt)
      .length;
  },

  async markNotificationRead(notificationId, userId) {
    return this._mutate((db, skip) => {
      const notification = db.notifications.find(
        (entry) => entry.id === notificationId && entry.userId === userId,
      );
      if (!notification) {
        return skip(null);
      }

      if (!notification.readAt) {
        notification.readAt = nowIso();
        return structuredClone(notification);
      }
      return skip(structuredClone(notification));
    });
  },

  /// «Прочитать всё»: один вызов вместо N поштучных POST'ов с клиента
  /// (экран активности лупил цикл markNotificationRead по каждому id).
  async markAllNotificationsRead(userId) {
    const normalizedUserId = String(userId || "").trim();
    if (!normalizedUserId) return 0;
    return this._mutate((db, skip) => {
      const now = nowIso();
      let markedCount = 0;
      for (const notification of db.notifications) {
        if (notification.userId !== normalizedUserId) continue;
        if (notification.readAt) continue;
        notification.readAt = now;
        markedCount += 1;
      }
      if (markedCount === 0) {
        return skip(0);
      }
      return markedCount;
    });
  },

  /// Курсорная страница ленты активности (все статусы по умолчанию).
  /// Keyset-курсор `createdAt|id` (base64url), сортировка createdAt DESC,
  /// id DESC — стабильна при вставке новых сверху. nextCursor null =
  /// лента закончилась.
  async listNotificationsPage(userId, {status = null, limit = 50, cursor = null} = {}) {
    const normalizedUserId = String(userId || "").trim();
    const normalizedLimit = Math.min(
      200,
      Math.max(1, Math.floor(Number(limit) || 50)),
    );
    if (!normalizedUserId) {
      return {notifications: [], nextCursor: null};
    }
    const decodedCursor = decodeNotificationCursor(cursor);
    const db = await this._read();
    const filtered = db.notifications.filter((entry) => {
      if (entry.userId !== normalizedUserId) return false;
      if (status === "unread" && entry.readAt) return false;
      if (status === "read" && !entry.readAt) return false;
      return true;
    });
    filtered.sort((left, right) => {
      const byCreated = String(right.createdAt || "").localeCompare(
        String(left.createdAt || ""),
      );
      if (byCreated !== 0) return byCreated;
      return String(right.id || "").localeCompare(String(left.id || ""));
    });
    const afterCursor = decodedCursor
      ? filtered.filter((entry) => {
          const created = String(entry.createdAt || "");
          if (created !== decodedCursor.createdAt) {
            return created < decodedCursor.createdAt;
          }
          return String(entry.id || "") < decodedCursor.id;
        })
      : filtered;
    const pageItems = afterCursor.slice(0, normalizedLimit);
    const hasMore = afterCursor.length > normalizedLimit;
    const last = pageItems[pageItems.length - 1];
    return {
      notifications: pageItems.map((entry) => structuredClone(entry)),
      nextCursor:
        hasMore && last
          ? encodeNotificationCursor(String(last.createdAt || ""), String(last.id || ""))
          : null,
    };
  },

  /// Bulk mark — отмечает прочитанными все уведомления юзера, у
  /// которых `data.<dataKey>` === `dataValue` И тип входит в
  /// `types` (если задан). Возвращает количество отмеченных
  /// записей. Используется для авто-погашения уведомлений когда
  /// юзер видит источник в приложении (например, открыл чат →
  /// гасим все «новое сообщение» по этому chatId).
  ///
  /// User-reported: «много в активностях остаётся оповещений
  /// которые были уже просмотрены в приложении» — раньше клиент
  /// должен был тапать каждое сообщение по отдельности или
  /// нажимать «Прочитать всё», что было неудобно и часто
  /// забывалось.
  async markNotificationsReadByDataKey({
    userId,
    dataKey,
    dataValue,
    types = null,
  }) {
    if (!userId || !dataKey) return 0;
    const normalizedValue = dataValue == null ? null : String(dataValue);
    const typeFilter = Array.isArray(types) && types.length > 0
      ? new Set(types.map((entry) => String(entry)))
      : null;

    return this._mutate((db, skip) => {
      const now = nowIso();
      let markedCount = 0;
      for (const notification of db.notifications) {
        if (notification.userId !== userId) continue;
        if (notification.readAt) continue;
        if (typeFilter && !typeFilter.has(String(notification.type || ""))) {
          continue;
        }
        const data = notification.data || {};
        const candidate = data[dataKey];
        if (candidate == null) continue;
        if (String(candidate) !== normalizedValue) continue;
        notification.readAt = now;
        markedCount += 1;
      }
      if (markedCount === 0) {
        return skip(markedCount);
      }
      return markedCount;
    });
  },

  async listUserBlocks(userId) {
    const db = await this._read();
    return db.blocks
      .filter((entry) => entry.blockerId === userId)
      .sort((left, right) =>
        String(right.createdAt || "").localeCompare(String(left.createdAt || "")),
      )
      .map((entry) => structuredClone(entry));
  },

  async createUserBlock({
    blockerId,
    blockedUserId,
    reason = null,
    metadata = {},
  }) {
    const db = await this._read();
    const normalizedBlockerId = String(blockerId || "").trim();
    const normalizedBlockedUserId = String(blockedUserId || "").trim();
    if (!normalizedBlockerId || !normalizedBlockedUserId) {
      return false;
    }
    if (normalizedBlockerId === normalizedBlockedUserId) {
      return false;
    }

    const blocker = db.users.find((entry) => entry.id === normalizedBlockerId);
    const blockedUser = db.users.find((entry) => entry.id === normalizedBlockedUserId);
    if (!blocker || !blockedUser) {
      return null;
    }

    const existingBlock = db.blocks.find((entry) => {
      return (
        entry.blockerId === normalizedBlockerId &&
        entry.blockedUserId === normalizedBlockedUserId
      );
    });
    if (existingBlock) {
      if (reason != null || (metadata && Object.keys(metadata).length > 0)) {
        existingBlock.reason = normalizeNullableString(reason) || existingBlock.reason;
        existingBlock.metadata = metadata && typeof metadata === "object"
          ? structuredClone(metadata)
          : existingBlock.metadata || {};
        existingBlock.updatedAt = nowIso();
        await this._write(db);
      }
      return structuredClone(existingBlock);
    }

    const block = createBlockRecord({
      blockerId: normalizedBlockerId,
      blockedUserId: normalizedBlockedUserId,
      reason,
      metadata,
    });
    db.blocks.push(block);
    await this._write(db);
    return structuredClone(block);
  },

  async deleteUserBlock({blockId, blockerId}) {
    const db = await this._read();
    const index = db.blocks.findIndex((entry) => {
      return entry.id === blockId && entry.blockerId === blockerId;
    });
    if (index < 0) {
      return null;
    }

    const [removed] = db.blocks.splice(index, 1);
    await this._write(db);
    return structuredClone(removed);
  },

  async isUserBlockedBetween(userIdA, userIdB) {
    const db = await this._read();
    return db.blocks.some((entry) => {
      return (
        (entry.blockerId === userIdA && entry.blockedUserId === userIdB) ||
        (entry.blockerId === userIdB && entry.blockedUserId === userIdA)
      );
    });
  },

  async createReport({
    reporterId,
    targetType,
    targetId,
    reason,
    details = null,
    metadata = {},
  }) {
    const db = await this._read();
    const normalizedReporterId = String(reporterId || "").trim();
    const normalizedTargetType = String(targetType || "").trim();
    const normalizedTargetId = String(targetId || "").trim();
    if (!normalizedReporterId || !normalizedTargetType || !normalizedTargetId) {
      return false;
    }

    if (!db.users.some((entry) => entry.id === normalizedReporterId)) {
      return null;
    }

    const report = createReportRecord({
      reporterId: normalizedReporterId,
      targetType: normalizedTargetType,
      targetId: normalizedTargetId,
      reason,
      details,
      metadata,
    });
    db.reports.push(report);
    await this._write(db);
    return structuredClone(report);
  },

  async listReports({status = null} = {}) {
    const db = await this._read();
    const normalizedStatus = normalizeNullableString(status);
    return db.reports
      .filter((entry) => {
        if (!normalizedStatus) {
          return true;
        }
        return entry.status === normalizedStatus;
      })
      .sort((left, right) =>
        String(right.createdAt || "").localeCompare(String(left.createdAt || "")),
      )
      .map((entry) => structuredClone(entry));
  },

  async resolveReport({
    reportId,
    resolvedBy,
    status,
    resolutionNote = null,
  }) {
    const db = await this._read();
    const report = db.reports.find((entry) => entry.id === reportId);
    if (!report) {
      return null;
    }

    report.status = String(status || "resolved").trim() || "resolved";
    report.resolvedBy = String(resolvedBy || "").trim() || null;
    report.resolutionNote = normalizeNullableString(resolutionNote);
    report.resolvedAt = nowIso();
    report.updatedAt = report.resolvedAt;
    await this._write(db);
    return structuredClone(report);
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
    const db = await this._read();
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
    db.clientDiagnostics.push(event);
    if (db.clientDiagnostics.length > 500) {
      db.clientDiagnostics = db.clientDiagnostics.slice(-500);
    }
    await this._write(db);
    return structuredClone(event);
  },

  async listClientDiagnostics({type = null, userId = null, limit = 100} = {}) {
    const db = await this._read();
    const normalizedType = normalizeNullableString(type);
    const normalizedUserId = normalizeNullableString(userId);
    const cappedLimit = Math.min(Math.max(Number(limit) || 100, 1), 500);
    return db.clientDiagnostics
      .filter((entry) => {
        if (normalizedType && entry.type !== normalizedType) {
          return false;
        }
        if (normalizedUserId && entry.userId !== normalizedUserId) {
          return false;
        }
        return true;
      })
      .sort((left, right) =>
        String(right.createdAt || "").localeCompare(String(left.createdAt || "")),
      )
      .slice(0, cappedLimit)
      .map((entry) => structuredClone(entry));
  },

  async addStoryReactionNotification(args) {
    return this._applyNotificationCoalescePlan(
      buildStoryReactionNotificationPlan(args || {}),
    );
  },

  /// Push a "X reacted to your post" notification, coalescing unread
  /// entries for the same (recipient, post, actor) tuple — multiple
  /// reactions don't spam the inbox. Returns the notification record
  /// or null if skipped (self-react or already-unread).
  async addPostReactionNotification(args) {
    return this._applyNotificationCoalescePlan(
      buildPostReactionNotificationPlan(args || {}),
    );
  },

  /// Same shape as [addPostReactionNotification] but scoped to a
  /// comment. Notifies the comment author. Post author is left alone
  /// — they already get a notification stream when their own comments
  /// get reacted to (separate flow).
  async addCommentReactionNotification(args) {
    return this._applyNotificationCoalescePlan(
      buildCommentReactionNotificationPlan(args || {}),
    );
  },

  /// Notify the parent comment author that someone replied to their
  /// comment. Distinct from comment_reaction so the inbox can render a
  /// dedicated "ответил на ваш комментарий" string and route directly
  /// to the comment thread instead of the reaction overlay.
  ///
  /// We dedupe on (parentCommentId, actorUserId) for unread entries —
  /// a single user posting two replies in quick succession refreshes
  /// the existing entry rather than fanning out two pings.
  async addCommentReplyNotification(args) {
    return this._applyNotificationCoalescePlan(
      buildCommentReplyNotificationPlan(args || {}),
    );
  },
};
