import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rodnya/backend/interfaces/auth_service_interface.dart';
import 'package:rodnya/startup/app_startup_pipeline.dart';
import 'package:rodnya/startup/app_warmup_coordinator.dart';

class _FakeAuthService implements AuthServiceInterface {
  _FakeAuthService({String? currentUserId}) : _currentUserId = currentUserId;

  final StreamController<String?> _controller =
      StreamController<String?>.broadcast();

  String? _currentUserId;

  void emitAuthState(String? userId) {
    _currentUserId = userId;
    _controller.add(userId);
  }

  Future<void> dispose() async {
    await _controller.close();
  }

  @override
  String? get currentUserId => _currentUserId;

  @override
  String? get currentUserEmail => null;

  @override
  String? get currentUserDisplayName => null;

  @override
  String? get currentUserPhotoUrl => null;

  @override
  List<String> get currentProviderIds => const <String>[];

  @override
  Stream<String?> get authStateChanges => _controller.stream;

  @override
  Future<Map<String, dynamic>> checkProfileCompleteness() {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteAccount([String? password]) {
    throw UnimplementedError();
  }

  @override
  String describeError(Object error) {
    throw UnimplementedError();
  }

  @override
  Future<Object?> loginWithEmail(String email, String password) {
    throw UnimplementedError();
  }

  @override
  Future<void> processPendingInvitation() {
    throw UnimplementedError();
  }

  @override
  Future<Object?> registerWithEmail({
    required String email,
    required String password,
    required String name,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> resetPassword(String email) {
    throw UnimplementedError();
  }

  @override
  Future<Object?> signInWithGoogle() {
    throw UnimplementedError();
  }

  @override
  Future<void> signOut() {
    throw UnimplementedError();
  }

  @override
  Future<void> updateDisplayName(String displayName) {
    throw UnimplementedError();
  }
}

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('runs feature warmup once and auth warmup after sign in', () async {
    final authService = _FakeAuthService();
    final phases = <StartupPhase>[];
    final coordinator = AppWarmupCoordinator(
      authService: authService,
      pipeline: AppStartupPipeline(
        tasks: <StartupPhaseTask>[
          StartupPhaseTask(
            phase: StartupPhase.featureLazy,
            label: 'feature',
            run: (_) async {
              phases.add(StartupPhase.featureLazy);
            },
          ),
          StartupPhaseTask(
            phase: StartupPhase.authenticatedDeferred,
            label: 'auth',
            run: (_) async {
              phases.add(StartupPhase.authenticatedDeferred);
            },
          ),
        ],
      ),
    );

    await coordinator.start(GlobalKey<ScaffoldMessengerState>());
    await _flushAsync();
    expect(phases, <StartupPhase>[StartupPhase.featureLazy]);

    authService.emitAuthState('user-1');
    await _flushAsync();
    expect(
      phases,
      <StartupPhase>[
        StartupPhase.featureLazy,
        StartupPhase.authenticatedDeferred,
      ],
    );

    await coordinator.start(GlobalKey<ScaffoldMessengerState>());
    await _flushAsync();
    expect(
      phases,
      <StartupPhase>[
        StartupPhase.featureLazy,
        StartupPhase.authenticatedDeferred,
      ],
    );

    await coordinator.dispose();
    await authService.dispose();
  });

  test('runs auth warmup during startup when session already exists', () async {
    final authService = _FakeAuthService(currentUserId: 'user-1');
    final phases = <StartupPhase>[];
    final coordinator = AppWarmupCoordinator(
      authService: authService,
      pipeline: AppStartupPipeline(
        tasks: <StartupPhaseTask>[
          StartupPhaseTask(
            phase: StartupPhase.featureLazy,
            label: 'feature',
            run: (_) async {
              phases.add(StartupPhase.featureLazy);
            },
          ),
          StartupPhaseTask(
            phase: StartupPhase.authenticatedDeferred,
            label: 'auth',
            run: (_) async {
              phases.add(StartupPhase.authenticatedDeferred);
            },
          ),
        ],
      ),
    );

    await coordinator.start(GlobalKey<ScaffoldMessengerState>());
    await _flushAsync();

    expect(
      phases,
      <StartupPhase>[
        StartupPhase.featureLazy,
        StartupPhase.authenticatedDeferred,
      ],
    );

    await coordinator.dispose();
    await authService.dispose();
  });
}
