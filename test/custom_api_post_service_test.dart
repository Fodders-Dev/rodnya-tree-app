import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rodnya/backend/backend_runtime_config.dart';
import 'package:rodnya/backend/interfaces/storage_service_interface.dart';
import 'package:rodnya/services/custom_api_auth_service.dart';
import 'package:rodnya/services/custom_api_post_service.dart';
import 'package:rodnya/services/invitation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('CustomApiPostService returns server-truth snapshot from like endpoint',
      () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/v1/posts/post-1/like');
      expect(request.headers['authorization'], 'Bearer access-token');
      expect(request.body, isEmpty);

      return http.Response(
        jsonEncode({
          'id': 'post-1',
          'treeId': 'tree-1',
          'authorId': 'author-1',
          'authorName': 'Анна',
          'content': 'Семейная новость',
          'createdAt': '2026-04-13T10:00:00.000Z',
          'likedBy': ['user-1', 'user-2'],
          'commentCount': 3,
          'imageUrls': const [],
          'circleId': 'circle-1',
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

    final service = CustomApiPostService(
      authService: authService,
      storageService: _FakeStorageService(),
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
      httpClient: client,
    );

    final post = await service.toggleLike('post-1');

    expect(post.id, 'post-1');
    expect(post.likedBy, ['user-1', 'user-2']);
    expect(post.likeCount, 2);
    expect(post.commentCount, 3);
    expect(post.circleId, 'circle-1');
  });

  test('CustomApiPostService sends optional circleId on create', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/v1/posts');
      expect(request.headers['authorization'], 'Bearer access-token');
      expect(jsonDecode(request.body), {
        'treeId': 'tree-1',
        'content': 'Для близких',
        'imageUrls': const [],
        'isPublic': false,
        'scopeType': 'wholeTree',
        'anchorPersonIds': const [],
        'circleId': 'circle-1',
      });

      return http.Response(
        jsonEncode({
          'id': 'post-1',
          'treeId': 'tree-1',
          'authorId': 'author-1',
          'authorName': 'Анна',
          'content': 'Для близких',
          'createdAt': '2026-04-13T10:00:00.000Z',
          'likedBy': const [],
          'commentCount': 0,
          'imageUrls': const [],
          'circleId': 'circle-1',
        }),
        201,
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
    final service = CustomApiPostService(
      authService: authService,
      storageService: _FakeStorageService(),
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
      httpClient: client,
    );

    final post = await service.createPost(
      treeId: 'tree-1',
      content: 'Для близких',
      circleId: 'circle-1',
    );

    expect(post.circleId, 'circle-1');
  });

  test('CustomApiPostService refreshes session once before retrying feed',
      () async {
    var postRequests = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/v1/posts') {
        postRequests += 1;
        if (postRequests == 1) {
          expect(request.headers['authorization'], 'Bearer old-token');
          return http.Response.bytes(
            utf8.encode(jsonEncode({'message': 'Сессия истекла'})),
            401,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }

        expect(request.headers['authorization'], 'Bearer new-token');
        return http.Response(
          jsonEncode([
            {
              'id': 'post-1',
              'treeId': 'tree-1',
              'authorId': 'author-1',
              'authorName': 'Анна',
              'content': 'Семейная новость',
              'createdAt': '2026-04-13T10:00:00.000Z',
              'likedBy': const [],
              'commentCount': 0,
              'imageUrls': const [],
            }
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.url.path == '/v1/auth/refresh') {
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {'refreshToken': 'refresh-token'});
        return http.Response(
          jsonEncode({
            'accessToken': 'new-token',
            'refreshToken': 'new-refresh-token',
            'user': {
              'id': 'user-1',
              'email': 'dev@rodnya.app',
              'displayName': 'Dev User',
              'providerIds': ['password'],
            },
            'profileStatus': {
              'isComplete': true,
              'missingFields': const [],
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
        'accessToken': 'old-token',
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
    final service = CustomApiPostService(
      authService: authService,
      storageService: _FakeStorageService(),
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
      httpClient: client,
    );

    final posts = await service.getPosts(treeId: 'tree-1');

    expect(posts, hasLength(1));
    expect(posts.single.id, 'post-1');
    expect(postRequests, 2);
    expect(authService.accessToken, 'new-token');
  });
}

class _FakeStorageService implements StorageServiceInterface {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
