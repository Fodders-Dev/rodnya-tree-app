part of '../custom_api_notification_service.dart';

mixin _CustomApiNotificationPushMixin on _CustomApiNotificationBase {
  @override
  Future<void> initialize() async {
    // Idempotent on purpose. Delivery helpers (`_showGenericNotification`,
    // `showChatMessageNotification`, `showIncomingCallNotification`, …) call
    // `initialize()` as a lazy "is the plugin ready?" guard — including from
    // inside `syncPendingNotifications`'s delivery loop. The one-time
    // hydration below MUST stay behind this guard: re-running
    // `_deliveredNotificationIds.clear()` on every call would discard the ids
    // the sync loop has added-but-not-yet-persisted, re-notifying the user
    // for the same items on the next poll.
    if (_isInitialized) {
      return;
    }

    _deliveredNotificationIds
      ..clear()
      ..addAll(_preferences.getStringList(_deliveredIdsStorageKey) ?? const []);
    _notificationsEnabled =
        _preferences.getBool(_notificationsEnabledStorageKey) ?? true;

    if (kIsWeb) {
      _isInitialized = true;
      return;
    }

    const initializationSettingsAndroid = AndroidInitializationSettings(
      _androidNotificationIcon,
    );
    const initializationSettingsIOS = DarwinInitializationSettings();
    const initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    // flutter_local_notifications 21.x switched the first arg to a
    // named `settings:` parameter. Same payload shape, just the
    // call site changed.
    await _plugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: _onDidReceiveNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          onDidReceiveBackgroundCustomApiNotificationResponse,
    );

    final androidPlugin = _androidPluginOverride ??
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    // createNotificationChannel is idempotent — if MainActivity has
    // already registered them via RodnyaNotificationChannels these
    // calls are no-ops. The order goes urgent → quiet so the
    // Settings screen shows them in the right hierarchy.
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelIdCalls,
        _channelNameCalls,
        description: _channelDescCalls,
        importance: Importance.high,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelIdChats,
        _channelNameChats,
        description: _channelDescChats,
        importance: Importance.high,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelIdSocial,
        _channelNameSocial,
        description: _channelDescSocial,
        importance: Importance.defaultImportance,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelIdSystem,
        _channelNameSystem,
        description: _channelDescSystem,
        importance: Importance.low,
      ),
    );
    await _ensureAndroidNotificationSurfacePermissions(
      androidPlugin: androidPlugin,
    );

    await _restoreLaunchNotificationPayload();
    _isInitialized = true;
  }

  Future<void> startForegroundSync() async {
    final generation = _syncGeneration;
    await initialize();
    if (generation != _syncGeneration ||
        _authService == null ||
        _runtimeConfig == null) {
      return;
    }

    final hasActiveSession = await _registerPushDevicesSafely();
    if (generation != _syncGeneration || !hasActiveSession) {
      return;
    }
    _ensureRemotePushTokenListener();

    if (_realtimeService != null) {
      await _realtimeService.connect();
      if (generation != _syncGeneration) {
        return;
      }
      await _realtimeSubscription?.cancel();
      if (generation != _syncGeneration) {
        return;
      }
      _realtimeSubscription = _realtimeService.events
          .where((event) => event.isNotificationEvent)
          .listen((event) {
        // Bulk-read события — сервер сообщает что N уведомлений
        // юзера погасились (например, после открытия чата). UI
        // обновляет счётчик. Сами notification снапшоты в этом
        // событии не приходят — это лёгкий сигнал «пересчитай».
        if (event.type == 'notification.bulk-read') {
          unawaited(refreshUnreadNotificationsCount());
          return;
        }
        final notification = event.notification;
        if (notification == null) {
          return;
        }
        unawaited(_handleRealtimeNotificationSafely(notification));
      });
    }

    _pollingTimer?.cancel();
    await refreshUnreadNotificationsCount();
    if (generation != _syncGeneration) {
      return;
    }
    await _syncPendingNotificationsSafely();
    if (generation != _syncGeneration) {
      return;
    }
    _pollingTimer = Timer.periodic(_pollInterval, (_) {
      unawaited(_syncPendingNotificationsSafely());
      unawaited(refreshUnreadNotificationsCount());
    });

    if (kIsWeb) {
      final initialPayload = Uri.base.queryParameters['notificationPayload'];
      if (initialPayload != null && initialPayload.isNotEmpty) {
        _schedulePayloadNavigation(initialPayload);
      }
    }

    final pendingPayload = _pendingNavigationPayload;
    if (pendingPayload != null && pendingPayload.isNotEmpty) {
      _schedulePayloadNavigation(pendingPayload);
    }
  }

  @override
  Future<void> stopForegroundSync() async {
    _syncGeneration++;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    await _remotePushTokenSubscription?.cancel();
    _remotePushTokenSubscription = null;
    await _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
  }

  Future<void> resetForSignOut() async {
    await stopForegroundSync();
    _deliveredNotificationIds.clear();
    _pendingNavigationPayload = null;
    _updateUnreadNotificationsCount(0);
  }

  Future<void> _ensureAndroidNotificationSurfacePermissions({
    AndroidFlutterLocalNotificationsPlugin? androidPlugin,
  }) async {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        _androidNotificationPermissionsChecked) {
      return;
    }

    final resolvedAndroidPlugin = androidPlugin ??
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (resolvedAndroidPlugin == null) {
      return;
    }

    _androidNotificationPermissionsChecked = true;

    try {
      final notificationsEnabled =
          await resolvedAndroidPlugin.areNotificationsEnabled();
      _androidNotificationsPermissionDenied = notificationsEnabled != true;
      if (notificationsEnabled != true) {
        final granted =
            await resolvedAndroidPlugin.requestNotificationsPermission();
        if (granted != true) {
          _androidNotificationsPermissionDenied = true;
          debugPrint(
            'Custom API notifications permission denied on Android',
          );
        } else {
          _androidNotificationsPermissionDenied = false;
        }
      }
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to request Android notification permission: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
    }
    permissionCtaRevision.value += 1;

    // Полноэкранный входящий звонок без разрешения на уведомления всё
    // равно не покажется — нет смысла вести в настройки. А спрашивать
    // можно только однажды: у плагина нет «уже разрешено?», и повторный
    // вызов = повторный прыжок в Settings на каждом запуске.
    if (_androidNotificationsPermissionDenied) {
      return;
    }
    if (_preferences.getBool(_fullScreenIntentPromptedStorageKey) == true) {
      return;
    }
    try {
      // Флаг — ДО вызова: если Settings открылись и приложение убили,
      // второй раз пользователя туда не отправим.
      await _preferences.setBool(_fullScreenIntentPromptedStorageKey, true);
      await resolvedAndroidPlugin.requestFullScreenIntentPermission();
    } catch (error, stackTrace) {
      debugPrint(
        'Failed to request Android full-screen intent permission: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> syncPendingNotifications() async {
    final authService = _authService;
    final runtimeConfig = _runtimeConfig;
    if (authService == null || runtimeConfig == null) {
      return;
    }
    final accessToken = authService.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      return;
    }

    final token = authService.accessToken;
    if (token == null || token.isEmpty) {
      return;
    }

    try {
      StartupTrace.logRequest(
          'GET', '/v1/notifications?status=unread&limit=20');
      final response = await _httpClient.get(
        _buildUri(runtimeConfig, '/v1/notifications?status=unread&limit=20'),
        headers: _headers(token),
      );

      final payload = _decodeResponse(response);
      final rawNotifications = payload['notifications'];
      if (rawNotifications is! List<dynamic>) {
        return;
      }

      final now = DateTime.now();
      final cutoff = now.subtract(_maxReplayAge);

      final notifications = rawNotifications
          .whereType<Map<String, dynamic>>()
          .where((notification) {
        final id = notification['id']?.toString() ?? '';
        return id.isNotEmpty && !_deliveredNotificationIds.contains(id);
      }).toList()
        ..sort((left, right) {
          // Newest first — so when we cap at _maxReplayBatch we
          // surface the most recent items, not the oldest.
          return (right['createdAt']?.toString() ?? '')
              .compareTo(left['createdAt']?.toString() ?? '');
        });

      var replayedNonCalls = 0;
      for (final notification in notifications) {
        final id = notification['id']!.toString();

        // Always mark as «delivered» so the next sync doesn't
        // reconsider it — even if we decide to suppress the system
        // notification this round, replaying it on the next poll
        // would just defer the flood by 20 seconds.
        _deliveredNotificationIds.add(id);

        // Calls bypass age + batch limits entirely. A missed call
        // from a few minutes ago still matters; if anything we
        // want it surfaced immediately (the native side already
        // builds a full-screen intent — this branch handles the
        // foreground/just-launched case).
        final type = notification['type']?.toString() ?? '';
        final isCall = type == 'call_invite' || type == 'call';

        if (!isCall) {
          // Skip stale items. They stay visible in /v1/notifications
          // for the in-app feed, just don't ping the OS.
          final createdAt = _parseIso(notification['createdAt']);
          if (createdAt != null && createdAt.isBefore(cutoff)) {
            continue;
          }
          // Avoid dumping the backlog on the lockscreen. This cap is
          // intentionally applied to every foreground sync because a
          // killed app can accumulate several fresh unread items before
          // the next launch.
          if (replayedNonCalls >= _maxReplayBatch) {
            continue;
          }
        }

        final displayed = await _showBackendNotification(notification);
        if (!isCall && displayed) {
          replayedNonCalls += 1;
        }
      }

      await _persistDeliveredNotificationIds();
    } on CustomApiException catch (error) {
      if (await _handleUnauthorizedError(error)) {
        _updateUnreadNotificationsCount(0);
        return;
      }
      rethrow;
    }
  }

  // ── N1/N3: состояние = реальный permission, не флаг ──────────────────

  /// iOS Safari вне установленного PWA: web-push недоступен в принципе,
  /// запрашивать разрешение бессмысленно — нужен «добавьте на Домой».
  bool get _isIosWebNonStandalone =>
      _isWeb &&
      _browserNotificationBridge.isIosWeb &&
      !_browserNotificationBridge.isStandalone;

  /// Web-push на этом клиенте невозможен: браузер не поддерживает, либо
  /// iOS-Safari вне PWA. (На native — всегда false.)
  bool get browserPushUnsupported {
    if (!_isWeb) return false;
    return !_browserNotificationBridge.isSupported ||
        !_browserNotificationBridge.isPushSupported ||
        _isIosWebNonStandalone;
  }

  /// Нужно явно (по жесту) запросить разрешение — показать CTA. Только
  /// когда запрос имеет смысл: web, фича включена в prefs, поддерживается,
  /// не iOS-вне-PWA, и текущий permission == default.
  bool get needsBrowserPermission =>
      _isWeb &&
      _notificationsEnabled &&
      !browserPushUnsupported &&
      _browserNotificationBridge.permissionStatus ==
          BrowserNotificationPermissionStatus.defaultState;

  /// iOS-Safari вне PWA при включённой фиче: вместо запроса — подсказка
  /// «добавьте «Родню» на экран „Домой“».
  bool get iosNeedsStandaloneForPush =>
      _isIosWebNonStandalone && _notificationsEnabled;

  /// Эффективно «уведомления работают» — основа для UI «Включены».
  /// На web требует granted; на native — просто prefs-флаг.
  bool get notificationsEffectivelyOn {
    if (!_isWeb) {
      return _notificationsEnabled && !_androidNotificationsPermissionDenied;
    }
    return _notificationsEnabled &&
        _browserNotificationBridge.permissionStatus ==
            BrowserNotificationPermissionStatus.granted;
  }

  // ── N2: first-run CTA «включить уведомления» ─────────────────────────

  bool get isNotificationCtaDismissed =>
      _preferences.getBool(_notificationCtaDismissedStorageKey) ?? false;

  /// Показывать ли ненавязчивый баннер с CTA. Сам баннер по
  /// [iosNeedsStandaloneForPush] решает: запрос разрешения или
  /// «добавьте на Домой».
  bool get shouldShowPermissionCta =>
      !isNotificationCtaDismissed &&
      (needsBrowserPermission ||
          iosNeedsStandaloneForPush ||
          (!_isWeb &&
              defaultTargetPlatform == TargetPlatform.android &&
              _notificationsEnabled &&
              _androidNotificationsPermissionDenied));

  Future<void> dismissNotificationCta() async {
    await _preferences.setBool(_notificationCtaDismissedStorageKey, true);
    permissionCtaRevision.value += 1;
  }

  Future<bool> setNotificationsEnabled(
    bool enabled, {
    bool promptForBrowserPermission = false,
  }) async {
    if (!enabled && _isWeb) {
      await _unregisterBrowserPushDevice();
    }

    if (enabled && _isWeb) {
      final permission = await _browserNotificationBridge.requestPermission(
        prompt: promptForBrowserPermission,
      );
      if (permission != BrowserNotificationPermissionStatus.granted) {
        _notificationsEnabled = false;
        await _preferences.setBool(_notificationsEnabledStorageKey, false);
        return false;
      }
    }

    if (enabled && !_isWeb && defaultTargetPlatform == TargetPlatform.android) {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      try {
        final alreadyEnabled =
            await androidPlugin?.areNotificationsEnabled() == true;
        final requested = alreadyEnabled
            ? true
            : await androidPlugin?.requestNotificationsPermission();
        final granted = requested == true;
        _androidNotificationsPermissionDenied = !granted;
        if (!granted) {
          _notificationsEnabled = false;
          await _preferences.setBool(_notificationsEnabledStorageKey, false);
          return false;
        }
      } catch (error, stackTrace) {
        debugPrint('Failed to enable Android notifications: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }

    _notificationsEnabled = enabled;
    await _preferences.setBool(_notificationsEnabledStorageKey, enabled);
    if (enabled && _isWeb) {
      final hasActiveSession = await _registerPushDevicesSafely(
        registerRemoteDevice: false,
      );
      if (!hasActiveSession) {
        _notificationsEnabled = false;
        await _preferences.setBool(_notificationsEnabledStorageKey, false);
      }
    }
    return _notificationsEnabled;
  }

  void _ensureRemotePushTokenListener() {
    if (kIsWeb || _remotePushTokenSubscription != null) {
      return;
    }
    final updates = _remotePushTokenUpdates ?? _rustoreService?.pushTokens;
    if (updates == null) {
      return;
    }

    _remotePushTokenSubscription = updates.listen((token) {
      final normalizedToken = token.trim();
      if (normalizedToken.isEmpty) {
        return;
      }
      unawaited(
        _registerPushDevicesSafely(
          registerBrowserDevice: false,
          remoteTokenOverride: normalizedToken,
        ),
      );
    });
  }

  Future<void> _registerRemotePushDevice({String? tokenOverride}) async {
    if (kIsWeb) {
      return;
    }

    final authService = _authService;
    final runtimeConfig = _runtimeConfig;
    if (authService == null || runtimeConfig == null) {
      return;
    }
    final accessToken = authService.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      return;
    }

    final token = tokenOverride?.trim().isNotEmpty == true
        ? tokenOverride!.trim()
        : await _resolveRemotePushToken();
    if (token == null || token.isEmpty) {
      return;
    }

    final registeredFingerprint = _preferences.getString(
      _registeredPushTokenStorageKey,
    );
    final provider = _remotePushProvider;
    final nextFingerprint =
        '$provider::$token::${authService.currentUserId ?? ''}';
    if (registeredFingerprint == nextFingerprint) {
      return;
    }

    // Pre-existing device for an OLD user/token combo — drop it from
    // the backend before registering the fresh one. Otherwise the
    // backend keeps stacking devices forever (account → re-login →
    // new userId or token rotation), which is both a privacy leak
    // and a wasted-quota issue: pushes meant for the previous owner
    // would still hit this physical device.
    final previousDeviceId = _preferences.getString(
      _registeredRemotePushDeviceIdStorageKey,
    );
    if (previousDeviceId != null && previousDeviceId.isNotEmpty) {
      try {
        await _deletePushDevice(previousDeviceId);
      } on CustomApiException catch (error) {
        if (error.statusCode == 401 || error.statusCode == 403) {
          rethrow;
        }
        debugPrint(
          'Failed to delete previous push device; '
          'remote registration deferred: ${error.message}',
        );
        return;
      } catch (error) {
        debugPrint(
          'Failed to delete previous push device; '
          'remote registration deferred: $error',
        );
        return;
      }
    }

    final response = await _httpClient.post(
      _buildUri(runtimeConfig, '/v1/push/devices'),
      headers: _headers(accessToken),
      body: jsonEncode({
        'provider': provider,
        'token': token,
        'platform': defaultTargetPlatform.name,
      }),
    );
    final payload = _decodeResponse(response);
    final device = _asStringDynamicMap(payload['device']);
    final deviceId = device['id']?.toString() ?? '';
    if (deviceId.isNotEmpty) {
      await _preferences.setString(
        _registeredRemotePushDeviceIdStorageKey,
        deviceId,
      );
    }

    await _preferences.setString(
      _registeredPushTokenStorageKey,
      nextFingerprint,
    );
    final maskedToken = token.length <= 8
        ? token
        : '${token.substring(0, 4)}...${token.substring(token.length - 4)}';
    debugPrint(
      'Custom API push registration completed: '
      'provider=$provider, '
      'platform=${defaultTargetPlatform.name}, '
      'userId=${authService.currentUserId ?? ''}, '
      'token=$maskedToken',
    );
  }

  Future<bool> _registerPushDevicesSafely({
    bool registerRemoteDevice = true,
    bool registerBrowserDevice = true,
    String? remoteTokenOverride,
  }) async {
    try {
      if (registerRemoteDevice) {
        await _registerRemotePushDevice(tokenOverride: remoteTokenOverride);
      }
      if (registerBrowserDevice) {
        await _registerBrowserPushDevice();
      }
      return true;
    } on CustomApiException catch (error) {
      if (await _handleUnauthorizedError(error)) {
        _updateUnreadNotificationsCount(0);
        return false;
      }

      debugPrint('Custom API push registration failed: ${error.message}');
      return true;
    } catch (error, stackTrace) {
      debugPrint('Custom API push registration failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return true;
    }
  }

  Future<void> _registerBrowserPushDevice() async {
    if (!kIsWeb ||
        !_notificationsEnabled ||
        !_browserNotificationBridge.isPushSupported) {
      return;
    }

    final authService = _authService;
    final runtimeConfig = _runtimeConfig;
    if (authService == null || runtimeConfig == null) {
      return;
    }

    final accessToken = authService.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      return;
    }

    if (_browserNotificationBridge.permissionStatus !=
        BrowserNotificationPermissionStatus.granted) {
      return;
    }

    final configResponse = await _httpClient.get(
      _buildUri(runtimeConfig, '/v1/push/web/config'),
      headers: _headers(accessToken),
    );
    final configPayload = _decodeResponse(configResponse);
    final isEnabled = configPayload['enabled'] == true;
    final publicKey = configPayload['publicKey']?.toString() ?? '';
    if (!isEnabled || publicKey.isEmpty) {
      return;
    }

    final subscription = await _browserNotificationBridge.subscribeToPush(
      publicKey: publicKey,
    );
    if (subscription == null || subscription.token.isEmpty) {
      return;
    }

    final previousToken =
        _preferences.getString(_registeredBrowserPushTokenStorageKey);
    final previousDeviceId =
        _preferences.getString(_registeredBrowserPushDeviceIdStorageKey);
    if (previousToken == subscription.token &&
        previousDeviceId != null &&
        previousDeviceId.isNotEmpty) {
      return;
    }

    final response = await _httpClient.post(
      _buildUri(runtimeConfig, '/v1/push/devices'),
      headers: _headers(accessToken),
      body: jsonEncode({
        'provider': 'webpush',
        'token': subscription.token,
        'platform': 'web',
      }),
    );
    final payload = _decodeResponse(response);
    final device = _asStringDynamicMap(payload['device']);
    final deviceId = device['id']?.toString() ?? '';
    if (deviceId.isEmpty) {
      return;
    }

    if (previousDeviceId != null &&
        previousDeviceId.isNotEmpty &&
        previousDeviceId != deviceId) {
      await _deletePushDevice(previousDeviceId);
    }

    await _preferences.setString(
      _registeredBrowserPushTokenStorageKey,
      subscription.token,
    );
    await _preferences.setString(
      _registeredBrowserPushDeviceIdStorageKey,
      deviceId,
    );
  }

  Future<void> _unregisterBrowserPushDevice() async {
    if (!kIsWeb) {
      return;
    }

    final deviceId =
        _preferences.getString(_registeredBrowserPushDeviceIdStorageKey);
    if (deviceId != null && deviceId.isNotEmpty) {
      try {
        await _deletePushDevice(deviceId);
      } catch (error) {
        debugPrint(
          'Failed to delete browser push device on signOut: $error',
        );
      }
    }

    await _browserNotificationBridge.unsubscribeFromPush();
    await _preferences.remove(_registeredBrowserPushDeviceIdStorageKey);
    await _preferences.remove(_registeredBrowserPushTokenStorageKey);
  }

  Future<void> _unregisterRemotePushDevice() async {
    if (kIsWeb) {
      return;
    }

    final deviceId =
        _preferences.getString(_registeredRemotePushDeviceIdStorageKey);
    if (deviceId != null && deviceId.isNotEmpty) {
      try {
        await _deletePushDevice(deviceId);
      } catch (error) {
        debugPrint(
          'Failed to delete remote push device on signOut: $error',
        );
      }
    }

    await _preferences.remove(_registeredRemotePushDeviceIdStorageKey);
    // Also drop the fingerprint so the next signin re-registers fresh
    // (registerRemotePushDevice short-circuits when the fingerprint
    // matches, which would otherwise skip registration after we just
    // deleted the backend record).
    await _preferences.remove(_registeredPushTokenStorageKey);
  }

  /// Public hook called from app startup's auth-state listener when
  /// the user signs out (or the session is force-revoked). Removes
  /// THIS device from the backend's push registry on both the mobile
  /// (RuStore) and web (VAPID) channels — without it the previous
  /// user's pushes would keep hitting the device until the token
  /// itself rotated.
  Future<void> unregisterAllPushDevicesForSignOut() async {
    await Future.wait<void>([
      _unregisterRemotePushDevice(),
      _unregisterBrowserPushDevice(),
    ]);
  }

  Future<void> _deletePushDevice(String deviceId,
      {String? overrideToken}) async {
    final authService = _authService;
    final runtimeConfig = _runtimeConfig;
    final accessToken = overrideToken ?? authService?.accessToken;
    if (runtimeConfig == null || accessToken == null || accessToken.isEmpty) {
      return;
    }

    try {
      final response = await _httpClient.delete(
        _buildUri(runtimeConfig, '/v1/push/devices/$deviceId'),
        headers: _headers(accessToken),
      );
      _decodeResponse(response);
    } on CustomApiException catch (error) {
      if (error.statusCode != 404) {
        rethrow;
      }
    }
  }

  Future<String?> _resolveRemotePushToken() async {
    if (_remotePushTokenProvider != null) {
      return _remotePushTokenProvider();
    }

    final rustoreService = _rustoreService;
    if (rustoreService == null) {
      return null;
    }

    return rustoreService.getRustorePushToken();
  }

  Future<void> _syncPendingNotificationsSafely() async {
    try {
      await syncPendingNotifications();
    } catch (error, stackTrace) {
      debugPrint('Custom API notification sync failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
