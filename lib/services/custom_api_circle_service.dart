import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../backend/backend_runtime_config.dart';
import '../backend/interfaces/circle_service_interface.dart';
import '../models/audience_preset.dart';
import '../models/circle.dart';
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

  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) {
        return <String, dynamic>{};
      }
      return jsonDecode(response.body);
    }

    final errorData = response.body.isNotEmpty ? jsonDecode(response.body) : {};
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
}

class CustomApiCircleException implements Exception {
  const CustomApiCircleException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
