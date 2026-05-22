import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/services/tree_refresh_coordinator.dart';

void main() {
  // TreeRefreshCoordinator is keyed by treeId — each test uses
  // unique treeIds to avoid cross-test interference on the singleton
  // map, and cleans up its callbacks через unregister на tearDown.
  group('TreeRefreshCoordinator', () {
    test('register makes hasSubscriber report true for that treeId',
        () async {
      final coordinator = TreeRefreshCoordinator.instance;
      const treeId = 't-register-1';
      Future<void> cb() async {}

      expect(coordinator.hasSubscriber(treeId), isFalse);
      coordinator.register(treeId, cb);
      addTearDown(() => coordinator.unregister(treeId, cb));
      expect(coordinator.hasSubscriber(treeId), isTrue);
    });

    test('unregister with matching callback removes the subscription',
        () async {
      final coordinator = TreeRefreshCoordinator.instance;
      const treeId = 't-unregister-1';
      Future<void> cb() async {}

      coordinator.register(treeId, cb);
      coordinator.unregister(treeId, cb);
      expect(coordinator.hasSubscriber(treeId), isFalse);
    });

    test(
        'unregister with foreign callback does not drop subscription '
        '(identity check protects other screens)', () async {
      final coordinator = TreeRefreshCoordinator.instance;
      const treeId = 't-unregister-foreign';
      Future<void> cb1() async {}
      Future<void> cb2() async {}

      coordinator.register(treeId, cb1);
      addTearDown(() => coordinator.unregister(treeId, cb1));
      // cb2 was never registered — must not unregister cb1.
      coordinator.unregister(treeId, cb2);
      expect(coordinator.hasSubscriber(treeId), isTrue);
    });

    test(
        'requestRefresh fires callback once when called multiple times '
        'within debounce window', () async {
      final coordinator = TreeRefreshCoordinator.instance;
      const treeId = 't-debounce-1';
      var fireCount = 0;
      Future<void> cb() async {
        fireCount += 1;
      }

      coordinator.register(treeId, cb);
      addTearDown(() => coordinator.unregister(treeId, cb));

      coordinator.requestRefresh(treeId);
      coordinator.requestRefresh(treeId);
      coordinator.requestRefresh(treeId);
      expect(fireCount, 0);

      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(fireCount, 1);
    });

    test('requestRefresh is a no-op without subscriber on that treeId',
        () async {
      final coordinator = TreeRefreshCoordinator.instance;
      const treeId = 't-no-subscriber';
      // Never register — just request.
      coordinator.requestRefresh(treeId);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      // No assertion target beyond "didn't throw" — verifying the
      // empty-state semantics is the point.
      expect(coordinator.hasSubscriber(treeId), isFalse);
    });

    test('refresh is isolated per treeId — request on A does not fire B',
        () async {
      final coordinator = TreeRefreshCoordinator.instance;
      const treeIdA = 't-isolated-A';
      const treeIdB = 't-isolated-B';
      var fireA = 0;
      var fireB = 0;
      Future<void> cbA() async {
        fireA += 1;
      }

      Future<void> cbB() async {
        fireB += 1;
      }

      coordinator.register(treeIdA, cbA);
      coordinator.register(treeIdB, cbB);
      addTearDown(() => coordinator.unregister(treeIdA, cbA));
      addTearDown(() => coordinator.unregister(treeIdB, cbB));

      coordinator.requestRefresh(treeIdA);
      await Future<void>.delayed(const Duration(milliseconds: 700));

      expect(fireA, 1);
      expect(fireB, 0);
    });

    test('register replaces previous callback for the same treeId',
        () async {
      final coordinator = TreeRefreshCoordinator.instance;
      const treeId = 't-replace-1';
      var cb1Count = 0;
      var cb2Count = 0;
      Future<void> cb1() async {
        cb1Count += 1;
      }

      Future<void> cb2() async {
        cb2Count += 1;
      }

      coordinator.register(treeId, cb1);
      coordinator.register(treeId, cb2);
      addTearDown(() => coordinator.unregister(treeId, cb2));

      coordinator.requestRefresh(treeId);
      await Future<void>.delayed(const Duration(milliseconds: 700));

      expect(cb1Count, 0);
      expect(cb2Count, 1);
    });

    test('empty treeId is a no-op for register / unregister / requestRefresh',
        () async {
      final coordinator = TreeRefreshCoordinator.instance;
      var fireCount = 0;
      Future<void> cb() async {
        fireCount += 1;
      }

      coordinator.register('', cb);
      expect(coordinator.hasSubscriber(''), isFalse);

      coordinator.requestRefresh('');
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(fireCount, 0);
    });

    test('callback exception is swallowed — coordinator survives',
        () async {
      final coordinator = TreeRefreshCoordinator.instance;
      const treeId = 't-exception';
      Future<void> badCb() async {
        throw StateError('boom');
      }

      coordinator.register(treeId, badCb);
      addTearDown(() => coordinator.unregister(treeId, badCb));

      coordinator.requestRefresh(treeId);
      await Future<void>.delayed(const Duration(milliseconds: 700));

      // After exception, a fresh subscriber should still receive events.
      var followupCount = 0;
      Future<void> followupCb() async {
        followupCount += 1;
      }

      coordinator.register(treeId, followupCb);
      addTearDown(() => coordinator.unregister(treeId, followupCb));

      coordinator.requestRefresh(treeId);
      await Future<void>.delayed(const Duration(milliseconds: 700));

      expect(followupCount, 1);
    });
  });
}
