part of 'chat_screen.dart';

class _VoicePlayerWidget extends StatefulWidget {
  const _VoicePlayerWidget({
    this.url,
    this.path,
    required this.isMe,
    this.initialDuration,
    this.semanticLabel,
  });

  final String? url;
  final String? path;
  final bool isMe;
  final Duration? initialDuration;
  final String? semanticLabel;

  @override
  State<_VoicePlayerWidget> createState() => _VoicePlayerWidgetState();
}

class _VoicePlayerWidgetState extends State<_VoicePlayerWidget> {
  late final AudioPlayer _player;
  PlayerState _playerState = PlayerState.stopped;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  StreamSubscription? _stateSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _posSub;
  StreamSubscription? _compSub;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _duration = widget.initialDuration ?? Duration.zero;
    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playerState = s);
    });
    _durationSub = _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _posSub = _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _compSub = _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playerState = PlayerState.stopped;
          _position = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _durationSub?.cancel();
    _posSub?.cancel();
    _compSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    try {
      if (widget.url != null) {
        await _player.play(UrlSource(widget.url!));
      } else if (widget.path != null) {
        await _player.play(DeviceFileSource(widget.path!));
      }
    } catch (e) {
      debugPrint('Error playing audio: $e');
    }
  }

  Future<void> _pause() async {
    await _player.pause();
  }

  @override
  Widget build(BuildContext context) {
    final isPlaying = _playerState == PlayerState.playing;
    final color = widget.isMe ? Colors.white : Colors.blue[700];
    final totalDuration = _duration > Duration.zero
        ? _duration
        : (widget.initialDuration ?? Duration.zero);
    final progressLabel = totalDuration > Duration.zero
        ? '${_formatDuration(_position)} / ${_formatDuration(totalDuration)}'
        : _formatDuration(_position);

    return Semantics(
      label: widget.semanticLabel ?? 'Голосовое сообщение',
      button: true,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: widget.isMe
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: isPlaying ? _pause : _play,
              icon: Icon(isPlaying
                  ? Icons.pause_circle_filled
                  : Icons.play_circle_filled),
              color: color,
              iconSize: 32,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 156,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.semanticLabel ?? 'Голосовое сообщение',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 2,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 4),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 10),
                      activeTrackColor: color,
                      inactiveTrackColor: color?.withValues(alpha: 0.3),
                      thumbColor: color,
                    ),
                    child: Slider(
                      value: _position.inMilliseconds.toDouble(),
                      max: totalDuration.inMilliseconds.toDouble() > 0
                          ? totalDuration.inMilliseconds.toDouble()
                          : 1.0,
                      onChanged: (val) {
                        _player.seek(Duration(milliseconds: val.toInt()));
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      progressLabel,
                      style: TextStyle(color: color, fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final min = d.inMinutes;
    final sec = d.inSeconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }
}

class _RemoteMediaGrid extends StatelessWidget {
  const _RemoteMediaGrid({
    required this.attachments,
    this.onOpenAttachment,
  });

  final List<ChatAttachment> attachments;
  final void Function(
          List<ChatAttachment> attachments, ChatAttachment attachment)?
      onOpenAttachment;

  @override
  Widget build(BuildContext context) {
    if (attachments.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 220,
          height: 220,
          child: _RemoteMediaTile(
            attachment: attachments.first,
            onTap: onOpenAttachment == null
                ? null
                : () => onOpenAttachment!(attachments, attachments.first),
          ),
        ),
      );
    }

    return SizedBox(
      width: 220,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: attachments
            .take(4)
            .map(
              (attachment) => ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 106,
                  height: 106,
                  child: _RemoteMediaTile(
                    attachment: attachment,
                    onTap: onOpenAttachment == null
                        ? null
                        : () => onOpenAttachment!(attachments, attachment),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _LocalMediaGrid extends StatelessWidget {
  const _LocalMediaGrid({
    required this.files,
    this.onOpenAttachment,
  });

  final List<XFile> files;
  final void Function(List<XFile> files, XFile file)? onOpenAttachment;

  @override
  Widget build(BuildContext context) {
    if (files.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 220,
          height: 220,
          child: _LocalMediaTile(
            file: files.first,
            onTap: onOpenAttachment == null
                ? null
                : () => onOpenAttachment!(files, files.first),
          ),
        ),
      );
    }

    return SizedBox(
      width: 220,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: files
            .take(4)
            .map(
              (file) => ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 106,
                  height: 106,
                  child: _LocalMediaTile(
                    file: file,
                    onTap: onOpenAttachment == null
                        ? null
                        : () => onOpenAttachment!(files, file),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _HighlightedMessageText extends StatelessWidget {
  const _HighlightedMessageText({
    required this.text,
    required this.query,
    required this.color,
  });

  final String text;
  final String query;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 16,
        ),
      );
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = normalizedQuery.toLowerCase();
    final spans = <TextSpan>[];
    var currentIndex = 0;

    while (currentIndex < text.length) {
      final nextMatch = lowerText.indexOf(lowerQuery, currentIndex);
      if (nextMatch == -1) {
        spans.add(
          TextSpan(
            text: text.substring(currentIndex),
            style: TextStyle(color: color),
          ),
        );
        break;
      }
      if (nextMatch > currentIndex) {
        spans.add(
          TextSpan(
            text: text.substring(currentIndex, nextMatch),
            style: TextStyle(color: color),
          ),
        );
      }
      final matchEnd = nextMatch + normalizedQuery.length;
      spans.add(
        TextSpan(
          text: text.substring(nextMatch, matchEnd),
          style: TextStyle(
            color: color,
            backgroundColor: Colors.amber.withValues(alpha: 0.55),
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      currentIndex = matchEnd;
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 16),
        children: spans,
      ),
    );
  }
}

class _LocalImagePreview extends StatelessWidget {
  const _LocalImagePreview({required this.file});

  final XFile file;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: file.readAsBytes(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const ColoredBox(
            color: Color(0x11000000),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        return Image.memory(
          snapshot.data!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const ColoredBox(
            color: Color(0x11000000),
            child: Center(child: Icon(Icons.broken_image_outlined)),
          ),
        );
      },
    );
  }
}

class _LocalMediaTile extends StatelessWidget {
  const _LocalMediaTile({
    required this.file,
    this.onTap,
  });

  final XFile file;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final kind = _attachmentKindFromXFile(file);
    if (_isVideoNoteFileName(file.name)) {
      return _VideoNoteTile(
        durationLabel: _durationFromAttachmentName(file.name) == null
            ? null
            : _formatAttachmentDuration(
                _durationFromAttachmentName(file.name)!),
        label: 'Кружок',
        onTap: onTap,
      );
    }
    if (kind == _ChatAttachmentKind.image) {
      return InkWell(
        onTap: onTap,
        child: _LocalImagePreview(file: file),
      );
    }
    if (kind == _ChatAttachmentKind.audio) {
      return const _AttachmentPlaceholder(
        icon: Icons.mic_none_outlined,
        label: 'Голосовое сообщение',
      );
    }

    return InkWell(
      onTap: onTap,
      child: _AttachmentPlaceholder(
        icon: kind == _ChatAttachmentKind.video
            ? Icons.videocam_outlined
            : Icons.insert_drive_file_outlined,
        label: kind == _ChatAttachmentKind.video
            ? 'Видео'
            : _displayName(file.name),
      ),
    );
  }
}

class _RemoteMediaTile extends StatelessWidget {
  const _RemoteMediaTile({
    required this.attachment,
    this.onTap,
  });

  final ChatAttachment attachment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final kind = attachment.type == ChatAttachmentType.file
        ? _attachmentKindFromName(attachment.fileName, attachment.url)
        : _chatAttachmentKindFromType(attachment.type);
    if (attachment.isVideoNote) {
      return _VideoNoteTile(
        previewUrl: attachment.thumbnailUrl,
        durationLabel: attachment.durationMs == null
            ? null
            : _formatAttachmentDuration(
                Duration(milliseconds: attachment.durationMs!),
              ),
        label: 'Кружок',
        onTap: onTap,
      );
    }
    if (kind == _ChatAttachmentKind.image) {
      return InkWell(
        onTap: onTap,
        child: Image.network(
          attachment.thumbnailUrl ?? attachment.url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const _AttachmentPlaceholder(
            icon: Icons.broken_image_outlined,
            label: 'Файл',
          ),
        ),
      );
    }
    if (kind == _ChatAttachmentKind.audio) {
      return const _AttachmentPlaceholder(
        icon: Icons.mic_none_outlined,
        label: 'Голосовое сообщение',
      );
    }

    return InkWell(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (kind == _ChatAttachmentKind.video &&
              attachment.thumbnailUrl != null &&
              attachment.thumbnailUrl!.isNotEmpty)
            Image.network(
              attachment.thumbnailUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(
                alpha: kind == _ChatAttachmentKind.video ? 0.28 : 0.08,
              ),
            ),
            child: _AttachmentPlaceholder(
              icon: kind == _ChatAttachmentKind.video
                  ? Icons.play_circle_outline_rounded
                  : Icons.insert_drive_file_outlined,
              label: kind == _ChatAttachmentKind.video
                  ? 'Видео'
                  : _displayName(attachment.fileName ?? attachment.url),
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoNoteTile extends StatelessWidget {
  const _VideoNoteTile({
    required this.label,
    this.previewUrl,
    this.durationLabel,
    this.onTap,
  });

  final String label;
  final String? previewUrl;
  final String? durationLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: onTap != null,
      child: ClipOval(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (previewUrl != null && previewUrl!.trim().isNotEmpty)
                  Image.network(
                    previewUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.black.withValues(alpha: 0.18),
                        Colors.black.withValues(alpha: 0.42),
                      ],
                    ),
                  ),
                ),
                Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.42),
                      shape: BoxShape.circle,
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
                if (durationLabel != null && durationLabel!.isNotEmpty)
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.58),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          durationLabel!,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AttachmentPlaceholder extends StatelessWidget {
  const _AttachmentPlaceholder({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0x11000000),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReactionGroup {
  const _ReactionGroup({
    required this.emoji,
    required this.count,
    required this.isMine,
  });

  final String emoji;
  final int count;
  final bool isMine;
}

class _ReactionPill extends StatelessWidget {
  const _ReactionPill({
    required this.reaction,
    required this.isMe,
    this.onTap,
  });

  final _ReactionGroup reaction;
  final bool isMe;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textColor =
        isMe ? Colors.white.withValues(alpha: 0.95) : Colors.black87;
    final selectedColor = isMe
        ? Colors.white.withValues(alpha: 0.18)
        : Colors.blue.withValues(alpha: 0.14);
    final defaultColor = isMe
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.72);

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: reaction.isMine ? selectedColor : defaultColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: reaction.isMine
                ? (isMe
                    ? Colors.white.withValues(alpha: 0.45)
                    : Colors.blue.withValues(alpha: 0.28))
                : Colors.transparent,
          ),
        ),
        child: Text(
          '${reaction.emoji} ${reaction.count}',
          style: TextStyle(
            color: textColor,
            fontSize: 12,
            fontWeight: reaction.isMine ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

enum _MessageAction {
  react,
  reply,
  forward,
  select,
  pin,
  edit,
  copy,
  report,
  block,
  retry,
  delete
}

class _ContextMenuActionItem<T> {
  const _ContextMenuActionItem({
    required this.label,
    required this.icon,
    required this.value,
    this.isDestructive = false,
  });

  final String label;
  final IconData icon;
  final T value;
  final bool isDestructive;
}

class _MessageSheetSelection {
  const _MessageSheetSelection({
    required this.action,
    this.emoji,
  });

  final _MessageAction action;
  final String? emoji;
}

class _SafetyReasonChoice {
  const _SafetyReasonChoice({
    required this.reason,
    required this.label,
  });

  final String reason;
  final String label;
}

class _SafetyActionDraft {
  const _SafetyActionDraft({
    required this.reason,
    required this.details,
  });

  final String reason;
  final String details;
}

class _ForwardBatchDraft {
  const _ForwardBatchDraft({
    required this.items,
  });

  final List<_ForwardDraft> items;
}

class _SelectedMessageEntry {
  _SelectedMessageEntry.remote({
    required ChatMessage message,
    required this.displayName,
  })  : remoteMessageId = message.id,
        outgoingLocalId = null,
        senderId = message.senderId,
        text = message.text,
        timestamp = message.timestamp,
        attachments = message.attachments;

  _SelectedMessageEntry.outgoing({
    required _OutgoingMessage message,
    required this.displayName,
    required List<ChatAttachment> normalizedAttachments,
  })  : remoteMessageId = null,
        outgoingLocalId = message.localId,
        senderId = message.senderId,
        text = message.text,
        timestamp = message.timestamp,
        attachments = normalizedAttachments;

  final String? remoteMessageId;
  final String? outgoingLocalId;
  final String senderId;
  final String displayName;
  final String text;
  final DateTime timestamp;
  final List<ChatAttachment> attachments;

  bool canDelete(String currentUserId) {
    if (remoteMessageId != null) {
      return senderId == currentUserId;
    }
    return true;
  }
}

class _AttachmentPreviewItem {
  const _AttachmentPreviewItem.remote({
    required this.id,
    required this.kind,
    required this.source,
    required this.displayName,
    this.thumbnailUrl,
    this.senderLabel,
    this.timestamp,
    this.caption,
  })  : file = null,
        isRemote = true;

  const _AttachmentPreviewItem.local({
    required this.id,
    required this.kind,
    required this.file,
    required this.displayName,
    this.senderLabel,
    this.timestamp,
    this.caption,
  })  : source = null,
        thumbnailUrl = null,
        isRemote = false;

  final String id;
  final _ChatAttachmentKind kind;
  final String? source;
  final String? thumbnailUrl;
  final XFile? file;
  final String displayName;
  final bool isRemote;
  final String? senderLabel;
  final DateTime? timestamp;
  final String? caption;

  bool get isVisual =>
      kind == _ChatAttachmentKind.image || kind == _ChatAttachmentKind.video;

  String? get trimmedCaption {
    final value = caption?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }
}

class _DesktopMessageContextMenu<T> extends StatelessWidget {
  const _DesktopMessageContextMenu({
    required this.actions,
    required this.onActionSelected,
    this.reactions = const <String>[],
    this.onReactionSelected,
  });

  final List<_ContextMenuActionItem<T>> actions;
  final List<String> reactions;
  final ValueChanged<T> onActionSelected;
  final ValueChanged<String>? onReactionSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF1F1F22) : Colors.white;
    final reactionBarColor =
        isDark ? const Color(0xFF2A2A2F) : const Color(0xFFF4F5F8);
    final shadowColor = Colors.black.withValues(alpha: isDark ? 0.34 : 0.16);

    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (reactions.isNotEmpty && onReactionSelected != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: reactionBarColor,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: shadowColor,
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: reactions
                      .map(
                        (emoji) => InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => onReactionSelected?.call(emoji),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 26, height: 1),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            if (reactions.isNotEmpty && onReactionSelected != null)
              const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: shadowColor,
                    blurRadius: 30,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var index = 0; index < actions.length; index++) ...[
                      _DesktopMessageContextMenuTile<T>(
                        item: actions[index],
                        onTap: () => onActionSelected(actions[index].value),
                      ),
                      if (index != actions.length - 1)
                        Divider(
                          height: 1,
                          indent: 54,
                          endIndent: 16,
                          color: theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.32),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopMessageContextMenuTile<T> extends StatelessWidget {
  const _DesktopMessageContextMenuTile({
    required this.item,
    required this.onTap,
  });

  final _ContextMenuActionItem<T> item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foregroundColor = item.isDestructive
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              child: Icon(
                item.icon,
                size: 21,
                color: foregroundColor,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                item.label,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentViewerDialog extends StatefulWidget {
  const _AttachmentViewerDialog({
    required this.items,
    required this.initialIndex,
    required this.onOpenExternally,
    required this.onDownload,
  });

  final List<_AttachmentPreviewItem> items;
  final int initialIndex;
  final Future<void> Function(_AttachmentPreviewItem item) onOpenExternally;
  final Future<void> Function(_AttachmentPreviewItem item) onDownload;

  @override
  State<_AttachmentViewerDialog> createState() =>
      _AttachmentViewerDialogState();
}

class _AttachmentViewerDialogState extends State<_AttachmentViewerDialog> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.items.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _goToPage(int index) async {
    if (index < 0 || index >= widget.items.length || index == _currentIndex) {
      return;
    }
    await _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _goToPrevious() {
    unawaited(_goToPage(_currentIndex - 1));
  }

  void _goToNext() {
    unawaited(_goToPage(_currentIndex + 1));
  }

  @override
  Widget build(BuildContext context) {
    final currentItem = widget.items[_currentIndex];
    final metadataLabel = <String>[
      if (currentItem.senderLabel != null &&
          currentItem.senderLabel!.isNotEmpty)
        currentItem.senderLabel!,
      if (currentItem.timestamp != null)
        DateFormat('dd.MM.yyyy H:mm', 'ru').format(currentItem.timestamp!),
    ].join(' • ');

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): _goToPrevious,
        const SingleActivator(LogicalKeyboardKey.arrowRight): _goToNext,
      },
      child: Dialog.fullscreen(
        backgroundColor: Colors.black.withValues(alpha: 0.92),
        child: Focus(
          autofocus: true,
          child: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            tooltip: 'Закрыть',
                            icon: const Icon(Icons.close, color: Colors.white),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  currentItem.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                if (metadataLabel.isNotEmpty)
                                  Text(
                                    metadataLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.72),
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            '${_currentIndex + 1} / ${widget.items.length}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.82),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: currentItem.isRemote
                                ? 'Открыть оригинал'
                                : 'Открыть файл',
                            onPressed: () =>
                                widget.onOpenExternally(currentItem),
                            icon: const Icon(
                              Icons.open_in_new,
                              color: Colors.white,
                            ),
                          ),
                          IconButton(
                            tooltip: supportsChatAttachmentDownload
                                ? 'Скачать'
                                : 'Открыть',
                            onPressed: () => widget.onDownload(currentItem),
                            icon: Icon(
                              supportsChatAttachmentDownload
                                  ? Icons.download_rounded
                                  : Icons.file_download_outlined,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: widget.items.length,
                        onPageChanged: (index) {
                          setState(() {
                            _currentIndex = index;
                          });
                        },
                        itemBuilder: (context, index) {
                          return _AttachmentViewerPage(
                              item: widget.items[index]);
                        },
                      ),
                    ),
                    if (currentItem.trimmedCaption != null ||
                        metadataLabel.isNotEmpty)
                      _AttachmentViewerDetails(
                        item: currentItem,
                        metadataLabel: metadataLabel,
                      ),
                    if (widget.items.length > 1)
                      _AttachmentViewerThumbnailStrip(
                        items: widget.items,
                        currentIndex: _currentIndex,
                        onSelect: _goToPage,
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Text(
                        'Esc закрыть • ← → листать',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.48),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                if (widget.items.length > 1 && _currentIndex > 0)
                  Positioned(
                    left: 20,
                    top: 0,
                    bottom: 92,
                    child: Center(
                      child: IconButton.filledTonal(
                        tooltip: 'Предыдущее вложение',
                        onPressed: _goToPrevious,
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                    ),
                  ),
                if (widget.items.length > 1 &&
                    _currentIndex < widget.items.length - 1)
                  Positioned(
                    right: 20,
                    top: 0,
                    bottom: 92,
                    child: Center(
                      child: IconButton.filledTonal(
                        tooltip: 'Следующее вложение',
                        onPressed: _goToNext,
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AttachmentViewerPage extends StatelessWidget {
  const _AttachmentViewerPage({required this.item});

  final _AttachmentPreviewItem item;

  @override
  Widget build(BuildContext context) {
    Widget content;
    switch (item.kind) {
      case _ChatAttachmentKind.image:
        content = item.isRemote
            ? InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: Image.network(
                  item.source!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      _AttachmentViewerPlaceholder(item: item),
                ),
              )
            : FutureBuilder<Uint8List>(
                future: item.file!.readAsBytes(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4,
                    child: Image.memory(
                      snapshot.data!,
                      fit: BoxFit.contain,
                    ),
                  );
                },
              );
        break;
      case _ChatAttachmentKind.video:
        final source = item.isRemote ? item.source! : item.file?.path;
        content = source == null || source.trim().isEmpty
            ? _AttachmentViewerPlaceholder(item: item)
            : _AttachmentVideoPlayer(
                source: source,
                isRemoteSource: item.isRemote,
                posterUrl: item.thumbnailUrl,
              );
        break;
      case _ChatAttachmentKind.audio:
      case _ChatAttachmentKind.other:
        content = _AttachmentViewerPlaceholder(item: item);
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: Center(child: content),
    );
  }
}

class _AttachmentViewerDetails extends StatelessWidget {
  const _AttachmentViewerDetails({
    required this.item,
    required this.metadataLabel,
  });

  final _AttachmentPreviewItem item;
  final String metadataLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (metadataLabel.isNotEmpty)
                Text(
                  metadataLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (metadataLabel.isNotEmpty && item.trimmedCaption != null)
                const SizedBox(height: 6),
              if (item.trimmedCaption != null)
                Text(
                  item.trimmedCaption!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentViewerThumbnailStrip extends StatelessWidget {
  const _AttachmentViewerThumbnailStrip({
    required this.items,
    required this.currentIndex,
    required this.onSelect,
  });

  final List<_AttachmentPreviewItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) => _AttachmentViewerThumbnail(
          item: items[index],
          isSelected: index == currentIndex,
          onTap: () => onSelect(index),
        ),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: items.length,
      ),
    );
  }
}

class _AttachmentViewerThumbnail extends StatelessWidget {
  const _AttachmentViewerThumbnail({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final _AttachmentPreviewItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor =
        isSelected ? Colors.white : Colors.white.withValues(alpha: 0.18);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 64,
        height: 64,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
          color: Colors.white.withValues(alpha: 0.08),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _AttachmentViewerThumbnailPreview(item: item),
            if (item.kind == _ChatAttachmentKind.video)
              Align(
                alignment: Alignment.center,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.48),
                    shape: BoxShape.circle,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentViewerThumbnailPreview extends StatelessWidget {
  const _AttachmentViewerThumbnailPreview({required this.item});

  final _AttachmentPreviewItem item;

  @override
  Widget build(BuildContext context) {
    if (item.kind == _ChatAttachmentKind.image && item.isRemote) {
      return Image.network(
        item.thumbnailUrl ?? item.source ?? '',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _AttachmentViewerThumbnailFallback(
          item: item,
        ),
      );
    }

    if (item.kind == _ChatAttachmentKind.image && item.file != null) {
      return FutureBuilder<Uint8List>(
        future: item.file!.readAsBytes(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.cover,
          );
        },
      );
    }

    if (item.kind == _ChatAttachmentKind.video &&
        item.thumbnailUrl != null &&
        item.thumbnailUrl!.isNotEmpty) {
      return Image.network(
        item.thumbnailUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _AttachmentViewerThumbnailFallback(
          item: item,
        ),
      );
    }

    return _AttachmentViewerThumbnailFallback(item: item);
  }
}

class _AttachmentViewerThumbnailFallback extends StatelessWidget {
  const _AttachmentViewerThumbnailFallback({required this.item});

  final _AttachmentPreviewItem item;

  @override
  Widget build(BuildContext context) {
    late final IconData icon;
    switch (item.kind) {
      case _ChatAttachmentKind.image:
        icon = Icons.image_outlined;
        break;
      case _ChatAttachmentKind.video:
        icon = Icons.videocam_outlined;
        break;
      case _ChatAttachmentKind.audio:
        icon = Icons.mic_none_outlined;
        break;
      case _ChatAttachmentKind.other:
        icon = Icons.insert_drive_file_outlined;
        break;
    }
    return ColoredBox(
      color: Colors.white.withValues(alpha: 0.06),
      child: Center(
        child: Icon(
          icon,
          color: Colors.white.withValues(alpha: 0.82),
        ),
      ),
    );
  }
}

class _AttachmentViewerPlaceholder extends StatelessWidget {
  const _AttachmentViewerPlaceholder({required this.item});

  final _AttachmentPreviewItem item;

  @override
  Widget build(BuildContext context) {
    final icon = item.kind == _ChatAttachmentKind.video
        ? Icons.videocam_outlined
        : Icons.insert_drive_file_outlined;
    final label = item.kind == _ChatAttachmentKind.video ? 'Видео' : 'Файл';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: Colors.white),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.displayName,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentVideoPlayer extends StatefulWidget {
  const _AttachmentVideoPlayer({
    required this.source,
    required this.isRemoteSource,
    this.posterUrl,
  });

  final String source;
  final bool isRemoteSource;
  final String? posterUrl;

  @override
  State<_AttachmentVideoPlayer> createState() => _AttachmentVideoPlayerState();
}

class _AttachmentVideoPlayerState extends State<_AttachmentVideoPlayer> {
  VideoPlayerController? _controller;
  Future<void>? _initializeFuture;

  @override
  void initState() {
    super.initState();
    final uri = _videoSourceUri(widget.source);
    _controller = widget.isRemoteSource
        ? VideoPlayerController.networkUrl(uri)
        : VideoPlayerController.contentUri(uri);
    _initializeFuture = _controller!.initialize();
    _controller!.setLooping(true);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<void>(
      future: _initializeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Stack(
            alignment: Alignment.center,
            children: [
              if (widget.posterUrl != null && widget.posterUrl!.isNotEmpty)
                Image.network(
                  widget.posterUrl!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              const CircularProgressIndicator(),
            ],
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 560),
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio == 0
                    ? 16 / 9
                    : controller.value.aspectRatio,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: Colors.black,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        VideoPlayer(controller),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(
                              alpha: controller.value.isPlaying ? 0.06 : 0.22,
                            ),
                          ),
                          child: const SizedBox.expand(),
                        ),
                        IconButton.filledTonal(
                          onPressed: _togglePlayback,
                          icon: Icon(
                            controller.value.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 28,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Slider(
              value: controller.value.position.inMilliseconds
                  .clamp(0, controller.value.duration.inMilliseconds)
                  .toDouble(),
              max: controller.value.duration.inMilliseconds <= 0
                  ? 1
                  : controller.value.duration.inMilliseconds.toDouble(),
              onChanged: (value) {
                controller.seekTo(Duration(milliseconds: value.round()));
              },
            ),
          ],
        );
      },
    );
  }

  Uri _videoSourceUri(String value) {
    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.hasScheme) {
      return parsed;
    }
    return Uri.file(value);
  }
}
