import 'package:flutter/foundation.dart' show kIsWeb;

enum BackendProviderKind { firebase, supabase, hybridLegacy, customApi }

class BackendProviderConfig {
  const BackendProviderConfig({
    this.authProvider = BackendProviderKind.firebase,
    this.profileProvider = BackendProviderKind.firebase,
    this.treeProvider = BackendProviderKind.firebase,
    this.chatProvider = BackendProviderKind.firebase,
    this.storageProvider = BackendProviderKind.hybridLegacy,
    this.notificationProvider = BackendProviderKind.firebase,
  });

  final BackendProviderKind authProvider;
  final BackendProviderKind profileProvider;
  final BackendProviderKind treeProvider;
  final BackendProviderKind chatProvider;
  final BackendProviderKind storageProvider;
  final BackendProviderKind notificationProvider;

  static const String _authProviderEnv = String.fromEnvironment(
    'LINEAGE_AUTH_PROVIDER',
    defaultValue: '',
  );
  static const String _profileProviderEnv = String.fromEnvironment(
    'LINEAGE_PROFILE_PROVIDER',
    defaultValue: '',
  );
  static const String _treeProviderEnv = String.fromEnvironment(
    'LINEAGE_TREE_PROVIDER',
    defaultValue: '',
  );
  static const String _chatProviderEnv = String.fromEnvironment(
    'LINEAGE_CHAT_PROVIDER',
    defaultValue: '',
  );
  static const String _storageProviderEnv = String.fromEnvironment(
    'LINEAGE_STORAGE_PROVIDER',
    defaultValue: '',
  );
  static const String _notificationProviderEnv = String.fromEnvironment(
    'LINEAGE_NOTIFICATION_PROVIDER',
    defaultValue: '',
  );
  static const String _runtimePresetEnv = String.fromEnvironment(
    'LINEAGE_RUNTIME_PRESET',
    defaultValue: '',
  );

  static BackendProviderConfig get current {
    final runtimePreset = _runtimePresetEnv.trim();
    if (_usesProdCustomApiPreset(runtimePreset, Uri.base.host)) {
      return const BackendProviderConfig(
        authProvider: BackendProviderKind.customApi,
        profileProvider: BackendProviderKind.customApi,
        treeProvider: BackendProviderKind.customApi,
        chatProvider: BackendProviderKind.customApi,
        storageProvider: BackendProviderKind.customApi,
        notificationProvider: BackendProviderKind.customApi,
      );
    }

    return resolve(
      runtimePresetRaw: _runtimePresetEnv,
      hostRaw: Uri.base.host,
      authProviderRaw: _authProviderEnv,
      profileProviderRaw: _profileProviderEnv,
      treeProviderRaw: _treeProviderEnv,
      chatProviderRaw: _chatProviderEnv,
      storageProviderRaw: _storageProviderEnv,
      notificationProviderRaw: _notificationProviderEnv,
      isWebRuntime: kIsWeb,
      hasWebFirebaseOptions: _hasRequiredWebFirebaseOptions,
    );
  }

  static BackendProviderConfig resolve({
    String runtimePresetRaw = '',
    String hostRaw = '',
    String authProviderRaw = '',
    String profileProviderRaw = '',
    String treeProviderRaw = '',
    String chatProviderRaw = '',
    String storageProviderRaw = '',
    String notificationProviderRaw = '',
    bool isWebRuntime = false,
    bool hasWebFirebaseOptions = true,
  }) {
    if (_usesProdCustomApiPreset(runtimePresetRaw, hostRaw)) {
      return const BackendProviderConfig(
        authProvider: BackendProviderKind.customApi,
        profileProvider: BackendProviderKind.customApi,
        treeProvider: BackendProviderKind.customApi,
        chatProvider: BackendProviderKind.customApi,
        storageProvider: BackendProviderKind.customApi,
        notificationProvider: BackendProviderKind.customApi,
      );
    }

    if (_usesFirebaselessWebFallback(
      runtimePresetRaw: runtimePresetRaw,
      authProviderRaw: authProviderRaw,
      profileProviderRaw: profileProviderRaw,
      treeProviderRaw: treeProviderRaw,
      chatProviderRaw: chatProviderRaw,
      storageProviderRaw: storageProviderRaw,
      notificationProviderRaw: notificationProviderRaw,
      isWebRuntime: isWebRuntime,
      hasWebFirebaseOptions: hasWebFirebaseOptions,
    )) {
      return const BackendProviderConfig(
        authProvider: BackendProviderKind.customApi,
        profileProvider: BackendProviderKind.customApi,
        treeProvider: BackendProviderKind.customApi,
        chatProvider: BackendProviderKind.customApi,
        storageProvider: BackendProviderKind.customApi,
        notificationProvider: BackendProviderKind.customApi,
      );
    }

    final authProvider = _providerFromRaw(
      authProviderRaw,
      BackendProviderKind.firebase,
    );
    final defaultDomainProvider = authProvider == BackendProviderKind.customApi
        ? BackendProviderKind.customApi
        : BackendProviderKind.firebase;

    return BackendProviderConfig(
      authProvider: authProvider,
      profileProvider: _providerFromRaw(
        profileProviderRaw,
        defaultDomainProvider,
      ),
      treeProvider: _providerFromRaw(treeProviderRaw, defaultDomainProvider),
      chatProvider: _providerFromRaw(chatProviderRaw, defaultDomainProvider),
      storageProvider: _providerFromRaw(
        storageProviderRaw,
        authProvider == BackendProviderKind.customApi
            ? BackendProviderKind.customApi
            : BackendProviderKind.hybridLegacy,
      ),
      notificationProvider: _providerFromRaw(
        notificationProviderRaw,
        defaultDomainProvider,
      ),
    );
  }

  static BackendProviderKind _providerFromRaw(
    String rawValue,
    BackendProviderKind fallback,
  ) {
    final resolved = rawValue.trim();
    if (resolved.isEmpty) {
      return fallback;
    }

    return BackendProviderKind.values.firstWhere(
      (value) => value.name == resolved,
      orElse: () => fallback,
    );
  }

  static bool _usesProdCustomApiPreset(
      String runtimePresetRaw, String hostRaw) {
    final runtimePreset = runtimePresetRaw.trim();
    if (runtimePreset == 'prod_custom_api') {
      return true;
    }

    final normalizedHost = hostRaw.trim().toLowerCase();
    return normalizedHost == 'rodnya-tree.ru' ||
        normalizedHost == 'www.rodnya-tree.ru';
  }

  static bool _usesFirebaselessWebFallback({
    required String runtimePresetRaw,
    required String authProviderRaw,
    required String profileProviderRaw,
    required String treeProviderRaw,
    required String chatProviderRaw,
    required String storageProviderRaw,
    required String notificationProviderRaw,
    required bool isWebRuntime,
    required bool hasWebFirebaseOptions,
  }) {
    if (!isWebRuntime || hasWebFirebaseOptions) {
      return false;
    }

    if (runtimePresetRaw.trim().isNotEmpty) {
      return false;
    }

    return authProviderRaw.trim().isEmpty &&
        profileProviderRaw.trim().isEmpty &&
        treeProviderRaw.trim().isEmpty &&
        chatProviderRaw.trim().isEmpty &&
        storageProviderRaw.trim().isEmpty &&
        notificationProviderRaw.trim().isEmpty;
  }

  static const String _webApiKeyEnv = String.fromEnvironment(
    'LINEAGE_FIREBASE_WEB_API_KEY',
    defaultValue: '',
  );
  static const String _webAppIdEnv = String.fromEnvironment(
    'LINEAGE_FIREBASE_WEB_APP_ID',
    defaultValue: '',
  );
  static const String _messagingSenderIdEnv = String.fromEnvironment(
    'LINEAGE_FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: '',
  );
  static const String _projectIdEnv = String.fromEnvironment(
    'LINEAGE_FIREBASE_PROJECT_ID',
    defaultValue: '',
  );

  static bool get _hasRequiredWebFirebaseOptions =>
      _webApiKeyEnv.isNotEmpty &&
      _webAppIdEnv.isNotEmpty &&
      _messagingSenderIdEnv.isNotEmpty &&
      _projectIdEnv.isNotEmpty;
}
