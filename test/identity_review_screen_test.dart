import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:rodnya/backend/interfaces/auth_service_interface.dart';
import 'package:rodnya/backend/interfaces/identity_service_interface.dart';
import 'package:rodnya/models/identity_claim.dart';
import 'package:rodnya/models/merge_proposal.dart';
import 'package:rodnya/screens/identity_review_screen.dart';

class _FakeAuthService implements AuthServiceInterface {
  @override
  String? get currentUserId => 'user-1';

  @override
  String? get currentUserEmail => 'codex@rodnya.dev';

  @override
  String? get currentUserDisplayName => 'Codex';

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

class _FakeIdentityService implements IdentityServiceInterface {
  _FakeIdentityService({
    this.proposals = const <MergeProposal>[],
    this.claims = const <IdentityClaim>[],
  });

  List<MergeProposal> proposals;
  List<IdentityClaim> claims;
  String? reviewedProposalId;
  bool? reviewedProposalAccepted;
  String? reviewedClaimId;
  bool? reviewedClaimApproved;
  bool discoverability = false;

  @override
  Future<List<MergeProposal>> getPendingMergeProposals() async => proposals;

  @override
  Future<List<IdentityClaim>> getPendingIdentityClaims() async => claims;

  @override
  Future<MergeProposal> reviewMergeProposal(
    String proposalId, {
    required bool accept,
    String? reason,
  }) async {
    reviewedProposalId = proposalId;
    reviewedProposalAccepted = accept;
    final source =
        proposals.firstWhere((proposal) => proposal.id == proposalId);
    return MergeProposal(
      id: source.id,
      status: accept ? 'accepted' : 'rejected',
      matchScore: source.matchScore,
      confidence: source.confidence,
      reasons: source.reasons,
      personA: source.personA,
      personB: source.personB,
      requiredReviewCount: source.requiredReviewCount,
      reviewCount: source.reviewCount + 1,
      createdAt: source.createdAt,
      resolvedAt: DateTime(2026, 5, 1),
    );
  }

  @override
  Future<IdentityClaim> reviewIdentityClaim(
    String claimId, {
    required bool approve,
    String? reason,
  }) async {
    reviewedClaimId = claimId;
    reviewedClaimApproved = approve;
    return claims.firstWhere((claim) => claim.id == claimId);
  }

  @override
  Future<bool> setPublicDiscoverability(bool enabled) async {
    discoverability = enabled;
    return discoverability;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final getIt = GetIt.instance;

  setUp(() async {
    await getIt.reset();
    getIt.registerSingleton<AuthServiceInterface>(_FakeAuthService());
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('IdentityReviewScreen shows safe A/B merge comparison',
      (tester) async {
    final identityService = _FakeIdentityService(
      proposals: [_proposal()],
      claims: [_claim()],
    );
    getIt.registerSingleton<IdentityServiceInterface>(identityService);

    await tester.pumpWidget(
      const MaterialApp(home: IdentityReviewScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Один человек?'), findsOneWidget);
    expect(find.text('2 на проверку'), findsOneWidget);
    expect(find.text('Совпадение по 2 признакам'), findsOneWidget);
    expect(find.text('Иван Петров'), findsWidgets);
    expect(find.text('Пётр Иванович'), findsWidgets);
    expect(find.text('Что совпадает'), findsOneWidget);
    expect(find.text('Год рождения'), findsOneWidget);
    expect(find.text('Это один человек — объединить'), findsOneWidget);
    expect(find.text('Разные люди'), findsOneWidget);
    expect(find.text('Решу позже'), findsOneWidget);
    expect(find.textContaining('tree-secret'), findsNothing);
    expect(find.textContaining('person-secret'), findsNothing);
    expect(find.textContaining('reviewer-secret'), findsNothing);

    final differentButton = find.widgetWithText(OutlinedButton, 'Разные люди');
    await tester.ensureVisible(differentButton);
    await tester.pumpAndSettle();
    await tester.tap(differentButton);
    await tester.pump();

    expect(identityService.reviewedProposalId, 'proposal-1');
    expect(identityService.reviewedProposalAccepted, isFalse);
  });

  testWidgets('IdentityReviewScreen keeps polished empty state',
      (tester) async {
    getIt.registerSingleton<IdentityServiceInterface>(_FakeIdentityService());

    await tester.pumpWidget(
      const MaterialApp(home: IdentityReviewScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Ничего не требует решения'), findsOneWidget);
    expect(find.text('Нет совпадений на проверку'), findsOneWidget);
    expect(find.text('Нет запросов личности'), findsOneWidget);
    expect(find.text('Вернуться назад'), findsOneWidget);
  });
}

MergeProposal _proposal() {
  return MergeProposal(
    id: 'proposal-1',
    status: 'pending',
    matchScore: 0.82,
    confidence: 'high',
    reasons: const ['Совпадает имя', 'Совпадает год рождения'],
    personA: const MergePersonPreview(
      name: 'Иван Петров',
      birthYear: '1950',
      contextLabel: 'Доступное семейное дерево',
    ),
    personB: const MergePersonPreview(
      name: 'Пётр Иванович',
      birthYear: '1950',
      contextLabel: 'Контекст скрыт настройками',
    ),
    requiredReviewCount: 2,
    reviewCount: 1,
    createdAt: DateTime(2026, 5, 1),
  );
}

IdentityClaim _claim() {
  return IdentityClaim(
    id: 'claim-1',
    identityId: 'identity-secret',
    personId: 'person-secret',
    claimantUserId: 'reviewer-secret',
    status: 'pending',
    createdAt: DateTime(2026, 5, 1),
  );
}
