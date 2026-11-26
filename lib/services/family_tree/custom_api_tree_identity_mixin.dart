part of '../custom_api_family_tree_service.dart';

mixin _CustomApiTreeIdentityMixin on _CustomApiFamilyTreeHost {
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
    _invalidateTreeCaches(sourceTreeId);
    _invalidateTreeCaches(targetTreeId);
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
    _invalidateTreeCaches(treeId);
  }

  // ── Phase 4: Find Blood Relation ───────────────────────────────────
  // Calls GET /v1/graph/relation?from=<gid>&to=<gid>&maxDepth=<n>
  // and parses the response into a BloodRelation. Returns
  // BloodRelation.empty when the server reports no path.

  // ── Phase 6.3: «Эта неделя в семье» digest ─────────────────────────

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

  @override
  Future<OnboardingState?> skipOnboarding() async {
    try {
      final response = await _requestJson(
        method: 'POST',
        path: '/v1/me/onboarding-state/skip',
      );
      final stateRaw = response['state'];
      if (stateRaw is! Map<String, dynamic>) return null;
      return OnboardingState.fromJson(stateRaw);
    } catch (_) {
      return null;
    }
  }

  // ── Phase 6 chunk 3: kinship-checks (bilateral «мы родственники?») ──

  @override
  Future<KinshipCheckCreateResult?> createKinshipCheck({
    required String targetUserId,
  }) async {
    try {
      final response = await _requestJson(
        method: 'POST',
        path: '/v1/kinship-checks',
        body: {'targetUserId': targetUserId},
      );
      return KinshipCheckCreateResult.fromJson(response);
    } on CustomApiException catch (e) {
      throw _mapKinshipCheckException(e, endpoint: 'create');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<KinshipCheck>> listReceivedKinshipChecks({
    KinshipCheckStatus? status,
  }) async {
    return _listKinshipChecks(role: 'received', status: status);
  }

  @override
  Future<List<KinshipCheck>> listIssuedKinshipChecks({
    KinshipCheckStatus? status,
  }) async {
    return _listKinshipChecks(role: 'issued', status: status);
  }

  Future<List<KinshipCheck>> _listKinshipChecks({
    required String role,
    KinshipCheckStatus? status,
  }) async {
    try {
      final basePath = '/v1/me/kinship-checks/$role';
      final path = status == null
          ? basePath
          : _buildPathWithQuery(basePath, {'status': status.serverValue});
      final response = await _requestJson(method: 'GET', path: path);
      final rawList = response['checks'];
      if (rawList is! List) return const <KinshipCheck>[];
      return rawList
          .whereType<Map>()
          .map((e) => KinshipCheck.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (_) {
      return const <KinshipCheck>[];
    }
  }

  @override
  Future<KinshipCheck?> respondToKinshipCheck({
    required String checkId,
    required KinshipCheckDecision decision,
  }) async {
    try {
      final response = await _requestJson(
        method: 'POST',
        path: '/v1/kinship-checks/$checkId/respond',
        body: {'decision': decision.serverValue},
      );
      final checkRaw = response['check'];
      if (checkRaw is! Map) return null;
      return KinshipCheck.fromJson(Map<String, dynamic>.from(checkRaw));
    } on CustomApiException catch (e) {
      throw _mapKinshipCheckException(e, endpoint: 'respond');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<KinshipCheck?> revokeKinshipCheck({
    required String checkId,
  }) async {
    try {
      final response = await _requestJson(
        method: 'POST',
        path: '/v1/kinship-checks/$checkId/revoke',
      );
      final checkRaw = response['check'];
      if (checkRaw is! Map) return null;
      return KinshipCheck.fromJson(Map<String, dynamic>.from(checkRaw));
    } on CustomApiException catch (e) {
      throw _mapKinshipCheckException(e, endpoint: 'revoke');
    } catch (_) {
      return null;
    }
  }

  /// Map [CustomApiException.statusCode] к domain-specific
  /// [KinshipCheckError] code. Backend response payloads documented
  /// в backend/src/routes/kinship-checks-routes.js.
  KinshipCheckError _mapKinshipCheckException(
    CustomApiException e, {
    required String endpoint,
  }) {
    final status = e.statusCode;
    String code;
    switch (status) {
      case 400:
        code = 'INVALID_INPUT';
        break;
      case 403:
        // Phase 6.5: revoke endpoint surfaces NOT_INITIATOR (caller —
        // не initiator). Respond endpoint surfaces NOT_FOUND
        // («foreign check» heuristic) для consistency с UI tone.
        code = endpoint == 'revoke' ? 'NOT_INITIATOR' : 'NOT_FOUND';
        break;
      case 404:
        code = endpoint == 'create' ? 'TARGET_NOT_FOUND' : 'NOT_FOUND';
        break;
      case 409:
        code = endpoint == 'create' ? 'SELF_CHECK_FORBIDDEN' : 'NOT_PENDING';
        break;
      case 429:
        code = 'REJECTION_COOLDOWN';
        break;
      default:
        code = 'UNKNOWN';
    }
    return KinshipCheckError(code: code, message: e.message);
  }
}
