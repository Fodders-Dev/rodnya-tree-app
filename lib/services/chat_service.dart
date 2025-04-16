import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/chat_message.dart';
import '../models/chat_preview.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // Отправка сообщения
  Future<void> sendMessage(ChatMessage message) async {
    try {
      // Сохраняем сообщение
      final docRef = await _firestore.collection('messages').add(message.toMap());
      
      // Обновляем или создаем информацию о чате
      await _updateChatPreview(message);
      
      print('Сообщение отправлено с ID: ${docRef.id}');
    } catch (e) {
      print('Ошибка при отправке сообщения: $e');
      rethrow;
    }
  }
  
  // Обновление информации о чате
  Future<void> _updateChatPreview(ChatMessage message) async {
    try {
      // ID текущего пользователя
      final currentUserId = _auth.currentUser!.uid;
      
      // ID другого пользователя
      final otherUserId = message.chatId.split('_').firstWhere((id) => id != currentUserId);
      
      // Получаем данные текущего пользователя
      final currentUserDoc = await _firestore.collection('users').doc(currentUserId).get();
      final currentUser = currentUserDoc.data() ?? {};
      
      // Получаем данные другого пользователя
      final otherUserDoc = await _firestore.collection('users').doc(otherUserId).get();
      final otherUser = otherUserDoc.data() ?? {};
      
      // Создаем/обновляем информацию о чате для текущего пользователя
      await _firestore.collection('chat_previews').doc('${message.chatId}_$currentUserId').set({
        'chatId': message.chatId,
        'userId': currentUserId,
        'otherUserId': otherUserId,
        'otherUserName': otherUser['displayName'] ?? 'Пользователь',
        'otherUserPhotoUrl': otherUser['photoURL'],
        'lastMessage': message.text,
        'lastMessageTime': message.timestamp,
        'unreadCount': 0, // текущий пользователь отправил, значит прочитал
        'lastMessageSenderId': message.senderId,
      }, SetOptions(merge: true));
      
      // Создаем/обновляем информацию о чате для другого пользователя
      await _firestore.collection('chat_previews').doc('${message.chatId}_$otherUserId').set({
        'chatId': message.chatId,
        'userId': otherUserId,
        'otherUserId': currentUserId,
        'otherUserName': currentUser['displayName'] ?? 'Пользователь',
        'otherUserPhotoUrl': currentUser['photoURL'],
        'lastMessage': message.text,
        'lastMessageTime': message.timestamp,
        'unreadCount': FieldValue.increment(1), // увеличиваем непрочитанное
        'lastMessageSenderId': message.senderId,
      }, SetOptions(merge: true));
      
    } catch (e) {
      print('Ошибка при обновлении информации о чате: $e');
    }
  }
  
  // Отметить чат как прочитанный
  Future<void> markChatAsRead(String chatId, String userId) async {
    try {
      // Обновляем превью чата - снижаем счетчик непрочитанных до нуля
      await _firestore.collection('chat_previews').doc('${chatId}_$userId').update({
        'unreadCount': 0,
      });
      
      // Находим все непрочитанные сообщения этого чата, отправленные не текущим пользователем
      final unreadMessagesQuery = await _firestore.collection('messages')
          .where('chatId', isEqualTo: chatId)
          .where('senderId', isNotEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .get();
      
      // Отмечаем все сообщения как прочитанные
      final batch = _firestore.batch();
      for (var doc in unreadMessagesQuery.docs) {
        batch.update(doc.reference, {'isRead': true});
      }
      
      await batch.commit();
    } catch (e) {
      print('Ошибка при отметке чата как прочитанного: $e');
    }
  }
  
  // Получение всех чатов текущего пользователя
  Stream<List<ChatPreview>> getUserChatsStream(String userId) {
    return _firestore
        .collection('chat_previews')
        .where('userId', isEqualTo: userId)
        .orderBy('lastMessageTime', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return ChatPreview.fromMap({
              'id': doc.id,
              ...doc.data(),
            });
          }).toList();
        });
  }
  
  // Получение общего количества непрочитанных сообщений
  Stream<int> getTotalUnreadCountStream(String userId) {
    return _firestore
        .collection('chat_previews')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
          int total = 0;
          for (var doc in snapshot.docs) {
            total += (doc.data()['unreadCount'] as int? ?? 0);
          }
          return total;
        });
  }
  
  // Добавляем метод getOrCreateChat в класс ChatService
  Future<String?> getOrCreateChat(String otherUserId) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return null;
      
      // Создаем ID чата как комбинацию двух ID пользователей (меньший + больший)
      // Это обеспечивает уникальность ID чата для любой пары пользователей
      final chatId = currentUser.uid.compareTo(otherUserId) < 0
          ? '${currentUser.uid}_$otherUserId'
          : '${otherUserId}_${currentUser.uid}';
      
      // Проверяем, существует ли чат
      final chatDoc = await _firestore.collection('chats').doc(chatId).get();
      
      if (!chatDoc.exists) {
        // Если чата нет, создаем его
        await _firestore.collection('chats').doc(chatId).set({
          'participants': [currentUser.uid, otherUserId],
          'createdAt': FieldValue.serverTimestamp(),
          'lastMessage': null,
          'lastMessageTime': null,
        });
        
        // Добавляем чат в список чатов для обоих пользователей
        await _firestore.collection('users').doc(currentUser.uid)
          .collection('chats').doc(chatId).set({
            'chatId': chatId,
            'otherUserId': otherUserId,
            'lastRead': FieldValue.serverTimestamp(),
            'unreadCount': 0,
          });
        
        await _firestore.collection('users').doc(otherUserId)
          .collection('chats').doc(chatId).set({
            'chatId': chatId,
            'otherUserId': currentUser.uid,
            'lastRead': FieldValue.serverTimestamp(),
            'unreadCount': 0,
          });
      }
      
      return chatId;
    } catch (e) {
      print('Ошибка при создании/получении чата: $e');
      return null;
    }
  }
} 