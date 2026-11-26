import 'package:package_info_plus/package_info_plus.dart';

/// Синхронизируется с `version:` в pubspec.yaml — используется как безопасный
/// фолбэк, когда на web недоступен `/version.json`.
const String kFallbackAppVersionLabel = 'Версия 1.0.49 (сборка 57)';

/// Загружает строку версии с таймаутом и безопасным фолбэком, чтобы экраны
/// настроек и «О приложении» никогда не зависали на «Версия загружается…».
Future<String> loadAppVersionLabel() async {
  try {
    final packageInfo =
        await PackageInfo.fromPlatform().timeout(const Duration(seconds: 4));
    final version = packageInfo.version.trim();
    if (version.isEmpty) {
      return kFallbackAppVersionLabel;
    }
    final buildNumber = packageInfo.buildNumber.trim();
    if (buildNumber.isEmpty) {
      return 'Версия $version';
    }
    return 'Версия $version (сборка $buildNumber)';
  } catch (_) {
    return kFallbackAppVersionLabel;
  }
}
