import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../backend/backend_runtime_config.dart';
import '../utils/client_instance_id.dart';
import 'custom_api_auth_service.dart';

class CustomApiDiagnosticsService {
  CustomApiDiagnosticsService({
    required CustomApiAuthService authService,
    required BackendRuntimeConfig runtimeConfig,
    http.Client? httpClient,
  })  : _authService = authService,
        _runtimeConfig = runtimeConfig,
        _httpClient = httpClient ?? http.Client();

  final CustomApiAuthService _authService;
  final BackendRuntimeConfig _runtimeConfig;
  final http.Client _httpClient;

  Future<String?> capture({
    required String type,
    required String message,
    Map<String, dynamic> context = const <String, dynamic>{},
    Object? error,
    StackTrace? stackTrace,
  }) async {
    final token = _authService.accessToken;
    if (token == null || token.isEmpty) {
      return null;
    }

    final packageInfo = await _packageInfoOrNull();
    final body = <String, dynamic>{
      'type': type,
      'message': message,
      'platform': <String, dynamic>{
        'isWeb': kIsWeb,
        'targetPlatform': defaultTargetPlatform.name,
        'clientInstanceId': ClientInstanceId.current,
      },
      'appVersion': packageInfo == null
          ? null
          : <String, dynamic>{
              'version': packageInfo.version,
              'buildNumber': packageInfo.buildNumber,
            },
      'context': context,
      if (error != null) 'error': error.toString(),
      if (stackTrace != null) 'stackTrace': stackTrace.toString(),
    };

    try {
      final response = await _httpClient.post(
        _buildUri('/v1/diagnostics/client-events'),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
          'X-Client-Instance-Id': ClientInstanceId.current,
        },
        body: jsonEncode(body),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'Client diagnostics failed: ${response.statusCode} ${response.body}',
        );
        return null;
      }
      if (response.body.isEmpty) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded['eventId']?.toString();
      }
    } catch (diagnosticsError) {
      debugPrint('Client diagnostics failed: $diagnosticsError');
    }
    return null;
  }

  Uri _buildUri(String path) {
    final normalizedBase = _runtimeConfig.apiBaseUrl.replaceAll(
      RegExp(r'/$'),
      '',
    );
    return Uri.parse('$normalizedBase$path');
  }

  Future<PackageInfo?> _packageInfoOrNull() async {
    try {
      return await PackageInfo.fromPlatform();
    } catch (_) {
      return null;
    }
  }
}
