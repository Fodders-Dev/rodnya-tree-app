part of '../chat_screen.dart';

extension _ChatScreenComposerSection on _ChatScreenState {
  List<XFile> get _selectedAttachments => _attachmentsController.attachments;

  void _handleAttachmentsChanged() {
    if (mounted) {
      _updateChatState(() {});
    }
  }

  void _handleRecordingControllerChanged() {
    if (!mounted) {
      return;
    }

    // C2: живая волна шлёт notify каждые ~120мс. Состав вложений и
    // composer↔бар свап нужны только на СМЕНЕ состояния — amplitude-only
    // нотификации пропускаем, чтобы не дёргать весь экран setState'ом.
    // Сам recording-бар перерисовывает волну/таймер через свой
    // AnimatedBuilder на том же контроллере.
    final state = _recordingController.state;
    if (state == _lastRecordingState) {
      return;
    }
    _lastRecordingState = state;

    final previewFile = _recordingController.previewFile;
    final shouldKeepPreview = state == ChatRecordingState.preview ||
        state == ChatRecordingState.failed;

    _attachmentsController.removeWhere(_isRecordedVoiceAttachment);
    if (shouldKeepPreview && previewFile != null) {
      _attachmentsController.replaceAll(<XFile>[previewFile]);
    }
    _updateChatState(() {});
  }

  bool _isRecordedVoiceAttachment(XFile file) {
    final rawName = file.name.trim().isNotEmpty
        ? file.name.trim()
        : path.basename(file.path);
    final normalizedName = rawName.toLowerCase();
    return normalizedName.startsWith('voice_note_') ||
        normalizedName.startsWith('voice-note-');
  }

  bool _isVideoNoteFile(XFile file) {
    final rawName = file.name.trim().isNotEmpty
        ? file.name.trim()
        : path.basename(file.path);
    final normalizedName = rawName.toLowerCase();
    return normalizedName.startsWith('video_note_') ||
        normalizedName.startsWith('video-note-');
  }

  Future<XFile> _renamePickedVideoAsVideoNote(XFile file) async {
    final originalName = file.name.trim().isNotEmpty
        ? file.name.trim()
        : path.basename(file.path);
    final extension = path.extension(originalName).trim().isNotEmpty
        ? path.extension(originalName).trim()
        : ((file.mimeType ?? '').toLowerCase().contains('webm')
            ? '.webm'
            : '.mp4');
    final nextName =
        'video_note_${DateTime.now().millisecondsSinceEpoch}$extension';
    if (file.path.trim().isNotEmpty) {
      return XFile(
        file.path,
        name: nextName,
        mimeType: file.mimeType,
      );
    }

    return XFile.fromData(
      await file.readAsBytes(),
      name: nextName,
      mimeType: file.mimeType,
    );
  }

  Future<void> _handleRecordingLongPressStart(
      LongPressStartDetails details) async {
    // FX1/C3a FR1: привязываем запись к пальцу, опущенному именно НА микрофон
    // (_micPointerId от локального Listener'а мик-кнопки), а не к любому
    // pointer-down в композере. Сам цикл move/release дальше ведёт
    // персистентный Listener — см. _handleRecordingPointer*.
    final micPointer = _micPointerId;
    if (micPointer == null) {
      // Нет валидного down на микрофоне — не стартуем (FR3-страховка).
      return;
    }
    _recordingPointerId = micPointer;
    _recordingPointerOrigin = details.globalPosition;
    _recordingPointerReleased = false;
    _recordingDragDx.value = 0;
    await _startRecording();
    // FX1/C3a FR3: палец отпустили, пока шёл старт (диалог разрешения) —
    // не оставляем осиротевшую запись без пальца: отменяем (discard).
    if (_recordingPointerReleased) {
      _recordingPointerId = null;
      _recordingPointerOrigin = null;
      _recordingPointerReleased = false;
      if (_recordingController.state == ChatRecordingState.recording) {
        unawaited(_cancelRecording());
      }
    }
  }

  /// C3a/V1: смещение указателя относительно точки старта — слайд-влево
  /// отменяет, слайд-вверх фиксирует (hands-free). Работает на raw-указателе
  /// со стабильного слоя, поэтому не зависит от ребилда композер↔бар.
  void _handleRecordingPointerMove(PointerMoveEvent event) {
    if (!mounted ||
        _recordingPointerId == null ||
        event.pointer != _recordingPointerId) {
      return;
    }
    if (_recordingController.state != ChatRecordingState.recording) {
      return;
    }
    final origin = _recordingPointerOrigin;
    if (origin == null) {
      return;
    }
    final dx = event.position.dx - origin.dx;
    final dy = event.position.dy - origin.dy;
    // Визуальный отклик слайда: бар следит за пальцем (0..-порог).
    _recordingDragDx.value =
        dx.clamp(-_ChatScreenState._recordingCancelThreshold, 0.0).toDouble();

    if (dx <= -_ChatScreenState._recordingCancelThreshold) {
      // C2: тактильный фидбек на слайд-влево (отмена).
      HapticFeedback.mediumImpact();
      // Указатель больше не ведёт запись — отпускание не должно отправить.
      _recordingPointerId = null;
      _recordingPointerOrigin = null;
      // dx НЕ сбрасываем в 0: _cancelRecording асинхронно рвёт рекордер,
      // бар живёт ещё кадры до смены state — при сбросе он мигал бы в
      // rest-визуал (полная волна, простой крестик). Оставляем взведённое
      // красное; следующая запись обнулит dx в longPressStart (ревью).
      _recordingDragDx.value = -_ChatScreenState._recordingCancelThreshold;
      unawaited(_cancelRecording());
      return;
    }

    if (dy <= -_ChatScreenState._recordingLockThreshold) {
      // C2: тактильный фидбек на слайд-вверх (фиксация). FR2: порог 52px —
      // осознанный заметный свайп, обычное отпускание (указатель почти на
      // месте) его не достигает, поэтому ложного lock на lift нет.
      HapticFeedback.mediumImpact();
      _recordingController.lock();
      // Зафиксировано (hands-free): отпускание пальца больше НЕ завершает —
      // отправка/отмена идут кнопками locked-бара.
      _recordingPointerId = null;
      _recordingPointerOrigin = null;
      _recordingDragDx.value = 0;
    }
  }

  /// C3a/V1 (FR1): надёжный конец press-hold — отпускание пальца завершает
  /// и ОТПРАВЛЯЕТ запись, даже после ребилда композер→бар.
  void _handleRecordingPointerUp(PointerUpEvent event) {
    if (!mounted ||
        _recordingPointerId == null ||
        event.pointer != _recordingPointerId) {
      return;
    }
    if (_recordingController.state == ChatRecordingState.recording) {
      _recordingPointerId = null;
      _recordingPointerOrigin = null;
      _recordingDragDx.value = 0;
      unawaited(_stopAndSendRecording());
      return;
    }
    // FX1/C3a FR3: запись ещё не активна (идёт старт/диалог разрешения), а
    // палец уже отпущен — помечаем, чтобы старт отменил осиротевшую запись.
    _recordingPointerReleased = true;
  }

  /// FX1/C3a FR2: прерванный жест (систему перехватили / pointer cancel) —
  /// это НЕ отправка. Отменяем запись (discard), а не шлём голосовое.
  void _handleRecordingPointerCancel(PointerCancelEvent event) {
    if (!mounted ||
        _recordingPointerId == null ||
        event.pointer != _recordingPointerId) {
      return;
    }
    if (_recordingController.state == ChatRecordingState.recording) {
      _recordingPointerId = null;
      _recordingPointerOrigin = null;
      _recordingDragDx.value = 0;
      unawaited(_cancelRecording());
      return;
    }
    _recordingPointerReleased = true;
  }

  Future<void> _pickImageAttachments() async {
    if (_selectedEdit != null) {
      _updateChatState(() {
        _selectedEdit = null;
      });
    }
    if (_selectedAttachments.any(
      (file) => _attachmentKindFromXFile(file) == _ChatAttachmentKind.audio,
    )) {
      _attachmentsController.clear();
    }
    if (_selectedAttachments.length >= _ChatScreenState._maxAttachments) {
      showAppSnackBar(
        context,
        'Можно прикрепить не более 6 вложений.',
        isError: true,
      );
      return;
    }

    try {
      final picked = widget.pickImages != null
          ? await widget.pickImages!()
          : await _imagePicker.pickMultiImage(
              imageQuality: 80,
              maxWidth: 1600,
            );
      if (picked.isEmpty || !mounted) {
        return;
      }

      final hadHeavyMedia = _selectedAttachments.any((f) {
        final kind = _attachmentKindFromXFile(f);
        return kind == _ChatAttachmentKind.video ||
            kind == _ChatAttachmentKind.audio;
      });
      if (hadHeavyMedia) {
        _attachmentsController.clear();
      }

      final addedCount = _attachmentsController.addAll(picked);
      if (picked.length > addedCount) {
        showAppSnackBar(
          context,
          'Можно добавить не более 6 фото.',
          isError: true,
        );
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(
        context,
        'Не удалось выбрать фотографии.',
        isError: true,
      );
    }
  }

  Future<void> _pickVideoAttachment({
    ImageSource source = ImageSource.gallery,
    bool asVideoNote = false,
    Duration maxDuration = const Duration(minutes: 10),
  }) async {
    if (_selectedEdit != null) {
      _updateChatState(() {
        _selectedEdit = null;
      });
    }
    if (_selectedAttachments.any(
      (file) => _attachmentKindFromXFile(file) == _ChatAttachmentKind.audio,
    )) {
      _attachmentsController.clear();
    }
    try {
      final pickedVideo = widget.pickVideo != null
          ? await widget.pickVideo!()
          : await _imagePicker.pickVideo(
              source: source,
              maxDuration: maxDuration,
            );
      if (pickedVideo == null || !mounted) {
        return;
      }

      final picked = asVideoNote
          ? await _renamePickedVideoAsVideoNote(pickedVideo)
          : pickedVideo;

      final size = await picked.length();
      if (size > 50 * 1024 * 1024) {
        // 50MB limit
        if (mounted) {
          showAppSnackBar(
            context,
            'Видео слишком большое (макс. 50 МБ).',
            isError: true,
          );
        }
        return;
      }

      _attachmentsController.replaceAll(<XFile>[picked]);
    } catch (_) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(
        context,
        asVideoNote
            ? 'Не удалось подготовить кружок.'
            : 'Не удалось выбрать видео.',
        isError: true,
      );
    }
  }

  Future<void> _pickVideoNote() async {
    // In-app Telegram-style кружок recorder with a round live preview —
    // user complaint was "почему у нас кружочки пишутся не так, как в
    // телеграм, а через файл отдельный?". This now runs on WEB too:
    // camera_web (≥0.3.5) drives getUserMedia preview + MediaRecorder
    // video recording, so the old «<input type=file> can't preview»
    // fallback (which silently no-op'd on web — the file dialog needs a
    // direct user gesture the long-press loses) is gone. If the camera
    // is missing / permission denied, the recorder shows its own error
    // affordance instead of doing nothing.
    if (_selectedEdit != null) {
      _updateChatState(() => _selectedEdit = null);
    }
    if (_selectedAttachments.any(
      (file) => _attachmentKindFromXFile(file) == _ChatAttachmentKind.audio,
    )) {
      _attachmentsController.clear();
    }
    // C3d/V2 (FR8): запись кружка инлайн-оверлеем — чат остаётся виден,
    // без fullscreen-роута и его лага; камера стартует сразу. Результат/
    // отмена прилетают в _onInlineKruzhokCaptured/_onInlineKruzhokCancel.
    _updateChatState(() => _showInlineKruzhok = true);
  }

  Future<void> _pickGenericFile() async {
    if (_selectedEdit != null) {
      _updateChatState(() {
        _selectedEdit = null;
      });
    }
    if (_selectedAttachments.any(
      (file) => _attachmentKindFromXFile(file) == _ChatAttachmentKind.audio,
    )) {
      _attachmentsController.clear();
    }
    try {
      // file_picker 11.x replaced `FilePicker.platform.pickFiles(...)`
      // with the static `FilePicker.pickFiles(...)`. Same kwargs.
      final result = await FilePicker.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );

      if (result == null || result.files.isEmpty || !mounted) {
        return;
      }

      final pickedFiles = result.files
          .where((f) => f.path != null)
          .map((f) => XFile(f.path!, name: f.name, bytes: f.bytes))
          .toList();

      if (pickedFiles.isEmpty) return;

      final addedCount = _attachmentsController.addAll(pickedFiles);
      if (pickedFiles.length > addedCount) {
        showAppSnackBar(context, 'Можно добавить не более 6 файлов.');
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
      if (mounted) {
        showAppSnackBar(context, 'Не удалось выбрать файл.', isError: true);
      }
    }
  }

  Future<void> _openAttachmentPicker() async {
    // Telegram-style attachment grid: vivid colored icon-tiles in a 4-up
    // layout. Replaces the previous vertical ListTile menu which the
    // user described as "колхоз".
    final choice = await showAttachmentPickerSheet(
      context,
      title: 'ПРИКРЕПИТЬ',
      actions: const [
        AttachmentPickerAction(
          id: 'images',
          icon: Icons.photo_library_rounded,
          label: 'Галерея',
          color: Color(0xFFE05A8B), // pink — "photos"
        ),
        AttachmentPickerAction(
          id: 'video',
          icon: Icons.videocam_rounded,
          label: 'Видео',
          color: Color(0xFFE85A40), // orange — "video"
        ),
        AttachmentPickerAction(
          id: 'video_note',
          icon: Icons.radio_button_checked_rounded,
          label: 'Кружок',
          color: Color(0xFF7B5BD6), // purple — "video note"
        ),
        AttachmentPickerAction(
          id: 'file',
          icon: Icons.insert_drive_file_rounded,
          label: 'Файл',
          color: Color(0xFF3D8DFF), // blue — "file"
        ),
      ],
    );

    if (!mounted || choice == null) {
      return;
    }

    switch (choice) {
      case 'images':
        await _pickImageAttachments();
        return;
      case 'video':
        await _pickVideoAttachment();
        return;
      case 'video_note':
        await _pickVideoNote();
        return;
      case 'file':
        await _pickGenericFile();
        return;
    }
  }

  /// Global hardware keyboard handler — registered on HardwareKeyboard directly.
  ///
  /// This is more reliable than [Focus.onKeyEvent] on Flutter web (CanvasKit)
  /// where key-event bubbling can be intercepted by the browser text layer.
  ///
  /// Returns true (consumes event) only when the message field has focus and
  /// we actually handle the shortcut.
  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (!mounted || event is! KeyDownEvent) return false;
    // Only fire when the composer text field (or this screen) has focus.
    final bool composerFocused = _messageFocusNode.hasFocus ||
        FocusScope.of(context).focusedChild == _messageFocusNode;

    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    // Ctrl+Enter → send (regardless of composer focus so tooltip users can send)
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.enter) {
      final canSend = _messageController.text.trim().isNotEmpty ||
          _selectedAttachments.isNotEmpty ||
          _selectedForward != null ||
          _selectedForwardBatch != null ||
          _selectedEdit != null;
      if (canSend) {
        if (_selectedEdit != null) {
          _saveEditedMessage();
        } else {
          _sendCurrentMessage();
        }
        return true;
      }
    }

    // The rest only when composer is focused.
    if (!composerFocused) return false;

    // Escape → clear context or exit search/selection
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_isSelectionMode) {
        _exitSelectionMode();
        return true;
      }
      if (_isSearchMode) {
        _closeSearch();
        return true;
      }
      if (_selectedEdit != null) {
        _updateChatState(() => _selectedEdit = null);
        _messageController.clear();
        return true;
      }
      if (_selectedReply != null) {
        _updateChatState(() => _selectedReply = null);
        return true;
      }
      if (_selectedForward != null || _selectedForwardBatch != null) {
        _updateChatState(() {
          _selectedForward = null;
          _selectedForwardBatch = null;
        });
        return true;
      }
    }

    // ↑ when field is empty → edit last own message (Telegram behaviour)
    if (!isCtrl && event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_messageController.text.isEmpty && _selectedEdit == null) {
        _startEditingLastOwnMessage();
        return true;
      }
    }

    // Ctrl+F → open search
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyF) {
      if (!_isSearchMode) {
        _openSearch();
        return true;
      }
    }

    return false;
  }

  // Legacy Focus.onKeyEvent — kept as secondary handler.
  KeyEventResult _handleMessageKeyEvent(FocusNode node, KeyEvent event) {
    return KeyEventResult.ignored; // Global handler takes precedence.
  }

  /// Edit the most recent message sent by the current user (↑ shortcut).
  void _startEditingLastOwnMessage() {
    final messages = _latestRemoteMessages;
    final myId = _currentUserId;
    if (messages.isEmpty || myId == null) return;

    for (final msg in messages) {
      if (msg.senderId == myId && msg.text.isNotEmpty) {
        _selectEditMessage(msg);
        return;
      }
    }
  }

  Future<void> _startRecording() async {
    if (_selectedEdit != null) {
      _updateChatState(() {
        _selectedEdit = null;
      });
    }
    if (_selectedAttachments.isNotEmpty) {
      _attachmentsController.clear();
    }
    try {
      await _recordingController.start();
      // C2: тактильный фидбек, когда запись реально пошла (после выдачи
      // разрешения) — как в Telegram.
      if (_recordingController.state == ChatRecordingState.recording) {
        HapticFeedback.lightImpact();
      }
    } catch (error) {
      debugPrint('Error starting recording: $error');
      if (mounted) {
        showAppSnackBar(context, 'Не удалось начать запись.', isError: true);
      }
    }
  }

  Future<void> _stopAndSendRecording() async {
    await _recordingController.stopToPreview();
    // Auto-send immediately — no preview panel, Telegram-style.
    if (!mounted) return;
    if (_recordingController.state == ChatRecordingState.preview) {
      await _sendCurrentMessage();
    }
  }

  Future<void> _cancelRecording() async {
    await _recordingController.cancelCurrent();
  }

  Future<void> _discardPendingVoiceAttachment() async {
    final voiceAttachment = _selectedAttachments.cast<XFile?>().firstWhere(
          (file) =>
              file != null &&
              _attachmentKindFromXFile(file) == _ChatAttachmentKind.audio,
          orElse: () => null,
        );
    if (voiceAttachment == null) {
      return;
    }
    _recordingController.discardPreview();
    _attachmentsController.remove(voiceAttachment);
  }

  Future<void> _rerecordVoiceAttachment() async {
    await _discardPendingVoiceAttachment();
    if (!mounted) {
      return;
    }
    await _startRecording();
  }

  Future<void> _sendCurrentMessage() async {
    final currentUserId = _currentUserId;
    final chatId = _chatId;
    if (currentUserId == null ||
        currentUserId.isEmpty ||
        chatId == null ||
        chatId.isEmpty) {
      // Bootstrap still running — give the user visible feedback.
      if (mounted) {
        showAppSnackBar(
          context,
          'Чат ещё загружается, подождите секунду.',
          duration: const Duration(seconds: 2),
        );
      }
      return;
    }

    final text = _messageController.text.trim();
    final forwardBatch = _selectedForwardBatch;
    if (forwardBatch != null) {
      await _sendForwardBatch(forwardBatch, commentText: text);
      return;
    }
    final attachments = List<XFile>.from(_selectedAttachments);
    final forwardedAttachments = List<ChatAttachment>.from(
        _selectedForward?.attachments ?? const <ChatAttachment>[]);
    final messageText = _composeMessageText(
      typedText: text,
      forwardedText: _selectedForward?.text ?? '',
    );
    final replyTo = _selectedReply;
    if (messageText.isEmpty &&
        attachments.isEmpty &&
        forwardedAttachments.isEmpty) {
      return;
    }

    // SPEED-1 замер: от тапа «отправить» до кадра, в котором отрисован
    // оптимистичный пузырь (цель <16мс — один кадр, «эффект Telegram»).
    final tapTrace = PerfTrace('chat.tap-to-bubble');

    if (attachments.any(_isRecordedVoiceAttachment)) {
      _recordingController.markSending();
    }
    _suppressSentDraftEcho(chatId: chatId, text: messageText);
    _messageController.clear();
    unawaited(
      _clearActiveDraft().catchError(
        (e) => debugPrint('[chat] draft-clear error: $e'),
      ),
    );

    _updateChatState(() {
      _selectedEdit = null;
      _selectedReply = null;
      _selectedForward = null;
    });
    _attachmentsController.clear();
    await _sendQueue.enqueue(
      chatId: chatId,
      senderId: currentUserId,
      text: messageText,
      attachments: attachments,
      forwardedAttachments: forwardedAttachments,
      replyTo: replyTo,
      expiresInSeconds: _autoDeleteSettings.option.ttl?.inSeconds,
    );
    // enqueue уже дёрнул notify → setState; пузырь отрисуется в ближайшем
    // кадре — фиксируем именно его.
    WidgetsBinding.instance.addPostFrameCallback((_) => tapTrace.finish());

    // Side-effects: fire-and-forget so they can't block or kill the send.
    unawaited(
      _setTypingActive(false, force: true).catchError(
        (e) => debugPrint('[chat] typing-clear error: $e'),
      ),
    );
  }

  Future<void> _sendForwardBatch(
    _ForwardBatchDraft draft, {
    required String commentText,
  }) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      return;
    }

    final batchItems = List<_ForwardDraft>.from(draft.items);
    if (batchItems.isEmpty) {
      return;
    }

    final comment = commentText.trim();
    _suppressSentDraftEcho(chatId: _chatId, text: comment);
    _messageController.clear();
    unawaited(
      _clearActiveDraft().catchError(
        (e) => debugPrint('[chat] draft-clear error: $e'),
      ),
    );
    _updateChatState(() {
      _selectedEdit = null;
      _selectedReply = null;
      _selectedForward = null;
      _selectedForwardBatch = null;
    });
    _attachmentsController.clear();
    unawaited(
      _setTypingActive(false, force: true).catchError(
        (e) => debugPrint('[chat] typing-clear error: $e'),
      ),
    );

    if (comment.isNotEmpty) {
      await _enqueueOutgoingMessageAndSend(
        senderId: currentUserId,
        text: comment,
      );
    }

    for (final item in batchItems) {
      final forwardedText = item.text.trim();
      await _enqueueOutgoingMessageAndSend(
        senderId: currentUserId,
        text: forwardedText,
        forwardedAttachments: item.attachments,
      );
    }
  }

  Future<void> _enqueueOutgoingMessageAndSend({
    required String senderId,
    required String text,
    List<XFile> attachments = const <XFile>[],
    List<ChatAttachment> forwardedAttachments = const <ChatAttachment>[],
    ChatReplyReference? replyTo,
  }) async {
    final chatId = _chatId;
    if (!mounted || chatId == null || chatId.isEmpty) {
      return;
    }
    await _sendQueue.enqueue(
      chatId: chatId,
      senderId: senderId,
      text: text,
      attachments: attachments,
      forwardedAttachments: forwardedAttachments,
      replyTo: replyTo,
      expiresInSeconds: _autoDeleteSettings.option.ttl?.inSeconds,
    );
  }

  Future<void> _saveEditedMessage() async {
    final edit = _selectedEdit;
    final chatId = _chatId;
    if (edit == null || chatId == null || chatId.isEmpty) {
      return;
    }

    final nextText = _messageController.text.trim();
    if (nextText.isEmpty && !edit.hasAttachments) {
      showAppSnackBar(context, 'Сообщение не должно быть пустым.');
      return;
    }

    try {
      unawaited(
        _setTypingActive(false, force: true).catchError(
          (e) => debugPrint('[chat] typing-clear error: $e'),
        ),
      );
      await _chatService.editChatMessage(
        chatId: chatId,
        messageId: edit.messageId,
        text: nextText,
      );
      _suppressSentDraftEcho(chatId: chatId, text: nextText);
      _messageController.clear();
      unawaited(
        _clearActiveDraft().catchError(
          (e) => debugPrint('[chat] draft-clear error: $e'),
        ),
      );
      if (!mounted) {
        return;
      }
      _updateChatState(() {
        _selectedEdit = null;
      });
      _attachmentsController.clear();
      _recordingController.discardPreview();
    } catch (_) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, 'Не удалось сохранить изменения.',
          isError: true);
    }
  }

  /// C3d/V2 (FR8): кружок записан инлайн-оверлеем — прячем оверлей и кладём
  /// результат во вложения (та же проверка размера, что и у роутового пути).
  Future<void> _onInlineKruzhokCaptured(XFile picked) async {
    if (mounted) {
      _updateChatState(() => _showInlineKruzhok = false);
    }
    try {
      final size = await picked.length();
      if (size > 50 * 1024 * 1024) {
        if (mounted) {
          showAppSnackBar(
            context,
            'Видео слишком большое (макс. 50 МБ).',
            isError: true,
          );
        }
        return;
      }
      _attachmentsController.replaceAll(<XFile>[picked]);
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          'Не удалось подготовить кружок.',
          isError: true,
        );
      }
    }
  }

  void _onInlineKruzhokCancel() {
    if (mounted) {
      _updateChatState(() => _showInlineKruzhok = false);
    }
  }

  /// Compact inline recording bar shown while the user is holding the mic.
  /// Replaces the entire input area — no popups, no panels — pure Telegram style.
  ///
  /// C2: бар перерисовывается через AnimatedBuilder на самом контроллере,
  /// так что живая волна (по амплитуде, ~120мс) и таймер обновляются без
  /// setState всего экрана. Слушатель экрана при этом пропускает
  /// amplitude-only нотификации.
  Widget _buildActiveRecordingInputBar() {
    final scheme = Theme.of(context).colorScheme;
    final recColor = scheme.error;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        8,
        4,
        8,
        MediaQuery.of(context).padding.bottom + 8,
      ),
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        borderRadius: BorderRadius.circular(28),
        child: AnimatedBuilder(
          animation: _recordingController,
          builder: (context, _) {
            final theme = Theme.of(context);
            final minutes = (_recordingController.durationSeconds ~/ 60)
                .toString()
                .padLeft(2, '0');
            final seconds = (_recordingController.durationSeconds % 60)
                .toString()
                .padLeft(2, '0');
            final waveform = _recordingController.liveWaveform;
            // Voice-cancel зона: слушаем dx слайда — подсказка едет за
            // пальцем и гаснет, кнопка отмены «наливается» красным и
            // раскрывает корзину у порога. Существующая подсказка/волна
            // остаются как есть (тест-контракт: '← отмена  ↑ фиксация' и
            // ключ 'recording-live-waveform' взаимоисключающи) — при
            // progress == 0 слои отмены полностью прозрачны.
            return ValueListenableBuilder<double>(
              valueListenable: _recordingDragDx,
              builder: (context, dragDx, _) {
                final progress =
                    (-dragDx / _ChatScreenState._recordingCancelThreshold)
                        .clamp(0.0, 1.0)
                        .toDouble();
                final trashRevealed = progress > 0.6;
                return Row(
                  children: [
                    // Cancel: кольцо-подсветка растёт с прогрессом слайда,
                    // у порога иконка сменяется корзиной.
                    Transform.scale(
                      scale: 1.0 + 0.25 * progress,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: recColor.withValues(
                            alpha: 0.10 + 0.35 * progress,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          onPressed: _cancelRecording,
                          tooltip: 'Отменить',
                          icon: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 120),
                            child: Icon(
                              trashRevealed
                                  ? Icons.delete_outline_rounded
                                  : Icons.close_rounded,
                              key: ValueKey(trashRevealed),
                              color: recColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                    _PulsingDot(color: recColor),
                    const SizedBox(width: 8),
                    // C2: крупный таймер моноширинными цифрами.
                    Text(
                      '$minutes:$seconds',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: recColor,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // C2: живая волна по амплитуде вместо статичной
                    // подсказки; поверх — «← Отмена», едущая за пальцем.
                    Expanded(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Opacity(
                            opacity: 1.0 - progress,
                            child: waveform.isEmpty
                                ? Text(
                                    '← отмена  ↑ фиксация',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : SizedBox(
                                    height: 28,
                                    child: CustomPaint(
                                      key: const Key('recording-live-waveform'),
                                      painter: _VoiceWaveformPainter(
                                        waveform: waveform,
                                        progress: 1.0,
                                        activeColor: recColor,
                                        inactiveColor:
                                            recColor.withValues(alpha: 0.30),
                                      ),
                                      size: Size.infinite,
                                    ),
                                  ),
                          ),
                          if (progress > 0)
                            IgnorePointer(
                              child: Transform.translate(
                                offset: Offset(dragDx * 0.6, 0),
                                child: Opacity(
                                  opacity: (1.0 - progress).clamp(0.25, 1.0),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.chevron_left_rounded,
                                        size: 18,
                                        color: recColor,
                                      ),
                                      Text(
                                        'Отмена',
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: recColor,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    // C3a/V1: чисто визуальная мик-кнопка. Жест press-hold
                    // ведёт персистентный Listener над композером (см.
                    // _buildMessageInputArea) — отдельный recognizer тут не
                    // видел pointer-down и не получал onLongPressEnd на lift.
                    _PulsingMicButton(color: recColor),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// Locked-state recording bar (user swiped up to lock).
  /// Compact single row — cancel on left, timer + label in centre, send on right.
  Widget _buildRecordingArea() {
    final theme = Theme.of(context);
    final minutes =
        (_recordingController.durationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds =
        (_recordingController.durationSeconds % 60).toString().padLeft(2, '0');
    final errorColor = theme.colorScheme.error;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        8,
        4,
        8,
        MediaQuery.of(context).padding.bottom + 8,
      ),
      child: GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        borderRadius: BorderRadius.circular(28),
        child: Row(
          children: [
            // Cancel
            IconButton(
              onPressed: _cancelRecording,
              tooltip: 'Отменить запись',
              icon: Icon(Icons.delete_outline_rounded, color: errorColor),
            ),
            // Pulsing dot + timer
            _PulsingDot(color: errorColor),
            const SizedBox(width: 8),
            Text(
              '$minutes:$seconds',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: errorColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Зафиксировано',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Send button
            IconButton.filled(
              onPressed: _stopAndSendRecording,
              tooltip: 'Отправить',
              icon: const Icon(Icons.send_rounded, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceAttachmentPreview(XFile voiceFile) {
    final theme = Theme.of(context);
    final hasRecordedPreview = _isRecordedVoiceAttachment(voiceFile);
    final durationLabel = hasRecordedPreview
        ? _formatDurationLabel(_recordingController.previewDurationSeconds)
        : 'Аудио';
    final recordingState = _recordingController.state;
    final helperText = recordingState == ChatRecordingState.sending
        ? 'Отправляем голосовое...'
        : recordingState == ChatRecordingState.failed
            ? (_recordingController.errorText ??
                'Не удалось отправить голосовое. Можно попробовать снова.')
            : 'Можно перезаписать или отправить.';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Проверьте голосовое',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  durationLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _VoicePlayerWidget(
            path: voiceFile.path,
            isMe: true,
            waveform: _recordingController.previewWaveform,
          ),
          const SizedBox(height: 4),
          Text(
            helperText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: recordingState == ChatRecordingState.failed
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              children: [
                if (hasRecordedPreview) ...[
                  TextButton.icon(
                    onPressed: recordingState == ChatRecordingState.sending
                        ? null
                        : _rerecordVoiceAttachment,
                    icon: const Icon(Icons.mic_none_rounded),
                    label: const Text('Перезаписать'),
                  ),
                  TextButton.icon(
                    onPressed: recordingState == ChatRecordingState.sending
                        ? null
                        : _discardPendingVoiceAttachment,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Удалить запись'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDurationLabel(int durationSeconds) {
    final minutes = (durationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (durationSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildMessageInputArea() {
    if (_isDirectChatBlocked) {
      return _buildBlockedComposerNotice();
    }

    final recordingState = _recordingController.state;
    final isLockedRecording = recordingState == ChatRecordingState.locked;
    final canSend = _messageController.text.trim().isNotEmpty ||
        _selectedAttachments.isNotEmpty ||
        _selectedForward != null ||
        _selectedForwardBatch != null ||
        _selectedEdit != null;

    // ── Compact Telegram-style recording UI ──
    // While the user is actively holding the mic, replace the whole input
    // area content with a minimal timer row so no big panel pops up.
    // We swap via AnimatedSwitcher so the recording bar fades + slides
    // in over the composer (220ms easeOutCubic) instead of appearing
    // as a hard cut. Same on the way back when recording stops.
    final isRecording = recordingState == ChatRecordingState.recording;
    // C3a/V1: персистентный Listener над AnimatedSwitcher'ом владеет циклом
    // press-hold (move/release) независимо от ребилда композер↔бар — иначе
    // на старте записи поддерево пересобирается и onLongPressEnd не приходит
    // на отпускание пальца.
    return Listener(
      // FX1/C3a FR1: этот композер-wide Listener ВЛАДЕЕТ только move/up/cancel
      // уже-захваченного recording-pointer (id ставит локальный Listener
      // мик-кнопки), но сам его НЕ назначает — иначе второе касание зоны
      // ввода перебивало бы привязку.
      onPointerMove: _handleRecordingPointerMove,
      onPointerUp: _handleRecordingPointerUp,
      onPointerCancel: _handleRecordingPointerCancel,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.08),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: isRecording
            ? KeyedSubtree(
                key: const ValueKey('composer-recording'),
                child: _buildActiveRecordingInputBar(),
              )
            : KeyedSubtree(
                key: const ValueKey('composer-idle'),
                child: _buildIdleComposer(canSend, isLockedRecording),
              ),
      ),
    );
  }

  /// Extracted from [_buildMessageInputArea] so the AnimatedSwitcher
  /// has a stable child key for the non-recording state. No behaviour
  /// change — this is the composer that used to be inlined.
  Widget _buildIdleComposer(bool canSend, bool isLockedRecording) {
    final recordingState = _recordingController.state;
    // Одна рамка, а не «овал в овале»: капсула композера и есть поле ввода
    // (как у Telegram), кнопки — плоские иконки внутри неё.
    return Padding(
      padding: EdgeInsets.fromLTRB(
        6,
        2,
        6,
        MediaQuery.of(context).padding.bottom + 6,
      ),
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
        borderRadius: BorderRadius.circular(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Show mic permission / error notices (not the "recording" state —
            // that is now handled by _buildActiveRecordingInputBar above).
            if (recordingState == ChatRecordingState.denied ||
                recordingState == ChatRecordingState.failed)
              _buildRecordingNotice(
                Theme.of(context),
                recordingState: recordingState,
              ),
            if (recordingState == ChatRecordingState.denied ||
                recordingState == ChatRecordingState.failed)
              const SizedBox(height: 8),
            // Composer-bar appearance is animated: AnimatedSize handles
            // the row-height grow / collapse; AnimatedSwitcher inside
            // cross-fades + slide-downs the actual bar so toggling
            // reply / edit / forward feels intentional rather than a
            // jump. Each helper wraps one conditional so the bars
            // never animate against each other when the user flips
            // between modes (e.g. cancel reply → start edit).
            _AnimatedComposerSlot(
              show: _selectedEdit != null,
              child: _selectedEdit == null
                  ? null
                  : _buildEditComposerBar(Theme.of(context), _selectedEdit!),
            ),
            _AnimatedComposerSlot(
              show: _selectedReply != null,
              child: _selectedReply == null
                  ? null
                  : _buildReplyComposerBar(Theme.of(context), _selectedReply!),
            ),
            _AnimatedComposerSlot(
              show: _selectedForward != null,
              child: _selectedForward == null
                  ? null
                  : _buildForwardComposerBar(
                      Theme.of(context), _selectedForward!),
            ),
            _AnimatedComposerSlot(
              show: _selectedForwardBatch != null,
              child: _selectedForwardBatch == null
                  ? null
                  : _buildForwardBatchComposerBar(
                      Theme.of(context),
                      _selectedForwardBatch!,
                    ),
            ),
            if (_autoDeleteSettings.option != ChatAutoDeleteOption.off)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    avatar: const Icon(Icons.timer_outlined, size: 18),
                    label: Text(
                      'Автоудаление: ${_autoDeleteSettings.option.label}',
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            // Only show the voice preview panel if NOT auto-sending
            // (i.e. it's a non-voice attachment or an edited voice).
            if (_selectedAttachments.isNotEmpty &&
                !_selectedAttachments.any(_isRecordedVoiceAttachment))
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.65),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          _attachmentPanelIcon(_selectedAttachments),
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _attachmentPanelTitle(_selectedAttachments),
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            if (_selectedAttachments.any(
                              _isRecordedVoiceAttachment,
                            )) {
                              _recordingController.discardPreview();
                            }
                            _attachmentsController.clear();
                          },
                          child: const Text('Очистить'),
                        ),
                      ],
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _attachmentSummaryLabel(_selectedAttachments),
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _attachmentKindsLabel(_selectedAttachments),
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _attachmentHintLabel(_selectedAttachments),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (_selectedAttachments.length == 1 &&
                        _attachmentKindFromXFile(_selectedAttachments.first) ==
                            _ChatAttachmentKind.audio)
                      _buildVoiceAttachmentPreview(
                        _selectedAttachments.first,
                      ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 74,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _selectedAttachments.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final attachment = _selectedAttachments[index];
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: SizedBox(
                                  width: 74,
                                  height: 74,
                                  child: _LocalMediaTile(file: attachment),
                                ),
                              ),
                              Positioned(
                                top: -6,
                                right: -6,
                                child: IconButton.filledTonal(
                                  onPressed: () {
                                    final attachmentToRemove =
                                        _selectedAttachments[index];
                                    if (_isRecordedVoiceAttachment(
                                      attachmentToRemove,
                                    )) {
                                      _recordingController.discardPreview();
                                    }
                                    _attachmentsController.removeAt(index);
                                  },
                                  icon: const Icon(Icons.close, size: 16),
                                  visualDensity: VisualDensity.compact,
                                  style: IconButton.styleFrom(
                                    minimumSize: const Size(28, 28),
                                    padding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            if (_selectedAttachments.isNotEmpty &&
                !_selectedAttachments.any(_isRecordedVoiceAttachment))
              const SizedBox(height: 8),
            Row(
              // Center-align so a single-line composer stays visually balanced;
              // multi-line still grows downward via TextField.maxLines.
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Кнопка вложений — плоская иконка без рамки (44dp
                // тач-таргет остаётся): рамок внутри капсулы быть не должно.
                _ComposerIconButton(
                  icon: Icons.attach_file_rounded,
                  tooltip: 'Добавить вложение',
                  onPressed: _selectedAttachments.length >=
                          _ChatScreenState._maxAttachments
                      ? null
                      : _openAttachmentPicker,
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Container(
                    // Поле без собственной рамки и фона: раньше внутри
                    // капсулы композера был второй овал («овал в овале»,
                    // жалоба пользователя). Скругление одно — у капсулы.
                    constraints: const BoxConstraints(minHeight: 40),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    // Focus wrapper owns the key event interception;
                    // TextField gets its own internal FocusNode.
                    // We keep _messageFocusNode for programmatic focus only.
                    child: Focus(
                      onKeyEvent: _handleMessageKeyEvent,
                      child: TextField(
                        controller: _messageController,
                        focusNode: _messageFocusNode,
                        onChanged: (_) => _updateChatState(() {}),
                        // User-reported: «зачем на овал в овале нарисованный».
                        // `InputDecoration.collapsed` clears `border` but
                        // not `enabledBorder` / `focusedBorder`, so the
                        // global InputDecorationTheme's stadium borders
                        // were drawing INSIDE the composer's outer
                        // border — that's the second oval the user saw.
                        // Explicitly nuke every border + the fill so
                        // the TextField is purely transparent.
                        decoration: InputDecoration(
                          isCollapsed: true,
                          filled: false,
                          fillColor: Colors.transparent,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          focusedErrorBorder: InputBorder.none,
                          hintText: 'Сообщение',
                          hintStyle: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.78),
                            // M3 (50+): ≥16 и для подсказки.
                            fontSize: 16,
                          ),
                        ),
                        // M3 (50+): 16/1.4 — крупный ввод; line-height
                        // оставляем, чтобы выносные элементы (д/р/у/щ)
                        // не липли к следующей строке.
                        style: const TextStyle(fontSize: 16, height: 1.4),
                        textCapitalization: TextCapitalization.sentences,
                        keyboardType: TextInputType.multiline,
                        minLines: 1,
                        maxLines: 5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildPrimaryComposerAction(
                  canSend: canSend,
                  isLockedRecording: isLockedRecording,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingNotice(
    ThemeData theme, {
    required ChatRecordingState recordingState,
  }) {
    final minutes =
        (_recordingController.durationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds =
        (_recordingController.durationSeconds % 60).toString().padLeft(2, '0');

    late final IconData icon;
    late final String title;
    late final String subtitle;
    late final Color foregroundColor;
    late final Color backgroundColor;

    switch (recordingState) {
      case ChatRecordingState.recording:
        icon = Icons.mic_rounded;
        title = '$minutes:$seconds';
        subtitle =
            'Проведите вверх, чтобы зафиксировать. Влево, чтобы отменить.';
        foregroundColor = Colors.red;
        backgroundColor = Colors.red.withValues(alpha: 0.08);
        break;
      case ChatRecordingState.failed:
        icon = Icons.error_outline;
        title = 'Голосовое не отправлено';
        subtitle = _recordingController.errorText ??
            'Проверьте сеть и попробуйте отправить снова.';
        foregroundColor = theme.colorScheme.error;
        backgroundColor =
            theme.colorScheme.errorContainer.withValues(alpha: 0.52);
        break;
      case ChatRecordingState.denied:
        icon = Icons.mic_off_outlined;
        title = 'Микрофон недоступен';
        subtitle =
            'Разрешите доступ к микрофону в настройках браузера или устройства.';
        foregroundColor = theme.colorScheme.error;
        backgroundColor =
            theme.colorScheme.errorContainer.withValues(alpha: 0.52);
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: foregroundColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: foregroundColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (recordingState == ChatRecordingState.denied)
            TextButton(
              onPressed: () {
                unawaited(openAppSettings());
              },
              child: const Text('Настройки'),
            ),
        ],
      ),
    );
  }

  Widget _buildPrimaryComposerAction({
    required bool canSend,
    required bool isLockedRecording,
  }) {
    if (canSend) {
      // Reference `.composer .send`: 42x42 accent-filled circle with
      // a soft drop shadow, replacing Material's flat IconButton.filled.
      // Icons.send (not send_rounded) keeps the existing widget tests
      // happy — both visually identical at this size.
      return _ComposerSendButton(
        icon: _selectedEdit != null ? Icons.check : Icons.send,
        tooltip: _selectedEdit != null ? 'Сохранить изменения' : 'Отправить',
        onPressed:
            _selectedEdit != null ? _saveEditedMessage : _sendCurrentMessage,
      );
    }

    final recordingState = _recordingController.state;
    if (isLockedRecording) {
      return IconButton.filled(
        onPressed: _stopAndSendRecording,
        tooltip: 'Остановить и прослушать',
        icon: const Icon(Icons.stop_rounded),
      );
    }

    // Mic / Kruzhok composer button — Telegram-style two-state.
    //   tap   → flip mode (voice ↔ kruzhok), no recording starts
    //   hold  → start recording in the current mode (voice loops
    //           through ChatRecordingController; kruzhok opens the
    //           video-note capture UI which is itself press-and-
    //           hold inside)
    //
    // We render the visual via a plain Material+Container instead of
    // IconButton + GestureDetector — the previous combo had IconButton's
    // own onPressed competing with our long-press in the gesture
    // arena, which on some Android devices made long-press never fire
    // ("на телефоне зажимаешь голосовуху — а появляется уведа
    // 'зажмите чтобы записать'"). With a non-interactive child the
    // GestureDetector owns the gesture cleanly.
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isKruzhokMode = _voiceModeIsKruzhok;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // Tap toggles the mode (no recording yet).
        HapticFeedback.selectionClick();
        _updateChatState(() {
          _voiceModeIsKruzhok = !_voiceModeIsKruzhok;
        });
      },
      onLongPressStart: (details) {
        if (_voiceModeIsKruzhok) {
          // Kruzhok mode: open the video-note recorder. Hold-to-
          // record happens inside the recorder UI itself.
          HapticFeedback.mediumImpact();
          unawaited(_pickVideoNote());
        } else {
          _handleRecordingLongPressStart(details);
        }
      },
      // C3a/V1: move/release голосовой записи ведёт персистентный Listener
      // над композером (см. _buildMessageInputArea), а не этот recognizer —
      // он размонтируется при появлении recording-бара.
      // User-reported on Samsung: «зажатием не записывается, появляется
      // только облачко 'зажмите для голосового' и всё». На ПК
      // мышью работало, на телефоне — нет.
      //
      // Корень: Material `Tooltip` на Android по умолчанию сам
      // открывается на long-press через свой собственный
      // LongPressGestureRecognizer. В gesture arena он конкурирует
      // с нашим GestureDetector — и часто выигрывает на чувствительных
      // экранах Samsung'а, поэтому `onLongPressStart` никогда не
      // вызывался: жест уходил Tooltip'у, наш recorder молчал.
      //
      // Заменили Tooltip на Semantics: TalkBack/screen-reader
      // прочитают тот же текст подсказки, но никаких gesture
      // recognizer-ов на child больше нет — long-press идёт нашему
      // GestureDetector'у напрямую.
      // FX1/C3a FR1: локальный Listener фиксирует id пальца, опущенного
      // именно НА микрофон — запись привяжется к нему, а не к чужому касанию
      // зоны ввода. Move/up уже-захваченного пальца ведёт композер-wide
      // Listener (он переживает ребилд композер→бар).
      child: Listener(
        onPointerDown: (event) => _micPointerId = event.pointer,
        onPointerUp: (event) {
          if (event.pointer == _micPointerId) {
            _micPointerId = null;
          }
        },
        onPointerCancel: (event) {
          if (event.pointer == _micPointerId) {
            _micPointerId = null;
          }
        },
        child: Semantics(
          button: true,
          label: isKruzhokMode ? 'Кружочек' : 'Голосовое сообщение',
          hint: isKruzhokMode
              ? 'Зажмите для кружочка, тап чтобы переключить на голосовое'
              : 'Зажмите для голосового, тап чтобы переключить на кружочек',
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              recordingState == ChatRecordingState.recording
                  ? Icons.lock_open_rounded
                  : (isKruzhokMode
                      ? Icons.videocam_outlined
                      : Icons.mic_none_rounded),
              color: scheme.onPrimary,
            ),
          ),
        ),
      ),
    );
  }

  String _attachmentSummaryLabel(List<XFile> files) {
    final count = files.length;
    final noun = count == 1
        ? 'вложение'
        : (count >= 2 && count <= 4 ? 'вложения' : 'вложений');
    return '$count $noun';
  }

  String _attachmentKindsLabel(List<XFile> files) {
    if (files.length == 1 && _isVideoNoteFile(files.first)) {
      return '1 кружок';
    }
    final counts = <_ChatAttachmentKind, int>{};
    for (final file in files) {
      final kind = _attachmentKindFromXFile(file);
      counts.update(kind, (value) => value + 1, ifAbsent: () => 1);
    }

    final segments = <String>[];
    void addSegment(_ChatAttachmentKind kind, String singular, String plural) {
      final count = counts[kind];
      if (count == null || count == 0) {
        return;
      }
      segments.add('$count ${count == 1 ? singular : plural}');
    }

    addSegment(_ChatAttachmentKind.image, 'фото', 'фото');
    addSegment(_ChatAttachmentKind.video, 'видео', 'видео');
    addSegment(_ChatAttachmentKind.audio, 'голосовое', 'голосовых');
    addSegment(_ChatAttachmentKind.other, 'файл', 'файла');
    return segments.join(' · ');
  }

  String _attachmentHintLabel(List<XFile> files) {
    if (files.length == 1 && _isVideoNoteFile(files.first)) {
      return 'Кружок уйдет отдельным сообщением и откроется как круглое видео.';
    }
    final kinds = files.map(_attachmentKindFromXFile).toSet();
    if (kinds.length > 1) {
      return 'Пакет уйдет одним сообщением. Проверьте подпись и состав перед отправкой.';
    }

    switch (kinds.first) {
      case _ChatAttachmentKind.image:
        return 'Фото будут ужаты перед отправкой, чтобы чат открывался быстрее.';
      case _ChatAttachmentKind.video:
        return 'Видео отправится как вложение. Можно добавить подпись к отправке.';
      case _ChatAttachmentKind.audio:
        return 'Голосовое отправится отдельным сообщением в текущий чат.';
      case _ChatAttachmentKind.other:
        return 'Файлы отправятся как документы без дополнительной обработки.';
    }
  }

  IconData _attachmentPanelIcon(List<XFile> files) {
    if (files.length == 1 && _isVideoNoteFile(files.first)) {
      return Icons.radio_button_checked_rounded;
    }
    final kinds = files.map(_attachmentKindFromXFile).toSet();
    if (kinds.length > 1) {
      return Icons.collections_outlined;
    }

    switch (kinds.first) {
      case _ChatAttachmentKind.image:
        return Icons.photo_library_outlined;
      case _ChatAttachmentKind.video:
        return Icons.videocam_outlined;
      case _ChatAttachmentKind.audio:
        return Icons.mic_none_outlined;
      case _ChatAttachmentKind.other:
        return Icons.insert_drive_file_outlined;
    }
  }

  String _attachmentPanelTitle(List<XFile> files) {
    if (files.length == 1 && _isVideoNoteFile(files.first)) {
      return 'Кружок перед отправкой';
    }
    final kinds = files.map(_attachmentKindFromXFile).toSet();
    if (kinds.length > 1) {
      return 'Пакет перед отправкой';
    }

    switch (kinds.first) {
      case _ChatAttachmentKind.image:
        return 'Фото перед отправкой';
      case _ChatAttachmentKind.video:
        return 'Видео перед отправкой';
      case _ChatAttachmentKind.audio:
        return 'Голосовое перед отправкой';
      case _ChatAttachmentKind.other:
        return 'Файлы перед отправкой';
    }
  }

  String? _groupSenderLabel(String? senderName, String senderId) {
    final normalizedName = senderName?.trim();
    if (normalizedName != null && normalizedName.isNotEmpty) {
      return normalizedName;
    }
    if (senderId == _currentUserId) {
      return 'Вы';
    }
    return 'Участник';
  }

  Widget _buildReplyComposerBar(ThemeData theme, ChatReplyReference reply) {
    final hasText = reply.text.trim().isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ответ: ${reply.senderName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasText ? reply.text : 'Сообщение без текста',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              _updateChatState(() {
                _selectedReply = null;
              });
            },
            tooltip: 'Отменить ответ',
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildEditComposerBar(ThemeData theme, _EditDraft draft) {
    final originalText = draft.originalText.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.secondary,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Редактируете сообщение',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.secondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  originalText.isNotEmpty
                      ? originalText
                      : (draft.hasAttachments
                          ? 'Сообщение с вложением'
                          : 'Сообщение без текста'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Отменить редактирование',
            onPressed: () {
              _messageController.clear();
              _updateChatState(() {
                _selectedEdit = null;
              });
            },
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildForwardComposerBar(ThemeData theme, _ForwardDraft draft) {
    final hasText = draft.text.trim().isNotEmpty;
    final attachmentCount = draft.attachments.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 42,
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiary,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Пересылаете: ${draft.senderName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.tertiary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasText ? draft.text : 'Сообщение без текста',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (attachmentCount > 0)
                  Text(
                    _attachmentCountLabel(attachmentCount),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Отменить пересылку',
            onPressed: () {
              _updateChatState(() {
                _selectedForward = null;
              });
            },
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildForwardBatchComposerBar(
    ThemeData theme,
    _ForwardBatchDraft draft,
  ) {
    final messageCount = draft.items.length;
    final attachmentCount = draft.items.fold<int>(
      0,
      (total, item) => total + item.attachments.length,
    );
    final previewText = draft.items.map((item) => item.text.trim()).firstWhere(
          (text) => text.isNotEmpty,
          orElse: () => 'Сообщения без текста',
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 42,
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiary,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  messageCount == 1
                      ? 'Пересылаете 1 сообщение'
                      : 'Пересылаете $messageCount сообщений',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.tertiary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  previewText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (attachmentCount > 0)
                  Text(
                    _attachmentCountLabel(attachmentCount),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Отменить пересылку',
            onPressed: () {
              _updateChatState(() {
                _selectedForwardBatch = null;
              });
            },
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  String _attachmentCountLabel(int count) {
    final noun = count == 1
        ? 'вложение'
        : (count >= 2 && count <= 4 ? 'вложения' : 'вложений');
    return '$count $noun';
  }
}
