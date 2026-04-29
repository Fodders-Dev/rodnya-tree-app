part of 'chat_screen.dart';

extension _ChatScreenScaffoldSections on _ChatScreenState {
  PreferredSizeWidget _buildChatAppBar(BuildContext context) {
    return AppBar(
      leading: IconButton(
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

    return Row(
      children: [
        GestureDetector(
          onTap: !widget.isGroup &&
                  widget.relativeId != null &&
                  widget.relativeId!.isNotEmpty
              ? () => context.push('/relative/details/${widget.relativeId}')
              : null,
          child: CircleAvatar(
            radius: 20,
            backgroundImage: peerAvatarImage,
            child: peerAvatarImage == null
                ? widget.isGroup
                    ? const Icon(Icons.group_outlined)
                    : Text(widget.title.isNotEmpty ? widget.title[0] : '?')
                : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _resolvedTitle,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _chatSubtitle(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
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

    return [
      if (_isCurrentDirectChat) ...[
        IconButton(
          onPressed: () => _startCall(CallMediaMode.audio),
          tooltip: 'Аудиозвонок',
          icon: const Icon(Icons.call_outlined),
        ),
        IconButton(
          onPressed: () => _startCall(CallMediaMode.video),
          tooltip: 'Видеозвонок',
          icon: const Icon(Icons.videocam_outlined),
        ),
      ],
      IconButton(
        onPressed: _openSearch,
        tooltip: 'Поиск по чату',
        icon: const Icon(Icons.search),
      ),
      IconButton(
        onPressed: _isLoadingChatDetails || _chatDetails == null
            ? null
            : _openChatInfo,
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
            if (_pinnedMessage != null) _buildPinnedMessageBanner(),
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
