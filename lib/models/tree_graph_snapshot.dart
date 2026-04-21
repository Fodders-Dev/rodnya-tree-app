import 'family_person.dart';
import 'family_relation.dart';

class TreeGraphWarning {
  const TreeGraphWarning({
    required this.id,
    required this.code,
    required this.severity,
    required this.message,
    required this.hint,
    required this.personIds,
    required this.familyUnitIds,
    required this.relationIds,
  });

  final String id;
  final String code;
  final String severity;
  final String message;
  final String? hint;
  final List<String> personIds;
  final List<String> familyUnitIds;
  final List<String> relationIds;

  bool appliesToPerson(String? personId) {
    final normalizedPersonId = personId?.trim();
    if (normalizedPersonId == null || normalizedPersonId.isEmpty) {
      return false;
    }
    return personIds.contains(normalizedPersonId);
  }

  bool appliesToRelation(String? relationId) {
    final normalizedRelationId = relationId?.trim();
    if (normalizedRelationId == null || normalizedRelationId.isEmpty) {
      return false;
    }
    return relationIds.contains(normalizedRelationId);
  }

  factory TreeGraphWarning.fromJson(Map<String, dynamic> json) {
    return TreeGraphWarning(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString() ?? 'graph_warning',
      severity: json['severity']?.toString() ?? 'warning',
      message: json['message']?.toString() ?? 'Дерево требует проверки.',
      hint: json['hint']?.toString(),
      personIds: (json['personIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .toList(),
      familyUnitIds:
          (json['familyUnitIds'] as List<dynamic>? ?? const <dynamic>[])
              .map((value) => value.toString())
              .where((value) => value.isNotEmpty)
              .toList(),
      relationIds: (json['relationIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .toList(),
    );
  }
}

class TreeGraphViewerDescriptor {
  const TreeGraphViewerDescriptor({
    required this.personId,
    required this.primaryRelationLabel,
    required this.isBlood,
    required this.alternatePathCount,
    required this.pathSummary,
    required this.primaryPathPersonIds,
  });

  final String personId;
  final String? primaryRelationLabel;
  final bool isBlood;
  final int alternatePathCount;
  final String? pathSummary;
  final List<String> primaryPathPersonIds;

  factory TreeGraphViewerDescriptor.fromJson(Map<String, dynamic> json) {
    return TreeGraphViewerDescriptor(
      personId: json['personId']?.toString() ?? '',
      primaryRelationLabel: json['primaryRelationLabel']?.toString(),
      isBlood: json['isBlood'] == true,
      alternatePathCount:
          int.tryParse(json['alternatePathCount']?.toString() ?? '') ?? 0,
      pathSummary: json['pathSummary']?.toString(),
      primaryPathPersonIds:
          (json['primaryPathPersonIds'] as List<dynamic>? ?? const <dynamic>[])
              .map((value) => value.toString())
              .where((value) => value.isNotEmpty)
              .toList(),
    );
  }
}

class TreeGraphFamilyUnit {
  const TreeGraphFamilyUnit({
    required this.id,
    required this.rootParentSetId,
    required this.adultIds,
    required this.childIds,
    required this.relationIds,
    required this.unionId,
    required this.unionType,
    required this.unionStatus,
    required this.parentSetType,
    required this.isPrimaryParentSet,
    required this.label,
  });

  final String id;
  final String? rootParentSetId;
  final List<String> adultIds;
  final List<String> childIds;
  final List<String> relationIds;
  final String? unionId;
  final String? unionType;
  final String? unionStatus;
  final String? parentSetType;
  final bool isPrimaryParentSet;
  final String label;

  factory TreeGraphFamilyUnit.fromJson(Map<String, dynamic> json) {
    return TreeGraphFamilyUnit(
      id: json['id']?.toString() ?? '',
      rootParentSetId: json['rootParentSetId']?.toString(),
      adultIds: (json['adultIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .toList(),
      childIds: (json['childIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .toList(),
      relationIds: (json['relationIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .toList(),
      unionId: json['unionId']?.toString(),
      unionType: json['unionType']?.toString(),
      unionStatus: json['unionStatus']?.toString(),
      parentSetType: json['parentSetType']?.toString(),
      isPrimaryParentSet: json['isPrimaryParentSet'] == true,
      label: json['label']?.toString() ?? 'Семья',
    );
  }
}

class TreeGraphBranchBlock {
  const TreeGraphBranchBlock({
    required this.id,
    required this.rootUnitId,
    required this.label,
    required this.memberPersonIds,
  });

  final String id;
  final String rootUnitId;
  final String label;
  final List<String> memberPersonIds;

  factory TreeGraphBranchBlock.fromJson(Map<String, dynamic> json) {
    return TreeGraphBranchBlock(
      id: json['id']?.toString() ?? '',
      rootUnitId: json['rootUnitId']?.toString() ?? '',
      label: json['label']?.toString() ?? 'Семья',
      memberPersonIds:
          (json['memberPersonIds'] as List<dynamic>? ?? const <dynamic>[])
              .map((value) => value.toString())
              .where((value) => value.isNotEmpty)
              .toList(),
    );
  }
}

class TreeGraphGenerationRow {
  const TreeGraphGenerationRow({
    required this.row,
    required this.label,
    required this.personIds,
    required this.familyUnitIds,
  });

  final int row;
  final String? label;
  final List<String> personIds;
  final List<String> familyUnitIds;

  factory TreeGraphGenerationRow.fromJson(Map<String, dynamic> json) {
    return TreeGraphGenerationRow(
      row: int.tryParse(json['row']?.toString() ?? '') ?? 0,
      label: json['label']?.toString(),
      personIds: (json['personIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .toList(),
      familyUnitIds:
          (json['familyUnitIds'] as List<dynamic>? ?? const <dynamic>[])
              .map((value) => value.toString())
              .where((value) => value.isNotEmpty)
              .toList(),
    );
  }
}

class TreeGraphSnapshot {
  const TreeGraphSnapshot({
    required this.treeId,
    required this.viewerPersonId,
    required this.people,
    required this.relations,
    required this.familyUnits,
    required this.viewerDescriptors,
    required this.branchBlocks,
    required this.generationRows,
    required this.warnings,
  });

  final String treeId;
  final String? viewerPersonId;
  final List<FamilyPerson> people;
  final List<FamilyRelation> relations;
  final List<TreeGraphFamilyUnit> familyUnits;
  final List<TreeGraphViewerDescriptor> viewerDescriptors;
  final List<TreeGraphBranchBlock> branchBlocks;
  final List<TreeGraphGenerationRow> generationRows;
  final List<TreeGraphWarning> warnings;

  Map<String, TreeGraphViewerDescriptor> get viewerDescriptorByPersonId {
    return <String, TreeGraphViewerDescriptor>{
      for (final descriptor in viewerDescriptors)
        descriptor.personId: descriptor,
    };
  }

  Map<String, FamilyPerson> get personById {
    return <String, FamilyPerson>{
      for (final person in people) person.id: person
    };
  }

  TreeGraphViewerDescriptor? findViewerDescriptor(String? personId) {
    final normalizedPersonId = personId?.trim();
    if (normalizedPersonId == null || normalizedPersonId.isEmpty) {
      return null;
    }
    return viewerDescriptorByPersonId[normalizedPersonId];
  }

  FamilyPerson? findPerson(String? personId) {
    final normalizedPersonId = personId?.trim();
    if (normalizedPersonId == null || normalizedPersonId.isEmpty) {
      return null;
    }
    return personById[normalizedPersonId];
  }

  List<TreeGraphFamilyUnit> parentFamilyUnitsForChild(String? childPersonId) {
    final normalizedPersonId = childPersonId?.trim();
    if (normalizedPersonId == null || normalizedPersonId.isEmpty) {
      return const <TreeGraphFamilyUnit>[];
    }
    final units = familyUnits
        .where((unit) => unit.childIds.contains(normalizedPersonId))
        .toList();
    units.sort((left, right) {
      final primaryComparison = (right.isPrimaryParentSet ? 1 : 0)
          .compareTo(left.isPrimaryParentSet ? 1 : 0);
      if (primaryComparison != 0) {
        return primaryComparison;
      }
      return left.label.compareTo(right.label);
    });
    return units;
  }

  FamilyRelation? findDirectRelation(String? personAId, String? personBId) {
    final normalizedPersonAId = personAId?.trim();
    final normalizedPersonBId = personBId?.trim();
    if (normalizedPersonAId == null ||
        normalizedPersonAId.isEmpty ||
        normalizedPersonBId == null ||
        normalizedPersonBId.isEmpty) {
      return null;
    }
    for (final relation in relations) {
      if ((relation.person1Id == normalizedPersonAId &&
              relation.person2Id == normalizedPersonBId) ||
          (relation.person1Id == normalizedPersonBId &&
              relation.person2Id == normalizedPersonAId)) {
        return relation;
      }
    }
    return null;
  }

  List<TreeGraphWarning> warningsForPerson(String? personId) {
    final normalizedPersonId = personId?.trim();
    if (normalizedPersonId == null || normalizedPersonId.isEmpty) {
      return const <TreeGraphWarning>[];
    }
    return warnings
        .where((warning) => warning.appliesToPerson(normalizedPersonId))
        .toList();
  }

  List<TreeGraphWarning> warningsForRelation(String? relationId) {
    final normalizedRelationId = relationId?.trim();
    if (normalizedRelationId == null || normalizedRelationId.isEmpty) {
      return const <TreeGraphWarning>[];
    }
    return warnings
        .where((warning) => warning.appliesToRelation(normalizedRelationId))
        .toList();
  }

  TreeGraphBranchBlock? findBranchBlockForPerson(String? personId) {
    final normalizedPersonId = personId?.trim();
    if (normalizedPersonId == null || normalizedPersonId.isEmpty) {
      return null;
    }

    final adultUnit = familyUnits.firstWhere(
      (unit) => unit.adultIds.contains(normalizedPersonId),
      orElse: () => const TreeGraphFamilyUnit(
        id: '',
        rootParentSetId: null,
        adultIds: <String>[],
        childIds: <String>[],
        relationIds: <String>[],
        unionId: null,
        unionType: null,
        unionStatus: null,
        parentSetType: null,
        isPrimaryParentSet: false,
        label: 'Семья',
      ),
    );
    if (adultUnit.id.isNotEmpty) {
      return branchBlocks.firstWhere(
        (block) => block.rootUnitId == adultUnit.id,
        orElse: () => const TreeGraphBranchBlock(
          id: '',
          rootUnitId: '',
          label: 'Семья',
          memberPersonIds: <String>[],
        ),
      );
    }

    final childUnit = familyUnits.firstWhere(
      (unit) =>
          unit.childIds.contains(normalizedPersonId) && unit.isPrimaryParentSet,
      orElse: () => const TreeGraphFamilyUnit(
        id: '',
        rootParentSetId: null,
        adultIds: <String>[],
        childIds: <String>[],
        relationIds: <String>[],
        unionId: null,
        unionType: null,
        unionStatus: null,
        parentSetType: null,
        isPrimaryParentSet: false,
        label: 'Семья',
      ),
    );
    if (childUnit.id.isEmpty) {
      return null;
    }
    final block = branchBlocks.firstWhere(
      (entry) => entry.rootUnitId == childUnit.id,
      orElse: () => const TreeGraphBranchBlock(
        id: '',
        rootUnitId: '',
        label: 'Семья',
        memberPersonIds: <String>[],
      ),
    );
    return block.id.isEmpty ? null : block;
  }

  factory TreeGraphSnapshot.fromJson(
    Map<String, dynamic> json, {
    required FamilyPerson Function(Map<String, dynamic>) personParser,
    required FamilyRelation Function(Map<String, dynamic>) relationParser,
  }) {
    return TreeGraphSnapshot(
      treeId: json['treeId']?.toString() ?? '',
      viewerPersonId: json['viewerPersonId']?.toString(),
      people: (json['people'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(personParser)
          .where((person) => person.id.isNotEmpty)
          .toList(),
      relations: (json['relations'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(relationParser)
          .where((relation) => relation.id.isNotEmpty)
          .toList(),
      familyUnits: (json['familyUnits'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(TreeGraphFamilyUnit.fromJson)
          .where((unit) => unit.id.isNotEmpty)
          .toList(),
      viewerDescriptors:
          (json['viewerDescriptors'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(TreeGraphViewerDescriptor.fromJson)
              .where((descriptor) => descriptor.personId.isNotEmpty)
              .toList(),
      branchBlocks:
          (json['branchBlocks'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(TreeGraphBranchBlock.fromJson)
              .where((block) => block.id.isNotEmpty)
              .toList(),
      generationRows:
          (json['generationRows'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Map<String, dynamic>>()
              .map(TreeGraphGenerationRow.fromJson)
              .toList(),
      warnings: (json['warnings'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(TreeGraphWarning.fromJson)
          .where((warning) => warning.id.isNotEmpty)
          .toList(),
    );
  }
}
