part of '../custom_api_notification_service.dart';

abstract class _CustomApiNotificationBase
    implements NotificationServiceInterface {
  _CustomApiNotificationBase._({
    required FlutterLocalNotificationsPlugin plugin,
    required SharedPreferences preferences,
    CustomApiAuthService? authService,
    BackendRuntimeConfig? runtimeConfig,
    CustomApiRealtimeService? realtimeService,
    RustoreService? rustoreService,
    http.Client? httpClient,
    Duration? pollInterval,
    String remotePushProvider = 'rustore',
    RemotePushTokenProvider? remotePushTokenProvider,
    Stream<String>? remotePushTokenUpdates,
    ChatNotificationCallback? onChatNotification,
    GenericNotificationCallback? onGenericNotification,
    BrowserNotificationBridge? browserNotificationBridge,
    AndroidIncomingCallService? androidIncomingCallService,
    AndroidFlutterLocalNotificationsPlugin? androidPluginOverride,
    bool isWeb = kIsWeb,
  })  : _plugin = plugin,
        _preferences = preferences,
        _androidPluginOverride = androidPluginOverride,
        _isWeb = isWeb,
        _authService = authService,
        _runtimeConfig = runtimeConfig,
        _realtimeService = realtimeService,
        _rustoreService = rustoreService,
        _httpClient = httpClient ?? http.Client(),
        _pollInterval = pollInterval ?? const Duration(seconds: 20),
        _remotePushProvider = remotePushProvider.trim().isEmpty
            ? 'rustore'
            : remotePushProvider.trim().toLowerCase(),
        _remotePushTokenProvider = remotePushTokenProvider,
        _remotePushTokenUpdates = remotePushTokenUpdates,
        _onChatNotification = onChatNotification,
        _onGenericNotification = onGenericNotification,
        _androidIncomingCallService = androidIncomingCallService,
        _browserNotificationBridge =
            browserNotificationBridge ?? createBrowserNotificationBridge();

  final FlutterLocalNotificationsPlugin _plugin;

  final SharedPreferences _preferences;

  /// Только для тестов: Android-плагин вместо
  /// `resolvePlatformSpecificImplementation` (на хосте без Android он null).
  final AndroidFlutterLocalNotificationsPlugin? _androidPluginOverride;

  final CustomApiAuthService? _authService;

  final BackendRuntimeConfig? _runtimeConfig;

  final CustomApiRealtimeService? _realtimeService;

  final RustoreService? _rustoreService;

  final http.Client _httpClient;

  final Duration _pollInterval;

  final String _remotePushProvider;

  final RemotePushTokenProvider? _remotePushTokenProvider;

  final Stream<String>? _remotePushTokenUpdates;

  final ChatNotificationCallback? _onChatNotification;

  final GenericNotificationCallback? _onGenericNotification;

  final AndroidIncomingCallService? _androidIncomingCallService;

  final BrowserNotificationBridge _browserNotificationBridge;

  // Веб-сборка (инъектируемо для VM-тестов state-логики). Native ветка
  // уведомлений (flutter_local_notifications) и веб-ветка (permission +
  // push-подписка) расходятся именно здесь.
  final bool _isWeb;

  final ChatNotificationSettingsStore _chatNotificationSettingsStore =
      const SharedPreferencesChatNotificationSettingsStore();

  bool _isInitialized = false;

  bool _notificationsEnabled = true;

  bool _androidNotificationPermissionsChecked = false;

  bool _androidNotificationsPermissionDenied = false;

  int _unreadNotificationsCount = 0;

  int _syncGeneration = 0;

  String? _pendingNavigationPayload;

  Timer? _pollingTimer;

  StreamSubscription<CustomApiRealtimeEvent>? _realtimeSubscription;

  StreamSubscription<String>? _remotePushTokenSubscription;

  final Set<String> _deliveredNotificationIds = <String>{};

  final StreamController<int> _unreadNotificationsCountController =
      StreamController<int>.broadcast();

  /// Ревизия состояния CTA «включите уведомления»: растёт после
  /// асинхронной Android-проверки разрешения и после дисмисса. Баннер
  /// подписан на неё — иначе он читал [shouldShowPermissionCta] один раз
  /// при build и показывался только если проверка успевала раньше
  /// (на живом запуске — то есть, то нет).
  final ValueNotifier<int> permissionCtaRevision = ValueNotifier<int>(0);

  DateTime? _parseIso(dynamic raw) {
    if (raw == null) return null;
    final text = raw.toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text)?.toLocal();
  }

  bool get notificationsEnabled => _notificationsEnabled;

  int get unreadNotificationsCount => _unreadNotificationsCount;

  Stream<int> get unreadNotificationsCountStream =>
      _unreadNotificationsCountController.stream;

  BrowserNotificationPermissionStatus get browserPermissionStatus =>
      _browserNotificationBridge.permissionStatus;

  _ChannelMeta _channelMetaFor(String channelId) {
    switch (channelId) {
      case _channelIdCalls:
        return const _ChannelMeta(
          name: _channelNameCalls,
          description: _channelDescCalls,
          importance: Importance.max,
          priority: Priority.max,
        );
      case _channelIdChats:
        return const _ChannelMeta(
          name: _channelNameChats,
          description: _channelDescChats,
          importance: Importance.high,
          priority: Priority.high,
        );
      case _channelIdSocial:
        return const _ChannelMeta(
          name: _channelNameSocial,
          description: _channelDescSocial,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        );
      case _channelIdSystem:
      default:
        return const _ChannelMeta(
          name: _channelNameSystem,
          description: _channelDescSystem,
          importance: Importance.low,
          priority: Priority.low,
        );
    }
  }

  Map<String, dynamic> _tryDecodePayload(String payload) {
    try {
      final decoded = jsonDecode(payload);
      return _asStringDynamicMap(decoded);
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  Map<String, dynamic> _asStringDynamicMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (key, mapValue) => MapEntry(key.toString(), mapValue),
      );
    }
    return const <String, dynamic>{};
  }

  /// perf(client): `tree_mutated` realtime/push events report changes
  /// made by ANOTHER device or family member — this device's own
  /// mutation methods already invalidate
  /// `CustomApiFamilyTreeService`'s getRelatives() cache directly, but
  /// a remote change needs this explicit hook. No-op when the family
  /// tree service isn't registered yet (early startup) or the
  /// concrete implementation doesn't support the capability (test
  /// doubles).
  void _invalidateRelativesCacheForTree(String treeId) {
    if (!GetIt.I.isRegistered<FamilyTreeServiceInterface>()) return;
    final familyTreeService = GetIt.I<FamilyTreeServiceInterface>();
    if (familyTreeService is RelativesCacheCapableFamilyTreeService) {
      (familyTreeService as RelativesCacheCapableFamilyTreeService)
          .invalidateRelativesCache(treeId);
    }
  }

  /// Extract `treeId` from notification `data` map (used by
  /// `tree_mutated` refresh coordinator routing).
  String? _readTreeId(dynamic data) {
    final map = _asStringDynamicMap(data);
    final raw = map['treeId']?.toString();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  Uri _buildUri(BackendRuntimeConfig runtimeConfig, String path) {
    final normalizedBase = runtimeConfig.apiBaseUrl.replaceAll(
      RegExp(r'/$'),
      '',
    );
    return Uri.parse('$normalizedBase$path');
  }

  Map<String, String> _headers(String token) {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    if (response.body.isEmpty) {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return const <String, dynamic>{};
      }
      throw const CustomApiException('Пустой ответ от backend');
    }

    final payload = tryDecodeJsonMap(response.body);
    if (payload == null) {
      throw CustomApiException(
        'Сервер вернул некорректный ответ (${response.statusCode})',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return payload;
    }

    throw CustomApiException(
      payload['message']?.toString() ??
          'Ошибка backend (${response.statusCode})',
      statusCode: response.statusCode,
    );
  }

  Future<void> _persistDeliveredNotificationIds() async {
    final sortedIds = _deliveredNotificationIds.toList()
      ..sort((left, right) => left.compareTo(right));
    final trimmedIds = sortedIds.length > 200
        ? sortedIds.sublist(sortedIds.length - 200)
        : sortedIds;

    _deliveredNotificationIds
      ..clear()
      ..addAll(trimmedIds);
    await _preferences.setStringList(
      _deliveredIdsStorageKey,
      trimmedIds,
    );
  }

  Future<bool> _handleUnauthorizedError(CustomApiException error) async {
    if (error.statusCode != 401) {
      return false;
    }

    final authService = _authService;
    if (authService != null) {
      await authService.clearSessionLocally(sessionExpired: true);
    }
    return true;
  }

  Future<void> dispose() async {
    await stopForegroundSync();
    await _unreadNotificationsCountController.close();
  }

  // Forwarders for cross-mixin calls.
  Future<void> _handleRealtimeNotificationSafely(
    Map<String, dynamic> notification,
  );
  void _onDidReceiveNotificationResponse(NotificationResponse response);
  Future<void> _restoreLaunchNotificationPayload();
  void _schedulePayloadNavigation(String payload);
  Future<bool> _showBackendNotification(Map<String, dynamic> notification);
  void _updateUnreadNotificationsCount(int count);
  @override
  Future<void> initialize();
  Future<int> refreshUnreadNotificationsCount();
  Future<void> stopForegroundSync();
}
