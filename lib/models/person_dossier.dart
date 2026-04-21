import 'family_person.dart';
import 'user_profile.dart';

class PersonDossier {
  const PersonDossier({
    required this.person,
    required this.mode,
    required this.canEditFamilyFields,
    required this.canSuggestOwnerFields,
    this.linkedProfile,
    this.hiddenSections = const <String>[],
  });

  final FamilyPerson person;
  final UserProfile? linkedProfile;
  final String mode;
  final bool canEditFamilyFields;
  final bool canSuggestOwnerFields;
  final List<String> hiddenSections;

  bool get isMemorial => mode == 'memorial';
  bool get isSelf => mode == 'self';
  bool get isLinkedUser =>
      (person.userId?.isNotEmpty ?? false) || linkedProfile != null;

  String get displayName {
    final linkedName = linkedProfile?.displayName.trim() ?? '';
    if (linkedName.isNotEmpty) {
      return linkedName;
    }
    final fullName = linkedProfile?.fullName.trim() ?? '';
    if (fullName.isNotEmpty) {
      return fullName;
    }
    return person.displayName.trim().isNotEmpty
        ? person.displayName
        : 'Без имени';
  }

  String? get photoUrl => linkedProfile?.photoURL ?? person.primaryPhotoUrl;

  DateTime? get birthDate => linkedProfile?.birthDate ?? person.birthDate;
  String? get birthPlace {
    final value = linkedProfile?.birthPlace?.trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
    return person.birthPlace;
  }

  String? get city => linkedProfile?.city?.trim().isNotEmpty == true
      ? linkedProfile!.city!.trim()
      : null;

  String? get country => linkedProfile?.country?.trim().isNotEmpty == true
      ? linkedProfile!.country!.trim()
      : null;

  String get familySummary {
    final summary = person.familySummary?.trim();
    if (summary != null && summary.isNotEmpty) {
      return summary;
    }
    final fallback = person.notes?.trim().isNotEmpty == true
        ? person.notes!.trim()
        : person.bio?.trim();
    return fallback ?? '';
  }

  String get bio => linkedProfile?.bio ?? '';
  String get familyStatus => linkedProfile?.familyStatus ?? '';
  String get aboutFamily => linkedProfile?.aboutFamily ?? '';
  String get education => linkedProfile?.education ?? '';
  String get work => linkedProfile?.work ?? '';
  String get hometown => linkedProfile?.hometown ?? '';
  String get languages => linkedProfile?.languages ?? '';
  String get values => linkedProfile?.values ?? '';
  String get religion => linkedProfile?.religion ?? '';
  String get interests => linkedProfile?.interests ?? '';
  String get maidenName {
    final linkedValue = linkedProfile?.maidenName.trim() ?? '';
    if (linkedValue.isNotEmpty) {
      return linkedValue;
    }
    return person.maidenName?.trim() ?? '';
  }

  factory PersonDossier.fromJson(Map<String, dynamic> json) {
    final rawPerson = json['person'];
    final rawLinkedProfile = json['linkedProfile'];
    return PersonDossier(
      person: FamilyPerson.fromMap(
        rawPerson is Map<String, dynamic>
            ? rawPerson
            : const <String, dynamic>{},
        rawPerson is Map<String, dynamic>
            ? rawPerson['id']?.toString() ?? ''
            : '',
      ),
      linkedProfile: rawLinkedProfile is Map<String, dynamic>
          ? UserProfile.fromMap(
              rawLinkedProfile,
              rawLinkedProfile['id']?.toString() ?? '',
            )
          : null,
      mode: json['mode']?.toString() ?? 'offline',
      canEditFamilyFields:
          (json['permissions'] as Map?)?['canEditFamilyFields'] == true,
      canSuggestOwnerFields:
          (json['permissions'] as Map?)?['canSuggestOwnerFields'] == true,
      hiddenSections:
          (json['hiddenSections'] as List<dynamic>? ?? const <dynamic>[])
              .map((value) => value.toString())
              .toList(),
    );
  }

  factory PersonDossier.fromProfile(
    UserProfile profile, {
    FamilyPerson? treePerson,
    bool isSelf = false,
  }) {
    return PersonDossier(
      person: treePerson ??
          FamilyPerson(
            id: profile.id,
            treeId: '',
            userId: profile.id,
            name: profile.fullName.isNotEmpty
                ? profile.fullName
                : profile.displayName,
            maidenName: profile.maidenName.isEmpty ? null : profile.maidenName,
            photoUrl: profile.photoURL,
            gender: profile.gender ?? Gender.unknown,
            birthDate: profile.birthDate,
            birthPlace: profile.birthPlace,
            isAlive: true,
            createdAt: profile.createdAt,
            updatedAt: profile.updatedAt ?? profile.createdAt,
          ),
      linkedProfile: profile,
      mode: isSelf ? 'self' : 'linked',
      canEditFamilyFields: isSelf,
      canSuggestOwnerFields: false,
      hiddenSections: profile.hiddenProfileSections ?? const <String>[],
    );
  }

  factory PersonDossier.fromPerson(
    FamilyPerson person, {
    bool canEditFamilyFields = false,
  }) {
    return PersonDossier(
      person: person,
      mode: person.isAlive ? 'offline' : 'memorial',
      canEditFamilyFields: canEditFamilyFields,
      canSuggestOwnerFields: false,
    );
  }
}
