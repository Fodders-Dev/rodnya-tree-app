Полный read-only обход выполнен. Ниже готовый план для агента-исполнителя.

---

## 0. Execution Log

- [x] 2026-04-29 — Task 1 / Wave A first slice:
  - добавлен `lib/utils/photo_url.dart`
  - добавлен `test/photo_url_test.dart`
  - `NetworkImage` / `Image.network` убраны из `lib/widgets/family_tree_node_card.dart`, `lib/screens/relatives_screen.dart`, `lib/screens/blocked_users_screen.dart`, `lib/screens/find_relative_screen.dart`
  - проверки: `dart format`, `flutter analyze`, `flutter test test/photo_url_test.dart test/relatives_screen_test.dart test/chats_list_screen_test.dart test/find_relative_screen_test.dart`, `flutter build web`, локальный Playwright smoke `/relatives -> /login`
- [x] 2026-04-29 — Task 2 / Realtime exponential backoff:
  - `lib/services/custom_api_realtime_service.dart` переведён на exponential backoff `1→2→4→8→16→30s` с jitter ±25%
  - ручной `connect()` отменяет pending reconnect timer и может переподключаться сразу
  - счётчик failures сбрасывается после успешного websocket handshake
  - проверки: `dart format`, `flutter test test/custom_api_realtime_service_test.dart test/custom_api_chat_service_test.dart`, `flutter analyze`
- [x] 2026-04-29 — Task 3 / Backend post routes split:
  - добавлен `backend/src/routes/post-routes.js`
  - `/v1/posts*` и `/v1/posts/:postId/comments*` вынесены из `backend/src/app.js` без изменения middleware order и response payload
  - проверки: `node --check backend/src/app.js`, `node --check backend/src/routes/post-routes.js`, `node --test backend/test/api.test.js backend/test/app-media-routes.test.js`, `node --test backend/test/chat-utils.test.js backend/test/postgres-store.test.js`
- [x] 2026-04-29 — Wave B / Chat thumbnails on cached_network_image:
  - добавлен локальный `_AttachmentImage` в `lib/screens/chat_screen_supporting_widgets.dart`
  - remote chat images/video thumbnails/video-note previews/viewer thumbnails/poster переведены с `Image.network` на `CachedNetworkImage`
  - peer/chat info/candidate avatars переведены с `NetworkImage` на `buildAvatarImageProvider`
  - в `lib/screens/chat_screen.dart`, `lib/screens/chat_screen_sections.dart`, `lib/screens/chat_screen_supporting_widgets.dart` не осталось прямых `Image.network(...)` / `NetworkImage(...)`
  - проверки: `dart format`, `flutter test test/chat_screen_test.dart test/custom_api_chat_service_test.dart`, `flutter analyze`
- [x] 2026-04-29 — Wave E / Backend chat routes split:
  - добавлен `backend/src/routes/chat-routes.js`
  - `/v1/chats*` вынесены из `backend/src/app.js` в `registerChatRoutes(...)`
  - `/v1/calls*`, `store.js` и call/voice логика не тронуты
  - проверки: `node --check backend/src/app.js`, `node --check backend/src/routes/chat-routes.js`, `node --test backend/test/api.test.js backend/test/app-media-routes.test.js backend/test/chat-utils.test.js backend/test/postgres-store.test.js`
- [x] 2026-04-29 — Wave F / chat_screen.dart selection controller:
  - добавлен `lib/controllers/chat_selection_controller.dart`
  - selection-mode state (`remote/outgoing selected ids`, count, select/toggle/clear) вынесен из `_ChatScreenState`
  - `ChatScreen` перестраивает appbar/body через `ListenableBuilder` на selection controller
  - добавлен `test/chat_selection_controller_test.dart`
  - проверки: `dart format`, `flutter test test/chat_selection_controller_test.dart test/chat_screen_test.dart`, `flutter analyze`
- [x] 2026-04-29 — Wave G / home_screen sections extraction:
  - `_buildOperationalBanner`, `_buildHomeContentSections`, `_buildHomeHeader`, `_buildFeedContent`, `_buildFeedEmptyState` перенесены из `lib/screens/home_screen.dart` в `lib/screens/home_screen_sections.dart`
  - loading/data methods и event/story/feed бизнес-логика оставлены в `home_screen.dart`
  - проверки: `dart format`, `flutter test test/home_screen_test.dart`, `flutter analyze`
- [x] 2026-04-29 — Wave H / interactive tree controls extraction:
  - `_buildViewportStatusBar`, `_buildViewportControlDock`, `_buildDockButton`, `_buildOverlayChip` перенесены в `lib/widgets/interactive_family_tree_sections.dart`
  - layout-алгоритм, drag/gesture handling, painter и persistence manual positions не тронуты
  - проверки: `dart format`, `flutter test test/interactive_family_tree_test.dart`, `flutter analyze`
- [x] 2026-04-29 — Web smoke after UI waves:
  - `flutter build web`
  - локальный `python -m http.server 3010 --bind 127.0.0.1` из `build/web`
  - Playwright smoke `/#/login`, `/#/chats`, `/#/tree`: Flutter host найден, `/chats` и `/tree` корректно редиректят на login без page errors/request failures
- [x] 2026-04-29 — Wave I / SnackBar helper first slice:
  - добавлен `lib/utils/snackbar.dart` с `showAppSnackBar(context, message, {isError = false})`
  - первые простые snackbar calls в `lib/screens/chat_screen.dart` переведены на helper: empty attachment galleries, start call error, copy selected messages, forbidden selected delete, image picker limits/errors
  - проверки: `dart format`, `flutter test test/chat_screen_test.dart`, `flutter analyze`
- [x] 2026-04-29 — Wave A continuation / chats list avatar cache:
  - `lib/screens/chats_list_screen.dart` переведён с прямых `NetworkImage` на `buildAvatarImageProvider`
  - `lib/screens/chats_list_screen_create_sheet.dart` переведён с прямых `NetworkImage` на `buildAvatarImageProvider`
  - в `chats_list_screen.dart` и `chats_list_screen_create_sheet.dart` не осталось прямых `NetworkImage(...)` / `Image.network(...)`
  - проверки: `dart format`, `flutter test test/chats_list_screen_test.dart`, `flutter analyze`
- [x] 2026-04-29 — Wave A continuation / forward selector avatar cache:
  - `lib/widgets/chat_forward_selector.dart` переведён с прямого `NetworkImage` на `buildAvatarImageProvider`
  - в `chat_forward_selector.dart` не осталось прямых `NetworkImage(...)` / `Image.network(...)`
  - проверки: `dart format`, `flutter test test/chat_screen_test.dart`, `flutter analyze`
- [x] 2026-04-29 — Wave A continuation / offline profiles avatar cache:
  - `lib/screens/offline_profiles_screen.dart` переведён с прямого `NetworkImage` на `buildAvatarImageProvider`
  - в `offline_profiles_screen.dart` не осталось прямых `NetworkImage(...)` / `Image.network(...)`
  - проверки: `dart format`, `flutter analyze`
- [x] 2026-04-29 — Wave A continuation / tree view avatar cache:
  - `lib/screens/family_tree/tree_node.dart` и `lib/screens/tree_view_screen_sections.dart` переведены с прямых `NetworkImage` на `buildAvatarImageProvider`
  - в этих tree-view файлах не осталось прямых `NetworkImage(...)` / `Image.network(...)`
  - проверки: `dart format`, `flutter test test/tree_view_screen_test.dart`, `flutter analyze`
- [x] 2026-04-29 — Wave A continuation / relation request avatar cache:
  - `lib/screens/send_relation_request_screen.dart` и `lib/screens/relation_requests_screen.dart` переведены с прямых `NetworkImage` на `buildAvatarImageProvider`
  - в этих relation-request файлах не осталось прямых `NetworkImage(...)` / `Image.network(...)`
  - проверки: `dart format`, `flutter test test/send_relation_request_screen_test.dart`, `flutter analyze`
- [x] 2026-04-29 — Wave A continuation / profile media cache:
  - `lib/screens/profile_edit_screen_sections.dart` и `lib/screens/profile_screen_sections.dart` переведены с прямых `NetworkImage` на `buildAvatarImageProvider`
  - gallery preview в `lib/screens/profile_screen.dart` переведён с `Image.network` на `CachedNetworkImage` с существующим broken-image fallback
  - в profile/profile-edit файлах не осталось прямых `NetworkImage(...)` / `Image.network(...)`
  - проверки: `dart format`, `flutter test test/profile_screen_test.dart`, `flutter analyze`
- [x] 2026-04-29 — Wave A continuation / relative details media cache:
  - gallery strip, fullscreen gallery и thumbnails в `lib/screens/relative_details_screen.dart` / `_sections.dart` переведены с `Image.network` на `CachedNetworkImage`
  - media URL перед рендером проходит через `normalizePhotoUrl`
  - в relative-details файлах не осталось прямых `NetworkImage(...)` / `Image.network(...)`
  - проверки: `dart format`, `flutter test test/relative_details_screen_test.dart`, `flutter analyze`
- [x] 2026-04-29 — Wave A continuation / story media cache:
  - story poster background и image-story content переведены с `Image.network` на `CachedNetworkImage`
  - story author avatar переведён с прямого `NetworkImage` на `buildAvatarImageProvider`
  - в `lib/widgets/story_visuals.dart` и `lib/screens/story_viewer_screen.dart` не осталось прямых `NetworkImage(...)` / `Image.network(...)`
  - проверки: `dart format`, `flutter test test/story_viewer_screen_test.dart`, `flutter analyze`
- [x] 2026-04-29 — Wave A continuation / interactive tree gallery cache:
  - person gallery viewer в `lib/widgets/interactive_family_tree.dart` переведён с `Image.network` на `CachedNetworkImage`
  - gallery URL перед рендером проходит через `normalizePhotoUrl`
  - в `interactive_family_tree.dart` не осталось прямых `NetworkImage(...)` / `Image.network(...)`
  - проверки: `dart format`, `flutter test test/interactive_family_tree_test.dart`, `flutter analyze`
- [x] 2026-04-29 — Wave A media sweep status:
  - `rg "\bNetworkImage\(|\bImage\.network\(" lib/screens lib/widgets` оставляет только `lib/screens/call_screen.dart`
  - call screen не тронут: calls/voice остаются phase 2 и вне MVP scope по этому плану
- [x] 2026-04-29 — P1 / Backend write hot path audit:
  - подтверждено, что `PostgresStore` переопределяет `_read()` / `_write()` и не вызывает `FileStore` read/write напрямую
  - добавлен regression guard в `backend/test/postgres-store.test.js`
  - проверки: `node --check backend/test/postgres-store.test.js`, `node --test backend/test/postgres-store.test.js`
- [x] 2026-04-29 — Wave I continuation / chat snackbar helper second slice:
  - `showAppSnackBar` получил поддержку `duration`
  - video/file/recording/edit/bootstrap snackbar calls в `lib/screens/chat_screen.dart` переведены на helper
  - проверки: `dart format`, `flutter test test/chat_screen_test.dart`, `flutter analyze`
- [x] 2026-04-29 — Web smoke after media/snackbar sweep:
  - `flutter build web`
  - локальный `python -m http.server 3011 --bind 127.0.0.1` из `build/web`
  - Playwright smoke `/#/login`, `/#/chats`, `/#/tree`, `/#/profile`: Flutter host найден, protected routes редиректят на login без page errors/request failures
  - локальный web server остановлен после smoke
- [x] 2026-04-29 — Wave I continuation / chat snackbar helper third slice:
  - notification/pin/send-failure/copy/report/attachment/download/delete/group-info snackbar calls в `lib/screens/chat_screen.dart` переведены на `showAppSnackBar`
  - прямой `ScaffoldMessenger` в `chat_screen.dart` оставлен только для snackbar с `SnackBarAction` (`Блокировки`)
  - проверки: `dart format`, `flutter test test/chat_screen_test.dart`, `flutter analyze`
- [x] 2026-04-29 — Wave I completion / chat snackbar helper action support:
  - `showAppSnackBar` получил поддержку `SnackBarAction`
  - последний прямой `ScaffoldMessenger` в `lib/screens/chat_screen.dart` заменён на helper без потери action `Блокировки`
  - `rg "ScaffoldMessenger|SnackBar" lib/screens/chat_screen.dart` больше не показывает прямых snackbar вызовов, только `showAppSnackBar` / `SnackBarAction`
  - проверки: `dart format`, `flutter test test/chat_screen_test.dart`, `flutter analyze`
- [x] 2026-04-29 — P1 / relatives screen appbar sections extraction:
  - AppBar actions и `PopupMenuButton` вынесены из `lib/screens/relatives_screen.dart` в новый `lib/screens/relatives_screen_sections.dart`
  - snackbar `Сначала выберите дерево` переведён на `showAppSnackBar`
  - loading/data/subscription logic не тронута
  - проверки: `dart format`, `flutter test test/relatives_screen_test.dart`, `flutter analyze`
- [x] 2026-04-29 — P0 / Backend tree routes split first slice:
  - добавлен `backend/src/routes/tree-routes.js`
  - `/v1/trees`, public tree read-only endpoints, `/v1/trees/selectable`, list/create persons вынесены из `backend/src/app.js` в `registerTreeRoutes(...)`
  - detailed person/media/history/relation routes были оставлены inline для следующей безопасной волны
  - проверки: `node --check backend/src/app.js`, `node --check backend/src/routes/tree-routes.js`, `node --test backend/test/api.test.js`
- [x] 2026-04-29 — P0 / Backend tree routes split second slice:
  - person detail/dossier/update/delete, profile contributions, person media, tree history, tree graph и tree relations перенесены в `backend/src/routes/tree-routes.js`
  - invitations/relation-requests/calls/notifications оставлены в `backend/src/app.js` для отдельных волн
  - API contract сохранён: handlers перенесены 1:1 с прежними статусами и payload
  - проверки: `node --check backend/src/app.js`, `node --check backend/src/routes/tree-routes.js`, `node --test backend/test/api.test.js backend/test/app-media-routes.test.js backend/test/chat-utils.test.js backend/test/postgres-store.test.js`
- [x] 2026-04-29 — P0 / Backend tree invitations routes split:
  - добавлен `backend/src/routes/tree-invitation-routes.js`
  - `/v1/tree-invitations/pending`, `/v1/trees/:treeId/invitations`, `/v1/tree-invitations/:invitationId/respond` вынесены из `backend/src/app.js`
  - notification side effects сохранены через `createAndDispatchNotification`
  - проверки: `node --check backend/src/app.js`, `node --check backend/src/routes/tree-invitation-routes.js`, `node --test backend/test/api.test.js backend/test/app-media-routes.test.js backend/test/postgres-store.test.js`
- [x] 2026-04-29 — P0 / Backend relation request routes split:
  - добавлен `backend/src/routes/relation-request-routes.js`
  - `/v1/trees/:treeId/relation-requests`, `/v1/relation-requests/pending`, `/v1/relation-requests/:requestId/respond` вынесены из `backend/src/app.js`
  - create/respond notification side effects сохранены через `createAndDispatchNotification`
  - проверки: `node --check backend/src/app.js`, `node --check backend/src/routes/relation-request-routes.js`, `node --test backend/test/api.test.js backend/test/app-media-routes.test.js backend/test/chat-utils.test.js backend/test/postgres-store.test.js`
- [x] 2026-04-29 — P0 / Backend story routes split:
  - добавлен `backend/src/routes/story-routes.js`
  - `/v1/stories`, `/v1/stories/:storyId/view`, `DELETE /v1/stories/:storyId` вынесены из `backend/src/app.js`
  - tree access checks, payload shape и русские сообщения ошибок перенесены 1:1
  - проверки: `node --check backend/src/app.js`, `node --check backend/src/routes/story-routes.js`, `node --test backend/test/api.test.js backend/test/app-media-routes.test.js backend/test/chat-utils.test.js backend/test/postgres-store.test.js`
- [x] 2026-04-29 — P1 / Backend safety routes split:
  - добавлен `backend/src/routes/safety-routes.js`
  - `/v1/blocks*` и `POST /v1/reports` вынесены из `backend/src/app.js`
  - `admin-routes` оставлен после report endpoint; payload/status/messages сохранены
  - проверки: `node --check backend/src/app.js`, `node --check backend/src/routes/safety-routes.js`, `node --test backend/test/api.test.js backend/test/app-media-routes.test.js backend/test/chat-utils.test.js backend/test/postgres-store.test.js`
- [x] 2026-04-29 — P1 / Backend users routes split:
  - добавлен `backend/src/routes/user-routes.js`
  - `/v1/users/search`, `/v1/users/search/by-field`, `/v1/users/:userId/profile` вынесены из `backend/src/app.js`
  - profile visibility через `buildProfileViewerContext` и `sanitizeProfile` сохранена
  - проверки: `node --check backend/src/app.js`, `node --check backend/src/routes/user-routes.js`, `node --test backend/test/api.test.js backend/test/app-media-routes.test.js backend/test/chat-utils.test.js backend/test/postgres-store.test.js`
- [x] 2026-04-29 — P1 / Backend notification and push routes split:
  - добавлены `backend/src/routes/notification-routes.js` и `backend/src/routes/push-routes.js`
  - `/v1/notifications*` и `/v1/push*` вынесены из `backend/src/app.js`
  - web push config и RuStore/webpush device payload сохранены без изменений
  - проверки: `node --check backend/src/routes/notification-routes.js`, `node --check backend/src/routes/push-routes.js`, `node --test backend/test/api.test.js backend/test/app-media-routes.test.js backend/test/chat-utils.test.js backend/test/postgres-store.test.js`
- [x] 2026-04-29 — P1 / Backend pending invitation process route split:
  - добавлен `backend/src/routes/pending-invitation-routes.js`
  - `POST /v1/invitations/pending/process` вынесен из `backend/src/app.js`
  - link-person response payload (`ok`, `tree`, `person`) сохранён
  - проверки: `node --check backend/src/routes/pending-invitation-routes.js`, `node --test backend/test/api.test.js backend/test/app-media-routes.test.js backend/test/chat-utils.test.js backend/test/postgres-store.test.js`
- [x] 2026-04-29 — P1 / Backend Google auth routes split:
  - добавлен `backend/src/routes/google-auth-routes.js`
  - `POST /v1/auth/google` и `POST /v1/auth/google/link` вынесены из `backend/src/app.js`
  - Google idToken handling, auth identity linking, session payload и error mapping сохранены 1:1
  - проверки: `node --check backend/src/app.js`, `node --check backend/src/routes/google-auth-routes.js`, `node --test backend/test/api.test.js backend/test/app-media-routes.test.js backend/test/postgres-store.test.js`
- [x] 2026-04-29 — P1 / Backend VK, Telegram and MAX auth routes split:
  - добавлены `backend/src/routes/vk-auth-routes.js`, `backend/src/routes/telegram-auth-routes.js`, `backend/src/routes/max-auth-routes.js`
  - `/v1/auth/vk*`, `/v1/auth/telegram*`, `/v1/auth/max*` вынесены из `backend/src/app.js`
  - provider-specific helpers (`PKCE redirect`, Telegram signature/render, MAX init-data identity) перенесены вместе с routes
  - `rg "app\\.(get|post|patch|delete)\\(" backend/src/app.js` оставляет только health/ready, технический LiveKit webhook и `/v1/calls*` phase 2 routes
  - проверки: `node --check backend/src/app.js`, `node --check backend/src/routes/vk-auth-routes.js`, `node --check backend/src/routes/telegram-auth-routes.js`, `node --check backend/src/routes/max-auth-routes.js`, `node --test backend/test/api.test.js backend/test/app-media-routes.test.js backend/test/chat-utils.test.js backend/test/postgres-store.test.js`
- [x] 2026-04-29 — P2 / chats list sections extraction:
  - добавлен `lib/screens/chats_list_screen_sections.dart`
  - desktop shell, overview/context chips, search bar, filter bar, archive summary и chat meta pill UI вынесены из `lib/screens/chats_list_screen.dart`
  - load/create/open chat logic, stream subscription, sorting/filtering data path не тронуты
  - `setState` из extension не используется: state mutations оставлены на `_ChatsListScreenState`
  - проверки: `dart format`, `flutter test test/chats_list_screen_test.dart`, `flutter analyze`
- [x] 2026-04-29 — P2 / kIsWeb audit first safe extraction:
  - `lib/services/phone_contacts_service.dart` переведён на conditional export
  - добавлены `lib/services/phone_contacts_service_mobile.dart` и `lib/services/phone_contacts_service_stub.dart`
  - web больше не заходит в `flutter_contacts`; Android/iOS сохраняют native contacts path, desktop получает unsupported/empty result
  - оставшиеся `kIsWeb` ветвления в notification/RuStore/call/auth services требуют отдельного design pass, потому что они меняют runtime init и push/calls paths
  - проверки: `dart format`, `flutter analyze`
- [x] 2026-04-29 — P3 / TODO triage cleanup:
  - удалён устаревший TODO в `lib/screens/add_relative_screen.dart`: пользовательская ошибка там уже показывается через snackbar
  - RuStore TODO заменены на ownership-комментарии: registration token path остаётся в `CustomApiNotificationService`, topic subscriptions вне текущего MVP push scope
  - `rg "TODO|FIXME|HACK" lib backend/src` больше не находит runtime-code TODO
  - проверки: `dart format`, `flutter test test/add_relative_screen_test.dart`, `flutter analyze`
- [x] 2026-04-29 — Web smoke after final UI/service cleanup:
  - `flutter build web`
  - локальный `python -m http.server 3012 --bind 127.0.0.1` из `build/web`
  - Playwright smoke `/#/login`, `/#/chats`, `/#/tree`, `/#/profile`: Flutter host найден, protected routes редиректят на login без page errors/request failures
  - локальный web server остановлен после smoke
- [x] 2026-04-29 — P0 / chat search controller extraction:
  - добавлен `lib/controllers/chat_search_controller.dart`
  - search-mode state, query normalization и message matching вынесены из `_ChatScreenState`
  - `TextEditingController` теперь принадлежит search controller и корректно освобождается вместе с ним
  - добавлен `test/chat_search_controller_test.dart`
  - проверки: `dart format`, `flutter test test/chat_search_controller_test.dart test/chat_screen_test.dart`, `flutter analyze`
- [x] 2026-04-29 — P1 / interactive tree positioning extraction:
  - добавлен `lib/widgets/interactive_family_tree_positioning.dart`
  - manual-position merge, tree-size calculation, node drag handling и generation-row snap logic вынесены из `interactive_family_tree.dart`
  - прямой `setState` не используется внутри extension: state mutations проходят через основной `_InteractiveFamilyTreeState`
  - проверки: `dart format`, `flutter test test/interactive_family_tree_test.dart`, `flutter analyze`
- [x] 2026-04-29 — Web smoke after chat/tree controller cleanup:
  - `flutter build web`
  - локальный `python -m http.server 3013 --bind 127.0.0.1` из `build/web`
  - Playwright smoke `/#/login`, `/#/chats`, `/#/tree`, `/#/profile`: без page errors и видимых Flutter/runtime errors
  - локальный web server остановлен после smoke
- [x] 2026-04-29 — Production hotfix / Google web auth and feed reliability:
  - web Google login переведён с deprecated `google_sign_in_web.signIn()` path на GIS `renderButton()` для получения `idToken`
  - `CustomApiAuthService` слушает web Google credential events и завершает backend login через `/v1/auth/google`
  - `serverClientId` больше не передаётся в `GoogleSignIn` на web, потому что web implementation его не поддерживает
  - `CustomApiPostService` получил 12s timeout, один refresh-session retry на `401/403`, и regression test для feed retry
  - home feed status copy заменён с ложного `Лента офлайн` на `Лента недоступна`
  - проверки: `flutter pub get`, `dart format` для изменённых Dart-файлов, `flutter test test/custom_api_post_service_test.dart test/custom_api_auth_service_test.dart test/auth_screen_test.dart test/home_screen_test.dart`, `flutter analyze`, backend node tests, `flutter build web`, локальный Playwright smoke с `RODNYA_GOOGLE_WEB_CLIENT_ID`
- [x] 2026-04-29 — Production hotfix / Postgres write queue and Google button layout:
  - MCP Playwright на prod подтвердил, что Google GIS iframe есть и консоль чистая, но кнопка клипуется внутри auth card
  - prod API write smoke подтвердил 60s `504` на `/v1/auth/register`; это объясняет медленную загрузку сайта и статус `Лента недоступна`
  - `PostgresStore` теперь передаёт `query_timeout`/`statement_timeout` в `pg` и обрывает зависшие state/session write queues вместо бесконечного ожидания следующими write-запросами
  - web `GlassPanel` теперь уважает `clipBehavior`, auth card на web отключает clipping для Google platform-view, а native GIS button выравнивается без обрезания
  - проверки: `node --test backend/test/api.test.js backend/test/app-media-routes.test.js backend/test/chat-utils.test.js backend/test/postgres-store.test.js`, `flutter test test/auth_screen_test.dart test/custom_api_auth_service_test.dart`, `flutter analyze`, `flutter build web`, локальный MCP Playwright smoke с production dart-defines

---

## 0.1 Current Plan Status

- MVP-critical waves A-I are implemented and verified.
- Media sweep status: `rg "\bNetworkImage\(|\bImage\.network\(" lib/screens lib/widgets` now leaves only `lib/screens/call_screen.dart`, which remains phase 2 by scope.
- Backend split status: `backend/src/app.js` keeps health/ready, LiveKit webhook and `/v1/calls*`; MVP routes for auth/profile/media/posts/stories/trees/relations/chats/safety/users/notifications/push are registered through route modules.
- Runtime-code TODO status: `rg "TODO|FIXME|HACK" lib backend/src` is clean.
- Extra safe cleanup completed after the original waves: chat search controller extraction and interactive tree positioning extraction.
- Extra production hotfix completed after MCP smoke: Google web button layout is fixed locally, and Postgres write queues now have query/queue timeouts to prevent the 60s nginx `504` loop seen on prod.
- Residual candidates for the next Claude plan: outgoing-message/attachments controllers in `chat_screen.dart`, notification/RuStore conditional-import design, production smoke/CI simplification, and a deeper Postgres data model split away from whole-state JSON writes. Calls remain phase 2. `.github/workflows/*` were intentionally not changed because the repo guide requires explicit consent for CI/secrets work.
- Estimated completion of this plan: 100%.
- Sections below this point are the original Claude audit baseline; use this status block and the execution log above for current truth.

---

## 1. Executive Summary

Самые опасные зоны для MVP:

- **Гигантские монолиты с логикой в `build()`**: [`lib/screens/chat_screen.dart`](lib/screens/chat_screen.dart) (7590 строк, 91 `setState`), [`lib/widgets/interactive_family_tree.dart`](lib/widgets/interactive_family_tree.dart) (3823 строки), [`backend/src/store.js`](backend/src/store.js) (8737 строк), [`backend/src/app.js`](backend/src/app.js) (5362 строки, 95 роутов). Команда уже идёт верным путём — последние коммиты (`chore: split…`, `chore: extract backend …`) подтверждают cadence маленьких безопасных извлечений. Их нужно продолжить.
- **Media reliability на web/Android**: 41 прямой `NetworkImage` / `Image.network` в screens/widgets при том, что `cached_network_image` уже есть в `pubspec.yaml` и используется только в 3 виджетах ([`comment_sheet.dart`](lib/widgets/comment_sheet.dart), [`post_card.dart`](lib/widgets/post_card.dart), [`person_dossier_view.dart`](lib/widgets/person_dossier_view.dart)). Это бьёт по аватаркам, чатам и спискам родственников: нет кэша → redownload при scroll, мелькают placeholder'ы, на флэшах сети «битая картинка».
- **Realtime fragile reconnect**: [`lib/services/custom_api_realtime_service.dart:92`](lib/services/custom_api_realtime_service.dart) использует фиксированный `Duration(seconds: 3)` без backoff. При падении бэка мы реконнектим каждые 3 сек, нагружая собственный сервер.
- **Деплой web fragile**: коммиты `f0efac9 fix: retry transient route smoke responses`, `87f9b3e ci: run web deploy for smoke tooling changes`, `b62347e ci: deploy backend from main changes` показывают, что smoke регулярно лажает; pipeline зависит от внешнего `/usr/local/bin/rodnya-activate-web-release` и `sshpass` (см. [`.github/workflows/backend-deploy.yml`](.github/workflows/backend-deploy.yml)).
- **Backend split не доведён**: уже вынесены `admin-routes`, `auth-session-routes`, `media-routes`, `profile-routes`, но в `app.js` ещё ~70 роутов чата, постов, дерева, relations, notifications, calls.

Calls/voice логика трогать не надо — она phase 2 и сейчас не блокирует MVP.

---

## 2. Architecture Map

### Flutter (`lib/`)
- **`lib/main.dart`** (497) — bootstrap, `_StartupFailureApp`, `MaterialApp.router`, E2E bridge для web.
- **`lib/startup/`** — `app_startup_pipeline.dart`, `app_warmup_coordinator.dart`, `startup_failure_policy.dart` (короткие, аккуратные).
- **`lib/services/app_startup_service.dart`** (364) — DI через `GetIt`, сборка всех `CustomApi*Service` + `CallCoordinatorService`.
- **`lib/navigation/`** — split на `app_router`, `_guards`, `_shared`, `app_shell_route_module` (680), `app_overlay_route_module` (414), `deep_link_handler`. Чисто.
- **`lib/providers/`** — `theme_provider.dart`, `tree_provider.dart` (только эти два, всё остальное — services).
- **`lib/screens/`** — 41 экран. Топ по размеру: chat 7590, chats_list 1858, relative_details 1773, auth 1586, relatives 1503, add_relative 1487, profile_edit 1466, home 1439, settings 1051. Несколько уже разделены на `*_sections.dart` / `*_state_models.dart` — паттерн принят.
- **`lib/widgets/`** — `interactive_family_tree.dart` (3823 — главный риск), `person_dossier_view`, `story_rail`, `post_card`, `call_runtime_host`, `glass_panel`, и др.
- **`lib/services/`** — все `custom_api_*_service.dart`: family_tree (1745), notification (1448), chat (1253), auth (1181), profile (1020), realtime, storage, story, post, safety, call. Плюс локальные store'ы (`chat_archive_store`, `chat_draft_store`, `chat_pin_store`, …), `app_status_service`, `local_storage_service`, `event_service`, `rustore_service` (FCM-замена 654 строки), `phone_contacts_service`.
- **`lib/backend/`** — interfaces + adapters: `backend_provider_config.dart`, `backend_provider_registry.dart`, `backend_runtime_config.dart`, `pending_backend_adapters.dart`, и `interfaces/*`.
- **`lib/models/`** — DTO + Hive `.g.dart` (chat_message, family_person, family_relation, family_tree, user_profile).
- **`lib/controllers/`** — только `chat_recording_controller.dart`, `chat_timeline_controller.dart`. Сюда нужно мигрировать логику из `chat_screen.dart`.
- **`lib/utils/`** — `e2e_state_bridge.dart`, `chat_attachment_download.dart`, `url_utils.dart`, `web_wheel_listener.dart`, и др.

### Backend (`backend/`)
- **`backend/src/server.js`** (111) — entry, runtime errors collector, attaches `RealtimeHub` + `PushGateway`.
- **`backend/src/app.js`** (5362, 95 роутов) — Express app. Уже вынесены `routes/admin-routes`, `routes/auth-session-routes`, `routes/media-routes`, `routes/profile-routes`. **Внутри `app.js` остались**: stories, posts/comments, trees, persons, relations, tree-invitations, relation-requests, chats (все CRUD/messages/read/participants), calls, notifications.
- **`backend/src/store.js`** (8737) — `FileStore` (in-memory + JSON dump), 129 функций, единая `_writeQueue` Promise chain, `fs.writeFile(JSON.stringify(data, null, 2))` всего state на каждый write.
- **`backend/src/postgres-store.js`** (1703) — `PostgresStore extends FileStore`, shared pool registry, projection-fallback хелперы.
- **`backend/src/realtime-hub.js`** (254) — WebSocket hub, `userSockets: Map`.
- **`backend/src/push-gateway.js`** (249) — web-push + RuStore.
- **`backend/src/livekit-service.js`** (113) — calls (трогать не надо).
- **`backend/src/{chat-utils, profile-utils, media-storage, migration-utils, operational-status, config, google-auth, vk-auth, max-auth}.js`** — supporting modules, в основном уже compact.

### Tests
- **`test/`** (56 dart-тестов, в т.ч. экранов, сервисов, роутера, startup, deep links).
- **`backend/test/`** (9 node-тестов: api, app-media-routes, chat-utils, config-env, media-storage, migration-utils, operational-status, postgres-store, store-factory).

### CI
- **`.github/workflows/backend-deploy.yml`** — `sshpass` + ручной archive activator on remote.
- **`.github/workflows/flutter-web-deploy.yml`** — web build + sync_web_shell_assets + Playwright `prod_route_smoke.mjs` после деплоя.
- **`.github/workflows/production-watch.yml`**, **`rustore-verify.yml`** — мониторинг.
- **`tool/`** — `backend_ready_alert.mjs`, `backend_runtime_watch.mjs`, `prod_route_smoke.mjs`, `sync_web_shell_assets.js`, `http_request_with_fallback.mjs`.

---

## 3. Top Findings

| Pri | Area | Files | Problem | Why it matters | Evidence | Suggested fix | Risk |
|---|---|---|---|---|---|---|---|
| P0 | Media reliability | `lib/screens/chat_screen_supporting_widgets.dart` (1274, 1476, 1509, 1667), `lib/screens/chats_list_screen.dart` (1517, 1700), `lib/screens/relative_details_screen.dart`, `lib/screens/blocked_users_screen.dart`, `lib/widgets/family_tree_node_card.dart` и т.д. | 41 прямой `NetworkImage` / `Image.network`, `cached_network_image` уже есть и используется лишь в 3 виджетах | Avatar/чат-картинки рекачаются при каждом скролле, на медленной сети мигают, нет единого error/loading. Ключевой жалобный класс багов на Android+web | `grep -rn NetworkImage lib/screens lib/widgets` — 41 совпадение; `pubspec.yaml:99: cached_network_image: ^3.3.1` | По одной зоне (post_card стиль) переводить avatars и chat thumbnails на `CachedNetworkImageProvider` / `CachedNetworkImage`; переиспользовать общий placeholder/errorWidget | Низкий, но требует тестировать каждый screen в браузере |
| P0 | Backend split | `backend/src/app.js` (5362, 95 routes) | Routing-monolith, тестировать сложно, hot zones (chats, posts, trees) перемешаны | Любая правка одного домена ломает диff-обзор и риск collateral | recent commits `chore: split backend auth profile routes`, `chore: extract backend chat helpers` — паттерн уже принят. В `grep route` по `app.js` чётко видны блоки stories/posts/trees/chats/calls/notifications | Продолжать вынос: следующая волна — `routes/post-routes.js`, потом `chat-routes.js`, потом `tree-routes.js` (см. Wave 2) | Низкий, если каждая волна = один файл и сохраняет сигнатуры |
| P0 | UI/state monolith | `lib/screens/chat_screen.dart` (7590, 91 setState), `chat_screen_supporting_widgets.dart` (1744) | Логика отправки, аттачей, реакций, поиска, выделения — всё в одном State'e с 91 `setState` | Любой rebuild чата ломает что-то ещё, регрессии после каждого коммита | header chat_screen.dart показывает 5 store'ов + realtime + safety service + record/timeline controller. Sections-extension уже только 164 строки — реальная логика осталась в `_ChatScreenState` | Извлечь по одному: (a) outgoing-message reducer в `ChatTimelineController`, (b) attachments controller, (c) selection-mode controller, (d) search controller. Без визуальных изменений | Средний — много путей. Нужно по одному, с прогоном `chat_screen_test.dart` |
| P1 | Realtime stability | `lib/services/custom_api_realtime_service.dart:92,127,128,207-208` | `Timer(_reconnectDelay, …)` всегда 3с, без backoff и без jitter | Каскад reconnect'ов на падении бэка/сети, лишние WS, лишние пушки | `_reconnectDelay = const Duration(seconds: 3)` | Экспоненциальный backoff 1→2→4→8→30с с jitter, сброс счётчика после успешного рукопожатия | Низкий |
| P1 | Tree widget monolith | `lib/widgets/interactive_family_tree.dart` (3823), `_layout_models.dart` (31), `_sections.dart` (126) | Sections-файлы пустые, layout/gestures/positioning всё в основном файле | Любая правка дерева трогает 3823 строки. Это самая визуально багующая зона | sections.dart 126 строк — extension создан, но почти не использован | Перенести в sections (a) сборку UI overlay (controls, generation guides), (b) gesture handling, (c) positions persistence. Без поведенческих изменений | Средний, нужны golden/widget tests |
| P1 | Home/profile/relatives жирные builds | `lib/screens/home_screen.dart` (1439, 16 `_build*`), `relatives_screen.dart` (1503), `relative_details_screen.dart` (1773), `add_relative_screen.dart` (1487), `profile_edit_screen.dart` (1466) | `build()` собирает большие popup-меню/секции на лету; `RefreshIndicator.onRefresh` запускает `Future.wait` параллельных загрузок без guard'ов от двойного pull | Лишние rebuild, перерисовки, иногда два запроса подряд при быстром pull-to-refresh | `home_screen.dart:362-412` — RefreshIndicator + Future.wait; `relatives_screen.dart:373-477` — PopupMenuButton с 5+ items inline | Вытащить `_build*` секции в `*_sections.dart` extensions (паттерн уже работает на chat). PopupMenu-конструкторы — в `const`-ные top-level builders | Низкий, можно по одному экрану за коммит |
| P1 | Backend write hot path | `backend/src/store.js:3836-3880` | Один общий `_writeQueue`, `fs.writeFile(JSON.stringify(data, null, 2))` — сериализация всего state на каждую запись | Ради FileStore этого хватит, но это same-class fallback, который наследует `PostgresStore`. Любая случайная запись через base — всё блокирует | строки 3836-3880 явно показывают global queue и whole-state stringify | Только аудит: убедиться, что `PostgresStore` ни в одном из 95 endpoint'ов не падает в file-write fallback (ключевая проверка перед изменениями) | Низкий аудит, средний если найдётся реальный путь |
| P1 | Web smoke fragility | `tool/prod_route_smoke.mjs`, `.github/workflows/flutter-web-deploy.yml:99-115` | Smoke падает на транзиентных HTTP — пришлось добавить retry (`f0efac9`); зависит от 8 секретов; деплой запускается при изменении smoke-tool — это бесконечный цикл | Каждый ложный fail блокирует релиз | recent fix-commit; workflow запускается на изменения тоже smoke-инструмента | Аудит retry-логики и идемпотентности smoke-проверок: сократить набор обязательных шагов до login + tree + chat list (под MVP), warning'и не fail'ить | Средний — если перетянуть, можно пропустить регрессию |
| P2 | Inconsistent error UX | по проекту 96 `ScaffoldMessenger`/`SnackBar` вызовов в `chat_screen.dart`, `relatives_screen.dart`, `relative_details_screen.dart` и др. | Snackbar-логика дублируется, тексты ошибок и стили разные | Усложняет правку и дальнейшую локализацию | grep по 3 файлам: 96 совпадений | Маленький helper `showAppSnackBar(context, …)` в `lib/utils/` (не новый design system, а просто унификация) и постепенно мигрировать | Низкий, делать только по path of least resistance |
| P2 | Раздельный chats_list_screen | `lib/screens/chats_list_screen.dart` (1858), `chats_list_screen_create_sheet.dart` (937) | Create-sheet уже вынесен, но основной экран всё ещё 1858 строк с вложенными builder'ами | Тяжёлый rebuild при appearance чата | размеры файлов | Извлечь sheet'ы поиска, пины, filter UI в `_sections.dart` по образцу chat_screen_sections | Низкий |
| P2 | Аватарка по `widget.photoUrl` без null-safe pipeline | `chat_screen_sections.dart:54`, `call_screen.dart:186`, `find_relative_screen.dart:764` | `NetworkImage(photoUrl!)` без HTTPS-нормализации в одном месте, при том что в bootstrap есть logic | Битая картинка → exception в render'е | строки выше | Завести `lib/utils/photo_url.dart` (или дополнить `url_utils.dart`) — единая нормализация к https + check на пустоту, использовать везде | Низкий |
| P2 | Множество `kIsWeb` ветвлений | `lib/services/{phone_contacts_service, rustore_service, custom_api_notification_service, custom_api_auth_service, call_coordinator_service, app_startup_service}.dart` | 16 `if (kIsWeb)` блоков в services, плюс отдельные `*_web.dart` / `*_stub.dart` для google sign-in и notifications — две модели сосуществуют | Риск рассинхронизации поведения, double init | grep `kIsWeb` services / widgets | Аудит: где есть `*_web.dart`/`*_stub.dart` — убрать `if(kIsWeb)` из вызывающего кода, оставить через conditional import | Средний |
| P3 | Dead/legacy hints | `pending_backend_adapters.dart`, `Codex_rules.md`, screenshots `tmp_emulator_*.png` (~150 файлов в repo root) | Накопились отладочные XML/PNG из call-репро-сессий | Шум при grep'ах, неудобный diff | `ls` корня | Только просьба пользователю прибрать — Codex не удаляет без подтверждения | Нулевой |
| P3 | TODO остатки | `lib/screens/add_relative_screen.dart:1391`, `lib/services/rustore_service.dart:568,652` | Старые TODO про передачу токена и обработку push-сообщений | Подсказка для следующей итерации push'ей | grep TODO | Просто триаж — решить, актуальны ли | Нулевой |
| P3 | `widget.photoUrl!` exclamation в build | `chat_screen_sections.dart:54-58`, `chats_list_screen.dart:1517,1700` | Нарушение null-safety стиля в hot path | Может бросить при пустой строке после нормализации | те же строки | После задачи аватарок и `photo_url` helper — снять `!` | Низкий |

---

## 4. Implementation Waves

Каждая волна = 1–2 коммита, не больше. Наследует cadence из `git log --oneline`.

### Wave A — Avatar/photo URL unification (P0)
- **Goal**: Все аватарки/превью в основных списках и чате через `cached_network_image` + общий нормализатор URL.
- **Files to touch**: новый `lib/utils/photo_url.dart` (или дополнение `lib/utils/url_utils.dart`); один экран за коммит — начать с [`lib/widgets/family_tree_node_card.dart`](lib/widgets/family_tree_node_card.dart), [`lib/screens/chats_list_screen.dart:1517,1700`](lib/screens/chats_list_screen.dart), [`lib/screens/relatives_screen.dart`](lib/screens/relatives_screen.dart), [`lib/screens/blocked_users_screen.dart:140`](lib/screens/blocked_users_screen.dart).
- **Files NOT to touch**: `lib/screens/chat_screen_supporting_widgets.dart` (это отдельная волна B), `lib/widgets/post_card.dart` (уже мигрирован).
- **Steps**:
  1. Завести `lib/utils/photo_url.dart` — `String? normalizePhotoUrl(String? raw)` (https, trim, empty→null) + `ImageProvider? buildAvatarImageProvider(String?)` возвращает `CachedNetworkImageProvider` или `null`.
  2. Заменить `NetworkImage(x!)` на `buildAvatarImageProvider(x)` в одном файле за коммит.
  3. Обновить unit-test нормализации.
- **Behavior preserved**: визуально идентично, ниже сетевая нагрузка.
- **Tests**: `flutter test test/relatives_screen_test.dart test/chats_list_screen_test.dart test/find_relative_screen_test.dart`; `flutter analyze`.
- **Rollback risk**: низкий, локально по одному файлу.
- **Commit msg pattern**: `chore: cache relatives avatars via cached_network_image`.

### Wave B — Chat thumbnails on cached_network_image (P0)
- **Goal**: чат-вложения и аватары собеседника через cached pipeline, единый `errorBuilder`.
- **Files**: `lib/screens/chat_screen_supporting_widgets.dart:382,470,495,548,1274,1476,1509,1667`, `lib/screens/chat_screen_sections.dart:54`, `lib/screens/chat_screen.dart:6272,6777`.
- **Not touch**: `chat_screen.dart` State logic, message-sending flow.
- **Steps**:
  1. Локальный helper `_AttachmentImage` в `chat_screen_supporting_widgets.dart` поверх `CachedNetworkImage` с placeholder/errorBuilder, повторяющим текущий `_AttachmentPlaceholder`.
  2. Заменить `Image.network` (8 мест).
  3. Avatar в sections — на `buildAvatarImageProvider`.
- **Tests**: `flutter test test/chat_screen_test.dart`; web smoke вручную (открыть чат с фото).
- **Rollback risk**: средний — много мест; делать ОДНИМ коммитом без поведенческих изменений.
- **Commit msg**: `chore: cache chat attachments and peer avatar`.

### Wave C — Realtime backoff (P1)
- **Goal**: убрать тугой 3с-loop, добавить exponential backoff + jitter.
- **Files**: только `lib/services/custom_api_realtime_service.dart`.
- **Not touch**: ничего.
- **Steps**:
  1. Хранить `_consecutiveFailures`, делать delay = `min(30, 1 << min(failures, 5)) * (0.5 + random)`.
  2. Сбрасывать счётчик в обработчике успешного `connect`.
  3. Юнит-тест: проверка инкремента delay (через инжект `WebSocketChannelFactory` с фабрикой исключений).
- **Tests**: `flutter test test/custom_api_chat_service_test.dart` (если затрагивается) и новый кейс в `custom_api_realtime_service_test.dart` (если есть, иначе создать).
- **Rollback**: тривиальный.
- **Commit**: `fix: backoff realtime ws reconnect`.

### Wave D — Backend posts/comments routes split (P0)
- **Goal**: вынести `/v1/posts*` и `/v1/posts/:id/comments*` из `backend/src/app.js` в `backend/src/routes/post-routes.js` по образцу `routes/profile-routes.js`.
- **Files to touch**: `backend/src/app.js:3000-3199`, новый `backend/src/routes/post-routes.js`.
- **Not touch**: `backend/src/store.js`, остальные 95 роутов.
- **Steps**:
  1. Создать `registerPostRoutes({app, store, requireAuth, …})` — копия 6 эндпоинтов 1:1.
  2. В `app.js` — `registerPostRoutes(...)` вместо инлайна.
  3. Прогнать `node --test backend/test/api.test.js`.
- **Tests**: backend node tests + ручной curl `/v1/posts`.
- **Rollback**: revert одного коммита.
- **Commit**: `chore: split backend post routes`.

### Wave E — Backend chat routes split (P0)
- **Goal**: то же для `/v1/chats*` (4130-4793).
- **Files**: `backend/src/app.js:4130-4793`, новый `backend/src/routes/chat-routes.js`.
- **Not touch**: store.js, calls/notifications routes.
- **Steps**: identical pattern; передать `realtimeHub`, `pushGateway`, `mediaStorage` через factory args.
- **Tests**: `node --test backend/test/api.test.js`; убедиться, что регресс для chat-utils тоже идёт.
- **Rollback**: revert коммита.
- **Commit**: `chore: split backend chat routes`.

### Wave F — chat_screen.dart selection controller (P0)
- **Goal**: вынести selection-mode (`_isSelectionMode`, `_selectedMessageIds`, related `setState` вызовы) в `lib/controllers/chat_selection_controller.dart` (`ChangeNotifier`), без визуальных изменений.
- **Files**: `lib/screens/chat_screen.dart`, новый `lib/controllers/chat_selection_controller.dart`.
- **Not touch**: send/recording/timeline/attachments — это отдельные волны.
- **Steps**:
  1. Создать controller с теми же полями + методами `enter/exit/toggle`.
  2. В State хранить controller, оборачивать UI в `ListenableBuilder` где сейчас `setState`.
  3. Убрать соответствующие `setState`.
- **Tests**: `flutter test test/chat_screen_test.dart`.
- **Rollback**: revert.
- **Commit**: `chore: extract chat selection controller`.

### Wave G — home_screen sections extraction (P1)
- **Goal**: вынести `_buildHomeHeader`, `_buildHomeContentSections`, `_buildFeedContent`, `_buildFeedEmptyState`, `_buildOperationalBanner` из `home_screen.dart` в `home_screen_sections.dart` (повторить chat-pattern).
- **Files**: `lib/screens/home_screen.dart` (~1439→~700), `lib/screens/home_screen_sections.dart`.
- **Not touch**: `_loadPosts`, `_loadStories`, `_loadEvents`.
- **Steps**: переместить методы в extension, `setState` оставить через колбеки.
- **Tests**: `flutter test test/home_screen_test.dart`.
- **Commit**: `chore: split home screen sections`.

### Wave H — interactive_family_tree sections extraction (P1)
- **Goal**: дописать пустую sections-extension: вынести overlay/controls/labels.
- **Files**: `lib/widgets/interactive_family_tree.dart`, `interactive_family_tree_sections.dart`.
- **Not touch**: layout-алгоритм и gesture-handler в этой волне.
- **Tests**: `flutter test test/interactive_family_tree_test.dart`.
- **Commit**: `chore: split interactive tree controls`.

### Wave I — SnackBar helper (P2)
- **Goal**: ввести `showAppSnackBar(context, message, {isError=false})` в `lib/utils/`, мигрировать первые 5–10 мест в `chat_screen.dart`.
- **Files**: новый `lib/utils/snackbar.dart`, `chat_screen.dart` (точечно).
- **Tests**: visual + `flutter analyze`.
- **Commit**: `chore: extract snackbar helper`.

---

## 5. First 3 High-Impact Tasks

### Task 1 — Avatar pipeline unification (Wave A first slice)
- **Files**:
  - new: `lib/utils/photo_url.dart`
  - edit: `lib/widgets/family_tree_node_card.dart`, `lib/screens/relatives_screen.dart` (avatar rows), `lib/screens/blocked_users_screen.dart:140`, `lib/screens/find_relative_screen.dart:764`
- **Change intent**: ввести `normalizePhotoUrl(String?) -> String?` (trim, https-upgrade, empty→null) и `buildAvatarImageProvider(String?) -> ImageProvider?` через `CachedNetworkImageProvider`. Заменить прямые `NetworkImage(x!)` без изменения визуала и без новых стилей.
- **Helper shape**:
  ```
  String? normalizePhotoUrl(String? raw)
  ImageProvider? buildAvatarImageProvider(String? raw)
  ```
- **Tests**: новый `test/photo_url_test.dart` (trim, http→https, empty); `flutter test test/relatives_screen_test.dart test/chats_list_screen_test.dart test/find_relative_screen_test.dart`; `flutter analyze`.
- **Acceptance criteria**:
  - В тронутых файлах нет прямого `NetworkImage(...)`.
  - Все аватарки рендерятся идентично (нет визуальных diff'ов на /relatives, /chats).
  - `flutter analyze` чисто.

### Task 2 — Realtime exponential backoff
- **Files**: `lib/services/custom_api_realtime_service.dart`; `test/` — добавить или расширить `custom_api_realtime_service_test.dart`.
- **Change intent**: заменить `Timer(_reconnectDelay, …)` на функцию `_nextBackoffDelay()` с exponential 1→2→4→8→16→30 сек, jitter ±25%, сброс счётчика на успешный `_handshakeComplete`.
- **Helper shape**: внутренний `Duration _nextBackoffDelay(int failures)`, поле `int _consecutiveFailures = 0`.
- **Tests**: фейковый `WebSocketChannelFactory`, который кидает ошибку 3 раза подряд — проверить, что delay растёт; на успех сбрасывается. `flutter test test/custom_api_chat_service_test.dart` (косвенно).
- **Acceptance criteria**:
  - Не более одного reconnect-таймера в момент времени.
  - Delay монотонно растёт до cap.
  - При успешном connect счётчик сбрасывается.

### Task 3 — Backend post routes split
- **Files**: `backend/src/app.js` (вырезать блок 3000-3199), новый `backend/src/routes/post-routes.js`; обновить экспорт в `app.js`.
- **Change intent**: 1:1 копия 6 endpoint'ов (`GET /v1/posts`, `POST /v1/posts`, `DELETE /v1/posts/:postId`, `POST /v1/posts/:postId/like`, `GET /v1/posts/:postId/comments`, `POST /v1/posts/:postId/comments`, `DELETE …/comments/:commentId`) в `registerPostRoutes({app, store, requireAuth, mediaStorage, realtimeHub, pushGateway, ensureReady})`.
- **Helper shape**: повторить точную сигнатуру `registerProfileRoutes` из `backend/src/routes/profile-routes.js`.
- **Tests**: `node --test backend/test/api.test.js backend/test/app-media-routes.test.js`. Локальный smoke `curl http://127.0.0.1:PORT/v1/posts` с auth header.
- **Acceptance criteria**:
  - `app.js` теряет ~200 строк.
  - Все node-тесты проходят без правок.
  - Никаких изменений API-контракта (response payload идентичен).

---

## 6. Test Matrix

- **Flutter analyze**: `flutter analyze` — после каждой волны.
- **Flutter unit/widget tests** по затронутой зоне:
  - chat: `flutter test test/chat_screen_test.dart test/custom_api_chat_service_test.dart`
  - home: `test/home_screen_test.dart`
  - tree widget: `test/interactive_family_tree_test.dart`
  - relatives: `test/relatives_screen_test.dart test/relative_details_screen_test.dart`
  - realtime: `test/custom_api_chat_service_test.dart` + новый realtime-тест
  - router: `test/app_router_tree_route_test.dart test/deep_link_handler_test.dart`
- **Backend node tests** (после splits):
  ```
  node --test backend/test/api.test.js backend/test/app-media-routes.test.js \
              backend/test/chat-utils.test.js backend/test/postgres-store.test.js
  ```
- **Web smoke**: `flutter build web` → `python -m http.server 3000 --bind 127.0.0.1` из `build/web` → ручной заход в /, /chats, /tree, /profile + Playwright `tool/prod_route_smoke.mjs` против локального адреса (если доступно).
- **Android smoke**: только если меняется `lib/services/rustore_service.dart`, `app_startup_service.dart`, `call_coordinator_service.dart` или `kIsWeb`-ветвления — не нужно для P0/P1 волн A–F кроме F.
- **CI**: после backend split — убедиться, что `.github/workflows/backend-deploy.yml` runs locally (steps `npm ci`, `node --test …`).
- **Никогда** не запускать прод-смоук случайно; не менять `.last_release_id`.

---

## 7. Risks / Unknowns

- **PostgresStore vs FileStore overlap**: `PostgresStore extends FileStore` — перед волнами с backend проверить, что наследуемые методы не падают в `fs.writeFile` пути. Не предполагать, читать [`backend/src/postgres-store.js:131+`](backend/src/postgres-store.js).
- **`cached_network_image` на web**: на некоторых хедлесс-CORS фотках может не кэшировать; перед Wave B проверить, что прод выдаёт корректные `cache-control` для `/media/*`. Если нет — нужен fallback `Image.network`.
- **`chat_screen.dart` controllers extraction (Wave F)**: 91 `setState` означает скрытые перекрёстные зависимости. Не пытаться вытащить всё сразу. Только selection-mode на первой итерации.
- **Backend route splits**: не менять сигнатуру и порядок middleware (`requireAuth`, rate-limit hooks) — это меняет contract для клиента.
- **Realtime backoff**: убедиться, что есть путь для немедленного reconnect при ручном `connect()` (например, при возврате из background) — иначе UX «чат молчит ещё минуту».
- **Smoke pipeline (`prod_route_smoke.mjs`) запускается даже на правки самого smoke**: если волна I/B затронет UI, smoke должен пройти; если он начнёт зависеть от новых селекторов — обновлять synchronously.
- **Не менять calls/voice пути** ([`call_coordinator_service.dart`](lib/services/call_coordinator_service.dart), `call_runtime_host.dart`, `routes /v1/calls/*`) — они выходят за scope MVP и работают по своему ритму.
- **Russian copy**: при любом trivial-change UI оставлять русские тексты как есть; не «улучшать» — UI design отдельно прорабатывается.
- **CI secrets**: workflow'ы используют `sshpass`, не трогать без явного согласия; никаких изменений в `.github/workflows/*` без user-явного запроса.
- **Untracked `.claude/`** в `git status` — не коммитить.
