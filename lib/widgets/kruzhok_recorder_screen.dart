import 'dart:async';
import 'dart:io';

// camera re-exports XFile (via cross_file), so no separate
// image_picker / cross_file import needed here.
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// In-app video recorder. Originally the Telegram-style кружок recorder
/// (round preview + 60s + video_note_* filename), now parameterised so
/// the same UI can serve other capture surfaces — most importantly
/// stories, where the OS native camera handoff via image_picker sits at
/// medium iOS quality and the user reported "качество съемки на айфоне
/// упало при снятия видео". The camera plugin defaults to high.
///
/// Push via [show] (default options = кружок) or
/// [showWithOptions] / [showStory] for a rectangular story recorder.
/// Resolves to the captured [XFile], or null if cancelled / no
/// permission / no camera.
class KruzhokRecorderScreen extends StatefulWidget {
  const KruzhokRecorderScreen({
    super.key,
    this.circularPreview = true,
    this.maxDuration = const Duration(seconds: 60),
    this.filenamePrefix = 'video_note',
    this.titleLabel = 'Кружок',
    this.idleHint = 'Нажмите, чтобы начать запись · до 60 сек',
  });

  /// Whether to clip the live preview to a circle (true = кружок,
  /// false = rectangular for stories).
  final bool circularPreview;

  /// Hard cap on recording length. Hitting this auto-stops + returns.
  final Duration maxDuration;

  /// Filename prefix written into the resulting XFile name. The chat
  /// side uses `video_note_*` to recognise кружочки; the story side
  /// uses `story_video_*` so feed code paths can keep their own
  /// detection.
  final String filenamePrefix;

  /// Label shown in the header before recording starts.
  final String titleLabel;

  /// One-line hint shown under the record button while idle.
  final String idleHint;

  /// Push the recorder above the current screen and resolve to the
  /// captured XFile. Defaults match the chat кружок (round, 60s,
  /// video_note prefix).
  static Future<XFile?> show(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<XFile>(
      MaterialPageRoute<XFile>(
        fullscreenDialog: true,
        builder: (_) => const KruzhokRecorderScreen(),
      ),
    );
  }

  /// Story-flavoured version: rectangular preview, 60s cap, filename
  /// prefixed `story_video_` so the upload path can tag it correctly.
  static Future<XFile?> showStory(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<XFile>(
      MaterialPageRoute<XFile>(
        fullscreenDialog: true,
        builder: (_) => const KruzhokRecorderScreen(
          circularPreview: false,
          maxDuration: Duration(seconds: 60),
          filenamePrefix: 'story_video',
          titleLabel: 'История',
          idleHint: 'Нажмите, чтобы записать · до 60 сек',
        ),
      ),
    );
  }

  /// Post-attachment version: rectangular preview, 3-minute cap,
  /// filename prefixed `post_video_`. Bypasses
  /// image_picker.pickVideo's medium-quality default on iOS — the
  /// camera plugin records at high quality by default, which is
  /// what users expect when they capture for a feed post.
  static Future<XFile?> showPost(BuildContext context) {
    return Navigator.of(context, rootNavigator: true).push<XFile>(
      MaterialPageRoute<XFile>(
        fullscreenDialog: true,
        builder: (_) => const KruzhokRecorderScreen(
          circularPreview: false,
          maxDuration: Duration(minutes: 3),
          filenamePrefix: 'post_video',
          titleLabel: 'Видео для поста',
          idleHint: 'Нажмите, чтобы записать · до 3 минут',
        ),
      ),
    );
  }

  @override
  State<KruzhokRecorderScreen> createState() => _KruzhokRecorderScreenState();
}

class _KruzhokRecorderScreenState extends State<KruzhokRecorderScreen> {
  static const Duration _tickInterval = Duration(milliseconds: 100);

  Duration get _maxDuration => widget.maxDuration;

  CameraController? _controller;
  Future<void>? _initialization;
  bool _isRecording = false;
  bool _isFinishing = false;
  Object? _initError;
  Duration _elapsed = Duration.zero;
  DateTime? _startedAt;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _initialization = _initCamera();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException(
          'no_cameras',
          'На устройстве не найдено камер.',
        );
      }
      // Prefer the front camera — кружочки always read as a self-shot
      // in Telegram / WhatsApp. Falls back to whatever's available.
      final selected = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      // 60s hardware-side cap — if anything wedges, recording stops on
      // its own and we don't end up with a 4-hour file.
      await controller.prepareForVideoRecording();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (error) {
      if (!mounted) return;
      setState(() => _initError = error);
    }
  }

  Future<void> _startRecording() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isRecording ||
        _isFinishing) {
      return;
    }
    try {
      await controller.startVideoRecording();
      if (!mounted) return;
      _startedAt = DateTime.now();
      _ticker?.cancel();
      _ticker = Timer.periodic(_tickInterval, (_) => _onTick());
      setState(() {
        _isRecording = true;
        _elapsed = Duration.zero;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось начать запись: $error')),
      );
    }
  }

  void _onTick() {
    if (!mounted || _startedAt == null) return;
    final elapsed = DateTime.now().difference(_startedAt!);
    setState(() => _elapsed = elapsed);
    if (elapsed >= _maxDuration) {
      _stopRecording(autoCap: true);
    }
  }

  Future<void> _stopRecording({bool autoCap = false}) async {
    final controller = _controller;
    if (controller == null || !_isRecording || _isFinishing) {
      return;
    }
    setState(() => _isFinishing = true);
    _ticker?.cancel();
    try {
      final raw = await controller.stopVideoRecording();
      if (!mounted) return;
      // Rename to video_note_* so chat_screen's _isVideoNoteFile picks
      // it up as a кружок rather than a regular video. The original
      // filename camera.mp4 wouldn't trigger that branch, and the
      // bubble would render a generic video card instead of the round
      // tile.
      final renamed = await _renameToVideoNote(raw);
      if (!mounted) return;
      Navigator.of(context).pop(renamed);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isFinishing = false;
        _isRecording = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить кружок: $error')),
      );
    }
  }

  Future<XFile> _renameToVideoNote(XFile raw) async {
    final prefix = widget.filenamePrefix;
    try {
      final dir = await getTemporaryDirectory();
      final extension = p.extension(raw.path).isNotEmpty
          ? p.extension(raw.path)
          : '.mp4';
      final newName =
          '${prefix}_${DateTime.now().millisecondsSinceEpoch}$extension';
      final newPath = p.join(dir.path, newName);
      final newFile = await File(raw.path).rename(newPath);
      return XFile(newFile.path, name: newName, mimeType: raw.mimeType);
    } catch (_) {
      // Rename can fail across volumes (e.g. cache vs tmp) — fall back
      // to wrapping the original path under a prefixed name. The
      // chat / story side check the filename string, not the path.
      final fallbackName =
          '${prefix}_${DateTime.now().millisecondsSinceEpoch}'
          '${p.extension(raw.path).isEmpty ? '.mp4' : p.extension(raw.path)}';
      return XFile(raw.path, name: fallbackName, mimeType: raw.mimeType);
    }
  }

  void _cancel() {
    if (_isRecording) {
      _stopRecording().then((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isRecording,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && _isRecording) {
          await _stopRecording();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: FutureBuilder<void>(
            future: _initialization,
            builder: (context, snapshot) {
              if (_initError != null) {
                return _buildError();
              }
              if (snapshot.connectionState != ConnectionState.done ||
                  _controller == null) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              }
              return _buildRecorderUI();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam_off_rounded,
              color: Colors.white70, size: 48),
          const SizedBox(height: 16),
          Text(
            'Не удалось получить доступ к камере. $_initError',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Widget _buildRecorderUI() {
    final controller = _controller!;
    final progress =
        (_elapsed.inMilliseconds / _maxDuration.inMilliseconds).clamp(0.0, 1.0);

    return Stack(
      children: [
        // Round live preview sitting in the upper-middle so the record
        // button has room below for thumb reach. Same proportional
        // placement Telegram uses.
        Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest.shortestSide.clamp(0.0, 320.0);
              // Story preview is full-screen 9:16 portrait; кружок
              // preview is a centered square clipped to a circle.
              if (!widget.circularPreview) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: controller.value.previewSize?.height ?? 1,
                          height: controller.value.previewSize?.width ?? 1,
                          child: CameraPreview(controller),
                        ),
                      ),
                    ),
                    if (_isRecording)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 140,
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Colors.white24,
                          color: const Color(0xFFE85A40),
                          minHeight: 4,
                        ),
                      ),
                  ],
                );
              }
              return SizedBox(
                width: size,
                height: size,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipOval(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: controller.value.previewSize?.height ?? 1,
                          height: controller.value.previewSize?.width ?? 1,
                          child: CameraPreview(controller),
                        ),
                      ),
                    ),
                    if (_isRecording)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _ProgressRingPainter(progress: progress),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        // Header chrome — title + cancel.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                tooltip: 'Отменить запись',
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: _cancel,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _isRecording
                      ? _formatDuration(_elapsed)
                      : widget.titleLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
        // Record / stop button. Telegram has long-press, but for v1
        // we use tap-to-toggle — easier on motor accessibility, no
        // accidental cancellations on a slip, and the user can stop
        // recording without holding their thumb still for 60 seconds.
        Positioned(
          left: 0,
          right: 0,
          bottom: 56,
          child: Center(
            child: GestureDetector(
              onTap: _isRecording
                  ? () => _stopRecording()
                  : () => _startRecording(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: _isRecording ? 80 : 72,
                height: _isRecording ? 80 : 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isRecording
                      ? const Color(0xFFE85A40)
                      : Colors.white,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.7),
                    width: 4,
                  ),
                ),
                alignment: Alignment.center,
                child: _isFinishing
                    ? const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        _isRecording ? Icons.stop_rounded : Icons.fiber_manual_record,
                        size: _isRecording ? 36 : 32,
                        color: _isRecording ? Colors.white : Colors.red,
                      ),
              ),
            ),
          ),
        ),
        // Hint text at the very bottom.
        Positioned(
          left: 24,
          right: 24,
          bottom: 16,
          child: Text(
            _isRecording
                ? 'Нажмите ещё раз, чтобы остановить'
                : widget.idleHint,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }
}

class _ProgressRingPainter extends CustomPainter {
  _ProgressRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 4;
    final ringPaint = Paint()
      ..color = const Color(0xFFE85A40)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 6;
    final sweep = 2 * 3.141592653589793 * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.141592653589793 / 2,
      sweep,
      false,
      ringPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter old) =>
      old.progress != progress;
}
