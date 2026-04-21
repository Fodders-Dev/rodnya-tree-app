import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../backend/backend_runtime_config.dart';
import 'custom_api_auth_service.dart';

typedef WebSocketChannelFactory = WebSocketChannel Function(Uri uri);

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

  Map<String, dynamic>? get call {
    final value = payload['call'];
    return value is Map<String, dynamic> ? value : null;
  }

  String? get userId => payload['userId']?.toString();

  bool? get isTyping =>
      payload['isTyping'] is bool ? payload['isTyping'] as bool : null;

  bool? get isOnline =>
      payload['isOnline'] is bool ? payload['isOnline'] as bool : null;

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
      type == 'chat.read.updated' ||
      type == 'chat.typing.updated';

  bool get isNotificationEvent => type == 'notification.created';

  bool get isCallEvent =>
      type == 'call.invite.created' || type == 'call.state.updated';

  bool get isPresenceEvent =>
      type == 'connection.ready' || type == 'presence.updated';

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
  })  : _authService = authService,
        _runtimeConfig = runtimeConfig,
        _channelFactory = channelFactory ?? WebSocketChannel.connect,
        _reconnectDelay = reconnectDelay ?? const Duration(seconds: 3);

  final CustomApiAuthService _authService;
  final BackendRuntimeConfig _runtimeConfig;
  final WebSocketChannelFactory _channelFactory;
  final Duration _reconnectDelay;
  final StreamController<CustomApiRealtimeEvent> _eventsController =
      StreamController<CustomApiRealtimeEvent>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSubscription;
  Timer? _reconnectTimer;
  bool _isConnecting = false;
  bool _disposed = false;

  Stream<CustomApiRealtimeEvent> get events => _eventsController.stream;

  Future<void> connect() async {
    if (_disposed || _isConnecting || _channel != null) {
      return;
    }

    final accessToken = _authService.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      return;
    }

    _isConnecting = true;
    try {
      final uri = _buildUri(accessToken);
      final channel = _channelFactory(uri);
      await channel.ready;
      _channel = channel;
      _channelSubscription = channel.stream.listen(
        _handleEvent,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
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

  Uri _buildUri(String accessToken) {
    final normalizedBase = _runtimeConfig.webSocketBaseUrl.replaceAll(
      RegExp(r'/$'),
      '',
    );
    return Uri.parse(
      '$normalizedBase/v1/realtime?accessToken=$accessToken',
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

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () {
      unawaited(connect());
    });
  }
}
