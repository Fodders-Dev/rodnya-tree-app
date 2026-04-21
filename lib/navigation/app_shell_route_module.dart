import 'dart:ui';

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
import '../screens/chat_screen.dart';
import '../screens/chats_list_screen.dart';
import '../screens/create_post_screen.dart';
import '../screens/find_relative_screen.dart';
import '../screens/home_screen.dart';
import '../screens/offline_profiles_screen.dart';
import '../screens/profile_edit_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/relatives_screen.dart';
import '../screens/relation_requests_screen.dart';
import '../screens/send_relation_request_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/tree_selector_screen.dart';
import '../screens/tree_view_screen.dart';
import '../screens/user_profile_entry_screen.dart';
import '../services/custom_api_notification_service.dart';
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
            final isDesktop = constraints.maxWidth >= 900;
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
                path: 'post/create',
                parentNavigatorKey: rootNavigatorKey,
                pageBuilder: (context, state) => RodnyaCustomTransitionPage(
                  key: state.pageKey,
                  constrainWidth: true,
                  child: const CreatePostScreen(),
                  transitionsBuilder: AppRouteTransitions.slideUp,
                ),
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
            pageBuilder: (context, state) => RodnyaNoTransitionPage(
              key: state.pageKey,
              child: TreeSelectorScreen(),
            ),
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
                    label: 'Главная',
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
                    label: 'Профиль',
                    outlinedIcon: Icons.person_outline_rounded,
                    filledIcon: Icons.person_rounded,
                  ),
                ];
                final theme = Theme.of(context);
                final scheme = theme.colorScheme;

                return Padding(
                  padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: Container(
                        width: 94,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 18,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surface.withValues(alpha: 0.84),
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(
                            color: scheme.outlineVariant.withValues(alpha: 0.9),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: scheme.shadow.withValues(alpha: 0.1),
                              blurRadius: 34,
                              offset: const Offset(0, 18),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: scheme.primary.withValues(alpha: 0.14),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.family_restroom,
                                color: scheme.primary,
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
                                      selected:
                                          navigationShell.currentIndex == index,
                                      onTap: () {
                                        navigationShell.goBranch(
                                          index,
                                          initialLocation: index ==
                                              navigationShell.currentIndex,
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
                      ),
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
    final icon = Icon(
      selected ? data.filledIcon : data.outlinedIcon,
      size: 22,
      color: selected ? scheme.primary : scheme.onSurfaceVariant,
    );

    final iconWithBadge = data.count <= 0
        ? icon
        : Badge(
            label: Text(data.count > 99 ? '99+' : data.count.toString()),
            child: icon,
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
            color: selected
                ? scheme.primary.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
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
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
