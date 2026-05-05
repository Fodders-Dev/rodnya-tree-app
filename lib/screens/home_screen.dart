// ignore_for_file: library_private_types_in_public_api
import 'dart:async';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
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
import '../backend/interfaces/identity_service_interface.dart';
import '../backend/models/tree_invitation.dart';
import '../backend/interfaces/post_service_interface.dart';
import '../backend/interfaces/story_service_interface.dart';
import '../models/post.dart';
import '../models/story.dart';
import '../services/app_status_service.dart';
import '../services/posts_cache.dart';
import '../theme/app_theme.dart';
import '../widgets/post_card.dart';
import '../widgets/post_card_shimmer.dart';
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
  String _selectedFeedFilter = 'Семья';
  bool _isLoadingEvents = true;
  bool _isLoadingPosts = false;
  bool _isLoadingStories = false;
  bool _postsUnavailable = false;
  bool _storiesUnavailable = false;
  bool _identityReviewsUnavailable = false;
  int _pendingIdentityReviewCount = 0;
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

  IdentityServiceInterface? get _identityService =>
      GetIt.I.isRegistered<IdentityServiceInterface>()
          ? GetIt.I<IdentityServiceInterface>()
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
    // Twitter / GitHub-style "/" shortcut to focus search. Only on
    // desktop where physical keyboard is the primary input.
    HardwareKeyboard.instance.addHandler(_handleHomeKeyEvent);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _treeProviderInstance = Provider.of<TreeProvider>(context, listen: false);
      _treeProviderInstance!.addListener(_handleTreeChange);
      _currentTreeId = _treeProviderInstance!.selectedTreeId;
      _loadIdentityReviewSummary();
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
    HardwareKeyboard.instance.removeHandler(_handleHomeKeyEvent);
    _treeProviderInstance?.removeListener(_handleTreeChange);
    _eventRailController.removeListener(_handleEventRailScrollChanged);
    _cancelWebWheelSubscription?.call();
    _eventRailController.dispose();
    super.dispose();
  }

  /// Global hotkey handler — registered on HardwareKeyboard directly
  /// rather than via Focus.onKeyEvent because Flutter web's CanvasKit
  /// can swallow KeyDown events at the framework Focus layer.
  ///
  /// Currently supports:
  /// - "/" → push the search screen (Twitter / GitHub style). Skipped
  ///   when any TextField has focus so users typing "/" inside a
  ///   composer aren't hijacked.
  bool _handleHomeKeyEvent(KeyEvent event) {
    if (!mounted || event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.slash) return false;
    final focused = FocusManager.instance.primaryFocus;
    final inEditable =
        focused?.context?.widget is EditableText ||
            (focused?.context != null &&
                focused!.context!.findAncestorWidgetOfExactType<
                        EditableText>() !=
                    null);
    if (inEditable) return false;
    // Don't fire for ?-shortcut or ctrl/cmd combos.
    if (HardwareKeyboard.instance.isShiftPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return false;
    }
    context.push('/post/search');
    return true;
  }

  void _handleTreeChange() {
    if (!mounted) return;
    final newTreeId = _treeProviderInstance?.selectedTreeId;
    if (_currentTreeId != newTreeId) {
      _currentTreeId = newTreeId;
      _loadIdentityReviewSummary();
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
          _selectedFeedFilter = 'Семья';
        });
      }
    }
  }

  Future<void> _loadIdentityReviewSummary() async {
    final service = _identityService;
    if (service == null) {
      if (mounted) {
        setState(() {
          _pendingIdentityReviewCount = 0;
          _identityReviewsUnavailable = false;
        });
      }
      return;
    }

    try {
      final proposals = await service.getPendingMergeProposals();
      final claims = await service.getPendingIdentityClaims();
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingIdentityReviewCount = proposals.length + claims.length;
        _identityReviewsUnavailable = false;
      });
    } catch (error) {
      debugPrint('Ошибка загрузки identity review summary: $error');
      if (mounted) {
        setState(() {
          _identityReviewsUnavailable = true;
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

  // Reference: fixed strip "Семья / Близкие / Архив / Истории" — always
  // visible regardless of post data, matching Claude design source.
  static const List<String> _feedFilters = <String>[
    'Семья',
    'Близкие',
    'Архив',
    'Истории',
  ];

  List<Post> get _visiblePosts {
    switch (_selectedFeedFilter) {
      case 'Близкие':
        // Близкие = posts to a non-default circle (favorites/inner ring).
        return _posts.where((post) => post.circleId != null).toList();
      case 'Архив':
        // Архив = older posts (>30 days).
        final cutoff = DateTime.now().subtract(const Duration(days: 30));
        return _posts.where((post) => post.createdAt.isBefore(cutoff)).toList();
      case 'Истории':
        // Истории = posts with at least one photo.
        return _posts
            .where((post) => post.renderableImageUrls.isNotEmpty)
            .toList();
      case 'Семья':
      default:
        return _posts;
    }
  }

  void _selectFeedFilter(String label) {
    if (_selectedFeedFilter == label) {
      return;
    }
    setState(() {
      _selectedFeedFilter = label;
    });
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
          'selectedFeedFilter': _selectedFeedFilter,
          'availableFeedFilters': _feedFilters,
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

  PostsCache? get _postsCache => GetIt.I.isRegistered<PostsCache>()
      ? GetIt.I<PostsCache>()
      : null;

  Future<void> _loadPosts(String treeId) async {
    if (!mounted) return;
    setState(() {
      _isLoadingPosts = true;
      // Don't surface "feed unavailable" the moment we start loading —
      // it'll flicker on every refresh. Only flip back if we actually
      // have no posts to show after the call fails.
    });
    // Cache-first hydrate: serve disk-cached posts immediately so the
    // feed paints content even if we're offline / network is slow.
    final cache = _postsCache;
    if (cache != null && _posts.isEmpty) {
      try {
        final cached = await cache.read(treeId);
        if (cached.isNotEmpty && mounted && _currentTreeId == treeId) {
          setState(() {
            _posts = cached;
            _postsUnavailable = false;
          });
        }
      } catch (_) {
        // Cache read failure is non-fatal.
      }
    }
    try {
      final posts = await _postService.getPosts(treeId: treeId);
      if (mounted) {
        unawaited(cache?.write(treeId, posts));
        setState(() {
          _posts = posts;
          _isLoadingPosts = false;
          _postsUnavailable = false;
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
          // Keep the existing _posts list so the user still sees what
          // they had cached / fetched previously. Only mark as
          // unavailable when we have NOTHING to show — that's the
          // case where the empty-state UI is the right answer.
          _postsUnavailable = _posts.isEmpty;
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

    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(76),
        child: _buildHomeTopbar(theme: theme, tokens: tokens),
      ),
      floatingActionButton: hasSelectedTree
          ? FloatingActionButton(
              onPressed: () => context.push('/post/create'),
              backgroundColor: tokens.accent,
              foregroundColor: tokens.accentInk,
              elevation: 4,
              shape: const CircleBorder(),
              tooltip: 'Написать пост',
              child: const Icon(Icons.edit_outlined, size: 22),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          await _customNotificationService?.refreshUnreadNotificationsCount();
          await _loadIdentityReviewSummary();
          if (_currentTreeId != null) {
            await Future.wait([
              _loadStories(_currentTreeId!),
              _loadEvents(_currentTreeId!),
              _loadPosts(_currentTreeId!),
            ]);
          }
        },
        child: StreamBuilder<List<TreeInvitation>>(
          stream: _familyTreeService.getPendingTreeInvitations(),
          builder: (context, snapshot) {
            final pendingInvitations =
                snapshot.data ?? const <TreeInvitation>[];
            return _buildHomeBody(
              pendingInvitations: pendingInvitations,
              hasSelectedTree: hasSelectedTree,
              isWideLayout: isWideLayout,
              selectedTreeName: selectedTreeName,
              isFriendsTree: isFriendsTree,
            );
          },
        ),
      ),
    );
  }

  Widget _buildHomeTopbar({
    required ThemeData theme,
    required RodnyaDesignTokens tokens,
  }) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: 76,
          decoration: BoxDecoration(
            color: tokens.surface.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.74 : 0.78,
            ),
            border: Border(
              bottom: BorderSide(
                color: tokens.surfaceLine.withValues(alpha: 0.5),
                width: 0.6,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(18, 12, 12, 14),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                Text(
                  'Родня',
                  style: AppTheme.serif(
                    color: tokens.ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.22,
                  ),
                ),
                const Spacer(),
                _buildTopbarIconButton(
                  tokens: tokens,
                  tooltip: 'Поиск по постам',
                  onTap: () => context.push('/post/search'),
                  child: Icon(
                    Icons.search_rounded,
                    size: 20,
                    color: tokens.accent,
                  ),
                ),
                const SizedBox(width: 8),
                _buildTopbarIconButton(
                  tokens: tokens,
                  child: _buildNotificationsAction(tokens: tokens),
                  tooltip: 'Активность',
                  onTap: () => context.push('/notifications'),
                ),
                const SizedBox(width: 8),
                _buildTopbarIconButton(
                  tokens: tokens,
                  tooltip: 'Выбрать дерево',
                  onTap: () => context.go('/tree?selector=1'),
                  child: Icon(
                    Icons.account_tree_outlined,
                    size: 19,
                    color: tokens.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopbarIconButton({
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

  Widget _buildNotificationsAction({required RodnyaDesignTokens tokens}) {
    final notificationService = _customNotificationService;
    final defaultIcon = Icon(
      Icons.notifications_outlined,
      size: 19,
      color: tokens.ink,
    );
    if (notificationService == null) {
      return defaultIcon;
    }

    return StreamBuilder<int>(
      stream: notificationService.unreadNotificationsCountStream,
      initialData: notificationService.unreadNotificationsCount,
      builder: (context, snapshot) {
        final unreadCount = snapshot.data ?? 0;
        if (unreadCount <= 0) {
          return defaultIcon;
        }
        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            defaultIcon,
            Positioned(
              top: -6,
              right: -8,
              child: Container(
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: tokens.warm,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: tokens.surfaceStrong, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    unreadCount > 99 ? '99+' : unreadCount.toString(),
                    style: AppTheme.sans(
                      color: Colors.black87,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  bool _isWideHomeLayout(BuildContext context) =>
      MediaQuery.of(context).size.width >= 1180;

  /// Wraps the home body. On narrow viewports we keep the legacy
  /// single-column phone layout (capped at 720). On wide desktop
  /// browsers we split into a feed + sidebar layout so the empty
  /// left/right margins ("выглядит как растянутый телефон") finally
  /// get used. Pending invitations / operational banner / no-tree
  /// state stay above the split as a top strip — they target the full
  /// width of the inner column either way.
  Widget _buildHomeBody({
    required List<TreeInvitation> pendingInvitations,
    required bool hasSelectedTree,
    required bool isWideLayout,
    required String? selectedTreeName,
    required bool isFriendsTree,
  }) {
    if (!isWideLayout) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: CustomScrollView(
            slivers: [
              if (pendingInvitations.isNotEmpty)
                SliverToBoxAdapter(
                  child: _buildPendingInvitationsBanner(pendingInvitations),
                ),
              if (_shouldShowOperationalBanner(hasSelectedTree))
                SliverToBoxAdapter(
                  child: _buildOperationalBanner(
                    hasSelectedTree: hasSelectedTree,
                  ),
                ),
              if (!hasSelectedTree)
                SliverToBoxAdapter(
                  child: _buildHomeHeader(
                    hasSelectedTree: hasSelectedTree,
                    selectedTreeName: selectedTreeName,
                    isFriendsTree: isFriendsTree,
                  ),
                ),
              if (hasSelectedTree) ...[
                SliverToBoxAdapter(
                  child: _buildHomeContentSections(isWideLayout: false),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ] else
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        ),
      );
    }

    // Wide-layout: feed column (~720) + contextual sidebar (~340)
    // anchored to the top. Banners + identity-review banner pin to a
    // strip across the top so they don't get swallowed by the sidebar.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: CustomScrollView(
          slivers: [
            if (pendingInvitations.isNotEmpty)
              SliverToBoxAdapter(
                child: _buildPendingInvitationsBanner(pendingInvitations),
              ),
            if (_shouldShowOperationalBanner(hasSelectedTree))
              SliverToBoxAdapter(
                child: _buildOperationalBanner(
                  hasSelectedTree: hasSelectedTree,
                ),
              ),
            if (!hasSelectedTree)
              SliverToBoxAdapter(
                child: _buildHomeHeader(
                  hasSelectedTree: hasSelectedTree,
                  selectedTreeName: selectedTreeName,
                  isFriendsTree: isFriendsTree,
                ),
              ),
            if (hasSelectedTree) ...[
              SliverToBoxAdapter(
                child: _buildWideHomeColumns(),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ] else
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  /// Two-column layout for wide viewports. Left = feed-shaped column
  /// (compose teaser, filters, posts) capped at ~720 so post media
  /// stays readable. Right = sidebar with stories rail and the events
  /// digest, sticky-feeling because it's positioned next to (rather
  /// than above) the feed.
  Widget _buildWideHomeColumns() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Feed column.
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: _buildHomeFeedColumn(),
            ),
          ),
          const SizedBox(width: 24),
          // Sidebar column.
          SizedBox(
            width: 340,
            child: _buildHomeSidebarColumn(),
          ),
        ],
      ),
    );
  }

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
    if (_isLoadingEvents) {
      return const SizedBox(height: 0);
    }
    if (_upcomingEvents.isEmpty) {
      return const SizedBox(height: 0);
    }

    final visibleEvents = _visibleUpcomingEvents;
    final showRailControls = MediaQuery.of(context).size.width >= 760;
    final categories = _eventCategories;
    final hasCategories = categories.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasCategories)
          SizedBox(
            height: 30,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18),
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
                for (final category in categories) ...[
                  const SizedBox(width: 6),
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
        if (hasCategories) const SizedBox(height: 8),
        if (visibleEvents.isEmpty)
          const SizedBox(height: 0)
        else
          SizedBox(
            height: 56,
            child: MouseRegion(
              onEnter: (_) => _setEventRailHovered(true),
              onExit: (_) => _setEventRailHovered(false),
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerSignal:
                    showRailControls ? _handleEventRailPointerSignal : null,
                child: ListView.separated(
                  key: _eventRailRegionKey,
                  controller: _eventRailController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  itemCount: visibleEvents.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    return EventCard(
                      event: visibleEvents[index],
                      compact: true,
                    );
                  },
                ),
              ),
            ),
          ),
        if (showRailControls && visibleEvents.length > 1) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
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
              ],
            ),
          ),
        ],
      ],
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

  /// Vertical events list for the wide-layout sidebar. Renders the
  /// same EventCards the horizontal rail uses but stacked instead of
  /// scrolled sideways — much friendlier on a 340dp column. Caps at
  /// 5 visible cards to keep the sidebar height reasonable; "Все
  /// события" link sits below the cap when there's more.
  Widget _buildSidebarUpcomingEvents() {
    final visibleEvents = _visibleUpcomingEvents;
    if (_isLoadingEvents || visibleEvents.isEmpty) {
      return const SizedBox.shrink();
    }
    final categories = _eventCategories;
    final hasCategories = categories.isNotEmpty;
    final cap = 5;
    final displayed = visibleEvents.take(cap).toList();
    final overflow = visibleEvents.length - displayed.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasCategories) ...[
          SizedBox(
            height: 30,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildEventFilterChip(
                  label: 'Все',
                  semanticLabel: 'home-event-filter-all',
                  selected: _selectedEventCategoryFilter == null,
                  onTap: () => setState(
                    () => _selectedEventCategoryFilter = null,
                  ),
                ),
                for (final category in categories) ...[
                  const SizedBox(width: 6),
                  _buildEventFilterChip(
                    label: category,
                    semanticLabel:
                        'home-event-filter-${_eventCategoryKey(category)}',
                    selected: _selectedEventCategoryFilter == category,
                    onTap: () => setState(
                      () => _selectedEventCategoryFilter = category,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        for (var i = 0; i < displayed.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          EventCard(
            event: displayed[i],
            compact: true,
            width: double.infinity,
          ),
        ],
        if (overflow > 0) ...[
          const SizedBox(height: 10),
          Center(
            child: Text(
              'и ещё $overflow',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ],
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
    final theme = Theme.of(context);
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final currentUserId = _authService.currentUserId ?? '';
    if (_isLoadingStories && _stories.isEmpty) {
      return const SizedBox(height: 0);
    }

    final byAuthor = <String, Story>{};
    for (final story in _stories) {
      final existing = byAuthor[story.authorId];
      if (existing == null || story.createdAt.isAfter(existing.createdAt)) {
        byAuthor[story.authorId] = story;
      }
    }
    final ordered = byAuthor.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return SizedBox(
      height: 88,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        children: [
          _StoryRing(
            tokens: tokens,
            isAdd: true,
            label: 'Создать',
            onTap: () async {
              final result = await context.push('/stories/create');
              if (result == true && _currentTreeId != null) {
                _loadStories(_currentTreeId!);
              }
            },
          ),
          for (final story in ordered)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _StoryRing(
                tokens: tokens,
                isAdd: false,
                label: story.authorName.split(' ').first,
                photoUrl: story.authorPhotoUrl,
                initials: _initialsFor(story.authorName),
                read: story.viewedBy.contains(currentUserId),
                onTap: () async {
                  final stories = _stories
                      .where((s) => s.authorId == story.authorId)
                      .toList();
                  if (stories.isEmpty) return;
                  final route =
                      '/stories/view/${story.treeId}/${story.authorId}';
                  await context.push(route);
                  if (_currentTreeId != null) {
                    _loadStories(_currentTreeId!);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  String _initialsFor(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts =
        trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      final a = String.fromCharCode(parts[0].runes.first);
      final b = String.fromCharCode(parts[1].runes.first);
      return (a + b).toUpperCase();
    }
    return String.fromCharCode(parts.first.runes.first).toUpperCase();
  }
}

class _StoryRing extends StatelessWidget {
  const _StoryRing({
    required this.tokens,
    required this.isAdd,
    required this.label,
    required this.onTap,
    this.photoUrl,
    this.initials,
    this.read = false,
  });

  final RodnyaDesignTokens tokens;
  final bool isAdd;
  final String label;
  final VoidCallback onTap;
  final String? photoUrl;
  final String? initials;
  final bool read;

  @override
  Widget build(BuildContext context) {
    final ringColor = isAdd
        ? tokens.accent
        : (read ? tokens.surfaceLine.withValues(alpha: 0.55) : tokens.accent);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: !isAdd && !read
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [tokens.accent, tokens.warm],
                      )
                    : null,
                color: (isAdd || read) ? Colors.transparent : null,
                border: (isAdd || read)
                    ? Border.all(color: ringColor, width: 1.6)
                    : null,
              ),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tokens.surfaceStrong,
                  border: Border.all(color: tokens.surfaceLine, width: 1),
                ),
                child: ClipOval(
                  child: isAdd
                      ? Center(
                          child: Icon(
                            Icons.add_rounded,
                            size: 22,
                            color: tokens.accent,
                          ),
                        )
                      : (photoUrl != null && photoUrl!.isNotEmpty)
                          ? Image.network(
                              photoUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Center(
                                child: Text(
                                  initials ?? '?',
                                  style: AppTheme.sans(
                                    color: tokens.ink,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            )
                          : Center(
                              child: Text(
                                initials ?? '?',
                                style: AppTheme.sans(
                                  color: tokens.ink,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                ),
              ),
            ),
            const SizedBox(height: 5),
            SizedBox(
              width: 64,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTheme.sans(
                  color: tokens.inkSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
