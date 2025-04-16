import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/relation_request.dart';
import '../models/family_relation.dart';
import '../models/family_person.dart';
import '../services/family_service.dart';
import 'package:uuid/uuid.dart';
import 'package:get_it/get_it.dart';

class RelationRequestsScreen extends StatefulWidget {
  final String treeId;
  
  const RelationRequestsScreen({
    Key? key,
    required this.treeId,
  }) : super(key: key);

  @override
  _RelationRequestsScreenState createState() => _RelationRequestsScreenState();
}

class _RelationRequestsScreenState extends State<RelationRequestsScreen> {
  List<RelationRequest> _requests = [];
  Map<String, dynamic> _userProfiles = {};
  bool _isLoading = true;
  String? _error;
  
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FamilyService _familyService = GetIt.I<FamilyService>();
  final Uuid _uuid = Uuid();
  
  @override
  void initState() {
    super.initState();
    _loadRequests();
    
    // Добавляем слушатель для автоматического обновления
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final focusNode = FocusNode();
      FocusScope.of(context).requestFocus(focusNode);
      focusNode.addListener(() {
        if (focusNode.hasFocus) {
          _loadRequests();
        }
      });
    });
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Проверяем, если экран активен, обновляем данные
    if (ModalRoute.of(context)?.isCurrent ?? false) {
      _loadRequests();
    }
  }
  
  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    try {
      // Проверяем, что пользователь авторизован
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _error = 'Пользователь не авторизован';
          _isLoading = false;
        });
        return;
      }
      
      // Загружаем запросы, где текущий пользователь является получателем
      final receivedSnapshot = await FirebaseFirestore.instance
          .collection('relation_requests')
          .where('recipientId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .get()
          .catchError((e) {
            print('Ошибка при загрузке полученных запросов: $e');
            // Проверяем, связана ли ошибка с отсутствием индекса
            if (e.toString().contains('index')) {
              setState(() {
                _error = 'Требуется создать индекс в Firebase. Пожалуйста, перейдите по ссылке в консоли.';
              });
            }
            return null;
          });
      
      if (receivedSnapshot == null) {
        // Если произошла ошибка при запросе
        setState(() {
          _isLoading = false;
          if (_error == null) {
            _error = 'Ошибка при загрузке запросов';
          }
        });
        return;
      }
      
      // Обрабатываем результаты
      final List<RelationRequest> receivedRequests = [];
      for (var doc in receivedSnapshot.docs) {
        try {
          final request = RelationRequest.fromFirestore(doc);
          receivedRequests.add(request);
        } catch (e) {
          print('Ошибка при обработке запроса ${doc.id}: $e');
        }
      }
      
      setState(() {
        _requests = receivedRequests;
        _userProfiles = {};
        _isLoading = false;
      });
    } catch (e) {
      print('Общая ошибка при загрузке запросов: $e');
      setState(() {
        _error = 'Ошибка при загрузке запросов: ${e.toString()}';
        _isLoading = false;
      });
    }
  }
  
  Future<void> _respondToRequest(String requestId, RequestStatus status) async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final request = _requests.firstWhere((req) => req.id == requestId);
      final requestDoc = await _firestore.collection('relation_requests').doc(requestId).get();
      final requestData = requestDoc.data() as Map<String, dynamic>;
      
      // Проверяем, является ли это запросом на замену (есть ли поле offlineRelativeId)
      final bool isReplaceRequest = requestData.containsKey('offlineRelativeId') && 
                                 requestData['offlineRelativeId'] != null;
      
      if (isReplaceRequest && status == RequestStatus.accepted) {
        // Если это запрос на замену и он принят, вызываем метод для замены
        await _acceptReplaceRequest(requestDoc);
      } else {
        // Обычный запрос на родство
        // Обновляем статус запроса
        await _firestore
            .collection('relation_requests')
            .doc(requestId)
            .update({
              'status': RelationRequest.requestStatusToString(status),
              'respondedAt': FieldValue.serverTimestamp(),
            });
        
        // Если запрос принят, создаем связь в обе стороны
        if (status == RequestStatus.accepted) {
          final userId = _auth.currentUser!.uid;
          
          // Получаем данные обоих пользователей для создания правильных связей
          final senderData = await _firestore.collection('users').doc(request.senderId).get();
          final recipientData = await _firestore.collection('users').doc(userId).get();
          
          final senderGender = _stringToGender(senderData['gender'] ?? 'unknown');
          final recipientGender = _stringToGender(recipientData['gender'] ?? 'unknown');
          
          // Создаем отношение от отправителя к получателю (уже существующее в запросе)
          final relationId1 = _uuid.v4();
          await _firestore
              .collection('family_relations')
              .doc(relationId1)
              .set({
                'id': relationId1,
                'treeId': request.treeId,
                'personAId': request.senderId,
                'personBId': userId,
                'relationType': FamilyRelation.relationTypeToString(request.senderToRecipient),
                'createdAt': FieldValue.serverTimestamp(),
              });
          
          // Создаем зеркальное отношение (от получателя к отправителю)
          final mirrorRelation = FamilyRelation.getMirrorRelation(request.senderToRecipient);
          final relationId2 = _uuid.v4();
          await _firestore
              .collection('family_relations')
              .doc(relationId2)
              .set({
                'id': relationId2,
                'treeId': request.treeId,
                'personAId': userId,
                'personBId': request.senderId,
                'relationType': FamilyRelation.relationTypeToString(mirrorRelation),
                'createdAt': FieldValue.serverTimestamp(),
              });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Родственная связь установлена')),
          );
        }
      }
      
      // Обновляем список запросов
      _loadRequests();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(status == RequestStatus.accepted 
          ? 'Запрос принят' 
          : 'Запрос отклонен')),
      );
    } catch (e) {
      print('Ошибка при обработке запроса: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  // Вспомогательный метод для преобразования строки в тип Gender
  Gender _stringToGender(String value) {
    switch (value) {
      case 'male': return Gender.male;
      case 'female': return Gender.female;
      case 'other': return Gender.other;
      default: return Gender.unknown;
    }
  }
  
  Future<void> _acceptReplaceRequest(DocumentSnapshot request) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final requestData = request.data() as Map<String, dynamic>;
      final String offlineRelativeId = requestData['offlineRelativeId'];
      final String treeId = requestData['treeId'];
      final String senderId = requestData['senderId'];
      final String relationType = requestData['relationType'];

      // Получаем данные офлайн родственника
      final offlineRelativeDoc = await _firestore
          .collection('family_trees')
          .doc(treeId)
          .collection('relatives')
          .doc(offlineRelativeId)
          .get();

      if (!offlineRelativeDoc.exists) {
        throw Exception('Офлайн родственник не найден');
      }

      // Получаем данные текущего пользователя
      final currentUserDoc = await _firestore
          .collection('users')
          .doc(_auth.currentUser!.uid)
          .get();

      if (!currentUserDoc.exists) {
        throw Exception('Данные пользователя не найдены');
      }

      final userData = currentUserDoc.data()!;

      // Создаем нового родственника на основе данных пользователя
      final newRelative = FamilyPerson(
        id: _auth.currentUser!.uid,
        treeId: treeId,
        userId: _auth.currentUser!.uid,
        name: userData['displayName'] ?? 'Без имени',
        gender: userData['gender'] == 'male' ? Gender.male : Gender.female,
        birthDate: userData['birthDate'] != null 
            ? (userData['birthDate'] as Timestamp).toDate() 
            : null,
        isAlive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Получаем все существующие связи для офлайн родственника
      final relationsQuery = await _firestore
          .collection('family_relations')
          .where('treeId', isEqualTo: treeId)
          .get();

      final List<Map<String, dynamic>> newRelations = [];
      final List<String> relationsToDelete = [];

      // Обрабатываем каждую связь
      for (var relationDoc in relationsQuery.docs) {
        final relationData = relationDoc.data();
        bool needsUpdate = false;

        if (relationData['person1Id'] == offlineRelativeId) {
          relationData['person1Id'] = _auth.currentUser!.uid;
          needsUpdate = true;
        }

        if (relationData['person2Id'] == offlineRelativeId) {
          relationData['person2Id'] = _auth.currentUser!.uid;
          needsUpdate = true;
        }

        if (needsUpdate) {
          newRelations.add(relationData);
          relationsToDelete.add(relationDoc.id);
        }
      }

      // Выполняем операции в транзакции
      await _firestore.runTransaction((transaction) async {
        // 1. Добавляем нового родственника
        transaction.set(
          _firestore
              .collection('family_trees')
              .doc(treeId)
              .collection('relatives')
              .doc(_auth.currentUser!.uid),
          newRelative.toMap(),
        );

        // 2. Удаляем старые связи и добавляем новые
        for (int i = 0; i < relationsToDelete.length; i++) {
          transaction.delete(
            _firestore.collection('family_relations').doc(relationsToDelete[i]),
          );

          transaction.set(
            _firestore.collection('family_relations').doc(),
            newRelations[i],
          );
        }

        // 3. Удаляем офлайн родственника
        transaction.delete(
          _firestore
              .collection('family_trees')
              .doc(treeId)
              .collection('relatives')
              .doc(offlineRelativeId),
        );

        // 4. Добавляем связь с отправителем запроса
        transaction.set(
          _firestore.collection('family_relations').doc(),
          {
            'treeId': treeId,
            'person1Id': senderId,
            'person2Id': _auth.currentUser!.uid,
            'relation1to2': relationType,
            'relation2to1': _getInverseRelation(relationType),
            'createdAt': FieldValue.serverTimestamp(),
          },
        );

        // 5. Обновляем статус запроса
        transaction.update(
          request.reference,
          {'status': 'accepted'},
        );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Вы заменили офлайн родственника')),
      );
    } catch (e) {
      print('Ошибка при принятии запроса: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
      _loadRequests();
    }
  }

  String _getInverseRelation(String relation) {
    switch (relation) {
      case 'parent': return 'child';
      case 'child': return 'parent';
      case 'spouse': return 'spouse';
      case 'sibling': return 'sibling';
      default: return 'other';
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Запросы на родство'),
      ),
      body: _isLoading 
          ? Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: Colors.red),
                      SizedBox(height: 16),
                      Text(
                        'Произошла ошибка',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 8),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadRequests,
                        child: Text('Повторить'),
                      ),
                    ],
                  ),
                )
              : _requests.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'Нет запросов на родство',
                            style: TextStyle(fontSize: 18),
                          ),
                          Text(
                            'Когда кто-то пригласит вас в свое дерево,\nзапросы появятся здесь',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _requests.length,
                      itemBuilder: (context, index) {
                        final request = _requests[index];
                        final senderProfile = _userProfiles[request.senderId];
                        
                        return Card(
                          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundImage: senderProfile != null && senderProfile['photoURL'] != null
                                          ? NetworkImage(senderProfile['photoURL'])
                                          : null,
                                      child: senderProfile == null || senderProfile['photoURL'] == null
                                          ? Icon(Icons.person)
                                          : null,
                                    ),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            senderProfile != null 
                                                ? senderProfile['displayName'] ?? 'Неизвестный пользователь'
                                                : 'Неизвестный пользователь',
                                            style: Theme.of(context).textTheme.titleMedium,
                                          ),
                                          Text(
                                            'Хочет добавить вас как: ${FamilyRelation.getRelationName(
                                              request.getRecipientToSender(),
                                              Gender.unknown, // Используем unknown, так как не знаем пол текущего пользователя
                                            )}',
                                            style: TextStyle(color: Colors.grey[600]),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                
                                if (request.message != null && request.message!.isNotEmpty) ...[
                                  SizedBox(height: 12),
                                  Container(
                                    padding: EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(request.message!),
                                  ),
                                ],
                                
                                SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: () => _respondToRequest(request.id, RequestStatus.rejected),
                                      child: Text('Отклонить'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.grey[700],
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    ElevatedButton(
                                      onPressed: () => _respondToRequest(request.id, RequestStatus.accepted),
                                      child: Text('Принять'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Theme.of(context).primaryColor,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
} 