// ignore_for_file: unused_field, unused_element
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/chat_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../models/chat_preview.dart';
import '../models/family_tree.dart';
import '../models/family_person.dart';
import '../models/family_relation.dart';
import '../providers/tree_provider.dart';
import '../services/app_status_service.dart';
import '../services/chat_archive_store.dart';
import '../services/chat_draft_store.dart';
import '../services/chat_notification_settings_store.dart';
import '../services/custom_api_chat_service.dart';
import '../services/custom_api_realtime_service.dart';
import '../theme/app_theme.dart';
import '../utils/photo_url.dart';
import '../utils/user_facing_error.dart';
import '../widgets/glass_panel.dart';

part 'chats_list_screen_create_sheet.dart';
part 'chats_list_screen_sections.dart';

String _countLabel(
  int count, {
  required String one,
  required String few,
  required String many,
}) {
  final mod10 = count % 10;
  final mod100 = count % 100;
  if (mod10 == 1 && mod100 != 11) {
    return '$count $one';
  }
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return '$count $few';
  }
  return '$count $many';
}

class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({
    super.key,
    this.draftStore,
    this.archiveStore,
    this.notificationSettingsStore,
  });

  final ChatDraftStore? draftStore;
  final ChatArchiveStore? archiveStore;
  final ChatNotificationSettingsStore? notificationSettingsStore;

  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen>
    with WidgetsBindingObserver {
  final ChatServiceInterface _chatService = GetIt.I<ChatServiceInterface>();
  final AuthServiceInterface _authService = GetIt.I<AuthServiceInterface>();
  final AppStatusService _appStatusService = GetIt.I<AppStatusService>();
  final CustomApiRealtimeService? _realtimeService =
      GetIt.I.isRegistered<CustomApiRealtimeService>()
          ? GetIt.I<CustomApiRealtimeService>()
          : null;
  ChatDraftStore get _draftStore =>
      widget.draftStore ??
      (GetIt.I.isRegistered<ChatDraftStore>()
          ? GetIt.I<ChatDraftStore>()
          : const SharedPreferencesChatDraftStore());
  ChatArchiveStore get _archiveStore =>
      widget.archiveStore ?? const SharedPreferencesChatArchiveStore();
  ChatNotificationSettingsStore get _notificationSettingsStore =>
      widget.notificationSettingsStore ??
      const SharedPreferencesChatNotificationSettingsStore();

  StreamSubscription<List<ChatPreview>>? _chatsSubscription;
  StreamSubscription<CustomApiRealtimeEvent>? _draftsRealtimeSubscription;
  List<ChatPreview> _chatPreviews = [];
  List<_GroupChatParticipant> _relatives = [];
  Map<String, ChatArchiveSnapshot> _archivedChats =
      <String, ChatArchiveSnapshot>{};
  Map<String, ChatDraftSnapshot> _drafts = <String, ChatDraftSnapshot>{};
  Map<String, ChatNotificationSettingsSnapshot> _notificationSettings =
      <String, ChatNotificationSettingsSnapshot>{};
  final Set<String> _onlineUserIds = <String>{};
  bool _isLoading = true;
  bool _hasLoadedInitialBatch = false;
  String? _errorMessage;
  String? _openingPrivateChatUserId;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  _ChatsVisibilityFilter _activeFilter = _ChatsVisibilityFilter.all;
  TreeProvider? _treeProvider;
  String? _observedTreeId;
  bool _isLoadingRelatives = false;
  String? _relativesLoadTreeId;
  int _relativesLoadToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadChats();
    _bindDraftRealtimeUpdates();
    _loadRelatives();
    unawaited(_loadAuxiliaryChatState());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _treeProvider = context.read<TreeProvider>();
      _observedTreeId = _treeProvider?.selectedTreeId;
      _treeProvider?.addListener(_handleTreeSelectionChanged);
    });
  }

  @override
  void dispose() {
    _chatsSubscription?.cancel();
    _draftsRealtimeSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _treeProvider?.removeListener(_handleTreeSelectionChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _bindDraftRealtimeUpdates() {
    final realtimeService = _realtimeService;
    if (realtimeService == null) {
      return;
    }
    unawaited(realtimeService.connect());
    _draftsRealtimeSubscription = realtimeService.events.listen((event) {
      _handlePresenceRealtimeEvent(event);
      _handleDraftRealtimeEvent(event);
    });
  }

  void _handlePresenceRealtimeEvent(CustomApiRealtimeEvent event) {
    if (!mounted || !event.isPresenceEvent) return;
    final ids = event.onlineUserIds;
    final userId = event.userId;
    final isOnline = event.isOnline;
    bool changed = false;
    if (ids.isNotEmpty) {
      final next = ids.toSet();
      if (next.length != _onlineUserIds.length ||
          !next.every(_onlineUserIds.contains)) {
        _onlineUserIds
          ..clear()
          ..addAll(next);
        changed = true;
      }
    } else if (userId != null && userId.isNotEmpty && isOnline != null) {
      changed =
          isOnline ? _onlineUserIds.add(userId) : _onlineUserIds.remove(userId);
    } else if (event.type == 'connection.disconnected') {
      if (_onlineUserIds.isNotEmpty) {
        _onlineUserIds.clear();
        changed = true;
      }
    }
    if (changed) {
      setState(() {});
    }
  }

  void _handleDraftRealtimeEvent(CustomApiRealtimeEvent event) {
    if (!mounted ||
        event.type != 'chat.draft.updated' ||
        event.userId != _authService.currentUserId) {
      return;
    }
    final chatId = event.chatId;
    if (chatId == null || chatId.isEmpty) {
      return;
    }

    final key = SharedPreferencesChatDraftStore.chatKey(chatId);
    final rawDraft = event.draft;
    final nextDraft =
        rawDraft == null ? null : ChatDraftSnapshot.fromJson(rawDraft);
    final draftStore = _draftStore;
    setState(() {
      if (nextDraft == null || nextDraft.text.trim().isEmpty) {
        _drafts.remove(key);
      } else {
        _drafts[key] = nextDraft;
      }
    });

    if (nextDraft == null || nextDraft.text.trim().isEmpty) {
      unawaited(
        draftStore is HybridChatDraftStore
            ? draftStore.clearLocalDraft(key)
            : draftStore.clearDraft(key),
      );
    } else {
      unawaited(
        draftStore is HybridChatDraftStore
            ? draftStore.saveLocalDraft(key, nextDraft.text)
            : draftStore.saveDraft(key, nextDraft.text),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }
    final chatService = _chatService;
    if (chatService is CustomApiChatService) {
      unawaited(chatService.refreshChatOverview());
    }
    unawaited(_loadAuxiliaryChatState());
    _loadRelatives();
  }

  void _handleTreeSelectionChanged() {
    if (!mounted) {
      return;
    }
    final nextTreeId = _treeProvider?.selectedTreeId;
    if (_observedTreeId == nextTreeId) {
      return;
    }
    _observedTreeId = nextTreeId;
    _loadRelatives();
    unawaited(_loadAuxiliaryChatState());
  }

  void _loadChats() {
    final currentUserId = _authService.currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      setState(() {
        _isLoading = false;
        _hasLoadedInitialBatch = true;
        _errorMessage =
            'Сессия закончилась. Войдите снова, чтобы открыть чаты и черновики.';
      });
      return;
    }

    _chatsSubscription?.cancel();
    _chatsSubscription = _chatService.getUserChatsStream(currentUserId).listen(
      (chatPreviews) {
        if (!mounted) {
          return;
        }
        setState(() {
          _chatPreviews = chatPreviews;
          _isLoading = false;
          _hasLoadedInitialBatch = true;
          _errorMessage = null;
        });
      },
      onError: (error, stackTrace) {
        _appStatusService.reportError(
          error,
          fallbackMessage: 'Не удалось загрузить список чатов.',
        );
        if (!mounted) {
          return;
        }
        final hasCachedPreviews = _chatPreviews.isNotEmpty;
        setState(() {
          _isLoading = false;
          _hasLoadedInitialBatch = true;
          _errorMessage = hasCachedPreviews
              ? null
              : (_appStatusService.isOffline
                  ? 'Нет соединения. Чаты появятся, как только интернет вернётся.'
                  : 'Не удалось загрузить чаты. Попробуйте ещё раз.');
        });
      },
    );
  }

  Future<void> _loadAuxiliaryChatState() async {
    await Future.wait([
      _loadArchivedChats(),
      _loadDrafts(),
      _loadNotificationSettings(),
    ]);
  }

  Future<void> _loadDrafts() async {
    final drafts = await _draftStore.getAllDrafts();
    if (!mounted) {
      return;
    }
    setState(() {
      _drafts = drafts;
    });
  }

  Future<void> _loadArchivedChats() async {
    final archivedChats = await _archiveStore.getAllArchivedChats();
    if (!mounted) {
      return;
    }
    setState(() {
      _archivedChats = archivedChats;
    });
  }

  Future<void> _loadNotificationSettings() async {
    final settings = await _notificationSettingsStore.getAllSettings();
    if (!mounted) {
      return;
    }
    setState(() {
      _notificationSettings = settings;
    });
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate =
        DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (messageDate == today) {
      return DateFormat.Hm('ru').format(timestamp);
    }

    final yesterday = today.subtract(const Duration(days: 1));
    if (messageDate == yesterday) {
      return 'Вчера';
    }

    if (now.difference(timestamp).inDays < 7) {
      const weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
      return weekdays[timestamp.weekday - 1];
    }

    return DateFormat('d MMM', 'ru').format(timestamp);
  }

  String _archiveKey(ChatPreview chat) =>
      SharedPreferencesChatArchiveStore.chatKey(chat.chatId);

  bool _isArchived(ChatPreview chat) => _archivedChats.containsKey(
        _archiveKey(chat),
      );

  int _archivedPreviewCount() {
    return _chatPreviews.where(_isArchived).length;
  }

  int _archivedUnreadCount() {
    return _chatPreviews
        .where(_isArchived)
        .fold<int>(0, (sum, chat) => sum + chat.unreadCount);
  }

  Future<void> _setChatArchived(ChatPreview chat, bool archived) async {
    final key = _archiveKey(chat);
    if (archived) {
      await _archiveStore.saveArchivedChat(
        key,
        ChatArchiveSnapshot(archivedAt: DateTime.now()),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _archivedChats[key] = ChatArchiveSnapshot(archivedAt: DateTime.now());
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Чат "${chat.displayName}" отправлен в архив'),
          action: SnackBarAction(
            label: 'Архив',
            onPressed: () {
              if (!mounted) {
                return;
              }
              setState(() {
                _activeFilter = _ChatsVisibilityFilter.archived;
              });
            },
          ),
        ),
      );
      return;
    }

    await _archiveStore.clearArchivedChat(key);
    if (!mounted) {
      return;
    }
    setState(() {
      _archivedChats.remove(key);
      if (_activeFilter == _ChatsVisibilityFilter.archived &&
          _archivedPreviewCount() == 0) {
        _activeFilter = _ChatsVisibilityFilter.all;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Чат "${chat.displayName}" возвращен в список')),
    );
  }

  Future<void> _openChatActions(ChatPreview chat) async {
    final isArchived = _isArchived(chat);
    final action = await showModalBottomSheet<_ChatListAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
              ),
              title: Text(
                isArchived ? 'Вернуть в основной список' : 'Архивировать чат',
              ),
              subtitle: Text(
                isArchived
                    ? 'Чат снова появится в обычной ленте.'
                    : 'Скрыть чат из основного списка без удаления истории.',
              ),
              onTap: () => Navigator.of(context).pop(
                isArchived
                    ? _ChatListAction.unarchive
                    : _ChatListAction.archive,
              ),
            ),
          ],
        ),
      ),
    );

    if (action == null || !mounted) {
      return;
    }

    switch (action) {
      case _ChatListAction.archive:
        await _setChatArchived(chat, true);
        break;
      case _ChatListAction.unarchive:
        await _setChatArchived(chat, false);
        break;
    }
  }

  void _loadRelatives() async {
    String? activeTreeId;
    try {
      final treeId =
          Provider.of<TreeProvider>(context, listen: false).selectedTreeId;
      activeTreeId = treeId;
      if (treeId == null || treeId.isEmpty) {
        _isLoadingRelatives = false;
        _relativesLoadTreeId = null;
        if (!mounted) {
          return;
        }
        setState(() {
          _relatives = [];
        });
        return;
      }

      if (_isLoadingRelatives && _relativesLoadTreeId == treeId) {
        return;
      }
      final loadToken = ++_relativesLoadToken;
      _isLoadingRelatives = true;
      _relativesLoadTreeId = treeId;

      final service = GetIt.I<FamilyTreeServiceInterface>();
      final relatives = await service.getRelatives(treeId);
      final currentUserId = _authService.currentUserId;

      if (!mounted || loadToken != _relativesLoadToken) {
        return;
      }
      setState(() {
        _relatives = relatives
            .where((p) => p.userId != null && p.userId != currentUserId)
            .map((p) => _GroupChatParticipant(
                  userId: p.userId!,
                  name: p.name.trim().isNotEmpty ? p.name : 'Родственник',
                  photoUrl: p.photoUrl,
                  relationLabel: (p.relation ?? '').trim().isNotEmpty
                      ? p.relation!
                      : 'Родственник',
                ))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
      });
    } catch (e) {
      debugPrint('Error loading relatives for search: $e');
    } finally {
      if (mounted && _relativesLoadTreeId == activeTreeId) {
        _isLoadingRelatives = false;
        _relativesLoadTreeId = null;
      }
    }
  }

  Future<void> _openChatComposer() async {
    final currentUserId = _authService.currentUserId;
    final messenger = ScaffoldMessenger.of(context);
    final treeProvider = context.read<TreeProvider>();
    final selectedTreeId = treeProvider.selectedTreeId;

    if (currentUserId == null || currentUserId.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Сначала войдите в аккаунт.')),
      );
      return;
    }

    if (selectedTreeId == null || selectedTreeId.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            treeProvider.selectedTreeKind == TreeKind.friends
                ? 'Сначала выберите активный круг друзей.'
                : 'Сначала выберите семейное дерево.',
          ),
          action: SnackBarAction(
            label: 'Открыть',
            onPressed: () => context.go('/tree?selector=1'),
          ),
        ),
      );
      return;
    }

    if (!GetIt.I.isRegistered<FamilyTreeServiceInterface>()) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Список родных временно недоступен.')),
      );
      return;
    }

    final draft = await showModalBottomSheet<_CreateChatDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CreateChatSheet(
        treeId: selectedTreeId,
        currentUserId: currentUserId,
      ),
    );

    if (!mounted || draft == null) {
      return;
    }

    try {
      late final String? chatId;
      late final String title;
      late final String chatType;
      if (draft.mode == _ChatComposerMode.direct) {
        title = draft.directUserName ?? 'Личный чат';
        chatType = 'direct';
        chatId = await _chatService.getOrCreateChat(draft.directUserId ?? '');
      } else if (draft.mode == _ChatComposerMode.branch ||
          draft.mode == _ChatComposerMode.branches) {
        title = _resolveBranchChatTitle(draft);
        chatType = 'branch';
        chatId = await _chatService.createBranchChat(
          treeId: selectedTreeId,
          branchRootPersonIds: draft.branchRootPersonIds,
          title: title,
        );
      } else {
        title = (draft.title?.trim().isNotEmpty ?? false)
            ? draft.title!.trim()
            : 'Групповой чат';
        chatType = 'group';
        chatId = await _chatService.createGroupChat(
          participantIds: draft.participantIds,
          title: draft.title,
          treeId: selectedTreeId,
        );
      }

      if (chatId == null || chatId.isEmpty) {
        throw StateError('Не удалось создать чат');
      }

      final encodedTitle = Uri.encodeComponent(title);
      if (!mounted) {
        return;
      }
      context.push('/chats/view/$chatId?type=$chatType&title=$encodedTitle');
    } catch (error) {
      _appStatusService.reportError(
        error,
        fallbackMessage: 'Не удалось создать чат.',
      );
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            draft.mode == _ChatComposerMode.branch ||
                    draft.mode == _ChatComposerMode.branches
                ? 'Не удалось создать чат ветки.'
                : draft.mode == _ChatComposerMode.direct
                    ? describeUserFacingError(
                        authService: _authService,
                        error: error,
                        fallbackMessage: _appStatusService.isOffline
                            ? 'Нет соединения. Личный чат откроется, когда интернет вернётся.'
                            : 'Не удалось открыть личный чат.',
                      )
                    : 'Не удалось создать групповой чат.',
          ),
        ),
      );
    }
  }

  String _resolveBranchChatTitle(_CreateChatDraft draft) {
    final explicitTitle = draft.title?.trim();
    if (explicitTitle != null && explicitTitle.isNotEmpty) {
      return explicitTitle;
    }

    if (draft.branchRootNames.length == 1) {
      return 'Ветка ${draft.branchRootNames.first}';
    }

    if (draft.branchRootNames.isEmpty) {
      return 'Чат веток';
    }

    final previewNames = draft.branchRootNames.take(2).join(', ');
    final suffix = draft.branchRootNames.length > 2 ? ' и ещё' : '';
    return 'Ветки: $previewNames$suffix';
  }

  // Always render the mobile-style chat list flow per Claude reference,
  // even on desktop — the side "Связь" panel is dropped intentionally.
  bool _isWideLayout(BuildContext context) => false;

  void _setSearchQuery(String value) {
    setState(() {
      _searchQuery = value;
    });
  }

  void _clearSearchQuery() {
    _searchController.clear();
    _setSearchQuery('');
  }

  void _setActiveFilter(_ChatsVisibilityFilter filter) {
    setState(() {
      _activeFilter = filter;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUserId = _authService.currentUserId ?? '';
    final treeProvider = context.watch<TreeProvider>();
    final isFriendsTree = treeProvider.selectedTreeKind == TreeKind.friends;
    final selectedTreeName = treeProvider.selectedTreeName;
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: _buildChatsTopbar(theme: theme, tokens: tokens),
      ),
      body: _errorMessage != null && _chatPreviews.isEmpty
          ? _buildErrorState()
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 6, 0, 12),
                  child: _buildDesktopShell(
                    theme: theme,
                    currentUserId: currentUserId,
                    isFriendsTree: isFriendsTree,
                    selectedTreeName: selectedTreeName,
                    showInitialLoading: _isLoading &&
                        _chatPreviews.isEmpty &&
                        _errorMessage == null,
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildChatsTopbar({
    required ThemeData theme,
    required RodnyaDesignTokens tokens,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceStrong.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.86 : 0.90,
        ),
        border: Border(
          bottom: BorderSide(color: tokens.surfaceLine, width: 0.7),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(18, 0, 12, 0),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Text(
              'Чаты',
              style: AppTheme.serif(
                color: tokens.ink,
                fontSize: 22,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.22,
              ),
            ),
            const Spacer(),
            _buildTopbarPillButton(
              tokens: tokens,
              tooltip: 'Поиск',
              onTap: _focusSearch,
              child: Icon(
                Icons.search_rounded,
                size: 19,
                color: tokens.ink,
              ),
            ),
            const SizedBox(width: 8),
            _buildTopbarPillButton(
              tokens: tokens,
              tooltip: 'Новый чат',
              onTap: _openChatComposer,
              child: Icon(
                Icons.edit_outlined,
                size: 18,
                color: tokens.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopbarPillButton({
    required RodnyaDesignTokens tokens,
    required Widget child,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: tokens.surfaceStrong,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: tokens.surfaceLine),
          borderRadius: BorderRadius.circular(14),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }

  void _focusSearch() {
    if (_searchFocusNode.canRequestFocus) {
      _searchFocusNode.requestFocus();
    }
  }

  Widget _buildErrorState() {
    final theme = Theme.of(context);
    final isOffline = _appStatusService.isOffline;
    final needsReauth = !isOffline &&
        (_authService.currentUserId == null ||
            _authService.currentUserId!.isEmpty);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: GlassPanel(
            borderRadius: BorderRadius.circular(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isOffline
                      ? Icons.cloud_off_outlined
                      : (needsReauth
                          ? Icons.lock_clock_outlined
                          : Icons.chat_bubble_outline_rounded),
                  size: 40,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 14),
                Text(
                  isOffline
                      ? 'Нет соединения'
                      : (needsReauth
                          ? 'Нужно снова войти'
                          : 'Чаты временно недоступны'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: needsReauth
                      ? () => context.go('/login?from=/chats')
                      : _retryChats,
                  icon: Icon(needsReauth ? Icons.login : Icons.refresh),
                  label: Text(needsReauth ? 'Войти снова' : 'Повторить'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _retryChats() {
    setState(() {
      _isLoading = true;
      _hasLoadedInitialBatch = false;
      _errorMessage = null;
    });
    _appStatusService.requestRetry();
    _loadChats();
    _loadRelatives();
    unawaited(_loadAuxiliaryChatState());
  }

  Widget _buildEmptyState(ThemeData theme) {
    final isFriendsTree =
        context.read<TreeProvider>().selectedTreeKind == TreeKind.friends;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: GlassPanel(
            padding: const EdgeInsets.all(16),
            borderRadius: BorderRadius.circular(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer
                            .withValues(alpha: 0.34),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 24,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Чатов нет',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isFriendsTree
                                ? 'Начните разговор в круге.'
                                : 'Начните семейный разговор.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _openChatComposer,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.add_comment_outlined),
                  label: const Text('Создать чат'),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => context.go('/relatives'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.people_outline, size: 18),
                      label: Text(isFriendsTree ? 'Связи' : 'Родные'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => context.go('/tree'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.account_tree_outlined, size: 18),
                      label: const Text('Дерево'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInitialLoadingState(ThemeData theme) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) => GlassPanel(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        blur: 10,
        borderRadius: BorderRadius.circular(24),
        color: theme.colorScheme.surface.withValues(alpha: 0.72),
        plain: true,
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 12,
                    width: 120 + (index % 3) * 28,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 10,
                    width: 210 + (index % 2) * 36,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatList(ThemeData theme, String currentUserId) {
    final filteredChats = _chatPreviews.where((chat) {
      final isArchived = _isArchived(chat);
      if (_activeFilter == _ChatsVisibilityFilter.archived && !isArchived) {
        return false;
      }
      if (_activeFilter != _ChatsVisibilityFilter.archived && isArchived) {
        return false;
      }
      if (_activeFilter == _ChatsVisibilityFilter.unread &&
          chat.unreadCount <= 0) {
        return false;
      }
      final draft =
          _drafts[SharedPreferencesChatDraftStore.chatKey(chat.chatId)];
      final draftText = draft?.text.toLowerCase() ?? '';
      if (_searchQuery.isEmpty) return true;
      return chat.displayName.toLowerCase().contains(_searchQuery) ||
          chat.lastMessage.toLowerCase().contains(_searchQuery) ||
          draftText.contains(_searchQuery);
    }).toList()
      ..sort((left, right) {
        final leftAt = _effectiveActivityAt(left);
        final rightAt = _effectiveActivityAt(right);
        return rightAt.compareTo(leftAt);
      });

    final filteredRelatives = _searchQuery.isEmpty ||
            _activeFilter == _ChatsVisibilityFilter.archived ||
            _activeFilter == _ChatsVisibilityFilter.unread
        ? const <_GroupChatParticipant>[]
        : _relatives.where((p) {
            final hasChat = _chatPreviews
                .any((c) => !c.isGroup && c.otherUserId == p.userId);
            if (hasChat) return false;
            return p.name.toLowerCase().contains(_searchQuery) ||
                p.relationLabel.toLowerCase().contains(_searchQuery);
          }).toList();

    if (filteredChats.isEmpty &&
        filteredRelatives.isEmpty &&
        _searchQuery.isNotEmpty) {
      final isFriendsTree =
          context.read<TreeProvider>().selectedTreeKind == TreeKind.friends;
      return _buildFilterEmptyState(
        theme,
        icon: Icons.search_off_outlined,
        title: 'Ничего не найдено',
        message: 'Попробуйте другой запрос.',
        actionLabel: 'Сбросить поиск',
        onAction: () {
          _searchController.clear();
          setState(() {
            _searchQuery = '';
          });
        },
        secondaryActionLabel: isFriendsTree ? 'Новый чат круга' : 'Новый чат',
        onSecondaryAction: _openChatComposer,
      );
    }

    if (filteredChats.isEmpty &&
        filteredRelatives.isEmpty &&
        _searchQuery.isEmpty &&
        _activeFilter == _ChatsVisibilityFilter.archived) {
      return _buildFilterEmptyState(
        theme,
        icon: Icons.archive_outlined,
        title: 'Архив пуст',
        message: 'Здесь пока ничего нет.',
        actionLabel: 'Показать все чаты',
        onAction: () {
          setState(() {
            _activeFilter = _ChatsVisibilityFilter.all;
          });
        },
      );
    }

    if (filteredChats.isEmpty &&
        filteredRelatives.isEmpty &&
        _searchQuery.isEmpty &&
        _activeFilter == _ChatsVisibilityFilter.unread) {
      return _buildFilterEmptyState(
        theme,
        icon: Icons.mark_chat_read_outlined,
        title: 'Новых нет',
        message: 'Список разобран.',
        actionLabel: 'Показать все чаты',
        onAction: () {
          setState(() {
            _activeFilter = _ChatsVisibilityFilter.all;
          });
        },
      );
    }

    final showRelatives = filteredRelatives.isNotEmpty;
    final showArchiveSummary =
        _activeFilter != _ChatsVisibilityFilter.archived &&
            _searchQuery.isEmpty &&
            _archivedPreviewCount() > 0;
    final totalCount = filteredChats.length +
        (showArchiveSummary ? 1 : 0) +
        (showRelatives ? filteredRelatives.length + 1 : 0);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 12),
      itemCount: totalCount,
      itemBuilder: (context, index) {
        if (showArchiveSummary && index == 0) {
          return KeyedSubtree(
            key: const ValueKey<String>('chats-archive-summary'),
            child: _buildArchiveSummaryCard(theme),
          );
        }

        final chatIndex = index - (showArchiveSummary ? 1 : 0);
        if (chatIndex < filteredChats.length) {
          return _buildChatTile(theme, filteredChats[chatIndex], currentUserId);
        }

        if (showRelatives) {
          final relativeIndex = chatIndex - filteredChats.length;
          if (relativeIndex == 0) {
            return Padding(
              key: const ValueKey<String>('chats-relative-suggestions-header'),
              padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
              child: Text(
                context.read<TreeProvider>().selectedTreeKind ==
                        TreeKind.friends
                    ? 'Люди круга'
                    : 'Люди',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          }
          final participant = filteredRelatives[relativeIndex - 1];
          return _buildRelativeSuggestionTile(theme, participant);
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildRelativeSuggestionTile(
    ThemeData theme,
    _GroupChatParticipant participant,
  ) {
    final isOpening = _openingPrivateChatUserId == participant.userId;
    final avatarImage = buildAvatarImageProvider(participant.photoUrl);
    return Padding(
      key: ValueKey<String>('relative-suggestion-${participant.userId}'),
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: isOpening ? null : () => _openPrivateChat(participant),
        child: GlassPanel(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          blur: 10,
          borderRadius: BorderRadius.circular(22),
          color: theme.colorScheme.surface.withValues(alpha: 0.74),
          plain: true,
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundImage: avatarImage,
                child: avatarImage == null
                    ? Text(
                        participant.name.isNotEmpty
                            ? participant.name[0].toUpperCase()
                            : '?',
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      participant.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      participant.relationLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isOpening)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.1,
                    color: theme.colorScheme.primary,
                  ),
                )
              else
                const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPrivateChat(_GroupChatParticipant participant) async {
    setState(() => _openingPrivateChatUserId = participant.userId);
    try {
      final chatId = await _chatService.getOrCreateChat(participant.userId);
      if (chatId != null && mounted) {
        context.push(
          '/chats/view/$chatId?type=direct&title=${Uri.encodeComponent(participant.name)}'
          '${participant.photoUrl != null ? '&photo=${Uri.encodeComponent(participant.photoUrl!)}' : ''}'
          '&userId=${participant.userId}',
        );
      }
    } catch (error) {
      _appStatusService.reportError(
        error,
        fallbackMessage: 'Не удалось открыть чат.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              describeUserFacingError(
                authService: _authService,
                error: error,
                fallbackMessage: _appStatusService.isOffline
                    ? 'Нет соединения. Чат откроется, когда интернет вернётся.'
                    : 'Не удалось открыть чат.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _openingPrivateChatUserId = null);
      }
    }
  }

  Widget _buildChatTile(
      ThemeData theme, ChatPreview chat, String currentUserId) {
    final draft = _drafts[SharedPreferencesChatDraftStore.chatKey(chat.chatId)];
    final isArchived = _isArchived(chat);
    final notificationLevel = _notificationSettings[
                SharedPreferencesChatNotificationSettingsStore.chatKey(
                    chat.chatId)]
            ?.level ??
        ChatNotificationLevel.all;
    final hasDraft = draft != null && draft.text.trim().isNotEmpty;
    final hasUnread = chat.unreadCount > 0;
    final isLastFromMe = chat.lastMessageSenderId == currentUserId;
    final messageTime = _effectiveActivityAt(chat);
    final timeLabel = _formatTimestamp(messageTime);
    final previewText = hasDraft ? draft.text.trim() : chat.lastMessage;
    final previewPrefix = hasDraft ? 'Черновик: ' : '';
    final previewColor = hasDraft
        ? theme.colorScheme.error
        : (hasUnread
            ? theme.colorScheme.onSurface
            : theme.colorScheme.onSurfaceVariant);
    final previewWeight = hasDraft
        ? FontWeight.w700
        : (hasUnread ? FontWeight.w600 : FontWeight.w400);
    final avatarImage = buildAvatarImageProvider(chat.displayPhotoUrl);
    final metaPills = <Widget>[
      if (chat.isBranch)
        _buildChatMetaPill(
          theme,
          icon: Icons.account_tree_outlined,
          label: 'Ветка',
        ),
      if (chat.isGroup && !chat.isBranch)
        _buildChatMetaPill(
          theme,
          icon: Icons.group_outlined,
          label: 'Группа',
        ),
      if (isArchived)
        _buildChatMetaPill(
          theme,
          icon: Icons.archive_outlined,
          label: 'Архив',
        ),
      if (notificationLevel == ChatNotificationLevel.muted)
        _buildChatMetaPill(
          theme,
          icon: Icons.notifications_off_outlined,
          label: 'Тихо',
        ),
      if (hasDraft)
        _buildChatMetaPill(
          theme,
          icon: Icons.edit_note_outlined,
          label: 'Черновик',
        ),
    ];

    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    return Material(
      key: ValueKey<String>('chat-tile-${chat.chatId}'),
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          final titleParam = Uri.encodeComponent(chat.displayName);
          final photoParam =
              chat.displayPhotoUrl != null && chat.displayPhotoUrl!.isNotEmpty
                  ? '&photo=${Uri.encodeComponent(chat.displayPhotoUrl!)}'
                  : '';
          final userParam = !chat.isGroup && chat.otherUserId.isNotEmpty
              ? '&userId=${Uri.encodeComponent(chat.otherUserId)}'
              : '';
          context
              .push(
            '/chats/view/${chat.chatId}?type=${Uri.encodeComponent(chat.type)}&title=$titleParam$photoParam$userParam',
          )
              .then((_) {
            unawaited(_loadAuxiliaryChatState());
          });
        },
        onLongPress: () => _openChatActions(chat),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundImage: avatarImage,
                    backgroundColor: tokens.accentSoft,
                    child: avatarImage == null
                        ? (chat.isGroup
                            ? Icon(
                                chat.isBranch
                                    ? Icons.account_tree_outlined
                                    : Icons.group_outlined,
                                size: 22,
                                color: tokens.accent,
                              )
                            : Text(
                                chat.displayName.isNotEmpty
                                    ? chat.displayName[0].toUpperCase()
                                    : '?',
                                style: AppTheme.sans(
                                  color: tokens.accent,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ))
                        : null,
                  ),
                  if (!chat.isGroup &&
                      chat.otherUserId.isNotEmpty &&
                      _onlineUserIds.contains(chat.otherUserId))
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: const Color(0xFF5BC176),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: tokens.bgBase,
                            width: 2.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            chat.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight:
                                  hasUnread ? FontWeight.w800 : FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: hasUnread
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                            fontWeight:
                                hasUnread ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        if (isLastFromMe && !hasDraft) ...[
                          Icon(
                            Icons.done_all_rounded,
                            size: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            '$previewPrefix$previewText',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: previewColor,
                              fontWeight: previewWeight,
                            ),
                          ),
                        ),
                        if (hasUnread)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              chat.unreadCount.toString(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (metaPills.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: metaPills,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  DateTime _effectiveActivityAt(ChatPreview chat) {
    final draft = _drafts[SharedPreferencesChatDraftStore.chatKey(chat.chatId)];
    if (draft == null) {
      return chat.lastMessageTime;
    }
    return draft.updatedAt.isAfter(chat.lastMessageTime)
        ? draft.updatedAt
        : chat.lastMessageTime;
  }
}

enum _ChatComposerMode { direct, group, branch, branches }

enum _ChatsVisibilityFilter { all, unread, archived }

enum _ChatListAction { archive, unarchive }
