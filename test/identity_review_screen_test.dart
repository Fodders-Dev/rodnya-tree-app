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

  testWidgets('K1: шапка не переполняется на 360dp (заголовок + чип)',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    getIt.registerSingleton<IdentityServiceInterface>(
      _FakeIdentityService(proposals: [_proposal()], claims: [_claim()]),
    );

    await tester.pumpWidget(
      const MaterialApp(home: IdentityReviewScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Раньше Text + Spacer + чип давали RenderFlex-полосу на Samsung.
    expect(tester.takeException(), isNull);
    expect(find.text('2 на проверку'), findsOneWidget);
  });

  testWidgets(
      'K1: проголосованное уходит в «Ждём других» со статусами, не как актив',
      (tester) async {
    getIt.registerSingleton<IdentityServiceInterface>(
      _FakeIdentityService(proposals: [_votedProposal()]),
    );

    await tester.pumpWidget(
      const MaterialApp(home: IdentityReviewScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Не актив: кнопок решения нет, чип шапки не считает проголосованное.
    expect(find.text('Это один человек — объединить'), findsNothing);
    expect(find.text('1 на проверку'), findsNothing);
    // Отдельная секция со статусом по именам.
    expect(find.text('Ждём других'), findsOneWidget);
    expect(find.text('Вы'), findsOneWidget);
    expect(find.text('Наталья — ждём'), findsOneWidget);
    expect(
      find.textContaining('Ваш голос «объединить» учтён'),
      findsOneWidget,
    );
  });

  testWidgets('K1: активная карточка показывает, чьего решения ждём',
      (tester) async {
    getIt.registerSingleton<IdentityServiceInterface>(
      _FakeIdentityService(proposals: [_awaitingProposalWithReviewers()]),
    );

    await tester.pumpWidget(
      const MaterialApp(home: IdentityReviewScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Вы — ждём'), findsOneWidget);
    expect(find.text('Наталья — ждём'), findsOneWidget);
    // Безликий «X/Y согласовано» больше не показывается при именах.
    expect(find.textContaining('согласовано'), findsNothing);
  });
}

MergeProposal _votedProposal() {
  return MergeProposal(
    id: 'proposal-voted',
    status: 'pending',
    matchScore: 0.82,
    confidence: 'high',
    reasons: const ['Совпадает имя'],
    personA: const MergePersonPreview(name: 'Иван Петров', birthYear: '1950'),
    personB: const MergePersonPreview(
      name: 'Пётр Иванович',
      birthYear: '1950',
    ),
    requiredReviewCount: 2,
    reviewCount: 1,
    myDecision: 'accepted',
    awaitingMyDecision: false,
    reviewers: const [
      MergeReviewer(
        userId: 'user-1',
        displayName: 'Артём',
        decision: 'accepted',
        isViewer: true,
      ),
      MergeReviewer(userId: 'user-2', displayName: 'Наталья'),
    ],
    createdAt: DateTime(2026, 5, 1),
  );
}

MergeProposal _awaitingProposalWithReviewers() {
  return MergeProposal(
    id: 'proposal-awaiting',
    status: 'pending',
    matchScore: 0.82,
    confidence: 'high',
    reasons: const ['Совпадает имя'],
    personA: const MergePersonPreview(name: 'Иван Петров', birthYear: '1950'),
    personB: const MergePersonPreview(
      name: 'Пётр Иванович',
      birthYear: '1950',
    ),
    requiredReviewCount: 2,
    reviewCount: 0,
    awaitingMyDecision: true,
    reviewers: const [
      MergeReviewer(userId: 'user-1', displayName: 'Артём', isViewer: true),
      MergeReviewer(userId: 'user-2', displayName: 'Наталья'),
    ],
    createdAt: DateTime(2026, 5, 1),
  );
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
