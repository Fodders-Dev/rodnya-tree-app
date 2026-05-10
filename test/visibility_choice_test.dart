import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/models/visibility_choice.dart';

void main() {
  group('VisibilityChoice.serverValue', () {
    test('maps every enum case to a stable wire string', () {
      expect(
        VisibilityChoice.connectedViaBloodGraph.serverValue,
        'connected-via-blood-graph',
      );
      expect(VisibilityChoice.ownerOnly.serverValue, 'owner-only');
      expect(VisibilityChoice.publicEveryone.serverValue, 'public');
    });
  });

  group('VisibilityChoice.fromServerValue', () {
    test('round-trips known values', () {
      for (final choice in VisibilityChoice.values) {
        expect(
          VisibilityChoice.fromServerValue(choice.serverValue),
          choice,
        );
      }
    });

    test('unknown / null / empty defaults to connected-via-blood-graph', () {
      expect(
        VisibilityChoice.fromServerValue('rainbow-mode'),
        VisibilityChoice.connectedViaBloodGraph,
      );
      expect(
        VisibilityChoice.fromServerValue(null),
        VisibilityChoice.connectedViaBloodGraph,
      );
      expect(
        VisibilityChoice.fromServerValue(''),
        VisibilityChoice.connectedViaBloodGraph,
      );
    });
  });

  group('VisibilityChoice human-readable labels', () {
    test('non-empty russianLabel + russianHint для каждого варианта', () {
      for (final choice in VisibilityChoice.values) {
        expect(choice.russianLabel.trim().isNotEmpty, isTrue);
        expect(choice.russianHint.trim().isNotEmpty, isTrue);
      }
    });

    test('blood-graph hint упоминает «4 поколений» (consistent с backend)', () {
      // PHASE-3.4-UI-PROPOSAL §4 + verify-2: backend
      // _connectedVisibilityMaxHops = 4, отдельный от
      // branch.includeRules.maxHops = 5. «Поколений» точнее
      // «колен» в русском (колено многозначно).
      expect(
        VisibilityChoice.connectedViaBloodGraph.russianHint,
        contains('4 поколений'),
      );
    });
  });

  group('GraphPersonVisibility.fromJson / toJson', () {
    test('round-trip', () {
      final source = const GraphPersonVisibility(
        choice: VisibilityChoice.ownerOnly,
        override: true,
      );
      final round = GraphPersonVisibility.fromJson(source.toJson());
      expect(round.choice, source.choice);
      expect(round.override, source.override);
    });

    test('missing visibilityOverride defaults to false', () {
      final result = GraphPersonVisibility.fromJson({'visibility': 'public'});
      expect(result.choice, VisibilityChoice.publicEveryone);
      expect(result.override, isFalse);
    });

    test('defaultState — connected-via-blood-graph + override=false', () {
      final state = GraphPersonVisibility.defaultState();
      expect(state.choice, VisibilityChoice.connectedViaBloodGraph);
      expect(state.override, isFalse);
    });

    test('copyWith сохраняет immutable, меняет только указанные поля', () {
      const source = GraphPersonVisibility(
        choice: VisibilityChoice.ownerOnly,
        override: true,
      );
      final updated = source.copyWith(choice: VisibilityChoice.publicEveryone);
      expect(updated.choice, VisibilityChoice.publicEveryone);
      expect(updated.override, isTrue); // unchanged
    });
  });

  group('GraphPersonAccessSnapshot.effectiveOwnerUserId', () {
    test('userId wins over createdBy when both present', () {
      const snapshot = GraphPersonAccessSnapshot(
        graphPersonId: 'gp-1',
        visibility: GraphPersonVisibility(
          choice: VisibilityChoice.ownerOnly,
          override: true,
        ),
        userId: 'user-claimed',
        createdBy: 'user-creator',
      );
      expect(snapshot.effectiveOwnerUserId, 'user-claimed');
    });

    test('falls back на createdBy если userId пустой', () {
      const snapshot = GraphPersonAccessSnapshot(
        graphPersonId: 'gp-2',
        visibility: GraphPersonVisibility(
          choice: VisibilityChoice.connectedViaBloodGraph,
          override: false,
        ),
        userId: null,
        createdBy: 'user-creator',
      );
      expect(snapshot.effectiveOwnerUserId, 'user-creator');
    });

    test('null если нет ни одного', () {
      const snapshot = GraphPersonAccessSnapshot(
        graphPersonId: 'gp-3',
        visibility: GraphPersonVisibility(
          choice: VisibilityChoice.publicEveryone,
          override: true,
        ),
      );
      expect(snapshot.effectiveOwnerUserId, isNull);
    });
  });
}
