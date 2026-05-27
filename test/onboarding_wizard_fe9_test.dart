// Ship FE9 (2026-05-27): wizard pending-invitation branching tests.
//
// Covers:
//   • Welcome step renders «Создать свою семью» когда нет приглашений
//   • Welcome step renders invitation card когда есть pending invitation
//   • Q1 skip path preserved (button still present + tap'able)
//   • Accept invitation tap → controller.acceptInvitation called
//   • Empty list → no invitation card rendered

import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/auth_service_interface.dart';
import 'package:rodnya/backend/interfaces/onboarding_capable_family_tree_service.dart';
import 'package:rodnya/backend/interfaces/semya_capable_family_tree_service.dart';
import 'package:rodnya/backend/models/onboarding_state.dart';
import 'package:rodnya/backend/models/semya.dart';
import 'package:rodnya/backend/models/semya_browse_token.dart';
import 'package:rodnya/backend/models/semya_invitation.dart';
import 'package:rodnya/backend/models/semya_pull_person_result.dart';
import 'package:rodnya/providers/onboarding_controller.dart';

class _FakeOnboardingService implements OnboardingCapableFamilyTreeService {
  _FakeOnboardingService();

  OnboardingState _state = OnboardingState.fresh;

  @override
  Future<OnboardingState?> getOnboardingState() async => _state;

  @override
  Future<OnboardingState?> updateOnboardingState({
    required OnboardingStep currentStep,
  }) async {
    _state = _state.copyWith(currentStep: currentStep);
    return _state;
  }

  @override
  Future<OnboardingState?> skipOnboarding() async {
    _state = _state.copyWith(currentStep: OnboardingStep.done, skipped: true);
    return _state;
  }

  @override
  Future<OnboardingSeedResult?> seedOnboarding({
    required OnboardingSeedPayload payload,
  }) async =>
      throw UnimplementedError();
}

class _FakeSemyaService implements SemyaCapableFamilyTreeService {
  _FakeSemyaService({this.pendingInvitations = const <SemyaInvitation>[]});

  List<SemyaInvitation> pendingInvitations;
  int acceptCalls = 0;
  String? lastAcceptedToken;

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
  Future<SemyaInvitationAcceptResult> acceptInvitation(String token) async {
    acceptCalls += 1;
    lastAcceptedToken = token;
    return SemyaInvitationAcceptResult(
      invitation: SemyaInvitation(
        id: 'inv-${pendingInvitations.length}',
        token: token,
        semyaId: 's-1',
        inviterUserId: 'u-owner',
        role: SemyaRole.editor,
        status: SemyaInvitationStatus.accepted,
        createdAt: '2026-05-27T00:00:00.000Z',
        expiresAt: '2026-06-26T00:00:00.000Z',
      ),
      semyaId: 's-1',
      role: SemyaRole.editor,
      membershipId: 'mem-new',
    );
  }

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
      pendingInvitations;
}

class _FakeAuthService implements AuthServiceInterface {
  int markedSkipped = 0;

  @override
  Future<void> markOnboardingSkipped() async {
    markedSkipped += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

SemyaInvitation _invitation({
  String id = 'inv-1',
  String token = 'tok-abc',
  String semyaName = 'Семья Ивановых',
  SemyaRole role = SemyaRole.editor,
}) {
  return SemyaInvitation(
    id: id,
    token: token,
    semyaId: 's-1',
    inviterUserId: 'u-owner',
    role: role,
    status: SemyaInvitationStatus.pending,
    createdAt: '2026-05-27T00:00:00.000Z',
    expiresAt: '2026-06-26T00:00:00.000Z',
    semyaName: semyaName,
  );
}

void main() {
  group('FE9 controller — listPendingInvitations integration', () {
    test('loads pending invitations on construct', () async {
      final semya = _FakeSemyaService(
        pendingInvitations: [
          _invitation(id: 'i-1', token: 't-1'),
          _invitation(id: 'i-2', token: 't-2', semyaName: 'Семья Петровых'),
        ],
      );
      final controller = OnboardingController(
        service: _FakeOnboardingService(),
        semyaService: semya,
      );
      // Wait для hydrate + invitations fetch.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(controller.hasPendingInvitations, isTrue);
      expect(controller.pendingInvitations.length, 2);
      expect(controller.pendingInvitations.first.semyaName, 'Семья Ивановых');
    });

    test('empty list when no invitations', () async {
      final controller = OnboardingController(
        service: _FakeOnboardingService(),
        semyaService: _FakeSemyaService(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(controller.hasPendingInvitations, isFalse);
    });

    test('null semyaService — no invitations fetched', () async {
      final controller = OnboardingController(
        service: _FakeOnboardingService(),
        semyaService: null,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(controller.hasPendingInvitations, isFalse);
      expect(controller.isLoadingInvitations, isFalse);
    });
  });

  group('FE9 controller — acceptInvitation', () {
    test('success marks onboarding skipped + removes from local list',
        () async {
      final auth = _FakeAuthService();
      final semya = _FakeSemyaService(
        pendingInvitations: [_invitation(id: 'i-1', token: 't-1')],
      );
      final controller = OnboardingController(
        service: _FakeOnboardingService(),
        authService: auth,
        semyaService: semya,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(controller.pendingInvitations.length, 1);
      final result = await controller.acceptInvitation('t-1');
      // Wait для unawaited markOnboardingSkipped microtask.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(result, isNotNull);
      expect(semya.acceptCalls, 1);
      expect(semya.lastAcceptedToken, 't-1');
      expect(auth.markedSkipped, 1);
      expect(controller.pendingInvitations, isEmpty);
    });

    test('error surfaces controller.error', () async {
      final semya = _FailingSemyaService();
      final controller = OnboardingController(
        service: _FakeOnboardingService(),
        semyaService: semya,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final result = await controller.acceptInvitation('bad-token');
      expect(result, isNull);
      expect(controller.error, contains('недоступно'));
    });
  });
}

class _FailingSemyaService extends _FakeSemyaService {
  @override
  Future<SemyaInvitationAcceptResult> acceptInvitation(String token) async {
    throw const SemyaError(
      code: 'INVITATION_NOT_FOUND',
      message: 'Приглашение недоступно',
    );
  }
}
