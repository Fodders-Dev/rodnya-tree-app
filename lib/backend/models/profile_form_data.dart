import '../../models/family_person.dart';

class ProfileFormData {
  const ProfileFormData({
    required this.userId,
    this.email,
    this.firstName = '',
    this.lastName = '',
    this.middleName = '',
    this.displayName = '',
    this.username = '',
    this.phoneNumber = '',
    this.countryCode,
    this.countryName,
    this.city = '',
    this.photoUrl,
    this.gender = Gender.unknown,
    this.maidenName = '',
    this.birthDate,
    this.birthPlace = '',
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
    this.profileContributionPolicy = 'suggestions',
    this.primaryTrustedChannel,
    this.profileVisibilityScopes = const {},
    this.profileVisibilityTreeIds = const {},
    this.profileVisibilityBranchRootIds = const {},
    this.profileVisibilityUserIds = const {},
  });

  final String userId;
  final String? email;
  final String firstName;
  final String lastName;
  final String middleName;
  final String displayName;
  final String username;
  final String phoneNumber;
  final String? countryCode;
  final String? countryName;
  final String city;
  final String? photoUrl;
  final Gender gender;
  final String maidenName;
  final DateTime? birthDate;
  final String birthPlace;
  final String bio;
  final String familyStatus;
  final String aboutFamily;
  final String education;
  final String work;
  final String hometown;
  final String languages;
  final String values;
  final String religion;
  final String interests;
  final String profileContributionPolicy;
  final String? primaryTrustedChannel;
  final Map<String, String> profileVisibilityScopes;
  final Map<String, List<String>> profileVisibilityTreeIds;
  final Map<String, List<String>> profileVisibilityBranchRootIds;
  final Map<String, List<String>> profileVisibilityUserIds;

  ProfileFormData copyWith({
    String? userId,
    String? email,
    String? firstName,
    String? lastName,
    String? middleName,
    String? displayName,
    String? username,
    String? phoneNumber,
    String? countryCode,
    String? countryName,
    String? city,
    String? photoUrl,
    Gender? gender,
    String? maidenName,
    DateTime? birthDate,
    String? birthPlace,
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
    String? primaryTrustedChannel,
    Map<String, String>? profileVisibilityScopes,
    Map<String, List<String>>? profileVisibilityTreeIds,
    Map<String, List<String>>? profileVisibilityBranchRootIds,
    Map<String, List<String>>? profileVisibilityUserIds,
  }) {
    return ProfileFormData(
      userId: userId ?? this.userId,
      email: email ?? this.email,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      middleName: middleName ?? this.middleName,
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      countryCode: countryCode ?? this.countryCode,
      countryName: countryName ?? this.countryName,
      city: city ?? this.city,
      photoUrl: photoUrl ?? this.photoUrl,
      gender: gender ?? this.gender,
      maidenName: maidenName ?? this.maidenName,
      birthDate: birthDate ?? this.birthDate,
      birthPlace: birthPlace ?? this.birthPlace,
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
      primaryTrustedChannel:
          primaryTrustedChannel ?? this.primaryTrustedChannel,
      profileVisibilityScopes:
          profileVisibilityScopes ?? this.profileVisibilityScopes,
      profileVisibilityTreeIds:
          profileVisibilityTreeIds ?? this.profileVisibilityTreeIds,
      profileVisibilityBranchRootIds:
          profileVisibilityBranchRootIds ?? this.profileVisibilityBranchRootIds,
      profileVisibilityUserIds:
          profileVisibilityUserIds ?? this.profileVisibilityUserIds,
    );
  }
}
