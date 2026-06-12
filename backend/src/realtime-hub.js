const {WebSocketServer} = require("ws");
const {deriveSessionPublicId} = require("./store");

class RealtimeHub {
  constructor({store, logger = console}) {
    this.store = store;
    this.logger = logger;
    this.userSockets = new Map();
    // Map<userId, Set<activeChatId>>. Юзер может одновременно быть
    // открыт в одном чате на телефоне и другом на ПК — Set покрывает
    // оба. Заполняется по `chat.active.set` от клиента (см.
    // ChatScreen.initState/dispose), очищается на disconnect.
    this.userActiveChats = new Map();
    this.wss = null;
  }

  /// `true` если у юзера хотя бы одна WS-сессия объявила этот chatId
  /// активным. Используется push-gateway чтобы не слать пуш для
  /// сообщения, которое получатель прямо сейчас читает в открытом
  /// окне чата — иначе на телефоне раздаётся buzz из шторки в тот
  /// момент когда сообщение и так уже видно на экране.
  ///
  /// S5: запись протухает (idle > 60с). Свёрнутое приложение держит WS,
  /// но клиентский heartbeat (chat.active.set раз в ~30с) замерзает
  /// вместе с таймерами — флажок гаснет, и пуши снова доходят.
  isUserActiveInChat(userId, chatId) {
    if (!userId || !chatId) return false;
    const chats = this.userActiveChats.get(userId);
    if (!chats) return false;
    const touchedAt = chats.get(String(chatId));
    if (touchedAt === undefined) return false;
    if (Date.now() - touchedAt > RealtimeHub.ACTIVE_CHAT_TTL_MS) {
      // Ленивое протухание — чистим по факту обращения.
      chats.delete(String(chatId));
      if (chats.size === 0) {
        this.userActiveChats.delete(userId);
      }
      return false;
    }
    return true;
  }

  static get ACTIVE_CHAT_TTL_MS() {
    return 60_000;
  }

  _scheduleSessionTouch(token, {userId = null} = {}) {
    if (typeof this.store?.touchSession !== "function") {
      return;
    }

    void Promise.resolve()
      .then(() => this.store.touchSession(token))
      .catch((error) => {
        this.logger.warn?.(
          "[rodnya-backend] realtime touch session failed",
          JSON.stringify({
            userId,
            message: String(error?.message || error || "unknown_error"),
          }),
        );
      });
  }

  attach(server) {
    this.wss = new WebSocketServer({
      server,
      path: "/v1/realtime",
      // ws library default `maxPayload` is 100 MB. Our realtime
      // protocol is just typing-indicator JSON (`chat.typing.set`)
      // — anything over a few hundred bytes is malformed or hostile.
      // 8 KB is roomy enough for any future small status payload
      // without giving an attacker a free DoS surface.
      maxPayload: 8 * 1024,
    });

    this.wss.on("connection", async (socket, request) => {
      let userId = null;

      try {
        const url = new URL(request.url, "http://127.0.0.1");
        const token = String(url.searchParams.get("accessToken") || "").trim();
        const instanceId = String(
          url.searchParams.get("instanceId") || "",
        ).trim();

        if (!token) {
          socket.close(4401, "Missing access token");
          return;
        }

        const session = await this.store.findSession(token);
        if (!session) {
          socket.close(4401, "Session not found");
          return;
        }

        const user = await this.store.findUserById(session.userId);
        if (!user) {
          socket.close(4401, "User not found");
          return;
        }

        userId = user.id;
        socket.publicSessionId = deriveSessionPublicId(token, instanceId);
        this._registerSocket(userId, socket);
        this._scheduleSessionTouch(token, {userId});
        const onlineUserIds = await this._collectOnlineParticipants(userId);

        socket.send(
          JSON.stringify({
            type: "connection.ready",
            userId,
            connectedAt: new Date().toISOString(),
            onlineUserIds,
          }),
        );

        await this._broadcastPresenceUpdate(userId, true);

        socket.on("close", () => {
          void this._handleSocketClose(userId, socket);
        });

        socket.on("error", (error) => {
          this.logger.warn?.("[rodnya-backend] realtime socket error", error);
          void this._handleSocketClose(userId, socket);
        });

        socket.on("message", (rawMessage) => {
          void this._handleSocketMessage(userId, rawMessage, socket);
        });
      } catch (error) {
        this.logger.warn?.("[rodnya-backend] realtime connection failed", error);
        socket.close(1011, "Realtime initialization failed");
      }
    });
  }

  publishToUser(userId, payload, {sessionPublicId = null} = {}) {
    const sockets = this.userSockets.get(userId);
    if (!sockets || sockets.size === 0) {
      return false;
    }

    const targetSessionPublicId = sessionPublicId
      ? String(sessionPublicId).trim()
      : "";
    const isPerSocketBuilder = typeof payload === "function";
    const staticSerializedPayload = isPerSocketBuilder
      ? null
      : JSON.stringify(payload);
    let sent = false;
    for (const socket of sockets) {
      if (socket.readyState !== socket.OPEN) {
        continue;
      }
      if (
        targetSessionPublicId &&
        (socket.publicSessionId || "") !== targetSessionPublicId
      ) {
        continue;
      }
      let serializedPayload = staticSerializedPayload;
      if (isPerSocketBuilder) {
        const builtPayload = payload({
          userId,
          sessionPublicId: socket.publicSessionId || "",
        });
        if (!builtPayload) {
          continue;
        }
        serializedPayload = JSON.stringify(builtPayload);
      }
      socket.send(serializedPayload);
      sent = true;
    }
    return sent;
  }

  disconnectSession(userId, sessionPublicId, {reason = "session.revoked"} = {}) {
    const sockets = this.userSockets.get(userId);
    if (!sockets || sockets.size === 0) {
      return 0;
    }
    const targetSessionPublicId = String(sessionPublicId || "").trim();
    if (!targetSessionPublicId) {
      return 0;
    }
    let closedCount = 0;
    for (const socket of Array.from(sockets)) {
      if ((socket.publicSessionId || "") !== targetSessionPublicId) {
        continue;
      }
      try {
        if (socket.readyState === socket.OPEN) {
          socket.send(
            JSON.stringify({
              type: "session.revoked",
              reason,
              revokedAt: new Date().toISOString(),
            }),
          );
        }
      } catch (_) {
        // best-effort notification — close anyway
      }
      try {
        socket.close(4403, reason);
      } catch (_) {
        // ignore close failures; socket close handler will clean up
      }
      closedCount += 1;
    }
    return closedCount;
  }

  async publishToChat(chatId, payload, {exceptUserId = null} = {}) {
    if (!chatId || typeof this.store?.findChat !== "function") {
      return false;
    }

    const chat = await this.store.findChat(chatId);
    if (!chat || !Array.isArray(chat.participantIds)) {
      return false;
    }

    const excludedUserId = exceptUserId ? String(exceptUserId).trim() : null;
    const deliveredUserIds = [];
    for (const participantId of chat.participantIds) {
      if (!participantId || participantId === excludedUserId) {
        continue;
      }
      const sent = this.publishToUser(participantId, payload);
      if (
        sent &&
        payload?.type === "chat.message.created" &&
        payload?.message?.id &&
        payload?.message?.senderId !== participantId
      ) {
        deliveredUserIds.push(participantId);
      }
    }

    if (
      deliveredUserIds.length > 0 &&
      typeof this.store?.markChatMessageDelivered === "function"
    ) {
      const delivery = await this.store.markChatMessageDelivered({
        chatId,
        messageId: payload.message.id,
        userIds: deliveredUserIds,
      });
      if (delivery && delivery !== false && delivery !== null) {
        const changedUserIds = Array.isArray(delivery.changedUserIds)
          ? delivery.changedUserIds
          : deliveredUserIds;
        if (changedUserIds.length > 0) {
          const deliveredPayload = {
            type: "message.delivered",
            chatId: delivery.chatId || chatId,
            messageId: delivery.messageId || payload.message.id,
            userIds: changedUserIds,
            deliveredTo: Array.isArray(delivery.deliveredTo)
              ? delivery.deliveredTo
              : changedUserIds,
          };
          // S5: галочки «доставлено» видны только на СВОИХ бабблах —
          // delivered-событие нужно одному отправителю, а не всем N
          // участникам. Было 2×N publish на сообщение (created+delivered
          // каждому), стало N+1: changedUserIds уже собраны батчем в
          // один payload.
          const senderId = String(payload?.message?.senderId || "").trim();
          if (senderId && senderId !== excludedUserId) {
            this.publishToUser(senderId, deliveredPayload);
          }
        }
      }
    }
    return true;
  }

  isUserOnline(userId) {
    const sockets = this.userSockets.get(userId);
    return Boolean(sockets && sockets.size > 0);
  }

  describeRuntimeStats() {
    let socketCount = 0;
    for (const sockets of this.userSockets.values()) {
      socketCount += sockets?.size || 0;
    }

    return {
      onlineUsers: this.userSockets.size,
      activeSockets: socketCount,
      wsAttached: this.wss != null,
    };
  }

  async _collectOnlineParticipants(userId) {
    const participantIds = await this._safeListRelatedChatParticipantIds(userId, {
      context: "collect_online_participants",
    });
    return participantIds.filter((participantId) => this.isUserOnline(participantId));
  }

  async _broadcastPresenceUpdate(userId, isOnline) {
    const participantIds = await this._safeListRelatedChatParticipantIds(userId, {
      context: "broadcast_presence_update",
    });
    const updatedAt = new Date().toISOString();
    // For going-offline transitions, the broadcast timestamp is exactly
    // the user's lastSeenAt. Persist it on the user record so chat-detail
    // responses on cold opens render "был(а) N минут назад" without
    // waiting for the realtime event. Best-effort — never blocks the
    // broadcast itself.
    if (!isOnline && typeof this.store?.markUserSeenAt === "function") {
      try {
        await this.store.markUserSeenAt(userId, {when: updatedAt});
      } catch (_) {
        /* swallow — UX hint, not source of truth */
      }
    }
    const payload = {
      type: "presence.updated",
      userId,
      isOnline,
      // Explicit lastSeenAt so the frontend doesn't have to assume
      // `updatedAt === lastSeenAt`. Online events return null — the user
      // is online, the timestamp would be misleading.
      lastSeenAt: isOnline ? null : updatedAt,
      updatedAt,
    };

    for (const participantId of participantIds) {
      this.publishToUser(participantId, payload);
    }
  }

  async _safeListRelatedChatParticipantIds(userId, {context = "realtime_presence"} = {}) {
    if (!userId || typeof this.store?.listRelatedChatParticipantIds !== "function") {
      return [];
    }

    try {
      return await this.store.listRelatedChatParticipantIds(userId);
    } catch (error) {
      this.logger.warn?.(
        "[rodnya-backend] realtime participant lookup failed",
        JSON.stringify({
          context,
          userId,
          message: String(error?.message || error || "unknown_error"),
        }),
      );
      return [];
    }
  }

  async _handleSocketClose(userId, socket) {
    const wasOnline = this.isUserOnline(userId);
    this._unregisterSocket(userId, socket);
    if (wasOnline && !this.isUserOnline(userId)) {
      // Последний сокет ушёл — стираем active-chats тоже, иначе
      // backgrounded-сессия с памятью «я в чате X» останется
      // висеть и неправильно гасить пуши после reconnect.
      this.userActiveChats.delete(userId);
      await this._broadcastPresenceUpdate(userId, false);
    }
  }

  // Per-socket message-rate accounting. Keyed by the WebSocket
  // instance via WeakMap so we don't keep references after the
  // socket closes. The realtime protocol has exactly one action
  // (`chat.typing.set`); anything beyond a few events per second is
  // either a buggy client looping or an attacker. 60 events / 10 s
  // = 6/s is way over normal typing cadence (~3/s peak).
  _shouldThrottleIncoming(socket) {
    if (!this._socketRateState) {
      this._socketRateState = new WeakMap();
    }
    const now = Date.now();
    const windowMs = 10_000;
    const maxEventsPerWindow = 60;
    const existing = this._socketRateState.get(socket);
    const bucket = existing && existing.resetAt > now
      ? existing
      : {count: 0, resetAt: now + windowMs};
    bucket.count += 1;
    this._socketRateState.set(socket, bucket);
    return bucket.count > maxEventsPerWindow;
  }

  async _handleSocketMessage(userId, rawMessage, socket = null) {
    if (socket && this._shouldThrottleIncoming(socket)) {
      // Silently drop; logging every dropped event would be noisy
      // and gives the attacker timing feedback.
      return;
    }

    const serializedMessage = Buffer.isBuffer(rawMessage)
      ? rawMessage.toString("utf8")
      : String(rawMessage || "").trim();
    if (!serializedMessage) {
      return;
    }

    // Defense-in-depth size cap on the parsed-string side — the
    // ws-level maxPayload already enforces 8 KB at the byte level,
    // but if a future protocol bump raises that we still want a
    // sanity bound on the parsed JSON before parsing it.
    if (serializedMessage.length > 8 * 1024) {
      return;
    }

    let payload;
    try {
      payload = JSON.parse(serializedMessage);
    } catch (_) {
      return;
    }

    if (!payload || typeof payload !== "object") {
      return;
    }

    if (payload.action === "chat.typing.set") {
      await this._handleTypingEvent(userId, payload);
      return;
    }

    if (payload.action === "chat.active.set") {
      this._handleActiveChatSet(userId, payload);
      return;
    }
    if (payload.action === "chat.active.clear") {
      this._handleActiveChatClear(userId, payload);
      return;
    }
  }

  _handleActiveChatSet(userId, payload) {
    const chatId = String(payload?.chatId || "").trim();
    if (!chatId) return;
    let chats = this.userActiveChats.get(userId);
    if (!chats) {
      // S5: Map<chatId, lastTouchedMs> вместо Set — активность протухает.
      chats = new Map();
      this.userActiveChats.set(userId, chats);
    }
    chats.set(chatId, Date.now());
  }

  _handleActiveChatClear(userId, payload) {
    const chatId = String(payload?.chatId || "").trim();
    const chats = this.userActiveChats.get(userId);
    if (!chats) return;
    if (chatId) {
      chats.delete(chatId);
    } else {
      chats.clear();
    }
    if (chats.size === 0) {
      this.userActiveChats.delete(userId);
    }
  }

  async _handleTypingEvent(userId, payload) {
    const chatId = String(payload.chatId || "").trim();
    if (!chatId) {
      return;
    }

    const chat = await this.store.findChat(chatId);
    if (!chat || !Array.isArray(chat.participantIds) || !chat.participantIds.includes(userId)) {
      return;
    }

    const isTyping = payload.isTyping === true;
    const realtimePayload = {
      type: "chat.typing.updated",
      chatId,
      userId,
      isTyping,
      updatedAt: new Date().toISOString(),
    };

    for (const participantId of chat.participantIds) {
      if (participantId === userId) {
        continue;
      }
      this.publishToUser(participantId, realtimePayload);
    }
  }

  _registerSocket(userId, socket) {
    const sockets = this.userSockets.get(userId) || new Set();
    sockets.add(socket);
    this.userSockets.set(userId, sockets);
  }

  _unregisterSocket(userId, socket) {
    if (!userId) {
      return;
    }

    const sockets = this.userSockets.get(userId);
    if (!sockets) {
      return;
    }

    sockets.delete(socket);
    if (sockets.size == 0) {
      this.userSockets.delete(userId);
    }
  }
}

module.exports = {
  RealtimeHub,
};
