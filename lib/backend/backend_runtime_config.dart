import 'backend_provider_config.dart';

class BackendRuntimeConfig {
  const BackendRuntimeConfig({
    this.publicAppUrl = 'https://rodnya-tree.ru',
    this.apiBaseUrl = 'https://api.rodnya-tree.ru',
    this.webSocketBaseUrl = 'wss://api.rodnya-tree.ru',
    this.googleWebClientId = '',
    this.enableE2e = false,
  });

  static const String _publicAppUrlEnv = String.fromEnvironment(
    'RODNYA_PUBLIC_APP_URL',
    defaultValue: '',
  );
  static const String _apiBaseUrlEnv = String.fromEnvironment(
    'RODNYA_API_BASE_URL',
    defaultValue: '',
  );
  static const String _webSocketBaseUrlEnv = String.fromEnvironment(
    'RODNYA_WS_BASE_URL',
    defaultValue: '',
  );
  static const String _googleWebClientIdEnv = String.fromEnvironment(
    'RODNYA_GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );
  static const String _runtimePresetEnv = String.fromEnvironment(
    'RODNYA_RUNTIME_PRESET',
    defaultValue: '',
  );
  static const String _e2eEnv = String.fromEnvironment(
    'RODNYA_E2E',
    defaultValue: '',
  );

  final String publicAppUrl;
  final String apiBaseUrl;
  final String webSocketBaseUrl;
  final String googleWebClientId;
  final bool enableE2e;

  static BackendRuntimeConfig get current {
    return resolve(
      runtimePresetRaw: _runtimePresetEnv,
      hostRaw: Uri.base.host,
      publicAppUrlRaw: _publicAppUrlEnv,
      apiBaseUrlRaw: _apiBaseUrlEnv,
      webSocketBaseUrlRaw: _webSocketBaseUrlEnv,
      googleWebClientIdRaw: _googleWebClientIdEnv,
      e2eRaw: _e2eEnv,
    );
  }

  static BackendRuntimeConfig resolve({
    String runtimePresetRaw = '',
    String hostRaw = '',
    String publicAppUrlRaw = '',
    String apiBaseUrlRaw = '',
    String webSocketBaseUrlRaw = '',
    String googleWebClientIdRaw = '',
    String e2eRaw = '',
    BackendProviderConfig? providerConfig,
  }) {
    final fallbackApiBaseUrl = 'https://api.rodnya-tree.ru';
    final resolvedApiBaseUrl =
        _stringFromRaw(apiBaseUrlRaw, fallbackApiBaseUrl);
    final resolvedPublicAppUrl = _stringFromRaw(
      publicAppUrlRaw,
      'https://rodnya-tree.ru',
    );
    final resolvedWebSocketBaseUrl = _stringFromRaw(
      webSocketBaseUrlRaw,
      defaultWebSocketBaseUrl(resolvedApiBaseUrl),
    );
    final resolvedGoogleWebClientId = _stringFromRaw(googleWebClientIdRaw, '');
    final resolvedE2e = _boolFromRaw(e2eRaw, false);

    return BackendRuntimeConfig(
      publicAppUrl: resolvedPublicAppUrl,
      apiBaseUrl: resolvedApiBaseUrl,
      webSocketBaseUrl: resolvedWebSocketBaseUrl,
      googleWebClientId: resolvedGoogleWebClientId,
      enableE2e: resolvedE2e,
    );
  }

  static String defaultWebSocketBaseUrl(String apiBaseUrl) {
    final trimmed = apiBaseUrl.trim();
    if (trimmed.startsWith('https://')) {
      return 'wss://${trimmed.substring('https://'.length)}';
    }
    if (trimmed.startsWith('http://')) {
      return 'ws://${trimmed.substring('http://'.length)}';
    }
    return trimmed;
  }

  static String _stringFromRaw(String rawValue, String fallback) {
    final resolved = rawValue.trim();
    return resolved.isEmpty ? fallback : resolved;
  }

  static bool _boolFromRaw(String rawValue, bool fallback) {
    final resolved = rawValue.trim();
    if (resolved.isEmpty) {
      return fallback;
    }

    switch (resolved.toLowerCase()) {
      case 'true':
      case '1':
      case 'yes':
      case 'on':
        return true;
      case 'false':
      case '0':
      case 'no':
      case 'off':
        return false;
      default:
        return fallback;
    }
  }
}
