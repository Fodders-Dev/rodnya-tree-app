import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:rodnya/backend/interfaces/semya_capable_family_tree_service.dart';
import 'package:rodnya/backend/models/deleted_person.dart';
import 'package:rodnya/backend/models/deleted_post.dart';
import 'package:rodnya/models/family_connection_prompt.dart';
import 'package:rodnya/models/family_person.dart';
import 'package:rodnya/models/family_story_question.dart';
import 'package:rodnya/models/tree_change_record.dart';
import 'package:rodnya/screens/trash_screen.dart';
import 'package:rodnya/theme/app_theme.dart';
import 'package:rodnya/utils/app_version_label.dart';
import 'package:rodnya/widgets/family_tree_node_card.dart';
import 'package:rodnya/widgets/interactive_family_tree.dart';
import 'package:rodnya/widgets/tree_history_sheet.dart';

class _EmptyTrashSemyaService implements SemyaCapableFamilyTreeService {
  @override
  Future<List<DeletedPerson>> listMyDeletedPersons() async =>
      const <DeletedPerson>[];

  @override
  Future<List<DeletedPost>> listMyDeletedPosts() async => const <DeletedPost>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  test('Item 13: loadAppVersionLabel falls back when platform channel fails',
      () async {
    final label = await loadAppVersionLabel();
    expect(label, kFallbackAppVersionLabel);
    expect(label, contains('1.0.49'));
  });

  test(
      'Items 10c/10d: nominative female names are not broken by case declension',
      () {
    final grandma = FamilyPerson(
      id: 'gm',
      treeId: 'tree-1',
      name: 'Петрова Мария',
      relation: 'Бабушка',
      gender: Gender.female,
      birthDate: DateTime(1948, 3, 12),
      isAlive: true,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );
    final prompt = FamilyConnectionPromptSelector.select(
      currentUserId: 'me',
      now: DateTime(2026, 11, 26),
      relatives: [grandma],
    );
    expect(prompt, isNotNull);
    expect(prompt!.message, contains('Мария'));
    expect(prompt.message, isNot(contains('Задайте Мария')));

    final shareText = buildFamilyStoryShareMessage(
      question: familyStoryQuestions.first,
      personName: 'Анна',
      relation: 'Бабушка',
    );
    expect(shareText, contains('Анна (Бабушка)'));
    expect(shareText, isNot(contains('про Анна')));
  });

  testWidgets(
      'Item 10e: TreeHistorySheet shows personName & actorName while preserving title',
      (tester) async {
    final json = <String, dynamic>{
      'id': 'chg-1',
      'treeId': 'tree-1',
      'actorId': 'user-other',
      'actorName': 'Елена Смирнова',
      'personId': 'person-2',
      'personName': 'Пётр Иванов',
      'type': 'person.updated',
      'createdAt': '2026-11-26T12:30:00Z',
    };
    final record = TreeChangeRecord.fromJson(json);
    expect(record.actorName, 'Елена Смирнова');
    expect(record.personName, 'Пётр Иванов');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: TreeHistorySheet(
            historyFuture: Future.value([record]),
            title: 'История дерева',
            subtitle: 'Семья Ивановых',
            currentUserId: 'user-me',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Обновлён профиль'), findsOneWidget);
    expect(find.textContaining('Пётр Иванов'), findsOneWidget);
    expect(find.textContaining('Елена Смирнова'), findsOneWidget);
  });

  testWidgets(
      'Items 5a/5b: InteractiveFamilyTree supports horizontal reserved insets and opaque current-user node',
      (tester) async {
    final me = FamilyPerson(
      id: 'me-1',
      treeId: 'tree-1',
      userId: 'user-1',
      name: 'Иванов Сергей',
      gender: Gender.male,
      isAlive: true,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Column(
            children: [
              const FamilyTreeNodeCard(
                displayName: 'Иванов Сергей',
                lifeDates: '1990 - н.в.',
                displayGender: Gender.male,
                isCurrentUserNode: true,
              ),
              Expanded(
                child: InteractiveFamilyTree(
                  peopleData: [
                    {'person': me},
                  ],
                  relations: const [],
                  currentUserId: 'user-1',
                  currentUserIsInTree: true,
                  viewportReservedLeft: 336,
                  viewportReservedRight: 64,
                  onPersonTap: (_) {},
                  onAddRelativeTapWithType: (_, __) {},
                  onAddSelfTapWithType: (_, __) {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final cardContainer = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(FamilyTreeNodeCard),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = cardContainer.decoration! as BoxDecoration;
    expect(decoration.color, isNotNull);
    expect(decoration.color!.a, equals(1.0));
  });

  testWidgets(
      'Item 12c: TrashScreen uses TabBarIndicatorSize.tab and tab-specific subtitles',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: TrashScreen(serviceOverride: _EmptyTrashSemyaService()),
      ),
    );
    await tester.pumpAndSettle();

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.indicatorSize, TabBarIndicatorSize.tab);
    expect(find.text('Корзина пуста'), findsOneWidget);
    expect(
      find.textContaining('Удалённые карточки родственников'),
      findsOneWidget,
    );

    await tester.tap(find.text('Посты'));
    await tester.pumpAndSettle();

    expect(find.text('Корзина пуста'), findsOneWidget);
    expect(find.textContaining('Удалённые посты'), findsOneWidget);
  });
}
