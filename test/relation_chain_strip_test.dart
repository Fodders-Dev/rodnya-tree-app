// Phase 6 chunk 3: RelationChainStrip render smoke + privacy
// anonymization behavior.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/models/blood_relation.dart';
import 'package:rodnya/widgets/relation_chain_strip.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: child),
  );
}

void main() {
  group('RelationChainStrip', () {
    testWidgets('renders empty when chain is empty', (tester) async {
      await tester.pumpWidget(_wrap(const RelationChainStrip(chain: [])));
      expect(find.byType(CircleAvatar), findsNothing);
    });

    testWidgets('renders one node для single-entry chain', (tester) async {
      await tester.pumpWidget(_wrap(const RelationChainStrip(
        chain: [
          BloodRelationPersonPreview(
            id: 'gp-1',
            name: 'Артём',
            gender: null,
            birthDate: null,
            deathDate: null,
            photoUrl: null,
          ),
        ],
      )));
      expect(find.byType(CircleAvatar), findsOneWidget);
      expect(find.text('Артём'), findsOneWidget);
    });

    testWidgets('anonymized node shows «?» placeholder', (tester) async {
      await tester.pumpWidget(_wrap(const RelationChainStrip(
        chain: [
          BloodRelationPersonPreview(
            id: 'gp-1',
            name: 'Артём',
            gender: null,
            birthDate: null,
            deathDate: null,
            photoUrl: null,
          ),
          BloodRelationPersonPreview(
            id: 'gp-2',
            name: null, // anonymized per privacy fence
            gender: null,
            birthDate: null,
            deathDate: null,
            photoUrl: null,
          ),
        ],
        edges: ['parent'],
      )));
      // Both nodes render avatars.
      expect(find.byType(CircleAvatar), findsNWidgets(2));
      // First node shows real name, second shows «?»
      expect(find.text('Артём'), findsOneWidget);
      expect(find.text('?'), findsWidgets);
    });

    testWidgets('edge label translates to Russian', (tester) async {
      await tester.pumpWidget(_wrap(const RelationChainStrip(
        chain: [
          BloodRelationPersonPreview(
            id: 'gp-1',
            name: 'Артём',
            gender: null,
            birthDate: null,
            deathDate: null,
            photoUrl: null,
          ),
          BloodRelationPersonPreview(
            id: 'gp-2',
            name: 'Мама',
            gender: null,
            birthDate: null,
            deathDate: null,
            photoUrl: null,
          ),
        ],
        edges: ['parent'],
      )));
      // Russian edge label appears under the arrow.
      expect(find.text('родитель'), findsOneWidget);
    });

    testWidgets('arrow appears between adjacent nodes', (tester) async {
      await tester.pumpWidget(_wrap(const RelationChainStrip(
        chain: [
          BloodRelationPersonPreview(
            id: '1',
            name: 'A',
            gender: null,
            birthDate: null,
            deathDate: null,
            photoUrl: null,
          ),
          BloodRelationPersonPreview(
            id: '2',
            name: 'B',
            gender: null,
            birthDate: null,
            deathDate: null,
            photoUrl: null,
          ),
          BloodRelationPersonPreview(
            id: '3',
            name: 'C',
            gender: null,
            birthDate: null,
            deathDate: null,
            photoUrl: null,
          ),
        ],
        edges: ['parent', 'child'],
      )));
      // 3 nodes → 2 arrows between.
      final arrows = find.byIcon(Icons.arrow_forward_rounded);
      expect(arrows, findsNWidgets(2));
    });
  });
}
