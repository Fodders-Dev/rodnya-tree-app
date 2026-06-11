// K3: движок правил плавающих дат — юнит-тесты на 2025–2030 (граничные
// годы), пасхалия и производные от Пасхи даты.

import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/utils/holiday_date_rules.dart';

void main() {
  group('fixedDate', () {
    test('просто фиксированная дата в году', () {
      expect(fixedDate(2026, 1, 25), DateTime(2026, 1, 25));
      expect(fixedDate(2030, 10, 5), DateTime(2030, 10, 5));
    });
  });

  group('nthWeekdayOfMonth', () {
    test('3-е воскресенье июня (День медработника) по годам 2025–2030', () {
      expect(
        nthWeekdayOfMonth(2025, 6, DateTime.sunday, 3),
        DateTime(2025, 6, 15),
      );
      // Проверка владельца: «медработник 2026 = 21 июня».
      expect(
        nthWeekdayOfMonth(2026, 6, DateTime.sunday, 3),
        DateTime(2026, 6, 21),
      );
      expect(
        nthWeekdayOfMonth(2027, 6, DateTime.sunday, 3),
        DateTime(2027, 6, 20),
      );
      expect(
        nthWeekdayOfMonth(2030, 6, DateTime.sunday, 3),
        DateTime(2030, 6, 16),
      );
    });

    test('1-е воскресенье месяца, когда 1-е число — само воскресенье', () {
      // Июнь 2025 начинается с воскресенья.
      expect(
        nthWeekdayOfMonth(2025, 6, DateTime.sunday, 1),
        DateTime(2025, 6, 1),
      );
    });

    test('будний день: последний четверг — через nth тоже считается', () {
      // 1-й четверг ноября 2026 — 5 ноября.
      expect(
        nthWeekdayOfMonth(2026, 11, DateTime.thursday, 1),
        DateTime(2026, 11, 5),
      );
    });
  });

  group('lastWeekdayOfMonth', () {
    test('последнее воскресенье августа (День шахтёра) 2025–2030', () {
      expect(
        lastWeekdayOfMonth(2025, 8, DateTime.sunday),
        DateTime(2025, 8, 31),
      );
      // Проверка владельца: «шахтёр 2026 = 30 августа».
      expect(
        lastWeekdayOfMonth(2026, 8, DateTime.sunday),
        DateTime(2026, 8, 30),
      );
      expect(
        lastWeekdayOfMonth(2030, 8, DateTime.sunday),
        DateTime(2030, 8, 25),
      );
    });

    test('последний четверг месяца — явная просьба владельца', () {
      // Ноябрь 2026: четверги 5, 12, 19, 26 → последний 26-е.
      expect(
        lastWeekdayOfMonth(2026, 11, DateTime.thursday),
        DateTime(2026, 11, 26),
      );
      // Февраль 2027 (28 дней): последний четверг — 25-е.
      expect(
        lastWeekdayOfMonth(2027, 2, DateTime.thursday),
        DateTime(2027, 2, 25),
      );
    });

    test('последнее воскресенье ноября (День матери)', () {
      expect(
        lastWeekdayOfMonth(2026, 11, DateTime.sunday),
        DateTime(2026, 11, 29),
      );
    });
  });

  group('orthodoxEaster / easterOffset', () {
    test('православная Пасха — общеизвестные даты', () {
      expect(orthodoxEaster(2025), DateTime(2025, 4, 20));
      expect(orthodoxEaster(2026), DateTime(2026, 4, 12));
      expect(orthodoxEaster(2027), DateTime(2027, 5, 2));
      expect(orthodoxEaster(2030), DateTime(2030, 4, 28));
    });

    test('Вербное воскресенье = Пасха − 7', () {
      expect(easterOffset(2026, -7), DateTime(2026, 4, 5));
    });

    test('Троица = Пасха + 49', () {
      expect(easterOffset(2026, 49), DateTime(2026, 5, 31));
    });

    test('Радоница = Пасха + 9', () {
      expect(easterOffset(2026, 9), DateTime(2026, 4, 21));
    });
  });
}
