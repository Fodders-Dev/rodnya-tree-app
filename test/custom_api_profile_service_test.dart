import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rodnya/backend/backend_runtime_config.dart';
import 'package:rodnya/backend/interfaces/storage_service_interface.dart';
import 'package:rodnya/backend/models/profile_form_data.dart';
import 'package:rodnya/models/profile_note.dart';
import 'package:rodnya/services/custom_api_auth_service.dart';
import 'package:rodnya/services/custom_api_profile_service.dart';
import 'package:rodnya/services/invitation_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('CustomApiProfileService loads and saves bootstrap profile data',
      () async {
    final client = MockClient((request) async {
      if (request.url.path == '/v1/profile/me/bootstrap' &&
          request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'profile': {
              'id': 'user-1',
              'email': 'dev@rodnya.app',
              'firstName': 'Иван',
              'lastName': 'Иванов',
              'middleName': 'Иванович',
              'displayName': 'Иван Иванович Иванов',
              'username': 'ivanov',
              'phoneNumber': '+79990001122',
              'countryCode': '+7',
              'countryName': 'Россия',
              'city': 'Москва',
              'gender': 'male',
              'bio': 'Люблю семейные архивы',
              'familyStatus': 'Женат',
              'aboutFamily': 'Собираю семейные истории для детей и внуков.',
              'education': 'МГУ',
              'work': 'Родня',
              'hometown': 'Тула',
              'languages': 'Русский, английский',
              'values': 'Семья',
              'religion': 'Православие',
              'interests': 'Генеалогия, архивы, путешествия',
              'profileVisibility': {
                'about': {
                  'scope': 'specific_trees',
                  'treeIds': ['tree-family'],
                },
                'background': {'scope': 'public'},
                'worldview': {
                  'scope': 'specific_users',
                  'userIds': ['user-2'],
                },
                'contacts': {
                  'scope': 'specific_branches',
                  'branchRootPersonIds': ['person-branch-1'],
                },
              },
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.url.path == '/v1/profile/me/bootstrap' &&
          request.method == 'PUT') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['firstName'], 'Пётр');
        expect(body['username'], 'petrov');
        expect(body.containsKey('isPhoneVerified'), isFalse);
        expect(body['bio'], 'Новый текст о себе');
        expect(body['aboutFamily'], 'Хочу сохранить семейные истории.');
        expect(body['hometown'], 'Казань');
        expect(body['languages'], 'Русский, татарский');
        expect(body['interests'], 'Семейные встречи и поездки');
        expect(
          body['profileVisibility'],
          {
            'contacts': {
              'scope': 'specific_branches',
              'branchRootPersonIds': ['person-1', 'person-2'],
            },
            'about': {
              'scope': 'specific_trees',
              'treeIds': ['tree-1', 'tree-2'],
            },
            'background': {'scope': 'shared_trees'},
            'worldview': {
              'scope': 'specific_users',
              'userIds': ['user-9'],
            },
          },
        );

        return http.Response(
          jsonEncode({
            'profile': {
              'id': 'user-1',
              'email': 'dev@rodnya.app',
              'firstName': body['firstName'],
              'lastName': body['lastName'],
              'middleName': body['middleName'],
              'displayName': body['displayName'],
              'username': body['username'],
              'phoneNumber': body['phoneNumber'],
              'countryCode': body['countryCode'],
              'countryName': body['countryName'],
              'city': body['city'],
              'gender': body['gender'],
              'bio': body['bio'],
              'familyStatus': body['familyStatus'],
              'aboutFamily': body['aboutFamily'],
              'education': body['education'],
              'work': body['work'],
              'hometown': body['hometown'],
              'languages': body['languages'],
              'values': body['values'],
              'religion': body['religion'],
              'interests': body['interests'],
              'profileVisibility': body['profileVisibility'],
            },
            'profileStatus': {
              'isComplete': true,
              'missingFields': [],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.url.path == '/v1/auth/session') {
        return http.Response('{"message":"offline"}', 500);
      }

      return http.Response('{"message":"not found"}', 404);
    });

    final runtimeConfig = const BackendRuntimeConfig(
      apiBaseUrl: 'https://api.example.ru',
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'custom_api_session_v1',
      jsonEncode({
        'accessToken': 'access-token',
        'refreshToken': 'refresh-token',
        'userId': 'user-1',
        'email': 'dev@rodnya.app',
        'displayName': 'Dev User',
        'providerIds': ['password'],
        'isProfileComplete': false,
        'missingFields': ['phoneNumber', 'username'],
      }),
    );

    final authService = await CustomApiAuthService.create(
      httpClient: client,
      preferences: prefs,
      runtimeConfig: runtimeConfig,
      invitationService: InvitationService(),
    );
    final profileService = await CustomApiProfileService.create(
      authService: authService,
      httpClient: client,
      preferences: prefs,
      runtimeConfig: runtimeConfig,
    );

    final bootstrap = await profileService.getCurrentUserProfileFormData();
    expect(bootstrap.firstName, 'Иван');
    expect(bootstrap.username, 'ivanov');
    expect(bootstrap.countryName, 'Россия');
    expect(bootstrap.bio, 'Люблю семейные архивы');
    expect(
        bootstrap.aboutFamily, 'Собираю семейные истории для детей и внуков.');
    expect(bootstrap.hometown, 'Тула');
    expect(bootstrap.languages, 'Русский, английский');
    expect(bootstrap.interests, 'Генеалогия, архивы, путешествия');
    expect(bootstrap.profileVisibilityScopes['background'], 'public');
    expect(bootstrap.profileVisibilityScopes['about'], 'specific_trees');
    expect(bootstrap.profileVisibilityTreeIds['about'], ['tree-family']);
    expect(bootstrap.profileVisibilityScopes['contacts'], 'specific_branches');
    expect(
      bootstrap.profileVisibilityBranchRootIds['contacts'],
      ['person-branch-1'],
    );
    expect(bootstrap.profileVisibilityScopes['worldview'], 'specific_users');
    expect(bootstrap.profileVisibilityUserIds['worldview'], ['user-2']);

    await profileService.saveCurrentUserProfileFormData(
      const ProfileFormData(
        userId: 'user-1',
        email: 'dev@rodnya.app',
        firstName: 'Пётр',
        lastName: 'Петров',
        middleName: '',
        username: 'petrov',
        phoneNumber: '+79991112233',
        countryCode: '+7',
        countryName: 'Россия',
        city: 'Казань',
        bio: 'Новый текст о себе',
        familyStatus: 'Женат',
        aboutFamily: 'Хочу сохранить семейные истории.',
        education: 'МГУ',
        work: 'Родня',
        hometown: 'Казань',
        languages: 'Русский, татарский',
        values: 'Семья',
        religion: 'Православие',
        interests: 'Семейные встречи и поездки',
        profileVisibilityScopes: {
          'contacts': 'specific_branches',
          'about': 'specific_trees',
          'background': 'shared_trees',
          'worldview': 'specific_users',
        },
        profileVisibilityTreeIds: {
          'contacts': [],
          'about': ['tree-1', 'tree-2'],
          'background': [],
          'worldview': [],
        },
        profileVisibilityBranchRootIds: {
          'contacts': ['person-1', 'person-2'],
          'about': [],
          'background': [],
          'worldview': [],
        },
        profileVisibilityUserIds: {
          'contacts': [],
          'about': [],
          'background': [],
          'worldview': ['user-9'],
        },
      ),
    );

    final savedProfile = await profileService.getCurrentUserProfile();
    expect(savedProfile?.firstName, 'Пётр');
    expect(savedProfile?.username, 'petrov');
    expect(savedProfile?.bio, 'Новый текст о себе');
    expect(savedProfile?.aboutFamily, 'Хочу сохранить семейные истории.');
    expect(savedProfile?.hometown, 'Казань');
    expect(savedProfile?.languages, 'Русский, татарский');
    expect(savedProfile?.interests, 'Семейные встречи и поездки');
    expect(savedProfile?.profileVisibilityScopes?['about'], 'specific_trees');
    expect(
        savedProfile?.profileVisibilityTreeIds?['about'], ['tree-1', 'tree-2']);
    expect(savedProfile?.profileVisibilityScopes?['contacts'],
        'specific_branches');
    expect(
      savedProfile?.profileVisibilityBranchRootIds?['contacts'],
      ['person-1', 'person-2'],
    );
    expect(savedProfile?.profileVisibilityUserIds?['worldview'], ['user-9']);

    final profileStatus = await authService.checkProfileCompleteness();
    expect(profileStatus['isComplete'], isTrue);
    expect(profileStatus['missingFields'], isEmpty);
  });

  test('CustomApiProfileService uploads profile photo and manages notes',
      () async {
    final client = MockClient((request) async {
      if (request.url.path == '/v1/profile/me' && request.method == 'PATCH') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(
          body['photoUrl'],
          'https://api.example.ru/media/avatars/user-1/avatar.png',
        );

        return http.Response(
          jsonEncode({
            'user': {
              'id': 'user-1',
              'email': 'dev@rodnya.app',
              'displayName': 'Dev User',
              'photoUrl': body['photoUrl'],
            },
            'profileStatus': {
              'isComplete': true,
              'missingFields': [],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.url.path == '/v1/users/user-1/profile-notes' &&
          request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'notes': [
              {
                'id': 'note-1',
                'title': 'Первая заметка',
                'content': 'Содержимое заметки',
                'createdAt': '2026-03-27T10:00:00.000Z',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.url.path == '/v1/users/user-1/profile-notes' &&
          request.method == 'POST') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['title'], 'Новая заметка');
        expect(body['content'], 'Новый текст');

        return http.Response(
          jsonEncode({
            'note': {
              'id': 'note-2',
              'title': body['title'],
              'content': body['content'],
              'createdAt': '2026-03-27T11:00:00.000Z',
            },
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.url.path == '/v1/users/user-1/profile-notes/note-1' &&
          request.method == 'PATCH') {
        return http.Response(
          jsonEncode({
            'note': {
              'id': 'note-1',
              'title': 'Обновлённая заметка',
              'content': 'Исправленный текст',
              'createdAt': '2026-03-27T10:00:00.000Z',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      if (request.url.path == '/v1/users/user-1/profile-notes/note-1' &&
          request.method == 'DELETE') {
        return http.Response('', 204);
      }

      if (request.url.path == '/v1/auth/session') {
        return http.Response('{"message":"offline"}', 500);
      }

      return http.Response('{"message":"not found"}', 404);
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'custom_api_session_v1',
      jsonEncode({
        'accessToken': 'access-token',
        'refreshToken': 'refresh-token',
        'userId': 'user-1',
        'email': 'dev@rodnya.app',
        'displayName': 'Dev User',
        'providerIds': ['password'],
        'isProfileComplete': false,
        'missingFields': ['photoUrl'],
      }),
    );
    await prefs.setString(
      'custom_api_profile_form_v1',
      jsonEncode({
        'userId': 'user-1',
        'email': 'dev@rodnya.app',
        'firstName': 'Dev',
        'lastName': 'User',
        'middleName': '',
        'displayName': 'Dev User',
        'username': 'devuser',
        'phoneNumber': '+79990001122',
        'countryCode': '+7',
        'countryName': 'Россия',
        'city': 'Москва',
        'photoUrl': null,
        'gender': 'unknown',
      }),
    );

    final authService = await CustomApiAuthService.create(
      httpClient: client,
      preferences: prefs,
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
      invitationService: InvitationService(),
    );

    final profileService = await CustomApiProfileService.create(
      authService: authService,
      httpClient: client,
      preferences: prefs,
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
      storageService: _FakeStorageService(
        uploadedUrl: 'https://api.example.ru/media/avatars/user-1/avatar.png',
      ),
    );

    final photoUrl = await profileService.uploadProfilePhoto(
      XFile.fromData(
        Uint8List.fromList(List<int>.filled(8, 1)),
        name: 'avatar.png',
        mimeType: 'image/png',
      ),
    );
    expect(photoUrl, 'https://api.example.ru/media/avatars/user-1/avatar.png');

    final notesStream = profileService.getProfileNotesStream('user-1');
    final initialNotes = await notesStream.first;
    expect(initialNotes, hasLength(1));
    expect(initialNotes.first.title, 'Первая заметка');

    await profileService.addProfileNote(
      'user-1',
      'Новая заметка',
      'Новый текст',
    );
    await profileService.updateProfileNote(
      'user-1',
      ProfileNote(
        id: 'note-1',
        title: 'Обновлённая заметка',
        content: 'Исправленный текст',
        createdAt: initialNotes.first.createdAt,
      ),
    );
    await profileService.deleteProfileNote('user-1', 'note-1');
  });

  test('CustomApiProfileService ignores legacy cached profile of another user',
      () async {
    final client = MockClient((request) async {
      if (request.url.path == '/v1/profile/me/bootstrap' &&
          request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'profile': {
              'id': 'user-1',
              'email': 'dev@rodnya.app',
              'firstName': 'Артем',
              'lastName': 'Кузнецов',
              'middleName': 'Андреевич',
              'displayName': 'Артем Андреевич Кузнецов',
              'username': 'artem',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      return http.Response('{"message":"not found"}', 404);
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'custom_api_session_v1',
      jsonEncode({
        'accessToken': 'access-token',
        'refreshToken': 'refresh-token',
        'userId': 'user-1',
        'email': 'dev@rodnya.app',
        'displayName': 'Dev User',
        'providerIds': ['password'],
        'isProfileComplete': true,
        'missingFields': [],
      }),
    );
    await prefs.setString(
      'custom_api_profile_form_v1',
      jsonEncode({
        'userId': 'user-2',
        'email': 'smoke@rodnya.app',
        'firstName': 'Prod',
        'lastName': 'UI Smoke',
        'displayName': 'Prod UI Smoke',
        'username': 'smoke',
      }),
    );

    final authService = await CustomApiAuthService.create(
      httpClient: client,
      preferences: prefs,
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
      invitationService: InvitationService(),
    );

    final profileService = await CustomApiProfileService.create(
      authService: authService,
      httpClient: client,
      preferences: prefs,
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
    );

    final profile = await profileService.getCurrentUserProfile();
    expect(profile?.displayName, 'Артем Андреевич Кузнецов');
    expect(profile?.username, 'artem');
  });

  test('CustomApiProfileService loads account linking status', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/v1/profile/me/account-linking-status' &&
          request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'linkedProviderIds': ['password', 'telegram'],
            'trustedChannels': [
              {
                'provider': 'telegram',
                'label': 'Telegram',
                'description': 'Подтверждённый канал связи.',
                'verificationLabel': 'Связь подтверждена через Telegram',
                'isLinked': true,
                'isTrustedChannel': true,
                'isLoginMethod': true,
                'isPrimary': true,
              },
            ],
            'primaryTrustedChannel': {
              'provider': 'telegram',
              'label': 'Telegram',
              'description': 'Подтверждённый канал связи.',
              'verificationLabel': 'Связь подтверждена через Telegram',
              'isLinked': true,
              'isTrustedChannel': true,
              'isLoginMethod': true,
              'isPrimary': true,
            },
            'verificationSummary': {
              'title': 'Аккаунт подтверждён через Telegram',
              'detail': 'Основной канал: Telegram',
            },
            'discoveryModes': [
              'username',
              'profile_code',
              'email',
              'invite_link',
              'claim_link',
              'qr',
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      return http.Response('{"message":"not found"}', 404);
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'custom_api_session_v1',
      jsonEncode({
        'accessToken': 'access-token',
        'refreshToken': 'refresh-token',
        'userId': 'user-1',
        'email': 'dev@rodnya.app',
        'displayName': 'Dev User',
        'providerIds': ['password'],
        'isProfileComplete': true,
        'missingFields': const <String>[],
      }),
    );

    final authService = await CustomApiAuthService.create(
      httpClient: client,
      preferences: prefs,
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
      invitationService: InvitationService(),
    );

    final profileService = await CustomApiProfileService.create(
      authService: authService,
      httpClient: client,
      preferences: prefs,
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
    );

    final status = await profileService.getCurrentAccountLinkingStatus();

    expect(status.linkedProviderIds, containsAll(['password', 'telegram']));
    expect(status.primaryTrustedChannelProvider, 'telegram');
    expect(status.summaryTitle, 'Аккаунт подтверждён через Telegram');
    expect(
      status.discoveryModes,
      containsAll(['username', 'profile_code', 'invite_link']),
    );
  });
}

class _FakeStorageService implements StorageServiceInterface {
  const _FakeStorageService({required this.uploadedUrl});

  final String uploadedUrl;

  @override
  Future<bool> deleteImage(String imageUrl) async => true;

  @override
  Future<String?> uploadImage(XFile imageFile, String folder) async =>
      uploadedUrl;

  @override
  Future<String?> uploadProfileImage(XFile imageFile) async => uploadedUrl;

  @override
  Future<String?> uploadBytes({
    required String bucket,
    required String path,
    required Uint8List fileBytes,
    FileOptions? fileOptions,
  }) async =>
      uploadedUrl;
}
