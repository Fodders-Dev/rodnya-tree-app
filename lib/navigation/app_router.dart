import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../utils/url_utils.dart';

import '../screens/home_screen.dart';
import '../screens/auth_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/profile_edit_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/about_screen.dart';
import '../screens/password_reset_screen.dart';
import '../screens/complete_profile_screen.dart';
import '../screens/relatives_screen.dart';
import '../screens/trees_screen.dart';
import '../screens/chats_list_screen.dart';
import '../screens/tree_view_screen.dart';
import '../screens/tree_selector_screen.dart';
import '../screens/add_relative_screen.dart';
import '../screens/find_relative_screen.dart';
import '../screens/relation_requests_screen.dart';
import '../screens/send_relation_request_screen.dart';
import '../screens/create_post_screen.dart';
import '../screens/create_story_screen.dart';
import '../screens/story_viewer_screen.dart';
import '../screens/family_tree/create_tree_screen.dart';
import '../screens/chat_screen.dart';
import '../widgets/offline_indicator.dart';
import '../widgets/main_navigation_bar.dart';
import '../widgets/app_backdrop.dart';
import '../screens/offline_profiles_screen.dart';
import '../screens/public_tree_entry_screen.dart';
import '../screens/public_tree_viewer_screen.dart';
import '../screens/relative_details_screen.dart';
import '../screens/user_profile_entry_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/blocked_users_screen.dart';
import '../models/family_person.dart';
import '../models/family_tree.dart';
import '../screens/privacy_policy_screen.dart';
import '../providers/tree_provider.dart';
import 'package:provider/provider.dart';
import 'package:get_it/get_it.dart';
import '../backend/interfaces/auth_service_interface.dart';
import '../backend/interfaces/chat_service_interface.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/backend_runtime_config.dart';
import '../services/invitation_service.dart';
import '../services/custom_api_notification_service.dart';

// Ключ для корневого навигатора
final rootNavigatorKey = GlobalKey<NavigatorState>();
// Ключи для навигаторов внутри вкладок (опционально, для сохранения состояния глубже)
// final _shellNavigatorHomeKey = GlobalKey<NavigatorState>(debugLabel: 'shellHome');
// final _shellNavigatorRelativesKey = GlobalKey<NavigatorState>(debugLabel: 'shellRelatives');
// final _shellNavigatorTreeKey = GlobalKey<NavigatorState>(debugLabel: 'shellTree');
// final _shellNavigatorTreesKey = GlobalKey<NavigatorState>(debugLabel: 'shellTrees');
// final _shellNavigatorProfileKey = GlobalKey<NavigatorState>(debugLabel: 'shellProfile');

// --- Классы страниц GoRouter ---

Widget _buildDesktopConstrainedScreen(Widget child) {
  return Builder(
    builder: (context) => Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: 1200), // Increased from 700
          child: ClipRect(child: child),
        ),
      ),
    ),
  );
}

// Базовый класс для кастомных переходов, наследуемся от пакета go_router
class LineageCustomTransitionPage<T> extends CustomTransitionPage<T> {
  LineageCustomTransitionPage({
    required Widget child,
    required super.transitionsBuilder,
    bool constrainWidth = false,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
    super.transitionDuration = const Duration(milliseconds: 300),
    super.reverseTransitionDuration = const Duration(milliseconds: 300),
    // maintainState убран
  }) : super(
          child: constrainWidth ? _buildDesktopConstrainedScreen(child) : child,
          maintainState: true,
        ); // ВОЗВРАЩАЕМ maintainState, он важен для ShellRoute!
}

// Страница без анимации для вкладок ShellRoute
class NoTransitionPage<T> extends LineageCustomTransitionPage<T> {
  NoTransitionPage({required super.child, super.key})
      : super(
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              child,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        );
}

class AuthState extends ChangeNotifier {
  final AuthServiceInterface _authService;
  late final StreamSubscription<String?> _subscription;

  AuthState(this._authService) {
    _subscription = _authService.authStateChanges.listen((_) {
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

class AppRouter {
  final AuthServiceInterface _authService = GetIt.I<AuthServiceInterface>();
  late final authState = AuthState(_authService);

  static String buildLoginRedirectTarget(GoRouterState state) {
    final location = state.uri.toString();
    return '/login?from=${Uri.encodeComponent(location)}';
  }

  static String? restoreDeferredLoginTarget(GoRouterState state) {
    final from = state.uri.queryParameters['from'];
    if (from == null || from.isEmpty) {
      return null;
    }

    final restored = Uri.decodeComponent(from);
    if (restored.isEmpty || restored == '/login') {
      return null;
    }
    return restored;
  }

  static String? resolveTreeRootRedirect({
    required Uri uri,
    required TreeProvider treeProvider,
  }) {
    final forceSelector = uri.queryParameters['selector'] == '1';
    if (forceSelector || uri.path.startsWith('/tree/view')) {
      return null;
    }

    final selectedTreeId = treeProvider.selectedTreeId;
    if (selectedTreeId == null) {
      return null;
    }

    final nameParam = treeProvider.selectedTreeName != null
        ? '?name=${Uri.encodeComponent(treeProvider.selectedTreeName!)}'
        : '';
    return '/tree/view/$selectedTreeId$nameParam';
  }

  late final GoRouter router = GoRouter(
    navigatorKey: rootNavigatorKey,
    debugLogDiagnostics: kDebugMode,
    initialLocation: '/',
    refreshListenable: authState,

    // Обработчик редиректа для аутентификации
    redirect: (context, state) async {
      final isLoggedIn = _authService.currentUserId != null;
      final loggingInPages = [
        '/login',
        '/password_reset',
        '/privacy',
        '/terms',
        '/support',
        '/account-deletion',
      ];
      final isLoggingIn = loggingInPages.contains(state.matchedLocation);
      final completingProfile = state.matchedLocation == '/complete_profile';
      final invitePage = state.matchedLocation == '/invite';
      final publicTreePage = state.matchedLocation.startsWith('/public/tree/');
      final e2eIdlePage = state.matchedLocation == '/__e2e__/idle';

      if (e2eIdlePage && BackendRuntimeConfig.current.enableE2e) {
        return null;
      }

      if (invitePage) {
        final treeId = state.uri.queryParameters['treeId'];
        final personId = state.uri.queryParameters['personId'];
        if (treeId != null &&
            treeId.isNotEmpty &&
            personId != null &&
            personId.isNotEmpty) {
          GetIt.I<InvitationService>().setPendingInvitation(
            treeId: treeId,
            personId: personId,
          );
          if (isLoggedIn) {
            await _authService.processPendingInvitation();
            return '/';
          }
          return '/login';
        }
        return isLoggedIn ? '/' : '/login';
      }

      if (publicTreePage) {
        return null;
      }

      // Если не залогинен и не на странице входа/сброса/завершения профиля/политики -> на /login
      if (!isLoggedIn && !isLoggingIn && !completingProfile) {
        return buildLoginRedirectTarget(state);
      }

      // Если залогинен и на странице входа -> на /
      if (isLoggedIn && isLoggingIn) {
        final deferredTarget = restoreDeferredLoginTarget(state);
        final target = deferredTarget ?? '/';
        return target;
      }

      // Если залогинен, но профиль не заполнен и не на странице заполнения -> на /complete_profile
      if (isLoggedIn && !completingProfile) {
        try {
          final profileStatus = await _authService.checkProfileCompleteness();
          if (_authService.currentUserId == null) {
            return buildLoginRedirectTarget(state);
          }
          final isComplete = profileStatus['isComplete'] == true;
          if (!isComplete) {
            return '/complete_profile?requiredFields=${Uri.encodeComponent(profileStatus.toString())}'; // Кодируем параметры
          }
        } catch (e) {
          debugPrint('Error checking profile completeness during redirect: $e');
          final normalizedError = e.toString().toLowerCase();
          final looksLikeSessionIssue = _authService.currentUserId == null ||
              normalizedError.contains('null check operator') ||
              normalizedError.contains('session') ||
              normalizedError.contains('сесс') ||
              normalizedError.contains('401') ||
              normalizedError.contains('403');
          if (looksLikeSessionIssue) {
            return buildLoginRedirectTarget(state);
          }
        }
      }
      return null; // Нет редиректа
    },

    routes: [
      // Основной каркас приложения с адаптивной навигацией
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          final currentUserId = GetIt.I<AuthServiceInterface>().currentUserId;
          final unreadNotificationsStream =
              GetIt.I.isRegistered<CustomApiNotificationService>()
                  ? GetIt.I<CustomApiNotificationService>()
                      .unreadNotificationsCountStream
                  : Stream.value(0);
          final unreadChatsStream = currentUserId != null
              ? GetIt.I<ChatServiceInterface>()
                  .getTotalUnreadCountStream(currentUserId)
              : Stream.value(0);
          final pendingInvitationsCountStream = currentUserId != null
              ? GetIt.I<FamilyTreeServiceInterface>()
                  .getPendingTreeInvitations()
                  .map((invitations) => invitations.length)
              : Stream.value(0);

          return LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth >= 900;
              final isTreeBranch =
                  navigationShell.currentIndex == 2; // Tree is branch 2

              // Вспомогательный виджет для контента
              Widget bodyContent = Column(
                children: <Widget>[
                  OfflineIndicator(),
                  Expanded(child: navigationShell),
                ],
              );

              // Если десктоп -> добавляем ограничение ширины контента и центрируем
              if (isDesktop) {
                bodyContent = Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth:
                          isTreeBranch ? double.infinity : 1400, // Fluid tree
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
                          _AdaptiveNavigationRail(
                            navigationShell: navigationShell,
                            unreadNotificationsStream:
                                unreadNotificationsStream,
                            unreadChatsStream: unreadChatsStream,
                            pendingInvitationsCountStream:
                                pendingInvitationsCountStream,
                          ),
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(10, 16, 18, 16),
                              child: bodyContent,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              } else {
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
                    pendingInvitationsCountStream:
                        pendingInvitationsCountStream,
                  ),
                );
              }
            },
          );
        },
        branches: [
          // Ветка 1: Главная
          StatefulShellBranch(
            // navigatorKey: _shellNavigatorHomeKey,
            routes: [
              GoRoute(
                path: '/',
                pageBuilder: (context, state) =>
                    NoTransitionPage(key: state.pageKey, child: HomeScreen()),
                routes: [
                  // <<< Добавляем маршрут для создания поста >>>
                  GoRoute(
                    path: 'post/create', // Относительный путь от '/'
                    // Открываем поверх основного экрана, используя rootNavigatorKey
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) =>
                        LineageCustomTransitionPage(
                      key: state
                          .pageKey, // Используем ключ для уникальности страницы
                      constrainWidth: true,
                      child: const CreatePostScreen(),
                      // Анимация "слайд снизу вверх" для модального эффекта
                      transitionsBuilder: slideUpTransition,
                    ),
                  ),
                  // ================================================
                  GoRoute(
                    path: 'user/:userId',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) {
                      final userId = state.pathParameters['userId'] ?? '';
                      return LineageCustomTransitionPage(
                        key: state.pageKey,
                        constrainWidth: true,
                        child: UserProfileEntryScreen(userId: userId),
                        transitionsBuilder: slideTransition,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),

          // Ветка 2: Родные
          StatefulShellBranch(
            // navigatorKey: _shellNavigatorRelativesKey,
            routes: [
              GoRoute(
                path: '/relatives',
                pageBuilder: (context, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: RelativesScreen(),
                ),
                routes: [
                  // Добавление родственника (открывается поверх)
                  GoRoute(
                    path: 'add/:treeId',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) {
                      final treeId = state.pathParameters['treeId'] ?? '';
                      final extra = state.extra;
                      final quickAddMode = extra is Map<String, dynamic> &&
                          extra['quickAddMode'] == true;
                      return LineageCustomTransitionPage(
                        key: state.pageKey,
                        constrainWidth: true,
                        child: AddRelativeScreen(
                          treeId: treeId,
                          quickAddMode: quickAddMode,
                          routeExtra:
                              extra is Map<String, dynamic> ? extra : null,
                          routeQueryParameters: state.uri.queryParameters,
                        ),
                        transitionsBuilder: slideTransition,
                      );
                    },
                  ),
                  // Маршрут для РЕДАКТИРОВАНИЯ родственника
                  GoRoute(
                    path: 'edit/:treeId/:personId',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) {
                      final treeId = state.pathParameters['treeId'] ?? '';
                      final personId = state.pathParameters['personId'] ?? '';
                      final personToEdit = state.extra as FamilyPerson?;

                      if (treeId.isEmpty || personId.isEmpty) {
                        return MaterialPage(
                          child: Scaffold(
                            body: Center(
                              child: Text(
                                'Ошибка: Не указан ID дерева или родственника для редактирования.',
                              ),
                            ),
                          ),
                        );
                      }

                      return LineageCustomTransitionPage(
                        key: ValueKey('edit_relative_$personId'),
                        constrainWidth: true,
                        child: AddRelativeScreen(
                          treeId: treeId,
                          person: personToEdit,
                          isEditing: true,
                        ),
                        transitionsBuilder: slideTransition,
                      );
                    },
                  ),
                  // Просмотр запросов (открывается поверх)
                  GoRoute(
                    path: 'requests/:treeId',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) {
                      final treeId = state.pathParameters['treeId'] ?? '';
                      return LineageCustomTransitionPage(
                        key: state.pageKey,
                        constrainWidth: true,
                        child: RelationRequestsScreen(treeId: treeId),
                        transitionsBuilder: slideTransition,
                      );
                    },
                  ),
                  GoRoute(
                    path: 'find/:treeId',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) {
                      final treeId = state.pathParameters['treeId'] ?? '';
                      return LineageCustomTransitionPage(
                        key: state.pageKey,
                        constrainWidth: true,
                        child: FindRelativeScreen(treeId: treeId),
                        transitionsBuilder: slideTransition,
                      );
                    },
                  ),
                  // Отправка запроса на родство (открывается поверх)
                  GoRoute(
                    path: 'send_request/:treeId',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) {
                      final treeId = state.pathParameters['treeId'] ?? '';
                      return LineageCustomTransitionPage(
                        key: state.pageKey,
                        constrainWidth: true,
                        child: SendRelationRequestScreen(treeId: treeId),
                        transitionsBuilder: slideTransition,
                      );
                    },
                  ),
                  // Переход в чат с пользователем
                  GoRoute(
                    path: 'chat/:userId',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) {
                      final userId = state.pathParameters['userId'] ?? '';
                      final name =
                          state.uri.queryParameters['name'] ?? 'Пользователь';
                      final photoUrl = state.uri.queryParameters['photo'];
                      final relativeId =
                          state.uri.queryParameters['relativeId'] ??
                              ''; // <-- ИЗВЛЕКАЕМ relativeId

                      // --- Добавим проверку на наличие relativeId ---
                      if (relativeId.isEmpty) {
                        debugPrint('Error: Missing relativeId for chat route');
                        // Можно вернуть страницу с ошибкой или перенаправить
                        return MaterialPage(
                          key: state.pageKey,
                          child: Scaffold(
                            appBar: AppBar(title: Text('Ошибка')),
                            body: Center(
                              child: Text(
                                'Не найден ID родственника для чата.',
                              ),
                            ),
                          ),
                        );
                      }
                      // -----------------------------------------------

                      return LineageCustomTransitionPage(
                        key: state.pageKey,
                        constrainWidth: true,
                        child: ChatScreen(
                          otherUserId: userId,
                          title: name,
                          photoUrl: UrlUtils.normalizeImageUrl(photoUrl),
                          relativeId: relativeId,
                          chatType: 'direct',
                        ),
                        transitionsBuilder: slideTransition,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),

          // Ветка 3: Дерево (Центральная кнопка)
          StatefulShellBranch(
            // navigatorKey: _shellNavigatorTreeKey,
            routes: [
              GoRoute(
                path: '/tree',
                redirect: (context, state) {
                  final treeProvider = context.read<TreeProvider>();
                  final redirectPath = resolveTreeRootRedirect(
                    uri: state.uri,
                    treeProvider: treeProvider,
                  );
                  if (redirectPath != null) {
                    debugPrint(
                      '[GoRouter Redirect] Redirecting tree root to $redirectPath',
                    );
                    return redirectPath;
                  }
                  return null;
                },
                pageBuilder: (context, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: TreeSelectorScreen(),
                ),
                routes: [
                  // Просмотр конкретного дерева (открывается поверх)
                  GoRoute(
                    path: 'view/:treeId',
                    pageBuilder: (context, state) {
                      // treeId из pathParameters, name из queryParameters
                      final treeId = state.pathParameters['treeId'] ?? '';
                      final treeName = state.uri.queryParameters['name'] ??
                          'Семейное дерево';
                      return LineageCustomTransitionPage(
                        key: state.pageKey,
                        child: TreeViewScreen(
                          routeTreeId: treeId,
                          routeTreeName: treeName,
                        ),
                        transitionsBuilder: slideTransition,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),

          // Ветка 4: Чаты
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/chats',
                pageBuilder: (context, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: const ChatsListScreen(),
                ),
              ),
            ],
          ),

          // Ветка 5: Профиль
          StatefulShellBranch(
            // navigatorKey: _shellNavigatorProfileKey,
            routes: [
              GoRoute(
                path: '/profile',
                pageBuilder: (context, state) => NoTransitionPage(
                  key: state.pageKey,
                  child: ProfileScreen(),
                ),
                routes: [
                  GoRoute(
                    path: 'edit',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) =>
                        LineageCustomTransitionPage(
                      key: state.pageKey,
                      constrainWidth: true,
                      child: const ProfileEditScreen(),
                      transitionsBuilder: slideTransition,
                    ),
                  ),
                  GoRoute(
                    path: 'settings',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) =>
                        LineageCustomTransitionPage(
                      key: state.pageKey,
                      constrainWidth: true,
                      child: const SettingsScreen(),
                      transitionsBuilder: slideTransition,
                    ),
                  ),
                  GoRoute(
                    path: 'about',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) =>
                        LineageCustomTransitionPage(
                      key: state.pageKey,
                      constrainWidth: true,
                      child: const AboutScreen(),
                      transitionsBuilder: slideTransition,
                    ),
                  ),
                  GoRoute(
                    path: 'offline_profiles',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) =>
                        LineageCustomTransitionPage(
                      key: state.pageKey,
                      constrainWidth: true,
                      child: const OfflineProfilesScreen(),
                      transitionsBuilder: slideTransition,
                    ),
                  ),
                  GoRoute(
                    path: 'blocks',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) =>
                        LineageCustomTransitionPage(
                      key: state.pageKey,
                      constrainWidth: true,
                      child: const BlockedUsersScreen(),
                      transitionsBuilder: slideTransition,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      // --- Маршруты вне основного Shell (доступны без BottomNavigationBar) ---

      // Деревья (перенесено из вкладки в отдельный маршрут)
      GoRoute(
        path: '/notifications',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => LineageCustomTransitionPage(
          key: state.pageKey,
          constrainWidth: true,
          child: const NotificationsScreen(),
          transitionsBuilder: slideTransition,
        ),
      ),
      GoRoute(
        path: '/stories/create',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => LineageCustomTransitionPage(
          key: state.pageKey,
          constrainWidth: true,
          child: const CreateStoryScreen(),
          transitionsBuilder: slideUpTransition,
        ),
      ),
      GoRoute(
        path: '/stories/view/:treeId/:authorId',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final treeId = state.pathParameters['treeId']?.trim() ?? '';
          final authorId = state.pathParameters['authorId']?.trim() ?? '';
          final child = treeId.isEmpty || authorId.isEmpty
              ? const _StoryViewerRouteFallback()
              : StoryViewerEntryScreen(
                  treeId: treeId,
                  authorId: authorId,
                  currentUserId: _authService.currentUserId ?? '',
                );

          if (kIsWeb) {
            return MaterialPage(
              key: state.pageKey,
              child: child,
            );
          }

          return LineageCustomTransitionPage(
            key: state.pageKey,
            child: child,
            transitionsBuilder: slideUpTransition,
          );
        },
      ),
      GoRoute(
        path: '/trees',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => LineageCustomTransitionPage(
          key: state.pageKey,
          constrainWidth: true,
          child: TreesScreen(
            initialTab: state.uri.queryParameters['tab'],
          ),
          transitionsBuilder: slideTransition,
        ),
        routes: [
          GoRoute(
            path: 'create',
            parentNavigatorKey: rootNavigatorKey,
            pageBuilder: (context, state) {
              final kindParam = state.uri.queryParameters['kind'];
              final initialKind = kindParam?.toLowerCase() == 'friends'
                  ? TreeKind.friends
                  : TreeKind.family;
              return LineageCustomTransitionPage(
                key: state.pageKey,
                constrainWidth: true,
                child: CreateTreeScreen(initialKind: initialKind),
                transitionsBuilder: slideTransition,
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: '/__e2e__/idle',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => LineageCustomTransitionPage(
          key: state.pageKey,
          child: const _E2EIdleScreen(),
          transitionsBuilder: fadeTransition,
        ),
      ),
      GoRoute(
        path: '/login',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final redirectAfterLogin = state.uri.queryParameters['from']?.trim();
          return LineageCustomTransitionPage(
            key: state.pageKey,
            child: AuthScreen(
              redirectAfterLogin:
                  redirectAfterLogin != null && redirectAfterLogin.isNotEmpty
                      ? redirectAfterLogin
                      : null,
            ),
            transitionsBuilder: fadeTransition,
          );
        },
      ),
      GoRoute(
        path: '/password_reset',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => LineageCustomTransitionPage(
          key: state.pageKey,
          child: const PasswordResetScreen(),
          transitionsBuilder: fadeTransition,
        ),
      ),
      GoRoute(
        path: '/complete_profile',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final queryParams = state.uri.queryParameters;
          Map<String, bool> requiredFields = {};
          // Пытаемся распарсить из строки, если она есть
          final fieldsString = queryParams['requiredFields'];
          if (fieldsString != null) {
            try {
              // Убираем {} и разбиваем на пары ключ-значение
              final pairs =
                  fieldsString.replaceAll(RegExp(r'[{}]'), '').split(', ');
              for (var pair in pairs) {
                final parts = pair.split(': ');
                if (parts.length == 2) {
                  requiredFields[parts[0]] = parts[1] == 'true';
                }
              }
            } catch (e) {
              debugPrint('Error parsing requiredFields query param: $e');
              requiredFields = {
                'hasPhoneNumber': false,
                'hasGender': false,
                'hasUsername': false,
                'isComplete': false,
              };
            }
          } else {
            requiredFields = state.extra as Map<String, bool>? ??
                {
                  'hasPhoneNumber': false,
                  'hasGender': false,
                  'hasUsername': false,
                  'isComplete': false,
                };
          }

          return LineageCustomTransitionPage(
            key: state.pageKey,
            constrainWidth: true,
            child: CompleteProfileScreen(requiredFields: requiredFields),
            transitionsBuilder: fadeTransition,
          );
        },
      ),
      // Маршрут чата ВНЕ оболочки (дублирует тот, что внутри ветки /relatives)
      // Оставляем его для возможности перехода в чат из других мест (уведомления и т.д.)
      GoRoute(
        path: '/chats/view/:chatId',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final chatId = state.pathParameters['chatId'] ?? '';
          final title = state.uri.queryParameters['title'] ?? 'Чат';
          final photoUrl = state.uri.queryParameters['photo'];
          final otherUserId = state.uri.queryParameters['userId'];
          final relativeId = state.uri.queryParameters['relativeId'];
          final chatType = state.uri.queryParameters['type'] ?? 'direct';

          return LineageCustomTransitionPage(
            key: state.pageKey,
            constrainWidth: true,
            child: ChatScreen(
              chatId: chatId,
              otherUserId: otherUserId,
              title: title,
              photoUrl:
                  photoUrl != null && photoUrl.isNotEmpty ? photoUrl : null,
              relativeId: relativeId != null && relativeId.isNotEmpty
                  ? relativeId
                  : null,
              chatType: chatType,
            ),
            transitionsBuilder: slideTransition,
          );
        },
      ),
      GoRoute(
        path: '/chat/:userId',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final userId = state.pathParameters['userId'] ?? '';
          final name = state.uri.queryParameters['name'] ?? 'Пользователь';
          final photoUrl = state.uri.queryParameters['photo'];
          final relativeId = state.uri.queryParameters['relativeId'] ??
              ''; // <-- ИЗВЛЕКАЕМ relativeId

          if (relativeId.isEmpty) {
            debugPrint('Error: Missing relativeId for chat route');
            return MaterialPage(
              key: state.pageKey,
              child: Scaffold(
                appBar: AppBar(title: Text('Ошибка')),
                body: Center(
                  child: Text('Не найден ID родственника для чата.'),
                ),
              ),
            );
          }

          return LineageCustomTransitionPage(
            key: state.pageKey,
            constrainWidth: true,
            child: ChatScreen(
              otherUserId: userId,
              title: name,
              photoUrl:
                  photoUrl != null && photoUrl.isNotEmpty ? photoUrl : null,
              relativeId: relativeId,
              chatType: 'direct',
            ),
            transitionsBuilder: slideTransition,
          );
        },
      ),
      GoRoute(
        path: '/user/:userId',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final userId = state.pathParameters['userId'] ?? '';
          return LineageCustomTransitionPage(
            key: state.pageKey,
            constrainWidth: true,
            child: UserProfileEntryScreen(userId: userId),
            transitionsBuilder: slideTransition,
          );
        },
      ),
      GoRoute(
        path: '/send_relation_request',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final treeId = state.uri.queryParameters['treeId'] ??
              state.uri.queryParameters['userId'] ??
              '';
          return LineageCustomTransitionPage(
            key: state.pageKey,
            constrainWidth: true,
            child: SendRelationRequestScreen(treeId: treeId),
            transitionsBuilder: slideTransition,
          );
        },
      ),
      // --- Добавляем маршрут для Политики конфиденциальности ---
      GoRoute(
        path: '/privacy',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => LineageCustomTransitionPage(
          key: state.pageKey,
          constrainWidth: true,
          child: const PrivacyPolicyScreen(),
          transitionsBuilder: slideTransition,
        ),
      ),
      GoRoute(
        path: '/terms',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => LineageCustomTransitionPage(
          key: state.pageKey,
          constrainWidth: true,
          child: const TermsOfUseScreen(),
          transitionsBuilder: slideTransition,
        ),
      ),
      GoRoute(
        path: '/support',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => LineageCustomTransitionPage(
          key: state.pageKey,
          constrainWidth: true,
          child: const SupportScreen(),
          transitionsBuilder: slideTransition,
        ),
      ),
      GoRoute(
        path: '/account-deletion',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => LineageCustomTransitionPage(
          key: state.pageKey,
          constrainWidth: true,
          child: const AccountDeletionInfoScreen(),
          transitionsBuilder: slideTransition,
        ),
      ),
      GoRoute(
        path: '/invite',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => LineageCustomTransitionPage(
          key: state.pageKey,
          child: const SizedBox.shrink(),
          transitionsBuilder: fadeTransition,
        ),
      ),
      GoRoute(
        path: '/public/tree/:publicTreeId',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final publicTreeId = state.pathParameters['publicTreeId'] ?? '';
          return LineageCustomTransitionPage(
            key: state.pageKey,
            child: PublicTreeEntryScreen(publicTreeId: publicTreeId),
            transitionsBuilder: slideTransition,
          );
        },
      ),
      GoRoute(
        path: '/public/tree/:publicTreeId/view',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final publicTreeId = state.pathParameters['publicTreeId'] ?? '';
          return LineageCustomTransitionPage(
            key: state.pageKey,
            child: PublicTreeViewerScreen(publicTreeId: publicTreeId),
            transitionsBuilder: slideTransition,
          );
        },
      ),
      // --- Общие маршруты, доступные из разных веток ---
      GoRoute(
        path: '/relative/details/:personId',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final personId = state.pathParameters['personId'] ?? '';
          if (personId.isEmpty) {
            return MaterialPage(
              key: state.pageKey,
              child: Scaffold(
                body: Center(child: Text('Ошибка: ID родственника не указан')),
              ),
            );
          }
          return LineageCustomTransitionPage(
            key: ValueKey('relative_details_$personId'),
            child: RelativeDetailsScreen(personId: personId),
            transitionsBuilder: slideTransition,
          );
        },
      ),
    ],

    // Обработчик ошибок
    errorPageBuilder: (context, state) => MaterialPage(
      key: state.pageKey,
      child: Scaffold(
        appBar: AppBar(title: const Text('Страница не найдена')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Ошибка 404: Страница не найдена\n${state.error}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/'),
                child: const Text('Вернуться на главную'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  // Функции анимации переходов
  static Widget fadeTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(opacity: animation, child: child);
  }

  static Widget slideTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    const begin = Offset(1.0, 0.0);
    const end = Offset.zero;
    const curve = Curves.easeInOut;

    var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
    var offsetAnimation = animation.drive(tween);

    return SlideTransition(position: offsetAnimation, child: child);
  }

  static Widget slideUpTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    const begin = Offset(0.0, 1.0);
    const end = Offset.zero;
    const curve = Curves.easeInOut;

    var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
    var offsetAnimation = animation.drive(tween);

    return SlideTransition(position: offsetAnimation, child: child);
  }
}

class _E2EIdleScreen extends StatelessWidget {
  const _E2EIdleScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SizedBox.expand(),
    );
  }
}

class _StoryViewerRouteFallback extends StatelessWidget {
  const _StoryViewerRouteFallback();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text(
          'История недоступна',
          style: theme.textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _AdaptiveNavigationRail extends StatelessWidget {
  const _AdaptiveNavigationRail({
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
