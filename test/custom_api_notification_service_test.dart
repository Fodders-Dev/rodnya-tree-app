import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rodnya/backend/backend_runtime_config.dart';
import 'package:rodnya/backend/interfaces/call_service_interface.dart';
import 'package:rodnya/models/call_event.dart';
import 'package:rodnya/models/call_invite.dart';
import 'package:rodnya/models/call_media_mode.dart';
import 'package:rodnya/services/custom_api_auth_service.dart';
import 'package:rodnya/services/call_coordinator_service.dart';
import 'package:rodnya/services/chat_notification_settings_store.dart';
import 'package:rodnya/services/custom_api_notification_service.dart';
import 'package:rodnya/services/invitation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterLocalNotificationsPlatform.instance =
        _FakeFlutterLocalNotificationsPlatform();
  });

  tearDown(() async {
    await GetIt.I.reset();
  });

  test(
    'CustomApiNotificationService treats call_invite as incoming call signal',
    () async {
      final client = MockClient((request) async {
        if (request.url.path == '/v1/notifications' &&
            request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'notifications': [
                {
                  'id': 'notification-call-1',
                  'type': 'call_invite',
                  'title': 'Собеседник',
                  'body': 'Входящий видеозвонок',
                  'createdAt': '2026-04-20T12:00:00.000Z',
                  'data': {
                    'chatId': 'chat-1',
                    'callId': 'call-1',
                    'mediaMode': 'video',
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"message":"not found"}', 404);
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'custom_api_session_v1',
        jsonEncode({
          'accessToken': 'access-token',
          'refreshToken': 'refresh-token',
          'userId': 'user-1',
          'email': 'dev@rodnya.app',
          'displayName': 'Dev User',
          'providerIds': ['password'],
          'isProfileComplete': true,
          'missingFields': const [],
        }),
      );

      final authService = await CustomApiAuthService.create(
        httpClient: client,
        preferences: prefs,
        runtimeConfig: const BackendRuntimeConfig(
          apiBaseUrl: 'https://api.example.ru',
        ),
        invitationService: InvitationService(),
      );

      final coordinator = _FakeNotificationCallCoordinator();
      GetIt.I.registerSingleton<CallCoordinatorService>(coordinator);

      final shownGenericNotifications = <Map<String, dynamic>>[];
      final service = await CustomApiNotificationService.create(
        preferences: prefs,
        authService: authService,
        runtimeConfig: const BackendRuntimeConfig(
          apiBaseUrl: 'https://api.example.ru',
        ),
        httpClient: client,
        onGenericNotification: ({
          required String title,
          required String body,
          required int notificationId,
          String? payload,
        }) async {
          shownGenericNotifications.add({
            'title': title,
            'body': body,
            'notificationId': notificationId,
            'payload': payload,
          });
        },
      );

      await service.initialize();
      await service.syncPendingNotifications();

      expect(coordinator.ensureRuntimeReadyCalls, greaterThanOrEqualTo(1));
      expect(coordinator.hydratedCallIds, ['call-1']);
      expect(coordinator.hydratedChatIds, ['chat-1']);
      expect(shownGenericNotifications, isEmpty);

      await service.dispose();
    },
  );

  test(
    'CustomApiNotificationService polls unread notifications and deduplicates delivered ids',
    () async {
      final unreadNotifications = [
        {
          'id': 'notification-1',
          'type': 'chat_message',
          'title': 'Собеседник',
          'body': 'Привет из чата',
          'createdAt': '2026-03-27T12:00:00.000Z',
          'data': {
            'chatId': 'chat-1',
            'senderId': 'user-2',
            'senderName': 'Собеседник',
          },
        },
        {
          'id': 'notification-2',
          'type': 'tree_invitation',
          'title': 'Приглашение в дерево',
          'body': 'Вас пригласили в дерево семьи',
          'createdAt': '2026-03-27T12:01:00.000Z',
          'data': {
            'treeId': 'tree-1',
            'treeName': 'Семья',
          },
        },
      ];

      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/notifications');
        expect(request.url.queryParameters['status'], 'unread');
        expect(request.url.queryParameters['limit'], '20');
        expect(request.headers['authorization'], 'Bearer access-token');

        return http.Response(
          jsonEncode({
            'notifications': unreadNotifications,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'custom_api_session_v1',
        jsonEncode({
          'accessToken': 'access-token',
          'refreshToken': 'refresh-token',
          'userId': 'user-1',
          'email': 'dev@rodnya.app',
          'displayName': 'Dev User',
          'providerIds': ['password'],
          'isProfileComplete': true,
          'missingFields': const [],
        }),
      );

      final authService = await CustomApiAuthService.create(
        httpClient: client,
        preferences: prefs,
        runtimeConfig: const BackendRuntimeConfig(
          apiBaseUrl: 'https://api.example.ru',
        ),
        invitationService: InvitationService(),
      );

      final shownChatNotifications = <Map<String, dynamic>>[];
      final shownGenericNotifications = <Map<String, dynamic>>[];

      final service = await CustomApiNotificationService.create(
        preferences: prefs,
        authService: authService,
        runtimeConfig: const BackendRuntimeConfig(
          apiBaseUrl: 'https://api.example.ru',
        ),
        httpClient: client,
        onChatNotification: ({
          required String chatId,
          required String senderId,
          required String senderName,
          required String messageText,
          required int notificationId,
          bool playSound = true,
        }) async {
          shownChatNotifications.add({
            'chatId': chatId,
            'senderId': senderId,
            'senderName': senderName,
            'messageText': messageText,
            'notificationId': notificationId,
            'playSound': playSound,
          });
        },
        onGenericNotification: ({
          required String title,
          required String body,
          required int notificationId,
          String? payload,
        }) async {
          shownGenericNotifications.add({
            'title': title,
            'body': body,
            'notificationId': notificationId,
            'payload': payload,
          });
        },
      );

      await service.initialize();
      await service.syncPendingNotifications();

      expect(shownChatNotifications, hasLength(1));
      expect(shownChatNotifications.first['chatId'], 'chat-1');
      expect(shownChatNotifications.first['messageText'], 'Привет из чата');

      expect(shownGenericNotifications, hasLength(1));
      expect(shownGenericNotifications.first['title'], 'Приглашение в дерево');
      expect(
        shownGenericNotifications.first['body'],
        'Вас пригласили в дерево семьи',
      );

      final deliveredIds = prefs.getStringList(
        'custom_api_delivered_notification_ids_v1',
      );
      expect(
        deliveredIds,
        containsAll(<String>['notification-1', 'notification-2']),
      );

      final restartedService = await CustomApiNotificationService.create(
        preferences: prefs,
        authService: authService,
        runtimeConfig: const BackendRuntimeConfig(
          apiBaseUrl: 'https://api.example.ru',
        ),
        httpClient: client,
        onChatNotification: ({
          required String chatId,
          required String senderId,
          required String senderName,
          required String messageText,
          required int notificationId,
          bool playSound = true,
        }) async {
          shownChatNotifications.add({'chatId': chatId});
        },
        onGenericNotification: ({
          required String title,
          required String body,
          required int notificationId,
          String? payload,
        }) async {
          shownGenericNotifications.add({'title': title});
        },
      );

      await restartedService.initialize();
      await restartedService.syncPendingNotifications();

      expect(shownChatNotifications, hasLength(1));
      expect(shownGenericNotifications, hasLength(1));

      await service.dispose();
      await restartedService.dispose();
    },
  );

  test(
    'CustomApiNotificationService suppresses muted chat notifications',
    () async {
      final unreadNotifications = [
        {
          'id': 'notification-muted-1',
          'type': 'chat_message',
          'title': 'Собеседник',
          'body': 'Тихий чат не должен всплыть',
          'createdAt': '2026-03-27T12:00:00.000Z',
          'data': {
            'chatId': 'chat-muted-1',
            'senderId': 'user-2',
            'senderName': 'Собеседник',
          },
        },
        {
          'id': 'notification-generic-1',
          'type': 'tree_invitation',
          'title': 'Приглашение в дерево',
          'body': 'Это уведомление должно прийти',
          'createdAt': '2026-03-27T12:01:00.000Z',
          'data': {'treeId': 'tree-1'},
        },
      ];

      final client = MockClient((request) async {
        if (request.url.path == '/v1/notifications' &&
            request.method == 'GET') {
          return http.Response(
            jsonEncode({'notifications': unreadNotifications}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"message":"not found"}', 404);
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'custom_api_session_v1',
        jsonEncode({
          'accessToken': 'access-token',
          'refreshToken': 'refresh-token',
          'userId': 'user-1',
          'email': 'dev@rodnya.app',
          'displayName': 'Dev User',
          'providerIds': ['password'],
          'isProfileComplete': true,
          'missingFields': const [],
        }),
      );
      await const SharedPreferencesChatNotificationSettingsStore().saveSettings(
        SharedPreferencesChatNotificationSettingsStore.chatKey('chat-muted-1'),
        ChatNotificationSettingsSnapshot(
          level: ChatNotificationLevel.muted,
          updatedAt: DateTime(2026, 4, 11, 12, 0),
        ),
      );

      final authService = await CustomApiAuthService.create(
        httpClient: client,
        preferences: prefs,
        runtimeConfig: const BackendRuntimeConfig(
          apiBaseUrl: 'https://api.example.ru',
        ),
        invitationService: InvitationService(),
      );

      final shownChatNotifications = <Map<String, dynamic>>[];
      final shownGenericNotifications = <Map<String, dynamic>>[];

      final service = await CustomApiNotificationService.create(
        preferences: prefs,
        authService: authService,
        runtimeConfig: const BackendRuntimeConfig(
          apiBaseUrl: 'https://api.example.ru',
        ),
        httpClient: client,
        onChatNotification: ({
          required String chatId,
          required String senderId,
          required String senderName,
          required String messageText,
          required int notificationId,
          bool playSound = true,
        }) async {
          shownChatNotifications.add({'chatId': chatId});
        },
        onGenericNotification: ({
          required String title,
          required String body,
          required int notificationId,
          String? payload,
        }) async {
          shownGenericNotifications.add({'title': title, 'body': body});
        },
      );

      await service.initialize();
      await service.syncPendingNotifications();

      expect(shownChatNotifications, isEmpty);
      expect(shownGenericNotifications, hasLength(1));
      expect(
        prefs.getStringList('custom_api_delivered_notification_ids_v1'),
        containsAll(
          <String>['notification-muted-1', 'notification-generic-1'],
        ),
      );

      await service.dispose();
    },
  );

  test(
    'CustomApiNotificationService forwards silent mode to chat notifications',
    () async {
      final unreadNotifications = [
        {
          'id': 'notification-silent-1',
          'type': 'chat_message',
          'title': 'Собеседник',
          'body': 'Тихий режим',
          'createdAt': '2026-03-27T12:00:00.000Z',
          'data': {
            'chatId': 'chat-silent-1',
            'senderId': 'user-2',
            'senderName': 'Собеседник',
          },
        },
      ];

      final client = MockClient((request) async {
        if (request.url.path == '/v1/notifications' &&
            request.method == 'GET') {
          return http.Response(
            jsonEncode({'notifications': unreadNotifications}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"message":"not found"}', 404);
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'custom_api_session_v1',
        jsonEncode({
          'accessToken': 'access-token',
          'refreshToken': 'refresh-token',
          'userId': 'user-1',
          'email': 'dev@rodnya.app',
          'displayName': 'Dev User',
          'providerIds': ['password'],
          'isProfileComplete': true,
          'missingFields': const [],
        }),
      );
      await const SharedPreferencesChatNotificationSettingsStore().saveSettings(
        SharedPreferencesChatNotificationSettingsStore.chatKey('chat-silent-1'),
        ChatNotificationSettingsSnapshot(
          level: ChatNotificationLevel.silent,
          updatedAt: DateTime(2026, 4, 11, 12, 5),
        ),
      );

      final authService = await CustomApiAuthService.create(
        httpClient: client,
        preferences: prefs,
        runtimeConfig: const BackendRuntimeConfig(
          apiBaseUrl: 'https://api.example.ru',
        ),
        invitationService: InvitationService(),
      );

      final shownChatNotifications = <Map<String, dynamic>>[];

      final service = await CustomApiNotificationService.create(
        preferences: prefs,
        authService: authService,
        runtimeConfig: const BackendRuntimeConfig(
          apiBaseUrl: 'https://api.example.ru',
        ),
        httpClient: client,
        onChatNotification: ({
          required String chatId,
          required String senderId,
          required String senderName,
          required String messageText,
          required int notificationId,
          bool playSound = true,
        }) async {
          shownChatNotifications.add({
            'chatId': chatId,
            'playSound': playSound,
          });
        },
      );

      await service.initialize();
      await service.syncPendingNotifications();

      expect(shownChatNotifications, hasLength(1));
      expect(shownChatNotifications.first['chatId'], 'chat-silent-1');
      expect(shownChatNotifications.first['playSound'], isFalse);

      await service.dispose();
    },
  );

  test(
    'CustomApiNotificationService registers rustore push token on backend startup',
    () async {
      var registeredDeviceCalls = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/v1/push/devices' &&
            request.method == 'POST') {
          registeredDeviceCalls += 1;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['provider'], 'rustore');
          expect(body['token'], 'rustore-token-1');

          return http.Response(
            jsonEncode({
              'device': {
                'id': 'device-1',
                'provider': 'rustore',
                'platform': 'android',
              },
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }

        if (request.url.path == '/v1/notifications' &&
            request.method == 'GET') {
          return http.Response(
            jsonEncode({'notifications': const []}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (request.url.path == '/v1/notifications/unread-count' &&
            request.method == 'GET') {
          return http.Response(
            jsonEncode({'totalUnread': 0}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response('{"message":"not found"}', 404);
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'custom_api_session_v1',
        jsonEncode({
          'accessToken': 'access-token',
          'refreshToken': 'refresh-token',
          'userId': 'user-1',
          'email': 'dev@rodnya.app',
          'displayName': 'Dev User',
          'providerIds': ['password'],
          'isProfileComplete': true,
          'missingFields': const [],
        }),
      );

      final authService = await CustomApiAuthService.create(
        httpClient: client,
        preferences: prefs,
        runtimeConfig: const BackendRuntimeConfig(
          apiBaseUrl: 'https://api.example.ru',
        ),
        invitationService: InvitationService(),
      );

      final service = await CustomApiNotificationService.create(
        preferences: prefs,
        authService: authService,
        runtimeConfig: const BackendRuntimeConfig(
          apiBaseUrl: 'https://api.example.ru',
        ),
        httpClient: client,
        pollInterval: const Duration(hours: 1),
        remotePushTokenProvider: () async => 'rustore-token-1',
      );

      await service.startForegroundSync();
      expect(registeredDeviceCalls, 1);

      await service.startForegroundSync();
      expect(registeredDeviceCalls, 1);

      await service.dispose();
    },
  );

  test(
    'CustomApiNotificationService обновляет unread count stream из backend',
    () async {
      final client = MockClient((request) async {
        if (request.url.path == '/v1/notifications/unread-count' &&
            request.method == 'GET') {
          return http.Response(
            jsonEncode({'totalUnread': 3}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (request.url.path == '/v1/notifications' &&
            request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'notifications': [
                {
                  'id': 'notification-1',
                  'type': 'tree_invitation',
                  'title': 'Приглашение в дерево',
                  'body': 'Вас пригласили',
                  'createdAt': '2026-04-03T10:00:00.000Z',
                  'data': {'treeId': 'tree-1'},
                },
                {
                  'id': 'notification-2',
                  'type': 'chat_message',
                  'title': 'Собеседник',
                  'body': 'Привет',
                  'createdAt': '2026-04-03T10:01:00.000Z',
                  'data': {
                    'chatId': 'chat-1',
                    'senderId': 'user-2',
                    'senderName': 'Собеседник',
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response('{"message":"not found"}', 404);
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'custom_api_session_v1',
        jsonEncode({
          'accessToken': 'access-token',
          'refreshToken': 'refresh-token',
          'userId': 'user-1',
          'email': 'dev@rodnya.app',
          'displayName': 'Dev User',
          'providerIds': ['password'],
          'isProfileComplete': true,
          'missingFields': const [],
        }),
      );

      final authService = await CustomApiAuthService.create(
        httpClient: client,
        preferences: prefs,
        runtimeConfig: const BackendRuntimeConfig(
          apiBaseUrl: 'https://api.example.ru',
        ),
        invitationService: InvitationService(),
      );

      final service = await CustomApiNotificationService.create(
        preferences: prefs,
        authService: authService,
        runtimeConfig: const BackendRuntimeConfig(
          apiBaseUrl: 'https://api.example.ru',
        ),
        httpClient: client,
      );

      final seenCounts = <int>[];
      final subscription =
          service.unreadNotificationsCountStream.listen(seenCounts.add);

      expect(await service.refreshUnreadNotificationsCount(), 3);
      expect(service.unreadNotificationsCount, 3);

      final notifications = await service.fetchUnreadNotifications(limit: 10);
      expect(notifications, hasLength(2));
      expect(service.unreadNotificationsCount, 2);

      await Future<void>.delayed(Duration.zero);
      expect(seenCounts, containsAllInOrder(<int>[3, 2]));

      await subscription.cancel();
      await service.dispose();
    },
  );

  test(
    'CustomApiNotificationService marks notification read and updates unread count',
    () async {
      var readCalls = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/v1/notifications/unread-count' &&
            request.method == 'GET') {
          return http.Response(
            jsonEncode({'totalUnread': 1}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (request.url.path == '/v1/notifications/notification-1/read' &&
            request.method == 'POST') {
          readCalls += 1;
          expect(request.headers['authorization'], 'Bearer access-token');
          return http.Response(
            jsonEncode({
              'notification': {
                'id': 'notification-1',
                'readAt': '2026-04-03T11:00:00.000Z',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        return http.Response('{"message":"not found"}', 404);
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'custom_api_session_v1',
        jsonEncode({
          'accessToken': 'access-token',
          'refreshToken': 'refresh-token',
          'userId': 'user-1',
          'email': 'dev@rodnya.app',
          'displayName': 'Dev User',
          'providerIds': ['password'],
          'isProfileComplete': true,
          'missingFields': const [],
        }),
      );

      final authService = await CustomApiAuthService.create(
        httpClient: client,
        preferences: prefs,
        runtimeConfig: const BackendRuntimeConfig(
          apiBaseUrl: 'https://api.example.ru',
        ),
        invitationService: InvitationService(),
      );

      final service = await CustomApiNotificationService.create(
        preferences: prefs,
        authService: authService,
        runtimeConfig: const BackendRuntimeConfig(
          apiBaseUrl: 'https://api.example.ru',
        ),
        httpClient: client,
      );

      await service.initialize();
      await service.refreshUnreadNotificationsCount();
      expect(service.unreadNotificationsCount, 1);
      await service.markNotificationRead('notification-1');

      expect(readCalls, 1);
      expect(service.unreadNotificationsCount, 0);

      await service.dispose();
    },
  );

  test(
    'CustomApiNotificationService signs out cleanly when push registration gets unauthorized',
    () async {
      var logoutCalls = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/v1/push/devices' &&
            request.method == 'POST') {
          return http.Response(
            jsonEncode({'message': 'Сессия не найдена или истекла'}),
            401,
            headers: {'content-type': 'application/json'},
          );
        }

        if (request.url.path == '/v1/auth/logout' && request.method == 'POST') {
          logoutCalls += 1;
          return http.Response('', 204);
        }

        return http.Response('{"message":"not found"}', 404);
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'custom_api_session_v1',
        jsonEncode({
          'accessToken': 'access-token',
          'refreshToken': 'refresh-token',
          'userId': 'user-1',
          'email': 'dev@rodnya.app',
          'displayName': 'Dev User',
          'providerIds': ['password'],
          'isProfileComplete': true,
          'missingFields': const [],
        }),
      );

      final authService = await CustomApiAuthService.create(
        httpClient: client,
        preferences: prefs,
        runtimeConfig: const BackendRuntimeConfig(
          apiBaseUrl: 'https://api.example.ru',
        ),
        invitationService: InvitationService(),
      );

      final service = await CustomApiNotificationService.create(
        preferences: prefs,
        authService: authService,
        runtimeConfig: const BackendRuntimeConfig(
          apiBaseUrl: 'https://api.example.ru',
        ),
        httpClient: client,
        pollInterval: const Duration(hours: 1),
        remotePushTokenProvider: () async => 'rustore-token-1',
      );

      await service.startForegroundSync();

      expect(authService.currentUserId, isNull);
      expect(service.unreadNotificationsCount, 0);
      expect(
        prefs.containsKey('custom_api_session_v1'),
        isFalse,
      );
      expect(logoutCalls, 0);

      await service.dispose();
    },
  );
}

class _FakeFlutterLocalNotificationsPlatform
    extends FlutterLocalNotificationsPlatform {
  final List<Map<String, Object?>> shownNotifications =
      <Map<String, Object?>>[];

  @override
  Future<NotificationAppLaunchDetails?>
      getNotificationAppLaunchDetails() async {
    return const NotificationAppLaunchDetails(false);
  }

  Future<bool?> initialize(
    InitializationSettings initializationSettings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
        onDidReceiveBackgroundNotificationResponse,
  }) async {
    return true;
  }

  @override
  Future<void> show(
    int id,
    String? title,
    String? body, {
    AndroidNotificationDetails? notificationDetails,
    String? payload,
  }) async {
    shownNotifications.add({
      'id': id,
      'title': title,
      'body': body,
      'payload': payload,
    });
  }

  @override
  Future<void> cancel(int id, {String? tag}) async {}
}

class _FakeNotificationCallCoordinator extends CallCoordinatorService {
  _FakeNotificationCallCoordinator()
      : super(
          callService: _FakeNotificationCallService(),
        );

  int ensureRuntimeReadyCalls = 0;
  final List<String> hydratedCallIds = <String>[];
  final List<String> hydratedChatIds = <String>[];

  @override
  Future<void> ensureRuntimeReady() async {
    ensureRuntimeReadyCalls += 1;
  }

  @override
  Future<CallInvite?> hydrateIncomingCall({
    String? callId,
    String? chatId,
  }) async {
    hydratedCallIds.add(callId ?? '');
    hydratedChatIds.add(chatId ?? '');
    return null;
  }
}

class _FakeNotificationCallService implements CallServiceInterface {
  @override
  String? get currentUserId => 'user-1';

  @override
  Stream<CallEvent> get events => const Stream<CallEvent>.empty();

  @override
  Future<CallInvite> acceptCall(String callId) {
    throw UnimplementedError();
  }

  @override
  Future<CallInvite> cancelCall(String callId) {
    throw UnimplementedError();
  }

  @override
  Future<CallInvite?> getActiveCall({String? chatId}) async => null;

  @override
  Future<CallInvite?> getCall(String callId) async => null;

  @override
  Future<CallInvite> hangUp(String callId) {
    throw UnimplementedError();
  }

  @override
  Future<CallInvite> rejectCall(String callId) {
    throw UnimplementedError();
  }

  @override
  Future<void> startRealtimeBridge() async {}

  @override
  Future<CallInvite> startCall({
    required String chatId,
    required CallMediaMode mediaMode,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> stopRealtimeBridge() async {}
}
