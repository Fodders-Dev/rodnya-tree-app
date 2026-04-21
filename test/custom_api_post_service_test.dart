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
  });
}

class _FakeStorageService implements StorageServiceInterface {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
