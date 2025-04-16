import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

class CrashlyticsService {
  final FirebaseCrashlytics _crashlytics = FirebaseCrashlytics.instance;
  
  // Инициализация сервиса
  Future<void> initialize() async {
    if (kIsWeb) return; // Пропускаем для веб-платформы
    
    // Включаем сбор данных для Crashlytics
    await _crashlytics.setCrashlyticsCollectionEnabled(true);
    
    // Регистрируем обработчик ошибок Flutter
    FlutterError.onError = _crashlytics.recordFlutterError;
    
    // Регистрируем обработчик асинхронных ошибок
    PlatformDispatcher.instance.onError = (error, stack) {
      _crashlytics.recordError(error, stack, fatal: true);
      return true;
    };
  }
  
  // Установка идентификаторов пользователя
  Future<void> setUserIdentifier(String userId) async {
    if (kIsWeb) return;
    
    await _crashlytics.setUserIdentifier(userId);
  }
  
  // Добавление пользовательских ключей
  Future<void> setCustomKey(String key, dynamic value) async {
    if (kIsWeb) return;
    
    await _crashlytics.setCustomKey(key, value);
  }
  
  // Логирование не фатальной ошибки
  Future<void> logError(dynamic exception, StackTrace? stack, {String? reason}) async {
    if (kIsWeb) return;
    
    await _crashlytics.recordError(
      exception,
      stack,
      reason: reason,
      fatal: false,
    );
  }
  
  // Отправка логов для последующего отчета о сбое
  Future<void> log(String message) async {
    if (kIsWeb) return;
    
    await _crashlytics.log(message);
  }
  
  // Тестовый метод для проверки Crashlytics
  Future<void> testCrash() async {
    if (kIsWeb) {
      print('Тестовое падение недоступно в веб-версии');
      return;
    }
    
    // Добавляем лог перед сбоем
    await _crashlytics.log('Тестовое падение приложения начинается');
    
    // Это вызовет сбой приложения
    _crashlytics.crash();
  }
} 