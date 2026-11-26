part of '../custom_api_chat_service.dart';

mixin _CustomApiChatMediaMixin on _CustomApiChatBase {
  @override
  Future<List<ChatAttachment>> _uploadAttachments(
    List<XFile> attachments, {
    void Function(ChatSendProgress progress)? onProgress,
  }) async {
    if (attachments.isEmpty) {
      return const <ChatAttachment>[];
    }

    final storageService = _storageService ??
        (GetIt.I.isRegistered<StorageServiceInterface>()
            ? GetIt.I<StorageServiceInterface>()
            : null);
    final userId = currentUserId;
    if (storageService == null || userId == null || userId.isEmpty) {
      throw const CustomApiException('Не удалось подготовить вложения');
    }

    onProgress?.call(
      const ChatSendProgress(
        stage: ChatSendProgressStage.preparing,
        completed: 0,
        total: 1,
      ),
    );
    onProgress?.call(
      ChatSendProgress(
        stage: ChatSendProgressStage.uploading,
        completed: 0,
        total: attachments.length,
      ),
    );

    final uploadedAttachments = <ChatAttachment>[];
    for (var index = 0; index < attachments.length; index++) {
      final attachment = attachments[index];
      final initialType = _attachmentTypeForFile(attachment, '');
      final initialPresentation = _attachmentPresentationForFile(
        attachment,
        initialType,
      );
      final useVoiceFolder = _looksLikeVoiceNoteAttachment(attachment);
      final uploadedUrl = await storageService.uploadImage(
        attachment,
        initialPresentation == ChatAttachmentPresentation.voiceNote ||
                useVoiceFolder
            ? 'chat-voice/$userId'
            : 'chat-media/$userId',
      );
      if (uploadedUrl == null || uploadedUrl.isEmpty) {
        throw const CustomApiException('Не удалось загрузить вложение.');
      }
      final attachmentType = _attachmentTypeForFile(attachment, uploadedUrl);
      final presentation = _attachmentPresentationForFile(
        attachment,
        attachmentType,
      );
      final metadata = await _buildAttachmentMetadata(
        attachment,
        attachmentType,
      );
      // V4 (ревью FR3): для исходящего видео генерим постер (первый кадр)
      // и грузим его — thumbnailUrl уезжает в сообщении, поэтому превью
      // видят и отправитель, и получатель. Best-effort: нет постера →
      // остаётся тёмная плитка с play-иконкой.
      final thumbnailUrl = attachmentType == ChatAttachmentType.video
          ? await _buildVideoPosterUrl(attachment, storageService, userId)
          : null;
      uploadedAttachments.add(
        ChatAttachment(
          type: attachmentType,
          url: uploadedUrl,
          presentation: presentation,
          mimeType: attachment.mimeType,
          fileName: _attachmentFileName(attachment, uploadedUrl),
          sizeBytes: await attachment.length(),
          durationMs: metadata.durationMs,
          waveform: metadata.waveform,
          width: metadata.width,
          height: metadata.height,
          thumbnailUrl: thumbnailUrl,
        ),
      );
      onProgress?.call(
        ChatSendProgress(
          stage: ChatSendProgressStage.uploading,
          completed: index + 1,
          total: attachments.length,
        ),
      );
    }
    return uploadedAttachments;
  }

  /// V4 (ревью FR3): постер (первый кадр) локального видео → загруженный URL.
  /// Только не-web (video_thumbnail — нативный MediaMetadataRetriever на
  /// Android). Любой сбой → null: получим тёмную плитку с play-иконкой, но
  /// отправку видео не ломаем.
  Future<String?> _buildVideoPosterUrl(
    XFile attachment,
    StorageServiceInterface storageService,
    String userId,
  ) async {
    if (kIsWeb) {
      return null;
    }
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: attachment.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 720,
        quality: 70,
      );
      if (bytes == null || bytes.isEmpty) {
        return null;
      }
      final poster = XFile.fromData(
        bytes,
        name: 'poster_${attachment.name}.jpg',
        mimeType: 'image/jpeg',
      );
      return await storageService.uploadImage(poster, 'chat-media/$userId');
    } catch (_) {
      return null;
    }
  }

  Future<_UploadedAttachmentMetadata> _buildAttachmentMetadata(
    XFile attachment,
    ChatAttachmentType type,
  ) async {
    if (type == ChatAttachmentType.audio) {
      return _UploadedAttachmentMetadata(
        durationMs: _durationFromAttachmentName(attachment.name),
        waveform: await _buildVoiceWaveform(attachment),
      );
    }
    if (type != ChatAttachmentType.video) {
      return const _UploadedAttachmentMetadata();
    }

    final sourceUri = _attachmentUri(attachment.path);
    final controller = _isRemoteLikeUri(sourceUri)
        ? VideoPlayerController.networkUrl(sourceUri)
        : VideoPlayerController.contentUri(sourceUri);
    try {
      await controller.initialize();
      final value = controller.value;
      final durationMs = value.duration.inMilliseconds > 0
          ? value.duration.inMilliseconds
          : null;
      final width = value.size.width > 0 ? value.size.width.round() : null;
      final height = value.size.height > 0 ? value.size.height.round() : null;
      return _UploadedAttachmentMetadata(
        durationMs: durationMs,
        width: width,
        height: height,
      );
    } catch (_) {
      return const _UploadedAttachmentMetadata();
    } finally {
      await controller.dispose();
    }
  }

  Future<List<double>> _buildVoiceWaveform(XFile attachment) async {
    try {
      return buildVoiceWaveformFromBytes(await attachment.readAsBytes());
    } catch (_) {
      return const <double>[];
    }
  }

  ChatAttachmentPresentation _attachmentPresentationForFile(
    XFile attachment,
    ChatAttachmentType type,
  ) {
    if (type == ChatAttachmentType.audio &&
        _looksLikeVoiceNoteAttachment(attachment)) {
      return ChatAttachmentPresentation.voiceNote;
    }
    final normalizedName = attachment.name.toLowerCase().trim();
    if (type == ChatAttachmentType.video &&
        (normalizedName.startsWith('video_note') ||
            normalizedName.startsWith('video-note'))) {
      return ChatAttachmentPresentation.videoNote;
    }
    return ChatAttachmentPresentation.defaultPresentation;
  }

  bool _looksLikeVoiceNoteAttachment(XFile attachment) {
    final candidates = <String>[
      attachment.name,
      attachment.path,
    ].map((value) => value.toLowerCase().trim()).where((value) {
      return value.isNotEmpty;
    });
    return candidates.any((value) =>
        value.startsWith('voice_note') ||
        value.startsWith('voice-note') ||
        value.contains('/voice_note') ||
        value.contains(r'\voice_note') ||
        value.contains('/voice-note') ||
        value.contains(r'\voice-note'));
  }

  ChatAttachmentType _attachmentTypeForFile(
    XFile attachment,
    String uploadedUrl,
  ) {
    final mimeType = (attachment.mimeType ?? '').toLowerCase().trim();
    final name = attachment.name.toLowerCase().trim();
    final url = uploadedUrl.toLowerCase().trim();

    // MIME type is authoritative when present. Web voice notes are
    // `audio/webm` with a `voice_note_*.webm` filename — and `.webm` also
    // lives in the video extension list below. If the extension fall-through
    // wins, a voice message ships as an unplayable «video». So decide by
    // mimeType FIRST; only sniff the extension when there's no usable
    // `<kind>/` mime (e.g. octet-stream from a bare upload).
    if (mimeType.startsWith('image/')) {
      return ChatAttachmentType.image;
    }
    if (mimeType.startsWith('video/')) {
      return ChatAttachmentType.video;
    }
    if (mimeType.startsWith('audio/')) {
      return ChatAttachmentType.audio;
    }

    if (['.jpg', '.jpeg', '.png', '.webp', '.heic', '.gif'].any(
      (ext) => name.endsWith(ext) || url.endsWith(ext),
    )) {
      return ChatAttachmentType.image;
    }
    if (['.mp4', '.mov', '.webm', '.avi', '.mkv'].any(
      (ext) => name.endsWith(ext) || url.endsWith(ext),
    )) {
      return ChatAttachmentType.video;
    }
    if (['.m4a', '.aac', '.mp3', '.wav', '.ogg', '.flac'].any(
      (ext) => name.endsWith(ext) || url.endsWith(ext),
    )) {
      return ChatAttachmentType.audio;
    }

    return ChatAttachmentType.file;
  }

  String? _attachmentFileName(XFile attachment, String uploadedUrl) {
    final name = attachment.name.trim();
    if (name.isNotEmpty) {
      return name;
    }

    final uri = Uri.tryParse(uploadedUrl);
    final lastSegment = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last.trim()
        : '';
    return lastSegment.isNotEmpty ? lastSegment : null;
  }

  int? _durationFromAttachmentName(String rawName) {
    final match = RegExp(r'_(\d+)s_').firstMatch(rawName.trim().toLowerCase());
    final seconds = int.tryParse(match?.group(1) ?? '');
    if (seconds == null || seconds <= 0) {
      return null;
    }
    return Duration(seconds: seconds).inMilliseconds;
  }

  Uri _attachmentUri(String rawPath) {
    final parsedUri = Uri.tryParse(rawPath);
    if (parsedUri != null && parsedUri.hasScheme) {
      return parsedUri;
    }
    return Uri.file(rawPath);
  }

  bool _isRemoteLikeUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https' || scheme == 'blob';
  }
}
