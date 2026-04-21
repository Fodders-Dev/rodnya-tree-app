import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../backend/interfaces/chat_service_interface.dart';
import '../models/call_invite.dart';
import '../models/call_state.dart';
import '../navigation/app_router_shared.dart';
import '../screens/call_screen.dart';
import '../services/call_coordinator_service.dart';
import '../services/custom_api_notification_service.dart';
import 'glass_panel.dart';

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

  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  CallInvite? _bannerCall;
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
      if (_bannerCall != null) {
        setState(() {
          _bannerCall = null;
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

    final shouldShowBanner = _shouldShowBanner(call);
    final nextBannerCall = shouldShowBanner ? call : null;
    if (_bannerCall?.id != nextBannerCall?.id ||
        _bannerCall?.state != nextBannerCall?.state ||
        _bannerCall?.updatedAt != nextBannerCall?.updatedAt) {
      setState(() {
        _bannerCall = nextBannerCall;
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

  bool _shouldShowBackgroundNotification(CallInvite call) {
    return _isIncoming(call) &&
        call.state == CallState.ringing &&
        _lifecycleState != AppLifecycleState.resumed &&
        _notifiedCallId != call.id;
  }

  bool _shouldShowBanner(CallInvite call) {
    if (_coordinator.isCallScreenVisible(call.id)) {
      return false;
    }
    if (_isPresentingCallScreen || _presentedCallId == call.id) {
      return false;
    }
    return call.state == CallState.ringing || call.state == CallState.active;
  }

  bool _shouldAutoPresent(CallInvite call) {
    if (!_isIncoming(call) || _lifecycleState != AppLifecycleState.resumed) {
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
    return call.state == CallState.ringing || call.state == CallState.active;
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

    if (_bannerCall != null) {
      setState(() {
        _bannerCall = null;
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

    final fallback = _CallPresentation(
      title: call.mediaMode.isVideo ? 'Видеозвонок' : 'Звонок',
    );
    final chatService = _chatService;
    if (chatService == null) {
      return fallback;
    }

    try {
      final details = await chatService
          .getChatDetails(call.chatId)
          .timeout(const Duration(seconds: 2));
      final photoUrl = details.participants.isNotEmpty
          ? details.participants.first.photoUrl
          : (details.branchRoots.isNotEmpty
              ? details.branchRoots.first.photoUrl
              : null);
      final resolved = _CallPresentation(
        title: details.displayTitle,
        photoUrl: photoUrl,
      );
      _presentations[call.chatId] = resolved;
      return resolved;
    } catch (_) {
      return fallback;
    }
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

  String _bannerStatusLabel(CallInvite call) {
    if (_coordinator.isReconnectingRoom && call.state == CallState.active) {
      return 'Восстанавливаем соединение...';
    }
    if (_coordinator.isConnectingRoom && call.state == CallState.active) {
      return 'Подключаем звонок...';
    }
    switch (call.state) {
      case CallState.ringing:
        return _isIncoming(call)
            ? 'Входящий ${call.mediaMode.isVideo ? 'видеозвонок' : 'аудиозвонок'}'
            : 'Вызываем...';
      case CallState.active:
        return call.mediaMode.isVideo ? 'Идет видеозвонок' : 'Идет аудиозвонок';
      case CallState.rejected:
      case CallState.cancelled:
      case CallState.ended:
      case CallState.missed:
      case CallState.failed:
        return 'Звонок';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bannerCall = _bannerCall;
    if (bannerCall == null) {
      return widget.child;
    }

    final theme = Theme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: GlassPanel(
                borderRadius: BorderRadius.circular(24),
                padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _bannerStatusLabel(bannerCall),
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Открыть экран звонка',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => unawaited(
                        _openCallScreen(bannerCall, force: true),
                      ),
                      child: Text(
                        bannerCall.state == CallState.active
                            ? 'Вернуться'
                            : 'Открыть',
                      ),
                    ),
                  ],
                ),
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
