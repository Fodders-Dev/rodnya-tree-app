const {
  buildCallParticipantIdentity,
  deriveSessionPublicId,
  normalizeParticipantIds,
} = require("../store");
const {
  logCallEvent,
  mapCallRecord,
  mapChatMessage,
  mapChatRecord,
} = require("../mappers");

const DEFAULT_CALL_INVITE_TIMEOUT_MS = 30_000;
const GROUP_CALL_MAX_PARTICIPANTS = 16;

function createCallCoordinator({
  store,
  config,
  realtimeHub = null,
  liveKitService,
  createAndDispatchNotification,
  getReadDeviceContext,
}) {
  const resolvedLiveKitService = liveKitService;
  const ringTimeoutTimers = new Map();
  const configuredCallInviteTimeoutMs = Number(config?.callInviteTimeoutMs);
  const callInviteTimeoutMs =
    Number.isFinite(configuredCallInviteTimeoutMs) &&
    configuredCallInviteTimeoutMs > 0
      ? Math.floor(configuredCallInviteTimeoutMs)
      : DEFAULT_CALL_INVITE_TIMEOUT_MS;

  function readDeviceContext(req) {
    return getReadDeviceContext()(req);
  }

  function clearCallInviteTimeout(callId) {
    const normalizedCallId = String(callId || "").trim();
    if (!normalizedCallId) {
      return;
    }
    const existingTimer = ringTimeoutTimers.get(normalizedCallId);
    if (existingTimer) {
      clearTimeout(existingTimer);
      ringTimeoutTimers.delete(normalizedCallId);
    }
  }

  async function publishCallState(call) {
    if (!call || typeof call !== "object") {
      return;
    }

    for (const participantId of call.participantIds || []) {
      realtimeHub?.publishToUser(participantId, ({sessionPublicId}) => ({
        type: "call.state.updated",
        call: mapCallRecord(call, {
          viewerUserId: participantId,
          viewerSessionId: sessionPublicId,
        }),
      }));
    }

    if (isCallTerminalForSummary(call)) {
      try {
        await appendCallSummaryMessage(call);
      } catch (error) {
        console.warn(
          "[backend] failed to append call summary message",
          JSON.stringify({
            callId: call.id || null,
            chatId: call.chatId || null,
            message: String(error?.message || error || "unknown_error"),
          }),
        );
      }
      // BUG 2: снимаем входящую уведомку звонка у получателей. Realtime
      // publish выше доходит только до живого WS — у убитого приложения
      // нативная full-screen уведомка зависала бы. Шлём data-пуш
      // call_cancelled/call_ended (через push-gateway) — нативный
      // RodnyaPushService снимет уведомку и, если звонок не принят,
      // выложит «Пропущенный».
      await dispatchCallTerminalSignal(call);
    }
  }

  // BUG 2: терминальный сигнал звонка получателям (НЕ инициатору — у него
  // не было входящей уведомки). data-пуш в фоне (awaitPush:false, как P0):
  // не держит обработчик, и недоступное устройство не тормозит остальных.
  async function dispatchCallTerminalSignal(call) {
    const state = String(call?.state || "").trim();
    const type = state === "ended" ? "call_ended" : "call_cancelled";
    const initiatorId = String(call.initiatorId || "").trim();
    let callerName = "Звонок";
    if (initiatorId) {
      try {
        const initiator = await store.findUserById(initiatorId);
        if (initiator) {
          callerName = displayNameForCallParticipant(initiator);
        }
      } catch (_) {
        // best-effort — без имени покажем дефолтный заголовок
      }
    }
    const recipients = (call.participantIds || [])
      .map((id) => String(id || "").trim())
      .filter((id) => id && id !== initiatorId);
    for (const recipientId of recipients) {
      await createAndDispatchNotification({
        userId: recipientId,
        type,
        title: callerName,
        body: "",
        data: {
          callId: call.id,
          chatId: call.chatId,
          callState: state,
          mediaMode: call.mediaMode,
        },
        // Контрольный сигнал, не элемент списка уведомлений.
        silent: true,
        awaitPush: false,
      });
    }
  }

  function isCallTerminalForSummary(call) {
    const state = String(call?.state || "").trim();
    return (
      state === "ended" ||
      state === "rejected" ||
      state === "cancelled" ||
      state === "missed" ||
      state === "failed"
    );
  }

  function describeCallSummaryText(call) {
    const isVideo = call?.mediaMode === "video";
    const kindLabel = isVideo ? "Видеозвонок" : "Аудиозвонок";
    const state = String(call?.state || "").trim();
    if (state === "ended") {
      const startedAtMs = call.acceptedAt
        ? new Date(call.acceptedAt).getTime()
        : null;
      const endedAtMs = call.endedAt
        ? new Date(call.endedAt).getTime()
        : null;
      const durationMs =
        Number.isFinite(startedAtMs) && Number.isFinite(endedAtMs)
          ? Math.max(0, endedAtMs - startedAtMs)
          : null;
      const formatted = formatCallDurationLabel(durationMs);
      return formatted ? `📞 ${kindLabel} · ${formatted}` : `📞 ${kindLabel}`;
    }
    if (state === "missed") {
      return isVideo ? "📞 Пропущенный видеозвонок" : "📞 Пропущенный звонок";
    }
    if (state === "rejected") {
      return isVideo ? "📞 Видеозвонок отклонён" : "📞 Звонок отклонён";
    }
    if (state === "cancelled") {
      return isVideo ? "📞 Видеозвонок отменён" : "📞 Звонок отменён";
    }
    if (state === "failed") {
      return "📞 Не удалось позвонить";
    }
    return `📞 ${kindLabel}`;
  }

  function formatCallDurationLabel(durationMs) {
    if (!Number.isFinite(durationMs) || durationMs <= 0) {
      return null;
    }
    const totalSeconds = Math.floor(durationMs / 1000);
    const seconds = totalSeconds % 60;
    const totalMinutes = Math.floor(totalSeconds / 60);
    const minutes = totalMinutes % 60;
    const hours = Math.floor(totalMinutes / 60);
    const padded = (value) => String(value).padStart(2, "0");
    if (hours > 0) {
      return `${hours}:${padded(minutes)}:${padded(seconds)}`;
    }
    return `${minutes}:${padded(seconds)}`;
  }

  async function appendCallSummaryMessage(call) {
    if (!call || !call.chatId || !call.initiatorId) {
      return;
    }
    if (typeof store.findChat === "function") {
      const chat = await store.findChat(call.chatId);
      if (!chat) {
        return;
      }
    }

    const startedAtMs = call.acceptedAt
      ? new Date(call.acceptedAt).getTime()
      : null;
    const endedAtMs = call.endedAt
      ? new Date(call.endedAt).getTime()
      : null;
    const durationMs =
      Number.isFinite(startedAtMs) && Number.isFinite(endedAtMs)
        ? Math.max(0, endedAtMs - startedAtMs)
        : null;

    const message = await store.addChatMessage({
      chatId: call.chatId,
      senderId: call.initiatorId,
      text: describeCallSummaryText(call),
      attachments: [],
      mediaUrls: [],
      imageUrl: null,
      clientMessageId: `call_summary_${call.id}`,
      replyTo: null,
      call: {
        callId: call.id,
        state: call.state,
        mediaMode: call.mediaMode,
        durationMs,
        initiatorId: call.initiatorId,
        direction: "outgoing",
      },
    });

    if (!message || message._deduplicated === true) {
      return;
    }

    const chat =
      typeof store.findChat === "function"
        ? await store.findChat(call.chatId)
        : null;
    const mappedMessage = mapChatMessage(message);
    const mappedChat = chat ? mapChatRecord(chat) : null;

    if (typeof realtimeHub?.publishToChat === "function") {
      await realtimeHub.publishToChat(message.chatId, {
        type: "chat.updated",
        chatId: message.chatId,
        chat: mappedChat,
      });
      await realtimeHub.publishToChat(message.chatId, {
        type: "chat.message.created",
        chatId: message.chatId,
        chat: mappedChat,
        message: mappedMessage,
      });
    } else if (chat && Array.isArray(chat.participantIds)) {
      for (const participantId of chat.participantIds) {
        realtimeHub?.publishToUser(participantId, {
          type: "chat.updated",
          chatId: message.chatId,
          chat: mappedChat,
        });
        realtimeHub?.publishToUser(participantId, {
          type: "chat.message.created",
          chatId: message.chatId,
          chat: mappedChat,
          message: mappedMessage,
        });
      }
    }
  }

  function scheduleCallInviteTimeout(call) {
    if (
      !call ||
      typeof call !== "object" ||
      call.state !== "ringing" ||
      callInviteTimeoutMs <= 0
    ) {
      return;
    }

    clearCallInviteTimeout(call.id);
    const createdAtMs = new Date(call.createdAt || 0).getTime();
    const elapsedMs = Number.isFinite(createdAtMs)
      ? Math.max(0, Date.now() - createdAtMs)
      : 0;
    const delayMs = Math.max(250, callInviteTimeoutMs - elapsedMs);
    const timer = setTimeout(async () => {
      ringTimeoutTimers.delete(call.id);
      try {
        const expiredCall =
          typeof store.markCallMissed === "function"
            ? await store.markCallMissed({
                callId: call.id,
                reason: "missed",
              })
            : null;
        if (!expiredCall) {
          return;
        }
        logCallEvent("invite.missed", expiredCall, {
          timeoutMs: callInviteTimeoutMs,
        });
        await publishCallState(expiredCall);
      } catch (error) {
        console.error(
          "[backend] call timeout",
          JSON.stringify({
            callId: call.id || null,
            message: String(error?.message || error || "unknown_error"),
          }),
        );
      }
    }, delayMs);
    if (typeof timer?.unref === "function") {
      timer.unref();
    }
    ringTimeoutTimers.set(call.id, timer);
  }

  function isCallInviteExpired(call) {
    if (
      !call ||
      typeof call !== "object" ||
      call.state !== "ringing" ||
      callInviteTimeoutMs <= 0
    ) {
      return false;
    }

    const createdAtMs = new Date(call.createdAt || 0).getTime();
    if (!Number.isFinite(createdAtMs) || createdAtMs <= 0) {
      return false;
    }
    return Date.now() - createdAtMs >= callInviteTimeoutMs;
  }

  async function expireRingingCallIfNeeded(call, {
    reason = "missed",
    eventType = "invite.missed",
    extra = {},
  } = {}) {
    if (!isCallInviteExpired(call)) {
      return call;
    }

    const expiredCall =
      typeof store.markCallMissed === "function"
        ? await store.markCallMissed({
            callId: call.id,
            reason,
          })
        : null;
    if (!expiredCall) {
      return store.findCall(call.id);
    }
    if (expiredCall.state === "ringing") {
      return expiredCall;
    }

    clearCallInviteTimeout(expiredCall.id);
    logCallEvent(eventType, expiredCall, {
      timeoutMs: callInviteTimeoutMs,
      lazyExpired: true,
      ...extra,
    });
    await publishCallState(expiredCall);
    return expiredCall;
  }

  async function findFreshCall(callId, {viewerUserId = null} = {}) {
    const call = await store.findCall(callId);
    if (!call) {
      return null;
    }
    const expiredCall = await expireRingingCallIfNeeded(call, {
      reason: "missed",
      eventType: "invite.missed",
      extra: {
        viewerUserId,
        source: "find_call",
      },
    });
    return expiredCall || call;
  }

  async function findFreshActiveCall({userId, chatId = null} = {}) {
    const activeCall = await store.findActiveCall({userId, chatId});
    if (!activeCall) {
      return null;
    }
    const expiredCall = await expireRingingCallIfNeeded(activeCall, {
      reason: "missed",
      eventType: "invite.missed",
      extra: {
        viewerUserId: userId,
        chatId: chatId || activeCall.chatId,
        source: "find_active_call",
      },
    });
    if (!expiredCall || expiredCall.state === "ringing") {
      return expiredCall || activeCall;
    }
    return store.findActiveCall({userId, chatId});
  }

  async function reconcileUserBusyCall(userId, {chatId = null} = {}) {
    const busyCall = await store.findActiveCall({userId, chatId});
    if (!busyCall) {
      return null;
    }
    if (busyCall.state === "ringing") {
      const expiredCall = await expireRingingCallIfNeeded(busyCall, {
        reason: "missed",
        eventType: "invite.missed",
        extra: {
          viewerUserId: userId,
          chatId: chatId || busyCall.chatId,
          source: "pre_invite_reconcile",
        },
      });
      return expiredCall || busyCall;
    }
    if (busyCall.state === "active") {
      const acceptedAtMs = new Date(
        busyCall.acceptedAt || busyCall.updatedAt || busyCall.createdAt || 0,
      ).getTime();
      const ageMs = Number.isFinite(acceptedAtMs) ? Date.now() - acceptedAtMs : 0;
      const roomName = busyCall.roomName || `call_${busyCall.id}`;
      let shouldEndStale = ageMs > 6 * 60 * 60 * 1000;
      if (
        !shouldEndStale &&
        ageMs > 20_000 &&
        resolvedLiveKitService.isConfigured &&
        typeof resolvedLiveKitService.listRooms === "function"
      ) {
        try {
          const rooms = await resolvedLiveKitService.listRooms([roomName]);
          const room = Array.isArray(rooms)
            ? rooms.find((r) => String(r?.name || "") === roomName)
            : null;
          if (!room || Number(room.numParticipants || 0) === 0) {
            shouldEndStale = true;
          }
        } catch (_) {
          // Best-effort LiveKit room check — don't drop call on transient error.
        }
      }
      if (shouldEndStale && typeof store.endStaleCall === "function") {
        const ended = await store.endStaleCall({
          callId: busyCall.id,
          reason: "room_gone",
        });
        if (ended) {
          clearCallInviteTimeout(ended.id);
          await publishCallState(ended);
          if (
            resolvedLiveKitService.isConfigured &&
            typeof resolvedLiveKitService.deleteRoom === "function"
          ) {
            resolvedLiveKitService.deleteRoom(roomName).catch(() => {});
          }
          return null;
        }
      }
    }
    return busyCall;
  }

  async function restoreRingingCallTimeouts() {
    if (typeof store.listRingingCalls !== "function") {
      return;
    }
    try {
      const ringingCalls = await store.listRingingCalls();
      for (const call of ringingCalls) {
        scheduleCallInviteTimeout(call);
      }
    } catch (error) {
      console.error(
        "[backend] restore ringing calls",
        JSON.stringify({
          message: String(error?.message || error || "unknown_error"),
        }),
      );
    }
  }

  void restoreRingingCallTimeouts();

  function resolvePublicApiUrl(req) {
    return String(config.publicApiUrl || "").trim() ||
      `${req.protocol}://${req.get("host")}`;
  }

  function displayNameForCallParticipant(user) {
    return (
      user?.profile?.displayName ||
      user?.displayName ||
      user?.email ||
      "Участник"
    );
  }

  async function createCallSessionsForParticipants({
    call,
    roomName,
    participantIds,
    ownerSessionByUserId = {},
  }) {
    const sessionEntries = await Promise.all(
      participantIds.map(async (participantId) => {
        const ownerSessionId = String(
          ownerSessionByUserId[participantId] || "",
        ).trim();
        if (!ownerSessionId) {
          return [participantId, null];
        }
        const participant = await store.findUserById(participantId);
        const session = await resolvedLiveKitService.createSession({
          roomName,
          participantIdentity: buildCallParticipantIdentity(
            participantId,
            ownerSessionId,
          ),
          participantName: displayNameForCallParticipant(participant),
          metadata: {
            callId: call.id,
            chatId: call.chatId,
            userId: participantId,
            sessionPublicId: ownerSessionId,
            mediaMode: call.mediaMode,
          },
        });
        return [participantId, session];
      }),
    );
    return Object.fromEntries(
      sessionEntries.filter(([, session]) => session != null),
    );
  }

  // Group late-join: mint a LiveKit session for the CALLER's own device and
  // merge it into the (already-active) call, so anyone with membership can
  // "залететь в звонок". Shared by POST /accept on an active call and the
  // dedicated POST /join. Responds with mapCallRecord carrying the caller's
  // real session ({url, token, roomName}). Assumes LiveKit is configured
  // (callers check) and the call is non-terminal.
  async function joinActiveCall(req, res, call) {
    const roomName = call.roomName || `call_${call.id}`;
    const callerId = req.auth.user.id;
    const callerSessionId = req.auth.sessionPublicId;
    try {
      // A non-invited chat member "залетает": put them on the roster first —
      // addCallParticipantSession (and later hangupCall) both require the
      // caller to be in participantIds. addCallParticipants only GROWS the
      // list, so a pre-invited joiner or a same-device rejoin is a no-op here.
      // addCallParticipantSession re-reads fresh, so it stays correct even if
      // this local `call` snapshot raced a concurrent add.
      let activeCall = call;
      if (
        !normalizeParticipantIds(call.participantIds || []).includes(callerId)
      ) {
        const grown = await store.addCallParticipants({
          callId: call.id,
          userIds: [callerId],
        });
        if (grown === null) {
          res.status(404).json({message: "Звонок не найден"});
          return;
        }
        if (grown === undefined) {
          res.status(409).json({message: "Звонок уже недоступен"});
          return;
        }
        if (grown && grown.call) {
          activeCall = grown.call;
        }
      }
      const callParticipantIds = normalizeParticipantIds(
        activeCall.participantIds || [],
      );
      await resolvedLiveKitService.ensureRoom(roomName, {
        maxParticipants: Math.max(
          callParticipantIds.length,
          GROUP_CALL_MAX_PARTICIPANTS,
        ),
      });
      const sessionByUserId = await createCallSessionsForParticipants({
        call: activeCall,
        roomName,
        participantIds: [callerId],
        ownerSessionByUserId: {[callerId]: callerSessionId},
      });
      const joinedCall = await store.addCallParticipantSession({
        callId: call.id,
        userId: callerId,
        sessionId: callerSessionId,
        session: sessionByUserId[callerId],
      });
      if (!joinedCall) {
        res.status(409).json({message: "Не удалось подключиться к звонку"});
        return;
      }
      clearCallInviteTimeout(joinedCall.id);

      await publishCallState(joinedCall);

      logCallEvent("join.succeeded", joinedCall, {viewerUserId: callerId});

      res.json({
        call: mapCallRecord(joinedCall, {
          viewerUserId: callerId,
          viewerSessionId: callerSessionId,
        }),
      });
    } catch (error) {
      const failedCall =
        typeof store.markCallRoomJoinFailure === "function"
          ? await store.markCallRoomJoinFailure({
              callId: call.id,
              reason: error?.message || "room_prepare_failed",
            })
          : call;
      logCallEvent("join.failed", failedCall || call, {
        viewerUserId: callerId,
        error: String(error?.message || error || "room_prepare_failed"),
      });
      res.status(502).json({message: "Не удалось подготовить комнату звонка"});
    }
  }


  return {
    callInviteTimeoutMs,
    groupCallMaxParticipants: GROUP_CALL_MAX_PARTICIPANTS,
    clearCallInviteTimeout,
    publishCallState,
    dispatchCallTerminalSignal,
    appendCallSummaryMessage,
    scheduleCallInviteTimeout,
    isCallInviteExpired,
    expireRingingCallIfNeeded,
    findFreshCall,
    findFreshActiveCall,
    reconcileUserBusyCall,
    restoreRingingCallTimeouts,
    resolvePublicApiUrl,
    displayNameForCallParticipant,
    createCallSessionsForParticipants,
    joinActiveCall,
  };
}

module.exports = {
  createCallCoordinator,
  DEFAULT_CALL_INVITE_TIMEOUT_MS,
  GROUP_CALL_MAX_PARTICIPANTS,
};
