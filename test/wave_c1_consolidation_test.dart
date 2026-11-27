import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:rodnya/backend/interfaces/auth_service_interface.dart';
import 'package:rodnya/backend/interfaces/family_tree_service_interface.dart';
import 'package:rodnya/backend/interfaces/onboarding_capable_family_tree_service.dart';
import 'package:rodnya/backend/interfaces/profile_article_service_interface.dart';
import 'package:rodnya/backend/interfaces/semya_capable_family_tree_service.dart';
import 'package:rodnya/backend/models/deleted_person.dart';
import 'package:rodnya/backend/models/deleted_post.dart';
import 'package:rodnya/backend/models/onboarding_state.dart';
import 'package:rodnya/backend/models/profile_article.dart';
import 'package:rodnya/backend/models/semya.dart';
import 'package:rodnya/backend/models/semya_browse_token.dart';
import 'package:rodnya/backend/models/semya_invitation.dart';
import 'package:rodnya/backend/models/semya_pull_person_result.dart';
import 'package:rodnya/navigation/app_overlay_route_module.dart';
import 'package:rodnya/navigation/app_router_shared.dart';
import 'package:rodnya/screens/onboarding/onboarding_wizard_screen.dart';
import 'package:rodnya/screens/profile_article_editor_screen.dart';
import 'package:rodnya/screens/semya_details_screen.dart';
import 'package:rodnya/screens/trash_screen.dart';

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

class _FakeTreeAndSemyaService
    implements
        FamilyTreeServiceInterface,
        OnboardingCapableFamilyTreeService,
        SemyaCapableFamilyTreeService {
  @override
  Future<OnboardingState?> getOnboardingState() async => null;

  @override
  Future<OnboardingSeedResult?> seedOnboarding({
    required OnboardingSeedPayload payload,
  }) async =>
      const OnboardingSeedResult(
        treeId: 't-1',
        personIds: ['p-1'],
        idempotent: false,
      );

  @override
  Future<OnboardingState?> updateOnboardingState({
    required OnboardingStep currentStep,
  }) async =>
      null;

  @override
  Future<OnboardingState?> skipOnboarding() async => null;

  @override
  Future<List<SemyaInvitation>> listPendingInvitations() async =>
      const <SemyaInvitation>[];

  @override
  Future<SemyaDetails?> findSemyaById(String semyaId) async => null;

  @override
  Future<List<DeletedPerson>> listMyDeletedPersons() async =>
      const <DeletedPerson>[];

  @override
  Future<List<DeletedPost>> listMyDeletedPosts() async => const <DeletedPost>[];

  @override
  Future<List<DeletedPerson>> listDeletedPersonsForSemya(
          String semyaId) async =>
      const <DeletedPerson>[];

  @override
  Future<void> restoreDeletedPerson(String deletedPersonId) async {}

  @override
  Future<void> permanentlyDeletePerson(String deletedPersonId) async {}

  @override
  Future<void> restoreDeletedPost(String deletedPostId) async {}

  @override
  Future<void> permanentlyDeletePost(String deletedPostId) async {}

  @override
  Future<List<Semya>> listMySemya() async => const <Semya>[];

  @override
  Future<List<SemyaMembership>> listMembershipsForSemya(String semyaId) async =>
      const <SemyaMembership>[];

  @override
  Future<SemyaInvitation> createInvitation({
    required String semyaId,
    required SemyaRole role,
    String? recipientEmail,
    String? recipientPhone,
    String? recipientUserId,
    String? personId,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<SemyaInvitation>> listInvitationsForSemya(String semyaId) async =>
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

  @override
  Future<SemyaBrowseToken> createBrowseToken({
    required String semyaId,
    int? expiresInDays,
  }) async =>
      throw UnimplementedError();

  @override
  Future<BrowsedSemyaTree> fetchBrowseTree(String token) async =>
      throw UnimplementedError();

  @override
  Future<List<SemyaBrowseTokenSummary>> listBrowseTokens({
    required String semyaId,
  }) async =>
      throw UnimplementedError();

  @override
  Future<SemyaBrowseTokenSummary> revokeBrowseToken({
    required String semyaId,
    required String tokenId,
  }) async =>
      throw UnimplementedError();

  @override
  Future<List<String>> listHiddenPersonIds({required String semyaId}) async =>
      const <String>[];

  @override
  Future<List<String>> updateHideFilter({
    required String semyaId,
    List<String> addPersonIds = const <String>[],
    List<String> removePersonIds = const <String>[],
  }) async =>
      throw UnimplementedError();

  @override
  Future<SemyaMembership> updateMembership({
    required String semyaId,
    required String userId,
    SemyaRole? role,
    bool? hasInviteGrant,
  }) async =>
      throw UnimplementedError();

  @override
  Future<SemyaMembership> addMembership({
    required String semyaId,
    required String userId,
    required SemyaRole role,
    bool hasInviteGrant = false,
  }) async =>
      throw UnimplementedError();

  @override
  Future<SemyaMembershipRemoveResult> removeMembership({
    required String semyaId,
    required String userId,
  }) async =>
      throw UnimplementedError();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeArticleService implements ProfileArticleServiceInterface {
  @override
  Future<ProfileArticle> getArticle(String personId) async => ProfileArticle(
        personId: personId,
        blocks: const <ArticleBlock>[],
        updatedAt: '2026-06-01T00:00:00.000Z',
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

GoRouter _buildOverlayRouter(String initialLocation) {
  final auth = _FakeAuthService();
  final overlayRoutes = AppOverlayRouteModule(authService: auth).build();
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: '/profile',
        builder: (context, state) => Text(
          'profile-edit=${state.uri.queryParameters['edit']}',
        ),
      ),
      ...overlayRoutes,
    ],
  );
}

void main() {
  final getIt = GetIt.instance;

  setUp(() async {
    await getIt.reset();
    getIt.registerSingleton<AuthServiceInterface>(_FakeAuthService());
    getIt.registerSingleton<FamilyTreeServiceInterface>(
      _FakeTreeAndSemyaService(),
    );
    getIt.registerSingleton<ProfileArticleServiceInterface>(
      _FakeArticleService(),
    );
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets(
      'Wave C1: /onboarding redirects to /setup (OnboardingWizardScreen)',
      (tester) async {
    final router = _buildOverlayRouter('/onboarding');
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingWizardScreen), findsOneWidget);
  });

  testWidgets('Wave C1: /complete_profile redirects to /profile?edit=1',
      (tester) async {
    final router = _buildOverlayRouter('/complete_profile?requiredFields=x');
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('profile-edit=1'), findsOneWidget);
  });

  testWidgets(
      'Wave C1: /semya/:semyaId, /profile/trash, and /relative/details/:id/biography resolve via GoRouter',
      (tester) async {
    final router = _buildOverlayRouter('/semya/semya-99?section=hidden');
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.byType(SemyaDetailsScreen), findsOneWidget);

    router.go('/profile/trash?semyaId=semya-99&semyaName=Соколовых');
    await tester.pumpAndSettle();
    expect(find.byType(TrashScreen), findsOneWidget);
    expect(find.text('Удалённые · Соколовых'), findsOneWidget);

    router.go('/relative/details/p-42/biography?name=Иван');
    await tester.pumpAndSettle();
    expect(find.byType(ProfileArticleEditorScreen), findsOneWidget);
  });

  testWidgets(
      'Wave C1: OnboardingWizardScreen profile step exposes optional birth date picker & clear',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: OnboardingWizardScreen()),
    );
    await tester.pumpAndSettle();

    // Advance Welcome -> Profile step.
    await tester.tap(find.byKey(const Key('onboarding-create-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('onboarding-birth-date-btn')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const Key('onboarding-birth-date-btn')),
    );
    await tester.tap(find.byKey(const Key('onboarding-birth-date-btn')));
    await tester.pumpAndSettle();

    // Confirm default date in showDatePicker.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(
        find.byKey(const Key('onboarding-birth-date-clear')), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboarding-birth-date-clear')));
    await tester.pumpAndSettle();

    expect(find.text('Указать дату рождения'), findsOneWidget);
  });
}
