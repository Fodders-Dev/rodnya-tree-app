part of '../custom_api_family_tree_service.dart';

mixin _CustomApiTreeGraphMixin on _CustomApiFamilyTreeHost {
  @override
  Future<List<FamilyRelation>> getRelations(String treeId) async {
    final response = await _requestJson(
      method: 'GET',
      path: '/v1/trees/$treeId/relations',
    );

    final relations = _relationListFromResponse(response);
    await _cacheRelations(relations);
    return relations;
  }

  @override
  Future<TreeGraphSnapshot> getTreeGraphSnapshot(String treeId) async {
    // Cache-first: try the on-disk snapshot before hitting the API
    // when nothing is in the in-memory cache yet. We still fall
    // through to the API call so the caller gets the freshest data,
    // but the disk cache lets the screen paint a parsed snapshot
    // even if the API call fails (offline). The API path overwrites
    // both caches on success.
    final cache = _treeGraphCache;
    if (cache != null && _graphSnapshotCache[treeId] == null) {
      try {
        final cached = await cache.read(treeId);
        if (cached != null) {
          final cachedSnapshot = TreeGraphSnapshot.fromJson(
            cached,
            personParser: (json) =>
                _personFromJson(json, fallbackTreeId: treeId),
            relationParser: (json) =>
                _relationFromJson(json, fallbackTreeId: treeId),
          );
          _graphSnapshotCache[treeId] = cachedSnapshot;
          for (final person in cachedSnapshot.people) {
            _personTreeIds[person.id] = treeId;
          }
        }
      } catch (_) {
        // Cache corruption is non-fatal — the API path repopulates.
      }
    }

    try {
      final response = await _requestJson(
        method: 'GET',
        path: '/v1/trees/$treeId/graph',
      );
      final snapshotJson = response['snapshot'];
      if (snapshotJson is! Map<String, dynamic>) {
        throw const CustomApiException(
          'Backend не вернул graph snapshot дерева',
        );
      }

      final snapshot = TreeGraphSnapshot.fromJson(
        snapshotJson,
        personParser: (json) => _personFromJson(json, fallbackTreeId: treeId),
        relationParser: (json) =>
            _relationFromJson(json, fallbackTreeId: treeId),
      );
      _graphSnapshotCache[treeId] = snapshot;
      for (final person in snapshot.people) {
        _personTreeIds[person.id] = treeId;
      }
      await _cachePersons(snapshot.people);
      await _cacheRelations(snapshot.relations);
      // Persist raw JSON for next cold-start / offline open.
      unawaited(cache?.write(treeId, snapshotJson));
      return snapshot;
    } catch (error) {
      // Fall back to whatever we hydrated from the cache so the
      // screen still has a snapshot to paint. Only rethrow when we
      // genuinely have nothing.
      final fallback = _graphSnapshotCache[treeId];
      if (fallback != null) return fallback;
      rethrow;
    }
  }

  @override
  Future<List<String>> getRelationPath({
    required String treeId,
    required String targetPersonId,
  }) async {
    final snapshot =
        _graphSnapshotCache[treeId] ?? await getTreeGraphSnapshot(treeId);
    final descriptor = snapshot.viewerDescriptorByPersonId[targetPersonId];
    return descriptor?.primaryPathPersonIds ?? const <String>[];
  }

  @override
  Future<void> reassignParentSet({
    required String treeId,
    required String childPersonId,
    required String parentPersonId,
    required String parentSetId,
    String? parentSetType,
    bool isPrimaryParentSet = true,
  }) async {
    await _requestJson(
      method: 'POST',
      path: '/v1/trees/$treeId/relations',
      body: {
        'person1Id': parentPersonId,
        'person2Id': childPersonId,
        'relation1to2': 'parent',
        'relation2to1': 'child',
        'isConfirmed': true,
        'parentSetId': parentSetId,
        if (parentSetType != null) 'parentSetType': parentSetType,
        'isPrimaryParentSet': isPrimaryParentSet,
      },
    );
    _invalidateTreeCaches(treeId);
  }

  @override
  Future<void> disconnectRelation({
    required String treeId,
    required String relationId,
  }) async {
    await _requestDelete(path: '/v1/trees/$treeId/relations/$relationId');
    _invalidateTreeCaches(treeId);
  }

  @override
  Future<void> setRelationType({
    required String treeId,
    required FamilyPerson anchorPerson,
    required FamilyPerson targetPerson,
    required String relationType,
    String? customRelationLabel1to2,
    String? customRelationLabel2to1,
  }) async {
    final relationTypeEnum = FamilyRelation.stringToRelationType(relationType);
    await createRelation(
      treeId: treeId,
      person1Id: targetPerson.id,
      person2Id: anchorPerson.id,
      relation1to2: relationTypeEnum,
      isConfirmed: true,
      customRelationLabel1to2: customRelationLabel1to2,
      customRelationLabel2to1: customRelationLabel2to1,
    );
    _invalidateTreeCaches(treeId);
  }

  @override
  Future<void> setUnionStatus({
    required String treeId,
    required String relationId,
    required String unionStatus,
  }) async {
    final relations = await getRelations(treeId);
    final relation = relations.firstWhere(
      (entry) => entry.id == relationId,
      orElse: () => throw const CustomApiException('Связь не найдена'),
    );
    await _requestJson(
      method: 'POST',
      path: '/v1/trees/$treeId/relations',
      body: {
        'person1Id': relation.person1Id,
        'person2Id': relation.person2Id,
        'relation1to2':
            FamilyRelation.relationTypeToString(relation.relation1to2),
        'relation2to1':
            FamilyRelation.relationTypeToString(relation.relation2to1),
        'isConfirmed': relation.isConfirmed,
        if (relation.marriageDate != null)
          'marriageDate': relation.marriageDate,
        if (relation.divorceDate != null) 'divorceDate': relation.divorceDate,
        'unionStatus': unionStatus,
      },
    );
    _invalidateTreeCaches(treeId);
  }

  @override
  Stream<List<FamilyPerson>> getRelativesStream(String treeId) {
    return Stream.fromFuture(getRelatives(treeId));
  }

  @override
  Stream<List<FamilyRelation>> getRelationsStream(String treeId) {
    return Stream.fromFuture(getRelations(treeId));
  }

  @override
  Future<RelationType> getRelationBetween(
    String treeId,
    String person1Id,
    String person2Id,
  ) async {
    final resolvedPerson1Id = await _resolvePersonIdForTree(treeId, person1Id);
    final resolvedPerson2Id = await _resolvePersonIdForTree(treeId, person2Id);

    if (resolvedPerson1Id == null || resolvedPerson2Id == null) {
      return RelationType.other;
    }

    try {
      final snapshot =
          _graphSnapshotCache[treeId] ?? await getTreeGraphSnapshot(treeId);
      if (snapshot.viewerPersonId == resolvedPerson1Id) {
        final descriptor =
            snapshot.viewerDescriptorByPersonId[resolvedPerson2Id];
        if (descriptor?.primaryRelationLabel != null) {
          return _relationTypeFromViewerLabel(descriptor!.primaryRelationLabel);
        }
      }
      if (snapshot.viewerPersonId == resolvedPerson2Id) {
        final descriptor =
            snapshot.viewerDescriptorByPersonId[resolvedPerson1Id];
        if (descriptor?.primaryRelationLabel != null) {
          return _relationTypeFromViewerLabel(descriptor!.primaryRelationLabel);
        }
      }
    } catch (_) {
      // Fallback to legacy direct-edge lookup below.
    }

    final relations = await getRelations(treeId);
    for (final relation in relations) {
      if (relation.person1Id == resolvedPerson1Id &&
          relation.person2Id == resolvedPerson2Id) {
        return relation.relation1to2;
      }
      if (relation.person1Id == resolvedPerson2Id &&
          relation.person2Id == resolvedPerson1Id) {
        return relation.relation2to1;
      }
    }

    return RelationType.other;
  }

  @override
  Future<List<TreeChangeRecord>> getTreeHistory({
    required String treeId,
    String? personId,
    String? type,
    String? actorId,
  }) async {
    final response = await _requestJson(
      method: 'GET',
      path: _buildPathWithQuery(
        '/v1/trees/$treeId/history',
        <String, String>{
          if (personId != null && personId.isNotEmpty) 'personId': personId,
          if (type != null && type.isNotEmpty) 'type': type,
          if (actorId != null && actorId.isNotEmpty) 'actorId': actorId,
        },
      ),
    );

    return _treeChangeRecordListFromResponse(response);
  }

  @override
  Future<GraphPersonAccessSnapshot?> getGraphPersonAccessSnapshot({
    required String graphPersonId,
  }) async {
    try {
      final response = await _requestJson(
        method: 'GET',
        path: '/v1/graph-persons/$graphPersonId',
      );
      final raw = response['graphPerson'];
      if (raw is! Map<String, dynamic>) return null;
      return GraphPersonAccessSnapshot.fromJson(raw);
    } catch (error) {
      // Visibility-gated read: 403/404 = viewer не имеет access.
      // UI gracefully скрывает visibility section. Network errors
      // тоже свернутся в null — лучше скрыть control, чем
      // показать broken UI.
      return null;
    }
  }

  @override
  Future<GraphPersonVisibility> setGraphPersonVisibility({
    required String graphPersonId,
    required VisibilityChoice choice,
  }) async {
    final response = await _requestJson(
      method: 'PATCH',
      path: '/v1/graph-persons/$graphPersonId/visibility',
      body: {'visibility': choice.serverValue},
    );
    final raw = response['graphPerson'];
    if (raw is! Map<String, dynamic>) {
      throw const FormatException(
        'Ожидался объект graphPerson в ответе на PATCH visibility',
      );
    }
    return GraphPersonVisibility.fromJson(raw);
  }

  @override
  Future<GraphPersonVisibility> clearGraphPersonVisibilityOverride({
    required String graphPersonId,
  }) async {
    final response = await _requestJson(
      method: 'DELETE',
      path: '/v1/graph-persons/$graphPersonId/visibility-override',
    );
    final raw = response['graphPerson'];
    if (raw is! Map<String, dynamic>) {
      throw const FormatException(
        'Ожидался объект graphPerson в ответе на DELETE visibility-override',
      );
    }
    return GraphPersonVisibility.fromJson(raw);
  }

  @override
  Future<EditGrant> addGraphPersonGrant({
    required String graphPersonId,
    required String granteeUserId,
    required EditGrantScope scope,
  }) async {
    final response = await _requestJson(
      method: 'POST',
      path: '/v1/graph-persons/$graphPersonId/grants',
      body: {
        'granteeUserId': granteeUserId,
        'scope': scope.serverValue,
      },
    );
    final raw = response['grant'];
    if (raw is! Map<String, dynamic>) {
      throw const FormatException(
        'Ожидался объект grant в ответе на POST grants',
      );
    }
    final granteePreview = response['grantee'];
    final merged = Map<String, dynamic>.from(raw);
    if (granteePreview is Map<String, dynamic>) {
      merged['grantee'] = granteePreview;
    }
    return EditGrant.fromJson(merged);
  }

  @override
  Future<EditGrant> revokeGraphPersonGrant({
    required String graphPersonId,
    required String grantId,
  }) async {
    final response = await _requestJson(
      method: 'DELETE',
      path: '/v1/graph-persons/$graphPersonId/grants/$grantId',
    );
    final raw = response['grant'];
    if (raw is! Map<String, dynamic>) {
      throw const FormatException(
        'Ожидался объект grant в ответе на DELETE grant',
      );
    }
    return EditGrant.fromJson(raw);
  }

  @override
  Future<List<EditGrant>> listGraphPersonGrants({
    required String graphPersonId,
  }) async {
    final response = await _requestJson(
      method: 'GET',
      path: '/v1/graph-persons/$graphPersonId/grants',
    );
    final raw = response['grants'];
    if (raw is! List) return const <EditGrant>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(EditGrant.fromJson)
        .toList(growable: false);
  }

  @override
  Future<List<EditGrant>> listMyEditGrants() async {
    final response =
        await _requestJson(method: 'GET', path: '/v1/me/edit-grants');
    final raw = response['grants'];
    if (raw is! List) return const <EditGrant>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(EditGrant.fromJson)
        .toList(growable: false);
  }

  @override
  Future<List<EditGrant>> listMyIssuedGrants() async {
    final response =
        await _requestJson(method: 'GET', path: '/v1/me/issued-grants');
    final raw = response['grants'];
    if (raw is! List) return const <EditGrant>[];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(EditGrant.fromJson)
        .toList(growable: false);
  }

  // ── Phase 4 chunk 1: extended network slice ────────────────────

  @override
  Future<ExtendedNetworkSlice?> getExtendedNetworkSlice({
    required String treeId,
    int maxHops = 4,
    bool includeAnonymous = true,
    List<String>? branchIds,
  }) async {
    // Clamp client-side (defensive — server тоже clamp'ит до
    // 2..4, но избегаем посылать ?maxHops=12 «на удачу»).
    final clamped = maxHops.clamp(2, 4);
    final queryParams = <String, String>{
      'maxHops': clamped.toString(),
      if (!includeAnonymous) 'includeAnonymous': 'false',
      if (branchIds != null && branchIds.isNotEmpty)
        'branchIds': branchIds.join(','),
    };
    final queryString = queryParams.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    final path = queryString.isEmpty
        ? '/v1/trees/$treeId/extended-network'
        : '/v1/trees/$treeId/extended-network?$queryString';
    try {
      final response = await _requestJson(method: 'GET', path: path);
      final sliceRaw = response['slice'];
      if (sliceRaw is! Map<String, dynamic>) return null;
      return ExtendedNetworkSlice.fromJson(sliceRaw);
    } catch (_) {
      // Capability detection: старый сервер без endpoint'а — 404.
      // Любая network/auth ошибка → null чтобы UI graceful disable.
      return null;
    }
  }

  // ── Phase 6 chunk 2: onboarding ──────────────────────────────────
}
