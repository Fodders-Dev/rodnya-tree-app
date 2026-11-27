import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../backend/interfaces/dynamic_link_service_interface.dart';

class AppLinksDynamicLinkService implements DynamicLinkServiceInterface {
  AppLinksDynamicLinkService({
    AppLinks? appLinks,
    Future<Uri?> Function()? initialLinkReader,
    Stream<Uri>? linkStream,
  })  : _appLinks = appLinks ?? AppLinks(),
        _initialLinkReader = initialLinkReader,
        _linkStream = linkStream;

  final AppLinks _appLinks;
  final Future<Uri?> Function()? _initialLinkReader;
  final Stream<Uri>? _linkStream;
  StreamSubscription<Uri>? _subscription;
  bool _started = false;
  String? _lastHandledRoute;
  DateTime? _lastHandledAt;
  static const Duration _burstDedupWindow = Duration(seconds: 2);

  @override
  Future<void> startListening(GoRouter router) async {
    if (kIsWeb || _started) {
      return;
    }
    _started = true;

    try {
      final initialLinkReader = _initialLinkReader;
      final initialUri = await (initialLinkReader != null
          ? initialLinkReader()
          : _appLinks.getInitialLink());
      _handleUri(router, initialUri);
    } catch (error) {
      debugPrint('[app_links] initial link failed: $error');
    }

    _subscription = (_linkStream ?? _appLinks.uriLinkStream).listen(
      (uri) => _handleUri(router, uri),
      onError: (Object error) {
        debugPrint('[app_links] stream failed: $error');
      },
    );
  }

  void _handleUri(GoRouter router, Uri? uri) {
    if (uri == null) {
      return;
    }
    final route = routeForUri(uri);
    if (route == null) {
      return;
    }
    final now = DateTime.now();
    final lastAt = _lastHandledAt;
    if (route == _lastHandledRoute &&
        lastAt != null &&
        now.difference(lastAt) < _burstDedupWindow) {
      return;
    }
    _lastHandledRoute = route;
    _lastHandledAt = now;
    router.go(route);
  }

  @visibleForTesting
  static String? routeForUri(Uri uri) {
    if (!_isRodnyaHost(uri)) {
      return null;
    }

    final fragment = uri.fragment.trim();
    if (fragment.startsWith('/')) {
      final fragmentUri = Uri.tryParse(fragment);
      final fragmentRoute = _routeFromAppUri(fragmentUri);
      if (fragmentRoute != null) {
        return fragmentRoute;
      }
    }

    return _routeFromAppUri(uri);
  }

  static bool _isRodnyaHost(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    return (scheme == 'https' || scheme == 'http') &&
        (host == 'rodnya-tree.ru' || host == 'www.rodnya-tree.ru');
  }

  static String? _routeFromAppUri(Uri? uri) {
    if (uri == null) {
      return null;
    }
    final path = uri.path.trim().isEmpty ? '/' : uri.path.trim();
    final query = uri.hasQuery ? '?${uri.query}' : '';

    // Never hijack OAuth callbacks or public guest SSR story URLs.
    if (path.startsWith('/oauth/') || path.startsWith('/story/')) {
      return null;
    }

    if (path == '/invite' ||
        path == '/reset-password' ||
        path == '/notifications' ||
        path == '/discover/relatives' ||
        path == '/tree' ||
        path == '/trees' ||
        path == '/family' ||
        path == '/profile/trash' ||
        path == '/privacy' ||
        path == '/terms' ||
        path == '/support' ||
        path == '/account-deletion') {
      return '$path$query';
    }

    if (_hasNonEmptyTail(path, '/invite/') ||
        _hasNonEmptyTail(path, '/browse/') ||
        _hasNonEmptyTail(path, '/public/tree/') ||
        _hasNonEmptyTail(path, '/tree/view/') ||
        _hasNonEmptyTail(path, '/post/') ||
        _hasNonEmptyTail(path, '/user/') ||
        _hasNonEmptyTail(path, '/relative/details/') ||
        _hasNonEmptyTail(path, '/relatives/find/') ||
        _hasNonEmptyTail(path, '/chats/view/') ||
        _hasNonEmptyTail(path, '/chat/') ||
        _hasNonEmptyTail(path, '/stories/view/') ||
        _hasNonEmptyTail(path, '/semya/')) {
      return '$path$query';
    }

    if (path.startsWith('/story-requests/') && path.endsWith('/answer')) {
      final requestId = path.substring(
        '/story-requests/'.length,
        path.length - '/answer'.length,
      );
      if (requestId.isNotEmpty && !requestId.contains('/')) {
        return '$path$query';
      }
    }

    return null;
  }

  static bool _hasNonEmptyTail(String path, String prefix) {
    return path.startsWith(prefix) && path.length > prefix.length;
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _started = false;
  }
}
