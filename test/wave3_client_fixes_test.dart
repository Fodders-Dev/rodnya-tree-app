import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rodnya/backend/backend_runtime_config.dart';
import 'package:rodnya/backend/interfaces/chat_service_interface.dart';
import 'package:rodnya/backend/models/semya_browse_token.dart';
import 'package:rodnya/navigation/app_router_guards.dart';
import 'package:rodnya/services/app_links_dynamic_link_service.dart';
import 'package:rodnya/services/chat_send_queue.dart';
import 'package:rodnya/services/custom_api_auth_service.dart';
import 'package:rodnya/services/custom_api_call_service.dart';
import 'package:rodnya/services/custom_api_family_tree_service.dart';
import 'package:rodnya/services/invitation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoopChatService implements ChatServiceInterface {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await GetIt.I.reset();
  });

  test(
      'Wave 3: CustomApiAuthService keeps session on 403 and rejects HTML 502 with CustomApiException',
      () async {
    var refreshCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/v1/auth/login') {
        return http.Response(
          jsonEncode({
            'accessToken': 'tok-1',
            'refreshToken': 'ref-1',
            'user': {
              'id': 'u1',
              'email': 'u1@example.com',
              'displayName': 'User 1',
              'providerIds': ['password'],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/v1/auth/refresh') {
        refreshCalls++;
        return http.Response('{}', 401);
      }
      if (request.url.path == '/v1/auth/session') {
        return http.Response(
          jsonEncode({'message': 'Forbidden'}),
          403,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/v1/trees') {
        return http.Response('<html><body>502 Bad Gateway</body></html>', 502);
      }
      return http.Response('{}', 404);
    });

    final prefs = await SharedPreferences.getInstance();
    final auth = await CustomApiAuthService.create(
      httpClient: client,
      preferences: prefs,
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
      invitationService: InvitationService(),
    );
    await auth.loginWithEmail('u1@example.com', 'password123');
    expect(auth.currentUserId, 'u1');

    // 403 on checkProfileCompleteness must NOT refresh or clear session.
    await auth.checkProfileCompleteness();
    expect(auth.currentUserId, 'u1');
    expect(refreshCalls, 0);

    // Non-JSON 502 HTML throws CustomApiException (not FormatException).
    final treeService = CustomApiFamilyTreeService(
      authService: auth,
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
      httpClient: client,
    );
    await expectLater(
      treeService.getUserTrees(),
      throwsA(isA<CustomApiException>()),
    );
    expect(auth.currentUserId, 'u1');
  });

  test(
      'Wave 3: getRelatives & getActiveCall emit zero unhandled Zone errors on 500',
      () async {
    final zoneErrors = <Object>[];
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'message': 'Server failure'}),
        500,
        headers: {'content-type': 'application/json'},
      );
    });

    final prefs = await SharedPreferences.getInstance();
    final auth = await CustomApiAuthService.create(
      httpClient: MockClient((req) async {
        return http.Response(
          jsonEncode({
            'accessToken': 'tok-1',
            'refreshToken': 'ref-1',
            'user': {
              'id': 'u1',
              'email': 'u1@example.com',
              'displayName': 'U1'
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      preferences: prefs,
      runtimeConfig:
          const BackendRuntimeConfig(apiBaseUrl: 'https://api.example.ru'),
      invitationService: InvitationService(),
    );
    await auth.loginWithEmail('u1@example.com', 'pass');

    final treeService = CustomApiFamilyTreeService(
      authService: auth,
      runtimeConfig:
          const BackendRuntimeConfig(apiBaseUrl: 'https://api.example.ru'),
      httpClient: client,
    );
    final callService = CustomApiCallService(
      authService: auth,
      runtimeConfig:
          const BackendRuntimeConfig(apiBaseUrl: 'https://api.example.ru'),
      httpClient: client,
    );

    await runZonedGuarded(() async {
      await expectLater(treeService.getRelatives('tree-1'), throwsException);
      await expectLater(
          callService.getActiveCall(chatId: 'chat-1'), throwsException);
      await Future<void>.delayed(Duration.zero);
    }, (error, stack) {
      zoneErrors.add(error);
    });

    expect(zoneErrors, isEmpty);
  });

  test(
      'Wave 3: ChatSendQueue isolates drafts by currentUserId and resets on signOut',
      () async {
    var activeUser = 'user-a';
    final queue = ChatSendQueue.memory(
      chatService: _NoopChatService(),
      currentUserId: () => activeUser,
    );

    await queue.enqueue(chatId: 'chat-1', senderId: 'user-a', text: 'Secret A');
    expect(queue.messagesFor('chat-1').length, 1);
    expect(queue.shouldSendItem(queue.messagesFor('chat-1').first), isTrue);

    final msgA = queue.messagesFor('chat-1').first;
    activeUser = 'user-b';
    expect(queue.messagesFor('chat-1'), isEmpty);
    expect(queue.shouldSendItem(msgA), isFalse);

    activeUser = 'user-a';
    expect(queue.messagesFor('chat-1').length, 1);
    queue.resetForSignOut();
    expect(queue.messagesFor('chat-1'), isEmpty);
  });

  test(
      'Wave 3: SemyaBrowseTokenSummary derives revoked & expired status when omitted',
      () {
    final revoked = SemyaBrowseTokenSummary.fromJson({
      'id': 't1',
      'semyaId': 's1',
      'createdByUserId': 'u1',
      'createdAt': '2026-01-01T00:00:00.000Z',
      'expiresAt': '2099-01-01T00:00:00.000Z',
      'revokedAt': '2026-02-01T00:00:00.000Z',
    });
    expect(revoked.status, 'revoked');
    expect(revoked.isRevoked, isTrue);

    final expired = SemyaBrowseTokenSummary.fromJson({
      'id': 't2',
      'semyaId': 's1',
      'createdByUserId': 'u1',
      'createdAt': '2020-01-01T00:00:00.000Z',
      'expiresAt': '2020-02-01T00:00:00.000Z',
    });
    expect(expired.status, 'expired');
    expect(expired.isExpired, isTrue);

    final active = SemyaBrowseTokenSummary.fromJson({
      'id': 't3',
      'semyaId': 's1',
      'createdByUserId': 'u1',
      'createdAt': '2026-01-01T00:00:00.000Z',
      'expiresAt': '2099-01-01T00:00:00.000Z',
    });
    expect(active.status, 'active');
    expect(active.isActive, isTrue);
  });

  test(
      'Wave 3: deep link routes for /reset-password and /browse & safe login redirect validation',
      () {
    expect(
      AppLinksDynamicLinkService.routeForUri(
        Uri.parse('https://rodnya-tree.ru/reset-password?token=abc'),
      ),
      '/reset-password?token=abc',
    );
    expect(
      AppLinksDynamicLinkService.routeForUri(
        Uri.parse('https://rodnya-tree.ru/browse/tok123'),
      ),
      '/browse/tok123',
    );
    expect(
      AppRouterGuards.hasSocialAuthPayload(
        Uri.parse('https://rodnya-tree.ru/login?maxAuthCode=xyz'),
      ),
      isTrue,
    );
  });
}
