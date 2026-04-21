import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../backend/interfaces/auth_service_interface.dart';
import '../models/family_tree.dart';
import '../screens/auth_screen.dart';
import '../screens/complete_profile_screen.dart';
import '../screens/create_story_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/family_tree/create_tree_screen.dart';
import '../screens/notifications_screen.dart';
import '../screens/password_reset_screen.dart';
import '../screens/privacy_policy_screen.dart';
import '../screens/public_tree_entry_screen.dart';
import '../screens/public_tree_viewer_screen.dart';
import '../screens/relative_details_screen.dart';
import '../screens/send_relation_request_screen.dart';
import '../screens/story_viewer_screen.dart';
import '../screens/trees_screen.dart';
import '../screens/user_profile_entry_screen.dart';
import 'app_router_shared.dart';

class AppOverlayRouteModule {
  const AppOverlayRouteModule({
    required AuthServiceInterface authService,
  }) : _authService = authService;

  final AuthServiceInterface _authService;

  List<RouteBase> build() {
    return <RouteBase>[
      GoRoute(
        path: '/notifications',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => RodnyaCustomTransitionPage(
          key: state.pageKey,
          constrainWidth: true,
          child: const NotificationsScreen(),
          transitionsBuilder: AppRouteTransitions.slide,
        ),
      ),
      GoRoute(
        path: '/stories/create',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => RodnyaCustomTransitionPage(
          key: state.pageKey,
          constrainWidth: true,
          child: const CreateStoryScreen(),
          transitionsBuilder: AppRouteTransitions.slideUp,
        ),
      ),
      GoRoute(
        path: '/stories/view/:treeId/:authorId',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final treeId = state.pathParameters['treeId']?.trim() ?? '';
          final authorId = state.pathParameters['authorId']?.trim() ?? '';
          final child = treeId.isEmpty || authorId.isEmpty
              ? const StoryViewerRouteFallback()
              : StoryViewerEntryScreen(
                  treeId: treeId,
                  authorId: authorId,
                  currentUserId: _authService.currentUserId ?? '',
                );

          if (kIsWeb) {
            return MaterialPage<void>(
              key: state.pageKey,
              child: child,
            );
          }

          return RodnyaCustomTransitionPage(
            key: state.pageKey,
            child: child,
            transitionsBuilder: AppRouteTransitions.slideUp,
          );
        },
      ),
      GoRoute(
        path: '/trees',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => RodnyaCustomTransitionPage(
          key: state.pageKey,
          constrainWidth: true,
          child: TreesScreen(
            initialTab: state.uri.queryParameters['tab'],
          ),
          transitionsBuilder: AppRouteTransitions.slide,
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
              return RodnyaCustomTransitionPage(
                key: state.pageKey,
                constrainWidth: true,
                child: CreateTreeScreen(initialKind: initialKind),
                transitionsBuilder: AppRouteTransitions.slide,
              );
            },
          ),
        ],
      ),
      GoRoute(
        path: '/__e2e__/idle',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => RodnyaCustomTransitionPage(
          key: state.pageKey,
          child: const E2EIdleScreen(),
          transitionsBuilder: AppRouteTransitions.fade,
        ),
      ),
      GoRoute(
        path: '/login',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final redirectAfterLogin = state.uri.queryParameters['from']?.trim();
          return RodnyaCustomTransitionPage(
            key: state.pageKey,
            child: AuthScreen(
              redirectAfterLogin:
                  redirectAfterLogin != null && redirectAfterLogin.isNotEmpty
                      ? redirectAfterLogin
                      : null,
            ),
            transitionsBuilder: AppRouteTransitions.fade,
          );
        },
      ),
      GoRoute(
        path: '/password_reset',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => RodnyaCustomTransitionPage(
          key: state.pageKey,
          child: const PasswordResetScreen(),
          transitionsBuilder: AppRouteTransitions.fade,
        ),
      ),
      GoRoute(
        path: '/complete_profile',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final queryParams = state.uri.queryParameters;
          Map<String, bool> requiredFields = <String, bool>{};
          final fieldsString = queryParams['requiredFields'];
          if (fieldsString != null) {
            try {
              final pairs =
                  fieldsString.replaceAll(RegExp(r'[{}]'), '').split(', ');
              for (final pair in pairs) {
                final parts = pair.split(': ');
                if (parts.length == 2) {
                  requiredFields[parts[0]] = parts[1] == 'true';
                }
              }
            } catch (error) {
              debugPrint('Error parsing requiredFields query param: $error');
              requiredFields = <String, bool>{
                'hasPhoneNumber': false,
                'hasGender': false,
                'hasUsername': false,
                'isComplete': false,
              };
            }
          } else {
            requiredFields = state.extra as Map<String, bool>? ??
                <String, bool>{
                  'hasPhoneNumber': false,
                  'hasGender': false,
                  'hasUsername': false,
                  'isComplete': false,
                };
          }

          return RodnyaCustomTransitionPage(
            key: state.pageKey,
            constrainWidth: true,
            child: CompleteProfileScreen(requiredFields: requiredFields),
            transitionsBuilder: AppRouteTransitions.fade,
          );
        },
      ),
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

          return RodnyaCustomTransitionPage(
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
            transitionsBuilder: AppRouteTransitions.slide,
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
          final relativeId = state.uri.queryParameters['relativeId'] ?? '';

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
              photoUrl:
                  photoUrl != null && photoUrl.isNotEmpty ? photoUrl : null,
              relativeId: relativeId,
              chatType: 'direct',
            ),
            transitionsBuilder: AppRouteTransitions.slide,
          );
        },
      ),
      GoRoute(
        path: '/user/:userId',
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
      GoRoute(
        path: '/send_relation_request',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final treeId = state.uri.queryParameters['treeId'] ??
              state.uri.queryParameters['userId'] ??
              '';
          return RodnyaCustomTransitionPage(
            key: state.pageKey,
            constrainWidth: true,
            child: SendRelationRequestScreen(treeId: treeId),
            transitionsBuilder: AppRouteTransitions.slide,
          );
        },
      ),
      GoRoute(
        path: '/privacy',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => RodnyaCustomTransitionPage(
          key: state.pageKey,
          constrainWidth: true,
          child: const PrivacyPolicyScreen(),
          transitionsBuilder: AppRouteTransitions.slide,
        ),
      ),
      GoRoute(
        path: '/terms',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => RodnyaCustomTransitionPage(
          key: state.pageKey,
          constrainWidth: true,
          child: const TermsOfUseScreen(),
          transitionsBuilder: AppRouteTransitions.slide,
        ),
      ),
      GoRoute(
        path: '/support',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => RodnyaCustomTransitionPage(
          key: state.pageKey,
          constrainWidth: true,
          child: const SupportScreen(),
          transitionsBuilder: AppRouteTransitions.slide,
        ),
      ),
      GoRoute(
        path: '/account-deletion',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => RodnyaCustomTransitionPage(
          key: state.pageKey,
          constrainWidth: true,
          child: const AccountDeletionInfoScreen(),
          transitionsBuilder: AppRouteTransitions.slide,
        ),
      ),
      GoRoute(
        path: '/invite',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => RodnyaCustomTransitionPage(
          key: state.pageKey,
          child: const SizedBox.shrink(),
          transitionsBuilder: AppRouteTransitions.fade,
        ),
      ),
      GoRoute(
        path: '/public/tree/:publicTreeId',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final publicTreeId = state.pathParameters['publicTreeId'] ?? '';
          return RodnyaCustomTransitionPage(
            key: state.pageKey,
            child: PublicTreeEntryScreen(publicTreeId: publicTreeId),
            transitionsBuilder: AppRouteTransitions.slide,
          );
        },
      ),
      GoRoute(
        path: '/public/tree/:publicTreeId/view',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final publicTreeId = state.pathParameters['publicTreeId'] ?? '';
          return RodnyaCustomTransitionPage(
            key: state.pageKey,
            child: PublicTreeViewerScreen(publicTreeId: publicTreeId),
            transitionsBuilder: AppRouteTransitions.slide,
          );
        },
      ),
      GoRoute(
        path: '/relative/details/:personId',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final personId = state.pathParameters['personId'] ?? '';
          final initialAction = state.uri.queryParameters['action'];
          if (personId.isEmpty) {
            return MaterialPage<void>(
              key: state.pageKey,
              child: const Scaffold(
                body: Center(
                  child: Text('Ошибка: ID родственника не указан'),
                ),
              ),
            );
          }
          return RodnyaCustomTransitionPage(
            key: ValueKey<String>('relative_details_$personId'),
            child: RelativeDetailsScreen(
              personId: personId,
              initialAction: initialAction,
            ),
            transitionsBuilder: AppRouteTransitions.slide,
          );
        },
      ),
    ];
  }

  Page<void> buildErrorPage(BuildContext context, GoRouterState state) {
    return MaterialPage<void>(
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
    );
  }
}
