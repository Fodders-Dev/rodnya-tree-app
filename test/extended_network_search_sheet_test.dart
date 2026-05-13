import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/models/extended_network_slice.dart';
import 'package:rodnya/widgets/extended_network_search_sheet.dart';

ExtendedNetworkSlice _slice() {
  return ExtendedNetworkSlice(
    graphPersons: const <ExtendedNetworkPerson>[
      ExtendedNetworkPerson(
        id: 'iv-1',
        name: 'Иван Петров',
        gender: 'male',
        birthDate: '1990',
        deathDate: null,
        photoUrl: null,
        isAlive: true,
        hopDistance: 0,
      ),
      ExtendedNetworkPerson(
        id: 'iv-2',
        name: 'Иван Сидоров',
        gender: 'male',
        birthDate: '1985',
        deathDate: null,
        photoUrl: null,
        isAlive: true,
        hopDistance: 2,
      ),
      ExtendedNetworkPerson(
        id: 'mr-1',
        name: 'Мария Иванова',
        gender: 'female',
        birthDate: '1950',
        deathDate: '2020',
        photoUrl: null,
        isAlive: false,
        hopDistance: 1,
      ),
    ],
    graphRelations: const <ExtendedNetworkRelation>[],
    branchMembership: const <String, List<String>>{},
    // Mark iv-2 as foreign (sparse: only foreign in ownerMap).
    ownerMap: const <String, ExtendedNetworkOwnerInfo>{
      'iv-2': ExtendedNetworkOwnerInfo(
        userId: 'u-other',
        displayName: 'Стёпа',
        photoUrl: null,
      ),
    },
    viewerSelfGraphPersonId: 'me-self',
    stats: const ExtendedNetworkStats(
      totalCount: 3,
      myCount: 2,
      extendedCount: 1,
      anonymousCount: 0,
      maxHopsReached: false,
      capReached: false,
    ),
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets('search sheet renders all persons initially', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ExtendedNetworkSearchSheet(
          slice: _slice(),
          onPersonSelected: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Иван Петров'), findsOneWidget);
    expect(find.text('Иван Сидоров'), findsOneWidget);
    expect(find.text('Мария Иванова'), findsOneWidget);
  });

  testWidgets('search filters by name substring (case-insensitive)',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        ExtendedNetworkSearchSheet(
          slice: _slice(),
          onPersonSelected: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'мари');
    await tester.pumpAndSettle();

    expect(find.text('Мария Иванова'), findsOneWidget);
    expect(find.text('Иван Петров'), findsNothing);
    expect(find.text('Иван Сидоров'), findsNothing);
  });

  testWidgets('search by "иван" → matches both Иванов', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ExtendedNetworkSearchSheet(
          slice: _slice(),
          onPersonSelected: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'иван');
    await tester.pumpAndSettle();

    // Both Иван Петров и Иван Сидоров (substring match).
    // Also Мария Иванова — substring 'иван' в Иванова.
    expect(find.text('Иван Петров'), findsOneWidget);
    expect(find.text('Иван Сидоров'), findsOneWidget);
    expect(find.text('Мария Иванова'), findsOneWidget);
  });

  testWidgets('empty query result → "Ничего не найдено"', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ExtendedNetworkSearchSheet(
          slice: _slice(),
          onPersonSelected: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'xyz-nomatch');
    await tester.pumpAndSettle();

    expect(find.text('Ничего не найдено'), findsOneWidget);
  });

  testWidgets('foreign result shows «не моя» badge', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ExtendedNetworkSearchSheet(
          slice: _slice(),
          onPersonSelected: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // iv-2 is foreign (in ownerMap), iv-1 / mr-1 are own.
    // Single «не моя» chip expected.
    expect(find.text('не моя'), findsOneWidget);
  });

  testWidgets('tap result → onPersonSelected called с graphPerson id',
      (tester) async {
    String? capturedId;
    await tester.pumpWidget(
      _wrap(
        ExtendedNetworkSearchSheet(
          slice: _slice(),
          onPersonSelected: (id) => capturedId = id,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Иван Сидоров'));
    await tester.pumpAndSettle();

    expect(capturedId, 'iv-2');
  });

  testWidgets('clear button показывается когда query non-empty', (tester) async {
    await tester.pumpWidget(
      _wrap(
        ExtendedNetworkSearchSheet(
          slice: _slice(),
          onPersonSelected: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.close_rounded), findsNothing);

    await tester.enterText(find.byType(TextField), 'и');
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });
}
