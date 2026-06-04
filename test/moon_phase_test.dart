// Calendar C: the synodic moon-phase util. Verified against the epoch
// reference points and two well-documented 2024 lunations.

import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/utils/moon_phase.dart';

void main() {
  test('moonAgeDays stays within one synodic month', () {
    for (final d in [
      DateTime(2024, 1, 1),
      DateTime(2026, 6, 4),
      DateTime(1999, 12, 31),
      DateTime(2030, 8, 15),
    ]) {
      final age = moonAgeDays(d);
      expect(age, greaterThanOrEqualTo(0));
      expect(age, lessThan(29.53059));
    }
  });

  test('epoch reference points map to the right principal phase', () {
    // Epoch new moon (2000-01-06) and its quarter/half/full offsets.
    expect(moonPhaseFor(DateTime(2000, 1, 6)), MoonPhase.newMoon);
    expect(moonPhaseFor(DateTime(2000, 1, 21)), MoonPhase.fullMoon);
    expect(moonPhaseFor(DateTime(2000, 2, 5)), MoonPhase.newMoon);
  });

  test('matches well-documented 2024 lunations', () {
    // New moon 2024-01-11, full moon 2024-01-25.
    expect(moonPhaseFor(DateTime(2024, 1, 11)), MoonPhase.newMoon);
    expect(moonPhaseFor(DateTime(2024, 1, 25)), MoonPhase.fullMoon);
  });

  test('isPrincipalMoonDay flags only days near a principal phase', () {
    expect(isPrincipalMoonDay(DateTime(2000, 1, 6)), isTrue); // new moon
    expect(isPrincipalMoonDay(DateTime(2000, 1, 21)), isTrue); // full moon
    // A waxing-crescent day (~4 days after the new moon) is not principal.
    expect(isPrincipalMoonDay(DateTime(2000, 1, 10)), isFalse);
  });

  test('every phase has a glyph and a label', () {
    for (final phase in MoonPhase.values) {
      expect(phase.glyph, isNotEmpty);
      expect(phase.label, isNotEmpty);
    }
  });
}
