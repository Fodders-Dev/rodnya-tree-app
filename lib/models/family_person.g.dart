// GENERATED CODE - DO NOT MODIFY BY HAND
//
// ⚠️ ВНИМАНИЕ (hotfix-1b): файл содержит РУЧНЫЕ правки read'а поверх
// генерата — build_runner их сносит (генератор не сопоставляет приватные
// _photoUrl/_photoGallery с параметрами конструктора и не знает legacy-
// дефолт visibility). После любой регенерации верни в read:
//   • photoUrl: fields[5] as String?
//   • photoGallery: (fields[24] as List?)…
//   • visibility: fields[27] as String? ?? 'private'  (старые записи без
//     поля 27 обязаны читаться)
//   • F5: birthDatePrecision: fields[28] as String? ?? 'exact' и
//     deathDatePrecision: fields[29] as String? ?? 'exact' (старые записи
//     без полей 28/29 обязаны читаться) + write 28/29, счётчик 29.
// Вынос этих дефолтов из генерённого файла — отдельная задача, не hotfix.

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
      identityId: fields[25] as String?,
      name: fields[3] as String,
      maidenName: fields[4] as String?,
      photoUrl: fields[5] as String?,
      gender: fields[6] as Gender,
      birthDate: fields[7] as DateTime?,
      birthPlace: fields[8] as String?,
      deathDate: fields[9] as DateTime?,
      deathPlace: fields[10] as String?,
      bio: fields[11] as String?,
      familySummary: fields[26] as String?,
      isAlive: fields[13] as bool,
      visibility: fields[27] as String? ?? 'private',
      birthDatePrecision: fields[28] as String? ?? 'exact',
      deathDatePrecision: fields[29] as String? ?? 'exact',
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
      photoGallery: (fields[24] as List?)
          ?.whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList(),
    );
  }

  @override
  void write(BinaryWriter writer, FamilyPerson obj) {
    writer
      ..writeByte(29)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.treeId)
      ..writeByte(2)
      ..write(obj.userId)
      ..writeByte(25)
      ..write(obj.identityId)
      ..writeByte(3)
      ..write(obj.name)
      ..writeByte(4)
      ..write(obj.maidenName)
      ..writeByte(5)
      ..write(obj._photoUrl)
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
      ..write(obj.details)
      ..writeByte(24)
      ..write(obj._photoGallery)
      ..writeByte(26)
      ..write(obj.familySummary)
      ..writeByte(27)
      ..write(obj.visibility)
      ..writeByte(28)
      ..write(obj.birthDatePrecision)
      ..writeByte(29)
      ..write(obj.deathDatePrecision);
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

class FamilyPersonDetailsAdapter extends TypeAdapter<FamilyPersonDetails> {
  @override
  final int typeId = 102;

  @override
  FamilyPersonDetails read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FamilyPersonDetails(
      education: fields[0] as String?,
      career: (fields[1] as List?)?.cast<Career>(),
      importantEvents: (fields[2] as List?)?.cast<Event>(),
      customData: (fields[3] as Map?)?.cast<String, dynamic>(),
    );
  }

  @override
  void write(BinaryWriter writer, FamilyPersonDetails obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.education)
      ..writeByte(1)
      ..write(obj.career)
      ..writeByte(2)
      ..write(obj.importantEvents)
      ..writeByte(3)
      ..write(obj.customData);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FamilyPersonDetailsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class CareerAdapter extends TypeAdapter<Career> {
  @override
  final int typeId = 103;

  @override
  Career read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Career(
      company: fields[0] as String?,
      position: fields[1] as String?,
      startDate: fields[2] as DateTime?,
      endDate: fields[3] as DateTime?,
      isCurrent: fields[4] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, Career obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.company)
      ..writeByte(1)
      ..write(obj.position)
      ..writeByte(2)
      ..write(obj.startDate)
      ..writeByte(3)
      ..write(obj.endDate)
      ..writeByte(4)
      ..write(obj.isCurrent);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CareerAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class EventAdapter extends TypeAdapter<Event> {
  @override
  final int typeId = 104;

  @override
  Event read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Event(
      title: fields[0] as String,
      description: fields[1] as String?,
      date: fields[2] as DateTime,
      location: fields[3] as String?,
      repeatsAnnually: fields[4] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, Event obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.title)
      ..writeByte(1)
      ..write(obj.description)
      ..writeByte(2)
      ..write(obj.date)
      ..writeByte(3)
      ..write(obj.location)
      ..writeByte(4)
      ..write(obj.repeatsAnnually);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EventAdapter &&
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
