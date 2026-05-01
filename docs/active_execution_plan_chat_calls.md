# Active Execution Plan — Chat / Calls

## Current Status

- Current wave: **Chat/calls plan complete through V10 + Android device smoke**
- Parallel tree-track boundary: do not touch `docs/active_execution_plan.md`, `family_person.dart`, `family_tree_service`, identity/circle routes, or `relative_details_screen.dart` unless a chat/call task explicitly requires it.

## Execution Checklist

- [x] **Plan intake**
  - [x] user pasted the chat/calls plan
  - [x] plan reviewed for phase order and tree-track boundaries
  - [x] top-level tracker added for chat/calls execution
- [x] **PHASE 1 — Скорость и отзывчивость**
  - [x] **C1 — Pagination на messages endpoint**
    - [x] backend route supports `limit`, `before`, `after`
    - [x] store pagination is stable by `timestamp + id`
    - [x] Flutter service exposes `fetchMessagesPage`
    - [x] backend and Flutter tests cover pagination
    - [x] verification run
  - [x] **C2 — Realtime broadcast: message lifecycle**
    - [x] backend exposes `realtimeHub.publishToChat`
    - [x] backend broadcasts `chat.message.created/updated/deleted`
    - [x] backend broadcasts `chat.updated` and `chat.unread.changed`
    - [x] Flutter merges own send response without a history refetch
    - [x] Flutter applies realtime total unread updates
    - [x] backend and Flutter tests cover realtime lifecycle updates
  - [x] **C3 — Убрать polling, переключиться на event-driven**
    - [x] regular overview/unread timers removed while realtime is connected
    - [x] `chat.updated` drives preview refresh
    - [x] `chat.unread.changed` patches unread count without full refetch
    - [x] realtime disconnect enables low-rate fallback polling
    - [x] app resume triggers one overview refresh from the chats list
  - [x] **C4 — Hive-кэш сообщений**
    - [x] `ChatMessageCache` abstraction added
    - [x] Hive-backed `chat_messages_v1` cache added
    - [x] chat stream emits cached messages before network refresh
    - [x] cached streams fetch newer delta with `after=<newestCachedMessageId>`
    - [x] realtime create/update/delete/read events update cache
    - [x] `fetchMessagesPage(before/after)` merges loaded pages into cache
    - [x] app startup injects cache into `CustomApiChatService`
    - [x] tests cover cache behavior and instant cached stream hydrate
  - [x] **C5 — Optimistic send в сервисе**
    - [x] `ChatSendQueue` service added
    - [x] queue state moved out of `chat_screen.dart`
    - [x] optimistic messages render from queue state
    - [x] send uses `clientMessageId` from queue
    - [x] retry and remove are handled by queue
    - [x] queue persists failed/pending entries in Hive box `chat_send_queue_v1`
    - [x] remote messages with matching `clientMessageId` confirm and remove pending queue item
    - [x] tests cover enqueue, retry, persistence, confirmation and screen behavior
- [x] **PHASE 2 — UI чистка и базовая настраиваемость звонков**
  - [x] **C6a — Selection controller**
    - [x] `ChatSelectionController` exists
    - [x] screen uses controller for remote and outgoing selection
    - [x] copy/forward/delete flow reads controller state
    - [x] unit test passed
  - [x] **C6b — Attachments controller**
    - [x] `ChatAttachmentsController` added
    - [x] selected attachment state moved out of `chat_screen.dart`
    - [x] composer preview reads controller state
    - [x] add/replace/remove/clear limits covered by unit tests
    - [x] `chat_screen_test.dart` passed after extraction
  - [x] **C6c — Search controller**
    - [x] `ChatSearchController` exists
    - [x] screen uses controller for search mode and local filtering
    - [x] unit test passed
  - [x] **C7 — Cached chat thumbnails + avatars**
    - [x] avatar helpers use `CachedNetworkImageProvider`
    - [x] chat app bar, chat list and forward selector avatars use cached providers
    - [x] remote chat attachments and gallery previews use `CachedNetworkImage`
    - [x] call screen avatar uses the shared cached provider and falls back on invalid URLs
    - [x] C7 verification run
  - [x] **V1 — Audio routing UI**
    - [x] `AudioRouteService` added on top of LiveKit audio outputs
    - [x] Android/mobile fallback routes cover speaker and earpiece
    - [x] Bluetooth and wired outputs appear when LiveKit/WebRTC reports them
    - [x] `CallCoordinatorService` attaches the route service to the active room
    - [x] `CallScreen` exposes an audio output button and picker sheet
    - [x] V1 verification run
  - [x] **V2 — Camera switch + mirror**
    - [x] `CallCoordinatorService` tracks current `CameraPosition`
    - [x] coordinator switches the active LiveKit camera track front/back
    - [x] local preview mirrors front camera and disables mirror for back camera
    - [x] `CallScreen` exposes the camera switch button in active video calls
    - [x] V2 verification run
  - [x] **V3 — Device pickers**
    - [x] `CallCoordinatorService` enumerates LiveKit audio/video input devices
    - [x] coordinator can select active microphone and camera devices
    - [x] `CallDevicePickerSheet` added with microphone and camera sections
    - [x] `CallScreen` opens the device picker from active call controls
    - [x] V3 verification run
- [x] **PHASE 3 — Telegram-parity фичи чата**
  - [x] **C8 — Server-side reactions**
    - [x] backend stores `messageReactions` separately from message text/media
    - [x] `POST /v1/chats/:chatId/messages/:messageId/reactions` toggles reactions
    - [x] message history returns aggregated `reactions: [{emoji, userIds, count}]`
    - [x] realtime publishes `message.reaction.changed`
    - [x] Flutter `ChatMessage` carries server-synced reactions through cache/streams
    - [x] local `chat_reaction_store.dart` removed from `ChatScreen`
    - [x] reaction chips and quick reaction picker call the chat service toggle
    - [x] C8 verification run
  - [x] **C9 — Read receipts + delivered**
    - [x] backend messages track `deliveredTo[]` and `readBy[]`
    - [x] WebSocket delivery marks online recipients as delivered
    - [x] `markChatAsRead` records per-user read receipts and publishes `message.read`
    - [x] message history returns delivery/read receipt arrays
    - [x] Flutter `ChatMessage` carries delivery/read receipt arrays through cache/streams
    - [x] realtime applies `message.delivered` and `message.read` updates
    - [x] chat bubble footer shows sent/delivered/read receipt states
    - [x] C9 verification run
  - [x] **C10 — Voice messages with waveform**
    - [x] `ChatAttachment` carries normalized `waveform` metadata
    - [x] recording controller samples mic amplitude for local voice previews
    - [x] upload pipeline stores voice notes under `chat-voice/<userId>`
    - [x] uploaded voice notes include `durationMs`, `presentation: voice_note`, and waveform bins
    - [x] backend preserves and caps waveform arrays in message attachments
    - [x] voice player renders a tappable waveform scrubber
    - [x] voice player supports 1x / 1.5x / 2x playback speed
    - [x] C10 verification run
  - [x] **C11 — Server-side full-text search**
    - [x] `GET /v1/chats/search?q=...&chatId=...` endpoint added
    - [x] file store searches visible participant messages with scoped chat filtering
    - [x] Postgres store uses SQL FTS via `to_tsvector`, `plainto_tsquery`, and `ts_headline`
    - [x] Postgres bootstrap creates a GIN expression index for message FTS
    - [x] Flutter chat service exposes `searchMessages`
    - [x] in-chat search uses debounced server results with local fallback
    - [x] C11 verification run
  - [x] **C12 — Drafts sync**
    - [x] backend stores per-user `chatDrafts`
    - [x] `GET /v1/chats/drafts` lists current user's drafts
    - [x] `GET/PUT/DELETE /v1/chats/:chatId/draft` sync one chat draft
    - [x] realtime publishes `chat.draft.updated` to the current user
    - [x] Flutter `HybridChatDraftStore` merges local and remote drafts
    - [x] app startup registers the hybrid draft store
    - [x] chat screen applies remote draft updates when composer is not focused
    - [x] chats list updates draft previews from realtime events
    - [x] C12 verification run
  - [x] **C13 — Pinned messages sync + jump-to-reply**
    - [x] backend stores one pinned message per chat
    - [x] `GET/POST/DELETE` pin endpoints added
    - [x] realtime publishes `chat.pin.updated`
    - [x] Flutter `HybridChatPinStore` merges local and remote pins
    - [x] app startup registers the hybrid pin store
    - [x] chat screen applies remote pin updates
    - [x] reply quote tap jumps to the original loaded message
    - [x] C13 verification run
- [x] **PHASE 4 — Звонки: качество и групповые**
  - [x] **V4 — PiP / mini-window**
    - [x] `CallRuntimeHost` shows active calls as a floating mini-window after minimize
    - [x] mini-window is draggable and tap-to-restore
    - [x] mini-window exposes basic mic/camera/hangup controls
    - [x] Android system PiP method channel added
    - [x] V4 verification run
  - [x] **V5 — Connection quality indicator + reconnect UX**
    - [x] `CallCoordinatorService` tracks LiveKit local/remote connection quality
    - [x] room reconnect/reconnected events drive reconnect banner state
    - [x] local mic/camera state is resumed after reconnect
    - [x] `CallScreen` shows connection quality ring/badge and reconnect banner
    - [x] mini-window reflects reconnect/quality state
    - [x] V5 verification run
  - [x] **V6 — Settings: default mic/camera/output, ringtone, vibration**
    - [x] `CallPreferences` added with Hive-backed persistence
    - [x] startup registers `CallPreferences` and passes it to `CallCoordinatorService`
    - [x] coordinator applies saved mic/camera/output defaults when joining a room
    - [x] incoming-call vibration reads saved preferences
    - [x] settings screen exposes mic/camera/output/ringtone/vibration controls
    - [x] V6 verification run
  - [x] **V7 — In-call chat panel**
    - [x] lightweight `InCallChatSheet` added
    - [x] call screen exposes chat button during active calls
    - [x] sheet reads current chat stream and marks it read
    - [x] sheet sends text through `sendMessageToChat`
    - [x] V7 verification run
  - [x] **V8 — Push reliability для incoming calls**
    - [x] backend WebPush payload marks incoming calls as high urgency with 30s TTL
    - [x] backend RuStore data payload carries high priority, time-sensitive, TTL and collapse metadata
    - [x] web push worker preserves time-sensitive notification options
    - [x] `IncomingCallWatcher` added for reconnect, resume and background fallback active-call hydration
    - [x] startup eagerly registers call coordinator and watcher so incoming-call recovery is active
    - [x] V8 verification run
  - [x] **V9 — Group calls**
    - [x] backend creates group call invites for all group/branch participants
    - [x] optional `participantIds` are normalized, include the initiator and must stay inside the chat
    - [x] LiveKit rooms use group-sized `maxParticipants`
    - [x] LiveKit sessions are created for every call participant after accept
    - [x] incoming-call checks treat every non-initiator participant as a recipient
    - [x] group chats expose audio/video call actions in the app bar
    - [x] call screen shows group waiting/status UX and supports multi-remote video layout
    - [x] group `participant_left` webhook keeps the call active while other participants remain connected
    - [x] V9 verification run
- [x] **PHASE 5 — Native Android incoming**
  - [x] **V10 — ConnectionService на Android**
    - [x] Android manifest declares `MANAGE_OWN_CALLS` and Telecom `ConnectionService`
    - [x] native Kotlin `RodnyaConnectionService` registers a self-managed `PhoneAccount`
    - [x] native incoming call bridge calls `TelecomManager.addNewIncomingCall`
    - [x] system accept opens `MainActivity` with a pending call action
    - [x] Dart `AndroidIncomingCallService` wraps the `rodnya/android_calls` channel
    - [x] incoming call notifications prefer Android Telecom and fall back to local full-screen notification
    - [x] `CallCoordinatorService` consumes pending Android accept/reject/disconnect actions through existing backend call APIs
    - [x] Sony XA2 smoke confirms registered self-managed phone account
    - [x] V10 verification run
- [x] **POST-V10 — Real-device chat/call smoke**
  - [x] signed dev release installed on emulator `emulator-5554`
  - [x] signed dev release installed on Sony XA2 `CQ30001TUR`
  - [x] both test accounts opened the same 1:1 chat after reinstall without clearing data
  - [x] 1:1 chat message `qa_after_fix_20260501` delivered to Sony and showed read receipt on emulator
  - [x] audio call started from emulator, accepted on Sony and showed active call controls
  - [x] audio remote hangup from emulator cleared Sony back to chat
  - [x] video call started from emulator, accepted on Sony and showed video call controls
  - [x] video controls present on Sony: mic, camera, camera switch, audio output, device picker and in-call chat
  - [x] video hangup from Sony cleared Sony immediately and emulator after LiveKit/recovery delay
  - [x] stale same-call terminal snapshots no longer get ignored by `CallCoordinatorService`
  - [x] active call recovery polling added for missed terminal call state

## Current Execution Log

- [x] 2026-04-30 — Created separate chat/calls execution track.
- [x] 2026-04-30 — Plan pasted and converted into a trackable checklist.
- [x] 2026-04-30 — Wave C1 completed: paginated message history on backend and `CustomApiChatService.fetchMessagesPage` on Flutter.
- [x] 2026-04-30 — Wave C2 completed: chat lifecycle realtime broadcasts, chat/unread events, and no-refetch own-send merge in Flutter.
- [x] 2026-04-30 — Wave C3 completed: event-driven chat overview/unread updates with reconnect fallback and resume refresh.
- [x] 2026-04-30 — Wave C4 completed: Hive-backed message cache for instant chat open, realtime cache updates, and paged cache merge.
- [x] 2026-04-30 — Wave C5 completed: optimistic send queue moved into `ChatSendQueue`, with retry, Hive persistence and remote confirmation by `clientMessageId`.
- [x] 2026-04-30 — Wave C6a verified complete: selection state is already extracted to `ChatSelectionController` and covered by tests.
- [x] 2026-04-30 — Wave C6c verified complete: search state is already extracted to `ChatSearchController` and covered by tests.
- [x] 2026-04-30 — Wave C6b completed: attachment selection/preview state extracted to `ChatAttachmentsController`.
- [x] 2026-04-30 — Wave C7 completed: chat/call avatars and chat attachment thumbnails use cached image loading with fallbacks.
- [x] 2026-04-30 — Wave V1 completed: LiveKit-backed audio output route service and in-call picker UI.
- [x] 2026-04-30 — Wave V2 completed: camera position switching and explicit local preview mirroring.
- [x] 2026-04-30 — Wave V3 completed: LiveKit microphone/camera device enumeration, selection and in-call picker UI.
- [x] 2026-04-30 — Wave C8 completed: server-synced message reactions with realtime and Flutter UI wiring.
- [x] 2026-04-30 — Wave C9 completed: server-backed delivered/read receipts with realtime updates and Flutter bubble status UI.
- [x] 2026-04-30 — C9 verification unblocked by compile-only compatibility fixes in `identity_review_screen.dart` and `relative_details_screen_sections.dart`.
- [x] 2026-04-30 — Wave C10 completed: voice messages now carry waveform metadata, upload as voice notes, and render with waveform scrubbing plus playback speed control.
- [x] 2026-04-30 — Wave C11 completed: server-side message search endpoint, Postgres FTS path, Flutter service API, and in-chat server search fallback.
- [x] 2026-04-30 — Wave C12 completed: backend-synced personal chat drafts with realtime updates and hybrid local/remote Flutter store.
- [x] 2026-04-30 — Wave C13 completed: server-synced pinned messages with realtime, hybrid Flutter pin store, and jump-to-reply.
- [x] 2026-05-01 — Wave V4 completed: active calls minimize into a draggable mini-window, restore full screen on tap, and expose Android PiP best-effort entry.
- [x] 2026-05-01 — Wave V5 completed: LiveKit connection quality is visible in calls and reconnect UX now explains recovery with auto media resume.
- [x] 2026-05-01 — Wave V6 completed: call defaults and incoming behavior settings are persisted and wired into startup/coordinator.
- [x] 2026-05-01 — Wave V7 completed: active calls now have a lightweight in-call chat panel with read and send support.
- [x] 2026-05-01 — Wave V8 completed: incoming call push is marked high-priority/time-sensitive and app-side recovery now polls/resyncs after background or realtime gaps.
- [x] 2026-05-01 — Sony XA2 smoke: installed signed dev release, launched `com.ahjkuio.rodnya_family_app.dev`, MainActivity focused with no FATAL/ANR.
- [x] 2026-05-01 — Wave V9 completed: group chats can start group calls, backend creates per-participant LiveKit sessions, and group calls survive one participant leaving while others remain connected.
- [x] 2026-05-01 — Wave V10 completed: Android Telecom ConnectionService baseline added for native incoming calls, with Dart channel wiring and Sony XA2 phone-account registration smoke.
- [x] 2026-05-01 — Android device smoke: emulator + Sony XA2 chat delivery passed with `qa_after_fix_20260501`, read receipt visible on emulator.
- [x] 2026-05-01 — Android device smoke: audio call emulator -> Sony passed; remote hangup from emulator closed Sony back to chat.
- [x] 2026-05-01 — Android device smoke: video call emulator -> Sony passed; Sony showed active video controls, and remote hangup from Sony eventually cleared emulator mini-call after recovery.
- [x] 2026-05-01 — Fixed stale active-call UI by accepting terminal same-call snapshots and polling active calls for missed terminal state.

## Verification Notes

- [x] `dart format lib/services/custom_api_chat_service.dart lib/services/chat_message_cache.dart lib/services/app_startup_service.dart lib/models/chat_message.dart test/custom_api_chat_service_test.dart test/chat_message_cache_test.dart`
- [x] `flutter test test/custom_api_chat_service_test.dart`
- [x] `flutter test test/chat_message_cache_test.dart`
- [x] `dart analyze lib/services/custom_api_chat_service.dart lib/services/chat_message_cache.dart lib/services/app_startup_service.dart lib/models/chat_message.dart test/custom_api_chat_service_test.dart test/chat_message_cache_test.dart`
- [x] `flutter test test/chat_send_queue_test.dart`
- [x] `flutter test test/chat_screen_test.dart`
- [x] `dart analyze lib/services/chat_send_queue.dart lib/screens/chat_screen.dart lib/screens/chat_screen_state_models.dart lib/services/app_startup_service.dart test/chat_send_queue_test.dart`
- [x] Full `flutter analyze`
- [x] `flutter test test/chat_selection_controller_test.dart`
- [x] `flutter test test/chat_search_controller_test.dart`
- [x] `flutter test test/chat_attachments_controller_test.dart`
- [x] `flutter test test/chat_screen_test.dart` after C6b extraction
- [x] `dart format lib/screens/call_screen.dart test/call_screen_test.dart`
- [x] `flutter test test/photo_url_test.dart test/call_screen_test.dart test/chat_screen_test.dart test/chats_list_screen_test.dart`
- [x] Full `flutter analyze` after C7
- [x] `dart format lib/services/audio_route_service.dart lib/services/call_coordinator_service.dart lib/services/app_startup_service.dart lib/screens/call_screen.dart test/audio_route_service_test.dart test/call_screen_test.dart`
- [x] `flutter test test/audio_route_service_test.dart test/call_screen_test.dart test/call_coordinator_service_test.dart`
- [x] Full `flutter analyze` after V1
- [x] `dart format lib/services/call_coordinator_service.dart lib/screens/call_screen.dart test/call_screen_test.dart`
- [x] `flutter test test/call_screen_test.dart test/call_coordinator_service_test.dart`
- [x] Full `flutter analyze` after V2
- [x] `dart format lib/services/call_coordinator_service.dart lib/screens/call_screen.dart lib/widgets/call_device_picker_sheet.dart test/call_screen_test.dart test/call_coordinator_service_test.dart`
- [x] `flutter test test/call_screen_test.dart test/call_coordinator_service_test.dart`
- [x] Full `flutter analyze` after V3
- [x] `dart format lib/models/chat_message.dart lib/models/chat_message.g.dart lib/backend/interfaces/chat_service_interface.dart lib/backend/pending_backend_adapters.dart lib/services/custom_api_realtime_service.dart lib/services/custom_api_chat_service.dart lib/screens/chat_screen.dart test/chat_screen_test.dart test/custom_api_chat_service_test.dart test/chats_list_screen_test.dart test/relatives_screen_test.dart test/tree_view_screen_test.dart`
- [x] `flutter test test/custom_api_chat_service_test.dart test/chat_screen_test.dart`
- [x] `node --test backend/test/api.test.js --test-name-pattern "chat message reactions"` *(Node ran the full api test file; 72 passed)*
- [x] Full `flutter analyze` after C8
- [x] `flutter build web`
- [x] `flutter build web --no-wasm-dry-run` after first smoke found missing `assets/FontManifest.json`
- [x] Playwright smoke against local `build/web`: loaded `#/login?from=/`, Flutter root ready, no console errors
- [x] `dart format lib/models/chat_message.dart lib/models/chat_message.g.dart lib/services/custom_api_chat_service.dart lib/services/custom_api_realtime_service.dart lib/screens/chat_screen.dart test/custom_api_chat_service_test.dart test/chat_screen_test.dart`
- [x] `flutter test test/custom_api_chat_service_test.dart test/chat_screen_test.dart` after C9
- [x] `node --test backend/test/api.test.js --test-name-pattern "presence, typing and read-state"` *(Node ran the full api test file; 72 passed)*
- [x] `dart format lib/screens/identity_review_screen.dart lib/screens/relative_details_screen_sections.dart` *(compile-only compatibility while preserving tree-track behavior)*
- [x] Full `flutter analyze` after C9 *(passed with 2 info warnings about deprecated `DropdownButtonFormField.value`)*
- [x] `flutter build web --no-wasm-dry-run` after C9
- [x] Playwright smoke against local `build/web`: loaded `#/login?from=/`, Flutter root ready, no console/page errors, no local 4xx responses
- [x] `dart format lib/utils/voice_waveform.dart lib/models/chat_attachment.dart lib/controllers/chat_recording_controller.dart lib/services/custom_api_chat_service.dart lib/screens/chat_screen.dart lib/screens/chat_screen_supporting_widgets.dart test/voice_waveform_test.dart test/custom_api_chat_service_test.dart`
- [x] `flutter test test/voice_waveform_test.dart test/custom_api_chat_service_test.dart`
- [x] `flutter test test/chat_screen_test.dart`
- [x] `node --test backend/test/chat-utils.test.js backend/test/api.test.js`
- [x] Full `flutter analyze` after C10
- [x] `flutter build web --no-wasm-dry-run` as compile check after C10
- [x] `flutter build web` for real local web smoke after C10
- [x] Playwright smoke against local `build/web`: loaded `#/login?from=/`, Flutter root ready, no console/page errors, no local 4xx responses
- [x] `dart format lib/models/chat_message_search_result.dart lib/backend/interfaces/chat_service_interface.dart lib/services/custom_api_chat_service.dart lib/screens/chat_screen.dart lib/backend/pending_backend_adapters.dart test/custom_api_chat_service_test.dart test/chat_screen_test.dart test/chats_list_screen_test.dart test/relatives_screen_test.dart test/tree_view_screen_test.dart`
- [x] `flutter test test/chat_screen_test.dart test/custom_api_chat_service_test.dart`
- [x] `node --test backend/test/postgres-store.test.js`
- [x] `node --test backend/test/api.test.js --test-name-pattern "chat message search"` *(Node ran the full api test file; 75 passed)*
- [x] Full `flutter analyze` after C11
- [x] `flutter build web` after C11
- [x] Playwright smoke against local `build/web`: loaded `#/login?from=/`, Flutter root ready, no console/page errors, no local 4xx responses
- [x] `dart format lib/services/chat_draft_store.dart lib/services/custom_api_chat_service.dart lib/services/custom_api_realtime_service.dart lib/screens/chat_screen.dart lib/screens/chats_list_screen.dart lib/services/app_startup_service.dart test/custom_api_chat_service_test.dart test/chat_draft_store_test.dart`
- [x] `flutter test test/chat_draft_store_test.dart test/custom_api_chat_service_test.dart test/chat_screen_test.dart test/chats_list_screen_test.dart`
- [x] `node --test backend/test/api.test.js --test-name-pattern "chat drafts"` *(Node ran the full api test file; 76 passed)*
- [x] `node --test backend/test/migration-utils.test.js`
- [x] `node --check backend/src/store.js`
- [x] `node --check backend/src/routes/chat-routes.js`
- [x] Full `flutter analyze` after C12
- [x] `flutter build web` after C12
- [x] Playwright smoke against local `build/web`: loaded `#/login?from=/`, Flutter root ready, no console/page errors, no local 4xx responses
- [x] `dart format lib/services/chat_pin_store.dart lib/services/custom_api_chat_service.dart lib/services/custom_api_realtime_service.dart lib/services/app_startup_service.dart lib/screens/chat_screen.dart test/chat_pin_store_test.dart test/custom_api_chat_service_test.dart test/chat_screen_test.dart`
- [x] `flutter test test/chat_pin_store_test.dart test/custom_api_chat_service_test.dart test/chat_screen_test.dart`
- [x] `node --check backend/src/store.js`
- [x] `node --check backend/src/routes/chat-routes.js`
- [x] `node --check backend/src/migration-utils.js`
- [x] `node --test backend/test/api.test.js --test-name-pattern "chat pinned"` *(Node ran the full api test file; 77 passed)*
- [x] `node --test backend/test/migration-utils.test.js`
- [x] Full `flutter analyze` after C13
- [x] `flutter build web` after C13
- [x] Playwright smoke against local `build/web`: loaded `#/login?from=/`, Flutter root ready, no console/page errors, no local 4xx/5xx responses
- [x] `dart format lib/services/call_pip_service.dart lib/widgets/call_floating_pip.dart lib/widgets/call_runtime_host.dart lib/screens/call_screen.dart test/call_runtime_host_test.dart test/call_screen_test.dart`
- [x] `flutter test test/call_runtime_host_test.dart test/call_screen_test.dart test/call_coordinator_service_test.dart`
- [x] `dart analyze lib/services/call_pip_service.dart lib/widgets/call_floating_pip.dart lib/widgets/call_runtime_host.dart lib/screens/call_screen.dart test/call_runtime_host_test.dart test/call_screen_test.dart`
- [x] Full `flutter analyze` after V4
- [x] `flutter build web` after V4
- [x] Playwright smoke against local `build/web`: loaded `#/login?from=/`, Flutter root ready, no console/page errors, no local 4xx/5xx responses
- [x] `flutter build apk --debug --flavor dev -t lib/main.dart` after V4
- [x] `dart format lib/services/call_coordinator_service.dart lib/screens/call_screen.dart lib/widgets/call_floating_pip.dart lib/widgets/call_connection_quality_badge.dart test/call_screen_test.dart test/call_runtime_host_test.dart test/call_coordinator_service_test.dart`
- [x] `flutter test test/call_screen_test.dart test/call_runtime_host_test.dart test/call_coordinator_service_test.dart`
- [x] `dart analyze lib/services/call_coordinator_service.dart lib/screens/call_screen.dart lib/widgets/call_floating_pip.dart lib/widgets/call_connection_quality_badge.dart test/call_screen_test.dart test/call_runtime_host_test.dart test/call_coordinator_service_test.dart`
- [x] Full `flutter analyze` after V5
- [x] `flutter build web` after V5
- [x] Playwright smoke against local `build/web`: loaded `#/login?from=/`, Flutter root ready, no console/page errors, no local 4xx/5xx responses
- [x] `flutter build apk --debug --flavor dev -t lib/main.dart` after V5
- [x] `dart format lib/services/call_preferences.dart lib/services/call_coordinator_service.dart lib/services/app_startup_service.dart lib/screens/settings_screen.dart test/call_preferences_test.dart test/call_coordinator_service_test.dart test/create_edit_flows_test.dart`
- [x] `flutter test test/call_preferences_test.dart test/call_coordinator_service_test.dart test/create_edit_flows_test.dart`
- [x] `dart analyze lib/services/call_preferences.dart lib/services/call_coordinator_service.dart lib/services/app_startup_service.dart lib/screens/settings_screen.dart test/call_preferences_test.dart test/call_coordinator_service_test.dart test/create_edit_flows_test.dart`
- [x] Full `flutter analyze` after V6
- [x] `flutter build web` after V6
- [x] `flutter build web --no-wasm-dry-run` after V6 smoke caught missing `assets/FontManifest.json`
- [x] Playwright smoke against local `build/web`: loaded `#/login?from=/`, Flutter root ready, no console/page errors, no local 4xx/5xx responses
- [x] `flutter build apk --debug --flavor dev -t lib/main.dart` after V6
- [x] `dart format lib/widgets/in_call_chat_sheet.dart lib/screens/call_screen.dart test/call_screen_test.dart`
- [x] `flutter test test/call_screen_test.dart test/call_runtime_host_test.dart`
- [x] `dart analyze lib/widgets/in_call_chat_sheet.dart lib/screens/call_screen.dart test/call_screen_test.dart test/call_runtime_host_test.dart`
- [x] Full `flutter analyze` after V7
- [x] `flutter build web --no-wasm-dry-run` after V7
- [x] Playwright smoke against local `build/web`: loaded `#/login?from=/`, Flutter root ready, no console/page errors, no local 4xx/5xx responses
- [x] `flutter build apk --debug --flavor dev -t lib/main.dart` after V7
- [x] `dart format lib/services/incoming_call_watcher.dart lib/services/app_startup_service.dart test/incoming_call_watcher_test.dart`
- [x] `node --check backend/src/push-gateway.js`
- [x] `node --check backend/test/api.test.js`
- [x] `flutter test test/incoming_call_watcher_test.dart test/call_coordinator_service_test.dart` after V8
- [x] `node --test backend/test/api.test.js --test-name-pattern "incoming call push uses high-priority metadata"` *(Node ran the full api test file; 78 passed)*
- [x] `dart analyze lib/services/incoming_call_watcher.dart lib/services/app_startup_service.dart test/incoming_call_watcher_test.dart`
- [x] Full `flutter analyze` after V8
- [x] `flutter build web` after V8
- [x] Playwright smoke against local `build/web`: loaded `#/login?from=/`, Flutter root ready, no console/page errors, no local 4xx/5xx responses, push worker served
- [x] `flutter build apk --debug --flavor dev -t lib/main.dart` after V8
- [x] `dart format lib/models/call_invite.dart lib/screens/chat_screen.dart lib/screens/chat_screen_sections.dart lib/screens/call_screen.dart test/call_screen_test.dart test/chat_screen_test.dart`
- [x] `node --check backend/src/app.js`
- [x] `node --check backend/src/store.js`
- [x] `node --check backend/src/livekit-service.js`
- [x] `node --check backend/test/api.test.js`
- [x] `node --test backend/test/api.test.js --test-name-pattern "group call starts from group chat"` *(Node ran the full api test file; 79 passed)*
- [x] `flutter test test/call_screen_test.dart test/chat_screen_test.dart test/custom_api_call_service_test.dart test/call_runtime_host_test.dart test/incoming_call_watcher_test.dart`
- [x] Full `flutter analyze` after V9
- [x] `flutter build web` after V9
- [x] `flutter build web --no-wasm-dry-run` after V9 smoke caught missing `assets/FontManifest.json`
- [x] Playwright smoke against local `build/web`: loaded `#/login?from=/`, Flutter root ready, no console/page errors, no local 4xx/5xx responses
- [x] `flutter build apk --debug --flavor dev -t lib/main.dart` after V9
- [x] `flutter build apk --release --flavor dev -t lib/main.dart` after V9
- [x] Sony XA2 install/smoke after V9: `adb install -r -d build/app/outputs/flutter-apk/app-dev-release.apk`, app launched and focused MainActivity, no FATAL/ANR in startup logcat
- [x] `dart format lib/services/android_incoming_call_service.dart lib/services/app_startup_service.dart lib/services/call_coordinator_service.dart lib/services/custom_api_notification_service.dart lib/widgets/call_runtime_host.dart test/android_incoming_call_service_test.dart test/call_coordinator_service_test.dart`
- [x] `flutter test test/android_incoming_call_service_test.dart test/call_coordinator_service_test.dart test/custom_api_notification_service_test.dart`
- [x] Full `flutter analyze` after V10
- [x] `flutter build apk --debug --flavor dev -t lib/main.dart` after V10
- [x] `flutter build web --no-wasm-dry-run` after V10
- [x] Playwright smoke against local `build/web`: loaded `#/login?from=/`, Flutter root ready, no console/page errors, no local 4xx/5xx responses
- [x] `flutter build apk --release --flavor dev -t lib/main.dart` after V10
- [x] Sony XA2 install/smoke after V10: signed dev APK installed, MainActivity focused, no FATAL/ANR, `dumpsys telecom` shows `RodnyaConnectionService` self-managed phone account
- [x] `dart format lib/services/call_coordinator_service.dart test/call_coordinator_service_test.dart`
- [x] `flutter test test/call_coordinator_service_test.dart`
- [x] `flutter test test/call_runtime_host_test.dart test/call_screen_test.dart test/call_coordinator_service_test.dart`
- [x] Full `flutter analyze` after active-call recovery fix
- [x] `flutter build apk --debug --flavor dev -t lib/main.dart` after active-call recovery fix
- [x] `flutter build apk --release --flavor dev -t lib/main.dart` after active-call recovery fix
- [x] Emulator + Sony XA2 install/smoke after active-call recovery fix: signed dev APK installed on both devices, chat delivery/read receipt passed, audio call remote hangup passed, video call connected and remote hangup eventually cleared the other side

---

## Incoming Plan

Чаты и звонки — Telegram-parity план
Целевая архитектура
Чаты:

Local-first: открыл чат → мгновенно из локального Hive-кэша → фоном подтягиваем дельту.
Realtime-driven: сервер пушит message.created/.updated/.deleted/.reaction.changed/.read. Polling выключаем.
Пагинация: REST даёт limit + before/after, для бесконечной прокрутки.
Optimistic send в сервисе: queue с retry. Экран только рендерит состояние.
chat_screen.dart распилен на контроллеры (selection / attachments / send queue / search), сам экран — тонкая View.
Звонки:

LiveKit остаётся. Расширяем UI: device pickers (mic/camera/output), audio routing, PiP, in-call chat, индикатор качества.
Group calls — отдельная ветка после стабилизации 1:1.
Полноэкранный нативный incoming на Android через ConnectionService — последняя фаза.
Координация с дерево-веткой
Безопасно: чат/звонок-трек не трогает family_person.dart, family_tree_service, новые circle/identity routes, relative_details_screen.dart.
Точки пересечения (только add-only diff'ы):

lib/services/app_startup_service.dart — DI новых сервисов (cache, send-queue, audio-router).
backend/src/realtime-hub.js — расширение типов event'ов.
backend/src/app.js — только регистрация новых routes (не общие места).
PHASE 1 — Скорость и отзывчивость (топ pain-points)
Wave C1 — Pagination на messages endpoint
Goal: открытие большого чата перестаёт быть O(N).
Files: backend/src/routes/chat-routes.js:345, backend/src/store.js (метод listChatMessages), lib/services/custom_api_chat_service.dart:926 (_fetchMessages).
Не трогать: chat_screen.dart, send-pipeline, store.js outside listChatMessages.
Steps:
Backend: GET /v1/chats/:chatId/messages?limit=50&before=<msgId>&after=<msgId>. Default limit=50, max 200. Возвращать {messages, hasMore}.
store.listChatMessages(chatId, {limit, beforeId, afterId}) — слайс по createdAt+id сортировке.
Postgres: индекс (chatId, createdAt DESC, id) если нет.
Flutter сервис: fetchMessagesPage(chatId, {limit, beforeId, afterId}). Текущий _fetchMessages оставить как fetchInitialPage.
Старые клиенты без параметров получают последние 100 — обратная совместимость.
Tests: node --test backend/test/api.test.js + новый тест pagination в backend/test/. flutter test test/custom_api_chat_service_test.dart.
Rollback: revert.
Commit: feat: paginate chat messages endpoint
Wave C2 — Realtime broadcast: message lifecycle
Goal: сервер пушит message.created, .updated, .deleted всем участникам чата. Клиент не делает refetch после своего же send.
Files: backend/src/routes/chat-routes.js, backend/src/realtime-hub.js, lib/services/custom_api_realtime_service.dart, lib/services/custom_api_chat_service.dart.
Не трогать: chat_screen.dart, polling (его уберём в C3).
Steps:
В POST/PATCH/DELETE messages добавить realtimeHub.publishToChat(chatId, {type: 'message.created', message}).
realtime-hub.js — метод publishToChat(chatId, payload): рассылка по participantIds.
Flutter: в _ensureMessageStream подписаться на message.created/.updated/.deleted для этого chatId и обновлять stream без HTTP-refetch.
Сервер также шлёт chat.updated (для preview list) и chat.unread.changed (для счётчика).
Tests: backend WebSocket integration test (мок-клиент); flutter test test/custom_api_chat_service_test.dart.
Rollback: revert.
Commit: feat: broadcast chat message lifecycle over realtime
Wave C3 — Убрать polling, переключиться на event-driven
Goal: убить Timer.periodic(3 сек) для chat previews и total unread.
Files: lib/services/custom_api_chat_service.dart:491,600.
Зависимость: после C2 (нужны chat.updated и chat.unread.changed).
Steps:
Удалить _chatPreviewsTimer и _totalUnreadTimer.
Подписаться на realtime: chat.updated → _refreshChatPreviewsDebounced(), chat.unread.changed → patch счётчика без полного refetch.
Fallback: при disconnect от ws, временный low-rate poll (1 раз в 30 сек), отключается при reconnect.
App lifecycle: AppLifecycleState.resumed → один refresh().
Tests: flutter test test/custom_api_chat_service_test.dart (мок realtime).
Rollback: revert (опасности нет).
Commit: chore: drop chat polling, drive previews via realtime
Wave C4 — Hive-кэш сообщений (instant chat open)
Goal: открыл чат → видно вчерашнюю историю мгновенно → дельта догружается в фоне.
Files: новый lib/services/chat_message_cache.dart, lib/services/custom_api_chat_service.dart, lib/main.dart (Hive adapter регистрация уже есть).
Не трогать: chat_screen.dart (только потребляет stream, реагирует автоматически).
Steps:
Hive box chat_messages_v1 ключ = chatId, value = List<ChatMessage> (последние 200 сообщений). Уже есть ChatMessageAdapter в lib/models/chat_message.g.dart.
ChatMessageCache: read(chatId), write(chatId, messages), appendOne(chatId, msg), removeOne(chatId, msgId), evictOlder(chatId, keepCount).
В getMessagesStream(chatId) — сразу emit'ить кэш, потом запросить дельту after=lastCachedMsgId.
На каждый realtime-event обновлять кэш и emit'ить.
Lazy-load старого: при scroll-up — fetchMessagesPage(before=oldestCachedMsgId) + дописать в кэш.
Tests: новый test/chat_message_cache_test.dart; widget-test «открыл чат при offline → видит cached».
Rollback: revert.
Commit: feat: cache chat messages with hive for instant open
Wave C5 — Optimistic send в сервисе (а не в экране)
Goal: send-pipeline переезжает из chat_screen.dart _OutgoingMessage в ChatSendQueue. Очередь, retry, прогресс, идемпотентность по clientMessageId.
Files: новый lib/services/chat_send_queue.dart, lib/services/custom_api_chat_service.dart, lib/screens/chat_screen.dart (только удаляем local-state, подключаем queue).
Зависимость: после C2 (чтобы не было double-render через realtime + локальный state).
Steps:
ChatSendQueue — ChangeNotifier, состояние: Map<chatId, List<PendingMessage>>. Каждое pending имеет clientMessageId (UUID).
enqueue(chatId, text, attachments, replyTo) → сразу появляется в stream сообщений как pending.
Реальный POST с clientMessageId (бэкенд игнорирует дубль). При ошибке — failed + кнопка retry на сообщении.
На message.created с тем же clientMessageId — pending сменяется на confirmed.
Сохранять очередь в Hive box chat_send_queue_v1 чтобы пережить рестарт приложения.
В chat_screen.dart удалить _OutgoingMessage, _sendQueue, _sendingMessages и т.д.
Tests: новый test/chat_send_queue_test.dart (queue, retry, persistence). flutter test test/chat_screen_test.dart.
Rollback risk: средний — затрагивает hot path. Один коммит, без визуальных изменений.
Commit: feat: extract chat send queue with persistent retry
PHASE 2 — UI чистка и базовая настраиваемость звонков
Wave C6 — chat_screen.dart split (controllers)
Goal: вытащить из 7519-строчного экрана 4 контроллера. Без визуальных изменений.
Files: lib/screens/chat_screen.dart, новые lib/controllers/chat_selection_controller.dart, chat_attachments_controller.dart, chat_search_controller.dart. Существующие chat_recording_controller.dart и chat_timeline_controller.dart дополнить.
Steps (один контроллер за коммит, 3 коммита):
C6a — selection controller (multi-select, copy, delete, forward).
C6b — attachments controller (pick, upload progress, preview).
C6c — search controller (in-chat search, scroll-to-match).
Tests: flutter test test/chat_screen_test.dart после каждого.
Rollback: revert по одному.
Commit: chore: extract chat <X> controller
Wave C7 — Cached chat thumbnails + avatars
Goal: убрать Image.network / NetworkImage из чата. Из MVP-аудита Wave A+B, объединено.
Files: новый lib/utils/photo_url.dart, lib/screens/chat_screen_supporting_widgets.dart, lib/screens/chats_list_screen.dart, lib/screens/call_screen.dart:186.
Steps: buildAvatarImageProvider(url) через CachedNetworkImageProvider; _AttachmentImage поверх CachedNetworkImage с placeholder/errorBuilder.
Tests: flutter test test/chat_screen_test.dart test/chats_list_screen_test.dart.
Commit: feat: cache chat avatars and attachments
Wave V1 — Audio routing UI (Speaker / Earpiece / BT / Wired)
Goal: главная боль звонков — нет выбора динамика. Меню в call_screen.dart: динамик / наушник / Bluetooth / проводные.
Files: новый lib/services/audio_route_service.dart, lib/screens/call_screen.dart, lib/services/call_coordinator_service.dart (только integration), pubspec.yaml (+flutter_audio_manager или нативный channel).
Не трогать: livekit room logic, signaling.
Steps:
AudioRouteService — enumerateOutputs(), currentOutput, selectOutput(deviceId). Слушает изменения (BT connect/disconnect).
На Android — через AudioManager setMode/setSpeakerphoneOn/setBluetoothScoOn (MethodChannel).
На web — setSinkId на <audio> элементе LiveKit.
UI: round button «Динамик» → bottom sheet со списком и иконками. Авто-переключение на BT при подключении.
Tests: ручной + smoke на Android emulator.
Commit: feat: add audio output routing to calls
Wave V2 — Camera switch (front/back) + mirror
Goal: кнопка «перевернуть камеру» в видеозвонке.
Files: lib/screens/call_screen.dart, lib/services/call_coordinator_service.dart.
Steps:
CallCoordinatorService.switchCamera() через room.localParticipant.setCameraPosition(CameraPosition.front/back) (LiveKit умеет).
Кнопка cameraswitch_rounded рядом с camera toggle. Только если _isVideoCall && hasConnectedRoom.
Local preview зеркалится для front-камеры (ставится mirror: true в VideoTrackRenderer).
Tests: ручной emulator + camera permission test.
Commit: feat: switch front/back camera mid-call
Wave V3 — Device pickers (mic + camera) для web и Android
Goal: bottom-sheet «Источники звука и видео» — выбор конкретного микрофона и камеры.
Files: новый lib/widgets/call_device_picker_sheet.dart, lib/services/call_coordinator_service.dart (enumerateDevices, setActiveMic, setActiveCamera).
Steps:
LiveKit Flutter SDK даёт Hardware.instance.audioInputs и videoInputs.
selectDevice — пересоздаёт track с новым deviceId без drop'а звонка.
UI: settings-icon в call_screen.dart → sheet с двумя секциями.
Tests: ручной web (Chrome) + Android.
Commit: feat: pick mic and camera devices in calls
PHASE 3 — Telegram-parity фичи чата
Wave C8 — Server-side reactions
Goal: реакция пришла → видна всем участникам через realtime. Local-store chat_reaction_store.dart удаляем.
Files: backend — backend/src/store.js (новый блок: messageReactions), backend/src/routes/chat-routes.js (новые endpoint'ы), Flutter — lib/services/custom_api_chat_service.dart, lib/models/chat_message.dart (поле reactions), lib/screens/chat_screen_supporting_widgets.dart (UI bubble).
Steps:
Backend схема: MessageReaction { messageId, userId, emoji, createdAt }. Уник (messageId, userId, emoji).
POST /v1/chats/:chatId/messages/:messageId/reactions { emoji } (toggle).
GET /v1/chats/:chatId/messages возвращает reactions: [{emoji, userIds, count}] агрегированно.
Realtime: message.reaction.changed { messageId, reactions }.
Flutter: в bubble под текстом — chip'ы с эмодзи и счётчиком, тап = toggle. Long-press на сообщении — quick-react picker (как в Telegram).
Tests: backend unit + integration; flutter test test/chat_screen_test.dart.
Commit: feat: server-synced message reactions
Wave C9 — Read receipts + delivered
Goal: галочки как в Telegram (✓ отправлено, ✓✓ доставлено, ✓✓ синие = прочитано).
Files: backend — backend/src/store.js (extend message: deliveredTo[], readBy[]), backend/src/routes/chat-routes.js; Flutter — lib/models/chat_message.dart, bubble UI.
Steps:
На WebSocket-доставке сервер маркирует deliveredTo += userId и шлёт message.delivered.
На markChatAsRead — readBy += userId для всех непрочитанных + realtime message.read.
UI: одна / две галочки. Цвет — primary при прочтении.
Tests: backend test двух WS-клиентов; widget test bubble status.
Commit: feat: delivered and read receipts
Wave C10 — Voice messages with waveform
Goal: запись голосового удержанием mic-кнопки → waveform → отправка → плеер с волной и перемоткой.
Files: расширить lib/controllers/chat_recording_controller.dart, новый lib/widgets/voice_message_player.dart, lib/services/custom_api_chat_service.dart (новый attachment type voice), lib/models/chat_attachment.dart.
Steps:
Запись: record package (уже в pubspec — проверить). Формат m4a/opus. Параллельно генерировать waveform-bins (downsampled RMS) — 100 значений хватит для отображения.
Загрузка: storage path chat-voice/<userId>/<uuid>.m4a + meta {durationMs, waveform: [floats]} в attachment.metadata.
Player widget: ProgressBar + waveform отображение, ускорение 1x/1.5x/2x.
UI кнопки: mic-icon в composer; tap-and-hold для записи, swipe-up для lock, swipe-left для отмены (как в Telegram).
Tests: ручной + unit на waveform downsample.
Commit: feat: voice messages with waveform
Wave C11 — Server-side full-text search
Goal: поиск по сообщениям всех чатов и внутри чата — быстрый, через Postgres FTS.
Files: backend/src/postgres-store.js (миграция: GIN-индекс на to_tsvector('russian', text)), backend/src/routes/chat-routes.js (новый endpoint GET /v1/chats/search?q=…&chatId=…), lib/services/custom_api_chat_service.dart, lib/screens/chats_list_screen.dart (UI глобального поиска).
Steps:
Миграция: ALTER TABLE messages ADD COLUMN tsv tsvector GENERATED ALWAYS AS (to_tsvector('russian', text)) STORED; CREATE INDEX ON messages USING GIN(tsv);.
Endpoint возвращает {messageId, chatId, snippet, matchedAt} с подсветкой через ts_headline.
Поиск внутри чата уже есть как client-side в _ChatScreenState — переключить на server-side.
Tests: backend integration test; flutter test test/chat_screen_test.dart (search controller).
Commit: feat: server-side message full-text search
Wave C12 — Drafts sync
Goal: написал draft на телефоне → виден на web через 1 сек.
Files: backend — backend/src/store.js (chatDrafts: [{userId, chatId, text, updatedAt}]), routes endpoint PUT/GET /v1/chats/:chatId/draft. Flutter — lib/services/chat_draft_store.dart (превратить в hybrid local+remote), realtime event draft.updated.
Steps:
PUT debounced (700ms after typing stop).
На realtime draft.updated для текущего user в другом устройстве — обновить composer если он не в фокусе.
Tests: integration backend; manual two-device.
Commit: feat: sync chat drafts across devices
Wave C13 — Pinned messages sync + jump-to-reply
Goal: pin server-synced + при тапе на reply-preview прыгаем к оригиналу с подсветкой.
Files: backend (store.js, chat-routes.js) — новый POST /v1/chats/:chatId/messages/:messageId/pin. Flutter — lib/services/chat_pin_store.dart (hybrid), lib/screens/chat_screen.dart (банер pinned + scroll-to).
Steps:
Pin банер сверху — последнее закреплённое, тап = scroll-to.
Reply-bubble имеет onTap → ChatTimelineController.scrollToMessage(messageId), highlight 1.5 сек.
Commit: feat: server-synced pins and jump-to-reply
PHASE 4 — Звонки: качество и групповые
Wave V4 — PiP / mini-window
Goal: свернуть видеозвонок → плавающее окно поверх app/системы.
Files: lib/widgets/call_runtime_host.dart (расширить overlay), новый lib/widgets/call_floating_pip.dart. Android: floating_window или нативный PiP через MethodChannel.
Steps:
Внутри app: «свернуть» → CallRuntimeHost показывает draggable mini-card с remote video + контролы tap-to-restore.
На Android — system PiP через enterPictureInPictureMode (pip_view package или нативный). На web — фиксированный floating div.
Commit: feat: pip mini-window for ongoing calls
Wave V5 — Connection quality indicator + reconnect UX
Goal: видно качество (зелёный/жёлтый/красный) и понятно что происходит при reconnect.
Files: lib/services/call_coordinator_service.dart, lib/screens/call_screen.dart.
Steps:
Подписка на room.connectionQualityUpdated и participant.connectionQuality.
Индикатор-колечко на аватаре собеседника (зелёный/жёлтый/красный).
На reconnect — banner с прогрессом + auto-resume audio.
Commit: feat: call quality indicator and reconnect ux
Wave V6 — Settings: default mic/camera/output, ringtone, vibration
Goal: экран настроек звонков.
Files: lib/screens/settings_screen.dart (новая секция), новый lib/services/call_preferences.dart (Hive).
Steps:
Сохранять выбранные defaultMicId, defaultCameraId, defaultOutputId, ringtoneAsset, vibrationOnIncoming.
CallCoordinator подхватывает при старте звонка.
Commit: feat: call default device preferences
Wave V7 — In-call chat panel
Goal: во время звонка swipe вниз → видно текущий чат с собеседником.
Files: lib/screens/call_screen.dart, новый lib/widgets/in_call_chat_sheet.dart.
Steps: bottom sheet с упрощённой версией ChatScreen (только bubbles + composer), payload подгружается из ChatService.
Commit: feat: in-call chat panel
Wave V8 — Push reliability для incoming calls
Goal: «звонок приходит всегда, на любом устройстве». Аудит и фикс RuStore + WebPush + fallback HTTP-poll при ws-разрыве.
Files: lib/services/rustore_service.dart, backend/src/push-gateway.js, новый lib/services/incoming_call_watcher.dart.
Steps:
Audit: какие условия сейчас приводят к не-доставке (logs + manual reproductions).
Гарантировать VoIP-grade priority в push payload (high priority, time_sensitive).
Background fallback: при app в фоне без push → один HTTP-poll /v1/calls/active каждые 30 сек (только при незакрытом ws).
На реконнекте ws — сразу getActiveCall() и если есть incoming с state=ringing → подтянуть UI.
Удалить TODO в rustore_service.dart:568,652.
Commit: fix: harden incoming call delivery
Wave V9 — Group calls (data model + UI)
Goal: 3+ участника в одном звонке. Сначала аудио, потом видео.
Files: backend/src/store.js (extend Call — participantIds[] уже есть, доделать lifecycle для multi-party), backend/src/livekit-service.js (room policy для N), lib/models/call_invite.dart, lib/screens/call_screen.dart (grid layout).
Steps:
POST /v1/calls принимает participantIds: [...] для group.
Любой участник может join'нуться (LiveKit room уже мульти).
UI: grid 2x2 / 3x3, активный говорящий выделяется, swipe для switch focus.
Group calls только из group chat'а (есть кнопка в app bar).
Commit: feat: group calls baseline
PHASE 5 — Native Android incoming (отложено, но запланировано)
Wave V10 — ConnectionService на Android
Goal: входящий звонок выглядит как настоящий телефонный, работает на заблокированном экране, доступен Bluetooth-ответ через гарнитуру.
Files: android/app/src/main/kotlin/.../ConnectionServiceImpl.kt (новый), AndroidManifest.xml (permissions: MANAGE_OWN_CALLS, BIND_TELECOM_CONNECTION_SERVICE), MethodChannel в lib/services/call_coordinator_service.dart.
Steps:
Регистрация PhoneAccount.
На push с типом call.incoming → TelecomManager.addNewIncomingCall.
UI ринг приходит через стандартный Android telecom UI.
На «accept» из системного UI — открывается наш CallScreen.
На lock-screen работает за счёт того, что Telecom держит wakelock.
Tests: ручной на физ-устройстве + emulator.
Risk: высокий — нативный код, нужно тестировать на нескольких устройствах. Делать после стабилизации остального.
Commit: feat: android connectionservice for incoming calls
Тест-матрица
После каждой волны:

flutter analyze
flutter test test/<затронутая зона>
Backend node tests: node --test backend/test/api.test.js backend/test/postgres-store.test.js backend/test/chat-utils.test.js
Web smoke: открыть чат, отправить, получить, реакция, draft, поиск.
Android smoke: те же сценарии + звонок 1:1, переключение output, switch camera.
Риски и unknowns
C4 Hive cache + C5 send queue — самые большие. Делать строго один за другим, без промежуточной работы в зоне.
V8 push reliability требует логов с реальных устройств — пользователю нужно быть готовым прислать reproductions.
V10 ConnectionService — нативный код, тестировать на нескольких Android-версиях. Не делать, пока не стабилизируется V1-V9.
Group calls (V9) опираются на LiveKit room semantics — убедиться, что текущая room creation logic в backend/src/livekit-service.js поддерживает N>2 без правок.
Server-side reactions / read receipts меняют форму ChatMessage — обратная совместимость через nullable поля.
Координация с дерево-веткой: единственное место риска при merge — lib/services/app_startup_service.dart. Каждая волна добавляет регистрации в КОНЕЦ соответствующего блока.
Рекомендуемый порядок исполнения
PHASE 1: C1 → C2 → C3 → C4 → C5      (скорость и отзывчивость — топ pain)
PHASE 2: C6a → C6b → C6c → C7 → V1 → V2 → V3   (UI + базовый control звонков)
PHASE 3: C8 → C9 → C10 → C11 → C12 → C13       (Telegram-parity чата)
PHASE 4: V4 → V5 → V6 → V7 → V8 → V9            (звонки: качество и групп)
PHASE 5: V10                                    (native Android incoming)
PHASE 1 и PHASE 2 закроют 80% твоих жалоб («долгая загрузка чата», «долгая отправка», «звонки с двумя кнопками»). PHASE 3-5 — догон до полной Telegram-parity.
