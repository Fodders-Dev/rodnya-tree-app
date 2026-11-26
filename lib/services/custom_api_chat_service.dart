import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../backend/backend_runtime_config.dart';
import '../backend/interfaces/chat_service_interface.dart';
import '../backend/interfaces/storage_service_interface.dart';
import '../models/chat_attachment.dart';
import '../models/chat_details.dart';
import '../models/chat_message.dart';
import '../models/chat_message_search_result.dart';
import '../models/chat_messages_page.dart';
import '../models/chat_preview.dart';
import '../models/chat_send_progress.dart';
import '../utils/safe_json_decode.dart';
import '../utils/startup_trace.dart';
import '../utils/voice_waveform.dart';
import 'app_status_service.dart';
import 'chat_draft_store.dart';
import 'chat_message_cache.dart';
import 'chat_preview_cache.dart';
import 'chat_pin_store.dart';
import 'hive_box_recovery.dart';
import 'custom_api_auth_service.dart';
import 'custom_api_realtime_service.dart';
import 'warm_http_client.dart';

part 'chat/custom_api_chat_base.dart';
part 'chat/custom_api_chat_rooms_mixin.dart';
part 'chat/custom_api_chat_realtime_mixin.dart';
part 'chat/custom_api_chat_messages_mixin.dart';
part 'chat/custom_api_chat_media_mixin.dart';

const int _maxPersistedOverrides = 200;

class _ChatMessageStreamState {
  _ChatMessageStreamState(this.chatId);

  final String chatId;
  late final StreamController<List<ChatMessage>> controller;
  StreamSubscription<CustomApiRealtimeEvent>? realtimeSubscription;
  Timer? refreshDebounce;
  int listenerCount = 0;
  bool started = false;
  bool isFetching = false;
  bool hasQueuedRefresh = false;
  List<ChatMessage> messages = const <ChatMessage>[];
  int messagesVersion = 0;
}

class _UploadedAttachmentMetadata {
  const _UploadedAttachmentMetadata({
    this.durationMs,
    this.waveform = const <double>[],
    this.width,
    this.height,
  });

  final int? durationMs;
  final List<double> waveform;
  final int? width;
  final int? height;
}

class CustomApiChatService extends _CustomApiChatBase
    with
        _CustomApiChatMediaMixin,
        _CustomApiChatRoomsMixin,
        _CustomApiChatRealtimeMixin,
        _CustomApiChatMessagesMixin
    implements
        ChatServiceInterface,
        RemoteChatDraftClient,
        RemoteChatPinClient {
  CustomApiChatService({
    required super.authService,
    required super.runtimeConfig,
    super.httpClient,
    super.realtimeService,
    super.storageService,
    super.messageCache,
    super.previewCache,
    super.overrideCache,
    super.appStatusService,
    super.pollInterval,
    super.overviewPollInterval,
    super.realtimeFallbackPollInterval,
  });
}

/// A realtime-sourced overlay for a chat-list preview. chat.updated carries the
/// full mapped chat (with photoUrl/title) — fresher than GET /v1/chats, which
/// can return a stale null group photoUrl until the backend is restarted.
/// A null field means "no override; fall through to the fetched value".
class ChatPreviewOverride {
  const ChatPreviewOverride({this.photoUrl, this.title, this.type});

  final String? photoUrl;
  final String? title;
  final String? type;

  bool get isGroup => type == 'group' || type == 'branch';

  Map<String, dynamic> toMap() => <String, dynamic>{
        'photoUrl': photoUrl,
        'title': title,
        'type': type,
      };

  factory ChatPreviewOverride.fromMap(Map<String, dynamic> map) {
    return ChatPreviewOverride(
      photoUrl: map['photoUrl']?.toString(),
      title: map['title']?.toString(),
      type: map['type']?.toString(),
    );
  }
}

/// Persists realtime chat-preview overrides (keyed by chatId) so a restored
/// group avatar survives a cold start / web reload. Without this the in-memory
/// override map is empty on boot, and the first (stale) /v1/chats refetch blanks
/// the group photo back out until a fresh chat.updated arrives.
abstract class ChatPreviewOverrideCache {
  Future<Map<String, ChatPreviewOverride>> read();

  Future<void> write(Map<String, ChatPreviewOverride> overrides);

  Future<void> clear();
}

class HiveChatPreviewOverrideCache implements ChatPreviewOverrideCache {
  HiveChatPreviewOverrideCache({this.boxName = 'chat_preview_overrides_v1'});

  final String boxName;
  static const String _key = 'overrides';
  Future<Box<String>>? _openTask;

  Future<Box<String>> _box() {
    return _openTask ??= openBoxWithRecovery<String>(boxName);
  }

  @override
  Future<Map<String, ChatPreviewOverride>> read() async {
    try {
      final raw = (await _box()).get(_key);
      if (raw == null || raw.trim().isEmpty) {
        return <String, ChatPreviewOverride>{};
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <String, ChatPreviewOverride>{};
      }
      final result = <String, ChatPreviewOverride>{};
      decoded.forEach((key, value) {
        if (value is Map) {
          result[key.toString()] =
              ChatPreviewOverride.fromMap(Map<String, dynamic>.from(value));
        }
      });
      return result;
    } catch (_) {
      // Corrupt cache → ignore; a fresh chat.updated repopulates it.
      return <String, ChatPreviewOverride>{};
    }
  }

  @override
  Future<void> write(Map<String, ChatPreviewOverride> overrides) async {
    try {
      final encoded = <String, dynamic>{};
      overrides.forEach((key, value) {
        encoded[key] = value.toMap();
      });
      await (await _box()).put(_key, jsonEncode(encoded));
    } catch (_) {
      // Best-effort — never fail the foreground flow because of cache I/O.
    }
  }

  @override
  Future<void> clear() async {
    try {
      await (await _box()).delete(_key);
    } catch (_) {
      // Best-effort.
    }
  }
}

/// Test helper that keeps overrides in memory; pre-fill via the constructor to
/// simulate a populated Hive box after a restart.
class InMemoryChatPreviewOverrideCache implements ChatPreviewOverrideCache {
  InMemoryChatPreviewOverrideCache([
    Map<String, ChatPreviewOverride>? initial,
  ]) : _overrides = <String, ChatPreviewOverride>{...?initial};

  Map<String, ChatPreviewOverride> _overrides;

  @override
  Future<Map<String, ChatPreviewOverride>> read() async =>
      Map<String, ChatPreviewOverride>.from(_overrides);

  @override
  Future<void> write(Map<String, ChatPreviewOverride> overrides) async {
    _overrides = Map<String, ChatPreviewOverride>.from(overrides);
  }

  @override
  Future<void> clear() async {
    _overrides = <String, ChatPreviewOverride>{};
  }
}
