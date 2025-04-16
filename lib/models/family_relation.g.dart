// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'family_relation.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FamilyRelationAdapter extends TypeAdapter<FamilyRelation> {
  @override
  final int typeId = 3;

  @override
  FamilyRelation read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FamilyRelation(
      id: fields[0] as String,
      treeId: fields[1] as String,
      person1Id: fields[2] as String,
      person2Id: fields[3] as String,
      relation1to2: fields[4] as RelationType,
      relation2to1: fields[5] as RelationType,
      isConfirmed: fields[6] as bool,
      createdAt: fields[7] as DateTime,
      updatedAt: fields[8] as DateTime?,
      createdBy: fields[9] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, FamilyRelation obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.treeId)
      ..writeByte(2)
      ..write(obj.person1Id)
      ..writeByte(3)
      ..write(obj.person2Id)
      ..writeByte(4)
      ..write(obj.relation1to2)
      ..writeByte(5)
      ..write(obj.relation2to1)
      ..writeByte(6)
      ..write(obj.isConfirmed)
      ..writeByte(7)
      ..write(obj.createdAt)
      ..writeByte(8)
      ..write(obj.updatedAt)
      ..writeByte(9)
      ..write(obj.createdBy);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FamilyRelationAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class RelationTypeAdapter extends TypeAdapter<RelationType> {
  @override
  final int typeId = 101;

  @override
  RelationType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return RelationType.parent;
      case 1:
        return RelationType.child;
      case 2:
        return RelationType.spouse;
      case 3:
        return RelationType.partner;
      case 4:
        return RelationType.sibling;
      case 5:
        return RelationType.cousin;
      case 6:
        return RelationType.uncle;
      case 7:
        return RelationType.aunt;
      case 8:
        return RelationType.nephew;
      case 9:
        return RelationType.niece;
      case 10:
        return RelationType.nibling;
      case 11:
        return RelationType.grandparent;
      case 12:
        return RelationType.grandchild;
      case 13:
        return RelationType.greatGrandparent;
      case 14:
        return RelationType.greatGrandchild;
      case 15:
        return RelationType.parentInLaw;
      case 16:
        return RelationType.childInLaw;
      case 17:
        return RelationType.siblingInLaw;
      case 18:
        return RelationType.inlaw;
      case 19:
        return RelationType.stepparent;
      case 20:
        return RelationType.stepchild;
      case 21:
        return RelationType.ex_spouse;
      case 22:
        return RelationType.ex_partner;
      case 23:
        return RelationType.friend;
      case 24:
        return RelationType.colleague;
      case 25:
        return RelationType.other;
      default:
        return RelationType.parent;
    }
  }

  @override
  void write(BinaryWriter writer, RelationType obj) {
    switch (obj) {
      case RelationType.parent:
        writer.writeByte(0);
        break;
      case RelationType.child:
        writer.writeByte(1);
        break;
      case RelationType.spouse:
        writer.writeByte(2);
        break;
      case RelationType.partner:
        writer.writeByte(3);
        break;
      case RelationType.sibling:
        writer.writeByte(4);
        break;
      case RelationType.cousin:
        writer.writeByte(5);
        break;
      case RelationType.uncle:
        writer.writeByte(6);
        break;
      case RelationType.aunt:
        writer.writeByte(7);
        break;
      case RelationType.nephew:
        writer.writeByte(8);
        break;
      case RelationType.niece:
        writer.writeByte(9);
        break;
      case RelationType.nibling:
        writer.writeByte(10);
        break;
      case RelationType.grandparent:
        writer.writeByte(11);
        break;
      case RelationType.grandchild:
        writer.writeByte(12);
        break;
      case RelationType.greatGrandparent:
        writer.writeByte(13);
        break;
      case RelationType.greatGrandchild:
        writer.writeByte(14);
        break;
      case RelationType.parentInLaw:
        writer.writeByte(15);
        break;
      case RelationType.childInLaw:
        writer.writeByte(16);
        break;
      case RelationType.siblingInLaw:
        writer.writeByte(17);
        break;
      case RelationType.inlaw:
        writer.writeByte(18);
        break;
      case RelationType.stepparent:
        writer.writeByte(19);
        break;
      case RelationType.stepchild:
        writer.writeByte(20);
        break;
      case RelationType.ex_spouse:
        writer.writeByte(21);
        break;
      case RelationType.ex_partner:
        writer.writeByte(22);
        break;
      case RelationType.friend:
        writer.writeByte(23);
        break;
      case RelationType.colleague:
        writer.writeByte(24);
        break;
      case RelationType.other:
        writer.writeByte(25);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RelationTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
