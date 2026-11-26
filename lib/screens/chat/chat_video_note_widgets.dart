part of '../chat_screen.dart';

class _VideoNoteTile extends StatefulWidget {
  const _VideoNoteTile({
    required this.label,
    this.previewUrl,
    this.durationLabel,
    this.onTap,
    this.videoSource,
    this.isRemoteSource = false,
  });

  // Telegram chat круглые видео сидят на ~200px iOS / 180dp Android.
  // 168 — комфортная середина для плотности нашего бабла.
  static const double _diameter = 168;

  final String label;
  final String? previewUrl;
  final String? durationLabel;
  final VoidCallback? onTap;

  /// C2: источник видео (remote URL либо локальный путь) для inline-
  /// проигрывания кружка прямо в бабле. Когда задан — тап играет на месте
  /// (как Telegram), без перехода в просмотрщик. Когда null — поведение
  /// прежнее: тап зовёт [onTap].
  final String? videoSource;
  final bool isRemoteSource;

  @override
  State<_VideoNoteTile> createState() => _VideoNoteTileState();
}

class _VideoNoteTileState extends State<_VideoNoteTile> {
  bool _playing = false;

  bool get _canPlayInline =>
      widget.videoSource != null && widget.videoSource!.trim().isNotEmpty;

  void _handleTap() {
    if (_canPlayInline) {
      setState(() => _playing = true);
    } else {
      widget.onTap?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    // C2: после тапа кружок играет на месте — переиспользуем
    // _VideoNotePlayer (V3: авто-плей, tap = play/pause, кольцо прогресса +
    // перемотка, мьют вторичной кнопкой), сжатый до размера бабла.
    // Просмотрщик не открываем.
    if (_playing && _canPlayInline) {
      return Semantics(
        label: widget.label,
        child: SizedBox(
          width: _VideoNoteTile._diameter,
          height: _VideoNoteTile._diameter,
          child: _VideoNotePlayer(
            key: const Key('video-note-inline-player'),
            source: widget.videoSource!,
            isRemoteSource: widget.isRemoteSource,
            posterUrl: widget.previewUrl,
            diameter: _VideoNoteTile._diameter,
          ),
        ),
      );
    }
    return Semantics(
      label: widget.label,
      button: true,
      // SizedBox обязателен: Stack(fit: StackFit.expand) внутри Wrap
      // получает unbounded constraints и валит layout с null-check'ом.
      // Раньше это рушило весь чат в момент когда в сообщении появлялся
      // кружок. Размер впихнут в сам тайл, чтобы новые callers не
      // забыли обернуть.
      child: SizedBox(
        width: _VideoNoteTile._diameter,
        height: _VideoNoteTile._diameter,
        child: ClipOval(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _handleTap,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.previewUrl != null &&
                      widget.previewUrl!.trim().isNotEmpty)
                    _AttachmentImage(
                      url: widget.previewUrl,
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
                  if (widget.durationLabel != null &&
                      widget.durationLabel!.isNotEmpty)
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
                            widget.durationLabel!,
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

class _VideoNotePlayer extends StatefulWidget {
  const _VideoNotePlayer({
    super.key,
    required this.source,
    required this.isRemoteSource,
    this.posterUrl,
    this.diameter = 320,
  });

  final String source;
  final bool isRemoteSource;
  final String? posterUrl;

  /// C2: диаметр круга. 320 — полноэкранный просмотрщик; ~168 — inline в
  /// бабле (играем кружок на месте, как в Telegram).
  final double diameter;

  @override
  State<_VideoNotePlayer> createState() => _VideoNotePlayerState();
}

class _VideoNotePlayerState extends State<_VideoNotePlayer> {
  VideoPlayerController? _controller;
  Future<void>? _initializeFuture;
  bool _isMuted = false;
  // V3 (ревью FR7): идёт перемотка по кольцу — на это время ведём позицию
  // от пальца, а тап не должен трактоваться как play/pause.
  bool _isScrubbing = false;

  @override
  void initState() {
    super.initState();
    final controller = _createController();
    _controller = controller;
    _initializeFuture = _startPlayback(controller);
  }

  VideoPlayerController _createController() {
    final uri = _videoSourceUri(widget.source);
    final controller = widget.isRemoteSource
        ? VideoPlayerController.networkUrl(uri)
        : VideoPlayerController.contentUri(uri);
    controller.addListener(_handleUpdate);
    return controller;
  }

  Future<void> _startPlayback(VideoPlayerController controller) {
    // FR3: ошибка initialize() (битый файл / недоступный URL / кодек)
    // долетит до FutureBuilder.snapshot.hasError → error-UI вместо
    // вечного спиннера. .then не выполнится, activate/play пропускаются.
    return controller.initialize().then((_) async {
      if (!mounted) return;
      // V3 (ревью FR5): НЕ форсим луп — кружок играет один раз, тап =
      // play/pause (как в Telegram). Звук включён, мьют — вторичным контролом.
      await controller.setVolume(1);
      if (!mounted) return;
      // C2c: один inline-плеер за раз — паузим другой кружок/голосовое.
      _InlineMediaPlayback.activate(this, _pauseSelf);
      await controller.play();
    });
  }

  Future<void> _retry() async {
    final old = _controller;
    old?.removeListener(_handleUpdate);
    unawaited(old?.dispose());
    final controller = _createController();
    setState(() {
      _controller = controller;
      _initializeFuture = _startPlayback(controller);
    });
  }

  /// C2c: пауза этого кружка по требованию реестра one-at-a-time.
  /// mounted-гард + null'нутый после dispose контроллер — защита от
  /// вызова на уже-disposed-плеере (pause() на нём кидает в debug/profile).
  void _pauseSelf() {
    if (!mounted) {
      return;
    }
    final controller = _controller;
    if (controller != null &&
        controller.value.isInitialized &&
        controller.value.isPlaying) {
      unawaited(controller.pause());
    }
  }

  @override
  void dispose() {
    // FR2: кружок ушёл с экрана / размонтирован → снимаем регистрацию в
    // реестре и диспоузим контроллер, что останавливает зацикленное
    // видео. Слушателя снимаем ПЕРЕД dispose, чтобы pause/teardown не
    // дёрнул setState в фазе билда (краш «setState during build»).
    _InlineMediaPlayback.resign(this);
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_handleUpdate);
    controller?.dispose();
    super.dispose();
  }

  void _handleUpdate() {
    if (!mounted) return;
    setState(() {});
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

  /// V3 (ревью FR5): основной тап = play/pause (как в Telegram). По концу
  /// (без лупа) тап перезапускает с начала. Старт игры заявляет себя в
  /// one-at-a-time реестре, чтобы заглушить другой играющий кружок/голос.
  Future<void> _togglePlayPause() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final value = controller.value;
    HapticFeedback.selectionClick();
    if (value.isPlaying) {
      await controller.pause();
      return;
    }
    if (value.duration > Duration.zero && value.position >= value.duration) {
      await controller.seekTo(Duration.zero);
    }
    _InlineMediaPlayback.activate(this, _pauseSelf);
    await controller.play();
  }

  /// V3 (ревью FR7): доля длительности из точки касания — угол вокруг центра
  /// кружка (0 — наверху/12 часов, по часовой стрелке).
  double _seekFractionFromLocal(Offset local) {
    final radius = widget.diameter / 2;
    final dx = local.dx - radius;
    final dy = local.dy - radius;
    var angle = math.atan2(dx, -dy);
    if (angle < 0) angle += 2 * math.pi;
    return (angle / (2 * math.pi)).clamp(0.0, 1.0);
  }

  /// FR6 (ревью C3c): касание попало в полосу КОЛЬЦА (наружные ~40% радиуса).
  /// Только такой drag захватывается под перемотку; центр оставляем скроллу
  /// ленты / свайпу PageView.
  bool _isOnSeekRing(Offset local) {
    final radius = widget.diameter / 2;
    if (radius <= 0) return false;
    final dx = local.dx - radius;
    final dy = local.dy - radius;
    final distance = math.sqrt(dx * dx + dy * dy);
    return distance >= radius * 0.6 && distance <= radius * 1.15;
  }

  void _seekToLocal(Offset local) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final duration = controller.value.duration;
    if (duration <= Duration.zero) return;
    final fraction = _seekFractionFromLocal(local);
    unawaited(controller.seekTo(duration * fraction));
  }

  void _onSeekStart(DragStartDetails details) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    _isScrubbing = true;
    _seekToLocal(details.localPosition);
  }

  void _onSeekUpdate(DragUpdateDetails details) {
    if (!_isScrubbing) return;
    _seekToLocal(details.localPosition);
  }

  void _onSeekEnd(DragEndDetails details) {
    _isScrubbing = false;
  }

  /// FR6: доля проигранного (0..1) для кольца прогресса.
  double _playbackFraction(VideoPlayerController controller) {
    final total = controller.value.duration.inMilliseconds;
    if (total <= 0) return 0;
    return (controller.value.position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  /// FR3: круг-плейсхолдер при сбое инициализации видео. Тап — повтор
  /// загрузки (а не мёртвый чёрный круг). Постер, если есть, остаётся
  /// фоном.
  Widget _buildErrorCircle(BuildContext context) {
    return Center(
      child: GestureDetector(
        key: const Key('video-note-error'),
        behavior: HitTestBehavior.opaque,
        onTap: _retry,
        child: ClipOval(
          child: Container(
            width: widget.diameter,
            height: widget.diameter,
            color: Colors.black,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (widget.posterUrl != null && widget.posterUrl!.isNotEmpty)
                  Opacity(
                    opacity: 0.4,
                    child: _AttachmentImage(
                      url: widget.posterUrl,
                      fit: BoxFit.cover,
                    ),
                  ),
                const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded, color: Colors.white, size: 32),
                    SizedBox(height: 4),
                    Text(
                      'Не удалось\nзагрузить',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
        // FR3: сбой инициализации — показываем affordance ошибки с
        // повтором, а не чёрный круг / вечный спиннер без onTap.
        if (snapshot.hasError) {
          return _buildErrorCircle(context);
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: ClipOval(
              child: Container(
                width: widget.diameter,
                height: widget.diameter,
                color: Colors.black,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (widget.posterUrl != null &&
                        widget.posterUrl!.isNotEmpty)
                      _AttachmentImage(
                        url: widget.posterUrl,
                        fit: BoxFit.cover,
                      ),
                    const CircularProgressIndicator(color: Colors.white),
                  ],
                ),
              ),
            ),
          );
        }
        // Кружочек — фиксированный квадрат-в-круг. Клипуем в Oval
        // независимо от исходного aspect ratio: video note по
        // протоколу TG всегда квадратный, но даже если бэкенд отдаст
        // 16:9, мы аккуратно центрируем + кропаем.
        final progress = _playbackFraction(controller);
        final isPlaying = controller.value.isPlaying;
        return Center(
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            // FR5: тап — play/pause. FR6 (ревью C3c): перемотку ведёт
            // кастомный pan-recognizer, который заявляет жест в арене ТОЛЬКО
            // для drag'а ПО кольцу (старт у края). Drag из центра/мимо кольца
            // не захватывается → уступает вертикальному скроллу ленты чата и
            // горизонтальному свайпу PageView-просмотрщика.
            gestures: <Type, GestureRecognizerFactory>{
              TapGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                () => TapGestureRecognizer(),
                (recognizer) => recognizer.onTap = _togglePlayPause,
              ),
              _RingPanGestureRecognizer: GestureRecognizerFactoryWithHandlers<
                  _RingPanGestureRecognizer>(
                () => _RingPanGestureRecognizer(isOnRing: _isOnSeekRing),
                (recognizer) => recognizer
                  ..onStart = _onSeekStart
                  ..onUpdate = _onSeekUpdate
                  ..onEnd = _onSeekEnd,
              ),
            },
            child: SizedBox(
              width: widget.diameter,
              height: widget.diameter,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: widget.diameter,
                      height: widget.diameter,
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: controller.value.size.width <= 0
                              ? 320
                              : controller.value.size.width,
                          height: controller.value.size.height <= 0
                              ? 320
                              : controller.value.size.height,
                          child: VideoPlayer(controller),
                        ),
                      ),
                    ),
                  ),
                  // FR6: кольцо прогресса по окружности кружка.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _VideoNoteProgressRingPainter(
                          progress: progress,
                          color: Colors.white,
                          trackColor: Colors.white.withValues(alpha: 0.28),
                        ),
                      ),
                    ),
                  ),
                  // FR5: центральный индикатор play, когда на паузе.
                  if (!isPlaying)
                    IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.32),
                          shape: BoxShape.circle,
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(
                            Icons.play_circle_fill_rounded,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                      ),
                    ),
                  // FR5: мьют — вторичный мелкий контрол (динамик) в углу.
                  Positioned(
                    right: widget.diameter * 0.10,
                    bottom: widget.diameter * 0.10,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _toggleMute,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isMuted
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
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

/// V3 (ревью FR6): кольцо прогресса по окружности видео-кружка. Дуга от
/// 12 часов по часовой стрелке, синхронна controller.position (репейнт на
/// каждом тике слушателя плеера).
class _VideoNoteProgressRingPainter extends CustomPainter {
  _VideoNoteProgressRingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  static const double stroke = 3;

  final double progress;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - stroke) / 2;
    if (radius <= 0) return;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = trackColor
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    final clamped = progress.clamp(0.0, 1.0);
    if (clamped <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      clamped * 2 * math.pi,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _VideoNoteProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.trackColor != trackColor;
  }
}

/// FR6 (ревью C3c): pan-recognizer перемотки кружка, который ВХОДИТ в арену
/// жестов только если касание началось в полосе кольца ([isOnRing]). Иначе
/// указатель ему не выдаётся — и жест достаётся родителю (вертикальный скролл
/// ленты чата / горизонтальный свайп PageView-просмотрщика), а не крадётся.
class _RingPanGestureRecognizer extends PanGestureRecognizer {
  _RingPanGestureRecognizer({required this.isOnRing});

  final bool Function(Offset localPosition) isOnRing;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    // Не на кольце — не претендуем на жест: указатель не трекается, жест
    // достаётся родителю (скролл ленты / свайп PageView), а не крадётся.
    if (isOnRing(event.localPosition)) {
      super.addAllowedPointer(event);
    }
  }
}

/// Wraps an image in an InteractiveViewer-friendly swipe-down-to-
/// dismiss gesture (TG / iOS Photos pattern).
///
/// Behaviour:
/// * Tracks scale via a [TransformationController]; we dismiss only
///   when the image is at scale 1 (i.e. not zoomed). If the user is
///   zoomed in we let InteractiveViewer keep all pan gestures so they
///   can still look around inside the zoom.
/// * On vertical pan: image follows the finger (Transform.translate)
///   and the surrounding dialog fades proportionally to the drag
///   distance. Past 110dp dismiss-threshold, releasing pops the
///   viewer; below threshold, releasing snaps back.
/// * Builder pattern lets the caller construct the actual image
///   widget (including the InteractiveViewer) so the controller is
///   shared between us (scale-detection) and the viewer
///   (pinch-zoom).
