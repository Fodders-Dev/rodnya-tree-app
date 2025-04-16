import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart'; // Импортируем Provider
import 'dart:async'; // Для StreamSubscription
import 'dart:math'; // Для Random
import 'package:firebase_crashlytics/firebase_crashlytics.dart'; // Импорт Crashlytics
import 'package:get_it/get_it.dart';

import '../models/family_person.dart';
import '../models/family_relation.dart';
import '../services/family_service.dart';
import '../widgets/interactive_family_tree.dart';
import '../providers/tree_provider.dart'; // Импортируем TreeProvider
import 'package:go_router/go_router.dart'; // Для навигации
import '../models/user_profile.dart';
import '../widgets/interactive_family_tree.dart';
import 'add_relative_screen.dart';
import 'dart:math';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'relative_details_screen.dart';

class SectionTitle extends StatelessWidget {
  final String title;
  
  const SectionTitle({Key? key, required this.title}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).primaryColor,
        ),
      ),
    );
  }
}

class TreeViewScreen extends StatefulWidget {
  // Убираем параметры treeId и treeName из конструктора
  // final String treeId;
  // final String treeName;

  const TreeViewScreen({ Key? key /* required this.treeId, required this.treeName */ }) : super(key: key);

  @override
  _TreeViewScreenState createState() => _TreeViewScreenState();
}

class _TreeViewScreenState extends State<TreeViewScreen> {
  final FamilyService _familyService = GetIt.I<FamilyService>();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseCrashlytics _crashlytics = FirebaseCrashlytics.instance;
  
  // Map<String, dynamic> _graphData = {'nodes': [], 'edges': []}; // Больше не нужно
  bool _isLoading = true;
  String _errorMessage = '';
  bool _isEditMode = false; // <<< Добавляем состояние режима редактирования
  TreeProvider? _treeProviderInstance; // Храним экземпляр
  String? _currentTreeId;
  // <<< НОВОЕ СОСТОЯНИЕ: Флаг, добавлен ли текущий пользователь в дерево >>>
  bool _currentUserIsInTree = true; // Изначально true, пока не проверили
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _treeProviderInstance = Provider.of<TreeProvider>(context, listen: false);
      _treeProviderInstance!.addListener(_handleTreeChange); // Подписываемся
      _currentTreeId = _treeProviderInstance!.selectedTreeId;
      if (_currentTreeId != null) {
        _loadData(_currentTreeId!);
      } else {
        setState(() { _isLoading = false; });
      }
    });
  }
  
  @override
  void dispose() {
    _treeProviderInstance?.removeListener(_handleTreeChange); // Отписываемся
    super.dispose();
  }
  
  // Метод-обработчик изменений
  void _handleTreeChange() {
     if (!mounted) return;
     final newTreeId = _treeProviderInstance?.selectedTreeId;
     if (_currentTreeId != newTreeId) {
       print('TreeView: Обнаружено изменение дерева с $_currentTreeId на $newTreeId');
       _currentTreeId = newTreeId;
       if (_currentTreeId != null) {
         _loadData(_currentTreeId!); 
       } else {
         setState(() {
           _isLoading = false;
           _errorMessage = '';
         });
       }
     }
  }

  // Метод загрузки данных, теперь принимает treeId
  Future<void> _loadData(String treeId) async {
    if (!mounted) return;
    print('TreeView: Загрузка данных для дерева $treeId');
      setState(() {
        _isLoading = true;
      _errorMessage = '';
      // Сбрасываем флаг перед проверкой
      _currentUserIsInTree = true; 
    });
    
    try {
      final user = _auth.currentUser;
      if (user == null) {
        context.go('/login');
        return;
      }
      
      // Загружаем родственников и связи
      List<FamilyPerson> relatives = await _familyService.getRelatives(treeId);
      List<FamilyRelation> relations = await _familyService.getRelations(treeId);
      print('Загружено родственников: ${relatives.length}, связей: ${relations.length}');

      if (!mounted) return;

      if (relatives.isEmpty) {
         print('Дерево $treeId пустое.');
         setState(() {
            _isLoading = false;
            _errorMessage = 'В этом дереве еще нет людей.';
         });
         return;
      }

      // <<< НОВАЯ ПРОВЕРКА: Есть ли текущий пользователь в дереве >>>
      bool userInTree = await _familyService.isCurrentUserInTree(treeId);
      if (!mounted) return;
      setState(() {
        _currentUserIsInTree = userInTree;
        print('Текущий пользователь ${user?.uid} ${_currentUserIsInTree ? "" : "НЕ "}найден в дереве $treeId');
      });
      // <<< КОНЕЦ ПРОВЕРКИ >>>

      // Собираем данные для peopleData (добавляем userProfile, если он есть)
      // TODO: Оптимизировать загрузку профилей, если это будет тормозить
      List<Map<String, dynamic>> peopleData = [];
      for (var person in relatives) {
         // Попытка загрузить UserProfile, если есть userId
         UserProfile? userProfile;
         if (person.userId != null) {
            // Здесь нужен ProfileService, но чтобы не усложнять, пока пропустим
            // userProfile = await _profileService.getUserProfile(person.userId!);
         }
         peopleData.add({
           'person': person,
           'userProfile': userProfile, // Будет null, если профиль не загружен
         });
      }

      // Сохраняем данные в состоянии для передачи в виджет
      if (mounted) {
        setState(() {
          // Сохраняем исходные данные, а не построенный граф
          _relativesData = peopleData; 
          _relationsData = relations; 
          _isLoading = false;
        });
      }
    } catch (e, s) {
      print('Ошибка загрузки данных дерева $treeId: $e\\n$s');
      if (mounted) {
         setState(() {
           _isLoading = false;
           _errorMessage = 'Не удалось загрузить данные дерева.';
         });
       }
       _crashlytics.recordError(e, s, reason: 'TreeViewLoadError');
    }
  }

  // Добавляем переменные состояния для хранения данных
  List<Map<String, dynamic>> _relativesData = [];
  List<FamilyRelation> _relationsData = [];

  @override
  Widget build(BuildContext context) {
    // Получаем TreeProvider, слушаем изменения
    final treeProvider = Provider.of<TreeProvider>(context);
    final selectedTreeId = treeProvider.selectedTreeId;
    final selectedTreeName = treeProvider.selectedTreeName ?? 'Семейное дерево'; // Используем имя из провайдера

    // Если дерево не выбрано, показываем заглушку
    if (selectedTreeId == null) {
      return Scaffold(
         appBar: AppBar(
           title: Text('Семейное дерево'),
           leading: context.canPop() ? IconButton(icon: Icon(Icons.arrow_back), onPressed: () => context.pop()) : null,
           actions: [
             IconButton(
               icon: Icon(Icons.account_tree_outlined),
               tooltip: 'Выбрать дерево',
               onPressed: () => context.push('/tree'), // Переход на выбор дерева
             ),
           ],
         ),
         body: Center(
           child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline, size: 60, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Дерево не выбрано',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Выберите дерево на предыдущем экране или в меню',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
               SizedBox(height: 20),
               ElevatedButton.icon(
                 icon: Icon(Icons.list_alt),
                 label: Text('К списку деревьев'),
                 onPressed: () => context.push('/tree'), // Переход на выбор
               ),
            ],
           ),
         ),
      );
    }

    // Основной Scaffold, когда дерево выбрано
    return Scaffold(
      appBar: AppBar(
        title: Text(selectedTreeName), // Используем имя дерева из провайдера
        leading: context.canPop() ? IconButton(icon: Icon(Icons.arrow_back), onPressed: () => context.pop()) : null,
        actions: [
           IconButton(
             icon: Icon(Icons.account_tree_outlined),
             tooltip: 'Выбрать другое дерево',
             onPressed: () => context.push('/tree'), // Переход на выбор дерева
           ),
          // <<< Добавляем кнопку редактирования >>>
           IconButton(
            icon: Icon(_isEditMode ? Icons.edit_off_outlined : Icons.edit_outlined),
             tooltip: _isEditMode ? 'Выйти из режима редактирования' : 'Редактировать дерево',
             onPressed: () {
              if (!mounted) return;
                 setState(() {
                   _isEditMode = !_isEditMode;
                 });
            },
          ),
          // Можно добавить другие кнопки, например, переключение режима отображения
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center( 
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(_errorMessage, textAlign: TextAlign.center),
                  ))
              : InteractiveFamilyTree(
                  // Передаем правильные данные
                  peopleData: _relativesData,
                  relations: _relationsData, 
                  // Передаем коллбэк для нажатия на узел
                  onPersonTap: (person) {
                    print('Нажатие на узел: ${person.name} (${person.id})'); 
                    // Переход на НОВЫЙ экран деталей родственника
                    context.push('/relative/details/${person.id}'); 
                  },
                  // === ВКЛЮЧАЕМ РЕЖИМ РЕДАКТИРОВАНИЯ ===
                  isEditMode: _isEditMode, // <<< Передаем состояние
                  // Передаем коллбэк для нажатия на кнопки "+"
                  onAddRelativeTapWithType: _handleAddRelativeFromTree, 
                  // <<< НОВЫЙ ПАРАМЕТР: Передаем флаг наличия пользователя в дереве >>>
                  currentUserIsInTree: _currentUserIsInTree,
                  // <<< НОВЫЙ ПАРАМЕТР: Передаем коллбэк для добавления себя >>>
                  onAddSelfTapWithType: _handleAddSelfFromTree,
                ),
      // Можно вернуть кнопку добавления, если она нужна
      // floatingActionButton: _isLoading || selectedTreeId == null ? null : FloatingActionButton(
      //   onPressed: () {
      //     // Переход на добавление родственника для ТЕКУЩЕГО дерева
      //     context.push('/relatives/add/$selectedTreeId');
      //   },
      //   tooltip: 'Добавить родственника',
      //   child: Icon(Icons.add),
      // ),
    );
  }

  // === НОВЫЙ МЕТОД-КОЛЛБЭК для InteractiveFamilyTree ===
  void _handleAddRelativeFromTree(FamilyPerson person, RelationType type) {
    if (_currentTreeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text('Ошибка: Не удается определить текущее дерево.')),
       );
       return;
    }
    print('Добавление родственника типа $type к ${person.name} (${person.id}) в дереве $_currentTreeId');
    
    // Переходим на экран добавления, передавая контекст
    // AddRelativeScreen должен будет обработать эти параметры в 'extra'
    context.push(
      '/relatives/add/$_currentTreeId', 
      extra: {
        'contextPersonId': person.id, // К кому добавляем
        'relationType': type,      // Какого типа родственника добавляем (относительно contextPersonId)
      }
    ).then((result) {
       // Опционально: перезагрузить данные дерева, если кто-то был добавлен
       if (result == true && mounted) {
         print('Возврат с экрана добавления (из дерева), перезагрузка...');
          // Возможно, стоит перезагрузить только если реально что-то изменилось,
          // но для простоты пока перезагружаем всегда.
         _loadData(_currentTreeId!); 
       }
    });
  }

  // <<< НОВЫЙ МЕТОД-КОЛЛБЭК: Обработка добавления себя из дерева >>>
  Future<void> _handleAddSelfFromTree(FamilyPerson targetPerson, RelationType relationType) async {
    if (_currentTreeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text('Ошибка: Не удается определить текущее дерево.')),
       );
       return;
    }
    
    final user = _auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text('Ошибка: Пользователь не авторизован.')),
       );
       context.go('/login'); // Перенаправляем на логин
       return;
    }

    // Показываем индикатор загрузки
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text("Добавляем вас в дерево..."),
              ],
            ),
          ),
        );
      },
    );

    try {
      print('Добавление ТЕКУЩЕГО ПОЛЬЗОВАТЕЛЯ (${user.uid}) типа $relationType к ${targetPerson.name} (${targetPerson.id}) в дереве $_currentTreeId');
      
      // Вызываем новый метод сервиса
      await _familyService.addCurrentUserToTree(
        treeId: _currentTreeId!,
        targetPersonId: targetPerson.id,
        relationType: relationType,
      );

      // Закрываем диалог загрузки
      if (mounted) Navigator.pop(context); 

      ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text('Вы успешно добавлены в дерево!'), duration: Duration(seconds: 2)),
       );
      
      // Обновляем данные дерева, чтобы отобразить изменения и скрыть кнопку
      if (mounted) {
         print('Перезагрузка дерева после добавления себя...');
         // Устанавливаем флаг локально, чтобы кнопка сразу пропала
         setState(() {
           _currentUserIsInTree = true; 
         });
         // Запускаем полную перезагрузку данных
         await _loadData(_currentTreeId!); 
      }

    } catch (e, s) {
      // Закрываем диалог загрузки в случае ошибки
      if (mounted) Navigator.pop(context); 

      print('Ошибка при добавлении себя в дерево: $e\\n$s');
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Произошла ошибка: ${e.toString()}'), duration: Duration(seconds: 5)),
         );
       }
       _crashlytics.recordError(e, s, reason: 'handleAddSelfFromTreeFailed');
    }
  }
  // =============================================================
}