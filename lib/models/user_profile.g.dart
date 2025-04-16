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
      isPhoneVerified: fields[9] as bool,
      gender: fields[10] as Gender?,
      birthDate: fields[11] as DateTime?,
      country: fields[12] as String?,
      city: fields[13] as String?,
      createdAt: fields[14] as DateTime,
      updatedAt: fields[15] as DateTime?,
      lastLoginAt: fields[16] as DateTime?,
      countryCode: fields[17] as String?,
      creatorOfTreeIds: (fields[18] as List?)?.cast<String>(),
      accessibleTreeIds: (fields[19] as List?)?.cast<String>(),
      fcmTokens: (fields[20] as List?)?.cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, UserProfile obj) {
    writer
      ..writeByte(21)
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
      ..writeByte(9)
      ..write(obj.isPhoneVerified)
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
      ..write(obj.fcmTokens);
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
