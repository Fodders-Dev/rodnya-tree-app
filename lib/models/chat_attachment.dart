import '../utils/url_utils.dart';

enum ChatAttachmentType {
  image,
  video,
  audio,
  file;

  String get value {
    switch (this) {
      case ChatAttachmentType.image:
        return 'image';
      case ChatAttachmentType.video:
        return 'video';
      case ChatAttachmentType.audio:
        return 'audio';
      case ChatAttachmentType.file:
        return 'file';
    }
  }

  static ChatAttachmentType fromRaw(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'image':
        return ChatAttachmentType.image;
      case 'video':
        return ChatAttachmentType.video;
      case 'audio':
        return ChatAttachmentType.audio;
      default:
        return ChatAttachmentType.file;
    }
  }
}

enum ChatAttachmentPresentation {
  defaultPresentation,
  voiceNote,
  videoNote;

  String get value {
    switch (this) {
      case ChatAttachmentPresentation.defaultPresentation:
        return 'default';
      case ChatAttachmentPresentation.voiceNote:
        return 'voice_note';
      case ChatAttachmentPresentation.videoNote:
        return 'video_note';
    }
  }

  static ChatAttachmentPresentation fromRaw(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'voice_note':
        return ChatAttachmentPresentation.voiceNote;
      case 'video_note':
        return ChatAttachmentPresentation.videoNote;
      default:
        return ChatAttachmentPresentation.defaultPresentation;
    }
  }
}

class ChatAttachment {
  const ChatAttachment({
    required this.type,
    required this.url,
    this.presentation = ChatAttachmentPresentation.defaultPresentation,
    this.mimeType,
    this.fileName,
    this.sizeBytes,
    this.durationMs,
    this.width,
    this.height,
    this.thumbnailUrl,
  });

  final ChatAttachmentType type;
  final String url;
  final ChatAttachmentPresentation presentation;
  final String? mimeType;
  final String? fileName;
  final int? sizeBytes;
  final int? durationMs;
  final int? width;
  final int? height;
  final String? thumbnailUrl;

  bool get isVisual =>
      type == ChatAttachmentType.image || type == ChatAttachmentType.video;
  bool get isVoiceNote =>
      type == ChatAttachmentType.audio &&
      presentation == ChatAttachmentPresentation.voiceNote;
  bool get isVideoNote =>
      type == ChatAttachmentType.video &&
      presentation == ChatAttachmentPresentation.videoNote;

  Map<String, dynamic> toMap() {
    return {
      'type': type.value,
      'url': url,
      if (presentation != ChatAttachmentPresentation.defaultPresentation)
        'presentation': presentation.value,
      if (mimeType != null && mimeType!.isNotEmpty) 'mimeType': mimeType,
      if (fileName != null && fileName!.isNotEmpty) 'fileName': fileName,
      if (sizeBytes != null) 'sizeBytes': sizeBytes,
      if (durationMs != null) 'durationMs': durationMs,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty)
        'thumbnailUrl': thumbnailUrl,
    };
  }

  factory ChatAttachment.fromMap(Map<String, dynamic> map) {
    return ChatAttachment(
      type: ChatAttachmentType.fromRaw(map['type']?.toString()),
      url: UrlUtils.normalizeImageUrl(map['url']?.toString()) ?? '',
      presentation: ChatAttachmentPresentation.fromRaw(
        map['presentation']?.toString(),
      ),
      mimeType: map['mimeType']?.toString(),
      fileName: map['fileName']?.toString(),
      sizeBytes: _asInt(map['sizeBytes']),
      durationMs: _asInt(map['durationMs']),
      width: _asInt(map['width']),
      height: _asInt(map['height']),
      thumbnailUrl: UrlUtils.normalizeImageUrl(map['thumbnailUrl']?.toString()),
    );
  }

  static List<ChatAttachment> listFromDynamic(dynamic raw) {
    if (raw is! List<dynamic>) {
      return const <ChatAttachment>[];
    }

    return raw
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .map(ChatAttachment.fromMap)
        .where((attachment) => attachment.url.trim().isNotEmpty)
        .toList();
  }

  static int? _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }
}
