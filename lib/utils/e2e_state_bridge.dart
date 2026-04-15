import '../backend/backend_runtime_config.dart';
import 'e2e_state_bridge_stub.dart'
    if (dart.library.html) 'e2e_state_bridge_web.dart' as e2e_platform;

typedef E2ELoginHandler = Future<Map<String, dynamic>> Function(
  String email,
  String password,
  String? targetPath,
);
typedef E2ELogoutHandler = Future<Map<String, dynamic>> Function(
  String? targetPath,
);
typedef E2EStatusHandler = Future<Map<String, dynamic>> Function();
typedef E2ENavigationHandler = Future<Map<String, dynamic>> Function(
  String path,
);
typedef E2EOpenTreeHandler = Future<Map<String, dynamic>> Function(
  String treeId,
  String? treeName,
  String? targetPath,
);
typedef E2EOpenAddRelativeHandler = Future<Map<String, dynamic>> Function({
  required String treeId,
  String? contextPersonId,
  String? relationType,
  bool quickAddMode,
});
typedef E2EOpenStoryViewerHandler = Future<Map<String, dynamic>> Function({
  String? treeId,
  String? authorId,
});

class E2EStateBridge {
  const E2EStateBridge._();

  static bool get isEnabled => BackendRuntimeConfig.current.enableE2e;

  static void initialize({
    required E2ELoginHandler onLogin,
    required E2ELogoutHandler onLogout,
    required E2EStatusHandler onStatus,
    required E2ENavigationHandler onNavigate,
    required E2EOpenTreeHandler onOpenTree,
    required E2EOpenAddRelativeHandler onOpenAddRelative,
    required E2EOpenStoryViewerHandler onOpenStoryViewer,
  }) {
    if (!isEnabled) {
      return;
    }

    e2e_platform.initializeBridge(
      onLogin: onLogin,
      onLogout: onLogout,
      onStatus: onStatus,
      onNavigate: onNavigate,
      onOpenTree: onOpenTree,
      onOpenAddRelative: onOpenAddRelative,
      onOpenStoryViewer: onOpenStoryViewer,
    );
  }

  static void publish({
    required String screen,
    required Map<String, dynamic> state,
  }) {
    if (!isEnabled) {
      return;
    }

    e2e_platform.publishState(
      <String, dynamic>{
        'enabled': true,
        'screen': screen,
        'state': state,
        'updatedAt': DateTime.now().toIso8601String(),
      },
    );
  }
}
