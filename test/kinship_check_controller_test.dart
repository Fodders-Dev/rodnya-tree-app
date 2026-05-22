// Phase 6 chunk 3: KinshipCheckController state machine + service
// interaction patterns.

import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/kinship_check_capable_family_tree_service.dart';
import 'package:rodnya/backend/models/blood_relation.dart';
import 'package:rodnya/backend/models/kinship_check.dart';
import 'package:rodnya/providers/kinship_check_controller.dart';

class _FakeService implements KinshipCheckCapableFamilyTreeService {
  _FakeService({
    this.received = const [],
    this.issued = const [],
    this.createResult,
    this.respondResult,
    this.revokeResult,
    this.throwOnCreate,
    this.throwOnRespond,
    this.throwOnRevoke,
  });

  List<KinshipCheck> received;
  List<KinshipCheck> issued;
  KinshipCheckCreateResult? createResult;
  KinshipCheck? respondResult;
  KinshipCheck? revokeResult;
  KinshipCheckError? throwOnCreate;
  KinshipCheckError? throwOnRespond;
  KinshipCheckError? throwOnRevoke;

  String? lastTargetUserId;
  KinshipCheckDecision? lastRespondDecision;
  String? lastRespondCheckId;
  String? lastRevokeCheckId;

  @override
  Future<KinshipCheckCreateResult?> createKinshipCheck({
    required String targetUserId,
  }) async {
    lastTargetUserId = targetUserId;
    if (throwOnCreate != null) throw throwOnCreate!;
    return createResult;
  }

  @override
  Future<List<KinshipCheck>> listReceivedKinshipChecks({
    KinshipCheckStatus? status,
  }) async =>
      received;

  @override
  Future<List<KinshipCheck>> listIssuedKinshipChecks({
    KinshipCheckStatus? status,
  }) async =>
      issued;

  @override
  Future<KinshipCheck?> respondToKinshipCheck({
    required String checkId,
    required KinshipCheckDecision decision,
  }) async {
    lastRespondDecision = decision;
    lastRespondCheckId = checkId;
    if (throwOnRespond != null) throw throwOnRespond!;
    return respondResult;
  }

  @override
  Future<KinshipCheck?> revokeKinshipCheck({
    required String checkId,
  }) async {
    lastRevokeCheckId = checkId;
    if (throwOnRevoke != null) throw throwOnRevoke!;
    return revokeResult;
  }
}

KinshipCheck _pending(String id, {String initiator = 'u-a', String target = 'u-b'}) {
  return KinshipCheck(
    id: id,
    initiatorUserId: initiator,
    targetUserId: target,
    status: KinshipCheckStatus.pending,
    createdAt: '2026-05-14T10:00:00Z',
    expiresAt: '2026-05-28T10:00:00Z',
  );
}

void main() {
  group('isCapable', () {
    test('false when service null', () {
      final c = KinshipCheckController(service: null);
      expect(c.isCapable, isFalse);
    });

    test('true when service non-null', () {
      final c = KinshipCheckController(service: _FakeService());
      expect(c.isCapable, isTrue);
    });
  });

  group('refresh', () {
    test('hydrates received + issued lists', () async {
      final fake = _FakeService(
        received: [_pending('r-1')],
        issued: [_pending('i-1')],
      );
      final c = KinshipCheckController(service: fake);
      await c.refresh();
      expect(c.received.length, 1);
      expect(c.issued.length, 1);
      expect(c.received.first.id, 'r-1');
      expect(c.issued.first.id, 'i-1');
    });

    test('pendingReceived фильтрует non-pending', () async {
      final fake = _FakeService(
        received: [
          _pending('p-1'),
          KinshipCheck(
            id: 'a-1',
            initiatorUserId: 'u-a',
            targetUserId: 'u-b',
            status: KinshipCheckStatus.accepted,
            createdAt: '2026-05-14T10:00:00Z',
            expiresAt: '2026-05-28T10:00:00Z',
          ),
        ],
      );
      final c = KinshipCheckController(service: fake);
      await c.refresh();
      expect(c.received.length, 2);
      expect(c.pendingReceived.length, 1);
      expect(c.pendingReceived.first.id, 'p-1');
    });

    test('no-op когда service == null', () async {
      final c = KinshipCheckController(service: null);
      await c.refresh();
      expect(c.received, isEmpty);
      expect(c.issued, isEmpty);
    });
  });

  group('outgoing flow', () {
    test('selectTarget transitions step → confirming', () {
      final c = KinshipCheckController(service: _FakeService());
      expect(c.step, DiscoverStep.start);
      c.selectTarget(userId: 'u-b', displayName: 'Иван');
      expect(c.step, DiscoverStep.confirming);
      expect(c.selectedTargetUserId, 'u-b');
      expect(c.selectedTargetDisplayName, 'Иван');
    });

    test('selectTarget ignores empty userId', () {
      final c = KinshipCheckController(service: _FakeService());
      c.selectTarget(userId: '', displayName: 'Foo');
      expect(c.step, DiscoverStep.start);
    });

    test('backToSearch resets target + step', () {
      final c = KinshipCheckController(service: _FakeService());
      c.selectTarget(userId: 'u-b', displayName: 'Иван');
      c.backToSearch();
      expect(c.step, DiscoverStep.start);
      expect(c.selectedTargetUserId, isNull);
    });

    test('submitCheck success → step=sent + submittedCheck', () async {
      final created = _pending('k-new');
      final fake = _FakeService(
        createResult: KinshipCheckCreateResult(
          check: created,
          created: true,
        ),
      );
      final c = KinshipCheckController(service: fake);
      c.selectTarget(userId: 'u-b', displayName: 'Иван');
      final ok = await c.submitCheck();
      expect(ok, isTrue);
      expect(c.step, DiscoverStep.sent);
      expect(c.submittedCheck?.id, 'k-new');
      expect(fake.lastTargetUserId, 'u-b');
    });

    test('submitCheck без selected target → error + false', () async {
      final c = KinshipCheckController(service: _FakeService());
      final ok = await c.submitCheck();
      expect(ok, isFalse);
      expect(c.error, isNotNull);
    });

    test('submitCheck когда service null → false', () async {
      final c = KinshipCheckController(service: null);
      c.selectTarget(userId: 'u-b', displayName: 'Иван');
      final ok = await c.submitCheck();
      expect(ok, isFalse);
    });

    test('submitCheck handles KinshipCheckError', () async {
      final fake = _FakeService(
        throwOnCreate: const KinshipCheckError(
          code: 'REJECTION_COOLDOWN',
          message: 'Попробуйте позже',
        ),
      );
      final c = KinshipCheckController(service: fake);
      c.selectTarget(userId: 'u-b', displayName: 'Иван');
      final ok = await c.submitCheck();
      expect(ok, isFalse);
      expect(c.error, 'Попробуйте позже');
      expect(c.step, DiscoverStep.confirming, reason: 'остаёмся на confirm');
    });
  });

  group('respondToCheck (bilateral consent)', () {
    test('accept success — updates local received + returns check', () async {
      final pending = _pending('r-1');
      final accepted = KinshipCheck(
        id: 'r-1',
        initiatorUserId: 'u-a',
        targetUserId: 'u-b',
        status: KinshipCheckStatus.accepted,
        createdAt: '2026-05-14T10:00:00Z',
        expiresAt: '2026-05-28T10:00:00Z',
        respondedAt: '2026-05-14T11:00:00Z',
        result: const BloodRelation(
          found: true,
          chain: [],
          edges: [],
          label: 'троюродная сестра',
          degree: 4,
        ),
      );
      final fake = _FakeService(
        received: [pending],
        respondResult: accepted,
      );
      final c = KinshipCheckController(service: fake);
      await c.refresh();
      final result = await c.respondToCheck(
        checkId: 'r-1',
        decision: KinshipCheckDecision.accepted,
      );
      expect(result?.status, KinshipCheckStatus.accepted);
      expect(fake.lastRespondDecision, KinshipCheckDecision.accepted);
      // Local list optimistically updated.
      expect(
        c.received.firstWhere((c) => c.id == 'r-1').status,
        KinshipCheckStatus.accepted,
      );
    });

    test('reject success — returns updated check', () async {
      final pending = _pending('r-2');
      final rejected = KinshipCheck(
        id: 'r-2',
        initiatorUserId: 'u-a',
        targetUserId: 'u-b',
        status: KinshipCheckStatus.rejected,
        createdAt: '2026-05-14T10:00:00Z',
        expiresAt: '2026-05-28T10:00:00Z',
        respondedAt: '2026-05-14T11:00:00Z',
      );
      final fake = _FakeService(
        received: [pending],
        respondResult: rejected,
      );
      final c = KinshipCheckController(service: fake);
      await c.refresh();
      final result = await c.respondToCheck(
        checkId: 'r-2',
        decision: KinshipCheckDecision.rejected,
      );
      expect(result?.status, KinshipCheckStatus.rejected);
      expect(fake.lastRespondDecision, KinshipCheckDecision.rejected);
    });

    test('handles NOT_PENDING error gracefully', () async {
      final fake = _FakeService(
        throwOnRespond: const KinshipCheckError(
          code: 'NOT_PENDING',
          message: 'Этот запрос уже обработан',
        ),
      );
      final c = KinshipCheckController(service: fake);
      final result = await c.respondToCheck(
        checkId: 'r-x',
        decision: KinshipCheckDecision.accepted,
      );
      expect(result, isNull);
      expect(c.error, 'Этот запрос уже обработан');
    });

    test('no-op когда service null', () async {
      final c = KinshipCheckController(service: null);
      final result = await c.respondToCheck(
        checkId: 'r-x',
        decision: KinshipCheckDecision.accepted,
      );
      expect(result, isNull);
    });
  });

  group('revokeCheck (Phase 6.5 initiator revocation)', () {
    test(
      'success — updates local issued + returns check with revokedAt',
      () async {
        final pending = _pending('i-1');
        final revoked = KinshipCheck(
          id: 'i-1',
          initiatorUserId: 'u-a',
          targetUserId: 'u-b',
          status: KinshipCheckStatus.revoked,
          createdAt: '2026-05-14T10:00:00Z',
          expiresAt: '2026-05-28T10:00:00Z',
          revokedAt: '2026-05-22T13:00:00Z',
        );
        final fake = _FakeService(
          issued: [pending],
          revokeResult: revoked,
        );
        final c = KinshipCheckController(service: fake);
        await c.refresh();
        final result = await c.revokeCheck(checkId: 'i-1');
        expect(result?.status, KinshipCheckStatus.revoked);
        expect(result?.revokedAt, '2026-05-22T13:00:00Z');
        expect(fake.lastRevokeCheckId, 'i-1');
        expect(
          c.issued.firstWhere((c) => c.id == 'i-1').status,
          KinshipCheckStatus.revoked,
        );
      },
    );

    test('handles NOT_INITIATOR error gracefully', () async {
      final fake = _FakeService(
        throwOnRevoke: const KinshipCheckError(
          code: 'NOT_INITIATOR',
          message: 'Нельзя отозвать чужой запрос',
        ),
      );
      final c = KinshipCheckController(service: fake);
      final result = await c.revokeCheck(checkId: 'i-x');
      expect(result, isNull);
      expect(c.error, 'Нельзя отозвать чужой запрос');
      expect(c.isRevoking, isFalse);
      expect(c.revokingCheckId, isNull);
    });

    test('handles NOT_PENDING (re-revoke / already responded)', () async {
      final fake = _FakeService(
        throwOnRevoke: const KinshipCheckError(
          code: 'NOT_PENDING',
          message: 'Этот запрос уже обработан либо отозван',
        ),
      );
      final c = KinshipCheckController(service: fake);
      final result = await c.revokeCheck(checkId: 'i-x');
      expect(result, isNull);
      expect(c.error, 'Этот запрос уже обработан либо отозван');
    });

    test('null result (network failure) sets error', () async {
      final fake = _FakeService(revokeResult: null);
      final c = KinshipCheckController(service: fake);
      final result = await c.revokeCheck(checkId: 'i-x');
      expect(result, isNull);
      expect(c.error, isNotNull);
      expect(c.isRevoking, isFalse);
    });

    test('no-op когда service null', () async {
      final c = KinshipCheckController(service: null);
      final result = await c.revokeCheck(checkId: 'i-x');
      expect(result, isNull);
    });

    test('no-op когда checkId empty', () async {
      final fake = _FakeService();
      final c = KinshipCheckController(service: fake);
      final result = await c.revokeCheck(checkId: '');
      expect(result, isNull);
      expect(fake.lastRevokeCheckId, isNull);
    });
  });

  group('findById helpers', () {
    test('findReceivedById matches', () async {
      final fake = _FakeService(received: [_pending('r-a'), _pending('r-b')]);
      final c = KinshipCheckController(service: fake);
      await c.refresh();
      expect(c.findReceivedById('r-a')?.id, 'r-a');
      expect(c.findReceivedById('r-zzz'), isNull);
    });

    test('findIssuedById matches', () async {
      final fake = _FakeService(issued: [_pending('i-a')]);
      final c = KinshipCheckController(service: fake);
      await c.refresh();
      expect(c.findIssuedById('i-a')?.id, 'i-a');
      expect(c.findIssuedById('i-zzz'), isNull);
    });
  });

  group('presentResult (chunk 4b deep-link)', () {
    test('sets submittedCheck + step=result', () {
      final accepted = KinshipCheck(
        id: 'k-x',
        initiatorUserId: 'u-a',
        targetUserId: 'u-b',
        status: KinshipCheckStatus.accepted,
        createdAt: '2026-05-14T10:00:00Z',
        expiresAt: '2026-05-28T10:00:00Z',
        respondedAt: '2026-05-14T11:00:00Z',
        result: const BloodRelation(
          found: true,
          chain: [],
          edges: [],
          label: 'мама',
          degree: 1,
        ),
      );
      final c = KinshipCheckController(service: _FakeService());
      c.presentResult(accepted);
      expect(c.step, DiscoverStep.result);
      expect(c.submittedCheck?.id, 'k-x');
      expect(c.selectedTargetUserId, 'u-b');
    });

    test('clears prior error', () async {
      final c = KinshipCheckController(service: _FakeService(
        throwOnCreate: const KinshipCheckError(
          code: 'UNKNOWN',
          message: 'fail',
        ),
      ));
      c.selectTarget(userId: 'u-b', displayName: 'Иван');
      await c.submitCheck(); // produces error
      expect(c.error, isNotNull);
      final accepted = KinshipCheck(
        id: 'k-x',
        initiatorUserId: 'u-a',
        targetUserId: 'u-b',
        status: KinshipCheckStatus.accepted,
        createdAt: '2026-05-14T10:00:00Z',
        expiresAt: '2026-05-28T10:00:00Z',
      );
      c.presentResult(accepted);
      expect(c.error, isNull);
    });
  });
}
