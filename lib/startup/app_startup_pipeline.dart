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
      // U6: каждый таск изолирован (M4-паттерн) — бросок одного НЕ
      // отменяет остальные таски фазы. Без этого сбой раннего lazy-таска
      // (например RuStore-warmup) отменял бы проверку OTA-обновления,
      // зарегистрированную позже в той же featureLazy-фазе.
      try {
        await task.run(context);
      } catch (error, stackTrace) {
        debugPrint(
          '[startup] таск "${task.label}" (${phase.name}) упал: $error',
        );
        debugPrintStack(stackTrace: stackTrace, label: task.label);
      }
    }
  }
}
