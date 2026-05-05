// ignore_for_file: avoid_dynamic_calls

/// Parses a datetime from JSON / Hive. Preserves the source's UTC /
/// local mode so cache round-trip equality holds (DateTime.== checks
/// both instant AND isUtc flag).
///
/// Display sites that format these values for the user MUST call
/// `.toLocal()` themselves before passing into `DateFormat.format` —
/// otherwise UTC-mode datetimes from the backend render the UTC
/// wall-clock time, which is hours off for any user not on UTC.
/// Helper available below as [toLocalForDisplay].
DateTime? parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is String) return DateTime.tryParse(value);
  // Legacy Firebase Timestamp may show up if old Hive caches survived
  // a migration — fall back to its toDate().
  try {
    if (value.runtimeType.toString() == 'Timestamp') {
      return value.toDate();
    }
  } catch (_) {}
  return null;
}

DateTime parseDateTimeRequired(dynamic value) {
  return parseDateTime(value) ?? DateTime.now();
}

/// Normalize a parsed datetime for human display. Backend always
/// sends UTC ISO strings (`...Z`); display widgets need wall-clock
/// time in the user's actual zone. Callers must use this before
/// `DateFormat.format(...)` instead of passing the raw value.
DateTime toLocalForDisplay(DateTime value) {
  return value.isUtc ? value.toLocal() : value;
}
