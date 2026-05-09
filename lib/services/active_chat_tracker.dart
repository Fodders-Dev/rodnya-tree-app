/// Tracks which chat (if any) the user is currently viewing on the
/// foreground. Used to suppress system notifications + push replays
/// for messages from THAT chat — пользователь УЖЕ читает их в окне
/// чата, ОС-нотификация будет шумом.
///
/// User-reported: «при переписке мне быстрее уведомления приходят,
/// чем само сообщение в чате... и нахуя они вообще шлются, когда я
/// в чате уже с ним?». Корень — клиент никогда не сообщал
/// notification service о том, что юзер сейчас в чате X. Сервис
/// исправно показывал push для каждого входящего, даже если оно
/// уже отрисовалось в открытом чате.
///
/// Singleton по простоте — у нас только один активный чат может быть
/// одновременно (полноэкранный экран чата). Если когда-нибудь
/// вернёмся к multi-pane (вкладка чата рядом с лентой), это нужно
/// будет переписать на set активных id или per-pane tracker.
class ActiveChatTracker {
  ActiveChatTracker._();
  static final ActiveChatTracker instance = ActiveChatTracker._();

  String? _activeChatId;

  String? get activeChatId => _activeChatId;

  bool isActive(String? chatId) {
    final normalized = chatId?.trim();
    if (normalized == null || normalized.isEmpty) return false;
    return _activeChatId == normalized;
  }

  void setActive(String chatId) {
    final normalized = chatId.trim();
    if (normalized.isEmpty) return;
    _activeChatId = normalized;
  }

  /// Clears the active chat. Pass `expected` чтобы не сбросить чужой
  /// chatId, если два экрана чата сменяют друг друга async (новый
  /// уже зарегистрировал свой id, старый dispose'ится позже).
  void clearActive([String? expected]) {
    if (expected != null && _activeChatId != expected.trim()) {
      return;
    }
    _activeChatId = null;
  }
}
