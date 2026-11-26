// F5: «знаю только год» — отображение. Карточка показывает «1888», а не
// фейковое «1 января 1888»; форматтер един для короткого/длинного вида.

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:rodnya/backend/models/semya_browse_token.dart';
import 'package:rodnya/models/family_person.dart';
import 'package:rodnya/models/person_dossier.dart';
import 'package:rodnya/utils/person_date_format.dart';

FamilyPerson _yearOnlyAncestor() => FamilyPerson(
      id: 'p-1888',
      treeId: 'tree-1',
      name: 'Кузнецов Пётр Степанович',
      gender: Gender.male,
      birthDate: DateTime(1888, 1, 1),
      birthDatePrecision: 'yearOnly',
      deathDate: DateTime(1959, 1, 1),
      deathDatePrecision: 'yearOnly',
      isAlive: false,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  group('formatPersonDate / formatPersonDateLong', () {
    test('exact — полная дата', () {
      expect(formatPersonDate(DateTime(1980, 6, 21), 'exact'), '21.06.1980');
      expect(
        formatPersonDateLong(DateTime(1980, 6, 21), 'exact'),
        '21 июня 1980',
      );
    });

    test('yearOnly — только год', () {
      expect(formatPersonDate(DateTime(1888, 1, 1), 'yearOnly'), '1888');
      expect(
        formatPersonDateLong(DateTime(1888, 1, 1), 'yearOnly'),
        '1888 год',
      );
    });
  });

  test('D3: BrowsedPerson.fromJson читает precision (и переживает null)', () {
    final withPrecision = BrowsedPerson.fromJson(const {
      'id': 'p-1',
      'treeId': 'tree-1',
      'name': 'Пётр',
      'birthDate': '1888-01-01T00:00:00.000Z',
      'birthDatePrecision': 'yearOnly',
    });
    expect(withPrecision.birthDatePrecision, 'yearOnly');
    expect(
      FamilyPerson.datePrecisionFromString(withPrecision.birthDatePrecision),
      'yearOnly',
    );

    // Старый бэк без поля — дефолт exact.
    final legacy = BrowsedPerson.fromJson(const {
      'id': 'p-2',
      'treeId': 'tree-1',
      'name': 'Анна',
      'birthDate': '1980-06-21T00:00:00.000Z',
    });
    expect(legacy.birthDatePrecision, isNull);
    expect(
      FamilyPerson.datePrecisionFromString(legacy.birthDatePrecision),
      'exact',
    );
  });

  test('досье: yearOnly хранит точность года и форматируется без 1 января', () {
    final dossier = PersonDossier.fromPerson(_yearOnlyAncestor());

    expect(dossier.person.birthDatePrecision, 'yearOnly');
    expect(dossier.person.deathDatePrecision, 'yearOnly');
    expect(
      formatPersonDate(dossier.birthDate!, dossier.person.birthDatePrecision),
      '1888',
    );
    expect(
      formatPersonDate(
        dossier.person.deathDate!,
        dossier.person.deathDatePrecision,
      ),
      '1959',
    );
    expect(
      formatPersonDateLong(
        dossier.birthDate!,
        dossier.person.birthDatePrecision,
      ),
      '1888 год',
    );
  });
}
