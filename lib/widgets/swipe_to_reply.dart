import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Telegram-style swipe-to-reply wrapper for chat bubbles.
///
/// Wraps any bubble widget with horizontal-drag detection. While the
/// user drags right (incoming) or left (outgoing) the bubble follows
/// the finger up to [maxOffset]; once the drag passes [triggerOffset]
/// a reply icon glows in and a haptic blip fires once. On release
/// past the threshold [onReply] is called and the bubble snaps back.
/// Below the threshold it just animates back without firing.
///
/// Drag direction is keyed off [isMe] — own messages slide left so
/// the reply gesture mirrors what Telegram does on the right-aligned
/// bubble side.
class SwipeToReply extends StatefulWidget {
  const SwipeToReply({
    super.key,
    required this.child,
    required this.isMe,
    required this.onReply,
    this.triggerOffset = 60,
    this.maxOffset = 90,
  });

  final Widget child;
  final bool isMe;
  final VoidCallback onReply;
  final double triggerOffset;
  final double maxOffset;

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply>
    with SingleTickerProviderStateMixin {
  late final AnimationController _snapBack;
  double _dragOffset = 0;
  bool _passedTriggerThisDrag = false;

  @override
  void initState() {
    super.initState();
    _snapBack = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        // Drives the bubble back to 0 after the user lifts. We animate
        // by reading the controller's value as a 1.0 → 0.0 multiplier
        // applied to the recorded offset at release.
        setState(() {
          _dragOffset = _snapBackStart * (1 - _snapBack.value);
        });
      });
  }

  double _snapBackStart = 0;

  @override
  void dispose() {
    _snapBack.dispose();
    super.dispose();
  }

  /// Sign of the drag we accept. Own bubbles swipe left → -1; their
  /// bubbles swipe right → +1.
  int get _direction => widget.isMe ? -1 : 1;

  void _onDragUpdate(DragUpdateDetails details) {
    final raw = _dragOffset + details.delta.dx;
    // Clamp to direction-correct range. We only allow drag in the
    // "pull to reply" direction — opposite drag is ignored so it
    // doesn't compete with horizontal scroll fling.
    final signed = _direction > 0 ? raw.clamp(0.0, widget.maxOffset) : raw.clamp(-widget.maxOffset, 0.0);
    if (!_passedTriggerThisDrag &&
        signed.abs() >= widget.triggerOffset) {
      _passedTriggerThisDrag = true;
      // One short tactile blip when we cross the threshold; user
      // knows they've "loaded" the gesture.
      HapticFeedback.lightImpact();
    }
    setState(() => _dragOffset = signed);
  }

  void _onDragEnd(DragEndDetails details) {
    if (_dragOffset.abs() >= widget.triggerOffset) {
      widget.onReply();
    }
    _passedTriggerThisDrag = false;
    _snapBackStart = _dragOffset;
    _snapBack.forward(from: 0);
  }

  void _onDragCancel() {
    _passedTriggerThisDrag = false;
    _snapBackStart = _dragOffset;
    _snapBack.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final progress =
        (_dragOffset.abs() / widget.triggerOffset).clamp(0.0, 1.0);
    final iconOpacity = progress;
    final iconScale = 0.5 + 0.5 * progress;

    return GestureDetector(
      // dragStart: 'down' lets us pick up the gesture before the
      // ListView starts horizontal flick — small move budget so
      // vertical scroll still wins.
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: _onDragCancel,
      behavior: HitTestBehavior.translucent,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
        children: [
          // Reply icon revealing as the user drags. Sits at the edge
          // the bubble is leaving — so on incoming bubbles it's on
          // the leading (left) side, on own bubbles it's trailing
          // (right).
          Positioned(
            left: widget.isMe ? null : 8,
            right: widget.isMe ? 8 : null,
            child: Opacity(
              opacity: iconOpacity,
              child: Transform.scale(
                scale: iconScale,
                child: const Icon(
                  Icons.reply_rounded,
                  size: 20,
                  color: Colors.grey,
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
