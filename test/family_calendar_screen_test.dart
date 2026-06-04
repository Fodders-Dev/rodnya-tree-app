// Calendar v1 (A): the month grid renders, a day with an event surfaces
// its EventCard on selection, an empty day shows the hint.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:rodnya/backend/interfaces/family_tree_service_interface.dart';
import 'package:rodnya/models/app_event.dart';
import 'package:rodnya/models/family_person.dart';
import 'package:rodnya/models/family_relation.dart';
import 'package:rodnya/screens/family_calendar_screen.dart';
import 'package:rodnya/services/event_service.dart';
import 'package:rodnya/theme/app_theme.dart';
import 'package:rodnya/utils/moon_phase.dart';
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

/// EventService whose month fetch always throws — drives the CP-2 error
/// state (the real service now lets errors propagate).
class _ThrowingEventService extends EventService {
  _ThrowingEventService()
      : super(familyTreeService: _FakeFamilyTreeService(relatives: const []));

  @override
  Future<List<AppEvent>> getEventsForMonth(String t, int y, int m) async {
    throw Exception('network down');
  }
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

  // ── CP-a: tap a holiday → info; family event → profile (unchanged) ──

  Widget routerHost(EventService service, {required DateTime initialMonth}) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => FamilyCalendarScreen(
            serviceOverride: service,
            treeId: 'tree-1',
            initialMonth: initialMonth,
          ),
        ),
        GoRoute(
          path: '/relative/details/:id',
          builder: (_, state) => Scaffold(
            body: Text('profile-${state.pathParameters['id']}'),
          ),
        ),
      ],
    );
    return MaterialApp.router(theme: AppTheme.lightTheme, routerConfig: router);
  }

  testWidgets('tapping a holiday shows its info bottom-sheet', (tester) async {
    final service = EventService(
      familyTreeService: _FakeFamilyTreeService(relatives: const []),
    );
    await tester.pumpWidget(
      routerHost(service, initialMonth: DateTime(2026, 5, 9)),
    );
    await tester.pumpAndSettle();

    // May 9 selected → «День Победы» card.
    expect(find.text('День Победы'), findsOneWidget);
    await tester.tap(find.text('День Победы'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('holiday-info-sheet')), findsOneWidget);
    expect(find.textContaining('Великой Отечественной'), findsOneWidget);
  });

  testWidgets(
    'tapping a family event opens the profile, not a holiday sheet',
    (tester) async {
      final service = EventService(
        familyTreeService: _FakeFamilyTreeService(
          relatives: [
            FamilyPerson(
              id: 'p1',
              treeId: 'tree-1',
              name: 'Иван Петров',
              gender: Gender.male,
              birthDate: DateTime(1990, 5, 9), // birthday on May 9
              isAlive: true,
              createdAt: DateTime(2024, 1, 1),
              updatedAt: DateTime(2024, 1, 1),
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        routerHost(service, initialMonth: DateTime(2026, 5, 9)),
      );
      await tester.pumpAndSettle();

      expect(find.text('День рождения'), findsOneWidget);
      await tester.tap(find.text('День рождения'));
      await tester.pumpAndSettle();

      // Navigated to the profile; no holiday sheet.
      expect(find.text('profile-p1'), findsOneWidget);
      expect(find.byKey(const Key('holiday-info-sheet')), findsNothing);
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
    // Moon gardening tip (CP-b) for the selected day is shown.
    expect(find.byKey(const Key('moon-tip')), findsOneWidget);
    final tip = gardeningTip(moonPhaseFor(DateTime(2026, 4, 15)));
    expect(find.text(tip), findsOneWidget);
  });

  testWidgets('shows error + «Повторить» when the month fails to load (CP-2)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: FamilyCalendarScreen(
          serviceOverride: _ThrowingEventService(),
          treeId: 'tree-1',
          initialMonth: DateTime(2026, 4, 15),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Не удалось загрузить'), findsOneWidget);
    expect(find.byKey(const Key('calendar-retry')), findsOneWidget);
  });

  testWidgets('shows «Выберите дерево» when no tree is bound (CP-2)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: FamilyCalendarScreen(
          serviceOverride: EventService(
            familyTreeService: _FakeFamilyTreeService(relatives: const []),
          ),
          treeId: '', // no tree bound
          initialMonth: DateTime(2026, 4, 15),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Выберите дерево'), findsOneWidget);
    expect(find.byKey(const Key('calendar-no-tree-cta')), findsOneWidget);
  });

  testWidgets('renders in dark theme without error (CP-1 legibility)',
      (tester) async {
    final service = EventService(
      familyTreeService: _FakeFamilyTreeService(relatives: const []),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: FamilyCalendarScreen(
          serviceOverride: service,
          treeId: 'tree-1',
          initialMonth: DateTime(2026, 4, 15),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TableCalendar<AppEvent>), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
