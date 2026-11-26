const path = require("node:path");
const {
  createCallRecord,
  isCallBusyState,
  isCallTerminalState,
  normalizeCallMetrics,
  normalizeCallSessionMap,
  normalizeJoinedSessionMap,
  normalizeNullableString,
  normalizeParticipantIds,
  normalizeStoredCall,
  nowIso,
} = require("../helpers");

module.exports = {
  // SPEED-9 B: prefetchedDb — см. listPersons выше.
  async listHiddenPersonIdsForCaller(semyaId, userId, prefetchedDb = null) {
    if (!semyaId || !userId) {
      return [];
    }
    const db = prefetchedDb || (await this._read());
    return (db.semyaMemberHiddenPersons || [])
      .filter((h) => h.semyaId === semyaId && h.userId === userId)
      .map((h) => h.personId);
  },

  async createCallInvite({
    chatId,
    initiatorId,
    recipientId,
    participantIds: requestedParticipantIds = null,
    mediaMode,
    originatedBySessionId = null,
  }) {
    return this._mutate((db, skip) => {
      const chat = this._resolveChat(db, chatId);
      if (!chat) {
        return skip(null);
      }

      const chatParticipantIds = normalizeParticipantIds(chat.participantIds || []);
      const participantIds = normalizeParticipantIds(
        Array.isArray(requestedParticipantIds) && requestedParticipantIds.length > 0
          ? requestedParticipantIds
          : chatParticipantIds,
      );
      if (
        !participantIds.includes(initiatorId) ||
        participantIds.some((participantId) => !chatParticipantIds.includes(participantId))
      ) {
        return skip(false);
      }
      if (chat.type === "direct" && participantIds.length !== 2) {
        return skip(false);
      }
      if ((chat.type === "group" || chat.type === "branch") && participantIds.length < 2) {
        return skip(false);
      }
      if (chat.type !== "direct" && chat.type !== "group" && chat.type !== "branch") {
        return skip(false);
      }

      const normalizedRecipientId =
        normalizeNullableString(recipientId) ||
        participantIds.find((participantId) => participantId !== initiatorId) ||
        "";
      if (!normalizedRecipientId || !participantIds.includes(normalizedRecipientId)) {
        return skip(false);
      }

      const hasBusyCall = db.calls
        .map((entry) => normalizeStoredCall(entry))
        .filter(Boolean)
        .some((call) => {
          if (!isCallBusyState(call.state)) {
            return false;
          }
          return participantIds.some((pid) => call.participantIds.includes(pid));
        });
      if (hasBusyCall) {
        return skip("BUSY");
      }

      const call = createCallRecord({
        chatId,
        initiatorId,
        recipientId: normalizedRecipientId,
        participantIds,
        mediaMode,
        originatedBySessionId,
      });
      db.calls.push(call);
      return structuredClone(call);
    });
  },

  async findCall(callId) {
    const db = await this._read();
    const call = db.calls
      .map((entry) => normalizeStoredCall(entry))
      .find((entry) => entry && entry.id === callId);
    return call ? structuredClone(call) : null;
  },

  async findActiveCall({userId, chatId = null} = {}) {
    const normalizedUserId = String(userId || "").trim();
    const normalizedChatId = String(chatId || "").trim();
    if (!normalizedUserId) {
      return null;
    }

    const db = await this._read();
    const statePriority = {
      active: 0,
      ringing: 1,
    };
    const activeCalls = db.calls
      .map((entry) => normalizeStoredCall(entry))
      .filter((call) => {
        if (!call || !isCallBusyState(call.state)) {
          return false;
        }
        if (!call.participantIds.includes(normalizedUserId)) {
          return false;
        }
        if (normalizedChatId && call.chatId !== normalizedChatId) {
          return false;
        }
        return true;
      })
      .sort((left, right) => {
        const leftPriority = statePriority[left.state] ?? 99;
        const rightPriority = statePriority[right.state] ?? 99;
        if (leftPriority != rightPriority) {
          return leftPriority - rightPriority;
        }
        return new Date(right.updatedAt) - new Date(left.updatedAt);
      });

    return activeCalls.length > 0 ? structuredClone(activeCalls[0]) : null;
  },

  // Discovery for group late-join: the freshest active/ringing call in a chat,
  // IGNORING participantIds — so a chat member who wasn't pre-invited can find
  // (and then POST /join) the call. Access is gated by the CALLER at the app
  // layer (chat membership); this method purposely does NOT filter by
  // participantIds. Kept distinct from findActiveCall, whose participantIds
  // filter drives busy-state and MUST stay strict (a chat member must not be
  // marked "busy" merely because their chat has a call they haven't joined).
  async findActiveCallForChat(chatId) {
    const normalizedChatId = String(chatId || "").trim();
    if (!normalizedChatId) {
      return null;
    }
    const db = await this._read();
    const statePriority = {
      active: 0,
      ringing: 1,
    };
    const calls = db.calls
      .map((entry) => normalizeStoredCall(entry))
      .filter(
        (call) =>
          call &&
          isCallBusyState(call.state) &&
          call.chatId === normalizedChatId,
      )
      .sort((left, right) => {
        const leftPriority = statePriority[left.state] ?? 99;
        const rightPriority = statePriority[right.state] ?? 99;
        if (leftPriority != rightPriority) {
          return leftPriority - rightPriority;
        }
        return new Date(right.updatedAt) - new Date(left.updatedAt);
      });
    return calls.length > 0 ? structuredClone(calls[0]) : null;
  },

  async listRingingCalls() {
    const db = await this._read();
    return db.calls
      .map((entry) => normalizeStoredCall(entry))
      .filter((call) => call && call.state === "ringing")
      .map((call) => structuredClone(call));
  },

  async acceptCall({
    callId,
    userId,
    roomName,
    sessionByUserId,
    acceptedBySessionId = null,
  }) {
    return this._mutate((db, skip) => {
      const storedCall = db.calls.find((entry) => String(entry?.id || "") === callId);
      const call = normalizeStoredCall(storedCall);
      if (!storedCall || !call) {
        return skip(null);
      }
      if (!call.participantIds.includes(userId) || call.initiatorId === userId) {
        return skip(false);
      }
      if (call.state !== "ringing") {
        return skip(undefined);
      }

      const timestamp = nowIso();
      storedCall.metrics = normalizeCallMetrics(storedCall.metrics);
      storedCall.state = "active";
      storedCall.roomName = normalizeNullableString(roomName);
      storedCall.sessionByUserId = normalizeCallSessionMap(sessionByUserId);
      // First joiner populates the N-way map; the scalars stay filled too for
      // back-compat (in-flight records + old clients that read acceptedBy*).
      storedCall.joinedSessionByUserId = normalizeJoinedSessionMap({
        [userId]: acceptedBySessionId,
      });
      storedCall.acceptedByUserId = userId;
      storedCall.acceptedBySessionId = normalizeNullableString(acceptedBySessionId);
      storedCall.acceptedAt = timestamp;
      storedCall.updatedAt = timestamp;
      storedCall.endedAt = null;
      storedCall.endedReason = null;
      storedCall.metrics.acceptLatencyMs = Math.max(
        0,
        new Date(timestamp).getTime() - new Date(call.createdAt).getTime(),
      );
      storedCall.metrics.connectedParticipantIds = [];
      storedCall.metrics.lastWebhookEvent = null;
      return structuredClone(normalizeStoredCall(storedCall));
    });
  },

  async markCallRoomJoinFailure({callId, reason = null}) {
    return this._mutate((db, skip) => {
      const storedCall = db.calls.find((entry) => String(entry?.id || "") === callId);
      const call = normalizeStoredCall(storedCall);
      if (!storedCall || !call) {
        return skip(null);
      }

      storedCall.metrics = normalizeCallMetrics(storedCall.metrics);
      storedCall.metrics.roomJoinFailureCount += 1;
      storedCall.metrics.lastRoomJoinFailureReason = normalizeNullableString(reason);
      storedCall.updatedAt = nowIso();
      return structuredClone(normalizeStoredCall(storedCall));
    });
  },

  async rejectCall({callId, userId}) {
    return this._mutate((db, skip) => {
      const storedCall = db.calls.find((entry) => String(entry?.id || "") === callId);
      const call = normalizeStoredCall(storedCall);
      if (!storedCall || !call) {
        return skip(null);
      }
      if (!call.participantIds.includes(userId) || call.initiatorId === userId) {
        return skip(false);
      }
      const isGroupCall = call.participantIds.length > 2;
      if (call.state !== "ringing" && !(isGroupCall && call.state === "active")) {
        return skip(undefined);
      }

      const timestamp = nowIso();
      if (isGroupCall) {
        storedCall.participantIds = call.participantIds.filter((id) => id !== userId);
        if (storedCall.sessionByUserId && typeof storedCall.sessionByUserId === "object") {
          delete storedCall.sessionByUserId[userId];
        }
        if (storedCall.joinedSessionByUserId && typeof storedCall.joinedSessionByUserId === "object") {
          delete storedCall.joinedSessionByUserId[userId];
        }
        if (storedCall.participantIds.length > 1) {
          storedCall.updatedAt = timestamp;
          return structuredClone(normalizeStoredCall(storedCall));
        }
      }

      storedCall.state = "rejected";
      storedCall.updatedAt = timestamp;
      storedCall.endedAt = timestamp;
      storedCall.endedReason = "rejected";
      return structuredClone(normalizeStoredCall(storedCall));
    });
  },

  async cancelCall({callId, userId}) {
    return this._mutate((db, skip) => {
      const storedCall = db.calls.find((entry) => String(entry?.id || "") === callId);
      const call = normalizeStoredCall(storedCall);
      if (!storedCall || !call) {
        return skip(null);
      }
      if (call.initiatorId !== userId) {
        return skip(false);
      }
      if (call.state !== "ringing") {
        return skip(undefined);
      }

      const timestamp = nowIso();
      storedCall.state = "cancelled";
      storedCall.updatedAt = timestamp;
      storedCall.endedAt = timestamp;
      storedCall.endedReason = "cancelled";
      return structuredClone(normalizeStoredCall(storedCall));
    });
  },

  async endStaleCall({callId, reason = "room_gone"}) {
    return this._mutate((db, skip) => {
      const storedCall = db.calls.find((entry) => String(entry?.id || "") === callId);
      const call = normalizeStoredCall(storedCall);
      if (!storedCall || !call || isCallTerminalState(call.state)) {
        return skip(null);
      }
      const timestamp = nowIso();
      storedCall.state = "ended";
      storedCall.updatedAt = timestamp;
      storedCall.endedAt = timestamp;
      storedCall.endedReason = normalizeNullableString(reason) || "room_gone";
      return structuredClone(normalizeStoredCall(storedCall));
    });
  },

  async markCallMissed({callId, reason = "missed"}) {
    return this._mutate((db, skip) => {
      const storedCall = db.calls.find((entry) => String(entry?.id || "") === callId);
      const call = normalizeStoredCall(storedCall);
      if (!storedCall || !call) {
        return skip(null);
      }
      if (call.state !== "ringing") {
        return skip(undefined);
      }

      const timestamp = nowIso();
      storedCall.state = "missed";
      storedCall.updatedAt = timestamp;
      storedCall.endedAt = timestamp;
      storedCall.endedReason = normalizeNullableString(reason) || "missed";
      return structuredClone(normalizeStoredCall(storedCall));
    });
  },

  async hangupCall({callId, userId}) {
    return this._mutate((db, skip) => {
      const storedCall = db.calls.find((entry) => String(entry?.id || "") === callId);
      const call = normalizeStoredCall(storedCall);
      if (!storedCall || !call) {
        return skip(null);
      }
      if (!call.participantIds.includes(userId)) {
        return skip(false);
      }
      if (call.state !== "active") {
        return skip(undefined);
      }

      const timestamp = nowIso();
      const normalizedUserId = String(userId || "").trim();
      storedCall.sessionByUserId = normalizeCallSessionMap(storedCall.sessionByUserId);
      storedCall.joinedSessionByUserId = normalizeJoinedSessionMap(
        storedCall.joinedSessionByUserId,
      );

      // Group call: one participant leaving is NOT the end — drop their session
      // and keep the call active while anyone else is still connected. Mirrors
      // the webhook participant_left path. The 1:1 case (≤2 participants) ends
      // the call as before. ended only when the LAST participant leaves.
      if (call.participantIds.length > 2) {
        delete storedCall.joinedSessionByUserId[normalizedUserId];
        delete storedCall.sessionByUserId[normalizedUserId];
        // Hand the scalar back-compat fields off to a remaining joiner so old
        // clients still resolve an owning session (or clear them if none left).
        if (normalizeNullableString(storedCall.acceptedByUserId) === normalizedUserId) {
          const remainingJoiner = Object.keys(storedCall.joinedSessionByUserId)[0];
          if (remainingJoiner) {
            storedCall.acceptedByUserId = remainingJoiner;
            storedCall.acceptedBySessionId =
              storedCall.joinedSessionByUserId[remainingJoiner];
          } else {
            storedCall.acceptedByUserId = null;
            storedCall.acceptedBySessionId = null;
          }
        }
        const someoneStillConnected =
          Object.keys(storedCall.sessionByUserId).length > 0;
        if (someoneStillConnected) {
          storedCall.updatedAt = timestamp;
          return structuredClone(normalizeStoredCall(storedCall));
        }
      }

      storedCall.state = "ended";
      storedCall.updatedAt = timestamp;
      storedCall.endedAt = timestamp;
      storedCall.endedReason = "hangup";
      return structuredClone(normalizeStoredCall(storedCall));
    });
  },

  // GP3: grow a live call's invite list (add-mid-call). Chat-membership of the
  // new ids is validated by the caller (POST /v1/calls/:id/add). This ONLY
  // extends participantIds — it deliberately does NOT touch sessionByUserId /
  // joinedSessionByUserId, so the last-leaves teardown in hangupCall
  // (someoneStillConnected) is unaffected: the call still ends only when the
  // last JOINED participant leaves, never because the roster grew.
  async addCallParticipants({callId, userIds}) {
    return this._mutate((db, skip) => {
      const storedCall = db.calls.find(
        (entry) => String(entry?.id || "") === callId,
      );
      const call = normalizeStoredCall(storedCall);
      if (!storedCall || !call) {
        return skip(null);
      }
      if (call.state !== "active" && call.state !== "ringing") {
        return skip(undefined);
      }
      const existing = normalizeParticipantIds(storedCall.participantIds || []);
      const additions = normalizeParticipantIds(userIds || []).filter(
        (participantId) => !existing.includes(participantId),
      );
      if (additions.length === 0) {
        return skip(false);
      }
      storedCall.participantIds = [...existing, ...additions];
      storedCall.updatedAt = nowIso();
      return {
        call: structuredClone(normalizeStoredCall(storedCall)),
        addedUserIds: additions,
      };
    });
  },

  async applyCallWebhook({roomName, event, participantIdentity = null}) {
    const normalizedRoomName = String(roomName || "").trim();
    if (!normalizedRoomName) {
      return null;
    }

    return this._mutate((db, skip) => {
      const storedCall = db.calls.find((entry) => {
        return normalizeNullableString(entry?.roomName) === normalizedRoomName;
      });
      const call = normalizeStoredCall(storedCall);
      if (!storedCall || !call || isCallTerminalState(call.state)) {
        return skip(call ? structuredClone(call) : null);
      }

      const normalizedEvent = String(event || "").trim();
      const normalizedParticipantIdentity = String(participantIdentity || "").trim();
      const timestamp = nowIso();
      storedCall.metrics = normalizeCallMetrics(storedCall.metrics);
      storedCall.metrics.lastWebhookEvent = normalizedEvent || null;

      if (normalizedEvent === "participant_joined" && call.state === "active") {
        if (normalizedParticipantIdentity) {
          const wasConnected = storedCall.metrics.connectedParticipantIds.includes(
            normalizedParticipantIdentity,
          );
          if (wasConnected) {
            storedCall.metrics.reconnectCount += 1;
          } else {
            storedCall.metrics.connectedParticipantIds = normalizeParticipantIds([
              ...storedCall.metrics.connectedParticipantIds,
              normalizedParticipantIdentity,
            ]);
          }
        }
        storedCall.updatedAt = timestamp;
        return structuredClone(normalizeStoredCall(storedCall));
      }

      if (normalizedEvent === "participant_connection_aborted" && call.state === "ringing") {
        storedCall.state = "missed";
        storedCall.updatedAt = timestamp;
        storedCall.endedAt = timestamp;
        storedCall.endedReason = normalizedParticipantIdentity || "missed";
        return structuredClone(normalizeStoredCall(storedCall));
      }

      if (normalizedEvent === "participant_left" || normalizedEvent === "room_finished") {
        if (normalizedParticipantIdentity) {
          storedCall.metrics.connectedParticipantIds =
            storedCall.metrics.connectedParticipantIds.filter(
              (value) => value !== normalizedParticipantIdentity,
            );
        }
        if (normalizedEvent === "participant_left") {
          const leftUserId = normalizedParticipantIdentity.split("#")[0];
          const sameUserStillConnected =
            Boolean(leftUserId) &&
            storedCall.metrics.connectedParticipantIds.some(
              (id) => String(id || "").split("#")[0] === leftUserId,
            );
          if (sameUserStillConnected) {
            storedCall.updatedAt = timestamp;
            return structuredClone(normalizeStoredCall(storedCall));
          }
          if (
            call.participantIds.length > 2 &&
            storedCall.metrics.connectedParticipantIds.length > 0
          ) {
            storedCall.updatedAt = timestamp;
            return structuredClone(normalizeStoredCall(storedCall));
          }
        }
        storedCall.state = "ended";
        storedCall.updatedAt = timestamp;
        storedCall.endedAt = timestamp;
        storedCall.endedReason = normalizedParticipantIdentity || normalizedEvent;
        return structuredClone(normalizeStoredCall(storedCall));
      }

      if (normalizedEvent) {
        storedCall.updatedAt = timestamp;
        return structuredClone(normalizeStoredCall(storedCall));
      }

      return skip(structuredClone(call));
    });
  },
};
