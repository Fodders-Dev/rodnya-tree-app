import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/chat_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../models/family_person.dart';
import '../providers/tree_provider.dart';
import '../screens/about_screen.dart';
import '../screens/add_relative_screen.dart';
import '../screens/blocked_users_screen.dart';
import '../screens/qr_login_scan_screen.dart';
import '../screens/sessions_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/chats_list_screen.dart';
import '../screens/create_post_screen.dart';
import '../screens/find_relative_screen.dart';
import '../screens/home_screen.dart';
import '../screens/offline_profiles_screen.dart';
import '../screens/post_search_screen.dart';
import '../screens/profile_edit_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/story_archive_screen.dart';
import '../screens/relatives_screen.dart';
import '../screens/relation_requests_screen.dart';
import '../screens/send_relation_request_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/tree_selector_screen.dart';
import '../screens/tree_view_screen.dart';
import '../screens/user_profile_entry_screen.dart';
import '../services/custom_api_notification_service.dart';
import '../theme/app_theme.dart';
import '../utils/url_utils.dart';
import '../widgets/app_backdrop.dart';
import '../widgets/main_navigation_bar.dart';
import '../widgets/offline_indicator.dart';
import 'app_router_guards.dart';
import 'app_router_shared.dart';

class AppShellRouteModule {
  const AppShellRouteModule();

  RouteBase build() {
    return StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        final currentUserId = GetIt.I<AuthServiceInterface>().currentUserId;
        final unreadNotificationsStream =
            GetIt.I.isRegistered<CustomApiNotificationService>()
                ? GetIt.I<CustomApiNotificationService>()
                    .unreadNotificationsCountStream
                : Stream<int>.value(0);
        final unreadChatsStream = currentUserId != null
            ? GetIt.I<ChatServiceInterface>()
                .getTotalUnreadCountStream(currentUserId)
            : Stream<int>.value(0);
        final pendingInvitationsCountStream = currentUserId != null
            ? GetIt.I<FamilyTreeServiceInterface>()
                .getPendingTreeInvitations()
                .map((invitations) => invitations.length)
            : Stream<int>.value(0);

        return LayoutBuilder(
          builder: (context, constraints) {
            // Earlier this was hard-coded to false — the design
            // reference is mobile-first and we forced that layout on
            // web. User feedback after live testing reversed course:
            // the centered narrow column on a wide browser felt like
            // "stretched phone with empty voids". Restore the proper
            // tablet / desktop shell at 900+ — sidebar nav rail
            // replaces the bottom dock, content centered at 1400 max.
            final bool isDesktop = constraints.maxWidth >= 900;
            final isTreeBranch = navigationShell.currentIndex == 2;

            Widget bodyContent = Column(
              children: <Widget>[
                OfflineIndicator(),
                Expanded(child: navigationShell),
              ],
            );

            if (isDesktop) {
              bodyContent = Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isTreeBranch ? double.infinity : 1400,
                  ),
                  child: bodyContent,
                ),
              );
            }

            if (isDesktop) {
              return Scaffold(
                backgroundColor: Colors.transparent,
                body: Stack(
                  fit: StackFit.expand,
                  children: [
                    const AppBackdrop(),
                    Row(
                      children: [
                        AdaptiveNavigationRail(
                          navigationShell: navigationShell,
                          unreadNotificationsStream: unreadNotificationsStream,
                          unreadChatsStream: unreadChatsStream,
                          pendingInvitationsCountStream:
                              pendingInvitationsCountStream,
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 16, 18, 16),
                            child: bodyContent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }

            return Scaffold(
              backgroundColor: Colors.transparent,
              // extendBody lets the AppBackdrop paint behind the floating
              // glass nav bar so content scrolls through it seamlessly.
              extendBody: true,
              body: Stack(
                fit: StackFit.expand,
                children: [
                  const AppBackdrop(),
                  bodyContent,
                ],
              ),
              bottomNavigationBar: MainNavigationBar(
                currentIndex: navigationShell.currentIndex,
                onTap: (index) {
                  navigationShell.goBranch(
                    index,
                    initialLocation: index == navigationShell.currentIndex,
                  );
                },
                unreadNotificationsStream: unreadNotificationsStream,
                unreadChatsStream: unreadChatsStream,
                pendingInvitationsCountStream: pendingInvitationsCountStream,
              ),
            );
          },
        );
      },
      branches: _buildBranches(),
    );
  }

  List<StatefulShellBranch> _buildBranches() {
    return <StatefulShellBranch>[
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) => RodnyaNoTransitionPage(
              key: state.pageKey,
              child: HomeScreen(),
            ),
            routes: [
              GoRoute(
                path: 'post/search',
                parentNavigatorKey: rootNavigatorKey,
                pageBuilder: (context, state) => RodnyaCustomTransitionPage(
                  key: state.pageKey,
                  constrainWidth: true,
                  child: const PostSearchScreen(),
                  transitionsBuilder: AppRouteTransitions.slide,
                ),
              ),
              GoRoute(
                path: 'post/create',
                parentNavigatorKey: rootNavigatorKey,
                pageBuilder: (context, state) {
                  // ?action=photo|video lets the home-screen teaser
                  // icons pre-fire the right picker on mount.
                  final action = state.uri.queryParameters['action'];
                  return RodnyaCustomTransitionPage(
                    key: state.pageKey,
                    constrainWidth: true,
                    child: CreatePostScreen(initialAction: action),
                    transitionsBuilder: AppRouteTransitions.slideUp,
                  );
                },
              ),
              GoRoute(
                path: 'user/:userId',
                parentNavigatorKey: rootNavigatorKey,
                pageBuilder: (context, state) {
                  final userId = state.pathParameters['userId'] ?? '';
                  return RodnyaCustomTransitionPage(
                    key: state.pageKey,
                    constrainWidth: true,
                    child: UserProfileEntryScreen(userId: userId),
                    transitionsBuilder: AppRouteTransitions.slide,
                  );
                },
              ),
            ],
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: '/relatives',
            pageBuilder: (context, state) => RodnyaNoTransitionPage(
              key: state.pageKey,
              child: RelativesScreen(),
            ),
            routes: [
              GoRoute(
                path: 'add/:treeId',
                parentNavigatorKey: rootNavigatorKey,
                pageBuilder: (context, state) {
                  final treeId = state.pathParameters['treeId'] ?? '';
                  final extra = state.extra;
                  final quickAddMode = extra is Map<String, dynamic> &&
                      extra['quickAddMode'] == true;
                  return RodnyaCustomTransitionPage(
                    key: state.pageKey,
                    constrainWidth: true,
                    child: AddRelativeScreen(
                      treeId: treeId,
                      quickAddMode: quickAddMode,
                      routeExtra: extra is Map<String, dynamic> ? extra : null,
                      routeQueryParameters: state.uri.queryParameters,
                    ),
                    transitionsBuilder: AppRouteTransitions.slide,
                  );
                },
              ),
              GoRoute(
                path: 'edit/:treeId/:personId',
                parentNavigatorKey: rootNavigatorKey,
                pageBuilder: (context, state) {
                  final treeId = state.pathParameters['treeId'] ?? '';
                  final personId = state.pathParameters['personId'] ?? '';
                  final personToEdit = state.extra as FamilyPerson?;

                  if (treeId.isEmpty || personId.isEmpty) {
                    return MaterialPage<void>(
                      child: Scaffold(
                        body: Center(
                          child: Text(
                            'Ошибка: Не указан ID дерева или родственника для редактирования.',
                          ),
                        ),
                      ),
                    );
                  }

                  return RodnyaCustomTransitionPage(
                    key: ValueKey<String>('edit_relative_$personId'),
                    constrainWidth: true,
                    child: AddRelativeScreen(
                      treeId: treeId,
                      person: personToEdit,
                      isEditing: true,
                    ),
                    transitionsBuilder: AppRouteTransitions.slide,
                  );
                },
              ),
              GoRoute(
                path: 'requests/:treeId',
                parentNavigatorKey: rootNavigatorKey,
                pageBuilder: (context, state) {
                  final treeId = state.pathParameters['treeId'] ?? '';
                  return RodnyaCustomTransitionPage(
                    key: state.pageKey,
                    constrainWidth: true,
                    child: RelationRequestsScreen(treeId: treeId),
                    transitionsBuilder: AppRouteTransitions.slide,
                  );
                },
              ),
              GoRoute(
                path: 'find/:treeId',
                parentNavigatorKey: rootNavigatorKey,
                pageBuilder: (context, state) {
                  final treeId = state.pathParameters['treeId'] ?? '';
                  return RodnyaCustomTransitionPage(
                    key: state.pageKey,
                    constrainWidth: true,
                    child: FindRelativeScreen(
                      treeId: treeId,
                      initialProfileCode:
                          state.uri.queryParameters['profileCode'],
                    ),
                    transitionsBuilder: AppRouteTransitions.slide,
                  );
                },
              ),
              GoRoute(
                path: 'send_request/:treeId',
                parentNavigatorKey: rootNavigatorKey,
                pageBuilder: (context, state) {
                  final treeId = state.pathParameters['treeId'] ?? '';
                  return RodnyaCustomTransitionPage(
                    key: state.pageKey,
                    constrainWidth: true,
                    child: SendRelationRequestScreen(treeId: treeId),
                    transitionsBuilder: AppRouteTransitions.slide,
                  );
                },
              ),
              GoRoute(
                path: 'chat/:userId',
                parentNavigatorKey: rootNavigatorKey,
                pageBuilder: (context, state) {
                  final userId = state.pathParameters['userId'] ?? '';
                  final name =
                      state.uri.queryParameters['name'] ?? 'Пользователь';
                  final photoUrl = state.uri.queryParameters['photo'];
                  final relativeId =
                      state.uri.queryParameters['relativeId'] ?? '';

                  if (relativeId.isEmpty) {
                    debugPrint('Error: Missing relativeId for chat route');
                    return MaterialPage<void>(
                      key: state.pageKey,
                      child: Scaffold(
                        appBar: AppBar(title: const Text('Ошибка')),
                        body: const Center(
                          child: Text('Не найден ID родственника для чата.'),
                        ),
                      ),
                    );
                  }

                  return RodnyaCustomTransitionPage(
                    key: state.pageKey,
                    constrainWidth: true,
                    child: ChatScreen(
                      otherUserId: userId,
                      title: name,
                      photoUrl: UrlUtils.normalizeImageUrl(photoUrl),
                      relativeId: relativeId,
                      chatType: 'direct',
                    ),
                    transitionsBuilder: AppRouteTransitions.slide,
                  );
                },
              ),
            ],
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: '/tree',
            redirect: (context, state) {
              final treeProvider = context.read<TreeProvider>();
              final redirectPath = AppRouterGuards.resolveTreeRootRedirect(
                uri: state.uri,
                treeProvider: treeProvider,
              );
              if (redirectPath != null) {
                debugPrint(
                  '[GoRouter Redirect] Redirecting tree root to $redirectPath',
                );
              }
              return redirectPath;
            },
            pageBuilder: (context, state) {
              // `?tab=invitations` deep-links from the home-feed
              // banner — pass it through so the selector scrolls
              // straight to the invitations section instead of the
              // user having to hunt for it in the list.
              final initialFocus = state.uri.queryParameters['tab'];
              return RodnyaNoTransitionPage(
                key: state.pageKey,
                child: TreeSelectorScreen(initialFocus: initialFocus),
              );
            },
            routes: [
              GoRoute(
                path: 'view/:treeId',
                pageBuilder: (context, state) {
                  final treeId = state.pathParameters['treeId'] ?? '';
                  final treeName =
                      state.uri.queryParameters['name'] ?? 'Семейное дерево';
                  return RodnyaCustomTransitionPage(
                    key: state.pageKey,
                    child: TreeViewScreen(
                      routeTreeId: treeId,
                      routeTreeName: treeName,
                    ),
                    transitionsBuilder: AppRouteTransitions.slide,
                  );
                },
              ),
            ],
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: '/chats',
            pageBuilder: (context, state) => RodnyaNoTransitionPage(
              key: state.pageKey,
              child: const ChatsListScreen(),
            ),
          ),
        ],
      ),
      StatefulShellBranch(
        routes: [
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) => RodnyaNoTransitionPage(
              key: state.pageKey,
              child: ProfileScreen(),
            ),
            routes: [
              GoRoute(
                path: 'edit',
                parentNavigatorKey: rootNavigatorKey,
                pageBuilder: (context, state) => RodnyaCustomTransitionPage(
                  key: state.pageKey,
                  constrainWidth: true,
                  child: const ProfileEditScreen(),
                  transitionsBuilder: AppRouteTransitions.slide,
                ),
              ),
              GoRoute(
                // Archive of the user's expired stories — IG / TG model.
                // Backend doesn't surface expired entries yet, so the
                // page may render an empty state until that lands.
                path: 'stories/archive',
                parentNavigatorKey: rootNavigatorKey,
                pageBuilder: (context, state) => RodnyaCustomTransitionPage(
                  key: state.pageKey,
                  constrainWidth: true,
                  child: const StoryArchiveScreen(),
                  transitionsBuilder: AppRouteTransitions.slide,
                ),
              ),
              GoRoute(
                path: 'settings',
                parentNavigatorKey: rootNavigatorKey,
                pageBuilder: (context, state) => RodnyaCustomTransitionPage(
                  key: state.pageKey,
                  constrainWidth: true,
                  child: const SettingsScreen(),
                  transitionsBuilder: AppRouteTransitions.slide,
                ),
              ),
              GoRoute(
                path: 'about',
                parentNavigatorKey: rootNavigatorKey,
                pageBuilder: (context, state) => RodnyaCustomTransitionPage(
                  key: state.pageKey,
                  constrainWidth: true,
                  child: const AboutScreen(),
                  transitionsBuilder: AppRouteTransitions.slide,
                ),
              ),
              GoRoute(
                path: 'offline_profiles',
                parentNavigatorKey: rootNavigatorKey,
                pageBuilder: (context, state) => RodnyaCustomTransitionPage(
                  key: state.pageKey,
                  constrainWidth: true,
                  child: const OfflineProfilesScreen(),
                  transitionsBuilder: AppRouteTransitions.slide,
                ),
              ),
              GoRoute(
                path: 'blocks',
                parentNavigatorKey: rootNavigatorKey,
                pageBuilder: (context, state) => RodnyaCustomTransitionPage(
                  key: state.pageKey,
                  constrainWidth: true,
                  child: const BlockedUsersScreen(),
                  transitionsBuilder: AppRouteTransitions.slide,
                ),
              ),
              GoRoute(
                path: 'sessions',
                parentNavigatorKey: rootNavigatorKey,
                pageBuilder: (context, state) => RodnyaCustomTransitionPage(
                  key: state.pageKey,
                  constrainWidth: true,
                  child: const SessionsScreen(),
                  transitionsBuilder: AppRouteTransitions.slide,
                ),
                routes: [
                  GoRoute(
                    path: 'scan',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) => RodnyaCustomTransitionPage(
                      key: state.pageKey,
                      constrainWidth: true,
                      child: const QrLoginScanScreen(),
                      transitionsBuilder: AppRouteTransitions.slideUp,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ];
  }
}

class AdaptiveNavigationRail extends StatelessWidget {
  const AdaptiveNavigationRail({
    super.key,
    required this.navigationShell,
    required this.unreadNotificationsStream,
    required this.unreadChatsStream,
    required this.pendingInvitationsCountStream,
  });

  final StatefulNavigationShell navigationShell;
  final Stream<int> unreadNotificationsStream;
  final Stream<int> unreadChatsStream;
  final Stream<int> pendingInvitationsCountStream;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: unreadNotificationsStream,
      initialData: 0,
      builder: (context, notificationsSnapshot) {
        final notificationsCount = notificationsSnapshot.data ?? 0;
        return StreamBuilder<int>(
          stream: unreadChatsStream,
          initialData: 0,
          builder: (context, chatsSnapshot) {
            final chatsCount = chatsSnapshot.data ?? 0;
            return StreamBuilder<int>(
              stream: pendingInvitationsCountStream,
              initialData: 0,
              builder: (context, invitationsSnapshot) {
                final invitationsCount = invitationsSnapshot.data ?? 0;
                final destinations = <_RailDestinationData>[
                  _RailDestinationData(
                    label: 'Лента',
                    outlinedIcon: Icons.home_outlined,
                    filledIcon: Icons.home_rounded,
                    count: notificationsCount,
                  ),
                  const _RailDestinationData(
                    label: 'Родные',
                    outlinedIcon: Icons.people_outline_rounded,
                    filledIcon: Icons.people_rounded,
                  ),
                  _RailDestinationData(
                    label: 'Дерево',
                    outlinedIcon: Icons.account_tree_outlined,
                    filledIcon: Icons.account_tree_rounded,
                    count: invitationsCount,
                  ),
                  _RailDestinationData(
                    label: 'Чаты',
                    outlinedIcon: Icons.chat_bubble_outline_rounded,
                    filledIcon: Icons.chat_bubble_rounded,
                    count: chatsCount,
                  ),
                  const _RailDestinationData(
                    label: 'Я',
                    outlinedIcon: Icons.person_outline_rounded,
                    filledIcon: Icons.person_rounded,
                  ),
                ];
                final theme = Theme.of(context);
                final isDark = theme.brightness == Brightness.dark;
                final tokens = theme.extension<RodnyaDesignTokens>() ??
                    (isDark
                        ? RodnyaDesignTokens.dark
                        : RodnyaDesignTokens.light);
                final railRadius = BorderRadius.circular(32);
                final rail = Container(
                  width: 94,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 18,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.surfaceStrong.withValues(
                      alpha: kIsWeb
                          ? (isDark ? 0.92 : 0.96)
                          : (isDark ? 0.78 : 0.82),
                    ),
                    borderRadius: railRadius,
                    border: Border.all(color: tokens.surfaceLine),
                    boxShadow:
                        tokens.panelShadow(theme.brightness, floating: true),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          gradient: tokens.accentGradient,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: tokens.accent.withValues(alpha: 0.28),
                              blurRadius: 18,
                              spreadRadius: -6,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.family_restroom,
                          color: tokens.accentInk,
                          size: 22,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            for (var index = 0;
                                index < destinations.length;
                                index++) ...[
                              _RailDestination(
                                data: destinations[index],
                                selected: navigationShell.currentIndex == index,
                                onTap: () {
                                  navigationShell.goBranch(
                                    index,
                                    initialLocation:
                                        index == navigationShell.currentIndex,
                                  );
                                },
                              ),
                              if (index != destinations.length - 1)
                                const SizedBox(height: 6),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );

                return Padding(
                  padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
                  child: ClipRRect(
                    borderRadius: railRadius,
                    child: kIsWeb
                        ? rail
                        : BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                            child: rail,
                          ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _RailDestinationData {
  const _RailDestinationData({
    required this.label,
    required this.outlinedIcon,
    required this.filledIcon,
    this.count = 0,
  });

  final String label;
  final IconData outlinedIcon;
  final IconData filledIcon;
  final int count;
}

class _RailDestination extends StatelessWidget {
  const _RailDestination({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  final _RailDestinationData data;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tokens = theme.extension<RodnyaDesignTokens>() ??
        (theme.brightness == Brightness.dark
            ? RodnyaDesignTokens.dark
            : RodnyaDesignTokens.light);
    final icon = Icon(
      selected ? data.filledIcon : data.outlinedIcon,
      size: 22,
      color: selected ? tokens.accentInk : scheme.onSurfaceVariant,
    );

    final iconWithBadge = data.count <= 0
        ? icon
        : Stack(
            clipBehavior: Clip.none,
            children: [
              icon,
              Positioned(
                top: -4,
                right: -8,
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.warm,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: selected ? tokens.accentInk : tokens.surfaceStrong,
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      data.count > 99 ? '99+' : data.count.toString(),
                      style: AppTheme.sans(
                        color: const Color(0xFF241A0D),
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

    return Semantics(
      button: true,
      selected: selected,
      label: data.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            gradient: selected ? tokens.accentGradient : null,
            borderRadius: BorderRadius.circular(24),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: tokens.accent.withValues(alpha: 0.28),
                      blurRadius: 16,
                      spreadRadius: -7,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              iconWithBadge,
              const SizedBox(height: 6),
              Text(
                data.label,
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 11,
                  height: 1.05,
                  color: selected ? tokens.accentInk : scheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
