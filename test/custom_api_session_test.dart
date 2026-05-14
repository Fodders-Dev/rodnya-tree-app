// Phase 6 chunk 4a: CustomApiSession serialization для `requiresOnboarding`
// flag — Option A simplified post-signup redirect (DECISIONS 2026-05-14).

import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/models/custom_api_session.dart';

void main() {
  group('CustomApiSession.requiresOnboarding', () {
    test('default = false', () {
      const s = CustomApiSession(accessToken: 't', userId: 'u');
      expect(s.requiresOnboarding, isFalse);
    });

    test('fromJson parses true flag', () {
      final s = CustomApiSession.fromJson({
        'accessToken': 't',
        'userId': 'u',
        'requiresOnboarding': true,
      });
      expect(s.requiresOnboarding, isTrue);
    });

    test('fromJson defaults к false when missing', () {
      final s = CustomApiSession.fromJson({
        'accessToken': 't',
        'userId': 'u',
      });
      expect(s.requiresOnboarding, isFalse);
    });

    test('toJson roundtrip preserves flag', () {
      const original = CustomApiSession(
        accessToken: 't',
        userId: 'u',
        requiresOnboarding: true,
      );
      final clone = CustomApiSession.fromJson(original.toJson());
      expect(clone.requiresOnboarding, isTrue);
    });

    test('copyWith preserves flag когда не overridden', () {
      const original = CustomApiSession(
        accessToken: 't',
        userId: 'u',
        requiresOnboarding: true,
      );
      final updated = original.copyWith(displayName: 'New');
      expect(updated.requiresOnboarding, isTrue);
    });

    test('copyWith overrides flag explicitly', () {
      const original = CustomApiSession(
        accessToken: 't',
        userId: 'u',
        requiresOnboarding: true,
      );
      final updated = original.copyWith(requiresOnboarding: false);
      expect(updated.requiresOnboarding, isFalse);
    });
  });
}
