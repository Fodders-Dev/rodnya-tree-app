// Profile Phase 2b-2 audio (2026-05-29): editable audio block — a saved
// voice recording (artifact) in the article. Play/pause + an interactive
// seek slider + duration; in the editor an overflow menu (заменить /
// удалить), like the photo block. Warm presentation (Lora, warm theme).
//
// Playback (2026-05-31 polish): pause keeps the position — the next tap
// resumes from where it stopped (was restarting from 0). The progress bar
// is now a real Slider: drag to scrub, release to seek (backend serves
// HTTP Range, so seeking is cheap). When the clip finishes we reset to 0,
// so the next play starts over — intentional.
//
// The AudioPlayer is created lazily on first interaction, so merely
// rendering the block (e.g., in a widget test) never touches the
// audioplayers plugin — the Slider is plugin-free; only an onChangeEnd
// seek or a play tap (a user gesture) loads the source. Tests may inject
// a fake player via [playerFactory]. Playback streams from the url.

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../backend/models/profile_article.dart';

class ArticleAudioBlock extends StatefulWidget {
  const ArticleAudioBlock({
    super.key,
    required this.block,
    required this.busy,
    required this.onReplace,
    required this.onDelete,
    this.playerFactory,
  });

  final ArticleBlock block;

  /// Replace / patch in flight — overlays a spinner, locks the menu.
  final bool busy;
  final VoidCallback onReplace;
  final VoidCallback onDelete;

  /// Test seam: supplies the [AudioPlayer]. Defaults to a real one,
  /// constructed lazily on first interaction. Injecting a fake keeps a
  /// widget test off the audioplayers plugin while exercising the
  /// play/pause/resume/seek control flow.
  final AudioPlayer Function()? playerFactory;

  @override
  State<ArticleAudioBlock> createState() => _ArticleAudioBlockState();
}

class _ArticleAudioBlockState extends State<ArticleAudioBlock> {
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<void>? _compSub;

  PlayerState _state = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  /// True once the player has a source (via play() or setSourceUrl()).
  /// seek() needs a loaded source, so we lazily load it on first scrub.
  bool _sourceLoaded = false;

  /// Non-null while the user is dragging the slider — the drag value (ms)
  /// wins over the streamed position so the thumb tracks the finger.
  double? _dragMs;

  void _ensurePlayer() {
    if (_player != null) return;
    final p = widget.playerFactory?.call() ?? AudioPlayer();
    _player = p;
    _stateSub = p.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    _durSub = p.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _posSub = p.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _compSub = p.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _state = PlayerState.stopped;
          _position = Duration.zero;
        });
      }
    });
  }

  Future<void> _toggle() async {
    final url = widget.block.audioUrl;
    if (url == null) return;
    _ensurePlayer();
    final p = _player!;
    try {
      if (_state == PlayerState.playing) {
        await p.pause();
      } else if (_state == PlayerState.paused) {
        // Resume from where we paused — do NOT restart the clip.
        await p.resume();
      } else {
        // First play, or after stop/complete (position is 0) → start over.
        await p.play(UrlSource(url));
        _sourceLoaded = true;
      }
    } catch (_) {
      // Playback failure is non-fatal — leave the controls usable.
    }
  }

  /// Seek to [position]. Loads the source first if the user scrubs before
  /// ever pressing play, so the playhead can move ahead of playback.
  Future<void> _seekTo(Duration position) async {
    final url = widget.block.audioUrl;
    if (url == null) return;
    _ensurePlayer();
    final p = _player!;
    try {
      if (!_sourceLoaded) {
        await p.setSourceUrl(url);
        _sourceLoaded = true;
      }
      await p.seek(position);
    } catch (_) {
      // Seeking before the source is ready is non-fatal.
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _compSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPlaying = _state == PlayerState.playing;
    final totalSec = widget.block.audioDurationSec;
    // Total duration: prefer the player's report, fall back to the stored
    // duration so the slider is usable (and seekable) before first play.
    final total = _duration > Duration.zero
        ? _duration
        : Duration(seconds: totalSec ?? 0);
    final maxMs = total.inMilliseconds.toDouble();
    final hasDuration = maxMs > 0;
    final posMs =
        _position.inMilliseconds.clamp(0, total.inMilliseconds).toDouble();
    // While dragging, the drag value wins; otherwise follow playback.
    final double sliderMs =
        (_dragMs ?? posMs).clamp(0.0, hasDuration ? maxMs : 1.0).toDouble();
    final displayPos =
        _dragMs != null ? Duration(milliseconds: _dragMs!.round()) : _position;
    final timeLabel = total > Duration.zero
        ? '${_fmt(displayPos)} / ${_fmt(total)}'
        : (totalSec != null ? _fmt(Duration(seconds: totalSec)) : '');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              key: Key('article-audio-play-${widget.block.id}'),
              onPressed: widget.busy ? null : _toggle,
              icon: widget.busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      isPlaying
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_fill_rounded,
                      size: 34,
                      color: theme.colorScheme.primary,
                    ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Запись голоса',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontFamily: 'Lora',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: theme.colorScheme.primary,
                      inactiveTrackColor:
                          theme.colorScheme.primary.withValues(alpha: 0.12),
                      thumbColor: theme.colorScheme.primary,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                      trackShape: const RoundedRectSliderTrackShape(),
                    ),
                    child: Slider(
                      key: Key('article-audio-seek-${widget.block.id}'),
                      value: sliderMs,
                      max: hasDuration ? maxMs : 1.0,
                      // Drag updates the thumb locally (visual); release
                      // seeks. Disabled until we know the duration, or
                      // while a replace/patch is in flight.
                      onChanged: !hasDuration || widget.busy
                          ? null
                          : (v) => setState(() => _dragMs = v),
                      onChangeEnd: !hasDuration || widget.busy
                          ? null
                          : (v) async {
                              setState(() => _dragMs = null);
                              await _seekTo(Duration(milliseconds: v.round()));
                            },
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timeLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              key: Key('article-audio-menu-${widget.block.id}'),
              tooltip: 'Действия с записью',
              enabled: !widget.busy,
              icon: Icon(
                Icons.more_vert_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              onSelected: (value) {
                if (value == 'replace') widget.onReplace();
                if (value == 'delete') widget.onDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'replace', child: Text('Перезаписать')),
                PopupMenuItem(value: 'delete', child: Text('Удалить')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
