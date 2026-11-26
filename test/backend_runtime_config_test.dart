import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/backend_provider_config.dart';
import 'package:rodnya/backend/backend_runtime_config.dart';

void main() {
  test('BackendRuntimeConfig uses custom-api production defaults', () {
    const config = BackendRuntimeConfig();

    expect(config.publicAppUrl, 'https://rodnya-tree.ru');
    expect(config.apiBaseUrl, 'https://api.rodnya-tree.ru');
    expect(config.webSocketBaseUrl, 'wss://api.rodnya-tree.ru');
    expect(config.googleWebClientId, '');
    expect(config.enableE2e, isFalse);
  });

  test('BackendRuntimeConfig allows explicit runtime overrides', () {
    const config = BackendRuntimeConfig(
      publicAppUrl: 'https://family.example.ru',
      apiBaseUrl: 'https://api.family.example.ru',
      webSocketBaseUrl: 'wss://ws.family.example.ru',
      googleWebClientId: 'google-client-id',
      enableE2e: true,
    );

    expect(config.publicAppUrl, 'https://family.example.ru');
    expect(config.apiBaseUrl, 'https://api.family.example.ru');
    expect(config.webSocketBaseUrl, 'wss://ws.family.example.ru');
    expect(config.googleWebClientId, 'google-client-id');
    expect(config.enableE2e, isTrue);
  });

  test('BackendRuntimeConfig derives websocket url from api url', () {
    expect(
      BackendRuntimeConfig.defaultWebSocketBaseUrl(
        'https://api.family.example.ru',
      ),
      'wss://api.family.example.ru',
    );
    expect(
      BackendRuntimeConfig.defaultWebSocketBaseUrl(
        'http://127.0.0.1:8080',
      ),
      'ws://127.0.0.1:8080',
    );
  });

  test('BackendRuntimeConfig resolves prod_custom_api preset cleanly', () {
    final config = BackendRuntimeConfig.resolve(
      runtimePresetRaw: 'prod_custom_api',
      providerConfig: const BackendProviderConfig(),
    );

    expect(config.publicAppUrl, 'https://rodnya-tree.ru');
    expect(config.apiBaseUrl, 'https://api.rodnya-tree.ru');
    expect(config.webSocketBaseUrl, 'wss://api.rodnya-tree.ru');
  });

  test(
    'BackendRuntimeConfig resolve honors explicit overrides on top of preset',
    () {
      final config = BackendRuntimeConfig.resolve(
        runtimePresetRaw: 'prod_custom_api',
        publicAppUrlRaw: 'https://family.example.ru',
        apiBaseUrlRaw: 'https://api.family.example.ru',
        webSocketBaseUrlRaw: 'wss://socket.family.example.ru',
      );

      expect(config.publicAppUrl, 'https://family.example.ru');
      expect(config.apiBaseUrl, 'https://api.family.example.ru');
      expect(config.webSocketBaseUrl, 'wss://socket.family.example.ru');
    },
  );

  test('BackendRuntimeConfig resolve enables e2e hooks from runtime flag', () {
    final config = BackendRuntimeConfig.resolve(e2eRaw: 'true');

    expect(config.enableE2e, isTrue);
  });

  test(
    'BackendRuntimeConfig auto-switches to customApi runtime on rodnya production host',
    () {
      final config =
          BackendRuntimeConfig.resolve(hostRaw: 'www.rodnya-tree.ru');

      expect(config.publicAppUrl, 'https://rodnya-tree.ru');
      expect(config.apiBaseUrl, 'https://api.rodnya-tree.ru');
      expect(config.webSocketBaseUrl, 'wss://api.rodnya-tree.ru');
    },
  );
}
