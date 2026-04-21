import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../backend/interfaces/call_service_interface.dart';
import '../models/call_event.dart';
import '../models/call_invite.dart';
import '../models/call_media_mode.dart';
import '../models/call_state.dart';
import 'custom_api_realtime_service.dart';
import 'rustore_service.dart';

typedef MediaPermissionRequester = Future<bool> Function(
  CallMediaMode mediaMode,
);

class CallCoordinatorService extends ChangeNotifier
    with WidgetsBindingObserver {
  CallCoordinatorService({
    required CallServiceInterface callService,
    CustomApiRealtimeService? realtimeService,
    Stream<RustorePushMessage>? pushMessages,
    MediaPermissionRequester? mediaPermissionRequester,
    Duration ringingRecoveryInterval = const Duration(seconds: 5),
  })  : _callService = callService,
        _realtimeService = realtimeService,
        _pushMessages = pushMessages,
        _ringingRecoveryInterval = ringingRecoveryInterval,
        _mediaPermissionRequester =
            mediaPermissionRequester ?? _requestPlatformMediaPermissions {
    WidgetsFlutterBinding.ensureInitialized();
    WidgetsBinding.instance.addObserver(this);
    _callEventsSubscription = _callService.events.listen(_handleCallEvent);
    final activeRealtimeService = _realtimeService;
    if (activeRealtimeService != null) {
      _realtimeSubscription = activeRealtimeService.events.listen((event) {
        if (event.type == 'connection.ready') {
          unawaited(resync());
        }
      });
    }
    final activePushMessages = _pushMessages;
    if (activePushMessages != null) {
      _pushSubscription = activePushMessages.listen(_handlePushMessage);
    }
    unawaited(ensureRuntimeReady());
  }

  final CallServiceInterface _callService;
  final CustomApiRealtimeService? _realtimeService;
  final Stream<RustorePushMessage>? _pushMessages;
  final MediaPermissionRequester _mediaPermissionRequester;
  final Duration _ringingRecoveryInterval;

  StreamSubscription<CallEvent>? _callEventsSubscription;
  StreamSubscription<CustomApiRealtimeEvent>? _realtimeSubscription;
  StreamSubscription<RustorePushMessage>? _pushSubscription;
  Future<void>? _runtimeReadyFuture;
  Timer? _ringingRecoveryTimer;
  String? _ringingRecoveryCallId;

  CallInvite? _currentCall;
  Room? _room;
  EventsListener<RoomEvent>? _roomListener;
  String? _connectedRoomName;
  bool _isConnectingRoom = false;
  bool _isReconnectingRoom = false;
  bool _microphoneEnabled = true;
  bool _cameraEnabled = false;
  String? _connectionError;
  bool _hasMediaPermissionIssue = false;
  bool _hasSeenRemoteParticipant = false;
  final Set<String> _visibleCallScreenIds = <String>{};

  String? get currentUserId => _callService.currentUserId;
  CallInvite? get currentCall => _currentCall;
  Room? get room => _room;
  bool get isConnectingRoom => _isConnectingRoom;
  bool get isReconnectingRoom => _isReconnectingRoom;
  bool get microphoneEnabled => _microphoneEnabled;
  bool get cameraEnabled => _cameraEnabled;
  String? get connectionError => _connectionError;
  bool get hasMediaPermissionIssue => _hasMediaPermissionIssue;

  bool isCallScreenVisible(String? callId) {
    if (callId == null || callId.isEmpty) {
      return false;
    }
    return _visibleCallScreenIds.contains(callId);
  }

  void setCallScreenVisible(
    String callId, {
    required bool isVisible,
  }) {
    if (callId.isEmpty) {
      return;
    }
    final hasChanged = isVisible
        ? _visibleCallScreenIds.add(callId)
        : _visibleCallScreenIds.remove(callId);
    if (hasChanged) {
      notifyListeners();
    }
  }

  Future<CallInvite?> hydrateIncomingCall({
    String? callId,
    String? chatId,
  }) async {
    final currentUser = currentUserId?.trim();
    if (currentUser == null || currentUser.isEmpty) {
      return null;
    }

    final activeCall = _currentCall;
    final normalizedCallId = callId?.trim();
    if (activeCall != null &&
        !activeCall.state.isTerminal &&
        (normalizedCallId == null ||
            normalizedCallId.isEmpty ||
            activeCall.id == normalizedCallId)) {
      return activeCall;
    }

    try {
      CallInvite? nextCall;
      if (normalizedCallId != null && normalizedCallId.isNotEmpty) {
        nextCall = await _callService.getCall(normalizedCallId);
      }
      nextCall ??= await _callService.getActiveCall(chatId: chatId?.trim());
      nextCall ??= await _callService.getActiveCall();
      if (nextCall == null || nextCall.state.isTerminal) {
        return null;
      }
      await _applyCall(nextCall);
      return nextCall;
    } catch (_) {
      return null;
    }
  }

  Future<void> activateCall(CallInvite call) async {
    await _applyCall(call);
  }

  Future<void> ensureRuntimeReady() {
    final existingFuture = _runtimeReadyFuture;
    if (existingFuture != null) {
      return existingFuture;
    }

    final completer = Completer<void>();
    _runtimeReadyFuture = completer.future;
    unawaited(() async {
      try {
        await _callService.startRealtimeBridge();
        await resync();
        completer.complete();
      } catch (error, stackTrace) {
        _runtimeReadyFuture = null;
        completer.completeError(error, stackTrace);
      }
    }());
    return completer.future;
  }

  Future<CallInvite?> getCall(String callId) {
    return _callService.getCall(callId);
  }

  Future<CallInvite?> getActiveCall({String? chatId}) {
    return _callService.getActiveCall(chatId: chatId);
  }

  Future<CallInvite?> resync({String? chatId}) async {
    final activeCall = await _callService.getActiveCall(chatId: chatId);
    if (activeCall == null) {
      if (chatId == null || _currentCall?.chatId == chatId) {
        await _applyCall(null);
      }
      return null;
    }

    await _applyCall(activeCall);
    return activeCall;
  }

  Future<CallInvite?> refreshCurrentCall() async {
    final currentCall = _currentCall;
    if (currentCall == null) {
      return null;
    }
    final refreshedCall = await _callService.getCall(currentCall.id);
    await _applyCall(refreshedCall);
    return refreshedCall;
  }

  Future<CallInvite> startCall({
    required String chatId,
    required CallMediaMode mediaMode,
  }) async {
    final invite = await _callService.startCall(
      chatId: chatId,
      mediaMode: mediaMode,
    );
    await _applyCall(invite);
    return invite;
  }

  Future<CallInvite> acceptCall([String? callId]) async {
    final resolvedCallId = callId ?? _currentCall?.id;
    if (resolvedCallId == null || resolvedCallId.isEmpty) {
      throw StateError('Нет активного звонка для принятия.');
    }
    final invite = await _callService.acceptCall(resolvedCallId);
    await _applyCall(invite);
    return invite;
  }

  Future<CallInvite?> finishCall([String? callId]) async {
    final activeCall = _currentCall;
    final resolvedCallId = callId ?? activeCall?.id;
    if (resolvedCallId == null || resolvedCallId.isEmpty) {
      return null;
    }

    CallInvite? result;
    final callToFinish = resolvedCallId == activeCall?.id
        ? activeCall
        : await _callService.getCall(resolvedCallId);
    if (callToFinish == null) {
      await _applyCall(null);
      return null;
    }

    if (callToFinish.state == CallState.ringing) {
      if (callToFinish.isIncomingFor(currentUserId ?? '')) {
        result = await _callService.rejectCall(resolvedCallId);
      } else {
        result = await _callService.cancelCall(resolvedCallId);
      }
    } else if (callToFinish.state == CallState.active) {
      result = await _callService.hangUp(resolvedCallId);
    } else {
      result = callToFinish;
    }

    await _applyCall(result);
    return result;
  }

  Future<void> toggleMicrophone() async {
    final room = _room;
    if (room == null) {
      return;
    }

    final nextValue = !_microphoneEnabled;
    await room.localParticipant?.setMicrophoneEnabled(nextValue);
    _microphoneEnabled = nextValue;
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    final room = _room;
    final activeCall = _currentCall;
    if (room == null || activeCall == null || !activeCall.mediaMode.isVideo) {
      return;
    }

    final nextValue = !_cameraEnabled;
    await room.localParticipant?.setCameraEnabled(nextValue);
    _cameraEnabled = nextValue;
    notifyListeners();
  }

  Future<void> _applyCall(CallInvite? nextCall) async {
    final currentCall = _currentCall;
    if (nextCall == null) {
      _cancelRingingRecovery();
      _currentCall = null;
      _isConnectingRoom = false;
      _isReconnectingRoom = false;
      _connectionError = null;
      _hasMediaPermissionIssue = false;
      _hasSeenRemoteParticipant = false;
      notifyListeners();
      await _disposeRoom();
      return;
    }

    if (_shouldIgnoreCallSnapshot(nextCall)) {
      return;
    }

    if (nextCall.state.isTerminal) {
      if (currentCall == null || currentCall.id != nextCall.id) {
        return;
      }
      _cancelRingingRecovery();
      _currentCall = null;
      _isConnectingRoom = false;
      _isReconnectingRoom = false;
      _connectionError = null;
      _hasMediaPermissionIssue = false;
      _hasSeenRemoteParticipant = false;
      notifyListeners();
      await _disposeRoom();
      return;
    }

    final previousCallId = _currentCall?.id;
    final previousRoomName = _connectedRoomName;
    _currentCall = nextCall;
    if (nextCall.state == CallState.ringing) {
      _scheduleRingingRecovery(nextCall);
    } else {
      _cancelRingingRecovery();
    }
    if (previousCallId != nextCall.id) {
      _connectionError = null;
      _hasMediaPermissionIssue = false;
      _hasSeenRemoteParticipant = false;
    }
    if (!nextCall.mediaMode.isVideo) {
      _cameraEnabled = false;
    }
    notifyListeners();

    if (nextCall.state == CallState.active) {
      if (_hasMediaPermissionIssue &&
          previousCallId == nextCall.id &&
          _room == null) {
        notifyListeners();
        return;
      }
      final shouldReconnect = previousCallId == nextCall.id &&
          previousRoomName != null &&
          _room == null;
      await _ensureConnected(nextCall, reconnect: shouldReconnect);
      return;
    }

    if (previousCallId != null && previousCallId != nextCall.id) {
      await _disposeRoom();
    }
  }

  void _scheduleRingingRecovery(CallInvite call) {
    if (_ringingRecoveryInterval <= Duration.zero) {
      return;
    }
    if (_ringingRecoveryCallId == call.id &&
        _ringingRecoveryTimer?.isActive == true) {
      return;
    }
    _cancelRingingRecovery();
    _ringingRecoveryCallId = call.id;
    _ringingRecoveryTimer = Timer.periodic(_ringingRecoveryInterval, (_) {
      unawaited(_refreshRingingCall(call.id));
    });
  }

  void _cancelRingingRecovery() {
    _ringingRecoveryTimer?.cancel();
    _ringingRecoveryTimer = null;
    _ringingRecoveryCallId = null;
  }

  Future<void> _refreshRingingCall(String callId) async {
    final activeCall = _currentCall;
    if (activeCall == null ||
        activeCall.id != callId ||
        activeCall.state != CallState.ringing) {
      _cancelRingingRecovery();
      return;
    }

    try {
      final refreshedCall = await _callService.getCall(callId);
      if (_currentCall == null || _currentCall!.id != callId) {
        return;
      }
      if (refreshedCall != null) {
        await _applyCall(refreshedCall);
        return;
      }

      final refreshedActiveCall =
          await _callService.getActiveCall(chatId: activeCall.chatId);
      if (_currentCall == null || _currentCall!.id != callId) {
        return;
      }
      if (refreshedActiveCall == null || refreshedActiveCall.id != callId) {
        await _applyCall(null);
        return;
      }
      await _applyCall(refreshedActiveCall);
    } catch (_) {
      // Keep the current ringing state and retry on the next interval.
    }
  }

  Future<void> _ensureConnected(
    CallInvite call, {
    bool reconnect = false,
  }) async {
    final session = call.session;
    if (session == null ||
        session.url.trim().isEmpty ||
        session.token.trim().isEmpty) {
      _connectionError = 'Сеанс звонка ещё готовится.';
      _isConnectingRoom = false;
      _isReconnectingRoom = false;
      notifyListeners();
      return;
    }

    if (_room != null && _connectedRoomName == session.roomName) {
      return;
    }
    if (_isConnectingRoom || _isReconnectingRoom) {
      return;
    }

    if (reconnect) {
      _isReconnectingRoom = true;
    } else {
      _isConnectingRoom = true;
    }
    _connectionError = null;
    _hasMediaPermissionIssue = false;
    notifyListeners();

    final hasMediaPermissions =
        await _mediaPermissionRequester.call(call.mediaMode);
    if (!hasMediaPermissions) {
      _hasMediaPermissionIssue = true;
      _connectionError =
          'Нет доступа к микрофону или камере. Разрешите доступ в настройках приложения.';
      _isConnectingRoom = false;
      _isReconnectingRoom = false;
      notifyListeners();
      return;
    }

    await _disposeRoom();

    final room = Room();
    final listener = room.createListener();
    listener
      ..on<RoomDisconnectedEvent>((_) {
        unawaited(_handleRoomDisconnected());
      })
      ..on<RoomReconnectingEvent>((_) {
        _isReconnectingRoom = true;
        _connectionError = 'Связь прервалась. Переподключаем...';
        notifyListeners();
      })
      ..on<RoomReconnectedEvent>((_) {
        _isReconnectingRoom = false;
        _connectionError = null;
        notifyListeners();
      })
      ..on<ParticipantConnectedEvent>((_) {
        _hasSeenRemoteParticipant = true;
        notifyListeners();
      })
      ..on<ParticipantDisconnectedEvent>((_) {
        unawaited(_handleRemoteParticipantDisconnected());
      })
      ..on<ParticipantEvent>((_) {
        notifyListeners();
      })
      ..on<RoomEvent>((_) {
        notifyListeners();
      });

    try {
      await room.connect(session.url, session.token);
      _microphoneEnabled = true;
      _cameraEnabled = call.mediaMode.isVideo;
      await room.localParticipant?.setMicrophoneEnabled(_microphoneEnabled);
      if (call.mediaMode.isVideo) {
        await room.localParticipant?.setCameraEnabled(_cameraEnabled);
      }
      _connectionError = null;
      _hasMediaPermissionIssue = false;
      _hasSeenRemoteParticipant = room.remoteParticipants.isNotEmpty;
      _room = room;
      _roomListener = listener;
      _connectedRoomName = session.roomName;
    } catch (error) {
      await listener.dispose();
      await room.dispose();
      _hasMediaPermissionIssue = _looksLikeMediaPermissionIssue(error);
      _connectionError = _hasMediaPermissionIssue
          ? 'Нет доступа к микрофону или камере. Разрешите доступ в настройках приложения.'
          : 'Не удалось подключиться к звонку.';
    } finally {
      _isConnectingRoom = false;
      _isReconnectingRoom = false;
      notifyListeners();
    }
  }

  Future<void> _handleRoomDisconnected() async {
    await _disposeRoom();

    final activeCall = _currentCall;
    if (activeCall == null || activeCall.state != CallState.active) {
      notifyListeners();
      return;
    }
    if (_hasMediaPermissionIssue) {
      notifyListeners();
      return;
    }

    _connectionError = 'Связь прервалась. Переподключаем...';
    _isReconnectingRoom = true;
    notifyListeners();
    await refreshCurrentCall();
  }

  Future<void> _handleRemoteParticipantDisconnected() async {
    final activeCall = _currentCall;
    final room = _room;
    if (activeCall == null ||
        activeCall.state != CallState.active ||
        room == null) {
      notifyListeners();
      return;
    }
    if (!_hasSeenRemoteParticipant || room.remoteParticipants.isNotEmpty) {
      notifyListeners();
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (_currentCall?.id != activeCall.id || _room == null) {
      return;
    }
    if (_room!.remoteParticipants.isNotEmpty) {
      notifyListeners();
      return;
    }
    await refreshCurrentCall();
  }

  bool _looksLikeMediaPermissionIssue(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('permission') ||
        message.contains('microphone') ||
        message.contains('camera') ||
        message.contains('device');
  }

  static Future<bool> _requestPlatformMediaPermissions(
    CallMediaMode mediaMode,
  ) async {
    if (kIsWeb) {
      return true;
    }
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return true;
    }

    final microphoneStatus = await Permission.microphone.request();
    if (!(microphoneStatus.isGranted || microphoneStatus.isLimited)) {
      return false;
    }
    if (!mediaMode.isVideo) {
      return true;
    }

    final cameraStatus = await Permission.camera.request();
    return cameraStatus.isGranted || cameraStatus.isLimited;
  }

  void _handleCallEvent(CallEvent event) {
    unawaited(_applyCall(event.call));
  }

  void _handlePushMessage(RustorePushMessage message) {
    if (!message.isCallInvite) {
      return;
    }
    unawaited(
      hydrateIncomingCall(
        callId: message.callId,
        chatId: message.chatId,
      ),
    );
  }

  bool _shouldIgnoreCallSnapshot(CallInvite nextCall) {
    final currentCall = _currentCall;
    if (currentCall == null) {
      return false;
    }
    if (currentCall.id != nextCall.id) {
      return nextCall.state.isTerminal;
    }

    final currentUpdatedAt = currentCall.updatedAt.millisecondsSinceEpoch;
    final nextUpdatedAt = nextCall.updatedAt.millisecondsSinceEpoch;
    if (nextUpdatedAt < currentUpdatedAt) {
      return true;
    }
    if (nextUpdatedAt > currentUpdatedAt) {
      return false;
    }

    final currentRank = _callStatePriority(currentCall);
    final nextRank = _callStatePriority(nextCall);
    if (nextRank < currentRank) {
      return true;
    }

    if (currentCall.state == CallState.active &&
        nextCall.state == CallState.active &&
        currentCall.session != null &&
        nextCall.session == null) {
      return true;
    }

    return false;
  }

  int _callStatePriority(CallInvite call) {
    if (call.state == CallState.active) {
      return call.session != null ? 4 : 3;
    }
    if (call.state == CallState.ringing) {
      return 2;
    }
    return 1;
  }

  Future<void> _disposeRoom() async {
    await _roomListener?.dispose();
    _roomListener = null;
    if (_room != null) {
      await _room!.disconnect();
      await _room!.dispose();
    }
    _room = null;
    _connectedRoomName = null;
    _hasSeenRemoteParticipant = false;
  }

  Future<void> reset() async {
    _cancelRingingRecovery();
    _currentCall = null;
    _connectionError = null;
    _isConnectingRoom = false;
    _isReconnectingRoom = false;
    _microphoneEnabled = true;
    _cameraEnabled = false;
    _hasMediaPermissionIssue = false;
    _hasSeenRemoteParticipant = false;
    await _disposeRoom();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_hasMediaPermissionIssue) {
        _hasMediaPermissionIssue = false;
        _connectionError = null;
      }
      unawaited(ensureRuntimeReady().then((_) => resync()));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelRingingRecovery();
    unawaited(_callEventsSubscription?.cancel());
    unawaited(_realtimeSubscription?.cancel());
    unawaited(_pushSubscription?.cancel());
    unawaited(_disposeRoom());
    super.dispose();
  }
}
