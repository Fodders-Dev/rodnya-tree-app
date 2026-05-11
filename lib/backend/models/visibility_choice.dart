/// Phase 3.4 (PHASE-3.4-UI-PROPOSAL §4 + DECISIONS.md ответ A):
/// human-readable visibility choices для UI radio селектора.
/// Backend stores `'owner-only' | 'connected-via-blood-graph' |
/// 'public'`; UI rendert русские labels через [russianLabel] /
/// [russianHint]. Юзер не должен думать про hops/identity/etc.
enum VisibilityChoice {
  /// Default. ≤ 4 hops по кровным рёбрам видят узел. Effective
  /// visibility может auto-resolve в "public" через 100 лет
  /// после рождения (см. [GraphPersonVisibility.override]).
  connectedViaBloodGraph,

  /// Owner-only — только владелец видит карточку. Override
  /// блокирует auto-public для deceased + 100 лет.
  ownerOnly,

  /// Public — открыта в общем поиске. Sensitive поля
  /// (телефон/email/адрес) всё равно скрыты — это category-level
  /// gate отдельно от node visibility.
  publicEveryone;

  String get serverValue {
    switch (this) {
      case VisibilityChoice.connectedViaBloodGraph:
        return 'connected-via-blood-graph';
      case VisibilityChoice.ownerOnly:
        return 'owner-only';
      case VisibilityChoice.publicEveryone:
        return 'public';
    }
  }

  /// Defensive — unknown / null / empty → connected-via-blood-graph
  /// (default). Явный fallback на безопасное значение.
  static VisibilityChoice fromServerValue(Object? raw) {
    final stringValue = raw?.toString();
    switch (stringValue) {
      case 'connected-via-blood-graph':
        return VisibilityChoice.connectedViaBloodGraph;
      case 'owner-only':
        return VisibilityChoice.ownerOnly;
      case 'public':
        return VisibilityChoice.publicEveryone;
      default:
        return VisibilityChoice.connectedViaBloodGraph;
    }
  }

  /// Top-line UI label (radio).
  String get russianLabel {
    switch (this) {
      case VisibilityChoice.connectedViaBloodGraph:
        return 'Моим родственникам';
      case VisibilityChoice.ownerOnly:
        return 'Только мне';
      case VisibilityChoice.publicEveryone:
        return 'Всем';
    }
  }

  /// Под-текст под radio. Объясняет «когда выбирать» в человеческих
  /// терминах — без слов «hops», «identity», «graphPerson». «4
  /// поколений» совпадает с backend'ным
  /// `FileStore._connectedVisibilityMaxHops = 4` — это **visibility**
  /// BFS, отдельный от `branch.includeRules.maxHops` (default 5,
  /// для наполнения веток). Намеренное «поколений» вместо «колен» —
  /// «колено» в просторечии часто означает одну ветвь, тогда как
  /// «поколение» однозначно про generation step (parent → child).
  String get russianHint {
    switch (this) {
      case VisibilityChoice.connectedViaBloodGraph:
        return 'Видят те, кто связан со мной через семейные связи до 4 поколений.';
      case VisibilityChoice.ownerOnly:
        return 'Никто кроме меня не видит эту карточку. Со временем не публикуется автоматически.';
      case VisibilityChoice.publicEveryone:
        return 'Открыта в общем поиске. Контакты остаются приватными.';
    }
  }
}

/// Snapshot текущего visibility state у graphPerson'а. Read-only
/// payload для UI — позволяет radio показать актуальный выбор +
/// override checkbox + (опционально) объяснить если стоит auto-
/// public для исторической записи.
class GraphPersonVisibility {
  const GraphPersonVisibility({
    required this.choice,
    required this.override,
  });

  /// Stored value на graphPerson.visibility поле. Это **не**
  /// effective — для effective server делает auto-resolve
  /// (deceased + 100 years → public) если override = false.
  final VisibilityChoice choice;

  /// Если true, server не auto-resolve'ит — `choice` final word.
  /// Default false: для свежих карточек allows auto-public после
  /// 100 лет с birthDate.
  final bool override;

  Map<String, dynamic> toJson() {
    return {
      'visibility': choice.serverValue,
      'visibilityOverride': override,
    };
  }

  factory GraphPersonVisibility.fromJson(Map<String, dynamic> json) {
    return GraphPersonVisibility(
      choice: VisibilityChoice.fromServerValue(json['visibility']),
      override: json['visibilityOverride'] == true,
    );
  }

  /// Default state для свеже-созданного graphPerson'а.
  factory GraphPersonVisibility.defaultState() {
    return const GraphPersonVisibility(
      choice: VisibilityChoice.connectedViaBloodGraph,
      override: false,
    );
  }

  GraphPersonVisibility copyWith({
    VisibilityChoice? choice,
    bool? override,
  }) {
    return GraphPersonVisibility(
      choice: choice ?? this.choice,
      override: override ?? this.override,
    );
  }
}

/// Phase 3.4 chunk 2: read-state response от
/// `GET /v1/graph-persons/:id`. Carrying owner identity (для UI
/// «is viewer the owner?» check'а) + visibility snapshot.
class GraphPersonAccessSnapshot {
  const GraphPersonAccessSnapshot({
    required this.graphPersonId,
    required this.visibility,
    this.userId,
    this.createdBy,
  });

  final String graphPersonId;
  final GraphPersonVisibility visibility;

  /// Claimed user, если карточка привязана к user-аккаунту.
  /// `null` для anonymous кар (e.g. предки, вписанные кем-то ещё).
  final String? userId;

  /// Кто первоначально создал графовый узел. Owner-of-graphPerson
  /// = `userId ?? createdBy`. UI использует это чтобы решить
  /// показывать ли visibility-toggle viewer'у.
  final String? createdBy;

  String? get effectiveOwnerUserId =>
      userId != null && userId!.isNotEmpty
          ? userId
          : (createdBy != null && createdBy!.isNotEmpty ? createdBy : null);

  factory GraphPersonAccessSnapshot.fromJson(Map<String, dynamic> json) {
    return GraphPersonAccessSnapshot(
      graphPersonId: (json['id'] ?? '').toString(),
      visibility: GraphPersonVisibility.fromJson(json),
      userId: json['userId']?.toString(),
      createdBy: json['createdBy']?.toString(),
    );
  }
}
