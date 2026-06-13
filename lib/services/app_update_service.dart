import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
/// молчит (магазин обновит сам).
const Set<String> kStoreInstallerPackages = <String>{
  'ru.vk.store', // RuStore
  'ru.rustore.app',
  'com.android.vending', // Google Play
  'com.huawei.appmarket', // AppGallery
  'com.sec.android.app.samsungapps', // Galaxy Store
  'com.xiaomi.market', // Mi GetApps
  'com.heytap.market', // OPPO / realme
  'com.amazon.venezia', // Amazon Appstore
};

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

enum AppUpdateDownloadStage { idle, downloading, opening, failed }

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

  bool get isBusy =>
      stage == AppUpdateDownloadStage.downloading ||
      stage == AppUpdateDownloadStage.opening;
}

@immutable
class AppLatestVersion {
  const AppLatestVersion({
    required this.versionCode,
    required this.apkUrl,
    this.versionName,
    this.minVersionCode = 0,
    this.notes,
  });

  final int versionCode;
  final String apkUrl;
  final String? versionName;
  final int minVersionCode;
  final String? notes;

  /// Парсит ответ /v1/app/latest. Возвращает null, если фича выключена
  /// или ответ некорректен (нет versionCode/apkUrl) — клиент молчит.
  static AppLatestVersion? tryParse(Object? json) {
    if (json is! Map) return null;
    final versionCode = _asInt(json['versionCode']);
    final apkUrl = (json['apkUrl'] as Object?)?.toString().trim() ?? '';
    if (versionCode == null || versionCode <= 0 || apkUrl.isEmpty) {
      return null;
    }
    final versionName = (json['versionName'] as Object?)?.toString().trim();
    final notes = (json['notes'] as Object?)?.toString().trim();
    return AppLatestVersion(
      versionCode: versionCode,
      apkUrl: apkUrl,
      versionName:
          versionName == null || versionName.isEmpty ? null : versionName,
      minVersionCode: _asInt(json['minVersionCode']) ?? 0,
      notes: notes == null || notes.isEmpty ? null : notes,
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
    bool isWeb = kIsWeb,
    TargetPlatform? platform,
  })  : _apiBaseUrl = apiBaseUrl,
        _httpClient = httpClient ?? http.Client(),
        _buildSnapshotProvider =
            buildSnapshotProvider ?? _defaultBuildSnapshot,
        _installerSourceProvider =
            installerSourceProvider ?? _defaultInstallerSource,
        _isWeb = isWeb,
        _platform = platform ?? defaultTargetPlatform {
    _updateInstaller = updateInstaller ?? _defaultUpdateInstaller;
  }

  static const MethodChannel _channel = MethodChannel('rodnya/apk_updater');

  final String _apiBaseUrl;
  final http.Client _httpClient;
  final Future<AppBuildSnapshot> Function() _buildSnapshotProvider;
  final Future<String?> Function() _installerSourceProvider;
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
    notifyListeners();
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
    // 3. ⚠️ Гейт источника: магазинная установка → апдейтер молчит.
    final installer = (await _safeInstallerSource())?.trim().toLowerCase();
    if (installer != null &&
        installer.isNotEmpty &&
        kStoreInstallerPackages.contains(installer)) {
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
      return null;
    }
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
    } catch (_) {
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
      await _updateInstaller(latest, (fraction) {
        _setDownload(AppUpdateDownloadProgress(
          stage: AppUpdateDownloadStage.downloading,
          fraction: fraction,
        ));
      });
      _setDownload(AppUpdateDownloadProgress.idle);
    } catch (_) {
      _setDownload(const AppUpdateDownloadProgress(
        stage: AppUpdateDownloadStage.failed,
        error: 'Не удалось скачать обновление. Попробуйте ещё раз.',
      ));
    }
  }

  void _setDownload(AppUpdateDownloadProgress next) {
    _download = next;
    notifyListeners();
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
      // Нативный обработчик ещё не подключён (тесты / до U3) — трактуем
      // как sideload (безопасный дефолт для sideload-сборки).
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _defaultUpdateInstaller(
    AppLatestVersion latest,
    void Function(double? fraction) onProgress,
  ) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'rodnya-update.apk'));
    final request = http.Request('GET', Uri.parse(latest.apkUrl));
    final response = await _httpClient.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException('APK download failed: ${response.statusCode}');
    }
    final total = response.contentLength ?? 0;
    var received = 0;
    final sink = file.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(total > 0 ? received / total : null);
      }
    } finally {
      await sink.close();
    }
    // Открываем системный установщик. FileProvider предоставляет
    // open_filex (authority ${applicationId}.fileProvider...); APK той
    // же релиз-подписью ставится поверх (in-place update).
    await OpenFilex.open(file.path);
  }

  @override
  void dispose() {
    _httpClient.close();
    super.dispose();
  }
}
