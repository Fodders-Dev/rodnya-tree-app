import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rodnya/backend/backend_runtime_config.dart';
import 'package:rodnya/backend/interfaces/storage_service_interface.dart';
import 'package:rodnya/models/story.dart';
import 'package:rodnya/services/custom_api_auth_service.dart';
import 'package:rodnya/services/custom_api_story_service.dart';
import 'package:rodnya/services/invitation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('CustomApiStoryService reads list and normalizes payload', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/v1/stories');
      expect(request.url.queryParameters['treeId'], 'tree-1');
      expect(request.headers['authorization'], 'Bearer access-token');

      return http.Response(
        jsonEncode([
          {
            'id': 'story-1',
            'treeId': 'tree-1',
            'authorId': 'user-2',
            'authorName': 'Анна',
            'authorPhotoUrl':
                'http://api.rodnya-tree.ru/media/avatars/anna.jpg',
            'type': 'image',
            'text': 'Новый снимок',
            'mediaUrl': 'http://api.rodnya-tree.ru/media/stories/story-1.jpg',
            'thumbnailUrl':
                'http://api.rodnya-tree.ru/media/stories/story-1-thumb.jpg',
            'createdAt': '2026-04-13T09:00:00.000Z',
            'updatedAt': '2026-04-13T09:05:00.000Z',
            'expiresAt': '2026-04-14T09:00:00.000Z',
            'viewedBy': ['user-1'],
          },
        ]),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final authService = await _createAuthService(client);
    final service = CustomApiStoryService(
      authService: authService,
      storageService: _FakeStorageService(),
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
      httpClient: client,
    );

    final stories = await service.getStories(treeId: 'tree-1');

    expect(stories, hasLength(1));
    expect(stories.first.id, 'story-1');
    expect(stories.first.type, StoryType.image);
    expect(
      stories.first.mediaUrl,
      'https://api.rodnya-tree.ru/media/stories/story-1.jpg',
    );
    expect(stories.first.isViewedBy('user-1'), isTrue);
  });

  test('CustomApiStoryService creates, views and deletes stories', () async {
    final client = MockClient((request) async {
      expect(request.headers['authorization'], 'Bearer access-token');

      if (request.method == 'POST' && request.url.path == '/v1/stories') {
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        expect(payload['treeId'], 'tree-1');
        expect(payload['type'], 'text');
        expect(payload['text'], 'Привет семье');

        return http.Response(
          jsonEncode({
            'id': 'story-2',
            'treeId': 'tree-1',
            'authorId': 'user-1',
            'authorName': 'Dev User',
            'type': 'text',
            'text': 'Привет семье',
            'createdAt': '2026-04-13T10:00:00.000Z',
            'updatedAt': '2026-04-13T10:00:00.000Z',
            'expiresAt': '2026-04-14T10:00:00.000Z',
            'viewedBy': [],
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.method == 'POST' &&
          request.url.path == '/v1/stories/story-2/view') {
        return http.Response(
          jsonEncode({
            'id': 'story-2',
            'treeId': 'tree-1',
            'authorId': 'user-1',
            'authorName': 'Dev User',
            'type': 'text',
            'text': 'Привет семье',
            'createdAt': '2026-04-13T10:00:00.000Z',
            'updatedAt': '2026-04-13T10:02:00.000Z',
            'expiresAt': '2026-04-14T10:00:00.000Z',
            'viewedBy': ['user-1'],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.method == 'DELETE' &&
          request.url.path == '/v1/stories/story-2') {
        return http.Response('', 204);
      }

      return http.Response('not found', 404);
    });

    final authService = await _createAuthService(client);
    final service = CustomApiStoryService(
      authService: authService,
      storageService: _FakeStorageService(),
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
      httpClient: client,
    );

    final created = await service.createStory(
      treeId: 'tree-1',
      type: StoryType.text,
      text: 'Привет семье',
    );
    final viewed = await service.markViewed(created.id);
    await service.deleteStory(created.id);

    expect(created.id, 'story-2');
    expect(viewed.viewedBy, ['user-1']);
    expect(viewed.isViewedBy('user-1'), isTrue);
  });

  test('CustomApiStoryService does not send requests without active session',
      () async {
    final client = MockClient((request) async {
      fail('Story request should not reach network without session');
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

    final service = CustomApiStoryService(
      authService: authService,
      storageService: _FakeStorageService(),
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
      httpClient: client,
    );

    await expectLater(
      () => service.getStories(treeId: 'tree-1'),
      throwsA(
        isA<CustomApiStoryException>().having(
          (error) => error.statusCode,
          'statusCode',
          401,
        ),
      ),
    );
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

class _FakeStorageService implements StorageServiceInterface {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
