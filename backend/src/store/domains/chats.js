const crypto = require("node:crypto");
const {
  describeMessagePreview,
  normalizeMessageAttachments,
  normalizeReplyReference,
} = require("../../chat-utils");
const {
  aggregateMessageReactions,
  attachMessageReactions,
  buildChatSearchSnippet,
  buildTreeGraphSnapshot,
  chatMessageSearchHaystack,
  chooseBranchBlockForPerson,
  compareChatMessagesDescending,
  composeDisplayNameFromProfile,
  createChatDraftRecord,
  createChatPinRecord,
  createChatRecord,
  ensureChatPins,
  ensureMessageReactions,
  isExpiredAt,
  isMessageReadByUser,
  normalizeChatMessageCall,
  normalizeChatSearchQuery,
  normalizeNullableString,
  normalizeOptionalIsoTimestamp,
  normalizeParticipantIds,
  normalizeReactionEmoji,
  nowIso,
  parseDirectParticipantsFromChatId,
  sameNormalizedIds,
} = require("../helpers");

module.exports = {
  _findStoredChat(db, chatId) {
    return db.chats.find((entry) => entry.id === chatId) || null;
  },

  _resolveChat(db, chatId) {
    const normalizedChatId = String(chatId || "").trim();
    const storedChat = this._findStoredChat(db, normalizedChatId);
    if (storedChat) {
      return storedChat;
    }

    const directParticipants = parseDirectParticipantsFromChatId(
      normalizedChatId,
    );
    if (directParticipants.length === 2) {
      const canonicalChatId = directParticipants.join("_");
      const storedCanonicalChat = this._findStoredChat(db, canonicalChatId);
      if (storedCanonicalChat) {
        return storedCanonicalChat;
      }
      const relatedMessages = db.messages
        .filter((entry) => {
          return (
            entry.chatId === normalizedChatId ||
            entry.chatId === canonicalChatId
          );
        })
        .sort((left, right) =>
          String(left.timestamp || "").localeCompare(String(right.timestamp || "")),
        );
      const firstTimestamp = relatedMessages[0]?.timestamp || nowIso();
      const lastTimestamp =
        relatedMessages[relatedMessages.length - 1]?.timestamp || firstTimestamp;
      return {
        id: canonicalChatId,
        type: "direct",
        participantIds: directParticipants,
        title: null,
        createdBy: directParticipants[0],
        treeId: null,
        branchRootPersonIds: [],
        createdAt: firstTimestamp,
        updatedAt: lastTimestamp,
      };
    }

    return null;
  },

  _resolveEquivalentChatIds(chatId, resolvedChat = null) {
    const relatedChatIds = new Set();
    const normalizedChatId = String(chatId || "").trim();
    if (normalizedChatId) {
      relatedChatIds.add(normalizedChatId);
    }

    const directParticipants = parseDirectParticipantsFromChatId(normalizedChatId);
    if (directParticipants.length === 2) {
      relatedChatIds.add(directParticipants.join("_"));
    }

    if (resolvedChat?.id) {
      relatedChatIds.add(String(resolvedChat.id).trim());
    }

    return relatedChatIds;
  },

  async findChat(chatId) {
    const db = await this._read();
    const chat = this._resolveChat(db, chatId);
    return chat ? structuredClone(chat) : null;
  },

  _findChatDraft(db, {userId, chatId}) {
    const normalizedUserId = String(userId || "").trim();
    const normalizedChatId = String(chatId || "").trim();
    if (!normalizedUserId || !normalizedChatId) {
      return null;
    }
    return (
      (Array.isArray(db.chatDrafts) ? db.chatDrafts : []).find((entry) => {
        return entry.userId === normalizedUserId && entry.chatId === normalizedChatId;
      }) || null
    );
  },

  _canAccessChatDraft(chat, userId) {
    return Boolean(
      chat &&
        String(userId || "").trim() &&
        normalizeParticipantIds(chat.participantIds).includes(String(userId).trim()),
    );
  },

  async getChatDraft({userId, chatId}) {
    const db = await this._read();
    const chat = this._resolveChat(db, chatId);
    if (!this._canAccessChatDraft(chat, userId)) {
      return null;
    }
    const draft = this._findChatDraft(db, {userId, chatId: chat.id});
    return draft ? structuredClone(draft) : null;
  },

  async listChatDrafts(userId) {
    const db = await this._read();
    const normalizedUserId = String(userId || "").trim();
    if (!normalizedUserId) {
      return [];
    }
    return (Array.isArray(db.chatDrafts) ? db.chatDrafts : [])
      .filter((draft) => {
        if (draft.userId !== normalizedUserId || !String(draft.text || "").trim()) {
          return false;
        }
        const chat = this._resolveChat(db, draft.chatId);
        return this._canAccessChatDraft(chat, normalizedUserId);
      })
      .sort((left, right) =>
        String(right.updatedAt || "").localeCompare(String(left.updatedAt || "")),
      )
      .map((draft) => structuredClone(draft));
  },

  async saveChatDraft({userId, chatId, text}) {
    return this._mutate((db, skip) => {
      const chat = this._resolveChat(db, chatId);
      if (!this._canAccessChatDraft(chat, userId)) {
        return skip(null);
      }

      db.chatDrafts = Array.isArray(db.chatDrafts) ? db.chatDrafts : [];
      const normalizedUserId = String(userId || "").trim();
      const normalizedText = String(text || "");
      const existingIndex = db.chatDrafts.findIndex((entry) => {
        return entry.userId === normalizedUserId && entry.chatId === chat.id;
      });

      if (!normalizedText.trim()) {
        if (existingIndex >= 0) {
          db.chatDrafts.splice(existingIndex, 1);
          return null;
        }
        return skip(null);
      }

      const draft = createChatDraftRecord({
        userId: normalizedUserId,
        chatId: chat.id,
        text: normalizedText,
      });
      if (existingIndex >= 0) {
        db.chatDrafts[existingIndex] = draft;
      } else {
        db.chatDrafts.push(draft);
      }
      return structuredClone(draft);
    });
  },

  async clearChatDraft({userId, chatId}) {
    return this.saveChatDraft({userId, chatId, text: ""});
  },

  _canAccessChatPin(chat, userId) {
    return Boolean(
      chat &&
        String(userId || "").trim() &&
        normalizeParticipantIds(chat.participantIds).includes(String(userId).trim()),
    );
  },

  _findChatPin(db, chat) {
    if (!chat) {
      return null;
    }
    const relatedChatIds = this._resolveEquivalentChatIds(chat.id, chat);
    return (
      ensureChatPins(db).find((entry) => {
        return relatedChatIds.has(String(entry?.chatId || "").trim());
      }) || null
    );
  },

  _findMessageForChatPin(db, {chat, messageId}) {
    if (!chat) {
      return null;
    }
    const normalizedMessageId = String(messageId || "").trim();
    if (!normalizedMessageId) {
      return null;
    }
    const relatedChatIds = this._resolveEquivalentChatIds(chat.id, chat);
    return (
      db.messages.find((entry) => {
        return (
          String(entry?.id || "").trim() === normalizedMessageId &&
          relatedChatIds.has(String(entry?.chatId || "").trim())
        );
      }) || null
    );
  },

  async getChatPinnedMessage({userId, chatId}) {
    // Чтение с opportunistic-записями (TTL-purge + чистка осиротевшего
    // пина) — через _mutate, иначе его stale whole-doc запись может затереть
    // конкурентную мутацию (SPEED-2 сделал фан-аут конкурентным). skip()
    // держит обычный путь (ничего не протухло) чистым чтением без записи.
    return this._mutate((db, skip) => {
      const purgedChatIds = this._purgeExpiredMessages(db);
      const chat = this._resolveChat(db, chatId);
      if (!this._canAccessChatPin(chat, userId)) {
        if (purgedChatIds.size > 0) {
          this._syncChatUpdatedAt(db, purgedChatIds);
          return null;
        }
        return skip(null);
      }

      const pin = this._findChatPin(db, chat);
      if (!pin) {
        if (purgedChatIds.size > 0) {
          this._syncChatUpdatedAt(db, purgedChatIds);
          return null;
        }
        return skip(null);
      }

      const message = this._findMessageForChatPin(db, {
        chat,
        messageId: pin.messageId,
      });
      if (!message) {
        db.chatPins = ensureChatPins(db).filter(
          (entry) => String(entry?.messageId || "").trim() !== pin.messageId,
        );
        if (purgedChatIds.size > 0) {
          this._syncChatUpdatedAt(db, purgedChatIds);
        }
        return null;
      }

      const freshPin = {
        ...createChatPinRecord({
          chatId: chat.id,
          message,
          pinnedBy: pin.pinnedBy || userId,
        }),
        pinnedAt: pin.pinnedAt || nowIso(),
      };
      if (purgedChatIds.size > 0) {
        this._syncChatUpdatedAt(db, purgedChatIds);
        return structuredClone(freshPin);
      }
      return skip(structuredClone(freshPin));
    });
  },

  async pinChatMessage({userId, chatId, messageId}) {
    return this._mutate((db, skip) => {
      const purgedChatIds = this._purgeExpiredMessages(db);
      const chat = this._resolveChat(db, chatId);
      if (!this._canAccessChatPin(chat, userId)) {
        if (purgedChatIds.size > 0) {
          this._syncChatUpdatedAt(db, purgedChatIds);
          return false;
        }
        return skip(false);
      }

      const message = this._findMessageForChatPin(db, {chat, messageId});
      if (!message) {
        if (purgedChatIds.size > 0) {
          this._syncChatUpdatedAt(db, purgedChatIds);
          return null;
        }
        return skip(null);
      }

      const relatedChatIds = this._resolveEquivalentChatIds(chat.id, chat);
      db.chatPins = ensureChatPins(db).filter((entry) => {
        return !relatedChatIds.has(String(entry?.chatId || "").trim());
      });
      const pin = createChatPinRecord({
        chatId: chat.id,
        message,
        pinnedBy: userId,
      });
      db.chatPins.push(pin);
      if (purgedChatIds.size > 0) {
        this._syncChatUpdatedAt(db, purgedChatIds);
      }
      return structuredClone(pin);
    });
  },

  async clearChatPinnedMessage({userId, chatId}) {
    return this._mutate((db, skip) => {
      const purgedChatIds = this._purgeExpiredMessages(db);
      const chat = this._resolveChat(db, chatId);
      if (!this._canAccessChatPin(chat, userId)) {
        if (purgedChatIds.size > 0) {
          this._syncChatUpdatedAt(db, purgedChatIds);
          return false;
        }
        return skip(false);
      }

      const relatedChatIds = this._resolveEquivalentChatIds(chat.id, chat);
      const pins = ensureChatPins(db);
      const nextPins = pins.filter((entry) => {
        return !relatedChatIds.has(String(entry?.chatId || "").trim());
      });
      const changed = nextPins.length !== pins.length;
      db.chatPins = nextPins;
      if (purgedChatIds.size > 0) {
        this._syncChatUpdatedAt(db, purgedChatIds);
      }
      if (changed || purgedChatIds.size > 0) {
        return true;
      }
      return skip(true);
    });
  },

  _buildChatDetails(db, chat) {
    const normalizedChat = structuredClone(chat);
    const participantIds = normalizeParticipantIds(chat.participantIds || []);
    const participants = participantIds
      .map((participantId) => {
        const user = db.users.find((entry) => entry.id === participantId);
        if (!user) {
          return null;
        }
        return {
          userId: user.id,
          displayName:
            user.profile?.displayName ||
            composeDisplayNameFromProfile(user.profile) ||
            user.email ||
            "Пользователь",
          // BUG 3: пустой user-аватар → фолбэк на фото связанной граф-персоны.
          photoUrl: this._resolveAvatarUrlForUser(
            db,
            user.id,
            user.profile?.photoUrl,
          ),
          // Last time the user was seen online. Updated on socket
          // disconnect via markUserSeenAt() — used by clients to render
          // "был(а) N минут назад" subtitles. Falls back to user updated/
          // created timestamp when never online.
          lastSeenAt:
            user.lastSeenAt || user.updatedAt || user.createdAt || null,
        };
      })
      .filter(Boolean);
    const branchRoots = Array.isArray(chat.branchRootPersonIds)
      ? chat.branchRootPersonIds
          .map((personId) => {
            const person = db.persons.find((entry) => {
              return entry.id === personId && entry.treeId === chat.treeId;
            });
            if (!person) {
              return null;
            }
            return {
              personId: person.id,
              name: person.name || "Без имени",
              photoUrl: person.photoUrl || null,
            };
          })
          .filter(Boolean)
      : [];

    return {
      chat: normalizedChat,
      participants,
      branchRoots,
    };
  },

  async getChatDetails(chatId) {
    const db = await this._read();
    const chat = this._resolveChat(db, chatId);
    if (!chat) {
      return null;
    }
    return this._buildChatDetails(db, chat);
  },

  async ensureDirectChat(userIdA, userIdB) {
    const db = await this._read();
    const participantIds = normalizeParticipantIds([userIdA, userIdB]);
    if (participantIds.length !== 2) {
      return null;
    }

    const missingUser = participantIds.some((participantId) => {
      return !db.users.some((entry) => entry.id === participantId);
    });
    if (missingUser) {
      return undefined;
    }

    const chatId = participantIds.join("_");
    let chat = this._findStoredChat(db, chatId);
    if (!chat) {
      chat = createChatRecord({
        id: chatId,
        type: "direct",
        participantIds,
        createdBy: participantIds[0],
      });
      db.chats.push(chat);
      await this._write(db);
    }

    return structuredClone(chat);
  },

  async createGroupChat({
    title,
    participantIds,
    createdBy,
    treeId = null,
    branchRootPersonIds = [],
  }) {
    const db = await this._read();
    const normalizedParticipants = normalizeParticipantIds([
      createdBy,
      ...(Array.isArray(participantIds) ? participantIds : []),
    ]);

    if (!normalizedParticipants.includes(createdBy) ||
        normalizedParticipants.length < 3) {
      return false;
    }

    const missingUser = normalizedParticipants.some((participantId) => {
      return !db.users.some((entry) => entry.id === participantId);
    });
    if (missingUser) {
      return null;
    }

    const chat = createChatRecord({
      id: `chat_${crypto.randomUUID()}`,
      type: "group",
      participantIds: normalizedParticipants,
      title,
      createdBy,
      treeId,
      branchRootPersonIds,
    });
    db.chats.push(chat);
    await this._write(db);
    return structuredClone(chat);
  },

  async updateGroupChat(chatId, {title, photoUrl}) {
    const db = await this._read();
    const chat = this._findStoredChat(db, chatId);
    if (!chat) {
      return null;
    }
    if (chat.type !== "group") {
      return false;
    }

    const hasTitlePatch = title !== undefined;
    const hasPhotoPatch = photoUrl !== undefined;
    if (!hasTitlePatch && !hasPhotoPatch) {
      return undefined;
    }

    if (hasTitlePatch) {
      const normalizedTitle = normalizeNullableString(title);
      if (!normalizedTitle) {
        return undefined;
      }
      chat.title = normalizedTitle;
    }
    if (hasPhotoPatch) {
      const normalizedPhotoUrl = normalizeNullableString(photoUrl);
      if (!normalizedPhotoUrl) {
        return undefined;
      }
      chat.photoUrl = normalizedPhotoUrl;
    }

    chat.updatedAt = nowIso();
    await this._write(db);
    return structuredClone(chat);
  },

  // G2: самовыход из группового чата. Отдельный метод (не reuse
  // removeGroupParticipant) намеренно: у remove есть пол в 3 участника
  // — нельзя ужать группу ниже жизнеспособной. Но ПОКИНУТЬ юзер обязан
  // мочь всегда (Telegram-паритет), поэтому здесь пола нет: убираем
  // звонящего из любого размера. Возвращает: null — чат не найден,
  // false — это не group-чат, undefined — звонящего нет в участниках,
  // иначе обновлённый чат.
  async leaveGroupChat(chatId, userId) {
    const db = await this._read();
    const chat = this._findStoredChat(db, chatId);
    if (!chat) {
      return null;
    }
    if (chat.type !== "group") {
      return false;
    }

    const normalizedUserId = String(userId || "").trim();
    if (!normalizedUserId) {
      return undefined;
    }

    const currentParticipantIds = normalizeParticipantIds(chat.participantIds || []);
    if (!currentParticipantIds.includes(normalizedUserId)) {
      return undefined;
    }

    chat.participantIds = currentParticipantIds.filter((entry) => {
      return entry !== normalizedUserId;
    });
    chat.updatedAt = nowIso();
    await this._write(db);
    return structuredClone(chat);
  },

  async createBranchChat({
    treeId,
    branchRootPersonIds,
    createdBy,
    title,
  }) {
    const db = await this._read();
    const tree = db.trees.find((entry) => entry.id === treeId);
    if (!tree) {
      return null;
    }

    const treePersons = db.persons.filter((entry) => entry.treeId === treeId);
    const personIds = new Set(treePersons.map((entry) => entry.id));
    const normalizedRoots = normalizeParticipantIds(branchRootPersonIds).filter(
      (personId) => personIds.has(personId),
    );
    if (normalizedRoots.length === 0) {
      return null;
    }

    const treeRelations = db.relations.filter((entry) => entry.treeId === treeId);
    const snapshot = buildTreeGraphSnapshot({
      treeId,
      persons: treePersons,
      relations: treeRelations,
      viewerPersonId: null,
    });
    const branchBlock =
      chooseBranchBlockForPerson(snapshot, normalizedRoots[0]) || null;
    const visiblePersonIds = new Set(
      branchBlock?.memberPersonIds || normalizedRoots,
    );

    const participantIds = normalizeParticipantIds([
      createdBy,
      ...treePersons
        .filter((entry) => visiblePersonIds.has(entry.id))
        .map((entry) => String(entry.userId || "").trim())
        .filter(Boolean),
    ]);
    if (!participantIds.includes(createdBy) || participantIds.length < 2) {
      return false;
    }

    const normalizedTitle = normalizeNullableString(title);
    const existingChat = db.chats.find((entry) => {
      return (
        entry.type === "branch" &&
        entry.treeId === treeId &&
        sameNormalizedIds(entry.branchRootPersonIds || [], normalizedRoots)
      );
    });
    if (existingChat) {
      let hasChanges = false;
      if (!sameNormalizedIds(existingChat.participantIds || [], participantIds)) {
        existingChat.participantIds = participantIds;
        hasChanges = true;
      }
      if (normalizedTitle && normalizedTitle !== existingChat.title) {
        existingChat.title = normalizedTitle;
        hasChanges = true;
      }
      if (hasChanges) {
        existingChat.updatedAt = nowIso();
        await this._write(db);
      }
      return structuredClone(existingChat);
    }

    const chat = createChatRecord({
      id: `chat_${crypto.randomUUID()}`,
      type: "branch",
      participantIds,
      title: normalizedTitle,
      createdBy,
      treeId,
      branchRootPersonIds:
        branchBlock?.rootUnitId ? normalizedRoots : normalizedRoots,
    });
    db.chats.push(chat);
    await this._write(db);
    return structuredClone(chat);
  },

  async listChatMessages(chatId, {limit = null, beforeId = null, afterId = null} = {}) {
    const db = await this._read();
    const purgedChatIds = this._purgeExpiredMessages(db);
    if (purgedChatIds.size > 0) {
      // Ответ уже отфильтрован in-memory; физическая зачистка — фоновым
      // атомарным sweep'ом, не stale-записью с read-пути.
      this._syncChatUpdatedAt(db, purgedChatIds);
      this._schedulePurgeSweep();
    }
    const chat = this._resolveChat(db, chatId);
    if (!chat) {
      return [];
    }
    const relatedChatIds = this._resolveEquivalentChatIds(chatId, chat);
    const sortedMessages = db.messages
      .filter((message) => relatedChatIds.has(String(message.chatId || "").trim()))
      .sort(compareChatMessagesDescending);

    const normalizedBeforeId = normalizeNullableString(beforeId);
    const normalizedAfterId = normalizeNullableString(afterId);
    let pageSource = sortedMessages;
    if (normalizedBeforeId) {
      const cursorIndex = sortedMessages.findIndex(
        (message) => String(message?.id || "").trim() === normalizedBeforeId,
      );
      pageSource = cursorIndex < 0 ? [] : sortedMessages.slice(cursorIndex + 1);
    } else if (normalizedAfterId) {
      const cursorIndex = sortedMessages.findIndex(
        (message) => String(message?.id || "").trim() === normalizedAfterId,
      );
      pageSource = cursorIndex < 0 ? [] : sortedMessages.slice(0, cursorIndex);
    }

    const normalizedLimit = Number.isFinite(Number(limit))
      ? Math.max(0, Math.floor(Number(limit)))
      : null;
    return (normalizedLimit === null ? pageSource : pageSource.slice(0, normalizedLimit))
      .map((message) => attachMessageReactions(db, message));
  },

  async searchChatMessages({
    userId,
    query,
    chatId = null,
    limit = 50,
  } = {}) {
    const db = await this._read();
    const purgedChatIds = this._purgeExpiredMessages(db);
    if (purgedChatIds.size > 0) {
      this._syncChatUpdatedAt(db, purgedChatIds);
      this._schedulePurgeSweep();
    }

    const normalizedUserId = String(userId || "").trim();
    const terms = normalizeChatSearchQuery(query);
    if (!normalizedUserId || terms.length === 0) {
      return [];
    }

    const normalizedLimit = Math.min(
      Math.max(1, Number.parseInt(String(limit || "50"), 10) || 50),
      100,
    );
    const normalizedChatId = normalizeNullableString(chatId);
    let allowedChatIds = null;
    if (normalizedChatId) {
      const chat = this._resolveChat(db, normalizedChatId);
      if (!chat || !normalizeParticipantIds(chat.participantIds).includes(normalizedUserId)) {
        return [];
      }
      allowedChatIds = this._resolveEquivalentChatIds(normalizedChatId, chat);
    }

    const chatsById = new Map(
      (Array.isArray(db.chats) ? db.chats : [])
        .map((chat) => [String(chat?.id || "").trim(), chat])
        .filter(([id]) => id),
    );
    const results = [];
    const messages = (Array.isArray(db.messages) ? db.messages : [])
      .slice()
      .sort(compareChatMessagesDescending);

    for (const message of messages) {
      if (results.length >= normalizedLimit) {
        break;
      }
      const messageChatId = String(message?.chatId || "").trim();
      if (!messageChatId || (allowedChatIds && !allowedChatIds.has(messageChatId))) {
        continue;
      }
      const chat = chatsById.get(messageChatId);
      const participantIds = chat
        ? normalizeParticipantIds(chat.participantIds)
        : parseDirectParticipantsFromChatId(messageChatId);
      if (!participantIds.includes(normalizedUserId)) {
        continue;
      }
      const expiresAt = normalizeOptionalIsoTimestamp(message?.expiresAt);
      if (expiresAt && expiresAt <= nowIso()) {
        continue;
      }
      const haystack = chatMessageSearchHaystack(message);
      if (!terms.every((term) => haystack.includes(term))) {
        continue;
      }
      results.push({
        messageId: message.id,
        chatId: messageChatId,
        senderId: message.senderId || "",
        senderName: message.senderName || "Участник",
        text: message.text || "",
        snippet: buildChatSearchSnippet(message, terms),
        matchedAt: message.timestamp,
      });
    }

    return structuredClone(results);
  },

  async addChatMessage({
    chatId,
    senderId,
    text,
    attachments = [],
    mediaUrls = [],
    imageUrl = null,
    clientMessageId = null,
    expiresAt = null,
    replyTo = null,
    call = null,
  }) {
    return this._mutate((db, skip) => {
      const purgedChatIds = this._purgeExpiredMessages(db);
      let chat = this._resolveChat(db, chatId);
      if (!chat) {
        return skip(null);
      }

      if (!db.chats.some((entry) => entry.id === chat.id)) {
        db.chats.push(chat);
      }

      const participants = normalizeParticipantIds(chat.participantIds);
      if (!participants.includes(senderId) || participants.length < 2) {
        return skip(null);
      }

      const sender = db.users.find((entry) => entry.id === senderId);
      const normalizedText = String(text || "").trim();
      const normalizedAttachments = normalizeMessageAttachments({
        attachments,
        mediaUrls,
        imageUrl,
      });
      const normalizedMediaUrls = normalizedAttachments.map((entry) => entry.url);
      const normalizedImageUrl =
        normalizedAttachments.find((entry) => entry.type === "image")?.url ||
        normalizedAttachments[0]?.url ||
        null;
      const normalizedClientMessageId = String(clientMessageId || "").trim() || null;
      const normalizedExpiresAt = normalizeOptionalIsoTimestamp(expiresAt);
      const normalizedReplyTo = normalizeReplyReference(replyTo);
      const normalizedCall = normalizeChatMessageCall(call);
      if (
        !normalizedText &&
        normalizedAttachments.length === 0 &&
        !normalizedCall
      ) {
        return skip(false);
      }

      const relatedChatIds = this._resolveEquivalentChatIds(chatId, chat);

      if (normalizedClientMessageId) {
        const existingMessage = db.messages.find(
          (entry) =>
            relatedChatIds.has(String(entry.chatId || "").trim()) &&
            entry.senderId === senderId &&
            entry.clientMessageId === normalizedClientMessageId,
        );
        if (existingMessage) {
          return skip({
            ...attachMessageReactions(db, existingMessage),
            _deduplicated: true,
          });
        }
      }

      const timestamp = nowIso();
      const message = {
        id: crypto.randomUUID(),
        chatId: chat.id,
        senderId,
        text: normalizedText,
        timestamp,
        isRead: false,
        participants,
        deliveredTo: [senderId],
        readBy: [senderId],
        senderName: sender?.profile?.displayName || "Пользователь",
        attachments: normalizedAttachments,
        imageUrl: normalizedImageUrl,
        mediaUrls: normalizedMediaUrls.length > 0 ? normalizedMediaUrls : null,
        clientMessageId: normalizedClientMessageId,
        expiresAt: normalizedExpiresAt,
        replyTo: normalizedReplyTo,
      };

      const storedChat = db.chats.find((entry) => entry.id === chat.id);
      if (storedChat) {
        storedChat.updatedAt = timestamp;
      }

      if (normalizedCall) {
        message.call = normalizedCall;
      }
      db.messages.push(message);
      if (purgedChatIds.size > 0) {
        purgedChatIds.add(chat.id);
        this._syncChatUpdatedAt(db, purgedChatIds);
      }
      return attachMessageReactions(db, message);
    });
  },

  async updateChatMessage({
    chatId,
    messageId,
    userId,
    text,
  }) {
    return this._mutate((db, skip) => {
      const purgedChatIds = this._purgeExpiredMessages(db);
      const chat = this._resolveChat(db, chatId);
      if (!chat || !chat.participantIds.includes(userId)) {
        return skip(false);
      }
      const relatedChatIds = this._resolveEquivalentChatIds(chatId, chat);

      const message = db.messages.find(
        (entry) =>
          entry.id === messageId &&
          relatedChatIds.has(String(entry.chatId || "").trim()),
      );
      if (!message) {
        return skip(null);
      }
      if (message.senderId !== userId) {
        return skip(undefined);
      }

      const normalizedText = String(text || "").trim();
      const attachments = normalizeMessageAttachments(message);
      if (!normalizedText && attachments.length === 0) {
        return skip("EMPTY_MESSAGE");
      }

      message.text = normalizedText;
      message.updatedAt = nowIso();
      const storedChat = db.chats.find((entry) => entry.id === chat.id);
      if (storedChat) {
        storedChat.updatedAt = message.updatedAt;
      }
      if (purgedChatIds.size > 0) {
        purgedChatIds.add(chat.id);
        this._syncChatUpdatedAt(db, purgedChatIds);
      }
      return attachMessageReactions(db, message);
    });
  },

  async deleteChatMessage({
    chatId,
    messageId,
    userId,
  }) {
    return this._mutate((db, skip) => {
      const purgedChatIds = this._purgeExpiredMessages(db);
      const chat = this._resolveChat(db, chatId);
      if (!chat || !chat.participantIds.includes(userId)) {
        return skip(false);
      }
      const relatedChatIds = this._resolveEquivalentChatIds(chatId, chat);

      const messageIndex = db.messages.findIndex(
        (entry) =>
          entry.id === messageId &&
          relatedChatIds.has(String(entry.chatId || "").trim()),
      );
      if (messageIndex === -1) {
        return skip(null);
      }

      const message = db.messages[messageIndex];
      if (message.senderId !== userId) {
        return skip(undefined);
      }

      db.messages.splice(messageIndex, 1);
      db.messageReactions = ensureMessageReactions(db).filter(
        (entry) => String(entry?.messageId || "").trim() !== message.id,
      );
      const pinCountBeforeDelete = ensureChatPins(db).length;
      db.chatPins = ensureChatPins(db).filter(
        (entry) => String(entry?.messageId || "").trim() !== message.id,
      );
      const clearedPinnedMessage = db.chatPins.length !== pinCountBeforeDelete;
      const storedChat = db.chats.find((entry) => entry.id === chat.id);
      if (storedChat) {
        storedChat.updatedAt = nowIso();
      }
      purgedChatIds.add(chat.id);
      this._syncChatUpdatedAt(db, purgedChatIds);
      const deletedMessage = attachMessageReactions(db, message);
      if (clearedPinnedMessage) {
        deletedMessage._clearedPinnedMessage = true;
      }
      return deletedMessage;
    });
  },

  async toggleChatMessageReaction({
    chatId,
    messageId,
    userId,
    emoji,
  }) {
    return this._mutate((db, skip) => {
      const purgedChatIds = this._purgeExpiredMessages(db);
      const chat = this._resolveChat(db, chatId);
      if (!chat || !chat.participantIds.includes(userId)) {
        return skip(false);
      }
      const relatedChatIds = this._resolveEquivalentChatIds(chatId, chat);
      const message = db.messages.find(
        (entry) =>
          entry.id === messageId &&
          relatedChatIds.has(String(entry.chatId || "").trim()),
      );
      if (!message) {
        if (purgedChatIds.size > 0) {
          this._syncChatUpdatedAt(db, purgedChatIds);
          return null;
        }
        return skip(null);
      }

      const normalizedEmoji = normalizeReactionEmoji(emoji);
      if (!normalizedEmoji) {
        return skip("INVALID_EMOJI");
      }

      const reactions = ensureMessageReactions(db);
      const existingIndex = reactions.findIndex(
        (entry) =>
          String(entry?.messageId || "").trim() === message.id &&
          String(entry?.userId || "").trim() === userId &&
          normalizeReactionEmoji(entry?.emoji) === normalizedEmoji,
      );

      let added = false;
      if (existingIndex >= 0) {
        reactions.splice(existingIndex, 1);
      } else {
        reactions.push({
          messageId: message.id,
          userId,
          emoji: normalizedEmoji,
          createdAt: nowIso(),
        });
        added = true;
      }

      if (purgedChatIds.size > 0) {
        this._syncChatUpdatedAt(db, purgedChatIds);
      }

      return {
        chatId: message.chatId || chat.id,
        messageId: message.id,
        reactions: aggregateMessageReactions(db, message.id),
        added,
      };
    });
  },

  async markChatMessageDelivered({
    chatId,
    messageId,
    userIds = [],
  }) {
    return this._mutate((db, skip) => {
      const purgedChatIds = this._purgeExpiredMessages(db);
      const chat = this._resolveChat(db, chatId);
      if (!chat) {
        return skip(false);
      }
      const relatedChatIds = this._resolveEquivalentChatIds(chatId, chat);
      const message = db.messages.find(
        (entry) =>
          entry.id === messageId &&
          relatedChatIds.has(String(entry.chatId || "").trim()),
      );
      if (!message) {
        if (purgedChatIds.size > 0) {
          this._syncChatUpdatedAt(db, purgedChatIds);
          return null;
        }
        return skip(null);
      }

      const participantIds = normalizeParticipantIds(chat.participantIds);
      const recipientIds = normalizeParticipantIds(userIds).filter(
        (userId) => participantIds.includes(userId) && userId !== message.senderId,
      );
      if (recipientIds.length === 0) {
        return skip({
          chatId: message.chatId || chat.id,
          messageId: message.id,
          deliveredTo: normalizeParticipantIds(message.deliveredTo),
          changedUserIds: [],
        });
      }

      const deliveredTo = normalizeParticipantIds(message.deliveredTo);
      let changed = false;
      for (const userId of recipientIds) {
        if (!deliveredTo.includes(userId)) {
          deliveredTo.push(userId);
          changed = true;
        }
      }
      message.deliveredTo = deliveredTo;

      if (purgedChatIds.size > 0) {
        this._syncChatUpdatedAt(db, purgedChatIds);
      }

      const result = {
        chatId: message.chatId || chat.id,
        messageId: message.id,
        deliveredTo: normalizeParticipantIds(message.deliveredTo),
        changedUserIds: changed ? recipientIds : [],
      };
      if (changed || purgedChatIds.size > 0) {
        return result;
      }
      return skip(result);
    });
  },

  async markChatAsRead(chatId, userId) {
    return this._mutate((db, skip) => {
      const purgedChatIds = this._purgeExpiredMessages(db);
      const chat = this._resolveChat(db, chatId);
      if (!chat || !chat.participantIds.includes(userId)) {
        return skip(false);
      }
      const relatedChatIds = this._resolveEquivalentChatIds(chatId, chat);

      let changed = false;
      const readMessageIds = [];

      for (const message of db.messages) {
        if (
          relatedChatIds.has(String(message.chatId || "").trim()) &&
          message.senderId !== userId
        ) {
          const deliveredTo = normalizeParticipantIds(message.deliveredTo);
          if (!deliveredTo.includes(userId)) {
            deliveredTo.push(userId);
            message.deliveredTo = deliveredTo;
            changed = true;
          }

          const readBy = normalizeParticipantIds(message.readBy);
          if (!readBy.includes(userId)) {
            readBy.push(userId);
            message.readBy = readBy;
            readMessageIds.push(message.id);
            changed = true;
          }

          if (message.isRead !== true) {
            message.isRead = true;
            changed = true;
          }
        }
      }

      if (purgedChatIds.size > 0) {
        this._syncChatUpdatedAt(db, purgedChatIds);
      }

      const result = {
        changed,
        chatId: chat.id,
        userId,
        messageIds: readMessageIds,
      };
      if (changed || purgedChatIds.size > 0) {
        return result;
      }
      return skip(result);
    });
  },

  async listChatPreviews(userId) {
    const db = await this._read();
    const purgedChatIds = this._purgeExpiredMessages(db);
    if (purgedChatIds.size > 0) {
      this._syncChatUpdatedAt(db, purgedChatIds);
      this._schedulePurgeSweep();
    }
    const relatedChats = new Map();
    const userById = new Map(
      db.users.map((entry) => [String(entry.id || "").trim(), entry]),
    );
    const previews = new Map();

    for (const chat of db.chats) {
      if (Array.isArray(chat.participantIds) && chat.participantIds.includes(userId)) {
        relatedChats.set(chat.id, chat);
      }
    }

    for (const message of db.messages) {
      if (relatedChats.has(message.chatId)) {
        continue;
      }
      const resolvedChat = this._resolveChat(db, message.chatId);
      if (resolvedChat && resolvedChat.participantIds.includes(userId)) {
        relatedChats.set(resolvedChat.id, resolvedChat);
      }
    }

    for (const chat of relatedChats.values()) {
      const participants = normalizeParticipantIds(chat.participantIds);
      const isGroup = chat.type === "group" || chat.type === "branch";
      const otherUserId = isGroup
        ? ""
        : participants.find((participant) => participant !== userId) || "";
      const preview = {
        chatId: chat.id,
        userId,
        type: chat.type || "direct",
        title: chat.title || null,
        photoUrl: isGroup ? chat.photoUrl || null : null,
        participantIds: participants,
        otherUserId,
        otherUserName: "Пользователь",
        otherUserPhotoUrl: null,
        lastMessage: "",
        lastMessageTime: chat.updatedAt || chat.createdAt || "",
        unreadCount: 0,
        lastMessageSenderId: "",
      };

      if (isGroup) {
        if (!preview.photoUrl && chat.type === "branch") {
          const rootIds = normalizeParticipantIds(chat.branchRootPersonIds);
          const rootPerson = db.persons.find((person) => {
            return (
              rootIds.includes(String(person?.id || "").trim()) &&
              String(person?.treeId || "").trim() ===
                String(chat.treeId || "").trim() &&
              (String(person?.primaryPhotoUrl || "").trim() ||
                String(person?.photoUrl || "").trim())
            );
          });
          if (rootPerson) {
            preview.photoUrl =
              String(rootPerson.primaryPhotoUrl || rootPerson.photoUrl || "")
                .trim() || null;
          }
        }
        const otherParticipantNames = [];
        for (const participantId of participants) {
          if (participantId === userId) {
            continue;
          }
          const participant = userById.get(participantId) || null;
          const participantName =
            participant?.profile?.displayName || participant?.email || "";
          if (!participantName) {
            continue;
          }
          otherParticipantNames.push(participantName);
          if (otherParticipantNames.length >= 3) {
            break;
          }
        }
        preview.otherUserName =
          chat.title ||
          (otherParticipantNames.length > 0
            ? otherParticipantNames.join(", ")
            : "Групповой чат");
      } else {
        const otherUser = userById.get(otherUserId) || null;
        if (otherUser) {
          preview.otherUserName =
            otherUser.profile?.displayName || otherUser.email || "Пользователь";
          preview.otherUserPhotoUrl = otherUser.profile?.photoUrl || null;
        }

        // Fallback: if the other user has no profile photo (or no account at all),
        // find their tree-person card and use its primaryPhotoUrl instead.
        // This covers offline-profile chats where the person has a tree photo
        // but hasn't registered an account yet.
        if (!preview.otherUserPhotoUrl && otherUserId) {
          const linkedPerson = db.persons.find((p) => {
            const personUserId = String(p.userId || "").trim();
            return (
              personUserId === otherUserId &&
              String(p.primaryPhotoUrl || "").trim()
            );
          });
          if (linkedPerson?.primaryPhotoUrl) {
            preview.otherUserPhotoUrl = String(linkedPerson.primaryPhotoUrl).trim();
          }
        }
      }

      previews.set(chat.id, preview);
    }

    for (const message of db.messages) {
      let resolvedChatId = String(message.chatId || "").trim();
      let preview = previews.get(resolvedChatId) || null;

      if (!preview) {
        const resolvedChat = this._resolveChat(db, message.chatId);
        if (!resolvedChat || !previews.has(resolvedChat.id)) {
          continue;
        }
        resolvedChatId = resolvedChat.id;
        preview = previews.get(resolvedChatId) || null;
      }

      if (!preview) {
        continue;
      }

      const messageTimestamp = String(message.timestamp || "").trim();
      const lastMessageTimestamp = String(preview.lastMessageTime || "").trim();
      if (
        !preview.lastMessage ||
        !lastMessageTimestamp ||
        messageTimestamp.localeCompare(lastMessageTimestamp) >= 0
      ) {
        preview.lastMessage = describeMessagePreview(message);
        preview.lastMessageTime = messageTimestamp;
        preview.lastMessageSenderId = message.senderId;
      }

      if (message.senderId !== userId && !isMessageReadByUser(message, userId)) {
        preview.unreadCount += 1;
      }
    }

    return Array.from(previews.values())
      .sort((left, right) =>
        String(right.lastMessageTime || "").localeCompare(
          String(left.lastMessageTime || ""),
        ),
      )
      .map((preview) => structuredClone(preview));
  },

  async countUnreadChatMessages(userId) {
    const previews = await this.listChatPreviews(userId);
    return previews.reduce((sum, preview) => {
      return sum + Number(preview?.unreadCount || 0);
    }, 0);
  },

  async listRelatedChatParticipantIds(userId) {
    const db = await this._read();
    const relatedParticipantIds = new Set();

    for (const chat of db.chats) {
      if (!Array.isArray(chat.participantIds) || !chat.participantIds.includes(userId)) {
        continue;
      }
      for (const participantId of chat.participantIds) {
        if (participantId && participantId !== userId) {
          relatedParticipantIds.add(participantId);
        }
      }
    }

    return Array.from(relatedParticipantIds);
  },

  // SPEED-2: read-пути (история чата, поиск, превью) больше НЕ пишут
  // whole-doc сами — их stale-запись после TTL-purge могла затереть
  // конкурентную _mutate-мутацию (тот же lost-update класс, что у GP3).
  // Ответ фильтруется in-memory как раньше; ФИЗИЧЕСКУЮ зачистку протухших
  // сообщений делает этот фоновый атомарный sweep: _mutate читает свежее
  // состояние в очереди, skip() держит «нечего чистить» без записи.
  _schedulePurgeSweep() {
    if (this._purgeSweepScheduled) {
      return;
    }
    this._purgeSweepScheduled = true;
    Promise.resolve()
      .then(() =>
        this._mutate((db, skip) => {
          const purgedChatIds = this._purgeExpiredMessages(db);
          if (purgedChatIds.size === 0) {
            return skip(undefined);
          }
          this._syncChatUpdatedAt(db, purgedChatIds);
          return undefined;
        }),
      )
      .catch((error) => {
        // Best-effort: протухшее вычистит следующий sweep или любая мутация —
        // но хроническую проблему (пул, oversized row) надо ВИДЕТЬ в логах.
        console.warn(
          "[store] purge sweep failed",
          error?.message || error,
        );
      })
      .then(() => {
        this._purgeSweepScheduled = false;
      });
  },

  _purgeExpiredMessages(db) {
    const expiredChatIds = new Set();
    const expiredMessageIds = new Set();
    const referenceTimeMs = Date.now();
    db.messages = db.messages.filter((message) => {
      if (isExpiredAt(message.expiresAt, referenceTimeMs)) {
        if (message.chatId) {
          expiredChatIds.add(message.chatId);
        }
        if (message.id) {
          expiredMessageIds.add(message.id);
        }
        return false;
      }
      return true;
    });
    if (expiredMessageIds.size > 0) {
      db.messageReactions = ensureMessageReactions(db).filter(
        (entry) => !expiredMessageIds.has(String(entry?.messageId || "").trim()),
      );
      db.chatPins = ensureChatPins(db).filter(
        (entry) => !expiredMessageIds.has(String(entry?.messageId || "").trim()),
      );
    }
    return expiredChatIds;
  },

  _syncChatUpdatedAt(db, chatIds) {
    for (const chatId of chatIds) {
      const chat = db.chats.find((entry) => entry.id === chatId);
      if (!chat) {
        continue;
      }
      const relatedChatIds = this._resolveEquivalentChatIds(chatId, chat);

      const latestMessage = db.messages
        .filter((entry) => relatedChatIds.has(String(entry.chatId || "").trim()))
        .sort((left, right) =>
          String(right.timestamp || "").localeCompare(String(left.timestamp || "")),
        )[0];

      chat.updatedAt = latestMessage?.timestamp || chat.createdAt || chat.updatedAt;
    }
  },
};
