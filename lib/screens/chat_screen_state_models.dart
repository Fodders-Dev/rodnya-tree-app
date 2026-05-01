part of 'chat_screen.dart';

typedef _OutgoingMessage = ChatPendingMessage;
typedef _OutgoingMessageStatus = ChatPendingMessageStatus;

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
