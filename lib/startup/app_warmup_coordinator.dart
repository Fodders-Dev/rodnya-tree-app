import 'dart:async';

import 'package:flutter/material.dart';

import '../backend/interfaces/auth_service_interface.dart';
import '../services/custom_api_notification_service.dart';
import '../services/custom_api_realtime_service.dart';
import '../startup/app_startup_pipeline.dart';

class AppWarmupCoordinator {
  AppWarmupCoordinator({
    required AuthServiceInterface authService,
    required AppStartupPipeline pipeline,
    CustomApiNotificationService? notificationService,
    CustomApiRealtimeService? realtimeService,
  })  : _authService = authService,
        _pipeline = pipeline,
        _notificationService = notificationService,
        _realtimeService = realtimeService;

  final AuthServiceInterface _authService;
  final AppStartupPipeline _pipeline;
  final CustomApiNotificationService? _notificationService;
  final CustomApiRealtimeService? _realtimeService;

  StreamSubscription<String?>? _authSubscription;
  bool _isStarted = false;
  bool _featureWarmupScheduled = false;
  Future<void>? _authWarmupTask;
  GlobalKey<ScaffoldMessengerState>? _scaffoldMessengerKey;

  Future<void> start(
    GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey,
  ) async {
    _scaffoldMessengerKey = scaffoldMessengerKey;
    if (_isStarted) {
      return;
    }
    _isStarted = true;

    if (!_featureWarmupScheduled) {
      _featureWarmupScheduled = true;
      unawaited(
        _pipeline.runPhase(
          StartupPhase.featureLazy,
          context: StartupPhaseContext(
            scaffoldMessengerKey: scaffoldMessengerKey,
          ),
        ),
      );
    }

    _authSubscription = _authService.authStateChanges.listen((userId) {
      unawaited(_handleAuthStateChanged(userId));
    });

    await _handleAuthStateChanged(_authService.currentUserId);
  }

  Future<void> _handleAuthStateChanged(String? userId) async {
    final normalizedUserId = userId?.trim();
    if (normalizedUserId == null || normalizedUserId.isEmpty) {
      await _stopAuthenticatedWarmup();
      return;
    }

    if (_authWarmupTask != null) {
      return _authWarmupTask;
    }

    final scaffoldMessengerKey = _scaffoldMessengerKey;
    _authWarmupTask = _pipeline.runPhase(
      StartupPhase.authenticatedDeferred,
      context: StartupPhaseContext(
        scaffoldMessengerKey: scaffoldMessengerKey,
      ),
    );
    try {
      await _authWarmupTask;
    } finally {
      _authWarmupTask = null;
    }
  }

  Future<void> _stopAuthenticatedWarmup() async {
    await _notificationService?.stopForegroundSync();
    await _realtimeService?.disconnect();
  }

  Future<void> dispose() async {
    await _authSubscription?.cancel();
    _authSubscription = null;
    _isStarted = false;
  }
}
