// Phase E2c: GatheringCard renders the event fields + «Встреча» badge.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:rodnya/models/gathering.dart';
import 'package:rodnya/theme/app_theme.dart';
import 'package:rodnya/widgets/gathering_card.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  testWidgets('renders the gathering title, place, author and badge',
      (tester) async {
    final gathering = Gathering(
      id: 'g1',
      treeId: 'tree-1',
      authorId: 'u1',
      authorName: 'Анна',
      title: 'Шашлыки на даче',
      description: 'Приезжайте всей семьёй',
      startAt: DateTime(2026, 7, 1, 15, 0),
      place: 'Дача в Подмосковье',
      createdAt: DateTime(2026, 6, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: GatheringCard(gathering: gathering)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('gathering-card-g1')), findsOneWidget);
    expect(find.text('Шашлыки на даче'), findsOneWidget);
    expect(find.text('Дача в Подмосковье'), findsOneWidget);
    expect(find.text('Приезжайте всей семьёй'), findsOneWidget);
    expect(find.text('Анна'), findsOneWidget);
    expect(find.text('Встреча'), findsOneWidget); // type badge
  });
}
