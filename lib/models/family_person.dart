import '../utils/date_parser.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../utils/url_utils.dart';

part 'family_person.g.dart';

@HiveType(typeId: 100)
enum Gender {
  @HiveField(0)
  male,
  @HiveField(1)
  female,
  @HiveField(2)
  other,
  @HiveField(3)
  unknown,
}

// Добавляем класс Person как псевдоним для FamilyPerson
// для обратной совместимости с существующим кодом
class Person {
  final String id;
  final String treeId;
  final String? userId;
  final String? identityId;
  final String firstName;
  final String lastName;
  final String? middleName;
  final String? maidenName;
  final String? _photoUrl;
  final Gender gender;
  final DateTime? birthDate;
  final String? birthPlace;
  final DateTime? deathDate;
  final String? deathPlace;
  final String? notes;

  Person({
    required this.id,
    required this.treeId,
    this.userId,
    this.identityId,
    required this.firstName,
    required this.lastName,
    this.middleName,
    this.maidenName,
    String? photoUrl,
    required this.gender,
    this.birthDate,
    this.birthPlace,
    this.deathDate,
    this.deathPlace,
    this.notes,
  }) : _photoUrl = UrlUtils.normalizeImageUrl(photoUrl);

  String? get photoUrl => _photoUrl;
  String? get primaryPhotoUrl => _photoUrl;

  // Геттер для получения полного имени
  String get name {
    final parts = [
      lastName,
      firstName,
      middleName,
    ].where((part) => part != null && part.isNotEmpty).toList();
    return parts.join(' ');
  }

  // Фабричный метод для создания Person из FamilyPerson
  factory Person.fromFamilyPerson(FamilyPerson person) {
    // Разбиваем полное имя на части (фамилия, имя, отчество)
    final nameParts = person.name.split(' ');
    String lastName = '';
    String firstName = '';
    String? middleName;

    if (nameParts.isNotEmpty) {
      lastName = nameParts[0];
    }
    if (nameParts.length >= 2) {
      firstName = nameParts[1];
    }
    if (nameParts.length >= 3) {
      middleName = nameParts.sublist(2).join(' ');
    }

    debugPrint('Преобразование FamilyPerson в Person:');
    debugPrint('Исходное имя: ${person.name}');
    debugPrint(
      'Разбитое имя: фамилия=$lastName, имя=$firstName, отчество=$middleName',
    );

    return Person(
      id: person.id,
      treeId: person.treeId,
      userId: person.userId,
      identityId: person.identityId,
      firstName: firstName,
      lastName: lastName,
      middleName: middleName,
      maidenName: person.maidenName,
      photoUrl: person.photoUrl,
      gender: person.gender,
      birthDate: person.birthDate,
      birthPlace: person.birthPlace,
      deathDate: person.deathDate,
      deathPlace: person.deathPlace,
      notes: person.notes,
    );
  }

  // Метод для преобразования Person в FamilyPerson
  FamilyPerson toFamilyPerson() {
    return FamilyPerson(
      id: id,
      treeId: treeId,
      userId: userId,
      identityId: identityId,
      name: name,
      maidenName: maidenName,
      photoUrl: photoUrl,
      gender: gender,
      birthDate: birthDate,
      birthPlace: birthPlace,
      deathDate: deathDate,
      deathPlace: deathPlace,
      isAlive: deathDate == null,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      notes: notes,
    );
  }

  // Оператор преобразования для автоматического преобразования FamilyPerson в Person
  static Person? fromDynamic(dynamic person) {
    if (person == null) return null;
    if (person is Person) return person;
    if (person is FamilyPerson) return Person.fromFamilyPerson(person);
    return null;
  }
}

@HiveType(typeId: 1)
class FamilyPerson extends HiveObject {
  // <<< НОВОЕ: Статическая константа для представления "пустого" или несуществующего человека >>>
  static final FamilyPerson empty = FamilyPerson(
    id: '__EMPTY__', // Уникальный ID, который не должен пересекаться с реальными
    treeId: '',
    name: '',
    gender: Gender.unknown,
    isAlive: false,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      0,
    ), // Используем минимальную дату
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  @HiveField(0)
  final String id;
  @HiveField(1)
  final String treeId;
  @HiveField(2)
  final String? userId; // Если это реальный пользователь, тут будет его ID
  @HiveField(25)
  final String?
      identityId; // Общая identity-связь между карточками в разных деревьях
  @HiveField(3)
  final String name;
  @HiveField(4)
  final String? maidenName; // Девичья фамилия (если применимо)
  @HiveField(5)
  final String? _photoUrl;
  @HiveField(6)
  final Gender gender;
  @HiveField(7)
  final DateTime? birthDate;
  @HiveField(8)
  final String? birthPlace;
  @HiveField(9)
  final DateTime? deathDate;
  @HiveField(10)
  final String? deathPlace;
  @HiveField(11)
  final String? bio;
  @HiveField(13)
  final bool isAlive;
  @HiveField(14)
  final String? creatorId; // Кто создал запись
  @HiveField(15)
  final DateTime createdAt;
  @HiveField(16)
  final DateTime updatedAt;
  @HiveField(17)
  final String? notes;
  @HiveField(18)
  final String? relation; // Тип связи относительно пользователя
  @HiveField(19)
  final List<String>? parentIds; // ID родителей
  @HiveField(20)
  final List<String>? childrenIds; // ID детей
  @HiveField(21)
  final String? spouseId; // ID супруга/супруги (основной)
  @HiveField(22)
  final List<String>? siblingIds; // ID братьев/сестер
  @HiveField(23)
  final FamilyPersonDetails?
      details; // Подробная информация (образование, карьера и т.д.)
  @HiveField(24)
  final List<Map<String, dynamic>> _photoGallery;

  String? get photoUrl => _photoUrl;
  String? get primaryPhotoUrl => _photoUrl;
  List<Map<String, dynamic>> get photoGallery => List.unmodifiable(
        _photoGallery.map(
          (entry) => Map<String, dynamic>.from(entry),
        ),
      );

  // Добавляем необходимые геттеры для работы с древовидной структурой
  List<String> get spouseIds =>
      _getListOrEmpty(spouseId != null ? [spouseId!] : []);
  List<SpouseInfo> get spouses => []; // Для обратной совместимости

  // Вспомогательный метод для получения списка или пустого списка
  List<String> _getListOrEmpty(List<String>? list) {
    return list ?? [];
  }

  FamilyPerson({
    required this.id,
    required this.treeId,
    this.userId,
    this.identityId,
    required this.name,
    this.maidenName,
    String? photoUrl,
    required this.gender,
    this.birthDate,
    this.birthPlace,
    this.deathDate,
    this.deathPlace,
    this.bio,
    required this.isAlive,
    this.creatorId,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
    this.relation,
    this.parentIds,
    this.childrenIds,
    this.spouseId,
    this.siblingIds,
    this.details,
    List<Map<String, dynamic>>? photoGallery,
  })  : _photoGallery = _normalizePhotoGallery(
          photoGallery,
          fallbackPrimaryPhotoUrl: photoUrl,
        ),
        _photoUrl = _resolvePrimaryPhotoUrl(
          _normalizePhotoGallery(
            photoGallery,
            fallbackPrimaryPhotoUrl: photoUrl,
          ),
          fallbackPrimaryPhotoUrl: photoUrl,
        );

  static List<Map<String, dynamic>> _normalizePhotoGallery(
    List<Map<String, dynamic>>? rawGallery, {
    String? fallbackPrimaryPhotoUrl,
  }) {
    final normalizedPrimaryPhotoUrl =
        UrlUtils.normalizeImageUrl(fallbackPrimaryPhotoUrl);
    final normalizedEntries = <Map<String, dynamic>>[];
    final seenIds = <String>{};
    final seenUrls = <String>{};

    void addEntry(Map<String, dynamic> rawEntry) {
      final normalizedUrl = UrlUtils.normalizeImageUrl(rawEntry['url']);
      if (normalizedUrl == null || seenUrls.contains(normalizedUrl)) {
        return;
      }

      final rawId = rawEntry['id']?.toString().trim();
      final mediaId =
          (rawId != null && rawId.isNotEmpty && !seenIds.contains(rawId))
              ? rawId
              : 'photo-${normalizedEntries.length + 1}';
      seenIds.add(mediaId);
      seenUrls.add(normalizedUrl);

      normalizedEntries.add({
        'id': mediaId,
        'url': normalizedUrl,
        'thumbnailUrl': UrlUtils.normalizeImageUrl(rawEntry['thumbnailUrl']),
        'type': rawEntry['type']?.toString() == 'video' ? 'video' : 'image',
        'contentType': rawEntry['contentType']?.toString(),
        'caption': rawEntry['caption']?.toString(),
        'createdAt': rawEntry['createdAt']?.toString(),
        'updatedAt': rawEntry['updatedAt']?.toString(),
        'isPrimary': rawEntry['isPrimary'] == true,
      });
    }

    if (rawGallery != null) {
      for (final entry in rawGallery) {
        addEntry(Map<String, dynamic>.from(entry));
      }
    }

    if (normalizedPrimaryPhotoUrl != null &&
        normalizedEntries
            .every((entry) => entry['url'] != normalizedPrimaryPhotoUrl)) {
      addEntry({
        'url': normalizedPrimaryPhotoUrl,
        'type': 'image',
        'isPrimary': true,
      });
    }

    final resolvedPrimaryPhotoUrl = normalizedPrimaryPhotoUrl ??
        normalizedEntries
            .cast<Map<String, dynamic>?>()
            .firstWhere(
              (entry) => entry?['isPrimary'] == true,
              orElse: () => null,
            )?['url']
            ?.toString() ??
        (normalizedEntries.isNotEmpty
            ? normalizedEntries.first['url']?.toString()
            : null);

    if (resolvedPrimaryPhotoUrl == null) {
      return const <Map<String, dynamic>>[];
    }

    final primaryIndex = normalizedEntries.indexWhere(
      (entry) => entry['url'] == resolvedPrimaryPhotoUrl,
    );
    if (primaryIndex > 0) {
      final primaryEntry = normalizedEntries.removeAt(primaryIndex);
      normalizedEntries.insert(0, primaryEntry);
    }

    for (final entry in normalizedEntries) {
      entry['isPrimary'] = entry['url'] == resolvedPrimaryPhotoUrl;
    }

    return normalizedEntries;
  }

  static String? _resolvePrimaryPhotoUrl(
    List<Map<String, dynamic>> photoGallery, {
    String? fallbackPrimaryPhotoUrl,
  }) {
    return UrlUtils.normalizeImageUrl(fallbackPrimaryPhotoUrl) ??
        (photoGallery.isNotEmpty
            ? photoGallery.first['url']?.toString()
            : null);
  }

  static List<Map<String, dynamic>> _photoGalleryFromDynamic(dynamic rawValue) {
    if (rawValue is! List) {
      return const <Map<String, dynamic>>[];
    }

    return rawValue
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  /// Возвращает отображаемое имя (синоним для поля `name`).
  String get displayName => name;

  /// Возвращает инициалы (первые буквы имени и фамилии, если есть).
  String get initials {
    if (name.isEmpty) return '?';
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      // Фамилия и Имя
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.length == 1) {
      // Только Имя (или Фамилия)
      return parts[0][0].toUpperCase();
    } else {
      return '?';
    }
  }

  factory FamilyPerson.fromFirestore(dynamic doc) {
    final data =
        (doc.data != null ? (doc.data() as Map<String, dynamic>?) : null) ?? {};

    Gender personGender = Gender.unknown;
    if (data['gender'] != null) {
      try {
        personGender = Gender.values.firstWhere(
          (e) => e.toString().split('.').last == data['gender'],
        );
      } catch (e) {
        /* оставим unknown */
      }
    }

    return FamilyPerson(
      id: doc.id,
      treeId: data['treeId'] ?? '',
      userId: data['userId'],
      identityId: data['identityId'],
      name: data['name'] ?? '',
      maidenName: data['maidenName'],
      photoUrl: data['primaryPhotoUrl'] ?? data['photoUrl'],
      gender: personGender,
      birthDate: parseDateTime(data['birthDate']),
      birthPlace: data['birthPlace'],
      deathDate: parseDateTime(data['deathDate']),
      deathPlace: data['deathPlace'],
      bio: data['bio'],
      isAlive: data['isAlive'] ?? (data['deathDate'] == null),
      creatorId: data['creatorId'],
      createdAt: parseDateTimeRequired(data['createdAt']),
      updatedAt: parseDateTimeRequired(data['updatedAt']),
      notes: data['notes'],
      relation: data['relation'],
      parentIds: List<String>.from(data['parentIds'] ?? []),
      childrenIds: List<String>.from(data['childrenIds'] ?? []),
      spouseId: data['spouseId'],
      siblingIds: List<String>.from(data['siblingIds'] ?? []),
      photoGallery: _photoGalleryFromDynamic(data['photoGallery']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'treeId': treeId,
      'userId': userId,
      'identityId': identityId,
      'name': name,
      'maidenName': maidenName,
      'photoUrl': photoUrl,
      'primaryPhotoUrl': primaryPhotoUrl,
      'photoGallery': photoGallery,
      'gender': gender.toString().split('.').last,
      'birthDate': birthDate?.toIso8601String(),
      'birthPlace': birthPlace,
      'deathDate': deathDate?.toIso8601String(),
      'deathPlace': deathPlace,
      'bio': bio,
      'isAlive': isAlive,
      'creatorId': creatorId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'notes': notes,
    };
  }

  // Добавляем метод для расчета возраста
  int? getAge() {
    if (birthDate == null) return null;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dob = DateTime(birthDate!.year, birthDate!.month, birthDate!.day);

    int age = today.year - dob.year;

    // Проверяем, был ли уже день рождения в этом году
    if (today.month < dob.month ||
        (today.month == dob.month && today.day < dob.day)) {
      age--;
    }

    return age;
  }

  // Добавляем геттеры для обратной совместимости
  String? get occupation {
    if (details == null ||
        details!.career == null ||
        details!.career!.isEmpty) {
      return null;
    }
    // Возвращаем последнюю должность
    final currentCareer = details!.career!.where((c) => c.isCurrent).toList();
    if (currentCareer.isNotEmpty && currentCareer.first.position != null) {
      return currentCareer.first.position;
    }
    return details!.career!.last.position;
  }

  String? get biography {
    if (details == null || details!.customData == null) {
      return bio; // Используем существующее поле bio
    }
    return details!.customData!['biography'] as String? ?? bio;
  }

  String get fullName {
    final nameParts = [
      name,
      maidenName,
    ].where((part) => part != null && part.isNotEmpty).toList();

    return nameParts.join(' ');
  }

  // Добавляем статический метод для парсинга строки в Gender
  static Gender genderFromString(String? genderString) {
    if (genderString == null) return Gender.unknown;
    switch (genderString.toLowerCase()) {
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
}

// Создаем класс для хранения детальной информации
class FamilyPersonDetails {
  final String? education; // Образование
  final List<Career>? career; // Карьера
  final List<Event>? importantEvents; // Важные события
  final Map<String, dynamic>? customData; // Произвольные данные

  FamilyPersonDetails({
    this.education,
    this.career,
    this.importantEvents,
    this.customData,
  });

  factory FamilyPersonDetails.fromMap(Map<String, dynamic> data) {
    return FamilyPersonDetails(
      education: data['education'],
      career: data['career'] != null
          ? (data['career'] as List).map((e) => Career.fromMap(e)).toList()
          : null,
      importantEvents: data['importantEvents'] != null
          ? (data['importantEvents'] as List)
              .map((e) => Event.fromMap(e))
              .toList()
          : null,
      customData: data['customData'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'education': education,
      'career': career?.map((e) => e.toMap()).toList(),
      'importantEvents': importantEvents?.map((e) => e.toMap()).toList(),
      'customData': customData,
    };
  }
}

// Класс для хранения информации о карьере
class Career {
  final String? company;
  final String? position;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isCurrent;

  Career({
    this.company,
    this.position,
    this.startDate,
    this.endDate,
    this.isCurrent = false,
  });

  factory Career.fromMap(Map<String, dynamic> data) {
    return Career(
      company: data['company'],
      position: data['position'],
      startDate: data['startDate'] != null
          ? parseDateTimeRequired(data['startDate'])
          : null,
      endDate: data['endDate'] != null
          ? parseDateTimeRequired(data['endDate'])
          : null,
      isCurrent: data['isCurrent'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'company': company,
      'position': position,
      'startDate': startDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'isCurrent': isCurrent,
    };
  }
}

// Класс для хранения важных событий
class Event {
  final String title;
  final String? description;
  final DateTime date;
  final String? location;

  Event({
    required this.title,
    this.description,
    required this.date,
    this.location,
  });

  factory Event.fromMap(Map<String, dynamic> data) {
    return Event(
      title: data['title'] ?? '',
      description: data['description'],
      date: data['date'] != null
          ? parseDateTimeRequired(data['date'])
          : DateTime.now(),
      location: data['location'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'date': date.toIso8601String(),
      'location': location,
    };
  }
}

// Класс для хранения информации о супруге
class SpouseInfo {
  final String personId;
  final bool isCurrent;
  final DateTime? marriageDate;
  final DateTime? divorceDate;

  SpouseInfo({
    required this.personId,
    this.isCurrent = true,
    this.marriageDate,
    this.divorceDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'personId': personId,
      'isCurrent': isCurrent,
      'marriageDate': marriageDate,
      'divorceDate': divorceDate,
    };
  }

  factory SpouseInfo.fromMap(Map<String, dynamic> map) {
    return SpouseInfo(
      personId: map['personId'] ?? '',
      isCurrent: map['isCurrent'] ?? true,
      marriageDate: map['marriageDate'],
      divorceDate: map['divorceDate'],
    );
  }
}
