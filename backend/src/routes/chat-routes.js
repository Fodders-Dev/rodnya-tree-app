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

    const messages = await store.listChatMessages(resolvedChatId);
    res.json({
      chat: mapChatRecord(chat),
      messages: messages.map(mapChatMessage),
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

      for (const participantId of chat.participantIds || []) {
        realtimeHub?.publishToUser(participantId, {
          type: "chat.message.created",
          chatId: message.chatId,
          chat: mapChatRecord(chat),
          message: mappedMessage,
        });
      }
    }

    res.status(isDeduplicated ? 200 : 201).json({message: mappedMessage});
  });

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
    for (const participantId of chat.participantIds || []) {
      realtimeHub?.publishToUser(participantId, {
        type: "chat.message.updated",
        chatId: message.chatId,
        chat: mapChatRecord(chat),
        message: mappedMessage,
      });
    }

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

    for (const participantId of chat.participantIds || []) {
      realtimeHub?.publishToUser(participantId, {
        type: "chat.message.deleted",
        chatId: message.chatId,
        chat: mapChatRecord(chat),
        messageId: message.id,
      });
    }

    res.json({ok: true, messageId: message.id});
  });

  app.post("/v1/chats/:chatId/read", requireAuth, async (req, res) => {
    const chat = await requireChatAccess(req, res, req.params.chatId);
    if (!chat) {
      return;
    }
    const resolvedChatId = chat.id;

    await store.markChatAsRead(resolvedChatId, req.auth.user.id);
    for (const participantId of chat.participantIds || []) {
      realtimeHub?.publishToUser(participantId, {
        type: "chat.read.updated",
        chatId: resolvedChatId,
        chat: mapChatRecord(chat),
        userId: req.auth.user.id,
      });
    }
    res.json({ok: true});
  });
}

module.exports = {
  registerChatRoutes,
};
