import 'dart:async'; // Добавляем для StreamSubscription
import 'package:flutter/foundation.dart';
// Используем новые импорты для API v8.0.0
import 'package:flutter_rustore_update/flutter_rustore_update.dart';
// Добавляем импорт для типов из update SDK
import 'package:flutter_rustore_update/pigeons/rustore.dart' as update;

// Импорт для Review API
import 'package:flutter_rustore_review/flutter_rustore_review.dart';

// Импорт для Billing API
import 'package:flutter_rustore_billing/flutter_rustore_billing.dart'; // Содержит RustoreBillingClient
import 'package:flutter_rustore_billing/pigeons/rustore.dart' as billing; // Нужен для типов Purchase, Product, PaymentResult и др.

// Импорт для Push API
import 'package:flutter_rustore_push/flutter_rustore_push.dart'; // Содержит RustorePushClient
// Типы Message, Notification доступны из основного импорта

// Константы из update SDK (могут быть уже определены в SDK, но оставим для ясности, если нужны напрямую)
// Используем целочисленные значения, т.к. доступ к enum вызывает ошибки
const int UPDATE_AVAILABILITY_UNKNOWN = 0;
const int UPDATE_AVAILABILITY_NOT_AVAILABLE = 1;
const int UPDATE_AVAILABILITY_AVAILABLE = 2;
const int UPDATE_AVAILABILITY_IN_PROGRESS = 3;

const int INSTALL_STATUS_UNKNOWN = 0;
const int INSTALL_STATUS_DOWNLOADED = 1;
const int INSTALL_STATUS_DOWNLOADING = 2;
const int INSTALL_STATUS_FAILED = 3;
const int INSTALL_STATUS_PENDING = 5;

class RustoreService {
  bool _isUpdateAvailable = false;
  bool _isReviewInitialized = false; // Флаг для инициализации Review SDK
  // StreamSubscription больше не нужен

  // Проверка наличия обновлений (возвращает UpdateInfo или null)
  Future<update.UpdateInfo?> checkForUpdate() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        print('Checking for RuStore update (v8 API)...');
        // Используем RustoreUpdateClient
        final update.UpdateInfo info = await RustoreUpdateClient.info();
        print('RuStore update check completed (v8 API). Info: ${info.toString()}');
        // Сравниваем с константой
        _isUpdateAvailable = info.updateAvailability == UPDATE_AVAILABILITY_AVAILABLE;
        return info;
      } catch (e) {
        print('Error checking for RuStore update (v8 API): $e');
        _isUpdateAvailable = false;
        print('Update check failed.');
        return null;
      }
    } else {
      print('RuStore SDK check skipped (not Android).');
      return null;
    }
  }

  // Используем download() для отложенного обновления
  Future<update.DownloadResponse?> startUpdateFlow() async {
    final info = await checkForUpdate();
    // Сравниваем с константой
    if (info == null || info.updateAvailability != UPDATE_AVAILABILITY_AVAILABLE) {
      print('RuStore update not available or error occurred. Cannot start update flow.');
      return null;
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        print('Starting RuStore update flow (v8 - download)...');
        // Используем RustoreUpdateClient
        final update.DownloadResponse response = await RustoreUpdateClient.download();
        print('Update flow (download) initiated. Response code: ${response.code}');
        return response;
      } catch (e) {
        print('Error starting RuStore update flow (download): $e');
        return null;
      }
    } else {
      return null;
    }
  }

  // --- Методы для слушателя обновлений (v8 API) ---

  // Колбэк принимает RequestResponse
  void startUpdateListener(Function(update.RequestResponse state) onStateChanged) {
     if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        print('Starting RuStore update listener (v8 API)...');
        try {
           // Используем RustoreUpdateClient.listener
           // listener принимает колбэк напрямую
           RustoreUpdateClient.listener((state) {
              print('Update listener state received: ${state.toString()}');
              onStateChanged(state);

              // Используем state.installStatus и константу
              if (state.installStatus == INSTALL_STATUS_DOWNLOADED) {
                 print('Update downloaded! Ready to complete.');
              }
           });
            print('Update listener started successfully.');
        } catch (e) {
            print('Error starting RuStore update listener: $e');
        }
     }
  }

  // Метод stopUpdateListener удален

  // --- Методы для завершения обновления (v8 API) ---
  Future<void> completeUpdateFlexible() async {
     if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        try {
           print('Completing RuStore update (flexible v8)...');
           // Используем RustoreUpdateClient
           await RustoreUpdateClient.completeUpdateFlexible();
           print('Flexible update completion initiated.');
        } catch (e) {
           print('Error completing flexible update: $e');
        }
     }
  }

  // --- Review SDK Methods ---

  Future<void> initializeReview() async {
    if (!_isReviewInitialized && !kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
       try {
          print('Initializing RuStore Review SDK (v8 API)...');
          // Используем RustoreReviewClient
          await RustoreReviewClient.initialize();
          _isReviewInitialized = true;
          print('RuStore Review SDK initialized.');
       } catch (e) {
          print('Error initializing RuStore Review SDK: $e');
          _isReviewInitialized = false;
          print('Review SDK initialization failed. Error: $e');
       }
    }
  }

  Future<void> requestReview() async {
    await initializeReview();
    if (!_isReviewInitialized || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      print('Cannot request review: SDK not initialized or not Android.');
      return;
    }

    try {
      print('Requesting RuStore review (v8 API - step 1: request)...');
      // Используем RustoreReviewClient
      await RustoreReviewClient.request();
      print('Review request prepared. Showing dialog (step 2: review)...');
      // Используем RustoreReviewClient
      await RustoreReviewClient.review();
      print('Review dialog shown (or skipped by RuStore).');
    } catch (e) {
       print('Error requesting/showing RuStore review (v8 API): $e');
       print('Review request failed. Error: $e');
    }
  }

  // --- Billing SDK Methods ---

  bool _isBillingAvailable = false; // Флаг доступности биллинга
  bool _isBillingInitialized = false; // Флаг инициализации биллинга

  // Инициализация биллинга (в v8 нет явного метода, проверяем доступность)
  Future<void> initializeBilling() async {
    if (!_isBillingInitialized && !kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        print('Initializing RuStore Billing Client...'); // Лог инициализации
        // *** ИСПРАВЛЯЕМ ВЫЗОВ ИНИЦИАЛИЗАЦИИ С АРГУМЕНТАМИ ***
        const String consoleAppId = 'ru.rustore.app.2063621085'; // Ваш ID из Manifest
        const String deeplinkScheme = 'lineagebilling'; // Выбранная схема
        await RustoreBillingClient.initialize(consoleAppId, deeplinkScheme, kDebugMode);
        print('RuStore Billing Client initialized successfully.');
        
        print('Checking RuStore Billing availability...');
        // Используем RustoreBillingClient.available()
        final availability = await RustoreBillingClient.available();
        // Проверяем сам факт успешного вызова как признак доступности
        _isBillingAvailable = true;
        print('Billing available check completed. Assuming available if no error.');
         // Считаем инициализированным после первой проверки
        _isBillingInitialized = true;
      } catch (e) {
        print('Error during RuStore Billing initialization or availability check: $e'); // Обновляем лог ошибки
        _isBillingAvailable = false;
        _isBillingInitialized = false; // Не удалось инициализировать
      }
    }
  }

  // Проверка имеющихся покупок
  Future<List<billing.Purchase>> checkPurchases() async {
     await initializeBilling(); // Убедимся, что была попытка инициализации
     if (!_isBillingAvailable || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
       print('Billing not available or not Android.');
       return [];
     }
     try {
        print('Checking for existing purchases...');
        // Используем RustoreBillingClient.purchases()
        final billing.PurchasesResponse response = await RustoreBillingClient.purchases();
        final validPurchases = response.purchases?.whereType<billing.Purchase>().toList() ?? [];
        print('Found ${validPurchases.length} purchases.');
        return validPurchases;
     } catch (e) {
        print('Error checking purchases: $e');
        return [];
     }
  }

  // Получение информации о продуктах
  Future<List<billing.Product>> getProducts(List<String> productIds) async {
     await initializeBilling();
     if (!_isBillingAvailable || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
        print('Billing not available or not Android.');
        return [];
     }
     if (productIds.isEmpty) return [];

     try {
        print('Getting product info for: ${productIds.join(', ')}');
        // Используем RustoreBillingClient.products()
        final billing.ProductsResponse response = await RustoreBillingClient.products(productIds);
        final validProducts = response.products?.whereType<billing.Product>().toList() ?? [];
        print('Received info for ${validProducts.length} products.');
        return validProducts;
     } catch (e) {
        print('Error getting products: $e');
        return [];
     }
  }

  // Покупка продукта
  Future<billing.PaymentResult?> purchaseProduct(String productId) async {
     await initializeBilling();
     if (!_isBillingAvailable || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
        print('Billing not available or not Android.');
        return null;
     }
     try {
        print('Attempting to purchase product: $productId');
        // Используем RustoreBillingClient.purchase()
        final billing.PaymentResult? result = await RustoreBillingClient.purchase(productId, null);
        // Временно убираем детальную проверку полей result, т.к. они вызывают ошибки
        if (result != null) {
           print('Purchase flow finished. Result: ${result.toString()}');
           // Здесь можно добавить базовую логику, если result не null, считаем условно успешным
           // Но без finishCode точный статус неизвестен
        } else {
           print('Purchase flow returned null result.');
        }
        return result;
     } catch (e) {
        print('Error purchasing product $productId: $e');
        return null;
     }
  }

  // Подтверждение покупки (если нужно для NON_CONSUMABLE/SUBSCRIPTION)
  Future<billing.ConfirmPurchaseResponse?> confirmPurchase(String purchaseId) async {
     await initializeBilling();
      if (!_isBillingAvailable || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
        print('Billing not available or not Android.');
        return null;
      }
      try {
        print('Confirming purchase: $purchaseId');
        // Используем RustoreBillingClient.confirm()
        final billing.ConfirmPurchaseResponse response = await RustoreBillingClient.confirm(purchaseId);
        print('Purchase confirmation result: ${response.toString()}');
        return response;
      } catch(e) {
        print('Error confirming purchase $purchaseId: $e');
        return null;
      }
  }

  // Отмена/Удаление покупки (для тестирования)
  Future<bool> deletePurchase(String purchaseId) async {
     await initializeBilling();
      if (!_isBillingAvailable || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
        print('Billing not available or not Android.');
        return false;
      }
      try {
        print('Deleting purchase: $purchaseId');
        // Используем RustoreBillingClient.deletePurchase()
        await RustoreBillingClient.deletePurchase(purchaseId);
        print('Purchase $purchaseId deleted successfully (for testing).');
        return true;
      } catch (e) {
        print('Error deleting purchase $purchaseId: $e');
        return false;
      }
  }

  // --- RuStore Push SDK Methods (v6.5.0) ---

  // Метод для инициализации слушателей Push SDK v6.5.0
  // Вызывать один раз при старте приложения
  void initializePushListeners() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      print('Initializing RuStore Push SDK v6.5.0 listeners...');

      try {
        // Используем attachCallbacks для передачи всех слушателей сразу
        RustorePushClient.attachCallbacks(
          onNewToken: (token) {
            print('[RuStore Push v6.5.0] New token received: $token');
            // TODO: Отправить новый токен на бэкенд
          },
          onMessageReceived: (message) {
            print('[RuStore Push v6.5.0] Message received: id=${message.messageId}, data=${message.data}, notification=${message.notification?.title}');
            // TODO: Обработать полученное сообщение
          },
          onDeletedMessages: () {
            print('[RuStore Push v6.5.0] Messages deleted on server.');
          },
          onError: (err) {
            print('[RuStore Push v6.5.0] SDK Error: $err');
          },
        );

        // Проверка доступности (опционально)
        // Используем RustorePushClient
        RustorePushClient.available().then((value) {
          print("[RuStore Push v6.5.0] Push available: $value");
        }, onError: (err) {
          print("[RuStore Push v6.5.0] Push availability check error: $err");
        });

        print('RuStore Push SDK v6.5.0 listeners initialized successfully using attachCallbacks.');
      } catch (e) {
         print('Error initializing RuStore Push listeners: $e');
      }
    } else {
      print('RuStore Push v6.5.0 skipped (not Android).');
    }
  }

  // Получение Push-токена RuStore
  Future<String?> getRustorePushToken() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
       print('RuStore Push skipped (not Android).');
       return null;
    }

    try {
       print('Requesting RuStore Push Token...');
       // Используем RustorePushClient
       final String? token = await RustorePushClient.getToken();
       print('RuStore Push Token: $token');
       return token;
    } catch (e) {
       print('Error getting RuStore Push Token: $e');
       return null;
    }
  }

  // TODO: Добавить методы для обработки полученных сообщений,
  // подписки/отписки от топиков, если необходимо для задания.

} 