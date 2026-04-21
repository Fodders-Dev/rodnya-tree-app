// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_profile.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class UserProfileAdapter extends TypeAdapter<UserProfile> {
  @override
  final int typeId = 0;

  @override
  UserProfile read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserProfile(
      id: fields[0] as String,
      email: fields[1] as String,
      displayName: fields[2] as String,
      firstName: fields[3] as String,
      lastName: fields[4] as String,
      middleName: fields[5] as String,
      username: fields[6] as String,
      photoURL: fields[7] as String?,
      phoneNumber: fields[8] as String,
      gender: fields[10] as Gender?,
      birthDate: fields[11] as DateTime?,
      maidenName: fields[38] as String? ?? '',
      birthPlace: fields[36] as String?,
      country: fields[12] as String?,
      city: fields[13] as String?,
      createdAt: fields[14] as DateTime,
      updatedAt: fields[15] as DateTime?,
      lastLoginAt: fields[16] as DateTime?,
      countryCode: fields[17] as String?,
      creatorOfTreeIds: (fields[18] as List?)?.cast<String>(),
      accessibleTreeIds: (fields[19] as List?)?.cast<String>(),
      fcmTokens: (fields[20] as List?)?.cast<String>(),
      bio: fields[21] as String? ?? '',
      familyStatus: fields[22] as String? ?? '',
      education: fields[23] as String? ?? '',
      work: fields[24] as String? ?? '',
      values: fields[25] as String? ?? '',
      religion: fields[26] as String? ?? '',
      profileVisibilityScopes: (fields[27] as Map?)?.cast<String, String>(),
      hiddenProfileSections: (fields[28] as List?)?.cast<String>(),
      profileVisibilityTreeIds: (fields[29] as Map?)?.map(
        (key, value) => MapEntry(
          key.toString(),
          (value as List?)?.cast<String>() ?? const <String>[],
        ),
      ),
      profileVisibilityUserIds: (fields[30] as Map?)?.map(
        (key, value) => MapEntry(
          key.toString(),
          (value as List?)?.cast<String>() ?? const <String>[],
        ),
      ),
      hometown: fields[31] as String? ?? '',
      languages: fields[32] as String? ?? '',
      interests: fields[33] as String? ?? '',
      aboutFamily: fields[34] as String? ?? '',
      profileVisibilityBranchRootIds: (fields[35] as Map?)?.map(
        (key, value) => MapEntry(
          key.toString(),
          (value as List?)?.cast<String>() ?? const <String>[],
        ),
      ),
      profileContributionPolicy: fields[37] as String? ?? 'suggestions',
    );
  }

  @override
  void write(BinaryWriter writer, UserProfile obj) {
    writer
      ..writeByte(38)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.email)
      ..writeByte(2)
      ..write(obj.displayName)
      ..writeByte(3)
      ..write(obj.firstName)
      ..writeByte(4)
      ..write(obj.lastName)
      ..writeByte(5)
      ..write(obj.middleName)
      ..writeByte(6)
      ..write(obj.username)
      ..writeByte(7)
      ..write(obj.photoURL)
      ..writeByte(8)
      ..write(obj.phoneNumber)
      ..writeByte(10)
      ..write(obj.gender)
      ..writeByte(11)
      ..write(obj.birthDate)
      ..writeByte(12)
      ..write(obj.country)
      ..writeByte(13)
      ..write(obj.city)
      ..writeByte(14)
      ..write(obj.createdAt)
      ..writeByte(15)
      ..write(obj.updatedAt)
      ..writeByte(16)
      ..write(obj.lastLoginAt)
      ..writeByte(17)
      ..write(obj.countryCode)
      ..writeByte(18)
      ..write(obj.creatorOfTreeIds)
      ..writeByte(19)
      ..write(obj.accessibleTreeIds)
      ..writeByte(20)
      ..write(obj.fcmTokens)
      ..writeByte(21)
      ..write(obj.bio)
      ..writeByte(22)
      ..write(obj.familyStatus)
      ..writeByte(23)
      ..write(obj.education)
      ..writeByte(24)
      ..write(obj.work)
      ..writeByte(25)
      ..write(obj.values)
      ..writeByte(26)
      ..write(obj.religion)
      ..writeByte(27)
      ..write(obj.profileVisibilityScopes)
      ..writeByte(28)
      ..write(obj.hiddenProfileSections)
      ..writeByte(29)
      ..write(obj.profileVisibilityTreeIds)
      ..writeByte(30)
      ..write(obj.profileVisibilityUserIds)
      ..writeByte(31)
      ..write(obj.hometown)
      ..writeByte(32)
      ..write(obj.languages)
      ..writeByte(33)
      ..write(obj.interests)
      ..writeByte(34)
      ..write(obj.aboutFamily)
      ..writeByte(35)
      ..write(obj.profileVisibilityBranchRootIds)
      ..writeByte(36)
      ..write(obj.birthPlace)
      ..writeByte(37)
      ..write(obj.profileContributionPolicy)
      ..writeByte(38)
      ..write(obj.maidenName);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfileAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
