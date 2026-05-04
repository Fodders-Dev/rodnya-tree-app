part of 'chat_screen.dart';

class _VoicePlayerWidget extends StatefulWidget {
  const _VoicePlayerWidget({
    this.url,
    this.path,
    required this.isMe,
    this.initialDuration,
    this.waveform = const <double>[],
    this.semanticLabel,
  });

  final String? url;
  final String? path;
  final bool isMe;
  final Duration? initialDuration;
  final List<double> waveform;
  final String? semanticLabel;

  @override
  State<_VoicePlayerWidget> createState() => _VoicePlayerWidgetState();
}

class _VoicePlayerWidgetState extends State<_VoicePlayerWidget> {
  late final AudioPlayer _player;
  PlayerState _playerState = PlayerState.stopped;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  double _playbackRate = 1.0;

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
      await _player.setPlaybackRate(_playbackRate);
    } catch (e) {
      debugPrint('Error playing audio: $e');
    }
  }

  Future<void> _pause() async {
    await _player.pause();
  }

  Future<void> _cyclePlaybackRate() async {
    const rates = <double>[1.0, 1.5, 2.0];
    final currentIndex = rates.indexOf(_playbackRate);
    final nextRate = rates[(currentIndex + 1) % rates.length];
    setState(() => _playbackRate = nextRate);
    try {
      await _player.setPlaybackRate(nextRate);
    } catch (e) {
      debugPrint('Error changing audio speed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isPlaying = _playerState == PlayerState.playing;
    // Theme-aligned palette: outgoing bubble uses onPrimary against the
    // accent gradient; incoming uses primary (accent) on the surface
    // bubble. Replaces the previous hardcoded white / blue.shade700,
    // which clashed with the warm cream brand.
    final Color color = widget.isMe ? scheme.onPrimary : scheme.primary;
    final totalDuration = _duration > Duration.zero
        ? _duration
        : (widget.initialDuration ?? Duration.zero);
    final progressFraction = totalDuration.inMilliseconds > 0
        ? (_position.inMilliseconds / totalDuration.inMilliseconds)
            .clamp(0.0, 1.0)
            .toDouble()
        : 0.0;
    final progressLabel = totalDuration > Duration.zero
        ? '${_formatDuration(_position)} / ${_formatDuration(totalDuration)}'
        : _formatDuration(_position);

    final waveform =
        widget.waveform.isNotEmpty ? widget.waveform : _fallbackVoiceWaveform;

    return Semantics(
      label: widget.semanticLabel ?? 'Голосовое сообщение',
      button: true,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: widget.isMe
              ? scheme.onPrimary.withValues(alpha: 0.14)
              : scheme.primary.withValues(alpha: 0.08),
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
              width: 168,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.semanticLabel ?? 'Голосовое сообщение',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _cyclePlaybackRate,
                        style: TextButton.styleFrom(
                          foregroundColor: color,
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          minimumSize: const Size(38, 24),
                          padding: EdgeInsets.zero,
                        ),
                        child: Text(
                          '${_playbackRate.toStringAsFixed(_playbackRate == 1.0 ? 0 : 1)}x',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  _VoiceWaveformScrubber(
                    waveform: waveform,
                    progress: progressFraction,
                    activeColor: color,
                    inactiveColor: color.withValues(alpha: 0.28),
                    onSeekFraction: totalDuration.inMilliseconds <= 0
                        ? null
                        : (fraction) {
                            _player.seek(
                              Duration(
                                milliseconds:
                                    (totalDuration.inMilliseconds * fraction)
                                        .round(),
                              ),
                            );
                          },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
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

const List<double> _fallbackVoiceWaveform = <double>[
  0.18,
  0.42,
  0.28,
  0.66,
  0.38,
  0.74,
  0.46,
  0.31,
  0.58,
  0.82,
  0.35,
  0.52,
  0.24,
  0.68,
  0.44,
  0.29,
  0.61,
  0.76,
  0.33,
  0.49,
  0.22,
  0.57,
  0.39,
  0.71,
  0.27,
  0.46,
  0.63,
  0.36,
  0.54,
  0.25,
  0.69,
  0.41,
];

class _VoiceWaveformScrubber extends StatelessWidget {
  const _VoiceWaveformScrubber({
    required this.waveform,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.onSeekFraction,
  });

  final List<double> waveform;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final ValueChanged<double>? onSeekFraction;

  @override
  Widget build(BuildContext context) {
    final effectiveWaveform =
        waveform.isEmpty ? _fallbackVoiceWaveform : waveform;
    return SizedBox(
      height: 34,
      child: LayoutBuilder(
        builder: (context, constraints) {
          void seek(Offset localPosition) {
            final callback = onSeekFraction;
            if (callback == null || constraints.maxWidth <= 0) {
              return;
            }
            callback(
              (localPosition.dx / constraints.maxWidth)
                  .clamp(0.0, 1.0)
                  .toDouble(),
            );
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => seek(details.localPosition),
            onHorizontalDragUpdate: (details) => seek(details.localPosition),
            child: CustomPaint(
              painter: _VoiceWaveformPainter(
                waveform: effectiveWaveform,
                progress: progress.clamp(0.0, 1.0).toDouble(),
                activeColor: activeColor,
                inactiveColor: inactiveColor,
              ),
              child: const SizedBox.expand(),
            ),
          );
        },
      ),
    );
  }
}

class _VoiceWaveformPainter extends CustomPainter {
  const _VoiceWaveformPainter({
    required this.waveform,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  final List<double> waveform;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || waveform.isEmpty) {
      return;
    }

    final gap = waveform.length > 48 ? 1.5 : 2.0;
    final barWidth =
        ((size.width - gap * (waveform.length - 1)) / waveform.length)
            .clamp(2.0, 5.0)
            .toDouble();
    final totalWidth = waveform.length * barWidth + (waveform.length - 1) * gap;
    final startX = (size.width - totalWidth).clamp(0.0, size.width) / 2;
    final centerY = size.height / 2;
    final radius = Radius.circular(barWidth / 2);

    final activePaint = Paint()..color = activeColor;
    final inactivePaint = Paint()..color = inactiveColor;

    for (var index = 0; index < waveform.length; index++) {
      final value = waveform[index].clamp(0.0, 1.0).toDouble();
      final barHeight = (size.height * (0.18 + value * 0.78))
          .clamp(4.0, size.height)
          .toDouble();
      final x = startX + index * (barWidth + gap);
      final rect = Rect.fromLTWH(
        x,
        centerY - barHeight / 2,
        barWidth,
        barHeight,
      );
      final sampleProgress = (index + 0.5) / waveform.length;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, radius),
        sampleProgress <= progress ? activePaint : inactivePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceWaveformPainter oldDelegate) {
    return oldDelegate.waveform != waveform ||
        oldDelegate.progress != progress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
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
    this.onOpenAttachment,
  });

  final List<XFile> files;
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
        // Reference `.msg`: 14.5/1.35 — slightly tighter than Material's
        // bodyLarge (16/1.5) so chat reads as conversational not formal.
        style: TextStyle(
          color: color,
          fontSize: 14.5,
          height: 1.35,
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
        style: const TextStyle(fontSize: 14.5, height: 1.35),
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

    return CachedNetworkImage(
      imageUrl: normalizedUrl!,
      fit: fit,
      placeholder: placeholder == null ? null : (_, __) => placeholder!,
      errorWidget: (_, __, ___) => fallback,
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

class _VideoNoteTile extends StatelessWidget {
  const _VideoNoteTile({
    required this.label,
    this.previewUrl,
    this.durationLabel,
    this.onTap,
  });

  // Telegram chat круглые видео сидят на ~200px iOS / 180dp Android.
  // 168 — комфортная середина для плотности нашего бабла.
  static const double _diameter = 168;

  final String label;
  final String? previewUrl;
  final String? durationLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: onTap != null,
      // SizedBox обязателен: Stack(fit: StackFit.expand) внутри Wrap
      // получает unbounded constraints и валит layout с null-check'ом.
      // Раньше это рушило весь чат в момент когда в сообщении появлялся
      // кружок. Размер впихнут в сам тайл, чтобы новые callers не
      // забыли обернуть.
      child: SizedBox(
        width: _diameter,
        height: _diameter,
        child: ClipOval(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (previewUrl != null && previewUrl!.trim().isNotEmpty)
                    _AttachmentImage(
                      url: previewUrl,
                      fit: BoxFit.cover,
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
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textColor =
        isMe ? scheme.onPrimary.withValues(alpha: 0.95) : scheme.onSurface;
    final selectedColor = isMe
        ? Colors.white.withValues(alpha: 0.22)
        : scheme.primary.withValues(alpha: 0.18);
    final defaultColor = isMe
        ? Colors.white.withValues(alpha: 0.12)
        : scheme.surface.withValues(alpha: 0.78);
    final borderColor = reaction.isMine
        ? (isMe
            ? Colors.white.withValues(alpha: 0.5)
            : scheme.primary.withValues(alpha: 0.32))
        : (isMe
            ? Colors.white.withValues(alpha: 0.18)
            : scheme.outlineVariant.withValues(alpha: 0.6));

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: reaction.isMine ? selectedColor : defaultColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor, width: 0.7),
        ),
        child: Text(
          '${reaction.emoji} ${reaction.count}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: textColor,
            fontWeight: reaction.isMine ? FontWeight.w800 : FontWeight.w600,
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
                _AttachmentImage(
                  url: widget.posterUrl,
                  fit: BoxFit.contain,
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
