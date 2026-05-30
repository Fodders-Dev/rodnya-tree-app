// Profile Phase 2b-2 audio (2026-05-29): editable audio block — a saved
// voice recording (artifact) in the article. Play/pause + progress +
// duration; in the editor an overflow menu (заменить / удалить), like the
// photo block. Warm presentation (Lora, warm theme).
//
// The AudioPlayer is created lazily on first play, so merely rendering
// the block (e.g., in a widget test) never touches the audioplayers
// plugin. Playback streams from the block's url (UrlSource).

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
  });

  final ArticleBlock block;

  /// Replace / patch in flight — overlays a spinner, locks the menu.
  final bool busy;
  final VoidCallback onReplace;
  final VoidCallback onDelete;

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

  void _ensurePlayer() {
    if (_player != null) return;
    final p = AudioPlayer();
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
      } else {
        await p.play(UrlSource(url));
      }
    } catch (_) {
      // Playback failure is non-fatal — leave the controls usable.
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
    final total = _duration > Duration.zero
        ? _duration
        : Duration(seconds: totalSec ?? 0);
    final fraction = total.inMilliseconds > 0
        ? (_position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final timeLabel = total > Duration.zero
        ? '${_fmt(_position)} / ${_fmt(total)}'
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
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 4,
                      backgroundColor:
                          theme.colorScheme.primary.withValues(alpha: 0.12),
                    ),
                  ),
                  const SizedBox(height: 4),
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
