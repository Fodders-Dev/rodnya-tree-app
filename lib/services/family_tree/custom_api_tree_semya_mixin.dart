part of '../custom_api_family_tree_service.dart';

mixin _CustomApiTreeSemyaMixin on _CustomApiFamilyTreeHost {
  // ---------- Phase B Ship FE1: семя read endpoints ----------

  @override
  Future<List<Semya>> listMySemya() async {
    try {
      final response = await _requestJson(
        method: 'GET',
        path: '/v1/me/semya',
      );
      final rawList = response['semyi'];
      if (rawList is! List) return const <Semya>[];
      return rawList
          .whereType<Map>()
          .map((e) => Semya.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } catch (_) {
      // Graceful degradation — UI shows empty state.
      return const <Semya>[];
    }
  }

  @override
  Future<SemyaDetails?> findSemyaById(String semyaId) async {
    final trimmed = semyaId.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      final response = await _requestJson(
        method: 'GET',
        path: '/v1/semya/$trimmed',
      );
      return SemyaDetails.fromJson(response);
    } on CustomApiException catch (e) {
      throw _mapSemyaException(e, endpoint: 'detail');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<SemyaMembership>> listMembershipsForSemya(String semyaId) async {
    final trimmed = semyaId.trim();
    if (trimmed.isEmpty) return const <SemyaMembership>[];
    try {
      final response = await _requestJson(
        method: 'GET',
        path: '/v1/semya/$trimmed/memberships',
      );
      final raw = response['memberships'];
      if (raw is! List) return const <SemyaMembership>[];
      return raw
          .whereType<Map>()
          .map((e) => SemyaMembership.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } on CustomApiException catch (e) {
      // 403/404 → return empty list (UI shows «не доступно»); other
      // codes throw mapped SemyaError so controller surface их.
      final status = e.statusCode;
      if (status == 403 || status == 404) return const <SemyaMembership>[];
      throw _mapSemyaException(e, endpoint: 'memberships');
    } catch (_) {
      return const <SemyaMembership>[];
    }
  }

  @override
  Future<SemyaInvitation> createInvitation({
    required String semyaId,
    required SemyaRole role,
    String? recipientEmail,
    String? recipientPhone,
    String? recipientUserId,
  }) async {
    final body = <String, dynamic>{'role': role.serverValue};
    final email = recipientEmail?.trim();
    final phone = recipientPhone?.trim();
    final userId = recipientUserId?.trim();
    if (email != null && email.isNotEmpty) body['recipientEmail'] = email;
    if (phone != null && phone.isNotEmpty) body['recipientPhone'] = phone;
    if (userId != null && userId.isNotEmpty) {
      body['recipientUserId'] = userId;
    }
    try {
      final response = await _requestJson(
        method: 'POST',
        path: '/v1/semya/${semyaId.trim()}/invitation',
        body: body,
      );
      final invRaw = response['invitation'];
      if (invRaw is! Map<String, dynamic>) {
        throw const CustomApiException(
          'invitation backend не вернул invitation объект',
        );
      }
      return SemyaInvitation.fromJson(invRaw);
    } on CustomApiException catch (e) {
      throw _mapSemyaException(e, endpoint: 'invitation_create');
    }
  }

  @override
  Future<List<SemyaInvitation>> listInvitationsForSemya(String semyaId) async {
    final trimmed = semyaId.trim();
    if (trimmed.isEmpty) return const <SemyaInvitation>[];
    try {
      final response = await _requestJson(
        method: 'GET',
        path: '/v1/semya/$trimmed/invitations',
      );
      final raw = response['invitations'];
      if (raw is! List) return const <SemyaInvitation>[];
      return raw
          .whereType<Map>()
          .map((e) => SemyaInvitation.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } on CustomApiException catch (e) {
      final status = e.statusCode;
      if (status == 403 || status == 404) return const <SemyaInvitation>[];
      throw _mapSemyaException(e, endpoint: 'invitations');
    } catch (_) {
      return const <SemyaInvitation>[];
    }
  }

  @override
  Future<SemyaInvitation> revokeInvitation({
    required String semyaId,
    required String invitationId,
  }) async {
    try {
      final response = await _requestJson(
        method: 'DELETE',
        path: '/v1/semya/${semyaId.trim()}/invitation/${invitationId.trim()}',
      );
      final invRaw = response['invitation'];
      if (invRaw is! Map<String, dynamic>) {
        throw const CustomApiException(
          'invitation revoke не вернул invitation объект',
        );
      }
      return SemyaInvitation.fromJson(invRaw);
    } on CustomApiException catch (e) {
      throw _mapSemyaException(e, endpoint: 'invitation_revoke');
    }
  }

  @override
  Future<SemyaInvitationAcceptResult> acceptInvitation(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      throw const SemyaError(
        code: 'INVALID_TOKEN',
        message: 'Некорректный токен',
      );
    }
    try {
      final response = await _requestJson(
        method: 'POST',
        path: '/v1/invitation/$trimmed/accept',
      );
      return SemyaInvitationAcceptResult.fromJson(response);
    } on CustomApiException catch (e) {
      throw _mapSemyaException(e, endpoint: 'invitation_accept');
    }
  }

  @override
  Future<List<SemyaInvitation>> listPendingInvitations() async {
    try {
      final response = await _requestJson(
        method: 'GET',
        path: '/v1/me/pending-invitations',
      );
      final raw = response['invitations'];
      if (raw is! List) return const <SemyaInvitation>[];
      return raw
          .whereType<Map>()
          .map((e) => SemyaInvitation.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } on CustomApiException {
      // Graceful degradation — onboarding wizard fallback к default
      // «create» path when service unreachable либо backend incapable.
      return const <SemyaInvitation>[];
    }
  }

  @override
  Future<SemyaPullPersonResult> pullPersonToSemya({
    required String targetSemyaId,
    required String sourceSemyaId,
    required String sourcePersonId,
  }) async {
    final target = targetSemyaId.trim();
    final source = sourceSemyaId.trim();
    final personId = sourcePersonId.trim();
    if (target.isEmpty || source.isEmpty || personId.isEmpty) {
      throw const SemyaError(
        code: 'INVALID_INPUT',
        message: 'Некорректные параметры',
      );
    }
    if (target == source) {
      throw const SemyaError(
        code: 'INVALID_INPUT',
        message: 'Источник и цель не могут быть одной семьёй',
      );
    }
    try {
      final response = await _requestJson(
        method: 'POST',
        path: '/v1/semya/$target/pull-person',
        body: <String, dynamic>{
          'sourceSemyaId': source,
          'sourcePersonId': personId,
        },
      );
      _invalidateAllTreeCaches();
      return SemyaPullPersonResult.fromJson(response);
    } on CustomApiException catch (e) {
      throw _mapSemyaException(e, endpoint: 'pull_person');
    }
  }

  @override
  Future<SemyaBrowseToken> createBrowseToken({
    required String semyaId,
    int? expiresInDays,
  }) async {
    final trimmed = semyaId.trim();
    if (trimmed.isEmpty) {
      throw const SemyaError(
        code: 'INVALID_INPUT',
        message: 'Некорректный идентификатор семьи',
      );
    }
    final body = <String, dynamic>{};
    if (expiresInDays != null) body['expiresInDays'] = expiresInDays;
    try {
      final response = await _requestJson(
        method: 'POST',
        path: '/v1/semya/$trimmed/browse-token',
        body: body,
      );
      final tokenRaw = response['token'];
      if (tokenRaw is! Map<String, dynamic>) {
        throw const CustomApiException(
          'browse-token backend не вернул token объект',
        );
      }
      return SemyaBrowseToken.fromJson(tokenRaw);
    } on CustomApiException catch (e) {
      throw _mapSemyaException(e, endpoint: 'browse_token_create');
    }
  }

  @override
  Future<BrowsedSemyaTree> fetchBrowseTree(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      throw const SemyaError(
        code: 'INVALID_TOKEN',
        message: 'Некорректный токен',
      );
    }
    // /v1/browse/:token — no auth required (token is capability).
    // Bypass _requestJson (which always sends Authorization header)
    // и hit endpoint directly via _httpClient.get + manual response
    // mapping. Backend treats Authorization-less GET as anonymous
    // capability resolve.
    try {
      final uri = _buildUri('/v1/browse/$trimmed');
      final response = await _httpClient.get(
        uri,
        headers: <String, String>{'Accept': 'application/json'},
      );
      if (response.statusCode == 410) {
        // 410 Gone: revoked либо expired. Backend message includes
        // «отозвана» либо «истёк». Map к specific SemyaError codes
        // так UI может render targeted copy.
        final body = response.body.isEmpty
            ? const <String, dynamic>{}
            : (jsonDecode(response.body) as Map<String, dynamic>);
        final msg = body['message']?.toString() ?? 'Ссылка недействительна';
        final isRevoked = msg.toLowerCase().contains('отозва');
        throw SemyaError(
          code: isRevoked ? 'TOKEN_REVOKED' : 'TOKEN_EXPIRED',
          message: msg,
        );
      }
      if (response.statusCode == 404) {
        final body = response.body.isEmpty
            ? const <String, dynamic>{}
            : (jsonDecode(response.body) as Map<String, dynamic>);
        throw SemyaError(
          code: 'TOKEN_NOT_FOUND',
          message: body['message']?.toString() ?? 'Ссылка не найдена',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = response.body.isEmpty
            ? const <String, dynamic>{}
            : (jsonDecode(response.body) as Map<String, dynamic>);
        throw SemyaError(
          code: 'UNKNOWN',
          message: body['message']?.toString() ??
              'Не удалось загрузить дерево (${response.statusCode})',
        );
      }
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        throw const SemyaError(
          code: 'UNKNOWN',
          message: 'Сервер вернул некорректный ответ',
        );
      }
      return BrowsedSemyaTree.fromJson(body);
    } on SemyaError {
      rethrow;
    } catch (error) {
      throw SemyaError(
        code: 'NETWORK',
        message: 'Не удалось подключиться к серверу: $error',
      );
    }
  }

  @override
  Future<List<SemyaBrowseTokenSummary>> listBrowseTokens({
    required String semyaId,
  }) async {
    final trimmed = semyaId.trim();
    if (trimmed.isEmpty) {
      throw const SemyaError(
        code: 'INVALID_INPUT',
        message: 'Некорректный идентификатор семьи',
      );
    }
    try {
      final response = await _requestJson(
        method: 'GET',
        path: '/v1/semya/$trimmed/browse-tokens',
      );
      final raw = response['tokens'];
      if (raw is! List) return const <SemyaBrowseTokenSummary>[];
      return raw
          .whereType<Map>()
          .map((e) =>
              SemyaBrowseTokenSummary.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } on CustomApiException catch (e) {
      throw _mapSemyaException(e, endpoint: 'browse_tokens_list');
    }
  }

  @override
  Future<SemyaBrowseTokenSummary> revokeBrowseToken({
    required String semyaId,
    required String tokenId,
  }) async {
    final trimmedSemya = semyaId.trim();
    final trimmedToken = tokenId.trim();
    if (trimmedSemya.isEmpty || trimmedToken.isEmpty) {
      throw const SemyaError(
        code: 'INVALID_INPUT',
        message: 'Некорректные параметры',
      );
    }
    try {
      final response = await _requestJson(
        method: 'DELETE',
        path: '/v1/semya/$trimmedSemya/browse-token/$trimmedToken',
      );
      final tokenRaw = response['token'];
      if (tokenRaw is! Map<String, dynamic>) {
        throw const CustomApiException(
          'revoke browse-token: backend не вернул token объект',
        );
      }
      return SemyaBrowseTokenSummary.fromJson(tokenRaw);
    } on CustomApiException catch (e) {
      // Inline mapping — generic _mapSemyaException treats 409 как
      // TREE_ALREADY_BOUND. Здесь 409 = TOKEN_ALREADY_REVOKED, 404 =
      // TOKEN_NOT_FOUND, 403 = NOT_CREATOR_OR_OWNER. Surface domain
      // codes так UI может render targeted copy.
      final status = e.statusCode;
      String code;
      switch (status) {
        case 400:
          code = 'INVALID_TOKEN_ID';
          break;
        case 403:
          code = 'NOT_CREATOR_OR_OWNER';
          break;
        case 404:
          code = 'TOKEN_NOT_FOUND';
          break;
        case 409:
          code = 'TOKEN_ALREADY_REVOKED';
          break;
        default:
          code = 'UNKNOWN';
      }
      throw SemyaError(code: code, message: e.message);
    }
  }

  @override
  Future<List<String>> listHiddenPersonIds({required String semyaId}) async {
    final trimmed = semyaId.trim();
    if (trimmed.isEmpty) {
      throw const SemyaError(
        code: 'INVALID_INPUT',
        message: 'Некорректный идентификатор семьи',
      );
    }
    try {
      final response = await _requestJson(
        method: 'GET',
        path: '/v1/me/semya/$trimmed/hide-filter',
      );
      final raw = response['hiddenPersonIds'];
      if (raw is! List) return const <String>[];
      return raw
          .map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    } on CustomApiException catch (e) {
      throw _mapSemyaException(e, endpoint: 'hide_filter_list');
    }
  }

  @override
  Future<List<String>> updateHideFilter({
    required String semyaId,
    List<String> addPersonIds = const <String>[],
    List<String> removePersonIds = const <String>[],
  }) async {
    final trimmed = semyaId.trim();
    if (trimmed.isEmpty) {
      throw const SemyaError(
        code: 'INVALID_INPUT',
        message: 'Некорректный идентификатор семьи',
      );
    }
    if (addPersonIds.isEmpty && removePersonIds.isEmpty) {
      throw const SemyaError(
        code: 'INVALID_INPUT',
        message: 'Нужны personId-ы для скрытия либо снятия',
      );
    }
    final body = <String, dynamic>{};
    if (addPersonIds.isNotEmpty) {
      body['add'] = addPersonIds
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    }
    if (removePersonIds.isNotEmpty) {
      body['remove'] = removePersonIds
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    }
    try {
      final response = await _requestJson(
        method: 'PATCH',
        path: '/v1/me/semya/$trimmed/hide-filter',
        body: body,
      );
      _invalidateAllTreeCaches();
      final raw = response['hiddenPersonIds'];
      if (raw is! List) return const <String>[];
      return raw
          .map((e) => e?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    } on CustomApiException catch (e) {
      throw _mapSemyaException(e, endpoint: 'hide_filter_update');
    }
  }

  @override
  Future<SemyaMembership> updateMembership({
    required String semyaId,
    required String userId,
    SemyaRole? role,
    bool? hasInviteGrant,
  }) async {
    final trimmedSemya = semyaId.trim();
    final trimmedUser = userId.trim();
    if (trimmedSemya.isEmpty || trimmedUser.isEmpty) {
      throw const SemyaError(
        code: 'INVALID_INPUT',
        message: 'Некорректные параметры',
      );
    }
    if (role == null && hasInviteGrant == null) {
      throw const SemyaError(
        code: 'INVALID_INPUT',
        message: 'Нечего обновлять',
      );
    }
    final body = <String, dynamic>{};
    if (role != null) body['role'] = role.serverValue;
    if (hasInviteGrant != null) body['hasInviteGrant'] = hasInviteGrant;
    try {
      final response = await _requestJson(
        method: 'PATCH',
        path: '/v1/semya/$trimmedSemya/membership/$trimmedUser',
        body: body,
      );
      final raw = response['membership'];
      if (raw is! Map<String, dynamic>) {
        throw const CustomApiException(
          'updateMembership: backend не вернул membership объект',
        );
      }
      return SemyaMembership.fromJson(raw);
    } on CustomApiException catch (e) {
      throw _mapMembershipException(e, isRemove: false);
    }
  }

  @override
  Future<SemyaMembership> addMembership({
    required String semyaId,
    required String userId,
    required SemyaRole role,
    bool hasInviteGrant = false,
  }) async {
    final trimmedSemya = semyaId.trim();
    final trimmedUser = userId.trim();
    if (trimmedSemya.isEmpty || trimmedUser.isEmpty) {
      throw const SemyaError(
        code: 'INVALID_INPUT',
        message: 'Некорректные параметры',
      );
    }
    try {
      final response = await _requestJson(
        method: 'POST',
        path: '/v1/semya/$trimmedSemya/membership',
        body: <String, dynamic>{
          'userId': trimmedUser,
          'role': role.serverValue,
          'hasInviteGrant': hasInviteGrant,
        },
      );
      final raw = response['membership'];
      if (raw is! Map<String, dynamic>) {
        throw const CustomApiException(
          'addMembership: backend не вернул membership объект',
        );
      }
      return SemyaMembership.fromJson(raw);
    } on CustomApiException catch (e) {
      throw _mapMembershipException(e, isRemove: false);
    }
  }

  @override
  Future<SemyaMembershipRemoveResult> removeMembership({
    required String semyaId,
    required String userId,
  }) async {
    final trimmedSemya = semyaId.trim();
    final trimmedUser = userId.trim();
    if (trimmedSemya.isEmpty || trimmedUser.isEmpty) {
      throw const SemyaError(
        code: 'INVALID_INPUT',
        message: 'Некорректные параметры',
      );
    }
    try {
      final response = await _requestJson(
        method: 'DELETE',
        path: '/v1/semya/$trimmedSemya/membership/$trimmedUser',
      );
      final raw = response['membership'];
      if (raw is! Map<String, dynamic>) {
        throw const CustomApiException(
          'removeMembership: backend не вернул membership объект',
        );
      }
      return SemyaMembershipRemoveResult(
        membership: SemyaMembership.fromJson(raw),
        wasSelfLeave: response['wasSelfLeave'] == true,
      );
    } on CustomApiException catch (e) {
      throw _mapMembershipException(e, isRemove: true);
    }
  }

  /// Ship FE8: dedicated mapper для 4 backend invariants. Generic
  /// _mapSemyaException treats 409 как TREE_ALREADY_BOUND — wrong
  /// для membership endpoints. Здесь 409 carries domain-specific
  /// code derivable из message text (backend returns localized
  /// message but not error code in body — frontend pattern-matches
  /// на ключевые words).
  SemyaError _mapMembershipException(
    CustomApiException e, {
    required bool isRemove,
  }) {
    final status = e.statusCode;
    final messageLower = e.message.toLowerCase();
    String code;
    switch (status) {
      case 400:
        code = 'INVALID_INPUT';
        break;
      case 403:
        code = 'NOT_OWNER';
        break;
      case 404:
        // MEMBERSHIP_NOT_FOUND либо SEMYA_NOT_FOUND — discriminate
        // через message keyword «участник» (membership) vs «семь» (semya).
        if (messageLower.contains('участник')) {
          code = 'MEMBERSHIP_NOT_FOUND';
        } else {
          code = 'SEMYA_NOT_FOUND';
        }
        break;
      case 409:
        if (isRemove) {
          code = 'LAST_OWNER_REMOVE_FORBIDDEN';
        } else if (messageLower.contains('свою роль')) {
          code = 'SELF_ROLE_CHANGE_FORBIDDEN';
        } else if (messageLower.contains('последнего владельца')) {
          code = 'LAST_OWNER_DEMOTE_FORBIDDEN';
        } else if (messageLower.contains('право приглашать') ||
            messageLower.contains('только для редакторов')) {
          code = 'INVITE_GRANT_ONLY_EDITOR';
        } else {
          code = 'CONFLICT';
        }
        break;
      default:
        code = 'UNKNOWN';
    }
    return SemyaError(code: code, message: e.message);
  }

  /// Map [CustomApiException.statusCode] к domain-specific
  /// [SemyaError] code. Backend response payloads documented в
  /// backend/src/routes/semya-routes.js + entity-design §1.
  SemyaError _mapSemyaException(
    CustomApiException e, {
    required String endpoint,
  }) {
    final status = e.statusCode;
    final lower = e.message.toLowerCase();
    String code;
    switch (status) {
      case 400:
        code = 'INVALID_INPUT';
        break;
      case 403:
        if (endpoint == 'accept_invitation' &&
            (lower.contains('адресовано') || lower.contains('recipient'))) {
          code = 'WRONG_RECIPIENT';
        } else {
          code = 'FORBIDDEN';
        }
        break;
      case 404:
        if (endpoint.contains('invitation') || lower.contains('приглаш')) {
          code = 'INVITATION_NOT_FOUND';
        } else if (endpoint.contains('browse_token') ||
            lower.contains('ссылк') ||
            lower.contains('токен')) {
          code = 'TOKEN_NOT_FOUND';
        } else {
          code = 'SEMYA_NOT_FOUND';
        }
        break;
      case 409:
        if (endpoint.contains('invitation') ||
            lower.contains('принято') ||
            lower.contains('отклонено') ||
            lower.contains('отозван')) {
          code = 'INVITATION_NOT_PENDING';
        } else if (endpoint.contains('browse_token')) {
          code = 'TOKEN_ALREADY_REVOKED';
        } else {
          code = 'TREE_ALREADY_BOUND';
        }
        break;
      case 410:
        code = lower.contains('семь') ? 'SEMYA_DELETED' : 'INVITATION_EXPIRED';
        break;
      default:
        code = 'UNKNOWN';
    }
    return SemyaError(code: code, message: e.message);
  }
}
