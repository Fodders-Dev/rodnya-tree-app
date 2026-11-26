import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';

/// Draggable picture-in-picture video tile for 1:1 calls with magnetic
/// horizontal edge snap and tap-to-swap with the main stage.
class CallDraggablePip extends StatefulWidget {
  const CallDraggablePip({
    super.key,
    required this.localTrack,
    required this.remoteTrack,
    required this.pipShowsLocal,
    required this.isFrontCamera,
    required this.onSwap,
  });

  final VideoTrack localTrack;
  final VideoTrack? remoteTrack;
  final bool pipShowsLocal;
  final bool isFrontCamera;
  final VoidCallback onSwap;

  @override
  State<CallDraggablePip> createState() => _CallDraggablePipState();
}

class _CallDraggablePipState extends State<CallDraggablePip> {
  static const double _pipWidth = 120;
  static const double _pipHeight = 180;
  // Drag-vs-tap disambiguation threshold для PIP gesture. Был 6.0 —
  // на slow swipe чувствовался «stuck» (Bug 4 audit 2026-05-22:
  // Артёма «окошки не двигаются»). 3.0 dp ≈ 4 physical px на 400ppi
  // displays: comfortably выше touchscreen jitter (1-2 px) и
  // intentional drag intent covers это в <50ms. Apple HIG suggests
  // 3.5pt minimum для drag detection — мы matched. Material
  // kTouchSlop default = 18.0 (намного больше) — мы intentionally
  // sub-system slop потому что `dragStartBehavior: DragStartBehavior.down`
  // уже bypassed system slop ↓ в GestureDetector.
  static const double _pipDragCommitThresholdDp = 3.0;

  Offset? _pipOffset;
  Offset? _pipDragStartOffset;
  Offset _pipDragAccumulated = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final pad = media.padding;
    // Default position: bottom-right, 16dp inside the safe area.
    final defaultOffset = Offset(
      size.width - _pipWidth - 16,
      size.height - _pipHeight - 16 - pad.bottom - 96,
    );
    final offset = _pipOffset ?? defaultOffset;
    // Currently-rendered feed in the PIP — swap flips this.
    final showLocal = widget.pipShowsLocal;
    final track = showLocal
        ? widget.localTrack
        : (widget.remoteTrack ?? widget.localTrack);
    final mirror = showLocal && widget.isFrontCamera;
    final fit = showLocal ? VideoViewFit.cover : VideoViewFit.contain;

    return Positioned(
      left: offset.dx,
      top: offset.dy,
      width: _pipWidth,
      height: _pipHeight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // dragStartBehavior.down → drag begins on touch-down without
        // the default 18px slop wait. Was the cause of "сначала надо
        // зажать и тянуть" — slop made the first finger movement
        // feel unresponsive.
        dragStartBehavior: DragStartBehavior.down,
        onTap: () {
          // Tap → swap which feed lives in the PIP. Only meaningful
          // when there's a remote track to swap with; otherwise the
          // tap is a no-op (PIP just shows local).
          if (widget.remoteTrack == null) return;
          HapticFeedback.lightImpact();
          widget.onSwap();
        },
        onPanStart: (details) {
          _pipDragStartOffset = offset;
          _pipDragAccumulated = Offset.zero;
        },
        onPanUpdate: (details) {
          _pipDragAccumulated += details.delta;
          // Quick taps hit a few px of jitter before lifting. Treat
          // anything under threshold as "still a tap" — onPanEnd then
          // routes back through onTap. Past threshold we commit the
          // drag. Threshold lowered к 3dp (was 6) для snappier feel —
          // Bug 4 audit 2026-05-22.
          if (_pipDragAccumulated.distance < _pipDragCommitThresholdDp) {
            return;
          }
          final next = (_pipDragStartOffset ?? offset) + _pipDragAccumulated;
          // Clamp to viewport (minus PIP size + 8dp gutter so the
          // tile never disappears off the edge).
          final clamped = Offset(
            next.dx.clamp(8.0, size.width - _pipWidth - 8.0),
            next.dy.clamp(
              pad.top + 8.0,
              size.height - _pipHeight - pad.bottom - 8.0,
            ),
          );
          setState(() => _pipOffset = clamped);
        },
        onPanEnd: (details) {
          // If the user barely moved, treat as a tap-swap. Same
          // threshold as onPanUpdate commit — symmetry between
          // «moved enough to drag» and «moved too much for tap».
          if (_pipDragAccumulated.distance < _pipDragCommitThresholdDp) {
            if (widget.remoteTrack != null) {
              HapticFeedback.lightImpact();
              widget.onSwap();
            }
            _pipDragStartOffset = null;
            return;
          }
          // Snap to nearest horizontal edge (left or right) for the
          // TG / WA "magnet" feel — vertical position stays where the
          // user dropped it.
          final mid = size.width / 2;
          final snapX = offset.dx + _pipWidth / 2 < mid
              ? 8.0
              : size.width - _pipWidth - 8.0;
          setState(() => _pipOffset = Offset(snapX, offset.dy));
          _pipDragStartOffset = null;
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.42),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: VideoTrackRenderer(
              track,
              fit: fit,
              mirrorMode:
                  mirror ? VideoViewMirrorMode.mirror : VideoViewMirrorMode.off,
            ),
          ),
        ),
      ),
    );
  }
}
