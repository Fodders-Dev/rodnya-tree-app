// ignore_for_file: library_private_types_in_public_api
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/tree_provider.dart';
import '../services/event_service.dart';
import '../models/app_event.dart';
import '../models/family_tree.dart';

import '../widgets/event_card.dart';
import 'package:get_it/get_it.dart';
import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/models/tree_invitation.dart';
import '../backend/interfaces/post_service_interface.dart';
import '../backend/interfaces/story_service_interface.dart';
import '../models/post.dart';
import '../models/story.dart';
import '../widgets/post_card.dart';
import '../widgets/post_card_shimmer.dart';
import '../widgets/empty_state_widget.dart';
import '../widgets/story_rail.dart';
import '../widgets/glass_panel.dart';
import '../services/custom_api_notification_service.dart';
import '../utils/e2e_state_bridge.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthServiceInterface _authService = GetIt.I<AuthServiceInterface>();
  final FamilyTreeServiceInterface _familyTreeService =
      GetIt.I<FamilyTreeServiceInterface>();
  final PostServiceInterface _postService = GetIt.I<PostServiceInterface>();
  final StoryServiceInterface _storyService = GetIt.I<StoryServiceInterface>();
  late final EventService _eventService;

  List<AppEvent> _upcomingEvents = [];
  List<Post> _posts = [];
  List<Story> _stories = [];
  String? _selectedEventCategoryFilter;
  bool _isLoadingEvents = true;
  bool _isLoadingPosts = false;
  bool _isLoadingStories = false;
  bool _postsUnavailable = false;
  bool _storiesUnavailable = false;
  String? _currentTreeId;
  TreeProvider? _treeProviderInstance;
  final ScrollController _eventRailController = ScrollController();

  CustomApiNotificationService? get _customNotificationService =>
      GetIt.I.isRegistered<CustomApiNotificationService>()
          ? GetIt.I<CustomApiNotificationService>()
          : null;

  @override
  void initState() {
    super.initState();
    _eventService = EventService();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _treeProviderInstance = Provider.of<TreeProvider>(context, listen: false);
      _treeProviderInstance!.addListener(_handleTreeChange);
      _currentTreeId = _treeProviderInstance!.selectedTreeId;
      if (_currentTreeId != null) {
        _loadStories(_currentTreeId!);
        _loadEvents(_currentTreeId!);
        _loadPosts(_currentTreeId!);
      } else {
        setState(() {
          _isLoadingStories = false;
          _isLoadingEvents = false;
          _isLoadingPosts = false;
          _selectedEventCategoryFilter = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _treeProviderInstance?.removeListener(_handleTreeChange);
    _eventRailController.dispose();
    super.dispose();
  }

  void _handleTreeChange() {
    if (!mounted) return;
    final newTreeId = _treeProviderInstance?.selectedTreeId;
    if (_currentTreeId != newTreeId) {
      _currentTreeId = newTreeId;
      if (_currentTreeId != null) {
        _loadStories(_currentTreeId!);
        _loadEvents(_currentTreeId!);
        _loadPosts(_currentTreeId!);
      } else {
        setState(() {
          _isLoadingStories = false;
          _isLoadingEvents = false;
          _isLoadingPosts = false;
          _stories = [];
          _upcomingEvents = [];
          _posts = [];
          _selectedEventCategoryFilter = null;
        });
      }
    }
  }

  Future<void> _loadStories(String treeId) async {
    if (!mounted) return;
    setState(() {
      _isLoadingStories = true;
      _storiesUnavailable = false;
    });
    try {
      final stories = await _storyService.getStories(treeId: treeId);
      if (mounted) {
        setState(() {
          _stories = stories;
          _isLoadingStories = false;
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки stories: $e');
      if (mounted) {
        setState(() {
          _storiesUnavailable = true;
          _stories = [];
          _isLoadingStories = false;
        });
      }
    }
  }

  Future<void> _loadEvents(String treeId) async {
    if (!mounted) return;
    setState(() {
      _isLoadingEvents = true;
      _upcomingEvents = [];
    });
    try {
      final events = await _eventService.getUpcomingEvents(treeId, limit: 5);
      if (mounted) {
        final categories = _collectEventCategories(events);
        setState(() {
          _upcomingEvents = events;
          if (_selectedEventCategoryFilter != null &&
              !categories.contains(_selectedEventCategoryFilter)) {
            _selectedEventCategoryFilter = null;
          }
          _isLoadingEvents = false;
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки событий: $e');
      if (mounted) {
        setState(() {
          _isLoadingEvents = false;
        });
      }
    }
  }

  List<String> _collectEventCategories(List<AppEvent> events) {
    final categories = <String>[];
    for (final event in events) {
      if (!categories.contains(event.categoryLabel)) {
        categories.add(event.categoryLabel);
      }
    }
    return categories;
  }

  List<String> get _eventCategories => _collectEventCategories(_upcomingEvents);

  List<AppEvent> get _visibleUpcomingEvents {
    final selectedCategory = _selectedEventCategoryFilter;
    if (selectedCategory == null || selectedCategory.isEmpty) {
      return _upcomingEvents;
    }
    return _upcomingEvents
        .where((event) => event.categoryLabel == selectedCategory)
        .toList();
  }

  String _eventCategoryKey(String label) {
    switch (label) {
      case 'Родня':
        return 'rodnya';
      case 'Семья':
        return 'family';
      case 'Память':
        return 'memory';
      case 'Повод':
        return 'custom';
      case 'Россия':
        return 'russia';
      case 'Православие':
        return 'orthodox';
      case 'Календарь':
        return 'calendar';
      default:
        return label
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9а-я]+'), '-')
            .replaceAll(RegExp(r'^-+|-+$'), '');
    }
  }

  void _publishHomeE2EState({
    required String? selectedTreeName,
    required bool hasSelectedTree,
  }) {
    if (!E2EStateBridge.isEnabled) {
      return;
    }

    final visibleEvents = _visibleUpcomingEvents;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      E2EStateBridge.publish(
        screen: 'home',
        state: <String, dynamic>{
          'selectedTreeId': _currentTreeId,
          'selectedTreeName': selectedTreeName,
          'hasSelectedTree': hasSelectedTree,
          'isLoadingEvents': _isLoadingEvents,
          'selectedEventFilter': _selectedEventCategoryFilter,
          'availableEventFilters': <String>['Все', ..._eventCategories],
          'visibleEvents': visibleEvents
              .map(
                (event) => <String, dynamic>{
                  'id': event.id,
                  'title': event.title,
                  'category': event.categoryLabel,
                  'status': event.status,
                  'personId': event.personId,
                },
              )
              .toList(),
        },
      );
    });
  }

  Future<void> _loadPosts(String treeId) async {
    if (!mounted) return;
    setState(() {
      _isLoadingPosts = true;
      _postsUnavailable = false;
    });
    try {
      final posts = await _postService.getPosts(treeId: treeId);
      if (mounted) {
        setState(() {
          _posts = posts;
          _isLoadingPosts = false;
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки постов: $e');
      if (mounted) {
        setState(() {
          _postsUnavailable = true;
          _posts = [];
          _isLoadingPosts = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final treeProvider = Provider.of<TreeProvider>(context);
    final selectedTreeName = treeProvider.selectedTreeName;
    final selectedTreeKind = treeProvider.selectedTreeKind;
    final isFriendsTree = selectedTreeKind == TreeKind.friends;
    final hasSelectedTree = _currentTreeId != null && selectedTreeName != null;
    final isWideLayout = _isWideHomeLayout(context);
    _publishHomeE2EState(
      selectedTreeName: selectedTreeName,
      hasSelectedTree: hasSelectedTree,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(selectedTreeName ?? 'Главная'),
        actions: [
          _buildNotificationsAction(),
          IconButton(
            icon: const Icon(Icons.account_tree_outlined),
            tooltip: 'Выбрать дерево',
            onPressed: () => context.go('/tree?selector=1'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _customNotificationService?.refreshUnreadNotificationsCount();
          if (_currentTreeId != null) {
            await Future.wait([
              _loadStories(_currentTreeId!),
              _loadEvents(_currentTreeId!),
              _loadPosts(_currentTreeId!),
            ]);
          }
        },
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWideLayout ? 1500 : 1400),
            child: StreamBuilder<List<TreeInvitation>>(
              stream: _familyTreeService.getPendingTreeInvitations(),
              builder: (context, snapshot) {
                final pendingInvitations =
                    snapshot.data ?? const <TreeInvitation>[];
                return CustomScrollView(
                  slivers: [
                    if (pendingInvitations.isNotEmpty)
                      SliverToBoxAdapter(
                        child: _buildPendingInvitationsBanner(
                          pendingInvitations,
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: _buildHomeHeader(
                        hasSelectedTree: hasSelectedTree,
                        selectedTreeName: selectedTreeName,
                        isFriendsTree: isFriendsTree,
                      ),
                    ),
                    if (hasSelectedTree) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                          child: _buildHomeContentSections(
                            isWideLayout: isWideLayout,
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 80)),
                    ] else ...[
                      const SliverToBoxAdapter(child: SizedBox(height: 40)),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
      floatingActionButton: _currentTreeId == null
          ? null
          : FloatingActionButton(
              onPressed: () async {
                final result = await context.push('/post/create');
                if (result == true && _currentTreeId != null) {
                  _loadPosts(_currentTreeId!);
                }
              },
              tooltip: 'Разместить публикацию',
              child: const Icon(Icons.add_comment_outlined),
            ),
    );
  }

  Widget _buildNotificationsAction() {
    final notificationService = _customNotificationService;
    if (notificationService == null) {
      return IconButton(
        icon: const Icon(Icons.notifications_outlined),
        tooltip: 'Активность',
        onPressed: () => context.push('/notifications'),
      );
    }

    return StreamBuilder<int>(
      stream: notificationService.unreadNotificationsCountStream,
      initialData: notificationService.unreadNotificationsCount,
      builder: (context, snapshot) {
        final unreadCount = snapshot.data ?? 0;
        final icon = unreadCount > 0
            ? Badge(
                label: Text(unreadCount > 99 ? '99+' : unreadCount.toString()),
                child: const Icon(Icons.notifications_outlined),
              )
            : const Icon(Icons.notifications_outlined);

        return IconButton(
          icon: icon,
          tooltip:
              unreadCount > 0 ? 'Активность, $unreadCount новых' : 'Активность',
          onPressed: () => context.push('/notifications'),
        );
      },
    );
  }

  bool _isWideHomeLayout(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1180;

  Widget _buildHomeContentSections({required bool isWideLayout}) {
    return Column(
      children: [
        _buildStoriesSection(),
        const SizedBox(height: 12),
        _buildUpcomingEventsSection(isWideLayout: isWideLayout),
        SizedBox(height: isWideLayout ? 18 : 16),
        _buildHomeFeedStage(isWideLayout: isWideLayout),
      ],
    );
  }

  String _currentDisplayName() {
    final displayName = _authService.currentUserDisplayName?.trim() ?? '';
    if (displayName.isNotEmpty) {
      return displayName;
    }
    final email = _authService.currentUserEmail?.trim() ?? '';
    if (email.isNotEmpty) {
      return email;
    }
    return 'Профиль';
  }

  String _displayInitial(String displayName) {
    final normalized = displayName.trim();
    if (normalized.isEmpty) {
      return 'Р';
    }
    return normalized.substring(0, 1).toUpperCase();
  }

  Widget _buildHomeHeader({
    required bool hasSelectedTree,
    required String? selectedTreeName,
    required bool isFriendsTree,
  }) {
    final theme = Theme.of(context);
    final displayName = _currentDisplayName();
    final photoUrl = _authService.currentUserPhotoUrl?.trim();
    final chips = <Widget>[
      _buildHeaderChip(
        icon: hasSelectedTree
            ? (isFriendsTree
                ? Icons.diversity_3_outlined
                : Icons.account_tree_outlined)
            : Icons.account_tree_outlined,
        label: hasSelectedTree
            ? (selectedTreeName ?? 'Активное дерево')
            : 'Нет активного дерева',
        highlighted: true,
      ),
    ];

    if (hasSelectedTree && !_isLoadingEvents) {
      chips.add(
        _buildHeaderChip(
          icon: Icons.event_outlined,
          label: _upcomingEvents.isEmpty
              ? 'Без событий'
              : '${_upcomingEvents.length} событий',
        ),
      );
    }

    if (hasSelectedTree && !_isLoadingPosts) {
      chips.add(
        _buildHeaderChip(
          icon: _postsUnavailable
              ? Icons.cloud_off_outlined
              : Icons.dynamic_feed_outlined,
          label: _postsUnavailable
              ? 'Лента недоступна'
              : (_posts.isEmpty ? 'Лента пустая' : '${_posts.length} постов'),
        ),
      );
    }

    if (hasSelectedTree && !_isLoadingStories) {
      chips.add(
        _buildHeaderChip(
          icon: _storiesUnavailable
              ? Icons.cloud_off_outlined
              : Icons.auto_stories_outlined,
          label: _storiesUnavailable
              ? 'Истории недоступны'
              : (_stories.isEmpty
                  ? 'Историй нет'
                  : '${_stories.length} историй'),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: _buildDesktopSideCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundImage: photoUrl != null && photoUrl.isNotEmpty
                      ? NetworkImage(photoUrl)
                      : null,
                  child: photoUrl == null || photoUrl.isEmpty
                      ? Text(
                          _displayInitial(displayName),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasSelectedTree
                                ? Icons.circle
                                : Icons.radio_button_unchecked_rounded,
                            size: 10,
                            color: hasSelectedTree
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            hasSelectedTree
                                ? (isFriendsTree
                                    ? 'Круг активен'
                                    : 'Дерево активно')
                                : 'Выберите дерево',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filledTonal(
                  tooltip: 'Открыть профиль',
                  onPressed: () => context.go('/profile'),
                  icon: const Icon(Icons.person_outline_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: chips,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: hasSelectedTree
                  ? [
                      _buildQuickActionButton(
                        icon: Icons.post_add_outlined,
                        label: 'Пост',
                        onTap: () => context.push('/post/create'),
                        primary: true,
                      ),
                      _buildQuickActionButton(
                        icon: isFriendsTree
                            ? Icons.hub_outlined
                            : Icons.people_outline,
                        label: isFriendsTree ? 'Люди' : 'Родные',
                        onTap: () => context.go('/relatives'),
                      ),
                      _buildQuickActionButton(
                        icon: Icons.account_tree_outlined,
                        label: 'Дерево',
                        onTap: () => context.go('/tree?selector=1'),
                      ),
                    ]
                  : [
                      _buildQuickActionButton(
                        icon: Icons.account_tree_outlined,
                        label: 'Выбрать дерево',
                        onTap: () => context.go('/tree?selector=1'),
                        primary: true,
                      ),
                      _buildQuickActionButton(
                        icon: Icons.add_circle_outline,
                        label: 'Создать граф',
                        onTap: () => context.push('/trees/create'),
                      ),
                    ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopSideCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(18),
  }) {
    return GlassPanel(
      padding: padding,
      borderRadius: BorderRadius.circular(30),
      child: child,
    );
  }

  Widget _buildHomeFeedStage({required bool isWideLayout}) {
    final feed = _buildFeedContent(wideLayout: isWideLayout);
    if (!isWideLayout) {
      return feed;
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: feed,
      ),
    );
  }

  Widget _buildFeedContent({bool wideLayout = false}) {
    if (_isLoadingPosts && _posts.isEmpty) {
      return Column(children: List.generate(3, (_) => const PostCardShimmer()));
    }

    if (_posts.isEmpty) {
      return _buildFeedEmptyState(wideLayout: wideLayout);
    }

    return Column(
      children: _posts
          .map(
            (post) => PostCard(
              post: post,
              onDeleted: () {
                if (_currentTreeId != null) {
                  _loadPosts(_currentTreeId!);
                }
              },
            ),
          )
          .toList(),
    );
  }

  Widget _buildFeedEmptyState({required bool wideLayout}) {
    Future<void> handleAction() async {
      if (_postsUnavailable) {
        if (_currentTreeId != null) {
          _loadPosts(_currentTreeId!);
        }
        return;
      }
      final result = await context.push('/post/create');
      if (result == true && _currentTreeId != null) {
        _loadPosts(_currentTreeId!);
      }
    }

    final title = _postsUnavailable ? 'Лента недоступна' : 'Лента пуста';
    final message = _postsUnavailable
        ? 'Обновите позже.'
        : _treeProviderInstance?.selectedTreeKind == TreeKind.friends
            ? 'Начните с короткого поста.'
            : 'Начните с первой публикации.';
    final actionLabel = _postsUnavailable ? 'Обновить' : 'Создать';

    if (!wideLayout) {
      return EmptyStateWidget(
        icon: Icons.post_add_outlined,
        title: title,
        message: message,
        actionLabel: actionLabel,
        onAction: handleAction,
      );
    }

    final theme = Theme.of(context);
    return _buildDesktopSideCard(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              _postsUnavailable
                  ? Icons.wifi_tethering_error_rounded
                  : Icons.auto_awesome_mosaic_outlined,
              size: 28,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderChip(
                  icon: _postsUnavailable
                      ? Icons.cloud_off_outlined
                      : Icons.dynamic_feed_outlined,
                  label: _postsUnavailable ? 'Офлайн' : 'Лента',
                  highlighted: !_postsUnavailable,
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          FilledButton.icon(
            onPressed: handleAction,
            icon: Icon(
              _postsUnavailable
                  ? Icons.refresh_rounded
                  : Icons.post_add_outlined,
            ),
            label: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderChip({
    required IconData icon,
    required String label,
    bool highlighted = false,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: highlighted
            ? theme.colorScheme.primary.withValues(alpha: 0.10)
            : theme.colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: highlighted
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.9),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: highlighted
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: highlighted
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    if (primary) {
      return FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
      );
    }
    return FilledButton.tonalIcon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
    );
  }

  Widget _buildPendingInvitationsBanner(List<TreeInvitation> invitations) {
    final theme = Theme.of(context);
    final count = invitations.length;
    final firstTreeName = invitations.first.tree.name.trim();
    final title = count == 1
        ? (firstTreeName.isNotEmpty ? firstTreeName : 'Новое приглашение')
        : '$count приглашения';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: GlassPanel(
        padding: const EdgeInsets.all(14),
        color: theme.colorScheme.tertiary.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onTertiaryContainer.withValues(
                      alpha: 0.08,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.mark_email_unread_outlined,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(title, style: theme.textTheme.titleMedium)),
                _buildHeaderChip(
                  icon: Icons.mark_email_unread_outlined,
                  label: count == 1 ? '1' : '$count',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    count == 1 ? 'Откройте и примите.' : 'Проверьте список.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  onPressed: () => context.go('/trees?tab=invitations'),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Открыть'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingEventsSection({required bool isWideLayout}) {
    final theme = Theme.of(context);
    final visibleEvents = _visibleUpcomingEvents;
    return _buildDesktopSideCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _treeProviderInstance?.selectedTreeKind == TreeKind.friends
                      ? 'Поводы'
                      : 'События',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (!_isLoadingEvents)
                _buildHeaderChip(
                  icon: Icons.schedule_outlined,
                  label: visibleEvents.isEmpty
                      ? '0'
                      : visibleEvents.length.toString(),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (!_isLoadingEvents && _upcomingEvents.isNotEmpty) ...[
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildEventFilterChip(
                    label: 'Все',
                    semanticLabel: 'home-event-filter-all',
                    selected: _selectedEventCategoryFilter == null,
                    onTap: () {
                      setState(() {
                        _selectedEventCategoryFilter = null;
                      });
                    },
                  ),
                  for (final category in _eventCategories) ...[
                    const SizedBox(width: 8),
                    _buildEventFilterChip(
                      label: category,
                      semanticLabel:
                          'home-event-filter-${_eventCategoryKey(category)}',
                      selected: _selectedEventCategoryFilter == category,
                      onTap: () {
                        setState(() {
                          _selectedEventCategoryFilter = category;
                        });
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (_isLoadingEvents)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_upcomingEvents.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.event_busy_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Событий пока нет',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          else if (visibleEvents.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_alt_off_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Под фильтр пока пусто.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Listener(
              onPointerSignal:
                  isWideLayout ? _handleEventRailPointerSignal : null,
              child: SizedBox(
                height: 126,
                child: ListView.builder(
                  controller: _eventRailController,
                  scrollDirection: Axis.horizontal,
                  itemCount: visibleEvents.length,
                  itemBuilder: (context, index) {
                    return EventCard(event: visibleEvents[index]);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEventFilterChip({
    required String label,
    required String semanticLabel,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      label: semanticLabel,
      button: true,
      selected: selected,
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onSelected: (_) => onTap(),
      ),
    );
  }

  void _handleEventRailPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_eventRailController.hasClients) {
      return;
    }

    final maxScrollExtent = _eventRailController.position.maxScrollExtent;
    final nextOffset = (_eventRailController.offset +
            event.scrollDelta.dy +
            event.scrollDelta.dx)
        .clamp(0.0, maxScrollExtent);
    _eventRailController.jumpTo(nextOffset);
  }

  Widget _buildStoriesSection() {
    return StoryRail(
      title: _treeProviderInstance?.selectedTreeKind == TreeKind.friends
          ? 'Истории круга'
          : 'Истории семьи',
      currentUserId: _authService.currentUserId ?? '',
      stories: _stories,
      isLoading: _isLoadingStories,
      unavailable: _storiesUnavailable,
      onRetry: () {
        if (_currentTreeId != null) {
          _loadStories(_currentTreeId!);
        }
      },
      onCreateStory: () async {
        final result = await context.push('/stories/create');
        if (result == true && _currentTreeId != null) {
          _loadStories(_currentTreeId!);
        }
      },
      onOpenStories: (stories) async {
        if (stories.isEmpty) {
          return;
        }
        final story = stories.last;
        final route = '/stories/view/${story.treeId}/${story.authorId}';
        await context.push(
          route,
        );
        if (_currentTreeId != null) {
          _loadStories(_currentTreeId!);
        }
      },
      emptyLabel: _treeProviderInstance?.selectedTreeKind == TreeKind.friends
          ? 'Первая история появится здесь.'
          : 'Первая история появится здесь.',
    );
  }
}
