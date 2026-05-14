import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/interfaces/onboarding_capable_family_tree_service.dart';
import 'package:rodnya/backend/models/onboarding_state.dart';
import 'package:rodnya/providers/onboarding_controller.dart';

class _FakeService implements OnboardingCapableFamilyTreeService {
  _FakeService({this.state, this.seedResult});

  OnboardingState? state;
  OnboardingSeedResult? seedResult;
  bool throwOnSeed = false;
  OnboardingSeedPayload? lastSeedPayload;
  OnboardingStep? lastUpdateStep;

  @override
  Future<OnboardingState?> getOnboardingState() async => state;

  @override
  Future<OnboardingSeedResult?> seedOnboarding({
    required OnboardingSeedPayload payload,
  }) async {
    if (throwOnSeed) throw StateError('boom');
    lastSeedPayload = payload;
    return seedResult;
  }

  @override
  Future<OnboardingState?> updateOnboardingState({
    required OnboardingStep currentStep,
  }) async {
    lastUpdateStep = currentStep;
    return state;
  }
}

void main() {
  group('OnboardingController capability', () {
    test('isCapable=false когда service null', () async {
      final controller = OnboardingController(service: null);
      // Wait for hydration tick.
      await Future<void>.delayed(Duration.zero);
      expect(controller.isCapable, isFalse);
      expect(controller.isLoading, isFalse);
    });

    test('isCapable=true когда service non-null', () async {
      final controller = OnboardingController(service: _FakeService());
      await Future<void>.delayed(Duration.zero);
      expect(controller.isCapable, isTrue);
    });
  });

  group('OnboardingController state hydration', () {
    test('default fresh state когда server returns nothing', () async {
      final controller = OnboardingController(service: _FakeService());
      await Future<void>.delayed(Duration.zero);
      expect(controller.currentStep, OnboardingStep.welcome);
      expect(controller.completed, isFalse);
    });

    test('hydrates с server state', () async {
      final service = _FakeService(
        state: const OnboardingState(
          userId: 'u',
          completed: false,
          currentStep: OnboardingStep.relatives,
        ),
      );
      final controller = OnboardingController(service: service);
      await Future<void>.delayed(Duration.zero);
      expect(controller.currentStep, OnboardingStep.relatives);
    });
  });

  group('OnboardingController step navigation', () {
    test('setStep updates state + persists fire-and-forget', () async {
      final service = _FakeService();
      final controller = OnboardingController(service: service);
      await Future<void>.delayed(Duration.zero);
      await controller.setStep(OnboardingStep.profile);
      expect(controller.currentStep, OnboardingStep.profile);
      await Future<void>.delayed(Duration.zero);
      expect(service.lastUpdateStep, OnboardingStep.profile);
    });

    test('setStep идемпотентен (same step → no-op)', () async {
      final service = _FakeService();
      final controller = OnboardingController(service: service);
      await Future<void>.delayed(Duration.zero);
      await controller.setStep(OnboardingStep.welcome);
      expect(service.lastUpdateStep, isNull);
    });
  });

  group('OnboardingController profile + relatives mutations', () {
    test('profileStepValid требует non-empty name', () async {
      final controller = OnboardingController(service: _FakeService());
      await Future<void>.delayed(Duration.zero);
      expect(controller.profileStepValid, isFalse);
      controller.setProfileName('Иван');
      expect(controller.profileStepValid, isTrue);
    });

    test('relatives draft slots default 2; addRelativeSlot до 5', () async {
      final controller = OnboardingController(service: _FakeService());
      await Future<void>.delayed(Duration.zero);
      expect(controller.relatives.length, 2);
      controller.addRelativeSlot();
      controller.addRelativeSlot();
      controller.addRelativeSlot();
      expect(controller.relatives.length, 5);
      controller.addRelativeSlot(); // cap'нут
      expect(controller.relatives.length, 5);
    });

    test('removeRelativeSlot keeps minimum 1', () async {
      final controller = OnboardingController(service: _FakeService());
      await Future<void>.delayed(Duration.zero);
      controller.removeRelativeSlot(0);
      expect(controller.relatives.length, 1);
      controller.removeRelativeSlot(0);
      expect(controller.relatives.length, 1, reason: 'нельзя удалить last slot');
    });

    test('hasMinimumRelatives когда хотя бы один valid', () async {
      final controller = OnboardingController(service: _FakeService());
      await Future<void>.delayed(Duration.zero);
      expect(controller.hasMinimumRelatives, isFalse);
      controller.setRelativeName(0, 'Мама');
      controller.setRelativeRelation(0, OnboardingRelationToMe.mother);
      expect(controller.hasMinimumRelatives, isTrue);
    });
  });

  group('OnboardingController submit', () {
    test(
        'submit без service либо invalid profile → false',
        () async {
      final controller = OnboardingController(service: null);
      await Future<void>.delayed(Duration.zero);
      final ok = await controller.submit();
      expect(ok, isFalse);
    });

    test('submit с пустым именем → false + error', () async {
      final controller = OnboardingController(service: _FakeService());
      await Future<void>.delayed(Duration.zero);
      final ok = await controller.submit();
      expect(ok, isFalse);
      expect(controller.error, contains('Имя'));
    });

    test('submit success → completed + treeId set', () async {
      final service = _FakeService(
        seedResult: const OnboardingSeedResult(
          treeId: 'tree-1',
          personIds: ['p1', 'p2'],
          idempotent: false,
        ),
      );
      final controller = OnboardingController(service: service);
      await Future<void>.delayed(Duration.zero);
      controller.setProfileName('Иван');
      controller.setRelativeName(0, 'Мама');
      controller.setRelativeRelation(0, OnboardingRelationToMe.mother);
      final ok = await controller.submit();
      expect(ok, isTrue);
      expect(controller.completed, isTrue);
      expect(controller.state.treeId, 'tree-1');
      // Payload contains only valid relatives (1).
      expect(service.lastSeedPayload?.relatives.length, 1);
    });

    test('submit с throw → error + false', () async {
      final service = _FakeService()..throwOnSeed = true;
      final controller = OnboardingController(service: service);
      await Future<void>.delayed(Duration.zero);
      controller.setProfileName('Иван');
      final ok = await controller.submit();
      expect(ok, isFalse);
      expect(controller.error, isNotNull);
    });

    test('submit с null service result → error', () async {
      final service = _FakeService(seedResult: null);
      final controller = OnboardingController(service: service);
      await Future<void>.delayed(Duration.zero);
      controller.setProfileName('Иван');
      final ok = await controller.submit();
      expect(ok, isFalse);
      expect(controller.error, isNotNull);
    });
  });

  group('OnboardingState DTO', () {
    test('fromJson coerces step + completed', () {
      final s = OnboardingState.fromJson({
        'userId': 'u-1',
        'completed': true,
        'currentStep': 'done',
        'treeId': 't-1',
        'personIds': ['p-1', 'p-2'],
      });
      expect(s.userId, 'u-1');
      expect(s.completed, isTrue);
      expect(s.currentStep, OnboardingStep.done);
      expect(s.treeId, 't-1');
      expect(s.personIds, ['p-1', 'p-2']);
    });

    test('fromJson defensive — unknown step → welcome', () {
      final s = OnboardingState.fromJson({
        'userId': 'u',
        'completed': false,
        'currentStep': 'random-string',
      });
      expect(s.currentStep, OnboardingStep.welcome);
    });
  });

  group('OnboardingRelativeDraft', () {
    test('isValid требует name + relationToMe', () {
      final draft = OnboardingRelativeDraft();
      expect(draft.isValid, isFalse);
      draft.name = 'Мама';
      expect(draft.isValid, isFalse);
      draft.relationToMe = OnboardingRelationToMe.mother;
      expect(draft.isValid, isTrue);
    });

    test('toRelative infers gender от mother/father/grandparent', () {
      final mom = OnboardingRelativeDraft(
        name: 'Мама',
        relationToMe: OnboardingRelationToMe.mother,
      ).toRelative();
      expect(mom.gender, 'female');
      final dad = OnboardingRelativeDraft(
        name: 'Папа',
        relationToMe: OnboardingRelationToMe.father,
      ).toRelative();
      expect(dad.gender, 'male');
      final sibling = OnboardingRelativeDraft(
        name: 'Брат',
        relationToMe: OnboardingRelationToMe.sibling,
      ).toRelative();
      expect(sibling.gender, isNull);
    });
  });
}
