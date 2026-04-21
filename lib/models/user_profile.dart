import '../utils/date_parser.dart';
import 'package:hive/hive.dart';
import '../models/family_person.dart';
import '../utils/url_utils.dart';

part 'user_profile.g.dart';

@HiveType(typeId: 0)
class UserProfile extends HiveObject {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String email;
  @HiveField(2)
  final String displayName;
  @HiveField(3)
  final String firstName;
  @HiveField(4)
  final String lastName;
  @HiveField(5)
  final String middleName;
  @HiveField(6)
  final String username;
  @HiveField(7)
  final String? _photoURL;
  @HiveField(8)
  final String phoneNumber;
  @HiveField(10)
  final Gender? gender;
  @HiveField(11)
  final DateTime? birthDate;
  @HiveField(12)
  final String? country;
  @HiveField(13)
  final String? city;
  @HiveField(14)
  final DateTime createdAt;
  @HiveField(15)
  final DateTime? updatedAt;
  @HiveField(16)
  final DateTime? lastLoginAt;
  @HiveField(17)
  final String? countryCode;
  @HiveField(18)
  final List<String>? creatorOfTreeIds;
  @HiveField(19)
  final List<String>? accessibleTreeIds;
  @HiveField(20)
  final List<String>? fcmTokens;
  @HiveField(21)
  final String bio;
  @HiveField(22)
  final String familyStatus;
  @HiveField(23)
  final String education;
  @HiveField(24)
  final String work;
  @HiveField(25)
  final String values;
  @HiveField(26)
  final String religion;
  @HiveField(27)
  final Map<String, String>? profileVisibilityScopes;
  @HiveField(28)
  final List<String>? hiddenProfileSections;
  @HiveField(29)
  final Map<String, List<String>>? profileVisibilityTreeIds;
  @HiveField(30)
  final Map<String, List<String>>? profileVisibilityUserIds;
  @HiveField(31)
  final String hometown;
  @HiveField(32)
  final String languages;
  @HiveField(33)
  final String interests;
  @HiveField(34)
  final String aboutFamily;
  @HiveField(35)
  final Map<String, List<String>>? profileVisibilityBranchRootIds;
  @HiveField(36)
  final String? birthPlace;
  @HiveField(37)
  final String profileContributionPolicy;
  @HiveField(38)
  final String maidenName;

  String? get photoURL => _photoURL;

  UserProfile({
    required this.id,
    required this.email,
    this.displayName = '',
    this.firstName = '',
    this.lastName = '',
    this.middleName = '',
    required this.username,
    String? photoURL,
    required this.phoneNumber,
    this.gender,
    this.birthDate,
    this.country,
    this.city,
    required this.createdAt,
    this.updatedAt,
    this.lastLoginAt,
    this.countryCode,
    this.creatorOfTreeIds,
    this.accessibleTreeIds,
    this.fcmTokens,
    this.bio = '',
    this.familyStatus = '',
    this.aboutFamily = '',
    this.education = '',
    this.work = '',
    this.hometown = '',
    this.languages = '',
    this.values = '',
    this.religion = '',
    this.interests = '',
    this.profileVisibilityScopes,
    this.hiddenProfileSections,
    this.profileVisibilityTreeIds,
    this.profileVisibilityUserIds,
    this.profileVisibilityBranchRootIds,
    this.birthPlace,
    this.profileContributionPolicy = 'suggestions',
    this.maidenName = '',
  }) : _photoURL = UrlUtils.normalizeImageUrl(photoURL);

  factory UserProfile.fromFirestore(dynamic doc) {
    final data =
        (doc.data != null ? (doc.data() as Map<String, dynamic>?) : null) ?? {};

    // Конвертируем строковое представление пола в enum
    Gender? userGender;
    if (data['gender'] != null) {
      switch (data['gender']) {
        case 'male':
          userGender = Gender.male;
          break;
        case 'female':
          userGender = Gender.female;
          break;
        case 'other':
          userGender = Gender.other;
          break;
        default:
          userGender = Gender.unknown;
      }
    }

    return UserProfile(
      id: doc.id,
      email: data['email'] ?? '',
      displayName: data['displayName'] ?? '',
      firstName: data['firstName'] ?? '',
      lastName: data['lastName'] ?? '',
      middleName: data['middleName'] ?? '',
      username: data['username'] ?? '',
      photoURL: data['photoURL'],
      phoneNumber: data['phoneNumber'] ?? '',
      gender: userGender,
      birthDate: data['birthDate'] != null
          ? parseDateTimeRequired(data['birthDate'])
          : null,
      maidenName: data['maidenName']?.toString() ?? '',
      birthPlace: data['birthPlace'] as String?,
      country: data['country'] as String?,
      city: data['city'],
      createdAt: data['createdAt'] != null
          ? parseDateTimeRequired(data['createdAt'])
          : DateTime.now(),
      updatedAt: data['updatedAt'] != null
          ? parseDateTimeRequired(data['updatedAt'])
          : null,
      lastLoginAt: data['lastLoginAt'] != null
          ? parseDateTimeRequired(data['lastLoginAt'])
          : null,
      countryCode: data['countryCode'],
      creatorOfTreeIds: (data['creatorOfTreeIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      accessibleTreeIds: (data['accessibleTreeIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      fcmTokens: (data['fcmTokens'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      bio: data['bio'] ?? '',
      familyStatus: data['familyStatus'] ?? '',
      aboutFamily: data['aboutFamily'] ?? '',
      education: data['education'] ?? '',
      work: data['work'] ?? '',
      hometown: data['hometown'] ?? '',
      languages: data['languages'] ?? '',
      values: data['values'] ?? '',
      religion: data['religion'] ?? '',
      interests: data['interests'] ?? '',
      profileContributionPolicy:
          data['profileContributionPolicy']?.toString() ?? 'suggestions',
      profileVisibilityScopes:
          (data['profileVisibility'] as Map?)?.map((key, value) => MapEntry(
                    key.toString(),
                    ((value as Map?)?['scope'] ?? value).toString(),
                  )) ??
              (data['profileVisibilityScopes'] as Map?)?.map(
                (key, value) => MapEntry(key.toString(), value.toString()),
              ),
      hiddenProfileSections:
          (data['hiddenProfileSections'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList(),
      profileVisibilityTreeIds: _mapStringListMap(
        (data['profileVisibility'] as Map?)?.map(
          (key, value) => MapEntry(key.toString(), (value as Map?)?['treeIds']),
        ),
      ),
      profileVisibilityBranchRootIds: _mapStringListMap(
        (data['profileVisibility'] as Map?)?.map(
          (key, value) => MapEntry(
            key.toString(),
            (value as Map?)?['branchRootPersonIds'],
          ),
        ),
      ),
      profileVisibilityUserIds: _mapStringListMap(
        (data['profileVisibility'] as Map?)?.map(
          (key, value) => MapEntry(key.toString(), (value as Map?)?['userIds']),
        ),
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'displayName': displayName,
      'firstName': firstName,
      'lastName': lastName,
      'middleName': middleName,
      'username': username,
      'photoURL': photoURL,
      'phoneNumber': phoneNumber,
      'gender': gender?.toString().split('.').last,
      'birthDate': birthDate?.toIso8601String(),
      'maidenName': maidenName,
      'birthPlace': birthPlace,
      'country': country,
      'city': city,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'lastLoginAt': lastLoginAt?.toIso8601String(),
      'countryCode': countryCode,
      if (creatorOfTreeIds != null) 'creatorOfTreeIds': creatorOfTreeIds,
      if (accessibleTreeIds != null) 'accessibleTreeIds': accessibleTreeIds,
      if (fcmTokens != null) 'fcmTokens': fcmTokens,
      'bio': bio,
      'familyStatus': familyStatus,
      'aboutFamily': aboutFamily,
      'education': education,
      'work': work,
      'hometown': hometown,
      'languages': languages,
      'values': values,
      'religion': religion,
      'interests': interests,
      'profileContributionPolicy': profileContributionPolicy,
      if (profileVisibilityScopes != null)
        'profileVisibilityScopes': profileVisibilityScopes,
      if (hiddenProfileSections != null)
        'hiddenProfileSections': hiddenProfileSections,
      if (profileVisibilityTreeIds != null)
        'profileVisibilityTreeIds': profileVisibilityTreeIds,
      if (profileVisibilityBranchRootIds != null)
        'profileVisibilityBranchRootIds': profileVisibilityBranchRootIds,
      if (profileVisibilityUserIds != null)
        'profileVisibilityUserIds': profileVisibilityUserIds,
    };
  }

  String get fullName {
    if (firstName.isNotEmpty || lastName.isNotEmpty) {
      return [
        firstName,
        middleName,
        lastName,
      ].where((part) => part.isNotEmpty).join(' ');
    }
    return displayName;
  }

  UserProfile copyWith({
    String? id,
    String? email,
    String? displayName,
    String? firstName,
    String? lastName,
    String? middleName,
    String? username,
    String? photoURL,
    String? phoneNumber,
    Gender? gender,
    DateTime? birthDate,
    String? maidenName,
    String? birthPlace,
    String? country,
    String? city,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastLoginAt,
    String? countryCode,
    List<String>? creatorOfTreeIds,
    List<String>? accessibleTreeIds,
    List<String>? fcmTokens,
    String? bio,
    String? familyStatus,
    String? aboutFamily,
    String? education,
    String? work,
    String? hometown,
    String? languages,
    String? values,
    String? religion,
    String? interests,
    String? profileContributionPolicy,
    Map<String, String>? profileVisibilityScopes,
    List<String>? hiddenProfileSections,
    Map<String, List<String>>? profileVisibilityTreeIds,
    Map<String, List<String>>? profileVisibilityBranchRootIds,
    Map<String, List<String>>? profileVisibilityUserIds,
  }) {
    return UserProfile(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      middleName: middleName ?? this.middleName,
      username: username ?? this.username,
      photoURL: photoURL ?? this.photoURL,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      gender: gender ?? this.gender,
      birthDate: birthDate ?? this.birthDate,
      maidenName: maidenName ?? this.maidenName,
      birthPlace: birthPlace ?? this.birthPlace,
      country: country ?? this.country,
      city: city ?? this.city,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      countryCode: countryCode ?? this.countryCode,
      creatorOfTreeIds: creatorOfTreeIds ?? this.creatorOfTreeIds,
      accessibleTreeIds: accessibleTreeIds ?? this.accessibleTreeIds,
      fcmTokens: fcmTokens ?? this.fcmTokens,
      bio: bio ?? this.bio,
      familyStatus: familyStatus ?? this.familyStatus,
      aboutFamily: aboutFamily ?? this.aboutFamily,
      education: education ?? this.education,
      work: work ?? this.work,
      hometown: hometown ?? this.hometown,
      languages: languages ?? this.languages,
      values: values ?? this.values,
      religion: religion ?? this.religion,
      interests: interests ?? this.interests,
      profileContributionPolicy:
          profileContributionPolicy ?? this.profileContributionPolicy,
      profileVisibilityScopes:
          profileVisibilityScopes ?? this.profileVisibilityScopes,
      hiddenProfileSections:
          hiddenProfileSections ?? this.hiddenProfileSections,
      profileVisibilityTreeIds:
          profileVisibilityTreeIds ?? this.profileVisibilityTreeIds,
      profileVisibilityBranchRootIds:
          profileVisibilityBranchRootIds ?? this.profileVisibilityBranchRootIds,
      profileVisibilityUserIds:
          profileVisibilityUserIds ?? this.profileVisibilityUserIds,
    );
  }

  factory UserProfile.create({
    required String id,
    required String email,
    String displayName = '',
    String firstName = '',
    String lastName = '',
    String middleName = '',
    required String username,
    String? photoURL,
    required String phoneNumber,
    Gender? gender,
    DateTime? birthDate,
    String maidenName = '',
    String? birthPlace,
    String? country,
    String? city,
    DateTime? updatedAt,
    DateTime? lastLoginAt,
    String? countryCode,
    List<String>? creatorOfTreeIds,
    List<String>? accessibleTreeIds,
    List<String>? fcmTokens,
    String bio = '',
    String familyStatus = '',
    String aboutFamily = '',
    String education = '',
    String work = '',
    String hometown = '',
    String languages = '',
    String values = '',
    String religion = '',
    String interests = '',
    String profileContributionPolicy = 'suggestions',
    Map<String, String>? profileVisibilityScopes,
    List<String>? hiddenProfileSections,
    Map<String, List<String>>? profileVisibilityTreeIds,
    Map<String, List<String>>? profileVisibilityBranchRootIds,
    Map<String, List<String>>? profileVisibilityUserIds,
  }) {
    return UserProfile(
      id: id,
      email: email,
      displayName: displayName,
      firstName: firstName,
      lastName: lastName,
      middleName: middleName,
      username: username,
      photoURL: photoURL,
      phoneNumber: phoneNumber,
      gender: gender,
      birthDate: birthDate,
      maidenName: maidenName,
      birthPlace: birthPlace,
      country: country,
      city: city,
      createdAt: DateTime.now(),
      updatedAt: updatedAt,
      lastLoginAt: lastLoginAt,
      countryCode: countryCode,
      creatorOfTreeIds: creatorOfTreeIds,
      accessibleTreeIds: accessibleTreeIds,
      fcmTokens: fcmTokens,
      bio: bio,
      familyStatus: familyStatus,
      aboutFamily: aboutFamily,
      education: education,
      work: work,
      hometown: hometown,
      languages: languages,
      values: values,
      religion: religion,
      interests: interests,
      profileContributionPolicy: profileContributionPolicy,
      profileVisibilityScopes: profileVisibilityScopes,
      hiddenProfileSections: hiddenProfileSections,
      profileVisibilityTreeIds: profileVisibilityTreeIds,
      profileVisibilityBranchRootIds: profileVisibilityBranchRootIds,
      profileVisibilityUserIds: profileVisibilityUserIds,
    );
  }

  static UserProfile fromMap(Map<String, dynamic> map, String id) {
    // Преобразование строкового пола в enum
    Gender? userGender;
    if (map['gender'] != null) {
      switch (map['gender']) {
        case 'male':
          userGender = Gender.male;
          break;
        case 'female':
          userGender = Gender.female;
          break;
        case 'other':
          userGender = Gender.other;
          break;
        default:
          userGender = Gender.unknown;
      }
    }

    return UserProfile(
      id: id,
      displayName: map['displayName'] ?? '',
      email: map['email'] ?? '',
      photoURL: map['photoURL'],
      firstName: map['firstName'] ?? '',
      lastName: map['lastName'] ?? '',
      middleName: map['middleName'],
      birthDate: map['birthDate'] != null
          ? parseDateTimeRequired(map['birthDate'])
          : null,
      maidenName: map['maidenName']?.toString() ?? '',
      birthPlace: map['birthPlace'] as String?,
      gender: userGender,
      phoneNumber: map['phoneNumber'] ?? '',
      country: map['country'] as String?,
      city: map['city'],
      createdAt: map['createdAt'] != null
          ? parseDateTimeRequired(map['createdAt'])
          : DateTime.now(),
      updatedAt: map['updatedAt'] != null
          ? parseDateTimeRequired(map['updatedAt'])
          : DateTime.now(),
      username: map['username'] ?? '',
      creatorOfTreeIds: (map['creatorOfTreeIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      accessibleTreeIds: (map['accessibleTreeIds'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      fcmTokens: (map['fcmTokens'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      bio: map['bio'] ?? '',
      familyStatus: map['familyStatus'] ?? '',
      aboutFamily: map['aboutFamily'] ?? '',
      education: map['education'] ?? '',
      work: map['work'] ?? '',
      hometown: map['hometown'] ?? '',
      languages: map['languages'] ?? '',
      values: map['values'] ?? '',
      religion: map['religion'] ?? '',
      interests: map['interests'] ?? '',
      profileContributionPolicy:
          map['profileContributionPolicy']?.toString() ?? 'suggestions',
      profileVisibilityScopes:
          (map['profileVisibility'] as Map?)?.map((key, value) => MapEntry(
                    key.toString(),
                    ((value as Map?)?['scope'] ?? value).toString(),
                  )) ??
              (map['profileVisibilityScopes'] as Map?)?.map(
                (key, value) => MapEntry(key.toString(), value.toString()),
              ),
      hiddenProfileSections:
          (map['hiddenProfileSections'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList(),
      profileVisibilityTreeIds:
          _mapStringListMap(map['profileVisibilityTreeIds']) ??
              _mapStringListMap(
                (map['profileVisibility'] as Map?)?.map(
                  (key, value) =>
                      MapEntry(key.toString(), (value as Map?)?['treeIds']),
                ),
              ),
      profileVisibilityUserIds:
          _mapStringListMap(map['profileVisibilityUserIds']) ??
              _mapStringListMap(
                (map['profileVisibility'] as Map?)?.map(
                  (key, value) =>
                      MapEntry(key.toString(), (value as Map?)?['userIds']),
                ),
              ),
    );
  }

  static Map<String, List<String>>? _mapStringListMap(dynamic value) {
    if (value is! Map) {
      return null;
    }

    return value.map(
      (key, rawList) => MapEntry(
        key.toString(),
        (rawList is List ? rawList : const <dynamic>[])
            .map((entry) => entry.toString())
            .where((entry) => entry.trim().isNotEmpty)
            .toList(),
      ),
    );
  }
}
