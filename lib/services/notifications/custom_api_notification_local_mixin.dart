part of '../custom_api_notification_service.dart';

mixin _CustomApiNotificationLocalMixin on _CustomApiNotificationBase {
  @override
  Future<void> showBirthdayNotification(
    rodnya_models.FamilyPerson person,
  ) async {
    if (!_notificationsEnabled) {
      return;
    }
    if (kIsWeb) {
      await _showBrowserNotification(
        title: 'День рождения',
        body: 'Сегодня день рождения у ${person.name}',
        tag: 'birthday-${person.id}',
        payload: jsonEncode({
          'type': 'birthday',
          'personId': person.id,
        }),
      );
      return;
    }
    await initialize();

    await _plugin.show(
      id: person.id.hashCode,
      title: 'День рождения',
      body: 'Сегодня день рождения у ${person.name}',
      // Birthdays are social activity, not «right now answer me»
      // — route through the social channel so the user can mute
      // them independently from chats and calls.
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelIdSocial,
          _channelNameSocial,
          channelDescription: _channelDescSocial,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: _androidNotificationIcon,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
    );
  }

  @override
  Future<void> showChatMessageNotification({
    required String chatId,
    required String senderId,
    required String senderName,
    required String messageText,
    required int notificationId,
    bool playSound = true,
  }) async {
    if (!_notificationsEnabled) {
      return;
    }

    final payload = jsonEncode({
      'type': 'chat',
      'chatId': chatId,
      'senderId': senderId,
      'senderName': senderName,
      'messageText': messageText,
    });

    if (kIsWeb) {
      final shortText = messageText.length > 120
          ? '${messageText.substring(0, 117)}...'
          : messageText;
      await _showBrowserNotification(
        title: senderName,
        body: shortText,
        tag: 'chat-$chatId',
        payload: payload,
      );
      return;
    }
    await initialize();

    if (_onChatNotification != null) {
      await _onChatNotification(
        chatId: chatId,
        senderId: senderId,
        senderName: senderName,
        messageText: messageText,
        notificationId: notificationId,
        playSound: playSound,
      );
      return;
    }

    final shortText = messageText.length > 120
        ? '${messageText.substring(0, 117)}...'
        : messageText;

    // Использую `chatId.hashCode` как notification id, чтобы все
    // сообщения из одного чата ОБНОВЛЯЛИ одну и ту же запись в
    // шторке (Android matches notification by id+tag — раньше
    // notificationId был производным от server id и каждое
    // сообщение создавало отдельную карточку, забивая шторку).
    // Telegram-style: «1 уведомление = 1 чат».
    final stableId = chatId.trim().isEmpty ? notificationId : chatId.hashCode;
    await _plugin.show(
      id: stableId,
      title: senderName,
      body: shortText,
      notificationDetails: NotificationDetails(
        // Chat messages live on the dedicated chats channel — high
        // importance so they show as a heads-up, but the user can
        // still mute it without losing call alerts.
        android: AndroidNotificationDetails(
          _channelIdChats,
          _channelNameChats,
          channelDescription: _channelDescChats,
          importance:
              playSound ? Importance.high : Importance.defaultImportance,
          priority: playSound ? Priority.high : Priority.defaultPriority,
          playSound: playSound,
          groupKey: 'rodnya.chat.$chatId',
          tag: 'rodnya.chat.$chatId',
          icon: _androidNotificationIcon,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: playSound,
          threadIdentifier: 'rodnya.chat.$chatId',
        ),
      ),
      payload: payload,
    );
  }

  Future<void> showIncomingCallNotification({
    required String callId,
    required String callerName,
    required bool isVideo,
    String? chatId,
  }) async {
    if (!_notificationsEnabled) {
      return;
    }

    final payload = jsonEncode({
      'type': 'call',
      'callId': callId,
    });
    final resolvedCallerName =
        callerName.trim().isEmpty ? 'Родня' : callerName.trim();
    final body = isVideo ? 'Входящий видеозвонок' : 'Входящий аудиозвонок';

    if (kIsWeb) {
      await _showBrowserNotification(
        title: resolvedCallerName,
        body: body,
        tag: 'call-$callId',
        payload: payload,
      );
      return;
    }

    await initialize();
    final nativeCallShown = await _androidIncomingCallService?.showIncomingCall(
          callId: callId,
          callerName: resolvedCallerName,
          isVideo: isVideo,
          chatId: chatId,
        ) ??
        false;
    if (nativeCallShown) {
      return;
    }

    await _plugin.show(
      // NTV-3: тот же id, что у нативной уведомки звонка
      // (RodnyaPushService/RodnyaTelecomBridge считают
      // `callId.hashCode() and 0x7fffffff` по Java-алгоритму). Dart
      // String.hashCode даёт ДРУГОЕ число → снятие с killed-пуша или
      // натива промахнулось бы мимо plugin-уведомки. Считаем Java-совместимо.
      id: _androidCallNotificationId(callId),
      title: resolvedCallerName,
      body: body,
      // Calls go on the dedicated «calls» channel — bypasses DND,
      // uses the system ringtone, and the channel-level config in
      // RodnyaNotificationChannels.kt ensures lockscreen visibility
      // and full-screen-intent permissions are respected.
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelIdCalls,
          _channelNameCalls,
          channelDescription: _channelDescCalls,
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          icon: _androidNotificationIcon,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
      payload: payload,
    );
  }

  Future<void> dismissCallNotification(String callId) async {
    if (callId.trim().isEmpty || kIsWeb) {
      return;
    }
    await initialize();
    await _androidIncomingCallService?.dismissCall(callId);
    // 21.x switched cancel to a named-arg form too. NTV-3: тот же
    // Java-совместимый id, что и при показе/в нативе.
    await _plugin.cancel(id: _androidCallNotificationId(callId));
  }

  /// Снимает system-уведомление для конкретного чата. Зовётся когда
  /// юзер открывает экран чата — старая нотификация в шторке больше
  /// не нужна, он сейчас читает сам. Используется одинаковый
  /// `chatId.hashCode` как id, тот же что и в
  /// `showChatMessageNotification` ниже — Android matches by id+tag.
  @override
  Future<void> dismissChatNotifications(String chatId) async {
    final normalized = chatId.trim();
    if (normalized.isEmpty || kIsWeb) {
      return;
    }
    await initialize();
    try {
      await _plugin.cancel(
        id: normalized.hashCode,
        tag: 'rodnya.chat.$normalized',
      );
    } catch (error) {
      debugPrint('Failed to dismiss chat notifications: $error');
    }
  }

  @override
  Future<bool> _showBackendNotification(
      Map<String, dynamic> notification) async {
    final id = notification['id']?.toString() ?? '';
    final type = notification['type']?.toString() ?? 'generic';
    final title = notification['title']?.toString() ?? 'Родня';
    final body = notification['body']?.toString() ?? '';
    final data = notification['data'];
    final silent = notification['silent'] == true;
    final payload = jsonEncode({
      'id': id,
      'type': type,
      'data': data is Map<String, dynamic> ? data : const <String, dynamic>{},
    });

    // Phase 6.5+ auto-refresh: type-dispatch ДО visual display.
    // WebSocket realtime + push converge через этот path —
    // foreground users получают instant refetch, background — на
    // первом app resume через _handleAppResumed либо via push tap.
    // Debounce 500ms в coordinator coalesces burst pushes.
    if (type == 'post_created') {
      PostsRefreshCoordinator.instance.requestRefresh();
      // Continue к display — banner OK для posts (user wants to see
      // «new post from X» в notification tray).
    } else if (type == 'tree_mutated') {
      final treeId = _readTreeId(data);
      if (treeId != null && treeId.isNotEmpty) {
        TreeRefreshCoordinator.instance.requestRefresh(treeId);
        _invalidateRelativesCacheForTree(treeId);
      }
      // Silent push: refetch only, no visual surface. Tree mutations
      // would spam user notifications otherwise (each person edit
      // = banner). Return early.
      if (silent) return false;
    }

    if (type == 'chat_message') {
      final chatData =
          data is Map<String, dynamic> ? data : const <String, dynamic>{};
      final chatId = chatData['chatId']?.toString() ?? '';
      // User-reported: «нахуя они вообще шлются, когда я в чате уже
      // с ним?». Если юзер прямо сейчас открыт в этом чате — он
      // увидит сообщение в timeline'е через realtime, ОС-нотификация
      // только мигнёт сверху и помешает. Глушим.
      if (ActiveChatTracker.instance.isActive(chatId)) {
        return false;
      }
      final deliveryLevel = await _resolveChatNotificationLevel(chatId);
      if (deliveryLevel == ChatNotificationLevel.muted) {
        return false;
      }
      await showChatMessageNotification(
        chatId: chatId,
        senderId: chatData['senderId']?.toString() ?? '',
        senderName: chatData['senderName']?.toString() ?? title,
        messageText: body,
        notificationId: id.hashCode,
        playSound: deliveryLevel != ChatNotificationLevel.silent,
      );
      return true;
    }

    if (type == 'call_invite') {
      final callData = _asStringDynamicMap(data);
      final callId = callData['callId']?.toString() ?? '';
      if (callId.isNotEmpty) {
        await _hydrateIncomingCallCoordinator(callData);
        await showIncomingCallNotification(
          callId: callId,
          callerName: title,
          isVideo: callData['mediaMode']?.toString() == 'video',
          chatId: callData['chatId']?.toString(),
        );
        return true;
      }
    }

    await _showGenericNotification(
      title: title,
      body: body,
      notificationId: id.hashCode,
      payload: payload,
      type: type,
    );
    return true;
  }

  /// Pick the matching native channel ID for a notification type.
  /// Mirrors `PushGateway._androidChannelId` on the backend so a
  /// foreground replay lands on the same channel as the original
  /// VKPNS push would have.
  String _channelForType(String type) {
    switch (type) {
      case 'call_invite':
      case 'call':
        return _channelIdCalls;
      case 'chat_message':
      case 'chat':
        return _channelIdChats;
      case 'post_like':
      case 'post_comment':
      case 'comment_reply':
      case 'story_view':
      case 'story_reaction':
      case 'relative_added':
      case 'tree_invitation':
      case 'birthday':
      // Phase 6 chunk 4b: kinship-check «мы родственники?» notifications
      // — social context, не «right now answer me».
      case 'kinship_check_received':
      case 'kinship_check_confirmed':
      case 'kinship_check_declined':
      case 'kinship_check_expired':
      // MVP-1 «Спросить историю» (STORY-REQUEST-MVP1-BRIEF.md §1) — same
      // bucket as kinship-checks: warm family context, not urgent.
      case 'story_request_received':
      case 'story_request_answered':
      case 'story_request_declined':
      case 'story_request_expired':
      case 'story_request_revoked':
        return _channelIdSocial;
      default:
        return _channelIdSystem;
    }
  }

  Future<void> _showGenericNotification({
    required String title,
    required String body,
    required int notificationId,
    String? payload,
    String type = 'generic',
  }) async {
    if (!_notificationsEnabled) {
      return;
    }
    if (kIsWeb) {
      await _showBrowserNotification(
        title: title,
        body: body,
        tag: 'generic-$notificationId',
        payload: payload,
      );
      return;
    }
    await initialize();

    if (_onGenericNotification != null) {
      await _onGenericNotification(
        title: title,
        body: body,
        notificationId: notificationId,
        payload: payload,
      );
      return;
    }

    final channelId = _channelForType(type);
    final meta = _channelMetaFor(channelId);
    final isQuiet = channelId == _channelIdSystem;

    await _plugin.show(
      id: notificationId,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          meta.name,
          channelDescription: meta.description,
          importance: meta.importance,
          priority: meta.priority,
          playSound: !isQuiet,
          enableVibration: !isQuiet,
          icon: _androidNotificationIcon,
          // System / social cards collapse under one app header so a
          // burst of «X лайкнул» notifications doesn't bury chats.
          groupKey: 'rodnya.$channelId',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: !isQuiet,
          interruptionLevel:
              isQuiet ? InterruptionLevel.passive : InterruptionLevel.active,
        ),
      ),
      payload: payload,
    );
  }

  Future<void> _showBrowserNotification({
    required String title,
    required String body,
    required String tag,
    String? payload,
  }) async {
    if (!_browserNotificationBridge.isSupported ||
        _browserNotificationBridge.permissionStatus !=
            BrowserNotificationPermissionStatus.granted) {
      return;
    }

    await _browserNotificationBridge.showNotification(
      title: title,
      body: body,
      tag: tag,
      onClick: payload == null || payload.isEmpty
          ? null
          : () => _schedulePayloadNavigation(payload),
    );
  }

  Future<ChatNotificationLevel> _resolveChatNotificationLevel(
    String chatId,
  ) async {
    final normalizedChatId = chatId.trim();
    if (normalizedChatId.isEmpty) {
      return ChatNotificationLevel.all;
    }
    final snapshot = await _chatNotificationSettingsStore.getSettings(
      SharedPreferencesChatNotificationSettingsStore.chatKey(normalizedChatId),
    );
    return snapshot?.level ?? ChatNotificationLevel.all;
  }

  Future<void> _hydrateIncomingCallCoordinator(
    Map<String, dynamic> data,
  ) async {
    if (!GetIt.I.isRegistered<CallCoordinatorService>()) {
      return;
    }

    final coordinator = GetIt.I<CallCoordinatorService>();
    await coordinator.ensureRuntimeReady();
    await coordinator.hydrateIncomingCall(
      callId: data['callId']?.toString(),
      chatId: data['chatId']?.toString(),
    );
  }
}
