// Profile Phase 2 (2026-05-29): article HTTP client.
//
// Mirrors CustomApiStorageService conventions (auth token + runtime
// config + _requestJson). Talks to the Phase 1 backend per-block API
// (profile-article-routes.js). url-addressed media — block content is
// passed through verbatim.

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../backend/backend_runtime_config.dart';
import '../backend/interfaces/profile_article_service_interface.dart';
import '../backend/models/profile_article.dart';
import 'custom_api_auth_service.dart';

class CustomApiProfileArticleService
    implements ProfileArticleServiceInterface {
  CustomApiProfileArticleService({
    required CustomApiAuthService authService,
    required BackendRuntimeConfig runtimeConfig,
    http.Client? httpClient,
  })  : _authService = authService,
        _runtimeConfig = runtimeConfig,
        _httpClient = httpClient ?? http.Client();

  final CustomApiAuthService _authService;
  final BackendRuntimeConfig _runtimeConfig;
  final http.Client _httpClient;

  String _base(String personId) =>
      '/v1/persons/${Uri.encodeComponent(personId)}/article';

  @override
  Future<ProfileArticle> getArticle(String personId) async {
    final res = await _requestJson(method: 'GET', path: _base(personId));
    final raw = res['article'];
    if (raw is Map) {
      return ProfileArticle.fromJson(Map<String, dynamic>.from(raw));
    }
    return ProfileArticle(personId: personId, blocks: const <ArticleBlock>[]);
  }

  @override
  Future<ArticleBlock> appendBlock(
    String personId, {
    required String type,
    required Map<String, dynamic> content,
  }) async {
    final res = await _requestJson(
      method: 'POST',
      path: '${_base(personId)}/blocks',
      body: {'type': type, 'content': content},
    );
    return ArticleBlock.fromJson(
      Map<String, dynamic>.from(res['block'] as Map),
    );
  }

  @override
  Future<ArticleBlockUpdateResult> updateBlock(
    String personId,
    String blockId, {
    required Map<String, dynamic> content,
    String? baseUpdatedAt,
  }) async {
    final res = await _requestJson(
      method: 'PATCH',
      path: '${_base(personId)}/blocks/${Uri.encodeComponent(blockId)}',
      body: {
        'content': content,
        if (baseUpdatedAt != null) 'baseUpdatedAt': baseUpdatedAt,
      },
    );
    return ArticleBlockUpdateResult(
      block: ArticleBlock.fromJson(
        Map<String, dynamic>.from(res['block'] as Map),
      ),
      conflict: res['conflict'] == true,
    );
  }

  @override
  Future<void> removeBlock(String personId, String blockId) async {
    await _requestJson(
      method: 'DELETE',
      path: '${_base(personId)}/blocks/${Uri.encodeComponent(blockId)}',
    );
  }

  @override
  Future<ProfileArticle> reorderBlocks(
    String personId,
    List<String> orderedBlockIds,
  ) async {
    final res = await _requestJson(
      method: 'PUT',
      path: '${_base(personId)}/blocks/order',
      body: {'order': orderedBlockIds},
    );
    final raw = res['article'];
    if (raw is Map) {
      return ProfileArticle.fromJson(Map<String, dynamic>.from(raw));
    }
    return ProfileArticle(personId: personId, blocks: const <ArticleBlock>[]);
  }

  @override
  Future<List<ArticleHistoryEntry>> getArticleHistory(String personId) async {
    final res = await _requestJson(
      method: 'GET',
      path: '${_base(personId)}/history',
    );
    final raw = res['history'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) =>
              ArticleHistoryEntry.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    }
    return const <ArticleHistoryEntry>[];
  }

  Future<Map<String, dynamic>> _requestJson({
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    final uri = _buildUri(path);
    final headers = _headers();
    final encoded = body == null ? null : jsonEncode(body);
    late http.Response response;
    switch (method) {
      case 'GET':
        response = await _httpClient.get(uri, headers: headers);
        break;
      case 'POST':
        response = await _httpClient.post(uri, headers: headers, body: encoded);
        break;
      case 'PATCH':
        response =
            await _httpClient.patch(uri, headers: headers, body: encoded);
        break;
      case 'PUT':
        response = await _httpClient.put(uri, headers: headers, body: encoded);
        break;
      case 'DELETE':
        response =
            await _httpClient.delete(uri, headers: headers, body: encoded);
        break;
      default:
        throw const ProfileArticleException('Неподдерживаемый HTTP-метод');
    }

    if (response.body.isEmpty) {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return const <String, dynamic>{};
      }
      throw ProfileArticleException(
        'Пустой ответ от backend',
        statusCode: response.statusCode,
      );
    }

    final dynamic decoded = jsonDecode(response.body);
    final payload = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{'data': decoded};

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return payload;
    }

    throw ProfileArticleException(
      payload['message']?.toString() ??
          payload['error']?.toString() ??
          'Ошибка биографии (${response.statusCode})',
      statusCode: response.statusCode,
    );
  }

  Uri _buildUri(String path) {
    var base = _runtimeConfig.apiBaseUrl.replaceAll(RegExp(r'/$'), '');
    final forceHttps = base.startsWith('http://api.rodnya-tree.ru') ||
        base.startsWith('http://rodnya-tree.ru') ||
        base.startsWith('http://api.fodder-development.ru');
    if (forceHttps) {
      base = 'https://${base.replaceFirst(RegExp(r'^http://'), '')}';
    }
    return Uri.parse('$base$path');
  }

  Map<String, String> _headers() {
    final token = _authService.accessToken;
    if (token == null || token.isEmpty) {
      throw const ProfileArticleException('Нет активной сессии');
    }
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }
}
