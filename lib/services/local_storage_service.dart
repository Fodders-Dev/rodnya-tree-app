import 'package:hive_flutter/hive_flutter.dart';
import 'dart:async';
import '../models/user_profile.dart';
import '../models/family_tree.dart';
import '../models/family_person.dart';
import '../models/family_relation.dart';
import '../models/chat_message.dart';
// Добавляем импорты для сгенерированных адаптеров
// import '../models/user_profile.g.dart';
// import '../models/family_tree.g.dart';
// import '../models/family_person.g.dart';
// import '../models/family_relation.g.dart';
// import '../models/chat_message.g.dart';
import 'dart:convert';

// Используем Hive для локального хранилища
class LocalStorageService {
  // Имена Hive Box'ов
  static const String _boxUsers = 'usersBox';
  static const String _boxTrees = 'treesBox';
  static const String _boxPersons = 'personsBox';
  static const String _boxRelations = 'relationsBox';
  static const String _boxMessages = 'messagesBox';

  bool _isInitialized = false;

  LocalStorageService._(); // Приватный конструктор

  // Статический метод для создания и инициализации экземпляра
  static Future<LocalStorageService> createInstance() async {
    final instance = LocalStorageService._();
    if (instance._isInitialized) {
      return instance;
    }

    // Инициализация Hive (обычно делается в main.dart, но убедимся, что она есть)
    // await Hive.initFlutter(); // Убедитесь, что это вызвано в main.dart

    // Регистрируем все адаптеры Hive здесь перед открытием боксов
    Hive.registerAdapter(UserProfileAdapter());
    Hive.registerAdapter(FamilyTreeAdapter());
    Hive.registerAdapter(FamilyPersonAdapter());
    Hive.registerAdapter(FamilyRelationAdapter());
    Hive.registerAdapter(ChatMessageAdapter());
    Hive.registerAdapter(GenderAdapter()); // Регистрируем адаптер для Gender
    Hive.registerAdapter(RelationTypeAdapter()); // Регистрируем адаптер для RelationType

    // Открываем все необходимые боксы
    await Hive.openBox<UserProfile>(_boxUsers);
    await Hive.openBox<FamilyTree>(_boxTrees);
    await Hive.openBox<FamilyPerson>(_boxPersons);
    await Hive.openBox<FamilyRelation>(_boxRelations);
    await Hive.openBox<ChatMessage>(_boxMessages);

    instance._isInitialized = true;
    print("LocalStorage: Using Hive for local data.");
    return instance;
  }

  // --- Операции с пользователями ---
  Future<void> saveUser(UserProfile user) async {
    final box = Hive.box<UserProfile>(_boxUsers);
    await box.put(user.id, user);
  }

  Future<UserProfile?> getUser(String userId) async {
    final box = Hive.box<UserProfile>(_boxUsers);
    return box.get(userId);
  }

  // --- NEW: Удаление пользователя из кэша --- 
  Future<void> deleteUser(String userId) async {
    try {
       final box = Hive.box<UserProfile>(_boxUsers);
       await box.delete(userId);
       print('LocalStorage: User $userId deleted from cache.');
    } catch (e) {
      print('LocalStorage: Error deleting user $userId: $e');
      // Решаем, нужно ли пробрасывать ошибку
    }
  }
  // --- END NEW ---

  // --- Операции с деревьями ---
  Future<void> saveTree(FamilyTree tree) async {
    final box = Hive.box<FamilyTree>(_boxTrees);
    await box.put(tree.id, tree);
  }

  // --- NEW: Сохранение списка деревьев --- 
  Future<void> saveTrees(List<FamilyTree> trees) async {
    if (trees.isEmpty) return;
    try {
      final box = Hive.box<FamilyTree>(_boxTrees);
      // Используем putAll для эффективного сохранения списка
      final Map<String, FamilyTree> treesMap = { for (var t in trees) t.id : t };
      await box.putAll(treesMap);
      print('LocalStorage: Saved ${trees.length} trees to cache.');
    } catch (e) {
       print('LocalStorage: Error saving trees: $e');
    }
  }
  // --- END NEW ---

  Future<List<FamilyTree>> getAllTrees() async {
    print('[LocalStorageService] Attempting to get all trees from box $_boxTrees...');
    final box = Hive.box<FamilyTree>(_boxTrees);
    print('[LocalStorageService] Box ${_boxTrees} opened. Contains ${box.length} keys: ${box.keys.toList()}');
    final List<FamilyTree> trees = box.values.toList();
    print('[LocalStorageService] Retrieved ${trees.length} trees from box values.');
    return trees;
  }

   Future<FamilyTree?> getTree(String treeId) async {
    final box = Hive.box<FamilyTree>(_boxTrees);
    return box.get(treeId);
  }

  // --- Операции с персонами ---
  Future<void> savePerson(FamilyPerson person) async {
    final box = Hive.box<FamilyPerson>(_boxPersons);
    await box.put(person.id, person);
  }

  Future<FamilyPerson?> getPerson(String personId) async {
    final box = Hive.box<FamilyPerson>(_boxPersons);
    return box.get(personId);
  }

  Future<List<FamilyPerson>> getPersonsByTreeId(String treeId) async {
    final box = Hive.box<FamilyPerson>(_boxPersons);
    return box.values.where((person) => person.treeId == treeId).toList();
  }

   Future<void> savePersons(List<FamilyPerson> persons) async {
     if (persons.isEmpty) return;
    final box = Hive.box<FamilyPerson>(_boxPersons);
    final Map<String, FamilyPerson> personsMap = { for (var p in persons) p.id : p };
    await box.putAll(personsMap);
  }

  // --- Операции со связями ---
  Future<void> saveRelation(FamilyRelation relation) async {
    final box = Hive.box<FamilyRelation>(_boxRelations);
    await box.put(relation.id, relation);
  }

   Future<void> saveRelations(List<FamilyRelation> relations) async {
     if (relations.isEmpty) return;
    final box = Hive.box<FamilyRelation>(_boxRelations);
    final Map<String, FamilyRelation> relationsMap = { for (var r in relations) r.id : r };
    await box.putAll(relationsMap);
  }

  Future<List<FamilyRelation>> getRelationsByTreeId(String treeId) async {
    final box = Hive.box<FamilyRelation>(_boxRelations);
    return box.values.where((relation) => relation.treeId == treeId).toList();
  }

  // --- Операции с сообщениями ---
  Future<void> saveMessage(ChatMessage message) async {
    final box = Hive.box<ChatMessage>(_boxMessages);
    await box.put(message.id, message);
  }

  Future<List<ChatMessage>> getMessagesByChatId(String chatId) async {
    final box = Hive.box<ChatMessage>(_boxMessages);
    final messages = box.values.where((msg) => msg.chatId == chatId).toList();
    // Сортировка сообщений по времени
    messages.sort((a, b) => a.getDateTime().compareTo(b.getDateTime()));
    return messages;
  }

  // --- Очистка кэша ---
  Future<void> clearCache() async {
    print("LocalStorage: Clearing all Hive boxes...");
    try {
      await Hive.box<UserProfile>(_boxUsers).clear();
      await Hive.box<FamilyTree>(_boxTrees).clear();
      await Hive.box<FamilyPerson>(_boxPersons).clear();
      await Hive.box<FamilyRelation>(_boxRelations).clear();
      await Hive.box<ChatMessage>(_boxMessages).clear();
      print("LocalStorage: All Hive boxes cleared.");
    } catch (e) {
      print("Error clearing Hive cache: $e");
      // Можно попытаться удалить файлы боксов, если clear не сработал
      // await Hive.deleteBoxFromDisk(_boxUsers);
      // ... и т.д.
    }
  }

  // --- Методы удаления для синхронизации --- 

  Future<void> deleteRelative(String personId) async {
    final box = Hive.box<FamilyPerson>(_boxPersons);
    await box.delete(personId);
    print("LocalStorage: Deleted person $personId");
  }

  Future<void> deleteRelationsByPersonId(String treeId, String personId) async {
    final box = Hive.box<FamilyRelation>(_boxRelations);
    // Находим ключи отношений для удаления
    final keysToDelete = box.keys.where((key) {
      final relation = box.get(key);
      return relation != null && 
             relation.treeId == treeId && 
             (relation.person1Id == personId || relation.person2Id == personId);
    }).toList();

    if (keysToDelete.isNotEmpty) {
      await box.deleteAll(keysToDelete);
      print("LocalStorage: Deleted ${keysToDelete.length} relations involving person $personId in tree $treeId");
    } else {
      print("LocalStorage: No relations found to delete for person $personId in tree $treeId");
    }
  }

  // Вспомогательные методы больше не нужны, т.к. Hive использует адаптеры
  // FamilyTree _treeFromLocalData(...) { ... }
  // FamilyPerson _personFromLocalData(...) { ... }
  // FamilyRelation _relationFromLocalData(...) { ... }
  // ChatMessage _messageFromLocalData(...) { ... }
  // Gender _genderFromString(...) { ... } // Перенести в адаптер Gender или модель FamilyPerson
}

// TODO: Не забудьте создать и зарегистрировать Hive адаптеры для всех моделей:
// UserProfile, FamilyTree, FamilyPerson, FamilyRelation, ChatMessage
// А также для любых Enum, например, Gender.
// Запустите build_runner для генерации адаптеров:
// flutter pub run build_runner build --delete-conflicting-outputs 