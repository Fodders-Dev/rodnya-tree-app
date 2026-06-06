import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rodnya/backend/backend_runtime_config.dart';
import 'package:rodnya/backend/interfaces/storage_service_interface.dart';
import 'package:rodnya/services/custom_api_auth_service.dart';
import 'package:rodnya/services/custom_api_poll_service.dart';
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

const _pollJson = <String, dynamic>{
  'id': 'p1',
  'treeId': 'tree-1',
  'branchIds': ['tree-1'],
  'authorId': 'u1',
  'authorName': 'Анна',
  'authorPhotoUrl': null,
  'imageUrls': [],
  'question': 'Когда собираемся?',
  'options': [
    {'id': 'o1', 'text': 'Суббота'},
    {'id': 'o2', 'text': 'Воскресенье'},
  ],
  'allowMultiple': false,
  'closesAt': null,
  'scopeType': 'wholeTree',
  'anchorPersonIds': [],
  'circleId': null,
  'createdAt': '2026-06-01T10:00:00.000Z',
  'updatedAt': '2026-06-01T10:00:00.000Z',
  'responses': [],
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('getPolls parses the list for a tree', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/v1/polls');
      expect(request.url.queryParameters['treeId'], 'tree-1');
      return http.Response(
        jsonEncode([_pollJson]),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final service = CustomApiPollService(
      authService: await _createAuthService(client),
      storageService: _FakeStorageService(),
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
      httpClient: client,
    );

    final list = await service.getPolls(treeId: 'tree-1');
    expect(list, hasLength(1));
    expect(list.first.question, 'Когда собираемся?');
    expect(list.first.options.length, 2);
  });

  test('createPoll uploads images, sends question + options', () async {
    Map<String, dynamic>? sentBody;
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/v1/polls');
      sentBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode(_pollJson),
        201,
        headers: {'content-type': 'application/json'},
      );
    });

    final storage = _FakeStorageService();
    final service = CustomApiPollService(
      authService: await _createAuthService(client),
      storageService: storage,
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
      httpClient: client,
    );

    await service.createPoll(
      treeId: 'tree-1',
      question: 'Когда собираемся?',
      options: const ['Суббота', 'Воскресенье', ''], // empty trimmed away
      images: [XFile('photo.jpg')],
    );

    expect(storage.uploadCalls, 1);
    expect(storage.lastBucket, 'polls');
    expect(sentBody?['question'], 'Когда собираемся?');
    expect(sentBody?['options'], ['Суббота', 'Воскресенье']);
    expect(
        sentBody?['imageUrls'], contains('https://cdn.example.ru/photo.jpg'));
  });

  test('vote posts the optionIds and parses the result', () async {
    Map<String, dynamic>? sentBody;
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/v1/polls/p1/respond');
      sentBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode(_pollJson),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final service = CustomApiPollService(
      authService: await _createAuthService(client),
      storageService: _FakeStorageService(),
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
      httpClient: client,
    );

    final updated = await service.vote('p1', const ['o1']);
    expect(updated.question, 'Когда собираемся?');
    expect(sentBody?['optionIds'], ['o1']);
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
