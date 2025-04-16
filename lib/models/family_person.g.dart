// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'family_person.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FamilyPersonAdapter extends TypeAdapter<FamilyPerson> {
  @override
  final int typeId = 1;

  @override
  FamilyPerson read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FamilyPerson(
      id: fields[0] as String,
      treeId: fields[1] as String,
      userId: fields[2] as String?,
      name: fields[3] as String,
      maidenName: fields[4] as String?,
      photoUrl: fields[5] as String?,
      gender: fields[6] as Gender,
      birthDate: fields[7] as DateTime?,
      birthPlace: fields[8] as String?,
      deathDate: fields[9] as DateTime?,
      deathPlace: fields[10] as String?,
      bio: fields[11] as String?,
      isAlive: fields[13] as bool,
      creatorId: fields[14] as String?,
      createdAt: fields[15] as DateTime,
      updatedAt: fields[16] as DateTime,
      notes: fields[17] as String?,
      relation: fields[18] as String?,
      parentIds: (fields[19] as List?)?.cast<String>(),
      childrenIds: (fields[20] as List?)?.cast<String>(),
      spouseId: fields[21] as String?,
      siblingIds: (fields[22] as List?)?.cast<String>(),
      details: fields[23] as FamilyPersonDetails?,
    );
  }

  @override
  void write(BinaryWriter writer, FamilyPerson obj) {
    writer
      ..writeByte(23)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.treeId)
      ..writeByte(2)
      ..write(obj.userId)
      ..writeByte(3)
      ..write(obj.name)
      ..writeByte(4)
      ..write(obj.maidenName)
      ..writeByte(5)
      ..write(obj.photoUrl)
      ..writeByte(6)
      ..write(obj.gender)
      ..writeByte(7)
      ..write(obj.birthDate)
      ..writeByte(8)
      ..write(obj.birthPlace)
      ..writeByte(9)
      ..write(obj.deathDate)
      ..writeByte(10)
      ..write(obj.deathPlace)
      ..writeByte(11)
      ..write(obj.bio)
      ..writeByte(13)
      ..write(obj.isAlive)
      ..writeByte(14)
      ..write(obj.creatorId)
      ..writeByte(15)
      ..write(obj.createdAt)
      ..writeByte(16)
      ..write(obj.updatedAt)
      ..writeByte(17)
      ..write(obj.notes)
      ..writeByte(18)
      ..write(obj.relation)
      ..writeByte(19)
      ..write(obj.parentIds)
      ..writeByte(20)
      ..write(obj.childrenIds)
      ..writeByte(21)
      ..write(obj.spouseId)
      ..writeByte(22)
      ..write(obj.siblingIds)
      ..writeByte(23)
      ..write(obj.details);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FamilyPersonAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class GenderAdapter extends TypeAdapter<Gender> {
  @override
  final int typeId = 100;

  @override
  Gender read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return Gender.male;
      case 1:
        return Gender.female;
      case 2:
        return Gender.other;
      case 3:
        return Gender.unknown;
      default:
        return Gender.male;
    }
  }

  @override
  void write(BinaryWriter writer, Gender obj) {
    switch (obj) {
      case Gender.male:
        writer.writeByte(0);
        break;
      case Gender.female:
        writer.writeByte(1);
        break;
      case Gender.other:
        writer.writeByte(2);
        break;
      case Gender.unknown:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GenderAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
