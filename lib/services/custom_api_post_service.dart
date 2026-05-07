import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../backend/backend_runtime_config.dart';
import '../backend/interfaces/post_service_interface.dart';
import '../backend/interfaces/storage_service_interface.dart';
import '../models/comment.dart';
import '../models/post.dart';
import '../models/reaction_summary.dart';
import 'custom_api_auth_service.dart';

class CustomApiPostService implements PostServiceInterface {
  CustomApiPostService({
    required CustomApiAuthService authService,
    required StorageServiceInterface storageService,
    required BackendRuntimeConfig runtimeConfig,
    http.Client? httpClient,
  })  : _authService = authService,
        _storageService = storageService,
        _runtimeConfig = runtimeConfig,
        _httpClient = httpClient ?? http.Client();

  final CustomApiAuthService _authService;
  final StorageServiceInterface _storageService;
  final BackendRuntimeConfig _runtimeConfig;
  final http.Client _httpClient;
  static const _requestTimeout = Duration(seconds: 12);

  @override
  Future<List<Post>> getPosts(
      {String? treeId, String? authorId, bool onlyBranches = false}) async {
    final queryParams = <String, String>{};
    if (treeId != null) queryParams['treeId'] = treeId;
    if (authorId != null) queryParams['authorId'] = authorId;
    if (onlyBranches) queryParams['scope'] = 'branches';

    try {
      final response = await _requestList(
        method: 'GET',
        path: '/v1/posts',
        queryParams: queryParams,
      );

      return response.map((json) => Post.fromJson(json)).toList();
    } on CustomApiPostException catch (error) {
      if (error.statusCode == 404) {
        return const <Post>[];
      }
      rethrow;
    }
  }

  @override
  Future<Post> createPost({
    required String treeId,
    required String content,
    List<XFile> images = const [],
    bool isPublic = false,
    TreeContentScopeType scopeType = TreeContentScopeType.wholeTree,
    List<String> anchorPersonIds = const [],
    String? circleId,
    List<String>? branchIds,
  }) async {
    final imageUrls = <String>[];
    for (final image in images) {
      final url = await _storageService.uploadImage(image, 'posts');
      if (url != null) imageUrls.add(url);
    }

    // Phase 3.4: only send branchIds if the caller passed a non-
    // empty list. The backend default ([treeId]) keeps the legacy
    // "single-branch publish" behavior when this is omitted.
    final cleanBranchIds = branchIds
        ?.map((b) => b.trim())
        .where((b) => b.isNotEmpty)
        .toSet()
        .toList(growable: false);

    final response = await _requestJson(
      method: 'POST',
      path: '/v1/posts',
      body: {
        'treeId': treeId,
        'content': content,
        'imageUrls': imageUrls,
        'isPublic': isPublic,
        'scopeType': scopeType == TreeContentScopeType.branches
            ? 'branches'
            : 'wholeTree',
        'anchorPersonIds': anchorPersonIds,
        if (circleId != null && circleId.trim().isNotEmpty)
          'circleId': circleId.trim(),
        if (cleanBranchIds != null && cleanBranchIds.isNotEmpty)
          'branchIds': cleanBranchIds,
      },
    );

    return Post.fromJson(response);
  }

  @override
  Future<void> deletePost(String postId) async {
    await _requestJson(
      method: 'DELETE',
      path: '/v1/posts/$postId',
    );
  }

  @override
  Future<List<Post>> searchPosts({
    required String query,
    String? treeId,
    int limit = 50,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const <Post>[];
    final params = <String, String>{
      'q': trimmed,
      if (treeId != null && treeId.trim().isNotEmpty) 'treeId': treeId.trim(),
      'limit': limit.toString(),
    };
    final response = await _requestList(
      method: 'GET',
      path: '/v1/posts/search',
      queryParams: params,
    );
    return response.map((json) => Post.fromJson(json)).toList();
  }

  @override
  Future<Post> toggleLike(String postId) async {
    final response = await _requestJson(
      method: 'POST',
      path: '/v1/posts/$postId/like',
    );
    return Post.fromJson(response);
  }

  @override
  Future<List<ReactionSummary>> togglePostReaction({
    required String postId,
    required String emoji,
  }) async {
    final normalized = emoji.trim();
    if (normalized.isEmpty) return const <ReactionSummary>[];
    final response = await _requestJson(
      method: 'POST',
      path: '/v1/posts/$postId/reactions',
      body: <String, dynamic>{'emoji': normalized},
    );
    return ReactionSummary.listFromDynamic(response['reactions']);
  }

  @override
  Future<List<ReactionSummary>> toggleCommentReaction({
    required String postId,
    required String commentId,
    required String emoji,
  }) async {
    final normalized = emoji.trim();
    if (normalized.isEmpty) return const <ReactionSummary>[];
    final response = await _requestJson(
      method: 'POST',
      path: '/v1/posts/$postId/comments/$commentId/reactions',
      body: <String, dynamic>{'emoji': normalized},
    );
    return ReactionSummary.listFromDynamic(response['reactions']);
  }

  @override
  Future<List<Comment>> getComments(String postId) async {
    final response = await _requestList(
      method: 'GET',
      path: '/v1/posts/$postId/comments',
    );

    return response.map((json) => Comment.fromJson(json)).toList();
  }

  @override
  Future<Comment> addComment(
    String postId,
    String content, {
    String? parentCommentId,
  }) async {
    final body = <String, dynamic>{'content': content};
    final trimmedParent = (parentCommentId ?? '').trim();
    if (trimmedParent.isNotEmpty) {
      body['parentCommentId'] = trimmedParent;
    }
    final response = await _requestJson(
      method: 'POST',
      path: '/v1/posts/$postId/comments',
      body: body,
    );

    return Comment.fromJson(response);
  }

  @override
  Future<void> deleteComment(String postId, String commentId) async {
    await _requestJson(
      method: 'DELETE',
      path: '/v1/posts/$postId/comments/$commentId',
    );
  }

  // Helper Methods

  Future<Map<String, dynamic>> _requestJson({
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    final response = await _sendRequest(
      method: method,
      path: path,
      body: body,
    );
    try {
      return _handleResponse(response);
    } on CustomApiPostException catch (error) {
      if (await _shouldRefreshAndRetry(error)) {
        final retryResponse = await _sendRequest(
          method: method,
          path: path,
          body: body,
        );
        return _handleResponse(retryResponse);
      }
      rethrow;
    }
  }

  Future<List<dynamic>> _requestList({
    required String method,
    required String path,
    Map<String, String>? queryParams,
  }) async {
    final response = await _sendRequest(
      method: method,
      path: path,
      queryParams: queryParams,
    );

    dynamic decoded;
    try {
      decoded = _handleResponse(response);
    } on CustomApiPostException catch (error) {
      if (!await _shouldRefreshAndRetry(error)) {
        rethrow;
      }
      final retryResponse = await _sendRequest(
        method: method,
        path: path,
        queryParams: queryParams,
      );
      decoded = _handleResponse(retryResponse);
    }
    if (decoded is List) return decoded;
    if (decoded is Map && decoded.containsKey('data')) {
      final data = decoded['data'];
      if (data is List) return data;
    }
    return [];
  }

  Future<http.Response> _sendRequest({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    Map<String, String>? queryParams,
  }) async {
    final uri = _buildUri(path, queryParams: queryParams);
    final headers = _headers();

    try {
      switch (method) {
        case 'GET':
          return await _httpClient
              .get(uri, headers: headers)
              .timeout(_requestTimeout);
        case 'POST':
          return await _httpClient
              .post(
                uri,
                headers: headers,
                body: body == null ? null : jsonEncode(body),
              )
              .timeout(_requestTimeout);
        case 'DELETE':
          return await _httpClient
              .delete(uri, headers: headers)
              .timeout(_requestTimeout);
        default:
          throw CustomApiPostException('Unsupported HTTP method: $method');
      }
    } on TimeoutException {
      throw const CustomApiPostException(
        'Backend не ответил за 12 секунд',
      );
    } on http.ClientException catch (error) {
      throw CustomApiPostException(error.message);
    }
  }

  Future<bool> _shouldRefreshAndRetry(CustomApiPostException error) async {
    if (error.statusCode != 401 && error.statusCode != 403) {
      return false;
    }
    await _authService.refreshSession();
    return _authService.accessToken != null;
  }

  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return <String, dynamic>{};
      return jsonDecode(response.body);
    }

    final errorData = response.body.isNotEmpty ? jsonDecode(response.body) : {};
    throw CustomApiPostException(
      errorData['message']?.toString() ??
          'Post Service Error: ${response.statusCode}',
      statusCode: response.statusCode,
    );
  }

  Uri _buildUri(String path, {Map<String, String>? queryParams}) {
    var base = _runtimeConfig.apiBaseUrl.replaceAll(RegExp(r'/$'), '');
    final shouldForceHttps = base.startsWith('http://api.rodnya-tree.ru') ||
        base.startsWith('http://rodnya-tree.ru') ||
        base.startsWith('http://api.fodder-development.ru');
    if (shouldForceHttps) {
      base = 'https://${base.replaceFirst(RegExp(r'^http://'), '')}';
    }

    final fullUrl = '$base$path';
    final uri = Uri.parse(fullUrl);

    if (queryParams != null && queryParams.isNotEmpty) {
      return uri.replace(queryParameters: queryParams);
    }
    return uri;
  }

  Map<String, String> _headers() {
    final token = _authService.accessToken;
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }
}

class CustomApiPostException implements Exception {
  const CustomApiPostException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
