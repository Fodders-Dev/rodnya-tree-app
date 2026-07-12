const {
  enforceTextLimit,
  enforceNonNegativeInt,
  enforceArrayCap,
} = require("../input-guards");

function registerChatRoutes(
  app,
  {
    store,
    requireAuth,
    requireTreeAccess,
    requireChatAccess,
    createAndDispatchNotification,
    mapChatPreview,
    mapChatRecord,
    mapChatMessage,
    mapChatParticipant,
    mapChatBranchRoot,
    realtimeHub,
    emergencyChatPreviewResponseCap = 200,
  },
) {
  function normalizeMessagePageLimit(query) {
    const hasCursor =
      query.limit != null || query.before != null || query.after != null;
    const fallbackLimit = hasCursor ? 50 : 100;
    const requestedLimit =
      Number.parseInt(String(query.limit || fallbackLimit), 10) || fallbackLimit;
    return Math.min(Math.max(1, requestedLimit), 200);
  }

  function normalizeMessageCursor(value) {
    const cursor = String(value || "").trim();
    return cursor || null;
  }

  async function resolveMappedChat(chatId, fallbackChat = null) {
    const chat = await store.findChat(chatId);
    const resolvedChat = chat || fallbackChat;
    return resolvedChat
      ? {
          chat: resolvedChat,
          mappedChat: mapChatRecord(resolvedChat),
        }
      : null;
  }

  // SPEED-3: `chat` — уже загруженная запись (например, из resolveMappedChat)
  // — избавляет publishToChat от повторного whole-doc чтения.
  async function publishChatPayload(chatId, payload, chat = null) {
    if (typeof realtimeHub?.publishToChat === "function") {
      await realtimeHub.publishToChat(chatId, payload, {chat});
      return;
    }

    const resolvedChat = chat || (await store.findChat(chatId));
    for (const participantId of resolvedChat?.participantIds || []) {
      realtimeHub?.publishToUser(participantId, payload);
    }
  }

  async function publishChatUpdated(chatId, fallbackChat = null) {
    const resolved = await resolveMappedChat(chatId, fallbackChat);
    if (!resolved) {
      return null;
    }

    await publishChatPayload(
      resolved.chat.id,
      {
        type: "chat.updated",
        chatId: resolved.chat.id,
        chat: resolved.mappedChat,
      },
      resolved.chat,
    );
    return resolved;
  }

  async function publishUnreadChanged(chat) {
    if (!chat || !Array.isArray(chat.participantIds)) {
      return;
    }

    for (const participantId of chat.participantIds) {
      if (!participantId) {
        continue;
      }
      const totalUnread = typeof store.countUnreadChatMessages === "function"
        ? await store.countUnreadChatMessages(participantId)
        : null;
      realtimeHub?.publishToUser(participantId, {
        type: "chat.unread.changed",
        chatId: chat.id,
        totalUnread,
      });
    }
  }

  function mapChatDraft(draft) {
    if (!draft) {
      return null;
    }
    return {
      chatId: String(draft.chatId || "").trim(),
      text: String(draft.text || ""),
      updatedAt: draft.updatedAt || null,
    };
  }

  function mapChatPin(pin) {
    if (!pin) {
      return null;
    }
    return {
      chatId: String(pin.chatId || "").trim(),
      messageId: String(pin.messageId || "").trim(),
      senderId: String(pin.senderId || "").trim(),
      senderName: String(pin.senderName || "Участник").trim() || "Участник",
      text: String(pin.text || ""),
      attachmentCount: Number(pin.attachmentCount || 0),
      pinnedAt: pin.pinnedAt || null,
      pinnedBy: String(pin.pinnedBy || "").trim() || null,
    };
  }

  function publishDraftUpdated({userId, chatId, draft}) {
    realtimeHub?.publishToUser(userId, {
      type: "chat.draft.updated",
      chatId,
      userId,
      draft: mapChatDraft(draft),
    });
  }

  async function publishPinUpdated({chatId, pin}) {
    await publishChatPayload(chatId, {
      type: "chat.pin.updated",
      chatId,
      pin: mapChatPin(pin),
    });
  }

  app.get("/v1/chats", requireAuth, async (req, res) => {
    const requestedLimit = Math.min(
      Math.max(1, Number.parseInt(String(req.query.limit || "100"), 10) || 100),
      200,
    );
    const limit = Math.min(requestedLimit, emergencyChatPreviewResponseCap);
    const previews = await store.listChatPreviews(req.auth.user.id);
    res.json({
      chats: previews.slice(0, limit).map(mapChatPreview),
      hasMore: previews.length > limit,
      requestedLimit,
      appliedLimit: limit,
    });
  });

  app.get("/v1/chats/unread-count", requireAuth, async (req, res) => {
    const totalUnread = typeof store.countUnreadChatMessages === "function"
      ? await store.countUnreadChatMessages(req.auth.user.id)
      : (await store.listChatPreviews(req.auth.user.id)).reduce((sum, preview) => {
        return sum + Number(preview.unreadCount || 0);
      }, 0);

    res.json({
      totalUnread,
    });
  });

  app.get("/v1/chats/search", requireAuth, async (req, res) => {
    const query = String(req.query.q || req.query.query || "").trim();
    if (!query) {
      res.json({results: []});
      return;
    }

    const requestedLimit =
      Number.parseInt(String(req.query.limit || "50"), 10) || 50;
    const results = typeof store.searchChatMessages === "function"
      ? await store.searchChatMessages({
          userId: req.auth.user.id,
          query,
          chatId: req.query.chatId,
          limit: requestedLimit,
        })
      : [];
    res.json({results});
  });

  app.get("/v1/chats/drafts", requireAuth, async (req, res) => {
    const drafts = typeof store.listChatDrafts === "function"
      ? await store.listChatDrafts(req.auth.user.id)
      : [];
    res.json({drafts: drafts.map(mapChatDraft).filter(Boolean)});
  });

  app.post("/v1/chats/direct", requireAuth, async (req, res) => {
    const otherUserId = String(req.body?.otherUserId || "").trim();
    if (!otherUserId) {
      res.status(400).json({message: "Нужен otherUserId"});
      return;
    }

    const otherUser = await store.findUserById(otherUserId);
    if (!otherUser) {
      res.status(404).json({message: "Собеседник не найден"});
      return;
    }

    const isBlocked = await store.isUserBlockedBetween(
      req.auth.user.id,
      otherUserId,
    );
    if (isBlocked) {
      res.status(403).json({
        message: "Личный чат недоступен: один из пользователей заблокирован",
      });
      return;
    }

    const chat = await store.ensureDirectChat(req.auth.user.id, otherUserId);
    if (chat === null) {
      res.status(400).json({message: "Не удалось создать личный чат"});
      return;
    }
    if (chat === undefined) {
      res.status(404).json({message: "Один из участников не найден"});
      return;
    }

    res.json({
      chatId: chat.id,
      chat: mapChatRecord(chat),
    });
  });

  app.post("/v1/chats/groups", requireAuth, async (req, res) => {
    // Cap the participants list — without this an attacker could
    // create a 100 k-member group, force the realtime hub to publish
    // chat.created to every one of them, and DoS the broadcast layer.
    const participantsGuard = enforceArrayCap(req.body?.participantIds, {
      max: 256, // matches Telegram's old "supergroup" boundary
      itemValidator: (raw) =>
          enforceTextLimit(raw, {
            max: 64,
            allowMultiline: false,
            fieldName: "participantId",
          }),
      fieldName: "participantIds",
    });
    if (!participantsGuard.ok) {
      res
          .status(participantsGuard.status)
          .json({message: participantsGuard.message});
      return;
    }
    const participantIds = participantsGuard.value;

    if (req.body?.title != null) {
      const titleGuard = enforceTextLimit(req.body?.title, {
        max: 120,
        allowEmpty: true,
        allowMultiline: false,
        fieldName: "title",
      });
      if (!titleGuard.ok) {
        res.status(titleGuard.status).json({message: titleGuard.message});
        return;
      }
    }
    const title = req.body?.title;
    const treeId = req.body?.treeId;

    const chat = await store.createGroupChat({
      title,
      participantIds,
      createdBy: req.auth.user.id,
      treeId,
    });
    if (chat === false) {
      res.status(400).json({
        message: "Для группового чата нужно выбрать минимум двух участников",
      });
      return;
    }
    if (chat === null) {
      res.status(404).json({message: "Один или несколько участников не найдены"});
      return;
    }

    const mappedChat = mapChatRecord(chat);
    for (const participantId of chat.participantIds) {
      realtimeHub?.publishToUser(participantId, {
        type: "chat.created",
        chatId: chat.id,
        chat: mappedChat,
      });
    }

    res.status(201).json({
      chatId: chat.id,
      chat: mappedChat,
    });
  });

  app.post("/v1/chats/branches", requireAuth, async (req, res) => {
    const treeId = String(req.body?.treeId || "").trim();
    const branchRootPersonIds = Array.isArray(req.body?.branchRootPersonIds)
      ? req.body.branchRootPersonIds
      : [];
    const title = req.body?.title;

    if (!treeId) {
      res.status(400).json({message: "Нужен treeId"});
      return;
    }

    const tree = await requireTreeAccess(req, res, treeId);
    if (!tree) {
      return;
    }

    const chat = await store.createBranchChat({
      treeId: tree.id,
      branchRootPersonIds,
      createdBy: req.auth.user.id,
      title,
    });
    if (chat === false) {
      res.status(400).json({
        message: "В этой ветке пока нет других участников с аккаунтами",
      });
      return;
    }
    if (chat === null) {
      res.status(404).json({message: "Ветка не найдена в выбранном дереве"});
      return;
    }

    const mappedChat = mapChatRecord(chat);
    for (const participantId of chat.participantIds) {
      realtimeHub?.publishToUser(participantId, {
        type: "chat.created",
        chatId: chat.id,
        chat: mappedChat,
      });
    }

    res.status(201).json({
      chatId: chat.id,
      chat: mappedChat,
    });
  });

  app.get("/v1/chats/:chatId", requireAuth, async (req, res) => {
    const chat = await requireChatAccess(req, res, req.params.chatId);
    if (!chat) {
      return;
    }

    const resolvedChatId = chat.id;
    const details = await store.getChatDetails(resolvedChatId);
    if (!details) {
      res.status(404).json({message: "Чат не найден"});
      return;
    }

    res.json({
      chat: mapChatRecord(details.chat),
      participants: details.participants.map(mapChatParticipant),
      branchRoots: details.branchRoots.map(mapChatBranchRoot),
    });
  });

  app.patch("/v1/chats/:chatId", requireAuth, async (req, res) => {
    const chat = await requireChatAccess(req, res, req.params.chatId);
    if (!chat) {
      return;
    }
    const resolvedChatId = chat.id;

    const updatedChat = await store.updateGroupChat(resolvedChatId, {
      title: req.body?.title,
      photoUrl: req.body?.photoUrl,
    });
    if (updatedChat === false) {
      res.status(400).json({message: "Менять можно только обычный групповой чат"});
      return;
    }
    if (updatedChat === undefined) {
      res.status(400).json({message: "Нужно указать название чата"});
      return;
    }
    if (!updatedChat) {
      res.status(404).json({message: "Чат не найден"});
      return;
    }

    const details = await store.getChatDetails(updatedChat.id);
    if (!details) {
      res.status(404).json({message: "Чат не найден"});
      return;
    }
    const mappedChat = mapChatRecord(details.chat);
    for (const participantId of details.chat.participantIds || []) {
      realtimeHub?.publishToUser(participantId, {
        type: "chat.updated",
        chatId: details.chat.id,
        chat: mappedChat,
      });
    }

    res.json({
      chat: mappedChat,
      participants: details.participants.map(mapChatParticipant),
      branchRoots: details.branchRoots.map(mapChatBranchRoot),
    });
  });

  app.get("/v1/chats/:chatId/draft", requireAuth, async (req, res) => {
    const chat = await requireChatAccess(req, res, req.params.chatId);
    if (!chat) {
      return;
    }
    const draft = typeof store.getChatDraft === "function"
      ? await store.getChatDraft({
          userId: req.auth.user.id,
          chatId: chat.id,
        })
      : null;
    res.json({draft: mapChatDraft(draft)});
  });

  app.put("/v1/chats/:chatId/draft", requireAuth, async (req, res) => {
    const chat = await requireChatAccess(req, res, req.params.chatId);
    if (!chat) {
      return;
    }
    const draft = typeof store.saveChatDraft === "function"
      ? await store.saveChatDraft({
          userId: req.auth.user.id,
          chatId: chat.id,
          text: req.body?.text,
        })
      : null;
    publishDraftUpdated({
      userId: req.auth.user.id,
      chatId: chat.id,
      draft,
    });
    res.json({draft: mapChatDraft(draft)});
  });

  app.delete("/v1/chats/:chatId/draft", requireAuth, async (req, res) => {
    const chat = await requireChatAccess(req, res, req.params.chatId);
    if (!chat) {
      return;
    }
    if (typeof store.clearChatDraft === "function") {
      await store.clearChatDraft({
        userId: req.auth.user.id,
        chatId: chat.id,
      });
    }
    publishDraftUpdated({
      userId: req.auth.user.id,
      chatId: chat.id,
      draft: null,
    });
    res.json({draft: null});
  });

  app.get("/v1/chats/:chatId/pin", requireAuth, async (req, res) => {
    const chat = await requireChatAccess(req, res, req.params.chatId);
    if (!chat) {
      return;
    }
    const pin = typeof store.getChatPinnedMessage === "function"
      ? await store.getChatPinnedMessage({
          userId: req.auth.user.id,
          chatId: chat.id,
        })
      : null;
    res.json({pin: mapChatPin(pin)});
  });

  app.post(
    "/v1/chats/:chatId/messages/:messageId/pin",
    requireAuth,
    async (req, res) => {
      const chat = await requireChatAccess(req, res, req.params.chatId);
      if (!chat) {
        return;
      }
      const pin = typeof store.pinChatMessage === "function"
        ? await store.pinChatMessage({
            userId: req.auth.user.id,
            chatId: chat.id,
            messageId: req.params.messageId,
          })
        : null;
      if (pin === false) {
        res.status(404).json({message: "Чат не найден"});
        return;
      }
      if (!pin) {
        res.status(404).json({message: "Сообщение не найдено"});
        return;
      }
      await publishPinUpdated({chatId: chat.id, pin});
      res.json({pin: mapChatPin(pin)});
    },
  );

  app.delete("/v1/chats/:chatId/pin", requireAuth, async (req, res) => {
    const chat = await requireChatAccess(req, res, req.params.chatId);
    if (!chat) {
      return;
    }
    if (typeof store.clearChatPinnedMessage === "function") {
      const cleared = await store.clearChatPinnedMessage({
        userId: req.auth.user.id,
        chatId: chat.id,
      });
      if (cleared === false) {
        res.status(404).json({message: "Чат не найден"});
        return;
      }
    }
    await publishPinUpdated({chatId: chat.id, pin: null});
    res.json({pin: null});
  });

  app.post("/v1/chats/:chatId/participants", requireAuth, async (req, res) => {
    const chat = await requireChatAccess(req, res, req.params.chatId);
    if (!chat) {
      return;
    }
    const resolvedChatId = chat.id;

    const participantIds = Array.isArray(req.body?.participantIds)
      ? req.body.participantIds
      : [];
    const updatedChat = await store.addGroupParticipants(
      resolvedChatId,
      participantIds,
    );
    if (updatedChat === false) {
      res.status(400).json({message: "Менять можно только обычный групповой чат"});
      return;
    }
    if (updatedChat === undefined) {
      res.status(400).json({message: "Нужны новые участники"});
      return;
    }
    if (!updatedChat) {
      res.status(404).json({message: "Один или несколько участников не найдены"});
      return;
    }

    const details = await store.getChatDetails(updatedChat.id);
    if (!details) {
      res.status(404).json({message: "Чат не найден"});
      return;
    }
    const mappedChat = mapChatRecord(details.chat);
    for (const participantId of details.chat.participantIds || []) {
      realtimeHub?.publishToUser(participantId, {
        type: "chat.updated",
        chatId: details.chat.id,
        chat: mappedChat,
      });
    }

    res.json({
      chat: mappedChat,
      participants: details.participants.map(mapChatParticipant),
      branchRoots: details.branchRoots.map(mapChatBranchRoot),
    });
  });

  app.delete(
    "/v1/chats/:chatId/participants/:participantId",
    requireAuth,
    async (req, res) => {
      const chat = await requireChatAccess(req, res, req.params.chatId);
      if (!chat) {
        return;
      }
      const resolvedChatId = chat.id;

      const updatedChat = await store.removeGroupParticipant(
        resolvedChatId,
        req.params.participantId,
      );
      if (updatedChat === false) {
        res.status(400).json({message: "Менять можно только обычный групповой чат"});
        return;
      }
      if (updatedChat === undefined) {
        res.status(400).json({
          message: "Нельзя удалить этого участника из группового чата",
        });
        return;
      }
      if (!updatedChat) {
        res.status(404).json({message: "Чат не найден"});
        return;
      }

      const details = await store.getChatDetails(updatedChat.id);
      if (!details) {
        res.status(404).json({message: "Чат не найден"});
        return;
      }
      const mappedChat = mapChatRecord(details.chat);
      const affectedParticipantIds = new Set([
        ...((chat.participantIds || []).map((entry) => String(entry || "").trim())),
        ...(details.chat.participantIds || []).map((entry) =>
          String(entry || "").trim(),
        ),
      ]);
      for (const participantId of affectedParticipantIds) {
        if (!participantId) {
          continue;
        }
        realtimeHub?.publishToUser(participantId, {
          type: "chat.updated",
          chatId: details.chat.id,
          chat: mappedChat,
        });
      }

      res.json({
        chat: mappedChat,
        participants: details.participants.map(mapChatParticipant),
        branchRoots: details.branchRoots.map(mapChatBranchRoot),
      });
    },
  );

  // G2: самовыход из группового чата. Участник убирает СЕБЯ — поэтому
  // POST (а не DELETE /participants/:id, который позволяет убрать любого);
  // звонящий берётся из auth, лишний путь-параметр не нужен, и это
  // закрывает дыру «любой может убрать любого». Realtime шлём объединению
  // before+after id, чтобы и ушедший получил chat.updated и убрал чат из
  // списка, и оставшиеся увидели уменьшившийся состав.
  app.post("/v1/chats/:chatId/leave", requireAuth, async (req, res) => {
    const chat = await requireChatAccess(req, res, req.params.chatId);
    if (!chat) {
      return;
    }
    const resolvedChatId = chat.id;

    const updatedChat = await store.leaveGroupChat(
      resolvedChatId,
      req.auth.user.id,
    );
    if (updatedChat === false) {
      res.status(400).json({message: "Покинуть можно только групповой чат"});
      return;
    }
    if (updatedChat === undefined) {
      res.status(400).json({message: "Вы не состоите в этом чате"});
      return;
    }
    if (!updatedChat) {
      res.status(404).json({message: "Чат не найден"});
      return;
    }

    const details = await store.getChatDetails(updatedChat.id);
    if (!details) {
      res.status(404).json({message: "Чат не найден"});
      return;
    }
    const mappedChat = mapChatRecord(details.chat);
    const affectedParticipantIds = new Set([
      ...(chat.participantIds || []).map((entry) => String(entry || "").trim()),
      ...(details.chat.participantIds || []).map((entry) =>
        String(entry || "").trim(),
      ),
    ]);
    for (const participantId of affectedParticipantIds) {
      if (!participantId) {
        continue;
      }
      realtimeHub?.publishToUser(participantId, {
        type: "chat.updated",
        chatId: details.chat.id,
        chat: mappedChat,
      });
    }

    res.json({
      chat: mappedChat,
      participants: details.participants.map(mapChatParticipant),
      branchRoots: details.branchRoots.map(mapChatBranchRoot),
    });
  });

  app.get("/v1/chats/:chatId/messages", requireAuth, async (req, res) => {
    const chat = await requireChatAccess(req, res, req.params.chatId);
    if (!chat) {
      return;
    }
    const resolvedChatId = chat.id;

    const beforeId = normalizeMessageCursor(req.query.before);
    const afterId = normalizeMessageCursor(req.query.after);
    if (beforeId && afterId) {
      res.status(400).json({message: "Нельзя передавать before и after вместе"});
      return;
    }

    const limit = normalizeMessagePageLimit(req.query);
    const page = await store.listChatMessages(resolvedChatId, {
      limit: limit + 1,
      beforeId,
      afterId,
    });
    const messages = page.slice(0, limit);
    res.json({
      chat: mapChatRecord(chat),
      messages: messages.map(mapChatMessage),
      hasMore: page.length > limit,
    });
  });

  app.post("/v1/chats/:chatId/messages", requireAuth, async (req, res) => {
    // SPEED-3: пофазный тайминг отправки — grep-абельная строка
    // «[send-timing] …» отвечает на вопрос «где миллисекунды» (доступ /
    // персист / фан-аут) до и после оптимизаций.
    const t0 = Date.now();
    const chat = await requireChatAccess(req, res, req.params.chatId);
    if (!chat) {
      return;
    }
    const tAccess = Date.now();
    const resolvedChatId = chat.id;

    if (chat.type === "direct") {
      const otherParticipantId = (Array.isArray(chat.participantIds)
        ? chat.participantIds
        : []
      ).find((participantId) => participantId !== req.auth.user.id);
      if (otherParticipantId) {
        const isBlocked = await store.isUserBlockedBetween(
          req.auth.user.id,
          otherParticipantId,
        );
        if (isBlocked) {
          res.status(403).json({
            message:
              "Отправка сообщений недоступна: один из пользователей заблокирован",
          });
          return;
        }
      }
    }

    // ── Hard caps on every user-input field ────────────────────────
    // The 50 MB express.json body cap is a defense-in-depth ceiling,
    // not a validation policy. Each field below has its own bound so
    // a single message can't bloat the DB, break realtime broadcast,
    // or crash clients trying to render it.
    const textGuard = enforceTextLimit(req.body?.text, {
      max: 16_384, // 16 KB — fits a long-form note, way under any UI breakage threshold
      allowEmpty: true,
      fieldName: "text",
    });
    if (!textGuard.ok) {
      res.status(textGuard.status).json({message: textGuard.message});
      return;
    }
    const text = textGuard.value;

    const attachmentsGuard = enforceArrayCap(req.body?.attachments, {
      max: 20, // matches client-side picker cap
      itemValidator: (item) => {
        if (item == null || typeof item !== "object") {
          return {ok: false, message: "должно быть объектом"};
        }
        return {ok: true, value: item};
      },
      fieldName: "attachments",
    });
    if (!attachmentsGuard.ok) {
      res.status(attachmentsGuard.status).json({message: attachmentsGuard.message});
      return;
    }
    const attachments = attachmentsGuard.value;

    const mediaUrlsGuard = enforceArrayCap(req.body?.mediaUrls, {
      max: 20,
      itemValidator: (raw) =>
          enforceTextLimit(raw, {
            max: 2048,
            fieldName: "mediaUrl",
          }),
      fieldName: "mediaUrls",
    });
    if (!mediaUrlsGuard.ok) {
      res.status(mediaUrlsGuard.status).json({message: mediaUrlsGuard.message});
      return;
    }
    const mediaUrls = mediaUrlsGuard.value;

    const imageUrl = req.body?.imageUrl;
    if (imageUrl != null && imageUrl !== "") {
      const imageGuard = enforceTextLimit(imageUrl, {
        max: 2048,
        fieldName: "imageUrl",
      });
      if (!imageGuard.ok) {
        res.status(imageGuard.status).json({message: imageGuard.message});
        return;
      }
    }

    const clientIdGuard = enforceTextLimit(req.body?.clientMessageId, {
      max: 128,
      allowEmpty: true,
      allowMultiline: false,
      fieldName: "clientMessageId",
    });
    if (!clientIdGuard.ok) {
      res.status(clientIdGuard.status).json({message: clientIdGuard.message});
      return;
    }
    const clientMessageId = clientIdGuard.value || null;

    // expiresInSeconds: cap at 90 days. Anything longer is either
    // attacker noise (Number.MAX_SAFE_INTEGER → year 285 000 stamp)
    // or a product mistake — disappearing-message UX shouldn't go
    // beyond a quarter.
    const expiresGuard = enforceNonNegativeInt(req.body?.expiresInSeconds || 0, {
      max: 90 * 24 * 60 * 60, // 90 days in seconds
      fieldName: "expiresInSeconds",
    });
    if (!expiresGuard.ok) {
      res.status(expiresGuard.status).json({message: expiresGuard.message});
      return;
    }
    const expiresInSeconds = expiresGuard.value;
    const expiresAt = expiresInSeconds > 0
      ? new Date(Date.now() + expiresInSeconds * 1000).toISOString()
      : req.body?.expiresAt;

    if (
      !text &&
      attachments.length === 0 &&
      mediaUrls.length === 0 &&
      !String(imageUrl || "").trim()
    ) {
      res.status(400).json({message: "Нужен text или вложение"});
      return;
    }

    const message = await store.addChatMessage({
      chatId: resolvedChatId,
      senderId: req.auth.user.id,
      text,
      attachments,
      mediaUrls,
      imageUrl,
      clientMessageId,
      expiresAt,
      replyTo: req.body?.replyTo,
    });

    if (message === false) {
      res.status(400).json({message: "Сообщение не должно быть пустым"});
      return;
    }
    if (!message) {
      res.status(400).json({message: "Не удалось отправить сообщение"});
      return;
    }

    const mappedMessage = mapChatMessage(message);
    const isDeduplicated = message._deduplicated === true;
    const recipientIds = (chat.participantIds || []).filter(
      (participantId) => participantId !== req.auth.user.id,
    );

    // SPEED-2: отправитель получает ack СРАЗУ после персиста сообщения —
    // ровно как Telegram/Slack (ack → фан-аут асинхронно). Всё, что ниже
    // (черновик, WS-публикации, unread, нотификации), не влияет на
    // латентность «галочки» и не растёт с числом получателей. Ошибки
    // фан-аута не могут уронить ответ — он уже отправлен.
    const tPersist = Date.now();
    res.status(isDeduplicated ? 200 : 201).json({message: mappedMessage});
    console.log(
      `[send-timing] chat=${message.chatId} access=${tAccess - t0}ms ` +
        `persist=${tPersist - tAccess}ms ack=${tPersist - t0}ms ` +
        `dedup=${isDeduplicated}`,
    );

    (async () => {
      if (typeof store.clearChatDraft === "function") {
        try {
          await store.clearChatDraft({
            userId: req.auth.user.id,
            chatId: message.chatId,
          });
          publishDraftUpdated({
            userId: req.auth.user.id,
            chatId: message.chatId,
            draft: null,
          });
        } catch (error) {
          console.warn(
            "[backend] clearChatDraft after message send failed",
            error?.message || error,
          );
        }
      }
      if (isDeduplicated) {
        return;
      }
      // Порядок важен: сначала шлём WS-нотификации, потом пуш.
      // Раньше было наоборот — пуш улетал первым через VKPNS
      // (мгновенная фоновая доставка), а WS-message прохож-
      // дил через Express + Node event loop ещё несколько
      // сотен миллисекунд. На клиенте получалось «buzz в
      // шторке раньше чем bubble в чате» — пользователь
      // жалуется именно на это.
      const resolved = await publishChatUpdated(message.chatId, chat);
      await publishChatPayload(
        message.chatId,
        {
          type: "chat.message.created",
          chatId: message.chatId,
          chat: resolved?.mappedChat || mapChatRecord(chat),
          message: mappedMessage,
        },
        resolved?.chat || chat,
      );
      await publishUnreadChanged(resolved?.chat || chat);

      const firstAttachment = Array.isArray(mappedMessage.attachments)
        ? mappedMessage.attachments.find((attachment) =>
            String(attachment?.url || "").trim(),
          )
        : null;
      const resolvedNotificationBody =
        message.text ||
        (firstAttachment?.presentation === "video_note"
          ? "Видеосообщение"
          : firstAttachment?.presentation === "voice_note"
            ? "Голосовое"
            : firstAttachment?.type === "video"
              ? "Видео"
              : firstAttachment?.type === "audio"
                ? "Голосовое"
                : firstAttachment?.type === "file"
                  ? "Файл"
                  : Array.isArray(message.mediaUrls) &&
                      message.mediaUrls.length > 0
                    ? "Фото"
                    : "Новое сообщение");
      const resolvedNotificationTitle =
        chat.type === "group" || chat.type === "branch"
          ? chat.title || message.senderName || "Групповой чат"
          : message.senderName || "Новое сообщение";

      for (const recipientId of recipientIds) {
        // Если получатель прямо сейчас открыт в этом же чате на любом своём
        // устройстве — пуш не нужен, он уже видел сообщение через WS-доставку
        // выше.
        if (realtimeHub?.isUserActiveInChat?.(recipientId, message.chatId)) {
          continue;
        }
        // FIX (латентность): медленный VKPNS-HTTP (AbortSignal.timeout 8с на
        // мёртвый токен) уходит в фон через awaitPush:false. Запись
        // notification-record — здесь же, в фоне: лента/непрочитанные
        // получателя обновляются через мгновение после WS-доставки.
        await createAndDispatchNotification({
          userId: recipientId,
          type: "chat_message",
          title: resolvedNotificationTitle,
          body: resolvedNotificationBody,
          awaitPush: false,
          data: {
            chatId: message.chatId,
            chatType: chat.type || "direct",
            chatTitle: chat.title || null,
            senderId: message.senderId,
            senderName: message.senderName,
            messageId: message.id,
            attachments: mappedMessage.attachments,
          },
        });
      }
      console.log(
        `[send-timing] chat=${message.chatId} fanout=${Date.now() - tPersist}ms ` +
          `recipients=${recipientIds.length}`,
      );
    })().catch((error) => {
      console.warn(
        "[backend] message fan-out failed",
        error?.message || error,
      );
    });
  });

  app.post(
    "/v1/chats/:chatId/messages/:messageId/reactions",
    requireAuth,
    async (req, res) => {
      const chat = await requireChatAccess(req, res, req.params.chatId);
      if (!chat) {
        return;
      }
      const resolvedChatId = chat.id;
      const emoji = String(req.body?.emoji || "").trim();
      if (!emoji) {
        res.status(400).json({message: "Нужна реакция"});
        return;
      }

      const result = await store.toggleChatMessageReaction({
        chatId: resolvedChatId,
        messageId: req.params.messageId,
        userId: req.auth.user.id,
        emoji,
      });

      if (result === false) {
        res.status(404).json({message: "Чат не найден"});
        return;
      }
      if (result === null) {
        res.status(404).json({message: "Сообщение не найдено"});
        return;
      }
      if (result === "INVALID_EMOJI") {
        res.status(400).json({message: "Нужна реакция"});
        return;
      }

      await publishChatPayload(result.chatId || resolvedChatId, {
        type: "message.reaction.changed",
        chatId: result.chatId || resolvedChatId,
        messageId: result.messageId,
        reactions: result.reactions,
      });

      res.json({
        messageId: result.messageId,
        reactions: result.reactions,
        added: result.added === true,
      });
    },
  );

  app.patch("/v1/chats/:chatId/messages/:messageId", requireAuth, async (req, res) => {
    const chat = await requireChatAccess(req, res, req.params.chatId);
    if (!chat) {
      return;
    }
    const resolvedChatId = chat.id;

    const message = await store.updateChatMessage({
      chatId: resolvedChatId,
      messageId: req.params.messageId,
      userId: req.auth.user.id,
      text: req.body?.text,
    });

    if (message === false) {
      res.status(404).json({message: "Чат не найден"});
      return;
    }
    if (message === null) {
      res.status(404).json({message: "Сообщение не найдено"});
      return;
    }
    if (message === undefined) {
      res.status(403).json({message: "Можно редактировать только свои сообщения"});
      return;
    }
    if (message === "EMPTY_MESSAGE") {
      res.status(400).json({message: "Сообщение не должно быть пустым"});
      return;
    }

    const mappedMessage = mapChatMessage(message);
    const resolved = await publishChatUpdated(message.chatId, chat);
    await publishChatPayload(message.chatId, {
      type: "chat.message.updated",
      chatId: message.chatId,
      chat: resolved?.mappedChat || mapChatRecord(chat),
      message: mappedMessage,
    });

    res.json({message: mappedMessage});
  });

  app.delete("/v1/chats/:chatId/messages/:messageId", requireAuth, async (req, res) => {
    const chat = await requireChatAccess(req, res, req.params.chatId);
    if (!chat) {
      return;
    }
    const resolvedChatId = chat.id;

    const message = await store.deleteChatMessage({
      chatId: resolvedChatId,
      messageId: req.params.messageId,
      userId: req.auth.user.id,
    });

    if (message === false) {
      res.status(404).json({message: "Чат не найден"});
      return;
    }
    if (message === null) {
      res.status(404).json({message: "Сообщение не найдено"});
      return;
    }
    if (message === undefined) {
      res.status(403).json({message: "Можно удалять только свои сообщения"});
      return;
    }

    const resolved = await publishChatUpdated(message.chatId, chat);
    await publishChatPayload(message.chatId, {
      type: "chat.message.deleted",
      chatId: message.chatId,
      chat: resolved?.mappedChat || mapChatRecord(chat),
      messageId: message.id,
    });
    if (message._clearedPinnedMessage === true) {
      await publishPinUpdated({chatId: message.chatId, pin: null});
    }
    await publishUnreadChanged(resolved?.chat || chat);

    res.json({ok: true, messageId: message.id});
  });

  app.post("/v1/chats/:chatId/read", requireAuth, async (req, res) => {
    const chat = await requireChatAccess(req, res, req.params.chatId);
    if (!chat) {
      return;
    }
    const resolvedChatId = chat.id;

    const readResult = await store.markChatAsRead(resolvedChatId, req.auth.user.id);
    const resolved = await publishChatUpdated(resolvedChatId, chat);
    await publishChatPayload(resolvedChatId, {
      type: "chat.read.updated",
      chatId: resolvedChatId,
      chat: resolved?.mappedChat || mapChatRecord(chat),
      userId: req.auth.user.id,
    });
    const readMessageIds = Array.isArray(readResult?.messageIds)
      ? readResult.messageIds
      : [];
    if (readMessageIds.length > 0) {
      await publishChatPayload(resolvedChatId, {
        type: "message.read",
        chatId: resolvedChatId,
        userId: req.auth.user.id,
        messageIds: readMessageIds,
      });
    }
    await publishUnreadChanged(resolved?.chat || chat);

    // Auto-погашение уведомлений «новое сообщение» по этому чату.
    // Когда юзер открывает chat-screen и сообщения помечаются
    // прочитанными, нет смысла оставлять «новое сообщение от X»
    // в ленте активности — он только что это прочитал. До этого
    // фикса лента забивалась, юзеру приходилось тапать «Прочитать
    // всё».
    if (typeof store.markNotificationsReadByDataKey === "function") {
      try {
        const markedCount = await store.markNotificationsReadByDataKey({
          userId: req.auth.user.id,
          dataKey: "chatId",
          dataValue: resolvedChatId,
          types: ["chat_message", "chat"],
        });
        if (markedCount > 0 && realtimeHub?.publishToUser) {
          // Бамп для bell-badge: клиент попросит свежий
          // unread-count и счётчик обновится сразу, а не на
          // следующем 20-секундном поллинге.
          realtimeHub.publishToUser(req.auth.user.id, {
            type: "notification.bulk-read",
            scope: "chat",
            chatId: resolvedChatId,
            count: markedCount,
          });
        }
      } catch (error) {
        // Лог + продолжаем — основной chat-read-flow выше уже
        // отработал. Вторая попытка случится на следующем
        // открытии чата.
        console.warn(
          "[backend] markNotificationsReadByDataKey failed",
          error?.message || error,
        );
      }
    }

    res.json({ok: true});
  });
}

module.exports = {
  registerChatRoutes,
};
