// S5: юнит-тесты RealtimeHub без сокетов — протухание userActiveChats
// (TTL 60с) и адресная доставка message.delivered (одному отправителю,
// а не всем N участникам).

const test = require("node:test");
const assert = require("node:assert/strict");

const {RealtimeHub} = require("../src/realtime-hub");

test("userActiveChats протухает через 60с idle", () => {
  const hub = new RealtimeHub({store: {}});

  hub._handleActiveChatSet("user-1", {chatId: "chat-1"});
  assert.equal(hub.isUserActiveInChat("user-1", "chat-1"), true);

  // Состариваем запись вручную — «свёрнутое приложение» 61 секунду.
  hub.userActiveChats.get("user-1").set("chat-1", Date.now() - 61_000);
  assert.equal(
    hub.isUserActiveInChat("user-1", "chat-1"),
    false,
    "протухшая активность не должна глушить пуши",
  );
  // Ленивая чистка удалила запись целиком.
  assert.equal(hub.userActiveChats.has("user-1"), false);

  // Свежий touch возвращает активность.
  hub._handleActiveChatSet("user-1", {chatId: "chat-1"});
  assert.equal(hub.isUserActiveInChat("user-1", "chat-1"), true);
});

test("message.delivered уходит только отправителю (N+1, не 2×N)", async () => {
  const participantIds = ["sender", "reader-1", "reader-2", "reader-3"];
  const store = {
    findChat: async () => ({id: "chat-1", participantIds}),
    markChatMessageDelivered: async ({userIds}) => ({
      chatId: "chat-1",
      messageId: "m-1",
      changedUserIds: userIds,
      deliveredTo: ["sender", ...userIds],
    }),
  };
  const hub = new RealtimeHub({store});

  const published = [];
  hub.publishToUser = (userId, payload) => {
    published.push({userId, type: payload.type});
    return true; // все онлайн
  };

  await hub.publishToChat("chat-1", {
    type: "chat.message.created",
    chatId: "chat-1",
    message: {id: "m-1", senderId: "sender"},
  });

  const createdRecipients = published
    .filter((entry) => entry.type === "chat.message.created")
    .map((entry) => entry.userId);
  const deliveredRecipients = published
    .filter((entry) => entry.type === "message.delivered")
    .map((entry) => entry.userId);

  assert.deepEqual(createdRecipients.sort(), [...participantIds].sort());
  assert.deepEqual(
    deliveredRecipients,
    ["sender"],
    "галочки «доставлено» нужны только автору сообщения",
  );
  // Итог: N created + 1 delivered, а не 2×N.
  assert.equal(published.length, participantIds.length + 1);
});
