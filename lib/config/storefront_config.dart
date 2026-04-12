class StorefrontConfig {
  const StorefrontConfig({
    required this.storeId,
    required this.enableRustoreBilling,
    required this.enableRustoreReview,
    required this.enableRustoreUpdates,
  });

  static const String _storeIdEnv = String.fromEnvironment(
    'LINEAGE_APP_STORE',
    defaultValue: 'rustore',
  );
  static const String _billingEnv = String.fromEnvironment(
    'LINEAGE_ENABLE_RUSTORE_BILLING',
    defaultValue: 'false',
  );
  static const String _reviewEnv = String.fromEnvironment(
    'LINEAGE_ENABLE_RUSTORE_REVIEW',
    defaultValue: 'true',
  );
  static const String _updatesEnv = String.fromEnvironment(
    'LINEAGE_ENABLE_RUSTORE_UPDATES',
    defaultValue: 'true',
  );

  final String storeId;
  final bool enableRustoreBilling;
  final bool enableRustoreReview;
  final bool enableRustoreUpdates;

  bool get isRustore => storeId == 'rustore';

  static StorefrontConfig get current => StorefrontConfig(
        storeId: _normalizeStoreId(_storeIdEnv),
        enableRustoreBilling: _parseBool(_billingEnv, fallback: false),
        enableRustoreReview: _parseBool(_reviewEnv, fallback: true),
        enableRustoreUpdates: _parseBool(_updatesEnv, fallback: true),
      );

  static String _normalizeStoreId(String rawValue) {
    final normalized = rawValue.trim().toLowerCase();
    return normalized.isEmpty ? 'rustore' : normalized;
  }

  static bool _parseBool(String rawValue, {required bool fallback}) {
    switch (rawValue.trim().toLowerCase()) {
      case '1':
      case 'true':
      case 'yes':
      case 'on':
        return true;
      case '0':
      case 'false':
      case 'no':
      case 'off':
        return false;
      default:
        return fallback;
    }
  }
}
