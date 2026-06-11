// F5: «знаю только год» — единый форматтер дат человека с учётом
// точности. Дата с precision == 'yearOnly' хранится как 01.01.года,
// и показывать фейковое «1 января» нельзя — только год.

import 'package:intl/intl.dart';

/// Короткий формат: `21.06.1980` или `1888` для yearOnly.
String formatPersonDate(DateTime date, String precision) {
  if (precision == 'yearOnly') {
    return '${date.year}';
  }
  return DateFormat('dd.MM.yyyy').format(date);
}

/// Длинный русский формат: `21 июня 1980` или `1888 год` для yearOnly.
String formatPersonDateLong(DateTime date, String precision) {
  if (precision == 'yearOnly') {
    return '${date.year} год';
  }
  return DateFormat('d MMMM y', 'ru').format(date);
}
