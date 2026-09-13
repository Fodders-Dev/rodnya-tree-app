// «Спросить историю» MVP-1 (STORY-REQUEST-MVP1-BRIEF.md §3.2, §3.7):
// CustomApiFamilyTreeService's StoryRequestCapableFamilyTreeService
// implementation against a fake HTTP client (§1 route contract — no
// live backend to test against, per the brief). Mirrors the MockClient
// pattern already used throughout custom_api_family_tree_service_test.dart.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rodnya/backend/backend_runtime_config.dart';
import 'package:rodnya/backend/interfaces/story_request_capable_family_tree_service.dart';
import 'package:rodnya/models/story_request.dart';
import 'package:rodnya/services/custom_api_auth_service.dart';
import 'package:rodnya/services/custom_api_family_tree_service.dart';
import 'package:rodnya/services/invitation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _requestJson({String status = 'pending'}) => {
      'id': 'sreq-1',
      'treeId': 'tree-1',
      'personId': 'person-1',
      'requesterUserId': 'user-1',
      'targetUserId': 'user-2',
      'question': {'text': 'Кто на фото?'},
      'status': status,
      'createdAt': '2026-09-13T10:00:00Z',
      'expiresAt': '2026-10-13T10:00:00Z',
    };

Future<StoryRequestCapableFamilyTreeService> _buildService(
  http.Client client,
) async {
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
    runtimeConfig: const BackendRuntimeConfig(apiBaseUrl: 'https://api.example.ru'),
    invitationService: InvitationService(),
  );

  final service = CustomApiFamilyTreeService(
    authService: authService,
    runtimeConfig: const BackendRuntimeConfig(apiBaseUrl: 'https://api.example.ru'),
    httpClient: client,
  );
  return service as StoryRequestCapableFamilyTreeService;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('createStoryRequest POSTs the contract §1 body and parses the request', () async {
    Map<String, dynamic>? sentBody;
    final client = MockClient((request) async {
      if (request.url.path == '/v1/story-requests' && request.method == 'POST') {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        expect(request.headers['authorization'], 'Bearer access-token');
        return http.Response(
          jsonEncode({'request': _requestJson()}),
          201,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{"message":"not found"}', 404);
    });

    final service = await _buildService(client);
    final result = await service.createStoryRequest(
      treeId: 'tree-1',
      personId: 'person-1',
      targetUserId: 'user-2',
      question: const StoryRequestQuestion(text: 'Кто на фото?', sourceQuestionId: 'old_photos'),
    );

    expect(sentBody, {
      'treeId': 'tree-1',
      'personId': 'person-1',
      'targetUserId': 'user-2',
      'question': {'text': 'Кто на фото?', 'sourceQuestionId': 'old_photos'},
    });
    expect(result?.id, 'sreq-1');
    expect(result?.status, StoryRequestStatus.pending);
  });

  test('createStoryRequest 409 → StoryRequestError DUPLICATE_PENDING with server message', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'message': 'Такой вопрос уже ждёт ответа'}),
        409,
        headers: {'content-type': 'application/json'},
      );
    });

    final service = await _buildService(client);
    await expectLater(
      () => service.createStoryRequest(
        treeId: 't',
        personId: 'p',
        targetUserId: 'u',
        question: const StoryRequestQuestion(text: 'Q'),
      ),
      throwsA(
        isA<StoryRequestError>()
            .having((e) => e.code, 'code', 'DUPLICATE_PENDING')
            .having((e) => e.message, 'message', 'Такой вопрос уже ждёт ответа')
            .having((e) => e.statusCode, 'statusCode', 409),
      ),
    );
  });

  test('createStoryRequest generic backend message falls back to friendly RU text', () async {
    final client = MockClient((request) async {
      // No JSON body at all → _requestJson's own "Ошибка backend (429)"
      // default message, which _mapStoryRequestException treats as
      // generic and replaces with the fallback copy.
      return http.Response('', 429);
    });

    final service = await _buildService(client);
    await expectLater(
      () => service.createStoryRequest(
        treeId: 't',
        personId: 'p',
        targetUserId: 'u',
        question: const StoryRequestQuestion(text: 'Q'),
      ),
      throwsA(
        isA<StoryRequestError>()
            .having((e) => e.code, 'code', 'TOO_MANY_PENDING')
            .having(
              (e) => e.message,
              'message',
              'Слишком много открытых вопросов — дождитесь ответов.',
            ),
      ),
    );
  });

  test('listStoryRequests GETs role/status query and parses the list', () async {
    Uri? seenUri;
    final client = MockClient((request) async {
      if (request.url.path == '/v1/me/story-requests') {
        seenUri = request.url;
        return http.Response(
          jsonEncode({
            'requests': [_requestJson(), _requestJson(status: 'answered')],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{"message":"not found"}', 404);
    });

    final service = await _buildService(client);
    final result = await service.listStoryRequests(
      role: 'issued',
      status: StoryRequestStatus.pending,
    );

    expect(seenUri?.queryParameters, {'role': 'issued', 'status': 'pending'});
    expect(result.length, 2);
    expect(result[1].status, StoryRequestStatus.answered);
  });

  test('listStoryRequests degrades to empty list on network failure', () async {
    final client = MockClient((request) async {
      throw Exception('boom');
    });
    final service = await _buildService(client);
    final result = await service.listStoryRequests(role: 'received');
    expect(result, isEmpty);
  });

  test('getStoryRequest GETs by id', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/v1/story-requests/sreq-1') {
        return http.Response(
          jsonEncode({'request': _requestJson()}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{"message":"not found"}', 404);
    });
    final service = await _buildService(client);
    final result = await service.getStoryRequest(requestId: 'sreq-1');
    expect(result?.id, 'sreq-1');
  });

  test('answerStoryRequest POSTs the answer payload and returns the updated request', () async {
    Map<String, dynamic>? sentBody;
    final client = MockClient((request) async {
      if (request.url.path == '/v1/story-requests/sreq-1/answer') {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'request': _requestJson(status: 'answered')}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{"message":"not found"}', 404);
    });
    final service = await _buildService(client);
    final result = await service.answerStoryRequest(
      requestId: 'sreq-1',
      answer: StoryRequestAnswerInput.text('Моя история'),
    );
    expect(sentBody, {'kind': 'text', 'text': 'Моя история'});
    expect(result?.status, StoryRequestStatus.answered);
  });

  test('answerStoryRequest 409 → NOT_PENDING', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'message': 'Вопрос уже закрыт'}),
        409,
        headers: {'content-type': 'application/json'},
      );
    });
    final service = await _buildService(client);
    await expectLater(
      () => service.answerStoryRequest(
        requestId: 'sreq-1',
        answer: StoryRequestAnswerInput.text('x'),
      ),
      throwsA(isA<StoryRequestError>().having((e) => e.code, 'code', 'NOT_PENDING')),
    );
  });

  test('declineStoryRequest POSTs decline', () async {
    var called = false;
    final client = MockClient((request) async {
      if (request.url.path == '/v1/story-requests/sreq-1/decline' &&
          request.method == 'POST') {
        called = true;
        return http.Response(
          jsonEncode({'request': _requestJson(status: 'declined')}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{"message":"not found"}', 404);
    });
    final service = await _buildService(client);
    final result = await service.declineStoryRequest(requestId: 'sreq-1');
    expect(called, isTrue);
    expect(result?.status, StoryRequestStatus.declined);
  });

  test('revokeStoryRequest POSTs revoke', () async {
    var called = false;
    final client = MockClient((request) async {
      if (request.url.path == '/v1/story-requests/sreq-1/revoke' &&
          request.method == 'POST') {
        called = true;
        return http.Response(
          jsonEncode({'request': _requestJson(status: 'revoked')}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{"message":"not found"}', 404);
    });
    final service = await _buildService(client);
    final result = await service.revokeStoryRequest(requestId: 'sreq-1');
    expect(called, isTrue);
    expect(result?.status, StoryRequestStatus.revoked);
  });

  test('revokeStoryRequest 403 → NOT_INITIATOR', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({'message': 'Не вы задавали вопрос'}),
        403,
        headers: {'content-type': 'application/json'},
      );
    });
    final service = await _buildService(client);
    await expectLater(
      () => service.revokeStoryRequest(requestId: 'sreq-1'),
      throwsA(isA<StoryRequestError>().having((e) => e.code, 'code', 'NOT_INITIATOR')),
    );
  });
}
