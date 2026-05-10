import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/models/include_rules.dart';

void main() {
  group('BranchRuleType.serverValue', () {
    test('maps every enum case to a stable wire string', () {
      expect(BranchRuleType.manual.serverValue, 'manual');
      expect(BranchRuleType.bloodFromMe.serverValue, 'blood-from-me');
      expect(BranchRuleType.descendantsOf.serverValue, 'descendants-of');
      expect(BranchRuleType.ancestorsOf.serverValue, 'ancestors-of');
    });
  });

  group('BranchRuleType.fromServerValue', () {
    test('round-trips known values', () {
      for (final type in BranchRuleType.values) {
        expect(
          BranchRuleType.fromServerValue(type.serverValue),
          type,
        );
      }
    });

    test('unknown / null / empty defaults to manual (defensive)', () {
      expect(BranchRuleType.fromServerValue('unknown-type'),
          BranchRuleType.manual);
      expect(BranchRuleType.fromServerValue(null), BranchRuleType.manual);
      expect(BranchRuleType.fromServerValue(''), BranchRuleType.manual);
    });
  });

  group('BranchRuleType helpers', () {
    test('requiresAnchor true только для descendants/ancestors', () {
      expect(BranchRuleType.manual.requiresAnchor, isFalse);
      expect(BranchRuleType.bloodFromMe.requiresAnchor, isFalse);
      expect(BranchRuleType.descendantsOf.requiresAnchor, isTrue);
      expect(BranchRuleType.ancestorsOf.requiresAnchor, isTrue);
    });

    test('usesBfs true для всего кроме manual', () {
      expect(BranchRuleType.manual.usesBfs, isFalse);
      expect(BranchRuleType.bloodFromMe.usesBfs, isTrue);
      expect(BranchRuleType.descendantsOf.usesBfs, isTrue);
      expect(BranchRuleType.ancestorsOf.usesBfs, isTrue);
    });
  });

  group('IncludeRules.toJson', () {
    test('blood-from-me со slider-ом 6 даёт минимальный payload', () {
      const rules = IncludeRules(
        type: BranchRuleType.bloodFromMe,
        maxHops: 6,
      );
      final json = rules.toJson();
      expect(json['type'], 'blood-from-me');
      expect(json['maxHops'], 6);
      // Empty manualPersonIds + null anchor → не сериализуются,
      // payload компактен.
      expect(json.containsKey('manualPersonIds'), isFalse);
      expect(json.containsKey('anchorPersonId'), isFalse);
    });

    test('descendants-of c anchor + maxHops payload-ит anchorPersonId', () {
      const rules = IncludeRules(
        type: BranchRuleType.descendantsOf,
        anchorPersonId: 'identity-mom',
        maxHops: 4,
      );
      final json = rules.toJson();
      expect(json['type'], 'descendants-of');
      expect(json['anchorPersonId'], 'identity-mom');
      expect(json['maxHops'], 4);
    });

    test('manual c manualPersonIds сериализует список', () {
      const rules = IncludeRules(
        type: BranchRuleType.manual,
        manualPersonIds: ['id-1', 'id-2'],
      );
      final json = rules.toJson();
      expect(json['type'], 'manual');
      expect(json['manualPersonIds'], ['id-1', 'id-2']);
    });

    test('пустой anchorPersonId не сериализуется', () {
      const rules = IncludeRules(
        type: BranchRuleType.descendantsOf,
        anchorPersonId: '',
      );
      final json = rules.toJson();
      // Empty string treated как «нет anchor'а».
      expect(json.containsKey('anchorPersonId'), isFalse);
    });
  });

  group('IncludeRules.tryFromJson', () {
    test('null input → null', () {
      expect(IncludeRules.tryFromJson(null), isNull);
    });

    test('full payload round-trip', () {
      final rules = IncludeRules.tryFromJson({
        'type': 'descendants-of',
        'anchorPersonId': 'identity-x',
        'maxHops': 7,
        'manualPersonIds': ['a', 'b'],
      });
      expect(rules, isNotNull);
      expect(rules!.type, BranchRuleType.descendantsOf);
      expect(rules.anchorPersonId, 'identity-x');
      expect(rules.maxHops, 7);
      expect(rules.manualPersonIds, ['a', 'b']);
    });

    test('missing maxHops → default 5', () {
      final rules = IncludeRules.tryFromJson({
        'type': 'blood-from-me',
      });
      expect(rules!.maxHops, 5);
    });

    test('empty anchorPersonId → null', () {
      final rules = IncludeRules.tryFromJson({
        'type': 'descendants-of',
        'anchorPersonId': '',
      });
      expect(rules!.anchorPersonId, isNull);
    });

    test('unknown type → manual fallback (defensive)', () {
      final rules = IncludeRules.tryFromJson({'type': 'rainbow-mode'});
      expect(rules!.type, BranchRuleType.manual);
    });
  });

  group('IncludeRules.copyWith', () {
    test('меняет один field, остальные сохраняются', () {
      const rules = IncludeRules(
        type: BranchRuleType.bloodFromMe,
        maxHops: 5,
      );
      final next = rules.copyWith(maxHops: 8);
      expect(next.type, BranchRuleType.bloodFromMe);
      expect(next.maxHops, 8);
    });

    test('clearAnchor: true → anchorPersonId = null', () {
      const rules = IncludeRules(
        type: BranchRuleType.descendantsOf,
        anchorPersonId: 'id-1',
      );
      final next = rules.copyWith(clearAnchor: true);
      expect(next.anchorPersonId, isNull);
    });
  });

  group('IncludeRules factories', () {
    test('bloodFromMeDefault', () {
      final rules = IncludeRules.bloodFromMeDefault();
      expect(rules.type, BranchRuleType.bloodFromMe);
      expect(rules.maxHops, 5);
      expect(rules.anchorPersonId, isNull);
    });

    test('manual', () {
      final rules = IncludeRules.manual();
      expect(rules.type, BranchRuleType.manual);
    });
  });
}
