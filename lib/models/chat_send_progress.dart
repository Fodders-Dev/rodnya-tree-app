enum ChatSendProgressStage { preparing, uploading, sending }

class ChatSendProgress {
  const ChatSendProgress({
    required this.stage,
    required this.completed,
    required this.total,
  });

  final ChatSendProgressStage stage;
  final int completed;
  final int total;

  double? get value {
    // Per-FILE progress (completed/total) is only a meaningful DETERMINATE bar
    // with 2+ files AND at least one already done. A single attachment has no
    // granularity — it sits at 0 until the instant it finishes — and the
    // completed==0 window looks frozen. Return null in both cases so the UI
    // shows an indeterminate (animated) bar instead of a stuck 0%.
    if (total <= 1 || completed <= 0) {
      return null;
    }
    final normalized = completed.clamp(0, total);
    return normalized / total;
  }
}
