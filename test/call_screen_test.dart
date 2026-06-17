import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:rodnya/backend/interfaces/chat_service_interface.dart';
import 'package:rodnya/backend/interfaces/call_service_interface.dart';
import 'package:rodnya/models/chat_attachment.dart';
import 'package:rodnya/models/chat_details.dart';
import 'package:rodnya/models/chat_message.dart' as rodnya_chat;
import 'package:rodnya/models/chat_preview.dart';
import 'package:rodnya/models/chat_send_progress.dart';
import 'package:rodnya/models/call_event.dart';
import 'package:rodnya/models/call_invite.dart';
import 'package:rodnya/models/call_media_mode.dart';
import 'package:rodnya/models/call_state.dart';
import 'package:rodnya/screens/call_screen.dart';
import 'package:rodnya/services/audio_route_service.dart';
import 'package:rodnya/services/call_coordinator_service.dart';
import 'package:rodnya/services/call_pip_service.dart';

void main() {
  testWidgets(
    'CallScreen shows settings CTA and hides media toggles when media permission is denied',
    (tester) async {
      final coordinator = _FakeCallCoordinator(
        call:
            _buildCall(state: CallState.active, mediaMode: CallMediaMode.video),
        connectionErrorValue:
            'Нет доступа к микрофону или камере. Разрешите доступ в настройках приложения.',
        hasMediaPermissionIssueValue: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CallScreen(
            initialCall: coordinator.currentCall!,
            title: 'Web QA',
            coordinator: coordinator,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Открыть настройки'), findsOneWidget);
      expect(find.textContaining('Нет доступа к микрофону'), findsOneWidget);
      expect(find.byTooltip('Выключить микрофон'), findsNothing);
      expect(find.byTooltip('Выключить камеру'), findsNothing);
      expect(find.byTooltip('Завершить звонок'), findsOneWidget);
    },
  );

  testWidgets('CallScreen falls back to initial for non-network avatar URLs',
      (tester) async {
    final coordinator = _FakeCallCoordinator(
      call: _buildCall(state: CallState.ringing),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CallScreen(
          initialCall: coordinator.currentCall!,
          title: 'Нина',
          coordinator: coordinator,
          photoUrl: 'avatar.jpg',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Нина'), findsOneWidget);
    expect(find.text('Н'), findsOneWidget);
  });

  testWidgets('CallScreen opens audio route picker for active calls',
      (tester) async {
    final selectedRoutes = <String>[];
    final audioRoutes = AudioRouteService(
      // CA1: тест инъектит selectAudioRoute (LiveKit-путь) — на android
      // (платформа теста) без этого создался бы реальный NativeCallAudio
      // и selectRoute ушёл бы в натив мимо инъекции.
      enableNativeAudio: false,
      initialRoutes: const <AudioRouteOption>[
        AudioRouteOption(
          id: 'speaker',
          label: 'Динамик',
          type: AudioRouteType.speaker,
        ),
        AudioRouteOption(
          id: 'earpiece',
          label: 'Наушник',
          type: AudioRouteType.earpiece,
        ),
      ],
      initialSelectedRouteId: 'speaker',
      enumerateAudioOutputs: () async => const <MediaDevice>[],
      selectAudioRoute: (option, _) async {
        selectedRoutes.add(option.id);
      },
      deviceChanges: const Stream<List<MediaDevice>>.empty(),
    );
    final room = _FakeRoom();
    addTearDown(() async {
      audioRoutes.dispose();
    });
    final coordinator = _FakeCallCoordinator(
      call: _buildCall(state: CallState.active),
      roomValue: room,
      audioRouteServiceValue: audioRoutes,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CallScreen(
          initialCall: coordinator.currentCall!,
          title: 'Web QA',
          coordinator: coordinator,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Аудиовыход: Динамик'), findsOneWidget);

    await tester.tap(find.byTooltip('Аудиовыход: Динамик'));
    await tester.pumpAndSettle();

    expect(find.text('Аудиовыход'), findsOneWidget);
    expect(find.text('Динамик'), findsOneWidget);
    expect(find.text('Наушник'), findsOneWidget);

    await tester.tap(find.text('Наушник'));
    await tester.pumpAndSettle();

    expect(selectedRoutes, ['earpiece']);
    expect(audioRoutes.selectedRouteId, 'earpiece');
  });

  testWidgets('CallScreen exposes camera switch for active video calls',
      (tester) async {
    final coordinator = _FakeCallCoordinator(
      call: _buildCall(state: CallState.active, mediaMode: CallMediaMode.video),
      roomValue: _FakeRoom(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CallScreen(
          initialCall: coordinator.currentCall!,
          title: 'Web QA',
          coordinator: coordinator,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Переключить камеру'), findsOneWidget);

    await tester.tap(find.byTooltip('Переключить камеру'));
    await tester.pumpAndSettle();

    expect(coordinator.switchCameraCallCount, 1);
    expect(coordinator.cameraPosition, CameraPosition.back);
  });

  testWidgets('CallScreen opens microphone and camera device picker',
      (tester) async {
    final coordinator = _FakeCallCoordinator(
      call: _buildCall(state: CallState.active, mediaMode: CallMediaMode.video),
      roomValue: _FakeRoom(),
      microphoneDevicesValue: const <MediaDevice>[
        MediaDevice('mic-usb', 'USB mic', 'audioinput', null),
      ],
      cameraDevicesValue: const <MediaDevice>[
        MediaDevice('camera-front', 'Front Camera', 'videoinput', null),
        MediaDevice('camera-back', 'Back Camera', 'videoinput', null),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CallScreen(
          initialCall: coordinator.currentCall!,
          title: 'Web QA',
          coordinator: coordinator,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Источники звука и видео'));
    await tester.pumpAndSettle();

    expect(find.text('Источники звука и видео'), findsOneWidget);
    expect(find.text('USB mic'), findsOneWidget);
    expect(find.text('Front Camera'), findsOneWidget);
    expect(find.text('Back Camera'), findsOneWidget);

    await tester.tap(find.text('USB mic'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back Camera'));
    await tester.pumpAndSettle();

    expect(coordinator.selectedMicrophoneDeviceId, 'mic-usb');
    expect(coordinator.selectedCameraDeviceId, 'camera-back');
    expect(coordinator.selectedMicrophoneCallCount, 1);
    expect(coordinator.selectedCameraCallCount, 1);
  });

  testWidgets('CallScreen shows connection quality for active calls',
      (tester) async {
    final coordinator = _FakeCallCoordinator(
      call: _buildCall(state: CallState.active),
      roomValue: _FakeRoom(),
      connectionQualityValue: ConnectionQuality.good,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CallScreen(
          initialCall: coordinator.currentCall!,
          title: 'Web QA',
          coordinator: coordinator,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Связь хорошая'), findsOneWidget);
    expect(find.byTooltip('Связь хорошая'), findsWidgets);
  });

  testWidgets('CallScreen shows reconnect banner during room reconnect',
      (tester) async {
    final coordinator = _FakeCallCoordinator(
      call: _buildCall(state: CallState.active),
      roomValue: _FakeRoom(),
      connectionQualityValue: ConnectionQuality.lost,
      isReconnectingRoomValue: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CallScreen(
          initialCall: coordinator.currentCall!,
          title: 'Web QA',
          coordinator: coordinator,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Восстанавливаем соединение...'), findsOneWidget);
    expect(find.text('Переподключение'), findsOneWidget);
    expect(
      find.text('Восстанавливаем звонок. Звук вернётся автоматически.'),
      findsOneWidget,
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('CallScreen shows waiting status for active group calls',
      (tester) async {
    final coordinator = _FakeCallCoordinator(
      call: _buildCall(
        state: CallState.active,
        participantIds: const ['user-1', 'user-2', 'user-3'],
      ),
      roomValue: _FakeRoom(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CallScreen(
          initialCall: coordinator.currentCall!,
          title: 'Семейный созвон',
          coordinator: coordinator,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Семейный созвон'), findsOneWidget);
    expect(find.text('Ожидаем участников звонка...'), findsOneWidget);
  });

  testWidgets('CallScreen shows group roster and nudges waiting members',
      (tester) async {
    final coordinator = _FakeCallCoordinator(
      call: _buildCall(
        state: CallState.active,
        participantIds: const ['user-1', 'user-2', 'user-3'],
      ),
      roomValue: _FakeRoom(),
    );
    final chatService = _FakeInCallChatService(
      messages: const <rodnya_chat.ChatMessage>[],
      details: ChatDetails(
        chatId: 'chat-1',
        type: 'group',
        title: 'Семейный созвон',
        participantIds: const ['user-1', 'user-2', 'user-3'],
        participants: const <ChatParticipantSummary>[
          ChatParticipantSummary(userId: 'user-1', displayName: 'Арина'),
          ChatParticipantSummary(userId: 'user-2', displayName: 'Борис'),
          ChatParticipantSummary(userId: 'user-3', displayName: 'Вера'),
        ],
        branchRoots: const <ChatBranchRootSummary>[],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CallScreen(
          initialCall: coordinator.currentCall!,
          title: 'Семейный созвон',
          coordinator: coordinator,
          chatService: chatService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Вы'), findsOneWidget);
    expect(find.text('Борис'), findsOneWidget);
    expect(find.text('Вера'), findsOneWidget);
    expect(find.text('1 в звонке · 2 ждут'), findsOneWidget);
    expect(find.text('Ждём'), findsNWidgets(2));

    await tester.tap(find.text('Позвать ещё'));
    await tester.pumpAndSettle();

    expect(coordinator.nudgeCallCount, 1);
    expect(
      coordinator.nudgedParticipantIds,
      unorderedEquals(<String>['user-2', 'user-3']),
    );
  });

  testWidgets('CallScreen opens in-call chat sheet and sends a text message',
      (tester) async {
    final coordinator = _FakeCallCoordinator(
      call: _buildCall(state: CallState.active),
      roomValue: _FakeRoom(),
    );
    final chatService = _FakeInCallChatService(
      messages: <rodnya_chat.ChatMessage>[
        rodnya_chat.ChatMessage(
          id: 'msg-1',
          chatId: 'chat-1',
          senderId: 'user-2',
          senderName: 'Нина',
          text: 'Я на связи',
          timestamp: DateTime(2026, 5, 1, 12),
          isRead: false,
          participants: const ['user-1', 'user-2'],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CallScreen(
          initialCall: coordinator.currentCall!,
          title: 'Web QA',
          coordinator: coordinator,
          chatService: chatService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Чат во время звонка'));
    await tester.pumpAndSettle();

    expect(find.text('Чат во время звонка'), findsOneWidget);
    expect(find.text('Я на связи'), findsOneWidget);
    expect(chatService.markReadCalls, 1);

    await tester.enterText(find.byType(TextField).last, 'Минуту');
    await tester.tap(find.byTooltip('Отправить'));
    await tester.pumpAndSettle();

    expect(chatService.sentTexts, ['Минуту']);
  });

  testWidgets('CallScreen pops when coordinator clears the active call',
      (tester) async {
    final coordinator = _FakeCallCoordinator(
      call: _buildCall(state: CallState.active),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CallScreen(
                    initialCall: coordinator.currentCall!,
                    title: 'Web QA',
                    coordinator: coordinator,
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Web QA'), findsOneWidget);

    coordinator.clearCall();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(CallScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('CallScreen requests Android PiP when minimizing active call',
      (tester) async {
    final coordinator = _FakeCallCoordinator(
      call: _buildCall(state: CallState.active),
    );
    final pipService = _FakeCallPipService();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CallScreen(
                    initialCall: coordinator.currentCall!,
                    title: 'Web QA',
                    coordinator: coordinator,
                    pipService: pipService,
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Свернуть звонок'));
    await tester.pumpAndSettle();

    expect(pipService.enterCalls, 1);
    expect(find.byType(CallScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  group('G1: подпись плитки участника группового звонка', () {
    test('показывает имя участника, когда оно есть', () {
      expect(
        resolveRemoteParticipantLabel(
          name: 'Наталья',
          identity: 'user-42',
          index: 0,
        ),
        'Наталья',
      );
    });

    test('фолбэк на identity, когда имя пустое', () {
      expect(
        resolveRemoteParticipantLabel(
          name: '   ',
          identity: 'user-42',
          index: 1,
        ),
        'user-42',
      );
    });

    test('фолбэк на «Участник N», когда нет ни имени, ни identity', () {
      expect(
        resolveRemoteParticipantLabel(name: '', identity: '', index: 2),
        'Участник 3',
      );
    });
  });
}

CallInvite _buildCall({
  required CallState state,
  CallMediaMode mediaMode = CallMediaMode.audio,
  List<String> participantIds = const ['user-1', 'user-2'],
}) {
  return CallInvite(
    id: 'call-1',
    chatId: 'chat-1',
    initiatorId: 'user-1',
    recipientId: 'user-2',
    participantIds: participantIds,
    mediaMode: mediaMode,
    state: state,
    createdAt: DateTime(2026, 4, 20, 10),
    updatedAt: DateTime(2026, 4, 20, 10, 1),
  );
}

class _FakeCallCoordinator extends CallCoordinatorService {
  _FakeCallCoordinator({
    required CallInvite call,
    this.connectionErrorValue,
    this.hasMediaPermissionIssueValue = false,
    Room? roomValue,
    AudioRouteService? audioRouteServiceValue,
    CameraPosition cameraPositionValue = CameraPosition.front,
    List<MediaDevice> microphoneDevicesValue = const <MediaDevice>[],
    List<MediaDevice> cameraDevicesValue = const <MediaDevice>[],
    ConnectionQuality connectionQualityValue = ConnectionQuality.unknown,
    bool isReconnectingRoomValue = false,
    bool showReconnectRestoredBannerValue = false,
  })  : _currentCall = call,
        _room = roomValue,
        _cameraPosition = cameraPositionValue,
        _microphoneDevices = microphoneDevicesValue,
        _cameraDevices = cameraDevicesValue,
        _connectionQuality = connectionQualityValue,
        _isReconnectingRoom = isReconnectingRoomValue,
        _showReconnectRestoredBanner = showReconnectRestoredBannerValue,
        _selectedMicrophoneDeviceId = microphoneDevicesValue.isEmpty
            ? null
            : microphoneDevicesValue.first.deviceId,
        _selectedCameraDeviceId = cameraDevicesValue.isEmpty
            ? null
            : cameraDevicesValue.first.deviceId,
        _audioRouteService = audioRouteServiceValue ??
            AudioRouteService(
              enableNativeAudio: false,
              initialRoutes: const <AudioRouteOption>[
                AudioRouteOption(
                  id: 'speaker',
                  label: 'Динамик',
                  type: AudioRouteType.speaker,
                ),
              ],
              initialSelectedRouteId: 'speaker',
              enumerateAudioOutputs: () async => const <MediaDevice>[],
              selectAudioRoute: (_, __) async {},
              deviceChanges: const Stream<List<MediaDevice>>.empty(),
            ),
        super(callService: _FakeCallService());

  CallInvite? _currentCall;
  final Room? _room;
  final AudioRouteService _audioRouteService;
  CameraPosition _cameraPosition;
  final List<MediaDevice> _microphoneDevices;
  final List<MediaDevice> _cameraDevices;
  final ConnectionQuality _connectionQuality;
  final bool _isReconnectingRoom;
  final bool _showReconnectRestoredBanner;
  String? _selectedMicrophoneDeviceId;
  String? _selectedCameraDeviceId;
  final String? connectionErrorValue;
  final bool hasMediaPermissionIssueValue;
  int switchCameraCallCount = 0;
  int refreshInputDevicesCallCount = 0;
  int selectedMicrophoneCallCount = 0;
  int selectedCameraCallCount = 0;
  int nudgeCallCount = 0;
  List<String>? nudgedParticipantIds;

  @override
  String? get currentUserId => 'user-1';

  @override
  CallInvite? get currentCall => _currentCall;

  @override
  Room? get room => _room;

  @override
  AudioRouteService get audioRouteService => _audioRouteService;

  @override
  bool get isReconnectingRoom => _isReconnectingRoom;

  @override
  ConnectionQuality get displayedConnectionQuality => _connectionQuality;

  @override
  bool get showReconnectRestoredBanner => _showReconnectRestoredBanner;

  @override
  String? get connectionError => connectionErrorValue;

  @override
  bool get hasMediaPermissionIssue => hasMediaPermissionIssueValue;

  @override
  bool get microphoneEnabled => true;

  @override
  bool get cameraEnabled => true;

  @override
  bool get isSwitchingCamera => false;

  @override
  CameraPosition get cameraPosition => _cameraPosition;

  @override
  List<MediaDevice> get microphoneDevices => _microphoneDevices;

  @override
  List<MediaDevice> get cameraDevices => _cameraDevices;

  @override
  String? get selectedMicrophoneDeviceId => _selectedMicrophoneDeviceId;

  @override
  String? get selectedCameraDeviceId => _selectedCameraDeviceId;

  @override
  bool get isRefreshingInputDevices => false;

  @override
  bool get isSelectingMediaDevice => false;

  @override
  String? get devicePickerErrorMessage => null;

  @override
  Future<void> switchCamera() async {
    switchCameraCallCount += 1;
    _cameraPosition = _cameraPosition.switched();
    notifyListeners();
  }

  @override
  Future<void> refreshInputDevices() async {
    refreshInputDevicesCallCount += 1;
    notifyListeners();
  }

  @override
  Future<void> selectMicrophoneDevice(MediaDevice device) async {
    selectedMicrophoneCallCount += 1;
    _selectedMicrophoneDeviceId = device.deviceId;
    notifyListeners();
  }

  @override
  Future<void> selectCameraDevice(MediaDevice device) async {
    selectedCameraCallCount += 1;
    _selectedCameraDeviceId = device.deviceId;
    if (device.deviceId.contains('back')) {
      _cameraPosition = CameraPosition.back;
    }
    notifyListeners();
  }

  void clearCall() {
    _currentCall = null;
    notifyListeners();
  }

  @override
  Future<void> activateCall(CallInvite call) async {
    _currentCall = call;
    notifyListeners();
  }

  @override
  Future<CallInvite> nudgeCallParticipants(
    String callId, {
    List<String>? participantIds,
  }) async {
    nudgeCallCount += 1;
    nudgedParticipantIds = participantIds;
    return _currentCall!;
  }
}

class _FakeRoom extends Fake implements Room {
  @override
  UnmodifiableMapView<String, RemoteParticipant> get remoteParticipants =>
      UnmodifiableMapView<String, RemoteParticipant>(
        const <String, RemoteParticipant>{},
      );

  @override
  LocalParticipant? get localParticipant => null;
}

class _FakeCallService implements CallServiceInterface {
  @override
  String? get currentUserId => 'user-1';

  @override
  Stream<CallEvent> get events => const Stream<CallEvent>.empty();

  @override
  Future<CallInvite> acceptCall(String callId) async => _buildCall(
        state: CallState.active,
      );

  @override
  Future<CallInvite> cancelCall(String callId) async => _buildCall(
        state: CallState.cancelled,
      );

  @override
  Future<CallInvite?> getActiveCall({String? chatId}) async => null;

  @override
  Future<CallInvite?> getCall(String callId) async => null;

  @override
  Future<CallInvite> hangUp(String callId) async => _buildCall(
        state: CallState.ended,
      );

  @override
  Future<CallInvite> rejectCall(String callId) async => _buildCall(
        state: CallState.rejected,
      );

  @override
  Future<void> startRealtimeBridge() async {}

  @override
  Future<CallInvite> startCall({
    required String chatId,
    required CallMediaMode mediaMode,
    List<String>? participantIds,
  }) async =>
      _buildCall(
        state: CallState.ringing,
        mediaMode: mediaMode,
      );

  @override
  Future<CallInvite> nudgeCallParticipants(
    String callId, {
    List<String>? participantIds,
  }) async =>
      _buildCall(state: CallState.ringing);

  @override
  Future<void> stopRealtimeBridge() async {}
}

class _FakeInCallChatService extends ChatServiceInterface {
  _FakeInCallChatService({
    required List<rodnya_chat.ChatMessage> messages,
    ChatDetails? details,
  })  : _messages = messages,
        _details = details;

  final List<rodnya_chat.ChatMessage> _messages;
  final ChatDetails? _details;
  final List<String> sentTexts = <String>[];
  int markReadCalls = 0;

  @override
  String? get currentUserId => 'user-1';

  @override
  String buildChatId(String otherUserId) => 'chat-$otherUserId';

  @override
  Stream<List<ChatPreview>> getUserChatsStream(String userId) {
    return Stream<List<ChatPreview>>.value(const <ChatPreview>[]);
  }

  @override
  Stream<int> getTotalUnreadCountStream(String userId) {
    return Stream<int>.value(0);
  }

  @override
  Stream<List<rodnya_chat.ChatMessage>> getMessagesStream(String chatId) {
    return Stream<List<rodnya_chat.ChatMessage>>.value(_messages);
  }

  @override
  Future<void> refreshMessages(String chatId) async {}

  @override
  Future<void> sendMessage({
    required String otherUserId,
    String text = '',
    List<XFile> attachments = const <XFile>[],
  }) async {}

  @override
  Future<void> sendMessageToChat({
    required String chatId,
    String text = '',
    List<XFile> attachments = const <XFile>[],
    List<ChatAttachment> forwardedAttachments = const <ChatAttachment>[],
    rodnya_chat.ChatReplyReference? replyTo,
    String? clientMessageId,
    int? expiresInSeconds,
    void Function(ChatSendProgress progress)? onProgress,
  }) async {
    sentTexts.add(text);
  }

  @override
  Future<void> markChatAsRead(String chatId, String userId) async {
    markReadCalls += 1;
  }

  @override
  Future<String?> getOrCreateChat(String otherUserId) async {
    return 'chat-$otherUserId';
  }

  @override
  Future<ChatDetails> getChatDetails(String chatId) async {
    final details = _details;
    if (details != null) {
      return details;
    }
    return ChatDetails(
      chatId: chatId,
      type: 'direct',
      participantIds: const <String>['user-1', 'user-2'],
      participants: const <ChatParticipantSummary>[
        ChatParticipantSummary(userId: 'user-1', displayName: 'Арина'),
        ChatParticipantSummary(userId: 'user-2', displayName: 'Нина'),
      ],
      branchRoots: const <ChatBranchRootSummary>[],
    );
  }
}

class _FakeCallPipService implements CallPipService {
  int enterCalls = 0;

  @override
  Future<bool> enterPictureInPicture({
    int aspectRatioWidth = 16,
    int aspectRatioHeight = 9,
  }) async {
    enterCalls += 1;
    return true;
  }
}
