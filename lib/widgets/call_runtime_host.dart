import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:hive/hive.dart';

import '../backend/interfaces/chat_service_interface.dart';
import '../models/call_invite.dart';
import '../models/call_state.dart';
import '../models/chat_details.dart';
import '../models/chat_preview.dart';
import '../navigation/app_router_shared.dart';
import '../screens/call_screen.dart';
import '../services/call_coordinator_service.dart';
import '../services/chat_preview_cache.dart';
import '../services/custom_api_notification_service.dart';
import 'call_floating_pip.dart';

class CallRuntimeHost extends StatefulWidget {
  const CallRuntimeHost({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<CallRuntimeHost> createState() => _CallRuntimeHostState();
}

class _CallRuntimeHostState extends State<CallRuntimeHost>
    with WidgetsBindingObserver {
  final CallCoordinatorService _coordinator = GetIt.I<CallCoordinatorService>();
  final ChatServiceInterface? _chatService =
      GetIt.I.isRegistered<ChatServiceInterface>()
          ? GetIt.I<ChatServiceInterface>()
          : null;
  final CustomApiNotificationService? _notificationService =
      GetIt.I.isRegistered<CustomApiNotificationService>()
          ? GetIt.I<CustomApiNotificationService>()
          : null;
  final Map<String, _CallPresentation> _presentations =
      <String, _CallPresentation>{};
  // Cold-start-survivable source for the incoming-call plaque name/photo when
  // getChatDetails is slow or times out. Read-only, best-effort; reads the same
  // Hive box the chat list uses ('chat_previews_v1').
  final ChatPreviewCache _chatPreviewCache = HiveChatPreviewCache();

  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  CallInvite? _floatingCall;
  String? _presentedCallId;
  String? _suppressedCallId;
  String? _notifiedCallId;
  bool _isPresentingCallScreen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _coordinator.addListener(_handleCoordinatorChanged);
    unawaited(_coordinator.ensureRuntimeReady());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _handleCoordinatorChanged();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _coordinator.removeListener(_handleCoordinatorChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final previousState = _lifecycleState;
    _lifecycleState = state;
    if (state == AppLifecycleState.resumed &&
        previousState != AppLifecycleState.resumed) {
      _suppressedCallId = null;
      unawaited(_coordinator.resync());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _handleCoordinatorChanged();
        }
      });
    }
  }

  void _handleCoordinatorChanged() {
    if (!mounted) {
      return;
    }

    final call = _coordinator.currentCall;
    if (call == null || call.state.isTerminal) {
      final notifiedCallId = _notifiedCallId;
      if (notifiedCallId != null) {
        unawaited(_dismissIncomingCallNotification(notifiedCallId));
      }
      if (_floatingCall != null) {
        setState(() {
          _floatingCall = null;
        });
      }
      if (call == null) {
        _suppressedCallId = null;
      }
      return;
    }

    if (_shouldShowBackgroundNotification(call)) {
      unawaited(_showIncomingCallNotification(call));
    } else if (_notifiedCallId != null && _notifiedCallId != call.id) {
      unawaited(_dismissIncomingCallNotification(_notifiedCallId!));
    } else if (_notifiedCallId == call.id && call.state != CallState.ringing) {
      unawaited(_dismissIncomingCallNotification(call.id));
    }

    final shouldShowFloatingPip = _shouldShowFloatingPip(call);
    final nextFloatingCall = shouldShowFloatingPip ? call : null;
    if (nextFloatingCall != null && !_presentations.containsKey(call.chatId)) {
      unawaited(_resolvePresentation(call).then((_) {
        if (mounted) {
          setState(() {});
        }
      }));
    }
    if (_floatingCall?.id != nextFloatingCall?.id ||
        _floatingCall?.state != nextFloatingCall?.state ||
        _floatingCall?.updatedAt != nextFloatingCall?.updatedAt) {
      setState(() {
        _floatingCall = nextFloatingCall;
      });
    }

    if (_shouldAutoPresent(call)) {
      unawaited(_openCallScreen(call));
    }
  }

  bool _isIncoming(CallInvite call) {
    final currentUserId = _coordinator.currentUserId;
    return currentUserId != null && call.isIncomingFor(currentUserId);
  }

  // P1: an ACTIVE call this user belongs to but hasn't joined (no session,
  // not joined on another device, not the initiator) — present it so the
  // «Войти» button is reachable («залететь в группу»). A dismissal is
  // already remembered via _suppressedCallId, so this won't nag.
  bool _canJoinActiveCall(CallInvite call) {
    final currentUserId = _coordinator.currentUserId;
    return currentUserId != null &&
        call.state == CallState.active &&
        call.session == null &&
        !call.joinedOnAnotherDevice &&
        !call.isOutgoingFor(currentUserId) &&
        call.participantIds.contains(currentUserId);
  }

  bool _shouldShowBackgroundNotification(CallInvite call) {
    return _isIncoming(call) &&
        call.state == CallState.ringing &&
        _lifecycleState != AppLifecycleState.resumed &&
        _notifiedCallId != call.id;
  }

  bool _shouldShowFloatingPip(CallInvite call) {
    if (call.state != CallState.ringing && call.state != CallState.active) {
      return false;
    }
    if (call.state == CallState.ringing &&
        !_isIncoming(call) &&
        !_coordinator.isLocallyStartedCall(call.id)) {
      return false;
    }
    if (call.joinedOnAnotherDevice) {
      return false;
    }
    if (_coordinator.isCallScreenVisible(call.id)) {
      return false;
    }
    if (_isPresentingCallScreen || _presentedCallId == call.id) {
      return false;
    }
    return true;
  }

  bool _shouldAutoPresent(CallInvite call) {
    if (_lifecycleState != AppLifecycleState.resumed) {
      return false;
    }
    if (call.joinedOnAnotherDevice) {
      return false;
    }
    if (_coordinator.isCallScreenVisible(call.id)) {
      return false;
    }
    if (_isPresentingCallScreen ||
        _presentedCallId == call.id ||
        _suppressedCallId == call.id) {
      return false;
    }
    // Auto-pop the full CallScreen only for calls this device must
    // handle immediately: incoming ringing calls, or an outgoing call
    // started from this exact app session. The same account can be open
    // on another phone/browser; those sessions may observe the call via
    // realtime/resync but must not hijack their UI.
    return (call.state == CallState.ringing &&
            (_isIncoming(call) ||
                _coordinator.isLocallyStartedCall(call.id))) ||
        _canJoinActiveCall(call);
  }

  Future<void> _openCallScreen(
    CallInvite call, {
    bool force = false,
  }) async {
    if (_isPresentingCallScreen) {
      return;
    }

    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_openCallScreen(call, force: force));
        }
      });
      return;
    }

    _isPresentingCallScreen = true;
    _presentedCallId = call.id;
    if (force) {
      _suppressedCallId = null;
    }

    final notifiedCallId = _notifiedCallId;
    if (notifiedCallId != null) {
      unawaited(_dismissIncomingCallNotification(notifiedCallId));
    }

    if (_floatingCall != null) {
      setState(() {
        _floatingCall = null;
      });
    }

    try {
      final presentation = await _resolvePresentation(call);
      if (!mounted) {
        return;
      }
      await _coordinator.activateCall(call);
      final result = await navigator.push<CallInvite>(
        MaterialPageRoute<CallInvite>(
          builder: (_) => CallScreen(
            initialCall: call,
            title: presentation.title,
            photoUrl: presentation.photoUrl,
            coordinator: _coordinator,
          ),
        ),
      );

      final activeCall = _coordinator.currentCall;
      final shouldSuppressReopen = activeCall != null &&
          activeCall.id == call.id &&
          !activeCall.state.isTerminal &&
          result != null &&
          !result.state.isTerminal;
      _suppressedCallId = shouldSuppressReopen ? call.id : null;
    } finally {
      _isPresentingCallScreen = false;
      if (_presentedCallId == call.id) {
        _presentedCallId = null;
      }
      if (mounted) {
        _handleCoordinatorChanged();
      }
    }
  }

  Future<_CallPresentation> _resolvePresentation(CallInvite call) async {
    final cached = _presentations[call.chatId];
    if (cached != null) {
      return cached;
    }

    final isGroup = call.isGroupCall;
    final chatService = _chatService;
    if (chatService == null) {
      return _fallbackPresentation(call, isGroup);
    }

    try {
      final details = await chatService
          .getChatDetails(call.chatId)
          .timeout(const Duration(seconds: 2));
      final currentUserId = _coordinator.currentUserId;
      if (isGroup) {
        // Group call → show the GROUP identity (chat title + group photo),
        // never one arbitrary member's name/avatar, so the callee can tell
        // it's a multi-party call before answering.
        final groupTitle = details.title?.trim();
        final resolved = _CallPresentation(
          title: (groupTitle != null && groupTitle.isNotEmpty)
              ? groupTitle
              : details.displayTitleFor(currentUserId),
          photoUrl: details.photoUrl,
        );
        _presentations[call.chatId] = resolved;
        return resolved;
      }
      final otherParticipant = details.participants.firstWhere(
        (participant) =>
            currentUserId == null || participant.userId != currentUserId,
        orElse: () => details.participants.isEmpty
            ? const ChatParticipantSummary(userId: '', displayName: '')
            : details.participants.first,
      );
      final photoUrl = otherParticipant.userId.isNotEmpty
          ? otherParticipant.photoUrl
          : (details.branchRoots.isNotEmpty
              ? details.branchRoots.first.photoUrl
              : null);
      final resolved = _CallPresentation(
        title: details.displayTitleFor(currentUserId),
        photoUrl: photoUrl,
      );
      _presentations[call.chatId] = resolved;
      return resolved;
    } catch (_) {
      return _fallbackPresentation(call, isGroup);
    }
  }

  // Best-effort presentation when chat details aren't available (no chat
  // service, slow network, or the 2s getChatDetails timeout): prefer the
  // cold-start-survivable preview cache (real name + photo) over a bare
  // «Звонок», and never frame a group call as 1:1. NOT stored in
  // `_presentations`, so a later getChatDetails success can still upgrade it.
  Future<_CallPresentation> _fallbackPresentation(
    CallInvite call,
    bool isGroup,
  ) async {
    final baseTitle = isGroup
        ? 'Групповой звонок'
        : (call.mediaMode.isVideo ? 'Видеозвонок' : 'Звонок');
    final preview = await _cachedChatPreview(call.chatId);
    // For a 1:1 incoming call the FCM push carries the caller's name (the
    // native notification already shows it) — the most reliable title when
    // getChatDetails is slow or the chat isn't cached. Prefer it over «Звонок»
    // (this is exactly the "в уведах вижу кто звонит, а в приложении Звонок"
    // gap — the screen ignored the push name the notification used).
    if (!isGroup) {
      final pushName = _coordinator.pushCallerNameFor(call.id);
      if (pushName != null && pushName.isNotEmpty) {
        return _CallPresentation(
          title: pushName,
          photoUrl: preview?.displayPhotoUrl,
        );
      }
    }
    if (preview == null) {
      return _CallPresentation(title: baseTitle);
    }
    // Use the preview's resolved display name (otherUserName for a 1:1 chat,
    // title for a group) — NOT preview.title, which is null for direct chats
    // and would leave the caller staring at a nameless «Звонок».
    final cachedName = preview.displayName.trim();
    return _CallPresentation(
      title: cachedName.isNotEmpty ? cachedName : baseTitle,
      photoUrl: preview.displayPhotoUrl,
    );
  }

  // Read-only lookup of a chat's cached preview (title/photo) from the
  // Hive-backed chat-preview cache. Best-effort — returns null off-cache or on
  // any error so the caller falls back to a generic label.
  Future<ChatPreview?> _cachedChatPreview(String chatId) async {
    // Only touch the cache when its Hive box is already open — populated by the
    // chat list in the real app. Before Hive init / in tests the box isn't
    // open; skip rather than trigger Hive's open + destructive delete-retry.
    if (!Hive.isBoxOpen('chat_previews_v1')) {
      return null;
    }
    try {
      final previews = await _chatPreviewCache.read();
      for (final preview in previews) {
        if (preview.chatId == chatId) {
          return preview;
        }
      }
    } catch (_) {
      // best-effort
    }
    return null;
  }

  Future<void> _showIncomingCallNotification(CallInvite call) async {
    final notificationService = _notificationService;
    if (notificationService == null) {
      return;
    }
    final presentation = await _resolvePresentation(call);
    await notificationService.showIncomingCallNotification(
      callId: call.id,
      callerName: presentation.title,
      isVideo: call.mediaMode.isVideo,
      chatId: call.chatId,
    );
    _notifiedCallId = call.id;
  }

  Future<void> _dismissIncomingCallNotification(String callId) async {
    final notificationService = _notificationService;
    if (notificationService != null) {
      await notificationService.dismissCallNotification(callId);
    }
    if (_notifiedCallId == callId) {
      _notifiedCallId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final floatingCall = _floatingCall;
    if (floatingCall == null) {
      return widget.child;
    }

    final floatingPresentation = _presentations[floatingCall.chatId] ??
        _CallPresentation(
          title: floatingCall.mediaMode.isVideo ? 'Видеозвонок' : 'Звонок',
        );
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned.fill(
          child: SafeArea(
            child: CallFloatingPip(
              call: floatingCall,
              title: floatingPresentation.title,
              photoUrl: floatingPresentation.photoUrl,
              coordinator: _coordinator,
              onRestore: () => unawaited(
                _openCallScreen(floatingCall, force: true),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CallPresentation {
  const _CallPresentation({
    required this.title,
    this.photoUrl,
  });

  final String title;
  final String? photoUrl;
}
