import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:rodnya/backend/interfaces/semya_capable_family_tree_service.dart';
import 'package:rodnya/backend/models/semya.dart';
import 'package:rodnya/backend/models/semya_invitation.dart';
import 'package:rodnya/backend/models/semya_pull_person_result.dart';
import 'package:rodnya/providers/semya_list_controller.dart';
import 'package:rodnya/widgets/semya_switcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('SemyaSwitcher renders nothing when service not capable',
      (tester) async {
    final controller = SemyaListController(); // no injected service
    await tester.pumpWidget(_wrapWithController(controller));
    expect(find.byType(SemyaSwitcher), findsOneWidget);
    expect(find.text('Создать семью'), findsNothing);
    expect(find.byIcon(Icons.family_restroom), findsNothing);
  });

  testWidgets('SemyaSwitcher renders empty pill when zero семья',
      (tester) async {
    final service = _FakeSemyaService(semyi: const []);
    final controller = SemyaListController(service: service);
    await tester.pumpWidget(_wrapWithController(controller));
    await tester.pump(); // initial mount triggers loadInitial
    await tester.pump(); // resolve async future
    expect(find.text('Создать семью'), findsOneWidget);
  });

  testWidgets('SemyaSwitcher renders pill with current семя name',
      (tester) async {
    final service = _FakeSemyaService(semyi: [
      _semya(id: 's1', name: 'Семья Ивановых'),
    ]);
    final controller = SemyaListController(service: service);
    await tester.pumpWidget(_wrapWithController(controller));
    await tester.pumpAndSettle();
    expect(find.text('Семья Ивановых'), findsOneWidget);
    expect(find.byIcon(Icons.family_restroom), findsOneWidget);
  });

  testWidgets(
    'SemyaSwitcher opens bottom sheet on tap, shows list + create button',
    (tester) async {
      final service = _FakeSemyaService(semyi: [
        _semya(id: 's1', name: 'A'),
        _semya(id: 's2', name: 'B'),
      ]);
      final controller = SemyaListController(service: service);
      await tester.pumpWidget(_wrapWithController(controller));
      await tester.pumpAndSettle();

      // Pill displays first семя (no auto-select since 2 entries — uses first)
      await tester.tap(find.byType(SemyaSwitcher));
      await tester.pumpAndSettle();

      // Sheet renders «Мои семьи» header + both rows + disabled CTA
      expect(find.text('Мои семьи'), findsOneWidget);
      expect(find.text('A'), findsWidgets);
      expect(find.text('B'), findsOneWidget);

      // «Создать семью» button rendered + disabled
      final createButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Создать семью'),
      );
      expect(createButton.onPressed, isNull, reason: 'Create disabled в Ship FE1');
    },
  );

  testWidgets('Tapping семя row in sheet selects + closes sheet',
      (tester) async {
    final service = _FakeSemyaService(semyi: [
      _semya(id: 's1', name: 'A'),
      _semya(id: 's2', name: 'B'),
    ]);
    final controller = SemyaListController(service: service);
    await tester.pumpWidget(_wrapWithController(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SemyaSwitcher));
    await tester.pumpAndSettle();
    expect(find.text('Мои семьи'), findsOneWidget);

    // Tap the row для семья B
    final tileB = find.ancestor(
      of: find.text('B'),
      matching: find.byType(ListTile),
    );
    await tester.tap(tileB);
    await tester.pumpAndSettle();

    // Sheet closed
    expect(find.text('Мои семьи'), findsNothing);
    // Selection updated в controller
    expect(controller.selectedSemyaId, 's2');
  });
}

Semya _semya({
  required String id,
  String name = 'Тестовая',
}) {
  return Semya(
    id: id,
    name: name,
    ownerId: 'user-1',
    treeId: 'tree-$id',
    createdAt: '2026-05-22T00:00:00.000Z',
    updatedAt: '2026-05-22T00:00:00.000Z',
  );
}

Widget _wrapWithController(SemyaListController controller) {
  return MaterialApp(
    home: ChangeNotifierProvider.value(
      value: controller,
      child: const Scaffold(
        body: Center(
          child: SemyaSwitcher(),
        ),
      ),
    ),
  );
}

class _FakeSemyaService implements SemyaCapableFamilyTreeService {
  _FakeSemyaService({required this.semyi});

  final List<Semya> semyi;

  @override
  Future<List<Semya>> listMySemya() async => semyi;

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
}
