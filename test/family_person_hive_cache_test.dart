// Hotfix-3: тест, которого не хватало. Прод-инцидент: FamilyPerson с
// заполненной расширенной анкетой (details: образование/карьера/события)
// падал при записи в Hive-кэш — FamilyPersonDetails/Career/Event не имели
// адаптеров, а генерённый FamilyPersonAdapter.write сериализует details.
//
// Реальный Hive round-trip без фейков: init во временную папку,
// регистрация адаптеров как в проде (app_startup_service), put → get,
// поэлементное равенство.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rodnya/backend/backend_runtime_config.dart';
import 'package:rodnya/models/family_person.dart';
import 'package:rodnya/services/custom_api_auth_service.dart';
import 'package:rodnya/services/custom_api_family_tree_service.dart';
import 'package:rodnya/services/invitation_service.dart';
import 'package:rodnya/services/local_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hotfix-2: локальное хранилище, у которого «сломан бокс» — любая
/// запись кидает HiveError (как в инциденте).
class _BrokenWriteLocalStorage implements LocalStorageService {
  int failedWrites = 0;

  @override
  Future<void> savePerson(FamilyPerson person) async {
    failedWrites += 1;
    throw HiveError('Cannot write, unknown type: FamilyPersonDetails.');
  }

  @override
  Future<void> savePersons(List<FamilyPerson> persons) async {
    failedWrites += 1;
    throw HiveError('Cannot write, unknown type: FamilyPersonDetails.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void registerProdAdapters() {
  // Те же idempotency-гарды, что в AppStartupService._registerHiveAdapters.
  if (!Hive.isAdapterRegistered(FamilyPersonAdapter().typeId)) {
    Hive.registerAdapter(FamilyPersonAdapter());
  }
  if (!Hive.isAdapterRegistered(GenderAdapter().typeId)) {
    Hive.registerAdapter(GenderAdapter());
  }
  if (!Hive.isAdapterRegistered(FamilyPersonDetailsAdapter().typeId)) {
    Hive.registerAdapter(FamilyPersonDetailsAdapter());
  }
  if (!Hive.isAdapterRegistered(CareerAdapter().typeId)) {
    Hive.registerAdapter(CareerAdapter());
  }
  if (!Hive.isAdapterRegistered(EventAdapter().typeId)) {
    Hive.registerAdapter(EventAdapter());
  }
}

FamilyPerson buildFilledPerson() => FamilyPerson(
      id: 'person-1',
      treeId: 'tree-1',
      userId: 'user-1',
      name: 'Кузнецова Наталья Геннадьевна',
      gender: Gender.female,
      birthDate: DateTime(1955, 6, 12),
      birthPlace: 'Самара',
      bio: 'Любит огород и внуков.',
      isAlive: true,
      // Ручные поля read'а в family_person.g.dart (hotfix-1b): слепая
      // регенерация их теряет — тест обязан это ловить.
      photoUrl: 'https://cdn.example.com/persons/natalya.jpg',
      photoGallery: const [
        {
          'id': 'media-1',
          'url': 'https://cdn.example.com/persons/natalya.jpg',
          'type': 'image',
          'isPrimary': true,
        },
      ],
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 2, 2),
      details: FamilyPersonDetails(
        education: 'Самарский политехнический институт',
        career: [
          Career(
            company: 'Школа №12',
            position: 'Учитель математики',
            startDate: DateTime(1978, 9, 1),
            endDate: DateTime(2010, 6, 30),
          ),
          Career(
            company: 'Дача',
            position: 'Главный агроном',
            startDate: DateTime(2010, 7, 1),
            isCurrent: true,
          ),
        ],
        importantEvents: [
          Event(
            title: 'Свадьба',
            description: 'Поженились с Андреем',
            date: DateTime(1976, 8, 14),
            location: 'Самара',
            repeatsAnnually: true,
          ),
          Event(
            title: 'Переезд в новый дом',
            date: DateTime(1990, 5, 3),
          ),
        ],
        customData: {'любимыйЦветок': 'пионы', 'внуков': 3},
      ),
    );

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('rodnya_hive_test');
    Hive.init(tempDir.path);
    registerProdAdapters();
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test(
      'FamilyPerson с полностью заполненной анкетой переживает Hive round-trip',
      () async {
    final person = buildFilledPerson();

    final box = await Hive.openBox<FamilyPerson>('persons_roundtrip');
    // На коде без адаптеров details именно эта строка кидала
    // HiveError: Cannot write, unknown type: FamilyPersonDetails.
    await box.put(person.id, person);
    await box.close();

    // Перечитываем с диска (не из memory-кэша бокса).
    final reopened = await Hive.openBox<FamilyPerson>('persons_roundtrip');
    final restored = reopened.get(person.id);

    expect(restored, isNotNull);
    expect(restored!.id, person.id);
    expect(restored.treeId, person.treeId);
    expect(restored.name, person.name);
    expect(restored.gender, Gender.female);
    expect(restored.birthDate, DateTime(1955, 6, 12));
    expect(restored.bio, person.bio);
    expect(restored.photoUrl, person.photoUrl);
    expect(restored.photoUrl, isNotNull);
    expect(restored.photoGallery, hasLength(1));
    expect(restored.photoGallery.first['isPrimary'], isTrue);
    expect(restored.visibility, person.visibility);

    final details = restored.details;
    expect(details, isNotNull);
    expect(details!.education, 'Самарский политехнический институт');

    final career = details.career;
    expect(career, hasLength(2));
    expect(career![0].company, 'Школа №12');
    expect(career[0].position, 'Учитель математики');
    expect(career[0].startDate, DateTime(1978, 9, 1));
    expect(career[0].endDate, DateTime(2010, 6, 30));
    expect(career[0].isCurrent, isFalse);
    expect(career[1].company, 'Дача');
    expect(career[1].isCurrent, isTrue);
    expect(career[1].endDate, isNull);

    final events = details.importantEvents;
    expect(events, hasLength(2));
    expect(events![0].title, 'Свадьба');
    expect(events[0].description, 'Поженились с Андреем');
    expect(events[0].date, DateTime(1976, 8, 14));
    expect(events[0].location, 'Самара');
    expect(events[0].repeatsAnnually, isTrue);
    expect(events[1].title, 'Переезд в новый дом');
    expect(events[1].repeatsAnnually, isFalse);
    expect(events[1].location, isNull);

    expect(details.customData, isNotNull);
    expect(details.customData!['любимыйЦветок'], 'пионы');
    expect(details.customData!['внуков'], 3);
  });

  test('старый формат записи (details == null) читается как есть', () async {
    // До хотфикса записи с non-null details никогда не ложились на диск
    // (write падал до коммита фрейма) — в проде лежат только null.
    final legacyPerson = FamilyPerson(
      id: 'person-legacy',
      treeId: 'tree-1',
      name: 'Кузнецов Андрей Анатольевич',
      gender: Gender.male,
      isAlive: true,
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    );

    final box = await Hive.openBox<FamilyPerson>('persons_legacy');
    await box.put(legacyPerson.id, legacyPerson);
    await box.close();

    final reopened = await Hive.openBox<FamilyPerson>('persons_legacy');
    final restored = reopened.get(legacyPerson.id);

    expect(restored, isNotNull);
    expect(restored!.details, isNull);
    expect(restored.name, legacyPerson.name);
  });

  test(
      'hotfix-2: сломанный кэш не валит getRelatives — данные возвращаются',
      () async {
    SharedPreferences.setMockInitialValues({});
    final client = MockClient((request) async {
      if (request.url.path == '/v1/trees/tree-1/persons' &&
          request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'persons': [
              {
                'id': 'person-1',
                'treeId': 'tree-1',
                'name': 'Кузнецова Наталья Геннадьевна',
                'gender': 'female',
                'isAlive': true,
                'details': {
                  'education': 'институт',
                  'career': [
                    {'company': 'Школа №12', 'isCurrent': true},
                  ],
                },
              },
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
        'missingFields': const [],
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

    final brokenStorage = _BrokenWriteLocalStorage();
    final treeService = CustomApiFamilyTreeService(
      authService: authService,
      runtimeConfig: const BackendRuntimeConfig(
        apiBaseUrl: 'https://api.example.ru',
      ),
      httpClient: client,
      localStorageService: brokenStorage,
    );

    // До hotfix-2 HiveError из кэша пробрасывался и валил загрузку у
    // зрителей дерева. Теперь: данные на руках, кэш — best-effort.
    final relatives = await treeService.getRelatives('tree-1');

    expect(brokenStorage.failedWrites, greaterThan(0));
    expect(relatives, hasLength(1));
    expect(relatives.first.name, 'Кузнецова Наталья Геннадьевна');
    expect(relatives.first.details?.education, 'институт');
  });
}
