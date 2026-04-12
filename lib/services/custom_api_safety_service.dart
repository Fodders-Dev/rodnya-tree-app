import 'dart:convert';

import 'package:http/http.dart' as http;

import '../backend/backend_runtime_config.dart';
import '../backend/interfaces/safety_service_interface.dart';
import '../models/user_block_record.dart';
import 'custom_api_auth_service.dart';

class CustomApiSafetyService implements SafetyServiceInterface {
  CustomApiSafetyService({
    required CustomApiAuthService authService,
    required BackendRuntimeConfig runtimeConfig,
    http.Client? httpClient,
  })  : _authService = authService,
        _runtimeConfig = runtimeConfig,
        _httpClient = httpClient ?? http.Client();

  final CustomApiAuthService _authService;
  final BackendRuntimeConfig _runtimeConfig;
  final http.Client _httpClient;

  @override
  Future<void> reportTarget({
    required String targetType,
    required String targetId,
    required String reason,
    String? details,
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) async {
    await _requestJson(
      method: 'POST',
      path: '/v1/reports',
      body: {
        'targetType': targetType,
        'targetId': targetId,
        'reason': reason,
        if (details != null && details.trim().isNotEmpty)
          'details': details.trim(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      },
    );
  }

  @override
  Future<UserBlockRecord> blockUser({
    required String userId,
    String? reason,
    Map<String, dynamic> metadata = const <String, dynamic>{},
  }) async {
    final response = await _requestJson(
      method: 'POST',
      path: '/v1/blocks',
      body: {
        'userId': userId,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        if (metadata.isNotEmpty) 'metadata': metadata,
      },
    );
    final blockPayload = _asMap(response['block']);
    return UserBlockRecord.fromMap(blockPayload);
  }

  @override
  Future<List<UserBlockRecord>> listBlockedUsers() async {
    final response = await _requestJson(
      method: 'GET',
      path: '/v1/blocks',
    );
    final rawBlocks = response['blocks'];
    if (rawBlocks is! List) {
      return const <UserBlockRecord>[];
    }
    return rawBlocks
        .whereType<Map>()
        .map((entry) => UserBlockRecord.fromMap(_asMap(entry)))
        .toList();
  }

  @override
  Future<void> unblockUser(String blockId) async {
    await _requestJson(
      method: 'DELETE',
      path: '/v1/blocks/$blockId',
    );
  }

  Future<Map<String, dynamic>> _requestJson({
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    final headers = _headers();
    final uri = _buildUri(path);
    late http.Response response;

    switch (method) {
      case 'GET':
        response = await _httpClient.get(uri, headers: headers);
        break;
      case 'POST':
        response = await _httpClient.post(
          uri,
          headers: headers,
          body: jsonEncode(body ?? const <String, dynamic>{}),
        );
        break;
      case 'DELETE':
        response = await _httpClient.delete(uri, headers: headers);
        break;
      default:
        throw CustomApiException('Неподдерживаемый HTTP-метод: $method');
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) {
        return const <String, dynamic>{};
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return const <String, dynamic>{};
    }

    final decoded = response.body.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(response.body);
    final payload =
        decoded is Map<String, dynamic> ? decoded : const <String, dynamic>{};
    throw CustomApiException(
      payload['message']?.toString() ??
          'Safety Service Error: ${response.statusCode}',
      statusCode: response.statusCode,
    );
  }

  Uri _buildUri(String path) {
    var base = _runtimeConfig.apiBaseUrl.replaceAll(RegExp(r'/$'), '');
    final shouldForceHttps = base.startsWith('http://api.rodnya-tree.ru') ||
        base.startsWith('http://rodnya-tree.ru') ||
        base.startsWith('http://api.fodder-development.ru');
    if (shouldForceHttps) {
      base = 'https://${base.replaceFirst(RegExp(r'^http://'), '')}';
    }

    return Uri.parse('$base$path');
  }

  Map<String, String> _headers() {
    final token = _authService.accessToken;
    if (token == null || token.isEmpty) {
      throw const CustomApiException('Нет активной customApi session');
    }

    return <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (key, entryValue) => MapEntry(key.toString(), entryValue),
      );
    }
    return const <String, dynamic>{};
  }
}
