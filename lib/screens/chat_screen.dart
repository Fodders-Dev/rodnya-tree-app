// ignore_for_file: unused_field
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';

import '../backend/interfaces/chat_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/safety_service_interface.dart';
import '../controllers/chat_recording_controller.dart';
import '../controllers/chat_timeline_controller.dart';
import '../models/call_media_mode.dart';
import '../models/chat_attachment.dart';
import '../models/chat_details.dart';
import '../models/chat_message.dart';
import '../models/chat_send_progress.dart';
import '../models/family_tree.dart';
import '../providers/tree_provider.dart';
import '../services/app_status_service.dart';
import '../services/call_coordinator_service.dart';
import '../services/chat_auto_delete_store.dart';
import '../services/chat_draft_store.dart';
import '../services/chat_notification_settings_store.dart';
import '../services/chat_pin_store.dart';
import '../services/chat_reaction_store.dart';
import '../services/custom_api_auth_service.dart';
import '../services/custom_api_realtime_service.dart';
import '../utils/chat_attachment_download.dart';
import '../widgets/glass_panel.dart';
import '../widgets/offline_indicator.dart';

part 'chat_screen_supporting_widgets.dart';

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

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    this.chatId,
    this.otherUserId,
    this.title = 'Чат',
    this.photoUrl,
    this.relativeId,
    this.chatType = 'direct',
    this.pickImages,
    this.pickVideo,
    this.draftStore,
    this.pinStore,
    this.notificationSettingsStore,
    this.reactionStore,
    this.autoDeleteStore,
    this.initialChatDetails,
  }) : assert(
          (chatId != null && chatId != '') ||
              (otherUserId != null && otherUserId != ''),
          'Нужен chatId или otherUserId',
        );

  final String? chatId;
  final String? otherUserId;
  final String title;
  final String? photoUrl;
  final String? relativeId;
  final String chatType;
  final Future<List<XFile>> Function()? pickImages;
  final Future<XFile?> Function()? pickVideo;
  final ChatDraftStore? draftStore;
  final ChatPinStore? pinStore;
  final ChatNotificationSettingsStore? notificationSettingsStore;
  final ChatReactionStore? reactionStore;
  final ChatAutoDeleteStore? autoDeleteStore;
  final ChatDetails? initialChatDetails;

  bool get isGroup => chatType == 'group' || chatType == 'branch';

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const int _maxAttachments = 6;
  static const List<String> _quickReactionEmoji = <String>[
    '👍',
    '❤️',
    '😂',
    '😮',
    '🙏',
    '🔥',
  ];

  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final CallCoordinatorService _callCoordinator =
      GetIt.I<CallCoordinatorService>();
  final ChatServiceInterface _chatService = GetIt.I<ChatServiceInterface>();
  final AppStatusService _appStatusService = GetIt.I<AppStatusService>();
  final SafetyServiceInterface? _safetyService =
      GetIt.I.isRegistered<SafetyServiceInterface>()
          ? GetIt.I<SafetyServiceInterface>()
          : null;
  final ImagePicker _imagePicker = ImagePicker();
  final CustomApiRealtimeService? _realtimeService =
      GetIt.I.isRegistered<CustomApiRealtimeService>()
          ? GetIt.I<CustomApiRealtimeService>()
          : null;

  String? _currentUserId;
  String? _chatId;
  ChatDetails? _chatDetails;
  String? _bootstrapError;
  bool _isBootstrapping = true;
  bool _isLoadingChatDetails = false;
  bool _isMarkingRead = false;
  int _localMessageCounter = 0;
  late String _resolvedTitle;
  final List<XFile> _selectedAttachments = <XFile>[];
  final List<_OutgoingMessage> _optimisticMessages = <_OutgoingMessage>[];
  Timer? _draftSaveTimer;
  bool _isApplyingDraft = false;
  String? _lastPersistedDraftKey;
  final ScrollController _messagesScrollController = ScrollController();
  final GlobalKey _unreadDividerKey = GlobalKey();
  bool _showJumpToLatestButton = false;
  bool _didInitialUnreadJump = false;
  String? _unreadAnchorMessageId;
  ChatReplyReference? _selectedReply;
  _ForwardDraft? _selectedForward;
  _ForwardBatchDraft? _selectedForwardBatch;
  _EditDraft? _selectedEdit;
  bool _isSearchMode = false;
  final Set<String> _selectedRemoteMessageIds = <String>{};
  final Set<String> _selectedOutgoingMessageIds = <String>{};
  bool _browserContextMenuWasEnabled = false;
  bool _isDirectChatBlocked = false;
  String? _directChatBlockedLabel;
  final ChatRecordingController _recordingController =
      ChatRecordingController();
  ChatTimelineController? _timelineController;
  ChatDraftStore get _draftStore =>
      widget.draftStore ?? const SharedPreferencesChatDraftStore();
  ChatNotificationSettingsStore get _notificationSettingsStore =>
      widget.notificationSettingsStore ??
      const SharedPreferencesChatNotificationSettingsStore();
  ChatPinStore get _pinStore =>
      widget.pinStore ?? const SharedPreferencesChatPinStore();
  ChatReactionStore get _reactionStore =>
      widget.reactionStore ?? const SharedPreferencesChatReactionStore();
  ChatAutoDeleteStore get _autoDeleteStore =>
      widget.autoDeleteStore ?? const SharedPreferencesChatAutoDeleteStore();
  ChatNotificationSettingsSnapshot _notificationSettings =
      ChatNotificationSettingsSnapshot.defaults();
  String? _lastPersistedNotificationSettingsKey;
  ChatAutoDeleteSnapshot _autoDeleteSettings =
      ChatAutoDeleteSnapshot.defaults();
  String? _lastPersistedAutoDeleteKey;
  ChatPinnedMessageSnapshot? _pinnedMessage;
  String? _lastPersistedPinKey;
  Map<String, List<ChatMessageReactionEntry>> _messageReactions =
      <String, List<ChatMessageReactionEntry>>{};
  String? _lastPersistedReactionKey;
  List<ChatMessage> _latestRemoteMessages = const <ChatMessage>[];
  final Map<String, GlobalKey> _remoteMessageKeys = <String, GlobalKey>{};
  Timer? _pinnedMessageHighlightTimer;
  String? _highlightedPinnedMessageId;
  StreamSubscription<CustomApiRealtimeEvent>? _realtimeIndicatorsSubscription;
  Timer? _typingHeartbeatTimer;
  Timer? _typingDecayTimer;
  bool _typingHeartbeatActive = false;
  final Map<String, DateTime> _typingUsers = <String, DateTime>{};
  final Set<String> _onlineUserIds = <String>{};
  static const double _recordingLockThreshold = 52;
  static const double _recordingCancelThreshold = 72;

  @override
  void initState() {
    super.initState();
    _chatDetails = widget.initialChatDetails;
    _resolvedTitle = widget.initialChatDetails?.displayTitle ?? widget.title;
    _messageController.addListener(_handleDraftChanged);
    _searchController.addListener(_handleSearchChanged);
    _messagesScrollController.addListener(_handleMessagesScroll);
    _recordingController.addListener(_handleRecordingControllerChanged);
    _configureBrowserContextMenu();
    _bootstrapChat();
  }

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    _pinnedMessageHighlightTimer?.cancel();
    _messageController.removeListener(_handleDraftChanged);
    _searchController.removeListener(_handleSearchChanged);
    _messagesScrollController.removeListener(_handleMessagesScroll);
    _messagesScrollController.dispose();
    _messageController.dispose();
    _searchController.dispose();
    _typingHeartbeatTimer?.cancel();
    _typingDecayTimer?.cancel();
    unawaited(_setTypingActive(false, force: true));
    final realtimeSubscription = _realtimeIndicatorsSubscription;
    _realtimeIndicatorsSubscription = null;
    if (realtimeSubscription != null) {
      unawaited(realtimeSubscription.cancel());
    }
    _restoreBrowserContextMenu();
    _recordingController.removeListener(_handleRecordingControllerChanged);
    _recordingController.dispose();
    _timelineController?.dispose();
    super.dispose();
  }

  bool get _isSelectionMode =>
      _selectedRemoteMessageIds.isNotEmpty ||
      _selectedOutgoingMessageIds.isNotEmpty;

  int get _selectedMessageCount =>
      _selectedRemoteMessageIds.length + _selectedOutgoingMessageIds.length;

  void _configureBrowserContextMenu() {
    if (!kIsWeb) {
      return;
    }
    _browserContextMenuWasEnabled = BrowserContextMenu.enabled;
    if (_browserContextMenuWasEnabled) {
      unawaited(BrowserContextMenu.disableContextMenu());
    }
  }

  void _restoreBrowserContextMenu() {
    if (!kIsWeb ||
        !_browserContextMenuWasEnabled ||
        BrowserContextMenu.enabled) {
      return;
    }
    unawaited(BrowserContextMenu.enableContextMenu());
  }

  void _handleRecordingControllerChanged() {
    if (!mounted) {
      return;
    }

    final previewFile = _recordingController.previewFile;
    final shouldKeepPreview =
        _recordingController.state == ChatRecordingState.preview ||
            _recordingController.state == ChatRecordingState.failed;

    setState(() {
      _selectedAttachments.removeWhere(_isRecordedVoiceAttachment);
      if (shouldKeepPreview && previewFile != null) {
        _selectedAttachments
          ..clear()
          ..add(previewFile);
      }
    });
  }

  bool _isRecordedVoiceAttachment(XFile file) {
    final rawName = file.name.trim().isNotEmpty
        ? file.name.trim()
        : path.basename(file.path);
    final normalizedName = rawName.toLowerCase();
    return normalizedName.startsWith('voice_note_') ||
        normalizedName.startsWith('voice-note-');
  }

  bool _isVideoNoteFile(XFile file) {
    final rawName = file.name.trim().isNotEmpty
        ? file.name.trim()
        : path.basename(file.path);
    final normalizedName = rawName.toLowerCase();
    return normalizedName.startsWith('video_note_') ||
        normalizedName.startsWith('video-note-');
  }

  Future<void> _openAttachmentPreviewGallery(
    List<_AttachmentPreviewItem> items, {
    int initialIndex = 0,
  }) async {
    if (items.isEmpty) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => _AttachmentViewerDialog(
        items: items,
        initialIndex: initialIndex.clamp(0, items.length - 1),
        onOpenExternally: _openAttachmentExternally,
        onDownload: _downloadAttachmentToDevice,
      ),
    );
  }

  void _showEmptyAttachmentCategorySnackBar(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> _openChatMediaGallery() async {
    final mediaItems = _remoteAttachmentGalleryItems()
        .where((item) => item.isVisual)
        .toList(growable: false);
    if (mediaItems.isEmpty) {
      _showEmptyAttachmentCategorySnackBar('В этом чате пока нет медиа.');
      return;
    }

    await _openAttachmentPreviewGallery(mediaItems);
  }

  Future<void> _openChatFilesGallery() async {
    final fileItems = _remoteAttachmentGalleryItems()
        .where((item) => !item.isVisual)
        .toList(growable: false);
    if (fileItems.isEmpty) {
      _showEmptyAttachmentCategorySnackBar(
        'В этом чате пока нет документов и голосовых.',
      );
      return;
    }

    await _openAttachmentPreviewGallery(fileItems);
  }

  Future<XFile> _renamePickedVideoAsVideoNote(XFile file) async {
    final originalName = file.name.trim().isNotEmpty
        ? file.name.trim()
        : path.basename(file.path);
    final extension = path.extension(originalName).trim().isNotEmpty
        ? path.extension(originalName).trim()
        : ((file.mimeType ?? '').toLowerCase().contains('webm')
            ? '.webm'
            : '.mp4');
    final nextName =
        'video_note_${DateTime.now().millisecondsSinceEpoch}$extension';
    if (file.path.trim().isNotEmpty) {
      return XFile(
        file.path,
        name: nextName,
        mimeType: file.mimeType,
      );
    }

    return XFile.fromData(
      await file.readAsBytes(),
      name: nextName,
      mimeType: file.mimeType,
    );
  }

  Future<void> _handleRecordingLongPressStart(LongPressStartDetails _) async {
    await _startRecording();
  }

  Future<void> _handleRecordingLongPressMoveUpdate(
    LongPressMoveUpdateDetails details,
  ) async {
    if (_recordingController.state != ChatRecordingState.recording) {
      return;
    }

    if (details.offsetFromOrigin.dx <= -_recordingCancelThreshold) {
      await _cancelRecording();
      return;
    }

    if (details.offsetFromOrigin.dy <= -_recordingLockThreshold) {
      _recordingController.lock();
    }
  }

  Future<void> _handleRecordingLongPressEnd(LongPressEndDetails _) async {
    if (_recordingController.state == ChatRecordingState.recording) {
      await _stopAndSendRecording();
    }
  }

  void _bindTimelineController(String chatId) {
    final currentController = _timelineController;
    if (currentController != null && currentController.chatId == chatId) {
      return;
    }

    currentController?.dispose();
    final nextController = ChatTimelineController(
      chatId: chatId,
      chatService: _chatService,
    );
    _timelineController = nextController;
    unawaited(nextController.start());
    unawaited(_ensureCallRuntimeReady(chatId));
  }

  Future<void> _ensureCallRuntimeReady(String chatId) async {
    await _callCoordinator.ensureRuntimeReady();
    await _callCoordinator.resync(chatId: chatId);
  }

  Future<void> _startCall(CallMediaMode mediaMode) async {
    final chatId = _chatId;
    if (chatId == null || chatId.isEmpty) {
      return;
    }
    try {
      await _callCoordinator.startCall(
        chatId: chatId,
        mediaMode: mediaMode,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  void _exitSelectionMode() {
    if (!_isSelectionMode) {
      return;
    }
    setState(() {
      _selectedRemoteMessageIds.clear();
      _selectedOutgoingMessageIds.clear();
    });
  }

  void _selectRemoteMessage(ChatMessage message) {
    if (_isSearchMode) {
      _closeSearch();
    }
    setState(() {
      _selectedEdit = null;
      _selectedReply = null;
      _selectedForward = null;
      _selectedForwardBatch = null;
      _selectedRemoteMessageIds.add(message.id);
    });
  }

  void _selectOutgoingMessage(_OutgoingMessage message) {
    if (_isSearchMode) {
      _closeSearch();
    }
    setState(() {
      _selectedEdit = null;
      _selectedReply = null;
      _selectedForward = null;
      _selectedForwardBatch = null;
      _selectedOutgoingMessageIds.add(message.localId);
    });
  }

  void _toggleRemoteMessageSelection(ChatMessage message) {
    setState(() {
      if (_selectedRemoteMessageIds.contains(message.id)) {
        _selectedRemoteMessageIds.remove(message.id);
      } else {
        _selectedRemoteMessageIds.add(message.id);
      }
    });
  }

  void _toggleOutgoingMessageSelection(_OutgoingMessage message) {
    setState(() {
      if (_selectedOutgoingMessageIds.contains(message.localId)) {
        _selectedOutgoingMessageIds.remove(message.localId);
      } else {
        _selectedOutgoingMessageIds.add(message.localId);
      }
    });
  }

  List<_SelectedMessageEntry> _selectedMessagesSnapshot() {
    final selectedMessages = <_SelectedMessageEntry>[
      ..._latestRemoteMessages
          .where((message) => _selectedRemoteMessageIds.contains(message.id))
          .map(
            (message) => _SelectedMessageEntry.remote(
              message: message,
              displayName: _senderDisplayNameForMessage(
                senderId: message.senderId,
                senderName: message.senderName,
              ),
            ),
          ),
      ..._optimisticMessages
          .where((message) =>
              _selectedOutgoingMessageIds.contains(message.localId))
          .map(
            (message) => _SelectedMessageEntry.outgoing(
              message: message,
              displayName: _senderDisplayNameForMessage(
                senderId: message.senderId,
                senderName: null,
              ),
              normalizedAttachments: _normalizedOutgoingAttachments(message),
            ),
          ),
    ];
    selectedMessages.sort(
      (left, right) => left.timestamp.compareTo(right.timestamp),
    );
    return selectedMessages;
  }

  String _senderDisplayNameForMessage({
    required String senderId,
    required String? senderName,
  }) {
    final normalizedSenderName = senderName?.trim();
    if (normalizedSenderName != null && normalizedSenderName.isNotEmpty) {
      return normalizedSenderName;
    }
    return _participantLabelForUserId(senderId);
  }

  List<ChatAttachment> _normalizedOutgoingAttachments(
      _OutgoingMessage message) {
    if (message.forwardedAttachments.isNotEmpty) {
      return List<ChatAttachment>.from(message.forwardedAttachments);
    }
    return message.attachments
        .map(
          (file) => ChatAttachment(
            type: _attachmentTypeForDraft(file),
            url: file.path,
            mimeType: file.mimeType,
            fileName: file.name,
          ),
        )
        .toList();
  }

  String _selectedMessagesTranscript(List<_SelectedMessageEntry> messages) {
    final formatter = DateFormat('dd.MM.yyyy H:mm', 'ru');
    return messages.map((message) {
      final body = message.text.trim().isNotEmpty
          ? message.text.trim()
          : _transcriptAttachmentLabel(message.attachments);
      return '[${formatter.format(message.timestamp)}] ${message.displayName}: $body';
    }).join('\n');
  }

  String _transcriptAttachmentLabel(List<ChatAttachment> attachments) {
    if (attachments.isEmpty) {
      return 'Сообщение';
    }

    final counts = <ChatAttachmentType, int>{};
    for (final attachment in attachments) {
      counts.update(attachment.type, (value) => value + 1, ifAbsent: () => 1);
    }

    final labels = <String>[];
    void addLabel(ChatAttachmentType type, String singular, String plural) {
      final count = counts[type];
      if (count == null || count == 0) {
        return;
      }
      labels.add('$count ${count == 1 ? singular : plural}');
    }

    addLabel(ChatAttachmentType.image, 'фото', 'фото');
    addLabel(ChatAttachmentType.video, 'видео', 'видео');
    addLabel(ChatAttachmentType.audio, 'голосовое', 'голосовых');
    addLabel(ChatAttachmentType.file, 'файл', 'файлов');
    return '[вложение: ${labels.join(', ')}]';
  }

  Future<void> _copySelectedMessages() async {
    final selectedMessages = _selectedMessagesSnapshot();
    if (selectedMessages.isEmpty) {
      return;
    }

    await Clipboard.setData(
      ClipboardData(text: _selectedMessagesTranscript(selectedMessages)),
    );
    if (!mounted) {
      return;
    }
    _exitSelectionMode();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          selectedMessages.length == 1
              ? 'Сообщение скопировано'
              : 'Скопировано ${selectedMessages.length} сообщений',
        ),
      ),
    );
  }

  Future<void> _forwardSelectedMessages() async {
    final selectedMessages = _selectedMessagesSnapshot();
    if (selectedMessages.isEmpty) {
      return;
    }

    setState(() {
      _selectedReply = null;
      _selectedEdit = null;
      _selectedForward = null;
      _selectedForwardBatch = _ForwardBatchDraft(
        items: selectedMessages
            .map(
              (message) => _ForwardDraft(
                senderName: message.displayName,
                text: message.text,
                attachments: message.attachments,
              ),
            )
            .toList(),
      );
      _selectedRemoteMessageIds.clear();
      _selectedOutgoingMessageIds.clear();
    });
  }

  Future<void> _deleteSelectedMessages() async {
    final selectedMessages = _selectedMessagesSnapshot();
    if (selectedMessages.isEmpty) {
      return;
    }
    final currentUserId = _currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      return;
    }
    final hasForbiddenMessages = selectedMessages.any(
      (message) => !message.canDelete(currentUserId),
    );
    if (hasForbiddenMessages) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Пока можно удалять только свои сообщения и локальную очередь.'),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          selectedMessages.length == 1
              ? 'Удалить сообщение'
              : 'Удалить ${selectedMessages.length} сообщений',
        ),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }

    final chatId = _chatId;
    if (chatId == null || chatId.isEmpty) {
      return;
    }

    final outgoingIdsToRemove = <String>{};
    for (final message in selectedMessages) {
      if (message.remoteMessageId != null) {
        await _chatService.deleteChatMessage(
          chatId: chatId,
          messageId: message.remoteMessageId!,
        );
        continue;
      }
      if (message.outgoingLocalId != null) {
        outgoingIdsToRemove.add(message.outgoingLocalId!);
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      if (outgoingIdsToRemove.isNotEmpty) {
        _optimisticMessages.removeWhere(
          (message) => outgoingIdsToRemove.contains(message.localId),
        );
      }
      _selectedRemoteMessageIds.clear();
      _selectedOutgoingMessageIds.clear();
    });
  }

  Future<void> _bootstrapChat() async {
    setState(() {
      _isBootstrapping = true;
      _bootstrapError = null;
      _didInitialUnreadJump = false;
      _unreadAnchorMessageId = null;
    });

    try {
      final currentUserId = _chatService.currentUserId;
      if (currentUserId == null || currentUserId.isEmpty) {
        throw StateError('Сессия недоступна');
      }

      String? resolvedChatId = widget.chatId;
      if (resolvedChatId == null || resolvedChatId.isEmpty) {
        final otherUserId = widget.otherUserId;
        if (otherUserId == null || otherUserId.isEmpty) {
          throw StateError('Не удалось определить чат');
        }
        resolvedChatId = await _chatService.getOrCreateChat(otherUserId);
      }
      if (resolvedChatId == null || resolvedChatId.isEmpty) {
        throw StateError('Не удалось определить чат');
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _currentUserId = currentUserId;
        _chatId = resolvedChatId;
        _isBootstrapping = false;
      });

      _bindTimelineController(resolvedChatId);
      _bindRealtimeIndicators();
      unawaited(_restoreBootstrapUiState());
      if (_shouldPrefetchChatDetails()) {
        unawaited(_loadChatDetails());
      }
      unawaited(_markChatAsRead());
    } catch (error) {
      _appStatusService.reportError(
        error,
        fallbackMessage: 'Не удалось открыть чат.',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _bootstrapError = _appStatusService.isOffline
            ? 'Нет соединения. Откройте чат снова, когда интернет вернётся.'
            : 'Не удалось открыть чат. Проверьте соединение и попробуйте снова.';
        _isBootstrapping = false;
      });
    }
  }

  bool _shouldPrefetchChatDetails() {
    if (_chatDetails != null) {
      return false;
    }
    if (widget.isGroup) {
      return true;
    }
    final normalizedTitle = widget.title.trim();
    return normalizedTitle.isEmpty ||
        normalizedTitle == 'Чат' ||
        normalizedTitle == 'Пользователь' ||
        widget.otherUserId == null ||
        widget.otherUserId!.trim().isEmpty;
  }

  Future<void> _restoreBootstrapUiState() async {
    await _runBootstrapTask(
      _restoreReactionsIfNeeded,
      label: 'восстановление реакций',
    );
    await _runBootstrapTask(
      _restorePinnedMessageIfNeeded,
      label: 'восстановление закрепа',
    );
    await _runBootstrapTask(
      _restoreDraftIfNeeded,
      label: 'восстановление черновика',
    );
    unawaited(
      _runBootstrapTask(
        _restoreNotificationSettingsIfNeeded,
        label: 'восстановление настроек уведомлений',
      ),
    );
    unawaited(
      _runBootstrapTask(
        _restoreAutoDeleteSettingsIfNeeded,
        label: 'восстановление автоудаления',
      ),
    );
  }

  Future<void> _runBootstrapTask(
    Future<void> Function() task, {
    required String label,
  }) async {
    try {
      await task();
    } catch (error, stackTrace) {
      debugPrint('ChatScreen: сбой during $label: $error\n$stackTrace');
    }
  }

  Future<void> _loadChatDetails() async {
    final chatId = _chatId;
    if (chatId == null || chatId.isEmpty) {
      return;
    }

    setState(() {
      _isLoadingChatDetails = true;
    });

    try {
      final details = await _chatService.getChatDetails(chatId);
      if (!mounted) {
        return;
      }

      setState(() {
        _chatDetails = details;
        _resolvedTitle = widget.isGroup ? details.displayTitle : _resolvedTitle;
        _isLoadingChatDetails = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingChatDetails = false;
      });
    }
  }

  Future<void> _markChatAsRead() async {
    final chatId = _chatId;
    final userId = _currentUserId;
    if (_isMarkingRead ||
        chatId == null ||
        chatId.isEmpty ||
        userId == null ||
        userId.isEmpty) {
      return;
    }

    _isMarkingRead = true;
    try {
      await _chatService.markChatAsRead(chatId, userId);
    } catch (error, stackTrace) {
      debugPrint(
        'ChatScreen: не удалось отметить чат как прочитанный: $error\n$stackTrace',
      );
    } finally {
      _isMarkingRead = false;
    }
  }

  Future<void> _pickImageAttachments() async {
    if (_selectedEdit != null) {
      setState(() {
        _selectedEdit = null;
      });
    }
    if (_selectedAttachments.any(
      (file) => _attachmentKindFromXFile(file) == _ChatAttachmentKind.audio,
    )) {
      setState(() {
        _selectedAttachments.clear();
      });
    }
    if (_selectedAttachments.length >= _maxAttachments) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Можно прикрепить не более 6 вложений.'),
        ),
      );
      return;
    }

    try {
      final picked = widget.pickImages != null
          ? await widget.pickImages!()
          : await _imagePicker.pickMultiImage(
              imageQuality: 80,
              maxWidth: 1600,
            );
      if (picked.isEmpty || !mounted) {
        return;
      }

      setState(() {
        final hadHeavyMedia = _selectedAttachments.any((f) {
          final kind = _attachmentKindFromXFile(f);
          return kind == _ChatAttachmentKind.video ||
              kind == _ChatAttachmentKind.audio;
        });
        if (hadHeavyMedia) {
          _selectedAttachments.clear();
        }

        final remaining = 6 - _selectedAttachments.length;
        if (picked.length > remaining) {
          _selectedAttachments.addAll(picked.take(remaining));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Можно добавить не более 6 фото.')),
          );
        } else {
          _selectedAttachments.addAll(picked);
        }
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось выбрать фотографии.')),
      );
    }
  }

  Future<void> _pickVideoAttachment({
    ImageSource source = ImageSource.gallery,
    bool asVideoNote = false,
    Duration maxDuration = const Duration(minutes: 10),
  }) async {
    if (_selectedEdit != null) {
      setState(() {
        _selectedEdit = null;
      });
    }
    if (_selectedAttachments.any(
      (file) => _attachmentKindFromXFile(file) == _ChatAttachmentKind.audio,
    )) {
      setState(() {
        _selectedAttachments.clear();
      });
    }
    try {
      final pickedVideo = widget.pickVideo != null
          ? await widget.pickVideo!()
          : await _imagePicker.pickVideo(
              source: source,
              maxDuration: maxDuration,
            );
      if (pickedVideo == null || !mounted) {
        return;
      }

      final picked = asVideoNote
          ? await _renamePickedVideoAsVideoNote(pickedVideo)
          : pickedVideo;

      final size = await picked.length();
      if (size > 50 * 1024 * 1024) {
        // 50MB limit
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Видео слишком большое (макс. 50 МБ).')),
          );
        }
        return;
      }

      setState(() {
        _selectedAttachments.clear();
        _selectedAttachments.add(picked);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            asVideoNote
                ? 'Не удалось подготовить кружок.'
                : 'Не удалось выбрать видео.',
          ),
        ),
      );
    }
  }

  Future<void> _pickVideoNote() {
    return _pickVideoAttachment(
      source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
      asVideoNote: true,
      maxDuration: const Duration(minutes: 2),
    );
  }

  Future<void> _pickGenericFile() async {
    if (_selectedEdit != null) {
      setState(() {
        _selectedEdit = null;
      });
    }
    if (_selectedAttachments.any(
      (file) => _attachmentKindFromXFile(file) == _ChatAttachmentKind.audio,
    )) {
      setState(() {
        _selectedAttachments.clear();
      });
    }
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );

      if (result == null || result.files.isEmpty || !mounted) {
        return;
      }

      final pickedFiles = result.files
          .where((f) => f.path != null)
          .map((f) => XFile(f.path!, name: f.name, bytes: f.bytes))
          .toList();

      if (pickedFiles.isEmpty) return;

      setState(() {
        final remaining = _maxAttachments - _selectedAttachments.length;
        if (pickedFiles.length > remaining) {
          _selectedAttachments.addAll(pickedFiles.take(remaining));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Можно добавить не более 6 файлов.')),
          );
        } else {
          _selectedAttachments.addAll(pickedFiles);
        }
      });
    } catch (e) {
      debugPrint('Error picking file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось выбрать файл.')),
        );
      }
    }
  }

  Future<void> _openAttachmentPicker() async {
    final choice = await showModalBottomSheet<_AttachmentPickerChoice>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Фото'),
                subtitle:
                    const Text('Сожмём перед отправкой, чтобы быстрее дошло'),
                onTap: () => Navigator.of(context).pop(
                  _AttachmentPickerChoice.images,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Видео'),
                subtitle: const Text('Добавится как вложение в чат'),
                onTap: () => Navigator.of(context).pop(
                  _AttachmentPickerChoice.video,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.radio_button_checked_outlined),
                title: const Text('Кружок'),
                subtitle: Text(
                  kIsWeb
                      ? 'Подготовим видеосообщение из файла или камеры'
                      : 'Короткое круглое видеосообщение',
                ),
                onTap: () => Navigator.of(context).pop(
                  _AttachmentPickerChoice.videoNote,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: const Text('Файл'),
                subtitle: const Text('Документы, архивы и другие файлы'),
                onTap: () => Navigator.of(context).pop(
                  _AttachmentPickerChoice.file,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || choice == null) {
      return;
    }

    if (choice == _AttachmentPickerChoice.images) {
      await _pickImageAttachments();
      return;
    }

    if (choice == _AttachmentPickerChoice.video) {
      await _pickVideoAttachment();
      return;
    }

    if (choice == _AttachmentPickerChoice.videoNote) {
      await _pickVideoNote();
      return;
    }

    await _pickGenericFile();
  }

  Future<void> _startRecording() async {
    if (_selectedEdit != null) {
      setState(() {
        _selectedEdit = null;
      });
    }
    if (_selectedAttachments.isNotEmpty) {
      setState(() {
        _selectedAttachments.clear();
      });
    }
    try {
      await _recordingController.start();
    } catch (error) {
      debugPrint('Error starting recording: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось начать запись.')),
        );
      }
    }
  }

  Future<void> _stopAndSendRecording() async {
    await _recordingController.stopToPreview();
  }

  Future<void> _cancelRecording() async {
    await _recordingController.cancelCurrent();
  }

  Future<void> _discardPendingVoiceAttachment() async {
    final voiceAttachment = _selectedAttachments.cast<XFile?>().firstWhere(
          (file) =>
              file != null &&
              _attachmentKindFromXFile(file) == _ChatAttachmentKind.audio,
          orElse: () => null,
        );
    if (voiceAttachment == null) {
      return;
    }
    _recordingController.discardPreview();
    setState(() {
      _selectedAttachments.remove(voiceAttachment);
    });
  }

  Future<void> _rerecordVoiceAttachment() async {
    await _discardPendingVoiceAttachment();
    if (!mounted) {
      return;
    }
    await _startRecording();
  }

  Future<void> _sendCurrentMessage() async {
    final currentUserId = _currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      return;
    }

    final text = _messageController.text.trim();
    final forwardBatch = _selectedForwardBatch;
    if (forwardBatch != null) {
      await _sendForwardBatch(forwardBatch, commentText: text);
      return;
    }
    final attachments = List<XFile>.from(_selectedAttachments);
    final forwardedAttachments = List<ChatAttachment>.from(
        _selectedForward?.attachments ?? const <ChatAttachment>[]);
    final messageText = _composeMessageText(
      typedText: text,
      forwardedText: _selectedForward?.text ?? '',
    );
    final replyTo = _selectedReply;
    final localMessageId = 'local-${_localMessageCounter++}';
    if (messageText.isEmpty &&
        attachments.isEmpty &&
        forwardedAttachments.isEmpty) {
      return;
    }

    if (attachments.any(_isRecordedVoiceAttachment)) {
      _recordingController.markSending();
    }
    _messageController.clear();
    await _setTypingActive(false, force: true);
    await _clearActiveDraft();
    setState(() {
      _selectedAttachments.clear();
      _selectedEdit = null;
      _selectedReply = null;
      _selectedForward = null;
      _optimisticMessages.insert(
        0,
        _OutgoingMessage(
          localId: localMessageId,
          senderId: currentUserId,
          text: messageText,
          timestamp: DateTime.now(),
          attachments: attachments,
          forwardedAttachments: forwardedAttachments,
          status: _OutgoingMessageStatus.pending,
          replyTo: replyTo,
          progress: attachments.isNotEmpty
              ? const ChatSendProgress(
                  stage: ChatSendProgressStage.preparing,
                  completed: 0,
                  total: 1,
                )
              : const ChatSendProgress(
                  stage: ChatSendProgressStage.sending,
                  completed: 1,
                  total: 1,
                ),
        ),
      );
    });

    final pendingMessage = _optimisticMessages.first;
    await _sendOptimisticMessage(pendingMessage);
  }

  Future<void> _sendForwardBatch(
    _ForwardBatchDraft draft, {
    required String commentText,
  }) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      return;
    }

    final batchItems = List<_ForwardDraft>.from(draft.items);
    if (batchItems.isEmpty) {
      return;
    }

    final comment = commentText.trim();
    _messageController.clear();
    await _setTypingActive(false, force: true);
    await _clearActiveDraft();
    setState(() {
      _selectedAttachments.clear();
      _selectedEdit = null;
      _selectedReply = null;
      _selectedForward = null;
      _selectedForwardBatch = null;
    });

    if (comment.isNotEmpty) {
      await _enqueueOutgoingMessageAndSend(
        senderId: currentUserId,
        text: comment,
      );
    }

    for (final item in batchItems) {
      final forwardedText = item.text.trim();
      await _enqueueOutgoingMessageAndSend(
        senderId: currentUserId,
        text: forwardedText,
        forwardedAttachments: item.attachments,
      );
    }
  }

  Future<void> _enqueueOutgoingMessageAndSend({
    required String senderId,
    required String text,
    List<XFile> attachments = const <XFile>[],
    List<ChatAttachment> forwardedAttachments = const <ChatAttachment>[],
    ChatReplyReference? replyTo,
  }) async {
    final localMessageId = 'local-${_localMessageCounter++}';
    final pendingMessage = _OutgoingMessage(
      localId: localMessageId,
      senderId: senderId,
      text: text,
      timestamp: DateTime.now(),
      attachments: attachments,
      forwardedAttachments: forwardedAttachments,
      status: _OutgoingMessageStatus.pending,
      replyTo: replyTo,
      progress: attachments.isNotEmpty
          ? ChatSendProgress(
              stage: ChatSendProgressStage.preparing,
              completed: 0,
              total: attachments.length,
            )
          : const ChatSendProgress(
              stage: ChatSendProgressStage.sending,
              completed: 1,
              total: 1,
            ),
    );

    if (!mounted) {
      return;
    }
    setState(() {
      _optimisticMessages.insert(0, pendingMessage);
    });
    await _sendOptimisticMessage(pendingMessage);
  }

  Future<void> _saveEditedMessage() async {
    final edit = _selectedEdit;
    final chatId = _chatId;
    if (edit == null || chatId == null || chatId.isEmpty) {
      return;
    }

    final nextText = _messageController.text.trim();
    if (nextText.isEmpty && !edit.hasAttachments) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сообщение не должно быть пустым.')),
      );
      return;
    }

    try {
      await _setTypingActive(false, force: true);
      await _chatService.editChatMessage(
        chatId: chatId,
        messageId: edit.messageId,
        text: nextText,
      );
      _messageController.clear();
      await _clearActiveDraft();
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedAttachments.clear();
        _selectedEdit = null;
      });
      _recordingController.discardPreview();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить изменения.')),
      );
    }
  }

  List<String> _draftCandidateKeys() {
    final keys = <String>[];
    final resolvedChatId = _chatId;
    if (resolvedChatId != null && resolvedChatId.isNotEmpty) {
      keys.add(SharedPreferencesChatDraftStore.chatKey(resolvedChatId));
    }
    final widgetChatId = widget.chatId;
    if (widgetChatId != null && widgetChatId.isNotEmpty) {
      keys.add(SharedPreferencesChatDraftStore.chatKey(widgetChatId));
    }
    final otherUserId = widget.otherUserId;
    if (otherUserId != null && otherUserId.isNotEmpty) {
      keys.add(SharedPreferencesChatDraftStore.directUserKey(otherUserId));
    }
    return keys.toSet().toList();
  }

  String? _primaryDraftKey() {
    final resolvedChatId = _chatId;
    if (resolvedChatId != null && resolvedChatId.isNotEmpty) {
      return SharedPreferencesChatDraftStore.chatKey(resolvedChatId);
    }
    final widgetChatId = widget.chatId;
    if (widgetChatId != null && widgetChatId.isNotEmpty) {
      return SharedPreferencesChatDraftStore.chatKey(widgetChatId);
    }
    final otherUserId = widget.otherUserId;
    if (otherUserId != null && otherUserId.isNotEmpty) {
      return SharedPreferencesChatDraftStore.directUserKey(otherUserId);
    }
    return null;
  }

  String _composeMessageText({
    required String typedText,
    required String forwardedText,
  }) {
    final cleanTyped = typedText.trim();
    final cleanForwarded = forwardedText.trim();
    if (cleanTyped.isEmpty) {
      return cleanForwarded;
    }
    if (cleanForwarded.isEmpty) {
      return cleanTyped;
    }
    return '$cleanTyped\n\n$cleanForwarded';
  }

  Future<void> _restoreDraftIfNeeded() async {
    final keys = _draftCandidateKeys();
    if (keys.isEmpty) {
      return;
    }

    ChatDraftSnapshot? bestDraft;
    String? bestDraftKey;
    for (final key in keys) {
      final snapshot = await _draftStore.getDraft(key);
      if (snapshot == null) {
        continue;
      }
      if (bestDraft == null ||
          snapshot.updatedAt.isAfter(bestDraft.updatedAt)) {
        bestDraft = snapshot;
        bestDraftKey = key;
      }
    }

    final preferredKey = _primaryDraftKey();
    if (bestDraft == null) {
      _lastPersistedDraftKey = preferredKey;
      return;
    }

    _isApplyingDraft = true;
    _messageController.value = TextEditingValue(
      text: bestDraft.text,
      selection: TextSelection.collapsed(offset: bestDraft.text.length),
    );
    _isApplyingDraft = false;

    _lastPersistedDraftKey = preferredKey ?? bestDraftKey;
    if (preferredKey != null &&
        bestDraftKey != null &&
        preferredKey != bestDraftKey) {
      await _draftStore.saveDraft(preferredKey, bestDraft.text);
      await _draftStore.clearDraft(bestDraftKey);
    }
  }

  void _handleDraftChanged() {
    if (_isApplyingDraft) {
      return;
    }
    _handleTypingChanged();
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(_persistCurrentDraft());
    });
  }

  Future<void> _persistCurrentDraft() async {
    final draftKey = _primaryDraftKey();
    if (draftKey == null) {
      return;
    }

    final text = _messageController.text;
    if (text.trim().isEmpty) {
      await _draftStore.clearDraft(draftKey);
    } else {
      await _draftStore.saveDraft(draftKey, text);
    }

    final previousKey = _lastPersistedDraftKey;
    _lastPersistedDraftKey = draftKey;
    if (previousKey != null && previousKey != draftKey) {
      await _draftStore.clearDraft(previousKey);
    }
  }

  Future<void> _clearActiveDraft() async {
    final keys = _draftCandidateKeys();
    for (final key in keys) {
      await _draftStore.clearDraft(key);
    }
    _lastPersistedDraftKey = _primaryDraftKey();
  }

  List<String> _reactionCandidateKeys() {
    final keys = <String>[];
    final resolvedChatId = _chatId;
    if (resolvedChatId != null && resolvedChatId.isNotEmpty) {
      keys.add(SharedPreferencesChatReactionStore.chatKey(resolvedChatId));
    }
    final widgetChatId = widget.chatId;
    if (widgetChatId != null && widgetChatId.isNotEmpty) {
      keys.add(SharedPreferencesChatReactionStore.chatKey(widgetChatId));
    }
    final otherUserId = widget.otherUserId;
    if (otherUserId != null && otherUserId.isNotEmpty) {
      keys.add(SharedPreferencesChatReactionStore.directUserKey(otherUserId));
    }
    return keys.toSet().toList();
  }

  String? _primaryReactionKey() {
    final resolvedChatId = _chatId;
    if (resolvedChatId != null && resolvedChatId.isNotEmpty) {
      return SharedPreferencesChatReactionStore.chatKey(resolvedChatId);
    }
    final widgetChatId = widget.chatId;
    if (widgetChatId != null && widgetChatId.isNotEmpty) {
      return SharedPreferencesChatReactionStore.chatKey(widgetChatId);
    }
    final otherUserId = widget.otherUserId;
    if (otherUserId != null && otherUserId.isNotEmpty) {
      return SharedPreferencesChatReactionStore.directUserKey(otherUserId);
    }
    return null;
  }

  Future<void> _restoreReactionsIfNeeded() async {
    final keys = _reactionCandidateKeys();
    if (keys.isEmpty) {
      return;
    }

    ChatReactionCatalogSnapshot? bestSnapshot;
    String? bestKey;
    for (final key in keys) {
      final snapshot = await _reactionStore.getCatalog(key);
      if (snapshot == null) {
        continue;
      }
      if (bestSnapshot == null ||
          snapshot.updatedAt.isAfter(bestSnapshot.updatedAt)) {
        bestSnapshot = snapshot;
        bestKey = key;
      }
    }

    final preferredKey = _primaryReactionKey();
    if (!mounted) {
      return;
    }
    setState(() {
      _messageReactions = bestSnapshot?.reactionsByMessage.map(
            (messageId, entries) => MapEntry(
              messageId,
              List<ChatMessageReactionEntry>.from(entries),
            ),
          ) ??
          <String, List<ChatMessageReactionEntry>>{};
    });

    _lastPersistedReactionKey = preferredKey ?? bestKey;
    if (bestSnapshot != null &&
        preferredKey != null &&
        bestKey != null &&
        preferredKey != bestKey) {
      await _reactionStore.saveCatalog(preferredKey, bestSnapshot);
      await _reactionStore.clearCatalog(bestKey);
    }
  }

  Future<void> _persistReactions() async {
    final reactionKey = _primaryReactionKey();
    if (reactionKey == null) {
      return;
    }

    final cleaned = _messageReactions.map(
      (messageId, entries) => MapEntry(
        messageId,
        entries
            .where(
              (entry) =>
                  entry.messageId.trim().isNotEmpty &&
                  entry.userId.trim().isNotEmpty &&
                  entry.emoji.trim().isNotEmpty,
            )
            .toList(),
      ),
    )..removeWhere((_, entries) => entries.isEmpty);

    final previousKey = _lastPersistedReactionKey;
    _lastPersistedReactionKey = reactionKey;

    if (cleaned.isEmpty) {
      await _reactionStore.clearCatalog(reactionKey);
    } else {
      await _reactionStore.saveCatalog(
        reactionKey,
        ChatReactionCatalogSnapshot(
          updatedAt: DateTime.now(),
          reactionsByMessage: cleaned,
        ),
      );
    }

    if (previousKey != null && previousKey != reactionKey) {
      await _reactionStore.clearCatalog(previousKey);
    }
  }

  List<String> _notificationSettingsCandidateKeys() {
    final keys = <String>[];
    final resolvedChatId = _chatId;
    if (resolvedChatId != null && resolvedChatId.isNotEmpty) {
      keys.add(
        SharedPreferencesChatNotificationSettingsStore.chatKey(resolvedChatId),
      );
    }
    final widgetChatId = widget.chatId;
    if (widgetChatId != null && widgetChatId.isNotEmpty) {
      keys.add(
        SharedPreferencesChatNotificationSettingsStore.chatKey(widgetChatId),
      );
    }
    final otherUserId = widget.otherUserId;
    if (otherUserId != null && otherUserId.isNotEmpty) {
      keys.add(
        SharedPreferencesChatNotificationSettingsStore.directUserKey(
          otherUserId,
        ),
      );
    }
    return keys.toSet().toList();
  }

  String? _primaryNotificationSettingsKey() {
    final resolvedChatId = _chatId;
    if (resolvedChatId != null && resolvedChatId.isNotEmpty) {
      return SharedPreferencesChatNotificationSettingsStore.chatKey(
        resolvedChatId,
      );
    }
    final widgetChatId = widget.chatId;
    if (widgetChatId != null && widgetChatId.isNotEmpty) {
      return SharedPreferencesChatNotificationSettingsStore.chatKey(
        widgetChatId,
      );
    }
    final otherUserId = widget.otherUserId;
    if (otherUserId != null && otherUserId.isNotEmpty) {
      return SharedPreferencesChatNotificationSettingsStore.directUserKey(
        otherUserId,
      );
    }
    return null;
  }

  Future<void> _restoreNotificationSettingsIfNeeded() async {
    final keys = _notificationSettingsCandidateKeys();
    if (keys.isEmpty) {
      return;
    }

    ChatNotificationSettingsSnapshot? bestSnapshot;
    String? bestKey;
    for (final key in keys) {
      final snapshot = await _notificationSettingsStore.getSettings(key);
      if (snapshot == null) {
        continue;
      }
      if (bestSnapshot == null ||
          snapshot.updatedAt.isAfter(bestSnapshot.updatedAt)) {
        bestSnapshot = snapshot;
        bestKey = key;
      }
    }

    final preferredKey = _primaryNotificationSettingsKey();
    final nextSnapshot =
        bestSnapshot ?? ChatNotificationSettingsSnapshot.defaults();
    if (!mounted) {
      return;
    }
    setState(() {
      _notificationSettings = nextSnapshot;
    });

    _lastPersistedNotificationSettingsKey = preferredKey ?? bestKey;
    if (bestSnapshot != null &&
        preferredKey != null &&
        bestKey != null &&
        preferredKey != bestKey) {
      await _notificationSettingsStore.saveSettings(preferredKey, bestSnapshot);
      await _notificationSettingsStore.clearSettings(bestKey);
    }
  }

  List<String> _autoDeleteCandidateKeys() {
    final keys = <String>[];
    final resolvedChatId = _chatId;
    if (resolvedChatId != null && resolvedChatId.isNotEmpty) {
      keys.add(SharedPreferencesChatAutoDeleteStore.chatKey(resolvedChatId));
    }
    final widgetChatId = widget.chatId;
    if (widgetChatId != null && widgetChatId.isNotEmpty) {
      keys.add(SharedPreferencesChatAutoDeleteStore.chatKey(widgetChatId));
    }
    final otherUserId = widget.otherUserId;
    if (otherUserId != null && otherUserId.isNotEmpty) {
      keys.add(SharedPreferencesChatAutoDeleteStore.directUserKey(otherUserId));
    }
    return keys.toSet().toList();
  }

  String? _primaryAutoDeleteKey() {
    final resolvedChatId = _chatId;
    if (resolvedChatId != null && resolvedChatId.isNotEmpty) {
      return SharedPreferencesChatAutoDeleteStore.chatKey(resolvedChatId);
    }
    final widgetChatId = widget.chatId;
    if (widgetChatId != null && widgetChatId.isNotEmpty) {
      return SharedPreferencesChatAutoDeleteStore.chatKey(widgetChatId);
    }
    final otherUserId = widget.otherUserId;
    if (otherUserId != null && otherUserId.isNotEmpty) {
      return SharedPreferencesChatAutoDeleteStore.directUserKey(otherUserId);
    }
    return null;
  }

  Future<void> _restoreAutoDeleteSettingsIfNeeded() async {
    final keys = _autoDeleteCandidateKeys();
    if (keys.isEmpty) {
      return;
    }

    ChatAutoDeleteSnapshot? bestSnapshot;
    String? bestKey;
    for (final key in keys) {
      final snapshot = await _autoDeleteStore.getSettings(key);
      if (snapshot == null) {
        continue;
      }
      if (bestSnapshot == null ||
          snapshot.updatedAt.isAfter(bestSnapshot.updatedAt)) {
        bestSnapshot = snapshot;
        bestKey = key;
      }
    }

    final preferredKey = _primaryAutoDeleteKey();
    final nextSnapshot = bestSnapshot ?? ChatAutoDeleteSnapshot.defaults();
    if (!mounted) {
      return;
    }

    setState(() {
      _autoDeleteSettings = nextSnapshot;
    });

    _lastPersistedAutoDeleteKey = preferredKey ?? bestKey;
    if (bestSnapshot != null &&
        preferredKey != null &&
        bestKey != null &&
        preferredKey != bestKey) {
      await _autoDeleteStore.saveSettings(preferredKey, bestSnapshot);
      await _autoDeleteStore.clearSettings(bestKey);
    }
  }

  Future<void> _updateAutoDeleteOption(ChatAutoDeleteOption option) async {
    final settingsKey = _primaryAutoDeleteKey();
    final nextSnapshot = ChatAutoDeleteSnapshot(
      option: option,
      updatedAt: DateTime.now(),
    );

    if (settingsKey != null) {
      await _autoDeleteStore.saveSettings(settingsKey, nextSnapshot);
      final previousKey = _lastPersistedAutoDeleteKey;
      _lastPersistedAutoDeleteKey = settingsKey;
      if (previousKey != null && previousKey != settingsKey) {
        await _autoDeleteStore.clearSettings(previousKey);
      }
    } else {
      _lastPersistedAutoDeleteKey = null;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _autoDeleteSettings = nextSnapshot;
    });
  }

  Future<void> _persistNotificationSettings(
    ChatNotificationSettingsSnapshot snapshot,
  ) async {
    final settingsKey = _primaryNotificationSettingsKey();
    if (settingsKey == null) {
      return;
    }
    await _notificationSettingsStore.saveSettings(settingsKey, snapshot);
    final previousKey = _lastPersistedNotificationSettingsKey;
    _lastPersistedNotificationSettingsKey = settingsKey;
    if (previousKey != null && previousKey != settingsKey) {
      await _notificationSettingsStore.clearSettings(previousKey);
    }
  }

  Future<void> _updateNotificationLevel(ChatNotificationLevel level) async {
    final nextSnapshot = ChatNotificationSettingsSnapshot(
      level: level,
      updatedAt: DateTime.now(),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _notificationSettings = nextSnapshot;
    });
    await _persistNotificationSettings(nextSnapshot);
    if (!mounted) {
      return;
    }
    String message;
    switch (level) {
      case ChatNotificationLevel.all:
        message = 'Уведомления чата включены';
        break;
      case ChatNotificationLevel.silent:
        message = 'Чат переведен в тихий режим';
        break;
      case ChatNotificationLevel.muted:
        message = 'Уведомления этого чата отключены';
        break;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _currentReactionEmoji(String messageId) {
    final currentUserId = _currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      return '';
    }
    final entries = _messageReactions[messageId] ?? const [];
    final currentReaction =
        entries.cast<ChatMessageReactionEntry?>().firstWhere(
              (entry) => entry?.userId == currentUserId,
              orElse: () => null,
            );
    return currentReaction?.emoji ?? '';
  }

  List<_ReactionGroup> _reactionGroupsForMessage(String messageId) {
    final entries = _messageReactions[messageId] ?? const [];
    if (entries.isEmpty) {
      return const <_ReactionGroup>[];
    }

    final currentUserId = _currentUserId;
    final grouped = <String, _ReactionGroup>{};
    for (final entry in entries) {
      final existing = grouped[entry.emoji];
      if (existing == null) {
        grouped[entry.emoji] = _ReactionGroup(
          emoji: entry.emoji,
          count: 1,
          isMine: currentUserId != null && entry.userId == currentUserId,
        );
        continue;
      }
      grouped[entry.emoji] = _ReactionGroup(
        emoji: existing.emoji,
        count: existing.count + 1,
        isMine: existing.isMine ||
            (currentUserId != null && entry.userId == currentUserId),
      );
    }

    final groups = grouped.values.toList()
      ..sort((left, right) => left.emoji.compareTo(right.emoji));
    return groups;
  }

  Future<void> _toggleReactionForMessage(
      ChatMessage message, String emoji) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null ||
        currentUserId.isEmpty ||
        emoji.trim().isEmpty) {
      return;
    }

    final currentEntries = List<ChatMessageReactionEntry>.from(
        _messageReactions[message.id] ?? const []);
    final currentIndex = currentEntries.indexWhere(
      (entry) => entry.userId == currentUserId,
    );

    if (currentIndex >= 0 && currentEntries[currentIndex].emoji == emoji) {
      currentEntries.removeAt(currentIndex);
    } else {
      final nextEntry = ChatMessageReactionEntry(
        messageId: message.id,
        emoji: emoji,
        userId: currentUserId,
        userName: 'Вы',
        reactedAt: DateTime.now(),
      );
      if (currentIndex >= 0) {
        currentEntries[currentIndex] = nextEntry;
      } else {
        currentEntries.add(nextEntry);
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      if (currentEntries.isEmpty) {
        _messageReactions.remove(message.id);
      } else {
        _messageReactions[message.id] = currentEntries;
      }
    });
    await _persistReactions();
  }

  List<String> _pinCandidateKeys() {
    final keys = <String>[];
    final resolvedChatId = _chatId;
    if (resolvedChatId != null && resolvedChatId.isNotEmpty) {
      keys.add(SharedPreferencesChatPinStore.chatKey(resolvedChatId));
    }
    final widgetChatId = widget.chatId;
    if (widgetChatId != null && widgetChatId.isNotEmpty) {
      keys.add(SharedPreferencesChatPinStore.chatKey(widgetChatId));
    }
    final otherUserId = widget.otherUserId;
    if (otherUserId != null && otherUserId.isNotEmpty) {
      keys.add(SharedPreferencesChatPinStore.directUserKey(otherUserId));
    }
    return keys.toSet().toList();
  }

  String? _primaryPinKey() {
    final resolvedChatId = _chatId;
    if (resolvedChatId != null && resolvedChatId.isNotEmpty) {
      return SharedPreferencesChatPinStore.chatKey(resolvedChatId);
    }
    final widgetChatId = widget.chatId;
    if (widgetChatId != null && widgetChatId.isNotEmpty) {
      return SharedPreferencesChatPinStore.chatKey(widgetChatId);
    }
    final otherUserId = widget.otherUserId;
    if (otherUserId != null && otherUserId.isNotEmpty) {
      return SharedPreferencesChatPinStore.directUserKey(otherUserId);
    }
    return null;
  }

  Future<void> _restorePinnedMessageIfNeeded() async {
    final keys = _pinCandidateKeys();
    if (keys.isEmpty) {
      return;
    }

    ChatPinnedMessageSnapshot? bestSnapshot;
    String? bestKey;
    for (final key in keys) {
      final snapshot = await _pinStore.getPinnedMessage(key);
      if (snapshot == null) {
        continue;
      }
      if (bestSnapshot == null ||
          snapshot.pinnedAt.isAfter(bestSnapshot.pinnedAt)) {
        bestSnapshot = snapshot;
        bestKey = key;
      }
    }

    final preferredKey = _primaryPinKey();
    if (bestSnapshot == null) {
      _lastPersistedPinKey = preferredKey;
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _pinnedMessage = bestSnapshot;
    });

    _lastPersistedPinKey = preferredKey ?? bestKey;
    if (preferredKey != null && bestKey != null && preferredKey != bestKey) {
      await _pinStore.savePinnedMessage(preferredKey, bestSnapshot);
      await _pinStore.clearPinnedMessage(bestKey);
    }
  }

  Future<void> _persistPinnedMessage(
    ChatPinnedMessageSnapshot snapshot,
  ) async {
    final pinKey = _primaryPinKey();
    if (pinKey == null) {
      return;
    }
    await _pinStore.savePinnedMessage(pinKey, snapshot);
    final previousKey = _lastPersistedPinKey;
    _lastPersistedPinKey = pinKey;
    if (previousKey != null && previousKey != pinKey) {
      await _pinStore.clearPinnedMessage(previousKey);
    }
  }

  Future<void> _clearPinnedMessage() async {
    final keys = _pinCandidateKeys();
    for (final key in keys) {
      await _pinStore.clearPinnedMessage(key);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _pinnedMessage = null;
      _highlightedPinnedMessageId = null;
    });
    _lastPersistedPinKey = _primaryPinKey();
  }

  ChatPinnedMessageSnapshot _snapshotFromMessage(ChatMessage message) {
    return ChatPinnedMessageSnapshot(
      messageId: message.id,
      senderId: message.senderId,
      senderName:
          _groupSenderLabel(message.senderName, message.senderId) ?? 'Участник',
      text: message.text,
      attachmentCount: message.attachments.length,
      pinnedAt: DateTime.now(),
    );
  }

  bool _isSamePinnedMessage(
    ChatPinnedMessageSnapshot first,
    ChatPinnedMessageSnapshot second,
  ) {
    return first.messageId == second.messageId &&
        first.senderId == second.senderId &&
        first.senderName == second.senderName &&
        first.text == second.text &&
        first.attachmentCount == second.attachmentCount;
  }

  Future<void> _pinRemoteMessage(ChatMessage message) async {
    final snapshot = _snapshotFromMessage(message);
    if (!mounted) {
      return;
    }
    setState(() {
      _pinnedMessage = snapshot;
    });
    await _persistPinnedMessage(snapshot);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Сообщение закреплено')),
    );
  }

  void _schedulePinnedSync(List<ChatMessage> remoteMessages) {
    final pinned = _pinnedMessage;
    if (pinned == null) {
      return;
    }
    final match = remoteMessages
        .where((message) => message.id == pinned.messageId)
        .cast<ChatMessage?>()
        .firstWhere((message) => message != null, orElse: () => null);

    if (match == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _pinnedMessage?.messageId != pinned.messageId) {
          return;
        }
        unawaited(_clearPinnedMessage());
      });
      return;
    }

    final nextSnapshot = pinned.copyWith(
      senderId: match.senderId,
      senderName: _groupSenderLabel(match.senderName, match.senderId) ??
          pinned.senderName,
      text: match.text,
      attachmentCount: match.attachments.length,
    );
    if (_isSamePinnedMessage(nextSnapshot, pinned)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pinnedMessage?.messageId != pinned.messageId) {
        return;
      }
      setState(() {
        _pinnedMessage = nextSnapshot;
      });
      unawaited(_persistPinnedMessage(nextSnapshot));
    });
  }

  void _bindRealtimeIndicators() {
    if (_realtimeService == null || _realtimeIndicatorsSubscription != null) {
      return;
    }

    unawaited(_realtimeService!.connect());
    _realtimeIndicatorsSubscription =
        _realtimeService!.events.listen(_handleRealtimeIndicatorEvent);
  }

  void _handleRealtimeIndicatorEvent(CustomApiRealtimeEvent event) {
    final currentChatId = _chatId;
    if (!mounted) {
      return;
    }

    if (event.type == 'connection.ready') {
      setState(() {
        _onlineUserIds
          ..clear()
          ..addAll(event.onlineUserIds);
      });
      return;
    }

    if (event.type == 'presence.updated') {
      final userId = event.userId;
      if (userId == null || userId.isEmpty) {
        return;
      }
      setState(() {
        if (event.isOnline == true) {
          _onlineUserIds.add(userId);
        } else {
          _onlineUserIds.remove(userId);
          _typingUsers.remove(userId);
        }
      });
      return;
    }

    if (event.type == 'chat.typing.updated' &&
        currentChatId != null &&
        event.chatId == currentChatId) {
      final userId = event.userId;
      if (userId == null ||
          userId.isEmpty ||
          userId == _currentUserId ||
          event.isTyping == null) {
        return;
      }

      setState(() {
        if (event.isTyping == true) {
          _typingUsers[userId] = DateTime.now().add(const Duration(seconds: 4));
          _onlineUserIds.add(userId);
          _ensureTypingDecayTimer();
        } else {
          _typingUsers.remove(userId);
        }
      });
    }
  }

  void _ensureTypingDecayTimer() {
    _typingDecayTimer ??=
        Timer.periodic(const Duration(seconds: 1), (_) => _pruneTypingUsers());
  }

  void _pruneTypingUsers() {
    if (!mounted) {
      _typingDecayTimer?.cancel();
      _typingDecayTimer = null;
      return;
    }

    final now = DateTime.now();
    final expiredUserIds = _typingUsers.entries
        .where((entry) => !entry.value.isAfter(now))
        .map((entry) => entry.key)
        .toList();
    if (expiredUserIds.isEmpty) {
      return;
    }

    setState(() {
      for (final userId in expiredUserIds) {
        _typingUsers.remove(userId);
      }
      if (_typingUsers.isEmpty) {
        _typingDecayTimer?.cancel();
        _typingDecayTimer = null;
      }
    });
  }

  void _handleTypingChanged() {
    final hasInput = _messageController.text.trim().isNotEmpty;
    if (hasInput) {
      unawaited(_setTypingActive(true));
    } else {
      unawaited(_setTypingActive(false));
    }
  }

  Future<void> _setTypingActive(bool isTyping, {bool force = false}) async {
    final chatId = _chatId;
    if (_realtimeService == null || chatId == null || chatId.isEmpty) {
      return;
    }

    if (!force && _typingHeartbeatActive == isTyping) {
      return;
    }

    _typingHeartbeatActive = isTyping;
    if (isTyping) {
      _typingHeartbeatTimer?.cancel();
      await _realtimeService!.sendTypingState(chatId: chatId, isTyping: true);
      _typingHeartbeatTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) {
          final stillTyping = _messageController.text.trim().isNotEmpty;
          if (!stillTyping) {
            unawaited(_setTypingActive(false));
            return;
          }
          unawaited(
            _realtimeService!.sendTypingState(chatId: chatId, isTyping: true),
          );
        },
      );
      return;
    }

    _typingHeartbeatTimer?.cancel();
    _typingHeartbeatTimer = null;
    await _realtimeService!.sendTypingState(chatId: chatId, isTyping: false);
  }

  String _pinnedPreviewLabel(ChatPinnedMessageSnapshot snapshot) {
    final text = snapshot.text.trim();
    if (text.isNotEmpty) {
      return text;
    }
    if (snapshot.attachmentCount > 0) {
      return _attachmentCountLabel(snapshot.attachmentCount);
    }
    return 'Сообщение без текста';
  }

  void _highlightPinnedMessage(String messageId) {
    _pinnedMessageHighlightTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      _highlightedPinnedMessageId = messageId;
    });
    _pinnedMessageHighlightTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || _highlightedPinnedMessageId != messageId) {
        return;
      }
      setState(() {
        _highlightedPinnedMessageId = null;
      });
    });
  }

  Future<void> _focusPinnedMessage() async {
    final pinned = _pinnedMessage;
    if (pinned == null) {
      return;
    }

    if (_isSearchMode) {
      _closeSearch();
    }

    final visibleContext = _remoteMessageKeys[pinned.messageId]?.currentContext;
    if (visibleContext != null) {
      _highlightPinnedMessage(pinned.messageId);
      await Scrollable.ensureVisible(
        visibleContext,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.18,
      );
      return;
    }

    if (!_messagesScrollController.hasClients) {
      return;
    }

    final messageIndex = _latestRemoteMessages.indexWhere(
      (message) => message.id == pinned.messageId,
    );
    if (messageIndex == -1) {
      return;
    }

    final targetMessage = _latestRemoteMessages[messageIndex];
    final estimatedTextHeight =
        ((targetMessage.text.trim().length / 34).ceil().clamp(1, 7) * 18)
            .toDouble();
    final estimatedAttachmentsHeight =
        targetMessage.attachments.isEmpty ? 0.0 : 160.0;
    final estimatedOffset =
        messageIndex * 112.0 + estimatedTextHeight + estimatedAttachmentsHeight;
    final clampedOffset = estimatedOffset.clamp(
      0.0,
      _messagesScrollController.position.maxScrollExtent,
    );
    await _messagesScrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) {
      return;
    }
    _highlightPinnedMessage(pinned.messageId);
    final resolvedContext =
        _remoteMessageKeys[pinned.messageId]?.currentContext;
    if (resolvedContext != null && resolvedContext.mounted) {
      await Scrollable.ensureVisible(
        resolvedContext,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: 0.18,
      );
    }
  }

  void _handleSearchChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _openSearch() {
    setState(() {
      _isSearchMode = true;
    });
  }

  void _closeSearch() {
    _searchController.clear();
    setState(() {
      _isSearchMode = false;
    });
  }

  bool _messageMatchesSearch(String text) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    return text.toLowerCase().contains(query);
  }

  int _searchMatchCount(
    List<ChatMessage> remoteMessages,
    List<_OutgoingMessage> optimisticMessages,
  ) {
    if (_searchController.text.trim().isEmpty) {
      return 0;
    }
    return remoteMessages
            .where((message) => _messageMatchesSearch(message.text))
            .length +
        optimisticMessages
            .where((message) => _messageMatchesSearch(message.text))
            .length;
  }

  void _handleMessagesScroll() {
    if (!_messagesScrollController.hasClients) {
      return;
    }
    final shouldShow = _messagesScrollController.offset > 120;
    if (shouldShow != _showJumpToLatestButton && mounted) {
      setState(() {
        _showJumpToLatestButton = shouldShow;
      });
    }
  }

  Future<void> _jumpToLatestMessages() async {
    if (!_messagesScrollController.hasClients) {
      return;
    }
    await _messagesScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _showJumpToLatestButton = false;
      _unreadAnchorMessageId = null;
    });
  }

  void _updateUnreadAnchor(List<ChatMessage> remoteMessages) {
    final unreadIncoming = remoteMessages
        .where(
          (message) =>
              message.senderId != _currentUserId && message.isRead == false,
        )
        .toList();
    if (unreadIncoming.isNotEmpty) {
      _unreadAnchorMessageId = unreadIncoming.last.id;
    }
  }

  void _scheduleUnreadJumpIfNeeded() {
    if (_didInitialUnreadJump || _unreadAnchorMessageId == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      final context = _unreadDividerKey.currentContext;
      if (context == null) {
        return;
      }
      _didInitialUnreadJump = true;
      await Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.12,
      );
    });
  }

  Future<void> _sendOptimisticMessage(_OutgoingMessage message) async {
    try {
      final chatId = _chatId;
      if (chatId == null || chatId.isEmpty) {
        throw StateError('Чат недоступен');
      }
      await _chatService.sendMessageToChat(
        chatId: chatId,
        text: message.text,
        attachments: message.attachments,
        forwardedAttachments: message.forwardedAttachments,
        replyTo: message.replyTo,
        clientMessageId: message.localId,
        expiresInSeconds: _autoDeleteSettings.option.ttl?.inSeconds,
        onProgress: (progress) {
          if (!mounted) {
            return;
          }
          setState(() {
            final currentIndex = _optimisticMessages.indexWhere(
              (item) => item.localId == message.localId,
            );
            if (currentIndex == -1) {
              return;
            }
            _optimisticMessages[currentIndex] =
                _optimisticMessages[currentIndex].copyWith(progress: progress);
          });
        },
      );
      if (!mounted) {
        return;
      }
      if (message.attachments.any(_isRecordedVoiceAttachment)) {
        _recordingController.completeSend();
      }
      setState(() {
        _replaceOptimisticMessage(
          message.localId,
          message.copyWith(status: _OutgoingMessageStatus.sent),
        );
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      final failureMessage = _messageActionErrorText(
        error,
        'Не удалось отправить сообщение.',
      );
      if (message.attachments.any(_isRecordedVoiceAttachment)) {
        _recordingController.markSendFailed(failureMessage);
      }
      setState(() {
        _replaceOptimisticMessage(
          message.localId,
          message.copyWith(
            status: _OutgoingMessageStatus.failed,
            errorText: failureMessage,
          ),
        );
        if (failureMessage.toLowerCase().contains('заблокирован') &&
            _isCurrentDirectChat) {
          _isDirectChatBlocked = true;
          _directChatBlockedLabel ??=
              _participantLabelForUserId(_currentDirectPeerUserId ?? '');
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failureMessage)),
      );
    }
  }

  void _replaceOptimisticMessage(String localId, _OutgoingMessage nextMessage) {
    final index = _optimisticMessages.indexWhere(
      (message) => message.localId == localId,
    );
    if (index == -1) {
      return;
    }
    _optimisticMessages[index] = nextMessage;
  }

  bool _matchesRemoteMessage(
    _OutgoingMessage localMessage,
    List<ChatMessage> remoteMessages,
  ) {
    return remoteMessages.any((message) {
      return message.clientMessageId != null &&
          message.clientMessageId == localMessage.localId;
    });
  }

  Future<void> _openChatInfo() async {
    final details = _chatDetails;
    final currentUserId = _currentUserId;
    if (details == null || currentUserId == null || currentUserId.isEmpty) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ChatInfoSheet(
        initialDetails: details,
        currentUserId: currentUserId,
        hasPinnedMessage: _pinnedMessage != null,
        initialNotificationLevel: _notificationSettings.level,
        initialAutoDeleteOption: _autoDeleteSettings.option,
        onRename: (title) async {
          final updatedDetails = await _chatService.renameGroupChat(
            chatId: details.chatId,
            title: title,
          );
          if (!mounted) {
            return updatedDetails;
          }
          setState(() {
            _chatDetails = updatedDetails;
            _resolvedTitle = updatedDetails.displayTitle;
          });
          return updatedDetails;
        },
        onAddParticipants: (participantIds) async {
          final updatedDetails = await _chatService.addGroupParticipants(
            chatId: details.chatId,
            participantIds: participantIds,
          );
          if (!mounted) {
            return updatedDetails;
          }
          setState(() {
            _chatDetails = updatedDetails;
          });
          return updatedDetails;
        },
        onRemoveParticipant: (participantId) async {
          final updatedDetails = await _chatService.removeGroupParticipant(
            chatId: details.chatId,
            participantId: participantId,
          );
          if (!mounted) {
            return updatedDetails;
          }
          setState(() {
            _chatDetails = updatedDetails;
          });
          return updatedDetails;
        },
        onOpenSearch: () {
          Navigator.of(context).pop();
          _openSearch();
        },
        onOpenPinnedMessage: _pinnedMessage == null
            ? null
            : () {
                Navigator.of(context).pop();
                unawaited(_focusPinnedMessage());
              },
        onOpenTree: details.treeId == null || details.treeId!.trim().isEmpty
            ? null
            : () {
                Navigator.of(context).pop();
                context.push('/tree/view/${details.treeId}');
              },
        onOpenRelatives:
            details.treeId == null || details.treeId!.trim().isEmpty
                ? null
                : () {
                    Navigator.of(context).pop();
                    context.go('/relatives');
                  },
        onOpenMedia: () {
          Navigator.of(context).pop();
          unawaited(_openChatMediaGallery());
        },
        onOpenFiles: () {
          Navigator.of(context).pop();
          unawaited(_openChatFilesGallery());
        },
        onNotificationLevelChanged: _updateNotificationLevel,
        onAutoDeleteChanged: _updateAutoDeleteOption,
      ),
    );
  }

  String? _typingSubtitle() {
    if (_typingUsers.isEmpty) {
      return null;
    }

    final typingUserIds = _typingUsers.keys.toList();
    if (!widget.isGroup && typingUserIds.isNotEmpty) {
      return 'печатает…';
    }
    if (typingUserIds.length == 1) {
      return '${_participantLabelForUserId(typingUserIds.first)} печатает…';
    }
    return 'Печатают: ${typingUserIds.length}';
  }

  String? _presenceSubtitle(ChatDetails? details) {
    final otherParticipantIds = _otherParticipantIds(details);
    if (otherParticipantIds.isEmpty) {
      return null;
    }

    final onlineCount = otherParticipantIds
        .where((participantId) => _onlineUserIds.contains(participantId))
        .length;
    if (onlineCount == 0) {
      return null;
    }

    if (!widget.isGroup) {
      return 'в сети';
    }
    return onlineCount == 1 ? '1 участник в сети' : '$onlineCount в сети';
  }

  List<String> _otherParticipantIds(ChatDetails? details) {
    final currentUserId = _currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      return const <String>[];
    }

    final participantIds = <String>{
      ...?details?.participantIds,
      ..._latestRemoteMessages.expand((message) => message.participants),
      if (widget.otherUserId != null && widget.otherUserId!.isNotEmpty)
        widget.otherUserId!,
    };

    participantIds.removeWhere(
      (participantId) =>
          participantId.trim().isEmpty || participantId == currentUserId,
    );
    return participantIds.toList();
  }

  String _participantLabelForUserId(String userId) {
    final details = _chatDetails;
    if (details != null) {
      for (final participant in details.participants) {
        if (participant.userId == userId &&
            participant.displayName.trim().isNotEmpty) {
          return participant.displayName;
        }
      }
    }

    for (final message in _latestRemoteMessages) {
      if (message.senderId == userId &&
          (message.senderName?.trim().isNotEmpty ?? false)) {
        return message.senderName!.trim();
      }
    }

    return 'Участник';
  }

  String _chatSubtitle() {
    final typingSubtitle = _typingSubtitle();
    if (typingSubtitle != null) {
      return typingSubtitle;
    }

    final details = _chatDetails;
    final presenceSubtitle = _presenceSubtitle(details);
    if (presenceSubtitle != null) {
      return presenceSubtitle;
    }
    if (details != null && details.isBranch) {
      final branchCount = details.branchRoots.length;
      final memberCount = details.memberCount;
      final branchLabel = branchCount == 1 ? '1 ветка' : '$branchCount ветки';
      final memberLabel =
          memberCount == 1 ? '1 участник' : '$memberCount участников';
      return '$branchLabel · $memberLabel';
    }
    if (details != null && details.isGroup) {
      final memberCount = details.memberCount;
      return memberCount == 1 ? '1 участник' : '$memberCount участников';
    }
    return widget.chatType == 'branch'
        ? 'Чат ветки'
        : (widget.isGroup ? 'Групповой чат' : 'Личные сообщения');
  }

  @override
  Widget build(BuildContext context) {
    final selectionCount = _selectedMessageCount;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(
            _isSelectionMode
                ? Icons.close
                : (_isSearchMode ? Icons.close : Icons.arrow_back),
          ),
          onPressed: _isSelectionMode
              ? _exitSelectionMode
              : (_isSearchMode ? _closeSearch : () => context.pop()),
        ),
        titleSpacing: 0,
        title: _isSelectionMode
            ? Text(
                'Выбрано: $selectionCount',
                style: const TextStyle(fontWeight: FontWeight.w600),
              )
            : _isSearchMode
                ? TextField(
                    controller: _searchController,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      hintText: 'Поиск по сообщениям',
                      border: InputBorder.none,
                    ),
                  )
                : Row(
                    children: [
                      GestureDetector(
                        onTap: !widget.isGroup &&
                                widget.relativeId != null &&
                                widget.relativeId!.isNotEmpty
                            ? () => context
                                .push('/relative/details/${widget.relativeId}')
                            : null,
                        child: CircleAvatar(
                          radius: 20,
                          backgroundImage: widget.photoUrl != null &&
                                  widget.photoUrl!.isNotEmpty
                              ? NetworkImage(widget.photoUrl!)
                              : null,
                          child: widget.photoUrl == null ||
                                  widget.photoUrl!.isEmpty
                              ? widget.isGroup
                                  ? const Icon(Icons.group_outlined)
                                  : Text(
                                      widget.title.isNotEmpty
                                          ? widget.title[0]
                                          : '?',
                                    )
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _resolvedTitle,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _chatSubtitle(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
        actions: _isSelectionMode
            ? [
                IconButton(
                  onPressed: _copySelectedMessages,
                  tooltip: 'Скопировать выбранное',
                  icon: const Icon(Icons.copy_all_rounded),
                ),
                IconButton(
                  onPressed: _forwardSelectedMessages,
                  tooltip: 'Переслать выбранное',
                  icon: const Icon(Icons.forward_rounded),
                ),
                IconButton(
                  onPressed: _deleteSelectedMessages,
                  tooltip: 'Удалить выбранное',
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ]
            : _isSearchMode
                ? null
                : [
                    if (_isCurrentDirectChat) ...[
                      IconButton(
                        onPressed: () => _startCall(CallMediaMode.audio),
                        tooltip: 'Аудиозвонок',
                        icon: const Icon(Icons.call_outlined),
                      ),
                      IconButton(
                        onPressed: () => _startCall(CallMediaMode.video),
                        tooltip: 'Видеозвонок',
                        icon: const Icon(Icons.videocam_outlined),
                      ),
                    ],
                    IconButton(
                      onPressed: _openSearch,
                      tooltip: 'Поиск по чату',
                      icon: const Icon(Icons.search),
                    ),
                    IconButton(
                      onPressed: _isLoadingChatDetails || _chatDetails == null
                          ? null
                          : _openChatInfo,
                      tooltip: 'О чате',
                      icon: const Icon(Icons.info_outline),
                    ),
                  ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _isWideLayout(context) ? 1100 : double.infinity,
          ),
          child: Column(
            children: [
              const OfflineIndicator(),
              if (_pinnedMessage != null) _buildPinnedMessageBanner(),
              Expanded(child: _buildMessagesBody()),
              if (_recordingController.state == ChatRecordingState.locked &&
                  !_isDirectChatBlocked)
                _buildRecordingArea()
              else
                _buildMessageInputArea(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingArea() {
    final theme = Theme.of(context);
    final isFriendsTree =
        context.read<TreeProvider>().selectedTreeKind == TreeKind.friends;
    final minutes =
        (_recordingController.durationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds =
        (_recordingController.durationSeconds % 60).toString().padLeft(2, '0');

    return Padding(
      padding: EdgeInsets.fromLTRB(
        8,
        4,
        8,
        MediaQuery.of(context).padding.bottom + 8,
      ),
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        borderRadius: BorderRadius.circular(28),
        child: Row(
          children: [
            const Icon(Icons.mic, color: Colors.red),
            const SizedBox(width: 12),
            Text(
              '$minutes:$seconds',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.red,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isFriendsTree
                    ? 'Запись для круга зафиксирована'
                    : 'Запись аудио',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            IconButton(
              onPressed: _cancelRecording,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Отмена',
            ),
            IconButton(
              onPressed: _stopAndSendRecording,
              icon: Icon(
                Icons.stop_rounded,
                color: theme.colorScheme.primary,
              ),
              tooltip: 'Остановить и прослушать',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceAttachmentPreview(XFile voiceFile) {
    final theme = Theme.of(context);
    final hasRecordedPreview = _isRecordedVoiceAttachment(voiceFile);
    final durationLabel = hasRecordedPreview
        ? _formatDurationLabel(_recordingController.previewDurationSeconds)
        : 'Аудио';
    final recordingState = _recordingController.state;
    final helperText = recordingState == ChatRecordingState.sending
        ? 'Отправляем голосовое...'
        : recordingState == ChatRecordingState.failed
            ? (_recordingController.errorText ??
                'Не удалось отправить голосовое. Можно попробовать снова.')
            : 'Можно перезаписать или отправить.';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Проверьте голосовое',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  durationLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _VoicePlayerWidget(path: voiceFile.path, isMe: true),
          const SizedBox(height: 4),
          Text(
            helperText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: recordingState == ChatRecordingState.failed
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              children: [
                if (hasRecordedPreview) ...[
                  TextButton.icon(
                    onPressed: recordingState == ChatRecordingState.sending
                        ? null
                        : _rerecordVoiceAttachment,
                    icon: const Icon(Icons.mic_none_rounded),
                    label: const Text('Перезаписать'),
                  ),
                  TextButton.icon(
                    onPressed: recordingState == ChatRecordingState.sending
                        ? null
                        : _discardPendingVoiceAttachment,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Удалить запись'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDurationLabel(int durationSeconds) {
    final minutes = (durationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (durationSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildMessagesBody() {
    if (_isBootstrapping) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_bootstrapError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: GlassPanel(
              borderRadius: BorderRadius.circular(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.chat_bubble_outline, size: 40),
                  const SizedBox(height: 12),
                  Text(
                    _bootstrapError!,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _bootstrapChat,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final chatId = _chatId;
    if (chatId == null || chatId.isEmpty) {
      return Center(
        child: GlassPanel(
          borderRadius: BorderRadius.circular(28),
          child: const Text('Чат недоступен.'),
        ),
      );
    }

    final timelineController = _timelineController;
    if (timelineController == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return StreamBuilder<List<ChatMessage>>(
      stream: timelineController.stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: GlassPanel(
                  borderRadius: BorderRadius.circular(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 40),
                      const SizedBox(height: 12),
                      const Text(
                        'Не удалось загрузить сообщения.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () {
                          unawaited(timelineController.refresh());
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Обновить'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        final remoteMessages = snapshot.data ?? const <ChatMessage>[];
        _latestRemoteMessages = remoteMessages;
        _schedulePinnedSync(remoteMessages);
        final optimisticMessages = _optimisticMessages
            .where((message) => !_matchesRemoteMessage(message, remoteMessages))
            .toList();
        final hasActiveSearch = _searchController.text.trim().isNotEmpty;
        final filteredRemoteMessages = hasActiveSearch
            ? remoteMessages
                .where((message) => _messageMatchesSearch(message.text))
                .toList()
            : remoteMessages;
        final filteredOptimisticMessages = hasActiveSearch
            ? optimisticMessages
                .where((message) => _messageMatchesSearch(message.text))
                .toList()
            : optimisticMessages;
        final hasUnreadIncoming = !hasActiveSearch &&
            remoteMessages.any(
              (message) =>
                  message.senderId != _currentUserId && message.isRead == false,
            );
        if (!hasActiveSearch) {
          _updateUnreadAnchor(remoteMessages);
        }
        if (hasUnreadIncoming) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _markChatAsRead();
          });
        }

        if (filteredRemoteMessages.isEmpty &&
            filteredOptimisticMessages.isEmpty) {
          if (hasActiveSearch) {
            return Center(
              child: GlassPanel(
                borderRadius: BorderRadius.circular(24),
                child: Text(
                  'Ничего не найдено по запросу "${_searchController.text.trim()}"',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final isFriendsTree =
              context.read<TreeProvider>().selectedTreeKind == TreeKind.friends;
          return Center(
            child: GlassPanel(
              borderRadius: BorderRadius.circular(24),
              child: Text(
                isFriendsTree
                    ? 'Пока пусто. Начните разговор.'
                    : 'Пока пусто. Начните диалог.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (!hasActiveSearch) {
          _scheduleUnreadJumpIfNeeded();
        }
        String? latestOutgoingMessageId;
        if (!widget.isGroup) {
          for (final message in remoteMessages) {
            if (message.senderId == _currentUserId) {
              latestOutgoingMessageId = message.id;
              break;
            }
          }
        }
        final unreadAnchorMessageId = _unreadAnchorMessageId;
        final hasUnreadDivider = !hasActiveSearch &&
            unreadAnchorMessageId != null &&
            remoteMessages
                .any((message) => message.id == unreadAnchorMessageId);
        final searchMatchCount = _searchMatchCount(
          filteredRemoteMessages,
          filteredOptimisticMessages,
        );

        return Stack(
          children: [
            ListView.builder(
              controller: _messagesScrollController,
              reverse: true,
              padding: EdgeInsets.fromLTRB(
                0,
                hasActiveSearch ? 52 : 8,
                0,
                8,
              ),
              itemCount: filteredRemoteMessages.length +
                  filteredOptimisticMessages.length +
                  (hasUnreadDivider ? 1 : 0),
              itemBuilder: (context, index) {
                if (index < filteredOptimisticMessages.length) {
                  final localMessage = filteredOptimisticMessages[index];
                  return _buildOptimisticBubble(localMessage);
                }

                final remoteIndex = index - filteredOptimisticMessages.length;
                if (hasUnreadDivider && remoteIndex >= 0) {
                  var remoteCursor = 0;
                  for (final message in filteredRemoteMessages) {
                    if (message.id == unreadAnchorMessageId) {
                      if (remoteCursor == remoteIndex) {
                        return _buildUnreadDivider();
                      }
                      remoteCursor++;
                    }

                    if (remoteCursor == remoteIndex) {
                      final isMe = message.senderId == _currentUserId;
                      return _buildRemoteBubble(
                        message,
                        isMe,
                        footerLabel: _messageFooterLabel(
                          message,
                          isMe: isMe,
                          isLatestOwnDirectMessage:
                              message.id == latestOutgoingMessageId,
                        ),
                      );
                    }
                    remoteCursor++;
                  }
                }

                final remoteMessage = filteredRemoteMessages[
                    remoteIndex - (hasUnreadDivider ? 1 : 0)];
                final isMe = remoteMessage.senderId == _currentUserId;
                return _buildRemoteBubble(
                  remoteMessage,
                  isMe,
                  footerLabel: _messageFooterLabel(
                    remoteMessage,
                    isMe: isMe,
                    isLatestOwnDirectMessage:
                        remoteMessage.id == latestOutgoingMessageId,
                  ),
                );
              },
            ),
            if (hasActiveSearch)
              Positioned(
                left: 12,
                right: 12,
                top: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      searchMatchCount == 1
                          ? 'Найдено 1 сообщение'
                          : 'Найдено $searchMatchCount сообщений',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ),
              ),
            if (_showJumpToLatestButton)
              Positioned(
                right: 16,
                bottom: 18,
                child: FloatingActionButton.small(
                  heroTag: 'jump-to-latest',
                  onPressed: _jumpToLatestMessages,
                  tooltip: 'К последним сообщениям',
                  child: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildPinnedMessageBanner() {
    final pinned = _pinnedMessage!;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: InkWell(
        onTap: _focusPinnedMessage,
        borderRadius: BorderRadius.circular(24),
        child: GlassPanel(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          borderRadius: BorderRadius.circular(24),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.push_pin_outlined, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Закрепленное сообщение',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      pinned.senderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _pinnedPreviewLabel(pinned),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => unawaited(_clearPinnedMessage()),
                tooltip: 'Открепить',
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUnreadDivider() {
    final theme = Theme.of(context);
    return Padding(
      key: _unreadDividerKey,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: theme.colorScheme.primary.withValues(alpha: 0.35),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Непрочитанные',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: theme.colorScheme.primary.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInputArea() {
    if (_isDirectChatBlocked) {
      return _buildBlockedComposerNotice();
    }

    final recordingState = _recordingController.state;
    final isLockedRecording = recordingState == ChatRecordingState.locked;
    final canSend = _messageController.text.trim().isNotEmpty ||
        _selectedAttachments.isNotEmpty ||
        _selectedForward != null ||
        _selectedForwardBatch != null ||
        _selectedEdit != null;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        8,
        4,
        8,
        MediaQuery.of(context).padding.bottom + 8,
      ),
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        borderRadius: BorderRadius.circular(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (recordingState == ChatRecordingState.denied ||
                recordingState == ChatRecordingState.failed ||
                recordingState == ChatRecordingState.recording)
              _buildRecordingNotice(
                Theme.of(context),
                recordingState: recordingState,
              ),
            if (recordingState == ChatRecordingState.denied ||
                recordingState == ChatRecordingState.failed ||
                recordingState == ChatRecordingState.recording)
              const SizedBox(height: 8),
            if (_selectedEdit != null)
              _buildEditComposerBar(Theme.of(context), _selectedEdit!),
            if (_selectedEdit != null) const SizedBox(height: 8),
            if (_selectedReply != null)
              _buildReplyComposerBar(Theme.of(context), _selectedReply!),
            if (_selectedReply != null) const SizedBox(height: 8),
            if (_selectedForward != null)
              _buildForwardComposerBar(Theme.of(context), _selectedForward!),
            if (_selectedForward != null) const SizedBox(height: 8),
            if (_selectedForwardBatch != null)
              _buildForwardBatchComposerBar(
                Theme.of(context),
                _selectedForwardBatch!,
              ),
            if (_selectedForwardBatch != null) const SizedBox(height: 8),
            if (_autoDeleteSettings.option != ChatAutoDeleteOption.off)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    avatar: const Icon(Icons.timer_outlined, size: 18),
                    label: Text(
                      'Автоудаление: ${_autoDeleteSettings.option.label}',
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            if (_selectedAttachments.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withValues(alpha: 0.65),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(
                          _attachmentPanelIcon(_selectedAttachments),
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _attachmentPanelTitle(_selectedAttachments),
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            if (_selectedAttachments.any(
                              _isRecordedVoiceAttachment,
                            )) {
                              _recordingController.discardPreview();
                            }
                            setState(() {
                              _selectedAttachments.clear();
                            });
                          },
                          child: const Text('Очистить'),
                        ),
                      ],
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _attachmentSummaryLabel(_selectedAttachments),
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _attachmentKindsLabel(_selectedAttachments),
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _attachmentHintLabel(_selectedAttachments),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (_selectedAttachments.length == 1 &&
                        _attachmentKindFromXFile(_selectedAttachments.first) ==
                            _ChatAttachmentKind.audio)
                      _buildVoiceAttachmentPreview(
                        _selectedAttachments.first,
                      ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 74,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _selectedAttachments.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final attachment = _selectedAttachments[index];
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: SizedBox(
                                  width: 74,
                                  height: 74,
                                  child: _LocalMediaTile(file: attachment),
                                ),
                              ),
                              Positioned(
                                top: -6,
                                right: -6,
                                child: IconButton.filledTonal(
                                  onPressed: () {
                                    final attachmentToRemove =
                                        _selectedAttachments[index];
                                    if (_isRecordedVoiceAttachment(
                                      attachmentToRemove,
                                    )) {
                                      _recordingController.discardPreview();
                                    }
                                    setState(() {
                                      _selectedAttachments.removeAt(index);
                                    });
                                  },
                                  icon: const Icon(Icons.close, size: 16),
                                  visualDensity: VisualDensity.compact,
                                  style: IconButton.styleFrom(
                                    minimumSize: const Size(28, 28),
                                    padding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            if (_selectedAttachments.isNotEmpty) const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton.filledTonal(
                  onPressed: _selectedAttachments.length >= _maxAttachments
                      ? null
                      : _openAttachmentPicker,
                  tooltip: 'Добавить вложение',
                  icon: const Icon(Icons.attach_file_rounded),
                ),
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerLowest
                          .withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _messageController,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration.collapsed(
                        hintText: 'Сообщение...',
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      keyboardType: TextInputType.multiline,
                      minLines: 1,
                      maxLines: 5,
                    ),
                  ),
                ),
                _buildPrimaryComposerAction(
                  canSend: canSend,
                  isLockedRecording: isLockedRecording,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingNotice(
    ThemeData theme, {
    required ChatRecordingState recordingState,
  }) {
    final minutes =
        (_recordingController.durationSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds =
        (_recordingController.durationSeconds % 60).toString().padLeft(2, '0');

    late final IconData icon;
    late final String title;
    late final String subtitle;
    late final Color foregroundColor;
    late final Color backgroundColor;

    switch (recordingState) {
      case ChatRecordingState.recording:
        icon = Icons.mic_rounded;
        title = '$minutes:$seconds';
        subtitle =
            'Проведите вверх, чтобы зафиксировать. Влево, чтобы отменить.';
        foregroundColor = Colors.red;
        backgroundColor = Colors.red.withValues(alpha: 0.08);
        break;
      case ChatRecordingState.failed:
        icon = Icons.error_outline;
        title = 'Голосовое не отправлено';
        subtitle = _recordingController.errorText ??
            'Проверьте сеть и попробуйте отправить снова.';
        foregroundColor = theme.colorScheme.error;
        backgroundColor =
            theme.colorScheme.errorContainer.withValues(alpha: 0.52);
        break;
      case ChatRecordingState.denied:
        icon = Icons.mic_off_outlined;
        title = 'Микрофон недоступен';
        subtitle =
            'Разрешите доступ к микрофону в настройках браузера или устройства.';
        foregroundColor = theme.colorScheme.error;
        backgroundColor =
            theme.colorScheme.errorContainer.withValues(alpha: 0.52);
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: foregroundColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: foregroundColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (recordingState == ChatRecordingState.denied)
            TextButton(
              onPressed: () {
                unawaited(openAppSettings());
              },
              child: const Text('Настройки'),
            ),
        ],
      ),
    );
  }

  Widget _buildPrimaryComposerAction({
    required bool canSend,
    required bool isLockedRecording,
  }) {
    if (canSend) {
      return IconButton.filled(
        onPressed:
            _selectedEdit != null ? _saveEditedMessage : _sendCurrentMessage,
        tooltip: _selectedEdit != null ? 'Сохранить изменения' : 'Отправить',
        icon: Icon(_selectedEdit != null ? Icons.check : Icons.send),
      );
    }

    final recordingState = _recordingController.state;
    if (isLockedRecording) {
      return IconButton.filled(
        onPressed: _stopAndSendRecording,
        tooltip: 'Остановить и прослушать',
        icon: const Icon(Icons.stop_rounded),
      );
    }

    return GestureDetector(
      onLongPressStart: _handleRecordingLongPressStart,
      onLongPressMoveUpdate: _handleRecordingLongPressMoveUpdate,
      onLongPressEnd: _handleRecordingLongPressEnd,
      child: IconButton.filled(
        onPressed: recordingState == ChatRecordingState.recording
            ? null
            : () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Зажмите кнопку, чтобы записать голосовое.',
                    ),
                  ),
                );
              },
        tooltip: 'Зажмите для голосового сообщения',
        icon: Icon(
          recordingState == ChatRecordingState.recording
              ? Icons.lock_open_rounded
              : Icons.mic_none_rounded,
        ),
      ),
    );
  }

  String? _messageFooterLabel(
    ChatMessage message, {
    required bool isMe,
    required bool isLatestOwnDirectMessage,
  }) {
    final segments = <String>[];
    final expiresLabel = _expiresLabel(message.expiresAt);
    if (expiresLabel != null) {
      segments.add('Автоудаление: $expiresLabel');
    }
    if (isMe && !widget.isGroup && isLatestOwnDirectMessage) {
      segments.add(message.isRead ? 'Просмотрено' : 'Доставлено');
    }
    if (segments.isEmpty) {
      return null;
    }
    return segments.join(' · ');
  }

  String? _expiresLabel(DateTime? expiresAt) {
    if (expiresAt == null) {
      return null;
    }

    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.inSeconds <= 0) {
      return 'скоро';
    }
    if (remaining.inHours < 1) {
      final minutes = remaining.inMinutes.clamp(1, 59);
      return '$minutes мин';
    }
    if (remaining.inDays < 1) {
      final hours = remaining.inHours.clamp(1, 23);
      return '$hours ч';
    }
    final days = remaining.inDays.clamp(1, 999);
    return '$days д';
  }

  Widget _buildRemoteBubble(
    ChatMessage message,
    bool isMe, {
    String? footerLabel,
  }) {
    final messageKey = _remoteMessageKeys.putIfAbsent(
      message.id,
      () => GlobalKey(),
    );
    return GestureDetector(
      key: messageKey,
      onTap: _isSelectionMode
          ? () => _toggleRemoteMessageSelection(message)
          : null,
      onLongPressStart: (details) {
        if (_isSelectionMode) {
          _toggleRemoteMessageSelection(message);
          return;
        }
        _openRemoteMessageActions(
          message,
          anchorPosition: details.globalPosition,
        );
      },
      onSecondaryTapDown: (details) {
        if (_isSelectionMode) {
          _toggleRemoteMessageSelection(message);
          return;
        }
        _openRemoteMessageActions(
          message,
          anchorPosition: details.globalPosition,
        );
      },
      child: _ChatBubble(
        isMe: isMe,
        senderLabel: widget.isGroup && !isMe
            ? _groupSenderLabel(message.senderName, message.senderId)
            : null,
        text: message.text,
        highlightQuery: _searchController.text.trim(),
        timeLabel: DateFormat.Hm('ru').format(message.timestamp),
        isRead: message.isRead,
        remoteAttachments: message.attachments,
        replyTo: message.replyTo,
        isPinned: _pinnedMessage?.messageId == message.id,
        isHighlighted: _highlightedPinnedMessageId == message.id,
        footerLabel: footerLabel,
        reactionGroups: _reactionGroupsForMessage(message.id),
        onReactionTap: (emoji) => _toggleReactionForMessage(message, emoji),
        showSelectionMarker: _isSelectionMode,
        isSelected: _selectedRemoteMessageIds.contains(message.id),
        onOpenRemoteAttachment: (attachments, attachment) =>
            _openRemoteAttachmentPreview(message, attachments, attachment),
      ),
    );
  }

  Widget _buildOptimisticBubble(_OutgoingMessage message) {
    final timeLabel = DateFormat.Hm('ru').format(message.timestamp);
    final theme = Theme.of(context);
    final statusMeta = _statusMetaForOutgoingMessage(theme, message);
    final progressValue = message.progress?.value;
    final showProgressBar = message.status == _OutgoingMessageStatus.pending &&
        message.attachments.isNotEmpty;
    final bubbleKey = ValueKey<String>('outgoing-bubble-${message.localId}');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            GestureDetector(
              key: bubbleKey,
              onTap: _isSelectionMode
                  ? () => _toggleOutgoingMessageSelection(message)
                  : null,
              onLongPressStart: (details) {
                if (_isSelectionMode) {
                  _toggleOutgoingMessageSelection(message);
                  return;
                }
                _openOutgoingMessageActions(
                  message,
                  anchorPosition: details.globalPosition,
                );
              },
              onSecondaryTapDown: (details) {
                if (_isSelectionMode) {
                  _toggleOutgoingMessageSelection(message);
                  return;
                }
                _openOutgoingMessageActions(
                  message,
                  anchorPosition: details.globalPosition,
                );
              },
              child: _ChatBubble(
                isMe: true,
                text: message.text,
                highlightQuery: _searchController.text.trim(),
                timeLabel: timeLabel,
                isRead: false,
                remoteAttachments: message.forwardedAttachments,
                localAttachments: message.attachments,
                replyTo: message.replyTo,
                isPinned: false,
                isHighlighted: false,
                reactionGroups: const <_ReactionGroup>[],
                showSelectionMarker: _isSelectionMode,
                isSelected:
                    _selectedOutgoingMessageIds.contains(message.localId),
                onOpenLocalAttachment: (files, file) =>
                    _openLocalAttachmentPreview(files, file),
                footerLabel:
                    _autoDeleteSettings.option == ChatAutoDeleteOption.off
                        ? null
                        : 'Автоудаление: ${_autoDeleteSettings.option.label}',
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  statusMeta.icon,
                  size: 14,
                  color: statusMeta.color,
                ),
                const SizedBox(width: 4),
                Text(
                  statusMeta.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: statusMeta.color,
                    fontWeight: message.status == _OutgoingMessageStatus.failed
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
                if (message.status == _OutgoingMessageStatus.failed) ...[
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: () => _sendOptimisticMessage(
                      message.copyWith(
                        status: _OutgoingMessageStatus.pending,
                        errorText: null,
                      ),
                    ),
                    child: const Text('Повторить'),
                  ),
                ],
              ],
            ),
            if (showProgressBar) ...[
              const SizedBox(height: 4),
              SizedBox(
                width: 140,
                child: LinearProgressIndicator(value: progressValue),
              ),
            ],
          ],
        ),
      ),
    );
  }

  _OutgoingStatusMeta _statusMetaForOutgoingMessage(
    ThemeData theme,
    _OutgoingMessage message,
  ) {
    if (message.status == _OutgoingMessageStatus.failed) {
      return _OutgoingStatusMeta(
        label: message.errorText ?? 'Ошибка отправки',
        icon: Icons.error_outline,
        color: theme.colorScheme.error,
      );
    }
    if (message.status == _OutgoingMessageStatus.sent) {
      return _OutgoingStatusMeta(
        label: 'Отправлено',
        icon: Icons.done_all,
        color: theme.colorScheme.primary,
      );
    }

    switch (message.progress?.stage) {
      case ChatSendProgressStage.preparing:
        return _OutgoingStatusMeta(
          label: 'Подготовка вложений...',
          icon: Icons.inventory_2_outlined,
          color: theme.colorScheme.onSurfaceVariant,
        );
      case ChatSendProgressStage.uploading:
        final total = message.progress?.total ?? 0;
        final completed = message.progress?.completed ?? 0;
        if (total > 1) {
          return _OutgoingStatusMeta(
            label: 'Загрузка вложений $completed/$total',
            icon: Icons.cloud_upload_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          );
        }
        return _OutgoingStatusMeta(
          label: 'Загрузка вложения...',
          icon: Icons.cloud_upload_outlined,
          color: theme.colorScheme.onSurfaceVariant,
        );
      case ChatSendProgressStage.sending:
      case null:
        return _OutgoingStatusMeta(
          label: 'Отправляется...',
          icon: Icons.schedule_send_outlined,
          color: theme.colorScheme.onSurfaceVariant,
        );
    }
  }

  String _attachmentSummaryLabel(List<XFile> files) {
    final count = files.length;
    final noun = count == 1
        ? 'вложение'
        : (count >= 2 && count <= 4 ? 'вложения' : 'вложений');
    return '$count $noun';
  }

  String _attachmentKindsLabel(List<XFile> files) {
    if (files.length == 1 && _isVideoNoteFile(files.first)) {
      return '1 кружок';
    }
    final counts = <_ChatAttachmentKind, int>{};
    for (final file in files) {
      final kind = _attachmentKindFromXFile(file);
      counts.update(kind, (value) => value + 1, ifAbsent: () => 1);
    }

    final segments = <String>[];
    void addSegment(_ChatAttachmentKind kind, String singular, String plural) {
      final count = counts[kind];
      if (count == null || count == 0) {
        return;
      }
      segments.add('$count ${count == 1 ? singular : plural}');
    }

    addSegment(_ChatAttachmentKind.image, 'фото', 'фото');
    addSegment(_ChatAttachmentKind.video, 'видео', 'видео');
    addSegment(_ChatAttachmentKind.audio, 'голосовое', 'голосовых');
    addSegment(_ChatAttachmentKind.other, 'файл', 'файла');
    return segments.join(' · ');
  }

  String _attachmentHintLabel(List<XFile> files) {
    if (files.length == 1 && _isVideoNoteFile(files.first)) {
      return 'Кружок уйдет отдельным сообщением и откроется как круглое видео.';
    }
    final kinds = files.map(_attachmentKindFromXFile).toSet();
    if (kinds.length > 1) {
      return 'Пакет уйдет одним сообщением. Проверьте подпись и состав перед отправкой.';
    }

    switch (kinds.first) {
      case _ChatAttachmentKind.image:
        return 'Фото будут ужаты перед отправкой, чтобы чат открывался быстрее.';
      case _ChatAttachmentKind.video:
        return 'Видео отправится как вложение. Можно добавить подпись к отправке.';
      case _ChatAttachmentKind.audio:
        return 'Голосовое отправится отдельным сообщением в текущий чат.';
      case _ChatAttachmentKind.other:
        return 'Файлы отправятся как документы без дополнительной обработки.';
    }
  }

  IconData _attachmentPanelIcon(List<XFile> files) {
    if (files.length == 1 && _isVideoNoteFile(files.first)) {
      return Icons.radio_button_checked_rounded;
    }
    final kinds = files.map(_attachmentKindFromXFile).toSet();
    if (kinds.length > 1) {
      return Icons.collections_outlined;
    }

    switch (kinds.first) {
      case _ChatAttachmentKind.image:
        return Icons.photo_library_outlined;
      case _ChatAttachmentKind.video:
        return Icons.videocam_outlined;
      case _ChatAttachmentKind.audio:
        return Icons.mic_none_outlined;
      case _ChatAttachmentKind.other:
        return Icons.insert_drive_file_outlined;
    }
  }

  String _attachmentPanelTitle(List<XFile> files) {
    if (files.length == 1 && _isVideoNoteFile(files.first)) {
      return 'Кружок перед отправкой';
    }
    final kinds = files.map(_attachmentKindFromXFile).toSet();
    if (kinds.length > 1) {
      return 'Пакет перед отправкой';
    }

    switch (kinds.first) {
      case _ChatAttachmentKind.image:
        return 'Фото перед отправкой';
      case _ChatAttachmentKind.video:
        return 'Видео перед отправкой';
      case _ChatAttachmentKind.audio:
        return 'Голосовое перед отправкой';
      case _ChatAttachmentKind.other:
        return 'Файлы перед отправкой';
    }
  }

  String? _groupSenderLabel(String? senderName, String senderId) {
    final normalizedName = senderName?.trim();
    if (normalizedName != null && normalizedName.isNotEmpty) {
      return normalizedName;
    }
    if (senderId == _currentUserId) {
      return 'Вы';
    }
    return 'Участник';
  }

  bool _isWideLayout(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1180;

  Future<void> _copyMessageText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: trimmed));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Текст сообщения скопирован')),
    );
  }

  bool get _isCurrentDirectChat =>
      _chatDetails?.isDirect ?? widget.chatType == 'direct';

  String? get _currentDirectPeerUserId {
    if (!_isCurrentDirectChat) {
      return null;
    }
    final participantIds = _otherParticipantIds(_chatDetails);
    if (participantIds.isEmpty) {
      final otherUserId = widget.otherUserId?.trim();
      return otherUserId == null || otherUserId.isEmpty ? null : otherUserId;
    }
    return participantIds.first;
  }

  String _messageActionErrorText(Object error, String fallback) {
    if (error is CustomApiException && error.message.trim().isNotEmpty) {
      return error.message.trim();
    }
    if (error is UnsupportedError && error.message?.trim().isNotEmpty == true) {
      return error.message!.trim();
    }
    return fallback;
  }

  Future<_SafetyActionDraft?> _pickSafetyActionDraft({
    required String title,
    required String subtitle,
    required List<_SafetyReasonChoice> choices,
  }) {
    return showModalBottomSheet<_SafetyActionDraft>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final detailsController = TextEditingController();
        _SafetyReasonChoice? selectedChoice = choices.first;

        return StatefulBuilder(
          builder: (context, setModalState) => SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 8,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: choices
                        .map(
                          (choice) => ChoiceChip(
                            label: Text(choice.label),
                            selected: selectedChoice == choice,
                            onSelected: (_) {
                              setModalState(() {
                                selectedChoice = choice;
                              });
                            },
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: detailsController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Комментарий для модерации',
                      hintText:
                          'Необязательно, но помогает быстрее разобраться',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Отмена'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: selectedChoice == null
                            ? null
                            : () => Navigator.of(context).pop(
                                  _SafetyActionDraft(
                                    reason: selectedChoice!.reason,
                                    details: detailsController.text.trim(),
                                  ),
                                ),
                        child: const Text('Продолжить'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _reportRemoteMessage(ChatMessage message) async {
    final safetyService = _safetyService;
    if (safetyService == null) {
      return;
    }

    final senderLabel = _participantLabelForUserId(message.senderId);
    final draft = await _pickSafetyActionDraft(
      title: 'Пожаловаться на сообщение',
      subtitle:
          'Жалоба уйдёт в модерацию. Мы передадим текст сообщения, автора и контекст чата.',
      choices: const <_SafetyReasonChoice>[
        _SafetyReasonChoice(reason: 'spam', label: 'Спам'),
        _SafetyReasonChoice(reason: 'abuse', label: 'Оскорбление'),
        _SafetyReasonChoice(reason: 'adult', label: 'Нежелательный контент'),
        _SafetyReasonChoice(reason: 'fraud', label: 'Мошенничество'),
        _SafetyReasonChoice(reason: 'other', label: 'Другое'),
      ],
    );
    if (draft == null) {
      return;
    }

    try {
      await safetyService.reportTarget(
        targetType: 'message',
        targetId: message.id,
        reason: draft.reason,
        details: draft.details.isEmpty ? null : draft.details,
        metadata: <String, dynamic>{
          'chatId': message.chatId,
          'senderId': message.senderId,
          'senderName': senderLabel,
          'messagePreview': message.text.trim(),
        },
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Жалоба на сообщение $senderLabel отправлена.'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _messageActionErrorText(error, 'Не удалось отправить жалобу.'),
          ),
        ),
      );
    }
  }

  Future<void> _blockUserFromMessage(ChatMessage message) async {
    final safetyService = _safetyService;
    final currentUserId = _currentUserId;
    if (safetyService == null ||
        currentUserId == null ||
        currentUserId.isEmpty ||
        message.senderId.trim().isEmpty ||
        message.senderId == currentUserId) {
      return;
    }

    final senderLabel = _participantLabelForUserId(message.senderId);
    final draft = await _pickSafetyActionDraft(
      title: 'Заблокировать пользователя',
      subtitle:
          'После блокировки личный чат станет только для чтения. Управлять списком блокировок можно в настройках.',
      choices: const <_SafetyReasonChoice>[
        _SafetyReasonChoice(reason: 'harassment', label: 'Навязчивость'),
        _SafetyReasonChoice(reason: 'spam', label: 'Спам'),
        _SafetyReasonChoice(reason: 'privacy', label: 'Нарушение границ'),
        _SafetyReasonChoice(reason: 'other', label: 'Другое'),
      ],
    );
    if (draft == null) {
      return;
    }

    try {
      await safetyService.blockUser(
        userId: message.senderId,
        reason: draft.reason,
        metadata: <String, dynamic>{
          'chatId': message.chatId,
          'source': 'chat_message',
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedAttachments.clear();
        _selectedEdit = null;
        _selectedReply = null;
        _selectedForward = null;
        _selectedForwardBatch = null;
        _isDirectChatBlocked = _isCurrentDirectChat;
        _directChatBlockedLabel = senderLabel;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$senderLabel заблокирован. Отправка в этом личном чате отключена.',
          ),
          action: SnackBarAction(
            label: 'Блокировки',
            onPressed: () => context.push('/profile/blocks'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _messageActionErrorText(
                error, 'Не удалось заблокировать пользователя.'),
          ),
        ),
      );
    }
  }

  Widget _buildBlockedComposerNotice() {
    final theme = Theme.of(context);
    final label = _directChatBlockedLabel?.trim();
    final title = label != null && label.isNotEmpty
        ? '$label в списке блокировок'
        : 'Собеседник в списке блокировок';

    return Padding(
      padding: EdgeInsets.fromLTRB(
        8,
        4,
        8,
        MediaQuery.of(context).padding.bottom + 8,
      ),
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        borderRadius: BorderRadius.circular(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.block_rounded,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Новые сообщения и медиа сейчас недоступны.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => context.push('/profile/blocks'),
                  icon: const Icon(Icons.shield_outlined),
                  label: const Text('Список блокировок'),
                ),
                TextButton.icon(
                  onPressed: () => context.push('/support'),
                  icon: const Icon(Icons.support_agent_outlined),
                  label: const Text('Поддержка'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRemoteMessageActions(
    ChatMessage message, {
    Offset? anchorPosition,
  }) async {
    final canCopy = message.text.trim().isNotEmpty;
    final isOwnMessage = message.senderId == _currentUserId;
    final isPinned = _pinnedMessage?.messageId == message.id;
    final supportsSafetyActions = _safetyService != null;
    final canReport = supportsSafetyActions && !isOwnMessage;
    final canBlock = canReport &&
        _isCurrentDirectChat &&
        (_currentDirectPeerUserId == null ||
            _currentDirectPeerUserId == message.senderId);
    final currentReaction = _currentReactionEmoji(message.id);
    final useDesktopMenu =
        _useDesktopMessageContextMenu() && anchorPosition != null;
    _MessageSheetSelection? selection;
    if (useDesktopMenu) {
      selection = await _showDesktopMessagePopover<_MessageSheetSelection>(
        anchorPosition: anchorPosition,
        reactions: _quickReactionEmoji,
        reactionValueBuilder: (emoji) => _MessageSheetSelection(
          action: _MessageAction.react,
          emoji: emoji,
        ),
        actions: <_ContextMenuActionItem<_MessageSheetSelection>>[
          const _ContextMenuActionItem<_MessageSheetSelection>(
            label: 'Ответить',
            icon: Icons.reply_rounded,
            value: _MessageSheetSelection(action: _MessageAction.reply),
          ),
          const _ContextMenuActionItem<_MessageSheetSelection>(
            label: 'Переслать',
            icon: Icons.forward_rounded,
            value: _MessageSheetSelection(action: _MessageAction.forward),
          ),
          const _ContextMenuActionItem<_MessageSheetSelection>(
            label: 'Выбрать',
            icon: Icons.checklist_rounded,
            value: _MessageSheetSelection(action: _MessageAction.select),
          ),
          _ContextMenuActionItem<_MessageSheetSelection>(
            label: isPinned ? 'Открепить' : 'Закрепить',
            icon: isPinned ? Icons.push_pin : Icons.push_pin_outlined,
            value: const _MessageSheetSelection(
              action: _MessageAction.pin,
            ),
          ),
          if (isOwnMessage)
            const _ContextMenuActionItem<_MessageSheetSelection>(
              label: 'Редактировать',
              icon: Icons.edit_outlined,
              value: _MessageSheetSelection(action: _MessageAction.edit),
            ),
          if (canCopy)
            const _ContextMenuActionItem<_MessageSheetSelection>(
              label: 'Копировать текст',
              icon: Icons.copy_rounded,
              value: _MessageSheetSelection(action: _MessageAction.copy),
            ),
          if (canReport)
            const _ContextMenuActionItem<_MessageSheetSelection>(
              label: 'Пожаловаться',
              icon: Icons.flag_outlined,
              value: _MessageSheetSelection(action: _MessageAction.report),
              isDestructive: true,
            ),
          if (canBlock)
            const _ContextMenuActionItem<_MessageSheetSelection>(
              label: 'Заблокировать',
              icon: Icons.block_outlined,
              value: _MessageSheetSelection(action: _MessageAction.block),
              isDestructive: true,
            ),
          if (isOwnMessage)
            const _ContextMenuActionItem<_MessageSheetSelection>(
              label: 'Удалить сообщение',
              icon: Icons.delete_outline_rounded,
              value: _MessageSheetSelection(action: _MessageAction.delete),
              isDestructive: true,
            ),
        ],
      );
    } else {
      selection = await showModalBottomSheet<_MessageSheetSelection>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Быстрые реакции',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _quickReactionEmoji
                        .map(
                          (emoji) => ChoiceChip(
                            label: Text(emoji),
                            selected: currentReaction == emoji,
                            onSelected: (_) => Navigator.of(context).pop(
                              _MessageSheetSelection(
                                action: _MessageAction.react,
                                emoji: emoji,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.reply_rounded),
                  title: const Text('Ответить'),
                  onTap: () => Navigator.of(context).pop(
                    const _MessageSheetSelection(
                      action: _MessageAction.reply,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.forward_rounded),
                  title: const Text('Переслать'),
                  onTap: () => Navigator.of(context).pop(
                    const _MessageSheetSelection(
                      action: _MessageAction.forward,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.checklist_rounded),
                  title: const Text('Выбрать'),
                  onTap: () => Navigator.of(context).pop(
                    const _MessageSheetSelection(
                      action: _MessageAction.select,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(
                    isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  ),
                  title: Text(isPinned ? 'Открепить' : 'Закрепить'),
                  onTap: () => Navigator.of(context).pop(
                    const _MessageSheetSelection(action: _MessageAction.pin),
                  ),
                ),
                if (isOwnMessage)
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Редактировать'),
                    onTap: () => Navigator.of(context).pop(
                      const _MessageSheetSelection(
                        action: _MessageAction.edit,
                      ),
                    ),
                  ),
                if (canCopy)
                  ListTile(
                    leading: const Icon(Icons.copy_rounded),
                    title: const Text('Копировать текст'),
                    onTap: () => Navigator.of(context).pop(
                      const _MessageSheetSelection(
                        action: _MessageAction.copy,
                      ),
                    ),
                  ),
                if (canReport)
                  ListTile(
                    leading: const Icon(Icons.flag_outlined),
                    title: const Text('Пожаловаться'),
                    onTap: () => Navigator.of(context).pop(
                      const _MessageSheetSelection(
                        action: _MessageAction.report,
                      ),
                    ),
                  ),
                if (canBlock)
                  ListTile(
                    leading: const Icon(Icons.block_outlined),
                    title: const Text('Заблокировать'),
                    onTap: () => Navigator.of(context).pop(
                      const _MessageSheetSelection(
                        action: _MessageAction.block,
                      ),
                    ),
                  ),
                if (isOwnMessage)
                  ListTile(
                    leading: const Icon(Icons.delete_outline_rounded),
                    title: const Text('Удалить сообщение'),
                    onTap: () => Navigator.of(context).pop(
                      const _MessageSheetSelection(
                        action: _MessageAction.delete,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    if (!mounted || selection == null) {
      return;
    }
    if (selection.action == _MessageAction.react && selection.emoji != null) {
      await _toggleReactionForMessage(message, selection.emoji!);
      return;
    }
    if (selection.action == _MessageAction.reply) {
      _selectReplyFromMessage(message);
      return;
    }
    if (selection.action == _MessageAction.forward) {
      _selectForwardFromMessage(message);
      return;
    }
    if (selection.action == _MessageAction.select) {
      _selectRemoteMessage(message);
      return;
    }
    if (selection.action == _MessageAction.pin) {
      if (isPinned) {
        await _clearPinnedMessage();
      } else {
        await _pinRemoteMessage(message);
      }
      return;
    }
    if (selection.action == _MessageAction.edit) {
      _selectEditMessage(message);
      return;
    }
    if (selection.action == _MessageAction.copy) {
      await _copyMessageText(message.text);
      return;
    }
    if (selection.action == _MessageAction.report) {
      await _reportRemoteMessage(message);
      return;
    }
    if (selection.action == _MessageAction.block) {
      await _blockUserFromMessage(message);
      return;
    }
    if (selection.action == _MessageAction.delete) {
      await _deleteRemoteMessage(message);
    }
  }

  Future<void> _openOutgoingMessageActions(
    _OutgoingMessage message, {
    Offset? anchorPosition,
  }) async {
    final canCopy = message.text.trim().isNotEmpty;
    final useDesktopMenu =
        _useDesktopMessageContextMenu() && anchorPosition != null;
    _MessageAction? action;
    if (useDesktopMenu) {
      action = await _showDesktopMessagePopover<_MessageAction>(
        anchorPosition: anchorPosition,
        actions: <_ContextMenuActionItem<_MessageAction>>[
          const _ContextMenuActionItem<_MessageAction>(
            label: 'Ответить',
            icon: Icons.reply_rounded,
            value: _MessageAction.reply,
          ),
          const _ContextMenuActionItem<_MessageAction>(
            label: 'Переслать',
            icon: Icons.forward_rounded,
            value: _MessageAction.forward,
          ),
          const _ContextMenuActionItem<_MessageAction>(
            label: 'Выбрать',
            icon: Icons.checklist_rounded,
            value: _MessageAction.select,
          ),
          if (canCopy)
            const _ContextMenuActionItem<_MessageAction>(
              label: 'Копировать текст',
              icon: Icons.copy_rounded,
              value: _MessageAction.copy,
            ),
          if (message.status == _OutgoingMessageStatus.failed)
            const _ContextMenuActionItem<_MessageAction>(
              label: 'Повторить отправку',
              icon: Icons.refresh_rounded,
              value: _MessageAction.retry,
            ),
          if (message.status != _OutgoingMessageStatus.sent)
            const _ContextMenuActionItem<_MessageAction>(
              label: 'Убрать из очереди',
              icon: Icons.delete_outline_rounded,
              value: _MessageAction.delete,
              isDestructive: true,
            ),
        ],
      );
    } else {
      action = await showModalBottomSheet<_MessageAction>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text('Ответить'),
                onTap: () => Navigator.of(context).pop(_MessageAction.reply),
              ),
              ListTile(
                leading: const Icon(Icons.forward_rounded),
                title: const Text('Переслать'),
                onTap: () => Navigator.of(context).pop(_MessageAction.forward),
              ),
              ListTile(
                leading: const Icon(Icons.checklist_rounded),
                title: const Text('Выбрать'),
                onTap: () => Navigator.of(context).pop(_MessageAction.select),
              ),
              if (canCopy)
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('Копировать текст'),
                  onTap: () => Navigator.of(context).pop(_MessageAction.copy),
                ),
              if (message.status == _OutgoingMessageStatus.failed)
                ListTile(
                  leading: const Icon(Icons.refresh_rounded),
                  title: const Text('Повторить отправку'),
                  onTap: () => Navigator.of(context).pop(_MessageAction.retry),
                ),
              if (message.status != _OutgoingMessageStatus.sent)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Убрать из очереди'),
                  onTap: () => Navigator.of(context).pop(_MessageAction.delete),
                ),
            ],
          ),
        ),
      );
    }
    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case _MessageAction.react:
        return;
      case _MessageAction.reply:
        _selectReplyFromOutgoingMessage(message);
        return;
      case _MessageAction.forward:
        _selectForwardFromOutgoingMessage(message);
        return;
      case _MessageAction.select:
        _selectOutgoingMessage(message);
        return;
      case _MessageAction.pin:
        return;
      case _MessageAction.edit:
        return;
      case _MessageAction.copy:
        await _copyMessageText(message.text);
        return;
      case _MessageAction.report:
        return;
      case _MessageAction.block:
        return;
      case _MessageAction.retry:
        await _sendOptimisticMessage(
          message.copyWith(
            status: _OutgoingMessageStatus.pending,
            errorText: null,
          ),
        );
        return;
      case _MessageAction.delete:
        setState(() {
          _optimisticMessages
              .removeWhere((item) => item.localId == message.localId);
        });
        return;
    }
  }

  void _selectReplyFromMessage(ChatMessage message) {
    final senderName =
        _groupSenderLabel(message.senderName, message.senderId) ??
            (message.senderId == _currentUserId ? 'Вы' : 'Участник');
    setState(() {
      _selectedEdit = null;
      _selectedForward = null;
      _selectedForwardBatch = null;
      _selectedReply = ChatReplyReference(
        messageId: message.id,
        senderId: message.senderId,
        senderName: senderName,
        text: message.text,
      );
    });
  }

  void _selectReplyFromOutgoingMessage(_OutgoingMessage message) {
    final senderName = message.senderId == _currentUserId ? 'Вы' : 'Участник';
    setState(() {
      _selectedEdit = null;
      _selectedForward = null;
      _selectedForwardBatch = null;
      _selectedReply = ChatReplyReference(
        messageId: message.localId,
        senderId: message.senderId,
        senderName: senderName,
        text: message.text,
      );
    });
  }

  void _selectForwardFromMessage(ChatMessage message) {
    final senderName =
        _groupSenderLabel(message.senderName, message.senderId) ??
            (message.senderId == _currentUserId ? 'Вы' : 'Участник');
    setState(() {
      _selectedEdit = null;
      _selectedReply = null;
      _selectedForwardBatch = null;
      _selectedForward = _ForwardDraft(
        senderName: senderName,
        text: message.text,
        attachments: message.attachments,
      );
    });
  }

  void _selectForwardFromOutgoingMessage(_OutgoingMessage message) {
    final senderName = message.senderId == _currentUserId ? 'Вы' : 'Участник';
    final forwardedAttachments = message.forwardedAttachments.isNotEmpty
        ? message.forwardedAttachments
        : message.attachments
            .map(
              (file) => ChatAttachment(
                type: _attachmentTypeForDraft(file),
                url: file.path,
                mimeType: file.mimeType,
                fileName: file.name,
              ),
            )
            .toList();
    setState(() {
      _selectedEdit = null;
      _selectedReply = null;
      _selectedForwardBatch = null;
      _selectedForward = _ForwardDraft(
        senderName: senderName,
        text: message.text,
        attachments: forwardedAttachments,
      );
    });
  }

  void _selectEditMessage(ChatMessage message) {
    _messageController.value = TextEditingValue(
      text: message.text,
      selection: TextSelection.collapsed(offset: message.text.length),
    );
    setState(() {
      _selectedReply = null;
      _selectedForward = null;
      _selectedForwardBatch = null;
      _selectedAttachments.clear();
      _selectedEdit = _EditDraft(
        messageId: message.id,
        originalText: message.text,
        hasAttachments: message.attachments.isNotEmpty,
      );
    });
  }

  bool _useDesktopMessageContextMenu() {
    final platform = Theme.of(context).platform;
    final isDesktopPlatform = kIsWeb ||
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux;
    return isDesktopPlatform && MediaQuery.of(context).size.width >= 720;
  }

  Future<T?> _showDesktopMessagePopover<T>({
    required Offset anchorPosition,
    required List<_ContextMenuActionItem<T>> actions,
    List<String> reactions = const <String>[],
    T Function(String emoji)? reactionValueBuilder,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'message-context-menu',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (dialogContext, _, __) {
        final screenSize = MediaQuery.of(dialogContext).size;
        const popupWidth = 320.0;
        final reactionBarHeight = reactions.isEmpty ? 0.0 : 58.0;
        final menuHeight = 16.0 + actions.length * 46.0;
        final totalHeight =
            reactionBarHeight + (reactionBarHeight == 0 ? 0 : 8) + menuHeight;
        final openBelow =
            anchorPosition.dy + totalHeight + 12 <= screenSize.height;
        final resolvedLeft = (anchorPosition.dx - popupWidth / 2)
            .clamp(12.0, screenSize.width - popupWidth - 12.0);
        final resolvedTop = (openBelow
                ? anchorPosition.dy + 10
                : anchorPosition.dy - totalHeight - 10)
            .clamp(12.0, screenSize.height - totalHeight - 12.0);

        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => Navigator.of(dialogContext).maybePop(),
              ),
            ),
            Positioned(
              left: resolvedLeft,
              top: resolvedTop,
              child: _DesktopMessageContextMenu<T>(
                reactions: reactions,
                actions: actions,
                onReactionSelected: reactionValueBuilder == null
                    ? null
                    : (emoji) => Navigator.of(dialogContext)
                        .pop(reactionValueBuilder(emoji)),
                onActionSelected: (value) {
                  Navigator.of(dialogContext).pop(value);
                },
              ),
            ),
          ],
        );
      },
      transitionBuilder: (context, animation, _, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curvedAnimation,
          child: ScaleTransition(
            scale: Tween<double>(
              begin: 0.96,
              end: 1,
            ).animate(curvedAnimation),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _openRemoteAttachmentPreview(
    ChatMessage message,
    List<ChatAttachment> attachments,
    ChatAttachment initialAttachment,
  ) async {
    final currentAttachmentIndex = attachments.indexWhere(
      (attachment) => _attachmentsMatch(attachment, initialAttachment),
    );
    final initialItemId =
        'remote:${message.id}:${currentAttachmentIndex < 0 ? 0 : currentAttachmentIndex}';
    final previewItems = _remoteAttachmentGalleryItems();
    if (previewItems.isEmpty) {
      return;
    }
    final initialIndex = previewItems.indexWhere(
      (item) => item.id == initialItemId,
    );
    await showDialog<void>(
      context: context,
      builder: (context) => _AttachmentViewerDialog(
        items: previewItems,
        initialIndex: initialIndex == -1 ? 0 : initialIndex,
        onOpenExternally: _openAttachmentExternally,
        onDownload: _downloadAttachmentToDevice,
      ),
    );
  }

  Future<void> _openLocalAttachmentPreview(
    List<XFile> files,
    XFile initialFile,
  ) async {
    final kind = _attachmentKindFromXFile(initialFile);
    if (kind == _ChatAttachmentKind.other) {
      await _openLocalAttachmentExternally(initialFile);
      return;
    }

    final previewItems = files
        .where((file) =>
            _attachmentKindFromXFile(file) != _ChatAttachmentKind.audio)
        .toList()
        .asMap()
        .entries
        .map(
          (entry) => _attachmentPreviewItemFromLocal(
            entry.value,
            id: 'local:${entry.key}:${entry.value.name}',
          ),
        )
        .toList();
    if (previewItems.isEmpty) {
      return;
    }
    final initialIndex = previewItems.indexWhere(
      (item) => item.displayName == _displayName(initialFile.name),
    );
    await showDialog<void>(
      context: context,
      builder: (context) => _AttachmentViewerDialog(
        items: previewItems,
        initialIndex: initialIndex == -1 ? 0 : initialIndex,
        onOpenExternally: _openAttachmentExternally,
        onDownload: _downloadAttachmentToDevice,
      ),
    );
  }

  List<_AttachmentPreviewItem> _remoteAttachmentGalleryItems() {
    final messages = List<ChatMessage>.from(_latestRemoteMessages)
      ..sort((left, right) => left.timestamp.compareTo(right.timestamp));
    final previewItems = <_AttachmentPreviewItem>[];
    for (final message in messages) {
      final senderLabel = _senderDisplayNameForMessage(
        senderId: message.senderId,
        senderName: message.senderName,
      );
      for (var index = 0; index < message.attachments.length; index++) {
        final attachment = message.attachments[index];
        final kind = _attachmentKindFromAttachment(attachment);
        if (kind == _ChatAttachmentKind.audio) {
          continue;
        }
        previewItems.add(
          _attachmentPreviewItemFromRemote(
            attachment,
            id: 'remote:${message.id}:$index',
            senderLabel: senderLabel,
            timestamp: message.timestamp,
            caption: message.text.trim(),
          ),
        );
      }
    }
    return previewItems;
  }

  _AttachmentPreviewItem _attachmentPreviewItemFromRemote(
    ChatAttachment attachment, {
    required String id,
    String? senderLabel,
    DateTime? timestamp,
    String? caption,
  }) {
    return _AttachmentPreviewItem.remote(
      id: id,
      kind: _attachmentKindFromAttachment(attachment),
      source: attachment.url,
      displayName: _displayName(attachment.fileName ?? attachment.url),
      thumbnailUrl: attachment.thumbnailUrl,
      senderLabel: senderLabel,
      timestamp: timestamp,
      caption: caption,
    );
  }

  _AttachmentPreviewItem _attachmentPreviewItemFromLocal(
    XFile file, {
    required String id,
  }) {
    return _AttachmentPreviewItem.local(
      id: id,
      kind: _attachmentKindFromXFile(file),
      file: file,
      displayName: _displayName(file.name),
      senderLabel: 'Вы',
      timestamp: DateTime.now(),
      caption: '',
    );
  }

  bool _attachmentsMatch(ChatAttachment left, ChatAttachment right) {
    return left.type == right.type &&
        left.url == right.url &&
        left.fileName == right.fileName &&
        left.thumbnailUrl == right.thumbnailUrl;
  }

  Future<void> _openAttachmentExternally(_AttachmentPreviewItem item) async {
    try {
      if (!item.isRemote && item.file != null) {
        await _openLocalAttachmentExternally(item.file!);
        return;
      }
      final source = item.source;
      if (source == null || source.trim().isEmpty) {
        return;
      }
      final uri = Uri.parse(source);
      await launchUrl(
        uri,
        mode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть вложение.')),
      );
    }
  }

  Future<void> _openLocalAttachmentExternally(XFile file) async {
    try {
      if (kIsWeb && file.path.trim().isNotEmpty) {
        await launchUrl(
          Uri.parse(file.path),
          webOnlyWindowName: '_blank',
        );
        return;
      }
      await OpenFilex.open(file.path);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть локальный файл.')),
      );
    }
  }

  Future<void> _downloadAttachmentToDevice(_AttachmentPreviewItem item) async {
    try {
      if (!item.isRemote ||
          item.source == null ||
          item.source!.trim().isEmpty) {
        await _openAttachmentExternally(item);
        return;
      }
      if (supportsChatAttachmentDownload) {
        await downloadChatAttachment(
          item.source!,
          suggestedFileName: item.displayName,
        );
      } else {
        await _openAttachmentExternally(item);
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            supportsChatAttachmentDownload
                ? 'Скачивание запущено'
                : 'Вложение открыто во внешнем приложении',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить вложение.')),
      );
    }
  }

  Future<void> _deleteRemoteMessage(ChatMessage message) async {
    final chatId = _chatId;
    if (chatId == null || chatId.isEmpty) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить сообщение'),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }

    try {
      await _chatService.deleteChatMessage(
        chatId: chatId,
        messageId: message.id,
      );
      if (!mounted) {
        return;
      }
      if (_selectedEdit?.messageId == message.id) {
        _messageController.clear();
        setState(() {
          _selectedEdit = null;
        });
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось удалить сообщение.')),
      );
    }
  }

  ChatAttachmentType _attachmentTypeForDraft(XFile file) {
    switch (_attachmentKindFromXFile(file)) {
      case _ChatAttachmentKind.image:
        return ChatAttachmentType.image;
      case _ChatAttachmentKind.video:
        return ChatAttachmentType.video;
      case _ChatAttachmentKind.audio:
        return ChatAttachmentType.audio;
      case _ChatAttachmentKind.other:
        return ChatAttachmentType.file;
    }
  }

  Widget _buildReplyComposerBar(ThemeData theme, ChatReplyReference reply) {
    final hasText = reply.text.trim().isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 36,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Ответ: ${reply.senderName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasText ? reply.text : 'Сообщение без текста',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {
              setState(() {
                _selectedReply = null;
              });
            },
            tooltip: 'Отменить ответ',
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildEditComposerBar(ThemeData theme, _EditDraft draft) {
    final originalText = draft.originalText.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.secondary,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Редактируете сообщение',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.secondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  originalText.isNotEmpty
                      ? originalText
                      : (draft.hasAttachments
                          ? 'Сообщение с вложением'
                          : 'Сообщение без текста'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Отменить редактирование',
            onPressed: () {
              _messageController.clear();
              setState(() {
                _selectedEdit = null;
              });
            },
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildForwardComposerBar(ThemeData theme, _ForwardDraft draft) {
    final hasText = draft.text.trim().isNotEmpty;
    final attachmentCount = draft.attachments.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 42,
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiary,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Пересылаете: ${draft.senderName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.tertiary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasText ? draft.text : 'Сообщение без текста',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (attachmentCount > 0)
                  Text(
                    _attachmentCountLabel(attachmentCount),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Отменить пересылку',
            onPressed: () {
              setState(() {
                _selectedForward = null;
              });
            },
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildForwardBatchComposerBar(
    ThemeData theme,
    _ForwardBatchDraft draft,
  ) {
    final messageCount = draft.items.length;
    final attachmentCount = draft.items.fold<int>(
      0,
      (total, item) => total + item.attachments.length,
    );
    final previewText = draft.items.map((item) => item.text.trim()).firstWhere(
          (text) => text.isNotEmpty,
          orElse: () => 'Сообщения без текста',
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 42,
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiary,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  messageCount == 1
                      ? 'Пересылаете 1 сообщение'
                      : 'Пересылаете $messageCount сообщений',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.tertiary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  previewText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (attachmentCount > 0)
                  Text(
                    _attachmentCountLabel(attachmentCount),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Отменить пересылку',
            onPressed: () {
              setState(() {
                _selectedForwardBatch = null;
              });
            },
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  String _attachmentCountLabel(int count) {
    final noun = count == 1
        ? 'вложение'
        : (count >= 2 && count <= 4 ? 'вложения' : 'вложений');
    return '$count $noun';
  }
}

class _ChatInfoSheet extends StatefulWidget {
  const _ChatInfoSheet({
    required this.initialDetails,
    required this.currentUserId,
    required this.hasPinnedMessage,
    required this.initialNotificationLevel,
    required this.initialAutoDeleteOption,
    required this.onRename,
    required this.onAddParticipants,
    required this.onRemoveParticipant,
    required this.onOpenSearch,
    required this.onNotificationLevelChanged,
    required this.onAutoDeleteChanged,
    this.onOpenPinnedMessage,
    this.onOpenTree,
    this.onOpenRelatives,
    this.onOpenMedia,
    this.onOpenFiles,
  });

  final ChatDetails initialDetails;
  final String currentUserId;
  final bool hasPinnedMessage;
  final ChatNotificationLevel initialNotificationLevel;
  final ChatAutoDeleteOption initialAutoDeleteOption;
  final Future<ChatDetails> Function(String title) onRename;
  final Future<ChatDetails> Function(List<String> participantIds)
      onAddParticipants;
  final Future<ChatDetails> Function(String participantId) onRemoveParticipant;
  final VoidCallback onOpenSearch;
  final Future<void> Function(ChatNotificationLevel level)
      onNotificationLevelChanged;
  final Future<void> Function(ChatAutoDeleteOption option) onAutoDeleteChanged;
  final VoidCallback? onOpenPinnedMessage;
  final VoidCallback? onOpenTree;
  final VoidCallback? onOpenRelatives;
  final VoidCallback? onOpenMedia;
  final VoidCallback? onOpenFiles;

  @override
  State<_ChatInfoSheet> createState() => _ChatInfoSheetState();
}

class _ChatInfoSheetState extends State<_ChatInfoSheet> {
  late ChatDetails _details;
  late ChatNotificationLevel _notificationLevel;
  late ChatAutoDeleteOption _autoDeleteOption;
  bool _isSaving = false;
  bool _isUpdatingNotifications = false;
  bool _isUpdatingAutoDelete = false;

  @override
  void initState() {
    super.initState();
    _details = widget.initialDetails;
    _notificationLevel = widget.initialNotificationLevel;
    _autoDeleteOption = widget.initialAutoDeleteOption;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFriendsTree =
        context.read<TreeProvider>().selectedTreeKind == TreeKind.friends;
    final screenHeight = MediaQuery.of(context).size.height;
    final hasTreeContext =
        _details.treeId != null && _details.treeId!.trim().isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SizedBox(
          height: screenHeight * 0.84,
          child: ListView(
            children: [
              Row(
                children: [
                  Text(
                    'О чате',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                      backgroundColor: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _details.displayTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip(
                    icon: _details.isBranch
                        ? Icons.account_tree_outlined
                        : (_details.isDirect
                            ? Icons.chat_bubble_outline
                            : Icons.groups_2_outlined),
                    label: _details.isBranch
                        ? 'Чат ветки'
                        : _details.isDirect
                            ? 'Личный чат'
                            : (isFriendsTree ? 'Группа круга' : 'Группа'),
                  ),
                  _InfoChip(
                    icon: Icons.people_outline,
                    label: _details.memberCount == 1
                        ? '1 участник'
                        : '${_details.memberCount} участников',
                  ),
                  _InfoChip(
                    icon: isFriendsTree
                        ? Icons.diversity_3_outlined
                        : Icons.account_tree_outlined,
                    label: isFriendsTree ? 'Контекст круга' : 'Контекст дерева',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              GlassPanel(
                padding: const EdgeInsets.all(14),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoChip(
                      icon: Icons.mark_chat_unread_outlined,
                      label: _details.isEditableGroup
                          ? 'Можно редактировать'
                          : 'Состав фиксируется',
                    ),
                    _InfoChip(
                      icon: Icons.badge_outlined,
                      label: _details.participants.any((participant) =>
                              participant.userId == widget.currentUserId)
                          ? 'Вы в составе'
                          : 'Без вашего профиля',
                    ),
                    if (widget.hasPinnedMessage)
                      const _InfoChip(
                        icon: Icons.push_pin_outlined,
                        label: 'Есть закрепленное',
                      ),
                    _InfoChip(
                      icon: _notificationLevel == ChatNotificationLevel.muted
                          ? Icons.notifications_off_outlined
                          : (_notificationLevel == ChatNotificationLevel.silent
                              ? Icons.notifications_none_outlined
                              : Icons.notifications_active_outlined),
                      label: _notificationLevel.label,
                    ),
                    _InfoChip(
                      icon: _autoDeleteOption == ChatAutoDeleteOption.off
                          ? Icons.timer_off_outlined
                          : Icons.timer_outlined,
                      label: _autoDeleteOption == ChatAutoDeleteOption.off
                          ? 'Без автоудаления'
                          : 'TTL: ${_autoDeleteOption.label}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Быстрые действия',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _QuickActionCard(
                    icon: Icons.search,
                    title: 'Поиск в чате',
                    subtitle: 'По слову или фразе',
                    onTap: widget.onOpenSearch,
                  ),
                  if (widget.onOpenMedia != null)
                    _QuickActionCard(
                      icon: Icons.perm_media_outlined,
                      title: 'Медиа',
                      subtitle: 'Фото, видео и кружки',
                      onTap: widget.onOpenMedia!,
                    ),
                  if (widget.onOpenFiles != null)
                    _QuickActionCard(
                      icon: Icons.folder_open_outlined,
                      title: 'Файлы',
                      subtitle: 'Документы и голосовые',
                      onTap: widget.onOpenFiles!,
                    ),
                  if (widget.onOpenPinnedMessage != null)
                    _QuickActionCard(
                      icon: Icons.push_pin_outlined,
                      title: 'К закрепленному',
                      subtitle: 'Открыть закрепленное',
                      onTap: widget.onOpenPinnedMessage!,
                    ),
                  if (hasTreeContext && widget.onOpenTree != null)
                    _QuickActionCard(
                      icon: Icons.account_tree_outlined,
                      title: 'Открыть дерево',
                      subtitle: 'Перейти к дереву',
                      onTap: widget.onOpenTree!,
                    ),
                  if (hasTreeContext && widget.onOpenRelatives != null)
                    _QuickActionCard(
                      icon: Icons.people_alt_outlined,
                      title: 'Открыть родных',
                      subtitle: 'Перейти к списку',
                      onTap: widget.onOpenRelatives!,
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Уведомления',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              GlassPanel(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _notificationLevel.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _notificationLevel.summary,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ChatNotificationLevel.values.map((level) {
                        final isSelected = _notificationLevel == level;
                        return ChoiceChip(
                          label: Text(level.label),
                          selected: isSelected,
                          onSelected: _isUpdatingNotifications || isSelected
                              ? null
                              : (_) => _setNotificationLevel(level),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Автоудаление',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              GlassPanel(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _autoDeleteOption.label,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _autoDeleteOption.summary,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ChatAutoDeleteOption.values.map((option) {
                        final isSelected = _autoDeleteOption == option;
                        return ChoiceChip(
                          label: Text(option.label),
                          selected: isSelected,
                          onSelected: _isUpdatingAutoDelete || isSelected
                              ? null
                              : (_) => _setAutoDeleteOption(option),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              if (_details.branchRoots.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  isFriendsTree ? 'Круги' : 'Ветки',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _details.branchRoots
                      .map(
                        (root) => _InfoChip(
                          icon: isFriendsTree
                              ? Icons.diversity_3_outlined
                              : Icons.account_tree_outlined,
                          label: root.name,
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 18),
              Text(
                'Управление',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              if (_details.isEditableGroup)
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isSaving ? null : _renameChat,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Переименовать'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isSaving ? null : _addParticipants,
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                        label: const Text('Добавить'),
                      ),
                    ),
                  ],
                )
              else
                GlassPanel(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    _details.isBranch
                        ? 'Состав идет из дерева.'
                        : _details.isDirect
                            ? 'Состав личного чата фиксирован.'
                            : 'Состав сейчас не меняется.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              Text(
                'Участники',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              GlassPanel(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Column(
                  children: _details.participants.asMap().entries.map((entry) {
                    final index = entry.key;
                    final participant = entry.value;
                    final isCurrentUser =
                        participant.userId == widget.currentUserId;
                    return Column(
                      children: [
                        if (index > 0) const Divider(height: 1),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundImage: participant.photoUrl != null &&
                                    participant.photoUrl!.isNotEmpty
                                ? NetworkImage(participant.photoUrl!)
                                : null,
                            child: participant.photoUrl == null ||
                                    participant.photoUrl!.isEmpty
                                ? Text(
                                    participant.displayName.isNotEmpty
                                        ? participant.displayName[0]
                                        : '?',
                                  )
                                : null,
                          ),
                          title: Text(participant.displayName),
                          subtitle: Text(isCurrentUser ? 'Вы' : 'Участник'),
                          trailing: _details.isEditableGroup && !isCurrentUser
                              ? IconButton(
                                  onPressed: _isSaving
                                      ? null
                                      : () => _removeParticipant(participant),
                                  tooltip: 'Убрать из чата',
                                  icon: const Icon(
                                    Icons.person_remove_outlined,
                                  ),
                                )
                              : null,
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setNotificationLevel(ChatNotificationLevel level) async {
    if (_notificationLevel == level) {
      return;
    }
    final previousLevel = _notificationLevel;
    setState(() {
      _isUpdatingNotifications = true;
      _notificationLevel = level;
    });
    try {
      await widget.onNotificationLevelChanged(level);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _notificationLevel = previousLevel;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось обновить настройки уведомлений.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingNotifications = false;
        });
      }
    }
  }

  Future<void> _setAutoDeleteOption(ChatAutoDeleteOption option) async {
    if (_autoDeleteOption == option) {
      return;
    }
    final previousOption = _autoDeleteOption;
    setState(() {
      _isUpdatingAutoDelete = true;
      _autoDeleteOption = option;
    });
    try {
      await widget.onAutoDeleteChanged(option);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _autoDeleteOption = previousOption;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось обновить автоудаление сообщений.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingAutoDelete = false;
        });
      }
    }
  }

  Future<void> _renameChat() async {
    final controller = TextEditingController(text: _details.displayTitle);
    final nextTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Переименовать чат'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Название',
            hintText: 'Например, Семья Кузнецовых',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (!mounted || nextTitle == null || nextTitle.trim().isEmpty) {
      return;
    }

    setState(() {
      _isSaving = true;
    });
    try {
      final details = await widget.onRename(nextTitle.trim());
      if (!mounted) {
        return;
      }
      setState(() {
        _details = details;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось переименовать чат.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _addParticipants() async {
    final treeId = _details.treeId;
    if (treeId == null || treeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Для этого чата не найдено дерево.')),
      );
      return;
    }
    if (!GetIt.I.isRegistered<FamilyTreeServiceInterface>()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Список родных временно недоступен.')),
      );
      return;
    }

    final familyTreeService = GetIt.I<FamilyTreeServiceInterface>();
    final relatives = await familyTreeService.getRelatives(treeId);
    if (!mounted) {
      return;
    }

    final existingParticipantIds = _details.participantIds.toSet();
    final candidates = relatives
        .where((person) {
          final userId = person.userId?.trim();
          return userId != null &&
              userId.isNotEmpty &&
              userId != widget.currentUserId &&
              !existingParticipantIds.contains(userId);
        })
        .map(
          (person) => _GroupChatCandidate(
            userId: person.userId!.trim(),
            displayName:
                person.name.trim().isNotEmpty ? person.name : 'Пользователь',
            photoUrl: person.photoUrl,
            relationLabel: (person.relation ?? '').trim().isNotEmpty
                ? person.relation!.trim()
                : 'Родственник',
          ),
        )
        .toList()
      ..sort((left, right) => left.displayName.compareTo(right.displayName));

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('В этом дереве больше некого добавить.')),
      );
      return;
    }

    final selectedIds = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _AddParticipantsSheet(candidates: candidates),
    );

    if (!mounted || selectedIds == null || selectedIds.isEmpty) {
      return;
    }

    setState(() {
      _isSaving = true;
    });
    try {
      final details = await widget.onAddParticipants(selectedIds);
      if (!mounted) {
        return;
      }
      setState(() {
        _details = details;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось добавить участников.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _removeParticipant(
    ChatParticipantSummary participant,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Убрать участника'),
        content: Text(
          'Убрать ${participant.displayName} из этого чата?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Убрать'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }

    setState(() {
      _isSaving = true;
    });
    try {
      final details = await widget.onRemoveParticipant(participant.userId);
      if (!mounted) {
        return;
      }
      setState(() {
        _details = details;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось обновить состав чата.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 220,
      child: GlassPanel(
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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

class _AddParticipantsSheet extends StatefulWidget {
  const _AddParticipantsSheet({required this.candidates});

  final List<_GroupChatCandidate> candidates;

  @override
  State<_AddParticipantsSheet> createState() => _AddParticipantsSheetState();
}

class _AddParticipantsSheetState extends State<_AddParticipantsSheet> {
  final Set<String> _selectedIds = <String>{};
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = _searchController.text.trim().toLowerCase();
    final filteredCandidates = widget.candidates.where((candidate) {
      if (search.isEmpty) {
        return true;
      }
      return candidate.displayName.toLowerCase().contains(search) ||
          candidate.relationLabel.toLowerCase().contains(search);
    }).toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SizedBox(
          height: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Добавить участников',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    _selectedIds.isEmpty ? '0' : '${_selectedIds.length}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              GlassPanel(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Найти по имени',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: filteredCandidates.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final candidate = filteredCandidates[index];
                    final isSelected = _selectedIds.contains(candidate.userId);
                    return GlassPanel(
                      padding: EdgeInsets.zero,
                      child: CheckboxListTile(
                        value: isSelected,
                        onChanged: (_) {
                          setState(() {
                            if (isSelected) {
                              _selectedIds.remove(candidate.userId);
                            } else {
                              _selectedIds.add(candidate.userId);
                            }
                          });
                        },
                        secondary: CircleAvatar(
                          backgroundImage: candidate.photoUrl != null &&
                                  candidate.photoUrl!.isNotEmpty
                              ? NetworkImage(candidate.photoUrl!)
                              : null,
                          child: candidate.photoUrl == null ||
                                  candidate.photoUrl!.isEmpty
                              ? Text(
                                  candidate.displayName.isNotEmpty
                                      ? candidate.displayName[0]
                                      : '?',
                                )
                              : null,
                        ),
                        title: Text(candidate.displayName),
                        subtitle: Text(candidate.relationLabel),
                        controlAffinity: ListTileControlAffinity.trailing,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _selectedIds.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(_selectedIds.toList()),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: Text(
                    _selectedIds.isEmpty
                        ? 'Выберите участников'
                        : 'Добавить ${_selectedIds.length}',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _AttachmentPickerChoice { images, video, videoNote, file }

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

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.isMe,
    required this.text,
    required this.timeLabel,
    required this.isRead,
    required this.isPinned,
    required this.isHighlighted,
    this.highlightQuery = '',
    this.senderLabel,
    this.remoteAttachments = const <ChatAttachment>[],
    this.localAttachments = const <XFile>[],
    this.replyTo,
    this.reactionGroups = const <_ReactionGroup>[],
    this.onReactionTap,
    this.footerLabel,
    this.showSelectionMarker = false,
    this.isSelected = false,
    this.onOpenRemoteAttachment,
    this.onOpenLocalAttachment,
  });

  final bool isMe;
  final String text;
  final String timeLabel;
  final bool isRead;
  final bool isPinned;
  final bool isHighlighted;
  final String highlightQuery;
  final String? senderLabel;
  final List<ChatAttachment> remoteAttachments;
  final List<XFile> localAttachments;
  final ChatReplyReference? replyTo;
  final List<_ReactionGroup> reactionGroups;
  final ValueChanged<String>? onReactionTap;
  final String? footerLabel;
  final bool showSelectionMarker;
  final bool isSelected;
  final void Function(
          List<ChatAttachment> attachments, ChatAttachment attachment)?
      onOpenRemoteAttachment;
  final void Function(List<XFile> files, XFile file)? onOpenLocalAttachment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // WhatsApp/Telegram-inspired bubble palette tuned to the warm teal brand.
    final Color bubbleColor;
    final Color onBubbleColor;
    final Color metaColor;
    final List<BoxShadow> bubbleShadow;
    final BoxBorder? bubbleBorder;

    if (isMe) {
      // Outgoing: solid accent gradient — confident, on-brand.
      bubbleColor = scheme.primary;
      onBubbleColor = scheme.onPrimary;
      metaColor = scheme.onPrimary.withValues(alpha: 0.78);
      bubbleShadow = [
        BoxShadow(
          color: scheme.primary.withValues(alpha: isDark ? 0.32 : 0.22),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ];
      bubbleBorder = null;
    } else {
      // Incoming: glassy surface tile with hairline border + soft drop shadow.
      bubbleColor = isDark
          ? scheme.surfaceContainerHigh.withValues(alpha: 0.92)
          : scheme.surface.withValues(alpha: 0.94);
      onBubbleColor = scheme.onSurface;
      metaColor = scheme.onSurfaceVariant;
      bubbleShadow = [
        BoxShadow(
          color: scheme.shadow.withValues(alpha: isDark ? 0.32 : 0.06),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ];
      bubbleBorder = Border.all(
        color: scheme.outlineVariant.withValues(alpha: isDark ? 0.4 : 0.55),
        width: 0.7,
      );
    }

    final highlightBorder = isHighlighted
        ? Border.all(color: scheme.tertiary, width: 1.6)
        : isSelected
            ? Border.all(color: scheme.primary, width: 1.4)
            : bubbleBorder;

    final outgoingGradient = isMe
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primary,
              Color.alphaBlend(
                Colors.black.withValues(alpha: 0.08),
                scheme.primary,
              ),
            ],
          )
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (showSelectionMarker) ...[
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? scheme.primary : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? scheme.primary
                      : scheme.outline.withValues(alpha: 0.72),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: scheme.onPrimary,
                    )
                  : null,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Align(
              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.78,
                ),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  decoration: BoxDecoration(
                    color: outgoingGradient == null ? bubbleColor : null,
                    gradient: outgoingGradient,
                    border: highlightBorder,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(isMe ? 20 : 6),
                      bottomRight: Radius.circular(isMe ? 6 : 20),
                    ),
                    boxShadow: bubbleShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      if (senderLabel != null && senderLabel!.isNotEmpty) ...[
                        Text(
                          senderLabel!,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: isMe
                                ? scheme.onPrimary.withValues(alpha: 0.92)
                                : scheme.primary,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.1,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (isPinned) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.push_pin,
                              size: 12,
                              color: metaColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Закреплено',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: metaColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                      ],
                      if (replyTo != null) ...[
                        _ReplyQuoteCard(
                          reply: replyTo!,
                          isMe: isMe,
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (remoteAttachments.isNotEmpty) ...[
                        _buildRemoteAttachments(context),
                        const SizedBox(height: 8),
                      ],
                      if (localAttachments.isNotEmpty) ...[
                        _buildLocalAttachments(context),
                        const SizedBox(height: 8),
                      ],
                      if (text.isNotEmpty)
                        _HighlightedMessageText(
                          text: text,
                          query: highlightQuery,
                          color: onBubbleColor,
                        ),
                      if (text.isEmpty &&
                          remoteAttachments.isEmpty &&
                          localAttachments.isEmpty)
                        Text(
                          'Сообщение',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: onBubbleColor,
                          ),
                        ),
                      if (reactionGroups.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: reactionGroups
                              .map(
                                (reaction) => _ReactionPill(
                                  reaction: reaction,
                                  isMe: isMe,
                                  onTap: onReactionTap == null
                                      ? null
                                      : () => onReactionTap!(reaction.emoji),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            timeLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: metaColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 4),
                            Icon(
                              isRead ? Icons.done_all : Icons.done,
                              size: 14,
                              color: isRead
                                  ? scheme.tertiary
                                  : scheme.onPrimary.withValues(alpha: 0.78),
                            ),
                          ],
                        ],
                      ),
                      if (footerLabel != null && footerLabel!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          footerLabel!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: metaColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemoteAttachments(BuildContext context) {
    final audio = remoteAttachments
        .where((a) => a.type == ChatAttachmentType.audio)
        .toList();
    final videoNotes = remoteAttachments.where((a) => a.isVideoNote).toList();
    final visuals = remoteAttachments
        .where((a) => a.type != ChatAttachmentType.audio && !a.isVideoNote)
        .toList();

    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (audio.isNotEmpty)
          ...audio.map(
            (attachment) => _VoicePlayerWidget(
              url: attachment.url,
              isMe: isMe,
              initialDuration: attachment.durationMs == null
                  ? null
                  : Duration(milliseconds: attachment.durationMs!),
              semanticLabel: attachment.isVoiceNote
                  ? 'Голосовое сообщение'
                  : 'Аудиовложение',
            ),
          ),
        if (videoNotes.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: videoNotes
                .map(
                  (attachment) => _VideoNoteTile(
                    previewUrl: attachment.thumbnailUrl,
                    durationLabel: attachment.durationMs == null
                        ? null
                        : _formatAttachmentDuration(
                            Duration(milliseconds: attachment.durationMs!),
                          ),
                    label: 'Кружок',
                    onTap: onOpenRemoteAttachment == null
                        ? null
                        : () => onOpenRemoteAttachment!(
                            remoteAttachments, attachment),
                  ),
                )
                .toList(),
          ),
          if (visuals.isNotEmpty) const SizedBox(height: 8),
        ],
        if (visuals.isNotEmpty)
          _RemoteMediaGrid(
            attachments: visuals,
            onOpenAttachment: onOpenRemoteAttachment,
          ),
      ],
    );
  }

  Widget _buildLocalAttachments(BuildContext context) {
    final audio = localAttachments
        .where((f) => _attachmentKindFromXFile(f) == _ChatAttachmentKind.audio)
        .toList();
    final videoNotes = localAttachments
        .where((file) => _isVideoNoteFileName(file.name))
        .toList();
    final visuals = localAttachments
        .where(
          (file) =>
              _attachmentKindFromXFile(file) != _ChatAttachmentKind.audio &&
              !_isVideoNoteFileName(file.name),
        )
        .toList();

    return Column(
      crossAxisAlignment:
          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (audio.isNotEmpty)
          ...audio.map(
            (file) => _VoicePlayerWidget(
              path: file.path,
              isMe: isMe,
              initialDuration: _durationFromAttachmentName(file.name),
              semanticLabel: _isVoiceNoteFileName(file.name)
                  ? 'Голосовое сообщение'
                  : 'Аудиовложение',
            ),
          ),
        if (videoNotes.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: videoNotes
                .map(
                  (file) => _VideoNoteTile(
                    durationLabel:
                        _durationFromAttachmentName(file.name) == null
                            ? null
                            : _formatAttachmentDuration(
                                _durationFromAttachmentName(file.name)!,
                              ),
                    label: 'Кружок',
                    onTap: onOpenLocalAttachment == null
                        ? null
                        : () => onOpenLocalAttachment!(localAttachments, file),
                  ),
                )
                .toList(),
          ),
          if (visuals.isNotEmpty) const SizedBox(height: 8),
        ],
        if (visuals.isNotEmpty)
          _LocalMediaGrid(
            files: visuals,
            onOpenAttachment: onOpenLocalAttachment,
          ),
      ],
    );
  }
}

class _ReplyQuoteCard extends StatelessWidget {
  const _ReplyQuoteCard({
    required this.reply,
    required this.isMe,
  });

  final ChatReplyReference reply;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final titleColor = isMe ? scheme.onPrimary : scheme.primary;
    final bodyColor = isMe
        ? scheme.onPrimary.withValues(alpha: 0.84)
        : scheme.onSurfaceVariant;
    final accentColor = isMe ? scheme.onPrimary : scheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: isMe
            ? Colors.white.withValues(alpha: 0.16)
            : scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 32,
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  reply.senderName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: titleColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  reply.text.trim().isNotEmpty
                      ? reply.text
                      : 'Сообщение без текста',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: bodyColor,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
