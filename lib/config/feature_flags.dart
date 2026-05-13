/// Phase 4 feature flags. Const-only сейчас (compile-time) — для
/// chunk 3 нам нужно bit-identical legacy path на flag=false, и
/// const ensures dead-code elimination когда flag = false.
///
/// Cleanup commit после chunk 4 manual smoke + 1 prod week
/// observation period (DECISIONS.md 2026-05-12 flag removal
/// sequence): step 5 удаляет flag + legacy code path
/// (irreversible).
///
/// Тесты которые нужно run'нуть с flag=true override'ят через
/// widget parameter (`InteractiveFamilyTree.extendedRenderPathOverride`)
/// — это позволяет golden tests / perf benchmarks с flag ON без
/// мутации global state.
class FeatureFlags {
  const FeatureFlags._();

  /// Phase 4 chunk 3 (visual elements 1-5 в PHASE-4-PROPOSAL.md
  /// §5.A). Default `false` → legacy InteractiveFamilyTree код
  /// идёт unchanged. `true` → tint + edge color + foreign-aware
  /// rendering (incremental implementation 3b → 3c → 3d).
  ///
  /// Никогда **не** mutate'ить эту константу runtime'ом — pure
  /// compile-time switch для clean tree-shaking. Override для тестов
  /// идёт через widget parameter, не через касание этой константы.
  static const bool useExtendedRenderPath = false;
}
