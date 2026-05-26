// Ship Q3a (2026-05-26): backend-driven auth provider capability
// flags. Tests verify fromHealthJson parsing + null-defensive paths
// (legacy server без authProviders field).

import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/models/auth_providers_availability.dart';

void main() {
  group('AuthProvidersAvailability.fromHealthJson', () {
    test('parses all 4 flags when present', () {
      final result = AuthProvidersAvailability.fromHealthJson({
        'authProviders': {
          'google': true,
          'vk': false,
          'telegram': true,
          'max': false,
        },
      });
      expect(result, isNotNull);
      expect(result!.google, isTrue);
      expect(result.vk, isFalse);
      expect(result.telegram, isTrue);
      expect(result.max, isFalse);
    });

    test('returns null когда authProviders missing (legacy server)', () {
      final result = AuthProvidersAvailability.fromHealthJson({
        'status': 'ok',
        'vkAuthEnabled': true, // flat fields ignored — frontend wants grouped
      });
      expect(result, isNull);
    });

    test('defensive false когда individual flag missing', () {
      final result = AuthProvidersAvailability.fromHealthJson({
        'authProviders': {
          'google': true,
          // vk, telegram, max omitted
        },
      });
      expect(result, isNotNull);
      expect(result!.google, isTrue);
      expect(result.vk, isFalse);
      expect(result.telegram, isFalse);
      expect(result.max, isFalse);
    });

    test('defensive false для non-bool values (e.g. accidentally string)', () {
      final result = AuthProvidersAvailability.fromHealthJson({
        'authProviders': {
          'google': 'true', // string, not bool
          'vk': 1, // int, not bool
          'telegram': null,
          'max': true,
        },
      });
      expect(result, isNotNull);
      expect(result!.google, isFalse, reason: 'string "true" != true bool');
      expect(result.vk, isFalse, reason: 'int 1 != true bool');
      expect(result.telegram, isFalse);
      expect(result.max, isTrue);
    });

    test('returns null когда authProviders неправильного type', () {
      final result = AuthProvidersAvailability.fromHealthJson({
        'authProviders': 'broken-shape',
      });
      expect(result, isNull);
    });
  });
}
