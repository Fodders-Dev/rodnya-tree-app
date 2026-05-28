// Ship FE3 (2026-05-26): invitations controller — load list, send,
// revoke. Tests cover happy paths + error surfaces + state transitions
// + capability fallback.

import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/semya_capable_family_tree_service.dart';
import 'package:rodnya/backend/models/deleted_person.dart';
import 'package:rodnya/backend/models/deleted_post.dart';
import 'package:rodnya/backend/models/semya.dart';
import 'package:rodnya/backend/models/semya_browse_token.dart';
import 'package:rodnya/backend/models/semya_invitation.dart';
import 'package:rodnya/backend/models/semya_pull_person_result.dart';
import 'package:rodnya/providers/semya_invitations_controller.dart';

class _FakeSemyaService implements SemyaCapableFamilyTreeService {
  _FakeSemyaService({
    this.invitations = const <SemyaInvitation>[],
    this.createResult,
    this.throwOnList,
    this.throwOnCreate,
    this.throwOnRevoke,
  });

  List<SemyaInvitation> invitations;
  SemyaInvitation? createResult;
  SemyaError? throwOnList;
  SemyaError? throwOnCreate;
  SemyaError? throwOnRevoke;

  int listCalls = 0;
  int createCalls = 0;
  int revokeCalls = 0;
  String? lastCreateRecipientEmail;
  String? lastCreateRecipientPhone;
  SemyaRole? lastCreateRole;
  String? lastRevokeId;

  @override
  Future<List<Semya>> listMySemya() async => const <Semya>[];

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
  }) async {
    createCalls += 1;
    lastCreateRecipientEmail = recipientEmail;
    lastCreateRecipientPhone = recipientPhone;
    lastCreateRole = role;
    if (throwOnCreate != null) throw throwOnCreate!;
    if (createResult == null) {
      throw const SemyaError(code: 'UNKNOWN', message: 'fake-not-configured');
    }
    return createResult!;
  }

  @override
  Future<List<SemyaInvitation>> listInvitationsForSemya(
    String semyaId,
  ) async {
    listCalls += 1;
    if (throwOnList != null) throw throwOnList!;
    return invitations;
  }

  @override
  Future<SemyaInvitation> revokeInvitation({
    required String semyaId,
    required String invitationId,
  }) async {
    revokeCalls += 1;
    lastRevokeId = invitationId;
    if (throwOnRevoke != null) throw throwOnRevoke!;
    // Mark як revoked (mirror backend behavior).
    return SemyaInvitation(
      id: invitationId,
      token: '',
      semyaId: semyaId,
      inviterUserId: 'u',
      role: SemyaRole.viewer,
      status: SemyaInvitationStatus.revoked,
      createdAt: '2026-05-26T00:00:00.000Z',
      expiresAt: '2026-06-25T00:00:00.000Z',
      revokedAt: '2026-05-26T00:00:01.000Z',
    );
  }

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

SemyaInvitation _invitation({
  String id = 'inv-1',
  String? email,
  SemyaInvitationStatus status = SemyaInvitationStatus.pending,
  SemyaRole role = SemyaRole.viewer,
}) {
  return SemyaInvitation(
    id: id,
    token: 'tok-$id',
    semyaId: 'semya-1',
    inviterUserId: 'user-1',
    role: role,
    status: status,
    createdAt: '2026-05-26T00:00:00.000Z',
    expiresAt: '2026-06-25T00:00:00.000Z',
    recipientEmail: email,
  );
}

void main() {
  test('controller.load() fetches invitations + updates state', () async {
    final service = _FakeSemyaService(
      invitations: [
        _invitation(id: 'a'),
        _invitation(id: 'b', status: SemyaInvitationStatus.accepted),
      ],
    );
    final controller = SemyaInvitationsController(
      semyaId: 'semya-1',
      service: service,
    );
    expect(controller.hasLoaded, isFalse);
    await controller.load();
    expect(controller.hasLoaded, isTrue);
    expect(controller.invitations.length, 2);
    expect(controller.errorMessage, isNull);
    expect(service.listCalls, 1);
  });

  test('controller.load() surfaces SemyaError message', () async {
    final service = _FakeSemyaService(
      throwOnList: const SemyaError(code: 'UNKNOWN', message: 'Сбой'),
    );
    final controller = SemyaInvitationsController(
      semyaId: 'semya-1',
      service: service,
    );
    await controller.load();
    expect(controller.errorMessage, 'Сбой');
    expect(controller.invitations, isEmpty);
  });

  test('sendInvitation requires recipient (returns false без recipient)',
      () async {
    final service = _FakeSemyaService();
    final controller = SemyaInvitationsController(
      semyaId: 'semya-1',
      service: service,
    );
    final ok = await controller.sendInvitation(role: SemyaRole.editor);
    expect(ok, isFalse);
    expect(controller.errorMessage, contains('email'));
    expect(service.createCalls, 0);
  });

  test('sendInvitation happy path — returns true + sets lastCreated',
      () async {
    final invitation = _invitation(id: 'inv-2', email: 'a@b.c');
    final service = _FakeSemyaService(
      invitations: [invitation],
      createResult: invitation,
    );
    final controller = SemyaInvitationsController(
      semyaId: 'semya-1',
      service: service,
    );
    final ok = await controller.sendInvitation(
      role: SemyaRole.editor,
      recipientEmail: 'a@b.c',
    );
    expect(ok, isTrue);
    expect(controller.lastCreated?.id, 'inv-2');
    expect(controller.errorMessage, isNull);
    expect(service.createCalls, 1);
    expect(service.lastCreateRecipientEmail, 'a@b.c');
    expect(service.lastCreateRole, SemyaRole.editor);
  });

  test('sendInvitation error — false + errorMessage set', () async {
    final service = _FakeSemyaService(
      throwOnCreate: const SemyaError(
        code: 'ALREADY_MEMBER',
        message: 'Уже состоит',
      ),
    );
    final controller = SemyaInvitationsController(
      semyaId: 'semya-1',
      service: service,
    );
    final ok = await controller.sendInvitation(
      role: SemyaRole.viewer,
      recipientEmail: 'a@b.c',
    );
    expect(ok, isFalse);
    expect(controller.errorMessage, 'Уже состоит');
    expect(controller.lastCreated, isNull);
  });

  test('revoke happy path — returns true + reloads list', () async {
    final service = _FakeSemyaService(invitations: [_invitation(id: 'x')]);
    final controller = SemyaInvitationsController(
      semyaId: 'semya-1',
      service: service,
    );
    await controller.load();
    final ok = await controller.revoke('x');
    expect(ok, isTrue);
    expect(service.revokeCalls, 1);
    expect(service.lastRevokeId, 'x');
    expect(service.listCalls, 2); // initial + post-revoke refresh
  });

  test('revoke error — false + errorMessage', () async {
    final service = _FakeSemyaService(
      throwOnRevoke: const SemyaError(
        code: 'INVITATION_NOT_PENDING',
        message: 'Уже не активно',
      ),
    );
    final controller = SemyaInvitationsController(
      semyaId: 'semya-1',
      service: service,
    );
    final ok = await controller.revoke('x');
    expect(ok, isFalse);
    expect(controller.errorMessage, 'Уже не активно');
  });

  test('clearLastCreated wipes lastCreated', () async {
    final invitation = _invitation(id: 'inv-3');
    final service = _FakeSemyaService(
      invitations: [invitation],
      createResult: invitation,
    );
    final controller = SemyaInvitationsController(
      semyaId: 'semya-1',
      service: service,
    );
    await controller.sendInvitation(
      role: SemyaRole.viewer,
      recipientEmail: 'a@b.c',
    );
    expect(controller.lastCreated, isNotNull);
    controller.clearLastCreated();
    expect(controller.lastCreated, isNull);
  });

  test('isCapable=false когда no service injected/registered', () async {
    final controller = SemyaInvitationsController(semyaId: 'semya-1');
    expect(controller.isCapable, isFalse);
    await controller.load();
    expect(controller.hasLoaded, isTrue);
    expect(controller.invitations, isEmpty);
  });

  test('Model fromJson round-trip preserves все 4 statuses', () {
    for (final status in SemyaInvitationStatus.values) {
      if (status == SemyaInvitationStatus.unknown) continue;
      final json = _invitation(status: status).toJson();
      final parsed = SemyaInvitation.fromJson(json);
      expect(parsed.status, status);
    }
  });

  test('Model recipientLabel falls back: email > phone > userId > default',
      () {
    final emailOnly = _invitation(email: 'a@b.c');
    expect(emailOnly.recipientLabel, 'a@b.c');

    final phoneOnly = SemyaInvitation(
      id: 'x',
      token: 't',
      semyaId: 's',
      inviterUserId: 'u',
      role: SemyaRole.viewer,
      status: SemyaInvitationStatus.pending,
      createdAt: 'c',
      expiresAt: 'e',
      recipientPhone: '+7 000',
    );
    expect(phoneOnly.recipientLabel, '+7 000');

    final userIdOnly = SemyaInvitation(
      id: 'y',
      token: 't',
      semyaId: 's',
      inviterUserId: 'u',
      role: SemyaRole.viewer,
      status: SemyaInvitationStatus.pending,
      createdAt: 'c',
      expiresAt: 'e',
      recipientUserId: 'usr-99',
    );
    expect(userIdOnly.recipientLabel, 'usr-99');

    final none = SemyaInvitation(
      id: 'z',
      token: 't',
      semyaId: 's',
      inviterUserId: 'u',
      role: SemyaRole.viewer,
      status: SemyaInvitationStatus.pending,
      createdAt: 'c',
      expiresAt: 'e',
    );
    expect(none.recipientLabel, 'Без получателя');
  });
}
