import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/backend_runtime_config.dart';
import 'package:rodnya/services/invitation_link_service.dart';

void main() {
  // Web routing is hash-based — `web/index.html` rewrites this canonical
  // `/invite?...` URL to `/#/invite?...` before Flutter boots. Keeping the
  // public link path-based lets Android App Links match installed APKs
  // directly instead of depending only on the legacy root/hash filter.
  test('HttpInvitationLinkService builds invite URL on root domain', () {
    final service = HttpInvitationLinkService(
      runtimeConfig: const BackendRuntimeConfig(
        publicAppUrl: 'https://family.example.ru',
      ),
    );

    final inviteUri = service.buildInvitationLink(
      treeId: 'tree-1',
      personId: 'person-2',
    );

    expect(
      inviteUri.toString(),
      'https://family.example.ru/invite?treeId=tree-1&personId=person-2',
    );
  });

  test('HttpInvitationLinkService preserves base path for hosted frontend', () {
    final service = HttpInvitationLinkService(
      runtimeConfig: const BackendRuntimeConfig(
        publicAppUrl: 'https://family.example.ru/app',
      ),
    );

    final inviteUri = service.buildInvitationLink(
      treeId: 'tree-1',
      personId: 'person-2',
    );

    expect(
      inviteUri.toString(),
      'https://family.example.ru/app/invite?treeId=tree-1&personId=person-2',
    );
  });
}
