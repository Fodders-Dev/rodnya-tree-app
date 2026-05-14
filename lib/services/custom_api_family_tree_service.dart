import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../backend/backend_runtime_config.dart';
import '../backend/interfaces/blood_relation_capable_family_tree_service.dart';
import '../backend/interfaces/branch_digest_capable_family_tree_service.dart';
import '../backend/interfaces/bulk_import_capable_family_tree_service.dart';
import '../backend/interfaces/cross_tree_person_search_capable_family_tree_service.dart';
import '../backend/interfaces/extended_network_capable_family_tree_service.dart';
import '../backend/interfaces/family_tree_service_interface.dart';
import '../backend/interfaces/graph_person_access_capable_family_tree_service.dart';
import '../backend/interfaces/identity_conflicts_capable_family_tree_service.dart';
import '../backend/interfaces/identity_duplicate_capable_family_tree_service.dart';
import '../backend/interfaces/identity_suggestions_capable_family_tree_service.dart';
import '../backend/interfaces/onboarding_capable_family_tree_service.dart';
import '../backend/interfaces/profile_service_interface.dart';
import '../backend/interfaces/tree_graph_capable_family_tree_service.dart';
import '../backend/models/blood_relation.dart';
import '../backend/models/branch_digest.dart';
import '../backend/models/edit_grant.dart';
import '../backend/models/extended_network_slice.dart';
import '../backend/models/identity_field_conflict.dart';
import '../backend/models/identity_suggestion.dart';
import '../backend/models/cross_tree_person_suggestion.dart';
import '../backend/models/include_rules.dart';
import '../backend/models/onboarding_state.dart';
import '../backend/models/visibility_choice.dart';
import '../backend/models/selectable_tree.dart';
import '../backend/models/tree_invitation.dart';
import '../models/family_person.dart';
import '../models/family_relation.dart';
import '../models/family_tree.dart';
import '../models/person_dossier.dart';
import '../models/person_duplicate_suggestion.dart';
import '../models/relation_request.dart';
import '../models/tree_graph_snapshot.dart';
import '../models/tree_change_record.dart';
import '../models/user_profile.dart';
import 'custom_api_auth_service.dart';
import 'local_storage_service.dart';
import 'tree_graph_cache.dart';

class CustomApiFamilyTreeService
    implements
        FamilyTreeServiceInterface,
        TreeGraphCapableFamilyTreeService,
        IdentityDuplicateCapableFamilyTreeService,
        CrossTreePersonSearchCapableFamilyTreeService,
        IdentitySuggestionsCapableFamilyTreeService,
        IdentityConflictsCapableFamilyTreeService,
        BloodRelationCapableFamilyTreeService,
        BranchDigestCapableFamilyTreeService,
        BulkImportCapableFamilyTreeService,
        GraphPersonAccessCapableFamilyTreeService,
        ExtendedNetworkCapableFamilyTreeService,
        OnboardingCapableFamilyTreeService {
  CustomApiFamilyTreeService({
    required CustomApiAuthService authService,
    required BackendRuntimeConfig runtimeConfig,
    http.Client? httpClient,
    LocalStorageService? localStorageService,
    ProfileServiceInterface? profileService,
    TreeGraphCache? treeGraphCache,
  })  : _authService = authService,
        _runtimeConfig = runtimeConfig,
        _httpClient = httpClient ?? http.Client(),
        _localStorageService = localStorageService,
        _profileService = profileService,
        _treeGraphCache = treeGraphCache;

  final CustomApiAuthService _authService;
  final BackendRuntimeConfig _runtimeConfig;
  final http.Client _httpClient;
  final LocalStorageService? _localStorageService;
  final ProfileServiceInterface? _profileService;
  final TreeGraphCache? _treeGraphCache;
  final Map<String, String> _personTreeIds = <String, String>{};
  final Map<String, TreeGraphSnapshot> _graphSnapshotCache =
      <String, TreeGraphSnapshot>{};
  late final StreamController<List<TreeInvitation>>
      _pendingInvitationsController =
      StreamController<List<TreeInvitation>>.broadcast(
    onListen: _handlePendingInvitationsListen,
    onCancel: _handlePendingInvitationsCancel,
  );
  Timer? _pendingInvitationsPollingTimer;
  bool _pendingInvitationsPollingStarted = false;
  int _pendingInvitationsListenerCount = 0;

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
  Future<List<FamilyPerson>> getRelatives(String treeId) async {
    final response = await _requestJson(
      method: 'GET',
      path: '/v1/trees/$treeId/persons',
    );

    final relatives = _personListFromResponse(response);
    for (final person in relatives) {
      _personTreeIds[person.id] = treeId;
    }
    await _cachePersons(relatives);
    return relatives;
  }

  /// Phase 0 cross-tree picker: surface relatives the user already
  /// entered on any of their other trees so they don't have to
  /// re-key the same human when starting a new tree. The Flutter
  /// add-relative screen calls this from a debounced text-field as
  /// the user types — pass [excludeTreeId] to keep the suggestions
  /// from including persons already on the tree being edited.
  ///
  /// On the picker, a tapped suggestion's [CrossTreePersonSuggestion.id]
  /// becomes the `sourcePersonId` on the create-person POST — the
  /// backend then shares an identityId between source and target so
  /// future Phase 1 work can propagate edits across trees.
  @override
  Future<List<CrossTreePersonSuggestion>> searchPersonsAcrossOwnTrees({
    required String query,
    String? excludeTreeId,
    int limit = 20,
  }) async {
    final params = <String, String>{};
    final trimmedQuery = query.trim();
    if (trimmedQuery.isNotEmpty) {
      params['q'] = trimmedQuery;
    }
    if (excludeTreeId != null && excludeTreeId.isNotEmpty) {
      params['excludeTreeId'] = excludeTreeId;
    }
    if (limit > 0) {
      params['limit'] = limit.toString();
    }

    final path = params.isEmpty
        ? '/v1/persons/search'
        : _buildPathWithQuery('/v1/persons/search', params);

    final response = await _requestJson(
      method: 'GET',
      path: path,
    );

    final raw = response['persons'];
    if (raw is! List) {
      return const <CrossTreePersonSuggestion>[];
    }
    return raw
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .map(CrossTreePersonSuggestion.fromJson)
        .toList(growable: false);
  }

  // ── Phase 1.2 voltage-indicator matcher ─────────────────────────────
  // Cross-tree suggestion fetch / link / dismiss. Service-level
  // implementation; UI surfaces are wired via the canvas's
  // IdentitySuggestionsCapableFamilyTreeService capability gate.

  @override
  Future<List<IdentitySuggestion>> getIdentitySuggestionsForPerson({
    required String treeId,
    required String personId,
    int limit = 10,
  }) async {
    final params = <String, String>{};
    if (limit > 0) params['limit'] = limit.toString();
    final path = params.isEmpty
        ? '/v1/trees/$treeId/persons/$personId/identity-suggestions'
        : _buildPathWithQuery(
            '/v1/trees/$treeId/persons/$personId/identity-suggestions',
            params,
          );
    final response = await _requestJson(method: 'GET', path: path);
    final raw = response['suggestions'];
    if (raw is! List) return const <IdentitySuggestion>[];
    return raw
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .map(IdentitySuggestion.fromJson)
        .toList(growable: false);
  }

  @override
  Future<void> linkIdentity({
    required String sourceTreeId,
    required String sourcePersonId,
    required String targetTreeId,
    required String targetPersonId,
  }) async {
    await _requestJson(
      method: 'POST',
      path: '/v1/trees/$sourceTreeId/persons/$sourcePersonId/link-identity',
      body: <String, dynamic>{
        'targetTreeId': targetTreeId,
        'targetPersonId': targetPersonId,
      },
    );
    // Both trees may have just had Phase 1.1 propagation effects
    // applied at the backend (the link itself doesn't propagate,
    // but the next edit on either side now will). Invalidate
    // graph snapshots for both so the consumer refetches.
    _graphSnapshotCache.remove(sourceTreeId);
    _graphSnapshotCache.remove(targetTreeId);
  }

  @override
  Future<void> dismissIdentitySuggestion({
    required String sourceTreeId,
    required String sourcePersonId,
    required String targetPersonId,
  }) async {
    await _requestJson(
      method: 'POST',
      path:
          '/v1/trees/$sourceTreeId/persons/$sourcePersonId/dismiss-suggestion',
      body: <String, dynamic>{'targetPersonId': targetPersonId},
    );
  }

  // ── Phase 1.3: identity-field conflicts ─────────────────────────────
  // Tree-level fetch (one HTTP call covers every visible card on
  // the canvas) and per-conflict resolve. Resolve invalidates the
  // tree's graph snapshot cache because `overwrite` changes the
  // target person's canonical fields.

  @override
  Future<List<IdentityFieldConflict>> getIdentityConflictsForTree({
    required String treeId,
  }) async {
    final response = await _requestJson(
      method: 'GET',
      path: '/v1/trees/$treeId/conflicts',
    );
    final raw = response['conflicts'];
    if (raw is! List) return const <IdentityFieldConflict>[];
    return raw
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .map(IdentityFieldConflict.fromJson)
        .toList(growable: false);
  }

  @override
  Future<void> resolveIdentityConflict({
    required String treeId,
    required String conflictId,
    required String choice,
  }) async {
    await _requestJson(
      method: 'POST',
      path: '/v1/trees/$treeId/conflicts/$conflictId/resolve',
      body: <String, dynamic>{'choice': choice},
    );
    // overwrite mutates the target person — drop the cached graph
    // snapshot so the next read shows the new canonical value.
    // keep is technically a no-op for graph data, but the badge
    // count still changes; cheap to invalidate either way.
    _graphSnapshotCache.remove(treeId);
  }

  // ── Phase 4: Find Blood Relation ───────────────────────────────────
  // Calls GET /v1/graph/relation?from=<gid>&to=<gid>&maxDepth=<n>
  // and parses the response into a BloodRelation. Returns
  // BloodRelation.empty when the server reports no path.

  // ── Phase 6.3: «Эта неделя в семье» digest ─────────────────────────

  @override
  Future<BranchDigest?> getBranchDigest({
    required String treeId,
    int days = 7,
  }) async {
    final params = <String, String>{
      if (days > 0 && days != 7) 'days': days.toString(),
    };
    final path = params.isEmpty
        ? '/v1/trees/$treeId/digest'
        : _buildPathWithQuery('/v1/trees/$treeId/digest', params);
    try {
      final response = await _requestJson(method: 'GET', path: path);
      final raw = response['digest'];
      if (raw is! Map) return null;
      return BranchDigest.fromJson(Map<String, dynamic>.from(raw));
    } on CustomApiException catch (error) {
      // 404 → branch unknown to this caller. Surface as null so
      // the home widget gracefully hides itself; treat anything
      // else as a real failure the caller can show in UI.
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<BulkImportResult> bulkImportPersonsToTree({
    required String sourceTreeId,
    required String targetTreeId,
    required List<String> sourcePersonIds,
  }) async {
    final response = await _requestJson(
      method: 'POST',
      path: '/v1/trees/$targetTreeId/persons/import',
      body: <String, dynamic>{
        'sourceTreeId': sourceTreeId,
        'sourcePersonIds': sourcePersonIds,
      },
    );
    final rawPersons = response['persons'];
    final persons = rawPersons is List
        ? rawPersons
            .whereType<Map>()
            .map(
              (raw) => _personFromJson(
                Map<String, dynamic>.from(raw),
                fallbackTreeId: targetTreeId,
              ),
            )
            .toList(growable: false)
        : const <FamilyPerson>[];
    final rawRelations = response['relations'];
    final bridgedRelationCount = rawRelations is List ? rawRelations.length : 0;
    return BulkImportResult(
      persons: persons,
      bridgedRelationCount: bridgedRelationCount,
    );
  }

  @override
  Future<BloodRelation> findBloodRelation({
    required String fromGraphPersonId,
    required String toGraphPersonId,
    int maxDepth = 10,
  }) async {
    final params = <String, String>{
      'from': fromGraphPersonId,
      'to': toGraphPersonId,
      if (maxDepth > 0 && maxDepth != 10) 'maxDepth': maxDepth.toString(),
    };
    final response = await _requestJson(
      method: 'GET',
      path: _buildPathWithQuery('/v1/graph/relation', params),
    );
    if (response['found'] != true) return BloodRelation.empty;
    return BloodRelation.fromJson(response);
  }

  @override
  Future<List<PersonDuplicateSuggestion>> getDuplicateSuggestions(
    String treeId,
  ) async {
    final response = await _requestJson(
      method: 'GET',
      path: '/v1/trees/$treeId/duplicates',
    );
    final rawSuggestions = response['suggestions'];
    if (rawSuggestions is! List<dynamic>) {
      return const <PersonDuplicateSuggestion>[];
    }

    return rawSuggestions
        .whereType<Map<String, dynamic>>()
        .map(PersonDuplicateSuggestion.fromJson)
        .where((suggestion) =>
            suggestion.id.isNotEmpty &&
            suggestion.personA.id.isNotEmpty &&
            suggestion.personB.id.isNotEmpty)
        .toList(growable: false);
  }

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
            personParser:
                (json) => _personFromJson(json, fallbackTreeId: treeId),
            relationParser:
                (json) => _relationFromJson(json, fallbackTreeId: treeId),
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
        relationParser:
            (json) => _relationFromJson(json, fallbackTreeId: treeId),
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
    _graphSnapshotCache.remove(treeId);
  }

  @override
  Future<void> disconnectRelation({
    required String treeId,
    required String relationId,
  }) async {
    await _requestDelete(path: '/v1/trees/$treeId/relations/$relationId');
    _graphSnapshotCache.remove(treeId);
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
    _graphSnapshotCache.remove(treeId);
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
    _graphSnapshotCache.remove(treeId);
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
  Future<String> addRelative(
      String treeId, Map<String, dynamic> personData) async {
    final response = await _requestJson(
      method: 'POST',
      path: '/v1/trees/$treeId/persons',
      body: _normalizePersonPayload(personData),
    );

    final person = _personFromResponse(response, fallbackTreeId: treeId);
    _personTreeIds[person.id] = treeId;
    _graphSnapshotCache.remove(treeId);
    await _cachePerson(person);
    return person.id;
  }

  @override
  Future<void> updateRelative(
      String personId, Map<String, dynamic> personData) async {
    final treeId = await _resolveTreeIdForPerson(personId);
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
    _graphSnapshotCache.remove(treeId);
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
              _graphSnapshotCache.remove(affectedTreeId);
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
        if (customRelationLabel1to2 != null &&
            customRelationLabel1to2.trim().isNotEmpty)
          'customRelationLabel1to2': customRelationLabel1to2.trim(),
        if (customRelationLabel2to1 != null &&
            customRelationLabel2to1.trim().isNotEmpty)
          'customRelationLabel2to1': customRelationLabel2to1.trim(),
      },
    );

    final relation = _relationFromResponse(response, fallbackTreeId: treeId);
    _graphSnapshotCache.remove(treeId);
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
  Stream<List<TreeInvitation>> getPendingTreeInvitations() {
    return _pendingInvitationsController.stream;
  }

  @override
  Future<List<RelationRequest>> getRelationRequests(
      {required String treeId}) async {
    final response = await _requestJson(
      method: 'GET',
      path: '/v1/trees/$treeId/relation-requests',
    );

    return _relationRequestListFromResponse(response);
  }

  @override
  Future<List<RelationRequest>> getPendingRelationRequests(
      {String? treeId}) async {
    final response = await _requestJson(
      method: 'GET',
      path: _buildPathWithQuery(
        '/v1/relation-requests/pending',
        {
          if (treeId != null && treeId.isNotEmpty) 'treeId': treeId,
        },
      ),
    );

    return _relationRequestListFromResponse(response);
  }

  @override
  Future<void> respondToTreeInvitation(String invitationId, bool accept) async {
    await _requestJson(
      method: 'POST',
      path: '/v1/tree-invitations/$invitationId/respond',
      body: {
        'accept': accept,
      },
    );
  }

  @override
  Future<void> respondToRelationRequest({
    required String requestId,
    required RequestStatus response,
  }) async {
    await _requestJson(
      method: 'POST',
      path: '/v1/relation-requests/$requestId/respond',
      body: {
        'response': RelationRequest.requestStatusToString(response),
      },
    );
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
    _graphSnapshotCache.remove(treeId);
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
    _graphSnapshotCache.remove(treeId);
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
    _graphSnapshotCache.remove(treeId);
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
    _graphSnapshotCache.remove(treeId);
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
    _graphSnapshotCache.remove(treeId);
    _invalidateCachesForPropagatedTrees(response);
    await _cachePerson(updatedPerson);
    return updatedPerson;
  }

  // Phase 1.1 helper: when the backend reports `propagatedTo` /
  // `identityPropagation.affected` on a write response, drop the
  // graph-snapshot cache for each touched tree so the next read
  // fetches fresh data. Backwards-compatible: silently no-ops on
  // older response shapes that don't carry the field.
  void _invalidateCachesForPropagatedTrees(Map<String, dynamic> response) {
    // New shape (media routes): top-level `propagatedTo: [...]`.
    final propagated = response['propagatedTo'];
    if (propagated is List) {
      for (final entry in propagated) {
        if (entry is Map) {
          final treeId = entry['treeId']?.toString();
          if (treeId != null && treeId.isNotEmpty) {
            _graphSnapshotCache.remove(treeId);
          }
        }
      }
    }
    // Pre-existing shape (PATCH /persons/:id): nested under
    // `identityPropagation.affected`. Same semantics, same
    // invalidation; we accept both for forward/back-compat.
    final propagation = response['identityPropagation'];
    if (propagation is Map<String, dynamic>) {
      final affected = propagation['affected'];
      if (affected is List) {
        for (final entry in affected) {
          if (entry is Map) {
            final treeId = entry['treeId']?.toString();
            if (treeId != null && treeId.isNotEmpty) {
              _graphSnapshotCache.remove(treeId);
            }
          }
        }
      }
    }
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
  Future<bool> hasDirectRelation({
    required String treeId,
    required String person1Id,
    required String person2Id,
  }) async {
    return await getRelationBetween(treeId, person1Id, person2Id) !=
        RelationType.other;
  }

  @override
  Future<bool> hasPendingRelationRequest({
    required String treeId,
    required String senderId,
    required String recipientId,
  }) async {
    final response = await _requestJson(
      method: 'GET',
      path: _buildPathWithQuery(
        '/v1/trees/$treeId/relation-requests',
        {
          'senderId': senderId,
          'recipientId': recipientId,
          'status': 'pending',
        },
      ),
    );

    return _relationRequestListFromResponse(response).isNotEmpty;
  }

  @override
  Future<void> sendRelationRequest({
    required String treeId,
    required String recipientId,
    required RelationType relationType,
    String? message,
  }) async {
    await _requestJson(
      method: 'POST',
      path: '/v1/trees/$treeId/relation-requests',
      body: {
        'recipientId': recipientId,
        'senderToRecipient': FamilyRelation.relationTypeToString(relationType),
        'relationType': FamilyRelation.relationTypeToString(relationType),
        'message': message,
      },
    );
  }

  @override
  Future<void> sendTreeInvitation({
    required String treeId,
    String? recipientUserId,
    String? recipientEmail,
    String? relationToTree,
  }) async {
    final trimmedUserId = recipientUserId?.trim() ?? '';
    final trimmedEmail = recipientEmail?.trim() ?? '';
    if (trimmedUserId.isEmpty && trimmedEmail.isEmpty) {
      throw const CustomApiException(
        'Нужно выбрать пользователя Родни для приглашения в дерево',
      );
    }

    await _requestJson(
      method: 'POST',
      path: '/v1/trees/$treeId/invitations',
      body: {
        if (trimmedUserId.isNotEmpty) 'recipientUserId': trimmedUserId,
        if (trimmedEmail.isNotEmpty) 'recipientEmail': trimmedEmail,
        if (relationToTree != null && relationToTree.trim().isNotEmpty)
          'relationToTree': relationToTree.trim(),
      },
    );
  }

  @override
  Future<void> sendOfflineRelationRequestByEmail({
    required String treeId,
    required String email,
    required String offlineRelativeId,
    required RelationType relationType,
  }) async {
    final searchResponse = await _requestJson(
      method: 'GET',
      path: _buildPathWithQuery(
        '/v1/users/search/by-field',
        {
          'field': 'email',
          'value': email.trim(),
          'limit': '1',
        },
      ),
    );

    final users = searchResponse['users'];
    if (users is! List<dynamic> || users.isEmpty) {
      throw const CustomApiException('Пользователь с таким email не найден');
    }

    final recipientJson = users.first;
    if (recipientJson is! Map<String, dynamic>) {
      throw const CustomApiException(
        'Backend вернул некорректный профиль пользователя',
      );
    }

    final recipientId = recipientJson['id']?.toString() ?? '';
    if (recipientId.isEmpty) {
      throw const CustomApiException(
        'Backend не вернул идентификатор получателя приглашения',
      );
    }

    await _requestJson(
      method: 'POST',
      path: '/v1/trees/$treeId/relation-requests',
      body: {
        'recipientId': recipientId,
        'targetPersonId': offlineRelativeId,
        'offlineRelativeId': offlineRelativeId,
        'senderToRecipient': FamilyRelation.relationTypeToString(relationType),
        'relationType': FamilyRelation.relationTypeToString(relationType),
      },
    );
  }

  Future<Map<String, dynamic>> _requestJson({
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    final uri = _buildUri(path);
    final normalizedBody = body == null ? null : _normalizePersonPayload(body);
    late http.Response response;

    switch (method) {
      case 'GET':
        response = await _httpClient.get(uri, headers: _headers());
        break;
      case 'POST':
        response = await _httpClient.post(
          uri,
          headers: _headers(),
          body: jsonEncode(normalizedBody ?? const <String, dynamic>{}),
        );
        break;
      case 'PATCH':
        response = await _httpClient.patch(
          uri,
          headers: _headers(),
          body: jsonEncode(normalizedBody ?? const <String, dynamic>{}),
        );
        break;
      case 'DELETE':
        response = await _httpClient.delete(
          uri,
          headers: _headers(),
          body: normalizedBody == null ? null : jsonEncode(normalizedBody),
        );
        break;
      default:
        throw CustomApiException('Неподдерживаемый HTTP-метод: $method');
    }

    if (response.body.isEmpty) {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return const <String, dynamic>{};
      }
      throw CustomApiException(
        'Пустой ответ от backend',
        statusCode: response.statusCode,
      );
    }

    final dynamic decoded = jsonDecode(response.body);
    final payload = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{'data': decoded};

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return payload;
    }

    throw CustomApiException(
      payload['message']?.toString() ??
          payload['error']?.toString() ??
          'Ошибка backend (${response.statusCode})',
      statusCode: response.statusCode,
    );
  }

  Future<void> _requestDelete({required String path}) async {
    final response = await _httpClient.delete(
      _buildUri(path),
      headers: _headers(),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }

    if (response.body.isNotEmpty) {
      final dynamic decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        throw CustomApiException(
          decoded['message']?.toString() ??
              'Ошибка backend (${response.statusCode})',
          statusCode: response.statusCode,
        );
      }
    }

    throw CustomApiException(
      'Ошибка backend (${response.statusCode})',
      statusCode: response.statusCode,
    );
  }

  Uri _buildUri(String path) {
    final normalizedBase = _runtimeConfig.apiBaseUrl.replaceAll(
      RegExp(r'/$'),
      '',
    );
    return Uri.parse('$normalizedBase$path');
  }

  String _buildPathWithQuery(
    String path,
    Map<String, String> queryParameters,
  ) {
    final uri = Uri.parse(path);
    return uri.replace(queryParameters: queryParameters).toString();
  }

  Map<String, String> _headers() {
    final token = _authService.accessToken;
    if (token == null || token.isEmpty) {
      throw const CustomApiException('Нет активной customApi session');
    }

    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

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
      birthPlace: json['birthPlace']?.toString(),
      deathDate: deathDate,
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
    if (normalizedLabel.contains('отчим') ||
        normalizedLabel.contains('мачех')) {
      return RelationType.stepparent;
    }
    if (normalizedLabel.contains('пасын') ||
        normalizedLabel.contains('падчер')) {
      return RelationType.stepchild;
    }
    if (normalizedLabel.contains('супруг') ||
        normalizedLabel == 'муж' ||
        normalizedLabel == 'жена') {
      return RelationType.spouse;
    }
    if (normalizedLabel.contains('партнер')) {
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

  Future<List<TreeInvitation>> _loadPendingTreeInvitations() async {
    final response = await _requestJson(
      method: 'GET',
      path: '/v1/tree-invitations/pending',
    );

    final rawInvitations = response['invitations'];
    if (rawInvitations is! List<dynamic>) {
      return const <TreeInvitation>[];
    }

    return rawInvitations
        .whereType<Map<String, dynamic>>()
        .map(_treeInvitationFromJson)
        .where((invitation) => invitation.invitationId.isNotEmpty)
        .toList();
  }

  void _startPendingInvitationsPolling() {
    if (_pendingInvitationsPollingStarted ||
        _pendingInvitationsController.isClosed) {
      return;
    }

    _pendingInvitationsPollingStarted = true;
    _pendingInvitationsPollingTimer?.cancel();
    unawaited(_refreshPendingInvitations());
    _pendingInvitationsPollingTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_refreshPendingInvitations()),
    );
  }

  void _handlePendingInvitationsListen() {
    _pendingInvitationsListenerCount++;
    if (_pendingInvitationsListenerCount == 1) {
      _startPendingInvitationsPolling();
    }
  }

  Future<void> _handlePendingInvitationsCancel() async {
    _pendingInvitationsListenerCount--;
    if (_pendingInvitationsListenerCount > 0) {
      return;
    }

    _pendingInvitationsListenerCount = 0;
    _pendingInvitationsPollingStarted = false;
    _pendingInvitationsPollingTimer?.cancel();
    _pendingInvitationsPollingTimer = null;
  }

  Future<void> _refreshPendingInvitations() async {
    if (_pendingInvitationsController.isClosed) {
      return;
    }

    try {
      _pendingInvitationsController.add(await _loadPendingTreeInvitations());
    } catch (error, stackTrace) {
      _pendingInvitationsController.addError(error, stackTrace);
    }
  }

  TreeInvitation _treeInvitationFromJson(Map<String, dynamic> json) {
    final treeJson = json['tree'];
    final tree = treeJson is Map<String, dynamic>
        ? _treeFromJson(treeJson)
        : FamilyTree(
            id: json['treeId']?.toString() ?? '',
            name: 'Семейное дерево',
            creatorId: '',
            description: '',
            memberIds: const <String>[],
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            members: const <String>[],
            isPrivate: true,
            publicSlug: null,
            isCertified: false,
            certificationNote: null,
          );

    return TreeInvitation(
      invitationId:
          json['invitationId']?.toString() ?? json['id']?.toString() ?? '',
      tree: tree,
      invitedBy: json['invitedBy']?.toString() ?? json['addedBy']?.toString(),
    );
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

  Future<void> _cacheTree(FamilyTree tree) async {
    final localStorageService = _localStorageService;
    if (localStorageService != null) {
      await localStorageService.saveTree(tree);
    }
  }

  Future<void> _cacheTrees(List<FamilyTree> trees) async {
    final localStorageService = _localStorageService;
    if (localStorageService != null) {
      await localStorageService.saveTrees(trees);
    }
  }

  Future<void> _cachePerson(FamilyPerson person) async {
    final localStorageService = _localStorageService;
    if (localStorageService != null) {
      await localStorageService.savePerson(person);
    }
  }

  Future<void> _cachePersons(List<FamilyPerson> persons) async {
    final localStorageService = _localStorageService;
    if (localStorageService != null) {
      await localStorageService.savePersons(persons);
    }
  }

  Future<void> _cacheRelation(FamilyRelation relation) async {
    final localStorageService = _localStorageService;
    if (localStorageService != null) {
      await localStorageService.saveRelation(relation);
    }
  }

  Future<void> _cacheRelations(List<FamilyRelation> relations) async {
    final localStorageService = _localStorageService;
    if (localStorageService != null) {
      await localStorageService.saveRelations(relations);
    }
  }

  Future<String?> _resolveTreeIdForPerson(String personId) async {
    if (_personTreeIds.containsKey(personId)) {
      return _personTreeIds[personId];
    }

    final localStorageService = _localStorageService;
    final cachedPerson = localStorageService == null
        ? null
        : await localStorageService.getPerson(personId);
    if (cachedPerson != null) {
      _personTreeIds[personId] = cachedPerson.treeId;
      return cachedPerson.treeId;
    }

    final trees = await getUserTrees();
    for (final tree in trees) {
      final persons = await getRelatives(tree.id);
      final matches = persons.where((person) => person.id == personId);
      if (matches.isNotEmpty) {
        _personTreeIds[personId] = tree.id;
        return tree.id;
      }
    }

    return null;
  }

  Future<String?> _resolvePersonIdForTree(
      String treeId, String rawPersonId) async {
    if (rawPersonId.isEmpty) {
      return null;
    }

    final localStorageService = _localStorageService;
    final cachedPerson = localStorageService == null
        ? null
        : await localStorageService.getPerson(rawPersonId);
    if (cachedPerson != null && cachedPerson.treeId == treeId) {
      _personTreeIds[cachedPerson.id] = treeId;
      return cachedPerson.id;
    }

    final persons = await getRelatives(treeId);
    for (final person in persons) {
      if (person.id == rawPersonId) {
        return person.id;
      }
      if (person.userId == rawPersonId) {
        return person.id;
      }
    }

    return null;
  }

  Future<UserProfile?> _loadCurrentUserProfile() async {
    final profileService = _profileService;
    if (profileService == null) {
      return null;
    }

    try {
      return await profileService.getCurrentUserProfile();
    } catch (_) {
      return null;
    }
  }

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

  @override
  Future<OnboardingSeedResult?> seedOnboarding({
    required OnboardingSeedPayload payload,
  }) async {
    try {
      final response = await _requestJson(
        method: 'POST',
        path: '/v1/onboarding/seed',
        body: payload.toJson(),
      );
      return OnboardingSeedResult.fromJson(response);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<OnboardingState?> getOnboardingState() async {
    try {
      final response = await _requestJson(
        method: 'GET',
        path: '/v1/me/onboarding-state',
      );
      final stateRaw = response['state'];
      if (stateRaw is! Map<String, dynamic>) return null;
      return OnboardingState.fromJson(stateRaw);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<OnboardingState?> updateOnboardingState({
    required OnboardingStep currentStep,
  }) async {
    try {
      final response = await _requestJson(
        method: 'PATCH',
        path: '/v1/me/onboarding-state',
        body: {'currentStep': currentStep.serverValue},
      );
      final stateRaw = response['state'];
      if (stateRaw is! Map<String, dynamic>) return null;
      return OnboardingState.fromJson(stateRaw);
    } catch (_) {
      return null;
    }
  }
}
