part of '../chat_screen.dart';

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
        DateFormat('dd.MM.yyyy H:mm', 'ru')
            .format(toLocalForDisplay(currentItem.timestamp!)),
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
        // Wrapped in _SwipeDownDismissibleImage so vertical drag from
        // an un-zoomed image follows the finger + dismisses the
        // viewer past a threshold (TG / iOS Photos pattern). When the
        // image is zoomed > 1.0 the InteractiveViewer wins all pan
        // gestures so users can still look around inside zoom.
        content = _SwipeDownDismissibleImage(
          builder: (context, transformController) => item.isRemote
              ? InteractiveViewer(
                  transformationController: transformController,
                  minScale: 0.8,
                  maxScale: 4,
                  child: _AttachmentImage(
                    url: item.source,
                    fit: BoxFit.contain,
                    placeholder: const Center(
                      child: CircularProgressIndicator(),
                    ),
                    errorWidget: _AttachmentViewerPlaceholder(item: item),
                  ),
                )
              : FutureBuilder<Uint8List>(
                  future: item.file!.readAsBytes(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return InteractiveViewer(
                      transformationController: transformController,
                      minScale: 0.8,
                      maxScale: 4,
                      child: Image.memory(
                        snapshot.data!,
                        fit: BoxFit.contain,
                        semanticLabel: 'Изображение в просмотрщике',
                      ),
                    );
                  },
                ),
        );
        break;
      case _ChatAttachmentKind.video:
        final source = item.isRemote ? item.source! : item.file?.path;
        if (source == null || source.trim().isEmpty) {
          content = _AttachmentViewerPlaceholder(item: item);
        } else if (item.isVideoNote) {
          // Кружочки рисуем как у TG: круглый плеер, авто-плей, tap =
          // play/pause, кольцо прогресса по окружности + перемотка по нему,
          // мьют вторичной кнопкой (V3).
          content = _VideoNotePlayer(
            source: source,
            isRemoteSource: item.isRemote,
            posterUrl: item.thumbnailUrl,
          );
        } else {
          content = _AttachmentVideoPlayer(
            source: source,
            isRemoteSource: item.isRemote,
            posterUrl: item.thumbnailUrl,
          );
        }
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

    return Semantics(
      button: true,
      label: 'Перейти к вложению',
      selected: isSelected,
      child: InkWell(
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
      return _AttachmentImage(
        url: item.thumbnailUrl ?? item.source,
        fit: BoxFit.cover,
        placeholder: const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        errorWidget: _AttachmentViewerThumbnailFallback(
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
            semanticLabel: 'Прикреплённое изображение',
          );
        },
      );
    }

    if (item.kind == _ChatAttachmentKind.video &&
        item.thumbnailUrl != null &&
        item.thumbnailUrl!.isNotEmpty) {
      return _AttachmentImage(
        url: item.thumbnailUrl,
        fit: BoxFit.cover,
        placeholder: const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        errorWidget: _AttachmentViewerThumbnailFallback(
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
  bool _isMuted = false;
  bool _seeking = false;
  // Position the user is currently dragging the seek bar to. We commit
  // to the controller on drag-end so the playback head doesn't fight
  // the live position updates while the thumb is in motion.
  Duration _scrubPosition = Duration.zero;
  bool _showControls = true;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    final uri = _videoSourceUri(widget.source);
    final controller = widget.isRemoteSource
        ? VideoPlayerController.networkUrl(uri)
        : VideoPlayerController.contentUri(uri);
    _controller = controller;
    // Listener pulls live position / playing state into setState so the
    // seek bar + time labels actually follow playback. Was missing
    // before — that's why the slider looked frozen.
    controller.addListener(_handleControllerUpdate);
    _initializeFuture = controller.initialize().then((_) {
      if (!mounted) return;
      // Don't auto-loop video files — TG / WA stop at end-of-file and
      // wait for user to scrub or restart.
      controller.setLooping(false);
    });
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _controller?.removeListener(_handleControllerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  void _handleControllerUpdate() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null) return;
    HapticFeedback.lightImpact();
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      // If we're at the end of the file, restart from 0.
      final pos = controller.value.position;
      final dur = controller.value.duration;
      if (dur > Duration.zero &&
          pos >= dur - const Duration(milliseconds: 250)) {
        await controller.seekTo(Duration.zero);
      }
      await controller.play();
      _scheduleControlsHide();
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleMute() async {
    final controller = _controller;
    if (controller == null) return;
    HapticFeedback.lightImpact();
    final next = !_isMuted;
    await controller.setVolume(next ? 0 : 1);
    if (!mounted) return;
    setState(() => _isMuted = next);
  }

  void _scheduleControlsHide() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      final controller = _controller;
      if (controller == null) return;
      // Don't auto-hide while paused — controls only fade out during
      // active playback so the user can still tap to resume.
      if (controller.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControlsVisibility() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _scheduleControlsHide();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) return '$h:$mm:$ss';
    return '$mm:$ss';
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
                _AttachmentImage(
                  url: widget.posterUrl,
                  fit: BoxFit.contain,
                ),
              const CircularProgressIndicator(color: Colors.white),
            ],
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Не удалось загрузить видео',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.78)),
              ),
            ),
          );
        }
        final duration = controller.value.duration;
        final position = _seeking ? _scrubPosition : controller.value.position;
        final maxMs =
            duration.inMilliseconds <= 0 ? 1 : duration.inMilliseconds;
        final scrubMs = position.inMilliseconds.clamp(0, maxMs).toDouble();
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 720),
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio == 0
                  ? 16 / 9
                  : controller.value.aspectRatio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: ColoredBox(
                  color: Colors.black,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Tap on the canvas toggles controls visibility,
                      // play/pause stays on the dedicated button so we
                      // don't fight gesture intent.
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _toggleControlsVisibility,
                        child: VideoPlayer(controller),
                      ),
                      AnimatedOpacity(
                        opacity: _showControls ? 1 : 0,
                        duration: const Duration(milliseconds: 220),
                        child: IgnorePointer(
                          ignoring: !_showControls,
                          child: _buildControlsOverlay(
                            controller: controller,
                            position: position,
                            duration: duration,
                            scrubMs: scrubMs,
                            maxMs: maxMs.toDouble(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildControlsOverlay({
    required VideoPlayerController controller,
    required Duration position,
    required Duration duration,
    required double scrubMs,
    required double maxMs,
  }) {
    return Stack(
      children: [
        // Soft gradient at top + bottom so white controls stay legible
        // over bright video content. Same look as TG / iOS player.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.42),
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.55),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ),
        // Center play / pause — big, hit-testable.
        Center(
          child: Material(
            color: Colors.black.withValues(alpha: 0.42),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: Semantics(
              button: true,
              label: controller.value.isPlaying
                  ? 'Поставить на паузу'
                  : 'Воспроизвести',
              child: InkWell(
                onTap: _togglePlayback,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Icon(
                    controller.value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ),
            ),
          ),
        ),
        // Bottom strip: time labels + seek bar + mute toggle.
        Positioned(
          left: 8,
          right: 8,
          bottom: 4,
          child: Row(
            children: [
              const SizedBox(width: 8),
              Text(
                _formatDuration(position),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.32),
                    thumbColor: Colors.white,
                    overlayColor: Colors.white.withValues(alpha: 0.12),
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 7,
                    ),
                  ),
                  child: Slider(
                    value: scrubMs,
                    max: maxMs,
                    onChangeStart: (_) {
                      setState(() => _seeking = true);
                    },
                    onChanged: (value) {
                      setState(() {
                        _scrubPosition = Duration(milliseconds: value.round());
                      });
                    },
                    onChangeEnd: (value) async {
                      await controller.seekTo(
                        Duration(milliseconds: value.round()),
                      );
                      if (mounted) setState(() => _seeking = false);
                    },
                  ),
                ),
              ),
              Text(
                _formatDuration(duration),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: _toggleMute,
                tooltip: _isMuted ? 'Включить звук' : 'Выключить звук',
                icon: Icon(
                  _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
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

/// Telegram-style circular video-note (кружок) player. Auto-plays on open
/// with sound on (V3): tap = play/pause (no force-loop), a progress ring
/// runs round the circle, drag along the ring seeks, and mute is a small
/// secondary speaker control. Save is available from the dialog header
/// (download icon at top-right).
class _SwipeDownDismissibleImage extends StatefulWidget {
  const _SwipeDownDismissibleImage({required this.builder});

  /// Caller builds the InteractiveViewer-wrapped image and binds the
  /// shared `transformationController` so we can read the scale.
  final Widget Function(
    BuildContext context,
    TransformationController controller,
  ) builder;

  @override
  State<_SwipeDownDismissibleImage> createState() =>
      _SwipeDownDismissibleImageState();
}

class _SwipeDownDismissibleImageState extends State<_SwipeDownDismissibleImage>
    with SingleTickerProviderStateMixin {
  final TransformationController _transform = TransformationController();
  late final AnimationController _snap;
  Offset _dragOffset = Offset.zero;
  bool _isAtRestingScale = true;

  // Past this many vertical pixels the release dismisses; under that
  // we snap back.
  static const double _dismissThreshold = 110;

  @override
  void initState() {
    super.initState();
    _snap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _transform.addListener(_handleTransformChange);
  }

  @override
  void dispose() {
    _transform.removeListener(_handleTransformChange);
    _transform.dispose();
    _snap.dispose();
    super.dispose();
  }

  void _handleTransformChange() {
    final scale = _transform.value.getMaxScaleOnAxis();
    final atRest = (scale - 1.0).abs() < 0.01;
    if (atRest != _isAtRestingScale) {
      setState(() => _isAtRestingScale = atRest);
    }
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_isAtRestingScale) return;
    setState(() {
      _dragOffset += Offset(0, details.delta.dy);
      // Don't let the user drag the image up forever — TG just
      // anchors at zero on upward drags.
      if (_dragOffset.dy < 0) {
        _dragOffset = Offset(_dragOffset.dx, _dragOffset.dy * 0.4);
      }
    });
  }

  Future<void> _handleDragEnd(DragEndDetails details) async {
    final velocity = details.velocity.pixelsPerSecond.dy;
    final passedThreshold =
        _dragOffset.dy > _dismissThreshold || velocity > 700;
    if (passedThreshold && mounted) {
      Navigator.of(context).maybePop();
      return;
    }
    // Snap back to origin via animation.
    final from = _dragOffset;
    _snap.value = 0;
    final tween = Tween<Offset>(begin: from, end: Offset.zero)
        .chain(CurveTween(curve: Curves.easeOutCubic))
        .animate(_snap);
    void listener() {
      if (!mounted) return;
      setState(() => _dragOffset = tween.value);
    }

    tween.addListener(listener);
    try {
      await _snap.forward();
    } on TickerCanceled {
      // Widget disposed mid-animation — safe to ignore.
    } finally {
      tween.removeListener(listener);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dyAbs = _dragOffset.dy.abs();
    // Background opacity falls from 1.0 → 0.55 over the threshold so
    // the "letting go past here will dismiss" point is visible.
    final dragProgress = (dyAbs / _dismissThreshold).clamp(0.0, 1.0);
    final backgroundOpacity = 1.0 - 0.45 * dragProgress;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Black layer that fades as the image translates. The dialog
        // already has its own black 92% backdrop; we layer a fading
        // black-out so the user sees the dimming as a confirmation
        // signal that release will dismiss.
        IgnorePointer(
          child: Container(
            color: Colors.black.withValues(
              alpha: 0.92 * backgroundOpacity,
            ),
          ),
        ),
        GestureDetector(
          // We only care about VERTICAL pan — letting horizontal
          // gestures fall through means the parent PageView still
          // handles swipe-between-pages.
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate: _isAtRestingScale ? _handleDragUpdate : null,
          onVerticalDragEnd: _isAtRestingScale ? _handleDragEnd : null,
          child: Transform.translate(
            offset: _dragOffset,
            child: widget.builder(context, _transform),
          ),
        ),
      ],
    );
  }
}

/// Small green presence dot rendered in the bottom-right corner of
/// the chat-AppBar avatar when the peer is online. Pulses gently
/// (1.4s cycle, 0.85 → 1.0 scale + 0.6 → 1.0 opacity on a halo) so
/// the indicator reads as a live signal rather than a static
/// notification badge. Skipped under flutter_test's binding so
/// pumpAndSettle in widget tests doesn't hang on the repeating
/// controller.
