// Ship FE3b (2026-05-28): deep-link token persist service tests.
//
// Covers:
//   • setPendingToken stores в RAM + notifies + persists к disk
//   • consumePendingToken returns + clears
//   • clearPendingToken nulls state
//   • restoreFromDisk hydrates RAM when no in-memory token set
//   • ready Future resolves after initial restore

import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/services/semya_invitation_deep_link_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('initial state — no pending token', () async {
    final service = SemyaInvitationDeepLinkService.forTest();
    await service.ready;
    expect(service.hasPendingToken, isFalse);
    expect(service.pendingToken, isNull);
  });

  test('setPendingToken stores in RAM + notifies', () async {
    final service = SemyaInvitationDeepLinkService.forTest();
    await service.ready;
    var notified = 0;
    service.addListener(() => notified += 1);
    service.setPendingToken('tok-abc');
    expect(service.pendingToken, 'tok-abc');
    expect(service.hasPendingToken, isTrue);
    expect(notified, 1);
  });

  test('setPendingToken trims + rejects empty', () async {
    final service = SemyaInvitationDeepLinkService.forTest();
    await service.ready;
    service.setPendingToken('   ');
    expect(service.hasPendingToken, isFalse);
    service.setPendingToken('  tok-trim  ');
    expect(service.pendingToken, 'tok-trim');
  });

  test('consumePendingToken returns + clears', () async {
    final service = SemyaInvitationDeepLinkService.forTest();
    await service.ready;
    service.setPendingToken('one-shot');
    final taken = service.consumePendingToken();
    expect(taken, 'one-shot');
    expect(service.hasPendingToken, isFalse);
    // Second call returns null.
    final second = service.consumePendingToken();
    expect(second, isNull);
  });

  test('clearPendingToken nulls state', () async {
    final service = SemyaInvitationDeepLinkService.forTest();
    await service.ready;
    service.setPendingToken('to-clear');
    service.clearPendingToken();
    expect(service.hasPendingToken, isFalse);
  });

  test('restore from disk on cold start', () async {
    SharedPreferences.setMockInitialValues({
      'pending_semya_invitation_token_v1': 'persisted-tok',
    });
    final service = SemyaInvitationDeepLinkService.forTest();
    await service.ready;
    // Pending token restored automatically.
    expect(service.pendingToken, 'persisted-tok');
  });

  test('persist round-trip — set → re-instantiate → restored', () async {
    final s1 = SemyaInvitationDeepLinkService.forTest();
    await s1.ready;
    s1.setPendingToken('persistent-tok');
    // Wait for unawaited persist to flush.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final s2 = SemyaInvitationDeepLinkService.forTest();
    await s2.ready;
    expect(s2.pendingToken, 'persistent-tok');
  });

  test('consume clears disk persistence', () async {
    SharedPreferences.setMockInitialValues({
      'pending_semya_invitation_token_v1': 'tok-to-consume',
    });
    final s1 = SemyaInvitationDeepLinkService.forTest();
    await s1.ready;
    s1.consumePendingToken();
    // Wait for unawaited clear.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final s2 = SemyaInvitationDeepLinkService.forTest();
    await s2.ready;
    expect(s2.pendingToken, isNull);
  });

  testWidgets('ChangeNotifier semantics — notifyListeners fires',
      (tester) async {
    final service = SemyaInvitationDeepLinkService.forTest();
    await service.ready;
    var changeCount = 0;
    service.addListener(() => changeCount += 1);
    service.setPendingToken('x');
    service.consumePendingToken();
    // set + consume = 2 notifications.
    expect(changeCount, 2);
  });
}
