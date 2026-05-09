import '../../models/family_person.dart';

abstract class NotificationServiceInterface {
  Future<void> initialize();
  Future<void> showBirthdayNotification(FamilyPerson person);
  Future<void> showChatMessageNotification({
    required String chatId,
    required String senderId,
    required String senderName,
    required String messageText,
    required int notificationId,
    bool playSound = true,
  });

  /// Снять все system-уведомления для конкретного чата. Зовётся
  /// при открытии чата, чтобы шторка не зависала с устаревшими
  /// нотификациями.
  Future<void> dismissChatNotifications(String chatId);
}
