import 'dart:async';

import 'package:flutter/widgets.dart';

import '../backend/interfaces/chat_service_interface.dart';
import '../models/chat_message.dart';

class ChatTimelineController extends ChangeNotifier
    with WidgetsBindingObserver {
  ChatTimelineController({
    required this.chatId,
    required ChatServiceInterface chatService,
  }) : _chatService = chatService;

  final String chatId;
  final ChatServiceInterface _chatService;
  final StreamController<List<ChatMessage>> _streamController =
      StreamController<List<ChatMessage>>.broadcast();

  StreamSubscription<List<ChatMessage>>? _messagesSubscription;
  bool _started = false;
  /// Snapshot of the most recently emitted message list. Exposed as
  /// `lastValue` so StreamBuilder can use it as `initialData` and skip the
  /// flash-of-empty when the chat screen rebuilds (route hop, hot reload,
  /// app resume) — the cached snapshot from `getMessagesStream` shows
  /// instantly while the stream wires up.
  List<ChatMessage>? _lastValue;
  List<ChatMessage>? get lastValue => _lastValue;

  Stream<List<ChatMessage>> get stream => _streamController.stream;

  Future<void> start() async {
    if (_started) {
      return;
    }

    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _messagesSubscription = _chatService.getMessagesStream(chatId).listen(
      (messages) {
        _lastValue = messages;
        if (!_streamController.isClosed) {
          _streamController.add(messages);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_streamController.isClosed) {
          _streamController.addError(error, stackTrace);
        }
      },
    );
  }

  Future<void> refresh() {
    return _chatService.refreshMessages(chatId);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_messagesSubscription?.cancel());
    unawaited(_streamController.close());
    super.dispose();
  }
}
