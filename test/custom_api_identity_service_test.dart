import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rodnya/backend/backend_runtime_config.dart';
import 'package:rodnya/services/custom_api_auth_service.dart';
import 'package:rodnya/services/custom_api_identity_service.dart';
import 'package:rodnya/services/invitation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('CustomApiIdentityService parses safe merge proposals', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/v1/merge-proposals/pending');
      expect(request.headers['authorization'], 'Bearer access-token');
      return _jsonResponse(
        {
          'proposals': [
            {
              'id': 'merge:person-a:person-b',
              'status': 'pending',
              'matchScore': 0.95,
              'confidence': 'high',
              'reasons': ['Совпадает ФИО', 'Совпадает год рождения'],
              'personA': {'name': 'Иван Петров', 'birthYear': '1950'},
              'personB': {'name': 'Иван Петров', 'birthYear': '1950'},
              'requiredReviewCount': 2,
              'reviewCount': 1,
              'createdAt': '2026-05-01T10:00:00.000Z',
            },
          ],
        },
        200,
      );
    });
    final service = CustomApiIdentityService(
      authService: await _createAuthService(client),
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
      httpClient: client,
    );

    final proposals = await service.getPendingMergeProposals();

    expect(proposals, hasLength(1));
    expect(proposals.single.personA.name, 'Иван Петров');
    expect(proposals.single.personA.birthYear, '1950');
    expect(proposals.single.requiredReviewCount, 2);
  });

  test('CustomApiIdentityService reviews identity claims and privacy',
      () async {
    final seenPaths = <String>[];
    final client = MockClient((request) async {
      seenPaths.add('${request.method} ${request.url.path}');
      expect(request.headers['authorization'], 'Bearer access-token');

      if (request.method == 'POST' &&
          request.url.path == '/v1/identity-claims') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['treeId'], 'tree-1');
        expect(body['personId'], 'person-1');
        return _jsonResponse(
          {
            'claim': {
              'id': 'claim-1',
              'identityId': 'identity-1',
              'personId': 'person-1',
              'claimantUserId': 'user-1',
              'status': 'pending',
              'createdAt': '2026-05-01T10:00:00.000Z',
            },
          },
          201,
        );
      }

      if (request.method == 'PUT' &&
          request.url.path == '/v1/trees/tree-1/persons/person-1/attributes') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['visibility'], 'cross-tree');
        expect(body['attributes'], isA<List<dynamic>>());
        return _jsonResponse(
          {
            'attributes': [
              {
                'id': 'attr-1',
                'identityId': 'identity-1',
                'sourcePersonId': 'person-1',
                'field': 'name',
                'value': 'Иван Петров',
                'visibility': 'cross-tree',
                'updatedAt': '2026-05-01T10:00:00.000Z',
              },
            ],
          },
          200,
        );
      }

      if (request.method == 'PATCH' &&
          request.url.path == '/v1/identity-discovery/me') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['isPublicDiscoverable'], true);
        return _jsonResponse(
          {
            'identityId': 'identity-1',
            'isPublicDiscoverable': true,
          },
          200,
        );
      }

      return http.Response('{"message":"not found"}', 404);
    });
    final service = CustomApiIdentityService(
      authService: await _createAuthService(client),
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
      httpClient: client,
    );

    final claim = await service.createIdentityClaim(
      treeId: 'tree-1',
      personId: 'person-1',
    );
    final attributes = await service.updatePersonAttributeVisibility(
      treeId: 'tree-1',
      personId: 'person-1',
      visibility: 'cross-tree',
      attributes: {'name': 'cross-tree'},
    );
    final discoverable = await service.setPublicDiscoverability(true);

    expect(claim.id, 'claim-1');
    expect(attributes.single.visibility, 'cross-tree');
    expect(discoverable, isTrue);
    expect(seenPaths, contains('POST /v1/identity-claims'));
    expect(
      seenPaths,
      contains('PUT /v1/trees/tree-1/persons/person-1/attributes'),
    );
    expect(seenPaths, contains('PATCH /v1/identity-discovery/me'));
  });
}

http.Response _jsonResponse(Map<String, dynamic> body, int statusCode) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
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
