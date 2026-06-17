import '../backend/backend_runtime_config.dart';
import '../backend/interfaces/invitation_link_service_interface.dart';

class HttpInvitationLinkService implements InvitationLinkServiceInterface {
  HttpInvitationLinkService({
    String? publicAppUrl,
    BackendRuntimeConfig? runtimeConfig,
  }) : _publicAppUrl = publicAppUrl ??
            runtimeConfig?.publicAppUrl ??
            BackendRuntimeConfig.current.publicAppUrl;

  final String _publicAppUrl;

  /// Builds `https://rodnya-tree.ru/invite?treeId=X&personId=Y`.
  ///
  /// Android App Links can match the `/invite` path directly and open
  /// installed APKs without claiming the whole root path. Flutter web still
  /// uses hash routing, so `web/index.html` rewrites `/invite?...` to
  /// `/#/invite?...` before bootstrapping the app.
  ///
  /// Старые hash-ссылки (`/#/invite?...`) продолжают приниматься в app links
  /// parser, потому что такие ссылки уже могли уйти пользователям.
  @override
  Uri buildInvitationLink({required String treeId, required String personId}) {
    final baseUri = Uri.parse(_publicAppUrl);
    // Keep base path with trailing slash so SPA fallback hits
    // the right index.html (nginx is happier serving /app/ than
    // /app on a hosted-subpath frontend).
    final basePath = _normalizeBasePath(baseUri.path);
    return Uri(
      scheme: baseUri.scheme,
      host: baseUri.host,
      port: baseUri.hasPort ? baseUri.port : null,
      path: '${basePath}invite',
      queryParameters: {
        'treeId': treeId,
        'personId': personId,
      },
    );
  }

  String _normalizeBasePath(String existingPath) {
    if (existingPath.isEmpty) {
      return '/';
    }
    return existingPath.endsWith('/') ? existingPath : '$existingPath/';
  }
}
