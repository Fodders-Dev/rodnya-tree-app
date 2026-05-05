import 'dart:async';

import 'package:flutter/material.dart';

/// Quick-emoji reaction picker — six predefined emojis arranged in a
/// horizontal pill. Used by post / comment cards on long-press to
/// match the IG / FB pattern. Tap an emoji and it returns from the
/// modal route via Navigator.pop(emoji).
///
/// Telegram-style staggered entry: each emoji tile fades + scales +
/// slides up in sequence (kicked off the frame after the sheet's own
/// slide-in beat) so the picker reads as deliberate rather than just
/// appearing. Tap on a tile triggers a tiny "pop" scale before the
/// pop returns the emoji — same satisfying click feel as TG.
class ReactionPicker extends StatefulWidget {
  const ReactionPicker({super.key});

  /// The default reaction set. Roughly mirrors the chat-message
  /// reaction picker so users build muscle memory across surfaces.
  static const List<String> emojis = [
    '❤️',
    '👍',
    '😂',
    '😮',
    '😢',
    '🔥',
  ];

  /// Convenience: show the picker as a bottom sheet and resolve to
  /// the tapped emoji (or null if dismissed).
  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Material(
            color: Theme.of(sheetContext).colorScheme.surface,
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            child: const ReactionPicker(),
          ),
        ),
      ),
    );
  }

  @override
  State<ReactionPicker> createState() => _ReactionPickerState();
}

class _ReactionPickerState extends State<ReactionPicker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entry;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entry.forward();
    });
  }

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final emojis = ReactionPicker.emojis;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (var i = 0; i < emojis.length; i++)
            _EmojiTile(
              emoji: emojis[i],
              entry: _entry,
              index: i,
              total: emojis.length,
              onTap: (emoji) => Navigator.of(context).pop(emoji),
            ),
        ],
      ),
    );
  }
}

class _EmojiTile extends StatefulWidget {
  const _EmojiTile({
    required this.emoji,
    required this.entry,
    required this.index,
    required this.total,
    required this.onTap,
  });

  final String emoji;
  final Animation<double> entry;
  final int index;
  final int total;
  final ValueChanged<String> onTap;

  @override
  State<_EmojiTile> createState() => _EmojiTileState();
}

class _EmojiTileState extends State<_EmojiTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tap;

  @override
  void initState() {
    super.initState();
    _tap = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
  }

  @override
  void dispose() {
    _tap.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    // "Ka-bunce" — quick scale up then return on tap. Adds the same
    // satisfying click feel TG / WA pickers have. Don't await fully
    // before pop or the picker feels laggy; 90ms in is enough.
    unawaited(_tap.forward());
    await Future<void>.delayed(const Duration(milliseconds: 90));
    if (mounted) widget.onTap(widget.emoji);
  }

  @override
  Widget build(BuildContext context) {
    // Stagger: each tile starts ~70ms after its left neighbour. Total
    // window 0.55, last tile finishes near 1.0 of the parent.
    final stride =
        widget.total <= 1 ? 0.0 : 0.4 / (widget.total - 1).clamp(1, 999);
    final start = (widget.index * stride).clamp(0.0, 0.4);
    final entryAnim = CurvedAnimation(
      parent: widget.entry,
      curve: Interval(start, (start + 0.6).clamp(0.0, 1.0),
          curve: Curves.easeOutBack),
    );

    final tapAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.25), weight: 1),
      TweenSequenceItem(
          tween: Tween(begin: 1.25, end: 1.0)
              .chain(CurveTween(curve: Curves.easeOutCubic)),
          weight: 1),
    ]).animate(_tap);

    return InkWell(
      onTap: _handleTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedBuilder(
        animation: Listenable.merge([entryAnim, tapAnim]),
        builder: (context, child) {
          final t = entryAnim.value;
          return Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, (1 - t).clamp(0.0, 1.0) * 12),
              child: Transform.scale(
                scale: (0.7 + 0.3 * t).clamp(0.0, 2.0) * tapAnim.value,
                child: child,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            widget.emoji,
            style: const TextStyle(fontSize: 30, height: 1),
          ),
        ),
      ),
    );
  }
}

