import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../backend/backend_runtime_config.dart';
import '../backend/interfaces/auth_service_interface.dart';
import '../backend/models/custom_api_session.dart';
import 'app_status_service.dart';
import 'invitation_service.dart';
import '../utils/url_utils.dart';

class CustomApiException implements Exception {
  const CustomApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class TelegramAuthCompletion {
  const TelegramAuthCompletion._({
    required this.status,
    this.linkCode,
    this.message,
    this.firstName,
    this.lastName,
    this.username,
    this.photoUrl,
  });

  const TelegramAuthCompletion.authenticated()
      : this._(status: TelegramAuthCompletionStatus.authenticated);

  const TelegramAuthCompletion.pendingLink({
    required String linkCode,
    String? message,
    String? firstName,
    String? lastName,
    String? username,
    String? photoUrl,
  }) : this._(
          status: TelegramAuthCompletionStatus.pendingLink,
          linkCode: linkCode,
          message: message,
          firstName: firstName,
          lastName: lastName,
          username: username,
          photoUrl: photoUrl,
        );

  const TelegramAuthCompletion.alreadyLinked({
    String? message,
  }) : this._(
          status: TelegramAuthCompletionStatus.alreadyLinked,
          message: message,
        );

  final TelegramAuthCompletionStatus status;
  final String? linkCode;
  final String? message;
  final String? firstName;
  final String? lastName;
  final String? username;
  final String? photoUrl;

  bool get isAuthenticated =>
      status == TelegramAuthCompletionStatus.authenticated;

  bool get isAlreadyLinked =>
      status == TelegramAuthCompletionStatus.alreadyLinked;
}

enum TelegramAuthCompletionStatus {
  authenticated,
  pendingLink,
  alreadyLinked,
}

class VkAuthCompletion {
  const VkAuthCompletion._({
    required this.status,
    this.linkCode,
    this.message,
    this.firstName,
    this.lastName,
    this.email,
    this.phoneNumber,
    this.photoUrl,
  });

  const VkAuthCompletion.authenticated()
      : this._(status: VkAuthCompletionStatus.authenticated);

  const VkAuthCompletion.pendingLink({
    required String linkCode,
    String? message,
    String? firstName,
    String? lastName,
    String? email,
    String? phoneNumber,
    String? photoUrl,
  }) : this._(
          status: VkAuthCompletionStatus.pendingLink,
          linkCode: linkCode,
          message: message,
          firstName: firstName,
          lastName: lastName,
          email: email,
          phoneNumber: phoneNumber,
          photoUrl: photoUrl,
        );

  const VkAuthCompletion.alreadyLinked({
    String? message,
  }) : this._(
          status: VkAuthCompletionStatus.alreadyLinked,
          message: message,
        );

  final VkAuthCompletionStatus status;
  final String? linkCode;
  final String? message;
  final String? firstName;
  final String? lastName;
  final String? email;
  final String? phoneNumber;
  final String? photoUrl;

  bool get isAuthenticated => status == VkAuthCompletionStatus.authenticated;

  bool get isAlreadyLinked => status == VkAuthCompletionStatus.alreadyLinked;
}

enum VkAuthCompletionStatus {
  authenticated,
  pendingLink,
  alreadyLinked,
}

class MaxAuthCompletion {
  const MaxAuthCompletion._({
    required this.status,
    this.linkCode,
    this.message,
    this.firstName,
    this.lastName,
    this.username,
    this.photoUrl,
  });

  const MaxAuthCompletion.authenticated()
      : this._(status: MaxAuthCompletionStatus.authenticated);

  const MaxAuthCompletion.pendingLink({
    required String linkCode,
    String? message,
    String? firstName,
    String? lastName,
    String? username,
    String? photoUrl,
  }) : this._(
          status: MaxAuthCompletionStatus.pendingLink,
          linkCode: linkCode,
          message: message,
          firstName: firstName,
          lastName: lastName,
          username: username,
          photoUrl: photoUrl,
        );

  const MaxAuthCompletion.alreadyLinked({
    String? message,
  }) : this._(
          status: MaxAuthCompletionStatus.alreadyLinked,
          message: message,
        );

  final MaxAuthCompletionStatus status;
  final String? linkCode;
  final String? message;
  final String? firstName;
  final String? lastName;
  final String? username;
  final String? photoUrl;

  bool get isAuthenticated => status == MaxAuthCompletionStatus.authenticated;

  bool get isAlreadyLinked => status == MaxAuthCompletionStatus.alreadyLinked;
}

enum MaxAuthCompletionStatus {
  authenticated,
  pendingLink,
  alreadyLinked,
}

class CustomApiAuthService implements AuthServiceInterface {
  static const String _defaultTelegramBotUsername = 'RodnyaFamilyBot';

  CustomApiAuthService._({
    required http.Client httpClient,
    required SharedPreferences preferences,
    required BackendRuntimeConfig runtimeConfig,
    required InvitationService invitationService,
    AppStatusService? appStatusService,
  })  : _httpClient = httpClient,
        _preferences = preferences,
        _runtimeConfig = runtimeConfig,
        _invitationService = invitationService,
        _appStatusService = appStatusService;

  static const _sessionStorageKey = 'custom_api_session_v1';

  final http.Client _httpClient;
  final SharedPreferences _preferences;
  final BackendRuntimeConfig _runtimeConfig;
  final InvitationService _invitationService;
  final AppStatusService? _appStatusService;
  final StreamController<String?> _authStateController =
      StreamController<String?>.broadcast();

  CustomApiSession? _session;
  bool _isRefreshing = false;
  Future<void>? _refreshTask;
  GoogleSignIn? _googleSignIn;

  static Future<CustomApiAuthService> create({
    http.Client? httpClient,
    SharedPreferences? preferences,
    BackendRuntimeConfig? runtimeConfig,
    InvitationService? invitationService,
    AppStatusService? appStatusService,
  }) async {
    final service = CustomApiAuthService._(
      httpClient: httpClient ?? http.Client(),
      preferences: preferences ?? await SharedPreferences.getInstance(),
      runtimeConfig: runtimeConfig ?? BackendRuntimeConfig.current,
      invitationService: invitationService ?? InvitationService(),
      appStatusService: appStatusService,
    );
    await service.restoreSession();
    return service;
  }

  String? get accessToken => _session?.accessToken;

  @override
  String? get currentUserId => _session?.userId;

  @override
  String? get currentUserEmail => _session?.email;

  @override
  String? get currentUserDisplayName => _session?.displayName;

  @override
  String? get currentUserPhotoUrl =>
      UrlUtils.normalizeImageUrl(_session?.photoUrl);

  @override
  List<String> get currentProviderIds => _session?.providerIds ?? const [];

  bool get isGoogleSignInConfigured =>
      _runtimeConfig.googleWebClientId.trim().isNotEmpty;

  Future<void> resetGoogleSelection() async {
    try {
      await _googleSignIn?.signOut();
    } catch (_) {}
  }

  @override
  Stream<String?> get authStateChanges => _authStateController.stream;

  Future<void> restoreSession() async {
    try {
      final rawValue = _preferences.getString(_sessionStorageKey);
      if (rawValue == null || rawValue.isEmpty) {
        _session = null;
        return;
      }

      final json = jsonDecode(rawValue);
      if (json is Map<String, dynamic>) {
        final session = CustomApiSession.fromJson(json);
        _session = session.userId.isEmpty ? null : session;
        if (_session != null) {
          _authStateController.add(_session!.userId);
        }
      }
    } catch (_) {
      _session = null;
      await _preferences.remove(_sessionStorageKey);
    }
  }

  Future<void>? refreshSession() async {
    if (_isRefreshing) {
      return _refreshTask;
    }

    final refreshToken = _session?.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      await _clearSession(sessionExpired: true);
      throw const CustomApiException('Нет refresh token для обновления сессии');
    }

    _isRefreshing = true;
    _refreshTask = _performRefresh(refreshToken);

    try {
      await _refreshTask;
    } finally {
      _isRefreshing = false;
      _refreshTask = null;
    }
  }

  Future<void> _performRefresh(String refreshToken) async {
    try {
      final response = await _httpClient.post(
        _buildUri('/v1/auth/refresh'),
        headers: _jsonHeaders(authenticated: false),
        body: jsonEncode({'refreshToken': refreshToken}),
      );

      if (response.statusCode == 401 || response.statusCode == 403) {
        await _clearSession(sessionExpired: true);
        throw const CustomApiException('Сессия истекла. Войдите заново.');
      }

      final body = _decodeResponse(response);
      final newSession = _sessionFromResponse(body);
      await _saveSession(newSession);
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<Object?> registerWithEmail({
    required String email,
    required String password,
    required String name,
  }) {
    return _authenticate(
      path: '/v1/auth/register',
      payload: {
        'email': email,
        'password': password,
        'displayName': name,
      },
    );
  }

  @override
  Future<Object?> loginWithEmail(String email, String password) {
    return _authenticate(
      path: '/v1/auth/login',
      payload: {
        'email': email,
        'password': password,
      },
    );
  }

  @override
  Future<Object?> signInWithGoogle() {
    if (!isGoogleSignInConfigured) {
      throw const CustomApiException(
        'Google sign-in не настроен. Нужен RODNYA_GOOGLE_WEB_CLIENT_ID.',
      );
    }

    return _signInWithResolvedGoogleAccount();
  }

  Future<void> linkGoogleIdentity() async {
    if (!isGoogleSignInConfigured) {
      throw const CustomApiException(
        'Google sign-in не настроен. Нужен RODNYA_GOOGLE_WEB_CLIENT_ID.',
      );
    }

    final account = await _resolveGoogleAccountForTokenExchange(
      interactiveCancelledMessage: 'Привязка Google отменена.',
    );
    final idToken = await _resolveGoogleIdToken(account);
    final response = await _requestJson(
      method: 'POST',
      path: '/v1/auth/google/link',
      authenticated: true,
      body: {
        'idToken': idToken,
      },
    );
    final userJson = _extractUserJson(response);
    final providerIds = (userJson['providerIds'] as List<dynamic>? ?? const [])
        .map((value) => value.toString())
        .toList();
    if (providerIds.isNotEmpty) {
      await updateCachedSession(providerIds: providerIds);
    }
  }

  Future<Object?> _signInWithResolvedGoogleAccount() async {
    final account = await _resolveGoogleAccountForTokenExchange(
      interactiveCancelledMessage: 'Вход через Google отменён.',
    );
    final idToken = await _resolveGoogleIdToken(account);
    return _authenticate(
      path: '/v1/auth/google',
      payload: {
        'idToken': idToken,
      },
    );
  }

  Future<GoogleSignInAccount> _resolveGoogleAccountForTokenExchange({
    required String interactiveCancelledMessage,
  }) async {
    final currentAccount = _googleClient.currentUser;
    if (currentAccount != null) {
      return currentAccount;
    }

    final account = await _googleClient.signIn();
    if (account == null) {
      throw CustomApiException(interactiveCancelledMessage);
    }
    return account;
  }

  Future<String> _resolveGoogleIdToken(GoogleSignInAccount account) async {
    final authentication = await account.authentication;
    final idToken = authentication.idToken?.trim() ?? '';
    if (idToken.isEmpty) {
      throw const CustomApiException(
        'Google не вернул idToken. Проверьте Web client ID и OAuth clients.',
      );
    }
    return idToken;
  }

  GoogleSignIn get _googleClient {
    return _googleSignIn ??= GoogleSignIn(
      scopes: const ['email'],
      clientId: kIsWeb ? _runtimeConfig.googleWebClientId : null,
      serverClientId: kIsWeb ? null : _runtimeConfig.googleWebClientId,
    );
  }

  String get telegramLoginStartUrl => buildTelegramStartUrl();

  String get telegramLinkStartUrl => buildTelegramStartUrl(linkMode: true);

  String get vkLoginStartUrl => buildVkStartUrl();

  String get vkLinkStartUrl => buildVkStartUrl(linkMode: true);

  String get maxLoginStartUrl => buildMaxStartUrl();

  String get maxLinkStartUrl => buildMaxStartUrl(linkMode: true);

  String buildTelegramStartUrl({bool linkMode = false}) {
    final appUri = Uri.parse(_runtimeConfig.publicAppUrl);
    final callbackUrl = _buildUri(
      '/v1/auth/telegram/callback',
      queryParameters: linkMode ? const {'intent': 'link'} : null,
    ).toString();
    return appUri.replace(
      path: '/telegram_login.html',
      queryParameters: <String, String>{
        'bot': _defaultTelegramBotUsername,
        'authUrl': callbackUrl,
      },
    ).toString();
  }

  String buildVkStartUrl({bool linkMode = false}) {
    return _buildUri(
      '/v1/auth/vk/start',
      queryParameters: linkMode ? const {'intent': 'link'} : null,
    ).toString();
  }

  String buildMaxStartUrl({bool linkMode = false}) {
    return _buildUri(
      '/v1/auth/max/start',
      queryParameters: linkMode ? const {'intent': 'link'} : null,
    ).toString();
  }

  Future<TelegramAuthCompletion> exchangeTelegramAuthCode(String code) async {
    final response = await _requestJson(
      method: 'POST',
      path: '/v1/auth/telegram/exchange',
      body: {'code': code},
    );

    final status = response['status']?.toString() ?? '';
    if (status == 'authenticated') {
      final authPayload = response['auth'];
      if (authPayload is! Map<String, dynamic>) {
        throw const CustomApiException(
          'Telegram auth backend не вернул корректную сессию',
        );
      }
      final session = _sessionFromResponse(authPayload);
      await _saveSession(session);
      _authStateController.add(session.userId);
      await processPendingInvitation();
      return const TelegramAuthCompletion.authenticated();
    }

    if (status == 'pending_link') {
      final profile = response['telegramProfile'];
      final profileMap =
          profile is Map<String, dynamic> ? profile : const <String, dynamic>{};
      final linkCode = response['linkCode']?.toString() ?? '';
      if (linkCode.isEmpty) {
        throw const CustomApiException(
          'Telegram link code не был получен от backend',
        );
      }
      return TelegramAuthCompletion.pendingLink(
        linkCode: linkCode,
        message: response['message']?.toString(),
        firstName: profileMap['firstName']?.toString(),
        lastName: profileMap['lastName']?.toString(),
        username: profileMap['username']?.toString(),
        photoUrl: profileMap['photoUrl']?.toString(),
      );
    }

    if (status == 'already_linked') {
      return TelegramAuthCompletion.alreadyLinked(
        message: response['message']?.toString(),
      );
    }

    throw const CustomApiException(
      'Telegram auth backend вернул неизвестный статус',
    );
  }

  Future<void> linkPendingTelegramIdentity(String code) async {
    final response = await _requestJson(
      method: 'POST',
      path: '/v1/auth/telegram/link',
      authenticated: true,
      body: {'code': code},
    );
    final userJson = _extractUserJson(response);
    final providerIds = (userJson['providerIds'] as List<dynamic>? ?? const [])
        .map((value) => value.toString())
        .toList();
    if (providerIds.isNotEmpty) {
      await updateCachedSession(providerIds: providerIds);
    }
  }

  Future<VkAuthCompletion> exchangeVkAuthCode(String code) async {
    final response = await _requestJson(
      method: 'POST',
      path: '/v1/auth/vk/exchange',
      body: {'code': code},
    );

    final status = response['status']?.toString() ?? '';
    if (status == 'authenticated') {
      final authPayload = response['auth'];
      if (authPayload is! Map<String, dynamic>) {
        throw const CustomApiException(
          'VK ID auth backend не вернул корректную сессию',
        );
      }
      final session = _sessionFromResponse(authPayload);
      await _saveSession(session);
      _authStateController.add(session.userId);
      await processPendingInvitation();
      return const VkAuthCompletion.authenticated();
    }

    if (status == 'pending_link') {
      final profile = response['vkProfile'];
      final profileMap =
          profile is Map<String, dynamic> ? profile : const <String, dynamic>{};
      final linkCode = response['linkCode']?.toString() ?? '';
      if (linkCode.isEmpty) {
        throw const CustomApiException(
          'VK ID link code не был получен от backend',
        );
      }
      return VkAuthCompletion.pendingLink(
        linkCode: linkCode,
        message: response['message']?.toString(),
        firstName: profileMap['firstName']?.toString(),
        lastName: profileMap['lastName']?.toString(),
        email: profileMap['email']?.toString(),
        phoneNumber: profileMap['phoneNumber']?.toString(),
        photoUrl: profileMap['photoUrl']?.toString(),
      );
    }

    if (status == 'already_linked') {
      return VkAuthCompletion.alreadyLinked(
        message: response['message']?.toString(),
      );
    }

    throw const CustomApiException(
      'VK ID auth backend вернул неизвестный статус',
    );
  }

  Future<void> linkPendingVkIdentity(String code) async {
    final response = await _requestJson(
      method: 'POST',
      path: '/v1/auth/vk/link',
      authenticated: true,
      body: {'code': code},
    );
    final userJson = _extractUserJson(response);
    final providerIds = (userJson['providerIds'] as List<dynamic>? ?? const [])
        .map((value) => value.toString())
        .toList();
    if (providerIds.isNotEmpty) {
      await updateCachedSession(providerIds: providerIds);
    }
  }

  Future<MaxAuthCompletion> exchangeMaxAuthCode(String code) async {
    final response = await _requestJson(
      method: 'POST',
      path: '/v1/auth/max/exchange',
      body: {'code': code},
    );

    final status = response['status']?.toString() ?? '';
    if (status == 'authenticated') {
      final authPayload = response['auth'];
      if (authPayload is! Map<String, dynamic>) {
        throw const CustomApiException(
          'MAX auth backend не вернул корректную сессию',
        );
      }
      final session = _sessionFromResponse(authPayload);
      await _saveSession(session);
      _authStateController.add(session.userId);
      await processPendingInvitation();
      return const MaxAuthCompletion.authenticated();
    }

    if (status == 'pending_link') {
      final profile = response['maxProfile'];
      final profileMap =
          profile is Map<String, dynamic> ? profile : const <String, dynamic>{};
      final linkCode = response['linkCode']?.toString() ?? '';
      if (linkCode.isEmpty) {
        throw const CustomApiException(
          'MAX link code не был получен от backend',
        );
      }
      return MaxAuthCompletion.pendingLink(
        linkCode: linkCode,
        message: response['message']?.toString(),
        firstName: profileMap['firstName']?.toString(),
        lastName: profileMap['lastName']?.toString(),
        username: profileMap['username']?.toString(),
        photoUrl: profileMap['photoUrl']?.toString(),
      );
    }

    if (status == 'already_linked') {
      return MaxAuthCompletion.alreadyLinked(
        message: response['message']?.toString(),
      );
    }

    throw const CustomApiException(
      'MAX auth backend вернул неизвестный статус',
    );
  }

  Future<void> linkPendingMaxIdentity(String code) async {
    final response = await _requestJson(
      method: 'POST',
      path: '/v1/auth/max/link',
      authenticated: true,
      body: {'code': code},
    );
    final userJson = _extractUserJson(response);
    final providerIds = (userJson['providerIds'] as List<dynamic>? ?? const [])
        .map((value) => value.toString())
        .toList();
    if (providerIds.isNotEmpty) {
      await updateCachedSession(providerIds: providerIds);
    }
  }

  @override
  Future<void> signOut() async {
    final currentToken = accessToken;
    if (currentToken != null && currentToken.isNotEmpty) {
      try {
        await _httpClient.post(
          _buildUri('/v1/auth/logout'),
          headers: _jsonHeaders(authenticated: true),
        );
      } catch (_) {}
    }

    try {
      await _googleSignIn?.signOut();
    } catch (_) {}

    await _clearSession();
  }

  Future<void> clearSessionLocally({bool sessionExpired = false}) async {
    await _clearSession(sessionExpired: sessionExpired);
  }

  @override
  Future<void> resetPassword(String email) async {
    await _requestJson(
      method: 'POST',
      path: '/v1/auth/password-reset',
      body: {'email': email},
    );
  }

  @override
  Future<void> deleteAccount([String? password]) async {
    await _requestJson(
      method: 'DELETE',
      path: '/v1/auth/account',
      authenticated: true,
      body: {
        if (password != null && password.isNotEmpty) 'password': password,
      },
    );
    await _clearSession();
  }

  @override
  Future<Map<String, dynamic>> checkProfileCompleteness() async {
    final session = _session;
    if (session == null) {
      return _signedOutProfileStatus();
    }

    try {
      final response = await _requestJson(
        method: 'GET',
        path: '/v1/auth/session',
        authenticated: true,
      );
      final refreshedSession = _sessionFromResponse(response);
      await _saveSession(refreshedSession);
      return _profileStatusMap(refreshedSession);
    } on CustomApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        await _clearSession(sessionExpired: true);
        return _signedOutProfileStatus();
      }
      final cachedSession = _session;
      if (cachedSession == null) {
        return _signedOutProfileStatus();
      }
      return _profileStatusMap(cachedSession);
    } catch (_) {
      final cachedSession = _session;
      if (cachedSession == null) {
        return _signedOutProfileStatus();
      }
      return _profileStatusMap(cachedSession);
    }
  }

  @override
  Future<void> processPendingInvitation() async {
    if (_session == null || !_invitationService.hasPendingInvitation) {
      return;
    }

    try {
      await _requestJson(
        method: 'POST',
        path: '/v1/invitations/pending/process',
        authenticated: true,
        body: {
          'treeId': _invitationService.pendingTreeId,
          'personId': _invitationService.pendingPersonId,
        },
      );
      _invitationService.clearPendingInvitation();
    } catch (_) {}
  }

  @override
  Future<void> updateDisplayName(String displayName) async {
    final response = await _requestJson(
      method: 'PATCH',
      path: '/v1/profile/me',
      authenticated: true,
      body: {
        'displayName': displayName.trim(),
      },
    );

    final user = _extractUserJson(response);
    if (_session != null) {
      await updateCachedSession(
        displayName: user['displayName']?.toString() ?? displayName.trim(),
      );
    }
  }

  Future<void> updateCachedSession({
    String? email,
    String? displayName,
    String? photoUrl,
    List<String>? providerIds,
    bool? isProfileComplete,
    List<String>? missingFields,
  }) async {
    final currentSession = _session;
    if (currentSession == null) {
      return;
    }

    await _saveSession(
      currentSession.copyWith(
        email: email ?? currentSession.email,
        displayName: displayName ?? currentSession.displayName,
        photoUrl: photoUrl ?? currentSession.photoUrl,
        providerIds: providerIds ?? currentSession.providerIds,
        isProfileComplete:
            isProfileComplete ?? currentSession.isProfileComplete,
        missingFields: missingFields ?? currentSession.missingFields,
      ),
    );
  }

  Future<Object?> _authenticate({
    required String path,
    required Map<String, dynamic> payload,
  }) async {
    final response = await _requestJson(
      method: 'POST',
      path: path,
      body: payload,
    );
    final session = _sessionFromResponse(response);
    await _saveSession(session);
    _authStateController.add(session.userId);
    await processPendingInvitation();
    return session;
  }

  Future<Map<String, dynamic>> _requestJson({
    required String method,
    required String path,
    bool authenticated = false,
    Map<String, dynamic>? body,
  }) async {
    final uri = _buildUri(path);
    try {
      return await _executeRequest(method, uri, authenticated, body);
    } on CustomApiException catch (e) {
      if (authenticated && (e.statusCode == 401 || e.statusCode == 403)) {
        if (_session?.refreshToken != null) {
          try {
            await refreshSession();
            return await _executeRequest(method, uri, authenticated, body);
          } catch (_) {
            await _clearSession(sessionExpired: true);
            rethrow;
          }
        } else {
          await _clearSession(sessionExpired: true);
        }
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _executeRequest(
    String method,
    Uri uri,
    bool authenticated,
    Map<String, dynamic>? body,
  ) async {
    late http.Response response;
    final headers = _jsonHeaders(authenticated: authenticated);

    switch (method) {
      case 'GET':
        response = await _httpClient.get(uri, headers: headers);
        break;
      case 'POST':
        response = await _httpClient.post(
          uri,
          headers: headers,
          body: jsonEncode(body ?? const {}),
        );
        break;
      case 'PATCH':
        response = await _httpClient.patch(
          uri,
          headers: headers,
          body: jsonEncode(body ?? const {}),
        );
        break;
      case 'DELETE':
        final request = http.Request('DELETE', uri)
          ..headers.addAll(headers)
          ..body = jsonEncode(body ?? const {});
        final streamedResponse = await _httpClient.send(request);
        response = await http.Response.fromStream(streamedResponse);
        break;
      default:
        throw CustomApiException('Неподдерживаемый HTTP-метод: $method');
    }

    return _decodeResponse(response);
  }

  Future<void> _saveSession(CustomApiSession session) async {
    _session = session;
    await _preferences.setString(
      _sessionStorageKey,
      jsonEncode(session.toJson()),
    );
    _appStatusService?.clearSessionIssue();
  }

  Future<void> _clearSession({bool sessionExpired = false}) async {
    _session = null;
    await _preferences.remove(_sessionStorageKey);
    _authStateController.add(null);
    if (sessionExpired) {
      _appStatusService?.reportSessionExpired();
    } else {
      _appStatusService?.clearSessionIssue();
    }
  }

  Uri _buildUri(String path, {Map<String, String>? queryParameters}) {
    var base = _runtimeConfig.apiBaseUrl.replaceAll(
      RegExp(r'/$'),
      '',
    );
    final shouldForceHttps = base.startsWith('http://api.rodnya-tree.ru') ||
        base.startsWith('http://rodnya-tree.ru') ||
        base.startsWith('http://api.fodder-development.ru');
    if (shouldForceHttps) {
      base = 'https://${base.replaceFirst(RegExp(r'^http://'), '')}';
    }
    return Uri.parse('$base$path').replace(queryParameters: queryParameters);
  }

  Map<String, String> _jsonHeaders({bool authenticated = false}) {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (authenticated && accessToken != null)
        'Authorization': 'Bearer ${accessToken!}',
    };
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    if (response.body.isEmpty) {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return const <String, dynamic>{};
      }
      throw CustomApiException(
        'Пустой ответ от backend',
        statusCode: response.statusCode,
      );
    }

    final dynamic decodedBody = jsonDecode(response.body);
    final bodyMap = decodedBody is Map<String, dynamic>
        ? decodedBody
        : <String, dynamic>{'data': decodedBody};

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return bodyMap;
    }

    final message = bodyMap['message']?.toString() ??
        bodyMap['error']?.toString() ??
        'Ошибка backend (${response.statusCode})';
    throw CustomApiException(message, statusCode: response.statusCode);
  }

  CustomApiSession _sessionFromResponse(Map<String, dynamic> response) {
    final sessionJson = _extractSessionJson(response);
    final userJson = _extractUserJson(response);
    final profileStatus = _extractProfileStatus(response);
    final providerIds = (userJson['providerIds'] as List<dynamic>? ??
            sessionJson['providerIds'] as List<dynamic>? ??
            const [])
        .map((value) => value.toString())
        .toList();

    final session = CustomApiSession(
      accessToken: sessionJson['accessToken']?.toString() ??
          response['accessToken']?.toString() ??
          '',
      refreshToken: sessionJson['refreshToken']?.toString() ??
          response['refreshToken']?.toString(),
      userId: userJson['id']?.toString() ??
          sessionJson['userId']?.toString() ??
          response['userId']?.toString() ??
          '',
      email: userJson['email']?.toString() ?? response['email']?.toString(),
      displayName: userJson['displayName']?.toString() ??
          response['displayName']?.toString(),
      photoUrl: userJson['photoUrl']?.toString() ??
          userJson['photoURL']?.toString() ??
          response['photoUrl']?.toString() ??
          response['photoURL']?.toString(),
      providerIds: providerIds,
      isProfileComplete: profileStatus['isComplete'] == true,
      missingFields:
          (profileStatus['missingFields'] as List<dynamic>? ?? const [])
              .map((value) => value.toString())
              .toList(),
    );

    if (session.accessToken.isEmpty || session.userId.isEmpty) {
      throw const CustomApiException(
        'Backend не вернул session/access token для customApi auth',
      );
    }

    return session;
  }

  Map<String, dynamic> _extractSessionJson(Map<String, dynamic> response) {
    final sessionValue = response['session'];
    if (sessionValue is Map<String, dynamic>) {
      return sessionValue;
    }
    return response;
  }

  Map<String, dynamic> _extractUserJson(Map<String, dynamic> response) {
    final sessionJson = _extractSessionJson(response);
    final userValue = response['user'] ?? sessionJson['user'];
    if (userValue is Map<String, dynamic>) {
      return userValue;
    }
    return sessionJson;
  }

  Map<String, dynamic> _extractProfileStatus(Map<String, dynamic> response) {
    final sessionJson = _extractSessionJson(response);
    final statusValue =
        response['profileStatus'] ?? sessionJson['profileStatus'];
    if (statusValue is Map<String, dynamic>) {
      return statusValue;
    }
    return const <String, dynamic>{};
  }

  Map<String, dynamic> _profileStatusMap(CustomApiSession session) {
    return {
      'isComplete': session.isProfileComplete,
      'missingFields': session.missingFields,
    };
  }

  Map<String, dynamic> _signedOutProfileStatus() {
    return {
      'isComplete': false,
      'missingFields': ['auth'],
    };
  }

  @override
  String describeError(Object error) {
    if (error is CustomApiException) {
      final normalizedMessage = error.message.trim();
      final lowerMessage = normalizedMessage.toLowerCase();

      if (error.statusCode == 401 || error.statusCode == 403) {
        if (lowerMessage.contains('email') || lowerMessage.contains('парол')) {
          return 'Не удалось войти. Проверьте email и пароль.';
        }
        return _sanitizeErrorMessage(normalizedMessage);
      }
      if (error.statusCode == 409) {
        if (lowerMessage.contains('email') &&
            lowerMessage.contains('существ')) {
          return 'Аккаунт с таким email уже существует.';
        }
        return _sanitizeErrorMessage(normalizedMessage);
      }
      if (error.statusCode == 429) {
        return 'Слишком много попыток. Попробуйте чуть позже.';
      }
      if ((error.statusCode ?? 0) >= 500) {
        return 'Сервис временно недоступен. Попробуйте чуть позже.';
      }
      if (lowerMessage.contains('socketexception') ||
          lowerMessage.contains('failed host lookup') ||
          lowerMessage.contains('connection refused') ||
          lowerMessage.contains('connection reset') ||
          lowerMessage.contains('network is unreachable') ||
          lowerMessage.contains('timed out')) {
        return 'Не удалось подключиться к серверу. Проверьте интернет и попробуйте ещё раз.';
      }

      return _sanitizeErrorMessage(normalizedMessage);
    }

    final rawMessage = error.toString();
    if (rawMessage.startsWith('Exception: ')) {
      return _sanitizeErrorMessage(rawMessage.substring('Exception: '.length));
    }
    return _sanitizeErrorMessage(rawMessage);
  }

  String _sanitizeErrorMessage(String message) {
    final trimmed = message.trim();
    final lowerMessage = trimmed.toLowerCase();

    if (trimmed.isEmpty) {
      return 'Не удалось выполнить вход. Попробуйте ещё раз.';
    }
    if (lowerMessage.startsWith('error:') ||
        lowerMessage.contains('typeerror') ||
        lowerMessage.contains('stack trace') ||
        lowerMessage.contains('exception:') ||
        lowerMessage.contains('status code') ||
        lowerMessage.contains('backend (')) {
      return 'Не удалось выполнить вход. Попробуйте ещё раз.';
    }

    return trimmed;
  }
}
