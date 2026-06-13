import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// U2: OTA-самообновление для sideloaded APK-сборок (раздача через
/// Telegram, вне магазина). Сервис проверяет версию на бэке
/// (/v1/app/latest, U1), сравнивает с текущей и решает, показать ли
/// баннер / блокирующий экран. Скачивание+установка — здесь же
/// ([downloadAndInstall]); нативное разрешение и гейт источника
/// (MethodChannel) подключаются в U3.
///
/// ⚠️ Гейт источника установки — критично для политики магазинов:
/// если приложение поставлено ИЗ МАГАЗИНА (RuStore и пр.), self-update
/// ВЫКЛЮЧЕН — обновление идёт штатным путём магазина
/// (flutter_rustore_update). Наш апдейтер работает только при sideload
/// (installer null/неизвестный) и только на Android.

/// Известные магазинные инсталлеры. Установка любым из них → апдейтер
/// молчит (магазин обновит сам). RuStore-семейство дополнительно
/// ловится по префиксу (см. [_isStoreInstaller]) — package id RuStore
/// исторически менялся.
const Set<String> kStoreInstallerPackages = <String>{
  'ru.vk.store', // RuStore (актуальный)
  'ru.rustore.app',
  'ru.rustore.installer',
  'com.rustore',
  'com.android.vending', // Google Play
  'com.huawei.appmarket', // AppGallery
  'com.sec.android.app.samsungapps', // Galaxy Store
  'com.xiaomi.market', // Mi GetApps
  'com.heytap.market', // OPPO / realme
  'com.amazon.venezia', // Amazon Appstore
};

/// Сентинел: источник установки определить не удалось (нативный канал
/// недоступен/ошибка). Трактуется как fail-closed — апдейтер НЕ
/// активируется, чтобы случайно не самообновиться внутри магазинной
/// сборки, если гейт сломался. Реальный sideload даёт native-null
/// (не сентинел) и апдейтер работает штатно.
const String kInstallerSourceUnavailable = '__installer_source_unavailable__';

enum AppUpdateAvailability {
  /// Апдейтер неприменим: не Android / web / магазинная установка /
  /// dev-флейвор / фича выключена на бэке / уже последняя версия.
  none,

  /// Доступно необязательное обновление — ненавязчивый баннер.
  optional,

  /// Текущая версия несовместима (current < minVersionCode) —
  /// блокирующий экран с единственной кнопкой «Обновить».
  mandatory,
}

enum AppUpdateDownloadStage { idle, downloading, failed }

@immutable
class AppUpdateDownloadProgress {
  const AppUpdateDownloadProgress({
    required this.stage,
    this.fraction,
    this.error,
  });

  final AppUpdateDownloadStage stage;

  /// 0..1, либо null когда длина ответа неизвестна (показываем
  /// неопределённый индикатор).
  final double? fraction;
  final String? error;

  static const AppUpdateDownloadProgress idle =
      AppUpdateDownloadProgress(stage: AppUpdateDownloadStage.idle);

  bool get isBusy => stage == AppUpdateDownloadStage.downloading;
}

@immutable
class AppLatestVersion {
  const AppLatestVersion({
    required this.versionCode,
    required this.apkUrl,
    this.versionName,
    this.minVersionCode = 0,
    this.notes,
    this.sha256,
  });

  final int versionCode;
  final String apkUrl;
  final String? versionName;
  final int minVersionCode;
  final String? notes;

  /// U6: hex SHA-256 ожидаемого APK (опц.). Если задан — клиент сверяет
  /// хэш скачанного файла ДО установки; пусто → проверка пропускается
  /// (обратная совместимость со старым бэком).
  final String? sha256;

  /// Парсит ответ /v1/app/latest. Возвращает null, если фича выключена
  /// или ответ некорректен (нет versionCode/apkUrl) — клиент молчит.
  static AppLatestVersion? tryParse(Object? json) {
    if (json is! Map) return null;
    final versionCode = _asInt(json['versionCode']);
    final apkUrl = (json['apkUrl'] as Object?)?.toString().trim() ?? '';
    if (versionCode == null || versionCode <= 0 || apkUrl.isEmpty) {
      return null;
    }
    // Хардинг: APK скачивается и ставится — только https, иначе
    // cleartext-загрузку можно подменить (MITM). Невалидную ссылку
    // трактуем как «фича выключена».
    final apkUri = Uri.tryParse(apkUrl);
    if (apkUri == null || apkUri.scheme.toLowerCase() != 'https') {
      return null;
    }
    final versionName = (json['versionName'] as Object?)?.toString().trim();
    final notes = (json['notes'] as Object?)?.toString().trim();
    final sha256Hex = (json['sha256'] as Object?)?.toString().trim();
    return AppLatestVersion(
      versionCode: versionCode,
      apkUrl: apkUrl,
      versionName:
          versionName == null || versionName.isEmpty ? null : versionName,
      minVersionCode: _asInt(json['minVersionCode']) ?? 0,
      notes: notes == null || notes.isEmpty ? null : notes,
      sha256: sha256Hex == null || sha256Hex.isEmpty ? null : sha256Hex,
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

@immutable
class AppUpdateState {
  const AppUpdateState({
    required this.availability,
    this.latest,
    this.currentVersionCode = 0,
  });

  final AppUpdateAvailability availability;
  final AppLatestVersion? latest;
  final int currentVersionCode;

  static const AppUpdateState none =
      AppUpdateState(availability: AppUpdateAvailability.none);
}

/// Снимок текущей сборки для гейта: код версии + packageName (для
/// skip dev-флейвора с суффиксом `.dev`).
@immutable
class AppBuildSnapshot {
  const AppBuildSnapshot({
    required this.versionCode,
    required this.packageName,
  });

  final int versionCode;
  final String packageName;
}

/// Функция, выполняющая фактическое скачивание+открытие установщика.
/// Вынесена в зависимость — UI-тесты подменяют её фейком без сети.
typedef AppUpdateInstaller = Future<void> Function(
  AppLatestVersion latest,
  void Function(double? fraction) onProgress,
);

class AppUpdateService extends ChangeNotifier {
  AppUpdateService({
    required String apiBaseUrl,
    http.Client? httpClient,
    Future<AppBuildSnapshot> Function()? buildSnapshotProvider,
    Future<String?> Function()? installerSourceProvider,
    AppUpdateInstaller? updateInstaller,
    Future<Directory> Function()? downloadDirectoryProvider,
    Future<void> Function(String path)? installerOpener,
    bool isWeb = kIsWeb,
    TargetPlatform? platform,
  })  : _apiBaseUrl = apiBaseUrl,
        _httpClient = httpClient ?? http.Client(),
        // Закрываем клиент в dispose только если создали его сами —
        // инъектированным (DI-singleton / тестовый) владеет вызывающий.
        _ownsHttpClient = httpClient == null,
        _buildSnapshotProvider =
            buildSnapshotProvider ?? _defaultBuildSnapshot,
        _installerSourceProvider =
            installerSourceProvider ?? _defaultInstallerSource,
        _downloadDirectoryProvider =
            downloadDirectoryProvider ?? getTemporaryDirectory,
        _installerOpener = installerOpener ?? _defaultOpenInstaller,
        _isWeb = isWeb,
        _platform = platform ?? defaultTargetPlatform {
    _updateInstaller = updateInstaller ?? _defaultUpdateInstaller;
  }

  static const MethodChannel _channel = MethodChannel('rodnya/apk_updater');

  final String _apiBaseUrl;
  final http.Client _httpClient;
  final bool _ownsHttpClient;
  bool _disposed = false;
  final Future<AppBuildSnapshot> Function() _buildSnapshotProvider;
  final Future<String?> Function() _installerSourceProvider;
  final Future<Directory> Function() _downloadDirectoryProvider;
  final Future<void> Function(String path) _installerOpener;
  late final AppUpdateInstaller _updateInstaller;
  final bool _isWeb;
  final TargetPlatform _platform;

  AppUpdateState _state = AppUpdateState.none;
  AppUpdateState get state => _state;

  AppUpdateDownloadProgress _download = AppUpdateDownloadProgress.idle;
  AppUpdateDownloadProgress get downloadProgress => _download;

  /// Сессионный дисмисс необязательного обновления («Позже»). Static
  /// переживает пересоздание виджетов в рамках сессии, сбрасывается
  /// перезапуском приложения. Обязательное обновление не дисмиссится.
  static bool _optionalDismissedThisSession = false;
  bool get isOptionalDismissed => _optionalDismissedThisSession;

  @visibleForTesting
  static void debugResetSessionDismissal() {
    _optionalDismissedThisSession = false;
  }

  void dismissOptionalForSession() {
    if (_optionalDismissedThisSession) return;
    _optionalDismissedThisSession = true;
    _safeNotify();
  }

  /// notifyListeners только если сервис ещё жив — длинные async-цепочки
  /// (HTTP, скачивание) могут завершиться уже после dispose().
  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// Главная проверка — вызывается в featureLazy-фазе warmup'а
  /// (graceful, в try/catch). Никогда не бросает.
  Future<void> checkForUpdate() async {
    try {
      _state = await _resolveState();
    } catch (_) {
      _state = AppUpdateState.none;
    }
    _safeNotify();
  }

  Future<AppUpdateState> _resolveState() async {
    // 1. Только Android, не web.
    if (_isWeb || _platform != TargetPlatform.android) {
      return AppUpdateState.none;
    }
    // 2. Снимок сборки. dev-флейвор (.dev) — другой package, его
    //    sideload не самообновляем.
    final AppBuildSnapshot build;
    try {
      build = await _buildSnapshotProvider();
    } catch (_) {
      return AppUpdateState.none;
    }
    if (build.packageName.endsWith('.dev')) {
      return AppUpdateState.none;
    }
    // 3. ⚠️ Гейт источника установки.
    final installerRaw = await _safeInstallerSource();
    // Источник не определён (канал недоступен/ошибка) — fail-closed:
    // не самообновляемся, чтобы не активироваться в магазинной сборке
    // при сломанном гейте. Реальный sideload даёт native-null.
    if (installerRaw == kInstallerSourceUnavailable) {
      return AppUpdateState.none;
    }
    final installer = installerRaw?.trim().toLowerCase() ?? '';
    if (installer.isNotEmpty && _isStoreInstaller(installer)) {
      // Магазинная установка → обновляет магазин (для RuStore —
      // flutter_rustore_update), наш апдейтер молчит.
      return AppUpdateState.none;
    }
    // 4. Спросить бэк. 204 / ошибка / непарсибельно → фича выключена.
    final latest = await _fetchLatest();
    if (latest == null) {
      return AppUpdateState.none;
    }
    // 5. Уже последняя версия.
    if (latest.versionCode <= build.versionCode) {
      return AppUpdateState(
        availability: AppUpdateAvailability.none,
        currentVersionCode: build.versionCode,
      );
    }
    // 6. Обязательное (несовместимая старая версия) либо необязательное.
    final availability = build.versionCode < latest.minVersionCode
        ? AppUpdateAvailability.mandatory
        : AppUpdateAvailability.optional;
    return AppUpdateState(
      availability: availability,
      latest: latest,
      currentVersionCode: build.versionCode,
    );
  }

  Future<String?> _safeInstallerSource() async {
    try {
      return await _installerSourceProvider();
    } catch (_) {
      // Ошибка определения источника → fail-closed (не sideload-дефолт).
      return kInstallerSourceUnavailable;
    }
  }

  /// Магазинный ли инсталлер. Помимо явного списка ловим RuStore-семейство
  /// по префиксу (package id RuStore исторически менялся). [installer]
  /// уже в нижнем регистре.
  bool _isStoreInstaller(String installer) {
    if (kStoreInstallerPackages.contains(installer)) return true;
    return installer.startsWith('ru.rustore') ||
        installer.startsWith('ru.vk.store') ||
        installer.startsWith('com.rustore');
  }

  Future<AppLatestVersion?> _fetchLatest() async {
    try {
      final base = _apiBaseUrl.endsWith('/')
          ? _apiBaseUrl.substring(0, _apiBaseUrl.length - 1)
          : _apiBaseUrl;
      final uri = Uri.parse('$base/v1/app/latest');
      final response =
          await _httpClient.get(uri).timeout(const Duration(seconds: 8));
      // 204 — фича выключена на бэке.
      if (response.statusCode == 204 || response.body.trim().isEmpty) {
        return null;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      return AppLatestVersion.tryParse(jsonDecode(response.body));
    } catch (error) {
      // Молча выключаем фичу, но оставляем след — обычно это
      // misconfig бэка/прокси (HTML вместо JSON), который иначе не виден.
      debugPrint('[app-update] не удалось получить версию: $error');
      return null;
    }
  }

  /// Скачивает APK и открывает системный установщик. На обоих этапах
  /// двигает [downloadProgress]; ошибки не бросает, а кладёт в стейт
  /// (failed) для UI-ретрая.
  Future<void> downloadAndInstall() async {
    final latest = _state.latest;
    if (latest == null || _download.isBusy) {
      return;
    }
    _setDownload(const AppUpdateDownloadProgress(
      stage: AppUpdateDownloadStage.downloading,
      fraction: 0,
    ));
    try {
      // Таймаут, чтобы зависший аплоад/OpenFilex не запер isBusy навсегда
      // (иначе кнопка «Обновить» молча игнорит повторные тапы). Щедрый —
      // большой APK на слабой сети качается долго.
      await _updateInstaller(latest, (fraction) {
        _setDownload(AppUpdateDownloadProgress(
          stage: AppUpdateDownloadStage.downloading,
          fraction: fraction,
        ));
      }).timeout(const Duration(minutes: 5));
      _setDownload(AppUpdateDownloadProgress.idle);
    } on TimeoutException {
      _setDownload(const AppUpdateDownloadProgress(
        stage: AppUpdateDownloadStage.failed,
        error: 'Загрузка заняла слишком долго. Попробуйте ещё раз.',
      ));
    } catch (_) {
      _setDownload(const AppUpdateDownloadProgress(
        stage: AppUpdateDownloadStage.failed,
        error: 'Не удалось скачать обновление. Попробуйте ещё раз.',
      ));
    }
  }

  void _setDownload(AppUpdateDownloadProgress next) {
    _download = next;
    _safeNotify();
  }

  // ── Дефолтные провайдеры (прод) ──────────────────────────────────

  static Future<AppBuildSnapshot> _defaultBuildSnapshot() async {
    final info = await PackageInfo.fromPlatform();
    return AppBuildSnapshot(
      versionCode: int.tryParse(info.buildNumber) ?? 0,
      packageName: info.packageName,
    );
  }

  static Future<String?> _defaultInstallerSource() async {
    try {
      return await _channel.invokeMethod<String?>('getInstallerPackageName');
    } on MissingPluginException {
      // Нативный обработчик не подключён (тесты / сломанная сборка) —
      // источник неизвестен. Fail-closed (см. kInstallerSourceUnavailable):
      // в проде канал всегда есть (U3), так что это не трогает реальный
      // sideload, где native возвращает null.
      return kInstallerSourceUnavailable;
    } catch (_) {
      return kInstallerSourceUnavailable;
    }
  }

  static Future<void> _defaultOpenInstaller(String path) async {
    // Системный установщик. FileProvider предоставляет open_filex
    // (authority ${applicationId}.fileProvider...) и сам ставит
    // FLAG_GRANT_READ_URI_PERMISSION; APK той же релиз-подписью ставится
    // поверх (in-place update).
    await OpenFilex.open(path);
  }

  Future<void> _defaultUpdateInstaller(
    AppLatestVersion latest,
    void Function(double? fraction) onProgress,
  ) async {
    final dir = await _downloadDirectoryProvider();
    // U6: уникальное имя на попытку — старый частичный файл не мешает и
    // open_filex не прочитает недописанный с прошлого раза.
    final file = File(p.join(
      dir.path,
      'rodnya-update-${DateTime.now().microsecondsSinceEpoch}.apk',
    ));
    try {
      final request = http.Request('GET', Uri.parse(latest.apkUrl));
      final response = await _httpClient.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw http.ClientException(
          'APK download failed: ${response.statusCode}',
        );
      }
      final total = response.contentLength ?? 0;
      var received = 0;
      // Считаем sha256 на лету (без второго прохода по файлу).
      Digest? digest;
      final hashOutput = ChunkedConversionSink<Digest>.withCallback(
        (digests) => digest = digests.single,
      );
      final hashInput = sha256.startChunkedConversion(hashOutput);
      final sink = file.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          hashInput.add(chunk);
          received += chunk.length;
          onProgress(total > 0 ? received / total : null);
        }
      } finally {
        await sink.close();
        hashInput.close();
      }

      // U6: целостность ДО установки.
      // 1. Размер: если сервер сообщил Content-Length — скачали ровно
      //    столько; иначе файл неполный, не открываем.
      if (total > 0 && received != total) {
        throw const FormatException('incomplete APK download: size mismatch');
      }
      if (received <= 0) {
        throw const FormatException('empty APK download');
      }
      // 2. SHA-256: если бэк отдал хэш — сверяем. Пусто → пропускаем
      //    (обратная совместимость).
      final expected = latest.sha256;
      if (expected != null && expected.isNotEmpty) {
        final actual = digest?.toString() ?? '';
        if (actual.toLowerCase() != expected.toLowerCase()) {
          throw const FormatException('APK sha256 mismatch');
        }
      }

      await _installerOpener(file.path);
    } catch (_) {
      // Чистим частичный/повреждённый файл — он не должен остаться в
      // кэше и быть случайно открытым.
      await _safeDelete(file);
      rethrow;
    }
  }

  static Future<void> _safeDelete(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // best-effort
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsHttpClient) {
      _httpClient.close();
    }
    super.dispose();
  }
}
