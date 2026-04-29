// ignore_for_file: library_private_types_in_public_api
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
import '../services/app_status_service.dart';
import '../widgets/post_card.dart';
import '../widgets/post_card_shimmer.dart';
import '../widgets/story_rail.dart';
import '../widgets/glass_panel.dart';
import '../services/custom_api_notification_service.dart';
import '../utils/e2e_state_bridge.dart';
import '../utils/web_wheel_listener.dart';

part 'home_screen_sections.dart';

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
  final AppStatusService _appStatusService = GetIt.I<AppStatusService>();
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
  final GlobalKey _eventRailRegionKey = GlobalKey();
  CancelWebWheelListener? _cancelWebWheelSubscription;
  int _webWheelEventCount = 0;
  bool _isEventRailHovered = false;

  CustomApiNotificationService? get _customNotificationService =>
      GetIt.I.isRegistered<CustomApiNotificationService>()
          ? GetIt.I<CustomApiNotificationService>()
          : null;

  @override
  void initState() {
    super.initState();
    _eventService = EventService();
    _eventRailController.addListener(_handleEventRailScrollChanged);
    if (kIsWeb) {
      _cancelWebWheelSubscription =
          registerWebWheelListener(_handleWebEventRailWheel);
    }

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
    _eventRailController.removeListener(_handleEventRailScrollChanged);
    _cancelWebWheelSubscription?.call();
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
      _appStatusService.reportError(
        e,
        fallbackMessage: 'Не удалось обновить истории.',
      );
      if (mounted) {
        setState(() {
          _storiesUnavailable = true;
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
      final events = await _eventService.getUpcomingEvents(treeId, limit: 10);
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
      _appStatusService.reportError(
        e,
        fallbackMessage: 'Не удалось обновить события.',
      );
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
      final eventRailBounds = _currentEventRailBounds();
      E2EStateBridge.publish(
        screen: 'home',
        state: <String, dynamic>{
          'selectedTreeId': _currentTreeId,
          'selectedTreeName': selectedTreeName,
          'hasSelectedTree': hasSelectedTree,
          'isLoadingEvents': _isLoadingEvents,
          'selectedEventFilter': _selectedEventCategoryFilter,
          'availableEventFilters': <String>['Все', ..._eventCategories],
          'eventRailOffset':
              _eventRailController.hasClients ? _eventRailController.offset : 0,
          'eventRailMaxOffset': _eventRailController.hasClients
              ? _eventRailController.position.maxScrollExtent
              : 0,
          'webWheelEventCount': _webWheelEventCount,
          'eventRailBounds': eventRailBounds == null
              ? null
              : <String, double>{
                  'left': eventRailBounds.left,
                  'top': eventRailBounds.top,
                  'width': eventRailBounds.width,
                  'height': eventRailBounds.height,
                },
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

  void _handleEventRailScrollChanged() {
    final treeProvider = _treeProviderInstance;
    if (!mounted || treeProvider == null) {
      return;
    }
    _publishHomeE2EState(
      selectedTreeName: treeProvider.selectedTreeName,
      hasSelectedTree:
          _currentTreeId != null && treeProvider.selectedTreeName != null,
    );
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
      _appStatusService.reportError(
        e,
        fallbackMessage: 'Не удалось обновить ленту.',
      );
      if (mounted) {
        setState(() {
          _postsUnavailable = true;
          _isLoadingPosts = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(selectedTreeName ?? 'Главная'),
        backgroundColor: theme.colorScheme.surface.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.84 : 0.76,
        ),
        surfaceTintColor: Colors.transparent,
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
                    if (_shouldShowOperationalBanner(hasSelectedTree))
                      SliverToBoxAdapter(
                        child: _buildOperationalBanner(
                          hasSelectedTree: hasSelectedTree,
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

  bool _shouldShowOperationalBanner(bool hasSelectedTree) {
    if (_appStatusService.hasVisibleStatus) {
      return true;
    }
    if (!hasSelectedTree) {
      return false;
    }
    return _postsUnavailable || _storiesUnavailable;
  }

  Widget _buildDesktopSideCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(18),
  }) {
    return GlassPanel(
      padding: padding,
      borderRadius: BorderRadius.circular(22),
      child: child,
    );
  }

  Widget _buildEventStatePanel({
    required IconData icon,
    required String title,
    required String message,
    bool showProgress = false,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.82),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: showProgress
                ? const Padding(
                    padding: EdgeInsets.all(11),
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : Icon(icon, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: onAction,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(actionLabel),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
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

  Widget _buildHeaderChip({
    required IconData icon,
    required String label,
    bool highlighted = false,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
            size: 15,
            color: highlighted
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
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
    final style = FilledButton.styleFrom(
      visualDensity: VisualDensity.compact,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    );
    if (primary) {
      return FilledButton.icon(
        onPressed: onTap,
        style: style,
        icon: Icon(icon),
        label: Text(label),
      );
    }
    return FilledButton.tonalIcon(
      onPressed: onTap,
      style: style,
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
    final showRailControls = MediaQuery.of(context).size.width >= 760;
    final canScrollRail = showRailControls && visibleEvents.length > 1;
    return _buildDesktopSideCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
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
              if (canScrollRail) ...[
                _buildEventRailArrowButton(
                  icon: Icons.chevron_left_rounded,
                  tooltip: 'Прокрутить события влево',
                  semanticLabel: 'home-event-scroll-left',
                  onTap: () => _nudgeEventRail(-220),
                ),
                const SizedBox(width: 6),
                _buildEventRailArrowButton(
                  icon: Icons.chevron_right_rounded,
                  tooltip: 'Прокрутить события вправо',
                  semanticLabel: 'home-event-scroll-right',
                  onTap: () => _nudgeEventRail(220),
                ),
                const SizedBox(width: 8),
              ],
              if (!_isLoadingEvents)
                _buildHeaderChip(
                  icon: Icons.schedule_outlined,
                  label: visibleEvents.isEmpty
                      ? '0'
                      : visibleEvents.length.toString(),
                ),
            ],
          ),
          const SizedBox(height: 8),
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
            const SizedBox(height: 8),
          ],
          if (_isLoadingEvents)
            _buildEventStatePanel(
              icon: Icons.schedule_outlined,
              title: 'Собираем ближайшие даты',
              message:
                  'Подтягиваем дни рождения, памятные даты и поводы для семьи.',
              showProgress: true,
            )
          else if (_upcomingEvents.isEmpty)
            _buildEventStatePanel(
              icon: Icons.event_busy_outlined,
              title: 'Ближайшие даты появятся здесь',
              message: _treeProviderInstance?.selectedTreeKind ==
                      TreeKind.friends
                  ? 'Добавьте памятные поводы, чтобы круг видел, что важно сейчас.'
                  : 'Когда в семье появятся дни рождения и памятные даты, они сразу соберутся в эту ленту.',
              actionLabel: _currentTreeId == null ? null : 'Обновить события',
              onAction: _currentTreeId == null
                  ? null
                  : () => _loadEvents(_currentTreeId!),
            )
          else if (visibleEvents.isEmpty)
            _buildEventStatePanel(
              icon: Icons.filter_alt_off_outlined,
              title: 'Под выбранный фильтр пока пусто',
              message:
                  'Сбросьте фильтр и посмотрите все ближайшие события одним списком.',
              actionLabel: 'Показать все',
              onAction: () {
                setState(() {
                  _selectedEventCategoryFilter = null;
                });
              },
            )
          else
            Container(
              key: _eventRailRegionKey,
              child: MouseRegion(
                onEnter: (_) => _setEventRailHovered(true),
                onExit: (_) => _setEventRailHovered(false),
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerSignal:
                      showRailControls ? _handleEventRailPointerSignal : null,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final cardWidth = _eventCardWidthFor(constraints);
                      return SizedBox(
                        height: 132,
                        child: ListView.builder(
                          controller: _eventRailController,
                          scrollDirection: Axis.horizontal,
                          itemCount: visibleEvents.length,
                          itemBuilder: (context, index) {
                            return EventCard(
                              event: visibleEvents[index],
                              width: cardWidth,
                            );
                          },
                        ),
                      );
                    },
                  ),
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

    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      if (resolved is PointerScrollEvent) {
        _scrollEventRailBy(resolved.scrollDelta.dx, resolved.scrollDelta.dy);
      }
    });
  }

  bool _handleWebEventRailWheel(
    double deltaX,
    double deltaY,
    double clientX,
    double clientY,
  ) {
    _webWheelEventCount += 1;
    if (!_eventRailController.hasClients ||
        !(_isEventRailHovered || _isPointInsideEventRail(clientX, clientY))) {
      _handleEventRailScrollChanged();
      return false;
    }

    final scrolled = _scrollEventRailBy(deltaX, deltaY);
    if (!scrolled) {
      _handleEventRailScrollChanged();
    }
    return scrolled;
  }

  bool _isPointInsideEventRail(double clientX, double clientY) {
    final rect = _currentEventRailBounds();
    if (rect == null) {
      return false;
    }
    return rect.contains(Offset(clientX, clientY));
  }

  Rect? _currentEventRailBounds() {
    final context = _eventRailRegionKey.currentContext;
    if (context == null) {
      return null;
    }

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }

    final topLeft = renderObject.localToGlobal(Offset.zero);
    return topLeft & renderObject.size;
  }

  void _setEventRailHovered(bool hovered) {
    if (_isEventRailHovered == hovered) {
      return;
    }
    _isEventRailHovered = hovered;
    _handleEventRailScrollChanged();
  }

  void _nudgeEventRail(double delta) {
    _scrollEventRailBy(delta, 0);
  }

  Widget _buildEventRailArrowButton({
    required IconData icon,
    required String tooltip,
    required String semanticLabel,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: semanticLabel,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(
          backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.82),
          foregroundColor: theme.colorScheme.onSurfaceVariant,
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.9),
          ),
        ),
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, size: 18),
      ),
    );
  }

  bool _scrollEventRailBy(double deltaX, double deltaY) {
    final maxScrollExtent = _eventRailController.position.maxScrollExtent;
    if (maxScrollExtent <= 0) {
      return false;
    }

    final delta = deltaY.abs() >= deltaX.abs() ? deltaY : deltaX;
    final normalizedDelta =
        delta == 0 ? 0.0 : delta.sign * (delta.abs() < 72 ? 72 : delta.abs());
    final nextOffset = (_eventRailController.offset + normalizedDelta).clamp(
      0.0,
      maxScrollExtent,
    );
    if ((nextOffset - _eventRailController.offset).abs() < 0.1) {
      return false;
    }
    _eventRailController.jumpTo(nextOffset);
    _handleEventRailScrollChanged();
    return true;
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
