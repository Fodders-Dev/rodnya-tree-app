const {
  normalizePublicUrl,
  normalizePublicUrlList,
} = require("../profile-utils");
const {normalizeAttachmentWaveform} = require("../chat-utils");
const {
  truncateText,
  normalizeSmallPublicUrl,
} = require("./notification-safety-mappers");

function mapChatMessage(message) {
  const explicitAttachments = Array.isArray(message.attachments)
    ? message.attachments
        .filter((attachment) => String(attachment?.url || "").trim())
        .map((attachment) => ({
          type: String(attachment.type || "file"),
          url: normalizePublicUrl(String(attachment.url || "").trim()),
          presentation: String(attachment.presentation || "default"),
          mimeType: attachment.mimeType || null,
          fileName: attachment.fileName || null,
          sizeBytes: Number.isFinite(Number(attachment.sizeBytes))
            ? Number(attachment.sizeBytes)
            : null,
          durationMs: Number.isFinite(Number(attachment.durationMs))
            ? Number(attachment.durationMs)
            : null,
          waveform: normalizeAttachmentWaveform(attachment.waveform),
          width: Number.isFinite(Number(attachment.width))
            ? Number(attachment.width)
            : null,
          height: Number.isFinite(Number(attachment.height))
            ? Number(attachment.height)
            : null,
          thumbnailUrl: normalizePublicUrl(attachment.thumbnailUrl || null),
        }))
    : [];
  const attachments = explicitAttachments.length > 0
    ? explicitAttachments
    : [
        ...new Set(
          [
            ...(Array.isArray(message.mediaUrls) ? message.mediaUrls : []),
            message.imageUrl,
          ]
            .map((value) => String(value || "").trim())
            .filter(Boolean),
        ),
      ].map((url) => ({
        type: "image",
        url: normalizePublicUrl(url),
        presentation: "default",
        mimeType: "image/jpeg",
        fileName: null,
        sizeBytes: null,
        durationMs: null,
        waveform: [],
        width: null,
        height: null,
        thumbnailUrl: null,
      }));
  const reactions = Array.isArray(message.reactions)
    ? message.reactions
        .map((reaction) => {
          const emoji = String(reaction?.emoji || "").trim();
          const userIds = Array.from(
            new Set(
              (Array.isArray(reaction?.userIds) ? reaction.userIds : [])
                .map((value) => String(value || "").trim())
                .filter(Boolean),
            ),
          );
          return {
            emoji,
            userIds,
            count: Number.isFinite(Number(reaction?.count))
              ? Math.max(0, Math.floor(Number(reaction.count)))
              : userIds.length,
          };
        })
        .filter((reaction) => reaction.emoji && reaction.count > 0)
    : [];
  return {
    id: message.id,
    chatId: message.chatId,
    senderId: message.senderId,
    text: message.text,
    timestamp: message.timestamp,
    updatedAt: message.updatedAt || null,
    isRead: message.isRead === true,
    deliveredTo: Array.isArray(message.deliveredTo)
      ? message.deliveredTo
          .map((value) => String(value || "").trim())
          .filter(Boolean)
      : [],
    readBy: Array.isArray(message.readBy)
      ? message.readBy
          .map((value) => String(value || "").trim())
          .filter(Boolean)
      : [],
    attachments,
    imageUrl: normalizePublicUrl(message.imageUrl || null),
    mediaUrls: normalizePublicUrlList(message.mediaUrls),
    participants: Array.isArray(message.participants)
      ? message.participants
      : [],
    senderName: message.senderName,
    clientMessageId: message.clientMessageId || null,
    expiresAt: message.expiresAt || null,
    replyTo: message.replyTo || null,
    reactions,
    call: mapChatMessageCall(message.call),
  };
}

function mapChatMessageCall(value) {
  if (!value || typeof value !== "object") {
    return null;
  }
  const callId = String(value.callId || "").trim();
  if (!callId) {
    return null;
  }
  return {
    callId,
    state: String(value.state || "").trim() || "ended",
    mediaMode: String(value.mediaMode || "").trim() === "video"
      ? "video"
      : "audio",
    durationMs: Number.isFinite(Number(value.durationMs))
      ? Math.max(0, Math.floor(Number(value.durationMs)))
      : null,
    initiatorId: value.initiatorId ? String(value.initiatorId).trim() : null,
    direction: value.direction === "incoming" ? "incoming" : "outgoing",
  };
}

function mapChatRecord(chat) {
  return {
    id: chat.id,
    type: chat.type || "direct",
    title: chat.title || null,
    photoUrl: normalizeSmallPublicUrl(chat.photoUrl || null),
    participantIds: Array.isArray(chat.participantIds)
      ? chat.participantIds
      : [],
    createdBy: chat.createdBy || null,
    treeId: chat.treeId || null,
    branchRootPersonIds: Array.isArray(chat.branchRootPersonIds)
      ? chat.branchRootPersonIds
      : [],
    createdAt: chat.createdAt,
    updatedAt: chat.updatedAt,
  };
}

function mapCallSession(session) {
  if (!session || typeof session !== "object") {
    return null;
  }
  return {
    roomName: String(session.roomName || "").trim(),
    url: String(session.url || "").trim(),
    token: String(session.token || "").trim(),
    participantIdentity: String(session.participantIdentity || "").trim(),
    participantName: session.participantName || null,
    createdAt: session.createdAt || null,
  };
}

function mapCallMetrics(metrics) {
  if (!metrics || typeof metrics !== "object") {
    return {
      acceptLatencyMs: null,
      roomJoinFailureCount: 0,
      reconnectCount: 0,
      lastRoomJoinFailureReason: null,
      lastWebhookEvent: null,
    };
  }
  return {
    acceptLatencyMs: Number.isFinite(Number(metrics.acceptLatencyMs))
      ? Math.max(0, Math.floor(Number(metrics.acceptLatencyMs)))
      : null,
    roomJoinFailureCount: Number.isFinite(Number(metrics.roomJoinFailureCount))
      ? Math.max(0, Math.floor(Number(metrics.roomJoinFailureCount)))
      : 0,
    reconnectCount: Number.isFinite(Number(metrics.reconnectCount))
      ? Math.max(0, Math.floor(Number(metrics.reconnectCount)))
      : 0,
    lastRoomJoinFailureReason: metrics.lastRoomJoinFailureReason || null,
    lastWebhookEvent: metrics.lastWebhookEvent || null,
  };
}

function logCallEvent(eventType, call, extra = {}) {
  if (!call || typeof call !== "object") {
    return;
  }

  const metrics = mapCallMetrics(call.metrics);
  console.log(
    "[backend] call",
    JSON.stringify({
      eventType,
      callId: call.id || null,
      chatId: call.chatId || null,
      mediaMode: call.mediaMode || null,
      state: call.state || null,
      createdAt: call.createdAt || null,
      acceptedAt: call.acceptedAt || null,
      endedAt: call.endedAt || null,
      endedReason: call.endedReason || null,
      acceptLatencyMs: metrics.acceptLatencyMs,
      roomJoinFailureCount: metrics.roomJoinFailureCount,
      reconnectCount: metrics.reconnectCount,
      lastRoomJoinFailureReason: metrics.lastRoomJoinFailureReason,
      lastWebhookEvent: metrics.lastWebhookEvent,
      ...extra,
    }),
  );
}

function ownerSessionIdForViewer(call, viewerUserId) {
  if (!call || !viewerUserId) {
    return "";
  }
  // N-way: any joined participant's device session (group late-join).
  const joinedSessionByUserId =
    call.joinedSessionByUserId && typeof call.joinedSessionByUserId === "object"
      ? call.joinedSessionByUserId
      : {};
  const joinedSessionId = String(
    joinedSessionByUserId[viewerUserId] || "",
  ).trim();
  if (joinedSessionId) {
    return joinedSessionId;
  }
  // The initiator never "joins" via accept — their owning device is the one
  // that originated the call.
  if (call.initiatorId === viewerUserId) {
    return String(call.originatedBySessionId || "").trim();
  }
  // Back-compat: scalar accepter for in-flight records / old clients.
  if (call.acceptedByUserId === viewerUserId) {
    return String(call.acceptedBySessionId || "").trim();
  }
  return "";
}

function mapCallRecord(
  call,
  {viewerUserId = null, viewerSessionId = null} = {},
) {
  const ownerSessionId = ownerSessionIdForViewer(call, viewerUserId);
  const normalizedViewerSessionId = String(viewerSessionId || "").trim();
  const isOwningDevice =
    Boolean(ownerSessionId) &&
    Boolean(normalizedViewerSessionId) &&
    ownerSessionId === normalizedViewerSessionId;
  const callIsActive = (call.state || "ringing") === "active";
  const otherDeviceJoined =
    callIsActive && Boolean(ownerSessionId) && !isOwningDevice;
  const session =
    isOwningDevice && viewerUserId && call.sessionByUserId
      ? mapCallSession(call.sessionByUserId[viewerUserId])
      : null;
  return {
    id: call.id,
    chatId: call.chatId,
    initiatorId: call.initiatorId,
    recipientId: call.recipientId,
    participantIds: Array.isArray(call.participantIds)
      ? call.participantIds
      : [],
    mediaMode: call.mediaMode || "audio",
    state: call.state || "ringing",
    roomName: call.roomName || null,
    createdAt: call.createdAt,
    updatedAt: call.updatedAt,
    acceptedAt: call.acceptedAt || null,
    endedAt: call.endedAt || null,
    endedReason: call.endedReason || null,
    metrics: mapCallMetrics(call.metrics),
    session,
    joinedOnAnotherDevice: otherDeviceJoined,
  };
}


function createChatCallMappers({realtimeHub = null} = {}) {
  function mapChatParticipant(participant) {
    // `isOnline` reflects the live realtime-hub state at response time —
    // any active socket for this user counts as online. `lastSeenAt`
    // comes from the user record (persisted via markUserSeenAt on socket
    // disconnect). Together they let the chat-screen subtitle render
    // "в сети" / "была N минут назад" on first paint, without needing
    // an extra realtime event before the data shows up.
    const isOnline =
      typeof realtimeHub?.isUserOnline === "function" && participant.userId
        ? realtimeHub.isUserOnline(participant.userId)
        : false;
    return {
      userId: participant.userId,
      displayName: participant.displayName || "Пользователь",
      photoUrl: normalizePublicUrl(participant.photoUrl || null),
      isOnline,
      lastSeenAt: participant.lastSeenAt || null,
    };
  }


  return {
    mapChatParticipant,
  };
}

function mapChatBranchRoot(branchRoot) {
  return {
    personId: branchRoot.personId,
    name: branchRoot.name || "Без имени",
    photoUrl: normalizePublicUrl(branchRoot.photoUrl || null),
  };
}

function mapChatPreview(preview) {
  const isGroupPreview =
    String(preview?.type || "").trim() === "group" ||
    String(preview?.type || "").trim() === "branch";
  const normalizedParticipantIds = Array.isArray(preview?.participantIds)
    ? preview.participantIds
    : [];
  const previewParticipantIds = isGroupPreview
    ? normalizedParticipantIds.slice(0, 12)
    : normalizedParticipantIds;
  return {
    id: `${preview.chatId}_${preview.userId}`,
    chatId: preview.chatId,
    userId: preview.userId,
    type: preview.type || "direct",
    title: truncateText(preview.title, 160),
    photoUrl: normalizeSmallPublicUrl(preview.photoUrl || null),
    participantIds: previewParticipantIds,
    participantCount: normalizedParticipantIds.length,
    otherUserId: preview.otherUserId,
    otherUserName: truncateText(preview.otherUserName || "Пользователь", 120),
    otherUserPhotoUrl: normalizeSmallPublicUrl(preview.otherUserPhotoUrl || null),
    lastMessage: truncateText(preview.lastMessage || "", 280) || "",
    lastMessageTime: preview.lastMessageTime,
    unreadCount: Number(preview.unreadCount || 0),
    lastMessageSenderId: preview.lastMessageSenderId || "",
  };
}


module.exports = {
  mapChatMessage,
  mapChatMessageCall,
  mapChatRecord,
  mapCallSession,
  mapCallMetrics,
  logCallEvent,
  ownerSessionIdForViewer,
  mapCallRecord,
  createChatCallMappers,
  mapChatBranchRoot,
  mapChatPreview,
};
