// Убираем условный импорт
// import 'dart:io' if (dart.library.html) 'dart:html' as html_file;

// Добавляем стандартный импорт dart:io
import 'dart:io';
import 'dart:typed_data';
// import 'dart:html' as html; // Удаляем прямой импорт
import 'package:flutter/foundation.dart' show kIsWeb;
// Убираем import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../models/user_profile.dart';
import '../models/profile_note.dart';
// Добавляем импорты
import 'package:get_it/get_it.dart';
import 'storage_service.dart'; // Убедитесь, что путь правильный
import 'local_storage_service.dart'; // Добавляем импорт LocalStorageService
import 'sync_service.dart'; // Добавляем импорт SyncService

class ProfileService {
  // Убираем FirebaseStorage final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  // Получаем StorageService через GetIt
  final StorageService _storageService = GetIt.I<StorageService>();
  // Получаем LocalStorageService через GetIt
  final LocalStorageService _localStorage = GetIt.I<LocalStorageService>();
  // Получаем SyncService через GetIt
  final SyncService _syncService = GetIt.I<SyncService>();
  
  // Максимальный размер фото (в байтах) - 5MB
  static const int maxPhotoSize = 5 * 1024 * 1024;
  
  // Допустимые форматы файлов
  static const List<String> allowedExtensions = ['.jpg', '.jpeg', '.png'];
  
  Future<String?> uploadProfilePhoto(XFile photo) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Пользователь не авторизован');
    }
    
    try {
      // 1. Проверка расширения файла (упрощенная)
      final fileNameLower = photo.name.toLowerCase();
      final fileExtension = allowedExtensions.firstWhere(
        (ext) => fileNameLower.endsWith(ext),
        orElse: () => '', // Возвращаем пустую строку, если расширение не найдено
      );

      if (fileExtension.isEmpty) {
        throw Exception('Недопустимый формат файла. Разрешены только ${allowedExtensions.join(', ')}');
      }

      // 2. Загрузка через StorageService (только для мобильных пока)
      if (kIsWeb) {
        // TODO: Реализовать веб-загрузку через StorageService, возможно, с uploadBinary
        print("Загрузка для веб через Supabase пока не реализована в ProfileService.");
        throw UnimplementedError('Web photo upload to Supabase is not implemented yet.');
      } else {
        // Мобильная версия
        final file = File(photo.path);
        final fileSize = await file.length();

        if (fileSize > maxPhotoSize) {
          throw Exception('Размер файла превышает 5MB');
        }

        // Вызываем метод StorageService для загрузки в Supabase
        print('Вызов _storageService.uploadAvatar для пользователя ${user.uid}');
        final downloadUrl = await _storageService.uploadAvatar(user.uid, file);

        // 3. Проверка результата и обновление данных
        if (downloadUrl == null) {
          print('Ошибка: _storageService.uploadAvatar вернул null.');
          throw Exception('Не удалось загрузить фото в хранилище Supabase.');
        }

        print('Получен Supabase URL: $downloadUrl');

        // Обновляем URL в Firestore
        await _firestore.collection('users').doc(user.uid).update({
          'photoURL': downloadUrl,
        });
        print('Firestore обновлен с новым Supabase URL.');

        // Обновляем photoURL в Firebase Auth
        await user.updatePhotoURL(downloadUrl);
        print('FirebaseAuth обновлен с новым Supabase URL.');

        return downloadUrl;
      }
    } catch (e) {
      print('Ошибка при загрузке фото профиля (ProfileService): $e');
      rethrow; // Пробрасываем ошибку для обработки в UI
    }
  }

  Future<UserProfile?> getUserProfile(String userId) async {
    try {
      // 1. Пытаемся получить профиль из локального кэша
      final cachedProfile = await _localStorage.getUser(userId);
      if (cachedProfile != null) {
        print('UserProfile for $userId found in cache.');
        return cachedProfile;
      }

      // 2. Если в кэше нет, проверяем сеть
      if (!_syncService.isOnline) {
        print('UserProfile for $userId not in cache and offline. Returning null.');
        return null; // Нет в кэше и нет сети
      }

      // 3. Если есть сеть, загружаем из Firestore
      print('UserProfile for $userId not in cache, fetching from Firestore...');
      final doc = await _firestore.collection('users').doc(userId).get();

      if (doc.exists) {
        final profileFromFirestore = UserProfile.fromFirestore(doc);
        // 4. Сохраняем в кэш
        await _localStorage.saveUser(profileFromFirestore);
        print('UserProfile for $userId fetched from Firestore and saved to cache.');
        return profileFromFirestore;
      } else {
        print('UserProfile for $userId not found in Firestore.');
        return null;
      }
    } catch (e) {
      print('Error getting user profile (ProfileService): $e');
      // В случае ошибки можно попробовать вернуть данные из кэша, если они там вдруг появились
      // Или просто вернуть null
      try {
        final cachedProfile = await _localStorage.getUser(userId);
        if (cachedProfile != null) {
          print('Returning cached profile for $userId after Firestore error.');
          return cachedProfile;
        }
      } catch (cacheError) {
         print('Error reading cache after Firestore error: $cacheError');
      }
      return null;
    }
  }

  Future<void> updateUserProfile(String userId, UserProfile profile) async {
    try {
      await _firestore.collection('users').doc(userId).update(profile.toMap());
       print('User profile updated successfully.');
    } catch (e) {
      print('Error updating user profile: $e');
      rethrow; // Пробрасываем ошибку дальше
    }
  }

  // Получение потока заметок пользователя
  Stream<List<ProfileNote>> getProfileNotesStream(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('profile_notes') // Используем подколлекцию
        .orderBy('createdAt', descending: true) // Сортируем по дате создания
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ProfileNote.fromFirestore(doc as DocumentSnapshot<Map<String, dynamic>>))
          .toList();
    });
  }

  // Добавление новой заметки
  Future<void> addProfileNote(String userId, String title, String content) async {
    try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('profile_notes')
          .add({
        'title': title,
        'content': content,
        'createdAt': FieldValue.serverTimestamp(), // Используем серверное время
      });
       print('Profile note added successfully.');
    } catch (e) {
      print('Error adding profile note: $e');
      rethrow;
    }
  }

  // Обновление существующей заметки
  Future<void> updateProfileNote(String userId, ProfileNote note) async {
     try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('profile_notes')
          .doc(note.id) // Используем ID заметки
          .update(note.toMap()); // Используем toMap для обновления полей
       print('Profile note updated successfully.');
    } catch (e) {
      print('Error updating profile note: $e');
      rethrow;
    }
  }

  // Удаление заметки
  Future<void> deleteProfileNote(String userId, String noteId) async {
     try {
      await _firestore
          .collection('users')
          .doc(userId)
          .collection('profile_notes')
          .doc(noteId) // Используем ID заметки
          .delete();
       print('Profile note deleted successfully.');
    } catch (e) {
      print('Error deleting profile note: $e');
      rethrow;
    }
  }
} 