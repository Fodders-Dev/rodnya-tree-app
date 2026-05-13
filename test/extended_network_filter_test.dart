import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rodnya/backend/interfaces/extended_network_capable_family_tree_service.dart';
import 'package:rodnya/backend/models/extended_network_slice.dart';
import 'package:rodnya/providers/extended_network_controller.dart';
import 'package:rodnya/widgets/extended_network_filter_sheet.dart';
import 'package:rodnya/widgets/extended_network_filter_sidebar.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeService implements ExtendedNetworkCapableFamilyTreeService {
  @override
  Future<ExtendedNetworkSlice?> getExtendedNetworkSlice({
    required String treeId,
    int maxHops = 4,
    bool includeAnonymous = true,
    List<String>? branchIds,
  }) async {
    return ExtendedNetworkSlice.empty;
  }
}

Widget _wrap(
  Widget child, {
  required ExtendedNetworkController controller,
  Size screenSize = const Size(420, 800),
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: screenSize),
      child: Scaffold(
        body: ChangeNotifierProvider<ExtendedNetworkController>.value(
          value: controller,
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('ExtendedNetworkFilterSheet', () {
    testWidgets('render slider 2..4 + chips Все + switch', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final controller = ExtendedNetworkController(
        treeId: 'tree-1',
        service: _FakeService(),
        preferences: prefs,
      );
      await controller.ready;

      await tester.pumpWidget(
        _wrap(
          const ExtendedNetworkFilterSheet(
            branchOptions: <BranchFilterOption>[],
          ),
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Фильтры расширенной сети'), findsOneWidget);
      expect(find.text('Глубина связи'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('Показывать карточки без аккаунта'), findsOneWidget);
    });

    testWidgets('slider шаг меняет maxHops в controller', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final controller = ExtendedNetworkController(
        treeId: 'tree-1',
        service: _FakeService(),
        preferences: prefs,
      );
      await controller.ready;
      expect(controller.maxHops, 4);

      await tester.pumpWidget(
        _wrap(
          const ExtendedNetworkFilterSheet(
            branchOptions: <BranchFilterOption>[],
          ),
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();

      // Перетягиваем slider до min (значение 2).
      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged!(2.0);
      await tester.pumpAndSettle();
      expect(controller.maxHops, 2);
    });

    testWidgets('switch toggle\'ит includeAnonymous', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final controller = ExtendedNetworkController(
        treeId: 'tree-1',
        service: _FakeService(),
        preferences: prefs,
      );
      await controller.ready;
      expect(controller.includeAnonymous, isTrue);

      await tester.pumpWidget(
        _wrap(
          const ExtendedNetworkFilterSheet(
            branchOptions: <BranchFilterOption>[],
          ),
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(controller.includeAnonymous, isFalse);
    });

    testWidgets('chip select работает', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final controller = ExtendedNetworkController(
        treeId: 'tree-1',
        service: _FakeService(),
        preferences: prefs,
      );
      await controller.ready;

      await tester.pumpWidget(
        _wrap(
          const ExtendedNetworkFilterSheet(
            branchOptions: <BranchFilterOption>[
              BranchFilterOption(treeId: 'br-1', displayName: 'Папа'),
              BranchFilterOption(treeId: 'br-2', displayName: 'Мама'),
            ],
          ),
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilterChip, 'Все'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Папа'), findsOneWidget);
      expect(find.widgetWithText(FilterChip, 'Мама'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'Папа'));
      await tester.pumpAndSettle();
      expect(controller.branchFilter.contains('br-1'), isTrue);
    });
  });

  group('ExtendedNetworkFilterSidebar', () {
    testWidgets('mine mode → shrink (sidebar пуст)', (tester) async {
      final prefs = await SharedPreferences.getInstance();
      final controller = ExtendedNetworkController(
        treeId: 'tree-1',
        service: _FakeService(),
        preferences: prefs,
      );
      await controller.ready;
      expect(controller.mode, ExtendedNetworkMode.mine);

      await tester.pumpWidget(
        _wrap(
          const ExtendedNetworkFilterSidebar(
            branchOptions: <BranchFilterOption>[],
          ),
          controller: controller,
          screenSize: const Size(1600, 900),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Расширенная сеть'), findsNothing);
    });

    testWidgets('extended mode → render slider + switch + stats',
        (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'extended_mode_tree-1': 'extended',
      });
      final prefs = await SharedPreferences.getInstance();
      final controller = ExtendedNetworkController(
        treeId: 'tree-1',
        service: _FakeService(),
        preferences: prefs,
      );
      await controller.ready;
      expect(controller.mode, ExtendedNetworkMode.extended);

      await tester.pumpWidget(
        _wrap(
          const ExtendedNetworkFilterSidebar(
            branchOptions: <BranchFilterOption>[],
          ),
          controller: controller,
          screenSize: const Size(1600, 900),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Расширенная сеть'), findsOneWidget);
      expect(find.text('Глубина'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      // Stats: empty slice → 'Показано: 0 человек'.
      expect(find.textContaining('Показано:'), findsOneWidget);
    });

    testWidgets('capReached → показывается красный hint', (tester) async {
      final capSlice = ExtendedNetworkSlice.fromJson({
        'graphPersons': [],
        'graphRelations': [],
        'branchMembership': {},
        'ownerMap': {},
        'stats': {
          'totalCount': 1000,
          'myCount': 100,
          'extendedCount': 900,
          'anonymousCount': 0,
          'maxHopsReached': true,
          'capReached': true,
        },
      });
      SharedPreferences.setMockInitialValues(<String, Object>{
        'extended_mode_tree-1': 'extended',
      });
      final prefs = await SharedPreferences.getInstance();
      final controller = ExtendedNetworkController(
        treeId: 'tree-1',
        service: _PrebuiltSliceService(capSlice),
        preferences: prefs,
      );
      await controller.ready;

      await tester.pumpWidget(
        _wrap(
          const ExtendedNetworkFilterSidebar(
            branchOptions: <BranchFilterOption>[],
          ),
          controller: controller,
          screenSize: const Size(1600, 900),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Достигнут лимит — сузьте через фильтры'),
        findsOneWidget,
      );
    });
  });
}

class _PrebuiltSliceService implements ExtendedNetworkCapableFamilyTreeService {
  _PrebuiltSliceService(this._slice);

  final ExtendedNetworkSlice _slice;

  @override
  Future<ExtendedNetworkSlice?> getExtendedNetworkSlice({
    required String treeId,
    int maxHops = 4,
    bool includeAnonymous = true,
    List<String>? branchIds,
  }) async {
    return _slice;
  }
}
