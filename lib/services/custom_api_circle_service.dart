import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../backend/models/user_facing_exception.dart';
import '../backend/backend_runtime_config.dart';
import '../backend/interfaces/circle_service_interface.dart';
import '../models/audience_preset.dart';
import '../models/circle.dart';
import '../utils/safe_json_decode.dart';
import 'custom_api_auth_service.dart';

class CustomApiCircleService implements CircleServiceInterface {
  CustomApiCircleService({
    required CustomApiAuthService authService,
    required BackendRuntimeConfig runtimeConfig,
    http.Client? httpClient,
  })  : _authService = authService,
        _runtimeConfig = runtimeConfig,
        _httpClient = httpClient ?? http.Client();

  final CustomApiAuthService _authService;
  final BackendRuntimeConfig _runtimeConfig;
  final http.Client _httpClient;

  static const _requestTimeout = Duration(seconds: 12);

  @override
  Future<List<FamilyCircle>> getCircles(String treeId) async {
    final normalizedTreeId = treeId.trim();
    if (normalizedTreeId.isEmpty) {
      return const <FamilyCircle>[];
    }

    final response = await _httpClient
        .get(
          _buildUri('/v1/trees/$normalizedTreeId/circles'),
          headers: _headers(),
        )
        .timeout(_requestTimeout);
    final decoded = _handleResponse(response);
    final rawCircles = decoded is Map<String, dynamic>
        ? decoded['circles']
        : decoded is List<dynamic>
            ? decoded
            : null;
    if (rawCircles is! List<dynamic>) {
      return const <FamilyCircle>[];
    }

    return rawCircles
        .whereType<Map<String, dynamic>>()
        .map(FamilyCircle.fromJson)
        .where((circle) => circle.id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<AudiencePresetsResponse> getAudiencePresets(String treeId) async {
    final normalizedTreeId = treeId.trim();
    if (normalizedTreeId.isEmpty) {
      return AudiencePresetsResponse.empty;
    }
    try {
      final response = await _httpClient
          .get(
            _buildUri('/v1/trees/$normalizedTreeId/audience-presets'),
            headers: _headers(),
          )
          .timeout(_requestTimeout);
      final decoded = _handleResponse(response);
      if (decoded is Map<String, dynamic>) {
        return AudiencePresetsResponse.fromJson(decoded);
      }
      return AudiencePresetsResponse.empty;
    } on CustomApiCircleException catch (error) {
      // 404 = older backend without the endpoint, or user has no
      // person on the tree. Either way: graceful degrade to no
      // presets so the picker doesn't error out.
      if (error.statusCode == 404) {
        return AudiencePresetsResponse.empty;
      }
      rethrow;
    }
  }

  @override
  Future<FamilyCircle> createCircle({
    required String treeId,
    required String name,
    String? description,
  }) async {
    final normalizedTreeId = treeId.trim();
    final response = await _httpClient
        .post(
          _buildUri('/v1/trees/$normalizedTreeId/circles'),
          headers: _jsonHeaders(),
          body: jsonEncode({
            'name': name.trim(),
            if (description != null) 'description': description.trim(),
          }),
        )
        .timeout(_requestTimeout);
    final decoded = _handleResponse(response);
    return FamilyCircle.fromJson(
      Map<String, dynamic>.from(decoded as Map? ?? const {}),
    );
  }

  @override
  Future<FamilyCircle> updateCircle({
    required String treeId,
    required String circleId,
    required String name,
    String? description,
  }) async {
    final response = await _httpClient
        .patch(
          _buildUri('/v1/trees/${treeId.trim()}/circles/${circleId.trim()}'),
          headers: _jsonHeaders(),
          body: jsonEncode({
            'name': name.trim(),
            if (description != null) 'description': description.trim(),
          }),
        )
        .timeout(_requestTimeout);
    final decoded = _handleResponse(response);
    return FamilyCircle.fromJson(
      Map<String, dynamic>.from(decoded as Map? ?? const {}),
    );
  }

  @override
  Future<List<String>> getCircleMemberIdentityIds({
    required String treeId,
    required String circleId,
  }) async {
    final response = await _httpClient
        .get(
          _buildUri(
            '/v1/trees/${treeId.trim()}/circles/${circleId.trim()}/members',
          ),
          headers: _headers(),
        )
        .timeout(_requestTimeout);
    final decoded = _handleResponse(response);
    final rawMembers =
        decoded is Map ? decoded['members'] as List<dynamic>? : null;
    if (rawMembers == null) {
      return const <String>[];
    }
    return rawMembers
        .whereType<Map>()
        .map((entry) => entry['identityId']?.toString().trim() ?? '')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<FamilyCircle> replaceCircleMembers({
    required String treeId,
    required String circleId,
    List<String> identityIds = const <String>[],
    List<String> personIds = const <String>[],
  }) async {
    final response = await _httpClient
        .put(
          _buildUri(
            '/v1/trees/${treeId.trim()}/circles/${circleId.trim()}/members',
          ),
          headers: _jsonHeaders(),
          body: jsonEncode({
            'identityIds': identityIds,
            'personIds': personIds,
          }),
        )
        .timeout(_requestTimeout);
    final decoded = _handleResponse(response);
    return FamilyCircle.fromJson(
      Map<String, dynamic>.from(decoded as Map? ?? const {}),
    );
  }

  @override
  Future<void> deleteCircle({
    required String treeId,
    required String circleId,
  }) async {
    final response = await _httpClient
        .delete(
          _buildUri('/v1/trees/${treeId.trim()}/circles/${circleId.trim()}'),
          headers: _headers(),
        )
        .timeout(_requestTimeout);
    _handleResponse(response);
  }

  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) {
        return <String, dynamic>{};
      }
      final decoded = tryDecodeJsonValue(response.body);
      if (decoded == null) {
        throw CustomApiCircleException(
          'Circle Service Error: некорректный ответ сервера (${response.statusCode})',
          statusCode: response.statusCode,
        );
      }
      return decoded;
    }

    final errorData =
        tryDecodeJsonMap(response.body) ?? const <String, dynamic>{};
    throw CustomApiCircleException(
      errorData['message']?.toString() ??
          'Circle Service Error: ${response.statusCode}',
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
      throw const CustomApiCircleException(
        'Нет активной сессии',
        statusCode: 401,
      );
    }

    return {
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Map<String, String> _jsonHeaders() {
    return {
      ..._headers(),
      'Content-Type': 'application/json',
    };
  }
}

class CustomApiCircleException implements UserFacingApiException {
  const CustomApiCircleException(this.message, {this.statusCode});

  @override
  final String message;
  @override
  final int? statusCode;

  @override
  String toString() => message;
}
