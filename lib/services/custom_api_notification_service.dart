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
import '../backend/interfaces/relatives_cache_capable_family_tree_service.dart';
import '../models/app_notification_item.dart';
import '../models/family_person.dart' as rodnya_models;
import '../navigation/app_router_shared.dart';
import '../providers/tree_provider.dart';
import '../utils/relative_details_route.dart';
import '../utils/safe_json_decode.dart';
import '../utils/startup_trace.dart';
import 'active_chat_tracker.dart';
import 'android_incoming_call_service.dart';
import 'call_coordinator_service.dart';
import 'chat_notification_settings_store.dart';
import 'browser_notification_bridge.dart';
import 'custom_api_auth_service.dart';
import 'custom_api_realtime_service.dart';
import 'posts_refresh_coordinator.dart';
import 'rustore_service.dart';
import 'tree_refresh_coordinator.dart';

part 'notifications/custom_api_notification_base.dart';
part 'notifications/custom_api_notification_push_mixin.dart';
part 'notifications/custom_api_notification_local_mixin.dart';
part 'notifications/custom_api_notification_feed_mixin.dart';

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

const String _androidNotificationIcon = 'ic_stat_notification';

const String _deliveredIdsStorageKey =
    'custom_api_delivered_notification_ids_v1';

const String _registeredPushTokenStorageKey =
    'custom_api_registered_push_token_v1';

const String _registeredRemotePushDeviceIdStorageKey =
    'custom_api_registered_remote_push_device_id_v1';

const String _notificationsEnabledStorageKey =
    'custom_api_notifications_enabled_v1';

const String _registeredBrowserPushDeviceIdStorageKey =
    'custom_api_registered_browser_push_device_id_v1';

const String _registeredBrowserPushTokenStorageKey =
    'custom_api_registered_browser_push_token_v1';

// N2: пользователь закрыл/ответил на first-run CTA «включить
// уведомления» — больше не показываем баннер в этой и будущих сессиях.
const String _notificationCtaDismissedStorageKey =
    'custom_api_notification_cta_dismissed_v1';

// Android 14+: запрос разрешения на полноэкранные уведомления ОТКРЫВАЕТ
// системные настройки. Спрашиваем один раз на установку — иначе
// приложение выкидывает в Settings при каждом холодном старте, пока
// пользователь не включит тумблер (так было в 1.0.30–1.0.31).
const String _fullScreenIntentPromptedStorageKey =
    'custom_api_full_screen_intent_prompted_v1';

// Channel IDs mirror RodnyaNotificationChannels.kt 1:1 — same
// entries in Android Settings whether the notification was rendered
// by VKPNS in the background or replayed locally from Dart, so the
// user has ONE place to mute «Активность» without losing chats or
// calls. The native side registers them on cold-start; the Dart
// calls below are belt-and-suspenders for the rare case where a
// local notification fires before MainActivity has run.
const String _channelIdCalls = 'calls';

const String _channelNameCalls = 'Звонки';

const String _channelDescCalls = 'Входящие аудио и видеозвонки';

const String _channelIdChats = 'chats';

const String _channelNameChats = 'Сообщения';

const String _channelDescChats = 'Новые сообщения от родных и друзей';

const String _channelIdSocial = 'social';

const String _channelNameSocial = 'Активность';

const String _channelDescSocial =
    'Реакции, ответы, дни рождения и обновления дерева';

const String _channelIdSystem = 'system';

const String _channelNameSystem = 'Системные';

const String _channelDescSystem = 'Объявления и тихие напоминания';

/// Anything older than this is shown only in the in-app feed —
/// never replayed as a system notification. Foreground replay is
/// just a rescue path for freshly missed pushes, not a backlog
/// dump when the user opens the app after an hour.
const Duration _maxReplayAge = Duration(minutes: 10);

/// Hard ceiling on how many non-call local notifications we replay
/// per foreground sync. Calls bypass it; chat/feed backlog stays
/// visible in the app without spamming the Android tray.
const int _maxReplayBatch = 1;

/// NTV-3: id уведомки звонка, СОВПАДАЮЩИЙ с нативным
/// (`callId.hashCode() and 0x7fffffff` в Kotlin — алгоритм Java
/// String.hashCode). Dart `String.hashCode` другой, поэтому считаем
/// Java-хэш руками: h = 31*h + char, по модулю 32 бит, затем срезаем
/// знаковый бит (& 0x7fffffff). Тогда снятие через flutter_local_-
/// notifications бьёт ровно по той же уведомке, что показал/снимает натив.
int _androidCallNotificationId(String callId) {
  var hash = 0;
  for (final unit in callId.codeUnits) {
    hash = (31 * hash + unit) & 0xFFFFFFFF; // держим младшие 32 бита
  }
  return hash & 0x7FFFFFFF;
}

class CustomApiNotificationService extends _CustomApiNotificationBase
    with
        _CustomApiNotificationFeedMixin,
        _CustomApiNotificationLocalMixin,
        _CustomApiNotificationPushMixin
    implements NotificationServiceInterface {
  CustomApiNotificationService._({
    required super.plugin,
    required super.preferences,
    super.authService,
    super.runtimeConfig,
    super.realtimeService,
    super.rustoreService,
    super.httpClient,
    super.pollInterval,
    super.remotePushProvider,
    super.remotePushTokenProvider,
    super.remotePushTokenUpdates,
    super.onChatNotification,
    super.onGenericNotification,
    super.browserNotificationBridge,
    super.androidIncomingCallService,
    super.androidPluginOverride,
    super.isWeb,
  }) : super._();

  static Future<CustomApiNotificationService> create({
    FlutterLocalNotificationsPlugin? plugin,
    SharedPreferences? preferences,
    CustomApiAuthService? authService,
    BackendRuntimeConfig? runtimeConfig,
    CustomApiRealtimeService? realtimeService,
    RustoreService? rustoreService,
    http.Client? httpClient,
    Duration? pollInterval,
    String remotePushProvider = 'rustore',
    RemotePushTokenProvider? remotePushTokenProvider,
    Stream<String>? remotePushTokenUpdates,
    ChatNotificationCallback? onChatNotification,
    GenericNotificationCallback? onGenericNotification,
    BrowserNotificationBridge? browserNotificationBridge,
    AndroidIncomingCallService? androidIncomingCallService,
    AndroidFlutterLocalNotificationsPlugin? androidPluginOverride,
    bool isWeb = kIsWeb,
  }) async {
    return CustomApiNotificationService._(
      plugin: plugin ?? FlutterLocalNotificationsPlugin(),
      preferences: preferences ?? await SharedPreferences.getInstance(),
      authService: authService,
      androidPluginOverride: androidPluginOverride,
      isWeb: isWeb,
      runtimeConfig: runtimeConfig,
      realtimeService: realtimeService,
      rustoreService: rustoreService,
      httpClient: httpClient,
      pollInterval: pollInterval,
      remotePushProvider: remotePushProvider,
      remotePushTokenProvider: remotePushTokenProvider,
      remotePushTokenUpdates: remotePushTokenUpdates,
      onChatNotification: onChatNotification,
      onGenericNotification: onGenericNotification,
      browserNotificationBridge: browserNotificationBridge,
      androidIncomingCallService: androidIncomingCallService,
    );
  }

  @visibleForTesting
  static int debugAndroidCallNotificationId(String callId) =>
      _androidCallNotificationId(callId);
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

/// Страница ленты активности: элементы + курсор продолжения (null = конец).
class NotificationsPageResult {
  const NotificationsPageResult(
      {required this.items, required this.nextCursor});

  final List<AppNotificationItem> items;
  final String? nextCursor;
}
