part of '../custom_api_family_tree_service.dart';

mixin _CustomApiTreeCrudMixin on _CustomApiFamilyTreeHost {
  @override
  Future<String> createTree({
    required String name,
    required String description,
    required bool isPrivate,
    TreeKind kind = TreeKind.family,
    IncludeRules? includeRules,
  }) async {
    // Phase 3.4 (DECISIONS.md ответ Q4 + fix-1): передаём
    // includeRules только когда они явно заданы wizard'ом. Missing
    // payload field → backend применит legacy default manual.
    // Malformed payload → backend вернёт 400, мы пропустим
    // exception вверх к UI как обычный network error.
    final body = <String, dynamic>{
      'name': name,
      'description': description,
      'isPrivate': isPrivate,
      'kind': kind.name,
      if (kind == TreeKind.family) 'bindSemya': true,
    };
    if (includeRules != null) {
      body['includeRules'] = includeRules.toJson();
    }

    final response = await _requestJson(
      method: 'POST',
      path: '/v1/trees',
      body: body,
    );

    final tree = _treeFromResponse(response);
    await _cacheTree(tree);
    return tree.id;
  }

  @override
  Future<List<FamilyTree>> getUserTrees() async {
    final response = await _requestJson(
      method: 'GET',
      path: '/v1/trees',
    );

    final trees = _treeListFromResponse(response);
    await _cacheTrees(trees);
    return trees;
  }

  @override
  Future<List<FamilyPerson>> getRelatives(String treeId) {
    final cached = _relativesCache[treeId];
    final cachedAt = _relativesCacheStamps[treeId];
    if (cached != null &&
        cachedAt != null &&
        _clock().difference(cachedAt) <
            _CustomApiFamilyTreeBase._relativesCacheTtl) {
      return Future.value(cached);
    }
    final inFlight = _relativesInFlight[treeId];
    if (inFlight != null) {
      return inFlight;
    }
    final generation = _treeCacheGeneration[treeId] ?? 0;
    late final Future<List<FamilyPerson>> tracked;
    tracked = _fetchRelatives(treeId, generation: generation).whenComplete(() {
      if (identical(_relativesInFlight[treeId], tracked)) {
        _relativesInFlight.remove(treeId);
      }
    });
    _relativesInFlight[treeId] = tracked;
    return tracked;
  }

  Future<List<FamilyPerson>> _fetchRelatives(
    String treeId, {
    required int generation,
  }) async {
    final response = await _requestJson(
      method: 'GET',
      path: '/v1/trees/$treeId/persons',
    );

    final relatives = _personListFromResponse(response);
    if (generation != (_treeCacheGeneration[treeId] ?? 0)) {
      return relatives;
    }
    for (final person in relatives) {
      _personTreeIds[person.id] = treeId;
    }
    await _cachePersons(relatives);
    if (generation == (_treeCacheGeneration[treeId] ?? 0)) {
      _relativesCache[treeId] = relatives;
      _relativesCacheStamps[treeId] = _clock();
    }
    return relatives;
  }

  @override
  Future<String> addRelative(
      String treeId, Map<String, dynamic> personData) async {
    final response = await _requestJson(
      method: 'POST',
      path: '/v1/trees/$treeId/persons',
      body: _normalizePersonPayload(personData),
    );

    final person = _personFromResponse(response, fallbackTreeId: treeId);
    _personTreeIds[person.id] = treeId;
    _invalidateTreeCaches(treeId);
    await _cachePerson(person);
    return person.id;
  }

  @override
  Future<void> updateRelative(
      String personId, Map<String, dynamic> personData) async {
    final treeId = await resolveTreeIdForPerson(personId);
    if (treeId == null) {
      throw const CustomApiException(
        'Не удалось определить дерево для редактируемого родственника',
      );
    }

    final response = await _requestJson(
      method: 'PATCH',
      path: '/v1/trees/$treeId/persons/$personId',
      body: _normalizePersonPayload(personData),
    );

    final updatedPerson = _personFromResponse(response, fallbackTreeId: treeId);
    _personTreeIds[updatedPerson.id] = treeId;
    _invalidateTreeCaches(treeId);
    await _cachePerson(updatedPerson);

    // Phase 1.1 unified-graph migration: identity propagation. The
    // backend may have fanned the change out to other person
    // records on OTHER trees that share the same identityId
    // (typically: the same human entered into a different tree
    // by the same user via the cross-tree picker). Server tells
    // us which trees got touched in `identityPropagation.affected`;
    // we invalidate those trees' graph-snapshot caches so the
    // next read fetches the updated data.
    //
    // Backwards-compatible: when the backend response omits the
    // field (older deploys, non-propagating updates), the loop is
    // a no-op.
    final propagation = response['identityPropagation'];
    if (propagation is Map<String, dynamic>) {
      final affected = propagation['affected'];
      if (affected is List) {
        for (final entry in affected) {
          if (entry is Map) {
            final affectedTreeId = entry['treeId']?.toString();
            if (affectedTreeId != null && affectedTreeId.isNotEmpty) {
              _invalidateTreeCaches(affectedTreeId);
              // We don't have the freshly-propagated person in
              // hand without an extra round-trip — clearing the
              // snapshot cache is enough to force the consumer
              // to refetch. Per-person cache stays as a stale
              // hint until the consumer pulls fresh data.
            }
          }
        }
      }
    }
  }

  @override
  Future<FamilyPerson> getPersonById(String treeId, String personId) async {
    final response = await _requestJson(
      method: 'GET',
      path: '/v1/trees/$treeId/persons/$personId',
    );

    final person = _personFromResponse(response, fallbackTreeId: treeId);
    _personTreeIds[person.id] = treeId;
    await _cachePerson(person);
    return person;
  }

  @override
  Future<PersonDossier> getPersonDossier(String treeId, String personId) async {
    final response = await _requestJson(
      method: 'GET',
      path: '/v1/trees/$treeId/persons/$personId/dossier',
    );
    final dossier = response['dossier'];
    if (dossier is! Map<String, dynamic>) {
      throw const CustomApiException('Backend не вернул dossier человека');
    }

    return PersonDossier.fromJson(dossier);
  }

  @override
  Future<void> proposePersonProfileContribution({
    required String treeId,
    required String personId,
    required Map<String, dynamic> fields,
    String? message,
  }) async {
    await _requestJson(
      method: 'POST',
      path: '/v1/trees/$treeId/persons/$personId/profile-contributions',
      body: {
        'fields': _normalizePersonPayload(fields),
        if (message != null && message.trim().isNotEmpty)
          'message': message.trim(),
      },
    );
  }

  @override
  Future<RelationType> getRelationToUser(
      String treeId, String relativeId) async {
    try {
      final snapshot =
          _graphSnapshotCache[treeId] ?? await getTreeGraphSnapshot(treeId);
      final descriptor = snapshot.viewerDescriptorByPersonId[relativeId];
      if (descriptor?.primaryRelationLabel != null) {
        return _relationTypeFromViewerLabel(descriptor!.primaryRelationLabel);
      }
    } catch (_) {
      // Fallback to direct-relation lookup below.
    }

    return RelationType.other;
  }

  @override
  Future<void> addRelation(
    String treeId,
    String person1Id,
    String person2Id,
    RelationType relationType,
  ) async {
    await createRelation(
      treeId: treeId,
      person1Id: person1Id,
      person2Id: person2Id,
      relation1to2: relationType,
      isConfirmed: true,
    );
  }

  @override
  Future<FamilyRelation> createRelation({
    required String treeId,
    required String person1Id,
    required String person2Id,
    required RelationType relation1to2,
    bool isConfirmed = true,
    DateTime? marriageDate,
    DateTime? divorceDate,
    String? customRelationLabel1to2,
    String? customRelationLabel2to1,
    String? unionStatus,
  }) async {
    final resolvedPerson1Id = await _resolvePersonIdForTree(treeId, person1Id);
    final resolvedPerson2Id = await _resolvePersonIdForTree(treeId, person2Id);

    if (resolvedPerson1Id == null || resolvedPerson2Id == null) {
      throw const CustomApiException(
        'Не удалось определить участников родственной связи в дереве',
      );
    }

    final response = await _requestJson(
      method: 'POST',
      path: '/v1/trees/$treeId/relations',
      body: {
        'person1Id': resolvedPerson1Id,
        'person2Id': resolvedPerson2Id,
        'relation1to2': FamilyRelation.relationTypeToString(relation1to2),
        'relation2to1': FamilyRelation.relationTypeToString(
          FamilyRelation.getMirrorRelation(relation1to2),
        ),
        'isConfirmed': isConfirmed,
        if (marriageDate != null) 'marriageDate': marriageDate,
        if (divorceDate != null) 'divorceDate': divorceDate,
        if (unionStatus != null && unionStatus.trim().isNotEmpty)
          'unionStatus': unionStatus.trim(),
        if (customRelationLabel1to2 != null &&
            customRelationLabel1to2.trim().isNotEmpty)
          'customRelationLabel1to2': customRelationLabel1to2.trim(),
        if (customRelationLabel2to1 != null &&
            customRelationLabel2to1.trim().isNotEmpty)
          'customRelationLabel2to1': customRelationLabel2to1.trim(),
      },
    );

    final relation = _relationFromResponse(response, fallbackTreeId: treeId);
    _invalidateTreeCaches(treeId);
    await _cacheRelation(relation);
    return relation;
  }

  @override
  Future<List<FamilyPerson>> getOfflineProfilesByCreator(
    String treeId,
    String creatorId,
  ) async {
    final persons = await getRelatives(treeId);
    return persons
        .where(
            (person) => person.creatorId == creatorId && person.userId == null)
        .toList();
  }

  @override
  Future<String?> findSpouseId(String treeId, String personId) async {
    final resolvedPersonId = await _resolvePersonIdForTree(treeId, personId);
    if (resolvedPersonId == null) {
      return null;
    }

    final relations = await getRelations(treeId);
    for (final relation in relations) {
      final isSpouse = relation.relation1to2 == RelationType.spouse ||
          relation.relation2to1 == RelationType.spouse ||
          relation.relation1to2 == RelationType.partner ||
          relation.relation2to1 == RelationType.partner;
      if (!isSpouse) {
        continue;
      }

      if (relation.person1Id == resolvedPersonId) {
        return relation.person2Id;
      }
      if (relation.person2Id == resolvedPersonId) {
        return relation.person1Id;
      }
    }

    return null;
  }

  @override
  Future<void> checkAndCreateSpouseRelationIfNeeded(
    String treeId,
    String childId,
    String newParentId,
  ) async {
    final resolvedChildId = await _resolvePersonIdForTree(treeId, childId);
    final resolvedParentId = await _resolvePersonIdForTree(treeId, newParentId);
    if (resolvedChildId == null || resolvedParentId == null) {
      return;
    }

    final relations = await getRelations(treeId);
    String? otherParentId;
    for (final relation in relations) {
      if (relation.person1Id == resolvedParentId ||
          relation.person2Id == resolvedParentId) {
        continue;
      }

      if (relation.person1Id == resolvedChildId &&
          relation.relation1to2 == RelationType.child) {
        otherParentId = relation.person2Id;
        break;
      }
      if (relation.person2Id == resolvedChildId &&
          relation.relation2to1 == RelationType.child) {
        otherParentId = relation.person1Id;
        break;
      }
      if (relation.person1Id == resolvedChildId &&
          relation.relation2to1 == RelationType.parent) {
        otherParentId = relation.person2Id;
        break;
      }
      if (relation.person2Id == resolvedChildId &&
          relation.relation1to2 == RelationType.parent) {
        otherParentId = relation.person1Id;
        break;
      }
    }

    if (otherParentId == null) {
      return;
    }

    final hasSpouseRelation = relations.any((relation) {
      final matchesPair = (relation.person1Id == resolvedParentId &&
              relation.person2Id == otherParentId) ||
          (relation.person1Id == otherParentId &&
              relation.person2Id == resolvedParentId);
      if (!matchesPair) {
        return false;
      }

      return relation.relation1to2 == RelationType.spouse ||
          relation.relation2to1 == RelationType.spouse ||
          relation.relation1to2 == RelationType.partner ||
          relation.relation2to1 == RelationType.partner;
    });

    if (!hasSpouseRelation) {
      await createRelation(
        treeId: treeId,
        person1Id: resolvedParentId,
        person2Id: otherParentId,
        relation1to2: RelationType.spouse,
        isConfirmed: true,
      );
    }
  }

  @override
  Future<void> checkAndCreateParentSiblingRelations(
    String treeId,
    String existingSiblingId,
    String newSiblingId,
  ) async {
    final resolvedExistingSiblingId =
        await _resolvePersonIdForTree(treeId, existingSiblingId);
    final resolvedNewSiblingId =
        await _resolvePersonIdForTree(treeId, newSiblingId);
    if (resolvedExistingSiblingId == null || resolvedNewSiblingId == null) {
      return;
    }

    final relations = await getRelations(treeId);
    final parentIds = <String>{};
    for (final relation in relations) {
      final parentToChild = relation.person2Id == resolvedExistingSiblingId &&
          relation.relation1to2 == RelationType.parent;
      final childToParent = relation.person1Id == resolvedExistingSiblingId &&
          relation.relation2to1 == RelationType.parent;
      if (parentToChild && relation.person1Id != resolvedNewSiblingId) {
        parentIds.add(relation.person1Id);
      } else if (childToParent && relation.person2Id != resolvedNewSiblingId) {
        parentIds.add(relation.person2Id);
      }
    }

    for (final parentId in parentIds) {
      final hasParentRelation = relations.any((relation) {
        final matchesPair = (relation.person1Id == parentId &&
                relation.person2Id == resolvedNewSiblingId) ||
            (relation.person1Id == resolvedNewSiblingId &&
                relation.person2Id == parentId);
        if (!matchesPair) {
          return false;
        }
        return relation.relation1to2 == RelationType.parent ||
            relation.relation2to1 == RelationType.parent;
      });

      if (!hasParentRelation) {
        await createRelation(
          treeId: treeId,
          person1Id: parentId,
          person2Id: resolvedNewSiblingId,
          relation1to2: RelationType.parent,
          isConfirmed: true,
        );
      }
    }
  }

  @override
  Future<List<SelectableTree>> getSelectableTreesForCurrentUser() async {
    final response = await _requestJson(
      method: 'GET',
      path: '/v1/trees/selectable',
    );

    final rawTrees = response['trees'];
    if (rawTrees is! List<dynamic>) {
      return const <SelectableTree>[];
    }

    return rawTrees
        .whereType<Map<String, dynamic>>()
        .map((tree) {
          final createdAtValue = tree['createdAt']?.toString();
          return SelectableTree(
            id: tree['id']?.toString() ?? '',
            name: tree['name']?.toString() ?? 'Семейное дерево',
            createdAt: createdAtValue != null && createdAtValue.isNotEmpty
                ? DateTime.tryParse(createdAtValue)
                : null,
          );
        })
        .where((tree) => tree.id.isNotEmpty)
        .toList();
  }

  @override
  Future<bool> isCurrentUserInTree(String treeId) async {
    final currentUserId = _authService.currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      return false;
    }

    final relatives = await getRelatives(treeId);
    return relatives.any((person) => person.userId == currentUserId);
  }

  @override
  Future<void> addCurrentUserToTree({
    required String treeId,
    required String targetPersonId,
    required RelationType relationType,
  }) async {
    final currentUserId = _authService.currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) {
      throw const CustomApiException('Пользователь не авторизован');
    }

    if (await isCurrentUserInTree(treeId)) {
      return;
    }

    final profile = await _loadCurrentUserProfile();
    final response = await _requestJson(
      method: 'POST',
      path: '/v1/trees/$treeId/persons',
      body: {
        'userId': currentUserId,
        'firstName': profile?.firstName,
        'lastName': profile?.lastName,
        'middleName': profile?.middleName,
        'name': profile?.displayName ?? _authService.currentUserDisplayName,
        'photoUrl': profile?.photoURL ?? _authService.currentUserPhotoUrl,
        'gender': profile?.gender?.name ?? Gender.unknown.name,
        'birthDate': profile?.birthDate?.toIso8601String(),
      },
    );

    final selfPerson = _personFromResponse(response, fallbackTreeId: treeId);
    _personTreeIds[selfPerson.id] = treeId;
    await _cachePerson(selfPerson);
    // This POST bypasses addRelative(), so it must invalidate the same
    // caches addRelative() would — otherwise the createRelation() call
    // right below resolves targetPersonId/selfPerson.id against a
    // getRelatives() snapshot taken before this person existed (surfaced
    // by the getRelatives short-TTL cache: isCurrentUserInTree() above
    // just populated it with the pre-join roster).
    _invalidateTreeCaches(treeId);

    await createRelation(
      treeId: treeId,
      person1Id: targetPersonId,
      person2Id: selfPerson.id,
      relation1to2: relationType,
      isConfirmed: true,
    );
  }

  @override
  Future<void> removeTree(String treeId) async {
    await _requestDelete(path: '/v1/trees/$treeId');

    final localStorageService = _localStorageService;
    if (localStorageService != null) {
      await localStorageService.deleteTree(treeId);
      await localStorageService.deletePersonsByTreeId(treeId);
      await localStorageService.deleteRelationsByTreeId(treeId);
    }

    _invalidateTreeCaches(treeId);
    _personTreeIds.removeWhere((_, cachedTreeId) => cachedTreeId == treeId);
  }

  @override
  Future<void> deleteRelative(String treeId, String personId) async {
    final resolvedPersonId = await _resolvePersonIdForTree(treeId, personId);
    if (resolvedPersonId == null) {
      throw const CustomApiException(
          'Не удалось определить родственника для удаления');
    }

    await _requestDelete(path: '/v1/trees/$treeId/persons/$resolvedPersonId');
    _personTreeIds.remove(resolvedPersonId);
    _invalidateTreeCaches(treeId);
    final localStorageService = _localStorageService;
    if (localStorageService != null) {
      await localStorageService.deleteRelative(resolvedPersonId);
      await localStorageService.deleteRelationsByPersonId(
        treeId,
        resolvedPersonId,
      );
    }
  }

  @override
  Future<FamilyPerson> unlinkUserFromPerson({
    required String treeId,
    required String personId,
  }) async {
    final resolvedPersonId = await _resolvePersonIdForTree(treeId, personId);
    if (resolvedPersonId == null) {
      throw const CustomApiException(
        'Не удалось найти этого человека в дереве',
      );
    }

    final response = await _requestJson(
      method: 'DELETE',
      path: '/v1/trees/$treeId/persons/$resolvedPersonId/user-link',
    );
    final personJson = response['person'];
    if (personJson is! Map<String, dynamic>) {
      throw const CustomApiException(
        'Сервер вернул некорректный ответ при отвязке пользователя',
      );
    }
    final updated = _personFromJson(personJson, fallbackTreeId: treeId);
    _invalidateTreeCaches(treeId);
    return updated;
  }

  @override
  Future<FamilyPerson> addRelativeMedia({
    required String treeId,
    required String personId,
    required Map<String, dynamic> mediaData,
  }) async {
    final resolvedPersonId = await _resolvePersonIdForTree(treeId, personId);
    if (resolvedPersonId == null) {
      throw const CustomApiException(
        'Не удалось определить родственника для добавления медиа',
      );
    }

    final response = await _requestJson(
      method: 'POST',
      path: '/v1/trees/$treeId/persons/$resolvedPersonId/media',
      body: _normalizePersonPayload(mediaData),
    );

    final updatedPerson = _personFromResponse(response, fallbackTreeId: treeId);
    _personTreeIds[updatedPerson.id] = treeId;
    _invalidateTreeCaches(treeId);
    _invalidateCachesForPropagatedTrees(response);
    await _cachePerson(updatedPerson);
    return updatedPerson;
  }

  @override
  Future<FamilyPerson> updateRelativeMedia({
    required String treeId,
    required String personId,
    required String mediaId,
    required Map<String, dynamic> mediaData,
  }) async {
    final resolvedPersonId = await _resolvePersonIdForTree(treeId, personId);
    if (resolvedPersonId == null) {
      throw const CustomApiException(
        'Не удалось определить родственника для обновления медиа',
      );
    }

    final response = await _requestJson(
      method: 'PATCH',
      path: '/v1/trees/$treeId/persons/$resolvedPersonId/media/$mediaId',
      body: _normalizePersonPayload(mediaData),
    );

    final updatedPerson = _personFromResponse(response, fallbackTreeId: treeId);
    _personTreeIds[updatedPerson.id] = treeId;
    _invalidateTreeCaches(treeId);
    _invalidateCachesForPropagatedTrees(response);
    await _cachePerson(updatedPerson);
    return updatedPerson;
  }

  @override
  Future<FamilyPerson> deleteRelativeMedia({
    required String treeId,
    required String personId,
    required String mediaId,
    String? fallbackUrl,
  }) async {
    final resolvedPersonId = await _resolvePersonIdForTree(treeId, personId);
    if (resolvedPersonId == null) {
      throw const CustomApiException(
        'Не удалось определить родственника для удаления медиа',
      );
    }

    final body = <String, dynamic>{};
    if (fallbackUrl != null && fallbackUrl.isNotEmpty) {
      body['url'] = fallbackUrl;
    }

    final response = await _requestJson(
      method: 'DELETE',
      path: '/v1/trees/$treeId/persons/$resolvedPersonId/media/$mediaId',
      body: body.isEmpty ? null : body,
    );

    final updatedPerson = _personFromResponse(response, fallbackTreeId: treeId);
    _personTreeIds[updatedPerson.id] = treeId;
    _invalidateTreeCaches(treeId);
    _invalidateCachesForPropagatedTrees(response);
    await _cachePerson(updatedPerson);
    return updatedPerson;
  }

  // Phase 1.1 helper: when the backend reports `propagatedTo` /
  // `identityPropagation.affected` on a write response, drop the
}
