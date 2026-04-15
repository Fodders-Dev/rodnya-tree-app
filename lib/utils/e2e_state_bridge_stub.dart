void publishState(Map<String, dynamic> payload) {}

void initializeBridge({
  required Future<Map<String, dynamic>> Function(
    String email,
    String password,
    String? targetPath,
  ) onLogin,
  required Future<Map<String, dynamic>> Function(String? targetPath) onLogout,
  required Future<Map<String, dynamic>> Function() onStatus,
  required Future<Map<String, dynamic>> Function(String path) onNavigate,
  required Future<Map<String, dynamic>> Function(
    String treeId,
    String? treeName,
    String? targetPath,
  ) onOpenTree,
  required Future<Map<String, dynamic>> Function({
    required String treeId,
    String? contextPersonId,
    String? relationType,
    bool quickAddMode,
  }) onOpenAddRelative,
  required Future<Map<String, dynamic>> Function({
    String? treeId,
    String? authorId,
  }) onOpenStoryViewer,
}) {}
