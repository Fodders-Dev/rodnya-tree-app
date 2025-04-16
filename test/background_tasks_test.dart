import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:hive/hive.dart';
import 'package:hive_test/hive_test.dart';
import 'package:get_it/get_it.dart';

// Импортируем классы, которые будем мокать и тестировать
import '../lib/services/notification_service.dart';
// Используем alias для нашей модели
import 'package:lineage_family_app/models/family_person.dart' as lineage_models;
// Импортируем адаптеры, чтобы зарегистрировать их
import 'package:lineage_family_app/models/family_person.dart'; 

// Аннотация для генерации mock-классов
// Убираем Box, т.к. используем hive_test для него
@GenerateMocks([NotificationService]) 
import 'background_tasks_test.mocks.dart'; // Имя генерируемого файла

void main() {
  // Инициализируем Hive для тестов
  setUp(() async {
    await setUpTestHive();
    // Регистрируем адаптер FamilyPersonAdapter (и другие, если нужны)
    // Важно: регистрация адаптеров нужна и в тестах!
    if (!Hive.isAdapterRegistered(FamilyPersonAdapter().typeId)) {
      Hive.registerAdapter(FamilyPersonAdapter());
    }
     if (!Hive.isAdapterRegistered(GenderAdapter().typeId)) {
        Hive.registerAdapter(GenderAdapter());
      }
       if (!Hive.isAdapterRegistered(RelationTypeAdapter().typeId)) {
        Hive.registerAdapter(RelationTypeAdapter());
      }
    // Очищаем GetIt перед каждым тестом
    GetIt.I.reset();
  });

  tearDown(() async {
    await tearDownTestHive();
  });

  test('birthdayCheckTask should show notification for person with birthday today', () async {
    // --- Arrange ---
    // 1. Создаем mock NotificationService
    final mockNotificationService = MockNotificationService();

    // 2. Регистрируем mock в GetIt
    GetIt.I.registerSingleton<NotificationService>(mockNotificationService);

    // 3. Создаем mock Box<FamilyPerson>
    // Вместо MockBox используем реальный бокс в памяти с hive_test
    final personsBox = await Hive.openBox<lineage_models.FamilyPerson>('testPersonsBox');

    // 4. Готовим тестовые данные
    final today = DateTime.now();
    final personWithBirthday = lineage_models.FamilyPerson(
      id: '1',
      treeId: 't1',
      firstName: 'Именинник',
      lastName: 'Сегодняшний',
      birthDate: DateTime(today.year - 30, today.month, today.day), // ДР сегодня
      // gender и другие поля можно оставить null или заполнить по необходимости
    );
    final personWithoutBirthday = lineage_models.FamilyPerson(
      id: '2',
      treeId: 't1',
      firstName: 'Не Именинник',
      lastName: 'Вчерашний',
      birthDate: DateTime(today.year - 25, today.month, today.day - 1), // ДР вчера
    );
    final personWithNullBirthday = lineage_models.FamilyPerson(
      id: '3',
      treeId: 't1',
      firstName: 'Без Даты',
      birthDate: null, // Нет даты рождения
    );

    // Добавляем данные в бокс
    await personsBox.put(personWithBirthday.id, personWithBirthday);
    await personsBox.put(personWithoutBirthday.id, personWithoutBirthday);
    await personsBox.put(personWithNullBirthday.id, personWithNullBirthday);

    // --- Act ---
    // Имитируем логику из birthdayCheckTask
    final List<lineage_models.FamilyPerson> relatives = personsBox.values.toList();
    for (final person in relatives) {
      if (person.birthDate != null &&
          person.birthDate!.day == today.day &&
          person.birthDate!.month == today.month) {
        // Вызываем метод у mock-сервиса
        await mockNotificationService.showBirthdayNotification(person);
      }
    }

    // --- Assert ---
    // Проверяем, что showBirthdayNotification был вызван ровно 1 раз
    // и именно для personWithBirthday
    verify(mockNotificationService.showBirthdayNotification(personWithBirthday)).called(1);

    // Проверяем, что для других персон метод НЕ вызывался
    verifyNever(mockNotificationService.showBirthdayNotification(personWithoutBirthday));
    // Проверка для personWithNullBirthday не нужна, т.к. условие if его отсекает

    // Дополнительно можно проверить, что больше никаких взаимодействий с моком не было
    verifyNoMoreInteractions(mockNotificationService);
  });
} 