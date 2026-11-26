part of '../chat_screen.dart';

/// C2c: единый реестр «один inline-медиаплеер за раз» — голосовые бабблы
/// и видео-кружки. Старт любого паузит предыдущий активный (как в
/// Telegram: новое голосовое глушит играющий кружок и наоборот). Раньше
/// реестр был только у голосовых (_VoicePlayerWidgetState), а видео его
/// не переиспользовало — два кружка играли разом с зацикленным звуком.
class _InlineMediaPlayback {
  _InlineMediaPlayback._();

  // Ключуем по ВЛАДЕЛЬЦУ (State-инстансу), а НЕ по колбэку: tear-off
  // метода (`_pauseSelf`) при каждом обращении — новый объект, и
  // identical() над ними всегда false → реестр бы не очищался и копил
  // ссылку на уже-disposed-плеер. State-инстанс стабилен, identical
  // работает корректно.
  static Object? _activeOwner;
  static VoidCallback? _activePause;

  /// Сделать [owner] активным плеером, поставив предыдущего на паузу.
  static void activate(Object owner, VoidCallback pauseSelf) {
    final previousPause = _activePause;
    if (previousPause != null && !identical(_activeOwner, owner)) {
      previousPause();
    }
    _activeOwner = owner;
    _activePause = pauseSelf;
  }

  /// Снять регистрацию (complete / pause / dispose), если активны были мы
  /// — чтобы следующий старт не дёргал устаревший колбэк.
  static void resign(Object owner) {
    if (identical(_activeOwner, owner)) {
      _activeOwner = null;
      _activePause = null;
    }
  }
}

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
  // C1: плеер создаём ЛЕНИВО — только при первом воспроизведении.
  // Раньше initState спавнил AudioPlayer на КАЖДОЕ голосовое в чате
  // (десятки плагин-инстансов на один скролл) и трогал плагин при
  // простом рендере. Теперь рендер бабла бесплатен, плеер появляется
  // по тапу Play.
  AudioPlayer? _player;
  PlayerState _playerState = PlayerState.stopped;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  double _playbackRate = 1.0;

  StreamSubscription? _stateSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _posSub;
  StreamSubscription? _compSub;

  // C2c: one-at-a-time playback теперь в общем реестре
  // [_InlineMediaPlayback] (голос + видео-кружки), не в локальном
  // статике — старт голосового паузит играющий кружок и наоборот.

  @override
  void initState() {
    super.initState();
    _duration = widget.initialDuration ?? Duration.zero;
  }

  /// C1: создать плеер и подписки один раз — на первом Play.
  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) {
      return existing;
    }
    final player = AudioPlayer();
    _player = player;
    _stateSub = player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playerState = s);
    });
    _durationSub = player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _posSub = player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _compSub = player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playerState = PlayerState.stopped;
          _position = Duration.zero;
        });
      }
      // Clear the global pointer if we were the active one — keeps
      // a stale callback from being invoked by the next bubble.
      _InlineMediaPlayback.resign(this);
    });
    return player;
  }

  void _pauseSelf() {
    if (mounted && _playerState == PlayerState.playing) {
      unawaited(_player?.pause());
    }
  }

  @override
  void dispose() {
    _InlineMediaPlayback.resign(this);
    _stateSub?.cancel();
    _durationSub?.cancel();
    _posSub?.cancel();
    _compSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    try {
      // C2c: паузим любой другой играющий inline-медиаплеер (голос или
      // видео-кружок) перед стартом — иначе две дорожки звучат разом.
      _InlineMediaPlayback.activate(this, _pauseSelf);

      final player = _ensurePlayer();
      if (widget.url != null) {
        await player.play(UrlSource(widget.url!));
      } else if (widget.path != null) {
        await player.play(DeviceFileSource(widget.path!));
      }
      if (!mounted) return;
      await player.setPlaybackRate(_playbackRate);
    } catch (e) {
      debugPrint('Error playing audio: $e');
    }
  }

  Future<void> _pause() async {
    await _player?.pause();
  }

  Future<void> _cyclePlaybackRate() async {
    const rates = <double>[1.0, 1.5, 2.0];
    final currentIndex = rates.indexOf(_playbackRate);
    final nextRate = rates[(currentIndex + 1) % rates.length];
    setState(() => _playbackRate = nextRate);
    try {
      // Если плеер ещё не создан — скорость применится при первом Play.
      await _player?.setPlaybackRate(nextRate);
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
              tooltip: isPlaying
                  ? 'Пауза голосового сообщения'
                  : 'Воспроизвести голосовое сообщение',
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
                    isPlaying: isPlaying,
                    activeColor: color,
                    inactiveColor: color.withValues(alpha: 0.28),
                    onSeekFraction: totalDuration.inMilliseconds <= 0
                        ? null
                        : (fraction) {
                            // Сик имеет смысл только когда плеер уже создан
                            // (после первого Play); иначе игнорируем.
                            _player?.seek(
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

/// Tappable / draggable waveform with live progress.
///
/// Telegram-style behaviour:
/// * Tap anywhere on the strip → immediate seek to that point.
/// * Horizontal drag → visual scrub follows the finger in real time
///   but the audio seek only fires on drag end. Committing on every
///   `onHorizontalDragUpdate` (the previous behaviour) caused
///   audible glitching on each frame and made the wave fight the
///   live-position listener.
/// * While playing, the bars under the playback head get a subtle
///   sin-wave breathing pulse — same "alive" feel TG has.
class _VoiceWaveformScrubber extends StatefulWidget {
  const _VoiceWaveformScrubber({
    required this.waveform,
    required this.progress,
    required this.isPlaying,
    required this.activeColor,
    required this.inactiveColor,
    required this.onSeekFraction,
  });

  final List<double> waveform;
  final double progress;
  final bool isPlaying;
  final Color activeColor;
  final Color inactiveColor;
  final ValueChanged<double>? onSeekFraction;

  @override
  State<_VoiceWaveformScrubber> createState() => _VoiceWaveformScrubberState();
}

class _VoiceWaveformScrubberState extends State<_VoiceWaveformScrubber>
    with SingleTickerProviderStateMixin {
  double? _dragFraction;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant _VoiceWaveformScrubber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) {
      _syncPulse();
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  /// Pulse runs only while `isPlaying`. Skipping under flutter_test's
  /// binding so widget tests' pumpAndSettle doesn't hang on the
  /// repeating controller.
  void _syncPulse() {
    final bindingName = WidgetsBinding.instance.runtimeType.toString();
    final inTest = bindingName.contains('TestWidgetsFlutterBinding');
    if (widget.isPlaying && !inTest) {
      if (!_pulseCtrl.isAnimating) {
        _pulseCtrl.repeat();
      }
    } else {
      _pulseCtrl.stop();
      _pulseCtrl.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveWaveform =
        widget.waveform.isEmpty ? _fallbackVoiceWaveform : widget.waveform;
    return SizedBox(
      height: 34,
      child: LayoutBuilder(
        builder: (context, constraints) {
          double? localToFraction(Offset localPosition) {
            if (constraints.maxWidth <= 0) return null;
            return (localPosition.dx / constraints.maxWidth)
                .clamp(0.0, 1.0)
                .toDouble();
          }

          void commit(double fraction) {
            final cb = widget.onSeekFraction;
            if (cb != null) cb(fraction);
          }

          // Effective progress: while user is dragging, follow the
          // finger; otherwise mirror the player's position.
          final visualProgress =
              (_dragFraction ?? widget.progress).clamp(0.0, 1.0).toDouble();

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) {
              final f = localToFraction(details.localPosition);
              if (f != null) commit(f);
            },
            onHorizontalDragStart: (details) {
              setState(() {
                _dragFraction = localToFraction(details.localPosition);
              });
            },
            onHorizontalDragUpdate: (details) {
              setState(() {
                _dragFraction = localToFraction(details.localPosition);
              });
            },
            onHorizontalDragEnd: (_) {
              final f = _dragFraction;
              setState(() => _dragFraction = null);
              if (f != null) commit(f);
            },
            onHorizontalDragCancel: () {
              setState(() => _dragFraction = null);
            },
            child: AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (context, _) {
                return CustomPaint(
                  painter: _VoiceWaveformPainter(
                    waveform: effectiveWaveform,
                    progress: visualProgress,
                    activeColor: widget.activeColor,
                    inactiveColor: widget.inactiveColor,
                    pulsePhase: widget.isPlaying ? _pulseCtrl.value : 0,
                    isPlaying: widget.isPlaying,
                  ),
                  child: const SizedBox.expand(),
                );
              },
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
    this.pulsePhase = 0,
    this.isPlaying = false,
  });

  final List<double> waveform;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  /// 0..1 — current phase of the breathing pulse animation. Only used
  /// when [isPlaying] is true to give bars near the playback head a
  /// subtle "alive" feel; off otherwise.
  final double pulsePhase;
  final bool isPlaying;

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
      final sampleProgress = (index + 0.5) / waveform.length;
      // Pulse: only bars within ±2 of the playback head get the
      // breathing scale; further bars stay flat. We compute distance
      // in *bar indices* and apply a falloff.
      double scale = 1.0;
      if (isPlaying && progress > 0) {
        final headIndex = progress * waveform.length;
        final distance = (index - headIndex).abs();
        if (distance < 3.0) {
          // Phased sin so each bar peaks slightly after its neighbour
          // → the pulse "rolls" along the head.
          final localPhase = (pulsePhase + index * 0.08) % 1.0;
          final wave = math.sin(localPhase * 2 * math.pi);
          // Closer = bigger amplitude. 1.0 amplitude at distance 0,
          // 0 at distance 3+.
          final intensity = (1.0 - distance / 3.0).clamp(0.0, 1.0);
          scale = 1.0 + 0.18 * intensity * wave;
        }
      }
      final barHeight = (size.height * (0.18 + value * 0.78) * scale)
          .clamp(4.0, size.height)
          .toDouble();
      final x = startX + index * (barWidth + gap);
      final rect = Rect.fromLTWH(
        x,
        centerY - barHeight / 2,
        barWidth,
        barHeight,
      );
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
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.pulsePhase != pulsePhase ||
        oldDelegate.isPlaying != isPlaying;
  }
}
