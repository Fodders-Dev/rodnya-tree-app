import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/family_tree_service_interface.dart';
import 'package:rodnya/backend/interfaces/graph_person_access_capable_family_tree_service.dart';
import 'package:rodnya/backend/interfaces/profile_service_interface.dart';
import 'package:rodnya/backend/models/edit_grant.dart';
import 'package:rodnya/backend/models/visibility_choice.dart';
import 'package:rodnya/models/user_profile.dart';
import 'package:rodnya/widgets/grant_edit_access_sheet.dart';

class _FakeAccessService
    implements
        FamilyTreeServiceInterface,
        GraphPersonAccessCapableFamilyTreeService {
  _FakeAccessService({this.grants = const <EditGrant>[]});

  final List<EditGrant> grants;
  final List<Map<String, dynamic>> added = <Map<String, dynamic>>[];
  final List<String> revokedIds = <String>[];

  @override
  Future<List<EditGrant>> listGraphPersonGrants({
    required String graphPersonId,
  }) async =>
      List<EditGrant>.from(grants);

  @override
  Future<EditGrant> addGraphPersonGrant({
    required String graphPersonId,
    required String granteeUserId,
    required EditGrantScope scope,
  }) async {
    added.add(<String, dynamic>{
      'graphPersonId': graphPersonId,
      'granteeUserId': granteeUserId,
      'scope': scope,
    });
    return EditGrant(
      id: 'grant-new-${added.length}',
      graphPersonId: graphPersonId,
      grantorUserId: 'me',
      granteeUserId: granteeUserId,
      scope: scope,
      grantedAt: '2026-11-27T10:00:00Z',
    );
  }

  @override
  Future<EditGrant> revokeGraphPersonGrant({
    required String graphPersonId,
    required String grantId,
  }) async {
    revokedIds.add(grantId);
    final match = grants.firstWhere((g) => g.id == grantId);
    return EditGrant(
      id: match.id,
      graphPersonId: match.graphPersonId,
      grantorUserId: match.grantorUserId,
      granteeUserId: match.granteeUserId,
      scope: match.scope,
      grantedAt: match.grantedAt,
      revokedAt: '2026-11-27T10:05:00Z',
    );
  }

  @override
  Future<List<EditGrant>> listMyEditGrants() async => const [];

  @override
  Future<List<EditGrant>> listMyIssuedGrants() async => const [];

  @override
  Future<EditGrant> relinquishMyEditGrant({required String grantId}) async =>
      throw UnimplementedError();

  @override
  Future<GraphPersonAccessSnapshot?> getGraphPersonAccessSnapshot({
    required String graphPersonId,
  }) async =>
      null;

  @override
  Future<GraphPersonVisibility> setGraphPersonVisibility({
    required String graphPersonId,
    required VisibilityChoice choice,
  }) async =>
      throw UnimplementedError();

  @override
  Future<GraphPersonVisibility> clearGraphPersonVisibilityOverride({
    required String graphPersonId,
  }) async =>
      throw UnimplementedError();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfileService implements ProfileServiceInterface {
  @override
  Future<List<UserProfile>> searchUsers(String query, {int limit = 20}) async {
    if (query.toLowerCase().contains('мария')) {
      return <UserProfile>[
        UserProfile(
          id: 'u-search',
          email: 'maria@example.ru',
          displayName: 'Мария Соколова',
          username: 'maria',
          phoneNumber: '',
          createdAt: DateTime(2026, 1, 1),
        ),
      ];
    }
    return const <UserProfile>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
      'GrantEditAccessSheet loads grants, revokes existing, searches user, and submits grant',
      (tester) async {
    final accessService = _FakeAccessService(
      grants: const <EditGrant>[
        EditGrant(
          id: 'g-existing',
          graphPersonId: 'gp-1',
          grantorUserId: 'me',
          granteeUserId: 'u-old',
          scope: EditGrantScope.edit,
          grantedAt: '2026-11-26T10:00:00Z',
          grantee: GrantPreviewSubject(id: 'u-old', displayName: 'Павел'),
        ),
      ],
    );
    final profileService = _FakeProfileService();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showGrantEditAccessSheet(
                context,
                accessService: accessService,
                viewerUserId: 'me',
                initialGraphPersonId: 'gp-1',
                initialPersonName: 'Иван Петров',
                initialGranteeCandidates: const <GrantPreviewSubject>[
                  GrantPreviewSubject(id: 'u-2', displayName: 'Алиса'),
                ],
                profileService: profileService,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Павел'), findsOneWidget);
    await tester.tap(find.byKey(const Key('grant-sheet-revoke-g-existing')));
    await tester.pumpAndSettle();
    expect(accessService.revokedIds, ['g-existing']);

    await tester.enterText(
      find.byKey(const Key('grant-sheet-search-input')),
      'Мария',
    );
    await tester.pumpAndSettle();

    final mariaTile = find.byKey(const Key('grant-sheet-grantee-u-search'));
    expect(mariaTile, findsOneWidget);
    await tester.tap(mariaTile);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('grant-sheet-scope-merge-consent')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('grant-sheet-submit')));
    await tester.pumpAndSettle();

    expect(accessService.added.length, 2);
    expect(accessService.added[0]['granteeUserId'], 'u-search');
    expect(
      accessService.added.map((e) => e['scope']).toSet(),
      {EditGrantScope.edit, EditGrantScope.mergeConsent},
    );
  });
}
