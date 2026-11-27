import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rodnya/backend/backend_runtime_config.dart';
import 'package:rodnya/models/circle.dart';
import 'package:rodnya/services/custom_api_auth_service.dart';
import 'package:rodnya/services/custom_api_circle_service.dart';
import 'package:rodnya/services/invitation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('CustomApiCircleService reads tree circles', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/v1/trees/tree-1/circles');
      expect(request.headers['authorization'], 'Bearer access-token');

      return http.Response(
        jsonEncode({
          'circles': [
            {
              'id': 'tree-1:all_tree',
              'treeId': 'tree-1',
              'kind': 'all_tree',
              'name': 'Всё дерево',
              'isSystem': true,
              'memberCount': 4,
              'createdAt': '2026-04-30T09:00:00.000Z',
              'updatedAt': '2026-04-30T09:00:00.000Z',
            },
            {
              'id': 'circle-close',
              'treeId': 'tree-1',
              'kind': 'custom',
              'name': 'Близкие',
              'isSystem': false,
              'memberCount': 2,
              'createdAt': '2026-04-30T09:05:00.000Z',
            },
            {
              'id': 'circle-tree-1-pair-a-b',
              'treeId': 'tree-1',
              'kind': 'pair',
              'name': 'Анна + Борис',
              'isSystem': true,
              'anchorPersonIds': ['person-a', 'person-b'],
              'memberCount': 3,
              'createdAt': '2026-04-30T09:10:00.000Z',
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final authService = await _createAuthService(client);
    final service = CustomApiCircleService(
      authService: authService,
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
      httpClient: client,
    );

    final circles = await service.getCircles('tree-1');

    expect(circles, hasLength(3));
    expect(circles.first.kind, FamilyCircleKind.allTree);
    expect(circles.first.memberCount, 4);
    expect(circles[1].name, 'Близкие');
    expect(circles.last.kind, FamilyCircleKind.pair);
    expect(circles.last.anchorPersonIds, ['person-a', 'person-b']);
    expect(circles.last.isAuto, isTrue);
  });

  test('CustomApiCircleService does not call backend without a session',
      () async {
    final client = MockClient((request) async {
      fail('Circle request should not reach network without session');
    });
    final prefs = await SharedPreferences.getInstance();
    final authService = await CustomApiAuthService.create(
      httpClient: client,
      preferences: prefs,
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
      invitationService: InvitationService(),
    );
    final service = CustomApiCircleService(
      authService: authService,
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
      httpClient: client,
    );

    await expectLater(
      () => service.getCircles('tree-1'),
      throwsA(
        isA<CustomApiCircleException>().having(
          (error) => error.statusCode,
          'statusCode',
          401,
        ),
      ),
    );
  });

  test('CustomApiCircleService supports create, update, members and delete',
      () async {
    final seenRequests = <String>[];
    final client = MockClient((request) async {
      seenRequests.add('${request.method} ${request.url.path}');
      if (request.url.path == '/v1/trees/tree-1/circles' &&
          request.method == 'POST') {
        return http.Response(
          jsonEncode({
            'id': 'circle-new',
            'treeId': 'tree-1',
            'kind': 'custom',
            'name': 'Тёплый круг',
            'createdBy': 'user-1',
            'isSystem': false,
            'memberCount': 0,
            'createdAt': '2026-06-01T00:00:00.000Z',
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/v1/trees/tree-1/circles/circle-new' &&
          request.method == 'PATCH') {
        return http.Response(
          jsonEncode({
            'id': 'circle-new',
            'treeId': 'tree-1',
            'kind': 'custom',
            'name': 'Свои',
            'createdBy': 'user-1',
            'isSystem': false,
            'memberCount': 0,
            'createdAt': '2026-06-01T00:00:00.000Z',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/v1/trees/tree-1/circles/circle-new/members' &&
          request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'members': [
              {'id': 'cm-1', 'identityId': 'identity-1'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/v1/trees/tree-1/circles/circle-new/members' &&
          request.method == 'PUT') {
        return http.Response(
          jsonEncode({
            'id': 'circle-new',
            'treeId': 'tree-1',
            'kind': 'custom',
            'name': 'Свои',
            'createdBy': 'user-1',
            'isSystem': false,
            'memberCount': 2,
            'createdAt': '2026-06-01T00:00:00.000Z',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path == '/v1/trees/tree-1/circles/circle-new' &&
          request.method == 'DELETE') {
        return http.Response('', 204);
      }
      return http.Response('{"message":"not found"}', 404);
    });

    final authService = await _createAuthService(client);
    final service = CustomApiCircleService(
      authService: authService,
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
      httpClient: client,
    );

    final created = await service.createCircle(
      treeId: 'tree-1',
      name: 'Тёплый круг',
    );
    final updated = await service.updateCircle(
      treeId: 'tree-1',
      circleId: created.id,
      name: 'Свои',
    );
    final members = await service.getCircleMemberIdentityIds(
      treeId: 'tree-1',
      circleId: created.id,
    );
    await service.replaceCircleMembers(
      treeId: 'tree-1',
      circleId: created.id,
      identityIds: const ['identity-1', 'identity-2'],
    );
    await service.deleteCircle(treeId: 'tree-1', circleId: created.id);

    expect(updated.name, 'Свои');
    expect(members, ['identity-1']);
    expect(
        seenRequests,
        containsAll([
          'POST /v1/trees/tree-1/circles',
          'PATCH /v1/trees/tree-1/circles/circle-new',
          'GET /v1/trees/tree-1/circles/circle-new/members',
          'PUT /v1/trees/tree-1/circles/circle-new/members',
          'DELETE /v1/trees/tree-1/circles/circle-new',
        ]));
  });
}

Future<CustomApiAuthService> _createAuthService(http.Client client) async {
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

  return CustomApiAuthService.create(
    httpClient: client,
    preferences: prefs,
    runtimeConfig: const BackendRuntimeConfig(
      apiBaseUrl: 'https://api.example.ru',
    ),
    invitationService: InvitationService(),
  );
}
