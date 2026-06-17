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
    });
  });
}
