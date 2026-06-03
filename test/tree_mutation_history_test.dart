// Phase B polish B: the «Отменить» toast calls TreeMutationHistory
// .undoForUi(), which inverts the most-recent mutation through the same
// service (recordPersonAdded → deleteRelative; recordRelationCreated →
// disconnectRelation). These lock that inverse behaviour.

import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/family_tree_service_interface.dart';
import 'package:rodnya/models/family_relation.dart';
import 'package:rodnya/services/tree_mutation_history.dart';

class _FakeService implements FamilyTreeServiceInterface {
  final List<Symbol> calls = <Symbol>[];
  final Map<Symbol, Invocation> invocations = <Symbol, Invocation>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName);
    invocations[invocation.memberName] = invocation;
    return Future<dynamic>.value(); // Future-returning methods → await ok
  }
}

FamilyRelation _relation(String id) => FamilyRelation(
      id: id,
      treeId: 't1',
      person1Id: 'a',
      person2Id: 'b',
      relation1to2: RelationType.parent,
      relation2to1: RelationType.child,
      isConfirmed: true,
      createdAt: DateTime(2024, 1, 1),
    );

void main() {
  test('recordPersonAdded → undoForUi deletes that person', () async {
    final history = TreeMutationHistory();
    final svc = _FakeService();
    history.recordPersonAdded(
      treeId: 't1',
      personId: 'p1',
      personData: const {'name': 'X'},
    );
    expect(history.canUndo, isTrue);

    final desc = await history.undoForUi(svc);

    expect(desc, isNotNull); // success → toast «Отменено: …»
    expect(svc.calls, contains(#deleteRelative));
    expect(svc.invocations[#deleteRelative]!.positionalArguments[1], 'p1');
  });

  test('recordRelationCreated → undoForUi disconnects that relation',
      () async {
    final history = TreeMutationHistory();
    final svc = _FakeService();
    history.recordRelationCreated(treeId: 't1', created: _relation('r1'));

    final desc = await history.undoForUi(svc);

    expect(desc, isNotNull);
    expect(svc.calls, contains(#disconnectRelation));
    expect(
      svc.invocations[#disconnectRelation]!.namedArguments[#relationId],
      'r1',
    );
  });

  test('empty history → undoForUi is a null no-op', () async {
    final history = TreeMutationHistory();
    final svc = _FakeService();
    expect(history.canUndo, isFalse);
    expect(await history.undoForUi(svc), isNull);
    expect(svc.calls, isEmpty);
  });
}
