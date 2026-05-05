import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';

import '../models/chat_preview.dart';
import 'hive_box_recovery.dart';

/// Cache layer for the chat list previews.
///
/// Mirrors [ChatMessageCache] but keeps the whole list under a single Hive
/// key (`previews`) — the list is small (typically 10–50 items) and we only
/// ever need to read/write the full set together.
abstract class ChatPreviewCache {
  Future<List<ChatPreview>> read();

  Future<void> write(List<ChatPreview> previews);

  Future<void> clear();
}

class HiveChatPreviewCache implements ChatPreviewCache {
  HiveChatPreviewCache({this.boxName = 'chat_previews_v1'});

  final String boxName;
  static const String _key = 'previews';
  Future<Box<String>>? _openTask;

  Future<Box<String>> _box() {
    return _openTask ??= openBoxWithRecovery<String>(boxName);
  }

  @override
  Future<List<ChatPreview>> read() async {
    final raw = (await _box()).get(_key);
    if (raw == null || raw.trim().isEmpty) {
      return const <ChatPreview>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) {
        return const <ChatPreview>[];
      }
      return decoded
          .whereType<Map>()
          .map((entry) =>
              ChatPreview.fromMap(Map<String, dynamic>.from(entry)))
          .toList(growable: false);
    } catch (_) {
      // Corrupt cache → ignore and let the API refresh repopulate it.
      return const <ChatPreview>[];
    }
  }

  @override
  Future<void> write(List<ChatPreview> previews) async {
    await (await _box()).put(
      _key,
      jsonEncode(previews.map(_previewToJson).toList(growable: false)),
    );
  }

  @override
  Future<void> clear() async {
    await (await _box()).delete(_key);
  }

  Map<String, dynamic> _previewToJson(ChatPreview preview) => preview.toMap();
}

/// Test helper that keeps everything in memory.
class InMemoryChatPreviewCache implements ChatPreviewCache {
  List<ChatPreview> _previews = const <ChatPreview>[];

  @override
  Future<List<ChatPreview>> read() async => List.of(_previews);

  @override
  Future<void> write(List<ChatPreview> previews) async {
    _previews = List.of(previews);
  }

  @override
  Future<void> clear() async {
    _previews = const <ChatPreview>[];
  }
}
