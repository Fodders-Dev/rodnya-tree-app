import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/models/family_person.dart';
import 'package:rodnya/models/family_relation.dart';
import 'package:rodnya/models/tree_graph_snapshot.dart';
import 'package:rodnya/widgets/interactive_family_tree.dart';

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
      'InteractiveFamilyTree touch long press opens direct relative add sheet',
      (tester) async {
    RelationType? capturedRelationType;
    FamilyPerson? capturedPerson;

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
              {
                'person': person,
                'userProfile': null,
              },
            ],
            relations: const <FamilyRelation>[],
            onPersonTap: (_) {},
            onAddRelativeTapWithType: (targetPerson, relationType) {
              capturedPerson = targetPerson;
              capturedRelationType = relationType;
            },
            currentUserIsInTree: true,
            onAddSelfTapWithType: (_, __) async {},
            onShowRelationPath: (_) {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.longPress(
      find.byKey(const ValueKey<String>('tree-node-person-1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Добавить к карточке'), findsOneWidget);
    expect(find.text('Добавить ребёнка'), findsOneWidget);

    await tester.tap(find.text('Добавить ребёнка'));
    await tester.pumpAndSettle();

    expect(capturedPerson?.id, person.id);
    expect(capturedRelationType, RelationType.child);
  });

  testWidgets(
      'InteractiveFamilyTree shows hover plus button for desktop add flow',
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
              {
                'person': person,
                'userProfile': null,
              },
            ],
            relations: const <FamilyRelation>[],
            onPersonTap: (_) {},
            onAddRelativeTapWithType: (_, __) {},
            currentUserIsInTree: true,
            onAddSelfTapWithType: (_, __) async {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('tree-node-add-relative-person-1')),
      findsNothing,
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer();
    await gesture.moveTo(
      tester
          .getCenter(find.byKey(const ValueKey<String>('tree-node-person-1'))),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('tree-node-add-relative-person-1')),
      findsOneWidget,
    );

    await gesture.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey<String>('tree-node-add-relative-person-1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('tree-node-add-relative-person-1')),
      findsOneWidget,
    );
  });

  testWidgets(
      'InteractiveFamilyTree keeps canvas minimal without branch overlays',
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

    expect(find.text('Иванов Иван'), findsOneWidget);
    expect(find.text('Иванова Мария'), findsOneWidget);
    expect(find.text('Иванов Пётр'), findsOneWidget);
    expect(find.text('Ветка Иванов'), findsNothing);
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

  testWidgets(
      'InteractiveFamilyTree does not let graph generation rows split spouses',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final grandpa = FamilyPerson(
      id: 'grandpa',
      treeId: 'tree-1',
      name: 'Дед',
      gender: Gender.male,
      isAlive: true,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );
    final grandma = FamilyPerson(
      id: 'grandma',
      treeId: 'tree-1',
      name: 'Бабушка',
      gender: Gender.female,
      isAlive: true,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );
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
        id: 'grand-union',
        treeId: 'tree-1',
        person1Id: grandpa.id,
        person2Id: grandma.id,
        relation1to2: RelationType.spouse,
        relation2to1: RelationType.spouse,
        isConfirmed: true,
        createdAt: DateTime(2024, 1, 1),
      ),
      FamilyRelation(
        id: 'grand-parent-1',
        treeId: 'tree-1',
        person1Id: grandpa.id,
        person2Id: father.id,
        relation1to2: RelationType.parent,
        relation2to1: RelationType.child,
        isConfirmed: true,
        createdAt: DateTime(2024, 1, 1),
      ),
      FamilyRelation(
        id: 'grand-parent-2',
        treeId: 'tree-1',
        person1Id: grandma.id,
        person2Id: father.id,
        relation1to2: RelationType.parent,
        relation2to1: RelationType.child,
        isConfirmed: true,
        createdAt: DateTime(2024, 1, 1),
      ),
      FamilyRelation(
        id: 'parents-union',
        treeId: 'tree-1',
        person1Id: father.id,
        person2Id: mother.id,
        relation1to2: RelationType.spouse,
        relation2to1: RelationType.spouse,
        isConfirmed: true,
        createdAt: DateTime(2024, 1, 1),
      ),
      FamilyRelation(
        id: 'child-parent-1',
        treeId: 'tree-1',
        person1Id: father.id,
        person2Id: child.id,
        relation1to2: RelationType.parent,
        relation2to1: RelationType.child,
        isConfirmed: true,
        createdAt: DateTime(2024, 1, 1),
      ),
      FamilyRelation(
        id: 'child-parent-2',
        treeId: 'tree-1',
        person1Id: mother.id,
        person2Id: child.id,
        relation1to2: RelationType.parent,
        relation2to1: RelationType.child,
        isConfirmed: true,
        createdAt: DateTime(2024, 1, 1),
      ),
    ];

    final snapshot = TreeGraphSnapshot(
      treeId: 'tree-1',
      viewerPersonId: child.id,
      people: [grandpa, grandma, father, mother, child],
      relations: relations,
      familyUnits: const <TreeGraphFamilyUnit>[],
      viewerDescriptors: const <TreeGraphViewerDescriptor>[],
      branchBlocks: const <TreeGraphBranchBlock>[],
      generationRows: const <TreeGraphGenerationRow>[
        TreeGraphGenerationRow(
          row: 0,
          label: 'Старшее поколение',
          personIds: ['grandpa', 'grandma'],
          familyUnitIds: <String>[],
        ),
        TreeGraphGenerationRow(
          row: 1,
          label: 'Отец',
          personIds: ['father'],
          familyUnitIds: <String>[],
        ),
        TreeGraphGenerationRow(
          row: 2,
          label: 'Мать',
          personIds: ['mother'],
          familyUnitIds: <String>[],
        ),
        TreeGraphGenerationRow(
          row: 3,
          label: 'Младшее поколение',
          personIds: ['child'],
          familyUnitIds: <String>[],
        ),
      ],
      warnings: const <TreeGraphWarning>[],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InteractiveFamilyTree(
            peopleData: [
              {'person': grandpa, 'userProfile': null},
              {'person': grandma, 'userProfile': null},
              {'person': father, 'userProfile': null},
              {'person': mother, 'userProfile': null},
              {'person': child, 'userProfile': null},
            ],
            relations: relations,
            graphSnapshot: snapshot,
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
    final fatherOffset = painter.nodePositions[father.id]!;
    final motherOffset = painter.nodePositions[mother.id]!;
    final childOffset = painter.nodePositions[child.id]!;

    expect((fatherOffset.dy - motherOffset.dy).abs(), lessThan(0.1));
    expect(childOffset.dy, greaterThan(fatherOffset.dy));
  });

  testWidgets(
      'InteractiveFamilyTree places partners outside the sibling rail for child groups',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
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
    final leftChild = FamilyPerson(
      id: 'left-child',
      treeId: 'tree-1',
      name: 'Алексей',
      gender: Gender.male,
      isAlive: true,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );
    final leftPartner = FamilyPerson(
      id: 'left-partner',
      treeId: 'tree-1',
      name: 'Анна',
      gender: Gender.female,
      isAlive: true,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );
    final rightChild = FamilyPerson(
      id: 'right-child',
      treeId: 'tree-1',
      name: 'Виктор',
      gender: Gender.male,
      isAlive: true,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );
    final rightPartner = FamilyPerson(
      id: 'right-partner',
      treeId: 'tree-1',
      name: 'Вера',
      gender: Gender.female,
      isAlive: true,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );

    final relations = [
      FamilyRelation(
        id: 'parent-left-f',
        treeId: 'tree-1',
        person1Id: father.id,
        person2Id: leftChild.id,
        relation1to2: RelationType.parent,
        relation2to1: RelationType.child,
        isConfirmed: true,
        createdAt: DateTime(2024, 1, 1),
      ),
      FamilyRelation(
        id: 'parent-left-m',
        treeId: 'tree-1',
        person1Id: mother.id,
        person2Id: leftChild.id,
        relation1to2: RelationType.parent,
        relation2to1: RelationType.child,
        isConfirmed: true,
        createdAt: DateTime(2024, 1, 1),
      ),
      FamilyRelation(
        id: 'parent-right-f',
        treeId: 'tree-1',
        person1Id: father.id,
        person2Id: rightChild.id,
        relation1to2: RelationType.parent,
        relation2to1: RelationType.child,
        isConfirmed: true,
        createdAt: DateTime(2024, 1, 1),
      ),
      FamilyRelation(
        id: 'parent-right-m',
        treeId: 'tree-1',
        person1Id: mother.id,
        person2Id: rightChild.id,
        relation1to2: RelationType.parent,
        relation2to1: RelationType.child,
        isConfirmed: true,
        createdAt: DateTime(2024, 1, 1),
      ),
      FamilyRelation(
        id: 'spouse-left',
        treeId: 'tree-1',
        person1Id: leftChild.id,
        person2Id: leftPartner.id,
        relation1to2: RelationType.partner,
        relation2to1: RelationType.partner,
        isConfirmed: true,
        createdAt: DateTime(2024, 1, 1),
      ),
      FamilyRelation(
        id: 'spouse-right',
        treeId: 'tree-1',
        person1Id: rightChild.id,
        person2Id: rightPartner.id,
        relation1to2: RelationType.partner,
        relation2to1: RelationType.partner,
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
              {'person': leftChild, 'userProfile': null},
              {'person': leftPartner, 'userProfile': null},
              {'person': rightChild, 'userProfile': null},
              {'person': rightPartner, 'userProfile': null},
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
    final leftChildOffset = painter.nodePositions[leftChild.id]!;
    final leftPartnerOffset = painter.nodePositions[leftPartner.id]!;
    final rightChildOffset = painter.nodePositions[rightChild.id]!;
    final rightPartnerOffset = painter.nodePositions[rightPartner.id]!;

    expect(leftPartnerOffset.dx, lessThan(leftChildOffset.dx));
    expect(rightPartnerOffset.dx, greaterThan(rightChildOffset.dx));
    expect((leftPartnerOffset.dy - leftChildOffset.dy).abs(), lessThan(0.1));
    expect((rightPartnerOffset.dy - rightChildOffset.dy).abs(), lessThan(0.1));
  });

  testWidgets(
      'InteractiveFamilyTree keeps connected grandparents above the correct parent side',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 1100);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    FamilyPerson person(String id, String name, Gender gender) => FamilyPerson(
          id: id,
          treeId: 'tree-1',
          name: name,
          gender: gender,
          isAlive: true,
          createdAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 1, 1),
        );

    final gennady = person('gennady', 'Мочалкин Геннадий', Gender.male);
    final lydia = person('lydia', 'Мочалкина Лидия', Gender.female);
    final anatoly = person('anatoly', 'Кузнецов Анатолий', Gender.male);
    final valentina = person('valentina', 'Кузнецова Валентина', Gender.female);
    final natalia = person('natalia', 'Кузнецова Наталья', Gender.female);
    final andrey = person('andrey', 'Кузнецов Андрей', Gender.male);
    final evgeniy = person('evgeniy', 'Мочалкин Евгений', Gender.male);
    final artem = person('artem', 'Кузнецов Артем', Gender.male);

    FamilyRelation parentRelation(String id, String parentId, String childId) =>
        FamilyRelation(
          id: id,
          treeId: 'tree-1',
          person1Id: parentId,
          person2Id: childId,
          relation1to2: RelationType.parent,
          relation2to1: RelationType.child,
          isConfirmed: true,
          createdAt: DateTime(2024, 1, 1),
        );

    FamilyRelation unionRelation(String id, String leftId, String rightId) =>
        FamilyRelation(
          id: id,
          treeId: 'tree-1',
          person1Id: leftId,
          person2Id: rightId,
          relation1to2: RelationType.spouse,
          relation2to1: RelationType.spouse,
          isConfirmed: true,
          createdAt: DateTime(2024, 1, 1),
        );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InteractiveFamilyTree(
            peopleData: [
              {'person': gennady, 'userProfile': null},
              {'person': lydia, 'userProfile': null},
              {'person': anatoly, 'userProfile': null},
              {'person': valentina, 'userProfile': null},
              {'person': natalia, 'userProfile': null},
              {'person': andrey, 'userProfile': null},
              {'person': evgeniy, 'userProfile': null},
              {'person': artem, 'userProfile': null},
            ],
            relations: [
              unionRelation('paternal-union', anatoly.id, valentina.id),
              unionRelation('maternal-union', gennady.id, lydia.id),
              unionRelation('parents-union', andrey.id, natalia.id),
              parentRelation('paternal-child-1', anatoly.id, andrey.id),
              parentRelation('paternal-child-2', valentina.id, andrey.id),
              parentRelation('maternal-child-1', gennady.id, natalia.id),
              parentRelation('maternal-child-2', lydia.id, natalia.id),
              parentRelation('maternal-child-3', gennady.id, evgeniy.id),
              parentRelation('maternal-child-4', lydia.id, evgeniy.id),
              parentRelation('child-1', andrey.id, artem.id),
              parentRelation('child-2', natalia.id, artem.id),
            ],
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

    final gennadyOffset = painter.nodePositions[gennady.id]!;
    final lydiaOffset = painter.nodePositions[lydia.id]!;
    final anatolyOffset = painter.nodePositions[anatoly.id]!;
    final valentinaOffset = painter.nodePositions[valentina.id]!;
    final nataliaOffset = painter.nodePositions[natalia.id]!;
    final andreyOffset = painter.nodePositions[andrey.id]!;
    final evgeniyOffset = painter.nodePositions[evgeniy.id]!;
    final artemOffset = painter.nodePositions[artem.id]!;

    expect(gennadyOffset.dx, lessThan(lydiaOffset.dx));
    expect(anatolyOffset.dx, lessThan(valentinaOffset.dx));

    final paternalCenter = (anatolyOffset.dx + valentinaOffset.dx) / 2;
    final maternalCenter = (gennadyOffset.dx + lydiaOffset.dx) / 2;
    final parentsCenter = (andreyOffset.dx + nataliaOffset.dx) / 2;

    expect(
      (andreyOffset.dx - paternalCenter).abs(),
      lessThan((andreyOffset.dx - maternalCenter).abs()),
    );
    expect(
      (nataliaOffset.dx - maternalCenter).abs(),
      lessThan((nataliaOffset.dx - paternalCenter).abs()),
    );
    expect(
      (evgeniyOffset.dx - maternalCenter).abs(),
      lessThan((evgeniyOffset.dx - paternalCenter).abs()),
    );
    expect((artemOffset.dx - parentsCenter).abs(), lessThan(120));
  });

  testWidgets(
      'InteractiveFamilyTree keeps the current Kuznetsov tree partners on the right generations',
      (tester) async {
    tester.view.physicalSize = const Size(1900, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    FamilyPerson person(
      String id,
      String name,
      Gender gender, {
      DateTime? birthDate,
      bool isAlive = true,
    }) =>
        FamilyPerson(
          id: id,
          treeId: 'tree-1',
          name: name,
          gender: gender,
          birthDate: birthDate,
          isAlive: isAlive,
          createdAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 1, 1),
        );

    FamilyRelation parentRelation(String id, String parentId, String childId) =>
        FamilyRelation(
          id: id,
          treeId: 'tree-1',
          person1Id: parentId,
          person2Id: childId,
          relation1to2: RelationType.parent,
          relation2to1: RelationType.child,
          isConfirmed: true,
          createdAt: DateTime(2024, 1, 1),
        );

    FamilyRelation unionRelation(
      String id,
      String leftId,
      String rightId, {
      RelationType relationType = RelationType.spouse,
    }) =>
        FamilyRelation(
          id: id,
          treeId: 'tree-1',
          person1Id: leftId,
          person2Id: rightId,
          relation1to2: relationType,
          relation2to1: relationType,
          isConfirmed: true,
          createdAt: DateTime(2024, 1, 1),
        );

    final alexander =
        person('alexander', 'Супрунов Александр', Gender.male, isAlive: false);
    final maria = person('maria', 'Супрунова Мария', Gender.female);
    final gennady = person('gennady', 'Мочалкин Геннадий Иванович', Gender.male,
        isAlive: false);
    final lydia = person(
        'lydia', 'Мочалкина Лидия Александровна', Gender.female,
        isAlive: false);
    final anatoly = person(
      'anatoly',
      'Кузнецов Анатолий Степанович',
      Gender.male,
    );
    final valentina = person(
      'valentina',
      'Кузнецова Валентина',
      Gender.female,
    );
    final andrey = person(
      'andrey',
      'Кузнецов Андрей Анатольевич',
      Gender.male,
      birthDate: DateTime(1971, 12, 16),
    );
    final natalia = person(
      'natalia',
      'Кузнецова Наталья Геннадьевна',
      Gender.female,
      birthDate: DateTime(1974, 5, 25),
    );
    final evgeniy = person(
      'evgeniy',
      'Мочалкин Евгений Геннадьевич',
      Gender.male,
      birthDate: DateTime(1971, 5, 25),
    );
    final artem = person(
      'artem',
      'Кузнецов Артем Андреевич',
      Gender.male,
      birthDate: DateTime(2002, 9, 24),
    );
    final anastasia = person(
      'anastasia',
      'Шуфляк Анастасия Эдуардовна',
      Gender.female,
      birthDate: DateTime(2000, 5, 16),
    );
    final darya = person(
      'darya',
      'Понькина Дарья Андреевна',
      Gender.female,
      birthDate: DateTime(1996, 1, 5),
    );
    final sergey = person(
      'sergey',
      'Понькин Сергей Леонидович',
      Gender.male,
      birthDate: DateTime(1987, 6, 13),
    );
    final pavel = person(
      'pavel',
      'Понькин Павел Сергеевич',
      Gender.male,
      birthDate: DateTime(2024, 2, 14),
    );

    final relations = [
      parentRelation('r1', andrey.id, artem.id),
      parentRelation('r2', natalia.id, artem.id),
      unionRelation('r3', andrey.id, natalia.id),
      unionRelation(
        'r4',
        anastasia.id,
        artem.id,
        relationType: RelationType.partner,
      ),
      FamilyRelation(
        id: 'r5',
        treeId: 'tree-1',
        person1Id: darya.id,
        person2Id: artem.id,
        relation1to2: RelationType.sibling,
        relation2to1: RelationType.sibling,
        isConfirmed: true,
        createdAt: DateTime(2024, 1, 1),
      ),
      parentRelation('r6', andrey.id, darya.id),
      parentRelation('r7', natalia.id, darya.id),
      unionRelation('r8', sergey.id, darya.id),
      parentRelation('r9', darya.id, pavel.id),
      parentRelation('r10', sergey.id, pavel.id),
      parentRelation('r11', anatoly.id, andrey.id),
      parentRelation('r12', valentina.id, andrey.id),
      parentRelation('r13', gennady.id, natalia.id),
      parentRelation('r14', lydia.id, natalia.id),
      parentRelation('r15', gennady.id, evgeniy.id),
      parentRelation('r16', lydia.id, evgeniy.id),
      parentRelation('r17', alexander.id, lydia.id),
      parentRelation('r18', maria.id, lydia.id),
      unionRelation('r19', anatoly.id, valentina.id),
      unionRelation('r20', gennady.id, lydia.id),
      unionRelation('r21', alexander.id, maria.id),
    ];
    final graphSnapshot = TreeGraphSnapshot(
      treeId: 'tree-1',
      viewerPersonId: artem.id,
      people: [
        alexander,
        maria,
        gennady,
        lydia,
        anatoly,
        valentina,
        andrey,
        natalia,
        evgeniy,
        artem,
        anastasia,
        darya,
        sergey,
        pavel,
      ],
      relations: relations,
      familyUnits: [
        TreeGraphFamilyUnit(
          id: 'fu-1',
          rootParentSetId: 'lydia-parents',
          adultIds: [alexander.id, maria.id],
          childIds: [lydia.id],
          relationIds: ['r17', 'r18', 'r21'],
          unionId: 'r21',
          unionType: 'spouse',
          unionStatus: 'current',
          parentSetType: 'biological',
          isPrimaryParentSet: true,
          label: 'Семья Супруновых',
        ),
        TreeGraphFamilyUnit(
          id: 'fu-2',
          rootParentSetId: 'mochalkin-parents',
          adultIds: [gennady.id, lydia.id],
          childIds: [natalia.id, evgeniy.id],
          relationIds: ['r13', 'r14', 'r15', 'r16', 'r20'],
          unionId: 'r20',
          unionType: 'spouse',
          unionStatus: 'current',
          parentSetType: 'biological',
          isPrimaryParentSet: true,
          label: 'Семья Мочалкиных',
        ),
        TreeGraphFamilyUnit(
          id: 'fu-3',
          rootParentSetId: 'andrey-parents',
          adultIds: [anatoly.id, valentina.id],
          childIds: [andrey.id],
          relationIds: ['r11', 'r12', 'r19'],
          unionId: 'r19',
          unionType: 'spouse',
          unionStatus: 'current',
          parentSetType: 'biological',
          isPrimaryParentSet: true,
          label: 'Семья Кузнецовых',
        ),
        TreeGraphFamilyUnit(
          id: 'fu-4',
          rootParentSetId: 'children-parents',
          adultIds: [andrey.id, natalia.id],
          childIds: [artem.id, darya.id],
          relationIds: ['r1', 'r2', 'r3', 'r5', 'r6', 'r7'],
          unionId: 'r3',
          unionType: 'spouse',
          unionStatus: 'current',
          parentSetType: 'biological',
          isPrimaryParentSet: true,
          label: 'Семья Андрея и Натальи',
        ),
        TreeGraphFamilyUnit(
          id: 'fu-5',
          rootParentSetId: null,
          adultIds: [artem.id, anastasia.id],
          childIds: const [],
          relationIds: ['r4'],
          unionId: 'r4',
          unionType: 'partner',
          unionStatus: 'current',
          parentSetType: null,
          isPrimaryParentSet: false,
          label: 'Артем и Анастасия',
        ),
        TreeGraphFamilyUnit(
          id: 'fu-6',
          rootParentSetId: 'pavel-parents',
          adultIds: [sergey.id, darya.id],
          childIds: [pavel.id],
          relationIds: ['r8', 'r9', 'r10'],
          unionId: 'r8',
          unionType: 'spouse',
          unionStatus: 'current',
          parentSetType: 'biological',
          isPrimaryParentSet: true,
          label: 'Семья Понькиных',
        ),
      ],
      viewerDescriptors: const [],
      branchBlocks: const [],
      generationRows: [
        TreeGraphGenerationRow(
          row: 0,
          label: 'Старшее поколение',
          personIds: [alexander.id, maria.id],
          familyUnitIds: const ['fu-1'],
        ),
        TreeGraphGenerationRow(
          row: 1,
          label: 'Поколение 2',
          personIds: [gennady.id, lydia.id, anatoly.id, valentina.id],
          familyUnitIds: const ['fu-1', 'fu-2', 'fu-3'],
        ),
        TreeGraphGenerationRow(
          row: 2,
          label: 'Поколение 3',
          personIds: [andrey.id, natalia.id, evgeniy.id],
          familyUnitIds: const ['fu-2', 'fu-3', 'fu-4'],
        ),
        TreeGraphGenerationRow(
          row: 3,
          label: 'Поколение 4',
          personIds: [artem.id, anastasia.id, darya.id, sergey.id],
          familyUnitIds: const ['fu-4', 'fu-5', 'fu-6'],
        ),
        TreeGraphGenerationRow(
          row: 4,
          label: 'Младшее поколение',
          personIds: [pavel.id],
          familyUnitIds: const ['fu-6'],
        ),
      ],
      warnings: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InteractiveFamilyTree(
            peopleData: [
              {'person': alexander, 'userProfile': null},
              {'person': maria, 'userProfile': null},
              {'person': gennady, 'userProfile': null},
              {'person': lydia, 'userProfile': null},
              {'person': anatoly, 'userProfile': null},
              {'person': valentina, 'userProfile': null},
              {'person': andrey, 'userProfile': null},
              {'person': natalia, 'userProfile': null},
              {'person': evgeniy, 'userProfile': null},
              {'person': artem, 'userProfile': null},
              {'person': anastasia, 'userProfile': null},
              {'person': darya, 'userProfile': null},
              {'person': sergey, 'userProfile': null},
              {'person': pavel, 'userProfile': null},
            ],
            relations: relations,
            graphSnapshot: graphSnapshot,
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

    final artemOffset = painter.nodePositions[artem.id]!;
    final anastasiaOffset = painter.nodePositions[anastasia.id]!;
    final daryaOffset = painter.nodePositions[darya.id]!;
    final sergeyOffset = painter.nodePositions[sergey.id]!;
    final andreyOffset = painter.nodePositions[andrey.id]!;
    final nataliaOffset = painter.nodePositions[natalia.id]!;
    final gennadyOffset = painter.nodePositions[gennady.id]!;
    final lydiaOffset = painter.nodePositions[lydia.id]!;
    final alexanderOffset = painter.nodePositions[alexander.id]!;
    final mariaOffset = painter.nodePositions[maria.id]!;
    final anatolyOffset = painter.nodePositions[anatoly.id]!;
    final valentinaOffset = painter.nodePositions[valentina.id]!;

    expect((artemOffset.dy - anastasiaOffset.dy).abs(), lessThan(0.1));
    expect((daryaOffset.dy - sergeyOffset.dy).abs(), lessThan(0.1));
    expect((andreyOffset.dy - nataliaOffset.dy).abs(), lessThan(0.1));
    expect((gennadyOffset.dy - lydiaOffset.dy).abs(), lessThan(0.1));
    expect((gennadyOffset.dy - anatolyOffset.dy).abs(), lessThan(0.1));
    expect((lydiaOffset.dy - valentinaOffset.dy).abs(), lessThan(0.1));
    expect((alexanderOffset.dy - mariaOffset.dy).abs(), lessThan(0.1));
    expect(alexanderOffset.dy, lessThan(gennadyOffset.dy));
    expect(mariaOffset.dy, lessThan(lydiaOffset.dy));
    expect(andreyOffset.dy, lessThan(artemOffset.dy));
    expect(nataliaOffset.dy, lessThan(daryaOffset.dy));
  });

  testWidgets('InteractiveFamilyTree keeps branch focus as secondary action',
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

    expect(find.text('Фокус'), findsNothing);
    expect(find.byTooltip('К ветке'), findsOneWidget);
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
    expect(
      tester.getTopLeft(find.text('Старшее поколение')).dx,
      greaterThan(20),
    );

    await tester.tap(find.byTooltip('Сбросить ветку'));
    await tester.pumpAndSettle();
    expect(clearCalls, 1);
  });

  testWidgets(
      'InteractiveFamilyTree shows warning badge and quick actions from graph snapshot',
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

    final snapshot = TreeGraphSnapshot(
      treeId: 'tree-1',
      viewerPersonId: 'person-1',
      people: [person],
      relations: const <FamilyRelation>[],
      familyUnits: const <TreeGraphFamilyUnit>[],
      viewerDescriptors: const <TreeGraphViewerDescriptor>[
        TreeGraphViewerDescriptor(
          personId: 'person-1',
          primaryRelationLabel: 'Это вы',
          isBlood: true,
          alternatePathCount: 0,
          pathSummary: 'Это вы',
          primaryPathPersonIds: ['person-1'],
        ),
      ],
      branchBlocks: const <TreeGraphBranchBlock>[],
      generationRows: const <TreeGraphGenerationRow>[
        TreeGraphGenerationRow(
          row: 0,
          label: 'Поколение 1',
          personIds: ['person-1'],
          familyUnitIds: <String>[],
        ),
      ],
      warnings: const <TreeGraphWarning>[
        TreeGraphWarning(
          id: 'warning-1',
          code: 'conflicting_direct_links',
          severity: 'warning',
          message: 'Нужна проверка связей.',
          hint: 'Откройте инструменты исправления.',
          personIds: ['person-1'],
          familyUnitIds: <String>[],
          relationIds: <String>[],
        ),
      ],
    );

    var fixCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InteractiveFamilyTree(
            peopleData: [
              {'person': person, 'userProfile': null},
            ],
            relations: const <FamilyRelation>[],
            graphSnapshot: snapshot,
            onPersonTap: (_) {},
            onAddRelativeTapWithType: (_, __) {},
            currentUserIsInTree: true,
            onAddSelfTapWithType: (_, __) async {},
            onShowRelationPath: (_) {},
            onFixPersonRelations: (_) => fixCalls += 1,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final badgeFinder =
        find.byKey(const ValueKey<String>('tree-warning-badge-person-1'));
    expect(badgeFinder, findsOneWidget);

    tester.widget<InkWell>(badgeFinder).onTap!.call();
    await tester.pumpAndSettle();

    expect(find.text('Предупреждения'), findsOneWidget);
    expect(find.text('Исправить связи'), findsWidgets);

    await tester.tap(find.text('Исправить связи').last);
    await tester.pumpAndSettle();

    expect(fixCalls, 1);
  });

  testWidgets(
      'InteractiveFamilyTree clamps stale manual vertical positions to generation rows',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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
            manualNodePositions: const <String, Offset>{
              'parent': Offset(260, 900),
            },
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
    final parentOffset = painter.nodePositions[parent.id]!;
    final childOffset = painter.nodePositions[child.id]!;

    expect(parentOffset.dy, lessThan(childOffset.dy));
    expect(childOffset.dy - parentOffset.dy, greaterThan(120));
  });

  testWidgets(
      'InteractiveFamilyTree keeps long-press drag inside generation row bounds',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Map<String, Offset>? reportedPositions;

    final left = FamilyPerson(
      id: 'left',
      treeId: 'tree-1',
      name: 'Левый',
      gender: Gender.male,
      isAlive: true,
      birthDate: DateTime(1971, 1, 1),
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );
    final right = FamilyPerson(
      id: 'right',
      treeId: 'tree-1',
      name: 'Правый',
      gender: Gender.female,
      isAlive: true,
      birthDate: DateTime(1974, 1, 1),
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );
    final child = FamilyPerson(
      id: 'child',
      treeId: 'tree-1',
      name: 'Ребёнок',
      gender: Gender.female,
      isAlive: true,
      birthDate: DateTime(2002, 1, 1),
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InteractiveFamilyTree(
            peopleData: [
              {'person': left, 'userProfile': null},
              {'person': right, 'userProfile': null},
              {'person': child, 'userProfile': null},
            ],
            relations: [
              FamilyRelation(
                id: 'union',
                treeId: 'tree-1',
                person1Id: left.id,
                person2Id: right.id,
                relation1to2: RelationType.spouse,
                relation2to1: RelationType.spouse,
                isConfirmed: true,
                createdAt: DateTime(2024, 1, 1),
              ),
              FamilyRelation(
                id: 'child-left',
                treeId: 'tree-1',
                person1Id: left.id,
                person2Id: child.id,
                relation1to2: RelationType.parent,
                relation2to1: RelationType.child,
                isConfirmed: true,
                createdAt: DateTime(2024, 1, 1),
              ),
              FamilyRelation(
                id: 'child-right',
                treeId: 'tree-1',
                person1Id: right.id,
                person2Id: child.id,
                relation1to2: RelationType.parent,
                relation2to1: RelationType.child,
                isConfirmed: true,
                createdAt: DateTime(2024, 1, 1),
              ),
            ],
            isEditMode: true,
            onPersonTap: (_) {},
            onAddRelativeTapWithType: (_, __) {},
            currentUserIsInTree: true,
            onAddSelfTapWithType: (_, __) async {},
            onNodePositionsChanged: (value) {
              reportedPositions = Map<String, Offset>.from(value);
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final paintBefore = tester.widget<CustomPaint>(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint && widget.painter is FamilyTreePainter,
      ),
    );
    final painterBefore = paintBefore.painter! as FamilyTreePainter;
    final leftBefore = painterBefore.nodePositions[left.id]!;
    final rightBefore = painterBefore.nodePositions[right.id]!;

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey<String>('tree-node-left'))),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 80));
    await gesture.moveBy(const Offset(320, 240));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final leftAfter = reportedPositions![left.id]!;
    expect(leftAfter.dy, closeTo(leftBefore.dy, 0.1));
    expect(leftAfter.dx, greaterThan(leftBefore.dx));
    expect(leftAfter.dx, lessThanOrEqualTo(rightBefore.dx + 0.1));
  });

  testWidgets(
      'InteractiveFamilyTree shows cohort subtitles on generation guides',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final zoomer = FamilyPerson(
      id: 'zoomer',
      treeId: 'tree-1',
      name: 'Зумер',
      gender: Gender.male,
      isAlive: true,
      birthDate: DateTime(2002, 1, 1),
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );
    final alpha = FamilyPerson(
      id: 'alpha',
      treeId: 'tree-1',
      name: 'Ребёнок',
      gender: Gender.female,
      isAlive: true,
      birthDate: DateTime(2024, 1, 1),
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InteractiveFamilyTree(
            peopleData: [
              {'person': zoomer, 'userProfile': null},
              {'person': alpha, 'userProfile': null},
            ],
            relations: [
              FamilyRelation(
                id: 'rel-1',
                treeId: 'tree-1',
                person1Id: zoomer.id,
                person2Id: alpha.id,
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
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Зумеры'), findsOneWidget);
    expect(find.text('Альфа'), findsOneWidget);
  });
}
