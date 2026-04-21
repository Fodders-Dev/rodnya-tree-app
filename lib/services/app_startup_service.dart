import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../backend/backend_provider_config.dart';
import '../backend/backend_provider_registry.dart';
import '../backend/backend_runtime_config.dart';
import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/app_startup_service_interface.dart';
import '../backend/interfaces/call_service_interface.dart';
import '../backend/interfaces/chat_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/invitation_link_service_interface.dart';
import '../backend/interfaces/notification_service_interface.dart';
import '../backend/interfaces/post_service_interface.dart';
import '../backend/interfaces/profile_service_interface.dart';
import '../backend/interfaces/safety_service_interface.dart';
import '../backend/interfaces/story_service_interface.dart';
import '../backend/interfaces/storage_service_interface.dart';
import '../models/chat_message.dart';
import '../models/family_person.dart' as rodnya_models;
import '../models/family_relation.dart';
import '../models/family_tree.dart';
import '../models/user_profile.dart';
import '../config/storefront_config.dart';
import '../providers/tree_provider.dart';
import '../startup/app_startup_pipeline.dart';
import '../startup/app_warmup_coordinator.dart';
import 'app_status_service.dart';
import 'custom_api_auth_service.dart';
import 'custom_api_call_service.dart';
import 'custom_api_chat_service.dart';
import 'custom_api_family_tree_service.dart';
import 'custom_api_notification_service.dart';
import 'custom_api_post_service.dart';
import 'custom_api_profile_service.dart';
import 'custom_api_realtime_service.dart';
import 'custom_api_safety_service.dart';
import 'custom_api_story_service.dart';
import 'custom_api_storage_service.dart';
import 'invitation_service.dart';
import 'invitation_link_service.dart';
import 'local_storage_service.dart';
import 'phone_contacts_service.dart';
import 'rustore_service.dart';
import 'call_coordinator_service.dart';

class AppStartupService implements AppStartupServiceInterface {
  AppStartupService({GetIt? getIt}) : _getIt = getIt ?? GetIt.I;

  final GetIt _getIt;

  @override
  Future<void> initializeForeground() async {
    final providerConfig = BackendProviderConfig.current;
    final runtimeConfig = BackendRuntimeConfig.current;
    final storefrontConfig = StorefrontConfig.current;

    await Hive.initFlutter();
    await initializeDateFormatting('ru', null);

    await _registerHiveAdapters();

    final localStorageService = await LocalStorageService.createInstance();
    _registerOrReplaceSingleton<LocalStorageService>(localStorageService);

    final appStatusService = AppStatusService();
    await appStatusService.initialize();
    _registerOrReplaceSingleton<AppStatusService>(appStatusService);

    final invitationService = InvitationService();
    _registerOrReplaceSingleton<InvitationService>(invitationService);
    _registerOrReplaceSingleton<InvitationLinkServiceInterface>(
      HttpInvitationLinkService(runtimeConfig: runtimeConfig),
    );
    final rustoreService = RustoreService();
    _registerOrReplaceSingleton<RustoreService>(rustoreService);
    _registerOrReplaceLazySingleton<PhoneContactsService>(
      () => PhoneContactsService(),
    );

    final customApiAuthService = await CustomApiAuthService.create(
      runtimeConfig: runtimeConfig,
      invitationService: invitationService,
      appStatusService: appStatusService,
    );
    _registerOrReplaceSingleton<CustomApiAuthService>(customApiAuthService);
    _registerOrReplaceSingleton<AuthServiceInterface>(customApiAuthService);

    // Startup should remain resilient even with a stale persisted session.
    // Live session validation and profile completeness redirects happen later
    // in the router flow, where errors don't block the whole app bootstrap.

    final customApiRealtimeService = CustomApiRealtimeService(
      authService: customApiAuthService,
      runtimeConfig: runtimeConfig,
    );
    _registerOrReplaceSingleton<CustomApiRealtimeService>(
      customApiRealtimeService,
    );

    final customApiStorageService = CustomApiStorageService(
      authService: customApiAuthService,
      runtimeConfig: runtimeConfig,
    );
    _registerOrReplaceSingleton<CustomApiStorageService>(
      customApiStorageService,
    );
    _registerOrReplaceSingleton<StorageServiceInterface>(
      customApiStorageService,
    );

    final customApiProfileService = await CustomApiProfileService.create(
      authService: customApiAuthService,
      runtimeConfig: runtimeConfig,
      storageService: customApiStorageService,
    );
    _registerOrReplaceSingleton<CustomApiProfileService>(
      customApiProfileService,
    );
    _registerOrReplaceSingleton<ProfileServiceInterface>(
      customApiProfileService,
    );

    final customApiTreeService = CustomApiFamilyTreeService(
      authService: customApiAuthService,
      runtimeConfig: runtimeConfig,
      localStorageService: localStorageService,
      profileService: customApiProfileService,
    );
    _registerOrReplaceSingleton<CustomApiFamilyTreeService>(
      customApiTreeService,
    );
    _registerOrReplaceSingleton<FamilyTreeServiceInterface>(
      customApiTreeService,
    );

    final customApiChatService = CustomApiChatService(
      authService: customApiAuthService,
      runtimeConfig: runtimeConfig,
      realtimeService: customApiRealtimeService,
      storageService: customApiStorageService,
      appStatusService: appStatusService,
    );
    _registerOrReplaceSingleton<CustomApiChatService>(customApiChatService);
    _registerOrReplaceSingleton<ChatServiceInterface>(customApiChatService);

    _registerOrReplaceLazySingleton<CustomApiCallService>(
      () => CustomApiCallService(
        authService: customApiAuthService,
        runtimeConfig: runtimeConfig,
        realtimeService: customApiRealtimeService,
      ),
    );
    _registerOrReplaceLazySingleton<CallServiceInterface>(
      () => _getIt<CustomApiCallService>(),
    );
    _registerOrReplaceLazySingleton<CallCoordinatorService>(
      () => CallCoordinatorService(
        callService: _getIt<CallServiceInterface>(),
        realtimeService: customApiRealtimeService,
        pushMessages: rustoreService.pushMessages,
      ),
    );

    final customApiNotificationService =
        await CustomApiNotificationService.create(
      authService: customApiAuthService,
      runtimeConfig: runtimeConfig,
      realtimeService: customApiRealtimeService,
      rustoreService: rustoreService,
    );
    _registerOrReplaceSingleton<CustomApiNotificationService>(
      customApiNotificationService,
    );
    _registerOrReplaceSingleton<NotificationServiceInterface>(
      customApiNotificationService,
    );

    final customApiPostService = CustomApiPostService(
      authService: customApiAuthService,
      runtimeConfig: runtimeConfig,
      storageService: customApiStorageService,
    );
    _registerOrReplaceSingleton<CustomApiPostService>(customApiPostService);
    _registerOrReplaceSingleton<PostServiceInterface>(customApiPostService);

    final customApiStoryService = CustomApiStoryService(
      authService: customApiAuthService,
      storageService: customApiStorageService,
      runtimeConfig: runtimeConfig,
    );
    _registerOrReplaceSingleton<CustomApiStoryService>(customApiStoryService);
    _registerOrReplaceSingleton<StoryServiceInterface>(customApiStoryService);

    final customApiSafetyService = CustomApiSafetyService(
      authService: customApiAuthService,
      runtimeConfig: runtimeConfig,
    );
    _registerOrReplaceSingleton<CustomApiSafetyService>(customApiSafetyService);
    _registerOrReplaceSingleton<SafetyServiceInterface>(customApiSafetyService);

    _registerOrReplaceSingleton<BackendRuntimeConfig>(runtimeConfig);

    BackendProviderRegistry.register(_getIt, config: providerConfig);

    final treeProvider = TreeProvider();
    await treeProvider.loadInitialTree();
    _registerOrReplaceSingleton<TreeProvider>(treeProvider);

    final startupPipeline = AppStartupPipeline(
      tasks: <StartupPhaseTask>[
        StartupPhaseTask(
          phase: StartupPhase.featureLazy,
          label: 'rustore-foreground',
          run: (context) => _warmupPlatformServices(
            context: context,
            rustoreService: rustoreService,
            storefrontConfig: storefrontConfig,
          ),
        ),
        StartupPhaseTask(
          phase: StartupPhase.authenticatedDeferred,
          label: 'notifications-foreground-sync',
          run: (_) => customApiNotificationService.startForegroundSync(),
        ),
      ],
    );
    _registerOrReplaceSingleton<AppStartupPipeline>(startupPipeline);
    _registerOrReplaceSingleton<AppWarmupCoordinator>(
      AppWarmupCoordinator(
        authService: customApiAuthService,
        pipeline: startupPipeline,
        notificationService: customApiNotificationService,
        realtimeService: customApiRealtimeService,
      ),
    );
  }

  Future<void> _registerHiveAdapters() async {
    if (!Hive.isAdapterRegistered(UserProfileAdapter().typeId)) {
      Hive.registerAdapter(UserProfileAdapter());
    }
    if (!Hive.isAdapterRegistered(FamilyTreeAdapter().typeId)) {
      Hive.registerAdapter(FamilyTreeAdapter());
    }
    if (!Hive.isAdapterRegistered(
      rodnya_models.FamilyPersonAdapter().typeId,
    )) {
      Hive.registerAdapter(rodnya_models.FamilyPersonAdapter());
    }
    if (!Hive.isAdapterRegistered(FamilyRelationAdapter().typeId)) {
      Hive.registerAdapter(FamilyRelationAdapter());
    }
    if (!Hive.isAdapterRegistered(ChatMessageAdapter().typeId)) {
      Hive.registerAdapter(ChatMessageAdapter());
    }
    if (!Hive.isAdapterRegistered(rodnya_models.GenderAdapter().typeId)) {
      Hive.registerAdapter(rodnya_models.GenderAdapter());
    }
    if (!Hive.isAdapterRegistered(RelationTypeAdapter().typeId)) {
      Hive.registerAdapter(RelationTypeAdapter());
    }
  }

  void _registerOrReplaceSingleton<T extends Object>(T instance) {
    if (_getIt.isRegistered<T>()) {
      _getIt.unregister<T>();
    }
    _getIt.registerSingleton<T>(instance);
  }

  void _registerOrReplaceLazySingleton<T extends Object>(
    T Function() factory,
  ) {
    if (_getIt.isRegistered<T>()) {
      _getIt.unregister<T>();
    }
    _getIt.registerLazySingleton<T>(factory);
  }

  Future<void> _warmupPlatformServices({
    required StartupPhaseContext context,
    required RustoreService rustoreService,
    required StorefrontConfig storefrontConfig,
  }) async {
    final isRuStoreRuntime = !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android &&
        storefrontConfig.isRustore;
    if (!isRuStoreRuntime) {
      return;
    }

    await rustoreService.startForegroundWarmup(enableUpdates: false);

    if (!storefrontConfig.enableRustoreUpdates) {
      return;
    }

    final updateInfo = await rustoreService.checkForUpdate();
    if (updateInfo == null ||
        updateInfo.updateAvailability != updateAvailabilityAvailable) {
      return;
    }

    rustoreService.startUpdateListener((state) {
      if (state.installStatus == installStatusDownloaded) {
        _showWarmupSnackBar(
          context.scaffoldMessengerKey,
          message: 'Обновление скачано.',
          actionLabel: 'УСТАНОВИТЬ',
          onAction: rustoreService.completeUpdateFlexible,
          duration: const Duration(days: 1),
        );
      } else if (state.installStatus == installStatusFailed) {
        _showWarmupSnackBar(
          context.scaffoldMessengerKey,
          message: 'Ошибка загрузки обновления: ${state.installErrorCode}',
          duration: const Duration(seconds: 10),
        );
      }
    });

    _showWarmupSnackBar(
      context.scaffoldMessengerKey,
      message: 'Доступно обновление приложения.',
      actionLabel: 'ОБНОВИТЬ',
      onAction: rustoreService.startUpdateFlow,
      duration: const Duration(days: 1),
    );
  }

  void _showWarmupSnackBar(
    GlobalKey<ScaffoldMessengerState>? scaffoldMessengerKey, {
    required String message,
    String? actionLabel,
    Future<void> Function()? onAction,
    Duration duration = const Duration(seconds: 6),
  }) {
    final messengerState = scaffoldMessengerKey?.currentState;
    if (messengerState == null) {
      return;
    }

    messengerState.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: duration,
        action: actionLabel == null || onAction == null
            ? null
            : SnackBarAction(
                label: actionLabel,
                onPressed: () {
                  unawaited(onAction());
                },
              ),
      ),
    );
  }
}
