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
    if (route == null || route == _lastHandledRoute) {
      return;
    }
    _lastHandledRoute = route;
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

    if (path == '/invite') {
      return '/invite$query';
    }
    if (path.startsWith('/invite/') && path.length > '/invite/'.length) {
      return '$path$query';
    }
    if (path.startsWith('/browse/') && path.length > '/browse/'.length) {
      return '$path$query';
    }
    if (path.startsWith('/public/tree/')) {
      return '$path$query';
    }
    if (path.startsWith('/tree/view/')) {
      return '$path$query';
    }
    return null;
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _started = false;
  }
}
