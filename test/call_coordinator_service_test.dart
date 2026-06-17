import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:rodnya/backend/interfaces/call_service_interface.dart';
import 'package:rodnya/models/call_event.dart';
import 'package:rodnya/models/call_invite.dart';
import 'package:rodnya/models/call_media_mode.dart';
import 'package:rodnya/models/call_session.dart';
import 'package:rodnya/models/call_state.dart';
import 'package:rodnya/services/android_incoming_call_service.dart';
import 'package:rodnya/services/call_coordinator_service.dart';
import 'package:rodnya/services/call_foreground_service.dart';
import 'package:rodnya/services/call_preferences.dart';
import 'package:rodnya/services/rustore_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'CallCoordinatorService resyncs active call on resume even without a current call',
    () async {
      final service = _CountingCallService(
        activeCall: _buildCall(state: CallState.ringing),
      );
      final coordinator = CallCoordinatorService(callService: service);

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      service.resetCounters();

      coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(service.activeCallRequests, greaterThanOrEqualTo(1));
      expect(coordinator.currentCall?.id, 'call-1');

      coordinator.dispose();
    },
  );

  test(
    'CallCoordinatorService exposes media permission issue before room connect',
    () async {
      final service = _CountingCallService(activeCall: null);
      final coordinator = CallCoordinatorService(
        callService: service,
        mediaPermissionRequester: (_) async => false,
      );

      await coordinator.activateCall(
        _buildCall(
          state: CallState.active,
          session: const CallSession(
            roomName: 'room-1',
            url: 'wss://livekit.example.test',
            token: 'token-1',
            participantIdentity: 'user-1',
          ),
        ),
      );

      expect(coordinator.hasMediaPermissionIssue, isTrue);
      expect(
        coordinator.connectionError,
        'Нет доступа к микрофону или камере. Разрешите доступ в настройках приложения.',
      );
      expect(coordinator.isConnectingRoom, isFalse);
      expect(coordinator.room, isNull);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      coordinator.dispose();
    },
  );

  test(
    'CallCoordinatorService starts foreground service on active call '
    'and stops on terminal',
    () async {
      final service = _CountingCallService(activeCall: null);
      final foreground = _FakeCallForegroundService();
      final coordinator = CallCoordinatorService(
        callService: service,
        // mediaPermissionRequester denied — coordinator bail'нет ДО
        // room.connect, но foreground service start вызывается ПЕРЕД
        // _ensureConnected (Bug A fix design — mic capture survival
        // на Android 14+ требует service alive ДО mic publish).
        mediaPermissionRequester: (_) async => false,
        callForegroundService: foreground,
      );

      // Settle initial ensureRuntimeReady resync (constructor schedules
      // its own resync → _applyCall(null) → _stopForegroundService).
      // Без этого resync race'нётся с activateCall и стоп flush'ит
      // foreground service flag сразу после start, ломая assertion.
      await coordinator.ensureRuntimeReady();

      final activeCall = _buildCall(
        state: CallState.active,
        session: const CallSession(
          roomName: 'room-1',
          url: 'wss://livekit.example.test',
          token: 'token-1',
          participantIdentity: 'user-1',
        ),
      );

      // Reset counters перед activate, чтобы initial resync stop'ы
      // не learked в подсчёт.
      foreground.startCalls = 0;
      foreground.updateCalls = 0;
      foreground.stopCalls = 0;

      await coordinator.activateCall(activeCall);

      expect(foreground.startCalls, greaterThanOrEqualTo(1));
      expect(foreground.lastStartCallId, 'call-1');
      expect(foreground.lastStartIsVideo, isFalse);
      expect(foreground.lastStartMicEnabled, isTrue);

      // Reset stopCalls перед terminal transition, чтобы verify
      // что именно terminal triggered stop.
      foreground.stopCalls = 0;

      // Terminal transition → stop foreground service.
      final terminalCall = _buildCall(
        state: CallState.ended,
        updatedAt: DateTime(2026, 4, 20, 10, 5),
      );
      await coordinator.activateCall(terminalCall);

      expect(foreground.stopCalls, greaterThanOrEqualTo(1));

      await Future<void>.delayed(const Duration(milliseconds: 20));
      coordinator.dispose();
    },
  );

  test(
    'CallCoordinatorService stops foreground service на explicit reset',
    () async {
      final service = _CountingCallService(activeCall: null);
      final foreground = _FakeCallForegroundService();
      final coordinator = CallCoordinatorService(
        callService: service,
        mediaPermissionRequester: (_) async => false,
        callForegroundService: foreground,
      );

      await coordinator.ensureRuntimeReady();
      foreground.startCalls = 0;
      foreground.stopCalls = 0;

      await coordinator.activateCall(
        _buildCall(
          state: CallState.active,
          session: const CallSession(
            roomName: 'room-1',
            url: 'wss://livekit.example.test',
            token: 'token-1',
            participantIdentity: 'user-1',
          ),
        ),
      );
      expect(foreground.startCalls, greaterThanOrEqualTo(1));

      foreground.stopCalls = 0;
      await coordinator.reset();
      expect(foreground.stopCalls, greaterThanOrEqualTo(1));

      await Future<void>.delayed(const Duration(milliseconds: 20));
      coordinator.dispose();
    },
  );

  test(
    'CallCoordinatorService tracks only calls started by this app session',
    () async {
      final service = _CountingCallService(
        activeCall: _buildCall(state: CallState.ringing),
      );
      final coordinator = CallCoordinatorService(callService: service);

      await coordinator.ensureRuntimeReady();

      final startedCall = await coordinator.startCall(
        chatId: 'chat-1',
        mediaMode: CallMediaMode.audio,
      );

      expect(coordinator.isLocallyStartedCall(startedCall.id), isTrue);

      await coordinator.activateCall(
        startedCall.copyWith(
          state: CallState.cancelled,
          updatedAt: DateTime(2026, 4, 20, 10, 2),
          endedAt: DateTime(2026, 4, 20, 10, 2),
          endedReason: 'cancelled',
        ),
      );

      expect(coordinator.isLocallyStartedCall(startedCall.id), isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      coordinator.dispose();
    },
  );

  test(
    'CallCoordinatorService dismisses native incoming UI when call is answered elsewhere',
    () async {
      final incomingCall = _buildCall(state: CallState.ringing);
      final service = _CountingCallService(activeCall: null);
      final androidCalls = _FakeAndroidIncomingCallService(null);
      final coordinator = CallCoordinatorService(
        callService: service,
        androidIncomingCallService: androidCalls,
      );

      await coordinator.ensureRuntimeReady();

      await coordinator.activateCall(incomingCall);
      await Future<void>.delayed(Duration.zero);
      androidCalls.dismissedCallIds.clear();

      await coordinator.activateCall(
        incomingCall.copyWith(
          state: CallState.active,
          joinedOnAnotherDevice: true,
          updatedAt: DateTime(2026, 4, 20, 10, 2),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(androidCalls.dismissedCallIds, contains(incomingCall.id));

      await Future<void>.delayed(const Duration(milliseconds: 20));
      coordinator.dispose();
    },
  );

  test(
    'CallCoordinatorService Fix A: un-mute updates microphoneEnabled '
    'через debugApplyMediaSync mirror того что _publishLocalMicrophone '
    'success path should leave',
    () async {
      // Bug 2 repro: pre-fix toggleMicrophone enable path вызывал
      // _publishLocalMicrophone (which set _microphoneEnabled = false
      // only на failure) но НЕ sets к true на success — поле застревал
      // в false после mute, UI showed «mic off» хотя peer слышит.
      // Fix A добавил `_microphoneEnabled = published` после await.
      //
      // Unit test'е без real Room мы exercise эквивалентный путь:
      // debugApplyMediaSync соответствует тому же diff-detect логике
      // (mic enabled flag transitions от false к true когда LiveKit
      // truth == true).
      final service = _CountingCallService(activeCall: null);
      final coordinator = CallCoordinatorService(callService: service);

      // Simulate mute first — sets _microphoneEnabled = false
      coordinator.debugApplyMediaSync(micEnabled: false, camEnabled: false);
      expect(coordinator.microphoneEnabled, isFalse);

      // Simulate un-mute success — Fix A guarantees _microphoneEnabled
      // tracks LiveKit truth.
      coordinator.debugApplyMediaSync(micEnabled: true, camEnabled: false);
      expect(coordinator.microphoneEnabled, isTrue);

      coordinator.dispose();
    },
  );

  test(
    'CallCoordinatorService Fix B: _applyCall preserves cameraEnabled '
    'когда room считается connected (audio→video upgrade override)',
    () async {
      // Bug 3 repro: user в audio call activated camera локально через
      // toggleCamera (audio→video upgrade), preview появилось. Затем
      // recovery snapshot каждые 2s вызывал _applyCall(audioCall),
      // line 752 reset'ил _cameraEnabled = false → preview disappeared
      // хотя publication active → peer всё ещё видел.
      // Fix B обернул reset в `if (_room == null)` — preservation на
      // connected room. Unit test'е используем debugTreatRoomAsActive
      // чтобы exercise preservation path без real Room mock.
      final service = _CountingCallService(activeCall: null);
      final coordinator = CallCoordinatorService(
        callService: service,
        mediaPermissionRequester: (_) async => false,
      );

      await coordinator.ensureRuntimeReady();

      // Simulate locally-activated camera (audio→video upgrade)
      coordinator.debugSetCameraEnabled(true);
      coordinator.debugTreatRoomAsActive = true;
      expect(coordinator.cameraEnabled, isTrue);

      // Trigger _applyCall с audio mediaMode — recovery snapshot path.
      final audioCall = _buildCall(
        state: CallState.active,
        mediaMode: CallMediaMode.audio,
        session: const CallSession(
          roomName: 'room-1',
          url: 'wss://livekit.example.test',
          token: 'token-1',
          participantIdentity: 'user-1',
        ),
      );
      await coordinator.activateCall(audioCall);

      // Fix B: camera flag preserved потому что мы treat room as active.
      expect(coordinator.cameraEnabled, isTrue);

      // Sanity — без preservation flag _applyCall очистил бы.
      coordinator.debugTreatRoomAsActive = false;
      coordinator.debugSetCameraEnabled(true);
      await coordinator.activateCall(
        _buildCall(
          state: CallState.active,
          mediaMode: CallMediaMode.audio,
          updatedAt: DateTime(2026, 4, 20, 10, 10),
          session: const CallSession(
            roomName: 'room-1',
            url: 'wss://livekit.example.test',
            token: 'token-1',
            participantIdentity: 'user-1',
          ),
        ),
      );
      expect(coordinator.cameraEnabled, isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      coordinator.dispose();
    },
  );

  test(
    'CallCoordinatorService Q1 false-positive fix: media sync clears '
    'stale microphonePublishFailed когда mic actually published',
    () async {
      // Q1 false positive race (post-Bug A device-verify): Q1
      // immediate check фired snackbar когда LiveKit publication
      // table briefly empty между setMicrophoneEnabled return и
      // LocalTrackPublishedEvent fire. Fix C event listener corrected
      // _microphoneEnabled но не clear'ил _microphonePublishFailed
      // → banner persisted пока user не reset call.
      //
      // Defensive reconciliation в _syncMediaStateFromLiveKit clears
      // flag когда LiveKit truth confirms mic is published.
      final service = _CountingCallService(activeCall: null);
      final coordinator = CallCoordinatorService(callService: service);

      // Simulate Q1 false positive: flag set, mic считается off.
      coordinator.debugMarkMicrophonePublishFailed(true);
      expect(coordinator.microphonePublishFailed, isTrue);
      expect(coordinator.microphoneEnabled, isFalse);

      // Simulate Fix C event-driven sync: LiveKit truth says mic IS
      // published. Helper должен update _microphoneEnabled И clear
      // stale _microphonePublishFailed flag.
      coordinator.debugApplyMediaSync(micEnabled: true, camEnabled: false);

      expect(coordinator.microphoneEnabled, isTrue);
      expect(coordinator.microphonePublishFailed, isFalse);

      coordinator.dispose();
    },
  );

  test(
    'CallCoordinatorService Fix C: debugApplyMediaSync notifies '
    'только on diff, no infinite loop',
    () async {
      final service = _CountingCallService(activeCall: null);
      final coordinator = CallCoordinatorService(callService: service);

      var notifyCount = 0;
      void listener() => notifyCount++;
      coordinator.addListener(listener);

      // Initial state — mic enabled true, cam enabled false (defaults).
      // Sync с same values — no diff, no notify.
      coordinator.debugApplyMediaSync(micEnabled: true, camEnabled: false);
      expect(notifyCount, 0);
      expect(coordinator.microphoneEnabled, isTrue);
      expect(coordinator.cameraEnabled, isFalse);

      // Diff на mic — notify fires once.
      coordinator.debugApplyMediaSync(micEnabled: false, camEnabled: false);
      expect(notifyCount, 1);
      expect(coordinator.microphoneEnabled, isFalse);

      // Diff на cam — notify fires.
      coordinator.debugApplyMediaSync(micEnabled: false, camEnabled: true);
      expect(notifyCount, 2);
      expect(coordinator.cameraEnabled, isTrue);

      // Repeat same values — no notify.
      coordinator.debugApplyMediaSync(micEnabled: false, camEnabled: true);
      expect(notifyCount, 2);

      // Both diff — single notify.
      coordinator.debugApplyMediaSync(micEnabled: true, camEnabled: false);
      expect(notifyCount, 3);

      coordinator.removeListener(listener);
      coordinator.dispose();
    },
  );

  test(
    'CallCoordinatorService exposes microphonePublishFailed flag и '
    'notifies listeners on transition',
    () async {
      final service = _CountingCallService(activeCall: null);
      final coordinator = CallCoordinatorService(callService: service);

      // Initial state — flag must be false и mic считается enabled
      // (default state до connect).
      expect(coordinator.microphonePublishFailed, isFalse);
      expect(coordinator.microphoneEnabled, isTrue);

      var notifyCount = 0;
      void listener() => notifyCount++;
      coordinator.addListener(listener);

      // Simulate Bug 1 publish failure scenario через test seam —
      // production-flow это происходит когда LiveKit
      // setMicrophoneEnabled возвращает null publication либо
      // isMicrophoneEnabled() == false после await (Android 14+
      // foreground service absent → mic capture revoked).
      coordinator.debugMarkMicrophonePublishFailed(true);

      expect(coordinator.microphonePublishFailed, isTrue);
      // Truthful UI — mic считается off потому что publication
      // отсутствует. Без этого иконка в CallScreen lies (показывает
      // «mic on» хотя собеседник не слышит).
      expect(coordinator.microphoneEnabled, isFalse);
      expect(notifyCount, 1);

      // Idempotent — flip к тому же значению should be no-op (никакого
      // повторного notify, иначе snackbar fire'нется каждый раз).
      coordinator.debugMarkMicrophonePublishFailed(true);
      expect(notifyCount, 1);

      // Reset path — used когда retry succeeded либо call'reset.
      coordinator.debugMarkMicrophonePublishFailed(false);
      expect(coordinator.microphonePublishFailed, isFalse);
      expect(notifyCount, 2);

      coordinator.removeListener(listener);
      coordinator.dispose();
    },
  );

  test(
    'CallCoordinatorService skips background resync when session is missing',
    () async {
      final service = _CountingCallService(
        activeCall: _buildCall(state: CallState.ringing),
        currentUserId: null,
      );
      final coordinator = CallCoordinatorService(callService: service);

      await coordinator.ensureRuntimeReady();
      final activeCall = await coordinator.resync();

      expect(activeCall, isNull);
      expect(service.activeCallRequests, 0);

      coordinator.dispose();
    },
  );

  test(
    'CallCoordinatorService refreshes microphone and camera device lists',
    () async {
      final service = _CountingCallService(activeCall: null);
      final coordinator = CallCoordinatorService(
        callService: service,
        audioInputEnumerator: () async => const <MediaDevice>[
          MediaDevice('mic-1', 'USB mic', 'audioinput', null),
        ],
        videoInputEnumerator: () async => const <MediaDevice>[
          MediaDevice('camera-1', 'Front Camera', 'videoinput', null),
        ],
      );

      await coordinator.refreshInputDevices();

      expect(coordinator.microphoneDevices.single.deviceId, 'mic-1');
      expect(coordinator.cameraDevices.single.deviceId, 'camera-1');
      expect(coordinator.selectedMicrophoneDeviceId, 'mic-1');
      expect(coordinator.selectedCameraDeviceId, 'camera-1');
      expect(coordinator.devicePickerErrorMessage, isNull);

      coordinator.dispose();
    },
  );

  test(
    'CallCoordinatorService hydrates incoming call from RuStore push payload',
    () async {
      final pushMessages = StreamController<RustorePushMessage>.broadcast();
      final pushedCall = _buildCall(state: CallState.ringing);
      final service = _CountingCallService(
        activeCall: null,
        callById: pushedCall,
      );
      final coordinator = CallCoordinatorService(
        callService: service,
        pushMessages: pushMessages.stream,
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      service.resetCounters();

      pushMessages.add(
        const RustorePushMessage(
          messageId: 'push-1',
          data: <String, String>{
            'type': 'call_invite',
            'callId': 'call-1',
            'chatId': 'chat-1',
          },
          title: 'Caller',
          body: 'Видеозвонок',
        ),
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(service.callByIdRequests, 1);
      expect(coordinator.currentCall?.id, 'call-1');
      expect(coordinator.currentCall?.state, CallState.ringing);

      await pushMessages.close();
      coordinator.dispose();
    },
  );

  test(
    'CallCoordinatorService accepts pending Android telecom action',
    () async {
      final incomingCall = _buildCall(state: CallState.ringing);
      final acceptedCall = _buildCall(
        state: CallState.active,
        session: const CallSession(
          roomName: 'room-1',
          url: 'wss://livekit.example.test',
          token: 'token-1',
          participantIdentity: 'user-1',
        ),
      );
      final service = _CountingCallService(
        activeCall: incomingCall,
        callById: incomingCall,
      )..acceptResult = acceptedCall;
      final androidCalls = _FakeAndroidIncomingCallService(
        const AndroidCallAction(
          action: 'accept',
          callId: 'call-1',
          chatId: 'chat-1',
        ),
      );
      final coordinator = CallCoordinatorService(
        callService: service,
        androidIncomingCallService: androidCalls,
        mediaPermissionRequester: (_) async => false,
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(androidCalls.registerPhoneAccountCalls, 1);
      expect(androidCalls.consumePendingActionCalls, 1);
      expect(service.acceptCallRequests, 1);
      expect(coordinator.currentCall?.state, CallState.active);

      coordinator.dispose();
    },
  );

  test(
    'CallCoordinatorService ignores terminal updates for another call id',
    () async {
      final events = StreamController<CallEvent>.broadcast();
      final activeCall = _buildCall(
        state: CallState.active,
        session: const CallSession(
          roomName: 'room-1',
          url: 'wss://livekit.example.test',
          token: 'token-1',
          participantIdentity: 'user-1',
        ),
      );
      final service = _CountingCallService(
        activeCall: activeCall,
        events: events.stream,
      );
      final coordinator = CallCoordinatorService(
        callService: service,
        mediaPermissionRequester: (_) async => false,
      );

      await coordinator.activateCall(activeCall);
      expect(coordinator.currentCall?.id, 'call-1');
      expect(coordinator.currentCall?.state, CallState.active);

      events.add(
        CallEvent(
          type: CallEventType.stateUpdated,
          call: _buildCall(
            id: 'call-legacy',
            state: CallState.missed,
          ),
        ),
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(coordinator.currentCall?.id, 'call-1');
      expect(coordinator.currentCall?.state, CallState.active);

      await events.close();
      coordinator.dispose();
    },
  );

  test(
    'CallCoordinatorService ignores stale same-call downgrade snapshot',
    () async {
      final events = StreamController<CallEvent>.broadcast();
      final activeCall = _buildCall(
        state: CallState.active,
        updatedAt: DateTime(2026, 4, 20, 10, 5),
        session: const CallSession(
          roomName: 'room-1',
          url: 'wss://livekit.example.test',
          token: 'token-1',
          participantIdentity: 'user-1',
        ),
      );
      final service = _CountingCallService(
        activeCall: activeCall,
        events: events.stream,
      );
      final coordinator = CallCoordinatorService(
        callService: service,
        mediaPermissionRequester: (_) async => false,
      );

      await coordinator.activateCall(activeCall);

      events.add(
        CallEvent(
          type: CallEventType.inviteCreated,
          call: _buildCall(
            state: CallState.ringing,
            updatedAt: DateTime(2026, 4, 20, 10, 1),
          ),
        ),
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(coordinator.currentCall?.state, CallState.active);
      expect(coordinator.currentCall?.session, isNotNull);

      await events.close();
      coordinator.dispose();
    },
  );

  test(
    'CallCoordinatorService applies terminal same-call snapshot even when stale',
    () async {
      final events = StreamController<CallEvent>.broadcast();
      final activeCall = _buildCall(
        state: CallState.active,
        updatedAt: DateTime(2026, 4, 20, 10, 5),
        session: const CallSession(
          roomName: 'room-1',
          url: 'wss://livekit.example.test',
          token: 'token-1',
          participantIdentity: 'user-1',
        ),
      );
      final service = _CountingCallService(
        activeCall: activeCall,
        events: events.stream,
      );
      final coordinator = CallCoordinatorService(
        callService: service,
        mediaPermissionRequester: (_) async => false,
      );

      await coordinator.activateCall(activeCall);

      events.add(
        CallEvent(
          type: CallEventType.stateUpdated,
          call: _buildCall(
            state: CallState.ended,
            updatedAt: DateTime(2026, 4, 20, 10, 1),
          ),
        ),
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(coordinator.currentCall, isNull);

      await events.close();
      coordinator.dispose();
    },
  );

  test(
    'CallCoordinatorService refreshes active call until terminal state',
    () async {
      final activeCall = _buildCall(
        state: CallState.active,
        session: const CallSession(
          roomName: 'room-1',
          url: 'wss://livekit.example.test',
          token: 'token-1',
          participantIdentity: 'user-1',
        ),
      );
      final service = _CountingCallService(activeCall: activeCall);
      final coordinator = CallCoordinatorService(
        callService: service,
        mediaPermissionRequester: (_) async => false,
        activeCallRecoveryInterval: const Duration(milliseconds: 20),
      );

      await coordinator.activateCall(activeCall);
      service.callById = _buildCall(
        state: CallState.ended,
        updatedAt: DateTime(2026, 4, 20, 10, 2),
      );

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(service.callByIdRequests, greaterThanOrEqualTo(1));
      expect(coordinator.currentCall, isNull);

      coordinator.dispose();
    },
  );

  test(
    'CallCoordinatorService refreshes stale ringing call until terminal state',
    () async {
      final service = _CountingCallService(
        activeCall: _buildCall(state: CallState.ringing),
      );
      final coordinator = CallCoordinatorService(
        callService: service,
        ringingRecoveryInterval: const Duration(milliseconds: 20),
      );

      await coordinator.activateCall(_buildCall(state: CallState.ringing));
      service.callById = _buildCall(
        state: CallState.missed,
        updatedAt: DateTime(2026, 4, 20, 10, 2),
      );

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(service.callByIdRequests, greaterThanOrEqualTo(1));
      expect(coordinator.currentCall, isNull);

      coordinator.dispose();
    },
  );

  test(
    'CallCoordinatorService uses call preferences for incoming vibration',
    () async {
      final service = _CountingCallService(activeCall: null);
      var vibrationCount = 0;
      final coordinator = CallCoordinatorService(
        callService: service,
        callPreferences: MemoryCallPreferences(
          CallPreferencesSnapshot.defaults(),
        ),
        vibrationTrigger: () async {
          vibrationCount += 1;
        },
      );

      await coordinator.ensureRuntimeReady();

      await coordinator.activateCall(_buildCall(state: CallState.ringing));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(vibrationCount, 1);

      await coordinator.activateCall(
        _buildCall(
          state: CallState.ringing,
          updatedAt: DateTime(2026, 4, 20, 10, 2),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(vibrationCount, 1);

      coordinator.dispose();
    },
  );
}

CallInvite _buildCall({
  String id = 'call-1',
  required CallState state,
  CallMediaMode mediaMode = CallMediaMode.audio,
  CallSession? session,
  DateTime? updatedAt,
}) {
  return CallInvite(
    id: id,
    chatId: 'chat-1',
    initiatorId: 'user-2',
    recipientId: 'user-1',
    participantIds: const ['user-1', 'user-2'],
    mediaMode: mediaMode,
    state: state,
    createdAt: DateTime(2026, 4, 20, 10),
    updatedAt: updatedAt ?? DateTime(2026, 4, 20, 10, 1),
    session: session,
  );
}

class _CountingCallService implements CallServiceInterface {
  CallInvite? activeCall;
  CallInvite? callById;
  CallInvite? acceptResult;
  final Stream<CallEvent> _events;
  final String? _currentUserId;
  int activeCallRequests = 0;
  int callByIdRequests = 0;
  int acceptCallRequests = 0;

  _CountingCallService._internal({
    required this.activeCall,
    required Stream<CallEvent> events,
    required String? currentUserId,
    this.callById,
  })  : _events = events,
        _currentUserId = currentUserId;

  factory _CountingCallService({
    required CallInvite? activeCall,
    CallInvite? callById,
    Stream<CallEvent>? events,
    String? currentUserId = 'user-1',
  }) {
    return _CountingCallService._internal(
      activeCall: activeCall,
      callById: callById,
      events: events ?? const Stream<CallEvent>.empty(),
      currentUserId: currentUserId,
    );
  }

  void resetCounters() {
    activeCallRequests = 0;
    callByIdRequests = 0;
  }

  @override
  String? get currentUserId => _currentUserId;

  @override
  Stream<CallEvent> get events => _events;

  @override
  Future<CallInvite> acceptCall(String callId) async {
    acceptCallRequests += 1;
    activeCall = acceptResult ?? activeCall;
    return activeCall!;
  }

  @override
  Future<CallInvite> cancelCall(String callId) async => activeCall!;

  @override
  Future<CallInvite?> getActiveCall({String? chatId}) async {
    activeCallRequests += 1;
    return activeCall;
  }

  @override
  Future<CallInvite?> getCall(String callId) async {
    callByIdRequests += 1;
    return callById ?? activeCall;
  }

  @override
  Future<CallInvite> hangUp(String callId) async => activeCall!;

  @override
  Future<CallInvite> rejectCall(String callId) async => activeCall!;

  @override
  Future<void> startRealtimeBridge() async {}

  @override
  Future<CallInvite> startCall({
    required String chatId,
    required CallMediaMode mediaMode,
    List<String>? participantIds,
  }) async =>
      activeCall!;

  @override
  Future<CallInvite> nudgeCallParticipants(
    String callId, {
    List<String>? participantIds,
  }) async =>
      activeCall!;

  @override
  Future<void> stopRealtimeBridge() async {}
}

class _FakeCallForegroundService extends CallForegroundService {
  _FakeCallForegroundService() : super();

  int startCalls = 0;
  int updateCalls = 0;
  int stopCalls = 0;
  int consumeActionCalls = 0;
  CallForegroundNotificationAction? pendingAction;
  String? lastStartCallId;
  String? lastStartPeerName;
  bool? lastStartIsVideo;
  bool? lastStartMicEnabled;

  @override
  bool get isSupported => true;

  @override
  Future<bool> start({
    required String callId,
    String? peerName,
    required bool isVideo,
    required bool micEnabled,
  }) async {
    startCalls += 1;
    lastStartCallId = callId;
    lastStartPeerName = peerName;
    lastStartIsVideo = isVideo;
    lastStartMicEnabled = micEnabled;
    return true;
  }

  @override
  Future<bool> update({
    required String callId,
    String? peerName,
    required bool isVideo,
    required bool micEnabled,
  }) async {
    updateCalls += 1;
    return true;
  }

  @override
  Future<bool> stop() async {
    stopCalls += 1;
    return true;
  }

  @override
  Future<CallForegroundNotificationAction?>
      consumePendingNotificationAction() async {
    consumeActionCalls += 1;
    return pendingAction;
  }
}

class _FakeAndroidIncomingCallService extends AndroidIncomingCallService {
  _FakeAndroidIncomingCallService(this.action);

  final AndroidCallAction? action;
  int registerPhoneAccountCalls = 0;
  int consumePendingActionCalls = 0;
  final List<String> shownCallIds = <String>[];
  final List<String> dismissedCallIds = <String>[];

  @override
  bool get isSupported => true;

  @override
  Future<bool> registerPhoneAccount() async {
    registerPhoneAccountCalls += 1;
    return true;
  }

  @override
  Future<AndroidCallAction?> consumePendingAction() async {
    consumePendingActionCalls += 1;
    return action;
  }

  @override
  Future<bool> showIncomingCall({
    required String callId,
    required String callerName,
    required bool isVideo,
    String? chatId,
  }) async {
    shownCallIds.add(callId);
    return true;
  }

  @override
  Future<bool> dismissCall(String callId) async {
    dismissedCallIds.add(callId);
    return true;
  }
}
