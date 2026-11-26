part of '../chat_screen.dart';

class _RemoteMediaGrid extends StatelessWidget {
  const _RemoteMediaGrid({
    required this.attachments,
    this.onOpenAttachment,
  });

  final List<ChatAttachment> attachments;
  final void Function(
          List<ChatAttachment> attachments, ChatAttachment attachment)?
      onOpenAttachment;

  // Telegram-style smart photo grid:
  //   1 photo  → full 220x220 with adaptive aspect.
  //   2 photos → side-by-side 50/50, single tall row.
  //   3 photos → first big-left + two stacked right.
  //   4 photos → 2x2 grid.
  //   5+ photos → 2x2 grid with the last tile carrying a "+N" overlay so
  //               the user knows there's more behind the tap.
  // Total grid width is locked at 220 — same as the previous single-tile
  // variant — so bubble width stays predictable.
  static const double _gridWidth = 220;
  static const double _gap = 4;
  static const double _radius = 14;

  void _open(int index) {
    final callback = onOpenAttachment;
    if (callback == null || index < 0 || index >= attachments.length) return;
    callback(attachments, attachments[index]);
  }

  Widget _tile(int index, {Widget? overlay}) {
    Widget tile = _RemoteMediaTile(
      attachment: attachments[index],
      onTap: onOpenAttachment == null ? null : () => _open(index),
    );
    if (overlay != null) {
      tile = Stack(fit: StackFit.expand, children: [tile, overlay]);
    }
    return ClipRRect(borderRadius: BorderRadius.circular(_radius), child: tile);
  }

  Widget _moreOverlay(int extraCount) {
    return IgnorePointer(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.42),
        child: Center(
          child: Text(
            '+$extraCount',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = attachments.length;
    if (count == 1) {
      return SizedBox(width: _gridWidth, height: 220, child: _tile(0));
    }
    if (count == 2) {
      return SizedBox(
        width: _gridWidth,
        height: 130,
        child: Row(
          children: [
            Expanded(child: _tile(0)),
            const SizedBox(width: _gap),
            Expanded(child: _tile(1)),
          ],
        ),
      );
    }
    if (count == 3) {
      return SizedBox(
        width: _gridWidth,
        height: 158,
        child: Row(
          children: [
            Expanded(flex: 3, child: _tile(0)),
            const SizedBox(width: _gap),
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  Expanded(child: _tile(1)),
                  const SizedBox(height: _gap),
                  Expanded(child: _tile(2)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    // 4+ photos: 2x2 grid; last tile gets a +N overlay when count > 4.
    final extra = count - 4;
    return SizedBox(
      width: _gridWidth,
      height: 220,
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: _tile(0)),
                const SizedBox(width: _gap),
                Expanded(child: _tile(1)),
              ],
            ),
          ),
          const SizedBox(height: _gap),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _tile(2)),
                const SizedBox(width: _gap),
                Expanded(
                  child: _tile(
                    3,
                    overlay: extra > 0 ? _moreOverlay(extra) : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalMediaGrid extends StatelessWidget {
  const _LocalMediaGrid({
    required this.files,
    this.statuses,
    this.onOpenAttachment,
  });

  final List<XFile> files;

  /// Пофайловые статусы загрузки (UX-аудит P1): совпадают по индексам
  /// с [files]; null → без оверлеев (превью в композере и т.п.).
  final List<ChatAttachmentUploadStatus>? statuses;
  final void Function(List<XFile> files, XFile file)? onOpenAttachment;

  // Mirror of _RemoteMediaGrid for not-yet-uploaded local files. Same
  //1/2/3/4+ smart layouts so the optimistic preview matches the final
  // remote rendering.
  static const double _gridWidth = 220;
  static const double _gap = 4;
  static const double _radius = 14;

  void _open(int index) {
    final callback = onOpenAttachment;
    if (callback == null || index < 0 || index >= files.length) return;
    callback(files, files[index]);
  }

  Widget _tile(int index, {Widget? overlay}) {
    Widget tile = _LocalMediaTile(
      file: files[index],
      onTap: onOpenAttachment == null ? null : () => _open(index),
    );
    final uploadOverlay = _uploadOverlayFor(index);
    if (uploadOverlay != null) {
      tile = Stack(fit: StackFit.expand, children: [tile, uploadOverlay]);
    }
    if (overlay != null) {
      tile = Stack(fit: StackFit.expand, children: [tile, overlay]);
    }
    return ClipRRect(borderRadius: BorderRadius.circular(_radius), child: tile);
  }

  /// Оверлей состояния загрузки: queued — притемнение, uploading —
  /// притемнение + спиннер, done — чисто, failed — иконка ошибки.
  Widget? _uploadOverlayFor(int index) {
    final list = statuses;
    if (list == null || index >= list.length) {
      return null;
    }
    final status = list[index];
    Widget? content;
    switch (status) {
      case ChatAttachmentUploadStatus.done:
        return null;
      case ChatAttachmentUploadStatus.queued:
        content = null;
        break;
      case ChatAttachmentUploadStatus.uploading:
        content = const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            key: Key('attachment-uploading-spinner'),
            strokeWidth: 2.5,
            color: Colors.white,
          ),
        );
        break;
      case ChatAttachmentUploadStatus.failed:
        content = const Icon(
          Icons.error_outline_rounded,
          key: Key('attachment-failed-icon'),
          color: Colors.white,
          size: 28,
        );
        break;
    }
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: ColoredBox(
          key: ValueKey(status),
          color: Colors.black.withValues(
            alpha: status == ChatAttachmentUploadStatus.queued ? 0.25 : 0.35,
          ),
          child: content == null ? null : Center(child: content),
        ),
      ),
    );
  }

  Widget _moreOverlay(int extraCount) {
    return IgnorePointer(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.42),
        child: Center(
          child: Text(
            '+$extraCount',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = files.length;
    if (count == 1) {
      return SizedBox(width: _gridWidth, height: 220, child: _tile(0));
    }
    if (count == 2) {
      return SizedBox(
        width: _gridWidth,
        height: 130,
        child: Row(
          children: [
            Expanded(child: _tile(0)),
            const SizedBox(width: _gap),
            Expanded(child: _tile(1)),
          ],
        ),
      );
    }
    if (count == 3) {
      return SizedBox(
        width: _gridWidth,
        height: 158,
        child: Row(
          children: [
            Expanded(flex: 3, child: _tile(0)),
            const SizedBox(width: _gap),
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  Expanded(child: _tile(1)),
                  const SizedBox(height: _gap),
                  Expanded(child: _tile(2)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final extra = count - 4;
    return SizedBox(
      width: _gridWidth,
      height: 220,
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: _tile(0)),
                const SizedBox(width: _gap),
                Expanded(child: _tile(1)),
              ],
            ),
          ),
          const SizedBox(height: _gap),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _tile(2)),
                const SizedBox(width: _gap),
                Expanded(
                  child: _tile(
                    3,
                    overlay: extra > 0 ? _moreOverlay(extra) : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Truncation threshold for long chat messages. Above this character
/// count we collapse the body to the first ~600 chars and surface a
/// "Показать ещё" affordance — same trick TG and WhatsApp use to
/// keep the bubble compact, the scroll snappy, and the painted
/// TextSpan tree shallow even on a 5 000+ char dump (e.g. pasted
/// log file). On tap the bubble expands to the full text inline.
const int _kLongMessageCollapseAt = 600;

final RegExp _chatMessageUrlPattern = RegExp(
  r'((?:https?://|www\.)[^\s<>()]+|(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}(?:/[^\s<>()]*)?)',
  caseSensitive: false,
);

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
          // Composer-side preview of an image the USER just picked from
          // their gallery. They know what it is, but a screen reader
          // user benefits from confirmation that the attach succeeded.
          semanticLabel: 'Прикреплённое изображение',
          errorBuilder: (_, __, ___) => const ColoredBox(
            color: Color(0x11000000),
            child: Center(child: Icon(Icons.broken_image_outlined)),
          ),
        );
      },
    );
  }
}

class _AttachmentImage extends StatelessWidget {
  const _AttachmentImage({
    required this.url,
    required this.fit,
    this.placeholder,
    this.errorWidget,
  });

  final String? url;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  @override
  Widget build(BuildContext context) {
    final normalizedUrl = UrlUtils.normalizeImageUrl(url);
    final fallback = errorWidget ?? const SizedBox.shrink();
    if (!UrlUtils.isRenderableNetworkImageUrl(normalizedUrl)) {
      return fallback;
    }

    return Semantics(
      // a11y: TalkBack/VoiceOver previously announced just "Image"
      // which is useless. "Изображение в сообщении" tells the user
      // what kind of media they're focused on. Future improvement:
      // surface alt-text from the attachment metadata when the
      // backend supports it.
      label: 'Изображение в сообщении',
      image: true,
      excludeSemantics: true,
      child: CachedNetworkImage(
        imageUrl: normalizedUrl!,
        fit: fit,
        useOldImageOnUrlChange: true,
        placeholder: placeholder == null ? null : (_, __) => placeholder!,
        errorWidget: (_, __, ___) => fallback,
      ),
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
        videoSource: file.path,
        isRemoteSource: false,
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
        videoSource: attachment.url,
        isRemoteSource: true,
      );
    }
    if (kind == _ChatAttachmentKind.image) {
      return InkWell(
        onTap: onTap,
        child: _AttachmentImage(
          url: attachment.thumbnailUrl ?? attachment.url,
          fit: BoxFit.cover,
          placeholder: const _AttachmentPlaceholder(
            icon: Icons.image_outlined,
            label: 'Фото',
          ),
          errorWidget: const _AttachmentPlaceholder(
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
            _AttachmentImage(
              url: attachment.thumbnailUrl,
              fit: BoxFit.cover,
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
