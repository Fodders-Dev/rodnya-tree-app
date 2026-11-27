part of '../chat_screen.dart';

extension _ChatScreenPersistenceAndRealtime on _ChatScreenState {
  void _bindClipboardImagePaste() {
    final injectedStream = widget.clipboardImages;
    if (injectedStream != null) {
      _clipboardImagePasteSubscription =
          injectedStream.listen(_handleClipboardImagePaste);
      return;
    }

    if (!kIsWeb) {
      return;
    }

    final service = ChatClipboardImagePasteService();
    _clipboardImagePasteService = service;
    _clipboardImagePasteSubscription = service.images.listen(
      _handleClipboardImagePaste,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint(
          'ChatScreen: не удалось прочитать изображение из буфера: '
          '$error\n$stackTrace',
        );
      },
    );
  }

  void _handleClipboardImagePaste(ChatClipboardImage image) {
    if (!mounted || image.bytes.isEmpty) {
      return;
    }
    if (_selectedAttachments.length >= _ChatScreenState._maxAttachments) {
      showAppSnackBar(
        context,
        'Можно прикрепить не более 6 вложений.',
        isError: true,
      );
      return;
    }

    if (_selectedEdit != null) {
      _updateChatState(() {
        _selectedEdit = null;
      });
    }

    final hasAudio = _selectedAttachments.any(
      (file) => _attachmentKindFromXFile(file) == _ChatAttachmentKind.audio,
    );
    if (hasAudio) {
      _attachmentsController.clear();
    }

    final hasHeavyMedia = _selectedAttachments.any((file) {
      final kind = _attachmentKindFromXFile(file);
      return kind == _ChatAttachmentKind.video ||
          kind == _ChatAttachmentKind.audio;
    });
    if (hasHeavyMedia) {
      _attachmentsController.clear();
    }

    final addedCount = _attachmentsController.addAll(
      <XFile>[
        XFile.fromData(
          image.bytes,
          name: image.name,
          mimeType: image.mimeType,
        ),
      ],
    );
    if (addedCount == 0) {
      showAppSnackBar(
        context,
        'Не удалось прикрепить изображение из буфера.',
        isError: true,
      );
      return;
    }

    _messageFocusNode.requestFocus();
  }

  List<_OutgoingMessage> get _optimisticMessages {
    final chatId = _chatId;
    if (chatId == null || chatId.isEmpty) {
      return const <_OutgoingMessage>[];
    }
    return _sendQueue.messagesFor(chatId);
  }

  void _handleSendQueueChanged() {
    if (!mounted) {
      return;
    }

    String? failureMessageToShow;
    var shouldMarkDirectChatBlocked = false;
    final optimisticMessages = _optimisticMessages;
    for (final message in optimisticMessages) {
      if (message.attachments.any(_isRecordedVoiceAttachment) &&
          _handledVoiceSendIds.add('${message.localId}-${message.status}')) {
        if (message.status == _OutgoingMessageStatus.sent) {
          _recordingController.completeSend();
        } else if (message.status == _OutgoingMessageStatus.failed) {
          _recordingController.markSendFailed(
            message.errorText ?? 'Не удалось отправить сообщение.',
          );
        }
      }

      if (message.status != _OutgoingMessageStatus.failed ||
          !_reportedSendFailureIds.add(message.localId)) {
        continue;
      }
      final errorText = message.errorText ?? 'Не удалось отправить сообщение.';
      failureMessageToShow ??= errorText;
      if (errorText.toLowerCase().contains('заблокирован') &&
          _isCurrentDirectChat) {
        shouldMarkDirectChatBlocked = true;
      }
    }

    // SPEED-5: очередь нотифицирует по ЛЮБОМУ чату и на каждый переход —
    // ребилдим экран только когда видимый оптимистичный список ЭТОГО чата
    // реально изменился (или надо проставить blocked-флаг). При rapid-fire
    // это срезает лишние полные ребилды списка сообщений.
    final fingerprint = optimisticMessages
        .map((message) => '${message.localId}:${message.status}:'
            '${message.progress?.stage}:${message.progress?.completed}:'
            '${message.errorText != null}')
        .join('|');
    final fingerprintChanged = fingerprint != _lastSendQueueFingerprint;
    _lastSendQueueFingerprint = fingerprint;
    if (!fingerprintChanged && !shouldMarkDirectChatBlocked) {
      if (failureMessageToShow != null) {
        final pendingFailureText = failureMessageToShow;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          showAppSnackBar(context, pendingFailureText, isError: true);
        });
      }
      return;
    }

    _updateChatState(() {
      if (shouldMarkDirectChatBlocked) {
        _isDirectChatBlocked = true;
        _directChatBlockedLabel ??=
            _participantLabelForUserId(_currentDirectPeerUserId ?? '');
      }
    });

    if (failureMessageToShow != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        showAppSnackBar(context, failureMessageToShow!, isError: true);
      });
    }
  }

  void _configureBrowserContextMenu() {
    if (!kIsWeb) {
      return;
    }
    _browserContextMenuWasEnabled = BrowserContextMenu.enabled;
    if (_browserContextMenuWasEnabled) {
      unawaited(BrowserContextMenu.disableContextMenu());
    }
  }

  void _restoreBrowserContextMenu() {
    if (!kIsWeb ||
        !_browserContextMenuWasEnabled ||
        BrowserContextMenu.enabled) {
      return;
    }
    unawaited(BrowserContextMenu.enableContextMenu());
  }

  void _bindTimelineController(String chatId) {
    final currentController = _timelineController;
    if (currentController != null && currentController.chatId == chatId) {
      return;
    }

    currentController?.dispose();
    final nextController = ChatTimelineController(
      chatId: chatId,
      chatService: _chatService,
    );
    _timelineController = nextController;
    unawaited(nextController.start());
    unawaited(_ensureCallRuntimeReady(chatId));
  }

  Future<void> _bootstrapChat() async {
    _updateChatState(() {
      _isBootstrapping = true;
      _bootstrapError = null;
      _didInitialUnreadJump = false;
      _unreadAnchorMessageId = null;
      _newBelowViewportCount = 0;
      _arrivalLedgerIds.clear();
      _newestArrivalSeen = null;
      _unreadDividerAboveViewport = false;
    });

    try {
      final currentUserId = _chatService.currentUserId;
      if (currentUserId == null || currentUserId.isEmpty) {
        throw StateError('Сессия недоступна');
      }

      String? resolvedChatId = widget.chatId;
      if (resolvedChatId == null || resolvedChatId.isEmpty) {
        final otherUserId = widget.otherUserId;
        if (otherUserId == null || otherUserId.isEmpty) {
          throw StateError('Не удалось определить чат');
        }
        resolvedChatId = await _chatService.getOrCreateChat(otherUserId);
      }
      if (resolvedChatId == null || resolvedChatId.isEmpty) {
        throw StateError('Не удалось определить чат');
      }

      if (!mounted) {
        return;
      }

      _updateChatState(() {
        _currentUserId = currentUserId;
        _chatId = resolvedChatId;
        _isBootstrapping = false;
      });

      // Помечаем чат активным — пуши и system-replays для входящих
      // от этого чата теперь будут глушиться, пока юзер тут.
      // dispose() снимет флажок (с защитой от race с другим экраном
      // чата, открытым подряд).
      ActiveChatTracker.instance.setActive(resolvedChatId);

      // Сообщаем серверу через WS чтобы он тоже не слал пуш для
      // сообщений из этого чата — без этого пуш улетал в VKPNS до
      // того как WS-doставка успевала, и на телефоне раздавался buzz
      // даже при открытом окне чата.
      unawaited(_realtimeService?.setActiveChat(resolvedChatId));
      // S5: heartbeat активности раз в 30с — серверная запись протухает
      // через 60с idle. Свёрнутое приложение замораживает таймер →
      // флажок гаснет → пуши снова доходят (раньше открытый-но-свёрнутый
      // чат глушил их бесконечно).
      _activeChatHeartbeat?.cancel();
      final heartbeatChatId = resolvedChatId;
      _activeChatHeartbeat = Timer.periodic(
        const Duration(seconds: 30),
        (_) => unawaited(_realtimeService?.setActiveChat(heartbeatChatId)),
      );

      // Очищаем шторку от прошлых нотификаций этого чата — юзер
      // зашёл сам, читать он начнёт прямо сейчас.
      if (GetIt.I.isRegistered<NotificationServiceInterface>()) {
        unawaited(
          GetIt.I<NotificationServiceInterface>()
              .dismissChatNotifications(resolvedChatId),
        );
      }

      unawaited(_sendQueue.restoreChat(resolvedChatId));
      _bindTimelineController(resolvedChatId);
      _bindRealtimeIndicators();
      unawaited(_restoreBootstrapUiState());
      if (_shouldPrefetchChatDetails()) {
        unawaited(_loadChatDetails());
      }
      unawaited(_markChatAsRead());
      if (_searchController.hasQuery) {
        _scheduleServerSearch(_searchController.query, resolvedChatId);
      }
    } catch (error) {
      _appStatusService.reportError(
        error,
        fallbackMessage: 'Не удалось открыть чат.',
      );
      if (!mounted) {
        return;
      }
      _updateChatState(() {
        _bootstrapError = _appStatusService.isOffline
            ? 'Нет соединения. Откройте чат снова, когда интернет вернётся.'
            : 'Не удалось открыть чат. Проверьте соединение и попробуйте снова.';
        _isBootstrapping = false;
      });
    }
  }

  bool _shouldPrefetchChatDetails() {
    if (_chatDetails != null) {
      return false;
    }
    if (widget.isGroup) {
      return true;
    }
    final normalizedTitle = widget.title.trim();
    return normalizedTitle.isEmpty ||
        normalizedTitle == 'Чат' ||
        normalizedTitle == 'Пользователь' ||
        widget.otherUserId == null ||
        widget.otherUserId!.trim().isEmpty;
  }

  Future<void> _restoreBootstrapUiState() async {
    // Was a serial chain — pinned → draft → notifications → autodelete.
    // Each one hits SharedPreferences (or its custom store) and does a
    // setState afterwards, so the chat sat with a half-painted header
    // for ~150–300 ms on Samsung mid-range while the chain laddered.
    // All four are independent so we fan them out and await once.
    await Future.wait<void>([
      _runBootstrapTask(
        _restorePinnedMessageIfNeeded,
        label: 'восстановление закрепа',
      ),
      _runBootstrapTask(
        _restoreDraftIfNeeded,
        label: 'восстановление черновика',
      ),
      _runBootstrapTask(
        _restoreNotificationSettingsIfNeeded,
        label: 'восстановление настроек уведомлений',
      ),
      _runBootstrapTask(
        _restoreAutoDeleteSettingsIfNeeded,
        label: 'восстановление автоудаления',
      ),
    ]);
  }

  Future<void> _runBootstrapTask(
    Future<void> Function() task, {
    required String label,
  }) async {
    try {
      await task();
    } catch (error, stackTrace) {
      debugPrint('ChatScreen: сбой during $label: $error\n$stackTrace');
    }
  }

  Future<void> _loadChatDetails() async {
    final chatId = _chatId;
    if (chatId == null || chatId.isEmpty) {
      return;
    }

    _updateChatState(() {
      _isLoadingChatDetails = true;
    });

    // Cache-first hydrate: if we have a cached snapshot of this
    // chat's details, paint it immediately so the user sees a
    // properly-populated header (title, member count, online dot)
    // even if the API call below times out / fails on offline.
    final cache = _chatDetailsCache;
    if (cache != null && _chatDetails == null) {
      try {
        final cached = await cache.read(chatId);
        if (cached != null && mounted) {
          _updateChatState(() {
            _chatDetails = cached;
            _resolvedTitle = cached.displayTitleFor(_currentUserId);
          });
        }
      } catch (_) {
        // Cache corruption is non-fatal — let the API repopulate.
      }
    }

    try {
      final details = await _chatService.getChatDetails(chatId);
      if (!mounted) {
        return;
      }

      // Persist to cache for future offline opens.
      unawaited(cache?.write(chatId, details));

      _updateChatState(() {
        _chatDetails = details;
        _resolvedTitle = details.displayTitleFor(_currentUserId);
        _isLoadingChatDetails = false;
        // Seed presence state from the chat details — gives the
        // subtitle a correct "в сети / был N минут назад" on first
        // paint without waiting for a realtime event.
        for (final participant in details.participants) {
          if (participant.userId == _currentUserId) continue;
          if (participant.isOnline) {
            _onlineUserIds.add(participant.userId);
          }
          if (participant.lastSeenAt != null) {
            _peerLastSeenAt[participant.userId] = participant.lastSeenAt!;
          }
        }
      });

      // GP2: opened from a chats-list «Позвонить» action — candidates are
      // now loaded, so fire the group-call flow exactly once (it runs the
      // same discovery → picker → start path as the header call button).
      if (widget.autoStartCall != null && !_autoStartCallConsumed && mounted) {
        _autoStartCallConsumed = true;
        unawaited(_startCallFromHeader(widget.autoStartCall!));
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      _updateChatState(() {
        _isLoadingChatDetails = false;
      });
    }
  }

  Future<void> _markChatAsRead() async {
    final chatId = _chatId;
    final userId = _currentUserId;
    if (_isMarkingRead ||
        chatId == null ||
        chatId.isEmpty ||
        userId == null ||
        userId.isEmpty) {
      return;
    }

    _isMarkingRead = true;
    try {
      await _chatService.markChatAsRead(chatId, userId);
    } catch (error, stackTrace) {
      debugPrint(
        'ChatScreen: не удалось отметить чат как прочитанный: $error\n$stackTrace',
      );
    } finally {
      _isMarkingRead = false;
    }
  }

  List<String> _draftCandidateKeys() {
    final keys = <String>[];
    final resolvedChatId = _chatId;
    if (resolvedChatId != null && resolvedChatId.isNotEmpty) {
      keys.add(SharedPreferencesChatDraftStore.chatKey(resolvedChatId));
    }
    final widgetChatId = widget.chatId;
    if (widgetChatId != null && widgetChatId.isNotEmpty) {
      keys.add(SharedPreferencesChatDraftStore.chatKey(widgetChatId));
    }
    final otherUserId = widget.otherUserId;
    if (otherUserId != null && otherUserId.isNotEmpty) {
      keys.add(SharedPreferencesChatDraftStore.directUserKey(otherUserId));
    }
    return keys.toSet().toList();
  }

  String? _primaryDraftKey() {
    final resolvedChatId = _chatId;
    if (resolvedChatId != null && resolvedChatId.isNotEmpty) {
      return SharedPreferencesChatDraftStore.chatKey(resolvedChatId);
    }
    final widgetChatId = widget.chatId;
    if (widgetChatId != null && widgetChatId.isNotEmpty) {
      return SharedPreferencesChatDraftStore.chatKey(widgetChatId);
    }
    final otherUserId = widget.otherUserId;
    if (otherUserId != null && otherUserId.isNotEmpty) {
      return SharedPreferencesChatDraftStore.directUserKey(otherUserId);
    }
    return null;
  }

  String _composeMessageText({
    required String typedText,
    required String forwardedText,
  }) {
    final cleanTyped = typedText.trim();
    final cleanForwarded = forwardedText.trim();
    if (cleanTyped.isEmpty) {
      return cleanForwarded;
    }
    if (cleanForwarded.isEmpty) {
      return cleanTyped;
    }
    return '$cleanTyped\n\n$cleanForwarded';
  }

  Future<void> _restoreDraftIfNeeded() async {
    final keys = _draftCandidateKeys();
    if (keys.isEmpty) {
      return;
    }

    final restoreVersion = _draftPersistenceVersion;
    ChatDraftSnapshot? bestDraft;
    String? bestDraftKey;
    for (final key in keys) {
      final snapshot = await _draftStore.getDraft(key);
      if (restoreVersion != _draftPersistenceVersion) {
        return;
      }
      if (snapshot == null) {
        continue;
      }
      if (ChatDraftSuppression.instance.shouldSuppressDraftKey(
        key: key,
        text: snapshot.text,
      )) {
        unawaited(_clearDraftKey(key));
        continue;
      }
      if (bestDraft == null ||
          snapshot.updatedAt.isAfter(bestDraft.updatedAt)) {
        bestDraft = snapshot;
        bestDraftKey = key;
      }
    }

    final preferredKey = _primaryDraftKey();
    if (bestDraft == null) {
      _lastPersistedDraftKey = preferredKey;
      return;
    }
    if (restoreVersion != _draftPersistenceVersion ||
        _messageController.text.isNotEmpty) {
      return;
    }

    _isApplyingDraft = true;
    _messageController.value = TextEditingValue(
      text: bestDraft.text,
      selection: TextSelection.collapsed(offset: bestDraft.text.length),
    );
    _isApplyingDraft = false;

    _lastPersistedDraftKey = preferredKey ?? bestDraftKey;
    if (preferredKey != null &&
        bestDraftKey != null &&
        preferredKey != bestDraftKey) {
      await _draftStore.saveDraft(preferredKey, bestDraft.text);
      await _draftStore.clearDraft(bestDraftKey);
    }
  }

  void _handleDraftChanged() {
    if (_isApplyingDraft) {
      return;
    }
    _handleTypingChanged();
    final version = ++_draftPersistenceVersion;
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(_persistCurrentDraft(version));
    });
  }

  Future<void> _persistCurrentDraft(int version) async {
    final draftKey = _primaryDraftKey();
    if (draftKey == null) {
      return;
    }

    final text = _messageController.text;
    if (version != _draftPersistenceVersion) {
      return;
    }
    if (text.trim().isEmpty) {
      await _draftStore.clearDraft(draftKey);
    } else {
      ChatDraftSuppression.instance.recordLocalDraftEdit(
        key: draftKey,
        text: text,
      );
      await _draftStore.saveDraft(draftKey, text);
    }
    if (version != _draftPersistenceVersion) {
      return;
    }

    final previousKey = _lastPersistedDraftKey;
    _lastPersistedDraftKey = draftKey;
    if (previousKey != null && previousKey != draftKey) {
      await _draftStore.clearDraft(previousKey);
    }
  }

  Future<void> _clearActiveDraft() async {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = null;
    _draftPersistenceVersion++;
    final keys = _draftCandidateKeys();
    for (final key in keys) {
      await _draftStore.clearDraft(key);
    }
    _lastPersistedDraftKey = _primaryDraftKey();
  }

  void _suppressSentDraftEcho({required String? chatId, required String text}) {
    final normalizedChatId = chatId?.trim();
    if (normalizedChatId == null || normalizedChatId.isEmpty) {
      return;
    }
    ChatDraftSuppression.instance.suppressSentDraft(
      chatId: normalizedChatId,
      text: text,
    );
  }

  Future<void> _clearDraftKey(String key) async {
    await _draftStore.clearDraft(key);
  }

  List<String> _notificationSettingsCandidateKeys() {
    final keys = <String>[];
    final resolvedChatId = _chatId;
    if (resolvedChatId != null && resolvedChatId.isNotEmpty) {
      keys.add(
        SharedPreferencesChatNotificationSettingsStore.chatKey(resolvedChatId),
      );
    }
    final widgetChatId = widget.chatId;
    if (widgetChatId != null && widgetChatId.isNotEmpty) {
      keys.add(
        SharedPreferencesChatNotificationSettingsStore.chatKey(widgetChatId),
      );
    }
    final otherUserId = widget.otherUserId;
    if (otherUserId != null && otherUserId.isNotEmpty) {
      keys.add(
        SharedPreferencesChatNotificationSettingsStore.directUserKey(
          otherUserId,
        ),
      );
    }
    return keys.toSet().toList();
  }

  String? _primaryNotificationSettingsKey() {
    final resolvedChatId = _chatId;
    if (resolvedChatId != null && resolvedChatId.isNotEmpty) {
      return SharedPreferencesChatNotificationSettingsStore.chatKey(
        resolvedChatId,
      );
    }
    final widgetChatId = widget.chatId;
    if (widgetChatId != null && widgetChatId.isNotEmpty) {
      return SharedPreferencesChatNotificationSettingsStore.chatKey(
        widgetChatId,
      );
    }
    final otherUserId = widget.otherUserId;
    if (otherUserId != null && otherUserId.isNotEmpty) {
      return SharedPreferencesChatNotificationSettingsStore.directUserKey(
        otherUserId,
      );
    }
    return null;
  }

  Future<void> _restoreNotificationSettingsIfNeeded() async {
    final keys = _notificationSettingsCandidateKeys();
    if (keys.isEmpty) {
      return;
    }

    ChatNotificationSettingsSnapshot? bestSnapshot;
    String? bestKey;
    for (final key in keys) {
      final snapshot = await _notificationSettingsStore.getSettings(key);
      if (snapshot == null) {
        continue;
      }
      if (bestSnapshot == null ||
          snapshot.updatedAt.isAfter(bestSnapshot.updatedAt)) {
        bestSnapshot = snapshot;
        bestKey = key;
      }
    }

    final preferredKey = _primaryNotificationSettingsKey();
    final nextSnapshot =
        bestSnapshot ?? ChatNotificationSettingsSnapshot.defaults();
    if (!mounted) {
      return;
    }
    _updateChatState(() {
      _notificationSettings = nextSnapshot;
    });

    _lastPersistedNotificationSettingsKey = preferredKey ?? bestKey;
    if (bestSnapshot != null &&
        preferredKey != null &&
        bestKey != null &&
        preferredKey != bestKey) {
      await _notificationSettingsStore.saveSettings(preferredKey, bestSnapshot);
      await _notificationSettingsStore.clearSettings(bestKey);
    }
  }

  List<String> _autoDeleteCandidateKeys() {
    final keys = <String>[];
    final resolvedChatId = _chatId;
    if (resolvedChatId != null && resolvedChatId.isNotEmpty) {
      keys.add(SharedPreferencesChatAutoDeleteStore.chatKey(resolvedChatId));
    }
    final widgetChatId = widget.chatId;
    if (widgetChatId != null && widgetChatId.isNotEmpty) {
      keys.add(SharedPreferencesChatAutoDeleteStore.chatKey(widgetChatId));
    }
    final otherUserId = widget.otherUserId;
    if (otherUserId != null && otherUserId.isNotEmpty) {
      keys.add(SharedPreferencesChatAutoDeleteStore.directUserKey(otherUserId));
    }
    return keys.toSet().toList();
  }

  String? _primaryAutoDeleteKey() {
    final resolvedChatId = _chatId;
    if (resolvedChatId != null && resolvedChatId.isNotEmpty) {
      return SharedPreferencesChatAutoDeleteStore.chatKey(resolvedChatId);
    }
    final widgetChatId = widget.chatId;
    if (widgetChatId != null && widgetChatId.isNotEmpty) {
      return SharedPreferencesChatAutoDeleteStore.chatKey(widgetChatId);
    }
    final otherUserId = widget.otherUserId;
    if (otherUserId != null && otherUserId.isNotEmpty) {
      return SharedPreferencesChatAutoDeleteStore.directUserKey(otherUserId);
    }
    return null;
  }

  Future<void> _restoreAutoDeleteSettingsIfNeeded() async {
    final keys = _autoDeleteCandidateKeys();
    if (keys.isEmpty) {
      return;
    }

    ChatAutoDeleteSnapshot? bestSnapshot;
    String? bestKey;
    for (final key in keys) {
      final snapshot = await _autoDeleteStore.getSettings(key);
      if (snapshot == null) {
        continue;
      }
      if (bestSnapshot == null ||
          snapshot.updatedAt.isAfter(bestSnapshot.updatedAt)) {
        bestSnapshot = snapshot;
        bestKey = key;
      }
    }

    final preferredKey = _primaryAutoDeleteKey();
    final nextSnapshot = bestSnapshot ?? ChatAutoDeleteSnapshot.defaults();
    if (!mounted) {
      return;
    }

    _updateChatState(() {
      _autoDeleteSettings = nextSnapshot;
    });

    _lastPersistedAutoDeleteKey = preferredKey ?? bestKey;
    if (bestSnapshot != null &&
        preferredKey != null &&
        bestKey != null &&
        preferredKey != bestKey) {
      await _autoDeleteStore.saveSettings(preferredKey, bestSnapshot);
      await _autoDeleteStore.clearSettings(bestKey);
    }
  }

  Future<void> _updateAutoDeleteOption(ChatAutoDeleteOption option) async {
    final settingsKey = _primaryAutoDeleteKey();
    final nextSnapshot = ChatAutoDeleteSnapshot(
      option: option,
      updatedAt: DateTime.now(),
    );

    if (settingsKey != null) {
      await _autoDeleteStore.saveSettings(settingsKey, nextSnapshot);
      final previousKey = _lastPersistedAutoDeleteKey;
      _lastPersistedAutoDeleteKey = settingsKey;
      if (previousKey != null && previousKey != settingsKey) {
        await _autoDeleteStore.clearSettings(previousKey);
      }
    } else {
      _lastPersistedAutoDeleteKey = null;
    }

    if (!mounted) {
      return;
    }
    _updateChatState(() {
      _autoDeleteSettings = nextSnapshot;
    });
  }

  Future<void> _persistNotificationSettings(
    ChatNotificationSettingsSnapshot snapshot,
  ) async {
    final settingsKey = _primaryNotificationSettingsKey();
    if (settingsKey == null) {
      return;
    }
    await _notificationSettingsStore.saveSettings(settingsKey, snapshot);
    final previousKey = _lastPersistedNotificationSettingsKey;
    _lastPersistedNotificationSettingsKey = settingsKey;
    if (previousKey != null && previousKey != settingsKey) {
      await _notificationSettingsStore.clearSettings(previousKey);
    }
  }

  Future<void> _updateNotificationLevel(ChatNotificationLevel level) async {
    final nextSnapshot = ChatNotificationSettingsSnapshot(
      level: level,
      updatedAt: DateTime.now(),
    );
    if (!mounted) {
      return;
    }
    _updateChatState(() {
      _notificationSettings = nextSnapshot;
    });
    await _persistNotificationSettings(nextSnapshot);
    final detailsChatId = _chatDetails?.chatId;
    final String? activeChatId = (_chatId != null && _chatId!.isNotEmpty)
        ? _chatId
        : (detailsChatId != null && detailsChatId.isNotEmpty
            ? detailsChatId
            : widget.chatId);
    if (activeChatId != null && activeChatId.isNotEmpty) {
      try {
        await _chatService.updateChatPreferences(
          chatId: activeChatId,
          notificationLevel: level.name,
        );
      } on UnsupportedError {
        // Test fakes may not implement server prefs sync yet.
      } on NoSuchMethodError {
        // Test fakes delegating to noSuchMethod.
      } catch (_) {
        // Keep local setting applied even if transient network call fails.
      }
    }
    if (!mounted) {
      return;
    }
    String message;
    switch (level) {
      case ChatNotificationLevel.all:
        message = 'Уведомления чата включены';
        break;
      case ChatNotificationLevel.silent:
        message = 'Чат переведен в тихий режим';
        break;
      case ChatNotificationLevel.muted:
        message = 'Уведомления этого чата отключены';
        break;
    }
    showAppSnackBar(context, message);
  }

  bool _hasCurrentUserReaction(ChatMessage message, String emoji) {
    final currentUserId = _currentUserId;
    if (currentUserId == null ||
        currentUserId.isEmpty ||
        emoji.trim().isEmpty) {
      return false;
    }
    return message.reactions.any(
      (reaction) =>
          reaction.emoji == emoji && reaction.userIds.contains(currentUserId),
    );
  }

  List<_ReactionGroup> _reactionGroupsForMessage(ChatMessage message) {
    if (message.reactions.isEmpty) {
      return const <_ReactionGroup>[];
    }

    final currentUserId = _currentUserId;
    final groups = message.reactions
        .map(
          (reaction) => _ReactionGroup(
            emoji: reaction.emoji,
            count: reaction.count,
            isMine: reaction.isMine(currentUserId),
          ),
        )
        .toList()
      ..sort((left, right) => left.emoji.compareTo(right.emoji));
    return groups;
  }

  Future<void> _toggleReactionForMessage(
      ChatMessage message, String emoji) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null ||
        currentUserId.isEmpty ||
        emoji.trim().isEmpty) {
      return;
    }
    final chatId = _chatId ?? widget.chatId;
    if (chatId == null || chatId.trim().isEmpty) {
      return;
    }

    try {
      await _chatService.toggleMessageReaction(
        chatId: chatId,
        messageId: message.id,
        emoji: emoji,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, 'Не удалось обновить реакцию.');
    }
  }

  List<String> _pinCandidateKeys() {
    final keys = <String>[];
    final resolvedChatId = _chatId;
    if (resolvedChatId != null && resolvedChatId.isNotEmpty) {
      keys.add(SharedPreferencesChatPinStore.chatKey(resolvedChatId));
    }
    final widgetChatId = widget.chatId;
    if (widgetChatId != null && widgetChatId.isNotEmpty) {
      keys.add(SharedPreferencesChatPinStore.chatKey(widgetChatId));
    }
    final otherUserId = widget.otherUserId;
    if (otherUserId != null && otherUserId.isNotEmpty) {
      keys.add(SharedPreferencesChatPinStore.directUserKey(otherUserId));
    }
    return keys.toSet().toList();
  }

  String? _primaryPinKey() {
    final resolvedChatId = _chatId;
    if (resolvedChatId != null && resolvedChatId.isNotEmpty) {
      return SharedPreferencesChatPinStore.chatKey(resolvedChatId);
    }
    final widgetChatId = widget.chatId;
    if (widgetChatId != null && widgetChatId.isNotEmpty) {
      return SharedPreferencesChatPinStore.chatKey(widgetChatId);
    }
    final otherUserId = widget.otherUserId;
    if (otherUserId != null && otherUserId.isNotEmpty) {
      return SharedPreferencesChatPinStore.directUserKey(otherUserId);
    }
    return null;
  }

  Future<void> _restorePinnedMessageIfNeeded() async {
    final keys = _pinCandidateKeys();
    if (keys.isEmpty) {
      return;
    }

    ChatPinnedMessageSnapshot? bestSnapshot;
    String? bestKey;
    for (final key in keys) {
      final snapshot = await _pinStore.getPinnedMessage(key);
      if (snapshot == null) {
        continue;
      }
      if (bestSnapshot == null ||
          snapshot.pinnedAt.isAfter(bestSnapshot.pinnedAt)) {
        bestSnapshot = snapshot;
        bestKey = key;
      }
    }

    final preferredKey = _primaryPinKey();
    if (bestSnapshot == null) {
      _lastPersistedPinKey = preferredKey;
      return;
    }

    if (!mounted) {
      return;
    }
    _updateChatState(() {
      _pinnedMessage = bestSnapshot;
    });

    _lastPersistedPinKey = preferredKey ?? bestKey;
    if (preferredKey != null && bestKey != null && preferredKey != bestKey) {
      await _pinStore.savePinnedMessage(preferredKey, bestSnapshot);
      await _pinStore.clearPinnedMessage(bestKey);
    }
  }

  Future<void> _persistPinnedMessage(
    ChatPinnedMessageSnapshot snapshot,
  ) async {
    final pinKey = _primaryPinKey();
    if (pinKey == null) {
      return;
    }
    await _pinStore.savePinnedMessage(pinKey, snapshot);
    final previousKey = _lastPersistedPinKey;
    _lastPersistedPinKey = pinKey;
    if (previousKey != null && previousKey != pinKey) {
      await _pinStore.clearPinnedMessage(previousKey);
    }
  }

  Future<void> _clearPinnedMessage() async {
    final keys = _pinCandidateKeys();
    for (final key in keys) {
      await _pinStore.clearPinnedMessage(key);
    }
    if (!mounted) {
      return;
    }
    _updateChatState(() {
      _pinnedMessage = null;
      _highlightedPinnedMessageId = null;
    });
    _lastPersistedPinKey = _primaryPinKey();
  }

  ChatPinnedMessageSnapshot _snapshotFromMessage(ChatMessage message) {
    return ChatPinnedMessageSnapshot(
      messageId: message.id,
      senderId: message.senderId,
      senderName:
          _groupSenderLabel(message.senderName, message.senderId) ?? 'Участник',
      text: message.text,
      attachmentCount: message.attachments.length,
      pinnedAt: DateTime.now(),
    );
  }

  bool _isSamePinnedMessage(
    ChatPinnedMessageSnapshot first,
    ChatPinnedMessageSnapshot second,
  ) {
    return first.messageId == second.messageId &&
        first.senderId == second.senderId &&
        first.senderName == second.senderName &&
        first.text == second.text &&
        first.attachmentCount == second.attachmentCount;
  }

  Future<void> _pinRemoteMessage(ChatMessage message) async {
    final snapshot = _snapshotFromMessage(message);
    if (!mounted) {
      return;
    }
    _updateChatState(() {
      _pinnedMessage = snapshot;
    });
    await _persistPinnedMessage(snapshot);
    if (!mounted) {
      return;
    }
    showAppSnackBar(context, 'Сообщение закреплено');
  }

  void _schedulePinnedSync(List<ChatMessage> remoteMessages) {
    final pinned = _pinnedMessage;
    if (pinned == null) {
      return;
    }
    final match = remoteMessages
        .where((message) => message.id == pinned.messageId)
        .cast<ChatMessage?>()
        .firstWhere((message) => message != null, orElse: () => null);

    if (match == null) {
      return;
    }

    final nextSnapshot = pinned.copyWith(
      senderId: match.senderId,
      senderName: _groupSenderLabel(match.senderName, match.senderId) ??
          pinned.senderName,
      text: match.text,
      attachmentCount: match.attachments.length,
    );
    if (_isSamePinnedMessage(nextSnapshot, pinned)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pinnedMessage?.messageId != pinned.messageId) {
        return;
      }
      _updateChatState(() {
        _pinnedMessage = nextSnapshot;
      });
      unawaited(_persistPinnedMessage(nextSnapshot));
    });
  }

  void _bindRealtimeIndicators() {
    if (_realtimeService == null || _realtimeIndicatorsSubscription != null) {
      return;
    }

    unawaited(_realtimeService.connect());
    _realtimeIndicatorsSubscription =
        _realtimeService.events.listen(_handleRealtimeIndicatorEvent);
  }

  void _handleRealtimeIndicatorEvent(CustomApiRealtimeEvent event) {
    final currentChatId = _chatId;
    if (!mounted) {
      return;
    }

    if (event.type == 'connection.ready') {
      _updateChatState(() {
        _isRealtimeReconnecting = false;
        _onlineUserIds
          ..clear()
          ..addAll(event.onlineUserIds);
      });
      // S5: после реконнекта серверный флажок активности мог протухнуть
      // — переобъявляем сразу, не дожидаясь heartbeat-тика.
      if (currentChatId != null && currentChatId.isNotEmpty) {
        unawaited(_realtimeService?.setActiveChat(currentChatId));
      }
      return;
    }

    // S5: разрыв WS — честный статус «Подключение…» в шапке, как в
    // Telegram, вместо тихо замершего чата.
    if (event.type == 'connection.disconnected') {
      if (!_isRealtimeReconnecting) {
        _updateChatState(() => _isRealtimeReconnecting = true);
      }
      return;
    }

    if (event.type == 'presence.updated') {
      final userId = event.userId;
      if (userId == null || userId.isEmpty) {
        return;
      }
      // Backend sends lastSeenAt on the offline transition (== updatedAt
      // for that broadcast). For online events lastSeenAt is null —
      // because the user IS online, the timestamp would be misleading.
      final lastSeenRaw = event.lastSeenAt ?? event.updatedAt;
      final parsedLastSeen =
          lastSeenRaw == null ? null : DateTime.tryParse(lastSeenRaw);
      _updateChatState(() {
        if (event.isOnline == true) {
          _onlineUserIds.add(userId);
        } else {
          _onlineUserIds.remove(userId);
          _typingUsers.remove(userId);
          if (parsedLastSeen != null) {
            _peerLastSeenAt[userId] = parsedLastSeen;
          }
        }
      });
      return;
    }

    if (event.type == 'chat.typing.updated' &&
        currentChatId != null &&
        event.chatId == currentChatId) {
      final userId = event.userId;
      if (userId == null ||
          userId.isEmpty ||
          userId == _currentUserId ||
          event.isTyping == null) {
        return;
      }

      _updateChatState(() {
        if (event.isTyping == true) {
          _typingUsers[userId] = DateTime.now().add(const Duration(seconds: 4));
          _onlineUserIds.add(userId);
          _ensureTypingDecayTimer();
        } else {
          _typingUsers.remove(userId);
        }
      });
      return;
    }

    if (event.type == 'chat.draft.updated' &&
        currentChatId != null &&
        event.chatId == currentChatId &&
        event.userId == _currentUserId) {
      _handleRemoteDraftUpdate(event);
      return;
    }

    if (event.type == 'chat.pin.updated' &&
        currentChatId != null &&
        event.chatId == currentChatId) {
      _handleRemotePinUpdate(event);
    }
  }

  void _handleRemotePinUpdate(CustomApiRealtimeEvent event) {
    final pinKey = _primaryPinKey();
    if (pinKey == null) {
      return;
    }

    final rawPin = event.pin;
    final snapshot =
        rawPin == null ? null : ChatPinnedMessageSnapshot.fromJson(rawPin);
    final pinStore = _pinStore;

    if (snapshot == null || snapshot.messageId.trim().isEmpty) {
      unawaited(
        pinStore is HybridChatPinStore
            ? pinStore.clearLocalPinnedMessage(pinKey)
            : pinStore.clearPinnedMessage(pinKey),
      );
      _updateChatState(() {
        _pinnedMessage = null;
        _highlightedPinnedMessageId = null;
      });
      _lastPersistedPinKey = pinKey;
      return;
    }

    unawaited(
      pinStore is HybridChatPinStore
          ? pinStore.saveLocalPinnedMessage(pinKey, snapshot)
          : pinStore.savePinnedMessage(pinKey, snapshot),
    );
    _updateChatState(() {
      _pinnedMessage = snapshot;
    });
    _lastPersistedPinKey = pinKey;
  }

  void _handleRemoteDraftUpdate(CustomApiRealtimeEvent event) {
    final draftKey = _primaryDraftKey();
    if (draftKey == null) {
      return;
    }

    final rawDraft = event.draft;
    final draft =
        rawDraft == null ? null : ChatDraftSnapshot.fromJson(rawDraft);
    final nextText = draft?.text ?? '';
    if (nextText.trim().isNotEmpty &&
        ChatDraftSuppression.instance.shouldSuppressDraft(
          chatId: event.chatId ?? _chatId ?? '',
          text: nextText,
        )) {
      unawaited(_clearDraftKey(draftKey));
      if (_messageController.text.trim() == nextText.trim()) {
        _isApplyingDraft = true;
        _messageController.clear();
        _isApplyingDraft = false;
      }
      return;
    }
    final draftStore = _draftStore;
    if (nextText.trim().isEmpty) {
      unawaited(
        draftStore is HybridChatDraftStore
            ? draftStore.clearLocalDraft(draftKey)
            : draftStore.clearDraft(draftKey),
      );
      final currentText = _messageController.text;
      if (currentText.trim().isEmpty ||
          ChatDraftSuppression.instance.shouldSuppressDraft(
            chatId: event.chatId ?? _chatId ?? '',
            text: currentText,
          )) {
        _isApplyingDraft = true;
        _messageController.clear();
        _isApplyingDraft = false;
      }
      _lastPersistedDraftKey = draftKey;
      return;
    } else {
      unawaited(
        draftStore is HybridChatDraftStore
            ? draftStore.saveLocalDraft(draftKey, nextText)
            : draftStore.saveDraft(draftKey, nextText),
      );
    }

    if (_messageFocusNode.hasFocus ||
        _selectedEdit != null ||
        _selectedForward != null ||
        _selectedForwardBatch != null) {
      return;
    }

    _isApplyingDraft = true;
    _messageController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
    _isApplyingDraft = false;
    _lastPersistedDraftKey = draftKey;
  }

  void _ensureTypingDecayTimer() {
    _typingDecayTimer ??=
        Timer.periodic(const Duration(seconds: 1), (_) => _pruneTypingUsers());
  }

  void _pruneTypingUsers() {
    if (!mounted) {
      _typingDecayTimer?.cancel();
      _typingDecayTimer = null;
      return;
    }

    final now = DateTime.now();
    final expiredUserIds = _typingUsers.entries
        .where((entry) => !entry.value.isAfter(now))
        .map((entry) => entry.key)
        .toList();
    if (expiredUserIds.isEmpty) {
      return;
    }

    _updateChatState(() {
      for (final userId in expiredUserIds) {
        _typingUsers.remove(userId);
      }
      if (_typingUsers.isEmpty) {
        _typingDecayTimer?.cancel();
        _typingDecayTimer = null;
      }
    });
  }

  void _handleTypingChanged() {
    final hasInput = _messageController.text.trim().isNotEmpty;
    if (hasInput) {
      unawaited(_setTypingActive(true));
    } else {
      unawaited(_setTypingActive(false));
    }
  }

  Future<void> _setTypingActive(bool isTyping, {bool force = false}) async {
    final chatId = _chatId;
    if (_realtimeService == null || chatId == null || chatId.isEmpty) {
      return;
    }

    if (!force && _typingHeartbeatActive == isTyping) {
      return;
    }

    _typingHeartbeatActive = isTyping;
    if (isTyping) {
      _typingHeartbeatTimer?.cancel();
      await _realtimeService.sendTypingState(chatId: chatId, isTyping: true);
      _typingHeartbeatTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) {
          final stillTyping = _messageController.text.trim().isNotEmpty;
          if (!stillTyping) {
            unawaited(_setTypingActive(false));
            return;
          }
          unawaited(
            _realtimeService.sendTypingState(chatId: chatId, isTyping: true),
          );
        },
      );
      return;
    }

    _typingHeartbeatTimer?.cancel();
    _typingHeartbeatTimer = null;
    await _realtimeService.sendTypingState(chatId: chatId, isTyping: false);
  }

  String? _typingSubtitle() {
    if (_typingUsers.isEmpty) {
      return null;
    }

    final typingUserIds = _typingUsers.keys.toList();
    if (!widget.isGroup && typingUserIds.isNotEmpty) {
      return 'печатает…';
    }
    if (typingUserIds.length == 1) {
      return '${_participantLabelForUserId(typingUserIds.first)} печатает…';
    }
    return 'Печатают: ${typingUserIds.length}';
  }

  String? _presenceSubtitle(ChatDetails? details) {
    // S5: разрыв WS перекрывает presence — пока соединение не вернётся,
    // «в сети» всё равно может врать.
    if (_isRealtimeReconnecting) {
      return 'Подключение…';
    }
    final otherParticipantIds = _otherParticipantIds(details);
    if (otherParticipantIds.isEmpty) {
      return null;
    }

    final onlineCount = otherParticipantIds
        .where((participantId) => _onlineUserIds.contains(participantId))
        .length;

    if (widget.isGroup) {
      if (onlineCount == 0) {
        return null;
      }
      return onlineCount == 1 ? '1 участник в сети' : '$onlineCount в сети';
    }

    // Direct chat — single peer presence drives the subtitle. Either
    // "в сети" (live) or "был(а) N минут назад" derived from the
    // last-seen timestamp populated by chat-details + presence events.
    if (onlineCount > 0) {
      return 'в сети';
    }
    final peerId =
        otherParticipantIds.isNotEmpty ? otherParticipantIds.first : null;
    if (peerId == null) {
      return null;
    }
    final lastSeen = _peerLastSeenAt[peerId];
    if (lastSeen == null) {
      return null;
    }
    return _formatLastSeen(lastSeen, peerId: peerId, details: details);
  }

  /// "был(а) N минут назад" formatter. Prefers gendered Russian forms
  /// when the participant has a known gender hint in the chat details
  /// (currently we don't carry gender on ChatParticipantSummary, so we
  /// default to feminine "была" if the display name ends with a vowel —
  /// a reasonable heuristic for Russian first names).
  String _formatLastSeen(
    DateTime lastSeen, {
    required String peerId,
    required ChatDetails? details,
  }) {
    final delta = DateTime.now().difference(lastSeen);
    final female = _looksFemaleName(_participantLabelForUserId(peerId));
    final byl = female ? 'была' : 'был';

    if (delta.inSeconds < 60) {
      return '$byl только что';
    }
    if (delta.inMinutes < 60) {
      final m = delta.inMinutes;
      return '$byl $m ${_minutesSuffix(m)} назад';
    }
    if (delta.inHours < 24) {
      final h = delta.inHours;
      return '$byl $h ${_hoursSuffix(h)} назад';
    }
    if (delta.inDays < 7) {
      final d = delta.inDays;
      return '$byl $d ${_daysSuffix(d)} назад';
    }
    // Older than a week — fall back to a date string (локальная дата:
    // UTC-компоненты у полуночи давали соседний день).
    final local = toLocalForDisplay(lastSeen);
    final date =
        '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}';
    return '$byl $date';
  }

  bool _looksFemaleName(String displayName) {
    final firstName = displayName.trim().split(RegExp(r'\s+')).first;
    if (firstName.isEmpty) return false;
    final last = firstName[firstName.length - 1].toLowerCase();
    // Russian feminine first names overwhelmingly end in 'а' or 'я'.
    return last == 'а' || last == 'я';
  }

  String _minutesSuffix(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return 'минуту';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return 'минуты';
    }
    return 'минут';
  }

  String _hoursSuffix(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return 'час';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return 'часа';
    }
    return 'часов';
  }

  String _daysSuffix(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    if (mod10 == 1 && mod100 != 11) return 'день';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return 'дня';
    return 'дней';
  }

  List<String> _otherParticipantIds(ChatDetails? details) {
    final currentUserId = _currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      return const <String>[];
    }

    final participantIds = <String>{
      ...?details?.participantIds,
      ..._latestRemoteMessages.expand((message) => message.participants),
      if (widget.otherUserId != null && widget.otherUserId!.isNotEmpty)
        widget.otherUserId!,
    };

    participantIds.removeWhere(
      (participantId) =>
          participantId.trim().isEmpty || participantId == currentUserId,
    );
    return participantIds.toList();
  }

  ChatParticipantSummary? _participantForUserId(String userId) {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      return null;
    }
    final details = _chatDetails;
    if (details == null) {
      return null;
    }
    for (final participant in details.participants) {
      if (participant.userId == normalizedUserId) {
        return participant;
      }
    }
    return null;
  }

  String _participantLabelForUserId(String userId) {
    final participant = _participantForUserId(userId);
    if (participant != null && participant.displayName.trim().isNotEmpty) {
      return participant.displayName;
    }

    for (final message in _latestRemoteMessages) {
      if (message.senderId == userId &&
          (message.senderName?.trim().isNotEmpty ?? false)) {
        return message.senderName!.trim();
      }
    }

    return 'Участник';
  }

  Future<void> _openDirectChatForParticipant(
    ChatParticipantSummary participant,
  ) {
    return _openDirectChatForUser(
      userId: participant.userId,
      title: participant.displayName,
      photoUrl: participant.photoUrl,
    );
  }

  Future<void> _openDirectChatForMessage(ChatMessage message) {
    final participant = _participantForUserId(message.senderId);
    return _openDirectChatForUser(
      userId: message.senderId,
      title: participant?.displayName ?? message.senderName ?? 'Участник',
      photoUrl: participant?.photoUrl,
    );
  }

  Future<void> _openDirectChatForUser({
    required String userId,
    required String title,
    String? photoUrl,
  }) async {
    final normalizedUserId = userId.trim();
    final currentUserId = _currentUserId?.trim();
    if (normalizedUserId.isEmpty ||
        currentUserId == null ||
        normalizedUserId == currentUserId) {
      return;
    }

    try {
      final chatId = await _chatService.getOrCreateChat(normalizedUserId);
      if (!mounted) {
        return;
      }
      if (chatId == null || chatId.trim().isEmpty) {
        showAppSnackBar(
          context,
          'Не удалось открыть личный чат.',
          isError: true,
        );
        return;
      }

      final resolvedTitle = title.trim().isNotEmpty
          ? title.trim()
          : _participantLabelForUserId(normalizedUserId);
      final resolvedPhoto = photoUrl != null && photoUrl.trim().isNotEmpty
          ? photoUrl.trim()
          : null;
      final openInParent = widget.onOpenDirectChat;
      if (openInParent != null) {
        openInParent(
          chatId: chatId.trim(),
          title: resolvedTitle,
          photoUrl: resolvedPhoto,
          otherUserId: normalizedUserId,
        );
        return;
      }

      final titleParam = Uri.encodeComponent(resolvedTitle);
      final userParam = Uri.encodeComponent(normalizedUserId);
      final photoParam = resolvedPhoto == null
          ? ''
          : '&photo=${Uri.encodeComponent(resolvedPhoto)}';
      await context.push(
        '/chats/view/${Uri.encodeComponent(chatId.trim())}'
        '?type=direct&title=$titleParam&userId=$userParam$photoParam',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(
        context,
        'Не удалось открыть личный чат.',
        isError: true,
      );
    }
  }

  String _chatSubtitle() {
    final typingSubtitle = _typingSubtitle();
    if (typingSubtitle != null) {
      return typingSubtitle;
    }

    final details = _chatDetails;
    final presenceSubtitle = _presenceSubtitle(details);
    if (presenceSubtitle != null) {
      return presenceSubtitle;
    }
    if (details != null && details.isBranch) {
      final branchCount = details.branchRoots.length;
      final memberCount = details.memberCount;
      final branchLabel = branchCount == 1 ? '1 ветка' : '$branchCount ветки';
      final memberLabel =
          memberCount == 1 ? '1 участник' : '$memberCount участников';
      return '$branchLabel · $memberLabel';
    }
    if (details != null && details.isGroup) {
      final memberCount = details.memberCount;
      return memberCount == 1 ? '1 участник' : '$memberCount участников';
    }
    return widget.chatType == 'branch'
        ? 'Чат ветки'
        : (widget.isGroup ? 'Групповой чат' : 'Личные сообщения');
  }
}
