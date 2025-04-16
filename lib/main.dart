import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/profile_edit_screen.dart';
import 'screens/settings_screen.dart';
import 'theme/app_theme.dart';
import 'firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'screens/auth_screen.dart';
import 'services/auth_service.dart';
import 'screens/family_tree/create_tree_screen.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'screens/password_reset_screen.dart';
import 'screens/about_screen.dart';
import 'package:provider/provider.dart';
import 'providers/theme_provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'screens/relatives_screen.dart';
import 'screens/trees_screen.dart';
import 'screens/add_relative_screen.dart';
import 'screens/relation_requests_screen.dart';
import 'screens/send_relation_request_screen.dart';
import 'screens/complete_profile_screen.dart';
import 'dart:async';
import 'screens/tree_view_screen.dart';
import 'screens/tree_selector_screen.dart';
import 'services/crashlytics_service.dart';
import 'services/analytics_service.dart';
import 'navigation/app_router.dart';
import 'services/local_storage_service.dart';
import 'services/sync_service.dart';
import 'package:get_it/get_it.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/notification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/storage_service.dart';
import 'providers/tree_provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:workmanager/workmanager.dart';
import 'models/family_person.dart' as lineage_models;
import 'models/user_profile.dart';
import 'models/family_tree.dart';
import 'models/family_relation.dart';
import 'models/chat_message.dart';
import 'services/rustore_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_rustore_update/flutter_rustore_update.dart';
import 'package:flutter_rustore_update/pigeons/rustore.dart' as update;
import 'package:flutter_rustore_update/flutter_rustore_update.dart' show UpdateInfo;
import 'package:flutter/scheduler.dart'; // Для postFrameCallback
import 'package:firebase_dynamic_links/firebase_dynamic_links.dart';
import 'services/invitation_service.dart';
import 'services/family_service.dart';

// ---- УДАЛЯЕМ НЕПРАВИЛЬНЫЕ ИМПОРТЫ АДАПТЕРОВ ----
// import 'models/user_profile.g.dart';
// import 'models/family_tree.g.dart';
// import 'models/family_person.g.dart'; // Был добавлен ранее, но тоже неверен
// import 'models/family_relation.g.dart';
// import 'models/chat_message.g.dart';

// ---- ДОБАВЛЯЕМ ИМПОРТЫ ОСНОВНЫХ МОДЕЛЕЙ ----
// family_person.dart уже импортирован выше
// -------------------------------------

// TOP-LEVEL FUNCTION для Workmanager
@pragma('vm:entry-point') // Обязательно для релизных сборок
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    late Box<lineage_models.FamilyPerson> personsBox; // Объявляем переменную для бокса

    // --- Инициализация сервисов для фоновых задач ---
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await Hive.initFlutter();
      // Регистрируем адаптеры Hive. Теперь они должны быть доступны через импорты моделей.
      if (!Hive.isAdapterRegistered(UserProfileAdapter().typeId)) {
        Hive.registerAdapter(UserProfileAdapter());
      }
      if (!Hive.isAdapterRegistered(FamilyTreeAdapter().typeId)) {
        Hive.registerAdapter(FamilyTreeAdapter());
      }
      if (!Hive.isAdapterRegistered(lineage_models.FamilyPersonAdapter().typeId)) {
        Hive.registerAdapter(lineage_models.FamilyPersonAdapter());
      }
       if (!Hive.isAdapterRegistered(FamilyRelationAdapter().typeId)) {
        Hive.registerAdapter(FamilyRelationAdapter());
      }
       if (!Hive.isAdapterRegistered(ChatMessageAdapter().typeId)) {
        Hive.registerAdapter(ChatMessageAdapter());
      }
       if (!Hive.isAdapterRegistered(lineage_models.GenderAdapter().typeId)) {
        Hive.registerAdapter(lineage_models.GenderAdapter());
      }
       if (!Hive.isAdapterRegistered(RelationTypeAdapter().typeId)) {
        // RelationTypeAdapter определен в family_relation.dart (через part)
        Hive.registerAdapter(RelationTypeAdapter());
      }
      // Открываем бокс с персонами
      personsBox = await Hive.openBox<lineage_models.FamilyPerson>('personsBox');

      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

      // Пересоздаем и регистрируем сервисы в GetIt для этого Isolate
      final localStorageService = await LocalStorageService.createInstance();
      final notificationService = NotificationService();
      await notificationService.initialize();

      if (!GetIt.I.isRegistered<LocalStorageService>()) {
         GetIt.I.registerSingleton<LocalStorageService>(localStorageService);
      }
      if (!GetIt.I.isRegistered<NotificationService>()) {
         GetIt.I.registerSingleton<NotificationService>(notificationService);
      }
      
      // SyncService требует Firestore и Auth, инициализируем их тоже
      final firestore = FirebaseFirestore.instance;
      final auth = FirebaseAuth.instance;

      // Инициализируем SyncService только если он нужен (для syncTask)
      if (task == "syncTask") {
         if (!GetIt.I.isRegistered<SyncService>()) {
            final syncService = await SyncService.createInstance(
               localStorage: localStorageService,
               firestore: firestore,
               auth: auth,
            );
            GetIt.I.registerSingleton<SyncService>(syncService);
         }
      }
      
    } catch (e, stackTrace) {
      print("Error initializing background services: $e\n$stackTrace");
      // Возвращаем false, чтобы WorkManager попробовал позже
      return Future.value(false); 
    }
    // --- КОНЕЦ ИНИЦИАЛИЗАЦИИ ---

    // Выполнение конкретной задачи
    try {
      switch (task) {
        case "syncTask":
          final syncService = GetIt.I<SyncService>();
          // Вызываем синхронизацию. Убедитесь, что метод syncData
          // корректно работает в фоне (например, обрабатывает отсутствие UI)
          await syncService.syncData(); 
          break;
        case "birthdayCheckTask":
          if (!personsBox.isOpen) {
             print("Error: Persons box is not open!");
             return Future.value(false);
          }
          final notificationService = GetIt.I<NotificationService>();
          
          final List<lineage_models.FamilyPerson> relatives = personsBox.values.toList();
          final today = DateTime.now();
          
          for (final person in relatives) {
            if (person.birthDate != null &&
                person.birthDate!.day == today.day &&
                person.birthDate!.month == today.month) {
                  
              print("Birthday found for: ${person.name}");
              // Показываем уведомление, передавая FamilyPerson
              await notificationService.showBirthdayNotification(person);
            }
          }
          break; 
        case Workmanager.iOSBackgroundTask:
          // Добавьте сюда логику, если нужно поддерживать iOS background fetch
          break;
      }
      // Если все успешно, возвращаем true
      return Future.value(true);
    } catch (e, stackTrace) {
       print("Error executing background task $task: $e\n$stackTrace");
       // При ошибке возвращаем false, чтобы WorkManager попробовал позже
       return Future.value(false);
    }
  });
}

// Вспомогательная функция для расчета задержки до следующего запуска проверки дней рождения (9 утра)
Duration _calculateInitialDelayForBirthdayCheck() {
  final now = DateTime.now();
  // Устанавливаем время следующего запуска на 9 утра
  var nextRunTime = DateTime(now.year, now.month, now.day, 9, 0, 0);
  // Если 9 утра сегодня уже прошло, переносим на завтра
  if (now.isAfter(nextRunTime)) {
    nextRunTime = nextRunTime.add(const Duration(days: 1));
  }
  // Возвращаем разницу между следующим запуском и текущим временем
  return nextRunTime.difference(now);
}

// --- Переменная для хранения SnackBarContext --- 
// Используем GlobalKey, чтобы получить доступ к ScaffoldMessenger
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Инициализация Workmanager (только не для веба)
  if (!kIsWeb) {
    await Workmanager().initialize(
      callbackDispatcher, // Передаем созданную функцию
      isInDebugMode: true // Включаем режим отладки для логов
    );

    // Регистрация периодических задач (только не для веба)
    // Синхронизация каждые 6 часов при наличии сети
    Workmanager().registerPeriodicTask(
      "lineageSyncTask",      // Уникальное имя
      "syncTask",             // Имя задачи в callbackDispatcher
      frequency: const Duration(hours: 6),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      // existingWorkPolicy: ExistingWorkPolicy.replace, // Раскомментировать при необходимости
    );

    // Проверка дней рождения раз в день (запуск в 9 утра)
    Workmanager().registerPeriodicTask(
      "lineageBirthdayCheckTask", // Уникальное имя
      "birthdayCheckTask",        // Имя задачи в callbackDispatcher
      frequency: const Duration(days: 1),
      initialDelay: _calculateInitialDelayForBirthdayCheck(), // Задержка до первого запуска
      constraints: Constraints(
        networkType: NetworkType.not_required,
      ),
      // existingWorkPolicy: ExistingWorkPolicy.replace, // Раскомментировать при необходимости
    );
  }
  
  // Инициализируем Hive для кэширования
  await Hive.initFlutter();
  
  // Инициализируем локализацию для правильного отображения дат
  await initializeDateFormatting('ru', null);
  
  // Инициализируем Firebase с правильными опциями
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Настраиваем персистентность для web-платформы
  if (kIsWeb) {
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
  }
  
  // Инициализируем Crashlytics
  final crashlyticsService = CrashlyticsService();
  await crashlyticsService.initialize();
  
  // Инициализируем Analytics
  final analyticsService = AnalyticsService();
  
  // Останавливаем крутилку если застряли на проверке профиля
  // final timer = Timer(Duration(seconds: 10), () {
  //   if (FirebaseAuth.instance.currentUser != null) {
  //     // Если через 10 секунд мы всё ещё ожидаем проверки профиля,
  //     // перезагружаем приложение или переходим на главный экран
  //     runApp(
  //       ChangeNotifierProvider(
  //         create: (_) => ThemeProvider(),
  //         child: const MyApp(skipProfileCheck: true),
  //       ),
  //     );
  //   }
  // });
  
  // Инициализируем сервис уведомлений
  final notificationService = NotificationService();
  await notificationService.initialize();
  
  // --- Инициализация FamilyService --- 
  // Используем новый асинхронный метод для создания LocalStorageService
  final localStorageService = await LocalStorageService.createInstance();
  
  // Используем новый асинхронный метод для создания SyncService
  final syncService = await SyncService.createInstance(
    localStorage: localStorageService,
    firestore: FirebaseFirestore.instance,
    auth: FirebaseAuth.instance,
  );

  // --- Инициализация FamilyService ПОСЛЕ зависимостей ---
  final familyService = FamilyService(
      localStorageService: localStorageService,
      syncService: syncService,
  ); // Создаем экземпляр, передавая зависимости
  // --- Инициализация InvitationService --- 
  final invitationService = InvitationService();
  // ---------------------------------------
  // -----------------------------------------------------

  // Инициализация Supabase
  await Supabase.initialize(
    url: 'https://aldugysbnodrfughcawu.supabase.co', // Ваш URL
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFsZHVneXNibm9kcmZ1Z2hjYXd1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDM0MjM3OTQsImV4cCI6MjA1ODk5OTc5NH0.e_IyhyA5pv2tbi2wdCgdw5a2K0BaYxQsrxQdE459Prg', // Ваш Anon Key
  );

  // --- Инициализация AuthService --- 
  final authService = AuthService();
  // ---------------------------------

  // Регистрируем сервисы в GetIt
  GetIt.I.registerSingleton<LocalStorageService>(localStorageService);
  GetIt.I.registerSingleton<SyncService>(syncService);
  GetIt.I.registerSingleton<FamilyService>(familyService); // Регистрируем FamilyService
  GetIt.I.registerSingleton<StorageService>(StorageService());
  GetIt.I.registerSingleton<InvitationService>(invitationService); // Регистрируем InvitationService
  GetIt.I.registerSingleton<AuthService>(authService); // Регистрируем AuthService
  final rustoreService = RustoreService(); // Создаем экземпляр RuStore сервиса
  GetIt.I.registerSingleton<RustoreService>(rustoreService); // Регистрируем его

  // --- Инициализация и регистрация TreeProvider --- 
  final treeProvider = TreeProvider(); // Создаем экземпляр
  // Загружаем начальное дерево СРАЗУ, чтобы он был готов к моменту отрисовки UI
  // Важно: loadInitialTree теперь проверяет кеш, который уже должен быть готов благодаря LocalStorageService.createInstance() выше
  await treeProvider.loadInitialTree(); 
  GetIt.I.registerSingleton<TreeProvider>(treeProvider); // Регистрируем в GetIt
  // -------------------------------------------------

  // Первичная синхронизация при запуске с полным разрешением конфликтов
  // Убрали if, т.к. syncData теперь сам проверяет пользователя
  // Вызываем после регистрации, на всякий случай
  await syncService.syncData();
  
  // Load environment variables
  try {
    await dotenv.load(fileName: ".env");
    print('.env file loaded successfully.');
  } catch (e) {
    print('Error loading .env file: $e. Ensure the file exists at the project root and is listed in pubspec.yaml assets.');
    // Можно не прерывать выполнение, если переменные не критичны для старта
  }

  // --- Проверка обновлений RuStore --- 
  _checkRuStoreUpdate(rustoreService);
  // -----------------------------------
  
  // --- Инициализация слушателей RuStore Push (v6.5.0) --- 
  rustoreService.initializePushListeners();
  // ----------------------------------------------------
  
  // --- Получение RuStore Push Token (для ДЗ) --- 
  rustoreService.getRustorePushToken().then((token) {
     if (token != null) {
        print('[RuStore Push] Token received for demonstration: $token');
        // TODO: Отправить токен на ваш бэкенд, если используете RuStore Push
     }
  });
  // ---------------------------------------------
  
  // Отдельная инициализация Review Manager больше не нужна
  // await rustoreService.initializeReviewManager(); // Инициализация менеджера отзывов

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(
          create: (_) => GetIt.I<TreeProvider>(), // Используем экземпляр из GetIt
        ),
        Provider<SyncService>.value(value: syncService),
        Provider<LocalStorageService>.value(value: localStorageService),
      ],
      // Возвращаем MyApp как корневой виджет
      child: const MyApp(), 
      /* Старый вариант с оберткой MaterialApp:
      // Оборачиваем MyApp в ScaffoldMessenger
      child: MaterialApp(
        scaffoldMessengerKey: scaffoldMessengerKey, // Привязываем ключ
        home: const MyApp(),
      ),
      */
    ),
  );
}

// --- Функция для проверки обновлений и показа SnackBar --- 
void _checkRuStoreUpdate(RustoreService rustoreService) {
  rustoreService.checkForUpdate().then((update.UpdateInfo? info) {
    if (info != null && info.updateAvailability == UPDATE_AVAILABILITY_AVAILABLE) { 
      print("!!! Доступно обновление в RuStore (v8 API) !!! Info: ${info.toString()}");
      
      // Используем SchedulerBinding, чтобы показать SnackBar после построения первого кадра
      SchedulerBinding.instance.addPostFrameCallback((_) {
        scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text('Доступно обновление приложения.'),
            duration: const Duration(days: 1), // Показываем долго
            action: SnackBarAction(
              label: 'ОБНОВИТЬ',
              onPressed: () {
                _startUpdateProcess(rustoreService);
              },
            ),
          ),
        );
      });
    } else if (info != null) {
      print("RuStore update status (v8 API): ${info.updateAvailability}"); 
    } else {
      print("RuStore update check returned null or failed.");
    }
  }).catchError((error) {
     print("Error during checkForUpdate: $error");
  });
}

// --- Функция для запуска процесса обновления --- 
void _startUpdateProcess(RustoreService rustoreService) {
  // 1. Запускаем listener
  rustoreService.startUpdateListener((update.RequestResponse state) {
    if (state.installStatus == INSTALL_STATUS_DOWNLOADED) {
      print('Update downloaded! Showing confirmation SnackBar.');
      // Показываем SnackBar для подтверждения установки
      SchedulerBinding.instance.addPostFrameCallback((_) {
         scaffoldMessengerKey.currentState?.showSnackBar(
           SnackBar(
             content: Text('Обновление скачано.'),
             duration: const Duration(days: 1), // Показываем долго
             action: SnackBarAction(
               label: 'УСТАНОВИТЬ',
               onPressed: () {
                 rustoreService.completeUpdateFlexible();
               },
             ),
           ),
         );
      });
    } else if (state.installStatus == INSTALL_STATUS_FAILED) {
       print('Update download failed! Error code: ${state.installErrorCode ?? 'Неизвестно'}');
       SchedulerBinding.instance.addPostFrameCallback((_) {
         scaffoldMessengerKey.currentState?.showSnackBar(
           SnackBar(
             content: Text('Ошибка загрузки обновления: ${state.installErrorCode ?? 'Неизвестно'}'),
             duration: const Duration(seconds: 10),
           ),
         );
       });
    }
    // Можно добавить обработку других статусов (DOWNLOADING, PENDING и т.д.) для показа прогресса
  });

  // 2. Запускаем поток скачивания
  rustoreService.startUpdateFlow().then((update.DownloadResponse? response) {
    // response?.code может быть Activity.RESULT_OK или Activity.RESULT_CANCELED
    if (response != null) {
       print("Update flow (download) response code: ${response.code}");
    } else {
      print("startUpdateFlow returned null (likely skipped or immediate error).");
    }
  }).catchError((error) {
     print("Error during startUpdateFlow: $error");
  });
}

class MyApp extends StatefulWidget {
  final bool skipAuth;
  final bool skipProfileCheck;
  
  const MyApp({super.key, this.skipAuth = false, this.skipProfileCheck = false});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Создаем экземпляр маршрутизатора ОДИН РАЗ
  late final AppRouter _appRouter;
  final InvitationService _invitationService = GetIt.I<InvitationService>(); // Получаем из GetIt

  @override
  void initState() {
    super.initState();
    _appRouter = AppRouter(); // Инициализируем здесь
    _initDynamicLinks();
  }

  @override
  Widget build(BuildContext context) {
    // Возвращаем MaterialApp.router и передаем scaffoldMessengerKey и routerConfig
    return MaterialApp.router(
      scaffoldMessengerKey: scaffoldMessengerKey, // Передаем ключ сюда
      routerConfig: _appRouter.router, // Используем routerConfig
      
      title: 'Lineage',
      debugShowCheckedModeBanner: false,
      theme: Provider.of<ThemeProvider>(context).themeMode == ThemeMode.dark
          ? AppTheme.darkTheme
          : AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: Provider.of<ThemeProvider>(context).themeMode,
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: [
        const Locale('ru', 'RU'),
        const Locale('en', 'US'),
      ],
      locale: const Locale('ru', 'RU'),
      
      builder: (context, child) {
        // Builder можно оставить для других целей или убрать, если не нужен
        return child ?? const SizedBox.shrink();
      },
    );
    /* Старый неверный вариант:
    // Убираем MaterialApp отсюда, так как он теперь выше
    return Router.router(
      routerDelegate: _appRouter.router.routerDelegate,
      routeInformationParser: _appRouter.router.routeInformationParser,
      routeInformationProvider: _appRouter.router.routeInformationProvider,
    );
    */
  }

  Future<void> _initDynamicLinks() async {
    // Обработка ссылки, которая запустила приложение
    FirebaseDynamicLinks.instance.getInitialLink().then(
      (PendingDynamicLinkData? initialLink) {
        if (initialLink != null) {
          print('[DynamicLinks] Initial link received: ${initialLink.link}');
          _handleDynamicLink(initialLink.link);
        }
      },
      onError: (error) {
         print('[DynamicLinks] Error getting initial link: $error');
         // Обработка ошибки
      },
    );

    // Обработка ссылок, полученных во время работы приложения
    FirebaseDynamicLinks.instance.onLink.listen(
      (PendingDynamicLinkData dynamicLinkData) {
        print('[DynamicLinks] Link received while app is running: ${dynamicLinkData.link}');
        _handleDynamicLink(dynamicLinkData.link);
        // TODO: Возможно, нужно перенаправить пользователя на экран регистрации/логина,
        // если он еще не аутентифицирован.
      },
      onError: (error) {
        print('[DynamicLinks] onLink error: $error');
        // Обработка ошибки
      },
    );
  }

  void _handleDynamicLink(Uri deepLink) {
    // Парсим ссылку, чтобы извлечь параметры
    // Наша ссылка: https://lineage.app/invite?treeId=...&personId=...
    if (deepLink.path == '/invite') {
      final treeId = deepLink.queryParameters['treeId'];
      final personId = deepLink.queryParameters['personId'];

      if (treeId != null && treeId.isNotEmpty && personId != null && personId.isNotEmpty) {
        print('[DynamicLinks] Parsed invite: treeId=$treeId, personId=$personId');
        // Сохраняем данные в сервисе
        _invitationService.setPendingInvitation(treeId: treeId, personId: personId);
        // Ничего больше не делаем, чтобы GoRouter не пытался перейти по этой ссылке
        // --- NEW: Принудительно обновляем/переходим на текущий маршрут, чтобы GoRouter не обрабатывал /invite
        // Используем router.go, чтобы точно переопределить попытку перехода на /invite
        // Переходим на '/', так как это безопасный базовый маршрут
        // Важно: Убедись, что _appRouter.router доступен здесь
        WidgetsBinding.instance.addPostFrameCallback((_) { // Вызываем после текущего кадра
           if (mounted) { // Проверяем, что стейт еще жив
             _appRouter.router.go('/'); 
             print('[DynamicLinks] Handled /invite, navigating to /');
           }
        });
        // --- END NEW ---

        // --- NEW: Вызываем связывание, если пользователь уже авторизован --- 
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
           print('[DynamicLinks] User is already logged in. Triggering invitation check.');
           // Получаем AuthService через GetIt (убедись, что он там зарегистрирован)
           final authService = GetIt.I<AuthService>();
           // Вызываем метод проверки и связывания
           // Используем `Future.microtask` чтобы не блокировать текущий обработчик ссылки
           Future.microtask(() => authService.checkAndLinkInvitationIfNeeded(currentUser.uid));
        } else {
           print('[DynamicLinks] User is not logged in. Linking will happen after auth.');
        }
      } else {
        print('[DynamicLinks] Error parsing invite link parameters.');
      }
    } else {
      print('[DynamicLinks] Received link with unknown path: ${deepLink.path}');
    }
  }
}

// Helper function to request notification permissions
Future<void> _requestNotificationPermission() async {
  if (await Permission.notification.isDenied) {
    final status = await Permission.notification.request();
    if (status.isGranted) {
      print("Notification permission granted.");
    } else {
      print("Notification permission denied.");
      // Optionally, show a message to the user explaining why notifications are needed
    }
  } else if (await Permission.notification.isPermanentlyDenied) {
     print("Notification permission permanently denied. Opening settings...");
    // Optionally, guide the user to app settings
     openAppSettings(); // Requires permission_handler >= 6.0.0
  } else {
    print("Notification permission already granted.");
  }
}
