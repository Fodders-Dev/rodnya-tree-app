import 'dart:async';

import 'package:flutter/foundation.dart';

import 'custom_api_auth_service.dart';
import 'custom_api_realtime_service.dart';

/// Listens to the realtime stream for `session.revoked` events emitted by the
/// backend when another device signs this session out.  When that fires we
/// drop the local session immediately so the user is bounced to the login
/// screen instead of seeing a stream of 401 errors.
class SessionRevocationWatcher {
  SessionRevocationWatcher({
    required CustomApiAuthService authService,
    required CustomApiRealtimeService realtimeService,
  })  : _authService = authService,
        _realtimeService = realtimeService;

  final CustomApiAuthService _authService;
  final CustomApiRealtimeService _realtimeService;

  StreamSubscription<CustomApiRealtimeEvent>? _subscription;

  void start() {
    _subscription?.cancel();
    _subscription = _realtimeService.events.listen(
      _onEvent,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('SessionRevocationWatcher: stream error: $error');
      },
    );
  }

  Future<void> _onEvent(CustomApiRealtimeEvent event) async {
    if (event.type != 'session.revoked') return;
    try {
      await _authService.clearSessionLocally(sessionExpired: true);
    } catch (error) {
      debugPrint('SessionRevocationWatcher: clearSession failed: $error');
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
