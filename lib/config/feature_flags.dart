import 'package:flutter/foundation.dart';

/// Phase 4 feature flags. Default false → legacy bit-identical
/// path. Override через [testOverrideExtendedRenderPath]
/// (@visibleForTesting) для widget tests / golden tests / perf
/// benchmarks которые exercise'ят flag-on rendering.
///
/// Cleanup commit после chunk 4 manual smoke + 1 prod week
/// observation period (DECISIONS.md 2026-05-12 flag removal
/// sequence): step 5 удаляет flag + legacy code path
/// (irreversible).
///
/// Goldens / unit tests могут также pass override через
/// `InteractiveFamilyTree.extendedRenderPathOverride` widget
/// parameter (more precise — affects single widget instance).
/// Global `testOverrideExtendedRenderPath` нужен для integration
/// tests которые exercise multiple widget instances (e.g.
/// TreeViewScreen → tree_view_screen_sections → InteractiveFamilyTree).
class FeatureFlags {
  const FeatureFlags._();

  // Phase 4 observation window (per DECISIONS.md 2026-05-12 flag
  // removal sequence step 2): default flipped to `true` после
  // squash-merge на main. Cleanup commit step 5 удалит const +
  // legacy code path после 1 week observation без regressions.
  static const bool _productionUseExtendedRenderPath = true;

  /// Test-only global override. Set в test setUp:
  ///   `FeatureFlags.testOverrideExtendedRenderPath = true;`
  /// Reset в tearDown либо setUp следующего теста.
  /// **Никогда** не set'ить в production code paths.
  @visibleForTesting
  static bool? testOverrideExtendedRenderPath;

  /// Phase 4 chunk 3 (visual elements 1-5 в PHASE-4-PROPOSAL.md
  /// §5.A). Default `false` → legacy InteractiveFamilyTree код
  /// идёт unchanged. `true` → tint + edge color + foreign-aware
  /// rendering (incremental implementation 3b → 3c → 3d).
  ///
  /// Production читает `_productionUseExtendedRenderPath` (compile-
  /// time const). Tests могут override через
  /// [testOverrideExtendedRenderPath].
  static bool get useExtendedRenderPath =>
      testOverrideExtendedRenderPath ?? _productionUseExtendedRenderPath;
}
