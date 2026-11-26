part of '../chat_screen.dart';

extension _ChatScreenMessageListSection on _ChatScreenState {
  String _pinnedPreviewLabel(ChatPinnedMessageSnapshot snapshot) {
    final text = snapshot.text.trim();
    if (text.isNotEmpty) {
      return text;
    }
    if (snapshot.attachmentCount > 0) {
      return _attachmentCountLabel(snapshot.attachmentCount);
    }
    return 'Сообщение без текста';
  }

  void _highlightPinnedMessage(String messageId) {
    _pinnedMessageHighlightTimer?.cancel();
    if (!mounted) {
      return;
    }
    _updateChatState(() {
      _highlightedPinnedMessageId = messageId;
    });
    _pinnedMessageHighlightTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || _highlightedPinnedMessageId != messageId) {
        return;
      }
      _updateChatState(() {
        _highlightedPinnedMessageId = null;
      });
    });
  }

  Future<void> _focusMessageById(String messageId) async {
    final normalizedMessageId = messageId.trim();
    if (normalizedMessageId.isEmpty) {
      return;
    }

    if (_isSearchMode) {
      _closeSearch();
    }

    final visibleContext =
        _remoteMessageKeys[normalizedMessageId]?.currentContext;
    if (visibleContext != null) {
      _highlightPinnedMessage(normalizedMessageId);
      await Scrollable.ensureVisible(
        visibleContext,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.18,
      );
      return;
    }

    if (!_messagesScrollController.hasClients) {
      return;
    }

    final messageIndex = _latestRemoteMessages.indexWhere(
      (message) => message.id == normalizedMessageId,
    );
    if (messageIndex == -1) {
      if (mounted) {
        showAppSnackBar(context, 'Исходное сообщение пока не загружено.');
      }
      return;
    }

    final targetMessage = _latestRemoteMessages[messageIndex];
    final estimatedTextHeight =
        ((targetMessage.text.trim().length / 34).ceil().clamp(1, 7) * 18)
            .toDouble();
    final estimatedAttachmentsHeight =
        targetMessage.attachments.isEmpty ? 0.0 : 160.0;
    final estimatedOffset =
        messageIndex * 112.0 + estimatedTextHeight + estimatedAttachmentsHeight;
    final clampedOffset = estimatedOffset.clamp(
      0.0,
      _messagesScrollController.position.maxScrollExtent,
    );
    await _messagesScrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) {
      return;
    }
    _highlightPinnedMessage(normalizedMessageId);
    final resolvedContext =
        _remoteMessageKeys[normalizedMessageId]?.currentContext;
    if (resolvedContext != null && resolvedContext.mounted) {
      await Scrollable.ensureVisible(
        resolvedContext,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: 0.18,
      );
    }
  }

  Future<void> _focusPinnedMessage() async {
    final pinned = _pinnedMessage;
    if (pinned == null) {
      return;
    }
    await _focusMessageById(pinned.messageId);
  }

  void _handleSearchChanged() {
    if (!mounted) {
      return;
    }
    final query = _searchController.query;
    final chatId = _chatId;
    if (query.isEmpty || chatId == null || chatId.isEmpty) {
      _serverSearchDebounce?.cancel();
      _updateChatState(_clearServerSearchState);
      return;
    }

    if (_serverSearchAvailable) {
      _scheduleServerSearch(query, chatId);
    }
    _updateChatState(() {});
  }

  void _openSearch() {
    _searchController.open();
  }

  void _closeSearch() {
    _searchController.close();
  }

  bool _messageMatchesSearch(String text) {
    return _searchController.matches(text);
  }

  int _searchMatchCount(
    List<ChatMessage> remoteMessages,
    List<_OutgoingMessage> optimisticMessages,
    int? serverResultCount,
  ) {
    if (!_searchController.hasQuery) {
      return 0;
    }
    if (serverResultCount != null) {
      return serverResultCount +
          optimisticMessages
              .where((message) => _messageMatchesSearch(message.text))
              .length;
    }
    return remoteMessages
            .where((message) => _messageMatchesSearch(message.text))
            .length +
        optimisticMessages
            .where((message) => _messageMatchesSearch(message.text))
            .length;
  }

  void _clearServerSearchState() {
    _serverSearchResults = const <ChatMessageSearchResult>[];
    _serverSearchQuery = '';
    _serverSearchError = null;
    _isServerSearchLoading = false;
  }

  void _scheduleServerSearch(String query, String chatId) {
    if (!_serverSearchAvailable) {
      return;
    }
    _serverSearchDebounce?.cancel();
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty || chatId.isEmpty) {
      return;
    }
    if (_serverSearchQuery != normalizedQuery || _serverSearchError != null) {
      _serverSearchQuery = normalizedQuery;
      _serverSearchResults = const <ChatMessageSearchResult>[];
      _serverSearchError = null;
    }
    _isServerSearchLoading = true;
    _serverSearchDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_runServerSearch(query: normalizedQuery, chatId: chatId));
    });
  }

  Future<void> _runServerSearch({
    required String query,
    required String chatId,
  }) async {
    try {
      final results = await _chatService.searchMessages(
        query: query,
        chatId: chatId,
        limit: 100,
      );
      if (!mounted || _searchController.query != query || _chatId != chatId) {
        return;
      }
      _updateChatState(() {
        _serverSearchQuery = query;
        _serverSearchResults = results;
        _serverSearchError = null;
        _isServerSearchLoading = false;
      });
    } on UnsupportedError {
      if (!mounted) {
        return;
      }
      _updateChatState(() {
        _serverSearchAvailable = false;
        _clearServerSearchState();
      });
    } catch (error) {
      if (!mounted || _searchController.query != query || _chatId != chatId) {
        return;
      }
      _updateChatState(() {
        _serverSearchQuery = query;
        _serverSearchError = error;
        _isServerSearchLoading = false;
      });
    }
  }

  bool get _hasCurrentServerSearchResult {
    return _searchController.hasQuery &&
        _serverSearchAvailable &&
        _serverSearchQuery == _searchController.query &&
        !_isServerSearchLoading &&
        _serverSearchError == null;
  }

  String _searchStatusLabel(int matchCount) {
    if (_isServerSearchLoading &&
        _serverSearchQuery == _searchController.query &&
        matchCount == 0) {
      return 'Ищем сообщения...';
    }
    if (_serverSearchError != null &&
        _serverSearchQuery == _searchController.query &&
        matchCount == 0) {
      return 'Поиск временно локальный';
    }
    return matchCount == 1
        ? 'Найдено 1 сообщение'
        : 'Найдено $matchCount сообщений';
  }

  void _handleMessagesScroll() {
    if (!_messagesScrollController.hasClients) {
      return;
    }
    final shouldShow = _messagesScrollController.offset > 120;
    if (shouldShow != _showJumpToLatestButton && mounted) {
      _updateChatState(() {
        _showJumpToLatestButton = shouldShow;
        if (!shouldShow) {
          // Дошли до низа — «новые снизу» прочитаны глазами.
          _newBelowViewportCount = 0;
        }
      });
    }
    _updateFloatingDayHeader();
    _updateUnreadChipVisibility();
  }

  /// Чип «N новых» показывается, пока разделитель непрочитанного выше
  /// вьюпорта И юзер отскроллен от низа. Если разделитель построен —
  /// сравниваем его глобальный dy с верхом вьюпорта (reverse-список:
  /// старое сверху); если он за cacheExtent (context == null) — fallback
  /// по времени: самый верхний видимый баббл НОВЕЕ якоря ⇒ разделитель
  /// выше. Гейт offset>120 не даёт чипу висеть, когда мы у низа и всё
  /// увидели (ревью батча: иначе timestamp-fallback вечно true у низа).
  void _updateUnreadChipVisibility() {
    if (!mounted) return;
    final anchorId = _unreadAnchorMessageId;
    bool above = false;
    final scrolledUp = _messagesScrollController.hasClients &&
        _messagesScrollController.offset > 120;
    if (anchorId != null && scrolledUp) {
      final dividerContext = _unreadDividerKey.currentContext;
      final dividerBox = dividerContext?.findRenderObject();
      if (dividerBox is RenderBox && dividerBox.attached) {
        final dy = dividerBox.localToGlobal(Offset.zero).dy;
        final viewportTop = _messagesViewportTopEdge();
        above = dy < viewportTop;
      } else if (dividerContext == null) {
        final anchorMessage = _findMessageById(anchorId);
        // Переиспользуем topmost из _updateFloatingDayHeader (в scroll-
        // пути он свежий и обходит ключи ОДИН раз); в post-frame пути,
        // где day-header не считался, добираем собственным обходом.
        final topmostVisible =
            _topmostVisibleRemoteMessage ?? _topmostVisibleMessage();
        if (anchorMessage != null && topmostVisible != null) {
          above = topmostVisible.timestamp.isAfter(anchorMessage.timestamp);
        }
      }
    }
    if (above != _unreadDividerAboveViewport) {
      _updateChatState(() => _unreadDividerAboveViewport = above);
    }
  }

  /// Пересчёт видимости чипа после кадра — нужен, когда состояние
  /// изменилось БЕЗ скролла (открытие чата с большим завалом: initial-
  /// jump молча не сработал за cacheExtent; приход снапшота сдвинул
  /// якорь). Дедуп через флаг, чтобы не копить колбэки на каждый build.
  void _scheduleUnreadChipRecompute() {
    if (_unreadChipRecomputeScheduled) return;
    _unreadChipRecomputeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _unreadChipRecomputeScheduled = false;
      _updateUnreadChipVisibility();
    });
  }

  double _messagesViewportTopEdge() {
    final box = context.findRenderObject();
    if (box is RenderBox && box.attached) {
      return box.localToGlobal(Offset.zero).dy;
    }
    return 0;
  }

  ChatMessage? _topmostVisibleMessage() {
    ChatMessage? best;
    double bestDy = double.infinity;
    for (final entry in _remoteMessageKeys.entries) {
      final renderObject = entry.value.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.attached) {
        continue;
      }
      final dy = renderObject.localToGlobal(Offset.zero).dy;
      if (dy >= -8 && dy < bestDy) {
        bestDy = dy;
        best = _findMessageById(entry.key);
      }
    }
    return best;
  }

  /// Walks the live remote-bubble GlobalKeys and finds the one closest
  /// to the top edge of the messages viewport. The day of that message
  /// is the floating-header value. We also bring the header in for ~1.2s
  /// after each scroll event, then fade it back out — same TG / iOS
  /// "show date while scrolling" pattern.
  void _updateFloatingDayHeader() {
    if (!mounted) return;
    // Плавающая плашка дня дублирует разделитель в списке, когда тот и так
    // на экране: история короткая (не скроллится) или проскроллена до
    // самого начала, где первый разделитель стоит прямо под шапкой.
    if (_messagesScrollController.hasClients) {
      final position = _messagesScrollController.position;
      if (position.maxScrollExtent <= 0 ||
          position.pixels >= position.maxScrollExtent - 4) {
        if (_floatingHeaderVisible) {
          _updateChatState(() => _floatingHeaderVisible = false);
        }
        return;
      }
    }
    DateTime? bestDay;
    ChatMessage? bestMessage;
    double bestDy = double.infinity;
    for (final entry in _remoteMessageKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final pos = box.localToGlobal(Offset.zero);
      // Items that scrolled above the viewport have negative dy. We
      // pick the highest one that is still within the visible area
      // (smallest non-negative dy) — that's the one whose day pill
      // should anchor at the top.
      if (pos.dy >= -8 && pos.dy < bestDy) {
        bestDy = pos.dy;
        final msg = _findMessageById(entry.key);
        if (msg != null) {
          bestDay = msg.timestamp;
          bestMessage = msg;
        }
      }
    }
    // Стэшим topmost — чип переиспользует его вместо второго обхода.
    _topmostVisibleRemoteMessage = bestMessage;
    if (bestDay != null && bestDay != _floatingDayHeader) {
      _updateChatState(() => _floatingDayHeader = bestDay);
    }
    // Visibility timer: header fades in immediately on scroll, fades
    // out 1.2s after the user stops scrolling.
    if (!_floatingHeaderVisible && mounted) {
      _updateChatState(() => _floatingHeaderVisible = true);
    }
    _floatingHeaderHideTimer?.cancel();
    _floatingHeaderHideTimer = Timer(
      const Duration(milliseconds: 1200),
      () {
        if (!mounted) return;
        _updateChatState(() => _floatingHeaderVisible = false);
      },
    );
  }

  ChatMessage? _findMessageById(String id) {
    for (final m in _latestRemoteMessages) {
      if (m.id == id) return m;
    }
    return null;
  }

  Future<void> _jumpToLatestMessages() async {
    if (!_messagesScrollController.hasClients) {
      return;
    }
    await _messagesScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) {
      return;
    }
    _updateChatState(() {
      _showJumpToLatestButton = false;
      _unreadAnchorMessageId = null;
      _newBelowViewportCount = 0;
      _unreadDividerAboveViewport = false;
    });
  }

  /// Тап по чипу «N новых»: к разделителю непрочитанного. Построен —
  /// плавный ensureVisible; за cacheExtent — через _focusMessageById по
  /// id якоря (оценка оффсета по индексу + добор), а не прыжок в самое
  /// начало истории maxScrollExtent, который уводил юзера мимо (ревью).
  Future<void> _scrollToUnreadDivider() async {
    final dividerContext = _unreadDividerKey.currentContext;
    if (dividerContext != null) {
      await Scrollable.ensureVisible(
        dividerContext,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.12,
      );
      return;
    }
    final anchorId = _unreadAnchorMessageId;
    if (anchorId == null) {
      return;
    }
    // Разделитель рендерится прямо перед якорным сообщением — скролл к
    // якорю выводит и разделитель.
    await _focusMessageById(anchorId);
  }

  bool _isIncomingMessageUnread(ChatMessage message) {
    if (message.senderId == _currentUserId || message.isRead) {
      return false;
    }
    final uid = _currentUserId;
    if (uid != null && uid.isNotEmpty && message.readBy.contains(uid)) {
      return false;
    }
    return true;
  }

  void _updateUnreadAnchor(List<ChatMessage> remoteMessages) {
    final unreadIncoming =
        remoteMessages.where(_isIncomingMessageUnread).toList();
    if (unreadIncoming.isNotEmpty) {
      _unreadAnchorMessageId = unreadIncoming.last.id;
    }
  }

  void _scheduleUnreadJumpIfNeeded() {
    if (_didInitialUnreadJump || _unreadAnchorMessageId == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      final context = _unreadDividerKey.currentContext;
      if (context == null) {
        return;
      }
      _didInitialUnreadJump = true;
      await Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.12,
      );
    });
  }

  bool _matchesRemoteMessage(
    _OutgoingMessage localMessage,
    List<ChatMessage> remoteMessages,
  ) {
    return remoteMessages.any((message) {
      return message.clientMessageId != null &&
          message.clientMessageId == localMessage.localId;
    });
  }

  Widget _buildMessagesBody() {
    if (_isBootstrapping) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_bootstrapError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: GlassPanel(
              borderRadius: BorderRadius.circular(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.chat_bubble_outline, size: 40),
                  const SizedBox(height: 12),
                  Text(
                    _bootstrapError!,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _bootstrapChat,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final chatId = _chatId;
    if (chatId == null || chatId.isEmpty) {
      return Center(
        child: GlassPanel(
          borderRadius: BorderRadius.circular(28),
          child: const Text('Чат недоступен.'),
        ),
      );
    }

    final timelineController = _timelineController;
    if (timelineController == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return StreamBuilder<List<ChatMessage>>(
      stream: timelineController.stream,
      // Hand StreamBuilder the controller's cached snapshot so the screen
      // doesn't flash a spinner on rebuilds (route swap, hot reload, app
      // resume) — the underlying chat service already has the messages
      // hydrated from Hive cache by the time we get here.
      initialData: timelineController.lastValue,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        // S1: первый кадр с сообщениями — конец замера открытия чата.
        final openTrace = _chatOpenTrace;
        if (openTrace != null && snapshot.hasData) {
          _chatOpenTrace = null;
          final count = snapshot.data?.length ?? 0;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => openTrace.finish('$count messages'),
          );
        }

        // Stream errors fire on every API failure — including a
        // simple offline state where we already have cached messages
        // hydrated. If we have data, prefer to keep showing it and
        // surface the error only via the OfflineIndicator banner +
        // a quiet status snack on retry; full error screen only
        // when we have NOTHING to show.
        final hasCachedData =
            snapshot.hasData && (snapshot.data?.isNotEmpty ?? false);
        if (snapshot.hasError && !hasCachedData) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: GlassPanel(
                  borderRadius: BorderRadius.circular(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 40),
                      const SizedBox(height: 12),
                      Text(
                        _appStatusService.isOffline
                            ? 'Нет соединения. Сообщения появятся, когда интернет вернётся.'
                            : 'Не удалось загрузить сообщения.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () {
                          unawaited(timelineController.refresh());
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Обновить'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        final remoteMessages = snapshot.data ?? const <ChatMessage>[];
        _latestRemoteMessages = remoteMessages;
        // First snapshot: hydrate _seenRemoteMessageIds with everything
        // we just got from the server so opening a chat doesn't animate
        // hundreds of messages at once. Subsequent snapshots will only
        // contain *new* ids that aren't in the set yet — those are the
        // ones the bubble enter animation should fire on.
        if (!_remoteHistoryHydrated && remoteMessages.isNotEmpty) {
          _seenRemoteMessageIds.addAll(remoteMessages.map((m) => m.id));
          _arrivalLedgerIds.addAll(remoteMessages.map((m) => m.id));
          // База «самое свежее, что видели» — по ней отличаем ГЕНУИННО
          // новое от старого, доехавшего смёрдженной страницей на
          // реконнекте (иначе бейдж раздувался на старые сообщения).
          for (final message in remoteMessages) {
            final seen = _newestArrivalSeen;
            if (seen == null || message.timestamp.isAfter(seen)) {
              _newestArrivalSeen = message.timestamp;
            }
          }
          _remoteHistoryHydrated = true;
        } else if (_remoteHistoryHydrated) {
          // Sticky unread: считаем НОВЫЕ входящие, пришедшие пока юзер
          // отскроллен вверх — бейдж на jump-FAB. Мутация поля в build —
          // установленный паттерн (_latestRemoteMessages строкой выше);
          // FAB строится ниже в этом же проходе.
          for (final message in remoteMessages) {
            final isFresh = _arrivalLedgerIds.add(message.id);
            final seen = _newestArrivalSeen;
            final isNewerThanBaseline =
                seen == null || message.timestamp.isAfter(seen);
            if (isFresh &&
                isNewerThanBaseline &&
                message.senderId != _currentUserId &&
                _messagesScrollController.hasClients &&
                _messagesScrollController.offset > 120) {
              _newBelowViewportCount += 1;
            }
            if (isNewerThanBaseline) {
              _newestArrivalSeen = message.timestamp;
            }
          }
        }
        _schedulePinnedSync(remoteMessages);
        final currentChatId = _chatId;
        if (currentChatId != null && currentChatId.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            unawaited(
              _sendQueue.confirmRemoteMessages(currentChatId, remoteMessages),
            );
          });
        }
        final optimisticMessages = _optimisticMessages
            .where((message) => !_matchesRemoteMessage(message, remoteMessages))
            .toList();
        final hasActiveSearch = _searchController.hasQuery;
        final hasServerSearchResult = _hasCurrentServerSearchResult;
        final serverSearchResultIds = hasServerSearchResult
            ? _serverSearchResults
                .map((result) => result.messageId)
                .where((messageId) => messageId.isNotEmpty)
                .toSet()
            : const <String>{};
        final filteredRemoteMessages = hasActiveSearch
            ? hasServerSearchResult
                ? remoteMessages
                    .where(
                        (message) => serverSearchResultIds.contains(message.id))
                    .toList()
                : remoteMessages
                    .where((message) => _messageMatchesSearch(message.text))
                    .toList()
            : remoteMessages;
        final filteredOptimisticMessages = hasActiveSearch
            ? optimisticMessages
                .where((message) => _messageMatchesSearch(message.text))
                .toList()
            : optimisticMessages;
        final loadedServerSearchIds = hasServerSearchResult
            ? filteredRemoteMessages.map((message) => message.id).toSet()
            : const <String>{};
        final serverOnlySearchResults = hasServerSearchResult
            ? _serverSearchResults
                .where(
                  (result) => !loadedServerSearchIds.contains(result.messageId),
                )
                .toList(growable: false)
            : const <ChatMessageSearchResult>[];
        final hasUnreadIncoming =
            !hasActiveSearch && remoteMessages.any(_isIncomingMessageUnread);
        if (!hasActiveSearch) {
          _updateUnreadAnchor(remoteMessages);
        }
        if (hasUnreadIncoming) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _markChatAsRead();
          });
        }

        if (filteredRemoteMessages.isEmpty &&
            filteredOptimisticMessages.isEmpty &&
            serverOnlySearchResults.isEmpty) {
          if (hasActiveSearch) {
            return Center(
              child: GlassPanel(
                borderRadius: BorderRadius.circular(24),
                child: Text(
                  'Ничего не найдено по запросу "${_searchController.query}"',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final isFriendsTree =
              context.read<TreeProvider>().selectedTreeKind == TreeKind.friends;
          return Center(
            child: GlassPanel(
              borderRadius: BorderRadius.circular(24),
              child: Text(
                isFriendsTree
                    ? 'Пока пусто. Начните разговор.'
                    : 'Пока пусто. Начните диалог.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (!hasActiveSearch) {
          _scheduleUnreadJumpIfNeeded();
          // Чип «N новых» появляется/обновляется и без скролла — когда
          // снапшот сдвинул якорь или чат открылся с завалом за
          // cacheExtent (там initial-jump молча не срабатывает).
          _scheduleUnreadChipRecompute();
        }
        String? latestOutgoingMessageId;
        if (!widget.isGroup) {
          for (final message in remoteMessages) {
            if (message.senderId == _currentUserId) {
              latestOutgoingMessageId = message.id;
              break;
            }
          }
        }
        final unreadAnchorMessageId = _unreadAnchorMessageId;
        final hasUnreadDivider = !hasActiveSearch &&
            unreadAnchorMessageId != null &&
            remoteMessages
                .any((message) => message.id == unreadAnchorMessageId);
        // «N новых» для плавающего чипа: входящие от якоря (самое старое
        // непрочитанное) до свежайшего. Список newest-first — это
        // индексы 0..anchorIndex.
        var unreadChipCount = 0;
        if (hasUnreadDivider) {
          final anchorIndex = remoteMessages
              .indexWhere((message) => message.id == unreadAnchorMessageId);
          for (var i = 0; i <= anchorIndex; i++) {
            if (remoteMessages[i].senderId != _currentUserId) {
              unreadChipCount += 1;
            }
          }
        }
        final searchMatchCount = _searchMatchCount(
          filteredRemoteMessages,
          filteredOptimisticMessages,
          hasServerSearchResult ? _serverSearchResults.length : null,
        );
        final searchStatusLabel = _searchStatusLabel(searchMatchCount);

        // When the peer starts typing, lift the message column by 20dp
        // so the most-recent bubble visually "anticipates" the
        // incoming message — same TG / iMessage subtle move that
        // tells you "hey, something's coming". Reverse ListView's
        // bottom-padding lives at the literal bottom of the viewport,
        // so growing it pushes the newest bubble up.
        final isPeerTyping = _typingUsers.isNotEmpty;
        return Stack(
          children: [
            AnimatedPadding(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.only(
                bottom: isPeerTyping ? 20 : 0,
              ),
              child: ListView.builder(
                controller: _messagesScrollController,
                reverse: true,
                padding: EdgeInsets.fromLTRB(
                  0,
                  hasActiveSearch ? 52 : 8,
                  0,
                  8,
                ),
                // Pre-render ~1.4 screens of bubbles in each scroll
                // direction (default is 250 px, which on a 1.5-meter
                // chat with photo carousels looked like a fresh build
                // every flick — the user reported jank when scrolling
                // through long histories). 1500 dp is roughly 3 phone
                // viewports of buffer; the trade-off is RAM, but
                // bubbles already cap their text + share an image
                // cache so the cost stays bounded.
                cacheExtent: 1500,
                itemCount: filteredRemoteMessages.length +
                    filteredOptimisticMessages.length +
                    serverOnlySearchResults.length +
                    (hasUnreadDivider ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index < filteredOptimisticMessages.length) {
                    final localMessage = filteredOptimisticMessages[index];
                    return _buildOptimisticBubble(localMessage);
                  }

                  final remoteIndex = index - filteredOptimisticMessages.length;
                  if (hasUnreadDivider && remoteIndex >= 0) {
                    var remoteCursor = 0;
                    for (var msgIdx = 0;
                        msgIdx < filteredRemoteMessages.length;
                        msgIdx++) {
                      final message = filteredRemoteMessages[msgIdx];
                      if (message.id == unreadAnchorMessageId) {
                        if (remoteCursor == remoteIndex) {
                          return _buildUnreadDivider();
                        }
                        remoteCursor++;
                      }

                      if (remoteCursor == remoteIndex) {
                        final isMe = message.senderId == _currentUserId;
                        return _wrapBubbleWithDayHeader(
                          bubble: _buildRemoteBubble(
                            message,
                            isMe,
                            footerLabel: _messageFooterLabel(
                              message,
                              isMe: isMe,
                              isLatestOwnDirectMessage:
                                  message.id == latestOutgoingMessageId,
                            ),
                            isGroupedWithAbove: _isGroupedWithAbove(
                              filteredRemoteMessages,
                              msgIdx,
                            ),
                          ),
                          messages: filteredRemoteMessages,
                          messageIndex: msgIdx,
                        );
                      }
                      remoteCursor++;
                    }
                  }

                  final remoteItemCount = filteredRemoteMessages.length +
                      (hasUnreadDivider ? 1 : 0);
                  if (remoteIndex >= remoteItemCount) {
                    final resultIndex = remoteIndex - remoteItemCount;
                    return _buildServerSearchResultTile(
                      serverOnlySearchResults[resultIndex],
                    );
                  }

                  final messageIdx = remoteIndex - (hasUnreadDivider ? 1 : 0);
                  final remoteMessage = filteredRemoteMessages[messageIdx];
                  final isMe = remoteMessage.senderId == _currentUserId;
                  return _wrapBubbleWithDayHeader(
                    bubble: _buildRemoteBubble(
                      remoteMessage,
                      isMe,
                      footerLabel: _messageFooterLabel(
                        remoteMessage,
                        isMe: isMe,
                        isLatestOwnDirectMessage:
                            remoteMessage.id == latestOutgoingMessageId,
                      ),
                      isGroupedWithAbove: _isGroupedWithAbove(
                        filteredRemoteMessages,
                        messageIdx,
                      ),
                    ),
                    messages: filteredRemoteMessages,
                    messageIndex: messageIdx,
                  );
                },
              ),
            ),
            if (hasActiveSearch)
              Positioned(
                left: 12,
                right: 12,
                top: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      searchStatusLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ),
              ),
            // Floating date header — pill at the top of the viewport
            // showing the day of the topmost-visible message. Fades in
            // on scroll, fades out 1.2s after scrolling stops.
            if (_floatingDayHeader != null && !hasActiveSearch)
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    opacity: _floatingHeaderVisible ? 1.0 : 0.0,
                    child: Center(
                      child: _buildDateDivider(_floatingDayHeader!),
                    ),
                  ),
                ),
              ),
            // Sticky unread: разделитель «Непрочитанные» ускроллен выше
            // вьюпорта (или вовсе за cacheExtent) — плавающий чип
            // «N новых» возвращает к нему одним тапом.
            if (_unreadDividerAboveViewport &&
                hasUnreadDivider &&
                unreadChipCount > 0 &&
                !hasActiveSearch)
              Positioned(
                top: 44,
                left: 0,
                right: 0,
                child: Center(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: const ValueKey('unread-floating-chip'),
                      borderRadius: BorderRadius.circular(999),
                      onTap: _scrollToUnreadDivider,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(alpha: 0.25),
                            width: 0.6,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.keyboard_arrow_up_rounded,
                              size: 16,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$unreadChipCount новых',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimaryContainer,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // Telegram-style entry: scale 0 → 1 with elastic overshoot
            // + fade. AnimatedSwitcher (vs AnimatedScale) actually
            // mounts / unmounts the FAB, so the existing test that
            // asserts findsNothing when there's nothing to scroll keeps
            // working — only the visual swap is animated.
            Positioned(
              right: 16,
              bottom: 18,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                switchInCurve: Curves.elasticOut,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  );
                },
                child: _showJumpToLatestButton
                    // Бейдж с числом новых снизу (Telegram). Key живёт на
                    // Badge — AnimatedSwitcher диффит прямого ребёнка.
                    ? Badge.count(
                        key: const ValueKey('jump-to-latest-fab'),
                        count: _newBelowViewportCount,
                        isLabelVisible: _newBelowViewportCount > 0,
                        offset: const Offset(-2, 2),
                        child: FloatingActionButton.small(
                          heroTag: 'jump-to-latest',
                          onPressed: _jumpToLatestMessages,
                          tooltip: 'К последним сообщениям',
                          child: const Icon(Icons.keyboard_arrow_down_rounded),
                        ),
                      )
                    : const SizedBox.shrink(
                        key: ValueKey('jump-to-latest-empty')),
              ),
            ),
          ],
        );
      },
    );
  }

  // Плотность (чанк 22): было 3 строки (заголовок «Закреплённое
  // сообщение» + имя + превью, ~76dp) — спека держит закреп одной
  // строкой 44-48dp (как в Telegram: заголовок избыточен, иконка-
  // булавка сама говорит «закреплено»). Имя и текст сообщения — два
  // отдельных Text подряд в одной строке (не TextSpan/RichText — чтобы
  // find.text в тестах продолжал находить имя и превью по отдельности).
  // Высоту держит IconButton «Открепить» (constraints 44×44 — тач-цель
  // по правилам плотности без VisualDensity), паддинг панели — 2dp
  // сверху-снизу, итог ≈48dp.
  Widget _buildPinnedMessageBanner() {
    final pinned = _pinnedMessage!;
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey<String>('pinned-message-banner'),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: InkWell(
        onTap: _focusPinnedMessage,
        borderRadius: BorderRadius.circular(16),
        child: GlassPanel(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          borderRadius: BorderRadius.circular(16),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 24,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.push_pin_outlined,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110),
                child: Text(
                  pinned.senderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _pinnedPreviewLabel(pinned),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => unawaited(_clearPinnedMessage()),
                tooltip: 'Открепить',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                // tapTargetSize: shrinkWrap — M3 по умолчанию (padded)
                // добавляет НЕВИДИМЫЙ, но занимающий layout паддинг до
                // 48dp тач-цели ПОВЕРХ minimumSize из constraints; без
                // этого однострочный закреп раздувается за целевые
                // 44-48dp. 44×44 из constraints уже держит правило
                // «тач-цели ≥44dp» сам по себе.
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                iconSize: 18,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUnreadDivider() {
    final theme = Theme.of(context);
    return Padding(
      key: _unreadDividerKey,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: theme.colorScheme.primary.withValues(alpha: 0.35),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Непрочитанные',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: theme.colorScheme.primary.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }

  String? _messageFooterLabel(
    ChatMessage message, {
    required bool isMe,
    required bool isLatestOwnDirectMessage,
  }) {
    final segments = <String>[];
    final expiresLabel = _expiresLabel(message.expiresAt);
    if (expiresLabel != null) {
      segments.add('Автоудаление: $expiresLabel');
    }
    // Direct: show receipt only on the latest own message (avoids label
    // spam down the entire bubble column). Group: same restriction —
    // we want the reader to glance at the latest message, not the
    // ten-message-back trail. Group label includes a "X из N прочитали"
    // hint when partial coverage.
    if (isMe && isLatestOwnDirectMessage) {
      final receipt =
          widget.isGroup ? _groupReceiptLabel(message) : _receiptLabel(message);
      if (receipt != null && receipt.isNotEmpty) {
        segments.add(receipt);
      }
    }
    if (segments.isEmpty) {
      return null;
    }
    return segments.join(' · ');
  }

  String _receiptLabel(ChatMessage message) {
    if (_messageReadByAnyRecipient(message)) {
      return 'Прочитано';
    }
    if (_messageDeliveredToAnyRecipient(message)) {
      return 'Доставлено';
    }
    return 'Отправлено';
  }

  /// Group-chat receipt summary: "Прочитали все", "Прочитали X из N",
  /// "Доставлено всем" depending on coverage. Returns null when the
  /// group has no other recipients (single-member group, edge case).
  String? _groupReceiptLabel(ChatMessage message) {
    final recipients = _messageRecipientIds(message);
    final total = recipients.length;
    if (total == 0) {
      return null;
    }
    final readCount = recipients.where(message.readBy.contains).length;
    if (readCount >= total) {
      return 'Прочитали все';
    }
    if (readCount > 0) {
      return 'Прочитали $readCount из $total';
    }
    final deliveredCount =
        recipients.where(message.deliveredTo.contains).length;
    if (deliveredCount >= total) {
      return 'Доставлено всем';
    }
    if (deliveredCount > 0) {
      return 'Доставлено $deliveredCount из $total';
    }
    return 'Отправлено';
  }

  bool _messageDeliveredToAnyRecipient(ChatMessage message) {
    return _messageRecipientIds(message).any(message.deliveredTo.contains);
  }

  bool _messageReadByAnyRecipient(ChatMessage message) {
    return _messageRecipientIds(message).any(message.readBy.contains) ||
        (message.readBy.isEmpty && message.isRead);
  }

  Set<String> _messageRecipientIds(ChatMessage message) {
    final currentUserId = _currentUserId;
    final recipients = message.participants
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && value != currentUserId)
        .toSet();
    if (recipients.isNotEmpty) {
      return recipients;
    }
    return message.readBy
        .followedBy(message.deliveredTo)
        .where((value) => value.trim().isNotEmpty && value != currentUserId)
        .toSet();
  }

  String? _expiresLabel(DateTime? expiresAt) {
    if (expiresAt == null) {
      return null;
    }

    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.inSeconds <= 0) {
      return 'скоро';
    }
    if (remaining.inHours < 1) {
      final minutes = remaining.inMinutes.clamp(1, 59);
      return '$minutes мин';
    }
    if (remaining.inDays < 1) {
      final hours = remaining.inHours.clamp(1, 23);
      return '$hours ч';
    }
    final days = remaining.inDays.clamp(1, 999);
    return '$days д';
  }

  /// Telegram-style message grouping: a message continues a same-sender run
  /// when the message displayed directly above it (the older neighbour at
  /// index+1, since the list is newest-first + reversed) is from the same
  /// sender within 60s. Continuation messages drop the repeated sender label
  /// and tighten the inter-bubble gap.
  bool _isGroupedWithAbove(List<ChatMessage> messages, int index) {
    final aboveIndex = index + 1;
    if (aboveIndex < 0 || aboveIndex >= messages.length) {
      return false;
    }
    final current = messages[index];
    final above = messages[aboveIndex];
    if (current.senderId != above.senderId) {
      return false;
    }
    return current.timestamp.difference(above.timestamp).abs().inSeconds <= 60;
  }

  Widget _buildRemoteBubble(
    ChatMessage message,
    bool isMe, {
    String? footerLabel,
    bool isGroupedWithAbove = false,
  }) {
    final messageKey = _remoteMessageKeys.putIfAbsent(
      message.id,
      () => GlobalKey(),
    );
    // Mark this id as seen on the next frame so the next time we build
    // we skip the animation. We do it post-frame instead of inline
    // because TweenAnimationBuilder needs the "not in set" signal to
    // be true for the entire first build pass.
    final isFirstAppearance = !_seenRemoteMessageIds.contains(message.id);
    if (isFirstAppearance) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _seenRemoteMessageIds.add(message.id);
      });
    }
    final callMetadata = message.call;
    if (callMetadata != null) {
      return _wrapInEnterAnimation(
        animate: isFirstAppearance,
        child: KeyedSubtree(
          key: messageKey,
          child: _buildCallSummaryBubble(message, callMetadata, isMe),
        ),
      );
    }
    return _wrapInEnterAnimation(
      animate: isFirstAppearance,
      child: SwipeToReply(
        key: messageKey,
        isMe: isMe,
        // Selection mode uses long-press / tap on the bubble for
        // multi-select — the swipe gesture would conflict, so disable
        // it via a no-op callback while in selection mode.
        onReply:
            _isSelectionMode ? () {} : () => _selectReplyFromMessage(message),
        child: GestureDetector(
          onTap: _isSelectionMode
              ? () => _toggleRemoteMessageSelection(message)
              : null,
          onLongPressStart: (details) {
            // Same TG / iOS pattern: medium-impact haptic confirms the
            // long-press fired before the action sheet opens. Without it
            // users hold a beat too long because nothing tells them the
            // gesture took. Mirrors what reaction-picker already does.
            HapticFeedback.mediumImpact();
            if (_isSelectionMode) {
              _toggleRemoteMessageSelection(message);
              return;
            }
            _openRemoteMessageActions(
              message,
              anchorPosition: details.globalPosition,
            );
          },
          onSecondaryTapDown: (details) {
            if (_isSelectionMode) {
              _toggleRemoteMessageSelection(message);
              return;
            }
            _openRemoteMessageActions(
              message,
              anchorPosition: details.globalPosition,
            );
          },
          child: _ChatBubble(
            isMe: isMe,
            groupedWithPrev: isGroupedWithAbove,
            senderLabel: widget.isGroup && !isMe && !isGroupedWithAbove
                ? _groupSenderLabel(message.senderName, message.senderId)
                : null,
            onSenderTap: widget.isGroup && !isMe
                ? () => unawaited(_openDirectChatForMessage(message))
                : null,
            text: message.text,
            highlightQuery: _searchController.query,
            timeLabel: DateFormat.Hm('ru')
                .format(toLocalForDisplay(message.timestamp)),
            isRead: isMe && _messageReadByAnyRecipient(message),
            isDelivered: isMe && _messageDeliveredToAnyRecipient(message),
            remoteAttachments: message.attachments,
            replyTo: message.replyTo,
            onReplyTap: message.replyTo == null
                ? null
                : () =>
                    unawaited(_focusMessageById(message.replyTo!.messageId)),
            isPinned: _pinnedMessage?.messageId == message.id,
            isHighlighted: _highlightedPinnedMessageId == message.id,
            footerLabel: footerLabel,
            reactionGroups: _reactionGroupsForMessage(message),
            onReactionTap: (emoji) => _toggleReactionForMessage(message, emoji),
            showSelectionMarker: _isSelectionMode,
            isSelected: _selectionController.isRemoteSelected(message.id),
            onOpenRemoteAttachment: (attachments, attachment) =>
                _openRemoteAttachmentPreview(message, attachments, attachment),
          ),
        ),
      ),
    );
  }

  /// Telegram-style date header: a small pill above the *oldest*
  /// message of each day. Detected by looking at the next-older
  /// message in the list (since `filteredRemoteMessages[0]` is newest):
  /// if its day differs, this message is the day-anchor and gets a
  /// header. Last message in the list (oldest of all) always gets
  /// one. Optimistic / search-result paths skip the header — they
  /// don't form a continuous timeline.
  Widget _wrapBubbleWithDayHeader({
    required Widget bubble,
    required List<ChatMessage> messages,
    required int messageIndex,
  }) {
    if (messageIndex < 0 || messageIndex >= messages.length) {
      return bubble;
    }
    final current = messages[messageIndex].timestamp;
    final hasOlder = messageIndex < messages.length - 1;
    final isOldestOfDay = !hasOlder ||
        _differentLocalDay(current, messages[messageIndex + 1].timestamp);
    if (!isOldestOfDay) return bubble;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDateDivider(current),
        bubble,
      ],
    );
  }

  bool _differentLocalDay(DateTime a, DateTime b) {
    final localA = toLocalForDisplay(a);
    final localB = toLocalForDisplay(b);
    return localA.year != localB.year ||
        localA.month != localB.month ||
        localA.day != localB.day;
  }

  Widget _buildDateDivider(DateTime timestamp) {
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    // Плотность (чанк 22): отступы 8/8 сверху-снизу (было 10/10) и
    // компактный чип ~22-24dp (текст явно 12sp, было labelSmall=11 с
    // паддингом 12/5) — спека держит разделитель дня на «22-24dp,
    // текст 12sp, отступы 8/8».
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: tokens.surfaceStrong.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: tokens.surfaceLine.withValues(alpha: 0.45),
              width: 0.6,
            ),
          ),
          child: Text(
            _formatDateDividerLabel(timestamp),
            style: theme.textTheme.labelSmall?.copyWith(
              color: tokens.inkSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ),
    );
  }

  /// "Сегодня" / "Вчера" / "12 марта" / "12 марта 2025" depending on
  /// how recent the message is. Same shape as TG date pills.
  String _formatDateDividerLabel(DateTime timestamp) {
    final now = DateTime.now();
    // Normalize source timestamp to LOCAL once — backend pushes
    // UTC, and `DateTime(timestamp.year, ...)` would otherwise pull
    // year/month/day from the UTC frame which can flip a date by ±1
    // day across midnight in the user's zone.
    final localTimestamp = toLocalForDisplay(timestamp);
    final today = DateTime(now.year, now.month, now.day);
    final messageDay =
        DateTime(localTimestamp.year, localTimestamp.month, localTimestamp.day);
    final diff = today.difference(messageDay).inDays;
    if (diff == 0) return 'Сегодня';
    if (diff == 1) return 'Вчера';
    final pattern = localTimestamp.year == now.year ? 'd MMMM' : 'd MMMM yyyy';
    return DateFormat(pattern, 'ru').format(localTimestamp);
  }

  /// Wraps a bubble in a slide-up + fade-in tween that runs once on
  /// first appearance. Pure VERTICAL entrance — matches the optimistic
  /// outgoing bubble (see _buildOutgoingMessageBubble). The earlier
  /// horizontal nudge (own from the right, peer from the left) made own
  /// messages visibly jump right→left when the server echo reconciled a
  /// just-sent message into a "first appearance" remote bubble — the
  /// «блок улетает справа налево» the user reported. Returns the child
  /// unchanged when [animate] is false (existing messages, history scroll).
  Widget _wrapInEnterAnimation({
    required bool animate,
    required Widget child,
  }) {
    if (!animate) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (context, t, c) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 14),
            child: c,
          ),
        );
      },
      child: child,
    );
  }

  Widget _buildCallSummaryBubble(
    ChatMessage message,
    ChatMessageCall callMetadata,
    bool isMe,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final timeLabel =
        DateFormat.Hm('ru').format(toLocalForDisplay(message.timestamp));
    final palette = _callSummaryPalette(scheme, callMetadata);
    final mediaIcon =
        callMetadata.isVideo ? Icons.videocam_rounded : Icons.call_rounded;
    final summaryLabel = _callSummaryLabel(callMetadata);
    final secondaryLabel = _callSummarySecondaryLabel(callMetadata);
    final tapMode =
        callMetadata.isVideo ? CallMediaMode.video : CallMediaMode.audio;

    // Плотность (чанк 22): было двухстрочной карточкой (34×34 иконка +
    // Column из заголовка и «длительность · время», паддинг 14/10 —
    // суммарно за 60dp высотой). Спека: «одна строка ≤44dp». Заголовок
    // и «длительность · время» склеены в одну строку через " · " —
    // ровно как их и озвучивают («Звонок · 12 мин»), иконка направления
    // (входящий/исходящий) остаётся справа.
    final summaryText = secondaryLabel != null
        ? '$summaryLabel · $secondaryLabel · $timeLabel'
        : '$summaryLabel · $timeLabel';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => unawaited(_startCall(tapMode)),
              child: Ink(
                decoration: BoxDecoration(
                  color: palette.background,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: palette.border,
                    width: 0.6,
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      mediaIcon,
                      size: 18,
                      color: palette.iconColor,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        summaryText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: palette.titleColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      isMe
                          ? Icons.call_made_rounded
                          : Icons.call_received_rounded,
                      size: 16,
                      color: palette.subtitleColor,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _callSummaryLabel(ChatMessageCall callMetadata) {
    final isVideo = callMetadata.isVideo;
    switch (callMetadata.state) {
      case 'ended':
        return isVideo ? 'Видеозвонок' : 'Аудиозвонок';
      case 'missed':
        return isVideo ? 'Пропущенный видеозвонок' : 'Пропущенный звонок';
      case 'rejected':
        return isVideo ? 'Видеозвонок отклонён' : 'Звонок отклонён';
      case 'cancelled':
        return isVideo ? 'Видеозвонок отменён' : 'Звонок отменён';
      case 'failed':
        return 'Не удалось позвонить';
      default:
        return isVideo ? 'Видеозвонок' : 'Аудиозвонок';
    }
  }

  String? _callSummarySecondaryLabel(ChatMessageCall callMetadata) {
    if (callMetadata.state != 'ended') {
      return null;
    }
    final durationMs = callMetadata.durationMs;
    if (durationMs == null || durationMs <= 0) {
      return null;
    }
    final totalSeconds = (durationMs / 1000).floor();
    final seconds = totalSeconds % 60;
    final totalMinutes = totalSeconds ~/ 60;
    final minutes = totalMinutes % 60;
    final hours = totalMinutes ~/ 60;
    String two(int v) => v.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:${two(minutes)}:${two(seconds)}';
    }
    return '$minutes:${two(seconds)}';
  }

  _CallSummaryPalette _callSummaryPalette(
    ColorScheme scheme,
    ChatMessageCall callMetadata,
  ) {
    final isMissedLike = callMetadata.isMissed || callMetadata.isRejected;
    if (isMissedLike) {
      final accent = scheme.error;
      return _CallSummaryPalette(
        background: scheme.errorContainer.withValues(alpha: 0.55),
        border: accent.withValues(alpha: 0.32),
        iconBackground: accent.withValues(alpha: 0.18),
        iconColor: accent,
        titleColor: scheme.onErrorContainer,
        subtitleColor: scheme.onErrorContainer.withValues(alpha: 0.78),
      );
    }
    return _CallSummaryPalette(
      background: scheme.surfaceContainerHigh.withValues(alpha: 0.85),
      border: scheme.outlineVariant.withValues(alpha: 0.55),
      iconBackground: scheme.primary.withValues(alpha: 0.12),
      iconColor: scheme.primary,
      titleColor: scheme.onSurface,
      subtitleColor: scheme.onSurfaceVariant,
    );
  }

  Widget _buildServerSearchResultTile(ChatMessageSearchResult result) {
    final theme = Theme.of(context);
    final isMe = result.senderId == _currentUserId;
    final senderLabel = isMe
        ? 'Вы'
        : result.senderName.trim().isEmpty
            ? 'Участник'
            : result.senderName.trim();
    final snippet = result.snippet.trim().isNotEmpty
        ? result.snippet.trim()
        : result.text.trim();
    final text = snippet.isEmpty ? 'Сообщение без текста' : snippet;
    final hasDate = result.matchedAt.millisecondsSinceEpoch > 0;
    final timeLabel = hasDate
        ? DateFormat('dd.MM HH:mm', 'ru').format(result.matchedAt.toLocal())
        : '';
    final background = isMe
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
    final foreground = isMe
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          senderLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: foreground.withValues(alpha: 0.82),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (timeLabel.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          timeLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: foreground.withValues(alpha: 0.68),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  _HighlightedMessageText(
                    text: text,
                    query: _searchController.query,
                    color: foreground,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOptimisticBubble(_OutgoingMessage message) {
    final timeLabel =
        DateFormat.Hm('ru').format(toLocalForDisplay(message.timestamp));
    final theme = Theme.of(context);
    final statusMeta = _statusMetaForOutgoingMessage(theme, message);
    final bubbleKey = ValueKey<String>('outgoing-bubble-${message.localId}');

    // Telegram-style send animation: the optimistic bubble slides up
    // 14dp + fades in over 220ms. Keyed by localId so the tween only
    // plays once per message — re-renders during status flips
    // (pending → sent → failed) keep the bubble in its rest state.
    return TweenAnimationBuilder<double>(
      key: ValueKey<String>('outgoing-bubble-anim-${message.localId}'),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * 14),
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
        child: Align(
          alignment: Alignment.centerRight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SwipeToReply(
                key: bubbleKey,
                isMe: true,
                onReply: _isSelectionMode
                    ? () {}
                    : () => _selectReplyFromOutgoingMessage(message),
                child: GestureDetector(
                  onTap: _isSelectionMode
                      ? () => _toggleOutgoingMessageSelection(message)
                      : null,
                  onLongPressStart: (details) {
                    HapticFeedback.mediumImpact();
                    if (_isSelectionMode) {
                      _toggleOutgoingMessageSelection(message);
                      return;
                    }
                    _openOutgoingMessageActions(
                      message,
                      anchorPosition: details.globalPosition,
                    );
                  },
                  onSecondaryTapDown: (details) {
                    if (_isSelectionMode) {
                      _toggleOutgoingMessageSelection(message);
                      return;
                    }
                    _openOutgoingMessageActions(
                      message,
                      anchorPosition: details.globalPosition,
                    );
                  },
                  child: _ChatBubble(
                    isMe: true,
                    text: message.text,
                    highlightQuery: _searchController.query,
                    timeLabel: timeLabel,
                    isRead: false,
                    isDelivered: false,
                    remoteAttachments: message.forwardedAttachments,
                    localAttachments: message.attachments,
                    localAttachmentStatuses: message.attachmentUploadStatuses,
                    replyTo: message.replyTo,
                    onReplyTap: message.replyTo == null
                        ? null
                        : () => unawaited(
                              _focusMessageById(message.replyTo!.messageId),
                            ),
                    isPinned: false,
                    isHighlighted: false,
                    reactionGroups: const <_ReactionGroup>[],
                    showSelectionMarker: _isSelectionMode,
                    isSelected: _selectionController
                        .isOutgoingSelected(message.localId),
                    onOpenLocalAttachment: (files, file) =>
                        _openLocalAttachmentPreview(files, file),
                    footerLabel: _autoDeleteSettings.option ==
                            ChatAutoDeleteOption.off
                        ? null
                        : 'Автоудаление: ${_autoDeleteSettings.option.label}',
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Status icon cross-fades + scales when the message
                  // walks the ladder (pending → sent → failed). Keyed by
                  // icon code so AnimatedSwitcher actually swaps.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => ScaleTransition(
                      scale: Tween<double>(begin: 0.6, end: 1.0)
                          .animate(animation),
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: Icon(
                      statusMeta.icon,
                      key: ValueKey<int>(statusMeta.icon.codePoint),
                      size: 14,
                      color: statusMeta.color,
                    ),
                  ),
                  const SizedBox(width: 4),
                  // S4: failed-строка («Не отправлено» + «Повторить»)
                  // переполняла узкий баббл — лейбл сжимаем, кнопка
                  // остаётся целой тап-целью.
                  Flexible(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: statusMeta.color,
                        fontWeight:
                            message.status == _OutgoingMessageStatus.failed
                                ? FontWeight.w700
                                : FontWeight.w500,
                      ),
                      child: Text(
                        statusMeta.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (message.status == _OutgoingMessageStatus.failed) ...[
                    const SizedBox(width: 6),
                    TextButton(
                      onPressed: () => unawaited(
                        _sendQueue.retry(message.chatId, message.localId),
                      ),
                      child: const Text('Повторить'),
                    ),
                  ],
                ],
              ),
              // Общий LinearProgressIndicator заменён пофайловыми
              // оверлеями на плитках (_LocalMediaGrid) — текстовый
              // статус «Загрузка вложений N/M» остаётся: он единственный
              // сигнал для файлов за «+N» и для аудио/кружков.
            ],
          ),
        ),
      ),
    );
  }

  _OutgoingStatusMeta _statusMetaForOutgoingMessage(
    ThemeData theme,
    _OutgoingMessage message,
  ) {
    if (message.status == _OutgoingMessageStatus.failed) {
      return _OutgoingStatusMeta(
        label: message.errorText ?? 'Ошибка отправки',
        icon: Icons.error_outline,
        color: theme.colorScheme.error,
      );
    }
    if (message.status == _OutgoingMessageStatus.sent) {
      return _OutgoingStatusMeta(
        label: 'Отправлено',
        icon: Icons.done_all,
        color: theme.colorScheme.primary,
      );
    }

    switch (message.progress?.stage) {
      case ChatSendProgressStage.preparing:
        return _OutgoingStatusMeta(
          label: 'Подготовка вложений...',
          icon: Icons.inventory_2_outlined,
          color: theme.colorScheme.onSurfaceVariant,
        );
      case ChatSendProgressStage.uploading:
        final total = message.progress?.total ?? 0;
        final completed = message.progress?.completed ?? 0;
        if (total > 1) {
          return _OutgoingStatusMeta(
            label: 'Загрузка вложений $completed/$total',
            icon: Icons.cloud_upload_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          );
        }
        return _OutgoingStatusMeta(
          label: 'Загрузка вложения...',
          icon: Icons.cloud_upload_outlined,
          color: theme.colorScheme.onSurfaceVariant,
        );
      case ChatSendProgressStage.sending:
      case null:
        return _OutgoingStatusMeta(
          label: 'Отправляется...',
          icon: Icons.schedule_send_outlined,
          color: theme.colorScheme.onSurfaceVariant,
        );
    }
  }
}
