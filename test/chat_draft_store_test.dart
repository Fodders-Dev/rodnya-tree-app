import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/services/chat_draft_store.dart';

class _MemoryChatDraftStore implements ChatDraftStore {
  final Map<String, ChatDraftSnapshot> drafts = <String, ChatDraftSnapshot>{};

  @override
  Future<void> clearDraft(String key) async {
    drafts.remove(key);
  }

  @override
  Future<Map<String, ChatDraftSnapshot>> getAllDrafts() async {
    return Map<String, ChatDraftSnapshot>.from(drafts);
  }

  @override
  Future<ChatDraftSnapshot?> getDraft(String key) async {
    return drafts[key];
  }

  @override
  Future<void> saveDraft(String key, String text) async {
    drafts[key] = ChatDraftSnapshot(
      text: text,
      updatedAt: DateTime(2026, 4, 30, 12, drafts.length),
    );
  }
}

class _FakeRemoteDraftClient implements RemoteChatDraftClient {
  Map<String, ChatDraftSnapshot> draftsByChatId = <String, ChatDraftSnapshot>{};
  final List<String> savedTexts = <String>[];
  final List<String> clearedChatIds = <String>[];

  @override
  Future<void> clearChatDraft(String chatId) async {
    clearedChatIds.add(chatId);
    draftsByChatId.remove(chatId);
  }

  @override
  Future<ChatDraftSnapshot?> getChatDraft(String chatId) async {
    return draftsByChatId[chatId];
  }

  @override
  Future<Map<String, ChatDraftSnapshot>> getChatDrafts() async {
    return draftsByChatId.map(
      (chatId, draft) => MapEntry(
        SharedPreferencesChatDraftStore.chatKey(chatId),
        draft,
      ),
    );
  }

  @override
  Future<void> saveChatDraft({
    required String chatId,
    required String text,
  }) async {
    savedTexts.add(text);
    draftsByChatId[chatId] = ChatDraftSnapshot(
      text: text,
      updatedAt: DateTime(2026, 4, 30, 13, savedTexts.length),
    );
  }
}

void main() {
  test('HybridChatDraftStore merges newer remote drafts into local cache',
      () async {
    final local = _MemoryChatDraftStore();
    final remote = _FakeRemoteDraftClient()
      ..draftsByChatId['chat-1'] = ChatDraftSnapshot(
        text: 'Черновик с телефона',
        updatedAt: DateTime(2026, 4, 30, 13),
      );
    final store = HybridChatDraftStore(
      localStore: local,
      remoteClient: remote,
    );

    final draft = await store.getDraft(
      SharedPreferencesChatDraftStore.chatKey('chat-1'),
    );

    expect(draft?.text, 'Черновик с телефона');
    expect(
      local.drafts[SharedPreferencesChatDraftStore.chatKey('chat-1')]?.text,
      'Черновик с телефона',
    );
  });

  test('HybridChatDraftStore writes chat-key drafts to local and remote',
      () async {
    final local = _MemoryChatDraftStore();
    final remote = _FakeRemoteDraftClient();
    final store = HybridChatDraftStore(
      localStore: local,
      remoteClient: remote,
    );
    final key = SharedPreferencesChatDraftStore.chatKey('chat-1');

    await store.saveDraft(key, 'Новый черновик');
    await store.clearDraft(key);

    expect(local.drafts.containsKey(key), isFalse);
    expect(remote.savedTexts, ['Новый черновик']);
    expect(remote.clearedChatIds, ['chat-1']);
  });
}
