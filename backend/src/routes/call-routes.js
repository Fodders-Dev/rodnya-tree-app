const express = require("express");
const {
  buildCallParticipantIdentity,
  deriveSessionPublicId,
  normalizeParticipantIds,
} = require("../store");
const {
  logCallEvent,
  mapCallRecord,
} = require("../mappers");
const {GROUP_CALL_MAX_PARTICIPANTS} = require("../calls/call-coordinator");

function registerLiveKitWebhookRoute(app, {
  store,
  liveKitService,
  callCoordinator,
}) {
  const resolvedLiveKitService = liveKitService;
  const {
    scheduleCallInviteTimeout,
    clearCallInviteTimeout,
    publishCallState,
  } = callCoordinator;

  app.post(
    "/v1/livekit/webhook",
    express.text({type: "*/*"}),
    async (req, res) => {
      try {
        const authHeader =
          String(req.get("Authorization") || "").trim() ||
          String(req.get("Authorize") || "").trim() ||
          String(req.get("x-livekit-signature") || "").trim();
        const body =
          typeof req.body === "string" ? req.body : JSON.stringify(req.body || {});
        const event = await resolvedLiveKitService.receiveWebhook(body, authHeader);
        const roomName = String(event?.room?.name || event?.room?.sid || "").trim();
        const participantIdentity = String(
          event?.participant?.identity || "",
        ).trim();
        const call = await store.applyCallWebhook({
          roomName,
          event: event?.event,
          participantIdentity,
        });
        if (call) {
          if (call.state === "ringing") {
            scheduleCallInviteTimeout(call);
          } else {
            clearCallInviteTimeout(call.id);
          }
          if (
            ["ended", "missed", "rejected", "cancelled", "failed"].includes(
              call.state,
            ) &&
            resolvedLiveKitService.isConfigured &&
            typeof resolvedLiveKitService.deleteRoom === "function"
          ) {
            const callRoomName = call.roomName || `call_${call.id}`;
            resolvedLiveKitService.deleteRoom(callRoomName).catch(() => {});
          }
          logCallEvent("webhook.processed", call, {
            webhookEvent: String(event?.event || "").trim() || null,
            participantIdentity: participantIdentity || null,
            roomName: roomName || null,
          });
          await publishCallState(call);
        }
        res.json({ok: true});
      } catch (error) {
        res.status(401).json({message: "Webhook verification failed"});
      }
    },
  );
}

function registerCallRoutes(app, {
  store,
  realtimeHub = null,
  liveKitService,
  requireAuth,
  requireChatAccess,
  requireCallAccess,
  requireCallJoinAccess,
  createAndDispatchNotification,
  callCoordinator,
}) {
  const resolvedLiveKitService = liveKitService;
  const {
    callInviteTimeoutMs,
    clearCallInviteTimeout,
    publishCallState,
    dispatchCallTerminalSignal,
    appendCallSummaryMessage,
    scheduleCallInviteTimeout,
    expireRingingCallIfNeeded,
    findFreshActiveCall,
    reconcileUserBusyCall,
    resolvePublicApiUrl,
    displayNameForCallParticipant,
    createCallSessionsForParticipants,
    joinActiveCall,
  } = callCoordinator;

  app.post("/v1/calls", requireAuth, async (req, res) => {
    if (!resolvedLiveKitService.isConfigured) {
      res.status(503).json({message: "Звонки пока не настроены на сервере"});
      return;
    }

    const requestedChatId = String(req.body?.chatId || "").trim();
    const mediaMode = String(req.body?.mediaMode || "audio").trim().toLowerCase() === "video"
      ? "video"
      : "audio";
    if (!requestedChatId) {
      res.status(400).json({message: "Нужен chatId"});
      return;
    }

    const chat = await requireChatAccess(req, res, requestedChatId);
    if (!chat) {
      return;
    }
    const chatId = chat.id;
    const chatParticipantIds = normalizeParticipantIds(chat.participantIds || []);
    const requestedParticipantIds = Array.isArray(req.body?.participantIds)
      ? normalizeParticipantIds(req.body.participantIds)
      : [];
    const participantIds = requestedParticipantIds.length > 0
      ? normalizeParticipantIds([
          req.auth.user.id,
          ...requestedParticipantIds,
        ])
      : chatParticipantIds;
    const isSupportedCallChat =
      chat.type === "direct" || chat.type === "group" || chat.type === "branch";
    const participantsBelongToChat = participantIds.every((participantId) =>
      chatParticipantIds.includes(participantId),
    );
    if (
      !isSupportedCallChat ||
      !participantsBelongToChat ||
      !participantIds.includes(req.auth.user.id) ||
      participantIds.length < 2 ||
      (chat.type === "direct" && participantIds.length !== 2)
    ) {
      res.status(400).json({message: "Не удалось определить участников звонка"});
      return;
    }

    const recipientId = participantIds.find((entry) => entry !== req.auth.user.id);
    if (!recipientId) {
      res.status(400).json({message: "Не удалось определить собеседника"});
      return;
    }

    for (const participantId of participantIds) {
      if (
        participantId !== req.auth.user.id &&
        (await store.isUserBlockedBetween(req.auth.user.id, participantId))
      ) {
        res.status(403).json({
          message: "Звонок недоступен: один из пользователей заблокирован",
        });
        return;
      }
    }

    for (const participantId of participantIds) {
      await reconcileUserBusyCall(participantId);
    }

    const call = await store.createCallInvite({
      chatId,
      initiatorId: req.auth.user.id,
      recipientId,
      participantIds,
      mediaMode,
      originatedBySessionId: req.auth.sessionPublicId,
    });
    if (call === null) {
      res.status(404).json({message: "Чат не найден"});
      return;
    }
    if (call === false) {
      // Групповые/branch-звонки поддержаны (store.createCallInvite их
      // принимает) — этот путь остаётся только для настоящих ошибок
      // валидации участников, поэтому сообщение общее.
      res.status(400).json({message: "Не удалось создать звонок"});
      return;
    }
    if (call === "BUSY") {
      logCallEvent(
        "invite.busy",
        {
          id: null,
          chatId,
          mediaMode,
          state: "busy",
          createdAt: null,
          acceptedAt: null,
          endedAt: null,
          endedReason: "busy",
          metrics: null,
        },
        {
          initiatorId: req.auth.user.id,
          participantIds,
        },
      );
      res.status(409).json({message: "Пользователь уже участвует в другом звонке"});
      return;
    }

    // FIX A1 (P0 latency): realtimeHub publish онлайн-получателям ИДЁТ
    // ПЕРВЫМ — in-memory WS доставляет звонок мгновенно и не должен стоять
    // за последовательной рассылкой HTTP-пушей. Раньше цикл пушей (await
    // на VKPNS-fetch без таймаута к мёртвому токену) висел до 30с, и из-за
    // этого и звонящий (ждёт ответ POST), и онлайн-получатель (publish был
    // ПОСЛЕ цикла) получали звонок с задержкой.
    const originatedSessionId = String(call.originatedBySessionId || "").trim();
    for (const participantId of call.participantIds || []) {
      realtimeHub?.publishToUser(participantId, ({sessionPublicId}) => {
        const viewerSessionId = String(sessionPublicId || "").trim();
        if (
          participantId === call.initiatorId &&
          originatedSessionId &&
          viewerSessionId !== originatedSessionId
        ) {
          return null;
        }
        return {
          type: "call.invite.created",
          call: mapCallRecord(call, {
            viewerUserId: participantId,
            viewerSessionId,
          }),
        };
      });
    }

    logCallEvent("invite.created", call, {
      initiatorId: call.initiatorId,
      participantIds: call.participantIds,
    });
    scheduleCallInviteTimeout(call);

    // FIX A2: запись уведомления (createNotification + realtime) синхронная
    // и быстрая, а МЕДЛЕННЫЙ HTTP-пуш уходит в фон (awaitPush:false) — мёртвый
    // токен больше не держит ответ. Последовательно (не Promise.all) — у
    // FileStore read-modify-write, параллельные записи затирали бы друг друга.
    const callerName = displayNameForCallParticipant(req.auth.user);
    const isGroupCall = participantIds.length > 2;
    for (const inviteeId of participantIds) {
      if (inviteeId === req.auth.user.id) {
        continue;
      }
      await createAndDispatchNotification({
        userId: inviteeId,
        type: "call_invite",
        title: callerName,
        body: isGroupCall
          ? (mediaMode === "video" ? "Групповой видеозвонок" : "Групповой аудиозвонок")
          : (mediaMode === "video" ? "Видеозвонок" : "Аудиозвонок"),
        data: {
          chatId,
          callId: call.id,
          mediaMode,
        },
        awaitPush: false,
      });
    }

    // Отвечаем сразу — звонящий (custom_api_call_service ждёт ответ POST)
    // показывает экран мгновенно; онлайн-получатель уже зазвенел по
    // realtime-публикации выше, не дожидаясь HTTP-пушей.
    res.status(201).json({
      call: mapCallRecord(call, {
        viewerUserId: req.auth.user.id,
        viewerSessionId: req.auth.sessionPublicId,
      }),
    });
  });

  app.get("/v1/calls/active", requireAuth, async (req, res) => {
    const chatId = String(req.query?.chatId || "").trim();
    let activeCall = await findFreshActiveCall({
      userId: req.auth.user.id,
      chatId: chatId || null,
    });
    // Discovery for group late-join: a chat member who is NOT on the call's
    // roster can still SEE the chat's active call (session:null) so they can
    // then "залететь" via POST /join. Busy-state (findActiveCall above) stays
    // strict; this only widens READ visibility, and only when gated on
    // authoritative chat membership.
    if (!activeCall && chatId) {
      const chat = await store.findChat(chatId);
      const chatMembers = Array.isArray(chat?.participantIds)
        ? chat.participantIds
        : [];
      if (chatMembers.includes(req.auth.user.id)) {
        const chatCall = await store.findActiveCallForChat(chatId);
        if (chatCall) {
          const fresh =
            (await expireRingingCallIfNeeded(chatCall, {
              reason: "missed",
              eventType: "invite.missed",
              extra: {
                viewerUserId: req.auth.user.id,
                chatId,
                source: "discovery_join",
              },
            })) || chatCall;
          // Only surface a still-live call (a ringing one may have just
          // expired to "missed" above).
          if (fresh.state === "active" || fresh.state === "ringing") {
            activeCall = fresh;
          }
        }
      }
    }
    res.json({
      call: activeCall
        ? mapCallRecord(activeCall, {
            viewerUserId: req.auth.user.id,
            viewerSessionId: req.auth.sessionPublicId,
          })
        : null,
    });
  });

  app.get("/v1/calls/:callId", requireAuth, async (req, res) => {
    const call = await requireCallAccess(req, res, req.params.callId);
    if (!call) {
      return;
    }

    res.json({
      call: mapCallRecord(call, {
        viewerUserId: req.auth.user.id,
        viewerSessionId: req.auth.sessionPublicId,
      }),
    });
  });

  app.post("/v1/calls/:callId/nudge", requireAuth, async (req, res) => {
    const call = await requireCallAccess(req, res, req.params.callId);
    if (!call) {
      return;
    }

    const state = String(call.state || "").trim();
    if (["ended", "missed", "rejected", "cancelled", "failed"].includes(state)) {
      res.status(409).json({message: "Звонок уже завершён"});
      return;
    }

    const callParticipantIds = normalizeParticipantIds(call.participantIds || []);
    const requestedParticipantIds = Array.isArray(req.body?.participantIds)
      ? normalizeParticipantIds(req.body.participantIds)
      : [];
    const recipientIds = (requestedParticipantIds.length > 0
      ? requestedParticipantIds
      : callParticipantIds
    ).filter((participantId) => participantId !== req.auth.user.id);

    if (
      recipientIds.length === 0 ||
      recipientIds.some((participantId) => !callParticipantIds.includes(participantId))
    ) {
      res.status(400).json({message: "Не удалось определить участников дозвона"});
      return;
    }

    const callerName = displayNameForCallParticipant(req.auth.user);
    const isGroupCall = callParticipantIds.length > 2;
    // FIX A2: realtime publish мгновенно онлайн-получателям…
    for (const inviteeId of recipientIds) {
      realtimeHub?.publishToUser(inviteeId, ({sessionPublicId}) => ({
        type: "call.invite.created",
        call: mapCallRecord(call, {
          viewerUserId: inviteeId,
          viewerSessionId: sessionPublicId,
        }),
      }));
    }

    // …запись уведомления синхронно, медленный HTTP-пуш в фоне
    // (awaitPush:false). Тот же паттерн, что и POST /v1/calls.
    for (const inviteeId of recipientIds) {
      await createAndDispatchNotification({
        userId: inviteeId,
        type: "call_invite",
        title: callerName,
        body: isGroupCall
          ? (call.mediaMode === "video" ? "Вас снова зовут в групповой видеозвонок" : "Вас снова зовут в групповой аудиозвонок")
          : (call.mediaMode === "video" ? "Вас снова зовут в видеозвонок" : "Вас снова зовут в аудиозвонок"),
        data: {
          chatId: call.chatId,
          callId: call.id,
          mediaMode: call.mediaMode,
        },
        awaitPush: false,
      });
    }

    logCallEvent("invite.nudged", call, {
      initiatorId: req.auth.user.id,
      participantIds: recipientIds,
    });

    res.json({
      call: mapCallRecord(call, {
        viewerUserId: req.auth.user.id,
        viewerSessionId: req.auth.sessionPublicId,
      }),
    });
  });

  // GP3: add a NEW person to a live call (unlike /nudge, which only re-rings
  // people already on the list). Any current participant may add a chat member
  // who isn't in the call yet; the newcomers get a fresh ring and land in the
  // same room. Grows participantIds only — the last-leaves teardown is
  // unaffected (see store.addCallParticipants).
  app.post("/v1/calls/:callId/add", requireAuth, async (req, res) => {
    const call = await requireCallAccess(req, res, req.params.callId);
    if (!call) {
      return;
    }
    const state = String(call.state || "").trim();
    if (["ended", "missed", "rejected", "cancelled", "failed"].includes(state)) {
      res.status(409).json({message: "Звонок уже завершён"});
      return;
    }

    const chat = await store.findChat(call.chatId);
    if (!chat) {
      res.status(404).json({message: "Чат не найден"});
      return;
    }
    const chatParticipantIds = normalizeParticipantIds(chat.participantIds || []);
    const callParticipantIds = normalizeParticipantIds(call.participantIds || []);
    const requestedIds = Array.isArray(req.body?.participantIds)
      ? normalizeParticipantIds(req.body.participantIds)
      : [];
    // New = requested ∩ chat members − already-in-call.
    const newParticipantIds = requestedIds.filter(
      (participantId) =>
        chatParticipantIds.includes(participantId) &&
        !callParticipantIds.includes(participantId),
    );
    if (newParticipantIds.length === 0) {
      res.status(400).json({message: "Некого добавить в звонок"});
      return;
    }

    for (const participantId of newParticipantIds) {
      if (await store.isUserBlockedBetween(req.auth.user.id, participantId)) {
        res.status(403).json({
          message: "Нельзя добавить в звонок заблокированного пользователя",
        });
        return;
      }
    }

    // Don't pull someone who's busy in another call into this one.
    for (const participantId of newParticipantIds) {
      await reconcileUserBusyCall(participantId);
      const activeOther = await store.findActiveCall({userId: participantId});
      if (activeOther && activeOther.id !== call.id) {
        res.status(409).json({
          message: "Пользователь уже участвует в другом звонке",
        });
        return;
      }
    }

    const result = await store.addCallParticipants({
      callId: call.id,
      userIds: newParticipantIds,
    });
    if (result === null) {
      res.status(404).json({message: "Звонок не найден"});
      return;
    }
    if (result === undefined) {
      res.status(409).json({message: "Звонок уже завершён"});
      return;
    }
    if (result === false) {
      res.status(400).json({message: "Некого добавить в звонок"});
      return;
    }

    const {call: updatedCall, addedUserIds} = result;
    const grownParticipantIds = normalizeParticipantIds(
      updatedCall.participantIds || [],
    );
    // Rooms are created with a generous cap, but keep the ensure idempotent +
    // non-shrinking so the newcomers always fit.
    const roomName = updatedCall.roomName || `call_${updatedCall.id}`;
    try {
      await resolvedLiveKitService.ensureRoom(roomName, {
        maxParticipants: Math.max(
          grownParticipantIds.length,
          GROUP_CALL_MAX_PARTICIPANTS,
        ),
      });
    } catch (_) {
      // best-effort — generous creation cap already covers additions.
    }

    // Ring the newcomers (realtime + background push), same as /nudge + POST.
    const callerName = displayNameForCallParticipant(req.auth.user);
    for (const inviteeId of addedUserIds) {
      realtimeHub?.publishToUser(inviteeId, ({sessionPublicId}) => ({
        type: "call.invite.created",
        call: mapCallRecord(updatedCall, {
          viewerUserId: inviteeId,
          viewerSessionId: sessionPublicId,
        }),
      }));
    }
    for (const inviteeId of addedUserIds) {
      await createAndDispatchNotification({
        userId: inviteeId,
        type: "call_invite",
        title: callerName,
        body: updatedCall.mediaMode === "video"
          ? "Вас зовут в групповой видеозвонок"
          : "Вас зовут в групповой аудиозвонок",
        data: {
          chatId: updatedCall.chatId,
          callId: updatedCall.id,
          mediaMode: updatedCall.mediaMode,
        },
        awaitPush: false,
      });
    }
    // Refresh the roster for everyone already in the call (grown participantIds).
    await publishCallState(updatedCall);

    logCallEvent("participants.added", updatedCall, {
      initiatorId: req.auth.user.id,
      addedUserIds,
    });

    res.json({
      call: mapCallRecord(updatedCall, {
        viewerUserId: req.auth.user.id,
        viewerSessionId: req.auth.sessionPublicId,
      }),
    });
  });

  app.post("/v1/calls/:callId/accept", requireAuth, async (req, res) => {
    if (!resolvedLiveKitService.isConfigured) {
      res.status(503).json({message: "Звонки пока не настроены на сервере"});
      return;
    }

    const call = await requireCallAccess(req, res, req.params.callId);
    if (!call) {
      return;
    }
    if (call.initiatorId === req.auth.user.id) {
      res.status(403).json({message: "Только приглашенный участник может принять звонок"});
      return;
    }
    if (call.state === "active") {
      // Late-join: the call is already running — mint THIS device's session
      // and merge it in (instead of the old tokenless early-return that left
      // every late participant with session:null).
      await joinActiveCall(req, res, call);
      return;
    }
    if (call.state !== "ringing") {
      res.status(409).json({message: "Звонок уже недоступен для принятия"});
      return;
    }

    const roomName = call.roomName || `call_${call.id}`;
    const callParticipantIds = normalizeParticipantIds(call.participantIds || []);
    const accepterSessionId = req.auth.sessionPublicId;
    const ownerSessionByUserId = {
      [call.initiatorId]: String(call.originatedBySessionId || "").trim(),
      [req.auth.user.id]: accepterSessionId,
    };
    try {
      await resolvedLiveKitService.ensureRoom(roomName, {
        maxParticipants: Math.max(
          callParticipantIds.length,
          GROUP_CALL_MAX_PARTICIPANTS,
        ),
      });
      const sessionByUserId = await createCallSessionsForParticipants({
        call,
        roomName,
        participantIds: callParticipantIds,
        ownerSessionByUserId,
      });
      const acceptedCall = await store.acceptCall({
        callId: call.id,
        userId: req.auth.user.id,
        roomName,
        sessionByUserId,
        acceptedBySessionId: accepterSessionId,
      });
      if (!acceptedCall) {
        res.status(409).json({message: "Не удалось принять звонок"});
        return;
      }
      clearCallInviteTimeout(acceptedCall.id);

      await publishCallState(acceptedCall);

      logCallEvent("accept.succeeded", acceptedCall, {
        viewerUserId: req.auth.user.id,
      });

      res.json({
        call: mapCallRecord(acceptedCall, {
          viewerUserId: req.auth.user.id,
          viewerSessionId: req.auth.sessionPublicId,
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
      logCallEvent("accept.failed", failedCall || call, {
        viewerUserId: req.auth.user.id,
        error: String(error?.message || error || "room_prepare_failed"),
      });
      res.status(502).json({message: "Не удалось подготовить комнату звонка"});
    }
  });

  // Group late-join: any CHAT member can "залететь" into a live call. Unlike
  // /accept (invited-recipient only), /join is chat-membership-gated
  // (requireCallJoinAccess) and works for any participant — a pre-invited
  // member, a non-invited chat member, or the initiator joining from another
  // device. joinActiveCall puts a non-invited joiner on the roster first.
  app.post("/v1/calls/:callId/join", requireAuth, async (req, res) => {
    if (!resolvedLiveKitService.isConfigured) {
      res.status(503).json({message: "Звонки пока не настроены на сервере"});
      return;
    }

    const call = await requireCallJoinAccess(req, res, req.params.callId);
    if (!call) {
      return;
    }
    // Joinable while the call is still live (ringing or active); the first
    // joiner flips ringing -> active inside addCallParticipantSession.
    if (call.state !== "ringing" && call.state !== "active") {
      res.status(409).json({message: "Звонок уже недоступен"});
      return;
    }

    await joinActiveCall(req, res, call);
  });

  app.post("/v1/calls/:callId/reject", requireAuth, async (req, res) => {
    const call = await requireCallAccess(req, res, req.params.callId);
    if (!call) {
      return;
    }
    const rejectedCall = await store.rejectCall({
      callId: call.id,
      userId: req.auth.user.id,
      sessionId: req.auth.sessionPublicId,
    });
    if (rejectedCall === null) {
      res.status(404).json({message: "Звонок не найден"});
      return;
    }
    if (rejectedCall === false) {
      res.status(403).json({message: "Только получатель может отклонить звонок"});
      return;
    }
    if (rejectedCall === undefined) {
      res.status(409).json({message: "Звонок уже неактуален"});
      return;
    }
    if (rejectedCall.state === "rejected") {
      clearCallInviteTimeout(rejectedCall.id);
      if (
        resolvedLiveKitService.isConfigured &&
        typeof resolvedLiveKitService.deleteRoom === "function"
      ) {
        resolvedLiveKitService
          .deleteRoom(rejectedCall.roomName || `call_${rejectedCall.id}`)
          .catch(() => {});
      }
    }
    await publishCallState(rejectedCall);
    logCallEvent("reject.completed", rejectedCall, {
      viewerUserId: req.auth.user.id,
    });
    res.json({
      call: mapCallRecord(rejectedCall, {
        viewerUserId: req.auth.user.id,
        viewerSessionId: req.auth.sessionPublicId,
      }),
    });
  });

  app.post("/v1/calls/:callId/cancel", requireAuth, async (req, res) => {
    const call = await requireCallAccess(req, res, req.params.callId);
    if (!call) {
      return;
    }
    const cancelledCall = await store.cancelCall({
      callId: call.id,
      userId: req.auth.user.id,
    });
    if (cancelledCall === null) {
      res.status(404).json({message: "Звонок не найден"});
      return;
    }
    if (cancelledCall === false) {
      res.status(403).json({message: "Только инициатор может отменить звонок"});
      return;
    }
    if (cancelledCall === undefined) {
      res.status(409).json({message: "Звонок уже неактуален"});
      return;
    }
    clearCallInviteTimeout(cancelledCall.id);
    if (
      resolvedLiveKitService.isConfigured &&
      typeof resolvedLiveKitService.deleteRoom === "function"
    ) {
      resolvedLiveKitService
        .deleteRoom(cancelledCall.roomName || `call_${cancelledCall.id}`)
        .catch(() => {});
    }
    await publishCallState(cancelledCall);
    logCallEvent("cancel.completed", cancelledCall, {
      viewerUserId: req.auth.user.id,
    });
    res.json({
      call: mapCallRecord(cancelledCall, {
        viewerUserId: req.auth.user.id,
        viewerSessionId: req.auth.sessionPublicId,
      }),
    });
  });

  app.post("/v1/calls/:callId/hangup", requireAuth, async (req, res) => {
    const call = await requireCallAccess(req, res, req.params.callId);
    if (!call) {
      return;
    }
    const endedCall = await store.hangupCall({
      callId: call.id,
      userId: req.auth.user.id,
      sessionId: req.auth.sessionPublicId,
    });
    if (endedCall === null) {
      res.status(404).json({message: "Звонок не найден"});
      return;
    }
    if (endedCall === false) {
      res.status(403).json({message: "Доступ к звонку запрещён"});
      return;
    }
    if (endedCall === undefined) {
      res.status(409).json({message: "Звонок уже завершён"});
      return;
    }
    const callRoomName = endedCall.roomName || `call_${endedCall.id}`;
    if (endedCall.state === "ended") {
      clearCallInviteTimeout(endedCall.id);
      if (
        resolvedLiveKitService.isConfigured &&
        typeof resolvedLiveKitService.deleteRoom === "function"
      ) {
        resolvedLiveKitService.deleteRoom(callRoomName).catch(() => {});
      }
    } else if (
      resolvedLiveKitService.isConfigured &&
      typeof resolvedLiveKitService.removeParticipant === "function"
    ) {
      const leavingIdentity =
        call.sessionByUserId?.[req.auth.user.id]?.participantIdentity ||
        buildCallParticipantIdentity(req.auth.user.id, req.auth.sessionPublicId);
      resolvedLiveKitService
        .removeParticipant(callRoomName, leavingIdentity)
        .catch(() => {});
    }
    await publishCallState(endedCall);
    logCallEvent("hangup.completed", endedCall, {
      viewerUserId: req.auth.user.id,
    });
    res.json({
      call: mapCallRecord(endedCall, {
        viewerUserId: req.auth.user.id,
        viewerSessionId: req.auth.sessionPublicId,
      }),
    });
  });
}

module.exports = {
  registerLiveKitWebhookRoute,
  registerCallRoutes,
};
