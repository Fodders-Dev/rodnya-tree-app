// Calendar C: synodic lunar phase — pure Dart, no dependency, no
// ephemeris precision. Moon age = days since a known new-moon epoch,
// modulo the mean synodic month (29.53059 d), mapped to 8 phases. Good
// enough for a dacha-gardener's glance (±~1 day), which is all v1 needs.

enum MoonPhase {
  newMoon,
  waxingCrescent,
  firstQuarter,
  waxingGibbous,
  fullMoon,
  waningGibbous,
  lastQuarter,
  waningCrescent,
}

const double _synodicMonth = 29.53059;

// A well-known reference new moon: 2000-01-06 18:14 UTC.
final DateTime _newMoonEpoch = DateTime.utc(2000, 1, 6, 18, 14);

/// Days since the most recent new moon, in [0, 29.53). Evaluated at noon
/// UTC of [date] so the result is stable for a whole calendar day.
double moonAgeDays(DateTime date) {
  final noon = DateTime.utc(date.year, date.month, date.day, 12);
  final daysSinceEpoch =
      noon.difference(_newMoonEpoch).inSeconds / Duration.secondsPerDay;
  var age = daysSinceEpoch % _synodicMonth;
  if (age < 0) age += _synodicMonth;
  return age;
}

/// The lunar phase for the calendar day containing [date]. The synodic
/// month is split into 8 buckets centred on each phase (new moon at both
/// age 0 and ~29.53).
MoonPhase moonPhaseFor(DateTime date) {
  final age = moonAgeDays(date);
  final index = ((age / _synodicMonth) * 8).round() % 8;
  return MoonPhase.values[index];
}

/// Whether [date] is one of the ~4 days a month that sit closest to a
/// principal phase moment (new / first quarter / full / last quarter) —
/// the dates a gardener plans around. Bucket membership alone would mark
/// ~15 days (each phase spans ~3.7 d); here we keep only the day nearest
/// each exact phase (age within ~0.6 d of the target), so the calendar
/// shows roughly four glyphs per month rather than half the grid.
bool isPrincipalMoonDay(DateTime date) {
  final age = moonAgeDays(date);
  const quarter = _synodicMonth / 4; // new → first → full → last
  const targets = <double>[0, quarter, quarter * 2, quarter * 3, _synodicMonth];
  for (final target in targets) {
    if ((age - target).abs() <= 0.6) return true;
  }
  return false;
}

extension MoonPhasePresentation on MoonPhase {
  /// Unicode moon glyph for the phase.
  String get glyph {
    switch (this) {
      case MoonPhase.newMoon:
        return '🌑';
      case MoonPhase.waxingCrescent:
        return '🌒';
      case MoonPhase.firstQuarter:
        return '🌓';
      case MoonPhase.waxingGibbous:
        return '🌔';
      case MoonPhase.fullMoon:
        return '🌕';
      case MoonPhase.waningGibbous:
        return '🌖';
      case MoonPhase.lastQuarter:
        return '🌗';
      case MoonPhase.waningCrescent:
        return '🌘';
    }
  }

  String get label {
    switch (this) {
      case MoonPhase.newMoon:
        return 'Новолуние';
      case MoonPhase.waxingCrescent:
        return 'Растущий месяц';
      case MoonPhase.firstQuarter:
        return 'Первая четверть';
      case MoonPhase.waxingGibbous:
        return 'Растущая луна';
      case MoonPhase.fullMoon:
        return 'Полнолуние';
      case MoonPhase.waningGibbous:
        return 'Убывающая луна';
      case MoonPhase.lastQuarter:
        return 'Последняя четверть';
      case MoonPhase.waningCrescent:
        return 'Старый месяц';
    }
  }
}
