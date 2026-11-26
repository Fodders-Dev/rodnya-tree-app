part of '../custom_api_family_tree_service.dart';

mixin _CustomApiFamilyTreeParsers on _CustomApiFamilyTreeBase {
  FamilyTree _treeFromResponse(Map<String, dynamic> response) {
    final tree = response['tree'];
    if (tree is Map<String, dynamic>) {
      return _treeFromJson(tree);
    }
    return _treeFromJson(response);
  }

  List<FamilyTree> _treeListFromResponse(Map<String, dynamic> response) {
    final rawTrees = response['trees'];
    if (rawTrees is! List<dynamic>) {
      return const <FamilyTree>[];
    }

    return rawTrees
        .whereType<Map<String, dynamic>>()
        .map(_treeFromJson)
        .where((tree) => tree.id.isNotEmpty)
        .toList();
  }

  FamilyTree _treeFromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final updatedAt = DateTime.tryParse(json['updatedAt']?.toString() ?? '');

    return FamilyTree(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Семейное дерево',
      description: json['description']?.toString() ?? '',
      creatorId: json['creatorId']?.toString() ?? '',
      memberIds: (json['memberIds'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => value.toString())
          .toList(),
      createdAt: createdAt ?? DateTime.now(),
      updatedAt: updatedAt ?? createdAt ?? DateTime.now(),
      isPrivate: json['isPrivate'] != false,
      members: (json['members'] as List<dynamic>? ?? const <dynamic>[])
          .map((value) => value.toString())
          .toList(),
      publicSlug: json['publicSlug']?.toString(),
      isCertified: json['isCertified'] == true,
      certificationNote: json['certificationNote']?.toString(),
      kind: json['kind']?.toString().trim().toLowerCase() == 'friends'
          ? TreeKind.friends
          : TreeKind.family,
    );
  }

  FamilyPerson _personFromResponse(
    Map<String, dynamic> response, {
    required String fallbackTreeId,
  }) {
    final person = response['person'];
    if (person is Map<String, dynamic>) {
      return _personFromJson(person, fallbackTreeId: fallbackTreeId);
    }
    return _personFromJson(response, fallbackTreeId: fallbackTreeId);
  }

  List<FamilyPerson> _personListFromResponse(Map<String, dynamic> response) {
    final rawPersons = response['persons'];
    if (rawPersons is! List<dynamic>) {
      return const <FamilyPerson>[];
    }

    return rawPersons
        .whereType<Map<String, dynamic>>()
        .map((person) => _personFromJson(person))
        .where((person) => person.id.isNotEmpty)
        .toList();
  }

  FamilyPerson _personFromJson(
    Map<String, dynamic> json, {
    String? fallbackTreeId,
  }) {
    final birthDate = DateTime.tryParse(json['birthDate']?.toString() ?? '');
    final deathDate = DateTime.tryParse(json['deathDate']?.toString() ?? '');
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final updatedAt = DateTime.tryParse(json['updatedAt']?.toString() ?? '');
    final treeId = json['treeId']?.toString() ?? fallbackTreeId ?? '';

    return FamilyPerson(
      id: json['id']?.toString() ?? '',
      treeId: treeId,
      userId: json['userId']?.toString(),
      identityId: json['identityId']?.toString(),
      name: json['name']?.toString() ?? '',
      maidenName: json['maidenName']?.toString(),
      photoUrl:
          json['primaryPhotoUrl']?.toString() ?? json['photoUrl']?.toString(),
      photoGallery: _photoGalleryFromJson(json['photoGallery']),
      gender: FamilyPerson.genderFromString(json['gender']?.toString()),
      birthDate: birthDate,
      // F5: «знаю только год» — точность дат с бэка.
      birthDatePrecision: FamilyPerson.datePrecisionFromString(
        json['birthDatePrecision']?.toString(),
      ),
      birthPlace: json['birthPlace']?.toString(),
      deathDate: deathDate,
      deathDatePrecision: FamilyPerson.datePrecisionFromString(
        json['deathDatePrecision']?.toString(),
      ),
      deathPlace: json['deathPlace']?.toString(),
      familySummary: json['familySummary']?.toString() ??
          json['notes']?.toString() ??
          json['bio']?.toString(),
      bio: json['bio']?.toString(),
      isAlive: json['isAlive'] != false,
      visibility: json['visibility']?.toString() ?? 'private',
      creatorId: json['creatorId']?.toString(),
      createdAt: createdAt ?? DateTime.now(),
      updatedAt: updatedAt ?? createdAt ?? DateTime.now(),
      notes: json['notes']?.toString() ??
          json['familySummary']?.toString() ??
          json['bio']?.toString(),
      details: json['details'] is Map<String, dynamic>
          ? FamilyPersonDetails.fromMap(json['details'] as Map<String, dynamic>)
          : null,
    );
  }

  FamilyRelation _relationFromResponse(
    Map<String, dynamic> response, {
    required String fallbackTreeId,
  }) {
    final relation = response['relation'];
    if (relation is Map<String, dynamic>) {
      return _relationFromJson(relation, fallbackTreeId: fallbackTreeId);
    }
    return _relationFromJson(response, fallbackTreeId: fallbackTreeId);
  }

  List<FamilyRelation> _relationListFromResponse(
      Map<String, dynamic> response) {
    final rawRelations = response['relations'];
    if (rawRelations is! List<dynamic>) {
      return const <FamilyRelation>[];
    }

    return rawRelations
        .whereType<Map<String, dynamic>>()
        .map((relation) => _relationFromJson(relation))
        .where((relation) => relation.id.isNotEmpty)
        .toList();
  }

  FamilyRelation _relationFromJson(
    Map<String, dynamic> json, {
    String? fallbackTreeId,
  }) {
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final updatedAt = DateTime.tryParse(json['updatedAt']?.toString() ?? '');
    final customRelationLabel1to2 =
        json['customRelationLabel1to2']?.toString().trim();
    final customRelationLabel2to1 =
        json['customRelationLabel2to1']?.toString().trim();

    return FamilyRelation(
      id: json['id']?.toString() ?? '',
      treeId: json['treeId']?.toString() ?? fallbackTreeId ?? '',
      person1Id: json['person1Id']?.toString() ?? '',
      person2Id: json['person2Id']?.toString() ?? '',
      relation1to2: FamilyRelation.stringToRelationType(
        json['relation1to2']?.toString(),
      ),
      relation2to1: FamilyRelation.stringToRelationType(
        json['relation2to1']?.toString(),
      ),
      isConfirmed: json['isConfirmed'] == true,
      createdAt: createdAt ?? DateTime.now(),
      updatedAt: updatedAt,
      createdBy: json['createdBy']?.toString(),
      marriageDate: DateTime.tryParse(json['marriageDate']?.toString() ?? ''),
      divorceDate: DateTime.tryParse(json['divorceDate']?.toString() ?? ''),
      customRelationLabel1to2:
          customRelationLabel1to2 == null || customRelationLabel1to2.isEmpty
              ? null
              : customRelationLabel1to2,
      customRelationLabel2to1:
          customRelationLabel2to1 == null || customRelationLabel2to1.isEmpty
              ? null
              : customRelationLabel2to1,
      parentSetId: json['parentSetId']?.toString(),
      parentSetType: json['parentSetType']?.toString(),
      isPrimaryParentSet: json['isPrimaryParentSet'] is bool
          ? json['isPrimaryParentSet'] as bool
          : null,
      unionId: json['unionId']?.toString(),
      unionType: json['unionType']?.toString(),
      unionStatus: json['unionStatus']?.toString(),
    );
  }

  RelationType _relationTypeFromViewerLabel(String? label) {
    final normalizedLabel = (label ?? '').trim().toLowerCase();
    if (normalizedLabel.isEmpty) {
      return RelationType.other;
    }
    // B2 (ревью FR5): союз распознаём по ОТДЕЛЬНОМУ СЛОВУ, а не подстроке.
    // Иначе genitive-форма «жены»/«мужа» в притяжательных метках («Семья
    // жены») ложно совпадала бы с прямым супругом.
    final labelWords = normalizedLabel
        .split(RegExp(r'[^а-яёa-z]+'))
        .where((word) => word.isNotEmpty)
        .toSet();
    bool isDirectSpouseWord() =>
        labelWords.contains('муж') ||
        labelWords.contains('жена') ||
        labelWords.contains('супруг') ||
        labelWords.contains('супруга');
    if (normalizedLabel.contains('отчим') ||
        normalizedLabel.contains('мачех')) {
      return RelationType.stepparent;
    }
    if (normalizedLabel.contains('пасын') ||
        normalizedLabel.contains('падчер')) {
      return RelationType.stepchild;
    }
    // B2: бывший союз. Метки графа гендерные («Бывший муж»/«Бывшая жена»/
    // «Бывший партнёр»/«Бывшая партнёрша»), проверяем ДО текущих spouse/
    // partner, иначе «Бывший супруг» попал бы в spouse. Супруга ловим
    // словом (не подстрокой); 'партн' ловит и е, и ё.
    if (normalizedLabel.contains('бывш')) {
      if (normalizedLabel.contains('партн')) {
        return RelationType.ex_partner;
      }
      if (isDirectSpouseWord()) {
        return RelationType.ex_spouse;
      }
    }
    // B2 (ревью FR5): притяжательные in-law метки backend строит как
    // «<родство> <супруг-в-родительном>» (Родитель жены, Родня мужа, Брат
    // супруга). Genitive «жены/мужа/супруга/супруги» — это НЕ сам супруг,
    // поэтому ловим их ДО ветки spouse, иначе «Родитель жены»/«Родня мужа»
    // ошибочно уходили бы в spouse.
    final mentionsSpousePossessive = normalizedLabel.contains('жены') ||
        normalizedLabel.contains('мужа') ||
        normalizedLabel.contains('супруга') ||
        normalizedLabel.contains('супруги');
    if (mentionsSpousePossessive) {
      if (normalizedLabel.contains('родител')) {
        // Родитель/Родительница жены/мужа/супруга → тесть/тёща-класс.
        return RelationType.parentInLaw;
      }
      if (normalizedLabel.contains('родн') ||
          normalizedLabel.contains('брат') ||
          normalizedLabel.contains('сестр') ||
          normalizedLabel.contains('сиблинг')) {
        // Родня жены/мужа, Брат/Сестра/Сиблинг супруга → родня супруга.
        return RelationType.siblingInLaw;
      }
    }
    if (isDirectSpouseWord()) {
      return RelationType.spouse;
    }
    if (normalizedLabel.contains('партн')) {
      return RelationType.partner;
    }
    if (normalizedLabel.contains('тесть') ||
        normalizedLabel.contains('теща') ||
        normalizedLabel.contains('свекор') ||
        normalizedLabel.contains('свекров')) {
      return RelationType.parentInLaw;
    }
    if (normalizedLabel.contains('прадед') ||
        normalizedLabel.contains('прабаб')) {
      return RelationType.greatGrandparent;
    }
    if (normalizedLabel.contains('дедуш') ||
        normalizedLabel.contains('бабуш')) {
      return RelationType.grandparent;
    }
    if (normalizedLabel.contains('дяд')) {
      return RelationType.uncle;
    }
    if (normalizedLabel.contains('тет')) {
      return RelationType.aunt;
    }
    if (normalizedLabel.contains('отец') ||
        normalizedLabel.contains('мать') ||
        normalizedLabel.contains('родитель') ||
        normalizedLabel.contains('предок')) {
      return RelationType.parent;
    }
    if (normalizedLabel.contains('зять') ||
        normalizedLabel.contains('невестк')) {
      return RelationType.childInLaw;
    }
    if (normalizedLabel.contains('правнук') ||
        normalizedLabel.contains('правнуч')) {
      return RelationType.greatGrandchild;
    }
    if (normalizedLabel.contains('внук') || normalizedLabel.contains('внуч')) {
      return RelationType.grandchild;
    }
    if (normalizedLabel.contains('племянниц')) {
      return RelationType.niece;
    }
    if (normalizedLabel.contains('племян')) {
      return RelationType.nephew;
    }
    if (normalizedLabel.contains('сын') ||
        normalizedLabel.contains('дочь') ||
        normalizedLabel.contains('ребен') ||
        normalizedLabel.contains('потомок')) {
      return RelationType.child;
    }
    if (normalizedLabel.contains('брат') ||
        normalizedLabel.contains('девер') ||
        normalizedLabel.contains('золов') ||
        normalizedLabel.contains('шурин') ||
        normalizedLabel.contains('своячениц') ||
        normalizedLabel.contains('свояк') ||
        normalizedLabel.contains('сестр') ||
        normalizedLabel.contains('сиблинг')) {
      if (normalizedLabel.contains('девер') ||
          normalizedLabel.contains('золов') ||
          normalizedLabel.contains('шурин') ||
          normalizedLabel.contains('своячениц') ||
          normalizedLabel.contains('свояк')) {
        return RelationType.siblingInLaw;
      }
      return RelationType.sibling;
    }
    if (normalizedLabel.contains('двоюрод') ||
        normalizedLabel.contains('троюрод') ||
        normalizedLabel.contains('четвероюрод') ||
        normalizedLabel.contains('кровный родственник')) {
      return RelationType.cousin;
    }
    if (normalizedLabel.contains('сват')) {
      return RelationType.inlaw;
    }
    return RelationType.other;
  }

  List<RelationRequest> _relationRequestListFromResponse(
    Map<String, dynamic> response,
  ) {
    final rawRequests = response['requests'];
    if (rawRequests is! List<dynamic>) {
      return const <RelationRequest>[];
    }

    return rawRequests
        .whereType<Map<String, dynamic>>()
        .map(_relationRequestFromJson)
        .where((request) => request.id.isNotEmpty)
        .toList();
  }

  List<TreeChangeRecord> _treeChangeRecordListFromResponse(
    Map<String, dynamic> response,
  ) {
    final rawRecords = response['records'];
    if (rawRecords is! List<dynamic>) {
      return const <TreeChangeRecord>[];
    }

    return rawRecords
        .whereType<Map<String, dynamic>>()
        .map(TreeChangeRecord.fromJson)
        .where((record) => record.id.isNotEmpty)
        .toList();
  }

  RelationRequest _relationRequestFromJson(Map<String, dynamic> json) {
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final respondedAt =
        DateTime.tryParse(json['respondedAt']?.toString() ?? '');

    return RelationRequest(
      id: json['id']?.toString() ?? '',
      treeId: json['treeId']?.toString() ?? '',
      senderId: json['senderId']?.toString() ?? '',
      recipientId: json['recipientId']?.toString() ?? '',
      senderToRecipient: FamilyRelation.stringToRelationType(
        json['senderToRecipient']?.toString() ??
            json['relationType']?.toString(),
      ),
      targetPersonId: json['targetPersonId']?.toString() ??
          json['offlineRelativeId']?.toString(),
      createdAt: createdAt ?? DateTime.now(),
      respondedAt: respondedAt,
      status: _requestStatusFromString(json['status']?.toString()),
      message: json['message']?.toString(),
    );
  }

  RequestStatus _requestStatusFromString(String? value) {
    switch (value) {
      case 'accepted':
        return RequestStatus.accepted;
      case 'rejected':
        return RequestStatus.rejected;
      case 'canceled':
        return RequestStatus.canceled;
      default:
        return RequestStatus.pending;
    }
  }

  @override
  Map<String, dynamic> _normalizePersonPayload(
      Map<String, dynamic> personData) {
    return personData.map(
      (key, value) => MapEntry(key, _normalizeJsonValue(value)),
    );
  }

  List<Map<String, dynamic>> _photoGalleryFromJson(dynamic rawValue) {
    if (rawValue is! List<dynamic>) {
      return const <Map<String, dynamic>>[];
    }

    return rawValue
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  dynamic _normalizeJsonValue(dynamic value) {
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is Map) {
      return value.map(
        (key, nestedValue) =>
            MapEntry(key.toString(), _normalizeJsonValue(nestedValue)),
      );
    }
    if (value is List) {
      return value.map(_normalizeJsonValue).toList();
    }
    return value;
  }

  // ── Phase 3.4 (chunk 2/3): graph-person owner-model endpoints ──
}
