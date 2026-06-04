// Calendar v1 (A): the month grid renders, a day with an event surfaces
// its EventCard on selection, an empty day shows the hint.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:rodnya/backend/interfaces/family_tree_service_interface.dart';
import 'package:rodnya/models/app_event.dart';
import 'package:rodnya/models/family_person.dart';
import 'package:rodnya/models/family_relation.dart';
import 'package:rodnya/screens/family_calendar_screen.dart';
import 'package:rodnya/services/event_service.dart';
import 'package:rodnya/theme/app_theme.dart';
import 'package:rodnya/widgets/event_card.dart';

class _FakeFamilyTreeService implements FamilyTreeServiceInterface {
  _FakeFamilyTreeService({required this.relatives});

  final List<FamilyPerson> relatives;

  @override
  Future<List<FamilyPerson>> getRelatives(String treeId) async => relatives;

  @override
  Future<List<FamilyRelation>> getRelations(String treeId) async =>
      const <FamilyRelation>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  Widget host(EventService service) => MaterialApp(
        theme: AppTheme.lightTheme,
        home: FamilyCalendarScreen(
          serviceOverride: service,
          treeId: 'tree-1',
          initialMonth: DateTime(2026, 4, 15),
        ),
      );

  testWidgets(
    'renders the month grid; tapping a day with an event shows its EventCard',
    (tester) async {
      final service = EventService(
        familyTreeService: _FakeFamilyTreeService(
          relatives: [
            FamilyPerson(
              id: 'p1',
              treeId: 'tree-1',
              name: 'Иван Петров',
              gender: Gender.male,
              birthDate: DateTime(1990, 4, 3), // birthday on April 3
              isAlive: true,
              createdAt: DateTime(2024, 1, 1),
              updatedAt: DateTime(2024, 1, 1),
            ),
          ],
        ),
      );

      await tester.pumpWidget(host(service));
      await tester.pumpAndSettle();

      // Grid present.
      expect(find.byType(TableCalendar<AppEvent>), findsOneWidget);
      // Apr 15 is selected initially and has no event → hint, no card.
      expect(find.text('В этот день событий нет'), findsOneWidget);
      expect(find.byType(EventCard), findsNothing);

      // Tap April 3 (the birthday). outsideDaysVisible:false → «3» is the
      // single April-3 cell.
      await tester.tap(find.text('3'));
      await tester.pumpAndSettle();

      expect(find.byType(EventCard), findsOneWidget);
      expect(find.text('День рождения'), findsOneWidget);
    },
  );

  testWidgets('empty tree shows the no-events hint', (tester) async {
    final service = EventService(
      familyTreeService: _FakeFamilyTreeService(relatives: const []),
    );
    await tester.pumpWidget(host(service));
    await tester.pumpAndSettle();

    expect(find.byType(TableCalendar<AppEvent>), findsOneWidget);
    expect(find.text('В этот день событий нет'), findsOneWidget);
    expect(find.byType(EventCard), findsNothing);
    // Moon-phase legend (C) is present.
    expect(find.text('🌑 Новолуние'), findsOneWidget);
    expect(find.text('🌕 Полнолуние'), findsOneWidget);
  });
}
