import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../backend/backend_runtime_config.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/notification_service_interface.dart';
import '../models/app_notification_item.dart';
import '../models/family_person.dart' as rodnya_models;
import '../navigation/app_router_shared.dart';
import '../providers/tree_provider.dart';
import 'android_incoming_call_service.dart';
import 'call_coordinator_service.dart';
import 'chat_notification_settings_store.dart';
import 'browser_notification_bridge.dart';
import 'custom_api_auth_service.dart';
import 'custom_api_realtime_service.dart';
import 'rustore_service.dart';

@pragma('vm:entry-point')
void onDidReceiveBackgroundCustomApiNotificationResponse(
  NotificationResponse response,
) {
  debugPrint(
    'Custom API notification tapped in background: ${response.payload}',
  );
}

typedef ChatNotificationCallback = Future<void> Function({
  required String chatId,
  required String senderId,
  required String senderName,
  required String messageText,
  required int notificationId,
  bool playSound,
});

typedef GenericNotificationCallback = Future<void> Function({
  required String title,
  required String body,
  required int notificationId,
  String? payload,
});

typedef RemotePushTokenProvider = Future<String?> Function();

class CustomApiNotificationService implements NotificationServiceInterface {
  static const String _androidNotificationIcon = 'ic_stat_notification';

  CustomApiNotificationService._({
    required FlutterLocalNotificationsPlugin plugin,
    required SharedPreferences preferences,
    CustomApiAuthService? authService,
    BackendRuntimeConfig? runtimeConfig,
    CustomApiRealtimeService? realtimeService,
    RustoreService? rustoreService,
    http.Client? httpClient,
    Duration? pollInterval,
    RemotePushTokenProvider? remotePushTokenProvider,
    ChatNotificationCallback? onChatNotification,
    GenericNotificationCallback? onGenericNotification,
    BrowserNotificationBridge? browserNotificationBridge,
    AndroidIncomingCallService? androidIncomingCallService,
  })  : _plugin = plugin,
        _preferences = preferences,
        _authService = authService,
        _runtimeConfig = runtimeConfig,
        _realtimeService = realtimeService,
        _rustoreService = rustoreService,
        _httpClient = httpClient ?? http.Client(),
        _pollInterval = pollInterval ?? const Duration(seconds: 20),
        _remotePushTokenProvider = remotePushTokenProvider,
        _onChatNotification = onChatNotification,
        _onGenericNotification = onGenericNotification,
        _androidIncomingCallService = androidIncomingCallService,
        _browserNotificationBridge =
            browserNotificationBridge ?? createBrowserNotificationBridge();

  static const String _deliveredIdsStorageKey =
      'custom_api_delivered_notification_ids_v1';
  static const String _registeredPushTokenStorageKey =
      'custom_api_registered_push_token_v1';
  static const String _registeredRemotePushDeviceIdStorageKey =
      'custom_api_registered_remote_push_device_id_v1';
  static const String _notificationsEnabledStorageKey =
      'custom_api_notifications_enabled_v1';
  static const String _registeredBrowserPushDeviceIdStorageKey =
      'custom_api_registered_browser_push_device_id_v1';
  static const String _registeredBrowserPushTokenStorageKey =
      'custom_api_registered_browser_push_token_v1';

  static Future<CustomApiNotificationService> create({
    FlutterLocalNotificationsPlugin? plugin,
    SharedPreferences? preferences,
    CustomApiAuthService? authService,
    BackendRuntimeConfig? runtimeConfig,
    CustomApiRealtimeService? realtimeService,
    RustoreService? rustoreService,
    http.Client? httpClient,
    Duration? pollInterval,
    RemotePushTokenProvider? remotePushTokenProvider,
    ChatNotificationCallback? onChatNotification,
    GenericNotificationCallback? onGenericNotification,
    BrowserNotificationBridge? browserNotificationBridge,
    AndroidIncomingCallService? androidIncomingCallService,
  }) async {
    return CustomApiNotificationService._(
      plugin: plugin ?? FlutterLocalNotificationsPlugin(),
      preferences: preferences ?? await SharedPreferences.getInstance(),
      authService: authService,
      runtimeConfig: runtimeConfig,
      realtimeService: realtimeService,
      rustoreService: rustoreService,
      httpClient: httpClient,
      pollInterval: pollInterval,
      remotePushTokenProvider: remotePushTokenProvider,
      onChatNotification: onChatNotification,
      onGenericNotification: onGenericNotification,
      browserNotificationBridge: browserNotificationBridge,
      androidIncomingCallService: androidIncomingCallService,
    );
  }

  final FlutterLocalNotificationsPlugin _plugin;
  final SharedPreferences _preferences;
  final CustomApiAuthService? _authService;
  final BackendRuntimeConfig? _runtimeConfig;
  final CustomApiRealtimeService? _realtimeService;
  final RustoreService? _rustoreService;
  final http.Client _httpClient;
  final Duration _pollInterval;
  final RemotePushTokenProvider? _remotePushTokenProvider;
  final ChatNotificationCallback? _onChatNotification;
  final GenericNotificationCallback? _onGenericNotification;
  final AndroidIncomingCallService? _androidIncomingCallService;
  final BrowserNotificationBridge _browserNotificationBridge;
  final ChatNotificationSettingsStore _chatNotificationSettingsStore =
      const SharedPreferencesChatNotificationSettingsStore();

  bool _isInitialized = false;
  bool _notificationsEnabled = true;
  bool _androidNotificationPermissionsChecked = false;
  int _unreadNotificationsCount = 0;
  String? _pendingNavigationPayload;
  Timer? _pollingTimer;
  StreamSubscription<CustomApiRealtimeEvent>? _realtimeSubscription;
  final Set<String> _deliveredNotificationIds = <String>{};
  final StreamController<int> _unreadNotificationsCountController =
      StreamController<int>.broadcast();

  // Channel IDs mirror RodnyaNotificationChannels.kt 1:1 — same
  // entries in Android Settings whether the notification was rendered
  // by VKPNS in the background or replayed locally from Dart, so the
  // user has ONE place to mute «Активность» without losing chats or
  // calls. The native side registers them on cold-start; the Dart
  // calls below are belt-and-suspenders for the rare case where a
  // local notification fires before MainActivity has run.
  static const String _channelIdCalls = 'calls';
  static const String _channelNameCalls = 'Звонки';
  static const String _channelDescCalls = 'Входящие аудио и видеозвонки';

  static const String _channelIdChats = 'chats';
  static const String _channelNameChats = 'Сообщения';
  static const String _channelDescChats = 'Новые сообщения от родных и друзей';

  static const String _channelIdSocial = 'social';
  static const String _channelNameSocial = 'Активность';
  static const String _channelDescSocial =
      'Реакции, ответы, дни рождения и обновления дерева';

  static const String _channelIdSystem = 'system';
  static const String _channelNameSystem = 'Системные';
  static const String _channelDescSystem = 'Объявления и тихие напоминания';

  @override
  Future<void> initialize() async {
    _deliveredNotificationIds
      ..clear()
      ..addAll(_preferences.getStringList(_deliveredIdsStorageKey) ?? const []);
    _notificationsEnabled =
        _preferences.getBool(_notificationsEnabledStorageKey) ?? true;

    if (_isInitialized) {
      _isInitialized = true;
      return;
    }

    if (kIsWeb) {
      _isInitialized = true;
      return;
    }

    const initializationSettingsAndroid = AndroidInitializationSettings(
      _androidNotificationIcon,
    );
    const initializationSettingsIOS = DarwinInitializationSettings();
    const initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    // flutter_local_notifications 21.x switched the first arg to a
    // named `settings:` parameter. Same payload shape, just the
    // call site changed.
    await _plugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: _onDidReceiveNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          onDidReceiveBackgroundCustomApiNotificationResponse,
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    // createNotificationChannel is idempotent — if MainActivity has
    // already registered them via RodnyaNotificationChannels these
    // calls are no-ops. The order goes urgent → quiet so the
    // Settings screen shows them in the right hierarchy.
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelIdCalls,
        _channelNameCalls,
        description: _channelDescCalls,
        importance: Importance.high,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelIdChats,
        _channelNameChats,
        description: _channelDescChats,
        importance: Importance.high,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelIdSocial,
        _channelNameSocial,
        description: _channelDescSocial,
        importance: Importance.defaultImportance,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelIdSystem,
        _channelNameSystem,
        description: _channelDescSystem,
        importance: Importance.low,
      ),
    );
    await _ensureAndroidNotificationSurfacePermissions(
      androidPlugin: androidPlugin,
    );

    await _restoreLaunchNotificationPayload();
    _isInitialized = true;
  }

  Future<void> startForegroundSync() async {
    await initialize();
    if (_authService == null || _runtimeConfig == null) {
      return;
    }

    final hasActiveSession = await _registerPushDevicesSafely();
    if (!hasActiveSession) {
      return;
    }

    if (_realtimeService != null) {
      await _realtimeService!.connect();
      await _realtimeSubscription?.cancel();
      _realtimeSubscription = _realtimeService!.events
          .where((event) => event.isNotificationEvent)
          .listen((event) {
        final notification = event.notification;
        if (notification == null) {
          return;
        }
        unawaited(_handleRealtimeNotificationSafely(notification));
      });
    }

    _pollingTimer?.cancel();
    await refreshUnreadNotificationsCount();
    await _syncPendingNotificationsSafely();
    _pollingTimer = Timer.periodic(_pollInterval, (_) {
      unawaited(_syncPendingNotificationsSafely());
      unawaited(refreshUnreadNotificationsCount());
    });

    if (kIsWeb) {
      final initialPayload = Uri.base.queryParameters['notificationPayload'];
      if (initialPayload != null && initialPayload.isNotEmpty) {
        _schedulePayloadNavigation(initialPayload);
      }
    }

    final pendingPayload = _pendingNavigationPayload;
    if (pendingPayload != null && pendingPayload.isNotEmpty) {
      _schedulePayloadNavigation(pendingPayload);
    }
  }

  Future<void> stopForegroundSync() async {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    await _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
  }

  Future<void> _ensureAndroidNotificationSurfacePermissions({
    AndroidFlutterLocalNotificationsPlugin? androidPlugin,
  }) async {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        _androidNotificationPermissionsChecked) {
      return;
    }

    final resolvedAndroidPlugin = androidPlugin ??
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (resolvedAndroidPlugin == null) {
      return;
    }

    _androidNotificationPermissionsChecked = true;

    try {
      final notificationsEnabled =
          await resolvedAndroidPlugin.areNotificationsEnabled();
      if (notificationsEnabled != true) {
        final granted =
            await resolvedAndroidPlugin.requestNotificationsPermission();
        if (granted != true) {
          debugPrint(
            'Custom API notifications permission denied on Android',
          );
        }
      }
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to request Android notification permission: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
    }

    try {
      await resolvedAndroidPlugin.requestFullScreenIntentPermission();
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to request Android full-screen intent permission: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  /// Anything older than this is shown only in the in-app feed —
  /// never replayed as a system notification. Catches the user's
  /// «их заёбывает уведомлениями по хуйне» complaint where a fresh
  /// install pulled 20 unread items and the OS pinged 20 times in
  /// a row. The number is generous enough that a missed call from
  /// last night still buzzes when the user opens the app in the
  /// morning, but tight enough that week-old «X лайкнул вашу
  /// историю» dies quietly.
  static const Duration _maxReplayAge = Duration(hours: 24);

  /// Hard ceiling on how many local notifications we replay per
  /// foreground sync, regardless of age. Even within the 24h
  /// window, dumping 20 system notifications at once is jarring —
  /// Telegram coalesces silently past ~3-5 from the same source.
  static const int _maxReplayBatch = 5;

  Future<void> syncPendingNotifications() async {
    final authService = _authService;
    final runtimeConfig = _runtimeConfig;
    if (authService == null || runtimeConfig == null) {
      return;
    }
    final accessToken = authService.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      return;
    }

    final token = authService.accessToken;
    if (token == null || token.isEmpty) {
      return;
    }

    try {
      final response = await _httpClient.get(
        _buildUri(runtimeConfig, '/v1/notifications?status=unread&limit=20'),
        headers: _headers(token),
      );

      final payload = _decodeResponse(response);
      final rawNotifications = payload['notifications'];
      if (rawNotifications is! List<dynamic>) {
        _updateUnreadNotificationsCount(0);
        return;
      }
      _updateUnreadNotificationsCount(rawNotifications.length);

      final now = DateTime.now();
      final cutoff = now.subtract(_maxReplayAge);
      final isFirstSync = _deliveredNotificationIds.isEmpty;

      final notifications = rawNotifications
          .whereType<Map<String, dynamic>>()
          .where((notification) {
        final id = notification['id']?.toString() ?? '';
        return id.isNotEmpty && !_deliveredNotificationIds.contains(id);
      }).toList()
        ..sort((left, right) {
          // Newest first — so when we cap at _maxReplayBatch we
          // surface the most recent items, not the oldest.
          return (right['createdAt']?.toString() ?? '')
              .compareTo(left['createdAt']?.toString() ?? '');
        });

      var shown = 0;
      for (final notification in notifications) {
        final id = notification['id']!.toString();

        // Always mark as «delivered» so the next sync doesn't
        // reconsider it — even if we decide to suppress the system
        // notification this round, replaying it on the next poll
        // would just defer the flood by 20 seconds.
        _deliveredNotificationIds.add(id);

        // Calls bypass age + batch limits entirely. A missed call
        // from a few minutes ago still matters; if anything we
        // want it surfaced immediately (the native side already
        // builds a full-screen intent — this branch handles the
        // foreground/just-launched case).
        final type = notification['type']?.toString() ?? '';
        final isCall = type == 'call_invite' || type == 'call';

        if (!isCall) {
          // Skip stale items. They stay visible in /v1/notifications
          // for the in-app feed, just don't ping the OS.
          final createdAt = _parseIso(notification['createdAt']);
          if (createdAt != null && createdAt.isBefore(cutoff)) {
            continue;
          }
          // First-time sync after install / re-login: avoid
          // dumping the entire backlog on the user's lockscreen.
          // After the first batch lands, subsequent syncs only
          // see new items anyway, so this only bites on day one.
          if (isFirstSync && shown >= _maxReplayBatch) {
            continue;
          }
        }

        await _showBackendNotification(notification);
        shown += 1;
      }

      await _persistDeliveredNotificationIds();
    } on CustomApiException catch (error) {
      if (await _handleUnauthorizedError(error)) {
        _updateUnreadNotificationsCount(0);
        return;
      }
      rethrow;
    }
  }

  DateTime? _parseIso(dynamic raw) {
    if (raw == null) return null;
    final text = raw.toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text)?.toLocal();
  }

  bool get notificationsEnabled => _notificationsEnabled;
  int get unreadNotificationsCount => _unreadNotificationsCount;
  Stream<int> get unreadNotificationsCountStream =>
      _unreadNotificationsCountController.stream;

  BrowserNotificationPermissionStatus get browserPermissionStatus =>
      _browserNotificationBridge.permissionStatus;

  Future<int> refreshUnreadNotificationsCount() async {
    final authService = _authService;
    final runtimeConfig = _runtimeConfig;
    if (authService == null || runtimeConfig == null) {
      _updateUnreadNotificationsCount(0);
      return 0;
    }

    final token = authService.accessToken;
    if (token == null || token.isEmpty) {
      _updateUnreadNotificationsCount(0);
      return 0;
    }

    try {
      final response = await _httpClient.get(
        _buildUri(runtimeConfig, '/v1/notifications/unread-count'),
        headers: _headers(token),
      );
      final payload = _decodeResponse(response);
      final totalUnread = _coerceUnreadCount(payload['totalUnread']);
      _updateUnreadNotificationsCount(totalUnread);
      return totalUnread;
    } on CustomApiException catch (error) {
      if (await _handleUnauthorizedError(error)) {
        _updateUnreadNotificationsCount(0);
        return 0;
      }
      rethrow;
    }
  }

  Future<List<AppNotificationItem>> fetchUnreadNotifications({
    int limit = 50,
  }) async {
    final authService = _authService;
    final runtimeConfig = _runtimeConfig;
    if (authService == null || runtimeConfig == null) {
      return const <AppNotificationItem>[];
    }

    final token = authService.accessToken;
    if (token == null || token.isEmpty) {
      return const <AppNotificationItem>[];
    }

    try {
      final response = await _httpClient.get(
        _buildUri(
            runtimeConfig, '/v1/notifications?status=unread&limit=$limit'),
        headers: _headers(token),
      );
      final payload = _decodeResponse(response);
      final rawNotifications = payload['notifications'];
      if (rawNotifications is! List<dynamic>) {
        _updateUnreadNotificationsCount(0);
        return const <AppNotificationItem>[];
      }

      final notifications = rawNotifications
          .whereType<Map<String, dynamic>>()
          .map(AppNotificationItem.fromBackendJson)
          .toList()
        ..sort((left, right) {
          final leftCreatedAt =
              left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final rightCreatedAt =
              right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return rightCreatedAt.compareTo(leftCreatedAt);
        });
      _updateUnreadNotificationsCount(notifications.length);
      return notifications;
    } on CustomApiException catch (error) {
      if (await _handleUnauthorizedError(error)) {
        _updateUnreadNotificationsCount(0);
        return const <AppNotificationItem>[];
      }
      rethrow;
    }
  }

  Future<void> markNotificationRead(String notificationId) async {
    final authService = _authService;
    final runtimeConfig = _runtimeConfig;
    if (authService == null || runtimeConfig == null) {
      return;
    }

    final normalizedId = notificationId.trim();
    if (normalizedId.isEmpty) {
      return;
    }

    final token = authService.accessToken;
    if (token == null || token.isEmpty) {
      return;
    }

    try {
      final response = await _httpClient.post(
        _buildUri(runtimeConfig, '/v1/notifications/$normalizedId/read'),
        headers: _headers(token),
      );
      _decodeResponse(response);
      _updateUnreadNotificationsCount(_unreadNotificationsCount - 1);
    } on CustomApiException catch (error) {
      if (await _handleUnauthorizedError(error)) {
        _updateUnreadNotificationsCount(0);
        return;
      }
      rethrow;
    }
  }

  Future<void> markNotificationsRead(Iterable<String> notificationIds) async {
    final ids = notificationIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty) {
      return;
    }

    for (final id in ids) {
      await markNotificationRead(id);
    }
  }

  void openNotificationPayload(String payload) {
    if (payload.isEmpty) {
      return;
    }
    _schedulePayloadNavigation(payload);
  }

  Future<bool> setNotificationsEnabled(
    bool enabled, {
    bool promptForBrowserPermission = false,
  }) async {
    if (!enabled && kIsWeb) {
      await _unregisterBrowserPushDevice();
    }

    if (enabled && kIsWeb) {
      final permission = await _browserNotificationBridge.requestPermission(
        prompt: promptForBrowserPermission,
      );
      if (permission != BrowserNotificationPermissionStatus.granted) {
        _notificationsEnabled = false;
        await _preferences.setBool(_notificationsEnabledStorageKey, false);
        return false;
      }
    }

    _notificationsEnabled = enabled;
    await _preferences.setBool(_notificationsEnabledStorageKey, enabled);
    if (enabled && kIsWeb) {
      final hasActiveSession = await _registerPushDevicesSafely(
        registerRemoteDevice: false,
      );
      if (!hasActiveSession) {
        _notificationsEnabled = false;
        await _preferences.setBool(_notificationsEnabledStorageKey, false);
      }
    }
    return _notificationsEnabled;
  }

  @override
  Future<void> showBirthdayNotification(
    rodnya_models.FamilyPerson person,
  ) async {
    if (!_notificationsEnabled) {
      return;
    }
    if (kIsWeb) {
      await _showBrowserNotification(
        title: 'День рождения',
        body: 'Сегодня день рождения у ${person.name}',
        tag: 'birthday-${person.id}',
        payload: jsonEncode({
          'type': 'birthday',
          'personId': person.id,
        }),
      );
      return;
    }
    await initialize();

    await _plugin.show(
      id: person.id.hashCode,
      title: 'День рождения',
      body: 'Сегодня день рождения у ${person.name}',
      // Birthdays are social activity, not «right now answer me»
      // — route through the social channel so the user can mute
      // them independently from chats and calls.
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelIdSocial,
          _channelNameSocial,
          channelDescription: _channelDescSocial,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: _androidNotificationIcon,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  @override
  Future<void> showChatMessageNotification({
    required String chatId,
    required String senderId,
    required String senderName,
    required String messageText,
    required int notificationId,
    bool playSound = true,
  }) async {
    if (!_notificationsEnabled) {
      return;
    }

    final payload = jsonEncode({
      'type': 'chat',
      'chatId': chatId,
      'senderId': senderId,
      'senderName': senderName,
      'messageText': messageText,
    });

    if (kIsWeb) {
      final shortText = messageText.length > 120
          ? '${messageText.substring(0, 117)}...'
          : messageText;
      await _showBrowserNotification(
        title: senderName,
        body: shortText,
        tag: 'chat-$chatId',
        payload: payload,
      );
      return;
    }
    await initialize();

    if (_onChatNotification != null) {
      await _onChatNotification!(
        chatId: chatId,
        senderId: senderId,
        senderName: senderName,
        messageText: messageText,
        notificationId: notificationId,
        playSound: playSound,
      );
      return;
    }

    final shortText = messageText.length > 120
        ? '${messageText.substring(0, 117)}...'
        : messageText;

    await _plugin.show(
      id: notificationId,
      title: senderName,
      body: shortText,
      notificationDetails: NotificationDetails(
        // Chat messages live on the dedicated chats channel — high
        // importance so they show as a heads-up, but the user can
        // still mute it without losing call alerts.
        android: AndroidNotificationDetails(
          _channelIdChats,
          _channelNameChats,
          channelDescription: _channelDescChats,
          importance:
              playSound ? Importance.high : Importance.defaultImportance,
          priority: playSound ? Priority.high : Priority.defaultPriority,
          playSound: playSound,
          // groupKey lets Android collapse multiple notifications
          // from the SAME chat under a single header («2 новых
          // сообщения») instead of stacking them as separate cards.
          // The conversation tag also rate-limits the per-chat
          // notification id to one — newer messages update the
          // existing entry rather than push a new one.
          groupKey: 'rodnya.chat.$chatId',
          tag: 'rodnya.chat.$chatId',
          icon: _androidNotificationIcon,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: playSound,
          threadIdentifier: 'rodnya.chat.$chatId',
        ),
      ),
      payload: payload,
    );
  }

  Future<void> showIncomingCallNotification({
    required String callId,
    required String callerName,
    required bool isVideo,
    String? chatId,
  }) async {
    if (!_notificationsEnabled) {
      return;
    }

    final payload = jsonEncode({
      'type': 'call',
      'callId': callId,
    });
    final resolvedCallerName =
        callerName.trim().isEmpty ? 'Родня' : callerName.trim();
    final body = isVideo ? 'Входящий видеозвонок' : 'Входящий аудиозвонок';

    if (kIsWeb) {
      await _showBrowserNotification(
        title: resolvedCallerName,
        body: body,
        tag: 'call-$callId',
        payload: payload,
      );
      return;
    }

    await initialize();
    final nativeCallShown = await _androidIncomingCallService?.showIncomingCall(
          callId: callId,
          callerName: resolvedCallerName,
          isVideo: isVideo,
          chatId: chatId,
        ) ??
        false;
    if (nativeCallShown) {
      return;
    }

    await _plugin.show(
      id: callId.hashCode,
      title: resolvedCallerName,
      body: body,
      // Calls go on the dedicated «calls» channel — bypasses DND,
      // uses the system ringtone, and the channel-level config in
      // RodnyaNotificationChannels.kt ensures lockscreen visibility
      // and full-screen-intent permissions are respected.
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelIdCalls,
          _channelNameCalls,
          channelDescription: _channelDescCalls,
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          icon: _androidNotificationIcon,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
      payload: payload,
    );
  }

  Future<void> dismissCallNotification(String callId) async {
    if (callId.trim().isEmpty || kIsWeb) {
      return;
    }
    await initialize();
    await _androidIncomingCallService?.dismissCall(callId);
    // 21.x switched cancel to a named-arg form too.
    await _plugin.cancel(id: callId.hashCode);
  }

  Future<void> _handleRealtimeNotification(
    Map<String, dynamic> notification,
  ) async {
    final id = notification['id']?.toString() ?? '';
    if (id.isEmpty || _deliveredNotificationIds.contains(id)) {
      return;
    }

    await _showBackendNotification(notification);
    _deliveredNotificationIds.add(id);
    _updateUnreadNotificationsCount(_unreadNotificationsCount + 1);
    await _persistDeliveredNotificationIds();
  }

  void _updateUnreadNotificationsCount(int count) {
    final normalizedCount = count < 0 ? 0 : count;
    if (_unreadNotificationsCount == normalizedCount) {
      return;
    }
    _unreadNotificationsCount = normalizedCount;
    if (!_unreadNotificationsCountController.isClosed) {
      _unreadNotificationsCountController.add(normalizedCount);
    }
  }

  int _coerceUnreadCount(dynamic rawValue) {
    if (rawValue is int) {
      return rawValue;
    }
    if (rawValue is num) {
      return rawValue.toInt();
    }
    return int.tryParse(rawValue?.toString() ?? '') ?? 0;
  }

  Future<void> _showBackendNotification(
      Map<String, dynamic> notification) async {
    final id = notification['id']?.toString() ?? '';
    final type = notification['type']?.toString() ?? 'generic';
    final title = notification['title']?.toString() ?? 'Родня';
    final body = notification['body']?.toString() ?? '';
    final data = notification['data'];
    final payload = jsonEncode({
      'id': id,
      'type': type,
      'data': data is Map<String, dynamic> ? data : const <String, dynamic>{},
    });

    if (type == 'chat_message') {
      final chatData =
          data is Map<String, dynamic> ? data : const <String, dynamic>{};
      final chatId = chatData['chatId']?.toString() ?? '';
      final deliveryLevel = await _resolveChatNotificationLevel(chatId);
      if (deliveryLevel == ChatNotificationLevel.muted) {
        return;
      }
      await showChatMessageNotification(
        chatId: chatId,
        senderId: chatData['senderId']?.toString() ?? '',
        senderName: chatData['senderName']?.toString() ?? title,
        messageText: body,
        notificationId: id.hashCode,
        playSound: deliveryLevel != ChatNotificationLevel.silent,
      );
      return;
    }

    if (type == 'call_invite') {
      final callData = _asStringDynamicMap(data);
      final callId = callData['callId']?.toString() ?? '';
      if (callId.isNotEmpty) {
        await _hydrateIncomingCallCoordinator(callData);
        await showIncomingCallNotification(
          callId: callId,
          callerName: title,
          isVideo: callData['mediaMode']?.toString() == 'video',
          chatId: callData['chatId']?.toString(),
        );
        return;
      }
    }

    await _showGenericNotification(
      title: title,
      body: body,
      notificationId: id.hashCode,
      payload: payload,
      type: type,
    );
  }

  /// Pick the matching native channel ID for a notification type.
  /// Mirrors `PushGateway._androidChannelId` on the backend so a
  /// foreground replay lands on the same channel as the original
  /// VKPNS push would have.
  String _channelForType(String type) {
    switch (type) {
      case 'call_invite':
      case 'call':
        return _channelIdCalls;
      case 'chat_message':
      case 'chat':
        return _channelIdChats;
      case 'post_like':
      case 'post_comment':
      case 'comment_reply':
      case 'story_view':
      case 'story_reaction':
      case 'relative_added':
      case 'tree_invitation':
      case 'birthday':
        return _channelIdSocial;
      default:
        return _channelIdSystem;
    }
  }

  _ChannelMeta _channelMetaFor(String channelId) {
    switch (channelId) {
      case _channelIdCalls:
        return const _ChannelMeta(
          name: _channelNameCalls,
          description: _channelDescCalls,
          importance: Importance.max,
          priority: Priority.max,
        );
      case _channelIdChats:
        return const _ChannelMeta(
          name: _channelNameChats,
          description: _channelDescChats,
          importance: Importance.high,
          priority: Priority.high,
        );
      case _channelIdSocial:
        return const _ChannelMeta(
          name: _channelNameSocial,
          description: _channelDescSocial,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        );
      case _channelIdSystem:
      default:
        return const _ChannelMeta(
          name: _channelNameSystem,
          description: _channelDescSystem,
          importance: Importance.low,
          priority: Priority.low,
        );
    }
  }

  Future<void> _registerRemotePushDevice() async {
    if (kIsWeb) {
      return;
    }

    final authService = _authService;
    final runtimeConfig = _runtimeConfig;
    if (authService == null || runtimeConfig == null) {
      return;
    }
    final accessToken = authService.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      return;
    }

    final token = await _resolveRemotePushToken();
    if (token == null || token.isEmpty) {
      return;
    }

    final registeredFingerprint = _preferences.getString(
      _registeredPushTokenStorageKey,
    );
    final nextFingerprint =
        'rustore::$token::${authService.currentUserId ?? ''}';
    if (registeredFingerprint == nextFingerprint) {
      return;
    }

    // Pre-existing device for an OLD user/token combo — drop it from
    // the backend before registering the fresh one. Otherwise the
    // backend keeps stacking devices forever (account → re-login →
    // new userId or token rotation), which is both a privacy leak
    // and a wasted-quota issue: pushes meant for the previous owner
    // would still hit this physical device.
    final previousDeviceId = _preferences.getString(
      _registeredRemotePushDeviceIdStorageKey,
    );
    if (previousDeviceId != null && previousDeviceId.isNotEmpty) {
      try {
        await _deletePushDevice(previousDeviceId);
      } catch (error) {
        debugPrint('Failed to delete previous push device: $error');
      }
    }

    final response = await _httpClient.post(
      _buildUri(runtimeConfig, '/v1/push/devices'),
      headers: _headers(accessToken),
      body: jsonEncode({
        'provider': 'rustore',
        'token': token,
        'platform': defaultTargetPlatform.name,
      }),
    );
    final payload = _decodeResponse(response);
    final device = _asStringDynamicMap(payload['device']);
    final deviceId = device['id']?.toString() ?? '';
    if (deviceId.isNotEmpty) {
      await _preferences.setString(
        _registeredRemotePushDeviceIdStorageKey,
        deviceId,
      );
    }

    await _preferences.setString(
      _registeredPushTokenStorageKey,
      nextFingerprint,
    );
    final maskedToken = token.length <= 8
        ? token
        : '${token.substring(0, 4)}...${token.substring(token.length - 4)}';
    debugPrint(
      'Custom API push registration completed: '
      'provider=rustore, '
      'platform=${defaultTargetPlatform.name}, '
      'userId=${authService.currentUserId ?? ''}, '
      'token=$maskedToken',
    );
  }

  Future<bool> _registerPushDevicesSafely({
    bool registerRemoteDevice = true,
    bool registerBrowserDevice = true,
  }) async {
    try {
      if (registerRemoteDevice) {
        await _registerRemotePushDevice();
      }
      if (registerBrowserDevice) {
        await _registerBrowserPushDevice();
      }
      return true;
    } on CustomApiException catch (error) {
      if (await _handleUnauthorizedError(error)) {
        _updateUnreadNotificationsCount(0);
        return false;
      }

      debugPrint('Custom API push registration failed: ${error.message}');
      return true;
    } catch (error, stackTrace) {
      debugPrint('Custom API push registration failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return true;
    }
  }

  Future<void> _registerBrowserPushDevice() async {
    if (!kIsWeb ||
        !_notificationsEnabled ||
        !_browserNotificationBridge.isPushSupported) {
      return;
    }

    final authService = _authService;
    final runtimeConfig = _runtimeConfig;
    if (authService == null || runtimeConfig == null) {
      return;
    }

    final accessToken = authService.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      return;
    }

    if (_browserNotificationBridge.permissionStatus !=
        BrowserNotificationPermissionStatus.granted) {
      return;
    }

    final configResponse = await _httpClient.get(
      _buildUri(runtimeConfig, '/v1/push/web/config'),
      headers: _headers(accessToken),
    );
    final configPayload = _decodeResponse(configResponse);
    final isEnabled = configPayload['enabled'] == true;
    final publicKey = configPayload['publicKey']?.toString() ?? '';
    if (!isEnabled || publicKey.isEmpty) {
      return;
    }

    final subscription = await _browserNotificationBridge.subscribeToPush(
      publicKey: publicKey,
    );
    if (subscription == null || subscription.token.isEmpty) {
      return;
    }

    final previousToken =
        _preferences.getString(_registeredBrowserPushTokenStorageKey);
    final previousDeviceId =
        _preferences.getString(_registeredBrowserPushDeviceIdStorageKey);
    if (previousToken == subscription.token &&
        previousDeviceId != null &&
        previousDeviceId.isNotEmpty) {
      return;
    }

    final response = await _httpClient.post(
      _buildUri(runtimeConfig, '/v1/push/devices'),
      headers: _headers(accessToken),
      body: jsonEncode({
        'provider': 'webpush',
        'token': subscription.token,
        'platform': 'web',
      }),
    );
    final payload = _decodeResponse(response);
    final device = _asStringDynamicMap(payload['device']);
    final deviceId = device['id']?.toString() ?? '';
    if (deviceId.isEmpty) {
      return;
    }

    if (previousDeviceId != null &&
        previousDeviceId.isNotEmpty &&
        previousDeviceId != deviceId) {
      await _deletePushDevice(previousDeviceId);
    }

    await _preferences.setString(
      _registeredBrowserPushTokenStorageKey,
      subscription.token,
    );
    await _preferences.setString(
      _registeredBrowserPushDeviceIdStorageKey,
      deviceId,
    );
  }

  Future<void> _unregisterBrowserPushDevice() async {
    if (!kIsWeb) {
      return;
    }

    final deviceId =
        _preferences.getString(_registeredBrowserPushDeviceIdStorageKey);
    if (deviceId != null && deviceId.isNotEmpty) {
      await _deletePushDevice(deviceId);
    }

    await _browserNotificationBridge.unsubscribeFromPush();
    await _preferences.remove(_registeredBrowserPushDeviceIdStorageKey);
    await _preferences.remove(_registeredBrowserPushTokenStorageKey);
  }

  Future<void> _unregisterRemotePushDevice() async {
    if (kIsWeb) {
      return;
    }

    final deviceId =
        _preferences.getString(_registeredRemotePushDeviceIdStorageKey);
    if (deviceId != null && deviceId.isNotEmpty) {
      try {
        await _deletePushDevice(deviceId);
      } catch (error) {
        debugPrint(
          'Failed to delete remote push device on signOut: $error',
        );
      }
    }

    await _preferences.remove(_registeredRemotePushDeviceIdStorageKey);
    // Also drop the fingerprint so the next signin re-registers fresh
    // (registerRemotePushDevice short-circuits when the fingerprint
    // matches, which would otherwise skip registration after we just
    // deleted the backend record).
    await _preferences.remove(_registeredPushTokenStorageKey);
  }

  /// Public hook called from app startup's auth-state listener when
  /// the user signs out (or the session is force-revoked). Removes
  /// THIS device from the backend's push registry on both the mobile
  /// (RuStore) and web (VAPID) channels — without it the previous
  /// user's pushes would keep hitting the device until the token
  /// itself rotated.
  Future<void> unregisterAllPushDevicesForSignOut() async {
    await Future.wait<void>([
      _unregisterRemotePushDevice(),
      _unregisterBrowserPushDevice(),
    ]);
  }

  Future<void> _deletePushDevice(String deviceId, {String? overrideToken}) async {
    final authService = _authService;
    final runtimeConfig = _runtimeConfig;
    final accessToken = overrideToken ?? authService?.accessToken;
    if (runtimeConfig == null ||
        accessToken == null ||
        accessToken.isEmpty) {
      return;
    }

    try {
      final response = await _httpClient.delete(
        _buildUri(runtimeConfig, '/v1/push/devices/$deviceId'),
        headers: _headers(accessToken),
      );
      _decodeResponse(response);
    } on CustomApiException catch (error) {
      if (error.statusCode != 404) {
        rethrow;
      }
    }
  }

  Future<String?> _resolveRemotePushToken() async {
    if (_remotePushTokenProvider != null) {
      return _remotePushTokenProvider!();
    }

    final rustoreService = _rustoreService;
    if (rustoreService == null) {
      return null;
    }

    return rustoreService.getRustorePushToken();
  }

  Future<void> _showGenericNotification({
    required String title,
    required String body,
    required int notificationId,
    String? payload,
    String type = 'generic',
  }) async {
    if (!_notificationsEnabled) {
      return;
    }
    if (kIsWeb) {
      await _showBrowserNotification(
        title: title,
        body: body,
        tag: 'generic-$notificationId',
        payload: payload,
      );
      return;
    }
    await initialize();

    if (_onGenericNotification != null) {
      await _onGenericNotification!(
        title: title,
        body: body,
        notificationId: notificationId,
        payload: payload,
      );
      return;
    }

    final channelId = _channelForType(type);
    final meta = _channelMetaFor(channelId);
    final isQuiet = channelId == _channelIdSystem;

    await _plugin.show(
      id: notificationId,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          meta.name,
          channelDescription: meta.description,
          importance: meta.importance,
          priority: meta.priority,
          playSound: !isQuiet,
          enableVibration: !isQuiet,
          icon: _androidNotificationIcon,
          // System / social cards collapse under one app header so a
          // burst of «X лайкнул» notifications doesn't bury chats.
          groupKey: 'rodnya.$channelId',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: !isQuiet,
          interruptionLevel: isQuiet
              ? InterruptionLevel.passive
              : InterruptionLevel.active,
        ),
      ),
      payload: payload,
    );
  }

  Future<void> _showBrowserNotification({
    required String title,
    required String body,
    required String tag,
    String? payload,
  }) async {
    if (!_browserNotificationBridge.isSupported ||
        _browserNotificationBridge.permissionStatus !=
            BrowserNotificationPermissionStatus.granted) {
      return;
    }

    await _browserNotificationBridge.showNotification(
      title: title,
      body: body,
      tag: tag,
      onClick: payload == null || payload.isEmpty
          ? null
          : () => _schedulePayloadNavigation(payload),
    );
  }

  Future<ChatNotificationLevel> _resolveChatNotificationLevel(
    String chatId,
  ) async {
    final normalizedChatId = chatId.trim();
    if (normalizedChatId.isEmpty) {
      return ChatNotificationLevel.all;
    }
    final snapshot = await _chatNotificationSettingsStore.getSettings(
      SharedPreferencesChatNotificationSettingsStore.chatKey(normalizedChatId),
    );
    return snapshot?.level ?? ChatNotificationLevel.all;
  }

  Future<void> _restoreLaunchNotificationPayload() async {
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final payload = launchDetails?.notificationResponse?.payload;
    if (launchDetails?.didNotificationLaunchApp == true &&
        payload != null &&
        payload.isNotEmpty) {
      _schedulePayloadNavigation(payload);
    }
  }

  void _onDidReceiveNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) {
      return;
    }
    _schedulePayloadNavigation(payload);
  }

  void _schedulePayloadNavigation(String payload, {int attempt = 0}) {
    final navigatorContext = rootNavigatorKey.currentContext;
    if (navigatorContext == null) {
      _pendingNavigationPayload = payload;
      if (attempt >= 12) {
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future<void>.delayed(const Duration(milliseconds: 250), () {
          _schedulePayloadNavigation(payload, attempt: attempt + 1);
        });
      });
      return;
    }

    _pendingNavigationPayload = null;
    unawaited(_handlePayloadNavigation(payload, navigatorContext));
  }

  Future<void> _handlePayloadNavigation(
    String payload,
    BuildContext navigatorContext,
  ) async {
    final rootPayload = _tryDecodePayload(payload);
    final type = rootPayload['type']?.toString() ?? '';
    final data = _asStringDynamicMap(rootPayload['data']);
    final router = GoRouter.of(navigatorContext);

    if (type == 'chat' || type == 'chat_message') {
      final chatId =
          rootPayload['chatId']?.toString() ?? data['chatId']?.toString() ?? '';
      final chatType = rootPayload['chatType']?.toString() ??
          data['chatType']?.toString() ??
          'direct';
      final chatTitle = rootPayload['chatTitle']?.toString() ??
          data['chatTitle']?.toString() ??
          '';
      final senderId =
          rootPayload['senderId']?.toString() ?? data['senderId']?.toString();
      final senderName = rootPayload['senderName']?.toString() ??
          data['senderName']?.toString() ??
          'Пользователь';
      final encodedTitle =
          Uri.encodeComponent(chatTitle.isNotEmpty ? chatTitle : senderName);

      if (chatId.isNotEmpty) {
        final userQuery =
            senderId != null && senderId.isNotEmpty ? '&userId=$senderId' : '';
        _navigateOverHome(
          router,
          '/chats/view/$chatId?type=$chatType&title=$encodedTitle$userQuery',
        );
        return;
      }

      if (senderId == null || senderId.isEmpty) {
        return;
      }

      final relativeId = await _resolveRelativeIdForUser(senderId);
      if (relativeId == null || relativeId.isEmpty) {
        _navigateOverHome(router, '/user/$senderId');
        return;
      }

      final encodedName = Uri.encodeComponent(senderName);
      _navigateOverHome(
        router,
        '/chat/$senderId?relativeId=$relativeId&name=$encodedName',
      );
      return;
    }

    if (type == 'call' || type == 'call_invite') {
      if (!GetIt.I.isRegistered<CallCoordinatorService>()) {
        return;
      }
      final callCoordinator = GetIt.I<CallCoordinatorService>();
      final callId =
          rootPayload['callId']?.toString() ?? data['callId']?.toString() ?? '';
      await callCoordinator.ensureRuntimeReady();
      final call = await callCoordinator.hydrateIncomingCall(
        callId: callId,
        chatId: data['chatId']?.toString(),
      );
      if (call != null && !call.state.isTerminal) {
        await callCoordinator.activateCall(call);
      }
      return;
    }

    if (type == 'birthday') {
      final personId =
          rootPayload['personId']?.toString() ?? data['personId']?.toString();
      if (personId != null && personId.isNotEmpty) {
        _navigateOverHome(router, '/relative/details/$personId');
      }
      return;
    }

    if (type == 'relation_request') {
      final treeId =
          rootPayload['treeId']?.toString() ?? data['treeId']?.toString();
      if (treeId != null && treeId.isNotEmpty) {
        _navigateOverHome(router, '/relatives/requests/$treeId');
      }
      return;
    }

    if (type == 'tree_invitation') {
      _navigateOverHome(router, '/trees?tab=invitations');
      return;
    }

    if (type == 'merge_proposal' || type == 'identity_claim') {
      _navigateOverHome(router, '/identity/review');
      return;
    }

    if (type == 'tree_update') {
      final treeId =
          rootPayload['treeId']?.toString() ?? data['treeId']?.toString();
      if (treeId != null && treeId.isNotEmpty) {
        _navigateOverHome(router, '/tree/view/$treeId');
      }
      return;
    }

    // Post-creation fan-out notifications + reactions / comment
    // replies all live on the home feed (audience-mode shows
    // every post the viewer is the audience for, regardless of
    // selected branch). No standalone post-detail screen exists,
    // so we land the user on home and let the post show at the
    // top — the freshly-published one is by construction the
    // most recent. Worth replacing with a real `/post/:postId`
    // screen + scroll-to-post when single-post permalinks become
    // a thing, but for now this is the most useful fallback.
    if (type == 'post_created' ||
        type == 'post_reaction' ||
        type == 'comment_reaction' ||
        type == 'comment_reply') {
      router.go('/');
      return;
    }

    final treeId =
        rootPayload['treeId']?.toString() ?? data['treeId']?.toString();
    if (treeId != null && treeId.isNotEmpty) {
      _navigateOverHome(router, '/tree/view/$treeId');
    }
  }

  /// Navigate to a deep-link target while preserving a sane
  /// back-stack: home → target. Pop/swipe-back from the target
  /// returns the user to the feed instead of stranding them.
  ///
  /// User-reported: «нажимаю на уведомление о сообщении, перехожу
  /// в чат и из этого чата я никуда не могу выйти». Корень: payload
  /// navigation использовал `router.go(...)`, а GoRouter.go REPLACES
  /// весь стек — на target экране Navigator.canPop() = false, кнопка
  /// «назад» исчезает / не работает.
  ///
  /// `pushReplacement('/')` сначала ставит home как корень, затем
  /// `push(location)` кладёт target поверх. Стэк [home, target] —
  /// pop возвращает в home shell с нижней навигацией.
  ///
  /// Для cold-start (приложение запущено через тап push'а из killed
  /// state) initial location уже на '/', так что pushReplacement
  /// безопасен. Для warm-start (юзер был в app и тапнул по
  /// уведомлению в шторке) поведение тоже консистентно: текущая
  /// branch заменяется на home, далее target кладётся поверх.
  /// Идеальный «вернуться к экрану ДО клика» требовал бы хранить
  /// стек до payload navigation — это уже мульти-уровневый Navigator
  /// rework, оставляем под отдельную задачу.
  void _navigateOverHome(GoRouter router, String location) {
    // Если уже на target — ничего не делаем (повторный тап по тому же
    // уведомлению).
    final currentUri =
        router.routerDelegate.currentConfiguration.uri.toString();
    if (currentUri == location) {
      return;
    }
    final isAtRoot = currentUri == '/' || currentUri.startsWith('/?');
    if (isAtRoot) {
      // Уже на корне — просто push поверх.
      router.push(location);
      return;
    }
    // Сбрасываем стек до '/' через replace, потом кладём target
    // поверх в следующем кадре чтобы GoRouter успел обработать
    // первый переход.
    router.pushReplacement('/');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      router.push(location);
    });
  }

  Future<String?> _resolveRelativeIdForUser(String userId) async {
    if (!GetIt.I.isRegistered<FamilyTreeServiceInterface>()) {
      return null;
    }

    final familyTreeService = GetIt.I<FamilyTreeServiceInterface>();
    final treeProvider =
        GetIt.I.isRegistered<TreeProvider>() ? GetIt.I<TreeProvider>() : null;

    final candidateTreeIds = <String>[];
    final selectedTreeId = treeProvider?.selectedTreeId;
    if (selectedTreeId != null && selectedTreeId.isNotEmpty) {
      candidateTreeIds.add(selectedTreeId);
    }

    try {
      final userTrees = await familyTreeService.getUserTrees();
      for (final tree in userTrees) {
        if (!candidateTreeIds.contains(tree.id)) {
          candidateTreeIds.add(tree.id);
        }
      }
    } catch (_) {
      // Если список деревьев не загрузился, пробуем хотя бы выбранное.
    }

    for (final treeId in candidateTreeIds) {
      try {
        final relatives = await familyTreeService.getRelatives(treeId);
        for (final person in relatives) {
          if (person.userId == userId) {
            return person.id;
          }
        }
      } catch (_) {
        // Переходим к следующему дереву.
      }
    }

    return null;
  }

  Map<String, dynamic> _tryDecodePayload(String payload) {
    try {
      final decoded = jsonDecode(payload);
      return _asStringDynamicMap(decoded);
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  Map<String, dynamic> _asStringDynamicMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (key, mapValue) => MapEntry(key.toString(), mapValue),
      );
    }
    return const <String, dynamic>{};
  }

  Uri _buildUri(BackendRuntimeConfig runtimeConfig, String path) {
    final normalizedBase = runtimeConfig.apiBaseUrl.replaceAll(
      RegExp(r'/$'),
      '',
    );
    return Uri.parse('$normalizedBase$path');
  }

  Map<String, String> _headers(String token) {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    if (response.body.isEmpty) {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return const <String, dynamic>{};
      }
      throw const CustomApiException('Пустой ответ от backend');
    }

    final dynamic decoded = jsonDecode(response.body);
    final payload = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{'data': decoded};

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return payload;
    }

    throw CustomApiException(
      payload['message']?.toString() ??
          'Ошибка backend (${response.statusCode})',
      statusCode: response.statusCode,
    );
  }

  Future<void> _persistDeliveredNotificationIds() async {
    final sortedIds = _deliveredNotificationIds.toList()
      ..sort((left, right) => left.compareTo(right));
    final trimmedIds = sortedIds.length > 200
        ? sortedIds.sublist(sortedIds.length - 200)
        : sortedIds;

    _deliveredNotificationIds
      ..clear()
      ..addAll(trimmedIds);
    await _preferences.setStringList(
      _deliveredIdsStorageKey,
      trimmedIds,
    );
  }

  Future<void> _syncPendingNotificationsSafely() async {
    try {
      await syncPendingNotifications();
    } catch (error, stackTrace) {
      debugPrint('Custom API notification sync failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _handleRealtimeNotificationSafely(
    Map<String, dynamic> notification,
  ) async {
    try {
      await _handleRealtimeNotification(notification);
    } catch (error, stackTrace) {
      debugPrint('Custom API realtime notification failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _hydrateIncomingCallCoordinator(
    Map<String, dynamic> data,
  ) async {
    if (!GetIt.I.isRegistered<CallCoordinatorService>()) {
      return;
    }

    final coordinator = GetIt.I<CallCoordinatorService>();
    await coordinator.ensureRuntimeReady();
    await coordinator.hydrateIncomingCall(
      callId: data['callId']?.toString(),
      chatId: data['chatId']?.toString(),
    );
  }

  Future<bool> _handleUnauthorizedError(CustomApiException error) async {
    final normalizedMessage = error.message.toLowerCase();
    final isUnauthorized = error.statusCode == 401 ||
        error.statusCode == 403 ||
        normalizedMessage.contains('сесс') ||
        normalizedMessage.contains('unauthorized');
    if (!isUnauthorized) {
      return false;
    }

    final authService = _authService;
    if (authService != null) {
      await authService.clearSessionLocally(sessionExpired: true);
    }
    return true;
  }

  Future<void> dispose() async {
    await stopForegroundSync();
    await _unreadNotificationsCountController.close();
  }
}

/// Bundles per-channel display metadata so `_showGenericNotification`
/// can pick the right name/description/priority/importance from a
/// channel id without a giant switch at every call site. Using a
/// const-friendly class instead of records keeps us compatible with
/// the project's pre-Dart-3 analyzer config.
class _ChannelMeta {
  const _ChannelMeta({
    required this.name,
    required this.description,
    required this.importance,
    required this.priority,
  });

  final String name;
  final String description;
  final Importance importance;
  final Priority priority;
}
