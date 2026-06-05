import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rodnya/backend/backend_runtime_config.dart';
import 'package:rodnya/backend/interfaces/storage_service_interface.dart';
import 'package:rodnya/models/post.dart' show TreeContentScopeType;
import 'package:rodnya/services/custom_api_auth_service.dart';
import 'package:rodnya/services/custom_api_gathering_service.dart';
import 'package:rodnya/services/invitation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeStorageService implements StorageServiceInterface {
  int uploadCalls = 0;
  String? lastBucket;

  @override
  Future<String?> uploadImage(XFile file, String bucket) async {
    uploadCalls++;
    lastBucket = bucket;
    return 'https://cdn.example.ru/${file.name}';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _gatheringJson = <String, dynamic>{
  'id': 'g1',
  'treeId': 'tree-1',
  'branchIds': ['tree-1'],
  'authorId': 'u1',
  'authorName': 'Анна',
  'authorPhotoUrl': null,
  'title': 'Шашлыки на даче',
  'description': 'Приезжайте',
  'startAt': '2026-07-01T15:00:00.000Z',
  'endAt': null,
  'isAllDay': false,
  'place': 'Дача',
  'scopeType': 'wholeTree',
  'anchorPersonIds': [],
  'circleId': null,
  'createdAt': '2026-06-01T10:00:00.000Z',
  'updatedAt': '2026-06-01T10:00:00.000Z',
  'rsvps': [],
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('getGatherings parses the list for a tree', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/v1/gatherings');
      expect(request.url.queryParameters['treeId'], 'tree-1');
      expect(request.headers['authorization'], 'Bearer access-token');
      return http.Response(
        jsonEncode([_gatheringJson]),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final service = CustomApiGatheringService(
      authService: await _createAuthService(client),
      storageService: _FakeStorageService(),
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
      httpClient: client,
    );

    final list = await service.getGatherings(treeId: 'tree-1');
    expect(list, hasLength(1));
    expect(list.first.title, 'Шашлыки на даче');
    expect(list.first.place, 'Дача');
    expect(list.first.startAt, DateTime.parse('2026-07-01T15:00:00.000Z'));
  });

  test('createGathering posts required fields and parses the result', () async {
    Map<String, dynamic>? sentBody;
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/v1/gatherings');
      sentBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode(_gatheringJson),
        201,
        headers: {'content-type': 'application/json'},
      );
    });

    final service = CustomApiGatheringService(
      authService: await _createAuthService(client),
      storageService: _FakeStorageService(),
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
      httpClient: client,
    );

    final created = await service.createGathering(
      treeId: 'tree-1',
      title: 'Шашлыки на даче',
      startAt: DateTime.parse('2026-07-01T15:00:00.000Z'),
      place: 'Дача',
      scopeType: TreeContentScopeType.wholeTree,
    );

    expect(created.title, 'Шашлыки на даче');
    expect(sentBody?['treeId'], 'tree-1');
    expect(sentBody?['title'], 'Шашлыки на даче');
    expect(sentBody?['startAt'], '2026-07-01T15:00:00.000Z');
    expect(sentBody?['place'], 'Дача');
    expect(sentBody?['scopeType'], 'wholeTree');
  });

  test('createGathering uploads images to the gatherings bucket', () async {
    Map<String, dynamic>? sentBody;
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/v1/gatherings');
      sentBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode(_gatheringJson),
        201,
        headers: {'content-type': 'application/json'},
      );
    });

    final storage = _FakeStorageService();
    final service = CustomApiGatheringService(
      authService: await _createAuthService(client),
      storageService: storage,
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
      httpClient: client,
    );

    await service.createGathering(
      treeId: 'tree-1',
      title: 'Фотовстреча',
      startAt: DateTime.parse('2026-07-01T15:00:00.000Z'),
      images: [XFile('photo.jpg')],
    );

    expect(storage.uploadCalls, 1);
    expect(storage.lastBucket, 'gatherings');
    expect(
        sentBody?['imageUrls'], contains('https://cdn.example.ru/photo.jpg'));
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
