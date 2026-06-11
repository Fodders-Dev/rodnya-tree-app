// K3: движок правил плавающих дат праздников — чистые функции без
// зависимостей, чтобы «последний четверг месяца» считался, а не зашивался
// числом. Используется EventService'ом для народных/профессиональных
// праздников и православной пасхалии.

/// Фиксированная дата «месяц-день» в конкретном году.
DateTime fixedDate(int year, int month, int day) =>
    DateTime(year, month, day);

/// N-й [weekday] месяца («3-е воскресенье июня»): n начинается с 1.
/// [weekday] — DateTime.monday..DateTime.sunday.
DateTime nthWeekdayOfMonth(int year, int month, int weekday, int n) {
  assert(n >= 1, 'n считается с 1');
  final first = DateTime(year, month, 1);
  final offset = (weekday - first.weekday + 7) % 7;
  return DateTime(year, month, 1 + offset + (n - 1) * 7);
}

/// Последний [weekday] месяца («последнее воскресенье августа»).
DateTime lastWeekdayOfMonth(int year, int month, int weekday) {
  final lastDay = DateTime(year, month + 1, 0); // 0-й день = конец месяца
  final offset = (lastDay.weekday - weekday + 7) % 7;
  return DateTime(year, month, lastDay.day - offset);
}

/// Православная Пасха по юлианской пасхалии, в григорианских датах
/// (+13 дней для 1900–2099). Перенесена из EventService — единственная
/// пасхалия проекта, вторую не пишем.
DateTime orthodoxEaster(int year) {
  final a = year % 4;
  final b = year % 7;
  final c = year % 19;
  final d = (19 * c + 15) % 30;
  final e = (2 * a + 4 * b - d + 34) % 7;
  final month = (d + e + 114) ~/ 31;
  final day = ((d + e + 114) % 31) + 1;
  final julianDate = DateTime(year, month, day);
  return julianDate.add(const Duration(days: 13));
}

/// Дата «Пасха ± N дней» («Радоница» = +9, «Вербное» = −7).
DateTime easterOffset(int year, int days) =>
    orthodoxEaster(year).add(Duration(days: days));
