import 'package:flutter_test/flutter_test.dart';
import 'package:rodnya/backend/backend_runtime_config.dart';
import 'package:rodnya/services/invitation_link_service.dart';

void main() {
  // Web routing is hash-based — `rodnya-tree.ru/#/tree/view/...` is
  // what the running app shows in its address bar. Invite links MUST
  // put `/invite?...` in the URL fragment so hash strategy actually
  // routes the recipient to the invitation handler. A path-segment
  // link (`/invite?...`) gets swallowed by SPA fallback to `/`.
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
      'https://family.example.ru/#/invite?treeId=tree-1&personId=person-2',
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
      'https://family.example.ru/app/#/invite?treeId=tree-1&personId=person-2',
    );
  });
}
