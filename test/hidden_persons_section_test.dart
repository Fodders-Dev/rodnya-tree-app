// Ship FE7 (2026-05-26): HiddenPersonsSection widget tests.
//
// Covers:
//   • Empty state copy when каркас loads + nothing hidden
//   • Populated state — rows render с resolved person names
//   • Person name fallback когда getPersonById throws (network glitch
//     либо deleted) → «Скрытый родственник»
//   • Unhide flow: tap «Показывать» → service.updateHideFilter →
//     row disappears + snackbar
//   • Inline error rendering when listHiddenPersonIds fails

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/family_tree_service_interface.dart';
import 'package:rodnya/backend/interfaces/semya_capable_family_tree_service.dart';
import 'package:rodnya/backend/models/deleted_person.dart';
import 'package:rodnya/backend/models/deleted_post.dart';
import 'package:rodnya/backend/models/semya.dart';
import 'package:rodnya/backend/models/semya_browse_token.dart';
import 'package:rodnya/backend/models/semya_invitation.dart';
import 'package:rodnya/backend/models/semya_pull_person_result.dart';
import 'package:rodnya/models/family_person.dart';
import 'package:rodnya/widgets/hidden_persons_section.dart';

class _FakeSemyaService implements SemyaCapableFamilyTreeService {
  _FakeSemyaService({
    this.hiddenIds = const <String>[],
    this.throwOnList,
    this.throwOnUpdate,
  });

  final List<String> hiddenIds;
  final SemyaError? throwOnList;
  final SemyaError? throwOnUpdate;

  int listCalls = 0;
  int updateCalls = 0;
  List<String>? lastAdd;
  List<String>? lastRemove;
  late List<String> _currentHidden;
  bool _initialized = false;

  void _ensureInit() {
    if (!_initialized) {
      _currentHidden = [...hiddenIds];
      _initialized = true;
    }
  }

  @override
  Future<List<Semya>> listMySemya() async => const <Semya>[];

  @override
  Future<SemyaDetails?> findSemyaById(String semyaId) async => null;

  @override
  Future<List<SemyaMembership>> listMembershipsForSemya(String semyaId) async =>
      const <SemyaMembership>[];

  @override
  Future<SemyaInvitation> createInvitation({
    required String semyaId,
    required SemyaRole role,
    String? recipientEmail,
    String? recipientPhone,
    String? recipientUserId,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<SemyaInvitation>> listInvitationsForSemya(String semyaId) async =>
      const <SemyaInvitation>[];

  @override
  Future<SemyaInvitation> revokeInvitation({
    required String semyaId,
    required String invitationId,
  }) async =>
      throw UnimplementedError();

  @override
  Future<SemyaInvitationAcceptResult> acceptInvitation(String token) async =>
      throw UnimplementedError();

  @override
  Future<SemyaPullPersonResult> pullPersonToSemya({
    required String targetSemyaId,
    required String sourceSemyaId,
    required String sourcePersonId,
  }) async =>
      throw UnimplementedError();

  @override
  Future<SemyaBrowseToken> createBrowseToken({
    required String semyaId,
    int? expiresInDays,
  }) async =>
      throw UnimplementedError();

  @override
  Future<BrowsedSemyaTree> fetchBrowseTree(String token) async =>
      throw UnimplementedError();

  @override
  Future<List<SemyaBrowseTokenSummary>> listBrowseTokens({
    required String semyaId,
  }) async =>
      const <SemyaBrowseTokenSummary>[];

  @override
  Future<SemyaBrowseTokenSummary> revokeBrowseToken({
    required String semyaId,
    required String tokenId,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<String>> listHiddenPersonIds({required String semyaId}) async {
    _ensureInit();
    listCalls += 1;
    if (throwOnList != null) throw throwOnList!;
    return _currentHidden;
  }

  @override
  Future<List<String>> updateHideFilter({
    required String semyaId,
    List<String> addPersonIds = const <String>[],
    List<String> removePersonIds = const <String>[],
  }) async {
    _ensureInit();
    updateCalls += 1;
    lastAdd = addPersonIds;
    lastRemove = removePersonIds;
    if (throwOnUpdate != null) throw throwOnUpdate!;
    for (final id in removePersonIds) {
      _currentHidden.remove(id);
    }
    for (final id in addPersonIds) {
      if (!_currentHidden.contains(id)) _currentHidden.add(id);
    }
    return [..._currentHidden];
  }

  @override
  Future<SemyaMembership> updateMembership({
    required String semyaId,
    required String userId,
    SemyaRole? role,
    bool? hasInviteGrant,
  }) async =>
      throw UnimplementedError();

  @override
  Future<SemyaMembership> addMembership({
    required String semyaId,
    required String userId,
    required SemyaRole role,
    bool hasInviteGrant = false,
  }) async =>
      throw UnimplementedError();

  @override
  Future<SemyaMembershipRemoveResult> removeMembership({
    required String semyaId,
    required String userId,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<SemyaInvitation>> listPendingInvitations() async =>
      const <SemyaInvitation>[];

  // Ship Q4a frontend (Ship 31): trash endpoint stubs.

  @override
  Future<List<DeletedPerson>> listMyDeletedPersons() async =>
      const <DeletedPerson>[];

  @override
  Future<List<DeletedPerson>> listDeletedPersonsForSemya(String semyaId) async =>
      const <DeletedPerson>[];

  @override
  Future<void> restoreDeletedPerson(String deletedPersonId) async =>
      throw UnimplementedError();

  @override
  Future<void> permanentlyDeletePerson(String deletedPersonId) async =>
      throw UnimplementedError();

  @override
  Future<List<DeletedPost>> listMyDeletedPosts() async =>
      const <DeletedPost>[];

  @override
  Future<void> restoreDeletedPost(String deletedPostId) async =>
      throw UnimplementedError();

  @override
  Future<void> permanentlyDeletePost(String deletedPostId) async =>
      throw UnimplementedError();
}

class _FakeFamilyService implements FamilyTreeServiceInterface {
  _FakeFamilyService({this.persons = const {}, this.throwOnFetch = const {}});

  final Map<String, FamilyPerson> persons;
  final Set<String> throwOnFetch;

  @override
  Future<FamilyPerson> getPersonById(String treeId, String personId) async {
    if (throwOnFetch.contains(personId)) {
      throw Exception('fake fetch error');
    }
    final p = persons[personId];
    if (p == null) throw Exception('not found');
    return p;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

FamilyPerson _person(String id, String name) {
  return FamilyPerson(
    id: id,
    treeId: 't-1',
    name: name,
    gender: Gender.unknown,
    isAlive: true,
    createdAt: DateTime(2024, 1, 1),
    updatedAt: DateTime(2024, 1, 1),
  );
}

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  testWidgets('empty state copy when nothing hidden', (tester) async {
    final semyaSvc = _FakeSemyaService(hiddenIds: const <String>[]);
    final familySvc = _FakeFamilyService();
    await tester.pumpWidget(_wrap(
      HiddenPersonsSection(
        semyaId: 's-1',
        treeId: 't-1',
        serviceOverride: semyaSvc,
        familyServiceOverride: familySvc,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Скрытые от меня'), findsOneWidget);
    expect(find.byKey(const Key('hidden-persons-empty')), findsOneWidget);
    expect(semyaSvc.listCalls, 1);
  });

  testWidgets('populated state renders rows с resolved names',
      (tester) async {
    final semyaSvc = _FakeSemyaService(hiddenIds: ['p-1', 'p-2']);
    final familySvc = _FakeFamilyService(
      persons: {
        'p-1': _person('p-1', 'Иван Иванов'),
        'p-2': _person('p-2', 'Мария Петрова'),
      },
    );
    await tester.pumpWidget(_wrap(
      HiddenPersonsSection(
        semyaId: 's-1',
        treeId: 't-1',
        serviceOverride: semyaSvc,
        familyServiceOverride: familySvc,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hidden-person-row-p-1')), findsOneWidget);
    expect(find.byKey(const Key('hidden-person-row-p-2')), findsOneWidget);
    expect(find.text('Иван Иванов'), findsOneWidget);
    expect(find.text('Мария Петрова'), findsOneWidget);
  });

  testWidgets('name fallback когда getPersonById throws', (tester) async {
    final semyaSvc = _FakeSemyaService(hiddenIds: ['p-1']);
    final familySvc = _FakeFamilyService(
      persons: const {},
      throwOnFetch: {'p-1'},
    );
    await tester.pumpWidget(_wrap(
      HiddenPersonsSection(
        semyaId: 's-1',
        treeId: 't-1',
        serviceOverride: semyaSvc,
        familyServiceOverride: familySvc,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Скрытый родственник'), findsOneWidget);
    expect(find.byKey(const Key('hidden-person-row-p-1')), findsOneWidget);
  });

  testWidgets('unhide flow: tap → service call → row removed + snackbar',
      (tester) async {
    final semyaSvc = _FakeSemyaService(hiddenIds: ['p-1', 'p-2']);
    final familySvc = _FakeFamilyService(
      persons: {
        'p-1': _person('p-1', 'A'),
        'p-2': _person('p-2', 'B'),
      },
    );
    await tester.pumpWidget(_wrap(
      HiddenPersonsSection(
        semyaId: 's-1',
        treeId: 't-1',
        serviceOverride: semyaSvc,
        familyServiceOverride: familySvc,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('hidden-person-unhide-p-1')));
    await tester.pumpAndSettle();
    expect(semyaSvc.updateCalls, 1);
    expect(semyaSvc.lastRemove, ['p-1']);
    expect(find.byKey(const Key('hidden-person-row-p-1')), findsNothing);
    expect(find.byKey(const Key('hidden-person-row-p-2')), findsOneWidget);
    expect(find.text('Снова видно'), findsOneWidget);
  });

  testWidgets('unhide failure → snackbar error, row preserved',
      (tester) async {
    final semyaSvc = _FakeSemyaService(
      hiddenIds: ['p-1'],
      throwOnUpdate: const SemyaError(
        code: 'FORBIDDEN',
        message: 'Нет доступа',
      ),
    );
    final familySvc = _FakeFamilyService(
      persons: {'p-1': _person('p-1', 'A')},
    );
    await tester.pumpWidget(_wrap(
      HiddenPersonsSection(
        semyaId: 's-1',
        treeId: 't-1',
        serviceOverride: semyaSvc,
        familyServiceOverride: familySvc,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('hidden-person-unhide-p-1')));
    await tester.pumpAndSettle();
    expect(semyaSvc.updateCalls, 1);
    expect(find.text('Нет доступа'), findsOneWidget);
    expect(find.byKey(const Key('hidden-person-row-p-1')), findsOneWidget);
  });

  testWidgets('inline error rendering on list failure', (tester) async {
    final semyaSvc = _FakeSemyaService(
      throwOnList: const SemyaError(
        code: 'FORBIDDEN',
        message: 'Нет прав',
      ),
    );
    final familySvc = _FakeFamilyService();
    await tester.pumpWidget(_wrap(
      HiddenPersonsSection(
        semyaId: 's-1',
        treeId: 't-1',
        serviceOverride: semyaSvc,
        familyServiceOverride: familySvc,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('hidden-persons-error')), findsOneWidget);
    expect(find.text('Нет прав'), findsOneWidget);
    expect(find.byKey(const Key('hidden-persons-retry')), findsOneWidget);
  });
}
