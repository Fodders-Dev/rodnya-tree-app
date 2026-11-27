import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/services/app_links_dynamic_link_service.dart';

void main() {
  group('AppLinksDynamicLinkService.routeForUri', () {
    test('maps legacy hash invite link to GoRouter invite route', () {
      final route = AppLinksDynamicLinkService.routeForUri(
        Uri.parse(
          'https://rodnya-tree.ru/#/invite?treeId=tree-1&personId=person-2',
        ),
      );

      expect(route, '/invite?treeId=tree-1&personId=person-2');
    });

    test('maps legacy path invite link to GoRouter invite route', () {
      final route = AppLinksDynamicLinkService.routeForUri(
        Uri.parse(
          'https://rodnya-tree.ru/invite?treeId=tree-1&personId=person-2',
        ),
      );

      expect(route, '/invite?treeId=tree-1&personId=person-2');
    });

    test('maps token invitation and browse links', () {
      expect(
        AppLinksDynamicLinkService.routeForUri(
          Uri.parse('https://rodnya-tree.ru/invite/token-123'),
        ),
        '/invite/token-123',
      );
      expect(
        AppLinksDynamicLinkService.routeForUri(
          Uri.parse('https://rodnya-tree.ru/browse/browse-123'),
        ),
        '/browse/browse-123',
      );
    });

    test('ignores unrelated hosts and oauth callback links', () {
      expect(
        AppLinksDynamicLinkService.routeForUri(
          Uri.parse('https://example.com/#/invite?treeId=x&personId=y'),
        ),
        isNull,
      );
      expect(
        AppLinksDynamicLinkService.routeForUri(
          Uri.parse('https://rodnya-tree.ru/oauth/callback?code=abc'),
        ),
        isNull,
      );
      expect(
        AppLinksDynamicLinkService.routeForUri(
          Uri.parse('https://rodnya-tree.ru/story/guest-story-token'),
        ),
        isNull,
      );
    });

    test('maps P2.6 synced deep-linkable routes and preserves query strings',
        () {
      expect(
        AppLinksDynamicLinkService.routeForUri(
          Uri.parse('https://rodnya-tree.ru/post/post-42?commentId=c-1'),
        ),
        '/post/post-42?commentId=c-1',
      );
      expect(
        AppLinksDynamicLinkService.routeForUri(
          Uri.parse('https://rodnya-tree.ru/user/user-9'),
        ),
        '/user/user-9',
      );
      expect(
        AppLinksDynamicLinkService.routeForUri(
          Uri.parse('https://rodnya-tree.ru/notifications'),
        ),
        '/notifications',
      );
      expect(
        AppLinksDynamicLinkService.routeForUri(
          Uri.parse('https://rodnya-tree.ru/semya/semya-1?section=hidden'),
        ),
        '/semya/semya-1?section=hidden',
      );
      expect(
        AppLinksDynamicLinkService.routeForUri(
          Uri.parse('https://rodnya-tree.ru/relative/details/p-7?treeId=t-2'),
        ),
        '/relative/details/p-7?treeId=t-2',
      );
      expect(
        AppLinksDynamicLinkService.routeForUri(
          Uri.parse('https://rodnya-tree.ru/discover/relatives?incoming=chk-1'),
        ),
        '/discover/relatives?incoming=chk-1',
      );
      expect(
        AppLinksDynamicLinkService.routeForUri(
          Uri.parse('https://rodnya-tree.ru/story-requests/req-1/answer'),
        ),
        '/story-requests/req-1/answer',
      );
      expect(
        AppLinksDynamicLinkService.routeForUri(
          Uri.parse('https://rodnya-tree.ru/story-requests/req-1'),
        ),
        isNull,
      );
    });
  });
}
