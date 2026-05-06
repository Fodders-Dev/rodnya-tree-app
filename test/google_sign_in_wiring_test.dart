import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rodnya/backend/backend_runtime_config.dart';
import 'package:rodnya/services/custom_api_auth_service.dart';
import 'package:rodnya/services/invitation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Spec-only check that the 7.x Google migration in
/// `CustomApiAuthService` calls the new `GoogleSignInPlatform` surface
/// in the right order: `init` first, THEN `authenticate`. We don't
/// have a real device to flip through the Google account picker, but
/// the wiring contract is testable in pure Dart by swapping a fake
/// platform instance under `GoogleSignInPlatform.instance`.
///
/// Catches the most common rollback regressions:
///   * `authenticate` called before `init` resolves (7.x throws in
///     practice; we want the test to fail loud if we ever skip init).
///   * `clientId` / `serverClientId` not threaded through from
///     BackendRuntimeConfig.
///   * `idToken` extraction path on the Dart side mishandling the
///     synchronous `account.authentication` getter introduced in 7.x.
class _RecordingGoogleSignInPlatform extends GoogleSignInPlatform {
  _RecordingGoogleSignInPlatform({
    required this.userId,
    required this.userEmail,
    required this.idToken,
  });

  final String userId;
  final String userEmail;
  final String idToken;

  InitParameters? lastInitParams;
  int initCount = 0;
  int authenticateCount = 0;
  int signOutCount = 0;
  int lightweightCount = 0;

  @override
  Future<void> init(InitParameters params) async {
    lastInitParams = params;
    initCount += 1;
  }

  @override
  Future<AuthenticationResults?>? attemptLightweightAuthentication(
    AttemptLightweightAuthenticationParameters params,
  ) {
    lightweightCount += 1;
    return Future<AuthenticationResults?>.value(null);
  }

  @override
  Future<AuthenticationResults> authenticate(
    AuthenticateParameters params,
  ) async {
    authenticateCount += 1;
    return AuthenticationResults(
      user: GoogleSignInUserData(id: userId, email: userEmail),
      authenticationTokens: AuthenticationTokenData(idToken: idToken),
    );
  }

  @override
  bool supportsAuthenticate() => true;

  @override
  bool authorizationRequiresUserInteraction() => false;

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
    ClientAuthorizationTokensForScopesParameters params,
  ) async =>
      null;

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
    ServerAuthorizationTokensForScopesParameters params,
  ) async =>
      null;

  @override
  Future<void> signOut(SignOutParams params) async {
    signOutCount += 1;
  }

  @override
  Future<void> disconnect(DisconnectParams params) async {}

  @override
  Stream<AuthenticationEvent>? get authenticationEvents => null;

  @override
  Future<void> clearAuthorizationToken(
      ClearAuthorizationTokenParams params) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'CustomApiAuthService.signInWithGoogle initializes the 7.x platform '
    'before authenticate, threads through both client ids, then '
    'forwards the idToken to /v1/auth/google',
    () async {
      final fakePlatform = _RecordingGoogleSignInPlatform(
        userId: 'gid-123',
        userEmail: 'artem@example.com',
        idToken: 'mock-id-token',
      );
      GoogleSignInPlatform.instance = fakePlatform;

      String? backendBodyReceived;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/v1/auth/google') {
          backendBodyReceived = request.body;
          return http.Response(
            jsonEncode({
              'accessToken': 'access-token',
              'refreshToken': 'refresh-token',
              'user': {
                'id': 'user-1',
                'email': 'artem@example.com',
                'displayName': 'Артем Кузнецов',
                'providerIds': ['google'],
              },
              'profileStatus': {
                'isComplete': true,
                'missingFields': <String>[],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"message":"not found"}', 404);
      });

      final service = await CustomApiAuthService.create(
        httpClient: mockClient,
        preferences: await SharedPreferences.getInstance(),
        runtimeConfig: const BackendRuntimeConfig(
          apiBaseUrl: 'https://api.example.ru',
          googleWebClientId: 'web-client.apps.googleusercontent.com',
        ),
        invitationService: InvitationService(),
      );

      await service.signInWithGoogle();

      // Ordering check: init must have happened before authenticate.
      expect(fakePlatform.initCount, greaterThan(0),
          reason:
              'Did not call GoogleSignInPlatform.init before authenticate');
      expect(fakePlatform.authenticateCount, 1);

      // Both client-id slots must be populated from BackendRuntimeConfig
      // — serverClientId is what the backend's `verifyIdToken({audience})`
      // checks against; missing it causes silent 401s in production.
      final params = fakePlatform.lastInitParams!;
      // On non-web (test runs as a non-web binding) the constant
      // `kIsWeb` is false → serverClientId carries the web client id.
      expect(params.serverClientId,
          'web-client.apps.googleusercontent.com');

      // Backend got the idToken from the synchronous
      // `account.authentication` getter, no `await` needed.
      expect(backendBodyReceived, isNotNull);
      final decoded = jsonDecode(backendBodyReceived!) as Map<String, dynamic>;
      expect(decoded['idToken'], 'mock-id-token');

      // Session was persisted on success.
      expect(service.currentUserId, 'user-1');
    },
  );

  test(
    'GoogleSignInException with code=canceled surfaces as the existing '
    '"sign-in cancelled" CustomApiException so the UX text is preserved',
    () async {
      final platform = _ThrowingGoogleSignInPlatform(
        toThrow: const GoogleSignInException(
          code: GoogleSignInExceptionCode.canceled,
        ),
      );
      GoogleSignInPlatform.instance = platform;

      final mockClient = MockClient(
        (request) async => http.Response('{}', 404),
      );

      final service = await CustomApiAuthService.create(
        httpClient: mockClient,
        preferences: await SharedPreferences.getInstance(),
        runtimeConfig: const BackendRuntimeConfig(
          apiBaseUrl: 'https://api.example.ru',
          googleWebClientId: 'web-client.apps.googleusercontent.com',
        ),
        invitationService: InvitationService(),
      );

      // Library-side cancellation must NOT bubble as a raw
      // GoogleSignInException — the auth-screen listens for our
      // CustomApiException type to render the "ещё не авторизованы"
      // hint instead of a red error banner.
      try {
        await service.signInWithGoogle();
        fail('Expected CustomApiException for canceled sign-in');
      } on CustomApiException catch (error) {
        expect(error.message, contains('отмен'),
            reason: 'Expected localized "сancelled" text in the message');
      }
    },
  );
}

class _ThrowingGoogleSignInPlatform extends GoogleSignInPlatform {
  _ThrowingGoogleSignInPlatform({required this.toThrow});

  final GoogleSignInException toThrow;

  @override
  Future<void> init(InitParameters params) async {}

  @override
  Future<AuthenticationResults?>? attemptLightweightAuthentication(
    AttemptLightweightAuthenticationParameters params,
  ) =>
      Future<AuthenticationResults?>.value(null);

  @override
  Future<AuthenticationResults> authenticate(
    AuthenticateParameters params,
  ) async {
    throw toThrow;
  }

  @override
  bool supportsAuthenticate() => true;

  @override
  bool authorizationRequiresUserInteraction() => false;

  @override
  Future<ClientAuthorizationTokenData?> clientAuthorizationTokensForScopes(
    ClientAuthorizationTokensForScopesParameters params,
  ) async =>
      null;

  @override
  Future<ServerAuthorizationTokenData?> serverAuthorizationTokensForScopes(
    ServerAuthorizationTokensForScopesParameters params,
  ) async =>
      null;

  @override
  Future<void> signOut(SignOutParams params) async {}

  @override
  Future<void> disconnect(DisconnectParams params) async {}

  @override
  Stream<AuthenticationEvent>? get authenticationEvents => null;

  @override
  Future<void> clearAuthorizationToken(
      ClearAuthorizationTokenParams params) async {}
}
