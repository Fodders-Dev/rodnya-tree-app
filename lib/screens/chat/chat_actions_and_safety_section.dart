part of '../chat_screen.dart';

extension _ChatScreenActionsAndSafety on _ChatScreenState {
  bool get _isSelectionMode => _selectionController.isSelectionMode;

  bool get _isSearchMode => _searchController.isSearchMode;

  int get _selectedMessageCount => _selectionController.selectedMessageCount;

  Future<void> _openAttachmentPreviewGallery(
    List<_AttachmentPreviewItem> items, {
    int initialIndex = 0,
  }) async {
    if (items.isEmpty) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => _AttachmentViewerDialog(
        items: items,
        initialIndex: initialIndex.clamp(0, items.length - 1),
        onOpenExternally: _openAttachmentExternally,
        onDownload: _downloadAttachmentToDevice,
      ),
    );
  }

  void _showEmptyAttachmentCategorySnackBar(String text) {
    showAppSnackBar(context, text);
  }

  Future<void> _openChatMediaGallery() async {
    final mediaItems = _remoteAttachmentGalleryItems()
        .where((item) => item.isVisual)
        .toList(growable: false);
    if (mediaItems.isEmpty) {
      _showEmptyAttachmentCategorySnackBar('В этом чате пока нет медиа.');
      return;
    }

    await _openAttachmentPreviewGallery(mediaItems);
  }

  Future<void> _openChatFilesGallery() async {
    final fileItems = _remoteAttachmentGalleryItems()
        .where((item) => !item.isVisual)
        .toList(growable: false);
    if (fileItems.isEmpty) {
      _showEmptyAttachmentCategorySnackBar(
        'В этом чате пока нет документов и голосовых.',
      );
      return;
    }

    await _openAttachmentPreviewGallery(fileItems);
  }

  Future<void> _ensureCallRuntimeReady(String chatId) async {
    await _callCoordinator.ensureRuntimeReady();
    await _callCoordinator.resync(chatId: chatId);
  }

  Future<void> _startCall(
    CallMediaMode mediaMode, {
    List<String>? participantIds,
  }) async {
    final chatId = _chatId;
    if (chatId == null || chatId.isEmpty) {
      return;
    }
    try {
      await _callCoordinator.startCall(
        chatId: chatId,
        mediaMode: mediaMode,
        participantIds: participantIds,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(
        context,
        humanizeError(error, fallback: 'Не удалось начать звонок.'),
        isError: true,
      );
    }
  }

  Future<void> _startCallFromHeader(CallMediaMode mediaMode) async {
    // GP2/GP5 discovery: if a call is already live in this chat, JOIN it
    // instead of starting a duplicate. requestForegroundPresentation surfaces
    // the CallScreen with «Войти» (chat-membership-gated /join) even if the
    // user had minimized this call — so a late member joins in one more tap
    // rather than spawning a second room the others aren't in.
    final chatId = _chatId;
    if (chatId != null && chatId.isNotEmpty) {
      try {
        final active = await _callCoordinator.getActiveCall(chatId: chatId);
        if (!mounted) {
          return;
        }
        if (active != null && !active.state.isTerminal) {
          await _callCoordinator.requestForegroundPresentation(active);
          return;
        }
        // getActiveCall resolved to null/terminal → genuinely no live call in
        // this chat; fall through to start a fresh one.
      } catch (_) {
        if (!mounted) {
          return;
        }
        // A TRANSIENT failure while checking for a live call — do NOT silently
        // start a duplicate room (that 409s if a call is actually live). Offer
        // a retry instead.
        showAppSnackBar(
          context,
          'Не удалось проверить активный звонок. Попробуйте ещё раз.',
          isError: true,
        );
        return;
      }
    }

    if (!widget.isGroup) {
      await _startCall(mediaMode);
      return;
    }

    final candidates = _groupCallInviteCandidates();
    if (candidates.isEmpty) {
      showAppSnackBar(
        context,
        'В этом чате пока некого позвать на звонок.',
        isError: true,
      );
      return;
    }
    if (candidates.length == 1) {
      await _startCall(
        mediaMode,
        participantIds: <String>[candidates.single.userId],
      );
      return;
    }

    final selectedParticipantIds = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _GroupCallParticipantPicker(
        mediaMode: mediaMode,
        participants: candidates,
      ),
    );
    if (!mounted ||
        selectedParticipantIds == null ||
        selectedParticipantIds.isEmpty) {
      return;
    }
    await _startCall(
      mediaMode,
      participantIds: selectedParticipantIds,
    );
  }

  List<ChatParticipantSummary> _groupCallInviteCandidates() {
    final details = _chatDetails;
    final currentUserId = _currentUserId?.trim();
    if (details == null || currentUserId == null || currentUserId.isEmpty) {
      return const <ChatParticipantSummary>[];
    }
    final participantsById = <String, ChatParticipantSummary>{
      for (final participant in details.participants)
        if (participant.userId.trim().isNotEmpty)
          participant.userId.trim(): participant,
    };

    final ids = details.participantIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty && id != currentUserId)
        .toSet()
        .toList(growable: false);
    return ids
        .map(
          (id) =>
              participantsById[id] ??
              ChatParticipantSummary(
                userId: id,
                displayName: _participantLabelForUserId(id),
              ),
        )
        .toList(growable: false);
  }

  void _exitSelectionMode() {
    _selectionController.clear();
  }

  void _selectRemoteMessage(ChatMessage message) {
    if (_isSearchMode) {
      _closeSearch();
    }
    _updateChatState(() {
      _selectedEdit = null;
      _selectedReply = null;
      _selectedForward = null;
      _selectedForwardBatch = null;
    });
    _selectionController.selectRemote(message.id);
  }

  void _selectOutgoingMessage(_OutgoingMessage message) {
    if (_isSearchMode) {
      _closeSearch();
    }
    _updateChatState(() {
      _selectedEdit = null;
      _selectedReply = null;
      _selectedForward = null;
      _selectedForwardBatch = null;
    });
    _selectionController.selectOutgoing(message.localId);
  }

  void _toggleRemoteMessageSelection(ChatMessage message) {
    _selectionController.toggleRemote(message.id);
  }

  void _toggleOutgoingMessageSelection(_OutgoingMessage message) {
    _selectionController.toggleOutgoing(message.localId);
  }

  List<_SelectedMessageEntry> _selectedMessagesSnapshot() {
    final selectedMessages = <_SelectedMessageEntry>[
      ..._latestRemoteMessages
          .where((message) => _selectionController.isRemoteSelected(message.id))
          .map(
            (message) => _SelectedMessageEntry.remote(
              message: message,
              displayName: _senderDisplayNameForMessage(
                senderId: message.senderId,
                senderName: message.senderName,
              ),
            ),
          ),
      ..._optimisticMessages
          .where((message) =>
              _selectionController.isOutgoingSelected(message.localId))
          .map(
            (message) => _SelectedMessageEntry.outgoing(
              message: message,
              displayName: _senderDisplayNameForMessage(
                senderId: message.senderId,
                senderName: null,
              ),
              normalizedAttachments: _normalizedOutgoingAttachments(message),
            ),
          ),
    ];
    selectedMessages.sort(
      (left, right) => left.timestamp.compareTo(right.timestamp),
    );
    return selectedMessages;
  }

  String _senderDisplayNameForMessage({
    required String senderId,
    required String? senderName,
  }) {
    final normalizedSenderName = senderName?.trim();
    if (normalizedSenderName != null && normalizedSenderName.isNotEmpty) {
      return normalizedSenderName;
    }
    return _participantLabelForUserId(senderId);
  }

  List<ChatAttachment> _normalizedOutgoingAttachments(
      _OutgoingMessage message) {
    if (message.forwardedAttachments.isNotEmpty) {
      return List<ChatAttachment>.from(message.forwardedAttachments);
    }
    return message.attachments
        .map(
          (file) => ChatAttachment(
            type: _attachmentTypeForDraft(file),
            url: file.path,
            mimeType: file.mimeType,
            fileName: file.name,
          ),
        )
        .toList();
  }

  String _selectedMessagesTranscript(List<_SelectedMessageEntry> messages) {
    final formatter = DateFormat('dd.MM.yyyy H:mm', 'ru');
    return messages.map((message) {
      final body = message.text.trim().isNotEmpty
          ? message.text.trim()
          : _transcriptAttachmentLabel(message.attachments);
      return '[${formatter.format(toLocalForDisplay(message.timestamp))}] ${message.displayName}: $body';
    }).join('\n');
  }

  String _transcriptAttachmentLabel(List<ChatAttachment> attachments) {
    if (attachments.isEmpty) {
      return 'Сообщение';
    }

    final counts = <ChatAttachmentType, int>{};
    for (final attachment in attachments) {
      counts.update(attachment.type, (value) => value + 1, ifAbsent: () => 1);
    }

    final labels = <String>[];
    void addLabel(ChatAttachmentType type, String singular, String plural) {
      final count = counts[type];
      if (count == null || count == 0) {
        return;
      }
      labels.add('$count ${count == 1 ? singular : plural}');
    }

    addLabel(ChatAttachmentType.image, 'фото', 'фото');
    addLabel(ChatAttachmentType.video, 'видео', 'видео');
    addLabel(ChatAttachmentType.audio, 'голосовое', 'голосовых');
    addLabel(ChatAttachmentType.file, 'файл', 'файлов');
    return '[вложение: ${labels.join(', ')}]';
  }

  Future<void> _copySelectedMessages() async {
    final selectedMessages = _selectedMessagesSnapshot();
    if (selectedMessages.isEmpty) {
      return;
    }

    await Clipboard.setData(
      ClipboardData(text: _selectedMessagesTranscript(selectedMessages)),
    );
    if (!mounted) {
      return;
    }
    _exitSelectionMode();
    showAppSnackBar(
      context,
      selectedMessages.length == 1
          ? 'Сообщение скопировано'
          : 'Скопировано ${selectedMessages.length} сообщений',
    );
  }

  Future<void> _forwardSelectedMessages() async {
    final selectedMessages = _selectedMessagesSnapshot();
    if (selectedMessages.isEmpty) {
      return;
    }

    _updateChatState(() {
      _selectedReply = null;
      _selectedEdit = null;
      _selectedForward = null;
      _selectedForwardBatch = _ForwardBatchDraft(
        items: selectedMessages
            .map(
              (message) => _ForwardDraft(
                senderName: message.displayName,
                text: message.text,
                attachments: message.attachments,
              ),
            )
            .toList(),
      );
    });
    _selectionController.clear();
  }

  Future<void> _deleteSelectedMessages() async {
    final selectedMessages = _selectedMessagesSnapshot();
    if (selectedMessages.isEmpty) {
      return;
    }
    final currentUserId = _currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      return;
    }
    final hasForbiddenMessages = selectedMessages.any(
      (message) => !message.canDelete(currentUserId),
    );
    if (hasForbiddenMessages) {
      showAppSnackBar(
        context,
        'Пока можно удалять только свои сообщения и локальную очередь.',
        isError: true,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          selectedMessages.length == 1
              ? 'Удалить сообщение'
              : 'Удалить ${selectedMessages.length} сообщений',
        ),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }

    final chatId = _chatId;
    if (chatId == null || chatId.isEmpty) {
      return;
    }

    final outgoingIdsToRemove = <String>{};
    var failedCount = 0;
    for (final message in selectedMessages) {
      if (message.remoteMessageId != null) {
        try {
          await _chatService.deleteChatMessage(
            chatId: chatId,
            messageId: message.remoteMessageId!,
          );
        } catch (_) {
          failedCount += 1;
        }
        continue;
      }
      if (message.outgoingLocalId != null) {
        outgoingIdsToRemove.add(message.outgoingLocalId!);
      }
    }

    if (!mounted) {
      return;
    }
    for (final outgoingId in outgoingIdsToRemove) {
      await _sendQueue.remove(chatId, outgoingId);
    }
    _selectionController.clear();
    if (failedCount > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            failedCount == 1
                ? 'Не удалось удалить сообщение.'
                : 'Не удалось удалить часть сообщений ($failedCount).',
          ),
        ),
      );
    }
  }

  Future<void> _openChatInfo() async {
    final details = _chatDetails;
    final currentUserId = _currentUserId;
    if (details == null || currentUserId == null || currentUserId.isEmpty) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ChatInfoSheet(
        initialDetails: details,
        currentUserId: currentUserId,
        // Снапшот присутствия на момент открытия — строки участников
        // показывают «в сети»/«был(а) …» (шит и так работает по
        // снапшоту details, live-обновления внутри шита не нужны).
        onlineUserIds: Set<String>.of(_onlineUserIds),
        lastSeenByUserId: Map<String, DateTime>.of(_peerLastSeenAt),
        hasPinnedMessage: _pinnedMessage != null,
        initialNotificationLevel: _notificationSettings.level,
        initialAutoDeleteOption: _autoDeleteSettings.option,
        onRename: (title) async {
          final updatedDetails = await _chatService.renameGroupChat(
            chatId: details.chatId,
            title: title,
          );
          if (!mounted) {
            return updatedDetails;
          }
          _updateChatState(() {
            _chatDetails = updatedDetails;
            _resolvedTitle = updatedDetails.displayTitleFor(_currentUserId);
          });
          return updatedDetails;
        },
        onUpdatePhoto: (photo) async {
          final updatedDetails = await _chatService.updateGroupChatPhoto(
            chatId: details.chatId,
            photo: photo,
          );
          unawaited(
              _chatDetailsCache?.write(updatedDetails.chatId, updatedDetails));
          if (!mounted) {
            return updatedDetails;
          }
          _updateChatState(() {
            _chatDetails = updatedDetails;
            _resolvedTitle = updatedDetails.displayTitleFor(_currentUserId);
          });
          return updatedDetails;
        },
        onAddParticipants: (participantIds) async {
          final updatedDetails = await _chatService.addGroupParticipants(
            chatId: details.chatId,
            participantIds: participantIds,
          );
          if (!mounted) {
            return updatedDetails;
          }
          _updateChatState(() {
            _chatDetails = updatedDetails;
          });
          return updatedDetails;
        },
        onRemoveParticipant: (participantId) async {
          final updatedDetails = await _chatService.removeGroupParticipant(
            chatId: details.chatId,
            participantId: participantId,
          );
          if (!mounted) {
            return updatedDetails;
          }
          _updateChatState(() {
            _chatDetails = updatedDetails;
          });
          return updatedDetails;
        },
        onOpenDirectChat: (participant) {
          Navigator.of(context).pop();
          unawaited(_openDirectChatForParticipant(participant));
        },
        onLeaveGroup: () async {
          // G2: выходим из группы. После выхода чат недоступен — закрываем
          // шит и уходим к списку чатов; realtime-событие уберёт его из
          // списка у нас и обновит состав у остальных. Navigator/роутер
          // захватываем до await (контекст после него использовать нельзя).
          final navigator = Navigator.of(context);
          final router = GoRouter.of(context);
          await _chatService.leaveGroup(details.chatId);
          if (!mounted) {
            return;
          }
          navigator.pop(); // закрыть шит
          router.go('/chats');
        },
        onDeleteChat: ({required bool forAll}) async {
          final navigator = Navigator.of(context);
          final router = GoRouter.of(context);
          await _chatService.deleteChat(details.chatId, forAll: forAll);
          if (!mounted) {
            return;
          }
          navigator.pop();
          router.go('/chats');
        },
        onOpenSearch: () {
          Navigator.of(context).pop();
          _openSearch();
        },
        onOpenPinnedMessage: _pinnedMessage == null
            ? null
            : () {
                Navigator.of(context).pop();
                unawaited(_focusPinnedMessage());
              },
        onOpenTree: details.treeId == null || details.treeId!.trim().isEmpty
            ? null
            : () {
                Navigator.of(context).pop();
                context.push('/tree/view/${details.treeId}');
              },
        onOpenRelatives:
            details.treeId == null || details.treeId!.trim().isEmpty
                ? null
                : () {
                    Navigator.of(context).pop();
                    context.go('/relatives');
                  },
        onOpenMedia: () {
          Navigator.of(context).pop();
          unawaited(_openChatMediaGallery());
        },
        onOpenFiles: () {
          Navigator.of(context).pop();
          unawaited(_openChatFilesGallery());
        },
        onNotificationLevelChanged: _updateNotificationLevel,
        onAutoDeleteChanged: _updateAutoDeleteOption,
      ),
    );
  }

  bool _isWideLayout(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1180;

  Future<void> _copyMessageText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: trimmed));
    if (!mounted) {
      return;
    }
    showAppSnackBar(context, 'Текст сообщения скопирован');
  }

  bool get _isCurrentDirectChat =>
      _chatDetails?.isDirect ?? widget.chatType == 'direct';

  bool get _canStartCallInChat {
    final details = _chatDetails;
    if (details != null) {
      return (details.isDirect || details.isGroup) &&
          details.participantIds.length >= 2;
    }
    return widget.chatType == 'direct';
  }

  String? get _currentDirectPeerUserId {
    if (!_isCurrentDirectChat) {
      return null;
    }
    final participantIds = _otherParticipantIds(_chatDetails);
    if (participantIds.isEmpty) {
      final otherUserId = widget.otherUserId?.trim();
      return otherUserId == null || otherUserId.isEmpty ? null : otherUserId;
    }
    return participantIds.first;
  }

  String _messageActionErrorText(Object error, String fallback) {
    if (error is CustomApiException && error.message.trim().isNotEmpty) {
      return error.message.trim();
    }
    if (error is UnsupportedError && error.message?.trim().isNotEmpty == true) {
      return error.message!.trim();
    }
    return fallback;
  }

  Future<_SafetyActionDraft?> _pickSafetyActionDraft({
    required String title,
    required String subtitle,
    required List<_SafetyReasonChoice> choices,
  }) {
    return showModalBottomSheet<_SafetyActionDraft>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final detailsController = TextEditingController();
        _SafetyReasonChoice? selectedChoice = choices.first;

        return StatefulBuilder(
          builder: (context, setModalState) => SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 8,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: choices
                        .map(
                          (choice) => ChoiceChip(
                            label: Text(choice.label),
                            selected: selectedChoice == choice,
                            onSelected: (_) {
                              setModalState(() {
                                selectedChoice = choice;
                              });
                            },
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: detailsController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Комментарий для модерации',
                      hintText:
                          'Необязательно, но помогает быстрее разобраться',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Отмена'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: selectedChoice == null
                            ? null
                            : () => Navigator.of(context).pop(
                                  _SafetyActionDraft(
                                    reason: selectedChoice!.reason,
                                    details: detailsController.text.trim(),
                                  ),
                                ),
                        child: const Text('Продолжить'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _reportRemoteMessage(ChatMessage message) async {
    final safetyService = _safetyService;
    if (safetyService == null) {
      return;
    }

    final senderLabel = _participantLabelForUserId(message.senderId);
    final draft = await _pickSafetyActionDraft(
      title: 'Пожаловаться на сообщение',
      subtitle:
          'Жалоба уйдёт в модерацию. Мы передадим текст сообщения, автора и контекст чата.',
      choices: const <_SafetyReasonChoice>[
        _SafetyReasonChoice(reason: 'spam', label: 'Спам'),
        _SafetyReasonChoice(reason: 'abuse', label: 'Оскорбление'),
        _SafetyReasonChoice(reason: 'adult', label: 'Нежелательный контент'),
        _SafetyReasonChoice(reason: 'fraud', label: 'Мошенничество'),
        _SafetyReasonChoice(reason: 'other', label: 'Другое'),
      ],
    );
    if (draft == null) {
      return;
    }

    try {
      await safetyService.reportTarget(
        targetType: 'message',
        targetId: message.id,
        reason: draft.reason,
        details: draft.details.isEmpty ? null : draft.details,
        metadata: <String, dynamic>{
          'chatId': message.chatId,
          'senderId': message.senderId,
          'senderName': senderLabel,
          'messagePreview': message.text.trim(),
        },
      );
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, 'Жалоба на сообщение $senderLabel отправлена.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(
        context,
        _messageActionErrorText(error, 'Не удалось отправить жалобу.'),
        isError: true,
      );
    }
  }

  Future<void> _blockUserFromMessage(ChatMessage message) async {
    final safetyService = _safetyService;
    final currentUserId = _currentUserId;
    if (safetyService == null ||
        currentUserId == null ||
        currentUserId.isEmpty ||
        message.senderId.trim().isEmpty ||
        message.senderId == currentUserId) {
      return;
    }

    final senderLabel = _participantLabelForUserId(message.senderId);
    final draft = await _pickSafetyActionDraft(
      title: 'Заблокировать пользователя',
      subtitle:
          'После блокировки личный чат станет только для чтения. Управлять списком блокировок можно в настройках.',
      choices: const <_SafetyReasonChoice>[
        _SafetyReasonChoice(reason: 'harassment', label: 'Навязчивость'),
        _SafetyReasonChoice(reason: 'spam', label: 'Спам'),
        _SafetyReasonChoice(reason: 'privacy', label: 'Нарушение границ'),
        _SafetyReasonChoice(reason: 'other', label: 'Другое'),
      ],
    );
    if (draft == null) {
      return;
    }

    try {
      await safetyService.blockUser(
        userId: message.senderId,
        reason: draft.reason,
        metadata: <String, dynamic>{
          'chatId': message.chatId,
          'source': 'chat_message',
        },
      );
      if (!mounted) {
        return;
      }
      _updateChatState(() {
        _selectedEdit = null;
        _selectedReply = null;
        _selectedForward = null;
        _selectedForwardBatch = null;
        _isDirectChatBlocked = _isCurrentDirectChat;
        _directChatBlockedLabel = senderLabel;
      });
      _attachmentsController.clear();
      showAppSnackBar(
        context,
        '$senderLabel заблокирован. Отправка в этом личном чате отключена.',
        action: SnackBarAction(
          label: 'Блокировки',
          onPressed: () => context.push('/profile/blocks'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(
        context,
        _messageActionErrorText(
            error, 'Не удалось заблокировать пользователя.'),
        isError: true,
      );
    }
  }

  Widget _buildBlockedComposerNotice() {
    final theme = Theme.of(context);
    final label = _directChatBlockedLabel?.trim();
    final title = label != null && label.isNotEmpty
        ? '$label в списке блокировок'
        : 'Собеседник в списке блокировок';

    return Padding(
      padding: EdgeInsets.fromLTRB(
        8,
        4,
        8,
        MediaQuery.of(context).padding.bottom + 8,
      ),
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        borderRadius: BorderRadius.circular(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.block_rounded,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Новые сообщения и медиа сейчас недоступны.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => context.push('/profile/blocks'),
                  icon: const Icon(Icons.shield_outlined),
                  label: const Text('Список блокировок'),
                ),
                TextButton.icon(
                  onPressed: () => context.push('/support'),
                  icon: const Icon(Icons.support_agent_outlined),
                  label: const Text('Поддержка'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRemoteMessageActions(
    ChatMessage message, {
    Offset? anchorPosition,
  }) async {
    final canCopy = message.text.trim().isNotEmpty;
    final isOwnMessage = message.senderId == _currentUserId;
    final isPinned = _pinnedMessage?.messageId == message.id;
    final supportsSafetyActions = _safetyService != null;
    final canOpenDirectChat =
        widget.isGroup && !isOwnMessage && message.senderId.trim().isNotEmpty;
    final canReport = supportsSafetyActions && !isOwnMessage;
    final canBlock = canReport &&
        _isCurrentDirectChat &&
        (_currentDirectPeerUserId == null ||
            _currentDirectPeerUserId == message.senderId);
    final useDesktopMenu =
        _useDesktopMessageContextMenu() && anchorPosition != null;
    _MessageSheetSelection? selection;
    if (useDesktopMenu) {
      selection = await _showDesktopMessagePopover<_MessageSheetSelection>(
        anchorPosition: anchorPosition,
        reactions: _ChatScreenState._quickReactionEmoji,
        reactionValueBuilder: (emoji) => _MessageSheetSelection(
          action: _MessageAction.react,
          emoji: emoji,
        ),
        actions: <_ContextMenuActionItem<_MessageSheetSelection>>[
          const _ContextMenuActionItem<_MessageSheetSelection>(
            label: 'Ответить',
            icon: Icons.reply_rounded,
            value: _MessageSheetSelection(action: _MessageAction.reply),
          ),
          const _ContextMenuActionItem<_MessageSheetSelection>(
            label: 'Переслать',
            icon: Icons.forward_rounded,
            value: _MessageSheetSelection(action: _MessageAction.forward),
          ),
          const _ContextMenuActionItem<_MessageSheetSelection>(
            label: 'Выбрать',
            icon: Icons.checklist_rounded,
            value: _MessageSheetSelection(action: _MessageAction.select),
          ),
          if (canOpenDirectChat)
            const _ContextMenuActionItem<_MessageSheetSelection>(
              label: 'Написать в личку',
              icon: Icons.chat_bubble_outline_rounded,
              value: _MessageSheetSelection(action: _MessageAction.openDirect),
            ),
          _ContextMenuActionItem<_MessageSheetSelection>(
            label: isPinned ? 'Открепить' : 'Закрепить',
            icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
            value: const _MessageSheetSelection(
              action: _MessageAction.pin,
            ),
          ),
          if (isOwnMessage)
            const _ContextMenuActionItem<_MessageSheetSelection>(
              label: 'Редактировать',
              icon: Icons.edit_outlined,
              value: _MessageSheetSelection(action: _MessageAction.edit),
            ),
          if (canCopy)
            const _ContextMenuActionItem<_MessageSheetSelection>(
              label: 'Копировать текст',
              icon: Icons.copy_rounded,
              value: _MessageSheetSelection(action: _MessageAction.copy),
            ),
          if (canReport)
            const _ContextMenuActionItem<_MessageSheetSelection>(
              label: 'Пожаловаться',
              icon: Icons.flag_outlined,
              value: _MessageSheetSelection(action: _MessageAction.report),
              isDestructive: true,
            ),
          if (canBlock)
            const _ContextMenuActionItem<_MessageSheetSelection>(
              label: 'Заблокировать',
              icon: Icons.block_outlined,
              value: _MessageSheetSelection(action: _MessageAction.block),
              isDestructive: true,
            ),
          if (isOwnMessage)
            const _ContextMenuActionItem<_MessageSheetSelection>(
              label: 'Удалить сообщение',
              icon: Icons.delete_outline_rounded,
              value: _MessageSheetSelection(action: _MessageAction.delete),
              isDestructive: true,
            ),
        ],
      );
    } else {
      selection = await showBlurredActionsSheet<_MessageSheetSelection>(
        context: context,
        builder: (context) => SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Быстрые реакции',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _ChatScreenState._quickReactionEmoji
                      .map(
                        (emoji) => ChoiceChip(
                          label: Text(emoji),
                          selected: _hasCurrentUserReaction(message, emoji),
                          onSelected: (_) => Navigator.of(context).pop(
                            _MessageSheetSelection(
                              action: _MessageAction.react,
                              emoji: emoji,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text('Ответить'),
                onTap: () => Navigator.of(context).pop(
                  const _MessageSheetSelection(
                    action: _MessageAction.reply,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.forward_rounded),
                title: const Text('Переслать'),
                onTap: () => Navigator.of(context).pop(
                  const _MessageSheetSelection(
                    action: _MessageAction.forward,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.checklist_rounded),
                title: const Text('Выбрать'),
                onTap: () => Navigator.of(context).pop(
                  const _MessageSheetSelection(
                    action: _MessageAction.select,
                  ),
                ),
              ),
              if (canOpenDirectChat)
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline_rounded),
                  title: const Text('Написать в личку'),
                  onTap: () => Navigator.of(context).pop(
                    const _MessageSheetSelection(
                      action: _MessageAction.openDirect,
                    ),
                  ),
                ),
              ListTile(
                leading: Icon(
                  isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                ),
                title: Text(isPinned ? 'Открепить' : 'Закрепить'),
                onTap: () => Navigator.of(context).pop(
                  const _MessageSheetSelection(action: _MessageAction.pin),
                ),
              ),
              if (isOwnMessage)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Редактировать'),
                  onTap: () => Navigator.of(context).pop(
                    const _MessageSheetSelection(
                      action: _MessageAction.edit,
                    ),
                  ),
                ),
              if (canCopy)
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('Копировать текст'),
                  onTap: () => Navigator.of(context).pop(
                    const _MessageSheetSelection(
                      action: _MessageAction.copy,
                    ),
                  ),
                ),
              if (canReport)
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('Пожаловаться'),
                  onTap: () => Navigator.of(context).pop(
                    const _MessageSheetSelection(
                      action: _MessageAction.report,
                    ),
                  ),
                ),
              if (canBlock)
                ListTile(
                  leading: const Icon(Icons.block_outlined),
                  title: const Text('Заблокировать'),
                  onTap: () => Navigator.of(context).pop(
                    const _MessageSheetSelection(
                      action: _MessageAction.block,
                    ),
                  ),
                ),
              if (isOwnMessage)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Удалить сообщение'),
                  onTap: () => Navigator.of(context).pop(
                    const _MessageSheetSelection(
                      action: _MessageAction.delete,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    if (!mounted || selection == null) {
      return;
    }
    if (selection.action == _MessageAction.react && selection.emoji != null) {
      await _toggleReactionForMessage(message, selection.emoji!);
      return;
    }
    if (selection.action == _MessageAction.reply) {
      _selectReplyFromMessage(message);
      return;
    }
    if (selection.action == _MessageAction.forward) {
      _selectForwardFromMessage(message);
      return;
    }
    if (selection.action == _MessageAction.select) {
      _selectRemoteMessage(message);
      return;
    }
    if (selection.action == _MessageAction.openDirect) {
      await _openDirectChatForMessage(message);
      return;
    }
    if (selection.action == _MessageAction.pin) {
      if (isPinned) {
        await _clearPinnedMessage();
      } else {
        await _pinRemoteMessage(message);
      }
      return;
    }
    if (selection.action == _MessageAction.edit) {
      _selectEditMessage(message);
      return;
    }
    if (selection.action == _MessageAction.copy) {
      await _copyMessageText(message.text);
      return;
    }
    if (selection.action == _MessageAction.report) {
      await _reportRemoteMessage(message);
      return;
    }
    if (selection.action == _MessageAction.block) {
      await _blockUserFromMessage(message);
      return;
    }
    if (selection.action == _MessageAction.delete) {
      await _deleteRemoteMessage(message);
    }
  }

  Future<void> _openOutgoingMessageActions(
    _OutgoingMessage message, {
    Offset? anchorPosition,
  }) async {
    final canCopy = message.text.trim().isNotEmpty;
    final useDesktopMenu =
        _useDesktopMessageContextMenu() && anchorPosition != null;
    _MessageAction? action;
    if (useDesktopMenu) {
      action = await _showDesktopMessagePopover<_MessageAction>(
        anchorPosition: anchorPosition,
        actions: <_ContextMenuActionItem<_MessageAction>>[
          const _ContextMenuActionItem<_MessageAction>(
            label: 'Ответить',
            icon: Icons.reply_rounded,
            value: _MessageAction.reply,
          ),
          const _ContextMenuActionItem<_MessageAction>(
            label: 'Переслать',
            icon: Icons.forward_rounded,
            value: _MessageAction.forward,
          ),
          const _ContextMenuActionItem<_MessageAction>(
            label: 'Выбрать',
            icon: Icons.checklist_rounded,
            value: _MessageAction.select,
          ),
          if (canCopy)
            const _ContextMenuActionItem<_MessageAction>(
              label: 'Копировать текст',
              icon: Icons.copy_rounded,
              value: _MessageAction.copy,
            ),
          if (message.status == _OutgoingMessageStatus.failed)
            const _ContextMenuActionItem<_MessageAction>(
              label: 'Повторить отправку',
              icon: Icons.refresh_rounded,
              value: _MessageAction.retry,
            ),
          if (message.status != _OutgoingMessageStatus.sent)
            const _ContextMenuActionItem<_MessageAction>(
              label: 'Убрать из очереди',
              icon: Icons.delete_outline_rounded,
              value: _MessageAction.delete,
              isDestructive: true,
            ),
        ],
      );
    } else {
      action = await showBlurredActionsSheet<_MessageAction>(
        context: context,
        builder: (context) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('Ответить'),
              onTap: () => Navigator.of(context).pop(_MessageAction.reply),
            ),
            ListTile(
              leading: const Icon(Icons.forward_rounded),
              title: const Text('Переслать'),
              onTap: () => Navigator.of(context).pop(_MessageAction.forward),
            ),
            ListTile(
              leading: const Icon(Icons.checklist_rounded),
              title: const Text('Выбрать'),
              onTap: () => Navigator.of(context).pop(_MessageAction.select),
            ),
            if (canCopy)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Копировать текст'),
                onTap: () => Navigator.of(context).pop(_MessageAction.copy),
              ),
            if (message.status == _OutgoingMessageStatus.failed)
              ListTile(
                leading: const Icon(Icons.refresh_rounded),
                title: const Text('Повторить отправку'),
                onTap: () => Navigator.of(context).pop(_MessageAction.retry),
              ),
            if (message.status != _OutgoingMessageStatus.sent)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Убрать из очереди'),
                onTap: () => Navigator.of(context).pop(_MessageAction.delete),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    }
    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case _MessageAction.react:
        return;
      case _MessageAction.reply:
        _selectReplyFromOutgoingMessage(message);
        return;
      case _MessageAction.forward:
        _selectForwardFromOutgoingMessage(message);
        return;
      case _MessageAction.select:
        _selectOutgoingMessage(message);
        return;
      case _MessageAction.pin:
        return;
      case _MessageAction.edit:
        return;
      case _MessageAction.copy:
        await _copyMessageText(message.text);
        return;
      case _MessageAction.openDirect:
        return;
      case _MessageAction.report:
        return;
      case _MessageAction.block:
        return;
      case _MessageAction.retry:
        await _sendQueue.retry(message.chatId, message.localId);
        return;
      case _MessageAction.delete:
        await _sendQueue.remove(message.chatId, message.localId);
        return;
    }
  }

  void _selectReplyFromMessage(ChatMessage message) {
    final senderName =
        _groupSenderLabel(message.senderName, message.senderId) ??
            (message.senderId == _currentUserId ? 'Вы' : 'Участник');
    _updateChatState(() {
      _selectedEdit = null;
      _selectedForward = null;
      _selectedForwardBatch = null;
      _selectedReply = ChatReplyReference(
        messageId: message.id,
        senderId: message.senderId,
        senderName: senderName,
        text: message.text,
      );
    });
  }

  void _selectReplyFromOutgoingMessage(_OutgoingMessage message) {
    final senderName = message.senderId == _currentUserId ? 'Вы' : 'Участник';
    _updateChatState(() {
      _selectedEdit = null;
      _selectedForward = null;
      _selectedForwardBatch = null;
      _selectedReply = ChatReplyReference(
        messageId: message.localId,
        senderId: message.senderId,
        senderName: senderName,
        text: message.text,
      );
    });
  }

  void _selectForwardFromMessage(ChatMessage message) {
    final senderName =
        _groupSenderLabel(message.senderName, message.senderId) ??
            (message.senderId == _currentUserId ? 'Вы' : 'Участник');
    _updateChatState(() {
      _selectedEdit = null;
      _selectedReply = null;
      _selectedForwardBatch = null;
      _selectedForward = _ForwardDraft(
        senderName: senderName,
        text: message.text,
        attachments: message.attachments,
      );
    });
  }

  void _selectForwardFromOutgoingMessage(_OutgoingMessage message) {
    final senderName = message.senderId == _currentUserId ? 'Вы' : 'Участник';
    final forwardedAttachments = message.forwardedAttachments.isNotEmpty
        ? message.forwardedAttachments
        : message.attachments
            .map(
              (file) => ChatAttachment(
                type: _attachmentTypeForDraft(file),
                url: file.path,
                mimeType: file.mimeType,
                fileName: file.name,
              ),
            )
            .toList();
    _updateChatState(() {
      _selectedEdit = null;
      _selectedReply = null;
      _selectedForwardBatch = null;
      _selectedForward = _ForwardDraft(
        senderName: senderName,
        text: message.text,
        attachments: forwardedAttachments,
      );
    });
  }

  void _selectEditMessage(ChatMessage message) {
    _messageController.value = TextEditingValue(
      text: message.text,
      selection: TextSelection.collapsed(offset: message.text.length),
    );
    _updateChatState(() {
      _selectedReply = null;
      _selectedForward = null;
      _selectedForwardBatch = null;
      _selectedEdit = _EditDraft(
        messageId: message.id,
        originalText: message.text,
        hasAttachments: message.attachments.isNotEmpty,
      );
    });
    _attachmentsController.clear();
  }

  bool _useDesktopMessageContextMenu() {
    final platform = Theme.of(context).platform;
    final isDesktopPlatform = kIsWeb ||
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux;
    return isDesktopPlatform && MediaQuery.of(context).size.width >= 720;
  }

  Future<T?> _showDesktopMessagePopover<T>({
    required Offset anchorPosition,
    required List<_ContextMenuActionItem<T>> actions,
    List<String> reactions = const <String>[],
    T Function(String emoji)? reactionValueBuilder,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'message-context-menu',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (dialogContext, _, __) {
        final screenSize = MediaQuery.of(dialogContext).size;
        const popupWidth = 320.0;
        final reactionBarHeight = reactions.isEmpty ? 0.0 : 58.0;
        final menuHeight = 16.0 + actions.length * 46.0;
        final totalHeight =
            reactionBarHeight + (reactionBarHeight == 0 ? 0 : 8) + menuHeight;
        final openBelow =
            anchorPosition.dy + totalHeight + 12 <= screenSize.height;
        final resolvedLeft = (anchorPosition.dx - popupWidth / 2)
            .clamp(12.0, screenSize.width - popupWidth - 12.0);
        final resolvedTop = (openBelow
                ? anchorPosition.dy + 10
                : anchorPosition.dy - totalHeight - 10)
            .clamp(12.0, screenSize.height - totalHeight - 12.0);

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => Navigator.of(dialogContext).maybePop(),
              ),
            ),
            Positioned(
              left: resolvedLeft,
              top: resolvedTop,
              child: _DesktopMessageContextMenu<T>(
                reactions: reactions,
                actions: actions,
                onReactionSelected: reactionValueBuilder == null
                    ? null
                    : (emoji) => Navigator.of(dialogContext)
                        .pop(reactionValueBuilder(emoji)),
                onActionSelected: (value) {
                  Navigator.of(dialogContext).pop(value);
                },
              ),
            ),
          ],
        );
      },
      transitionBuilder: (context, animation, _, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curvedAnimation,
          child: ScaleTransition(
            scale: Tween<double>(
              begin: 0.96,
              end: 1,
            ).animate(curvedAnimation),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _openRemoteAttachmentPreview(
    ChatMessage message,
    List<ChatAttachment> attachments,
    ChatAttachment initialAttachment,
  ) async {
    final currentAttachmentIndex = attachments.indexWhere(
      (attachment) => _attachmentsMatch(attachment, initialAttachment),
    );
    final initialItemId =
        'remote:${message.id}:${currentAttachmentIndex < 0 ? 0 : currentAttachmentIndex}';
    final previewItems = _remoteAttachmentGalleryItems();
    if (previewItems.isEmpty) {
      return;
    }
    final initialIndex = previewItems.indexWhere(
      (item) => item.id == initialItemId,
    );
    await showDialog<void>(
      context: context,
      builder: (context) => _AttachmentViewerDialog(
        items: previewItems,
        initialIndex: initialIndex == -1 ? 0 : initialIndex,
        onOpenExternally: _openAttachmentExternally,
        onDownload: _downloadAttachmentToDevice,
      ),
    );
  }

  Future<void> _openLocalAttachmentPreview(
    List<XFile> files,
    XFile initialFile,
  ) async {
    final kind = _attachmentKindFromXFile(initialFile);
    if (kind == _ChatAttachmentKind.other) {
      await _openLocalAttachmentExternally(initialFile);
      return;
    }

    final previewItems = files
        .where((file) =>
            _attachmentKindFromXFile(file) != _ChatAttachmentKind.audio)
        .toList()
        .asMap()
        .entries
        .map(
          (entry) => _attachmentPreviewItemFromLocal(
            entry.value,
            id: 'local:${entry.key}:${entry.value.name}',
          ),
        )
        .toList();
    if (previewItems.isEmpty) {
      return;
    }
    final initialIndex = previewItems.indexWhere(
      (item) => item.displayName == _displayName(initialFile.name),
    );
    await showDialog<void>(
      context: context,
      builder: (context) => _AttachmentViewerDialog(
        items: previewItems,
        initialIndex: initialIndex == -1 ? 0 : initialIndex,
        onOpenExternally: _openAttachmentExternally,
        onDownload: _downloadAttachmentToDevice,
      ),
    );
  }

  List<_AttachmentPreviewItem> _remoteAttachmentGalleryItems() {
    final messages = List<ChatMessage>.from(_latestRemoteMessages)
      ..sort((left, right) => left.timestamp.compareTo(right.timestamp));
    final previewItems = <_AttachmentPreviewItem>[];
    for (final message in messages) {
      final senderLabel = _senderDisplayNameForMessage(
        senderId: message.senderId,
        senderName: message.senderName,
      );
      for (var index = 0; index < message.attachments.length; index++) {
        final attachment = message.attachments[index];
        final kind = _attachmentKindFromAttachment(attachment);
        if (kind == _ChatAttachmentKind.audio) {
          continue;
        }
        previewItems.add(
          _attachmentPreviewItemFromRemote(
            attachment,
            id: 'remote:${message.id}:$index',
            senderLabel: senderLabel,
            timestamp: message.timestamp,
            caption: message.text.trim(),
          ),
        );
      }
    }
    return previewItems;
  }

  _AttachmentPreviewItem _attachmentPreviewItemFromRemote(
    ChatAttachment attachment, {
    required String id,
    String? senderLabel,
    DateTime? timestamp,
    String? caption,
  }) {
    return _AttachmentPreviewItem.remote(
      id: id,
      kind: _attachmentKindFromAttachment(attachment),
      source: attachment.url,
      displayName: _displayName(attachment.fileName ?? attachment.url),
      thumbnailUrl: attachment.thumbnailUrl,
      senderLabel: senderLabel,
      timestamp: timestamp,
      caption: caption,
      isVideoNote: attachment.isVideoNote,
    );
  }

  _AttachmentPreviewItem _attachmentPreviewItemFromLocal(
    XFile file, {
    required String id,
  }) {
    return _AttachmentPreviewItem.local(
      id: id,
      kind: _attachmentKindFromXFile(file),
      file: file,
      displayName: _displayName(file.name),
      senderLabel: 'Вы',
      timestamp: DateTime.now(),
      caption: '',
      isVideoNote: _isVideoNoteFile(file),
    );
  }

  bool _attachmentsMatch(ChatAttachment left, ChatAttachment right) {
    return left.type == right.type &&
        left.url == right.url &&
        left.fileName == right.fileName &&
        left.thumbnailUrl == right.thumbnailUrl;
  }

  Future<void> _openAttachmentExternally(_AttachmentPreviewItem item) async {
    try {
      if (!item.isRemote && item.file != null) {
        await _openLocalAttachmentExternally(item.file!);
        return;
      }
      final source = item.source;
      if (source == null || source.trim().isEmpty) {
        return;
      }
      final uri = Uri.parse(source);
      await launchUrl(
        uri,
        mode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, 'Не удалось открыть вложение.', isError: true);
    }
  }

  Future<void> _openLocalAttachmentExternally(XFile file) async {
    try {
      if (kIsWeb && file.path.trim().isNotEmpty) {
        await launchUrl(
          Uri.parse(file.path),
          webOnlyWindowName: '_blank',
        );
        return;
      }
      await OpenFilex.open(file.path);
    } catch (_) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(
        context,
        'Не удалось открыть локальный файл.',
        isError: true,
      );
    }
  }

  Future<void> _downloadAttachmentToDevice(_AttachmentPreviewItem item) async {
    try {
      if (!item.isRemote ||
          item.source == null ||
          item.source!.trim().isEmpty) {
        await _openAttachmentExternally(item);
        return;
      }
      if (supportsChatAttachmentDownload) {
        await downloadChatAttachment(
          item.source!,
          suggestedFileName: item.displayName,
        );
      } else {
        await _openAttachmentExternally(item);
      }
      if (!mounted) {
        return;
      }
      showAppSnackBar(
        context,
        supportsChatAttachmentDownload
            ? 'Скачивание запущено'
            : 'Вложение открыто во внешнем приложении',
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, 'Не удалось сохранить вложение.', isError: true);
    }
  }

  Future<void> _deleteRemoteMessage(ChatMessage message) async {
    final chatId = _chatId;
    if (chatId == null || chatId.isEmpty) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить сообщение'),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }

    try {
      await _chatService.deleteChatMessage(
        chatId: chatId,
        messageId: message.id,
      );
      if (!mounted) {
        return;
      }
      if (_selectedEdit?.messageId == message.id) {
        _messageController.clear();
        _updateChatState(() {
          _selectedEdit = null;
        });
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      showAppSnackBar(context, 'Не удалось удалить сообщение.', isError: true);
    }
  }

  ChatAttachmentType _attachmentTypeForDraft(XFile file) {
    switch (_attachmentKindFromXFile(file)) {
      case _ChatAttachmentKind.image:
        return ChatAttachmentType.image;
      case _ChatAttachmentKind.video:
        return ChatAttachmentType.video;
      case _ChatAttachmentKind.audio:
        return ChatAttachmentType.audio;
      case _ChatAttachmentKind.other:
        return ChatAttachmentType.file;
    }
  }
}
