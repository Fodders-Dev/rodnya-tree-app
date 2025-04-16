// functions/index.js
const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

// Убедись, что ты выбрал правильный регион для функции,
// если твоя база данных не в us-central1
// Например: functions.region('europe-west3').firestore...
exports.sendChatNotification = functions.firestore
    .document("messages/{messageId}") // Следим за коллекцией messages
    .onCreate(async (snap, context) => {
      const messageData = snap.data();
      if (!messageData) {
        console.log("No message data found for messageId:", context.params.messageId);
        return null;
      }

      // --- Используем имена полей из твоей структуры ---
      const senderId = messageData.senderId;
      // !!! ПРЕДПОЛАГАЕМ, что ты добавишь поле senderName !!!
      const senderName = messageData.senderName || "Новое сообщение"; 
      const messageText = messageData.text || "";
      const chatId = messageData.chatId;
      // !!! ПРЕДПОЛАГАЕМ, что ты добавишь поле participants !!!
      const participants = messageData.participants; 
      // Используем timestamp вместо createdAt
      const createdAt = messageData.timestamp; 
      // --- Конец использования твоих имен полей ---

      // Проверка наличия необходимых данных
      if (!senderId || !Array.isArray(participants) || participants.length === 0 || !messageText) {
        console.error("Missing required fields in message document:", context.params.messageId, 
                      { senderId: !!senderId, participants: Array.isArray(participants), text: !!messageText });
        return null;
      }
       // Проверка createdAt/timestamp (опционально, но полезно)
      if (!createdAt || !(createdAt instanceof admin.firestore.Timestamp)) {
           console.warn("Message timestamp is missing or not a Timestamp object for messageId:", context.params.messageId);
           // Можно продолжить или вернуть null в зависимости от требований
      }

      console.log(`Processing new message from ${senderName} (${senderId}) in chat ${chatId}`);

      // Определяем получателей (все участники, кроме отправителя)
      const recipients = participants.filter((uid) => uid !== senderId);
      if (recipients.length === 0) {
        console.log("No recipients for this message (only sender in participants?).");
        return null;
      }

      console.log("Calculated Recipients:", recipients);

      // --- Получаем FCM токены получателей ---
      const tokensPromises = recipients.map(userId =>
          admin.firestore().collection("users").doc(userId).get()
      );
      const userDocs = await Promise.all(tokensPromises);

      const recipientTokens = [];
      const tokensToRemoveByUser = {}; // Для удаления невалидных токенов

      userDocs.forEach((userDoc) => {
          const userId = userDoc.id;
          if (userDoc.exists) {
              const userData = userDoc.data();
              // Убедись, что поле называется fcmTokens и это массив строк
              const tokens = userData.fcmTokens; 
              if (Array.isArray(tokens) && tokens.length > 0) {
                  // Фильтруем пустые или невалидные токены на всякий случай
                  const validTokens = tokens.filter(token => token && typeof token === 'string' && token.length > 10); 
                  if(validTokens.length > 0){
                      recipientTokens.push(...validTokens);
                      console.log(`Found ${validTokens.length} valid tokens for user ${userId}`);
                  } else {
                      console.log(`No valid tokens found for user ${userId} in fcmTokens array.`);
                  }
                  tokensToRemoveByUser[userId] = []; // Инициализируем массив для удаления
              } else {
                  console.log(`fcmTokens field is missing, not an array, or empty for user ${userId}`);
              }
          } else {
              console.warn(`User profile not found for recipient ${userId}`);
          }
      });
      // --- Конец получения токенов ---


      if (recipientTokens.length === 0) {
        console.log("No valid tokens found for any recipient.");
        return null;
      }

      // Убираем дубликаты токенов
      const uniqueTokens = [...new Set(recipientTokens)];
      console.log(`Sending notification to ${uniqueTokens.length} unique tokens.`);

      // --- Формируем Payload уведомления ---
      const payload = {
        notification: {
          title: senderName, 
          body: messageText.length > 100 ?
                messageText.substring(0, 97) + "..." : messageText, 
          // Дополнительные параметры (опционально)
          // sound: "default", // Стандартный звук
          // icon: 'ic_stat_notification', // Убедись, что иконка есть в drawable
          // tag: chatId, // Группировка уведомлений на Android по чату
        },
        data: {
          // Данные для обработки в приложении при нажатии
          chatId: chatId || "", 
          senderId: senderId || "", // Передаем ID отправителя
          type: "chat", // Тип для различения
          click_action: "FLUTTER_NOTIFICATION_CLICK", // Стандартный action
        },
        // Опции для Android (опционально)
        // android: {
        //   notification: {
        //     channel_id: "general_notifications" // Укажи ID канала, если нужно специфичный
        //   }
        // },
        // Опции для APNS (iOS) (опционально)
        // apns: {
        //   payload: {
        //     aps: {
        //       sound: "default",
        //       'thread-id': chatId // Группировка на iOS
        //     }
        //   }
        // }
      };
      // --- Конец формирования Payload ---

      try {
        // --- Отправка уведомлений ---
        const response = await admin.messaging().sendToDevice(uniqueTokens, payload);
        console.log("Successfully sent message count:", response.successCount);
        console.log("Failed message count:", response.failureCount);

        // --- Обработка ошибок и удаление невалидных токенов ---
        response.results.forEach((result, index) => {
          const error = result.error;
          const token = uniqueTokens[index];
          if (error) {
            console.error(
                `Failure sending notification to token ${token}:`, 
                error.code, 
                error.message
            );
            // Если токен недействителен, помечаем на удаление
            if (error.code === "messaging/invalid-registration-token" ||
                error.code === "messaging/registration-token-not-registered") {
                // Находим пользователя, которому принадлежит токен (нужна обратная логика или хранить userId вместе с токеном)
                // В данном коде мы не знаем точно, какому userId принадлежит невалидный токен,
                // поэтому удаление сложнее. Простой вариант - не удалять или переделать логику получения токенов.
                console.warn(`Token ${token} is invalid. Consider removing it.`);
                 // Простая реализация: найдем всех юзеров с этим токеном и удалим у них
                 // Это неэффективно, лучше переделать хранение токенов, если удаление критично
                 recipients.forEach(userId => {
                    const userTokens = userDocs.find(doc => doc.id === userId)?.data()?.fcmTokens;
                    if (Array.isArray(userTokens) && userTokens.includes(token)) {
                       if (!tokensToRemoveByUser[userId]) tokensToRemoveByUser[userId] = [];
                       tokensToRemoveByUser[userId].push(token);
                    }
                 });
            }
          }
        });

        // Удаляем невалидные токены из Firestore
        const removePromises = Object.entries(tokensToRemoveByUser).map(([userId, tokens]) => {
            if (tokens && tokens.length > 0) {
                console.log(`Removing invalid tokens for user ${userId}: ${tokens}`);
                return admin.firestore().collection("users").doc(userId).update({
                    fcmTokens: admin.firestore.FieldValue.arrayRemove(...tokens)
                });
            }
            return Promise.resolve();
        });
        await Promise.all(removePromises);
        // --- Конец обработки ошибок ---

        return response;
      } catch (error) {
        console.error("Error sending push notification:", error);
        return null;
      }
    });
