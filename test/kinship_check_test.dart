// Phase 6 chunk 3: KinshipCheck DTO + status enum parsing.

import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/models/kinship_check.dart';

void main() {
  group('KinshipCheckStatus.fromServerValue', () {
    test('maps known values', () {
      expect(
        KinshipCheckStatus.fromServerValue('pending'),
        KinshipCheckStatus.pending,
      );
      expect(
        KinshipCheckStatus.fromServerValue('accepted'),
        KinshipCheckStatus.accepted,
      );
      expect(
        KinshipCheckStatus.fromServerValue('rejected'),
        KinshipCheckStatus.rejected,
      );
      expect(
        KinshipCheckStatus.fromServerValue('expired'),
        KinshipCheckStatus.expired,
      );
    });

    test('defaults к unknown для неизвестных значений', () {
      expect(
        KinshipCheckStatus.fromServerValue('weird'),
        KinshipCheckStatus.unknown,
      );
      expect(
        KinshipCheckStatus.fromServerValue(null),
        KinshipCheckStatus.unknown,
      );
    });
  });

  group('KinshipCheck.fromJson', () {
    test('parses pending check без result', () {
      final c = KinshipCheck.fromJson({
        'id': 'k-1',
        'initiatorUserId': 'u-a',
        'targetUserId': 'u-b',
        'status': 'pending',
        'createdAt': '2026-05-14T10:00:00Z',
        'expiresAt': '2026-05-28T10:00:00Z',
      });
      expect(c.id, 'k-1');
      expect(c.initiatorUserId, 'u-a');
      expect(c.targetUserId, 'u-b');
      expect(c.status, KinshipCheckStatus.pending);
      expect(c.result, isNull);
      expect(c.respondedAt, isNull);
    });

    test('parses accepted check + result chain', () {
      final c = KinshipCheck.fromJson({
        'id': 'k-2',
        'initiatorUserId': 'u-a',
        'targetUserId': 'u-b',
        'status': 'accepted',
        'createdAt': '2026-05-14T10:00:00Z',
        'expiresAt': '2026-05-28T10:00:00Z',
        'respondedAt': '2026-05-14T11:00:00Z',
        'result': {
          'found': true,
          'label': 'двоюродная сестра',
          'degree': 4,
          'chain': [
            {'id': 'gp-1', 'name': 'Артём'},
            {'id': 'gp-2', 'name': null}, // anonymized
            {'id': 'gp-3', 'name': 'Иван'},
          ],
          'edges': ['parent', 'child'],
        },
      });
      expect(c.status, KinshipCheckStatus.accepted);
      expect(c.respondedAt, '2026-05-14T11:00:00Z');
      expect(c.result, isNotNull);
      expect(c.result!.found, isTrue);
      expect(c.result!.label, 'двоюродная сестра');
      expect(c.result!.degree, 4);
      expect(c.result!.chain.length, 3);
      expect(c.result!.chain[0].name, 'Артём');
      expect(c.result!.chain[1].name, isNull); // privacy anonymization
      expect(c.result!.edges, ['parent', 'child']);
    });

    test('parses rejected check (result отсутствует)', () {
      final c = KinshipCheck.fromJson({
        'id': 'k-3',
        'initiatorUserId': 'u-a',
        'targetUserId': 'u-b',
        'status': 'rejected',
        'createdAt': '2026-05-14T10:00:00Z',
        'expiresAt': '2026-05-28T10:00:00Z',
        'respondedAt': '2026-05-14T11:00:00Z',
      });
      expect(c.status, KinshipCheckStatus.rejected);
      expect(c.result, isNull);
    });
  });

  group('KinshipCheckCreateResult.fromJson', () {
    test('extracts created flag + check', () {
      final r = KinshipCheckCreateResult.fromJson({
        'check': {
          'id': 'k-x',
          'initiatorUserId': 'u-a',
          'targetUserId': 'u-b',
          'status': 'pending',
          'createdAt': '2026-05-14T10:00:00Z',
          'expiresAt': '2026-05-28T10:00:00Z',
        },
        'created': true,
      });
      expect(r.created, isTrue);
      expect(r.check.id, 'k-x');
    });

    test('idempotent re-call → created=false', () {
      final r = KinshipCheckCreateResult.fromJson({
        'check': {
          'id': 'k-x',
          'initiatorUserId': 'u-a',
          'targetUserId': 'u-b',
          'status': 'pending',
          'createdAt': '2026-05-14T10:00:00Z',
          'expiresAt': '2026-05-28T10:00:00Z',
        },
        'created': false,
      });
      expect(r.created, isFalse);
    });

    test('throws когда `check` отсутствует', () {
      expect(
        () => KinshipCheckCreateResult.fromJson({'created': true}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('KinshipCheckDecision serverValue', () {
    test('mapping', () {
      expect(KinshipCheckDecision.accepted.serverValue, 'accepted');
      expect(KinshipCheckDecision.rejected.serverValue, 'rejected');
    });
  });
}
