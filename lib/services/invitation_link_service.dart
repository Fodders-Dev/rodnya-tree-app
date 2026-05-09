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

  /// Builds `https://rodnya-tree.ru/#/invite?treeId=X&personId=Y`.
  ///
  /// User-reported: «уверен что ссылки рабочие?» — ответ «нет, не
  /// были». Раньше сюда клался path-сегмент `/invite?...` без
  /// hash-фрагмента. Веб-приложение использует hash URL strategy
  /// (видно в адресной строке: `rodnya-tree.ru/#/tree/view/...`).
  /// Когда получатель открывал ссылку в браузере, nginx отдавал
  /// index.html (SPA fallback), Flutter web стартовал, читал
  /// `window.location.hash` — пусто — и роутился на `/`. treeId
  /// и personId терялись в path-сегменте, гард `/invite` никогда
  /// не срабатывал, приглашение не привязывалось.
  ///
  /// Фикс — кладём `/invite?treeId=X&personId=Y` целиком в
  /// fragment. Получаем `https://rodnya-tree.ru/#/invite?treeId=...`,
  /// hash routing видит `/invite`, гард ловит, привязка работает.
  ///
  /// Старые ссылки (без `#`) пока не починятся, но новые приглашения
  /// — да; на сервере имеет смысл добавить redirect
  /// `/invite?…` → `/#/invite?…`, чтобы выкатить ссылки сразу всем
  /// получателям, кому уже отправили старый формат.
  @override
  Uri buildInvitationLink({required String treeId, required String personId}) {
    final baseUri = Uri.parse(_publicAppUrl);
    final query = Uri(queryParameters: {
      'treeId': treeId,
      'personId': personId,
    }).query;
    // Keep base path with trailing slash so SPA fallback hits
    // the right index.html (nginx is happier serving /app/ than
    // /app on a hosted-subpath frontend).
    final basePath = _normalizeBasePath(baseUri.path);
    return Uri(
      scheme: baseUri.scheme,
      host: baseUri.host,
      port: baseUri.hasPort ? baseUri.port : null,
      path: basePath,
      fragment: '/invite?$query',
    );
  }

  String _normalizeBasePath(String existingPath) {
    if (existingPath.isEmpty) {
      return '/';
    }
    return existingPath.endsWith('/') ? existingPath : '$existingPath/';
  }
}
