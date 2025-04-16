import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/family_relation.dart';
import '../models/family_person.dart';

class SendRelationRequestScreen extends StatefulWidget {
  final String treeId;
  final String treeName;
  final FamilyPerson offlineRelative; // Офлайн родственник, который будет заменен

  const SendRelationRequestScreen({
    Key? key,
    required this.treeId,
    required this.treeName,
    required this.offlineRelative,
  }) : super(key: key);

  @override
  _SendRelationRequestScreenState createState() => _SendRelationRequestScreenState();
}

class _SendRelationRequestScreenState extends State<SendRelationRequestScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  RelationType _relationType = RelationType.other;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Отправить запрос на родство'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Заменить родственника на реального пользователя',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              Text(
                'Офлайн родственник: ${widget.offlineRelative.name}',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Email пользователя',
                  hintText: 'Введите email пользователя',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Пожалуйста, введите email';
                  }
                  if (!value.contains('@')) {
                    return 'Пожалуйста, введите корректный email';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),
              Text(
                'Кем приходится вам этот человек:',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 8),
              DropdownButtonFormField<RelationType>(
                value: _relationType,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                ),
                items: RelationType.values.map((type) {
                  return DropdownMenuItem<RelationType>(
                    value: type,
                    child: Text(_getRelationTypeText(type)),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _relationType = value!;
                  });
                },
              ),
              SizedBox(height: 24),
              _isLoading
                  ? Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _sendRequest,
                      child: Text('Отправить запрос'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(double.infinity, 50),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  String _getRelationTypeText(RelationType type) {
    switch (type) {
      case RelationType.parent: return 'Родитель';
      case RelationType.child: return 'Ребенок';
      case RelationType.spouse: return 'Супруг(а)';
      case RelationType.sibling: return 'Брат/Сестра';
      default: return 'Другое';
    }
  }

  Future<void> _sendRequest() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final FirebaseFirestore firestore = FirebaseFirestore.instance;
      final String currentUserId = FirebaseAuth.instance.currentUser!.uid;

      // Ищем пользователя по email
      final userQuery = await firestore
          .collection('users')
          .where('email', isEqualTo: _emailController.text.trim())
          .get();

      if (userQuery.docs.isEmpty) {
        throw Exception('Пользователь с таким email не найден');
      }

      final targetUserId = userQuery.docs.first.id;
      
      // Проверяем, что пользователь не отправляет запрос самому себе
      if (targetUserId == currentUserId) {
        throw Exception('Нельзя отправить запрос самому себе');
      }

      // Создаем запрос на родство
      await firestore.collection('relation_requests').add({
        'senderId': currentUserId,
        'recipientId': targetUserId,
        'treeId': widget.treeId,
        'offlineRelativeId': widget.offlineRelative.id,
        'relationType': _relationType.toString().split('.').last,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Запрос отправлен')),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
} 