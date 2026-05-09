import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../backend/backend_runtime_config.dart';
import '../utils/client_instance_id.dart';
import 'custom_api_auth_service.dart';

typedef WebSocketChannelFactory = WebSocketChannel Function(Uri uri);
typedef ReconnectJitterFactor = double Function();
typedef ReconnectTimerFactory = Timer Function(
  Duration delay,
  void Function() callback,
);

class CustomApiRealtimeEvent {
  const CustomApiRealtimeEvent({
    required this.type,
    required this.payload,
  });

  final String type;
  final Map<String, dynamic> payload;

  String? get chatId => payload['chatId']?.toString();

  Map<String, dynamic>? get notification {
    final value = payload['notification'];
    return value is Map<String, dynamic> ? value : null;
  }

  Map<String, dynamic>? get message {
    final value = payload['message'];
    return value is Map<String, dynamic> ? value : null;
  }

  Map<String, dynamic>? get chat {
    final value = payload['chat'];
    return value is Map<String, dynamic> ? value : null;
  }

  Map<String, dynamic>? get draft {
    final value = payload['draft'];
    return value is Map<String, dynamic> ? value : null;
  }

  Map<String, dynamic>? get pin {
    final value = payload['pin'];
    return value is Map<String, dynamic> ? value : null;
  }

  Map<String, dynamic>? get call {
    final value = payload['call'];
    return value is Map<String, dynamic> ? value : null;
  }

  String? get userId => payload['userId']?.toString();

  bool? get isTyping =>
      payload['isTyping'] is bool ? payload['isTyping'] as bool : null;

  bool? get isOnline =>
      payload['isOnline'] is bool ? payload['isOnline'] as bool : null;

  /// ISO8601 timestamp from `presence.updated` payloads. `lastSeenAt` is
  /// what to render in subtitles for offline peers; `updatedAt` is the
  /// broadcast moment (== lastSeenAt for offline transitions, "now" for
  /// online ones).
  String? get lastSeenAt => payload['lastSeenAt']?.toString();
  String? get updatedAt => payload['updatedAt']?.toString();

  List<String> get onlineUserIds {
    final value = payload['onlineUserIds'];
    if (value is! List) {
      return const <String>[];
    }
    return value.map((item) => item.toString()).toList();
  }

  bool get isChatEvent =>
      type == 'chat.created' ||
      type == 'chat.updated' ||
      type == 'chat.message.created' ||
      type == 'chat.message.updated' ||
      type == 'chat.message.deleted' ||
      type == 'message.reaction.changed' ||
      type == 'message.delivered' ||
      type == 'message.read' ||
      type == 'chat.read.updated' ||
      type == 'chat.unread.changed' ||
      type == 'chat.typing.updated' ||
      type == 'chat.draft.updated' ||
      type == 'chat.pin.updated';

  bool get isNotificationEvent =>
      type == 'notification.created' || type == 'notification.bulk-read';

  bool get isCallEvent =>
      type == 'call.invite.created' || type == 'call.state.updated';

  bool get isPresenceEvent =>
      type == 'connection.ready' ||
      type == 'connection.disconnected' ||
      type == 'presence.updated';

  factory CustomApiRealtimeEvent.fromJson(Map<String, dynamic> json) {
    return CustomApiRealtimeEvent(
      type: json['type']?.toString() ?? 'unknown',
      payload: json,
    );
  }
}

class CustomApiRealtimeService {
  CustomApiRealtimeService({
    required CustomApiAuthService authService,
    required BackendRuntimeConfig runtimeConfig,
    WebSocketChannelFactory? channelFactory,
    Duration? reconnectDelay,
    Duration? maxReconnectDelay,
    ReconnectJitterFactor? reconnectJitterFactor,
    ReconnectTimerFactory? reconnectTimerFactory,
  })  : _authService = authService,
        _runtimeConfig = runtimeConfig,
        _channelFactory = channelFactory ?? WebSocketChannel.connect,
        _baseReconnectDelay = reconnectDelay ?? const Duration(seconds: 1),
        _maxReconnectDelay = maxReconnectDelay ?? const Duration(seconds: 30),
        _reconnectJitterFactor =
            reconnectJitterFactor ?? _createReconnectJitterFactor(Random()),
        _reconnectTimerFactory = reconnectTimerFactory ??
            ((delay, callback) => Timer(delay, callback));

  final CustomApiAuthService _authService;
  final BackendRuntimeConfig _runtimeConfig;
  final WebSocketChannelFactory _channelFactory;
  final Duration _baseReconnectDelay;
  final Duration _maxReconnectDelay;
  final ReconnectJitterFactor _reconnectJitterFactor;
  final ReconnectTimerFactory _reconnectTimerFactory;
  final StreamController<CustomApiRealtimeEvent> _eventsController =
      StreamController<CustomApiRealtimeEvent>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSubscription;
  Timer? _reconnectTimer;
  bool _isConnecting = false;
  bool _disposed = false;
  int _consecutiveFailures = 0;

  Stream<CustomApiRealtimeEvent> get events => _eventsController.stream;

  Future<void> connect() async {
    if (_disposed || _isConnecting || _channel != null) {
      return;
    }

    final accessToken = _authService.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isConnecting = true;
    try {
      final uri = _buildUri(accessToken);
      final channel = _channelFactory(uri);
      await channel.ready;
      _consecutiveFailures = 0;
      _channel = channel;
      _channelSubscription = channel.stream.listen(
        _handleEvent,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _consecutiveFailures = 0;
    await _channelSubscription?.cancel();
    _channelSubscription = null;
    await _channel?.sink.close();
    _channel = null;
  }

  Future<void> dispose() async {
    _disposed = true;
    await disconnect();
    await _eventsController.close();
  }

  Future<void> sendTypingState({
    required String chatId,
    required bool isTyping,
  }) async {
    if (_disposed) {
      return;
    }

    await connect();
    final channel = _channel;
    if (channel == null) {
      return;
    }

    channel.sink.add(
      jsonEncode({
        'action': 'chat.typing.set',
        'chatId': chatId,
        'isTyping': isTyping,
      }),
    );
  }

  /// Сообщает серверу что юзер прямо сейчас открыт в чате.
  /// Сервер использует это в push-gateway: для исходящих сообщений
  /// в этот чат push не дёргается, потому что юзер и так увидит
  /// realtime-доставку в открытом окне. Закрывает жалобу
  /// «нахуя пуши когда я уже в чате».
  Future<void> setActiveChat(String chatId) async {
    if (_disposed || chatId.trim().isEmpty) return;
    await connect();
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(
      jsonEncode({
        'action': 'chat.active.set',
        'chatId': chatId,
      }),
    );
  }

  /// Снимает active-флажок. `chatId` опционально — пустой clears
  /// всё (полезно при logout / переходе в фон).
  Future<void> clearActiveChat({String? chatId}) async {
    if (_disposed) return;
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(
      jsonEncode({
        'action': 'chat.active.clear',
        if (chatId != null) 'chatId': chatId,
      }),
    );
  }

  Uri _buildUri(String accessToken) {
    final normalizedBase = _runtimeConfig.webSocketBaseUrl.replaceAll(
      RegExp(r'/$'),
      '',
    );
    return Uri.parse(
      '$normalizedBase/v1/realtime'
      '?accessToken=$accessToken'
      '&instanceId=${Uri.encodeQueryComponent(ClientInstanceId.current)}',
    );
  }

  void _handleEvent(dynamic rawEvent) {
    if (rawEvent is! String || rawEvent.trim().isEmpty) {
      return;
    }

    final dynamic decoded = jsonDecode(rawEvent);
    if (decoded is! Map<String, dynamic>) {
      return;
    }

    final event = CustomApiRealtimeEvent.fromJson(decoded);
    _eventsController.add(event);
  }

  void _scheduleReconnect() {
    _channelSubscription?.cancel();
    _channelSubscription = null;
    _channel = null;

    if (_disposed) {
      return;
    }

    _emitConnectionEvent('connection.disconnected');
    _consecutiveFailures += 1;
    final delay = _nextBackoffDelay(_consecutiveFailures);
    _reconnectTimer?.cancel();
    _reconnectTimer = _reconnectTimerFactory(delay, () {
      _reconnectTimer = null;
      unawaited(connect());
    });
  }

  void _emitConnectionEvent(String type) {
    if (_eventsController.isClosed) {
      return;
    }

    _eventsController.add(
      CustomApiRealtimeEvent(
        type: type,
        payload: <String, dynamic>{
          'type': type,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        },
      ),
    );
  }

  Duration debugBackoffDelayForFailureCount(int failures) {
    return _nextBackoffDelay(failures);
  }

  Duration _nextBackoffDelay(int failures) {
    final normalizedFailures = max(1, failures);
    final multiplier = 1 << min(normalizedFailures - 1, 5);
    final baseMilliseconds = _baseReconnectDelay.inMilliseconds * multiplier;
    final cappedMilliseconds = min(
      baseMilliseconds,
      _maxReconnectDelay.inMilliseconds,
    );
    final jitterFactor = _reconnectJitterFactor().clamp(0.75, 1.25);
    final jitteredMilliseconds = max(
      1,
      (cappedMilliseconds * jitterFactor).round(),
    );

    return Duration(milliseconds: jitteredMilliseconds);
  }

  static ReconnectJitterFactor _createReconnectJitterFactor(Random random) {
    return () => 0.75 + random.nextDouble() * 0.5;
  }
}
