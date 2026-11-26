part of '../chat_screen.dart';

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.isMe,
    required this.text,
    required this.timeLabel,
    required this.isRead,
    required this.isDelivered,
    required this.isPinned,
    required this.isHighlighted,
    this.highlightQuery = '',
    this.senderLabel,
    this.onSenderTap,
    this.groupedWithPrev = false,
    this.remoteAttachments = const <ChatAttachment>[],
    this.localAttachments = const <XFile>[],
    this.localAttachmentStatuses,
    this.replyTo,
    this.onReplyTap,
    this.reactionGroups = const <_ReactionGroup>[],
    this.onReactionTap,
    this.footerLabel,
    this.showSelectionMarker = false,
    this.isSelected = false,
    this.onOpenRemoteAttachment,
    this.onOpenLocalAttachment,
  });

  final bool isMe;
  final String text;
  final String timeLabel;
  final bool isRead;
  final bool isDelivered;
  final bool isPinned;
  final bool isHighlighted;
  final String highlightQuery;
  final String? senderLabel;
  final VoidCallback? onSenderTap;
  final bool groupedWithPrev;
  final List<ChatAttachment> remoteAttachments;
  final List<XFile> localAttachments;

  /// Пофайловые статусы загрузки (только исходящий optimistic-баббл;
  /// null у remote-сообщений — оверлеев нет). Индексы соответствуют
  /// [localAttachments].
  final List<ChatAttachmentUploadStatus>? localAttachmentStatuses;
  final ChatReplyReference? replyTo;
  final VoidCallback? onReplyTap;
  final List<_ReactionGroup> reactionGroups;
  final ValueChanged<String>? onReactionTap;
  final String? footerLabel;
  final bool showSelectionMarker;
  final bool isSelected;
  final void Function(
          List<ChatAttachment> attachments, ChatAttachment attachment)?
      onOpenRemoteAttachment;
  final void Function(List<XFile> files, XFile file)? onOpenLocalAttachment;

  /// True when the message is a "naked" video note — single circular
  /// kruzhok and nothing else. In TG / WhatsApp such messages render
  /// as a free-floating circle with no bubble background, time stamp,
  /// or border. Detection: empty text + no reply + a single video-note
  /// attachment on either remote or local side.
  bool get _isVideoNoteOnly {
    if (text.trim().isNotEmpty) return false;
    if (replyTo != null) return false;
    if (remoteAttachments.length == 1 &&
        localAttachments.isEmpty &&
        remoteAttachments.first.isVideoNote) {
      return true;
    }
    if (localAttachments.length == 1 && remoteAttachments.isEmpty) {
      // Detect by file name prefix — same heuristic the host state
      // uses for `_isVideoNoteFile` but inlined here so the bubble
      // doesn't depend on the parent state class.
      final raw = localAttachments.first.name.trim().toLowerCase();
      if (raw.startsWith('video_note_') || raw.startsWith('video-note-')) {
        return true;
      }
    }
    return false;
  }

  /// True when the message is "naked" media — only photos / videos,
  /// no text, no reply, no reactions to display via the meta footer.
  /// User-reported: «у картинок нет границ сообщения. Картинка (и
  /// прочее медиа) без рамок как правило отправляется. Рамки нужны
  /// по факту, чтобы текст читать». Same TG / WA behaviour: pure
  /// media floats on the canvas without a bubble around it.
  bool get _isNakedMediaOnly {
    if (text.trim().isNotEmpty) return false;
    if (replyTo != null) return false;
    final hasNonMediaRemote = remoteAttachments.any((a) =>
        a.type != ChatAttachmentType.image &&
        a.type != ChatAttachmentType.video);
    if (hasNonMediaRemote) return false;
    final hasNonMediaLocal = localAttachments.any((file) {
      final kind = _attachmentKindFromXFile(file);
      return kind != _ChatAttachmentKind.image &&
          kind != _ChatAttachmentKind.video;
    });
    if (hasNonMediaLocal) return false;
    final hasAnyMedia =
        remoteAttachments.isNotEmpty || localAttachments.isNotEmpty;
    return hasAnyMedia;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // WhatsApp/Telegram-inspired bubble palette tuned to the warm teal brand.
    final Color bubbleColor;
    final Color onBubbleColor;
    final Color metaColor;
    final List<BoxShadow> bubbleShadow;
    final BoxBorder? bubbleBorder;

    if (isMe) {
      // Outgoing: solid accent gradient — confident, on-brand.
      bubbleColor = scheme.primary;
      onBubbleColor = scheme.onPrimary;
      metaColor = scheme.onPrimary.withValues(alpha: 0.78);
      bubbleShadow = [
        BoxShadow(
          color: scheme.primary.withValues(alpha: isDark ? 0.32 : 0.22),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ];
      bubbleBorder = null;
    } else {
      // Incoming: glassy surface tile with hairline border + soft drop shadow.
      bubbleColor = isDark
          ? scheme.surfaceContainerHigh.withValues(alpha: 0.92)
          : scheme.surface.withValues(alpha: 0.94);
      onBubbleColor = scheme.onSurface;
      metaColor = scheme.onSurfaceVariant;
      bubbleShadow = [
        BoxShadow(
          color: scheme.shadow.withValues(alpha: isDark ? 0.32 : 0.06),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ];
      bubbleBorder = Border.all(
        color: scheme.outlineVariant.withValues(alpha: isDark ? 0.4 : 0.55),
        width: 0.7,
      );
    }

    // Telegram-style inline timestamp: for short, plain-text messages the meta
    // (time + read tick) sits in a Wrap next to the text, so it tucks onto the
    // last line (wrapping below only when there's no room). The message text
    // stays a clean Text widget (no embedded WidgetSpan) so search / copy /
    // a11y / find.text are unaffected. Long / reaction / media / reply bubbles
    // keep the footer meta.
    final inlineMeta = text.isNotEmpty &&
        text.trim().length <= 64 &&
        replyTo == null &&
        remoteAttachments.isEmpty &&
        localAttachments.isEmpty &&
        reactionGroups.isEmpty &&
        !_isNakedMediaOnly &&
        !_isVideoNoteOnly;
    final metaRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          timeLabel,
          style: theme.textTheme.labelSmall?.copyWith(
            color: metaColor,
            // Плотность (чанк 22): было 12.5 — спека держит время ровно
            // на 12sp (labelSmall/11 мелковат, но 12.5 уже не давало
            // экономии против явного значения из тикета).
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (isMe) ...[
          const SizedBox(width: 4),
          _ReadReceiptTick(
            isRead: isRead,
            isDelivered: isDelivered,
            readColor: const Color(0xFF6FC4FF),
            dimColor: scheme.onPrimary.withValues(alpha: 0.72),
          ),
        ],
      ],
    );

    final highlightBorder = isHighlighted
        ? Border.all(color: scheme.tertiary, width: 1.6)
        : isSelected
            ? Border.all(color: scheme.primary, width: 1.4)
            : bubbleBorder;

    final outgoingGradient = isMe
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primary,
              Color.alphaBlend(
                Colors.black.withValues(alpha: 0.08),
                scheme.primary,
              ),
            ],
          )
        : null;

    return Padding(
      // Плотность (чанк 22): зазор между пузырями — спека держит его на
      // 2dp внутри одного автора / 8dp при смене автора. Раньше верх и
      // низ были симметричны и оба зависели ТОЛЬКО от [groupedWithPrev]
      // этого же сообщения — а зазор между двумя пузырями фактически
      // равен bottom(верхнего) + top(нижнего), где bottom верхнего
      // сообщения отражает его СОБСТВЕННУЮ группировку (с сообщением
      // ЕЩЁ выше), а не то, продолжает ли его текущее. На стыке рана
      // (последнее сообщение серии само было «grouped» сверху) это
      // тихо давало короткий зазор вместо разделительного. Фикс: низ —
      // константа (1dp), весь зазор кодирует top ТЕКУЩЕГО сообщения,
      // которое как раз знает, продолжает ли оно автора над собой.
      padding: EdgeInsets.fromLTRB(
        10,
        groupedWithPrev ? 1 : 7,
        10,
        1,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Selection marker slides in/out when selection mode toggles
          // — AnimatedSize collapses the slot to 0-width when hidden so
          // bubbles shift back to flush-left without a jump. Inner
          // ScaleTransition + FadeTransition makes the circle "pop"
          // instead of just appearing.
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.centerLeft,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutBack,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
              child: !showSelectionMarker
                  ? const SizedBox(
                      key: ValueKey('selection-marker-hidden'),
                      width: 0,
                      height: 24,
                    )
                  : Padding(
                      key: const ValueKey('selection-marker-shown'),
                      padding: const EdgeInsets.only(right: 8),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              isSelected ? scheme.primary : Colors.transparent,
                          border: Border.all(
                            color: isSelected
                                ? scheme.primary
                                : scheme.outline.withValues(alpha: 0.72),
                            width: 2,
                          ),
                        ),
                        child: isSelected
                            ? Icon(
                                Icons.check_rounded,
                                size: 16,
                                color: scheme.onPrimary,
                              )
                            : null,
                      ),
                    ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.78,
                ),
                // AnimatedContainer so the highlight border (when the
                // user taps a reply preview and we focus the original)
                // fades in / out over 360ms instead of jumping. Picks
                // up boxShadow + decoration changes too — pinned /
                // selected transitions look smoother for free.
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 360),
                  curve: Curves.easeOutCubic,
                  // Плотность (чанк 22): паддинг 6/12 (было 6/11; ревью вернуло 6 верт —
                  // однострочное сообщение 52dp вместо 55) — Telegram `.msg`,
                  // радиус 16 + 6 на «хвостовом» углу без изменений.
                  //
                  // Special case: a "naked" кружочек skips the bubble
                  // entirely (no padding, no background, no border) and
                  // renders just the round video tile — same TG / WA
                  // behaviour where video notes float on the canvas.
                  // Naked media (photos / videos with no text, no
                  // reply, no other content) drops the bubble like
                  // video notes do — TG / WA convention.
                  padding: (_isVideoNoteOnly || _isNakedMediaOnly)
                      ? EdgeInsets.zero
                      : const EdgeInsets.fromLTRB(12, 6, 12, 6),
                  decoration: (_isVideoNoteOnly || _isNakedMediaOnly)
                      ? null
                      : BoxDecoration(
                          color: outgoingGradient == null ? bubbleColor : null,
                          gradient: outgoingGradient,
                          border: highlightBorder,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(isMe ? 16 : 6),
                            bottomRight: Radius.circular(isMe ? 6 : 16),
                          ),
                          boxShadow: bubbleShadow,
                        ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (senderLabel != null && senderLabel!.isNotEmpty) ...[
                        _ChatSenderLabel(
                          label: senderLabel!,
                          color: isMe
                              ? scheme.onPrimary.withValues(alpha: 0.92)
                              : scheme.primary,
                          onTap: onSenderTap,
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (isPinned) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.push_pin,
                              size: 12,
                              color: metaColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Закреплено',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: metaColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                      ],
                      if (replyTo != null) ...[
                        _ReplyQuoteCard(
                          reply: replyTo!,
                          isMe: isMe,
                          onTap: onReplyTap,
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (remoteAttachments.isNotEmpty) ...[
                        _buildRemoteAttachments(context),
                        if (!_isNakedMediaOnly && !_isVideoNoteOnly)
                          const SizedBox(height: 8),
                      ],
                      if (localAttachments.isNotEmpty) ...[
                        _buildLocalAttachments(context),
                        if (!_isNakedMediaOnly && !_isVideoNoteOnly)
                          const SizedBox(height: 8),
                      ],
                      if (text.isNotEmpty)
                        inlineMeta
                            ? Wrap(
                                crossAxisAlignment: WrapCrossAlignment.end,
                                spacing: 6,
                                runSpacing: 2,
                                children: [
                                  _HighlightedMessageText(
                                    text: text,
                                    query: highlightQuery,
                                    color: onBubbleColor,
                                  ),
                                  metaRow,
                                ],
                              )
                            : _HighlightedMessageText(
                                text: text,
                                query: highlightQuery,
                                color: onBubbleColor,
                              ),
                      if (text.isEmpty &&
                          remoteAttachments.isEmpty &&
                          localAttachments.isEmpty)
                        Text(
                          'Сообщение',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: onBubbleColor,
                          ),
                        ),
                      if (reactionGroups.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        // Плотность (чанк 22): зазор чипов 4dp (было 6) —
                        // спека: «ряд чипов 24dp под пузырём с зазором
                        // 4dp».
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: reactionGroups
                              .map(
                                (reaction) => _ReactionPill(
                                  reaction: reaction,
                                  isMe: isMe,
                                  onTap: onReactionTap == null
                                      ? null
                                      : () => onReactionTap!(reaction.emoji),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      // Footer meta (timestamp + read tick) — only when it was
                      // NOT inlined next to the text above (see inlineMeta).
                      // Naked media skips it entirely (floats as just media);
                      // footerLabel shows below regardless of inline vs footer.
                      if (!inlineMeta &&
                          !_isNakedMediaOnly &&
                          !_isVideoNoteOnly) ...[
                        const SizedBox(height: 2),
                        metaRow,
                      ] else if (!inlineMeta && _isNakedMediaOnly) ...[
                        const SizedBox(height: 4),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            child: DefaultTextStyle.merge(
                              style: const TextStyle(color: Colors.white),
                              child: IconTheme.merge(
                                data: const IconThemeData(color: Colors.white),
                                child: metaRow,
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (footerLabel != null &&
                          footerLabel!.isNotEmpty &&
                          !_isNakedMediaOnly &&
                          !_isVideoNoteOnly) ...[
                        const SizedBox(height: 2),
                        Text(
                          footerLabel!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: metaColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemoteAttachments(BuildContext context) {
    final audio = remoteAttachments
        .where((a) => a.type == ChatAttachmentType.audio)
        .toList();
    final videoNotes = remoteAttachments.where((a) => a.isVideoNote).toList();
    final visuals = remoteAttachments
        .where((a) => a.type != ChatAttachmentType.audio && !a.isVideoNote)
        .toList();

    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (audio.isNotEmpty)
          ...audio.map(
            (attachment) => _VoicePlayerWidget(
              url: attachment.url,
              isMe: isMe,
              initialDuration: attachment.durationMs == null
                  ? null
                  : Duration(milliseconds: attachment.durationMs!),
              waveform: attachment.waveform,
              semanticLabel: attachment.isVoiceNote
                  ? 'Голосовое сообщение'
                  : 'Аудиовложение',
            ),
          ),
        if (videoNotes.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: videoNotes
                .map(
                  (attachment) => _VideoNoteTile(
                    previewUrl: attachment.thumbnailUrl,
                    durationLabel: attachment.durationMs == null
                        ? null
                        : _formatAttachmentDuration(
                            Duration(milliseconds: attachment.durationMs!),
                          ),
                    label: 'Кружок',
                    videoSource: attachment.url,
                    isRemoteSource: true,
                    onTap: onOpenRemoteAttachment == null
                        ? null
                        : () => onOpenRemoteAttachment!(
                            remoteAttachments, attachment),
                  ),
                )
                .toList(),
          ),
          if (visuals.isNotEmpty) const SizedBox(height: 8),
        ],
        if (visuals.isNotEmpty)
          _RemoteMediaGrid(
            attachments: visuals,
            onOpenAttachment: onOpenRemoteAttachment,
          ),
      ],
    );
  }

  Widget _buildLocalAttachments(BuildContext context) {
    // Пары (файл, статус) собираем ДО фильтраций — сплиты по типам
    // теряют исходные индексы, а статусы идут по порядку attachments.
    final statuses = localAttachmentStatuses;
    final audio = localAttachments
        .where((f) => _attachmentKindFromXFile(f) == _ChatAttachmentKind.audio)
        .toList();
    final videoNotes = localAttachments
        .where((file) => _isVideoNoteFileName(file.name))
        .toList();
    final visuals = <XFile>[];
    final visualStatuses = <ChatAttachmentUploadStatus>[];
    for (var i = 0; i < localAttachments.length; i++) {
      final file = localAttachments[i];
      if (_attachmentKindFromXFile(file) != _ChatAttachmentKind.audio &&
          !_isVideoNoteFileName(file.name)) {
        visuals.add(file);
        if (statuses != null && i < statuses.length) {
          visualStatuses.add(statuses[i]);
        }
      }
    }

    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (audio.isNotEmpty)
          ...audio.map(
            (file) => _VoicePlayerWidget(
              path: file.path,
              isMe: isMe,
              initialDuration: _durationFromAttachmentName(file.name),
              semanticLabel: _isVoiceNoteFileName(file.name)
                  ? 'Голосовое сообщение'
                  : 'Аудиовложение',
            ),
          ),
        if (videoNotes.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: videoNotes
                .map(
                  (file) => _VideoNoteTile(
                    durationLabel:
                        _durationFromAttachmentName(file.name) == null
                            ? null
                            : _formatAttachmentDuration(
                                _durationFromAttachmentName(file.name)!,
                              ),
                    label: 'Кружок',
                    videoSource: file.path,
                    isRemoteSource: false,
                    onTap: onOpenLocalAttachment == null
                        ? null
                        : () => onOpenLocalAttachment!(localAttachments, file),
                  ),
                )
                .toList(),
          ),
          if (visuals.isNotEmpty) const SizedBox(height: 8),
        ],
        if (visuals.isNotEmpty)
          _LocalMediaGrid(
            files: visuals,
            statuses:
                visualStatuses.length == visuals.length ? visualStatuses : null,
            onOpenAttachment: onOpenLocalAttachment,
          ),
      ],
    );
  }
}

class _ChatSenderLabel extends StatelessWidget {
  const _ChatSenderLabel({
    required this.label,
    required this.color,
    this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelMedium?.copyWith(
        color: color,
        fontWeight: FontWeight.w800,
      ),
    );
    if (onTap == null) {
      return text;
    }

    return Tooltip(
      message: 'Написать в личку',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: text),
                const SizedBox(width: 4),
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 12,
                  color: color.withValues(alpha: 0.86),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReplyQuoteCard extends StatelessWidget {
  const _ReplyQuoteCard({
    required this.reply,
    required this.isMe,
    this.onTap,
  });

  final ChatReplyReference reply;
  final bool isMe;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final titleColor = isMe ? scheme.onPrimary : scheme.primary;
    final bodyColor = isMe
        ? scheme.onPrimary.withValues(alpha: 0.84)
        : scheme.onSurfaceVariant;
    final accentColor = isMe ? scheme.onPrimary : scheme.primary;
    final borderRadius = BorderRadius.circular(12);
    final maxPreviewWidth = math.min(
      360.0,
      math.max(220.0, MediaQuery.sizeOf(context).width * 0.58),
    );
    final maxTextWidth = math.max(140.0, maxPreviewWidth - 34);

    // Плотность (чанк 22): убрана собственная фон-плашка цитаты (была
    // read Container с цветной заливкой + скруглением поверх пузыря —
    // ровно та «рамка-в-рамке», которую спека запрещает). Полоса-
    // акцент 3dp остаётся единственным визуальным маркером цитаты,
    // цитата рисуется прямо на поверхности пузыря. borderRadius
    // сохранён только для формы ripple у InkWell ниже.
    final content = Container(
      key: const ValueKey<String>('chat-reply-quote-card'),
      constraints: BoxConstraints(maxWidth: maxPreviewWidth),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 32,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxTextWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  reply.senderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: titleColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reply.text.trim().isNotEmpty
                      ? reply.text
                      : 'Сообщение без текста',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  // Плотность (чанк 22): 14sp (было bodySmall=12) —
                  // спека держит цитату на 2 строках 14sp.
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: bodyColor,
                    fontSize: 14,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) {
      return content;
    }

    return Semantics(
      button: true,
      label: 'Перейти к исходному сообщению',
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: content,
      ),
    );
  }
}

class _CallSummaryPalette {
  const _CallSummaryPalette({
    required this.background,
    required this.border,
    required this.iconBackground,
    required this.iconColor,
    required this.titleColor,
    required this.subtitleColor,
  });

  final Color background;
  final Color border;
  final Color iconBackground;
  final Color iconColor;
  final Color titleColor;
  final Color subtitleColor;
}
