// U4: виджет-тесты OTA-UI.
//   • баннер показывается при newer (optional), «Позже» дисмиссит;
//   • блок-экран при current < minVersionCode (mandatory) поверх приложения;
//   • гейт источника (RuStore-installer) → ни баннера, ни блок-экрана.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rodnya/services/app_update_service.dart';
import 'package:rodnya/theme/app_theme.dart';
import 'package:rodnya/widgets/app_update_ui.dart';

http.Client _client(Map<String, dynamic>? latestJson) {
  return MockClient((request) async {
    if (request.url.path == '/v1/app/latest') {
      if (latestJson == null) return http.Response('', 204);
      return http.Response(
        jsonEncode(latestJson),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('not found', 404);
  });
}

Future<AppUpdateService> _registerService({
  Map<String, dynamic>? latestJson,
  int currentVersionCode = 40,
  String? installer,
  AppUpdateInstaller? updateInstaller,
}) async {
  final service = AppUpdateService(
    apiBaseUrl: 'https://api.example.test',
    httpClient: _client(latestJson),
    buildSnapshotProvider: () async => AppBuildSnapshot(
      versionCode: currentVersionCode,
      packageName: 'com.ahjkuio.rodnya_family_app',
    ),
    installerSourceProvider: () async => installer,
    isWeb: false,
    platform: TargetPlatform.android,
    updateInstaller: updateInstaller ?? (latest, onProgress) async {},
  );
  await service.checkForUpdate();
  GetIt.I.registerSingleton<AppUpdateService>(service);
  return service;
}

Map<String, dynamic> _payload({
  int versionCode = 42,
  int minVersionCode = 0,
  String? notes = 'Чинят чаты и ленту',
}) {
  return {
    'versionCode': versionCode,
    'versionName': '1.0.3',
    'apkUrl': 'https://s3.ru-msk.example/rodnya/rodnya-1.0.3.apk',
    'minVersionCode': minVersionCode,
    'notes': notes,
  };
}

Widget _hostBanner() => MaterialApp(
      theme: AppTheme.lightTheme,
      home: const Scaffold(body: AppUpdateBanner()),
    );

Widget _hostGate() => MaterialApp(
      theme: AppTheme.lightTheme,
      home: const AppUpdateGate(
        child: Scaffold(body: Center(child: Text('Главный экран'))),
      ),
    );

void main() {
  setUp(() async {
    await GetIt.I.reset();
    AppUpdateService.debugResetSessionDismissal();
  });

  tearDown(() async {
    await GetIt.I.reset();
    AppUpdateService.debugResetSessionDismissal();
  });

  testWidgets('баннер показывается при optional + notes + кнопки', (tester) async {
    await _registerService(
      latestJson: _payload(versionCode: 42),
      currentVersionCode: 40,
    );

    await tester.pumpWidget(_hostBanner());
    await tester.pump();

    expect(find.byKey(const Key('app-update-banner')), findsOneWidget);
    expect(find.text('Доступно обновление'), findsOneWidget);
    expect(find.text('Чинят чаты и ленту'), findsOneWidget);
    expect(find.byKey(const Key('app-update-install-button')), findsOneWidget);
    expect(find.byKey(const Key('app-update-later-button')), findsOneWidget);
  });

  testWidgets('«Позже» дисмиссит баннер на сессию', (tester) async {
    await _registerService(
      latestJson: _payload(versionCode: 42),
      currentVersionCode: 40,
    );

    await tester.pumpWidget(_hostBanner());
    await tester.pump();
    expect(find.byKey(const Key('app-update-banner')), findsOneWidget);

    await tester.tap(find.byKey(const Key('app-update-later-button')));
    await tester.pump();

    expect(find.byKey(const Key('app-update-banner')), findsNothing);
  });

  testWidgets('нет обновления (none) → баннера нет', (tester) async {
    await _registerService(
      latestJson: _payload(versionCode: 40),
      currentVersionCode: 40,
    );

    await tester.pumpWidget(_hostBanner());
    await tester.pump();

    expect(find.byKey(const Key('app-update-banner')), findsNothing);
  });

  testWidgets('«Обновить» запускает скачивание/установку', (tester) async {
    var installerCalls = 0;
    await _registerService(
      latestJson: _payload(versionCode: 42),
      currentVersionCode: 40,
      updateInstaller: (latest, onProgress) async {
        installerCalls++;
      },
    );

    await tester.pumpWidget(_hostBanner());
    await tester.pump();

    await tester.tap(find.byKey(const Key('app-update-install-button')));
    await tester.pumpAndSettle();

    expect(installerCalls, 1);
  });

  testWidgets('блок-экран при mandatory поверх приложения', (tester) async {
    await _registerService(
      latestJson: _payload(versionCode: 42, minVersionCode: 40),
      currentVersionCode: 30,
    );

    await tester.pumpWidget(_hostGate());
    await tester.pump();

    expect(
      find.byKey(const Key('app-update-mandatory-screen')),
      findsOneWidget,
    );
    expect(find.text('Нужно обновить приложение'), findsOneWidget);
    expect(find.byKey(const Key('app-update-install-button')), findsOneWidget);
    // «Позже» на блок-экране нет — обновление обязательно.
    expect(find.byKey(const Key('app-update-later-button')), findsNothing);
    // Главный экран под блок-экраном не показан.
    expect(find.text('Главный экран'), findsNothing);
  });

  testWidgets('нет mandatory → гейт пропускает приложение', (tester) async {
    await _registerService(
      latestJson: _payload(versionCode: 42),
      currentVersionCode: 40,
    );

    await tester.pumpWidget(_hostGate());
    await tester.pump();

    expect(find.text('Главный экран'), findsOneWidget);
    expect(
      find.byKey(const Key('app-update-mandatory-screen')),
      findsNothing,
    );
  });

  testWidgets('гейт источника: RuStore-installer → ни баннера, ни блока',
      (tester) async {
    // Даже при несовместимо старой версии: установка из RuStore значит
    // обновлять должен магазин, а не наш апдейтер.
    await _registerService(
      latestJson: _payload(versionCode: 99, minVersionCode: 90),
      currentVersionCode: 10,
      installer: 'ru.vk.store',
    );

    await tester.pumpWidget(_hostGate());
    await tester.pump();

    expect(find.text('Главный экран'), findsOneWidget);
    expect(
      find.byKey(const Key('app-update-mandatory-screen')),
      findsNothing,
    );
  });

  testWidgets('сервис не зарегистрирован → виджеты молчат', (tester) async {
    // GetIt пуст (после reset). Баннер — пустой, гейт пропускает.
    await tester.pumpWidget(_hostGate());
    await tester.pump();
    expect(find.text('Главный экран'), findsOneWidget);

    await tester.pumpWidget(_hostBanner());
    await tester.pump();
    expect(find.byKey(const Key('app-update-banner')), findsNothing);
  });
}
