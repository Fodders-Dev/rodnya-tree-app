/// Phase 6 chunk 1/2: server-side wizard progress + seed result.
///
/// Persisted в backend `onboardingStates` collection per-user.
/// Wizard reads on app launch, decides resume vs start vs skip
/// (skip когда completed=true либо existing-user detection через
/// `hasExistingTree` heuristic в router guard).
class OnboardingState {
  const OnboardingState({
    required this.userId,
    required this.completed,
    required this.currentStep,
    this.treeId,
    this.personIds = const <String>[],
    this.completedAt,
    this.updatedAt,
  });

  final String userId;
  final bool completed;
  final OnboardingStep currentStep;
  final String? treeId;
  final List<String> personIds;
  final String? completedAt;
  final String? updatedAt;

  factory OnboardingState.fromJson(Map<String, dynamic> json) {
    return OnboardingState(
      userId: (json['userId'] ?? '').toString(),
      completed: json['completed'] == true,
      currentStep: OnboardingStep.fromServerValue(json['currentStep']),
      treeId: _nullableString(json['treeId']),
      personIds: json['personIds'] is List
          ? (json['personIds'] as List)
              .where((e) => e != null)
              .map((e) => e.toString())
              .toList(growable: false)
          : const <String>[],
      completedAt: _nullableString(json['completedAt']),
      updatedAt: _nullableString(json['updatedAt']),
    );
  }

  /// Default state для freshly registered user (server возвращает
  /// этот shape когда нет персистентной записи).
  static const OnboardingState fresh = OnboardingState(
    userId: '',
    completed: false,
    currentStep: OnboardingStep.welcome,
  );

  OnboardingState copyWith({
    bool? completed,
    OnboardingStep? currentStep,
    String? treeId,
    List<String>? personIds,
  }) {
    return OnboardingState(
      userId: userId,
      completed: completed ?? this.completed,
      currentStep: currentStep ?? this.currentStep,
      treeId: treeId ?? this.treeId,
      personIds: personIds ?? this.personIds,
      completedAt: completedAt,
      updatedAt: updatedAt,
    );
  }
}

enum OnboardingStep {
  welcome,
  profile,
  relatives,
  finish,
  done;

  String get serverValue {
    switch (this) {
      case OnboardingStep.welcome:
        return 'welcome';
      case OnboardingStep.profile:
        return 'profile';
      case OnboardingStep.relatives:
        return 'relatives';
      case OnboardingStep.finish:
        return 'finish';
      case OnboardingStep.done:
        return 'done';
    }
  }

  static OnboardingStep fromServerValue(Object? raw) {
    switch (raw?.toString()) {
      case 'profile':
        return OnboardingStep.profile;
      case 'relatives':
        return OnboardingStep.relatives;
      case 'finish':
        return OnboardingStep.finish;
      case 'done':
        return OnboardingStep.done;
      case 'welcome':
      default:
        return OnboardingStep.welcome;
    }
  }

  /// Step index в linear flow (welcome=0 → done=4). Note: enum's
  /// intrinsic `index` reflects declaration order, which для текущего
  /// porder совпадает с linear flow. Exposing explicit getter
  /// чтобы future re-ordering enum cases не сломало UI assumptions.
  int get stepIndex {
    switch (this) {
      case OnboardingStep.welcome:
        return 0;
      case OnboardingStep.profile:
        return 1;
      case OnboardingStep.relatives:
        return 2;
      case OnboardingStep.finish:
        return 3;
      case OnboardingStep.done:
        return 4;
    }
  }
}

/// Seed payload — wizard sends к backend для atomic creation.
class OnboardingSeedPayload {
  const OnboardingSeedPayload({
    required this.profile,
    this.relatives = const <OnboardingRelative>[],
  });

  final OnboardingProfile profile;
  final List<OnboardingRelative> relatives;

  Map<String, dynamic> toJson() {
    return {
      'profile': profile.toJson(),
      'relatives': relatives.map((r) => r.toJson()).toList(),
    };
  }
}

class OnboardingProfile {
  const OnboardingProfile({
    required this.name,
    this.gender,
    this.birthDate,
  });

  final String name;
  final String? gender; // 'male' | 'female' | null
  final String? birthDate; // ISO YYYY-MM-DD

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (gender != null) 'gender': gender,
      if (birthDate != null) 'birthDate': birthDate,
    };
  }
}

class OnboardingRelative {
  const OnboardingRelative({
    required this.name,
    required this.relationToMe,
    this.gender,
    this.birthDate,
  });

  final String name;
  final OnboardingRelationToMe relationToMe;
  final String? gender;
  final String? birthDate;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'relationToMe': relationToMe.serverValue,
      if (gender != null) 'gender': gender,
      if (birthDate != null) 'birthDate': birthDate,
    };
  }
}

enum OnboardingRelationToMe {
  mother,
  father,
  sibling,
  child,
  grandmother,
  grandfather,
  spouse;

  String get serverValue {
    switch (this) {
      case OnboardingRelationToMe.mother:
        return 'mother';
      case OnboardingRelationToMe.father:
        return 'father';
      case OnboardingRelationToMe.sibling:
        return 'sibling';
      case OnboardingRelationToMe.child:
        return 'child';
      case OnboardingRelationToMe.grandmother:
        return 'grandmother';
      case OnboardingRelationToMe.grandfather:
        return 'grandfather';
      case OnboardingRelationToMe.spouse:
        return 'spouse';
    }
  }

  String get russianLabel {
    switch (this) {
      case OnboardingRelationToMe.mother:
        return 'Мама';
      case OnboardingRelationToMe.father:
        return 'Папа';
      case OnboardingRelationToMe.sibling:
        return 'Брат/Сестра';
      case OnboardingRelationToMe.child:
        return 'Ребёнок';
      case OnboardingRelationToMe.grandmother:
        return 'Бабушка';
      case OnboardingRelationToMe.grandfather:
        return 'Дедушка';
      case OnboardingRelationToMe.spouse:
        return 'Супруг(а)';
    }
  }
}

/// Result от POST /onboarding/seed.
class OnboardingSeedResult {
  const OnboardingSeedResult({
    required this.treeId,
    required this.personIds,
    required this.idempotent,
  });

  final String treeId;
  final List<String> personIds;
  final bool idempotent;

  factory OnboardingSeedResult.fromJson(Map<String, dynamic> json) {
    return OnboardingSeedResult(
      treeId: (json['treeId'] ?? '').toString(),
      personIds: json['personIds'] is List
          ? (json['personIds'] as List)
              .where((e) => e != null)
              .map((e) => e.toString())
              .toList(growable: false)
          : const <String>[],
      idempotent: json['idempotent'] == true,
    );
  }
}

String? _nullableString(Object? raw) {
  if (raw == null) return null;
  final s = raw.toString();
  if (s.isEmpty) return null;
  return s;
}
