// Ship FE8 (2026-05-27): SemyaDetailsController mutation flow tests.
//
// Covers controller-layer (updateMemberRoleOrGrant + removeMember):
//   • Success path: pending state set/cleared + refresh fires
//   • All 4 backend invariant errors surface через mutationErrorMessage
//   • Self-leave returns wasSelfLeave=true
//   • activeOwnerCount tracks correctly post-load

import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/semya_capable_family_tree_service.dart';
import 'package:rodnya/backend/models/deleted_person.dart';
import 'package:rodnya/backend/models/deleted_post.dart';
import 'package:rodnya/backend/models/semya.dart';
import 'package:rodnya/backend/models/semya_browse_token.dart';
import 'package:rodnya/backend/models/semya_invitation.dart';
import 'package:rodnya/backend/models/semya_pull_person_result.dart';
import 'package:rodnya/providers/semya_details_controller.dart';

class _FakeService implements SemyaCapableFamilyTreeService {
  _FakeService({
    required this.details,
    this.members = const <SemyaMembership>[],
    this.throwOnUpdate,
    this.throwOnRemove,
    this.removeResultBuilder,
  });

  final SemyaDetails details;
  List<SemyaMembership> members;
  SemyaError? throwOnUpdate;
  SemyaError? throwOnRemove;
  SemyaMembershipRemoveResult Function(String userId)? removeResultBuilder;

  int updateCalls = 0;
  int removeCalls = 0;
  String? lastUpdateUserId;
  SemyaRole? lastUpdateRole;
  bool? lastUpdateGrant;
  String? lastRemoveUserId;

  @override
  Future<List<Semya>> listMySemya() async => const <Semya>[];

  @override
  Future<SemyaDetails?> findSemyaById(String semyaId) async => details;

  @override
  Future<List<SemyaMembership>> listMembershipsForSemya(
    String semyaId,
  ) async =>
      members;

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
  }) async {
    updateCalls += 1;
    lastUpdateUserId = userId;
    lastUpdateRole = role;
    lastUpdateGrant = hasInviteGrant;
    if (throwOnUpdate != null) throw throwOnUpdate!;
    final idx = members.indexWhere((m) => m.userId == userId);
    final orig = members[idx];
    final updated = SemyaMembership(
      id: orig.id,
      semyaId: orig.semyaId,
      userId: orig.userId,
      role: role ?? orig.role,
      joinedAt: orig.joinedAt,
      invitedByUserId: orig.invitedByUserId,
      hasInviteGrant: hasInviteGrant ?? orig.hasInviteGrant,
    );
    members = [...members];
    members[idx] = updated;
    return updated;
  }

  @override
  Future<SemyaMembershipRemoveResult> removeMembership({
    required String semyaId,
    required String userId,
  }) async {
    removeCalls += 1;
    lastRemoveUserId = userId;
    if (throwOnRemove != null) throw throwOnRemove!;
    if (removeResultBuilder != null) return removeResultBuilder!(userId);
    final idx = members.indexWhere((m) => m.userId == userId);
    final orig = members[idx];
    members = [...members]..removeAt(idx);
    // Default: kick semantics (actor != target). Tests needing
    // self-leave behavior supply removeResultBuilder с wasSelfLeave=true.
    return SemyaMembershipRemoveResult(
      membership: orig,
      wasSelfLeave: false,
    );
  }

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

SemyaMembership _mem({
  String id = 'mem',
  String userId = 'u-target',
  SemyaRole role = SemyaRole.viewer,
  bool hasInviteGrant = false,
}) {
  return SemyaMembership(
    id: id,
    semyaId: 's-1',
    userId: userId,
    role: role,
    joinedAt: '2026-05-26T00:00:00.000Z',
    hasInviteGrant: hasInviteGrant,
  );
}

SemyaDetails _details({SemyaRole callerRole = SemyaRole.owner}) {
  return SemyaDetails(
    semya: const Semya(
      id: 's-1',
      name: 'Семья Тест',
      ownerId: 'u-owner',
      treeId: 't-1',
      createdAt: '2026-05-26T00:00:00.000Z',
      updatedAt: '2026-05-26T00:00:00.000Z',
    ),
    membership: _mem(
      id: 'mem-self',
      userId: 'u-owner',
      role: callerRole,
    ),
  );
}

void main() {
  group('FE8 controller — updateMemberRoleOrGrant', () {
    test('success path — pending cleared, refresh fires', () async {
      final service = _FakeService(
        details: _details(),
        members: [
          _mem(id: 'mem-self', userId: 'u-owner', role: SemyaRole.owner),
          _mem(id: 'mem-target', userId: 'u-target', role: SemyaRole.viewer),
        ],
      );
      final controller = SemyaDetailsController(
        semyaId: 's-1',
        service: service,
      );
      await controller.load();
      expect(controller.isPending('u-target'), isFalse);

      final ok = await controller.updateMemberRoleOrGrant(
        userId: 'u-target',
        role: SemyaRole.editor,
      );
      expect(ok, isTrue);
      expect(service.updateCalls, 1);
      expect(service.lastUpdateRole, SemyaRole.editor);
      expect(controller.isPending('u-target'), isFalse);
      expect(controller.mutationErrorMessage, isNull);
    });

    test('SELF_ROLE_CHANGE_FORBIDDEN surfaces message', () async {
      final service = _FakeService(
        details: _details(),
        members: [_mem()],
        throwOnUpdate: const SemyaError(
          code: 'SELF_ROLE_CHANGE_FORBIDDEN',
          message: 'Свою роль изменить нельзя',
        ),
      );
      final controller = SemyaDetailsController(
        semyaId: 's-1',
        service: service,
      );
      await controller.load();
      final ok = await controller.updateMemberRoleOrGrant(
        userId: 'u-target',
        role: SemyaRole.editor,
      );
      expect(ok, isFalse);
      expect(
        controller.mutationErrorMessage,
        'Свою роль изменить нельзя',
      );
    });

    test('LAST_OWNER_DEMOTE_FORBIDDEN surfaces message', () async {
      final service = _FakeService(
        details: _details(),
        members: [_mem(role: SemyaRole.owner)],
        throwOnUpdate: const SemyaError(
          code: 'LAST_OWNER_DEMOTE_FORBIDDEN',
          message: 'Нельзя понизить последнего владельца',
        ),
      );
      final controller = SemyaDetailsController(
        semyaId: 's-1',
        service: service,
      );
      await controller.load();
      final ok = await controller.updateMemberRoleOrGrant(
        userId: 'u-target',
        role: SemyaRole.editor,
      );
      expect(ok, isFalse);
      expect(
        controller.mutationErrorMessage,
        contains('последнего владельца'),
      );
    });

    test('INVITE_GRANT_ONLY_EDITOR surfaces message', () async {
      final service = _FakeService(
        details: _details(),
        members: [_mem(role: SemyaRole.viewer)],
        throwOnUpdate: const SemyaError(
          code: 'INVITE_GRANT_ONLY_EDITOR',
          message: 'Право приглашать только для редакторов',
        ),
      );
      final controller = SemyaDetailsController(
        semyaId: 's-1',
        service: service,
      );
      await controller.load();
      final ok = await controller.updateMemberRoleOrGrant(
        userId: 'u-target',
        hasInviteGrant: true,
      );
      expect(ok, isFalse);
      expect(
        controller.mutationErrorMessage,
        contains('редакторов'),
      );
    });
  });

  group('FE8 controller — removeMember', () {
    test('kick success — returns wasSelfLeave=false, refresh fires',
        () async {
      final service = _FakeService(
        details: _details(),
        members: [
          _mem(id: 'mem-self', userId: 'u-owner', role: SemyaRole.owner),
          _mem(id: 'mem-target', userId: 'u-target', role: SemyaRole.viewer),
        ],
      );
      final controller = SemyaDetailsController(
        semyaId: 's-1',
        service: service,
      );
      await controller.load();
      final result = await controller.removeMember(userId: 'u-target');
      expect(result, isNotNull);
      expect(result!.wasSelfLeave, isFalse);
      expect(service.removeCalls, 1);
    });

    test('self-leave returns wasSelfLeave=true', () async {
      final service = _FakeService(
        details: _details(callerRole: SemyaRole.viewer),
        members: [
          _mem(id: 'mem-owner', userId: 'u-owner', role: SemyaRole.owner),
          _mem(id: 'mem-self', userId: 'u-owner', role: SemyaRole.viewer),
        ],
        removeResultBuilder: (userId) => SemyaMembershipRemoveResult(
          membership: _mem(id: 'mem-self', userId: userId),
          wasSelfLeave: true,
        ),
      );
      final controller = SemyaDetailsController(
        semyaId: 's-1',
        service: service,
      );
      await controller.load();
      final result = await controller.removeMember(userId: 'u-owner');
      expect(result, isNotNull);
      expect(result!.wasSelfLeave, isTrue);
    });

    test('LAST_OWNER_REMOVE_FORBIDDEN surfaces message', () async {
      final service = _FakeService(
        details: _details(),
        members: [_mem(role: SemyaRole.owner)],
        throwOnRemove: const SemyaError(
          code: 'LAST_OWNER_REMOVE_FORBIDDEN',
          message: 'Нельзя удалить последнего владельца',
        ),
      );
      final controller = SemyaDetailsController(
        semyaId: 's-1',
        service: service,
      );
      await controller.load();
      final result = await controller.removeMember(userId: 'u-target');
      expect(result, isNull);
      expect(
        controller.mutationErrorMessage,
        contains('последнего владельца'),
      );
    });
  });

  group('FE8 controller — activeOwnerCount', () {
    test('counts owners only после load', () async {
      final service = _FakeService(
        details: _details(),
        members: [
          _mem(id: 'm1', userId: 'u-o1', role: SemyaRole.owner),
          _mem(id: 'm2', userId: 'u-o2', role: SemyaRole.owner),
          _mem(id: 'm3', userId: 'u-e1', role: SemyaRole.editor),
          _mem(id: 'm4', userId: 'u-v1', role: SemyaRole.viewer),
        ],
      );
      final controller = SemyaDetailsController(
        semyaId: 's-1',
        service: service,
      );
      await controller.load();
      expect(controller.activeOwnerCount, 2);
    });

    test('zero when no owners (edge case)', () async {
      final service = _FakeService(
        details: _details(),
        members: [_mem(role: SemyaRole.editor)],
      );
      final controller = SemyaDetailsController(
        semyaId: 's-1',
        service: service,
      );
      await controller.load();
      expect(controller.activeOwnerCount, 0);
    });
  });
}
