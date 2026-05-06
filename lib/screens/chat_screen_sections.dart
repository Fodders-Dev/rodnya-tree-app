part of 'chat_screen.dart';

extension _ChatScreenScaffoldSections on _ChatScreenState {
  PreferredSizeWidget _buildChatAppBar(BuildContext context) {
    return AppBar(
      leading: IconButton(
        tooltip: _isSelectionMode
            ? 'Снять выделение'
            : (_isSearchMode ? 'Закрыть поиск' : 'Назад'),
        icon: Icon(
          _isSelectionMode
              ? Icons.close
              : (_isSearchMode ? Icons.close : Icons.arrow_back),
        ),
        onPressed: _isSelectionMode
            ? _exitSelectionMode
            : (_isSearchMode ? _closeSearch : () => context.pop()),
      ),
      titleSpacing: 0,
      title: _buildChatAppBarTitle(context),
      actions: _buildChatAppBarActions(),
    );
  }

  Widget _buildChatAppBarTitle(BuildContext context) {
    if (_isSelectionMode) {
      return Text(
        'Выбрано: $_selectedMessageCount',
        style: const TextStyle(fontWeight: FontWeight.w600),
      );
    }

    if (_isSearchMode) {
      return TextField(
        controller: _searchController.textController,
        autofocus: true,
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(
          hintText: 'Поиск по сообщениям',
          border: InputBorder.none,
        ),
      );
    }

    final peerAvatarImage = buildAvatarImageProvider(widget.photoUrl);
    // Direct chat → peer online state drives the green dot. We only
    // show the dot when the peer (the other participant) is actually
    // online; for groups we skip it because "any of N is online" is
    // less actionable visually. The pulsing animation lives in
    // _OnlinePulseDot to keep it scoped.
    final showOnlineDot = !widget.isGroup &&
        _otherParticipantIds(_chatDetails).any(_onlineUserIds.contains);

    return Row(
      children: [
        GestureDetector(
          onTap: !widget.isGroup &&
                  widget.relativeId != null &&
                  widget.relativeId!.isNotEmpty
              ? () {
                  // Light haptic before navigation — confirms the tap
                  // hit before the screen swap, same TG / iOS pattern.
                  HapticFeedback.lightImpact();
                  context.push('/relative/details/${widget.relativeId}');
                }
              : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 20,
                backgroundImage: peerAvatarImage,
                child: peerAvatarImage == null
                    ? widget.isGroup
                        ? const Icon(Icons.group_outlined)
                        : Text(
                            widget.title.isNotEmpty ? widget.title[0] : '?')
                    : null,
              ),
              if (showOnlineDot)
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: _OnlinePulseDot(
                    color: const Color(0xFF2EBD68),
                    surfaceColor: Theme.of(context).colorScheme.surface,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Reference `.subhead h2`: Lora 19px / 600 / -0.01em letter
              // spacing — gives the chat title elegance vs the previous
              // 16px Manrope-default.
              Text(
                _resolvedTitle,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.serif(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.18,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              // Reference `.subhead .meta`: 12px ink-3 — secondary,
              // calmer than the previous bodySmall default. When the
              // peer is typing we strip the trailing "…" and append
              // animated _TypingDots so the indicator reads as live.
              _buildChatSubtitleRow(context),
            ],
          ),
        ),
      ],
    );
  }

  /// Smart subtitle row: peeks at [_typingUsers] to decide between the
  /// static text path (presence / member count) and the animated typing
  /// path (text + three pulsing dots, "печатает" instead of "печатает…").
  Widget _buildChatSubtitleRow(BuildContext context) {
    final isTyping = _typingUsers.isNotEmpty;
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final textStyle = AppTheme.sans(
      color: color,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 1.2,
    );
    final raw = _chatSubtitle();
    if (!isTyping) {
      return Text(
        raw,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textStyle,
      );
    }
    // Trim a trailing "…" or "..." so the animated dots take over the
    // ellipsis role and we don't end up with "печатает… ...".
    final trimmed = raw
        .replaceFirst(RegExp(r'\s*[…\.]+\s*$'), '')
        .trimRight();
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            trimmed,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        ),
        const SizedBox(width: 4),
        _TypingDots(color: color),
      ],
    );
  }

  List<Widget>? _buildChatAppBarActions() {
    if (_isSelectionMode) {
      return [
        IconButton(
          onPressed: _copySelectedMessages,
          tooltip: 'Скопировать выбранное',
          icon: const Icon(Icons.copy_all_rounded),
        ),
        IconButton(
          onPressed: _forwardSelectedMessages,
          tooltip: 'Переслать выбранное',
          icon: const Icon(Icons.forward_rounded),
        ),
        IconButton(
          onPressed: _deleteSelectedMessages,
          tooltip: 'Удалить выбранное',
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ];
    }

    if (_isSearchMode) {
      return null;
    }

    // Phone AppBar gets squeezed by 4 icons + avatar + long titles
    // ("Анастасия Эдуардовна Шуфляк"). Use compact visualDensity on
    // narrow widths so the icon buttons shrink from 48dp → ~40dp,
    // freeing ~32dp horizontal for the title text. Wide layouts keep
    // standard density.
    final isWide = _isWideLayout(context);
    final infoEnabled = !_isLoadingChatDetails && _chatDetails != null;
    final density =
        isWide ? VisualDensity.standard : VisualDensity.compact;
    return [
      if (_canStartCallInChat) ...[
        IconButton(
          visualDensity: density,
          onPressed: () => _startCall(CallMediaMode.audio),
          tooltip: widget.isGroup ? 'Групповой аудиозвонок' : 'Аудиозвонок',
          icon: const Icon(Icons.call_outlined),
        ),
        IconButton(
          visualDensity: density,
          onPressed: () => _startCall(CallMediaMode.video),
          tooltip: widget.isGroup ? 'Групповой видеозвонок' : 'Видеозвонок',
          icon: const Icon(Icons.videocam_outlined),
        ),
      ],
      IconButton(
        visualDensity: density,
        onPressed: _openSearch,
        tooltip: 'Поиск по чату',
        icon: const Icon(Icons.search),
      ),
      IconButton(
        visualDensity: density,
        onPressed: infoEnabled ? _openChatInfo : null,
        tooltip: 'О чате',
        icon: const Icon(Icons.info_outline),
      ),
    ];
  }

  Widget _buildChatBody(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: _isWideLayout(context) ? 1100 : double.infinity,
        ),
        child: Column(
          children: [
            const OfflineIndicator(),
            // Pinned banner slides down + fades in when a message gets
            // pinned, slides up + fades out when unpinned. AnimatedSize
            // collapses the row so the messages list grows / shrinks
            // smoothly with the banner.
            AnimatedSize(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return ClipRect(
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, -0.3),
                        end: Offset.zero,
                      ).animate(animation),
                      child: FadeTransition(
                        opacity: animation,
                        child: child,
                      ),
                    ),
                  );
                },
                child: _pinnedMessage == null
                    ? const SizedBox(
                        key: ValueKey('pinned-banner-hidden'),
                        height: 0,
                        width: double.infinity,
                      )
                    : KeyedSubtree(
                        key: const ValueKey('pinned-banner-shown'),
                        child: _buildPinnedMessageBanner(),
                      ),
              ),
            ),
            Expanded(child: _buildMessagesBody()),
            if (_recordingController.state == ChatRecordingState.locked &&
                !_isDirectChatBlocked)
              _buildRecordingArea()
            else
              _buildMessageInputArea(),
          ],
        ),
      ),
    );
  }
}
