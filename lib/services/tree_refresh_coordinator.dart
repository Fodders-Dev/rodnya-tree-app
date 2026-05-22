import 'dart:async';

/// Per-tree auto-refresh coordinator. Backend dispatches
/// `tree_mutated` notification (silent, data-only push для background;
/// realtime `notification.created` event для foreground) с payload
/// `{treeId, kind, actorUserId}`. Client routes к
/// `requestRefresh(treeId)`, который debounces 500ms и calls
/// registered callback.
///
/// Map-keyed by treeId — поддерживает несколько deep-linked tree
/// surfaces (TreeViewScreen, ExtendedNetwork view, branch sidebar).
/// Каждый surface registers callback на mount + unregisters на dispose.
/// Stale signals (treeId без subscriber) дропаются — no buffered queue.
///
/// Стейл-cache на app background: WidgetsBindingObserver hook на
/// app resume может re-call coordinator.requestRefresh для currently
/// viewed tree чтобы catch missed mutations.
class TreeRefreshCoordinator {
  TreeRefreshCoordinator._();

  static final TreeRefreshCoordinator instance = TreeRefreshCoordinator._();

  static const Duration _debounceWindow = Duration(milliseconds: 500);

  final Map<String, Future<void> Function()> _callbacks = {};
  final Map<String, Timer> _debounceTimers = {};

  bool hasSubscriber(String treeId) => _callbacks.containsKey(treeId);

  /// Register refresh callback для конкретного treeId. Если callback
  /// уже registered с тем же treeId, replaces — typical когда screen
  /// rebuilds.
  void register(String treeId, Future<void> Function() callback) {
    if (treeId.isEmpty) return;
    _callbacks[treeId] = callback;
  }

  /// Unregister callback for treeId. Cancels pending debounce timer.
  /// Identity check на callback prevents accidental unregister другого
  /// screen с same treeId.
  void unregister(String treeId, Future<void> Function() callback) {
    if (identical(_callbacks[treeId], callback)) {
      _callbacks.remove(treeId);
      _debounceTimers.remove(treeId)?.cancel();
    }
  }

  /// Request refresh для конкретного treeId. Debounced. No-op если нет
  /// subscriber'а на этот treeId.
  void requestRefresh(String treeId) {
    if (treeId.isEmpty) return;
    if (!_callbacks.containsKey(treeId)) return;
    _debounceTimers.remove(treeId)?.cancel();
    _debounceTimers[treeId] = Timer(_debounceWindow, () => _fire(treeId));
  }

  Future<void> _fire(String treeId) async {
    _debounceTimers.remove(treeId);
    final callback = _callbacks[treeId];
    if (callback == null) return;
    try {
      await callback();
    } catch (_) {
      // Silent — same rationale as PostsRefreshCoordinator. Next
      // push triggers retry.
    }
  }
}
