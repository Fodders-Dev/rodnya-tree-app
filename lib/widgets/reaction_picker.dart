import 'package:flutter/material.dart';

/// Quick-emoji reaction picker — six predefined emojis arranged in a
/// horizontal pill. Used by post / comment cards on long-press to
/// match the IG / FB pattern. Tap an emoji and it returns from the
/// modal route via Navigator.pop(emoji).
///
/// Keep the set small and culture-neutral. Custom emoji picking is
/// out of scope here — would need a full emoji catalogue widget.
class ReactionPicker extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final emoji in emojis)
            _EmojiTile(
              emoji: emoji,
              onTap: () => Navigator.of(context).pop(emoji),
            ),
        ],
      ),
    );
  }
}

class _EmojiTile extends StatelessWidget {
  const _EmojiTile({required this.emoji, required this.onTap});

  final String emoji;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          emoji,
          style: const TextStyle(fontSize: 30, height: 1),
        ),
      ),
    );
  }
}
