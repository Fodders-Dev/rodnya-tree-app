import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_profile.dart';
import '../models/chat_message.dart';
import '../services/chat_service.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

// Импортируем RelativeDetailsScreen
import '../screens/relative_details_screen.dart'; 
// Комментируем импорт UserProfileScreen
// import '../screens/user_profile_screen.dart'; 

class ChatScreen extends StatefulWidget {
  final String otherUserId;
  final String otherUserName;
  final String? otherUserPhotoUrl;
  final String relativeId;
  
  const ChatScreen({
    Key? key,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserPhotoUrl,
    required this.relativeId,
  }) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _messageController = TextEditingController();
  final ChatService _chatService = ChatService();
  
  late String _currentUserId;
  late String _chatId;
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _currentUserId = _auth.currentUser!.uid;
    
    // Создаем или получаем чатId (меньший ID всегда первый для конистентности)
    List<String> ids = [_currentUserId, widget.otherUserId];
    ids.sort(); // Сортируем IDs для получения консистентного ID чата
    _chatId = ids.join('_');
    
    _markChatAsRead();
    print('ChatScreen initialized for chatId: $_chatId, relativeId: ${widget.relativeId}');
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }
  
  // Отмечаем чат как прочитанный
  Future<void> _markChatAsRead() async {
    try {
      await _chatService.markChatAsRead(_chatId, _currentUserId);
      print('Chat $_chatId marked as read by $_currentUserId');
    } catch (e) {
      print('Ошибка при отметке чата как прочитанного: $e');
    }
  }
  
  // Отправка сообщения
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    try {
      // Получаем имя текущего пользователя (оптимизация: можно загрузить один раз в initState)
      String? senderName = _auth.currentUser?.displayName;
      // Попробуем получить более полное имя из профиля, если нужно
      // final userProfileDoc = await _firestore.collection('users').doc(_currentUserId).get();
      // if (userProfileDoc.exists) {
      //   senderName = UserProfile.fromMap(userProfileDoc.data()!, _currentUserId).displayName;
      // }

      final message = ChatMessage(
        id: '',
        chatId: _chatId,
        senderId: _currentUserId,
        text: text,
        timestamp: DateTime.now(),
        isRead: false,
        // Добавляем participants
        participants: [_currentUserId, widget.otherUserId],
        // Добавляем senderName
        senderName: senderName ?? 'Пользователь', // Используем displayName или заглушку
      );
      
      await _chatService.sendMessage(message);
      print('Message sent to chat $_chatId');
    } catch (e) {
      print('Ошибка при отправке сообщения: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось отправить сообщение')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            GestureDetector(
              onTap: () {
                print('Navigating to relative details: ${widget.relativeId}');
                context.push('/relative/details/${widget.relativeId}');
              },
              child: CircleAvatar(
                radius: 20,
                backgroundImage: widget.otherUserPhotoUrl != null && widget.otherUserPhotoUrl!.isNotEmpty
                    ? NetworkImage(widget.otherUserPhotoUrl!)
                    : null,
                child: widget.otherUserPhotoUrl == null || widget.otherUserPhotoUrl!.isEmpty
                    ? Text(widget.otherUserName.isNotEmpty ? widget.otherUserName[0] : '?')
                    : null,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                 crossAxisAlignment: CrossAxisAlignment.start,
                 children: [
                    Text(
                      widget.otherUserName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                 ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                   .collection('messages')
                   .where('chatId', isEqualTo: _chatId)
                   .orderBy('timestamp', descending: true)
                   .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  print('Chat stream error: ${snapshot.error}');
                  return Center(
                    child: Text('Ошибка загрузки сообщений.'),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text('Нет сообщений. Начните общение!'),
                  );
                }
                
                final messages = snapshot.data!.docs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>?;
                  if (data == null) {
                     print('Warning: Chat message data is null for doc ${doc.id}');
                     return null;
                  }
                  try {
                     return ChatMessage.fromMap({
                        'id': doc.id,
                        ...data,
                      });
                  } catch (e) {
                     print('Error parsing message ${doc.id}: $e');
                     return null;
                  }
                }).where((msg) => msg != null).cast<ChatMessage>().toList();

                if (messages.isEmpty) {
                  return Center(
                    child: Text('Нет сообщений. Начните общение!'),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isMe = message.senderId == _currentUserId;
                    
                    return _buildMessageBubble(message, isMe);
                  },
                );
              },
            ),
          ),
          
          _buildMessageInputArea(),
        ],
      ),
    );
  }
  
  Widget _buildMessageInputArea() {
     return Material(
      elevation: 5.0,
       color: Theme.of(context).cardColor,
       child: Padding(
         padding: EdgeInsets.only(
           left: 8.0,
           right: 8.0,
           top: 8.0,
            bottom: MediaQuery.of(context).padding.bottom + 8.0,
         ),
         child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
             Expanded(
              child: Container(
                 padding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                 decoration: BoxDecoration(
                   color: Theme.of(context).scaffoldBackgroundColor,
                   borderRadius: BorderRadius.circular(24.0),
                 ),
                 child: TextField(
                   controller: _messageController,
                   decoration: InputDecoration.collapsed(
                     hintText: 'Сообщение...',
                   ),
                   textCapitalization: TextCapitalization.sentences,
                   keyboardType: TextInputType.multiline,
                    minLines: 1,
                    maxLines: 5,
                 ),
               ),
             ),
             SizedBox(width: 8.0),
             FloatingActionButton(
                mini: true,
                onPressed: _sendMessage,
                child: Icon(Icons.send),
                elevation: 0,
             ),
           ],
         ),
       ),
     );
  }
  
  Widget _buildMessageBubble(ChatMessage message, bool isMe) {
    final time = DateFormat.Hm('ru').format(message.timestamp);
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 8.0),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          decoration: BoxDecoration(
            color: isMe 
                ? Colors.blue[600]
                : Colors.grey[300],
            borderRadius: BorderRadius.only(
               topLeft: Radius.circular(16.0),
               topRight: Radius.circular(16.0),
               bottomLeft: Radius.circular(isMe ? 16.0 : 0),
               bottomRight: Radius.circular(isMe ? 0 : 16.0),
            ),
          ),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(
                message.text,
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.black87,
                  fontSize: 16.0,
                ),
              ),
              SizedBox(height: 4.0),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    time,
                    style: TextStyle(
                      color: isMe 
                          ? Colors.white.withOpacity(0.7) 
                          : Colors.black54,
                      fontSize: 11.0,
                    ),
                  ),
                  if (isMe) ...[
                    SizedBox(width: 5.0),
                    Icon(
                      message.isRead ? Icons.done_all : Icons.done,
                      size: 14.0,
                      color: message.isRead
                            ? Colors.lightBlueAccent[100]
                            : Colors.white.withOpacity(0.7),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
} 