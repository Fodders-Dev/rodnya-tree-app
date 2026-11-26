import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';

import '../utils/user_facing_error.dart';
import '../backend/interfaces/chat_service_interface.dart';
import '../models/call_invite.dart';
import '../models/call_media_mode.dart';
import '../models/call_state.dart';
import '../models/chat_details.dart';
import '../services/audio_route_service.dart';
import '../services/call_coordinator_service.dart';
import '../services/call_pip_service.dart';
import '../utils/photo_url.dart';
import '../widgets/call_connection_quality_badge.dart';
import '../widgets/call_device_picker_sheet.dart';
import '../widgets/glass_panel.dart';
import '../widgets/in_call_chat_sheet.dart';
import 'call/call_controls_bar.dart';
import 'call/call_draggable_pip.dart';
import 'call/call_formatters.dart';
import 'call/call_group_roster.dart';
import 'call/call_ringer_controller.dart';
import 'call/call_sheets_and_banners.dart';
import 'call/call_video_stage.dart';

export 'call/call_formatters.dart'
    show
        formatCallDuration,
        resolveAdaptiveVideoFit,
        resolveRemoteParticipantLabel;

class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.initialCall,
    required this.title,
    required this.coordinator,
    this.photoUrl,
    this.pipService = const MethodChannelCallPipService(),
    this.chatService,
  });

  final CallInvite initialCall;
  final String title;
  final String? photoUrl;
  final CallCoordinatorService coordinator;
  final CallPipService pipService;
  final ChatServiceInterface? chatService;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  CallInvite? _call;
  // Тracks last-observed value of `coordinator.microphonePublishFailed`
  // чтобы snackbar показывался ровно на false → true transition (а не
  // каждый notifyListeners во время failure). Reset на dispose.
  bool _lastMicrophonePublishFailed = false;
  // Камерное зеркало: transition-tracking для cameraPublishFailed
  // (S20 FE 2026-07-04 — publish камеры падал молча, юзер видел
  // перечёркнутую иконку без единого объяснения).
  bool _lastCameraPublishFailed = false;
  // Дебаунс «Завершить»: второй тап во время exit-анимации снимал бы
  // нижележащий роут вторым maybePop.
  bool _isFinishingCall = false;
  // Дисмисс запрашиваем один раз: повторные notify-микротаски не должны
  // дёргать navigator после того, как закрытие уже пошло.
  bool _dismissRequested = false;
  // Видел ли листенер СВОЙ звонок в координаторе — гейт для дисмисса
  // по id-mismatch (см. _handleCoordinatorChanged).
  bool _coordinatorTrackedOurCall = false;
  // Экран открылся сразу на терминальном состоянии (гонка stale-PIP):
  // координатор молчит (bare return без notify), pop-по-null не
  // сработает — закрываемся сами после короткой паузы.
  Timer? _terminalAutoCloseTimer;
  // Incoming-call / ringback ringer + lifecycle SFX controller.
  late final CallRingerController _ringer = CallRingerController(
    audioRouteService: () => _audioRouteService,
    isMounted: () => mounted,
  );
  // Active-video-call chrome auto-hide: header + status panel fade
  // out after 3s of inactivity so the remote video gets the whole
  // canvas. Tap brings them back. User said the always-on header
  // was annoying ("шапка торчит — нахуя?").
  bool _videoChromeVisible = true;
  Timer? _videoChromeHideTimer;
  // Таймер длительности звонка: тикает раз в секунду пока звонок
  // active, база — coordinator.activeSince (латчится один раз на
  // звонок). Skip'ается в flutter_test binding'е (см. _startRinger).
  Timer? _durationTicker;
  // Collapsible action row: lets the user fold the bottom mic / audio /
  // camera / chat / device controls down to just the end-call button so
  // the video stage gets more breathing room. Same affordance the user
  // asked for on the latest device-test pass: "Кнопки нижние при
  // звонках хотелось бы тоже сворачивать иметь возможность."
  bool _actionsCollapsed = false;
  // `_pipShowsLocal` tracks which feed sits in the small PIP tile vs
  // the full stage — tapping the PIP swaps them.
  bool _pipShowsLocal = true;
  Map<String, ChatParticipantSummary> _callParticipantsById =
      const <String, ChatParticipantSummary>{};
  String? _participantDetailsChatId;
  bool _isNudgingGroupParticipants = false;
  bool _isAddingParticipant = false;

  String? get _currentUserId => widget.coordinator.currentUserId;
  CallInvite get _resolvedCall => _call ?? widget.initialCall;
  bool get _isIncoming =>
      _currentUserId != null && _resolvedCall.isIncomingFor(_currentUserId!);
  // GP1/GP5: an ACTIVE call I'm viewing but have no session in yet → «Войти»
  // for a late member to «залететь в группу». We DON'T gate on
  // participantIds.contains(uid): the server `/join` is chat-membership-gated
  // (requireCallJoinAccess — any member of the call's chat may join, and a
  // non-invited joiner is added to the roster server-side in joinActiveCall),
  // so the old client check was STRICTER than the server and hid «Войти» from
  // chat members who weren't on the original invite list. Optimistic-show +
  // server validation (a join failure surfaces a retriable snackbar). The
  // initiator is excluded via isOutgoingFor.
  bool get _canJoinActive {
    final uid = _currentUserId;
    return uid != null &&
        _resolvedCall.state == CallState.active &&
        _resolvedCall.session == null &&
        widget.coordinator.room == null &&
        _resolvedCall.participantIds.contains(uid) &&
        (!_resolvedCall.isOutgoingFor(uid) ||
            _resolvedCall.joinedOnAnotherDevice ||
            widget.coordinator.joinedOnAnotherDevice);
  }

  bool get _isVideoCall => _resolvedCall.mediaMode == CallMediaMode.video;
  AudioRouteService get _audioRouteService =>
      widget.coordinator.audioRouteService;
  ChatServiceInterface? get _chatService =>
      widget.chatService ??
      (GetIt.I.isRegistered<ChatServiceInterface>()
          ? GetIt.I<ChatServiceInterface>()
          : null);

  @override
  void initState() {
    super.initState();
    _call = widget.coordinator.currentCall?.id == widget.initialCall.id
        ? widget.coordinator.currentCall
        : widget.initialCall;
    widget.coordinator.setCallScreenVisible(
      widget.initialCall.id,
      isVisible: true,
    );
    widget.coordinator.addListener(_handleCoordinatorChanged);
    unawaited(widget.coordinator.activateCall(_resolvedCall));
    unawaited(_loadCallParticipantSummaries());
    _ringer.syncRinger(
      isRinging: _resolvedCall.state == CallState.ringing,
      isIncoming: _isIncoming,
    );
    _syncDurationTicker();
    if (widget.coordinator.currentCall?.id == _resolvedCall.id) {
      _coordinatorTrackedOurCall = true;
    }
    // Stuck-path №3 (скаут 2026-07-04): терминальный initialCall при
    // молчащем координаторе — activateCall упрётся в bare return без
    // notify, экран завис бы статично. Пауза, чтобы юзер увидел исход.
    if (_resolvedCall.state.isTerminal &&
        widget.coordinator.currentCall == null) {
      _terminalAutoCloseTimer = Timer(const Duration(milliseconds: 1200), () {
        if (!mounted) {
          return;
        }
        if (_resolvedCall.state.isTerminal &&
            widget.coordinator.currentCall == null) {
          _dismissCallScreen();
        }
      });
    }
  }

  @override
  void dispose() {
    widget.coordinator.removeListener(_handleCoordinatorChanged);
    widget.coordinator.setCallScreenVisible(
      widget.initialCall.id,
      isVisible: false,
    );
    _ringer.dispose();
    _videoChromeHideTimer?.cancel();
    _durationTicker?.cancel();
    _terminalAutoCloseTimer?.cancel();
    super.dispose();
  }

  /// Держит секундный тикер длительности ровно пока звонок active.
  /// В flutter_test binding'е periodic-таймер не заводим — pumpAndSettle
  /// иначе никогда не settle'ится (конвенция файла, см. _startRinger).
  void _syncDurationTicker() {
    final shouldTick = _resolvedCall.state == CallState.active &&
        widget.coordinator.activeSince != null;
    if (shouldTick && _durationTicker == null) {
      final bindingName = WidgetsBinding.instance.runtimeType.toString();
      if (bindingName.contains('TestWidgetsFlutterBinding')) {
        return;
      }
      _durationTicker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        // Хром спрятан (видеозвонок, авто-hide) — статус невидим,
        // секундная перерисовка впустую; догоним при показе хрома.
        if (_isVideoCall && !_videoChromeVisible) return;
        setState(() {});
      });
    } else if (!shouldTick) {
      _durationTicker?.cancel();
      _durationTicker = null;
    }
  }

  void _scheduleVideoChromeHide() {
    _videoChromeHideTimer?.cancel();
    if (_resolvedCall.state != CallState.active || !_isVideoCall) return;
    _videoChromeHideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _videoChromeVisible = false);
    });
  }

  void _toggleVideoChromeVisibility() {
    setState(() => _videoChromeVisible = !_videoChromeVisible);
    if (_videoChromeVisible) _scheduleVideoChromeHide();
  }

  void _handleCoordinatorChanged() {
    final coordinatorCall = widget.coordinator.currentCall;
    if (coordinatorCall == null) {
      if (mounted) {
        Future<void>.microtask(_dismissCallScreen);
      }
      return;
    }
    if (coordinatorCall.id != _resolvedCall.id) {
      // Координатор переключился на ДРУГОЙ звонок — наш закончился и
      // был вытеснен. Раньше экран замерзал навсегда (терминальные
      // снапшоты чужих id координатор дропает — скаут, stuck-path №2).
      // Гард _coordinatorTrackedOurCall закрывает гонку свежего экрана:
      // между addListener и завершением activateCall координатор ещё
      // может уведомлять про предыдущий звонок.
      if (_coordinatorTrackedOurCall && mounted) {
        Future<void>.microtask(_dismissCallScreen);
      }
      return;
    }
    _coordinatorTrackedOurCall = true;
    // Microphone publish failure surfaced — поднимаем snackbar один
    // раз на transition false → true. Без этого юзер видит «mic on»
    // иконку хотя собеседник его не слышит (Bug 1 root cause #2 per
    // AUDIT-2026-05-22). Action button предлагает retry — повторный
    // toggleMicrophone re-arm'нёт publish path.
    final micPublishFailed = widget.coordinator.microphonePublishFailed;
    if (micPublishFailed && !_lastMicrophonePublishFailed) {
      Future<void>.microtask(() {
        if (!mounted) {
          return;
        }
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 6),
            content: const Text(
              'Микрофон не подключился. Собеседник вас не слышит.',
            ),
            action: SnackBarAction(
              label: 'Повторить',
              onPressed: () {
                if (!mounted) {
                  return;
                }
                // Reset tracker — если retry снова fails, мы хотим
                // увидеть snackbar заново (а не silently swallow'нуть).
                _lastMicrophonePublishFailed = false;
                // Single toggle off→on (_microphoneEnabled уже false
                // потому что failure обнулило truthful UI state).
                unawaited(widget.coordinator.toggleMicrophone());
              },
            ),
          ),
        );
      });
    }
    _lastMicrophonePublishFailed = micPublishFailed;
    // Camera publish failure — тот же Q1-паттерн, что и микрофон выше:
    // snackbar один раз на false → true transition + «Повторить».
    final camPublishFailed = widget.coordinator.cameraPublishFailed;
    if (camPublishFailed && !_lastCameraPublishFailed) {
      Future<void>.microtask(() {
        if (!mounted) {
          return;
        }
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 6),
            content: const Text(
              'Камера не подключилась. Собеседник не видит видео.',
            ),
            action: SnackBarAction(
              label: 'Повторить',
              onPressed: () {
                if (!mounted) {
                  return;
                }
                // Reset tracker — если retry снова fails, показываем
                // snackbar заново (а не silently swallow'иваем).
                _lastCameraPublishFailed = false;
                // toggleCamera включит камеру заново: `_cameraEnabled`
                // уже false, потому что failure обнулило truthful state.
                unawaited(widget.coordinator.toggleCamera());
              },
            ),
          ),
        );
      });
    }
    _lastCameraPublishFailed = camPublishFailed;
    final previousState = _resolvedCall.state;
    setState(() {
      _call = coordinatorCall;
    });
    unawaited(_loadCallParticipantSummaries());
    // Re-evaluate ringer status whenever the call state mutates —
    // accept / decline / cancel / "joined on other device" all need
    // to silence the loop immediately.
    _ringer.syncRinger(
      isRinging: _resolvedCall.state == CallState.ringing,
      isIncoming: _isIncoming,
    );
    _syncDurationTicker();
    // Lifecycle SFX: a soft chime when the line connects, a closing
    // descend when it ends. Skipped on first hop into ringing — the
    // ringer loop itself is the audio cue at that point.
    if (previousState != coordinatorCall.state) {
      if (previousState == CallState.ringing &&
          coordinatorCall.state == CallState.active) {
        _ringer.playOneShot('audio/connect.wav');
      } else if (!previousState.isTerminal &&
          coordinatorCall.state.isTerminal) {
        _ringer.playOneShot('audio/hangup.wav');
      }
    }
    // When a video call transitions to active, schedule the chrome
    // auto-hide so the user gets the full canvas after 3s.
    if (_isVideoCall && coordinatorCall.state == CallState.active) {
      _scheduleVideoChromeHide();
    }
    if (coordinatorCall.joinedOnAnotherDevice &&
        coordinatorCall.state == CallState.active) {
      Future<void>.microtask(() {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Звонок принят на другом устройстве'),
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.of(context).maybePop(coordinatorCall);
      });
    }
  }

  Future<void> _acceptIncomingCall() async {
    try {
      final acceptedCall =
          await widget.coordinator.acceptCall(_resolvedCall.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _call = acceptedCall;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            humanizeError(error, fallback: 'Не удалось принять звонок.'),
          ),
        ),
      );
    }
  }

  Future<void> _joinActiveCall() async {
    try {
      final joinedCall =
          await widget.coordinator.joinActiveCall(_resolvedCall.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _call = joinedCall;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            humanizeError(error, fallback: 'Не удалось войти в звонок.'),
          ),
          // GP1: join can transiently fail (token race, brief network
          // blip) — a retry beats a dead-end snackbar.
          action: SnackBarAction(
            label: 'Ещё раз',
            onPressed: _joinActiveCall,
          ),
        ),
      );
    }
  }

  Future<void> _finishCall() async {
    // Дебаунс двойного тапа: сам API-вызов дедупится в координаторе
    // (memo-future), но второй maybePop здесь снял бы НИЖЕЛЕЖАЩИЙ роут
    // во время exit-анимации.
    if (_isFinishingCall) {
      return;
    }
    _isFinishingCall = true;
    try {
      final result = await widget.coordinator.finishCall(_resolvedCall.id);
      if (!mounted) {
        return;
      }
      Navigator.of(context).maybePop(result ?? _resolvedCall);
    } catch (_) {
    } finally {
      _isFinishingCall = false;
    }
  }

  /// Закрыть CallScreen надёжно: сперва снять СВОИ открытые шторки
  /// (аудио-маршрут / пикер устройств / чат — они живут на том же
  /// навигаторе), потом сам экран. Одиночный maybePop снимал только
  /// верхний роут — шторку — и экран зависал на терминальном состоянии
  /// (скаут 2026-07-04, stuck-path №1: _currentCall уже null, повторного
  /// notify не будет).
  void _dismissCallScreen() {
    if (!mounted || _dismissRequested) {
      return;
    }
    final navigator = Navigator.of(context);
    final ownRoute = ModalRoute.of(context);
    // Роут уже снят (exit-анимация, чужой pop): его нет в history —
    // popUntil никогда не нашёл бы предикат и слил бы ВЕСЬ стек до
    // первого роута (ревью батча). isActive == «ещё в history».
    if (ownRoute == null || !ownRoute.isActive) {
      return;
    }
    _dismissRequested = true;
    if (!ownRoute.isCurrent) {
      navigator.popUntil((route) => route == ownRoute || route.isFirst);
    }
    navigator.maybePop();
  }

  void _minimizeCall() {
    if (_resolvedCall.state == CallState.active) {
      unawaited(widget.pipService.enterPictureInPicture());
    }
    Navigator.of(context).maybePop(_resolvedCall);
  }

  Future<void> _toggleMicrophone() async {
    await widget.coordinator.toggleMicrophone();
    // Force a rebuild — the coordinator notifies its listeners but
    // edge cases (toggleMicrophone fast-failing, no notifyListeners)
    // would leave the icon stale.
    if (mounted) setState(() {});
  }

  Future<void> _toggleCamera() async {
    HapticFeedback.lightImpact();
    try {
      await widget.coordinator.toggleCamera();
    } catch (error) {
      debugPrint('toggleCamera failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Не удалось переключить камеру. Проверьте разрешение.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _switchCamera() async {
    try {
      await widget.coordinator.switchCamera();
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось переключить камеру.')),
      );
    }
  }

  Future<void> _openAudioRouteSheet() async {
    unawaited(_audioRouteService.refreshRoutes());
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => CallAudioRouteSheet(service: _audioRouteService),
    );
  }

  Future<void> _toggleSpeakerRoute() async {
    final routes = _audioRouteService.routes;
    AudioRouteOption? routeById(String id) =>
        routes.firstWhereOrNull((route) => route.id == id);

    final selectedType = _audioRouteService.selectedRoute?.type;
    final target = selectedType == AudioRouteType.speaker
        ? routeById('earpiece')
        : routeById('speaker');
    if (target == null) {
      await _openAudioRouteSheet();
      return;
    }

    HapticFeedback.lightImpact();
    await _audioRouteService.selectRoute(target);
    if (!mounted) return;
    final error = _audioRouteService.errorMessage;
    if (error != null && error.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
  }

  Future<void> _openDevicePickerSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => CallDevicePickerSheet(
        coordinator: widget.coordinator,
      ),
    );
  }

  Future<void> _openInCallChatSheet() async {
    final chatService = _chatService;
    if (chatService == null) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => InCallChatSheet(
        chatId: _resolvedCall.chatId,
        chatService: chatService,
      ),
    );
  }

  Future<void> _loadCallParticipantSummaries({bool force = false}) async {
    final chatId = _resolvedCall.chatId.trim();
    if (chatId.isEmpty) {
      return;
    }
    if (!force && _participantDetailsChatId == chatId) {
      return;
    }
    final chatService = _chatService;
    if (chatService == null) {
      return;
    }

    _participantDetailsChatId = chatId;
    try {
      final details = await chatService.getChatDetails(chatId);
      if (!mounted || _resolvedCall.chatId != chatId) {
        return;
      }
      setState(() {
        _callParticipantsById = <String, ChatParticipantSummary>{
          for (final participant in details.participants)
            if (participant.userId.trim().isNotEmpty)
              participant.userId.trim(): participant,
        };
      });
    } catch (_) {
      // The call screen can work without chat details; ids fall back
      // to generic labels. Avoid retry-spam on every coordinator tick.
    }
  }

  void _openSystemSettings() {
    unawaited(openAppSettings());
  }

  bool get _isGroupCall => _resolvedCall.isGroupCall;

  List<String> get _waitingGroupParticipantIds => _groupCallParticipants
      .where(
        (participant) =>
            !participant.isCurrentUser &&
            participant.state == GroupCallParticipantConnectionState.waiting,
      )
      .map((participant) => participant.userId)
      .toList(growable: false);

  List<GroupCallParticipantStatus> get _groupCallParticipants {
    final currentUserId = _currentUserId?.trim();
    final participantIds = <String>{
      for (final id in _resolvedCall.participantIds)
        if (id.trim().isNotEmpty) id.trim(),
      if (currentUserId != null && currentUserId.isNotEmpty) currentUserId,
    }.toList(growable: false);
    participantIds.sort((left, right) {
      if (left == currentUserId) return -1;
      if (right == currentUserId) return 1;
      return _participantLabelForCallUser(left)
          .compareTo(_participantLabelForCallUser(right));
    });

    return participantIds.map((userId) {
      final isCurrentUser = userId == currentUserId;
      final remoteParticipant = _remoteParticipantForUser(userId);
      final isConnected = isCurrentUser || remoteParticipant != null;
      final state = isConnected
          ? GroupCallParticipantConnectionState.connected
          : (_resolvedCall.state == CallState.active ||
                  _resolvedCall.state == CallState.ringing)
              ? GroupCallParticipantConnectionState.waiting
              : GroupCallParticipantConnectionState.notConnected;
      return GroupCallParticipantStatus(
        userId: userId,
        displayName:
            isCurrentUser ? 'Вы' : _participantLabelForCallUser(userId),
        photoUrl: _callParticipantsById[userId]?.photoUrl,
        state: state,
        isCurrentUser: isCurrentUser,
      );
    }).toList(growable: false);
  }

  RemoteParticipant? _remoteParticipantForUser(String userId) {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      return null;
    }
    return _remoteParticipants.firstWhereOrNull((participant) {
      final identity = participant.identity.trim();
      return identity == normalizedUserId ||
          identity.startsWith('$normalizedUserId#');
    });
  }

  String _participantLabelForCallUser(String userId) {
    final normalizedUserId = userId.trim();
    final summary = _callParticipantsById[normalizedUserId];
    final displayName = summary?.displayName.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }
    final remoteParticipant = _remoteParticipantForUser(normalizedUserId);
    if (remoteParticipant != null) {
      return resolveRemoteParticipantLabel(
        name: remoteParticipant.name,
        identity: remoteParticipant.identity,
        index: 0,
      );
    }
    if (normalizedUserId.length <= 8) {
      return 'Участник';
    }
    return 'Участник ${normalizedUserId.substring(0, 6)}';
  }

  Future<void> _nudgeWaitingGroupParticipants() async {
    final waitingIds = _waitingGroupParticipantIds;
    await _nudgeGroupParticipants(waitingIds);
  }

  Future<void> _nudgeGroupParticipant(String participantId) async {
    final normalizedParticipantId = participantId.trim();
    if (normalizedParticipantId.isEmpty) {
      return;
    }
    await _nudgeGroupParticipants(<String>[normalizedParticipantId]);
  }

  Future<void> _nudgeGroupParticipants(List<String> participantIds) async {
    final waitingIds = participantIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (waitingIds.isEmpty || _isNudgingGroupParticipants) {
      return;
    }
    setState(() => _isNudgingGroupParticipants = true);
    try {
      await widget.coordinator.nudgeCallParticipants(
        _resolvedCall.id,
        participantIds: waitingIds,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Повторно зовём: ${_formatParticipantCount(waitingIds.length)}',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              humanizeError(error, fallback: 'Не удалось позвать повторно.')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isNudgingGroupParticipants = false);
      }
    }
  }

  // GP3: chat members not yet on this call — the candidates for «Добавить».
  List<ChatParticipantSummary> get _addableParticipants {
    final selfId = _currentUserId?.trim();
    final inCall = _resolvedCall.participantIds.toSet();
    return _callParticipantsById.values
        .where((participant) =>
            participant.userId.trim().isNotEmpty &&
            !inCall.contains(participant.userId) &&
            participant.userId != selfId)
        .toList(growable: false);
  }

  Future<void> _openAddParticipantSheet() async {
    if (_isAddingParticipant) {
      return;
    }
    final addable = _addableParticipants;
    if (addable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Все участники чата уже в звонке.')),
      );
      return;
    }
    final pickedUserId = await showAddCallParticipantSheet(
      context: context,
      addableParticipants: addable,
    );
    if (!mounted || pickedUserId == null || pickedUserId.isEmpty) {
      return;
    }
    await _addParticipantsToCall(<String>[pickedUserId]);
  }

  Future<void> _addParticipantsToCall(List<String> participantIds) async {
    if (_isAddingParticipant) {
      return;
    }
    setState(() => _isAddingParticipant = true);
    try {
      await widget.coordinator.addCallParticipants(
        _resolvedCall.id,
        participantIds: participantIds,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавляем в звонок…')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            humanizeError(error, fallback: 'Не удалось добавить участника.'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isAddingParticipant = false);
      }
    }
  }

  List<RemoteParticipant> get _remoteParticipants =>
      widget.coordinator.room?.remoteParticipants.values.toList() ??
      const <RemoteParticipant>[];

  RemoteParticipant? get _remoteParticipant => _remoteParticipants.firstOrNull;

  VideoTrack? get _remoteVideoTrack {
    final publication = _remoteParticipant?.videoTrackPublications
        .firstWhereOrNull((entry) => entry.source == TrackSource.camera);
    return publication?.track;
  }

  List<CallVideoTileData> _videoTilesForGroup(VideoTrack? localVideoTrack) {
    return _groupCallParticipants.map((participant) {
      final remoteParticipant = participant.isCurrentUser
          ? null
          : _remoteParticipantForUser(participant.userId);
      final publication = remoteParticipant?.videoTrackPublications
          .firstWhereOrNull((entry) => entry.source == TrackSource.camera);
      final track =
          participant.isCurrentUser ? localVideoTrack : publication?.track;
      // GP4: mute + active-speaker per tile. Read at build — the
      // coordinator's catch-all on<RoomEvent> re-notifies on TrackMuted/
      // Unmuted and ActiveSpeakersChanged, so this reflects live state.
      final bool isMuted;
      final bool isSpeaking;
      if (participant.isCurrentUser) {
        isMuted = !widget.coordinator.microphoneEnabled;
        isSpeaking =
            widget.coordinator.room?.localParticipant?.isSpeaking ?? false;
      } else if (remoteParticipant != null) {
        final audioPublication =
            remoteParticipant.audioTrackPublications.firstOrNull;
        isMuted = audioPublication?.muted ?? false;
        isSpeaking = remoteParticipant.isSpeaking;
      } else {
        isMuted = false;
        isSpeaking = false;
      }
      return CallVideoTileData(
        track: track,
        label: participant.displayName,
        statusLabel: _stageLabelForGroupParticipant(participant),
        photoUrl: participant.photoUrl,
        statusColor: _stateColorForGroupParticipant(participant.state),
        mirror: participant.isCurrentUser &&
            widget.coordinator.cameraPosition == CameraPosition.front,
        isMuted: isMuted,
        isSpeaking: isSpeaking,
      );
    }).toList(growable: false);
  }

  String _stageLabelForGroupParticipant(
    GroupCallParticipantStatus participant,
  ) {
    if (participant.isCurrentUser) {
      return 'Вы в звонке';
    }
    switch (participant.state) {
      case GroupCallParticipantConnectionState.connected:
        return 'В звонке';
      case GroupCallParticipantConnectionState.waiting:
        return 'Ждём ответа';
      case GroupCallParticipantConnectionState.notConnected:
        return 'Не подключился';
    }
  }

  Color _stateColorForGroupParticipant(
    GroupCallParticipantConnectionState state,
  ) {
    switch (state) {
      case GroupCallParticipantConnectionState.connected:
        return const Color(0xFF37B24D);
      case GroupCallParticipantConnectionState.waiting:
        return const Color(0xFFFFC857);
      case GroupCallParticipantConnectionState.notConnected:
        return const Color(0xFFADB5BD);
    }
  }

  VideoTrack? get _localVideoTrack {
    // Camera state has THREE inputs that all need to agree before we
    // render the local video tile:
    //   * the user-facing toggle (`coordinator.cameraEnabled`) — the
    //     intent we just expressed via `_toggleCamera`
    //   * the publication's `muted` flag — what livekit actually did
    //     server-side
    //   * the track being non-null — what's actually paintable
    //
    // Before this guard the getter only checked the publication, so
    // calling `setCameraEnabled(false)` (which mutes the track but
    // leaves the publication in place) left a frozen last-frame in
    // the PIP — the user reported "При видеозвонке видео не
    // отключается". Treating the muted publication or the user-side
    // disabled state as "no track" hides the tile immediately and
    // matches what the remote peer sees.
    if (!widget.coordinator.cameraEnabled) {
      return null;
    }
    final publication = widget
        .coordinator.room?.localParticipant?.videoTrackPublications
        .firstWhereOrNull((entry) => entry.source == TrackSource.camera);
    if (publication == null || publication.muted) {
      return null;
    }
    return publication.track;
  }

  bool get _showReconnectBanner =>
      _resolvedCall.state == CallState.active &&
      !widget.coordinator.hasMediaPermissionIssue &&
      // P1: before joining, the active call has no session and the
      // coordinator surfaces «Сеанс звонка ещё готовится» — that's not an
      // error here, the «Войти» button is the affordance. Suppress the
      // banner until the user has actually joined.
      !_canJoinActive &&
      (widget.coordinator.isReconnectingRoom ||
          widget.coordinator.showReconnectRestoredBanner ||
          widget.coordinator.connectionError != null);

  String _statusLabel() {
    if (widget.coordinator.isReconnectingRoom) {
      return 'Восстанавливаем соединение...';
    }
    if (widget.coordinator.isConnectingRoom) {
      return 'Подключаем звонок...';
    }
    if (widget.coordinator.connectionError != null &&
        _resolvedCall.state == CallState.active) {
      return widget.coordinator.connectionError!;
    }
    switch (_resolvedCall.state) {
      case CallState.ringing:
        return _isIncoming ? 'Входящий звонок' : 'Вызываем...';
      case CallState.active:
        if (widget.coordinator.room == null) {
          return 'Подключаем медиаканал...';
        }
        if (_isGroupCall) {
          if (_remoteParticipants.isEmpty) {
            return 'Ожидаем участников звонка...';
          }
          final connectedCount = _remoteParticipants.length + 1;
          final base = '${_formatParticipantCount(connectedCount)} в звонке';
          final duration = _callDurationText();
          return duration == null ? base : '$base · $duration';
        }
        if (_remoteParticipant == null) {
          return 'Ожидаем подключение собеседника...';
        }
        // Собеседник на линии — вместо статичного «Видеозвонок» /
        // «Аудиозвонок» показываем тикающую длительность (Telegram-
        // поведение). Fallback на старую метку, пока база не залатчена.
        return _callDurationText() ??
            (_isVideoCall ? 'Видеозвонок' : 'Аудиозвонок');
      case CallState.rejected:
        return 'Звонок отклонен';
      case CallState.cancelled:
        return 'Звонок отменен';
      case CallState.ended:
        return 'Звонок завершен';
      case CallState.missed:
        return 'Пропущенный звонок';
      case CallState.failed:
        return 'Не удалось начать звонок';
    }
  }

  /// Текущая длительность звонка «м:сс» / «ч:мм:сс», null пока звонок
  /// не стал active. Отрицательный дрейф серверного acceptedAt
  /// клампится в ноль.
  String? _callDurationText() {
    final since = widget.coordinator.activeSince;
    if (since == null) {
      return null;
    }
    var elapsed = DateTime.now().difference(since);
    if (elapsed.isNegative) {
      elapsed = Duration.zero;
    }
    return formatCallDuration(elapsed);
  }

  String _formatParticipantCount(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    final suffix = mod10 == 1 && mod100 != 11
        ? 'участник'
        : (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)
            ? 'участника'
            : 'участников');
    return '$count $suffix';
  }

  // Плотность: было 138/132/124dp (аватар без видео — единственный
  // визуальный контент экрана на пустом тёмном фоне, «огромный аватар»
  // из жалобы владельца). Пропорции кольца-индикатора качества и зазоров
  // сохранены (те же 3dp/4dp отступы между слоями), сам размер — под
  // порог 120dp.
  Widget _buildAvatar() {
    final avatarImage = buildAvatarImageProvider(widget.photoUrl);
    final quality = widget.coordinator.displayedConnectionQuality;
    final qualityColor = callConnectionQualityColor(
      quality,
      isReconnecting: widget.coordinator.isReconnectingRoom,
    );
    return SizedBox(
      width: 108,
      height: 108,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 102,
            height: 102,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: qualityColor.withValues(alpha: 0.92),
                width: 3,
              ),
            ),
          ),
          Container(
            width: 94,
            height: 94,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.12),
              image: avatarImage != null
                  ? DecorationImage(
                      image: avatarImage,
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: avatarImage == null
                ? Center(
                    child: Text(
                      widget.title.isNotEmpty
                          ? widget.title[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  )
                : null,
          ),
          Positioned(
            right: 2,
            bottom: 6,
            child: CallConnectionQualityBadge(
              quality: quality,
              isReconnecting: widget.coordinator.isReconnectingRoom,
              compact: true,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final remoteVideoTrack = _remoteVideoTrack;
    final localVideoTrack = _localVideoTrack;
    final groupVideoTiles = _videoTilesForGroup(localVideoTrack);
    final hasConnectedRoom = widget.coordinator.room != null;
    final showPermissionSettingsCta = _resolvedCall.state == CallState.active &&
        widget.coordinator.hasMediaPermissionIssue &&
        !hasConnectedRoom;

    return Scaffold(
      backgroundColor: const Color(0xFF111318),
      body: Stack(
        children: [
          Positioned.fill(
            // Tap-anywhere on the video stage toggles the chrome
            // visibility (title / status / quality badge). Audio
            // calls keep chrome pinned because there's nothing else
            // on screen to look at.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: (_isVideoCall && _resolvedCall.state == CallState.active)
                  ? _toggleVideoChromeVisibility
                  : null,
              // Stage normally shows the remote feed; when the user
              // taps the PIP and we swap, the local feed takes over
              // the full stage and the remote moves into the PIP.
              child: _pipShowsLocal || localVideoTrack == null
                  ? CallStage(
                      isGroupCall: _isGroupCall,
                      remoteVideoTrack: remoteVideoTrack,
                      groupVideoTiles: groupVideoTiles,
                      fallbackAvatar: _buildAvatar(),
                    )
                  : LocalFullStage(
                      track: localVideoTrack,
                      mirror: widget.coordinator.cameraPosition ==
                          CameraPosition.front,
                    ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      onPressed: _minimizeCall,
                      color: Colors.white,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      tooltip: 'Свернуть звонок',
                    ),
                  ),
                  const SizedBox(height: 12),
                  // On an active video call we auto-hide the title /
                  // status panel after 3s so the remote video gets the
                  // whole canvas. Tap-anywhere on the canvas brings it
                  // back. For audio calls + ringing we keep it pinned
                  // because there's nothing else to look at.
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    opacity: (_isVideoCall &&
                            _resolvedCall.state == CallState.active &&
                            !_videoChromeVisible)
                        ? 0.0
                        : 1.0,
                    child: IgnorePointer(
                      ignoring: _isVideoCall &&
                          _resolvedCall.state == CallState.active &&
                          !_videoChromeVisible,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: (_isVideoCall &&
                                _resolvedCall.state == CallState.active)
                            ? _toggleVideoChromeVisibility
                            : null,
                        child: GlassPanel(
                          // Экран звонка всегда тёмный (Scaffold 0xFF111318),
                          // но GlassPanel по умолчанию берёт цвет из АМБИЕНТНОЙ
                          // темы — в светлой теме панель выходит светло-бежевой,
                          // и жёстко-белые имя/статус на ней не читаются.
                          // Принудительно тёмное стекло, чтобы белый текст был
                          // виден независимо от темы устройства.
                          color: Colors.white.withValues(alpha: 0.10),
                          borderColor: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(22),
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          child: Column(
                            children: [
                              Text(
                                widget.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _statusLabel(),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color:
                                          Colors.white.withValues(alpha: 0.82),
                                    ),
                                textAlign: TextAlign.center,
                              ),
                              if (_isGroupCall) ...[
                                const SizedBox(height: 12),
                                GroupCallRoster(
                                  participants: _groupCallParticipants,
                                  isNudging: _isNudgingGroupParticipants,
                                  onNudgeWaiting:
                                      _waitingGroupParticipantIds.isEmpty
                                          ? null
                                          : _nudgeWaitingGroupParticipants,
                                  onNudgeParticipant: _nudgeGroupParticipant,
                                ),
                                // GP3: pull a new chat member into the live call.
                                if (_resolvedCall.state == CallState.active &&
                                    _addableParticipants.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  TextButton.icon(
                                    onPressed: _isAddingParticipant
                                        ? null
                                        : _openAddParticipantSheet,
                                    icon: const Icon(
                                      Icons.person_add_alt_1,
                                      size: 18,
                                    ),
                                    label: const Text('Добавить участника'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ],
                              ],
                              if (_resolvedCall.state == CallState.active) ...[
                                const SizedBox(height: 12),
                                CallConnectionQualityBadge(
                                  quality: widget
                                      .coordinator.displayedConnectionQuality,
                                  isReconnecting:
                                      widget.coordinator.isReconnectingRoom,
                                ),
                              ],
                              if (_showReconnectBanner) ...[
                                const SizedBox(height: 12),
                                CallReconnectBanner(
                                  isReconnecting:
                                      widget.coordinator.isReconnectingRoom,
                                  isRestored: widget
                                      .coordinator.showReconnectRestoredBanner,
                                  message: widget.coordinator.connectionError,
                                ),
                              ],
                              if (showPermissionSettingsCta) ...[
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: _openSystemSettings,
                                  icon: const Icon(Icons.settings_rounded),
                                  label: const Text('Открыть настройки'),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  // PIP moved to a top-level Positioned in the outer
                  // Stack so it can be dragged + swapped freely.
                  const SizedBox(height: 8),
                  CallControlsBar(
                    callState: _resolvedCall.state,
                    hasConnectedRoom: hasConnectedRoom,
                    actionsCollapsed: _actionsCollapsed,
                    onToggleCollapse: () => setState(
                      () => _actionsCollapsed = !_actionsCollapsed,
                    ),
                    audioRouteService: _audioRouteService,
                    onToggleSpeakerRoute: _toggleSpeakerRoute,
                    microphoneEnabled: widget.coordinator.microphoneEnabled,
                    onToggleMicrophone: _toggleMicrophone,
                    onOpenDevicePickerSheet: _openDevicePickerSheet,
                    hasChatService: _chatService != null,
                    onOpenInCallChatSheet: _openInCallChatSheet,
                    cameraEnabled: widget.coordinator.cameraEnabled,
                    isVideoCall: _isVideoCall,
                    onToggleCamera: _toggleCamera,
                    isSwitchingCamera: widget.coordinator.isSwitchingCamera,
                    onSwitchCamera: _switchCamera,
                    onFinishCall: _finishCall,
                    isIncoming: _isIncoming,
                    canJoinActive: _canJoinActive,
                    onJoinActiveCall: _joinActiveCall,
                    onAcceptIncomingCall: _acceptIncomingCall,
                  ),
                ],
              ),
            ),
          ),
          // Picture-in-picture for the secondary feed (local by
          // default, remote when swapped). Draggable across the
          // whole viewport with edge-snap on release; tap to swap
          // with the main stage.
          if (localVideoTrack != null && !_isGroupCall)
            CallDraggablePip(
              localTrack: localVideoTrack,
              remoteTrack: remoteVideoTrack,
              pipShowsLocal: _pipShowsLocal,
              isFrontCamera:
                  widget.coordinator.cameraPosition == CameraPosition.front,
              onSwap: () => setState(() => _pipShowsLocal = !_pipShowsLocal),
            ),
        ],
      ),
    );
  }
}
