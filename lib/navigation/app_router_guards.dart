import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../backend/backend_runtime_config.dart';
import '../backend/interfaces/auth_service_interface.dart';
import '../providers/tree_provider.dart';
import '../services/invitation_service.dart';

class AppRouterGuards {
  AppRouterGuards({
    required AuthServiceInterface authService,
    required InvitationService invitationService,
  })  : _authService = authService,
        _invitationService = invitationService;

  final AuthServiceInterface _authService;
  final InvitationService _invitationService;

  static const Set<String> authEntryPages = <String>{
    '/login',
    '/password_reset',
  };

  static const Set<String> publicInfoPages = <String>{
    '/privacy',
    '/terms',
    '/support',
    '/account-deletion',
  };

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

  static bool isAuthEntryPage(String matchedLocation) =>
      authEntryPages.contains(matchedLocation);

  static bool isPublicInfoPage(String matchedLocation) =>
      publicInfoPages.contains(matchedLocation);

  static bool allowsAnonymousAccess(String matchedLocation) =>
      isAuthEntryPage(matchedLocation) || isPublicInfoPage(matchedLocation);

  static bool hasTelegramAuthPayload(Uri uri) =>
      uri.queryParameters.containsKey('telegramAuthCode') ||
      uri.queryParameters.containsKey('telegramAuthError');

  static bool hasVkAuthPayload(Uri uri) =>
      uri.queryParameters.containsKey('vkAuthCode') ||
      uri.queryParameters.containsKey('vkAuthError');

  static bool hasSocialAuthPayload(Uri uri) =>
      hasTelegramAuthPayload(uri) || hasVkAuthPayload(uri);

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

  Future<String?> redirect(BuildContext context, GoRouterState state) async {
    final isLoggedIn = _authService.currentUserId != null;
    final isAuthEntryRoute = isAuthEntryPage(state.matchedLocation);
    final completingProfile = state.matchedLocation == '/complete_profile';
    final invitePage = state.matchedLocation == '/invite';
    final publicTreePage = state.matchedLocation.startsWith('/public/tree/');
    final e2eIdlePage = state.matchedLocation == '/__e2e__/idle';

    if (e2eIdlePage && BackendRuntimeConfig.current.enableE2e) {
      return null;
    }

    if (invitePage) {
      return _handleInviteRoute(isLoggedIn: isLoggedIn, state: state);
    }

    if (publicTreePage) {
      return null;
    }

    if (!isLoggedIn &&
        !allowsAnonymousAccess(state.matchedLocation) &&
        !completingProfile) {
      return buildLoginRedirectTarget(state);
    }

    if (isLoggedIn && isAuthEntryRoute) {
      if (hasSocialAuthPayload(state.uri)) {
        return null;
      }
      final deferredTarget = restoreDeferredLoginTarget(state);
      return deferredTarget ?? '/';
    }

    if (isLoggedIn && !completingProfile) {
      final profileRedirect = await _ensureCompletedProfile(state);
      if (profileRedirect != null) {
        return profileRedirect;
      }
    }
    return null;
  }

  Future<String?> _handleInviteRoute({
    required bool isLoggedIn,
    required GoRouterState state,
  }) async {
    final treeId = state.uri.queryParameters['treeId'];
    final personId = state.uri.queryParameters['personId'];
    if (treeId != null &&
        treeId.isNotEmpty &&
        personId != null &&
        personId.isNotEmpty) {
      _invitationService.setPendingInvitation(
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

  Future<String?> _ensureCompletedProfile(GoRouterState state) async {
    try {
      final profileStatus = await _authService.checkProfileCompleteness();
      if (_authService.currentUserId == null) {
        return buildLoginRedirectTarget(state);
      }
      final isComplete = profileStatus['isComplete'] == true;
      if (!isComplete) {
        return '/complete_profile?requiredFields=${Uri.encodeComponent(profileStatus.toString())}';
      }
    } catch (error) {
      debugPrint('Error checking profile completeness during redirect: $error');
      final normalizedError = error.toString().toLowerCase();
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
    return null;
  }
}
