/// Phase 3.4 (PHASE-3.4-UI-PROPOSAL §4 + §3): edit grant DTO для
/// `/v1/graph-persons/:id/grants` + `/v1/me/edit-grants` +
/// `/v1/me/issued-grants`. Используется в edit-grants screen
/// (chunk 3) и grant-action sheet на person card.
enum EditGrantScope {
  /// Изменение canonical полей graphPerson'а (имя, даты, фото и
  /// т.д.). Не включает visibility — это отдельный owner-only-всегда
  /// flow.
  edit,

  /// Согласие на merge с другой карточкой через
  /// `linkPersonsByIdentity`. Двусторонний — обе стороны merge'а
  /// должны иметь grant (или быть owners).
  mergeConsent,

  /// Soft-delete карточки. 30-day window до hard-delete (Phase 3.6).
  softDelete;

  String get serverValue {
    switch (this) {
      case EditGrantScope.edit:
        return 'edit';
      case EditGrantScope.mergeConsent:
        return 'merge-consent';
      case EditGrantScope.softDelete:
        return 'soft-delete';
    }
  }

  /// Defensive — unknown values default'ят на `edit` (наименее
  /// destructive из трёх). Если backend когда-то расширит scope'ы,
  /// старый client прочтёт unknown'ы как edit и не сломается.
  static EditGrantScope fromServerValue(Object? raw) {
    switch (raw?.toString()) {
      case 'edit':
        return EditGrantScope.edit;
      case 'merge-consent':
        return EditGrantScope.mergeConsent;
      case 'soft-delete':
        return EditGrantScope.softDelete;
      default:
        return EditGrantScope.edit;
    }
  }

  /// Russian label для UI (PHASE-3.4-UI-PROPOSAL §4 mapping).
  String get russianLabel {
    switch (this) {
      case EditGrantScope.edit:
        return 'Может редактировать';
      case EditGrantScope.mergeConsent:
        return 'Может объединять с другой карточкой';
      case EditGrantScope.softDelete:
        return 'Может удалить';
    }
  }
}

/// Lightweight preview для UI rendering.
class GrantPreviewSubject {
  const GrantPreviewSubject({
    required this.id,
    required this.displayName,
    this.photoUrl,
  });

  final String id;
  final String displayName;
  final String? photoUrl;

  factory GrantPreviewSubject.fromJson(Map<String, dynamic> json) {
    final raw = json;
    return GrantPreviewSubject(
      id: (raw['id'] ?? '').toString(),
      displayName: (raw['displayName'] ?? raw['name'] ?? '').toString(),
      photoUrl: raw['photoUrl'] is String && (raw['photoUrl'] as String).isNotEmpty
          ? raw['photoUrl'] as String
          : null,
    );
  }
}

class EditGrant {
  const EditGrant({
    required this.id,
    required this.graphPersonId,
    required this.grantorUserId,
    required this.granteeUserId,
    required this.scope,
    required this.grantedAt,
    this.revokedAt,
    this.graphPerson,
    this.grantee,
    this.grantor,
  });

  final String id;
  final String graphPersonId;
  final String grantorUserId;
  final String granteeUserId;
  final EditGrantScope scope;
  final String grantedAt;

  /// `null` пока grant активен. ISO-string когда owner revoke'нул.
  /// 30-day window: revoked-since-this-cut срезается на server
  /// /v1/me/edit-grants и /v1/me/issued-grants endpoints.
  final String? revokedAt;

  /// Hydrated by `/v1/me/edit-grants` + `/v1/me/issued-grants` —
  /// preview карточки чтобы UI отрендерил «доступ к XXX».
  final GrantPreviewSubject? graphPerson;

  /// Hydrated by `/v1/me/issued-grants` — preview юзера-grantee'а
  /// для outgoing-таб edit-grants screen ("кому я разрешил").
  final GrantPreviewSubject? grantee;

  /// Hydrated by `/v1/me/edit-grants` — preview юзера-grantor'а
  /// для incoming-таб ("кто мне разрешил"). Backend пока не
  /// отдаёт grantor preview через /v1/me/edit-grants — placeholder
  /// для future symmetry; client gracefully тaks null.
  final GrantPreviewSubject? grantor;

  bool get isRevoked => revokedAt != null && revokedAt!.isNotEmpty;

  factory EditGrant.fromJson(Map<String, dynamic> json) {
    final graphPerson = json['graphPerson'];
    final grantee = json['grantee'];
    final grantor = json['grantor'];
    return EditGrant(
      id: (json['id'] ?? '').toString(),
      graphPersonId: (json['graphPersonId'] ?? '').toString(),
      grantorUserId: (json['grantorUserId'] ?? '').toString(),
      granteeUserId: (json['granteeUserId'] ?? '').toString(),
      scope: EditGrantScope.fromServerValue(json['scope']),
      grantedAt: (json['grantedAt'] ?? '').toString(),
      revokedAt: json['revokedAt']?.toString(),
      graphPerson: graphPerson is Map<String, dynamic>
          ? GrantPreviewSubject.fromJson(graphPerson)
          : null,
      grantee: grantee is Map<String, dynamic>
          ? GrantPreviewSubject.fromJson(grantee)
          : null,
      grantor: grantor is Map<String, dynamic>
          ? GrantPreviewSubject.fromJson(grantor)
          : null,
    );
  }
}
