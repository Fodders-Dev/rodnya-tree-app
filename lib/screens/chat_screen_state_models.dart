part of 'chat_screen.dart';

enum _OutgoingMessageStatus { pending, sent, failed }

class _OutgoingStatusMeta {
  const _OutgoingStatusMeta({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color? color;
}

class _OutgoingMessage {
  const _OutgoingMessage({
    required this.localId,
    required this.senderId,
    required this.text,
    required this.timestamp,
    required this.attachments,
    required this.forwardedAttachments,
    required this.status,
    this.replyTo,
    this.progress,
    this.errorText,
  });

  final String localId;
  final String senderId;
  final String text;
  final DateTime timestamp;
  final List<XFile> attachments;
  final List<ChatAttachment> forwardedAttachments;
  final _OutgoingMessageStatus status;
  final ChatReplyReference? replyTo;
  final ChatSendProgress? progress;
  final String? errorText;

  _OutgoingMessage copyWith({
    _OutgoingMessageStatus? status,
    ChatSendProgress? progress,
    String? errorText,
  }) {
    return _OutgoingMessage(
      localId: localId,
      senderId: senderId,
      text: text,
      timestamp: timestamp,
      attachments: attachments,
      forwardedAttachments: forwardedAttachments,
      status: status ?? this.status,
      replyTo: replyTo,
      progress: progress ?? this.progress,
      errorText: errorText,
    );
  }
}
