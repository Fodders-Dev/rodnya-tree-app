// U4/U6: юнит-тесты OTA-апдейтера sideload-сборок.
//   • парсинг ответа /v1/app/latest;
//   • сравнение версий (newer/equal/older/mandatory);
//   • выключенное состояние (204 / пустой конфиг);
//   • ⚠️ гейт источника — магазинная установка глушит апдейтер
//     (мокается), sideload — активирует;
//   • U6: целостность скачанного APK (размер/sha256), очистка частичного
//     файла, fail-closed на нативный sentinel.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
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

  group('U6: натив-sentinel fail-closed', () {
    test('источник = kInstallerSourceUnavailable → none (как при ошибке)', () async {
      // Натив на внутренней ошибке возвращает этот маркер вместо null —
      // Dart одинаково fail-close'ит и на ошибке канала, и на ошибке
      // натива.
      final service = _buildService(
        latestJson: _payload(versionCode: 99),
        installer: kInstallerSourceUnavailable,
      );
      await service.checkForUpdate();
      expect(service.state.availability, AppUpdateAvailability.none);
      service.dispose();
    });
  });

  group('U6: mandatory-гейт на уровне сервиса', () {
    test('магазинный installer глушит даже mandatory (none, не блок-экран)',
        () async {
      // current(10) < minVersionCode(90) — была бы mandatory, но установка
      // из RuStore → обновляет магазин, наш сервис молчит на УРОВНЕ
      // состояния (не только в виджете).
      final service = _buildService(
        latestJson: _payload(versionCode: 99, minVersionCode: 90),
        currentVersionCode: 10,
        installer: 'ru.vk.store',
      );
      await service.checkForUpdate();
      expect(service.state.availability, AppUpdateAvailability.none);
      service.dispose();
    });
  });

  group('U6: целостность скачивания (реальный installer)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('rodnya_apk_test');
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    List<File> apkFiles() => tempDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('rodnya-update-'))
        .toList();

    Future<AppUpdateService> build({
      required List<int> apkBytes,
      int? apkContentLength,
      int apkStatus = 200,
      String? sha256Hex,
      required List<String> openedPaths,
    }) async {
      final client = MockClient.streaming((request, bodyStream) async {
        final path = request.url.path;
        if (path == '/v1/app/latest') {
          final body = utf8.encode(jsonEncode({
            'versionCode': 99,
            'apkUrl': 'https://s3.example/rodnya.apk',
            if (sha256Hex != null) 'sha256': sha256Hex,
          }));
          return http.StreamedResponse(
            Stream.fromIterable([body]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (path.endsWith('.apk')) {
          return http.StreamedResponse(
            Stream.fromIterable([apkBytes]),
            apkStatus,
            contentLength: apkContentLength ?? apkBytes.length,
          );
        }
        return http.StreamedResponse(const Stream.empty(), 404);
      });
      final service = AppUpdateService(
        apiBaseUrl: 'https://api.example.test',
        httpClient: client,
        buildSnapshotProvider: () async => const AppBuildSnapshot(
          versionCode: 40,
          packageName: 'com.ahjkuio.rodnya_family_app',
        ),
        installerSourceProvider: () async => null,
        isWeb: false,
        platform: TargetPlatform.android,
        downloadDirectoryProvider: () async => tempDir,
        installerOpener: (path) async => openedPaths.add(path),
      );
      await service.checkForUpdate();
      return service;
    }

    test('успех (без sha) → installer открыт, файл скачан', () async {
      final opened = <String>[];
      final service = await build(
        apkBytes: List<int>.generate(64, (i) => i),
        openedPaths: opened,
      );
      await service.downloadAndInstall();

      expect(service.downloadProgress.stage, AppUpdateDownloadStage.idle);
      expect(opened, hasLength(1));
      expect(apkFiles(), hasLength(1)); // скачанный APK остаётся для установки
      service.dispose();
    });

    test('размер не сошёлся с Content-Length → отмена + частичный удалён',
        () async {
      final opened = <String>[];
      final service = await build(
        apkBytes: List<int>.generate(64, (i) => i),
        apkContentLength: 999, // сервер «обещал» больше, чем пришло
        openedPaths: opened,
      );
      await service.downloadAndInstall();

      expect(service.downloadProgress.stage, AppUpdateDownloadStage.failed);
      expect(opened, isEmpty); // неполный файл НЕ открыт
      expect(apkFiles(), isEmpty); // частичный файл удалён
      service.dispose();
    });

    test('http-ошибка (500) → отмена + частичный файл не остаётся', () async {
      final opened = <String>[];
      final service = await build(
        apkBytes: List<int>.generate(64, (i) => i),
        apkStatus: 500,
        openedPaths: opened,
      );
      await service.downloadAndInstall();

      expect(service.downloadProgress.stage, AppUpdateDownloadStage.failed);
      expect(opened, isEmpty);
      expect(apkFiles(), isEmpty);
      service.dispose();
    });

    test('sha256 совпал → installer открыт', () async {
      final bytes = List<int>.generate(128, (i) => (i * 7) % 256);
      final hash = sha256.convert(bytes).toString();
      final opened = <String>[];
      final service = await build(
        apkBytes: bytes,
        sha256Hex: hash,
        openedPaths: opened,
      );
      await service.downloadAndInstall();

      expect(service.downloadProgress.stage, AppUpdateDownloadStage.idle);
      expect(opened, hasLength(1));
      service.dispose();
    });

    test('sha256 не совпал → отмена + файл удалён, installer НЕ открыт',
        () async {
      final bytes = List<int>.generate(128, (i) => (i * 7) % 256);
      final opened = <String>[];
      final service = await build(
        apkBytes: bytes,
        sha256Hex: 'deadbeef' * 8, // заведомо неверный хэш
        openedPaths: opened,
      );
      await service.downloadAndInstall();

      expect(service.downloadProgress.stage, AppUpdateDownloadStage.failed);
      expect(opened, isEmpty);
      expect(apkFiles(), isEmpty);
      service.dispose();
    });

    test('sha256 регистронезависим (UPPERCASE expected) → открыт', () async {
      final bytes = List<int>.generate(32, (i) => i);
      final hash = sha256.convert(bytes).toString().toUpperCase();
      final opened = <String>[];
      final service = await build(
        apkBytes: bytes,
        sha256Hex: hash,
        openedPaths: opened,
      );
      await service.downloadAndInstall();

      expect(service.downloadProgress.stage, AppUpdateDownloadStage.idle);
      expect(opened, hasLength(1));
      service.dispose();
    });
  });

  group('FX-B: кэш скачанного APK', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('rodnya_apk_cache_test');
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    List<File> apkFiles() => tempDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('rodnya-update-'))
        .toList();

    File writeCached(String name, List<int> bytes) {
      final file = File(p.join(tempDir.path, name));
      file.writeAsBytesSync(bytes);
      return file;
    }

    // servedBytes — то, что отдаст сеть, если дело дойдёт до загрузки;
    // onApkHit считает обращения к .apk (0 ⇒ переиспользовали кэш).
    Future<AppUpdateService> build({
      required List<int> servedBytes,
      String? sha256Hex,
      required List<String> openedPaths,
      required void Function() onApkHit,
    }) async {
      final client = MockClient.streaming((request, bodyStream) async {
        final path = request.url.path;
        if (path == '/v1/app/latest') {
          final body = utf8.encode(jsonEncode({
            'versionCode': 99,
            'apkUrl': 'https://s3.example/rodnya.apk',
            if (sha256Hex != null) 'sha256': sha256Hex,
          }));
          return http.StreamedResponse(
            Stream.fromIterable([body]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (path.endsWith('.apk')) {
          onApkHit();
          return http.StreamedResponse(
            Stream.fromIterable([servedBytes]),
            200,
            contentLength: servedBytes.length,
          );
        }
        return http.StreamedResponse(const Stream.empty(), 404);
      });
      final service = AppUpdateService(
        apiBaseUrl: 'https://api.example.test',
        httpClient: client,
        buildSnapshotProvider: () async => const AppBuildSnapshot(
          versionCode: 40,
          packageName: 'com.ahjkuio.rodnya_family_app',
        ),
        installerSourceProvider: () async => null,
        isWeb: false,
        platform: TargetPlatform.android,
        downloadDirectoryProvider: () async => tempDir,
        installerOpener: (path) async => openedPaths.add(path),
      );
      await service.checkForUpdate();
      return service;
    }

    test('валидный APK в кэше → переиспользуем, без повторной загрузки',
        () async {
      final bytes = List<int>.generate(256, (i) => (i * 3) % 256);
      final hash = sha256.convert(bytes).toString();
      final cached = writeCached('rodnya-update-cached.apk', bytes);
      var apkHits = 0;
      final opened = <String>[];
      final service = await build(
        servedBytes: const [1, 2, 3], // не должно скачаться
        sha256Hex: hash,
        openedPaths: opened,
        onApkHit: () => apkHits++,
      );
      await service.downloadAndInstall();

      expect(apkHits, 0); // сеть за APK не дёргали
      expect(opened, [cached.path]); // открыли именно кэш
      expect(cached.existsSync(), isTrue); // кэш остался для повторного запуска
      expect(service.downloadProgress.stage, AppUpdateDownloadStage.idle);
      service.dispose();
    });

    test('битый кандидат в кэше → удаляется, качаем заново', () async {
      final freshBytes = List<int>.generate(200, (i) => (i * 5) % 256);
      final freshHash = sha256.convert(freshBytes).toString();
      // Кандидат с НЕ тем содержимым (частичный/от старой версии).
      final stale = writeCached('rodnya-update-stale.apk', const [9, 9, 9, 9]);
      var apkHits = 0;
      final opened = <String>[];
      final service = await build(
        servedBytes: freshBytes,
        sha256Hex: freshHash,
        openedPaths: opened,
        onApkHit: () => apkHits++,
      );
      await service.downloadAndInstall();

      expect(apkHits, 1); // скачали заново
      expect(stale.existsSync(), isFalse); // битый кандидат вычищен
      expect(opened, hasLength(1));
      expect(opened.single, isNot(stale.path)); // открыт свежескачанный
      expect(apkFiles(), hasLength(1)); // в кэше только валидный
      expect(service.downloadProgress.stage, AppUpdateDownloadStage.idle);
      service.dispose();
    });

    test('без sha кэшу доверять нельзя → всегда качаем', () async {
      // Кладём «валидный по виду» файл, но бэк не дал sha → проверить
      // нечем, поэтому переиспользовать нельзя.
      writeCached('rodnya-update-unverifiable.apk', const [1, 2, 3, 4]);
      var apkHits = 0;
      final opened = <String>[];
      final service = await build(
        servedBytes: List<int>.generate(64, (i) => i),
        sha256Hex: null,
        openedPaths: opened,
        onApkHit: () => apkHits++,
      );
      await service.downloadAndInstall();

      expect(apkHits, 1); // скачали, кэш проигнорирован
      expect(opened, hasLength(1));
      service.dispose();
    });
  });
}
