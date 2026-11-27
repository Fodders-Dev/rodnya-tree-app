import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:rodnya/backend/interfaces/auth_service_interface.dart';
import 'package:rodnya/backend/interfaces/family_tree_service_interface.dart';
import 'package:rodnya/backend/interfaces/profile_service_interface.dart';
import 'package:rodnya/models/family_relation.dart';
import 'package:rodnya/models/relation_request.dart';
import 'package:rodnya/models/user_profile.dart';
import 'package:rodnya/screens/relation_requests_screen.dart';

class _FakeAuthService implements AuthServiceInterface {
  @override
  String? get currentUserId => 'user-1';

  @override
  String? get currentUserEmail => 'user1@rodnya.app';

  @override
  String? get currentUserDisplayName => 'Артём';

  @override
  String? get currentUserPhotoUrl => null;

  @override
  List<String> get currentProviderIds => const ['password'];

  @override
  Stream<String?> get authStateChanges => const Stream<String?>.empty();

  @override
  String describeError(Object error) => error.toString();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfileService implements ProfileServiceInterface {
  _FakeProfileService(this.profiles);

  final Map<String, UserProfile> profiles;

  @override
  Future<UserProfile?> getUserProfile(String userId) async => profiles[userId];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFamilyTreeService implements FamilyTreeServiceInterface {
  _FakeFamilyTreeService({
    required this.incoming,
    required this.outgoing,
  });

  List<RelationRequest> incoming;
  List<RelationRequest> outgoing;
  String? canceledRequestId;

  @override
  Future<List<RelationRequest>> getPendingRelationRequests({
    String? treeId,
  }) async =>
      incoming;

  @override
  Future<List<RelationRequest>> getSentRelationRequests({
    String? treeId,
  }) async =>
      outgoing;

  @override
  Future<void> cancelRelationRequest(String requestId) async {
    canceledRequestId = requestId;
    outgoing =
        outgoing.where((item) => item.id != requestId).toList(growable: false);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final getIt = GetIt.instance;

  setUp(() async {
    await getIt.reset();
    getIt.registerSingleton<AuthServiceInterface>(_FakeAuthService());
    getIt.registerSingleton<ProfileServiceInterface>(
      _FakeProfileService({
        'user-sender': UserProfile(
          id: 'user-sender',
          email: 'sender@rodnya.app',
          displayName: 'Мария Петрова',
          firstName: 'Мария',
          lastName: 'Петрова',
          middleName: '',
          username: 'maria',
          phoneNumber: '',
          createdAt: DateTime(2026, 1, 1),
        ),
        'user-recipient': UserProfile(
          id: 'user-recipient',
          email: 'rec@rodnya.app',
          displayName: 'Дмитрий Иванов',
          firstName: 'Дмитрий',
          lastName: 'Иванов',
          middleName: '',
          username: 'dima',
          phoneNumber: '',
          createdAt: DateTime(2026, 1, 1),
        ),
      }),
    );
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets(
      'RelationRequestsScreen switches to outgoing tab and cancels sent request',
      (tester) async {
    final treeService = _FakeFamilyTreeService(
      incoming: [
        RelationRequest(
          id: 'in-1',
          treeId: 'tree-1',
          senderId: 'user-sender',
          recipientId: 'user-1',
          senderToRecipient: RelationType.sibling,
          createdAt: DateTime(2026, 6, 1),
        ),
      ],
      outgoing: [
        RelationRequest(
          id: 'out-1',
          treeId: 'tree-1',
          senderId: 'user-1',
          recipientId: 'user-recipient',
          senderToRecipient: RelationType.cousin,
          createdAt: DateTime(2026, 6, 2),
          message: 'Проверьте, пожалуйста',
        ),
      ],
    );
    getIt.registerSingleton<FamilyTreeServiceInterface>(treeService);

    await tester.pumpWidget(
      const MaterialApp(
        home: RelationRequestsScreen(treeId: 'tree-1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Мария Петрова'), findsOneWidget);
    expect(find.byKey(const Key('relation-requests-incoming-tab')),
        findsOneWidget);
    expect(find.byKey(const Key('relation-requests-outgoing-tab')),
        findsOneWidget);

    await tester.tap(find.byKey(const Key('relation-requests-outgoing-tab')));
    await tester.pumpAndSettle();

    expect(find.text('Дмитрий Иванов'), findsOneWidget);
    expect(
        find.byKey(const Key('relation-request-cancel-out-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('relation-request-cancel-out-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('relation-request-cancel-confirm')));
    await tester.pumpAndSettle();

    expect(treeService.canceledRequestId, 'out-1');
    expect(find.text('Дмитрий Иванов'), findsNothing);
    expect(find.text('Нет отправленных запросов'), findsOneWidget);
  });
}
