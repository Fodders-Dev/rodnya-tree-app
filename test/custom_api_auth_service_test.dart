import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lineage/backend/backend_runtime_config.dart';
import 'package:lineage/services/custom_api_auth_service.dart';
import 'package:lineage/services/invitation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('CustomApiAuthService logs in and restores cached session', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/v1/auth/login') {
        expect(request.method, 'POST');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['email'], 'dev@lineage.app');
        expect(body['password'], 'secret123');

        return http.Response(
          jsonEncode({
            'accessToken': 'access-token',
            'refreshToken': 'refresh-token',
            'user': {
              'id': 'user-1',
              'email': 'dev@lineage.app',
              'displayName': 'Dev User',
              'providerIds': ['password'],
            },
            'profileStatus': {
              'isComplete': false,
              'missingFields': ['phoneNumber', 'username'],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.url.path == '/v1/auth/session') {
        return http.Response('{"message":"offline"}', 500);
      }

      if (request.url.path == '/v1/auth/logout') {
        return http.Response('{}', 200);
      }

      return http.Response('{"message":"not found"}', 404);
    });

    final runtimeConfig = const BackendRuntimeConfig(
      apiBaseUrl: 'https://api.example.ru',
    );
    final prefs = await SharedPreferences.getInstance();

    final service = await CustomApiAuthService.create(
      httpClient: client,
      preferences: prefs,
      runtimeConfig: runtimeConfig,
      invitationService: InvitationService(),
    );

    await service.loginWithEmail('dev@lineage.app', 'secret123');

    expect(service.currentUserId, 'user-1');
    expect(service.currentUserEmail, 'dev@lineage.app');
    expect(service.currentUserDisplayName, 'Dev User');
    expect(service.currentProviderIds, ['password']);

    final restoredService = await CustomApiAuthService.create(
      httpClient: client,
      preferences: prefs,
      runtimeConfig: runtimeConfig,
      invitationService: InvitationService(),
    );

    expect(restoredService.currentUserId, 'user-1');
    expect(
      await restoredService.checkProfileCompleteness(),
      {
        'isComplete': false,
        'missingFields': ['phoneNumber', 'username'],
      },
    );
  });

  test('CustomApiAuthService processes pending invitation after login',
      () async {
    final invitationService = InvitationService()
      ..setPendingInvitation(treeId: 'tree-1', personId: 'person-1');

    final client = MockClient((request) async {
      if (request.url.path == '/v1/auth/login') {
        return http.Response(
          jsonEncode({
            'accessToken': 'access-token',
            'refreshToken': 'refresh-token',
            'user': {
              'id': 'user-1',
              'email': 'dev@lineage.app',
              'displayName': 'Dev User',
              'providerIds': ['password'],
            },
            'profileStatus': {
              'isComplete': true,
              'missingFields': <String>[],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.url.path == '/v1/invitations/pending/process') {
        expect(request.method, 'POST');
        expect(request.headers['authorization'], 'Bearer access-token');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['treeId'], 'tree-1');
        expect(body['personId'], 'person-1');
        return http.Response(
          jsonEncode({
            'ok': true,
            'person': {
              'id': 'person-1',
              'treeId': 'tree-1',
              'userId': 'user-1',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      return http.Response('{"message":"not found"}', 404);
    });

    final service = await CustomApiAuthService.create(
      httpClient: client,
      preferences: await SharedPreferences.getInstance(),
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
      invitationService: invitationService,
    );

    await service.loginWithEmail('dev@lineage.app', 'secret123');

    expect(invitationService.hasPendingInvitation, isFalse);
    expect(service.currentUserId, 'user-1');
  });

  test('CustomApiAuthService clears stale session on unauthorized refresh',
      () async {
    final client = MockClient((request) async {
      if (request.url.path == '/v1/auth/login') {
        return http.Response(
          jsonEncode({
            'accessToken': 'access-token',
            'refreshToken': 'refresh-token',
            'user': {
              'id': 'user-1',
              'email': 'artem@example.com',
              'displayName': 'Артем Кузнецов',
              'providerIds': ['password'],
            },
            'profileStatus': {
              'isComplete': true,
              'missingFields': <String>[],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.url.path == '/v1/auth/session') {
        return http.Response('{"message":"unauthorized"}', 401);
      }

      return http.Response('{"message":"not found"}', 404);
    });

    final prefs = await SharedPreferences.getInstance();
    final service = await CustomApiAuthService.create(
      httpClient: client,
      preferences: prefs,
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
      invitationService: InvitationService(),
    );

    await service.loginWithEmail('artem@example.com', 'secret123');
    expect(service.currentUserId, 'user-1');

    final profileStatus = await service.checkProfileCompleteness();

    expect(profileStatus, {
      'isComplete': false,
      'missingFields': ['auth'],
    });
    expect(service.currentUserId, isNull);
    expect(prefs.getString('custom_api_session_v1'), isNull);
  });

  test('CustomApiAuthService describeError hides technical backend details',
      () async {
    final service = await CustomApiAuthService.create(
      httpClient: MockClient((request) async => http.Response('{}', 200)),
      preferences: await SharedPreferences.getInstance(),
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
      invitationService: InvitationService(),
    );

    expect(
      service.describeError(
        const CustomApiException('backend (500)', statusCode: 500),
      ),
      'Сервис временно недоступен. Попробуйте чуть позже.',
    );
    expect(
      service.describeError(
        const CustomApiException('SocketException: Connection refused'),
      ),
      'Не удалось подключиться к серверу. Проверьте интернет и попробуйте ещё раз.',
    );
    expect(
      service.describeError(
        const CustomApiException('TypeError: Failed to fetch'),
      ),
      'Не удалось выполнить вход. Попробуйте ещё раз.',
    );
  });
}
