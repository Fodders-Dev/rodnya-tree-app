import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/utils/photo_url.dart';

void main() {
  group('normalizePhotoUrl', () {
    test('trims values', () {
      expect(
        normalizePhotoUrl('  https://example.com/avatar.jpg  '),
        'https://example.com/avatar.jpg',
      );
    });

    test('returns null for empty values', () {
      expect(normalizePhotoUrl(null), isNull);
      expect(normalizePhotoUrl(''), isNull);
      expect(normalizePhotoUrl('   '), isNull);
    });

    test('upgrades remote http URLs to https', () {
      expect(
        normalizePhotoUrl('http://api.rodnya-tree.ru/media/avatar.jpg'),
        'https://api.rodnya-tree.ru/media/avatar.jpg',
      );
      expect(
        normalizePhotoUrl('http://example.com/avatar.jpg'),
        'https://example.com/avatar.jpg',
      );
    });

    test('keeps localhost http URLs for local development', () {
      expect(
        normalizePhotoUrl('http://127.0.0.1:3000/media/avatar.jpg'),
        'http://127.0.0.1:3000/media/avatar.jpg',
      );
      expect(
        normalizePhotoUrl('http://localhost:3000/media/avatar.jpg'),
        'http://localhost:3000/media/avatar.jpg',
      );
    });
  });

  group('buildAvatarImageProvider', () {
    test('returns null for non-network values', () {
      expect(buildAvatarImageProvider('avatar.jpg'), isNull);
      expect(buildAvatarImageProvider('/media/avatar.jpg'), isNull);
    });

    test('returns cached provider for normalized network URL', () {
      final provider = buildAvatarImageProvider(
        ' http://api.rodnya-tree.ru/media/avatar.jpg ',
      );

      expect(provider, isA<CachedNetworkImageProvider>());
      expect(
        (provider as CachedNetworkImageProvider).url,
        'https://api.rodnya-tree.ru/media/avatar.jpg',
      );
    });
  });
}
