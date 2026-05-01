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
    emergencyChatPreviewResponseCap = 3,
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

  async function publishChatPayload(chatId, payload) {
    if (typeof realtimeHub?.publishToChat === "function") {
      await realtimeHub.publishToChat(chatId, payload);
      return;
    }

    const chat = await store.findChat(chatId);
    for (const participantId of chat?.participantIds || []) {
      realtimeHub?.publishToUser(participantId, payload);
    }
  }

  async function publishChatUpdated(chatId, fallbackChat = null) {
    const resolved = await resolveMappedChat(chatId, fallbackChat);
    if (!resolved) {
      return null;
    }

    await publishChatPayload(resolved.chat.id, {
      type: "chat.updated",
      chatId: resolved.chat.id,
      chat: resolved.mappedChat,
    });
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
    const participantIds = Array.isArray(req.body?.participantIds)
      ? req.body.participantIds
      : [];
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
    const chat = await requireChatAccess(req, res, req.params.chatId);
    if (!chat) {
      return;
    }
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

    const text = String(req.body?.text || "").trim();
    const attachments = Array.isArray(req.body?.attachments)
      ? req.body.attachments
      : [];
    const mediaUrls = Array.isArray(req.body?.mediaUrls) ? req.body.mediaUrls : [];
    const imageUrl = req.body?.imageUrl;
    const clientMessageId = String(req.body?.clientMessageId || "").trim() || null;
    const expiresInSeconds = Number(req.body?.expiresInSeconds || 0);
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
    if (!isDeduplicated) {
      for (const recipientId of recipientIds) {
        const firstAttachment = Array.isArray(mappedMessage.attachments)
          ? mappedMessage.attachments.find((attachment) =>
              String(attachment?.url || "").trim(),
            )
          : null;
        await createAndDispatchNotification({
          userId: recipientId,
          type: "chat_message",
          title:
            chat.type === "group" || chat.type === "branch"
              ? chat.title || message.senderName || "Групповой чат"
              : message.senderName || "Новое сообщение",
          body:
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
                        : "Новое сообщение"),
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

      const resolved = await publishChatUpdated(message.chatId, chat);
      await publishChatPayload(message.chatId, {
        type: "chat.message.created",
        chatId: message.chatId,
        chat: resolved?.mappedChat || mapChatRecord(chat),
        message: mappedMessage,
      });
      await publishUnreadChanged(resolved?.chat || chat);
    }

    res.status(isDeduplicated ? 200 : 201).json({message: mappedMessage});
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
    res.json({ok: true});
  });
}

module.exports = {
  registerChatRoutes,
};
