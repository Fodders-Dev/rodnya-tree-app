import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/call_invite.dart';
import '../models/call_state.dart';
import 'call_coordinator_service.dart';
import 'custom_api_realtime_service.dart';

typedef IncomingCallFallbackTimerFactory = Timer Function(
  Duration delay,
  void Function() callback,
);

class IncomingCallWatcher with WidgetsBindingObserver {
  IncomingCallWatcher({
    required CallCoordinatorService coordinator,
    CustomApiRealtimeService? realtimeService,
    Stream<CustomApiRealtimeEvent>? realtimeEvents,
    Duration pollInterval = const Duration(seconds: 5),
    IncomingCallFallbackTimerFactory? timerFactory,
  })  : _coordinator = coordinator,
        _realtimeEvents = realtimeEvents ?? realtimeService?.events,
        _pollInterval = pollInterval,
        _timerFactory = timerFactory ?? Timer.new;

  final CallCoordinatorService _coordinator;
  final Stream<CustomApiRealtimeEvent>? _realtimeEvents;
  final Duration _pollInterval;
  final IncomingCallFallbackTimerFactory _timerFactory;

  StreamSubscription<CustomApiRealtimeEvent>? _realtimeSubscription;
  Timer? _fallbackTimer;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  bool _started = false;
  bool _disposed = false;
  bool _realtimeDisconnected = false;

  bool get isFallbackPolling => _fallbackTimer?.isActive ?? false;

  void start() {
    if (_started || _disposed) {
      return;
    }
    WidgetsFlutterBinding.ensureInitialized();
    _started = true;
    _lifecycleState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _realtimeSubscription = _realtimeEvents?.listen(_handleRealtime);
    _updateFallbackPolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshIncomingCall());
    }
    _updateFallbackPolling();
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    await _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
  }

  void _handleRealtime(CustomApiRealtimeEvent event) {
    if (event.type == 'connection.ready') {
      _realtimeDisconnected = false;
      unawaited(_refreshIncomingCall());
      _updateFallbackPolling();
      return;
    }

    if (event.type == 'connection.disconnected') {
      _realtimeDisconnected = true;
      _updateFallbackPolling();
    }
  }

  void _updateFallbackPolling() {
    if (_shouldRunFallbackPolling) {
      _scheduleFallbackPoll();
      return;
    }

    _fallbackTimer?.cancel();
    _fallbackTimer = null;
  }

  bool get _shouldRunFallbackPolling =>
      _started &&
      !_disposed &&
      (_realtimeDisconnected || _lifecycleState != AppLifecycleState.resumed);

  void _scheduleFallbackPoll() {
    if (_fallbackTimer?.isActive ?? false) {
      return;
    }

    _fallbackTimer = _timerFactory(_pollInterval, () {
      _fallbackTimer = null;
      unawaited(_runFallbackPoll());
    });
  }

  Future<void> _runFallbackPoll() async {
    if (!_shouldRunFallbackPolling) {
      return;
    }

    try {
      await _refreshIncomingCall();
    } finally {
      if (_shouldRunFallbackPolling) {
        _scheduleFallbackPoll();
      }
    }
  }

  Future<void> _refreshIncomingCall() async {
    try {
      await _coordinator.ensureRuntimeReady();
      final call = await _coordinator.hydrateIncomingCall();
      await _activateVisibleIncomingCall(call);
    } catch (_) {
      // Incoming-call recovery must not break app lifecycle handling.
    }
  }

  Future<void> _activateVisibleIncomingCall(CallInvite? call) async {
    if (call == null || call.state.isTerminal) {
      return;
    }

    final currentUserId = _coordinator.currentUserId?.trim();
    if (currentUserId == null || currentUserId.isEmpty) {
      return;
    }

    if (call.state == CallState.ringing && call.isIncomingFor(currentUserId)) {
      await _coordinator.activateCall(call);
    }
  }
}
