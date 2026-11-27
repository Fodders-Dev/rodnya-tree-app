// ignore_for_file: unused_field
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../utils/user_facing_error.dart';
import '../utils/date_parser.dart';
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
import '../controllers/chat_attachments_controller.dart';
import '../controllers/chat_recording_controller.dart';
import '../controllers/chat_search_controller.dart';
import '../controllers/chat_selection_controller.dart';
import '../controllers/chat_timeline_controller.dart';
import '../models/call_media_mode.dart';
import '../models/chat_attachment.dart';
import '../models/chat_details.dart';
import '../models/chat_message.dart';
import '../models/chat_message_search_result.dart';
import '../models/chat_send_progress.dart';
import '../models/family_tree.dart';
import '../providers/tree_provider.dart';
import '../backend/interfaces/notification_service_interface.dart';
import '../services/active_chat_tracker.dart';
import '../services/app_status_service.dart';
import '../services/call_coordinator_service.dart';
import '../services/chat_auto_delete_store.dart';
import '../services/chat_clipboard_image_paste.dart';
import '../services/chat_details_cache.dart';
import '../services/chat_draft_suppression.dart';
import '../services/chat_draft_store.dart';
import '../services/chat_notification_settings_store.dart';
import '../services/chat_pin_store.dart';
import '../services/chat_send_queue.dart';
import '../services/custom_api_auth_service.dart';
import '../services/custom_api_realtime_service.dart';
import '../theme/app_theme.dart';
import '../widgets/attachment_picker_sheet.dart';
import '../widgets/kruzhok_recorder_screen.dart';
import '../widgets/swipe_to_reply.dart';
import '../utils/chat_attachment_download.dart';
import '../utils/photo_url.dart';
import '../utils/perf_log.dart';
import '../utils/snackbar.dart';
import '../utils/url_utils.dart';
import '../widgets/glass_panel.dart';
import '../widgets/offline_indicator.dart';
import '../widgets/safe_delete_confirmation_dialog.dart';

part 'chat/chat_models.dart';
part 'chat/chat_inline_playback.dart';
part 'chat/chat_video_note_widgets.dart';
part 'chat/chat_media_grid.dart';
part 'chat/chat_attachment_viewer.dart';
part 'chat/chat_message_text.dart';
part 'chat/chat_message_bubble.dart';
part 'chat/chat_indicators.dart';
part 'chat/chat_context_menu.dart';
part 'chat/chat_info_sheet.dart';
part 'chat/chat_group_call_picker.dart';
part 'chat/chat_presence_format.dart';
part 'chat/chat_app_bar_section.dart';
part 'chat/chat_composer_section.dart';
part 'chat/chat_message_list_section.dart';
part 'chat/chat_actions_and_safety_section.dart';
part 'chat/chat_persistence_and_realtime_section.dart';

typedef OpenDirectChatCallback = void Function({
  required String chatId,
  required String title,
  String? photoUrl,
  String? otherUserId,
});

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
    this.autoDeleteStore,
    this.initialChatDetails,
    this.recordingController,
    this.embedded = false,
    this.onOpenDirectChat,
    this.clipboardImages,
    this.autoStartCall,
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
  // GP2: when opened from a chats-list «Позвонить» action, auto-trigger the
  // group-call flow once chat details (candidates) have loaded.
  final CallMediaMode? autoStartCall;
  final Future<List<XFile>> Function()? pickImages;
  final Future<XFile?> Function()? pickVideo;
  final ChatDraftStore? draftStore;
  final ChatPinStore? pinStore;
  final ChatNotificationSettingsStore? notificationSettingsStore;
  final ChatAutoDeleteStore? autoDeleteStore;
  final ChatDetails? initialChatDetails;

  /// C2/тестируемость: позволяет внедрить контроллер записи (с фейковым
  /// рекордером) — тогда recording-бар и его живую волну можно проверить
  /// виджет-тестом. В проде null → создаётся свой.
  final ChatRecordingController? recordingController;

  /// Desktop master-detail: when true the screen is hosted inside the
  /// «Чаты» tab's right pane (not a pushed route), so it must NOT render a
  /// «назад» leading that would pop the whole shell route. The chat list
  /// stays visible to the left; switching chats just swaps this pane.
  final bool embedded;

  /// Desktop master-detail hook: lets the parent chat list swap the right pane
  /// to a direct chat opened from a group message/member row.
  final OpenDirectChatCallback? onOpenDirectChat;

  /// Test hook for web clipboard-image paste. Production uses the browser
  /// paste listener from [ChatClipboardImagePasteService].
  final Stream<ChatClipboardImage>? clipboardImages;

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

  // GP2: guards the one-shot auto-start-call trigger (widget.autoStartCall)
  // against _loadChatDetails running more than once (cache + API).
  bool _autoStartCallConsumed = false;

  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final CallCoordinatorService _callCoordinator =
      GetIt.I<CallCoordinatorService>();
  final ChatServiceInterface _chatService = GetIt.I<ChatServiceInterface>();
  // Optional details cache — when registered we hydrate the chat
  // header (title / participants / branch roots) from disk so the
  // user sees the chat fully populated even if the API is offline.
  ChatDetailsCache? get _chatDetailsCache =>
      GetIt.I.isRegistered<ChatDetailsCache>()
          ? GetIt.I<ChatDetailsCache>()
          : null;
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
  late String _resolvedTitle;
  final ChatAttachmentsController _attachmentsController =
      ChatAttachmentsController(maxAttachments: _maxAttachments);
  ChatClipboardImagePasteService? _clipboardImagePasteService;
  StreamSubscription<ChatClipboardImage>? _clipboardImagePasteSubscription;
  late final ChatSendQueue _sendQueue;
  bool _ownsSendQueue = false;
  // S1: открытие чата до первого кадра с сообщениями.
  PerfTrace? _chatOpenTrace;
  // S5: heartbeat активного чата (сервер протухает запись через 60с).
  Timer? _activeChatHeartbeat;
  // S5: видимый статус соединения — «Подключение…» в шапке при разрыве.
  bool _isRealtimeReconnecting = false;
  final Set<String> _reportedSendFailureIds = <String>{};
  final Set<String> _handledVoiceSendIds = <String>{};
  // SPEED-5: отпечаток видимого оптимистичного списка — ребилд только на
  // реальное изменение (см. _handleSendQueueChanged).
  String? _lastSendQueueFingerprint;
  Timer? _draftSaveTimer;
  bool _isApplyingDraft = false;
  int _draftPersistenceVersion = 0;
  String? _lastPersistedDraftKey;
  final ScrollController _messagesScrollController = ScrollController();
  final GlobalKey _unreadDividerKey = GlobalKey();
  bool _showJumpToLatestButton = false;
  bool _didInitialUnreadJump = false;
  String? _unreadAnchorMessageId;
  // Sticky unread (UX-аудит P1): сколько НОВЫХ входящих пришло снизу,
  // пока юзер отскроллен вверх — бейдж на jump-FAB (Telegram-паттерн).
  // Серверный unreadCount мёртв для этого: _markChatAsRead гасит его
  // через секунды после прихода независимо от скролла — считаем
  // клиентской сессией. Леджер прихода отдельный от
  // _seenRemoteMessageIds (тот заполняется только для ПОСТРОЕННЫХ
  // бабблов и пропускает всё за cacheExtent).
  int _newBelowViewportCount = 0;
  final Set<String> _arrivalLedgerIds = <String>{};
  // База «самое свежее сообщение, что мы видели» — чтобы старые
  // сообщения, доехавшие смёрдженной страницей на реконнекте, не
  // считались «новыми снизу» (ревью батча).
  DateTime? _newestArrivalSeen;
  // Плавающий чип «N новых»: разделитель непрочитанного выше вьюпорта
  // (включая случай за cacheExtent, где initial-jump молча не сработал).
  bool _unreadDividerAboveViewport = false;
  // Верхний видимый баббл — стэшится в _updateFloatingDayHeader, чтобы
  // чип непрочитанного не обходил ключи повторно (ревью батча).
  ChatMessage? _topmostVisibleRemoteMessage;
  ChatReplyReference? _selectedReply;
  _ForwardDraft? _selectedForward;
  _ForwardBatchDraft? _selectedForwardBatch;
  _EditDraft? _selectedEdit;
  final ChatSearchController _searchController = ChatSearchController();
  final ChatSelectionController _selectionController =
      ChatSelectionController();
  bool _browserContextMenuWasEnabled = false;
  bool _isDirectChatBlocked = false;
  String? _directChatBlockedLabel;
  late final ChatRecordingController _recordingController;
  late final bool _ownsRecordingController;
  ChatTimelineController? _timelineController;
  ChatDraftStore get _draftStore =>
      widget.draftStore ??
      (GetIt.I.isRegistered<ChatDraftStore>()
          ? GetIt.I<ChatDraftStore>()
          : const SharedPreferencesChatDraftStore());
  ChatNotificationSettingsStore get _notificationSettingsStore =>
      widget.notificationSettingsStore ??
      const SharedPreferencesChatNotificationSettingsStore();
  ChatPinStore get _pinStore =>
      widget.pinStore ??
      (GetIt.I.isRegistered<ChatPinStore>()
          ? GetIt.I<ChatPinStore>()
          : const SharedPreferencesChatPinStore());
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
  List<ChatMessage> _latestRemoteMessages = const <ChatMessage>[];
  final Map<String, GlobalKey> _remoteMessageKeys = <String, GlobalKey>{};

  /// Day of the topmost-visible message — drives the floating
  /// "Сегодня / Вчера / 12 марта" pill at the top of the messages
  /// area while the user is scrolling history.
  DateTime? _floatingDayHeader;
  bool _floatingHeaderVisible = false;
  Timer? _floatingHeaderHideTimer;

  /// Message ids that have already been rendered at least once. Used
  /// to gate the bubble enter animation: ids in this set render in
  /// their rest state, ids NOT in the set get a one-shot
  /// slide-up + fade-in TweenAnimationBuilder. We populate the set
  /// with the entire first history batch (so opening a chat doesn't
  /// animate every message) and only skip-add on subsequent
  /// snapshots — meaning only newly arrived messages animate.
  final Set<String> _seenRemoteMessageIds = <String>{};
  bool _remoteHistoryHydrated = false;
  Timer? _pinnedMessageHighlightTimer;
  String? _highlightedPinnedMessageId;
  Timer? _serverSearchDebounce;
  List<ChatMessageSearchResult> _serverSearchResults =
      const <ChatMessageSearchResult>[];
  String _serverSearchQuery = '';
  bool _isServerSearchLoading = false;
  bool _serverSearchAvailable = true;
  Object? _serverSearchError;
  StreamSubscription<CustomApiRealtimeEvent>? _realtimeIndicatorsSubscription;
  Timer? _typingHeartbeatTimer;
  Timer? _typingDecayTimer;
  bool _typingHeartbeatActive = false;
  final Map<String, DateTime> _typingUsers = <String, DateTime>{};
  final Set<String> _onlineUserIds = <String>{};

  /// Last-seen timestamps per peer userId. Populated from chat-details
  /// participants on chat open and updated by realtime `presence.updated`
  /// events when a peer goes offline. Drives the "был(а) N минут назад"
  /// subtitle on direct chats.
  final Map<String, DateTime> _peerLastSeenAt = <String, DateTime>{};
  static const double _recordingLockThreshold = 52;
  static const double _recordingCancelThreshold = 72;
  // Voice-cancel зона (UX-аудит P1): визуальный отклик слайда-влево.
  // ValueNotifier вместо setState — плавные per-move перерисовки только
  // внутри recording-бара; контроллер записи остаётся platform-pure.
  final ValueNotifier<double> _recordingDragDx = ValueNotifier<double>(0);

  // C3a/V1 (ревью): персистентный pointer-трекинг press-hold. Цикл записи
  // (move/lock/cancel/release) ведём raw-Listener'ом на СТАБИЛЬНОМ слое над
  // AnimatedSwitcher'ом композер↔бар. Иначе при ребилде (старт записи меняет
  // поддерево) LongPress-recognizer композера размонтируется, а recognizer
  // in-bar мика не видел pointer-down → onLongPressEnd не приходил на lift,
  // и запись не завершалась. Listener остаётся в hit-тесте указателя с
  // момента down, поэтому надёжно получает move/up несмотря на ребилд.
  int? _recordingPointerId;
  Offset? _recordingPointerOrigin;
  // FX1/C3a (ревью): id пальца, опущенного именно НА микрофон (локальный
  // Listener вокруг мик-кнопки). Запись привязываем к нему, а НЕ к любому
  // pointer-down в зоне композера — иначе второе касание TextField во время
  // long-press перебивало бы привязку и реальное отпускание не завершало
  // запись (stuck-recording).
  int? _micPointerId;
  // FX1/C3a FR3: палец отпущен, пока шёл старт (диалог разрешения микрофона)
  // — не оставляем осиротевшую запись без пальца и без Send.
  bool _recordingPointerReleased = false;

  // C3d/V2 (ревью FR8): запись кружка инлайн-оверлеем поверх чата (чат
  // виден), вместо отдельного fullscreen-роута. true → оверлей-рекордер
  // в Stack тела чата.
  bool _showInlineKruzhok = false;

  /// Telegram-style toggle for the composer's primary action button.
  /// Tap flips between voice (false) and kruzhok / video-note (true);
  /// long-press starts the corresponding recording flow. Was hard-
  /// coded to «tap = kruzhok» before, which forced users to long-
  /// press for a voice message every time. The user reported:
  /// «нажимаю на голосувуху - открывается запись кружочка... по тапу
  /// они должны меняться (как в тг), а вот при удержании
  /// записываться».
  bool _voiceModeIsKruzhok = false;

  @override
  void initState() {
    super.initState();
    _recordingController =
        widget.recordingController ?? ChatRecordingController();
    _ownsRecordingController = widget.recordingController == null;
    _chatOpenTrace = PerfTrace('chat.open-to-messages');
    _ownsSendQueue = !GetIt.I.isRegistered<ChatSendQueue>();
    _sendQueue = _ownsSendQueue
        ? ChatSendQueue.memory(chatService: _chatService)
        : GetIt.I<ChatSendQueue>();
    _sendQueue.addListener(_handleSendQueueChanged);
    _attachmentsController.addListener(_handleAttachmentsChanged);
    _chatDetails = widget.initialChatDetails;
    _resolvedTitle =
        widget.initialChatDetails?.displayTitleFor(_currentUserId) ??
            widget.title;
    _messageController.addListener(_handleDraftChanged);
    _searchController.addListener(_handleSearchChanged);
    // Global key handler — more reliable than Focus.onKeyEvent on Flutter web.
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    _messagesScrollController.addListener(_handleMessagesScroll);
    _recordingController.addListener(_handleRecordingControllerChanged);
    _configureBrowserContextMenu();
    _bindClipboardImagePaste();
    // Defer the chat bootstrap until AFTER the first frame paints.
    // The bootstrap awaits getOrCreateChat / SharedPreferences /
    // notification-settings store reads, all of which compete with
    // the slide-transition that's animating this screen in. On
    // Samsung mid-range that competition shows up as a 150–300 ms
    // freeze where the chat header pops in late. addPostFrameCallback
    // gives the route transition a clean first frame and starts the
    // actual data-loading work right after — net latency is the same
    // but perceived smoothness is much better.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _bootstrapChat();
    });
  }

  @override
  void dispose() {
    // Снимаем активность чата ДО прочих очисток. Pass `_chatId` —
    // если пользователь свайпнулся в другой чат, и его initState
    // уже выставил новый id, наш expected mismatch'нется и мы
    // не затрём его флажок.
    final activeChatIdToClear = _chatId;
    if (activeChatIdToClear != null && activeChatIdToClear.isNotEmpty) {
      ActiveChatTracker.instance.clearActive(activeChatIdToClear);
      unawaited(
        _realtimeService?.clearActiveChat(chatId: activeChatIdToClear),
      );
    }
    _draftSaveTimer?.cancel();
    _activeChatHeartbeat?.cancel();
    _pinnedMessageHighlightTimer?.cancel();
    _serverSearchDebounce?.cancel();
    _floatingHeaderHideTimer?.cancel();
    _messageController.removeListener(_handleDraftChanged);
    _searchController.removeListener(_handleSearchChanged);
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _messagesScrollController.removeListener(_handleMessagesScroll);
    _messagesScrollController.dispose();
    _messageController.dispose();
    _searchController.dispose();
    // Обнуляем pointer-привязку ДО dispose нотифаера: палец мог остаться
    // опущенным на записи (юзер свернул чат вторым пальцем), а
    // persistent-Listener продолжает слать move/up на down-time hit-path
    // и после unmount — ранний выход в _handleRecordingPointer* по
    // null id не даст записать в disposed ValueNotifier (ревью батча).
    _recordingPointerId = null;
    _recordingPointerOrigin = null;
    _recordingDragDx.dispose();
    _messageFocusNode.dispose();
    _typingHeartbeatTimer?.cancel();
    _typingDecayTimer?.cancel();
    unawaited(_setTypingActive(false, force: true));
    final realtimeSubscription = _realtimeIndicatorsSubscription;
    _realtimeIndicatorsSubscription = null;
    if (realtimeSubscription != null) {
      unawaited(realtimeSubscription.cancel());
    }
    _restoreBrowserContextMenu();
    unawaited(_clipboardImagePasteSubscription?.cancel());
    _clipboardImagePasteSubscription = null;
    _clipboardImagePasteService?.dispose();
    _clipboardImagePasteService = null;
    _sendQueue.removeListener(_handleSendQueueChanged);
    _attachmentsController.removeListener(_handleAttachmentsChanged);
    _attachmentsController.dispose();
    _recordingController.removeListener(_handleRecordingControllerChanged);
    if (_ownsRecordingController) {
      _recordingController.dispose();
    }
    if (_ownsSendQueue) {
      _sendQueue.dispose();
    }
    _selectionController.dispose();
    _timelineController?.dispose();
    super.dispose();
  }

  ChatRecordingState? _lastRecordingState;
  bool _unreadChipRecomputeScheduled = false;

  void _updateChatState(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _selectionController,
      builder: (context, _) => Scaffold(
        appBar: _buildChatAppBar(context),
        body: Stack(
          children: [
            _buildChatBody(context),
            // C3d/V2 (FR8): инлайн-рекордер кружка поверх чата — чат виден за
            // затемнением, без отдельного экрана и его лага.
            if (_showInlineKruzhok)
              Positioned.fill(
                child: KruzhokRecorderScreen(
                  embedded: true,
                  onCaptured: _onInlineKruzhokCaptured,
                  onCancelled: _onInlineKruzhokCancel,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
