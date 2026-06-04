import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/semya_capable_family_tree_service.dart';
import 'package:rodnya/backend/models/deleted_person.dart';
import 'package:rodnya/backend/models/deleted_post.dart';
import 'package:rodnya/backend/models/semya.dart';
import 'package:rodnya/backend/models/semya_browse_token.dart';
import 'package:rodnya/backend/models/semya_invitation.dart';
import 'package:rodnya/backend/models/semya_pull_person_result.dart';
import 'package:rodnya/providers/semya_list_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  test('SemyaListController loads семя через injected service', () async {
    final service = _FakeSemyaService(semyi: [
      _semya(id: 's1', name: 'Семья A'),
      _semya(id: 's2', name: 'Семья B'),
    ]);
    final controller = SemyaListController(service: service);
    expect(controller.hasLoaded, isFalse);
    expect(controller.semyi, isEmpty);

    await controller.loadInitial();

    expect(controller.hasLoaded, isTrue);
    expect(controller.semyi.length, 2);
    expect(controller.semyi[0].id, 's1');
    expect(controller.errorMessage, isNull);
  });

  test('SemyaListController auto-selects single семя', () async {
    final service = _FakeSemyaService(semyi: [_semya(id: 's-only')]);
    final controller = SemyaListController(service: service);
    await controller.loadInitial();
    expect(controller.selectedSemyaId, 's-only');
  });

  test(
    'SemyaListController NO auto-select когда multiple семья',
    () async {
      final service = _FakeSemyaService(semyi: [
        _semya(id: 's1', name: 'A'),
        _semya(id: 's2', name: 'B'),
      ]);
      final controller = SemyaListController(service: service);
      await controller.loadInitial();
      expect(controller.selectedSemyaId, isNull);
    },
  );

  test('SemyaListController restores persisted selection', () async {
    SharedPreferences.setMockInitialValues({
      'phase_b_selected_semya_id': 's2',
    });
    final service = _FakeSemyaService(semyi: [
      _semya(id: 's1'),
      _semya(id: 's2', name: 'Восстановленная'),
    ]);
    final controller = SemyaListController(service: service);
    await controller.loadInitial();
    expect(controller.selectedSemyaId, 's2');
    expect(controller.selectedSemya?.name, 'Восстановленная');
  });

  test(
    'SemyaListController clears stale persisted selection после refresh',
    () async {
      SharedPreferences.setMockInitialValues({
        'phase_b_selected_semya_id': 's-deleted',
      });
      final service = _FakeSemyaService(semyi: [_semya(id: 's-active')]);
      final controller = SemyaListController(service: service);
      await controller.loadInitial();
      // Stale id cleared, auto-select fires (single new entry)
      expect(controller.selectedSemyaId, 's-active');
    },
  );

  test('SemyaListController selectSemya persists choice', () async {
    final service = _FakeSemyaService(semyi: [
      _semya(id: 's1'),
      _semya(id: 's2'),
    ]);
    final controller = SemyaListController(service: service);
    await controller.loadInitial();

    await controller.selectSemya('s2');
    expect(controller.selectedSemyaId, 's2');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('phase_b_selected_semya_id'), 's2');
  });

  test(
    'SemyaListController selectSemya rejects unknown id silently',
    () async {
      final service = _FakeSemyaService(semyi: [_semya(id: 's1')]);
      final controller = SemyaListController(service: service);
      await controller.loadInitial();
      await controller.selectSemya('unknown');
      expect(controller.selectedSemyaId, 's1', reason: 'auto-selection preserved');
    },
  );

  test('SemyaListController clearSelection wipes choice + prefs', () async {
    final service = _FakeSemyaService(semyi: [_semya(id: 's1')]);
    final controller = SemyaListController(service: service);
    await controller.loadInitial();
    expect(controller.selectedSemyaId, 's1');

    await controller.clearSelection();
    expect(controller.selectedSemyaId, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('phase_b_selected_semya_id'), isNull);
  });

  test(
    'SemyaListController isCapable=false when no service injected/registered',
    () async {
      // Default GetIt не has FamilyTreeServiceInterface in test env.
      final controller = SemyaListController();
      expect(controller.isCapable, isFalse);
      await controller.loadInitial();
      expect(controller.hasLoaded, isTrue);
      expect(controller.semyi, isEmpty);
    },
  );

  test('SemyaListController surfaces SemyaError message', () async {
    final service = _FakeSemyaService(
      semyi: const [],
      throwOnList: const SemyaError(
        code: 'UNKNOWN',
        message: 'Боком сервер',
      ),
    );
    final controller = SemyaListController(service: service);
    await controller.loadInitial();
    expect(controller.errorMessage, 'Боком сервер');
    expect(controller.semyi, isEmpty);
  });

  test(
    'SemyaListController fires notifyListeners на loaded + selection changes',
    () async {
      final service = _FakeSemyaService(semyi: [
        _semya(id: 's1'),
        _semya(id: 's2'),
      ]);
      final controller = SemyaListController(service: service);
      var notifyCount = 0;
      controller.addListener(() => notifyCount++);

      await controller.loadInitial();
      expect(notifyCount, greaterThanOrEqualTo(1));

      final before = notifyCount;
      await controller.selectSemya('s2');
      expect(notifyCount, greaterThan(before));
    },
  );
}

Semya _semya({
  required String id,
  String name = 'Тестовая семья',
  String ownerId = 'user-1',
  String treeId = 'tree-1',
}) {
  return Semya(
    id: id,
    name: name,
    ownerId: ownerId,
    treeId: treeId,
    createdAt: '2026-05-22T00:00:00.000Z',
    updatedAt: '2026-05-22T00:00:00.000Z',
  );
}

class _FakeSemyaService implements SemyaCapableFamilyTreeService {
  _FakeSemyaService({required this.semyi, this.throwOnList});

  final List<Semya> semyi;
  final SemyaError? throwOnList;
  int listCalls = 0;

  @override
  Future<List<Semya>> listMySemya() async {
    listCalls += 1;
    if (throwOnList != null) {
      throw throwOnList!;
    }
    return semyi;
  }

  @override
  Future<SemyaDetails?> findSemyaById(String semyaId) async => null;

  @override
  Future<List<SemyaMembership>> listMembershipsForSemya(
    String semyaId,
  ) async =>
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
  Future<List<SemyaInvitation>> listInvitationsForSemya(
    String semyaId,
  ) async =>
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
      throw UnimplementedError();

  @override
  Future<SemyaBrowseTokenSummary> revokeBrowseToken({
    required String semyaId,
    required String tokenId,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<String>> listHiddenPersonIds({required String semyaId}) async =>
      const <String>[];

  @override
  Future<List<String>> updateHideFilter({
    required String semyaId,
    List<String> addPersonIds = const <String>[],
    List<String> removePersonIds = const <String>[],
  }) async =>
      throw UnimplementedError();

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
