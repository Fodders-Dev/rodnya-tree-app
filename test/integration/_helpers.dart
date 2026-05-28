// Ship FE10 partial (2026-05-26): shared infrastructure для integration
// тестов FE1-FE7 flows. `IntegrationFakeService` — stateful реализация
// `SemyaCapableFamilyTreeService`, mimicking ключевые backend behaviors
// (state transitions invitations + browse tokens, idempotent hide list
// mutations, identity-aware pull). НЕ полная backend simulation — только
// shape достаточный для end-to-end UI flow assertions.
//
// Factories — `make*` функции — keep тесты compact: каждый тест строит
// initial state + scripts service mutations через it.

import 'package:flutter/material.dart';
import 'package:rodnya/backend/interfaces/semya_capable_family_tree_service.dart';
import 'package:rodnya/backend/models/deleted_person.dart';
import 'package:rodnya/backend/models/deleted_post.dart';
import 'package:rodnya/backend/models/semya.dart';
import 'package:rodnya/backend/models/semya_browse_token.dart';
import 'package:rodnya/backend/models/semya_invitation.dart';
import 'package:rodnya/backend/models/semya_pull_person_result.dart';
import 'package:rodnya/models/family_person.dart';

/// Stateful in-memory fake — supports cross-method workflows so
/// integration tests assert end-to-end behavior без separate mocks
/// per controller / widget.
class IntegrationFakeService implements SemyaCapableFamilyTreeService {
  IntegrationFakeService({
    required this.currentUserId,
    this.currentUserEmail = '',
    List<Semya> initialSemyi = const <Semya>[],
    Map<String, List<SemyaMembership>>? initialMemberships,
    Map<String, List<SemyaInvitation>>? initialInvitations,
    Map<String, List<SemyaBrowseTokenSummary>>? initialBrowseTokens,
    Map<String, Set<String>>? initialHideFilter,
    Map<String, FamilyPerson>? personRegistry,
  })  : _semyi = [...initialSemyi],
        _memberships = {
          for (final entry in (initialMemberships ?? const {}).entries)
            entry.key: [...entry.value],
        },
        _invitations = {
          for (final entry in (initialInvitations ?? const {}).entries)
            entry.key: [...entry.value],
        },
        _browseTokens = {
          for (final entry in (initialBrowseTokens ?? const {}).entries)
            entry.key: [...entry.value],
        },
        _hideFilter = {
          for (final entry in (initialHideFilter ?? const {}).entries)
            _hideKey(entry.key, currentUserId): {...entry.value},
        },
        _personRegistry = {...?personRegistry};

  final String currentUserId;
  // Ship FE10 full (2026-05-27): optional caller email — used by
  // listPendingInvitations к match email-only invitations sent
  // perед user existed (post-registration matching flow).
  final String currentUserEmail;
  final List<Semya> _semyi;
  final Map<String, List<SemyaMembership>> _memberships;
  final Map<String, List<SemyaInvitation>> _invitations;
  final Map<String, List<SemyaBrowseTokenSummary>> _browseTokens;
  final Map<String, Set<String>> _hideFilter;
  final Map<String, FamilyPerson> _personRegistry;

  // Call counters для tests verifying что нужные endpoints вызваны.
  int listMySemyaCalls = 0;
  int findSemyaCalls = 0;
  int listMembershipsCalls = 0;
  int createInvitationCalls = 0;
  int listInvitationsCalls = 0;
  int revokeInvitationCalls = 0;
  int acceptInvitationCalls = 0;
  int pullCalls = 0;
  int createBrowseTokenCalls = 0;
  int fetchBrowseTreeCalls = 0;
  int listBrowseTokensCalls = 0;
  int revokeBrowseTokenCalls = 0;
  int listHiddenCalls = 0;
  int updateHideCalls = 0;

  static String _hideKey(String semyaId, String userId) =>
      '$semyaId::$userId';

  @override
  Future<List<Semya>> listMySemya() async {
    listMySemyaCalls += 1;
    // Mimic backend filtering soft-deleted семя.
    return _semyi.where((s) => s.deletedAt == null).toList(growable: false);
  }

  @override
  Future<SemyaDetails?> findSemyaById(String semyaId) async {
    findSemyaCalls += 1;
    final semya = _semyi.firstWhere(
      (s) => s.id == semyaId,
      orElse: () =>
          throw const SemyaError(code: 'SEMYA_NOT_FOUND', message: 'нет семьи'),
    );
    final myMembership = _memberships[semyaId]?.firstWhere(
      (m) => m.userId == currentUserId,
      orElse: () =>
          throw const SemyaError(code: 'FORBIDDEN', message: 'не участник'),
    );
    if (myMembership == null) {
      throw const SemyaError(code: 'FORBIDDEN', message: 'не участник');
    }
    return SemyaDetails(semya: semya, membership: myMembership);
  }

  @override
  Future<List<SemyaMembership>> listMembershipsForSemya(String semyaId) async {
    listMembershipsCalls += 1;
    return _memberships[semyaId] ?? const <SemyaMembership>[];
  }

  @override
  Future<SemyaInvitation> createInvitation({
    required String semyaId,
    required SemyaRole role,
    String? recipientEmail,
    String? recipientPhone,
    String? recipientUserId,
  }) async {
    createInvitationCalls += 1;
    final invitation = SemyaInvitation(
      id: 'inv-${_invitations[semyaId]?.length ?? 0}-${DateTime.now().microsecondsSinceEpoch}',
      token: 'tok-$semyaId-${recipientEmail ?? recipientPhone ?? recipientUserId}',
      semyaId: semyaId,
      inviterUserId: currentUserId,
      role: role,
      status: SemyaInvitationStatus.pending,
      recipientEmail: recipientEmail,
      recipientPhone: recipientPhone,
      recipientUserId: recipientUserId,
      createdAt: '2026-05-26T00:00:00.000Z',
      expiresAt: '2026-06-25T00:00:00.000Z',
    );
    (_invitations[semyaId] ??= <SemyaInvitation>[]).add(invitation);
    return invitation;
  }

  @override
  Future<List<SemyaInvitation>> listInvitationsForSemya(String semyaId) async {
    listInvitationsCalls += 1;
    return _invitations[semyaId] ?? const <SemyaInvitation>[];
  }

  @override
  Future<SemyaInvitation> revokeInvitation({
    required String semyaId,
    required String invitationId,
  }) async {
    revokeInvitationCalls += 1;
    final list = _invitations[semyaId];
    if (list == null) {
      throw const SemyaError(
        code: 'INVITATION_NOT_FOUND',
        message: 'нет приглашения',
      );
    }
    final idx = list.indexWhere((i) => i.id == invitationId);
    if (idx < 0) {
      throw const SemyaError(
        code: 'INVITATION_NOT_FOUND',
        message: 'нет приглашения',
      );
    }
    final orig = list[idx];
    final revoked = SemyaInvitation(
      id: orig.id,
      token: orig.token,
      semyaId: orig.semyaId,
      inviterUserId: orig.inviterUserId,
      role: orig.role,
      status: SemyaInvitationStatus.revoked,
      recipientEmail: orig.recipientEmail,
      recipientPhone: orig.recipientPhone,
      recipientUserId: orig.recipientUserId,
      createdAt: orig.createdAt,
      expiresAt: orig.expiresAt,
    );
    list[idx] = revoked;
    return revoked;
  }

  @override
  Future<SemyaInvitationAcceptResult> acceptInvitation(String token) async {
    acceptInvitationCalls += 1;
    SemyaInvitation? matched;
    String? matchedSemyaId;
    for (final entry in _invitations.entries) {
      final hit = entry.value.firstWhere(
        (i) => i.token == token,
        orElse: () => _placeholderInvitation,
      );
      if (hit.id != _placeholderInvitation.id) {
        matched = hit;
        matchedSemyaId = entry.key;
        break;
      }
    }
    if (matched == null || matchedSemyaId == null) {
      throw const SemyaError(
        code: 'INVITATION_NOT_FOUND',
        message: 'нет приглашения',
      );
    }
    if (matched.status != SemyaInvitationStatus.pending) {
      throw const SemyaError(
        code: 'INVITATION_NOT_PENDING',
        message: 'приглашение не активно',
      );
    }
    // Flip status + create membership.
    final list = _invitations[matchedSemyaId]!;
    final idx = list.indexOf(matched);
    list[idx] = SemyaInvitation(
      id: matched.id,
      token: matched.token,
      semyaId: matched.semyaId,
      inviterUserId: matched.inviterUserId,
      role: matched.role,
      status: SemyaInvitationStatus.accepted,
      recipientEmail: matched.recipientEmail,
      recipientPhone: matched.recipientPhone,
      recipientUserId: matched.recipientUserId,
      createdAt: matched.createdAt,
      expiresAt: matched.expiresAt,
    );
    final newMembership = SemyaMembership(
      id: 'mem-${matched.id}',
      semyaId: matched.semyaId,
      userId: currentUserId,
      role: matched.role,
      joinedAt: '2026-05-26T00:00:00.000Z',
    );
    (_memberships[matched.semyaId] ??= <SemyaMembership>[])
        .add(newMembership);
    return SemyaInvitationAcceptResult(
      invitation: list[idx],
      semyaId: matched.semyaId,
      role: matched.role,
      membershipId: newMembership.id,
    );
  }

  @override
  Future<SemyaPullPersonResult> pullPersonToSemya({
    required String targetSemyaId,
    required String sourceSemyaId,
    required String sourcePersonId,
  }) async {
    pullCalls += 1;
    final sourcePerson = _personRegistry[sourcePersonId];
    if (sourcePerson == null) {
      throw const SemyaError(
        code: 'PERSON_NOT_FOUND',
        message: 'персона не найдена',
      );
    }
    return SemyaPullPersonResult(
      person: sourcePerson,
      targetSemyaId: targetSemyaId,
      sourceSemyaId: sourceSemyaId,
      sourcePersonId: sourcePersonId,
    );
  }

  @override
  Future<SemyaBrowseToken> createBrowseToken({
    required String semyaId,
    int? expiresInDays,
  }) async {
    createBrowseTokenCalls += 1;
    final id = 'bt-${_browseTokens[semyaId]?.length ?? 0}';
    final tokenStr = 'tok-$semyaId-$id';
    final token = SemyaBrowseToken(
      id: id,
      semyaId: semyaId,
      token: tokenStr,
      createdByUserId: currentUserId,
      createdAt: '2026-05-26T00:00:00.000Z',
      expiresAt: '2026-06-25T00:00:00.000Z',
    );
    (_browseTokens[semyaId] ??= <SemyaBrowseTokenSummary>[]).add(
      SemyaBrowseTokenSummary(
        id: id,
        semyaId: semyaId,
        createdByUserId: currentUserId,
        createdAt: token.createdAt,
        expiresAt: token.expiresAt,
        status: 'active',
      ),
    );
    return token;
  }

  @override
  Future<BrowsedSemyaTree> fetchBrowseTree(String token) async {
    fetchBrowseTreeCalls += 1;
    // Find семя by token match.
    for (final entry in _browseTokens.entries) {
      for (final summary in entry.value) {
        final expected = 'tok-${entry.key}-${summary.id}';
        if (expected != token) continue;
        if (summary.status == 'revoked') {
          throw const SemyaError(
            code: 'TOKEN_REVOKED',
            message: 'отозвана',
          );
        }
        if (summary.status == 'expired') {
          throw const SemyaError(
            code: 'TOKEN_EXPIRED',
            message: 'истекла',
          );
        }
        final semya = _semyi.firstWhere((s) => s.id == entry.key);
        return BrowsedSemyaTree(
          semyaId: semya.id,
          semyaName: semya.name,
          treeId: semya.treeId,
          treeName: 'Дерево ${semya.name}',
          treeKind: 'family',
          persons: const <BrowsedPerson>[],
          relations: const <BrowsedRelation>[],
          sessionExpiresAt: summary.expiresAt,
        );
      }
    }
    throw const SemyaError(code: 'TOKEN_NOT_FOUND', message: 'не найдена');
  }

  @override
  Future<List<SemyaBrowseTokenSummary>> listBrowseTokens({
    required String semyaId,
  }) async {
    listBrowseTokensCalls += 1;
    return _browseTokens[semyaId] ?? const <SemyaBrowseTokenSummary>[];
  }

  @override
  Future<SemyaBrowseTokenSummary> revokeBrowseToken({
    required String semyaId,
    required String tokenId,
  }) async {
    revokeBrowseTokenCalls += 1;
    final list = _browseTokens[semyaId];
    if (list == null) {
      throw const SemyaError(
        code: 'TOKEN_NOT_FOUND',
        message: 'не найдена',
      );
    }
    final idx = list.indexWhere((t) => t.id == tokenId);
    if (idx < 0) {
      throw const SemyaError(
        code: 'TOKEN_NOT_FOUND',
        message: 'не найдена',
      );
    }
    final orig = list[idx];
    if (orig.status == 'revoked') {
      throw const SemyaError(
        code: 'TOKEN_ALREADY_REVOKED',
        message: 'уже отозвана',
      );
    }
    final updated = SemyaBrowseTokenSummary(
      id: orig.id,
      semyaId: orig.semyaId,
      createdByUserId: orig.createdByUserId,
      createdAt: orig.createdAt,
      expiresAt: orig.expiresAt,
      status: 'revoked',
      revokedAt: '2026-05-26T12:00:00.000Z',
    );
    list[idx] = updated;
    return updated;
  }

  @override
  Future<List<String>> listHiddenPersonIds({required String semyaId}) async {
    listHiddenCalls += 1;
    final key = _hideKey(semyaId, currentUserId);
    return (_hideFilter[key] ?? const <String>{}).toList(growable: false);
  }

  @override
  Future<List<String>> updateHideFilter({
    required String semyaId,
    List<String> addPersonIds = const <String>[],
    List<String> removePersonIds = const <String>[],
  }) async {
    updateHideCalls += 1;
    if (addPersonIds.isEmpty && removePersonIds.isEmpty) {
      throw const SemyaError(
        code: 'INVALID_INPUT',
        message: 'нужны personId',
      );
    }
    final key = _hideKey(semyaId, currentUserId);
    final set = _hideFilter[key] ??= <String>{};
    set.removeAll(removePersonIds);
    set.addAll(addPersonIds);
    return set.toList(growable: false);
  }

  // Ship Q4a frontend (2026-05-28, Ship 31): trash endpoints. Minimal
  // stateful stub — integration тесты пока не drive soft-delete flows
  // end-to-end (backend mutates collection напрямую), но interface
  // must compile. Returns [] для list, throws NOT_FOUND для destructive
  // ops с unknown id.

  @override
  Future<List<DeletedPerson>> listMyDeletedPersons() async {
    return const <DeletedPerson>[];
  }

  @override
  Future<List<DeletedPerson>> listDeletedPersonsForSemya(String semyaId) async {
    return const <DeletedPerson>[];
  }

  @override
  Future<void> restoreDeletedPerson(String deletedPersonId) async {
    throw const SemyaError(
      code: 'DELETED_PERSON_NOT_FOUND',
      message: 'нет такой записи в корзине',
    );
  }

  @override
  Future<void> permanentlyDeletePerson(String deletedPersonId) async {
    throw const SemyaError(
      code: 'DELETED_PERSON_NOT_FOUND',
      message: 'нет такой записи в корзине',
    );
  }

  @override
  Future<List<DeletedPost>> listMyDeletedPosts() async {
    return const <DeletedPost>[];
  }

  @override
  Future<void> restoreDeletedPost(String deletedPostId) async {
    throw const SemyaError(
      code: 'DELETED_POST_NOT_FOUND',
      message: 'нет такой записи в корзине',
    );
  }

  @override
  Future<void> permanentlyDeletePost(String deletedPostId) async {
    throw const SemyaError(
      code: 'DELETED_POST_NOT_FOUND',
      message: 'нет такой записи в корзине',
    );
  }

  // Sentinel для acceptInvitation lookup miss check (orElse can't
  // return null type для SemyaInvitation list element).
  static const SemyaInvitation _placeholderInvitation = SemyaInvitation(
    id: '__placeholder__',
    token: '',
    semyaId: '',
    inviterUserId: '',
    role: SemyaRole.viewer,
    status: SemyaInvitationStatus.pending,
    createdAt: '',
    expiresAt: '',
  );

  @override
  Future<SemyaMembership> updateMembership({
    required String semyaId,
    required String userId,
    SemyaRole? role,
    bool? hasInviteGrant,
  }) async {
    // Mimic backend: requires actor to be owner. Find target row,
    // apply role change with invariant checks parallel к store.js.
    final members = _memberships[semyaId];
    if (members == null) {
      throw const SemyaError(
        code: 'SEMYA_NOT_FOUND',
        message: 'нет семьи',
      );
    }
    final idx = members.indexWhere((m) => m.userId == userId);
    if (idx < 0) {
      throw const SemyaError(
        code: 'MEMBERSHIP_NOT_FOUND',
        message: 'нет участника',
      );
    }
    if (role == null && hasInviteGrant == null) {
      throw const SemyaError(
        code: 'INVALID_INPUT',
        message: 'нечего обновлять',
      );
    }
    final orig = members[idx];
    if (role != null && role != orig.role) {
      if (orig.userId == currentUserId) {
        throw const SemyaError(
          code: 'SELF_ROLE_CHANGE_FORBIDDEN',
          message: 'свою роль изменить нельзя',
        );
      }
      if (orig.role == SemyaRole.owner && role != SemyaRole.owner) {
        final owners = members.where((m) => m.role == SemyaRole.owner).length;
        if (owners <= 1) {
          throw const SemyaError(
            code: 'LAST_OWNER_DEMOTE_FORBIDDEN',
            message: 'нельзя понизить последнего владельца',
          );
        }
      }
    }
    final nextRole = role ?? orig.role;
    var nextGrant = hasInviteGrant ?? orig.hasInviteGrant;
    if (nextRole != SemyaRole.editor) {
      if (hasInviteGrant != null && hasInviteGrant && nextRole != SemyaRole.editor) {
        throw const SemyaError(
          code: 'INVITE_GRANT_ONLY_EDITOR',
          message: 'право приглашать только для редакторов',
        );
      }
      nextGrant = false;
    }
    final updated = SemyaMembership(
      id: orig.id,
      semyaId: orig.semyaId,
      userId: orig.userId,
      role: nextRole,
      joinedAt: orig.joinedAt,
      invitedByUserId: orig.invitedByUserId,
      hasInviteGrant: nextGrant,
    );
    members[idx] = updated;
    return updated;
  }

  @override
  Future<SemyaMembershipRemoveResult> removeMembership({
    required String semyaId,
    required String userId,
  }) async {
    final members = _memberships[semyaId];
    if (members == null) {
      throw const SemyaError(
        code: 'SEMYA_NOT_FOUND',
        message: 'нет семьи',
      );
    }
    final idx = members.indexWhere((m) => m.userId == userId);
    if (idx < 0) {
      throw const SemyaError(
        code: 'MEMBERSHIP_NOT_FOUND',
        message: 'нет участника',
      );
    }
    final target = members[idx];
    final wasSelfLeave = target.userId == currentUserId;
    if (target.role == SemyaRole.owner) {
      final owners = members.where((m) => m.role == SemyaRole.owner).length;
      if (owners <= 1) {
        throw const SemyaError(
          code: 'LAST_OWNER_REMOVE_FORBIDDEN',
          message: 'нельзя удалить последнего владельца',
        );
      }
    }
    members.removeAt(idx);
    return SemyaMembershipRemoveResult(
      membership: target,
      wasSelfLeave: wasSelfLeave,
    );
  }

  @override
  Future<List<SemyaInvitation>> listPendingInvitations() async {
    // Ship FE10 full (2026-05-27): mimic backend store filtering —
    // pending invitations addressed к currentUserId либо к
    // currentUserEmail (when recipientUserId == null). Enrich
    // каждый row с denormalized semyaName per FE9 endpoint shape.
    final normalizedEmail = currentUserEmail.toLowerCase().trim();
    final results = <SemyaInvitation>[];
    for (final entry in _invitations.entries) {
      for (final inv in entry.value) {
        if (inv.status != SemyaInvitationStatus.pending) continue;
        final matchesUserId = inv.recipientUserId == currentUserId;
        final invEmail = (inv.recipientEmail ?? '').toLowerCase().trim();
        final matchesEmail = inv.recipientUserId == null &&
            normalizedEmail.isNotEmpty &&
            invEmail.isNotEmpty &&
            invEmail == normalizedEmail;
        if (!matchesUserId && !matchesEmail) continue;
        final semya = _semyi.firstWhere(
          (s) => s.id == inv.semyaId && s.deletedAt == null,
          orElse: () => makeSemya(id: '__missing__', name: ''),
        );
        if (semya.id == '__missing__') continue;
        results.add(SemyaInvitation(
          id: inv.id,
          token: inv.token,
          semyaId: inv.semyaId,
          inviterUserId: inv.inviterUserId,
          role: inv.role,
          status: inv.status,
          recipientUserId: inv.recipientUserId,
          recipientEmail: inv.recipientEmail,
          recipientPhone: inv.recipientPhone,
          createdAt: inv.createdAt,
          expiresAt: inv.expiresAt,
          semyaName: semya.name,
        ));
      }
    }
    return results;
  }
}

// ============== Factories ==============

Semya makeSemya({
  String id = 's-1',
  String name = 'Семья Тест',
  String ownerId = 'u-owner',
  String treeId = 't-1',
}) {
  return Semya(
    id: id,
    name: name,
    ownerId: ownerId,
    treeId: treeId,
    createdAt: '2026-05-26T00:00:00.000Z',
    updatedAt: '2026-05-26T00:00:00.000Z',
  );
}

SemyaMembership makeMembership({
  String id = 'mem-1',
  String semyaId = 's-1',
  String userId = 'u-owner',
  SemyaRole role = SemyaRole.owner,
  bool hasInviteGrant = false,
}) {
  return SemyaMembership(
    id: id,
    semyaId: semyaId,
    userId: userId,
    role: role,
    joinedAt: '2026-05-26T00:00:00.000Z',
    hasInviteGrant: hasInviteGrant,
  );
}

SemyaInvitation makePendingInvitation({
  String id = 'inv-1',
  String token = 'tok-abc',
  String semyaId = 's-1',
  String inviterUserId = 'u-owner',
  SemyaRole role = SemyaRole.viewer,
  String? recipientEmail = 'invitee@example.com',
}) {
  return SemyaInvitation(
    id: id,
    token: token,
    semyaId: semyaId,
    inviterUserId: inviterUserId,
    role: role,
    status: SemyaInvitationStatus.pending,
    recipientEmail: recipientEmail,
    createdAt: '2026-05-26T00:00:00.000Z',
    expiresAt: '2026-06-25T00:00:00.000Z',
  );
}

SemyaBrowseTokenSummary makeBrowseTokenSummary({
  String id = 'bt-1',
  String semyaId = 's-1',
  String createdByUserId = 'u-owner',
  String status = 'active',
}) {
  return SemyaBrowseTokenSummary(
    id: id,
    semyaId: semyaId,
    createdByUserId: createdByUserId,
    createdAt: '2026-05-25T00:00:00.000Z',
    expiresAt: '2026-06-25T00:00:00.000Z',
    status: status,
  );
}

FamilyPerson makePerson({
  String id = 'p-1',
  String treeId = 't-1',
  String name = 'Иван Иванов',
  Gender gender = Gender.male,
}) {
  return FamilyPerson(
    id: id,
    treeId: treeId,
    name: name,
    gender: gender,
    isAlive: true,
    createdAt: DateTime(2026, 5, 26),
    updatedAt: DateTime(2026, 5, 26),
  );
}

// ============== Widget pump util ==============

Widget wrapMaterial(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));
