import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

import '../../utils/photo_url.dart';
import 'call_formatters.dart';

/// Full-stage local-camera renderer used when the PIP swap puts the
/// local track on the main stage. Mirror always on (front camera
/// case) — back camera swap is rare and would require dynamic
/// detection here.
class LocalFullStage extends StatelessWidget {
  const LocalFullStage({super.key, required this.track, required this.mirror});

  final VideoTrack track;
  final bool mirror;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Colors.black),
      child: VideoTrackRenderer(
        track,
        fit: VideoViewFit.cover,
        mirrorMode:
            mirror ? VideoViewMirrorMode.mirror : VideoViewMirrorMode.off,
      ),
    );
  }
}

/// Remote-видео с динамическим fit'ом по живым размерам кадра.
///
/// В livekit_client 2.7.0 нет события об изменении dimensions
/// publication'а, а `renderer.onResize` безусловно перезаписывается
/// внутри VideoTrackRenderer._attach — поэтому заводим СВОЙ
/// RTCVideoRenderer (он ValueNotifier: didTextureChangeVideoSize /
/// Rotation дёргают notifyListeners) и отдаём его как cachedRenderer.
/// autoDisposeRenderer:false — им владеем мы, dispose наш.
class AdaptiveFitVideo extends StatefulWidget {
  const AdaptiveFitVideo({
    super.key,
    required this.track,
    this.mirror = false,
  });

  final VideoTrack track;
  final bool mirror;

  @override
  State<AdaptiveFitVideo> createState() => _AdaptiveFitVideoState();
}

class _AdaptiveFitVideoState extends State<AdaptiveFitVideo> {
  rtc.RTCVideoRenderer? _renderer;
  double? _videoAspect;

  @override
  void initState() {
    super.initState();
    unawaited(_initRenderer());
  }

  Future<void> _initRenderer() async {
    final renderer = rtc.RTCVideoRenderer();
    try {
      await renderer.initialize();
    } catch (_) {
      // Нет текстур (flutter_test / экзотическая платформа) — остаёмся
      // на fallback-рендере со статичным contain.
      unawaited(renderer.dispose());
      return;
    }
    if (!mounted) {
      unawaited(renderer.dispose());
      return;
    }
    renderer.addListener(_handleFrameMetrics);
    setState(() => _renderer = renderer);
  }

  @override
  void didUpdateWidget(covariant AdaptiveFitVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.track, widget.track)) {
      // Плитка получила другой трек (reorder в группе) — аспект старого
      // трека больше не факт; до первых кадров нового — contain.
      _videoAspect = null;
    }
  }

  void _handleFrameMetrics() {
    final value = _renderer?.value;
    if (value == null || value.width <= 0 || value.height <= 0) {
      return;
    }
    final aspect = value.aspectRatio; // rotation-aware
    if (aspect == _videoAspect || !mounted) {
      return;
    }
    setState(() => _videoAspect = aspect);
  }

  @override
  void dispose() {
    _renderer?.removeListener(_handleFrameMetrics);
    unawaited(_renderer?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final renderer = _renderer;
    if (renderer == null) {
      // Инициализация renderer'а — миллисекунды (раньше первого кадра);
      // до готовности и при сбое — прежний contain-путь. ValueKey ниже
      // форсит remount при готовности: VideoTrackRenderer не подхватывает
      // смену cachedRenderer через didUpdateWidget.
      return VideoTrackRenderer(
        widget.track,
        key: const ValueKey('adaptive-fit-fallback'),
        fit: VideoViewFit.contain,
        mirrorMode: widget.mirror
            ? VideoViewMirrorMode.mirror
            : VideoViewMirrorMode.off,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasBoundedStage = constraints.hasBoundedWidth &&
            constraints.hasBoundedHeight &&
            constraints.maxHeight > 0;
        final fit = resolveAdaptiveVideoFit(
          videoAspect: _videoAspect,
          stageAspect: hasBoundedStage
              ? constraints.maxWidth / constraints.maxHeight
              : null,
        );
        return VideoTrackRenderer(
          widget.track,
          key: const ValueKey('adaptive-fit-live'),
          cachedRenderer: renderer,
          autoDisposeRenderer: false,
          fit: fit,
          mirrorMode: widget.mirror
              ? VideoViewMirrorMode.mirror
              : VideoViewMirrorMode.off,
        );
      },
    );
  }
}

class CallStage extends StatelessWidget {
  const CallStage({
    super.key,
    required this.isGroupCall,
    required this.remoteVideoTrack,
    required this.groupVideoTiles,
    required this.fallbackAvatar,
  });

  final bool isGroupCall;
  final VideoTrack? remoteVideoTrack;
  final List<CallVideoTileData> groupVideoTiles;
  final Widget fallbackAvatar;

  @override
  Widget build(BuildContext context) {
    if (isGroupCall && groupVideoTiles.isNotEmpty) {
      // Adaptive grid: scales the column count and aspect ratio so 3,
      // 4, 5+ participants all fit visibly. Was hard-coded to 2-col +
      // 0.88 aspect with `NeverScrollableScrollPhysics`, which dropped
      // tiles 5+ off the bottom of the viewport with no scroll.
      // Bottom padding tightened from 220 → 160 to claw back vertical
      // room for the bigger grids. We keep scrolling enabled when
      // we'd otherwise overflow.
      final count = groupVideoTiles.length;
      final crossAxisCount = count <= 2
          ? 1
          : count <= 4
              ? 2
              : count <= 9
                  ? 3
                  : 4;
      return DecoratedBox(
        decoration: _stageDecoration,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 84, 12, 160),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide =
                    constraints.maxWidth > constraints.maxHeight * 1.18;
                final adaptiveCrossAxisCount =
                    isWide && count <= 4 ? count : crossAxisCount;
                final rowCount = (count / adaptiveCrossAxisCount).ceil();
                const spacing = 10.0;
                final tileWidth = (constraints.maxWidth -
                        spacing * (adaptiveCrossAxisCount - 1)) /
                    adaptiveCrossAxisCount;
                final tileHeight =
                    (constraints.maxHeight - spacing * (rowCount - 1)) /
                        rowCount;
                final adaptiveAspectRatio =
                    (tileWidth / tileHeight).clamp(0.72, 1.85).toDouble();
                final shouldScroll = count > 4 || tileHeight < 132;

                return GridView.builder(
                  physics: shouldScroll
                      ? const ClampingScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: adaptiveCrossAxisCount,
                    crossAxisSpacing: spacing,
                    mainAxisSpacing: spacing,
                    childAspectRatio: adaptiveAspectRatio,
                  ),
                  itemCount: count,
                  itemBuilder: (context, index) => RemoteVideoTile(
                    tile: groupVideoTiles[index],
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    if (remoteVideoTrack != null) {
      return AdaptiveFitVideo(track: remoteVideoTrack!);
    }

    return DecoratedBox(
      decoration: _stageDecoration,
      child: Center(child: fallbackAvatar),
    );
  }

  static const BoxDecoration _stageDecoration = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xFF1A202C),
        Color(0xFF0F1722),
        Color(0xFF201A27),
      ],
    ),
  );
}

class CallVideoTileData {
  const CallVideoTileData({
    required this.track,
    required this.label,
    required this.statusLabel,
    required this.statusColor,
    this.mirror = false,
    this.photoUrl,
    this.isMuted = false,
    this.isSpeaking = false,
  });

  final VideoTrack? track;
  final String label;
  final String statusLabel;
  final Color statusColor;
  final bool mirror;
  final String? photoUrl;
  // GP4: mic muted → mic-off badge; active speaker → highlighted tile border.
  // Camera-off is already conveyed by the avatar fallback (track == null).
  final bool isMuted;
  final bool isSpeaking;
}

class RemoteVideoTile extends StatelessWidget {
  const RemoteVideoTile({
    super.key,
    required this.tile,
  });

  final CallVideoTileData tile;

  @override
  Widget build(BuildContext context) {
    final track = tile.track;
    final theme = Theme.of(context);
    final avatarImage = buildAvatarImageProvider(tile.photoUrl);
    final initial =
        tile.label.trim().isNotEmpty ? tile.label.trim()[0].toUpperCase() : '?';
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          // GP4: active speaker → green highlighted border (2.5px). Inside
          // the ClipRRect a border reads better than a shadow glow (shadows
          // are clipped). Idle tiles keep the faint 1px hairline.
          border: Border.all(
            color: tile.isSpeaking
                ? const Color(0xFF37B24D)
                : Colors.white.withValues(alpha: 0.10),
            width: tile.isSpeaking ? 2.5 : 1,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (track != null)
              AdaptiveFitVideo(track: track, mirror: tile.mirror)
            else
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: Colors.white.withValues(alpha: 0.16),
                      backgroundImage: avatarImage,
                      child: avatarImage == null
                          ? Text(
                              initial,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: tile.statusColor,
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox(width: 8, height: 8),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          tile.statusLabel,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            Positioned(
              left: 10,
              bottom: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.68),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // GP4: mic-off badge in front of the name when muted.
                      if (tile.isMuted) ...[
                        const Icon(
                          Icons.mic_off_rounded,
                          size: 13,
                          color: Color(0xFFFF8787),
                        ),
                        const SizedBox(width: 5),
                      ],
                      Text(
                        tile.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
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
