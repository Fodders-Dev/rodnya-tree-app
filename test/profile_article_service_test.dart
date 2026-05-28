// Profile Phase 2a (2026-05-29): article HTTP client + DTO tests.
//
// Uses http MockClient to assert the service hits the Phase 1 backend
// per-block endpoints with the right method/path/body and parses the
// responses (incl. the multi-author conflict flag). No live server.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rodnya/backend/backend_runtime_config.dart';
import 'package:rodnya/backend/interfaces/profile_article_service_interface.dart';
import 'package:rodnya/backend/models/profile_article.dart';
import 'package:rodnya/services/custom_api_auth_service.dart';
import 'package:rodnya/services/custom_api_profile_article_service.dart';
import 'package:rodnya/services/invitation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _config = BackendRuntimeConfig(apiBaseUrl: 'https://api.test.local');

Future<CustomApiProfileArticleService> buildService(MockClient client) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    'custom_api_session_v1',
    jsonEncode({
      'accessToken': 'test-token',
      'refreshToken': 'refresh-token',
      'userId': 'u1',
      'email': 'dev@rodnya.app',
      'displayName': 'Dev',
      'providerIds': ['password'],
      'isProfileComplete': true,
      'missingFields': const [],
    }),
  );
  // Auth bootstrap uses its own benign client — the test `client` may
  // simulate error responses for article endpoints, which must not
  // bleed into session loading.
  final authClient = MockClient((req) async => http.Response('{}', 200));
  final auth = await CustomApiAuthService.create(
    httpClient: authClient,
    preferences: prefs,
    runtimeConfig: _config,
    invitationService: InvitationService(),
  );
  return CustomApiProfileArticleService(
    authService: auth,
    runtimeConfig: _config,
    httpClient: client,
  );
}

void main() {
  group('ArticleBlock model', () {
    test('plainText joins paragraph spans (mention → fallback)', () {
      final block = ArticleBlock.fromJson({
        'id': 'b1',
        'type': 'paragraph',
        'content': {
          'spans': [
            {'text': 'вместе с '},
            {'type': 'mention', 'personId': 'p9', 'fallbackText': 'мужем'},
            {'text': ' они переехали'},
          ],
        },
        'createdAt': 't',
        'updatedAt': 't',
      });
      expect(block.plainText, 'вместе с мужем они переехали');
    });

    test('paragraphContent builds single span (empty → no spans)', () {
      expect(ArticleBlock.paragraphContent('Привет'), {
        'spans': [
          {'text': 'Привет'},
        ],
      });
      expect(ArticleBlock.paragraphContent(''), {'spans': []});
    });

    test('header helpers', () {
      final h = ArticleBlock.fromJson({
        'id': 'h1',
        'type': 'header',
        'content': {'text': 'Детство', 'level': 2},
        'createdAt': 't',
        'updatedAt': 't',
      });
      expect(h.isHeader, true);
      expect(h.headerText, 'Детство');
      expect(h.headerLevel, 2);
    });
  });

  test('getArticle GETs the article endpoint + parses blocks', () async {
    late http.Request captured;
    final client = MockClient((req) async {
      captured = req;
      return http.Response(
        jsonEncode({
          'article': {
            'id': 'a1',
            'personId': 'p1',
            'blocks': [
              {
                'id': 'b1',
                'type': 'paragraph',
                'content': {
                  'spans': [
                    {'text': 'Текст'},
                  ],
                },
                'createdAt': 't',
                'updatedAt': 't',
              },
            ],
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final article = await (await buildService(client)).getArticle('p1');
    expect(captured.method, 'GET');
    expect(captured.url.path, '/v1/persons/p1/article');
    expect(captured.headers['authorization'], 'Bearer test-token');
    expect(article.blocks.length, 1);
    expect(article.blocks.first.plainText, 'Текст');
  });

  test('appendBlock POSTs type + content', () async {
    late http.Request captured;
    final client = MockClient((req) async {
      captured = req;
      return http.Response(
        jsonEncode({
          'block': {
            'id': 'b-new',
            'type': 'paragraph',
            'content': {'spans': []},
            'authorUserId': 'u1',
            'createdAt': 't',
            'updatedAt': 't',
          },
        }),
        201,
      );
    });
    final block = await (await buildService(client)).appendBlock(
      'p1',
      type: 'paragraph',
      content: ArticleBlock.paragraphContent('Hi'),
    );
    expect(captured.method, 'POST');
    expect(captured.url.path, '/v1/persons/p1/article/blocks');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['type'], 'paragraph');
    expect(block.id, 'b-new');
  });

  test('updateBlock PATCHes with baseUpdatedAt + parses conflict flag',
      () async {
    late http.Request captured;
    final client = MockClient((req) async {
      captured = req;
      return http.Response(
        jsonEncode({
          'block': {
            'id': 'b1',
            'type': 'paragraph',
            'content': {
              'spans': [
                {'text': 'new'},
              ],
            },
            'authorUserId': 'u2',
            'createdAt': 't',
            'updatedAt': 't2',
          },
          'conflict': true,
        }),
        200,
      );
    });
    final result = await (await buildService(client)).updateBlock(
      'p1',
      'b1',
      content: ArticleBlock.paragraphContent('new'),
      baseUpdatedAt: 't0',
    );
    expect(captured.method, 'PATCH');
    expect(captured.url.path, '/v1/persons/p1/article/blocks/b1');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['baseUpdatedAt'], 't0');
    expect(result.conflict, true);
    expect(result.block.authorUserId, 'u2');
  });

  test('removeBlock DELETEs the block', () async {
    late http.Request captured;
    final client = MockClient((req) async {
      captured = req;
      return http.Response(jsonEncode({'removed': true, 'blockId': 'b1'}), 200);
    });
    await (await buildService(client)).removeBlock('p1', 'b1');
    expect(captured.method, 'DELETE');
    expect(captured.url.path, '/v1/persons/p1/article/blocks/b1');
  });

  test('reorderBlocks PUTs the order array', () async {
    late http.Request captured;
    final client = MockClient((req) async {
      captured = req;
      return http.Response(
        jsonEncode({
          'article': {'personId': 'p1', 'blocks': []},
        }),
        200,
      );
    });
    await (await buildService(client)).reorderBlocks('p1', ['b2', 'b1']);
    expect(captured.method, 'PUT');
    expect(captured.url.path, '/v1/persons/p1/article/blocks/order');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['order'], ['b2', 'b1']);
  });

  test('non-2xx throws ProfileArticleException with backend message',
      () async {
    final client = MockClient((req) async {
      return http.Response(
        jsonEncode({'message': 'Человек не найден'}),
        404,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final service = await buildService(client);
    await expectLater(
      service.getArticle('missing'),
      throwsA(
        isA<ProfileArticleException>().having(
          (e) => e.statusCode,
          'statusCode',
          404,
        ),
      ),
    );
  });
}
