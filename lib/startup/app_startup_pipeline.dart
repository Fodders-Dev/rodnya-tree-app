import 'package:flutter/material.dart';

enum StartupPhase {
  critical,
  authenticatedDeferred,
  featureLazy,
}

class StartupPhaseContext {
  const StartupPhaseContext({
    this.scaffoldMessengerKey,
  });

  final GlobalKey<ScaffoldMessengerState>? scaffoldMessengerKey;
}

typedef StartupPhaseTaskRunner = Future<void> Function(
  StartupPhaseContext context,
);

class StartupPhaseTask {
  const StartupPhaseTask({
    required this.phase,
    required this.label,
    required this.run,
  });

  final StartupPhase phase;
  final String label;
  final StartupPhaseTaskRunner run;
}

class AppStartupPipeline {
  const AppStartupPipeline({
    required List<StartupPhaseTask> tasks,
  }) : _tasks = tasks;

  final List<StartupPhaseTask> _tasks;

  Future<void> runPhase(
    StartupPhase phase, {
    StartupPhaseContext context = const StartupPhaseContext(),
  }) async {
    for (final task in _tasks) {
      if (task.phase != phase) {
        continue;
      }
      await task.run(context);
    }
  }
}
