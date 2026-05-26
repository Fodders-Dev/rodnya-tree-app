// Ship FE2 (2026-05-26): controller loads семя details + memberships
// в parallel, exposes loading/error/loaded state. Tests verify happy
// path + 404 returning null + SemyaError surface + incapable fallback.

import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/semya_capable_family_tree_service.dart';
import 'package:rodnya/backend/models/semya.dart';
import 'package:rodnya/backend/models/semya_browse_token.dart';
import 'package:rodnya/backend/models/semya_invitation.dart';
import 'package:rodnya/backend/models/semya_pull_person_result.dart';
import 'package:rodnya/providers/semya_details_controller.dart';

class _FakeSemyaService implements SemyaCapableFamilyTreeService {
  _FakeSemyaService({
    this.details,
    this.memberships = const <SemyaMembership>[],
    this.throwOnDetails,
  });

  SemyaDetails? details;
  List<SemyaMembership> memberships;
  SemyaError? throwOnDetails;
  int detailsCalls = 0;
  int membershipsCalls = 0;

  @override
  Future<List<Semya>> listMySemya() async => const <Semya>[];

  @override
  Future<SemyaDetails?> findSemyaById(String semyaId) async {
    detailsCalls += 1;
    if (throwOnDetails != null) throw throwOnDetails!;
    return details;
  }

  @override
  Future<List<SemyaMembership>> listMembershipsForSemya(
    String semyaId,
  ) async {
    membershipsCalls += 1;
    return memberships;
  }

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
}

SemyaDetails _details({
  String id = 'semya-1',
  String name = 'Семья Кузнецовых',
  SemyaRole role = SemyaRole.owner,
  bool hasInviteGrant = false,
}) {
  return SemyaDetails(
    semya: Semya(
      id: id,
      name: name,
      ownerId: 'user-1',
      treeId: 'tree-1',
      createdAt: '2026-05-22T00:00:00.000Z',
      updatedAt: '2026-05-22T00:00:00.000Z',
    ),
    membership: SemyaMembership(
      id: 'm-1',
      semyaId: id,
      userId: 'user-1',
      role: role,
      joinedAt: '2026-05-22T00:00:00.000Z',
      hasInviteGrant: hasInviteGrant,
    ),
  );
}

SemyaMembership _membership({
  String id = 'm-x',
  String userId = 'user-x',
  SemyaRole role = SemyaRole.editor,
}) {
  return SemyaMembership(
    id: id,
    semyaId: 'semya-1',
    userId: userId,
    role: role,
    joinedAt: '2026-05-22T00:00:00.000Z',
  );
}

void main() {
  test('SemyaDetailsController loads details + memberships в parallel',
      () async {
    final service = _FakeSemyaService(
      details: _details(),
      memberships: [
        _membership(userId: 'editor-a', role: SemyaRole.editor),
        _membership(userId: 'viewer-b', role: SemyaRole.viewer),
      ],
    );
    final controller = SemyaDetailsController(
      semyaId: 'semya-1',
      service: service,
    );
    expect(controller.hasLoaded, isFalse);
    await controller.load();
    expect(controller.hasLoaded, isTrue);
    expect(controller.isLoading, isFalse);
    expect(controller.details, isNotNull);
    expect(controller.details!.semya.name, 'Семья Кузнецовых');
    expect(controller.memberships.length, 2);
    expect(controller.errorMessage, isNull);
    expect(service.detailsCalls, 1);
    expect(service.membershipsCalls, 1);
  });

  test('SemyaDetailsController surfaces error when details null',
      () async {
    final service = _FakeSemyaService(details: null);
    final controller = SemyaDetailsController(
      semyaId: 'unknown',
      service: service,
    );
    await controller.load();
    expect(controller.details, isNull);
    expect(controller.errorMessage, isNotNull);
    expect(controller.hasLoaded, isTrue);
  });

  test('SemyaDetailsController surfaces SemyaError message', () async {
    final service = _FakeSemyaService(
      throwOnDetails: const SemyaError(
        code: 'FORBIDDEN',
        message: 'Нет доступа',
      ),
    );
    final controller = SemyaDetailsController(
      semyaId: 'semya-1',
      service: service,
    );
    await controller.load();
    expect(controller.errorMessage, 'Нет доступа');
    expect(controller.details, isNull);
  });

  test('SemyaDetailsController isCapable=false когда no service', () async {
    // Default GetIt не has FamilyTreeServiceInterface registered.
    final controller = SemyaDetailsController(semyaId: 'semya-1');
    expect(controller.isCapable, isFalse);
    await controller.load();
    expect(controller.hasLoaded, isTrue);
    expect(controller.details, isNull);
  });

  test('SemyaDetailsController.callerRole convenience reads', () async {
    final service = _FakeSemyaService(
      details: _details(role: SemyaRole.viewer),
    );
    final controller = SemyaDetailsController(
      semyaId: 'semya-1',
      service: service,
    );
    await controller.load();
    expect(controller.details!.callerRole, SemyaRole.viewer);
    expect(controller.details!.canEdit, isFalse);
    expect(controller.details!.canInvite, isFalse);
  });

  test('SemyaDetailsController owner с invite grant', () async {
    final service = _FakeSemyaService(
      details: _details(
        role: SemyaRole.editor,
        hasInviteGrant: true,
      ),
    );
    final controller = SemyaDetailsController(
      semyaId: 'semya-1',
      service: service,
    );
    await controller.load();
    expect(controller.details!.canInvite, isTrue);
  });

  test('refresh() re-fetches', () async {
    final service = _FakeSemyaService(details: _details());
    final controller = SemyaDetailsController(
      semyaId: 'semya-1',
      service: service,
    );
    await controller.load();
    expect(service.detailsCalls, 1);
    await controller.refresh();
    expect(service.detailsCalls, 2);
    expect(service.membershipsCalls, 2);
  });
}
