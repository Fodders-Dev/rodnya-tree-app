part of '../chat_screen.dart';

String _relativeLastSeenLabel(DateTime rawLastSeen) {
  final lastSeen = toLocalForDisplay(rawLastSeen);
  final delta = DateTime.now().difference(lastSeen);
  if (delta.inMinutes < 1) {
    return 'был(а) только что';
  }
  if (delta.inMinutes < 60) {
    return 'был(а) ${delta.inMinutes} мин назад';
  }
  if (delta.inHours < 24) {
    return 'был(а) ${delta.inHours} ч назад';
  }
  if (delta.inDays < 7) {
    return 'был(а) ${delta.inDays} дн назад';
  }
  final date =
      '${lastSeen.day.toString().padLeft(2, '0')}.${lastSeen.month.toString().padLeft(2, '0')}';
  return 'был(а) $date';
}

bool _isVoiceNoteFileName(String value) {
  final normalizedValue = value.trim().toLowerCase();
  return normalizedValue.startsWith('voice_note_') ||
      normalizedValue.startsWith('voice-note-');
}

bool _isVideoNoteFileName(String value) {
  final normalizedValue = value.trim().toLowerCase();
  return normalizedValue.startsWith('video_note_') ||
      normalizedValue.startsWith('video-note-');
}

Duration? _durationFromAttachmentName(String value) {
  final match = RegExp(r'_(\d+)s_').firstMatch(value.trim().toLowerCase());
  final seconds = int.tryParse(match?.group(1) ?? '');
  if (seconds == null || seconds <= 0) {
    return null;
  }
  return Duration(seconds: seconds);
}

String _formatAttachmentDuration(Duration duration) {
  final minutes = duration.inMinutes;
  final seconds = duration.inSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

// ── Recording animation widgets ─────────────────────────────────────────────

/// A small red dot that pulses (opacity + scale) on a 900 ms loop.
/// Self-contained — no parent TickerProvider needed.
