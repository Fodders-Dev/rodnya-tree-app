import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../../services/auth_service.dart';
import '../../models/family_tree.dart';

class CreateTreeScreen extends StatefulWidget {
  const CreateTreeScreen({Key? key}) : super(key: key);

  @override
  _CreateTreeScreenState createState() => _CreateTreeScreenState();
}

class _CreateTreeScreenState extends State<CreateTreeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  bool _isLoading = false;
  bool _isPrivate = true; // Значение по умолчанию - приватное дерево
  
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  Future<void> _createTree() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final user = _authService.currentUser;
      if (user == null) {
        throw Exception('Пользователь не авторизован');
      }
      
      final treeId = Uuid().v4();
      final now = DateTime.now();
      
      final tree = FamilyTree(
        id: treeId,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        creatorId: user.uid,
        createdAt: now,
        updatedAt: now,
        isPrivate: _isPrivate,
        members: [user.uid],
        memberIds: [user.uid],
      );
      
      // Сохраняем дерево
      await _firestore.collection('family_trees').doc(treeId).set(tree.toMap());
      
      // Добавляем пользователя как владельца дерева
      await _firestore.collection('tree_members').doc().set({
        'treeId': treeId,
        'userId': user.uid,
        'role': 'owner',
        'addedAt': now,
        'acceptedAt': now,
      });
      
      // --- ДОБАВЛЯЕМ ОБНОВЛЕНИЕ ПРОФИЛЯ ПОЛЬЗОВАТЕЛЯ --- 
      print('Updating user profile (${user.uid}) with new tree ID ($treeId)');
      await _firestore.collection('users').doc(user.uid).update({
          'creatorOfTreeIds': FieldValue.arrayUnion([treeId]),
          // Опционально: также можно добавить в accessibleTreeIds, 
          // если создатель всегда имеет доступ
          // 'accessibleTreeIds': FieldValue.arrayUnion([treeId])
      });
      print('User profile updated successfully.');
      // --- КОНЕЦ ДОБАВЛЕНИЯ ---

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Семейное дерево создано')),
        );
        // Возвращаемся на предыдущий экран с флагом обновления
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Создать семейное дерево'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Создайте новое семейное дерево',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Добавьте информацию о вашем семейном дереве',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Название дерева',
                  hintText: 'Например: Семья Ивановых',
                  prefixIcon: Icon(Icons.family_restroom),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Введите название дерева';
                  }
                  return null;
                },
              ),
              
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Описание',
                  hintText: 'Кратко опишите ваше семейное дерево',
                  prefixIcon: Icon(Icons.description),
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
              ),
              
              const SizedBox(height: 32),
              
              Switch(
                value: _isPrivate,
                onChanged: (value) {
                  setState(() {
                    _isPrivate = value;
                  });
                },
                activeColor: Theme.of(context).primaryColor,
              ),
              Text(
                _isPrivate ? 'Приватное дерево' : 'Публичное дерево',
                style: TextStyle(
                  color: Colors.grey[700],
                ),
              ),
              
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _createTree,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: _isLoading 
                        ? const SizedBox(
                            height: 20, 
                            width: 20, 
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Создать семейное дерево'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
} 