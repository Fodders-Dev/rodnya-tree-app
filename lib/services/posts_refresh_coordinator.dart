import 'dart:async';

/// Coordinates auto-refresh of the home feed when new posts arrive
/// via realtime либо push.
///
/// Flow:
/// 1. Backend `post_created` notification published via
///    `createAndDispatchNotification`. Two channels carry it:
///    - WebSocket `notification.created` event (foreground users)
///    - Push gateway FCM/RuStore/web-push (background users)
/// 2. Client `_handleRealtimeNotification` (and equivalent push tap
///    handler) calls `PostsRefreshCoordinator.instance.requestRefresh()`.
/// 3. Home feed registers callback via [register] when widget mounts.
/// 4. Coordinator debounces requests (500ms) — burst of N pushes
///    coalesces в один refresh call.
///
/// Singleton — single feed surface на этот ship. Future: if second
/// feed surface появится (e.g. notifications screen), promote к
/// id-keyed map.
class PostsRefreshCoordinator {
  PostsRefreshCoordinator._();

  static final PostsRefreshCoordinator instance = PostsRefreshCoordinator._();

  static const Duration _debounceWindow = Duration(milliseconds: 500);

  Future<void> Function()? _callback;
  Timer? _debounceTimer;

  /// `true` если у coordinator есть subscriber, который примет
  /// refresh request. False — pending requests дропаются (no-op),
  /// потому что нет UI surface чтобы refetch'ить.
  bool get hasSubscriber => _callback != null;

  /// Register the refresh callback. Single subscriber pattern —
  /// последний registered wins (typical когда HomeScreen rebuilds).
  void register(Future<void> Function() callback) {
    _callback = callback;
  }

  /// Unregister callback (на dispose of subscriber). Cancels pending
  /// debounce timer чтобы dangling callback не вызвался.
  void unregister(Future<void> Function() callback) {
    if (identical(_callback, callback)) {
      _callback = null;
      _debounceTimer?.cancel();
      _debounceTimer = null;
    }
  }

  /// Request a refresh. Debounced — multiple requests within
  /// [_debounceWindow] collapse в один callback call.
  /// No-op если нет subscriber'а — refresh would have nothing to do.
  void requestRefresh() {
    if (_callback == null) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceWindow, _fire);
  }

  Future<void> _fire() async {
    _debounceTimer = null;
    final callback = _callback;
    if (callback == null) return;
    try {
      await callback();
    } catch (_) {
      // Refresh callbacks should swallow their own errors; coordinator
      // не должен крашить от UI-level failures. Silent — каждый
      // refresh is best-effort, next push triggers retry.
    }
  }
}
