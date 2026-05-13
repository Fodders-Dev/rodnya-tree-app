import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/blood_relation_capable_family_tree_service.dart';
import 'package:rodnya/backend/models/blood_relation.dart';
import 'package:rodnya/backend/models/extended_network_slice.dart';
import 'package:rodnya/models/family_person.dart';
import 'package:rodnya/widgets/foreign_node_sheet.dart';

class _FakeBloodService implements BloodRelationCapableFamilyTreeService {
  _FakeBloodService({this.result});

  BloodRelation? result;
  bool throwOnCall = false;
  String? lastFrom;
  String? lastTo;

  @override
  Future<BloodRelation> findBloodRelation({
    required String fromGraphPersonId,
    required String toGraphPersonId,
    int maxDepth = 10,
  }) async {
    lastFrom = fromGraphPersonId;
    lastTo = toGraphPersonId;
    if (throwOnCall) throw StateError('boom');
    return result ?? BloodRelation.empty;
  }
}

FamilyPerson _person({
  String id = 'p-foreign',
  String name = 'Иван Петров',
  String? identityId,
}) {
  return FamilyPerson(
    id: id,
    treeId: 'tree-1',
    name: name,
    identityId: identityId ?? id,
    gender: Gender.male,
    isAlive: true,
    createdAt: DateTime(2024, 1, 1),
    updatedAt: DateTime(2024, 1, 1),
  );
}

ExtendedNetworkSlice _sliceWithForeignOwner({
  required String foreignGraphPersonId,
  required String? ownerUserId,
  required String? ownerDisplayName,
  String? viewerSelfGraphPersonId,
}) {
  return ExtendedNetworkSlice(
    graphPersons: <ExtendedNetworkPerson>[
      ExtendedNetworkPerson(
        id: foreignGraphPersonId,
        name: 'Иван Петров',
        gender: 'male',
        birthDate: null,
        deathDate: null,
        photoUrl: null,
        isAlive: true,
        hopDistance: 2,
      ),
    ],
    graphRelations: const <ExtendedNetworkRelation>[],
    branchMembership: const <String, List<String>>{},
    ownerMap: <String, ExtendedNetworkOwnerInfo>{
      foreignGraphPersonId: ExtendedNetworkOwnerInfo(
        userId: ownerUserId,
        displayName: ownerDisplayName,
        photoUrl: null,
      ),
    },
    viewerSelfGraphPersonId: viewerSelfGraphPersonId,
    stats: const ExtendedNetworkStats(
      totalCount: 1,
      myCount: 0,
      extendedCount: 1,
      anonymousCount: 0,
      maxHopsReached: false,
      capReached: false,
    ),
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  testWidgets('ForeignNodeSheet: render header + owner + actions',
      (tester) async {
    final service = _FakeBloodService(result: const BloodRelation(
      found: true,
      chain: [],
      edges: [],
      label: 'двоюродная сестра',
      degree: 4,
    ));
    final person = _person();
    final slice = _sliceWithForeignOwner(
      foreignGraphPersonId: 'p-foreign',
      ownerUserId: 'user-stepan',
      ownerDisplayName: 'Степан Мочаров',
      viewerSelfGraphPersonId: 'me-self',
    );
    await tester.pumpWidget(
      _wrap(
        ForeignNodeSheet(
          person: person,
          slice: slice,
          bloodRelationService: service,
          onOpenCard: () {},
          onWriteToOwner: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Person header
    expect(find.text('Иван Петров'), findsOneWidget);
    // Owner block
    expect(find.text('Кто это добавил'), findsOneWidget);
    expect(find.text('Степан Мочаров'), findsOneWidget);
    // Relation row resolved
    expect(find.text('двоюродная сестра'), findsOneWidget);
    expect(find.textContaining('через 4'), findsOneWidget);
    // Actions
    expect(find.text('Открыть карточку'), findsOneWidget);
    expect(find.text('Написать Степан Мочаров'), findsOneWidget);
  });

  testWidgets(
      'ForeignNodeSheet: anonymous owner (userId=null) → italic note + chat disabled',
      (tester) async {
    final service = _FakeBloodService();
    final slice = _sliceWithForeignOwner(
      foreignGraphPersonId: 'p-foreign',
      ownerUserId: null,
      ownerDisplayName: null,
      viewerSelfGraphPersonId: 'me-self',
    );
    await tester.pumpWidget(
      _wrap(
        ForeignNodeSheet(
          person: _person(),
          slice: slice,
          bloodRelationService: service,
          onOpenCard: () {},
          onWriteToOwner: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Карточка без аккаунта'),
      findsOneWidget,
    );
    expect(find.text('Чат недоступен'), findsOneWidget);
  });

  testWidgets(
      'ForeignNodeSheet: relation FutureBuilder loading → spinner; resolved → label',
      (tester) async {
    final service = _FakeBloodService(result: const BloodRelation(
      found: true,
      chain: [],
      edges: [],
      label: 'троюродный брат',
      degree: 6,
    ));
    final slice = _sliceWithForeignOwner(
      foreignGraphPersonId: 'p-foreign',
      ownerUserId: 'u-x',
      ownerDisplayName: 'X',
      viewerSelfGraphPersonId: 'me-self',
    );
    await tester.pumpWidget(
      _wrap(
        ForeignNodeSheet(
          person: _person(),
          slice: slice,
          bloodRelationService: service,
          onOpenCard: () {},
          onWriteToOwner: (_) {},
        ),
      ),
    );
    // Initial pump — FutureBuilder показывает spinner.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('троюродный брат'), findsOneWidget);
    expect(service.lastFrom, 'me-self');
    expect(service.lastTo, 'p-foreign');
  });

  testWidgets(
      'ForeignNodeSheet: relation not found → "Связь не найдена" muted',
      (tester) async {
    final service = _FakeBloodService(result: BloodRelation.empty);
    final slice = _sliceWithForeignOwner(
      foreignGraphPersonId: 'p-foreign',
      ownerUserId: 'u-x',
      ownerDisplayName: 'X',
      viewerSelfGraphPersonId: 'me-self',
    );
    await tester.pumpWidget(
      _wrap(
        ForeignNodeSheet(
          person: _person(),
          slice: slice,
          bloodRelationService: service,
          onOpenCard: () {},
          onWriteToOwner: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Связь не найдена в видимом графе'), findsOneWidget);
  });

  testWidgets(
      'ForeignNodeSheet: viewerSelfGraphPersonId null → не fetch relation, '
      'shows fallback', (tester) async {
    final service = _FakeBloodService();
    final slice = _sliceWithForeignOwner(
      foreignGraphPersonId: 'p-foreign',
      ownerUserId: 'u-x',
      ownerDisplayName: 'X',
      viewerSelfGraphPersonId: null,
    );
    await tester.pumpWidget(
      _wrap(
        ForeignNodeSheet(
          person: _person(),
          slice: slice,
          bloodRelationService: service,
          onOpenCard: () {},
          onWriteToOwner: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Связь не найдена в видимом графе'), findsOneWidget);
    // Service не должен быть called когда self null.
    expect(service.lastFrom, isNull);
  });

  testWidgets('ForeignNodeSheet: relation throw → error fallback',
      (tester) async {
    final service = _FakeBloodService()..throwOnCall = true;
    final slice = _sliceWithForeignOwner(
      foreignGraphPersonId: 'p-foreign',
      ownerUserId: 'u-x',
      ownerDisplayName: 'X',
      viewerSelfGraphPersonId: 'me-self',
    );
    await tester.pumpWidget(
      _wrap(
        ForeignNodeSheet(
          person: _person(),
          slice: slice,
          bloodRelationService: service,
          onOpenCard: () {},
          onWriteToOwner: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Не удалось вычислить связь'), findsOneWidget);
  });

  testWidgets(
      'ForeignNodeSheet: tap «Открыть карточку» → onOpenCard called',
      (tester) async {
    var openCalled = false;
    final service = _FakeBloodService();
    final slice = _sliceWithForeignOwner(
      foreignGraphPersonId: 'p-foreign',
      ownerUserId: 'u-x',
      ownerDisplayName: 'X',
      viewerSelfGraphPersonId: 'me-self',
    );
    await tester.pumpWidget(
      _wrap(
        ForeignNodeSheet(
          person: _person(),
          slice: slice,
          bloodRelationService: service,
          onOpenCard: () => openCalled = true,
          onWriteToOwner: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть карточку'));
    await tester.pumpAndSettle();
    expect(openCalled, isTrue);
  });

  testWidgets(
      'ForeignNodeSheet: tap «Написать» → onWriteToOwner(ownerUserId)',
      (tester) async {
    String? capturedUserId;
    final service = _FakeBloodService();
    final slice = _sliceWithForeignOwner(
      foreignGraphPersonId: 'p-foreign',
      ownerUserId: 'u-stepan',
      ownerDisplayName: 'Степан',
      viewerSelfGraphPersonId: 'me-self',
    );
    await tester.pumpWidget(
      _wrap(
        ForeignNodeSheet(
          person: _person(),
          slice: slice,
          bloodRelationService: service,
          onOpenCard: () {},
          onWriteToOwner: (uid) => capturedUserId = uid,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Написать Степан'));
    await tester.pumpAndSettle();
    expect(capturedUserId, 'u-stepan');
  });
}
