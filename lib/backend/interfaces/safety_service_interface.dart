import '../../models/user_block_record.dart';

abstract class SafetyServiceInterface {
  Future<void> reportTarget({
    required String targetType,
    required String targetId,
    required String reason,
    String? details,
    Map<String, dynamic> metadata = const <String, dynamic>{},
  });

  Future<UserBlockRecord> blockUser({
    required String userId,
    String? reason,
    Map<String, dynamic> metadata = const <String, dynamic>{},
  });

  Future<List<UserBlockRecord>> listBlockedUsers();

  Future<void> unblockUser(String blockId);
}
