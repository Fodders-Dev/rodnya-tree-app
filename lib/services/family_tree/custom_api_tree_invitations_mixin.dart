part of '../custom_api_family_tree_service.dart';

mixin _CustomApiTreeInvitationsMixin on _CustomApiFamilyTreeHost {
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
    _invalidateAllTreeCaches();
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

  @override
  void _handlePendingInvitationsListen() {
    _pendingInvitationsListenerCount++;
    if (_pendingInvitationsListenerCount == 1) {
      _startPendingInvitationsPolling();
    }
  }

  @override
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
      if (!_pendingInvitationsController.isClosed &&
          _pendingInvitationsController.hasListener) {
        _pendingInvitationsController.addError(error, stackTrace);
      }
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
}
