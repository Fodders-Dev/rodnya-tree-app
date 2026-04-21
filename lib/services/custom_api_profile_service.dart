import 'dart:convert';
import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../backend/backend_runtime_config.dart';
import '../backend/interfaces/profile_service_interface.dart';
import '../backend/interfaces/storage_service_interface.dart';
import '../models/account_linking_status.dart';
import '../backend/models/profile_form_data.dart';
import '../models/family_person.dart';
import '../models/profile_contribution.dart';
import '../models/profile_note.dart';
import '../models/user_profile.dart';
import 'custom_api_auth_service.dart';

class CustomApiProfileService implements ProfileServiceInterface {
  CustomApiProfileService._({
    required CustomApiAuthService authService,
    required http.Client httpClient,
    required SharedPreferences preferences,
    required BackendRuntimeConfig runtimeConfig,
    StorageServiceInterface? storageService,
  })  : _authService = authService,
        _httpClient = httpClient,
        _preferences = preferences,
        _runtimeConfig = runtimeConfig,
        _storageService = storageService;

  static const _profileStorageKey = 'custom_api_profile_form_v1';
  static const _maxPhotoSizeBytes = 5 * 1024 * 1024;
  static const _allowedExtensions = ['.jpg', '.jpeg', '.png', '.webp'];
  static const Map<String, String> _defaultProfileVisibilityScopes = {
    'contacts': 'private',
    'about': 'shared_trees',
    'background': 'shared_trees',
    'worldview': 'shared_trees',
  };
  static const Map<String, List<String>> _emptyProfileVisibilityTargets = {
    'contacts': <String>[],
    'about': <String>[],
    'background': <String>[],
    'worldview': <String>[],
  };

  final CustomApiAuthService _authService;
  final http.Client _httpClient;
  final SharedPreferences _preferences;
  final BackendRuntimeConfig _runtimeConfig;
  final StorageServiceInterface? _storageService;
  final Map<String, StreamController<List<ProfileNote>>> _noteControllers = {};

  static Future<CustomApiProfileService> create({
    required CustomApiAuthService authService,
    http.Client? httpClient,
    SharedPreferences? preferences,
    BackendRuntimeConfig? runtimeConfig,
    StorageServiceInterface? storageService,
  }) async {
    return CustomApiProfileService._(
      authService: authService,
      httpClient: httpClient ?? http.Client(),
      preferences: preferences ?? await SharedPreferences.getInstance(),
      runtimeConfig: runtimeConfig ?? BackendRuntimeConfig.current,
      storageService: storageService,
    );
  }

  @override
  Future<UserProfile?> getUserProfile(String userId) async {
    if (_authService.currentUserId == userId) {
      return getCurrentUserProfile();
    }

    try {
      final response = await _requestJson(
        method: 'GET',
        path: '/v1/users/$userId/profile',
      );
      return _userProfileFromJson(userId, response);
    } on CustomApiException catch (error) {
      if (error.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<UserProfile?> getCurrentUserProfile() async {
    final cached = _getCachedProfileForm();
    if (cached != null) {
      return _toUserProfile(cached);
    }

    final formData = await getCurrentUserProfileFormData();
    return _toUserProfile(formData);
  }

  @override
  Future<ProfileFormData> getCurrentUserProfileFormData() async {
    final currentUserId = _authService.currentUserId;
    if (currentUserId == null) {
      throw const CustomApiException('Пользователь не авторизован');
    }

    try {
      final response = await _requestJson(
        method: 'GET',
        path: '/v1/profile/me/bootstrap',
      );
      final formData = _profileFormDataFromResponse(response);
      await _cacheProfileForm(formData);
      return formData;
    } catch (_) {
      final cached = _getCachedProfileForm(userId: currentUserId);
      if (cached != null) {
        return cached;
      }
      rethrow;
    }
  }

  @override
  Future<AccountLinkingStatus> getCurrentAccountLinkingStatus() async {
    final response = await _requestJson(
      method: 'GET',
      path: '/v1/profile/me/account-linking-status',
    );
    return AccountLinkingStatus.fromJson(response);
  }

  @override
  Future<void> saveCurrentUserProfileFormData(ProfileFormData data) async {
    final response = await _requestJson(
      method: 'PUT',
      path: '/v1/profile/me/bootstrap',
      body: _profilePayload(data),
    );

    final savedData = _profileFormDataFromResponse(response).copyWith(
      userId: data.userId,
    );
    await _cacheProfileForm(savedData);

    final profileStatus = _extractProfileStatus(response);
    await _authService.updateCachedSession(
      email: savedData.email,
      displayName: savedData.displayName.isNotEmpty
          ? savedData.displayName
          : _composeDisplayName(savedData),
      photoUrl: savedData.photoUrl,
      isProfileComplete: profileStatus['isComplete'] == true,
      missingFields:
          (profileStatus['missingFields'] as List<dynamic>? ?? const [])
              .map((value) => value.toString())
              .toList(),
    );
  }

  @override
  Future<String?> uploadProfilePhoto(XFile photo) async {
    final storageService = _storageService;
    if (storageService == null) {
      throw UnsupportedError(
        'Для customApi profile adapter нужен storage provider customApi.',
      );
    }

    final extension = _detectExtension(photo.name, mimeType: photo.mimeType);
    if (!_allowedExtensions.contains(extension)) {
      throw Exception(
        'Недопустимый формат файла. Разрешены только ${_allowedExtensions.join(', ')}',
      );
    }

    final fileBytes = await photo.readAsBytes();
    if (fileBytes.length > _maxPhotoSizeBytes) {
      throw Exception('Размер файла превышает 5MB');
    }

    final photoUrl = await storageService.uploadProfileImage(photo);
    if (photoUrl == null || photoUrl.isEmpty) {
      throw Exception('Не удалось загрузить фото профиля');
    }

    final response = await _requestJson(
      method: 'PATCH',
      path: '/v1/profile/me',
      body: {
        'photoUrl': photoUrl,
      },
    );

    final cached = _getCachedProfileForm();
    if (cached != null) {
      await _cacheProfileForm(cached.copyWith(photoUrl: photoUrl));
    }

    final profileStatus = _extractProfileStatus(response);
    await _authService.updateCachedSession(
      email: cached?.email,
      displayName: cached?.displayName,
      photoUrl: photoUrl,
      isProfileComplete: profileStatus['isComplete'] == true,
      missingFields:
          (profileStatus['missingFields'] as List<dynamic>? ?? const [])
              .map((value) => value.toString())
              .toList(),
    );

    return photoUrl;
  }

  @override
  Future<void> updateUserProfile(String userId, UserProfile profile) async {
    await _requestJson(
      method: 'PATCH',
      path: '/v1/users/$userId/profile',
      body: _profilePayload(
        ProfileFormData(
          userId: userId,
          email: profile.email,
          firstName: profile.firstName,
          lastName: profile.lastName,
          middleName: profile.middleName,
          displayName: profile.displayName,
          username: profile.username,
          phoneNumber: profile.phoneNumber,
          countryCode: profile.countryCode,
          countryName: profile.country,
          city: profile.city ?? '',
          photoUrl: profile.photoURL,
          gender: profile.gender ?? Gender.unknown,
          birthDate: profile.birthDate,
          birthPlace: profile.birthPlace ?? '',
          bio: profile.bio,
          familyStatus: profile.familyStatus,
          aboutFamily: profile.aboutFamily,
          education: profile.education,
          work: profile.work,
          hometown: profile.hometown,
          languages: profile.languages,
          values: profile.values,
          religion: profile.religion,
          interests: profile.interests,
          profileContributionPolicy: profile.profileContributionPolicy,
          primaryTrustedChannel: null,
          profileVisibilityScopes: profile.profileVisibilityScopes ??
              _defaultProfileVisibilityScopes,
          profileVisibilityTreeIds: profile.profileVisibilityTreeIds ??
              _emptyProfileVisibilityTargets,
          profileVisibilityBranchRootIds:
              profile.profileVisibilityBranchRootIds ??
                  _emptyProfileVisibilityTargets,
          profileVisibilityUserIds: profile.profileVisibilityUserIds ??
              _emptyProfileVisibilityTargets,
        ),
      ),
    );
  }

  @override
  Future<List<ProfileContribution>> getPendingProfileContributions() async {
    final response = await _requestJson(
      method: 'GET',
      path: '/v1/profile/me/contributions?status=pending',
    );
    final items = response['contributions'];
    if (items is! List<dynamic>) {
      return const <ProfileContribution>[];
    }
    return items
        .whereType<Map<String, dynamic>>()
        .map(ProfileContribution.fromJson)
        .where((item) => item.id.isNotEmpty)
        .toList();
  }

  @override
  Future<void> acceptProfileContribution(String contributionId) async {
    final response = await _requestJson(
      method: 'POST',
      path: '/v1/profile/me/contributions/$contributionId/accept',
    );
    final profile = response['profile'];
    if (profile is Map<String, dynamic>) {
      await _cacheProfileForm(_profileFormDataFromJson(profile));
    }
  }

  @override
  Future<void> rejectProfileContribution(String contributionId) async {
    await _requestJson(
      method: 'POST',
      path: '/v1/profile/me/contributions/$contributionId/reject',
    );
  }

  @override
  Stream<List<ProfileNote>> getProfileNotesStream(String userId) {
    final controller = _noteControllers.putIfAbsent(
      userId,
      () {
        final streamController = StreamController<List<ProfileNote>>.broadcast(
          onListen: () {
            _refreshProfileNotes(userId);
          },
        );
        return streamController;
      },
    );

    _refreshProfileNotes(userId);
    return controller.stream;
  }

  @override
  Future<void> addProfileNote(
      String userId, String title, String content) async {
    final response = await _requestJson(
      method: 'POST',
      path: '/v1/users/$userId/profile-notes',
      body: {
        'title': title,
        'content': content,
      },
    );

    final note = _profileNoteFromResponse(response);
    await _refreshProfileNotes(userId, insertedNote: note);
  }

  @override
  Future<void> updateProfileNote(String userId, ProfileNote note) async {
    await _requestJson(
      method: 'PATCH',
      path: '/v1/users/$userId/profile-notes/${note.id}',
      body: {
        'title': note.title,
        'content': note.content,
      },
    );
    await _refreshProfileNotes(userId);
  }

  @override
  Future<void> deleteProfileNote(String userId, String noteId) async {
    await _requestDelete(
      path: '/v1/users/$userId/profile-notes/$noteId',
    );
    await _refreshProfileNotes(userId);
  }

  @override
  Future<List<UserProfile>> searchUsersByField({
    required String field,
    required String value,
    int limit = 10,
  }) async {
    final response = await _requestJson(
      method: 'GET',
      path: '/v1/users/search/by-field',
      queryParameters: {
        'field': field,
        'value': value,
        'limit': '$limit',
      },
    );
    return _userProfileListFromResponse(response);
  }

  @override
  Future<List<UserProfile>> searchUsers(String query, {int limit = 10}) async {
    final response = await _requestJson(
      method: 'GET',
      path: '/v1/users/search',
      queryParameters: {
        'query': query,
        'limit': '$limit',
      },
    );
    return _userProfileListFromResponse(response);
  }

  Future<Map<String, dynamic>> _requestJson({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
  }) async {
    final uri = _buildUri(path, queryParameters: queryParameters);
    late http.Response response;

    switch (method) {
      case 'GET':
        response = await _httpClient.get(uri, headers: _headers());
        break;
      case 'PUT':
        response = await _httpClient.put(
          uri,
          headers: _headers(),
          body: jsonEncode(body ?? const {}),
        );
        break;
      case 'PATCH':
        response = await _httpClient.patch(
          uri,
          headers: _headers(),
          body: jsonEncode(body ?? const {}),
        );
        break;
      case 'POST':
        response = await _httpClient.post(
          uri,
          headers: _headers(),
          body: jsonEncode(body ?? const {}),
        );
        break;
      default:
        throw CustomApiException('Неподдерживаемый HTTP-метод: $method');
    }

    if (response.body.isEmpty) {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return const <String, dynamic>{};
      }
      throw CustomApiException(
        'Пустой ответ от backend',
        statusCode: response.statusCode,
      );
    }

    final dynamic decoded = jsonDecode(response.body);
    final payload = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{'data': decoded};

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return payload;
    }

    throw CustomApiException(
      payload['message']?.toString() ??
          payload['error']?.toString() ??
          'Ошибка backend (${response.statusCode})',
      statusCode: response.statusCode,
    );
  }

  Future<void> _requestDelete({
    required String path,
  }) async {
    final uri = _buildUri(path);
    final response = await _httpClient.delete(uri, headers: _headers());

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    if (response.body.isNotEmpty) {
      final dynamic decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        throw CustomApiException(
          decoded['message']?.toString() ??
              'Ошибка backend (${response.statusCode})',
          statusCode: response.statusCode,
        );
      }
    }

    throw CustomApiException(
      'Ошибка backend (${response.statusCode})',
      statusCode: response.statusCode,
    );
  }

  Uri _buildUri(String path, {Map<String, String>? queryParameters}) {
    final normalizedBase = _runtimeConfig.apiBaseUrl.replaceAll(
      RegExp(r'/$'),
      '',
    );
    return Uri.parse('$normalizedBase$path')
        .replace(queryParameters: queryParameters);
  }

  Map<String, String> _headers() {
    final token = _authService.accessToken;
    if (token == null || token.isEmpty) {
      throw const CustomApiException('Нет активной customApi session');
    }

    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<void> _cacheProfileForm(ProfileFormData data) async {
    final storageKey = _profileStorageKeyForUser(data.userId);
    await _preferences.setString(
      storageKey,
      jsonEncode({
        'userId': data.userId,
        'email': data.email,
        'firstName': data.firstName,
        'lastName': data.lastName,
        'middleName': data.middleName,
        'displayName': data.displayName,
        'username': data.username,
        'phoneNumber': data.phoneNumber,
        'countryCode': data.countryCode,
        'countryName': data.countryName,
        'city': data.city,
        'photoUrl': data.photoUrl,
        'gender': data.gender.name,
        'maidenName': data.maidenName,
        'birthDate': data.birthDate?.toIso8601String(),
        'birthPlace': data.birthPlace,
        'bio': data.bio,
        'familyStatus': data.familyStatus,
        'aboutFamily': data.aboutFamily,
        'education': data.education,
        'work': data.work,
        'hometown': data.hometown,
        'languages': data.languages,
        'values': data.values,
        'religion': data.religion,
        'interests': data.interests,
        'profileContributionPolicy': data.profileContributionPolicy,
        'primaryTrustedChannel': data.primaryTrustedChannel,
        'profileVisibility': _encodeProfileVisibility(
          data.profileVisibilityScopes,
          treeIdsBySection: data.profileVisibilityTreeIds,
          branchRootIdsBySection: data.profileVisibilityBranchRootIds,
          userIdsBySection: data.profileVisibilityUserIds,
        ),
      }),
    );
    await _preferences.remove(_profileStorageKey);
  }

  ProfileFormData? _getCachedProfileForm({String? userId}) {
    final currentUserId = userId ?? _authService.currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      return null;
    }

    final scopedValue = _preferences.getString(
      _profileStorageKeyForUser(currentUserId),
    );
    if (scopedValue != null && scopedValue.isNotEmpty) {
      return _decodeCachedProfileForm(scopedValue,
          expectedUserId: currentUserId);
    }

    final rawValue = _preferences.getString(_profileStorageKey);
    if (rawValue == null || rawValue.isEmpty) {
      return null;
    }

    final legacyProfile = _decodeCachedProfileForm(
      rawValue,
      expectedUserId: currentUserId,
    );
    if (legacyProfile != null) {
      unawaited(_cacheProfileForm(legacyProfile));
      return legacyProfile;
    }

    unawaited(_preferences.remove(_profileStorageKey));
    return null;
  }

  String _profileStorageKeyForUser(String userId) =>
      '${_profileStorageKey}_$userId';

  ProfileFormData? _decodeCachedProfileForm(
    String rawValue, {
    required String expectedUserId,
  }) {
    try {
      final decoded = jsonDecode(rawValue);
      if (decoded is Map<String, dynamic>) {
        final profileForm = _profileFormDataFromJson(decoded);
        if (profileForm.userId == expectedUserId) {
          return profileForm;
        }
      }
    } catch (_) {}
    return null;
  }

  ProfileFormData _profileFormDataFromResponse(Map<String, dynamic> response) {
    final profile = response['profile'];
    if (profile is Map<String, dynamic>) {
      return _profileFormDataFromJson(profile);
    }
    return _profileFormDataFromJson(response);
  }

  ProfileFormData _profileFormDataFromJson(Map<String, dynamic> json) {
    final userId = json['userId']?.toString() ??
        json['id']?.toString() ??
        _authService.currentUserId ??
        '';
    final firstName = json['firstName']?.toString() ?? '';
    final lastName = json['lastName']?.toString() ?? '';
    final middleName = json['middleName']?.toString() ?? '';
    final displayName = json['displayName']?.toString() ??
        _composeDisplayNameFromParts(firstName, middleName, lastName);
    final gender = _genderFromValue(json['gender']);
    final birthDateValue = json['birthDate']?.toString();

    return ProfileFormData(
      userId: userId,
      email: json['email']?.toString() ?? _authService.currentUserEmail,
      firstName: firstName,
      lastName: lastName,
      middleName: middleName,
      displayName: displayName,
      username: json['username']?.toString() ?? '',
      phoneNumber: json['phoneNumber']?.toString() ?? '',
      countryCode: json['countryCode']?.toString(),
      countryName:
          json['countryName']?.toString() ?? json['country']?.toString(),
      city: json['city']?.toString() ?? '',
      photoUrl: json['photoUrl']?.toString() ?? json['photoURL']?.toString(),
      gender: gender,
      maidenName: json['maidenName']?.toString() ?? '',
      birthDate: birthDateValue != null && birthDateValue.isNotEmpty
          ? DateTime.tryParse(birthDateValue)
          : null,
      birthPlace: json['birthPlace']?.toString() ?? '',
      bio: json['bio']?.toString() ?? '',
      familyStatus: json['familyStatus']?.toString() ?? '',
      aboutFamily: json['aboutFamily']?.toString() ?? '',
      education: json['education']?.toString() ?? '',
      work: json['work']?.toString() ?? '',
      hometown: json['hometown']?.toString() ?? '',
      languages: json['languages']?.toString() ?? '',
      values: json['values']?.toString() ?? '',
      religion: json['religion']?.toString() ?? '',
      interests: json['interests']?.toString() ?? '',
      profileContributionPolicy:
          json['profileContributionPolicy']?.toString() ?? 'suggestions',
      primaryTrustedChannel: json['primaryTrustedChannel']?.toString(),
      profileVisibilityScopes: _decodeProfileVisibility(
        json['profileVisibility'],
      ),
      profileVisibilityTreeIds: _decodeProfileVisibilityTargets(
        json['profileVisibility'],
        targetKey: 'treeIds',
      ),
      profileVisibilityBranchRootIds: _decodeProfileVisibilityTargets(
        json['profileVisibility'],
        targetKey: 'branchRootPersonIds',
      ),
      profileVisibilityUserIds: _decodeProfileVisibilityTargets(
        json['profileVisibility'],
        targetKey: 'userIds',
      ),
    );
  }

  Gender _genderFromValue(dynamic value) {
    switch (value?.toString()) {
      case 'male':
        return Gender.male;
      case 'female':
        return Gender.female;
      case 'other':
        return Gender.other;
      default:
        return Gender.unknown;
    }
  }

  Map<String, dynamic> _profilePayload(ProfileFormData data) {
    final displayName = data.displayName.isNotEmpty
        ? data.displayName
        : _composeDisplayName(data);

    return {
      'email': data.email,
      'firstName': data.firstName.trim(),
      'lastName': data.lastName.trim(),
      'middleName': data.middleName.trim(),
      'displayName': displayName,
      'username': data.username.trim(),
      'phoneNumber': data.phoneNumber.trim(),
      'countryCode': data.countryCode,
      'countryName': data.countryName,
      'city': data.city.trim(),
      'photoUrl': data.photoUrl,
      'gender': data.gender.name,
      'maidenName': data.maidenName.trim(),
      'birthDate': data.birthDate?.toIso8601String(),
      'birthPlace': data.birthPlace.trim(),
      'bio': data.bio.trim(),
      'familyStatus': data.familyStatus.trim(),
      'aboutFamily': data.aboutFamily.trim(),
      'education': data.education.trim(),
      'work': data.work.trim(),
      'hometown': data.hometown.trim(),
      'languages': data.languages.trim(),
      'values': data.values.trim(),
      'religion': data.religion.trim(),
      'interests': data.interests.trim(),
      'profileContributionPolicy': data.profileContributionPolicy,
      'primaryTrustedChannel': data.primaryTrustedChannel,
      'profileVisibility': _encodeProfileVisibility(
        data.profileVisibilityScopes,
        treeIdsBySection: data.profileVisibilityTreeIds,
        branchRootIdsBySection: data.profileVisibilityBranchRootIds,
        userIdsBySection: data.profileVisibilityUserIds,
      ),
    };
  }

  Map<String, dynamic> _extractProfileStatus(Map<String, dynamic> response) {
    final value = response['profileStatus'];
    if (value is Map<String, dynamic>) {
      return value;
    }
    return const <String, dynamic>{};
  }

  UserProfile _toUserProfile(ProfileFormData data) {
    return UserProfile(
      id: data.userId,
      email: data.email ?? '',
      displayName: data.displayName.isNotEmpty
          ? data.displayName
          : _composeDisplayName(data),
      firstName: data.firstName,
      lastName: data.lastName,
      middleName: data.middleName,
      username: data.username,
      photoURL: data.photoUrl,
      phoneNumber: data.phoneNumber,
      gender: data.gender,
      birthDate: data.birthDate,
      maidenName: data.maidenName,
      birthPlace: data.birthPlace.isEmpty ? null : data.birthPlace,
      country: data.countryName,
      city: data.city,
      countryCode: data.countryCode,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      bio: data.bio,
      familyStatus: data.familyStatus,
      aboutFamily: data.aboutFamily,
      education: data.education,
      work: data.work,
      hometown: data.hometown,
      languages: data.languages,
      values: data.values,
      religion: data.religion,
      interests: data.interests,
      profileContributionPolicy: data.profileContributionPolicy,
      profileVisibilityScopes: data.profileVisibilityScopes,
      profileVisibilityTreeIds: data.profileVisibilityTreeIds,
      profileVisibilityBranchRootIds: data.profileVisibilityBranchRootIds,
      profileVisibilityUserIds: data.profileVisibilityUserIds,
    );
  }

  UserProfile _userProfileFromJson(
      String fallbackId, Map<String, dynamic> json) {
    final profile = json['profile'];
    final payload = profile is Map<String, dynamic> ? profile : json;
    final formData = _profileFormDataFromJson({
      'id': payload['id'] ?? fallbackId,
      ...payload,
    });
    return _toUserProfile(formData).copyWith(
      id: fallbackId,
      hiddenProfileSections:
          (payload['hiddenProfileSections'] as List<dynamic>? ?? const [])
              .map((value) => value.toString())
              .toList(),
      profileVisibilityScopes: _decodeProfileVisibility(
        payload['profileVisibility'],
      ),
      profileVisibilityTreeIds: _decodeProfileVisibilityTargets(
        payload['profileVisibility'],
        targetKey: 'treeIds',
      ),
      profileVisibilityBranchRootIds: _decodeProfileVisibilityTargets(
        payload['profileVisibility'],
        targetKey: 'branchRootPersonIds',
      ),
      profileVisibilityUserIds: _decodeProfileVisibilityTargets(
        payload['profileVisibility'],
        targetKey: 'userIds',
      ),
    );
  }

  List<UserProfile> _userProfileListFromResponse(
      Map<String, dynamic> response) {
    final list = response['users'] ?? response['data'];
    if (list is! List<dynamic>) {
      return const [];
    }
    return list
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final id = item['id']?.toString() ?? '';
          return _userProfileFromJson(id, item);
        })
        .where((profile) => profile.id.isNotEmpty)
        .toList();
  }

  Map<String, String> _decodeProfileVisibility(dynamic value) {
    final decoded = <String, String>{..._defaultProfileVisibilityScopes};
    if (value is! Map) {
      return decoded;
    }

    for (final entry in value.entries) {
      final sectionKey = entry.key.toString();
      final sectionValue = entry.value;
      final scope = sectionValue is Map
          ? sectionValue['scope']?.toString()
          : sectionValue?.toString();
      if (scope != null && scope.isNotEmpty) {
        decoded[sectionKey] = scope;
      }
    }
    return decoded;
  }

  Map<String, List<String>> _decodeProfileVisibilityTargets(
    dynamic value, {
    required String targetKey,
  }) {
    final decoded = _defaultProfileVisibilityScopes.map(
      (sectionKey, _) => MapEntry(sectionKey, <String>[]),
    );
    if (value is! Map) {
      return decoded;
    }

    for (final entry in value.entries) {
      final sectionKey = entry.key.toString();
      final sectionValue = entry.value;
      if (sectionValue is! Map) {
        continue;
      }
      decoded[sectionKey] = _normalizeVisibilityTargetList(
        sectionValue[targetKey],
      );
    }
    return decoded;
  }

  Map<String, dynamic> _encodeProfileVisibility(
    Map<String, String> scopes, {
    Map<String, List<String>> treeIdsBySection = const {},
    Map<String, List<String>> branchRootIdsBySection = const {},
    Map<String, List<String>> userIdsBySection = const {},
  }) {
    final resolvedScopes = <String, String>{
      ..._defaultProfileVisibilityScopes,
      ...scopes,
    };
    final resolvedTreeIds = _resolveProfileVisibilityTargets(treeIdsBySection);
    final resolvedBranchRootIds =
        _resolveProfileVisibilityTargets(branchRootIdsBySection);
    final resolvedUserIds = _resolveProfileVisibilityTargets(userIdsBySection);

    return resolvedScopes.map(
      (sectionKey, scope) => MapEntry(sectionKey, {
        'scope': scope,
        if ((resolvedTreeIds[sectionKey] ?? const <String>[]).isNotEmpty)
          'treeIds': resolvedTreeIds[sectionKey],
        if ((resolvedBranchRootIds[sectionKey] ?? const <String>[]).isNotEmpty)
          'branchRootPersonIds': resolvedBranchRootIds[sectionKey],
        if ((resolvedUserIds[sectionKey] ?? const <String>[]).isNotEmpty)
          'userIds': resolvedUserIds[sectionKey],
      }),
    );
  }

  Map<String, List<String>> _resolveProfileVisibilityTargets(
    Map<String, List<String>> rawTargets,
  ) {
    return _defaultProfileVisibilityScopes.map(
      (sectionKey, _) => MapEntry(
        sectionKey,
        _normalizeVisibilityTargetList(rawTargets[sectionKey]),
      ),
    );
  }

  List<String> _normalizeVisibilityTargetList(dynamic rawTargets) {
    if (rawTargets is! List) {
      return const [];
    }
    final seen = <String>{};
    final normalized = <String>[];
    for (final entry in rawTargets) {
      final value = entry.toString().trim();
      if (value.isEmpty || !seen.add(value)) {
        continue;
      }
      normalized.add(value);
    }
    return normalized;
  }

  String _composeDisplayName(ProfileFormData data) {
    return _composeDisplayNameFromParts(
      data.firstName,
      data.middleName,
      data.lastName,
    );
  }

  String _composeDisplayNameFromParts(
    String firstName,
    String middleName,
    String lastName,
  ) {
    return [
      firstName.trim(),
      middleName.trim(),
      lastName.trim(),
    ].where((part) => part.isNotEmpty).join(' ');
  }

  String _detectExtension(String fileName, {String? mimeType}) {
    final normalizedName = fileName.toLowerCase().trim();
    for (final extension in _allowedExtensions) {
      if (normalizedName.endsWith(extension)) {
        return extension;
      }
    }

    switch (mimeType) {
      case 'image/png':
        return '.png';
      case 'image/webp':
        return '.webp';
      case 'image/jpeg':
        return '.jpeg';
      case 'image/jpg':
        return '.jpg';
    }
    return '';
  }

  Future<void> _refreshProfileNotes(
    String userId, {
    ProfileNote? insertedNote,
  }) async {
    final controller = _noteControllers[userId];
    if (controller == null || controller.isClosed) {
      return;
    }

    try {
      final notes = insertedNote == null
          ? await _fetchProfileNotes(userId)
          : [
              insertedNote,
              ...await _fetchProfileNotes(userId).then((items) =>
                  items.where((item) => item.id != insertedNote.id).toList()),
            ];
      controller.add(notes);
    } catch (error, stackTrace) {
      controller.addError(error, stackTrace);
    }
  }

  Future<List<ProfileNote>> _fetchProfileNotes(String userId) async {
    final response = await _requestJson(
      method: 'GET',
      path: '/v1/users/$userId/profile-notes',
    );

    final rawList = response['notes'];
    if (rawList is! List<dynamic>) {
      return const [];
    }

    return rawList
        .whereType<Map<String, dynamic>>()
        .map(_profileNoteFromJson)
        .toList();
  }

  ProfileNote _profileNoteFromResponse(Map<String, dynamic> response) {
    final note = response['note'];
    if (note is Map<String, dynamic>) {
      return _profileNoteFromJson(note);
    }
    return _profileNoteFromJson(response);
  }

  ProfileNote _profileNoteFromJson(Map<String, dynamic> json) {
    final createdAtValue = json['createdAt']?.toString();
    final createdAt = createdAtValue != null && createdAtValue.isNotEmpty
        ? DateTime.tryParse(createdAtValue) ?? DateTime.now()
        : DateTime.now();

    return ProfileNote(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      createdAt: createdAt,
    );
  }
}
