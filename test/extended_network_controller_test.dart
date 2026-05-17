import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/extended_network_capable_family_tree_service.dart';
import 'package:rodnya/backend/models/extended_network_slice.dart';
import 'package:rodnya/providers/extended_network_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeService implements ExtendedNetworkCapableFamilyTreeService {
  _FakeService({this.slice});

  ExtendedNetworkSlice? slice;
  int callCount = 0;
  int? lastMaxHops;
  bool? lastIncludeAnonymous;
  List<String>? lastBranchIds;
  bool throwOnFetch = false;

  @override
  Future<ExtendedNetworkSlice?> getExtendedNetworkSlice({
    required String treeId,
    int maxHops = 4,
    bool includeAnonymous = true,
    List<String>? branchIds,
  }) async {
    callCount += 1;
    lastMaxHops = maxHops;
    lastIncludeAnonymous = includeAnonymous;
    lastBranchIds = branchIds;
    if (throwOnFetch) throw StateError('boom');
    return slice;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('ExtendedNetworkController capability', () {
    test('isCapable=true когда service ≠ null', () async {
      final prefs = await SharedPreferences.getInstance();
      final controller = ExtendedNetworkController(
        treeId: 'tree-1',
        service: _FakeService(),
        preferences: prefs,
      );
      await controller.ready;
      expect(controller.isCapable, isTrue);
    });

    test('isCapable=false когда service = null', () async {
      final prefs = await SharedPreferences.getInstance();
      final controller = ExtendedNetworkController(
        treeId: 'tree-1',
        service: null,
        preferences: prefs,
      );
      await controller.ready;
      expect(controller.isCapable, isFalse);
    });
  });

  group('ExtendedNetworkController default state', () {
    test('mode=mine, maxHops=4, includeAnonymous=true, branchFilter empty',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final controller = ExtendedNetworkController(
        treeId: 'tree-1',
        service: _FakeService(),
        preferences: prefs,
      );
      await controller.ready;
      expect(controller.mode, ExtendedNetworkMode.mine);
      expect(controller.maxHops, 4);
      expect(controller.includeAnonymous, isTrue);
      expect(controller.branchFilter, isEmpty);
      expect(controller.slice, isNull);
    });
  });

  group('ExtendedNetworkController setMode', () {
    test('переключение в extended триггерит fetch slice', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final service = _FakeService(slice: ExtendedNetworkSlice.empty);
      final controller = ExtendedNetworkController(
        treeId: 'tree-1',
        service: service,
        preferences: prefs,
      );
      await controller.ready;
      expect(service.callCount, 0);
      await controller.setMode(ExtendedNetworkMode.extended);
      expect(controller.mode, ExtendedNetworkMode.extended);
      expect(service.callCount, 1);
      expect(controller.slice, isNotNull);
    });

    test('переключение mine → mine no-op', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = _FakeService();
      final controller = ExtendedNetworkController(
        treeId: 'tree-1',
        service: service,
        preferences: prefs,
      );
      await controller.ready;
      await controller.setMode(ExtendedNetworkMode.mine);
      expect(service.callCount, 0);
    });

    test('persist mode = "extended" в SharedPreferences', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final controller = ExtendedNetworkController(
        treeId: 'tree-abc',
        service: _FakeService(slice: ExtendedNetworkSlice.empty),
        preferences: prefs,
      );
      await controller.ready;
      await controller.setMode(ExtendedNetworkMode.extended);
      expect(prefs.getString('extended_mode_tree-abc'), 'extended');
    });
  });

  group('ExtendedNetworkController setMaxHops', () {
    test('clamp 1 → 2 (under lower bound)', () async {
      final prefs = await SharedPreferences.getInstance();
      final controller = ExtendedNetworkController(
        treeId: 'tree-1',
        service: _FakeService(),
        preferences: prefs,
      );
      await controller.ready;
      await controller.setMaxHops(1);
      expect(controller.maxHops, 2);
    });

    test('clamp 10 → 4 (above upper bound = privacy fence)', () async {
      final prefs = await SharedPreferences.getInstance();
      final controller = ExtendedNetworkController(
        treeId: 'tree-1',
        service: _FakeService(),
        preferences: prefs,
      );
      await controller.ready;
      await controller.setMaxHops(10);
      expect(controller.maxHops, 4);
    });

    test('valid 3 → 3', () async {
      final prefs = await SharedPreferences.getInstance();
      final controller = ExtendedNetworkController(
        treeId: 'tree-1',
        service: _FakeService(),
        preferences: prefs,
      );
      await controller.ready;
      await controller.setMaxHops(3);
      expect(controller.maxHops, 3);
    });

    test('setMaxHops в mine mode persist'
        'ит, но НЕ fetch'
        'ит slice', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = _FakeService();
      final controller = ExtendedNetworkController(
        treeId: 'tree-1',
        service: service,
        preferences: prefs,
      );
      await controller.ready;
      expect(controller.mode, ExtendedNetworkMode.mine);
      await controller.setMaxHops(3);
      expect(service.callCount, 0);
      expect(prefs.getInt('extended_max_hops_tree-1'), 3);
    });

    test('setMaxHops в extended mode fetch'
        'ит slice заново', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'extended_mode_tree-1': 'extended',
      });
      final prefs = await SharedPreferences.getInstance();
      final service = _FakeService(slice: ExtendedNetworkSlice.empty);
      final controller = ExtendedNetworkController(
        treeId: 'tree-1',
        service: service,
        preferences: prefs,
      );
      await controller.ready;
      expect(controller.mode, ExtendedNetworkMode.extended);
      // Initial load уже сделан в loadPersistedState
      final initialCalls = service.callCount;
      await controller.setMaxHops(2);
      expect(service.callCount, greaterThan(initialCalls));
      expect(service.lastMaxHops, 2);
    });
  });

  group('ExtendedNetworkController persistence on reload', () {
    test('mode persisted across controller restarts', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'extended_mode_tree-1': 'extended',
        'extended_max_hops_tree-1': 3,
        'extended_include_anonymous_tree-1': false,
      });
      final prefs = await SharedPreferences.getInstance();
      final controller = ExtendedNetworkController(
        treeId: 'tree-1',
        service: _FakeService(slice: ExtendedNetworkSlice.empty),
        preferences: prefs,
      );
      await controller.ready;
      expect(controller.mode, ExtendedNetworkMode.extended);
      expect(controller.maxHops, 3);
      expect(controller.includeAnonymous, isFalse);
    });

    test('per-tree isolation: tree-1 settings не влияют на tree-2', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'extended_mode_tree-1': 'extended',
      });
      final prefs = await SharedPreferences.getInstance();
      final controller1 = ExtendedNetworkController(
        treeId: 'tree-1',
        service: _FakeService(slice: ExtendedNetworkSlice.empty),
        preferences: prefs,
      );
      final controller2 = ExtendedNetworkController(
        treeId: 'tree-2',
        service: _FakeService(slice: ExtendedNetworkSlice.empty),
        preferences: prefs,
      );
      await controller1.ready;
      await controller2.ready;
      expect(controller1.mode, ExtendedNetworkMode.extended);
      expect(controller2.mode, ExtendedNetworkMode.mine);
    });
  });

  group('ExtendedNetworkController error handling', () {
    test('fetch error → error state, isFetching=false', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = _FakeService()..throwOnFetch = true;
      final controller = ExtendedNetworkController(
        treeId: 'tree-1',
        service: service,
        preferences: prefs,
      );
      await controller.ready;
      await controller.setMode(ExtendedNetworkMode.extended);
      expect(controller.error, isNotNull);
      expect(controller.error, contains('boom'));
      expect(controller.isFetching, isFalse);
    });
  });

  group('ExtendedNetworkController setBranchFilter', () {
    test('toggle filter values + persist as string list', () async {
      final prefs = await SharedPreferences.getInstance();
      final controller = ExtendedNetworkController(
        treeId: 'tree-1',
        service: _FakeService(),
        preferences: prefs,
      );
      await controller.ready;
      await controller.setBranchFilter({'br-1', 'br-2'});
      expect(controller.branchFilter, {'br-1', 'br-2'});
      expect(
        prefs.getStringList('extended_branch_filter_tree-1'),
        containsAll(['br-1', 'br-2']),
      );
    });

    test('setting same filter no-op', () async {
      final service = _FakeService(slice: ExtendedNetworkSlice.empty);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'extended_mode_tree-1': 'extended',
      });
      final prefs2 = await SharedPreferences.getInstance();
      final controller = ExtendedNetworkController(
        treeId: 'tree-1',
        service: service,
        preferences: prefs2,
      );
      await controller.ready;
      final initialCalls = service.callCount;
      await controller.setBranchFilter({});
      // Уже было пусто — no notify, no fetch.
      expect(service.callCount, initialCalls);
    });
  });

  group('ExtendedNetworkMode enum', () {
    test('serverValue round-trip', () {
      for (final mode in ExtendedNetworkMode.values) {
        expect(
          ExtendedNetworkMode.fromServerValue(mode.serverValue),
          mode,
        );
      }
    });

    test('fromServerValue unknown → mine (defensive)', () {
      expect(
        ExtendedNetworkMode.fromServerValue('unknown'),
        ExtendedNetworkMode.mine,
      );
      expect(
        ExtendedNetworkMode.fromServerValue(null),
        ExtendedNetworkMode.mine,
      );
    });

    test('russianLabel / russianLongLabel non-empty', () {
      for (final mode in ExtendedNetworkMode.values) {
        expect(mode.russianLabel.isNotEmpty, isTrue);
        expect(mode.russianLongLabel.isNotEmpty, isTrue);
      }
    });
  });
}
