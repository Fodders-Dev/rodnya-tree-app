import 'package:package_info_plus/package_info_plus.dart';

const String _definedAppVersion =
    String.fromEnvironment('RODNYA_APP_VERSION', defaultValue: '');

/// Синхронизируется с `version:` в pubspec.yaml или передаётся через
/// `--dart-define=RODNYA_APP_VERSION=<version+build>` при web-сборке.
final String kFallbackAppVersionLabel = _formatVersionSpec(
  _definedAppVersion.trim().isNotEmpty
      ? _definedAppVersion.trim()
      : '1.0.49+57',
);

String _formatVersionSpec(String spec) {
  final parts = spec.split('+');
  final version = parts.first.trim();
  final build = parts.length > 1 ? parts[1].trim() : '';
  if (version.isEmpty) {
    return 'Версия 1.0.49 (сборка 57)';
  }
  if (build.isEmpty) {
    return 'Версия $version';
  }
  return 'Версия $version (сборка $build)';
}

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
