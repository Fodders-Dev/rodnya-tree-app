/// Phase 3.4 (DECISIONS.md ответ D): включает person'ов в branch
/// либо вручную (legacy default), либо автоматически по
/// blood-graph relations.
///
/// Backend wire-format (`backend/src/migration-utils.js` +
/// `applyIncludeRulesToBranch` в `store.js`) принимает строки
/// `'manual' | 'blood-from-me' | 'descendants-of' | 'ancestors-of'`.
/// Map'инг hidden внутрь `serverValue` чтобы UI код работал с
/// type-safe enum'ом, а network — с stable строками.
enum BranchRuleType {
  /// Default. Юзер сам добавляет/убирает person'ов через UI.
  /// `anchorPersonId` / `maxHops` игнорируются.
  manual,

  /// BFS до `maxHops` колен от self-graphPerson'а юзера, по
  /// кровным связям (parent/child/sibling). `anchorPersonId`
  /// игнорируется (anchor = self).
  bloodFromMe,

  /// BFS вниз от `anchorPersonId` (только child-edges) до
  /// `maxHops` колен. Wizard prompts'ит выбрать anchor через
  /// person-picker.
  descendantsOf,

  /// BFS вверх от `anchorPersonId` (только parent-edges) до
  /// `maxHops` колен.
  ancestorsOf;

  /// Wire-value для backend payload. Stable между релизами —
  /// если когда-то понадобится переименовать enum case в Dart,
  /// network contract не сломается.
  String get serverValue {
    switch (this) {
      case BranchRuleType.manual:
        return 'manual';
      case BranchRuleType.bloodFromMe:
        return 'blood-from-me';
      case BranchRuleType.descendantsOf:
        return 'descendants-of';
      case BranchRuleType.ancestorsOf:
        return 'ancestors-of';
    }
  }

  /// Reverse-map. Неизвестное значение → `manual` (defensive — не
  /// падать на новом бекенде с типом которого UI ещё не знает,
  /// просто show старый-known fallback).
  static BranchRuleType fromServerValue(Object? raw) {
    final stringValue = raw?.toString();
    switch (stringValue) {
      case 'manual':
        return BranchRuleType.manual;
      case 'blood-from-me':
        return BranchRuleType.bloodFromMe;
      case 'descendants-of':
        return BranchRuleType.descendantsOf;
      case 'ancestors-of':
        return BranchRuleType.ancestorsOf;
      default:
        return BranchRuleType.manual;
    }
  }

  /// Human-readable label для UI radio (per Артёмовой Q-A: «не
  /// должен думать про hops»). Не зависит от выбранного `kind`
  /// (family/friends) — wizard показывает их только в family.
  String get russianLabel {
    switch (this) {
      case BranchRuleType.manual:
        return 'Свободная — я выбираю кого добавить';
      case BranchRuleType.bloodFromMe:
        return 'Кровная семья от меня';
      case BranchRuleType.descendantsOf:
        return 'Потомки выбранного человека';
      case BranchRuleType.ancestorsOf:
        return 'Предки выбранного человека';
    }
  }

  /// Sub-label под radio'ом. Конкретный для каждого типа,
  /// объясняет «когда такая ветка имеет смысл».
  String get russianHint {
    switch (this) {
      case BranchRuleType.manual:
        return 'Полный контроль над списком людей.';
      case BranchRuleType.bloodFromMe:
        return 'Все родственники до выбранного количества колен.';
      case BranchRuleType.descendantsOf:
        return 'Все потомки выбранного родственника.';
      case BranchRuleType.ancestorsOf:
        return 'Все предки выбранного родственника.';
    }
  }

  /// Нужен ли `anchorPersonId` для этого типа.
  bool get requiresAnchor =>
      this == BranchRuleType.descendantsOf || this == BranchRuleType.ancestorsOf;

  /// Использует ли этот тип BFS-обход (с `maxHops`).
  bool get usesBfs => this != BranchRuleType.manual;
}

/// Carrier для всего includeRules-payload'а. Wire shape совпадает
/// с серверным `applyIncludeRulesToBranch` — type, optional anchor,
/// optional maxHops, optional manualPersonIds.
class IncludeRules {
  const IncludeRules({
    required this.type,
    this.anchorPersonId,
    this.maxHops = 5,
    this.manualPersonIds = const <String>[],
  });

  final BranchRuleType type;

  /// graphPerson.id (= identityId) для descendants-of / ancestors-of.
  /// Для manual / blood-from-me игнорируется.
  final String? anchorPersonId;

  /// 1..20 на бекенде; UI clamp 3..8 в slider'е (sensible UX
  /// range — bigger trees редкость, меньше 3 не имеет смысла).
  /// Для manual игнорируется.
  final int maxHops;

  /// Только для type=manual. graphPerson IDs.
  final List<String> manualPersonIds;

  /// Default — blood-from-me с maxHops=5 (per RFC §D и Артёмовой
  /// рекомендацией branch wizard'у). Используется wizard'ом как
  /// initial state до того как юзер тапнет radio.
  factory IncludeRules.bloodFromMeDefault() {
    return const IncludeRules(type: BranchRuleType.bloodFromMe);
  }

  factory IncludeRules.manual() {
    return const IncludeRules(type: BranchRuleType.manual);
  }

  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{
      'type': type.serverValue,
      'maxHops': maxHops,
    };
    if (anchorPersonId != null && anchorPersonId!.isNotEmpty) {
      result['anchorPersonId'] = anchorPersonId;
    }
    if (manualPersonIds.isNotEmpty) {
      result['manualPersonIds'] = manualPersonIds;
    }
    return result;
  }

  static IncludeRules? tryFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final rawMaxHops = json['maxHops'];
    final maxHops = rawMaxHops is num ? rawMaxHops.toInt() : 5;
    final rawManual = json['manualPersonIds'];
    final manualPersonIds = rawManual is List
        ? rawManual.map((entry) => entry.toString()).toList(growable: false)
        : const <String>[];
    final anchorPersonIdRaw = json['anchorPersonId'];
    final anchorPersonId = anchorPersonIdRaw?.toString();
    return IncludeRules(
      type: BranchRuleType.fromServerValue(json['type']),
      anchorPersonId:
          anchorPersonId != null && anchorPersonId.isNotEmpty
              ? anchorPersonId
              : null,
      maxHops: maxHops,
      manualPersonIds: manualPersonIds,
    );
  }

  IncludeRules copyWith({
    BranchRuleType? type,
    String? anchorPersonId,
    int? maxHops,
    List<String>? manualPersonIds,
    bool clearAnchor = false,
  }) {
    return IncludeRules(
      type: type ?? this.type,
      anchorPersonId: clearAnchor ? null : (anchorPersonId ?? this.anchorPersonId),
      maxHops: maxHops ?? this.maxHops,
      manualPersonIds: manualPersonIds ?? this.manualPersonIds,
    );
  }
}
