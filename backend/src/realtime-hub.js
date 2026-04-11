const {WebSocketServer} = require("ws");

class RealtimeHub {
  constructor({store, logger = console}) {
    this.store = store;
    this.logger = logger;
    this.userSockets = new Map();
    this.wss = null;
  }

  attach(server) {
    this.wss = new WebSocketServer({
      server,
      path: "/v1/realtime",
    });

    this.wss.on("connection", async (socket, request) => {
      let userId = null;

      try {
        const url = new URL(request.url, "http://127.0.0.1");
        const token = String(url.searchParams.get("accessToken") || "").trim();

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

        await this.store.touchSession(token);
        userId = user.id;
        this._registerSocket(userId, socket);
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
          this.logger.warn?.("[lineage-backend] realtime socket error", error);
          void this._handleSocketClose(userId, socket);
        });

        socket.on("message", (rawMessage) => {
          void this._handleSocketMessage(userId, rawMessage);
        });
      } catch (error) {
        this.logger.warn?.("[lineage-backend] realtime connection failed", error);
        socket.close(1011, "Realtime initialization failed");
      }
    });
  }

  publishToUser(userId, payload) {
    const sockets = this.userSockets.get(userId);
    if (!sockets || sockets.size === 0) {
      return;
    }

    const serializedPayload = JSON.stringify(payload);
    for (const socket of sockets) {
      if (socket.readyState === socket.OPEN) {
        socket.send(serializedPayload);
      }
    }
  }

  isUserOnline(userId) {
    const sockets = this.userSockets.get(userId);
    return Boolean(sockets && sockets.size > 0);
  }

  async _collectOnlineParticipants(userId) {
    const participantIds = await this.store.listRelatedChatParticipantIds(userId);
    return participantIds.filter((participantId) => this.isUserOnline(participantId));
  }

  async _broadcastPresenceUpdate(userId, isOnline) {
    const participantIds = await this.store.listRelatedChatParticipantIds(userId);
    const payload = {
      type: "presence.updated",
      userId,
      isOnline,
      updatedAt: new Date().toISOString(),
    };

    for (const participantId of participantIds) {
      this.publishToUser(participantId, payload);
    }
  }

  async _handleSocketClose(userId, socket) {
    const wasOnline = this.isUserOnline(userId);
    this._unregisterSocket(userId, socket);
    if (wasOnline && !this.isUserOnline(userId)) {
      await this._broadcastPresenceUpdate(userId, false);
    }
  }

  async _handleSocketMessage(userId, rawMessage) {
    const serializedMessage = Buffer.isBuffer(rawMessage)
      ? rawMessage.toString("utf8")
      : String(rawMessage || "").trim();
    if (!serializedMessage) {
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
