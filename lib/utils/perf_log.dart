// S1: лёгкая инструментация ключевых путей — не APM-комбайн, а
// Stopwatch + debug-лог с единым префиксом [perf], чтобы «быстро» было
// числом до и после оптимизаций.

import 'package:flutter/foundation.dart';

/// Одноразовый замер: создать → [finish]. Повторный finish — no-op.
class PerfTrace {
  PerfTrace(this.label) : _stopwatch = Stopwatch()..start();

  final String label;
  final Stopwatch _stopwatch;
  bool _finished = false;

  int get elapsedMs => _stopwatch.elapsedMilliseconds;

  void finish([String? note]) {
    if (_finished) return;
    _finished = true;
    _stopwatch.stop();
    debugPrint(
      '[perf] $label: ${_stopwatch.elapsedMilliseconds}ms'
      '${note == null ? '' : ' · $note'}',
    );
  }

  /// Отменить без лога (например, экран закрыли до завершения).
  void cancel() {
    _finished = true;
    _stopwatch.stop();
  }
}
