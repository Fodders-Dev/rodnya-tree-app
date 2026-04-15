import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lineage/models/family_person.dart';
import 'package:lineage/models/family_relation.dart';
import 'package:lineage/widgets/interactive_family_tree.dart';

final Uint8List _transparentImageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9WlH0X8AAAAASUVORK5CYII=',
);

class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _TestHttpClient();
  }
}

class _TestHttpClient implements HttpClient {
  bool _autoUncompress = true;

  @override
  bool get autoUncompress => _autoUncompress;

  @override
  set autoUncompress(bool value) {
    _autoUncompress = value;
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _TestHttpClientRequest();

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _TestHttpClientRequest();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestHttpClientRequest implements HttpClientRequest {
  @override
  HttpHeaders headers = _TestHttpHeaders();

  @override
  bool followRedirects = false;

  @override
  int maxRedirects = 5;

  @override
  Future<HttpClientResponse> close() async => _TestHttpClientResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  @override
  final HttpHeaders headers = _TestHttpHeaders();

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => _transparentImageBytes.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  bool get persistentConnection => false;

  @override
  bool get isRedirect => false;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.fromIterable([_transparentImageBytes]).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestHttpHeaders implements HttpHeaders {
  @override
  void add(
    String name,
    Object value, {
    bool preserveHeaderCase = false,
  }) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final originalHttpOverrides = HttpOverrides.current;

  setUpAll(() {
    HttpOverrides.global = _TestHttpOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = originalHttpOverrides;
  });

  testWidgets('InteractiveFamilyTree does not introduce a nested Scaffold',
      (tester) async {
    final person = FamilyPerson(
      id: 'person-1',
      treeId: 'tree-1',
      userId: 'user-1',
      name: 'Иван Петров',
      gender: Gender.male,
      isAlive: true,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InteractiveFamilyTree(
            peopleData: [
              {
                'person': person,
                'userProfile': null,
              },
            ],
            relations: <FamilyRelation>[],
            onPersonTap: (_) {},
            isEditMode: false,
            onAddRelativeTapWithType: (_, __) {},
            currentUserIsInTree: true,
            onAddSelfTapWithType: (_, __) async {},
            currentUserId: 'user-1',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('Иван Петров'), findsOneWidget);
    expect(find.byTooltip('Вписать дерево'), findsOneWidget);
    expect(find.byTooltip('Ко мне'), findsOneWidget);
    expect(find.byTooltip('Увеличить'), findsOneWidget);
    expect(find.byTooltip('Уменьшить'), findsOneWidget);
    expect(find.text('Это вы'), findsOneWidget);
  });

  testWidgets('InteractiveFamilyTree shows inline edit actions in edit mode',
      (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.reset();
    });

    final person = FamilyPerson(
      id: 'person-1',
      treeId: 'tree-1',
      userId: 'user-1',
      name: 'Иван Петров',
      gender: Gender.male,
      isAlive: true,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InteractiveFamilyTree(
            peopleData: [
              {
                'person': person,
                'userProfile': null,
              },
            ],
            relations: <FamilyRelation>[],
            onPersonTap: (_) {},
            isEditMode: true,
            selectedEditPersonId: person.id,
            onAddRelativeTapWithType: (_, __) {},
            currentUserIsInTree: false,
            onAddSelfTapWithType: (_, __) async {},
            currentUserId: 'user-2',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Без фото'), findsOneWidget);
    expect(find.text('Родитель'), findsOneWidget);
    expect(find.text('Супруг'), findsOneWidget);
    expect(find.text('Ребёнок'), findsOneWidget);
    expect(find.text('Сиблинг'), findsOneWidget);
    expect(find.text('Карточка'), findsOneWidget);
    expect(find.text('Фото'), findsOneWidget);
    expect(find.text('История'), findsOneWidget);
    expect(find.text('Ещё'), findsOneWidget);
    expect(
        find.bySemanticsLabel('tree-inspector-open-gallery'), findsOneWidget);
    expect(
        find.bySemanticsLabel('tree-inspector-open-history'), findsOneWidget);
    expect(
        find.bySemanticsLabel('tree-inspector-more-actions'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets(
      'InteractiveFamilyTree bottom sheet exposes gallery and history quick actions',
      (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.reset();
    });

    var historyOpened = false;
    final person = FamilyPerson(
      id: 'person-1',
      treeId: 'tree-1',
      name: 'Иван Петров',
      gender: Gender.male,
      isAlive: true,
      photoUrl: 'https://example.com/photo-1.jpg',
      photoGallery: const [
        {
          'id': 'media-1',
          'url': 'https://example.com/photo-1.jpg',
          'isPrimary': true,
        },
        {
          'id': 'media-2',
          'url': 'https://example.com/photo-2.jpg',
          'isPrimary': false,
        },
      ],
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InteractiveFamilyTree(
            peopleData: [
              {
                'person': person,
                'userProfile': null,
              },
            ],
            relations: <FamilyRelation>[],
            onPersonTap: (_) {},
            isEditMode: true,
            selectedEditPersonId: person.id,
            onAddRelativeTapWithType: (_, __) {},
            currentUserIsInTree: true,
            onAddSelfTapWithType: (_, __) async {},
            currentUserId: 'user-1',
            onOpenPersonHistory: (_) {
              historyOpened = true;
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    tester
        .widget<ActionChip>(find.widgetWithText(ActionChip, 'Ещё'))
        .onPressed!
        .call();
    await tester.pumpAndSettle();

    expect(find.text('Быстрые переходы'), findsOneWidget);
    expect(find.text('2 фото'), findsWidgets);
    expect(find.text('Основное фото есть'), findsWidgets);
    expect(find.text('Открыть фото'), findsOneWidget);
    expect(find.text('История изменений'), findsOneWidget);
    expect(find.bySemanticsLabel('tree-sheet-open-gallery'), findsOneWidget);
    expect(find.bySemanticsLabel('tree-sheet-open-history'), findsOneWidget);

    tester
        .widget<ListTile>(find.widgetWithText(ListTile, 'История изменений'))
        .onTap!
        .call();
    await tester.pumpAndSettle();

    expect(historyOpened, isTrue);
    semantics.dispose();
  });

  testWidgets(
      'InteractiveFamilyTree marks family branches with labeled overlays',
      (tester) async {
    final father = FamilyPerson(
      id: 'person-1',
      treeId: 'tree-1',
      name: 'Иванов Иван',
      gender: Gender.male,
      isAlive: true,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );
    final mother = FamilyPerson(
      id: 'person-2',
      treeId: 'tree-1',
      name: 'Иванова Мария',
      gender: Gender.female,
      isAlive: true,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );
    final child = FamilyPerson(
      id: 'person-3',
      treeId: 'tree-1',
      name: 'Иванов Пётр',
      gender: Gender.male,
      isAlive: true,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );

    final relations = [
      FamilyRelation(
        id: 'relation-1',
        treeId: 'tree-1',
        person1Id: father.id,
        person2Id: mother.id,
        relation1to2: RelationType.spouse,
        relation2to1: RelationType.spouse,
        isConfirmed: true,
        createdAt: DateTime(2024, 1, 1),
      ),
      FamilyRelation(
        id: 'relation-2',
        treeId: 'tree-1',
        person1Id: father.id,
        person2Id: child.id,
        relation1to2: RelationType.parent,
        relation2to1: RelationType.child,
        isConfirmed: true,
        createdAt: DateTime(2024, 1, 1),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InteractiveFamilyTree(
            peopleData: [
              {'person': father, 'userProfile': null},
              {'person': mother, 'userProfile': null},
              {'person': child, 'userProfile': null},
            ],
            relations: relations,
            onPersonTap: (_) {},
            onAddRelativeTapWithType: (_, __) {},
            currentUserIsInTree: true,
            onAddSelfTapWithType: (_, __) async {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Ветка Иванов'), findsOneWidget);
  });

  testWidgets(
      'InteractiveFamilyTree keeps sibling-only relation in same visual band',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final father = FamilyPerson(
      id: 'father',
      treeId: 'tree-1',
      name: 'Иванов Иван',
      gender: Gender.male,
      isAlive: true,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );
    final mother = FamilyPerson(
      id: 'mother',
      treeId: 'tree-1',
      name: 'Иванова Мария',
      gender: Gender.female,
      isAlive: true,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );
    final anchorChild = FamilyPerson(
      id: 'anchor-child',
      treeId: 'tree-1',
      name: 'Иванов Пётр',
      gender: Gender.male,
      isAlive: true,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );
    final siblingOnly = FamilyPerson(
      id: 'sibling-only',
      treeId: 'tree-1',
      name: 'Иванова Анна',
      gender: Gender.female,
      isAlive: true,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );

    final relations = [
      FamilyRelation(
        id: 'relation-1',
        treeId: 'tree-1',
        person1Id: father.id,
        person2Id: mother.id,
        relation1to2: RelationType.spouse,
        relation2to1: RelationType.spouse,
        isConfirmed: true,
        createdAt: DateTime(2024, 1, 1),
      ),
      FamilyRelation(
        id: 'relation-2',
        treeId: 'tree-1',
        person1Id: father.id,
        person2Id: anchorChild.id,
        relation1to2: RelationType.parent,
        relation2to1: RelationType.child,
        isConfirmed: true,
        createdAt: DateTime(2024, 1, 1),
      ),
      FamilyRelation(
        id: 'relation-3',
        treeId: 'tree-1',
        person1Id: anchorChild.id,
        person2Id: siblingOnly.id,
        relation1to2: RelationType.sibling,
        relation2to1: RelationType.sibling,
        isConfirmed: true,
        createdAt: DateTime(2024, 1, 1),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InteractiveFamilyTree(
            peopleData: [
              {'person': father, 'userProfile': null},
              {'person': mother, 'userProfile': null},
              {'person': anchorChild, 'userProfile': null},
              {'person': siblingOnly, 'userProfile': null},
            ],
            relations: relations,
            onPersonTap: (_) {},
            onAddRelativeTapWithType: (_, __) {},
            currentUserIsInTree: true,
            onAddSelfTapWithType: (_, __) async {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final paint = tester.widget<CustomPaint>(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint && widget.painter is FamilyTreePainter,
      ),
    );
    final painter = paint.painter! as FamilyTreePainter;
    final anchorOffset = painter.nodePositions[anchorChild.id]!;
    final siblingOffset = painter.nodePositions[siblingOnly.id]!;

    expect((anchorOffset.dy - siblingOffset.dy).abs(), lessThan(0.1));
    expect((anchorOffset.dx - siblingOffset.dx).abs(), lessThan(260));
  });

  testWidgets(
      'InteractiveFamilyTree keeps spouse on the same generation as a person with parents',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final father = FamilyPerson(
      id: 'father',
      treeId: 'tree-1',
      name: 'Отец',
      gender: Gender.male,
      isAlive: true,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );
    final mother = FamilyPerson(
      id: 'mother',
      treeId: 'tree-1',
      name: 'Мать',
      gender: Gender.female,
      isAlive: true,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );
    final person = FamilyPerson(
      id: 'person',
      treeId: 'tree-1',
      name: 'Иван',
      gender: Gender.male,
      isAlive: true,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );
    final spouse = FamilyPerson(
      id: 'spouse',
      treeId: 'tree-1',
      name: 'Елена',
      gender: Gender.female,
      isAlive: true,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );
    final child = FamilyPerson(
      id: 'child',
      treeId: 'tree-1',
      name: 'Ребёнок',
      gender: Gender.male,
      isAlive: true,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );

    final relations = [
      FamilyRelation(
        id: 'p1',
        treeId: 'tree-1',
        person1Id: father.id,
        person2Id: person.id,
        relation1to2: RelationType.parent,
        relation2to1: RelationType.child,
        isConfirmed: true,
        createdAt: DateTime(2024, 1, 1),
      ),
      FamilyRelation(
        id: 'p2',
        treeId: 'tree-1',
        person1Id: mother.id,
        person2Id: person.id,
        relation1to2: RelationType.parent,
        relation2to1: RelationType.child,
        isConfirmed: true,
        createdAt: DateTime(2024, 1, 1),
      ),
      FamilyRelation(
        id: 'sp',
        treeId: 'tree-1',
        person1Id: spouse.id,
        person2Id: person.id,
        relation1to2: RelationType.spouse,
        relation2to1: RelationType.spouse,
        isConfirmed: true,
        createdAt: DateTime(2024, 1, 1),
      ),
      FamilyRelation(
        id: 'c1',
        treeId: 'tree-1',
        person1Id: person.id,
        person2Id: child.id,
        relation1to2: RelationType.parent,
        relation2to1: RelationType.child,
        isConfirmed: true,
        createdAt: DateTime(2024, 1, 1),
      ),
      FamilyRelation(
        id: 'c2',
        treeId: 'tree-1',
        person1Id: spouse.id,
        person2Id: child.id,
        relation1to2: RelationType.parent,
        relation2to1: RelationType.child,
        isConfirmed: true,
        createdAt: DateTime(2024, 1, 1),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InteractiveFamilyTree(
            peopleData: [
              {'person': father, 'userProfile': null},
              {'person': mother, 'userProfile': null},
              {'person': person, 'userProfile': null},
              {'person': spouse, 'userProfile': null},
              {'person': child, 'userProfile': null},
            ],
            relations: relations,
            onPersonTap: (_) {},
            onAddRelativeTapWithType: (_, __) {},
            currentUserIsInTree: true,
            onAddSelfTapWithType: (_, __) async {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final paint = tester.widget<CustomPaint>(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint && widget.painter is FamilyTreePainter,
      ),
    );
    final painter = paint.painter! as FamilyTreePainter;
    final personOffset = painter.nodePositions[person.id]!;
    final spouseOffset = painter.nodePositions[spouse.id]!;
    final childOffset = painter.nodePositions[child.id]!;

    expect((personOffset.dy - spouseOffset.dy).abs(), lessThan(0.1));
    expect(childOffset.dy, greaterThan(personOffset.dy));
  });

  testWidgets('InteractiveFamilyTree shows readable branch focus chip',
      (tester) async {
    final person = FamilyPerson(
      id: 'person-1',
      treeId: 'tree-1',
      name: 'Иван Петров',
      gender: Gender.male,
      isAlive: true,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InteractiveFamilyTree(
            peopleData: [
              {'person': person, 'userProfile': null},
            ],
            relations: const <FamilyRelation>[],
            onPersonTap: (_) {},
            onAddRelativeTapWithType: (_, __) {},
            currentUserIsInTree: true,
            onAddSelfTapWithType: (_, __) async {},
            branchRootPersonId: person.id,
            onBranchFocusRequested: (_) {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Фокус'), findsOneWidget);
  });

  testWidgets(
      'InteractiveFamilyTree shows generation guides, zoom indicator and branch reset',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final parent = FamilyPerson(
      id: 'parent',
      treeId: 'tree-1',
      name: 'Родитель',
      gender: Gender.male,
      isAlive: true,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );
    final child = FamilyPerson(
      id: 'child',
      treeId: 'tree-1',
      name: 'Ребёнок',
      gender: Gender.female,
      isAlive: true,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );

    var clearCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InteractiveFamilyTree(
            peopleData: [
              {'person': parent, 'userProfile': null},
              {'person': child, 'userProfile': null},
            ],
            relations: [
              FamilyRelation(
                id: 'rel-1',
                treeId: 'tree-1',
                person1Id: parent.id,
                person2Id: child.id,
                relation1to2: RelationType.parent,
                relation2to1: RelationType.child,
                isConfirmed: true,
                createdAt: DateTime(2024, 1, 1),
              ),
            ],
            onPersonTap: (_) {},
            onAddRelativeTapWithType: (_, __) {},
            currentUserIsInTree: true,
            onAddSelfTapWithType: (_, __) async {},
            branchRootPersonId: parent.id,
            onBranchFocusRequested: (_) {},
            onBranchFocusCleared: () => clearCalls += 1,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final zoomIndicatorFinder = find.byWidgetPredicate(
      (widget) => widget is Text && (widget.data?.endsWith('%') ?? false),
      description: 'zoom indicator',
    );

    expect(find.text('Старшее поколение'), findsOneWidget);
    expect(find.text('Младшее поколение'), findsOneWidget);
    expect(zoomIndicatorFinder, findsOneWidget);
    expect(find.byTooltip('Сбросить ветку'), findsOneWidget);

    await tester.tap(find.byTooltip('Сбросить ветку'));
    await tester.pumpAndSettle();
    expect(clearCalls, 1);
  });
}
