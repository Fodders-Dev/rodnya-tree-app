// U4: юнит-тесты OTA-апдейтера sideload-сборок.
//   • парсинг ответа /v1/app/latest;
//   • сравнение версий (newer/equal/older/mandatory);
//   • выключенное состояние (204 / пустой конфиг);
//   • ⚠️ гейт источника — магазинная установка глушит апдейтер
//     (мокается), sideload — активирует.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rodnya/services/app_update_service.dart';

http.Client _latestClient(Map<String, dynamic>? latestJson) {
  return MockClient((request) async {
    if (request.url.path == '/v1/app/latest') {
      if (latestJson == null) {
        return http.Response('', 204);
      }
      return http.Response(
        jsonEncode(latestJson),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('not found', 404);
  });
}

AppUpdateService _buildService({
  Map<String, dynamic>? latestJson,
  int currentVersionCode = 40,
  String packageName = 'com.ahjkuio.rodnya_family_app',
  String? installer,
  bool installerThrows = false,
  bool isWeb = false,
  TargetPlatform platform = TargetPlatform.android,
  AppUpdateInstaller? updateInstaller,
}) {
  return AppUpdateService(
    apiBaseUrl: 'https://api.example.test',
    httpClient: _latestClient(latestJson),
    buildSnapshotProvider: () async => AppBuildSnapshot(
      versionCode: currentVersionCode,
      packageName: packageName,
    ),
    installerSourceProvider: () async {
      if (installerThrows) throw Exception('installer channel error');
      return installer;
    },
    isWeb: isWeb,
    platform: platform,
    updateInstaller: updateInstaller,
  );
}

Map<String, dynamic> _payload({
  int versionCode = 42,
  String? versionName = '1.0.3',
  String apkUrl = 'https://s3.ru-msk.example/rodnya/rodnya-1.0.3.apk',
  int minVersionCode = 0,
  String? notes = 'Чинят чаты',
}) {
  return {
    'versionCode': versionCode,
    'versionName': versionName,
    'apkUrl': apkUrl,
    'minVersionCode': minVersionCode,
    'notes': notes,
  };
}

void main() {
  setUp(AppUpdateService.debugResetSessionDismissal);
  tearDown(AppUpdateService.debugResetSessionDismissal);

  group('AppLatestVersion.tryParse', () {
    test('парсит полный ответ', () {
      final parsed = AppLatestVersion.tryParse(_payload());
      expect(parsed, isNotNull);
      expect(parsed!.versionCode, 42);
      expect(parsed.versionName, '1.0.3');
      expect(parsed.apkUrl, 'https://s3.ru-msk.example/rodnya/rodnya-1.0.3.apk');
      expect(parsed.notes, 'Чинят чаты');
    });

    test('null без versionCode или apkUrl', () {
      expect(AppLatestVersion.tryParse(_payload(versionCode: 0)), isNull);
      expect(AppLatestVersion.tryParse(_payload(apkUrl: '')), isNull);
    });

    test('null на не-Map / мусор', () {
      expect(AppLatestVersion.tryParse(null), isNull);
      expect(AppLatestVersion.tryParse('строка'), isNull);
      expect(AppLatestVersion.tryParse(42), isNull);
    });

    test('опциональные versionName/notes пустые → null', () {
      final parsed = AppLatestVersion.tryParse(
        _payload(versionName: '', notes: ''),
      );
      expect(parsed, isNotNull);
      expect(parsed!.versionName, isNull);
      expect(parsed.notes, isNull);
    });
  });

  group('сравнение версий', () {
    test('newer → optional', () async {
      final service = _buildService(
        latestJson: _payload(versionCode: 42),
        currentVersionCode: 40,
      );
      await service.checkForUpdate();
      expect(service.state.availability, AppUpdateAvailability.optional);
      expect(service.state.latest?.versionCode, 42);
      service.dispose();
    });

    test('equal → none', () async {
      final service = _buildService(
        latestJson: _payload(versionCode: 40),
        currentVersionCode: 40,
      );
      await service.checkForUpdate();
      expect(service.state.availability, AppUpdateAvailability.none);
      service.dispose();
    });

    test('older → none', () async {
      final service = _buildService(
        latestJson: _payload(versionCode: 38),
        currentVersionCode: 40,
      );
      await service.checkForUpdate();
      expect(service.state.availability, AppUpdateAvailability.none);
      service.dispose();
    });

    test('current < minVersionCode → mandatory', () async {
      final service = _buildService(
        latestJson: _payload(versionCode: 42, minVersionCode: 40),
        currentVersionCode: 30,
      );
      await service.checkForUpdate();
      expect(service.state.availability, AppUpdateAvailability.mandatory);
      expect(service.state.latest?.minVersionCode, 40);
      service.dispose();
    });

    test('current >= minVersionCode но newer → optional, не mandatory', () async {
      final service = _buildService(
        latestJson: _payload(versionCode: 42, minVersionCode: 40),
        currentVersionCode: 41,
      );
      await service.checkForUpdate();
      expect(service.state.availability, AppUpdateAvailability.optional);
      service.dispose();
    });
  });

  group('выключенное состояние', () {
    test('204 (фича выключена на бэке) → none', () async {
      final service = _buildService(latestJson: null);
      await service.checkForUpdate();
      expect(service.state.availability, AppUpdateAvailability.none);
      expect(service.state.latest, isNull);
      service.dispose();
    });

    test('web → none даже при newer', () async {
      final service = _buildService(
        latestJson: _payload(versionCode: 99),
        isWeb: true,
      );
      await service.checkForUpdate();
      expect(service.state.availability, AppUpdateAvailability.none);
      service.dispose();
    });

    test('не Android (iOS) → none', () async {
      final service = _buildService(
        latestJson: _payload(versionCode: 99),
        platform: TargetPlatform.iOS,
      );
      await service.checkForUpdate();
      expect(service.state.availability, AppUpdateAvailability.none);
      service.dispose();
    });

    test('dev-флейвор (.dev package) → none', () async {
      final service = _buildService(
        latestJson: _payload(versionCode: 99),
        packageName: 'com.ahjkuio.rodnya_family_app.dev',
      );
      await service.checkForUpdate();
      expect(service.state.availability, AppUpdateAvailability.none);
      service.dispose();
    });
  });

  group('гейт источника установки', () {
    test('установка из RuStore → апдейтер молчит (none)', () async {
      final service = _buildService(
        latestJson: _payload(versionCode: 99),
        installer: 'ru.vk.store',
      );
      await service.checkForUpdate();
      expect(service.state.availability, AppUpdateAvailability.none);
      service.dispose();
    });

    test('установка из Google Play → none', () async {
      final service = _buildService(
        latestJson: _payload(versionCode: 99),
        installer: 'com.android.vending',
      );
      await service.checkForUpdate();
      expect(service.state.availability, AppUpdateAvailability.none);
      service.dispose();
    });

    test('магазинный инсталлер регистронезависим (RU.VK.STORE) → none', () async {
      final service = _buildService(
        latestJson: _payload(versionCode: 99),
        installer: 'RU.VK.STORE',
      );
      await service.checkForUpdate();
      expect(service.state.availability, AppUpdateAvailability.none);
      service.dispose();
    });

    test('sideload (installer null) → апдейтер активен (optional)', () async {
      final service = _buildService(
        latestJson: _payload(versionCode: 99),
        installer: null,
      );
      await service.checkForUpdate();
      expect(service.state.availability, AppUpdateAvailability.optional);
      service.dispose();
    });

    test('неизвестный инсталлер (не магазин) → sideload → optional', () async {
      final service = _buildService(
        latestJson: _payload(versionCode: 99),
        installer: 'com.some.filemanager',
      );
      await service.checkForUpdate();
      expect(service.state.availability, AppUpdateAvailability.optional);
      service.dispose();
    });

    test('ошибка определения источника → fail-closed (none), не sideload', () async {
      // Хардинг: если источник установки определить нельзя (канал
      // упал), НЕ самообновляемся — иначе можно активироваться внутри
      // магазинной сборки при сломанном гейте.
      final service = _buildService(
        latestJson: _payload(versionCode: 99),
        installerThrows: true,
      );
      await service.checkForUpdate();
      expect(service.state.availability, AppUpdateAvailability.none);
      service.dispose();
    });

    test('RuStore-семейство по префиксу (ru.rustore.installer) → none', () async {
      final service = _buildService(
        latestJson: _payload(versionCode: 99),
        installer: 'ru.rustore.installer',
      );
      await service.checkForUpdate();
      expect(service.state.availability, AppUpdateAvailability.none);
      service.dispose();
    });
  });

  group('https-only apkUrl', () {
    test('http-ссылка → tryParse null (фича выключена)', () {
      final parsed = AppLatestVersion.tryParse({
        'versionCode': 42,
        'apkUrl': 'http://insecure.example/rodnya.apk',
      });
      expect(parsed, isNull);
    });

    test('https-ссылка парсится', () {
      final parsed = AppLatestVersion.tryParse({
        'versionCode': 42,
        'apkUrl': 'https://secure.example/rodnya.apk',
      });
      expect(parsed, isNotNull);
    });

    test('http apkUrl от бэка → состояние none', () async {
      final service = _buildService(
        latestJson: {
          'versionCode': 99,
          'apkUrl': 'http://insecure.example/rodnya.apk',
        },
      );
      await service.checkForUpdate();
      expect(service.state.availability, AppUpdateAvailability.none);
      service.dispose();
    });
  });

  group('сессионный дисмисс', () {
    test('dismissOptionalForSession ставит флаг и уведомляет', () async {
      final service = _buildService(latestJson: _payload(versionCode: 99));
      await service.checkForUpdate();
      expect(service.isOptionalDismissed, isFalse);

      var notified = 0;
      service.addListener(() => notified++);
      service.dismissOptionalForSession();

      expect(service.isOptionalDismissed, isTrue);
      expect(notified, 1);
      service.dispose();
    });
  });

  group('downloadAndInstall', () {
    test('зовёт инсталлер один раз и возвращается в idle', () async {
      var calls = 0;
      final service = _buildService(
        latestJson: _payload(versionCode: 99),
        updateInstaller: (latest, onProgress) async {
          calls++;
          onProgress(0.5);
        },
      );
      await service.checkForUpdate();
      await service.downloadAndInstall();

      expect(calls, 1);
      expect(service.downloadProgress.stage, AppUpdateDownloadStage.idle);
      service.dispose();
    });

    test('ошибка скачивания → стадия failed с текстом', () async {
      final service = _buildService(
        latestJson: _payload(versionCode: 99),
        updateInstaller: (latest, onProgress) async {
          throw Exception('network down');
        },
      );
      await service.checkForUpdate();
      await service.downloadAndInstall();

      expect(service.downloadProgress.stage, AppUpdateDownloadStage.failed);
      expect(service.downloadProgress.error, isNotNull);
      service.dispose();
    });
  });
}
