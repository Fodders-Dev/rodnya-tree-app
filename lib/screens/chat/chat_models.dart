part of '../chat_screen.dart';

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

enum _MessageAction {
  react,
  reply,
  forward,
  select,
  pin,
  edit,
  copy,
  openDirect,
  report,
  block,
  retry,
  delete
}

class _ContextMenuActionItem<T> {
  const _ContextMenuActionItem({
    required this.label,
    required this.icon,
    required this.value,
    this.isDestructive = false,
  });

  final String label;
  final IconData icon;
  final T value;
  final bool isDestructive;
}

class _MessageSheetSelection {
  const _MessageSheetSelection({
    required this.action,
    this.emoji,
  });

  final _MessageAction action;
  final String? emoji;
}

class _SafetyReasonChoice {
  const _SafetyReasonChoice({
    required this.reason,
    required this.label,
  });

  final String reason;
  final String label;
}

class _SafetyActionDraft {
  const _SafetyActionDraft({
    required this.reason,
    required this.details,
  });

  final String reason;
  final String details;
}

class _ForwardBatchDraft {
  const _ForwardBatchDraft({
    required this.items,
  });

  final List<_ForwardDraft> items;
}

class _SelectedMessageEntry {
  _SelectedMessageEntry.remote({
    required ChatMessage message,
    required this.displayName,
  })  : remoteMessageId = message.id,
        outgoingLocalId = null,
        senderId = message.senderId,
        text = message.text,
        timestamp = message.timestamp,
        attachments = message.attachments;

  _SelectedMessageEntry.outgoing({
    required _OutgoingMessage message,
    required this.displayName,
    required List<ChatAttachment> normalizedAttachments,
  })  : remoteMessageId = null,
        outgoingLocalId = message.localId,
        senderId = message.senderId,
        text = message.text,
        timestamp = message.timestamp,
        attachments = normalizedAttachments;

  final String? remoteMessageId;
  final String? outgoingLocalId;
  final String senderId;
  final String displayName;
  final String text;
  final DateTime timestamp;
  final List<ChatAttachment> attachments;

  bool canDelete(String currentUserId) {
    if (remoteMessageId != null) {
      return senderId == currentUserId;
    }
    return true;
  }
}

class _AttachmentPreviewItem {
  const _AttachmentPreviewItem.remote({
    required this.id,
    required this.kind,
    required this.source,
    required this.displayName,
    this.thumbnailUrl,
    this.senderLabel,
    this.timestamp,
    this.caption,
    this.isVideoNote = false,
  })  : file = null,
        isRemote = true;

  const _AttachmentPreviewItem.local({
    required this.id,
    required this.kind,
    required this.file,
    required this.displayName,
    this.senderLabel,
    this.timestamp,
    this.caption,
    this.isVideoNote = false,
  })  : source = null,
        thumbnailUrl = null,
        isRemote = false;

  final String id;
  final _ChatAttachmentKind kind;
  final String? source;
  final String? thumbnailUrl;
  final XFile? file;
  final String displayName;
  final bool isRemote;
  final String? senderLabel;
  final DateTime? timestamp;
  final String? caption;

  /// True when this video item should render as a Telegram-style
  /// circular video note (auto-play, loop, tap-mute, no controls)
  /// instead of a regular video file player.
  final bool isVideoNote;

  bool get isVisual =>
      kind == _ChatAttachmentKind.image || kind == _ChatAttachmentKind.video;

  String? get trimmedCaption {
    final value = caption?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }
}

class _GroupChatCandidate {
  const _GroupChatCandidate({
    required this.userId,
    required this.displayName,
    required this.relationLabel,
    this.photoUrl,
  });

  final String userId;
  final String displayName;
  final String relationLabel;
  final String? photoUrl;
}

class _ForwardDraft {
  const _ForwardDraft({
    required this.senderName,
    required this.text,
    required this.attachments,
  });

  final String senderName;
  final String text;
  final List<ChatAttachment> attachments;
}

class _EditDraft {
  const _EditDraft({
    required this.messageId,
    required this.originalText,
    required this.hasAttachments,
  });

  final String messageId;
  final String originalText;
  final bool hasAttachments;
}

enum _ChatAttachmentKind { image, video, audio, other }

_ChatAttachmentKind _chatAttachmentKindFromType(ChatAttachmentType type) {
  switch (type) {
    case ChatAttachmentType.image:
      return _ChatAttachmentKind.image;
    case ChatAttachmentType.video:
      return _ChatAttachmentKind.video;
    case ChatAttachmentType.audio:
      return _ChatAttachmentKind.audio;
    case ChatAttachmentType.file:
      return _ChatAttachmentKind.other;
  }
}

_ChatAttachmentKind _attachmentKindFromAttachment(ChatAttachment attachment) {
  if (attachment.type == ChatAttachmentType.file) {
    return _attachmentKindFromName(attachment.fileName, attachment.url);
  }
  return _chatAttachmentKindFromType(attachment.type);
}

_ChatAttachmentKind _attachmentKindFromXFile(XFile file) {
  final mimeType = file.mimeType?.toLowerCase().trim();
  if (mimeType != null && mimeType.isNotEmpty) {
    if (mimeType.startsWith('image/')) {
      return _ChatAttachmentKind.image;
    }
    if (mimeType.startsWith('video/')) {
      return _ChatAttachmentKind.video;
    }
    if (mimeType.startsWith('audio/')) {
      return _ChatAttachmentKind.audio;
    }
  }

  return _attachmentKindFromName(file.name, file.path);
}

_ChatAttachmentKind _attachmentKindFromName(
  String? preferredName,
  String? fallbackPath,
) {
  final fileName = (preferredName?.trim().isNotEmpty ?? false)
      ? preferredName!.trim()
      : (fallbackPath ?? '');
  final extension = path.extension(fileName).toLowerCase();
  const imageExtensions = <String>{
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
    '.heic',
    '.heif',
  };
  if (imageExtensions.contains(extension)) {
    return _ChatAttachmentKind.image;
  }

  const videoExtensions = <String>{
    '.mp4',
    '.mov',
    '.webm',
    '.m4v',
    '.avi',
    '.mkv',
    '.3gp',
  };
  if (videoExtensions.contains(extension)) {
    return _ChatAttachmentKind.video;
  }

  const audioExtensions = <String>{
    '.mp3',
    '.m4a',
    '.wav',
    '.ogg',
    '.aac',
  };
  if (audioExtensions.contains(extension)) {
    return _ChatAttachmentKind.audio;
  }

  return _ChatAttachmentKind.other;
}

String _displayName(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Файл';
  }
  final normalized = value.split('/').last.split('?').first;
  return normalized.length > 24
      ? '${normalized.substring(0, 21)}...'
      : normalized;
}
