# MVP web audit - 2026-04-09

Scope:
- local web build served from `build/web`
- login performed with a real account during the interactive session
- routes checked through Playwright MCP

## Critical blockers

### Production duplicate-claim blocker is closed through a targeted identity shim
- Flow: offline-card claim via `/v1/invitations/pending/process` after relation request acceptance.
- Current production state after the 2026-04-16 live verification:
  - direct smoke against the raw live backend still reproduced the old bug: relation request acceptance created an auto-person, `claimIdentityId` stayed `null`, and the tree ended at `3` persons after claim
  - a targeted sidecar `claim_merge_shim` was then enabled behind Caddy for:
    - `/v1/relation-requests/:requestId/respond`
    - `/v1/invitations/pending/process`
    - `/v1/trees/:treeId/persons`
    - `/v1/trees/:treeId/persons/:personId`
  - after that override, the same live smoke on `api.rodnya-tree.ru` returned `x-rodnya-claim-shim: 1` and `x-rodnya-identity-shim: 1`, rewired the relation back to the offline card, and the tree stayed at exactly `2` persons after claim
  - a second live smoke on a second fresh tree for the same recipient re-used the same externally visible `identityId` across both claims
- MVP impact: end users no longer hit the duplicate-person blocker in the live claim flow, and the public claim/person endpoints now expose a stable identity layer, but production still relies on a targeted runtime shim instead of a full backend rollout.

### 1. Home feed backend gap is closed on production
- Route: `/#/`
- Current production state after the 2026-04-10 deployment: `GET https://api.rodnya-tree.ru/v1/posts?treeId=...` returns `200`, and the backend feed contract is now available on the live API.
- MVP impact: the backend blocker is removed; remaining feed quality work is now mostly frontend UX and content-state handling.

### 2. Profile posts backend gap is closed on production
- Route: `/#/profile`
- Current production state after the 2026-04-10 deployment: `GET https://api.rodnya-tree.ru/v1/posts?authorId=...` returns `200`.
- MVP impact: authored posts are available in the live API; frontend presentation is now the main remaining concern.

### 3. Direct chat details endpoint mismatch
- Route reached from `/#/chats`
- Current state after client fix: direct chat view skips the non-essential details request and opens without that extra `404`.
- Backend note: the production API still appears inconsistent for some `GET /v1/chats/:chatId` requests.
- MVP impact: direct chat is more stable on web, but backend contract still needs cleanup for full parity.

### 4. Chat media now emits and serves canonical HTTPS media URLs
- Route: chat view
- Root cause: older media storage relied on local filesystem URLs and historical `http://...` records, which made the browser path brittle.
- Current production state after the 2026-04-12 storage cutover:
  - backend storage runs on `PostgreSQL + S3-compatible object storage`
  - `/v1/media/upload` returns canonical HTTPS storage URLs
  - legacy `/media/...` links still resolve through redirect to `/storage/rodnya-media/...`
- Remaining note: historical `http://...` values can still exist in old records, but the client normalization path remains in place and the backend now serves canonical HTTPS media directly.
- MVP impact: both migrated historical media and new uploads have a stable HTTPS delivery path on production.

## High-priority UX issues

### 5. Desktop layouts are materially improved, but tree view still sets the quality ceiling
- Routes: `/#/`, `/#/relatives`, `/#/chats`, `/#/profile`, `/#/notifications`, chat view
- Repo state: home now uses a denser desktop split, chats list has a structured desktop shell, profile header is card-based, relatives and notifications gained side panels, and chat view no longer stretches edge-to-edge on wide screens.
- Current repo state after the 2026-04-10 pass: tree view now uses a split desktop composition with a dedicated side control panel and bordered canvas area.
- 2026-04-20 follow-up: tree view now also has an action-first hero/status stack, compact-mode quick actions, branch/focus context and health warnings without throwing away canvas height on mobile.
- Remaining issue: the overall desktop baseline is acceptable for MVP, but tree view still deserves one more visual pass if the goal is premium polish rather than MVP readiness.
- MVP impact: web is now substantially more desktop-usable, with tree view remaining the clearest presentation gap.

### 6. Tree view uses desktop width poorly
- Route: `/#/tree/view/:treeId`
- Symptom: tree is rendered in a very large canvas with substantial dead space and weak centering behavior.
- MVP impact: the flagship feature looks less polished than the underlying data quality deserves.

### 7. Notifications content quality is improved, but grouping can go further
- Route: `/#/notifications`
- Current repo state after the 2026-04-10 pass: repeated same-day notifications now collapse visually, preview text is normalized, and the desktop side panel shows a type summary.
- MVP impact: the screen is far more scannable for MVP, though a richer timeline or server-side grouping would still be a later polish step.

## Medium-priority issues

### 8. Create-post flow now has better confidence cues
- Route: `/#/post/create`
- Current repo state after the 2026-04-10 pass: the screen now explains image limits, branch visibility, publication mode, and retry expectations, and uses a more desktop-friendly two-column layout.
- MVP impact: content creation is meaningfully closer to MVP-ready.

### 9. Remaining MVP work is now mostly quality and operational hardening
- Scope: live web + API
- Symptom: the main deployment blockers are resolved, but the product still needs deeper route-by-route QA, stronger failure UX, and more operational monitoring.
- MVP impact: the app is substantially closer to a usable MVP than to a prototype, but it still needs disciplined smoke coverage before calling it finished.

## Positive observations
- 2026-04-21 MVP freeze checkpoint on live production is now green:
  - disposable production smoke secrets are configured
  - full live route smoke passes for `login`, `home`, `tree`, `relatives`, `relative-details`, `chats`, `chat-view`, `profile`, `settings`, `notifications`, `create-post`, `invite`, and `claim`
  - `https://api.rodnya-tree.ru/ready` returns `storage=postgres`, `media=s3`, `adminEmailsConfigured=1`, `warnings=[]`
  - runtime watch reports `recentErrorCount=0`
  - the latest backend backup archive was restored successfully in the backup/restore drill
  - GitHub Actions `Production Watch` manual dispatch `24711915793` passed end-to-end with the same smoke/runtime contract
- Auth flow itself works on web with the current custom API session logic.
- Relatives list loads real data and reflects invite/chat affordances.
- Tree route redirect and tree rendering work after login.
- Notifications list loads real items and now sits inside a more desktop-appropriate shell.
- Web build is recoverable and now compiles with `flutter build web --no-wasm-dry-run`.
- Desktop layouts for home, chats, profile, relatives, notifications, and chat view are all denser than the initial audit baseline.
- Production deployment was updated on 2026-04-10 for both `api.rodnya-tree.ru` and `rodnya-tree.ru`.
- Additional live production smoke passed on 2026-04-10: home feed renders a new post, profile shows authored posts, notifications grouping is visible after a fresh bundle load, tree view uses the new split desktop layout, and direct chat renders photo messages correctly.
- Storage migration production smoke passed on 2026-04-12: `https://api.rodnya-tree.ru/ready` now reports `storage=postgres` and `media=s3`, migrated media open over HTTPS, and a fresh upload/delete cycle succeeds on the live API.
- Deployment hardening moved forward on 2026-04-11: the repo now contains a shared web release activator, a Windows manual deploy helper, and a tar-based GitHub workflow path instead of raw in-place rsync.
- Production web deploys can now expose a plain `last_build_id.txt` marker for external verification without SSH.
- Public legal routes were re-verified on 2026-04-12 after a fresh deploy: `/#/privacy` and `/#/support` now render the current release-ready text on `rodnya-tree.ru`.
- Web startup hardening was re-verified on 2026-04-12 after the shell sync fix and fresh deploy: `assets/AssetManifest.bin.json` and `assets/FontManifest.json` now return `200` on production, and their cache policy was tightened so older browser sessions do not keep a stale `404` for up to a day.
- 2026-04-16 local verification passed after the shared app-status/router hardening pass:
  - `flutter analyze` is green
  - targeted Flutter tests are green from the mirror worktree, including auth/chat/tree/relatives screens and the new router regression coverage
  - `flutter build web` completes and local Playwright smoke confirms `/#/privacy` renders from the static bundle without console errors
- 2026-04-16 production route smoke after a fresh web deploy passed for:
  - login and profile-complete redirect handling
  - home, chats, relatives, tree, profile, notifications, and `/#/profile/settings`
  - public legal/support routes `/#/privacy`, `/#/terms`, `/#/support`, `/#/account-deletion`
  - create-post screen and a real publish cycle on a disposable account
  - delete-account UI flow for that disposable account
- 2026-04-16 production phone-linking hardening passed after a fresh backend + web deploy:
  - the backend no longer trusts client-sent `isPhoneVerified` during обычное profile save
  - changing the phone in `/#/profile/edit` immediately drops the verified state in the UI and shows the retry CTA again
  - live API smoke on disposable accounts confirmed: verified-phone conflict returns `409`, editing the phone resets verification to `false`, the old number can then be verified on another account, and contact discovery now returns only verified phone matches
- 2026-04-16 build marker verification is now healthy again: `https://rodnya-tree.ru/last_build_id.txt` returns the active deploy label after the latest web activation.
- 2026-04-16 production media/CORS cleanup is now live:
  - legacy first-party media URLs from the backend are normalized to `https://api.rodnya-tree.ru/...` in session, profile, post, story, comment, chat preview, chat participant, message attachment, and person payloads
  - the targeted identity shim on `persons` routes now answers CORS preflight itself and mirrors `Access-Control-Allow-Origin` on GET/OPTIONS responses
  - fresh Playwright smoke on `/#/profile/edit` after the deploy shows `0` console errors; the old mixed-content avatar tail is closed
- 2026-04-16 production web deploy also fixed the legal-route redirect bug:
  - before the fix, authenticated visits to `/#/privacy` and related pages were incorrectly redirected away by `AppRouter`
  - after the fix and redeploy, those routes stay reachable in both anonymous and authenticated sessions
- 2026-04-20 repo-side route smoke discipline moved forward again:
  - `tool/prod_route_smoke.mjs` now serves as the shared Playwright route-by-route smoke runner
  - `deploy/web/deploy_web.ps1` can run that smoke after activation and roll back automatically on failure
  - `.github/workflows/flutter-web-deploy.yml` now runs the same smoke contract after deploy and uploads the smoke artifact
- 2026-04-20 production QA and failure UX moved forward again in repo:
  - `tool/prod_route_smoke.mjs` can auto-register a disposable smoke account, auto-create disposable person fixtures, cover `relative-details` and `chat-view`, and clean the person fixture after the run
  - `.github/workflows/production-watch.yml` now uses the shared `deploy/backend/verify_backup_restore_drill.sh` instead of an inline one-off backup precheck
  - `Home`, `Tree`, `Profile`, and `Relative details` gained cleaner failure states and less raw technical copy in the main repo flow
- 2026-04-20 backend operational visibility also moved forward in repo:
  - `/health`, `/ready`, and `/v1/admin/runtime` now expose runtime metadata, realtime stats, SMS readiness, release label, and operational warnings
  - the active release is mirrored in `x-rodnya-release`, which makes smoke/debug correlation easier after deploys
- 2026-04-16 production identity smoke exposed two distinct states:
  - raw live backend parity is still incomplete: without the targeted claim shim, relation request acceptance plus claim still drifts into `3` persons and `identityId: null`
  - public production traffic is now protected by the targeted identity shim on relation accept, claim, and person read endpoints, and with that path active the same smoke ends at `2` persons with the relation target attached to the claimed offline card and a stable synthetic `identityId`
- 2026-04-16 production smoke still shows one residual console issue:
  - after deleting the disposable account from settings, the app redirects back to `/#/login`, but one trailing `GET /v1/stories?authorId=...` returns `401` during teardown
  - this is not blocking the delete flow itself, but it should be cleaned up as a post-delete polish item
- 2026-04-16 repo state after the rich-profile/privacy foundation pass:
  - `CustomApiStoryService` now refuses to send stories requests without an active session, so the trailing post-delete stories teardown no longer leaves the client as an anonymous network caller
  - the production smoke note above remains true until the next web deploy, but the repo-side fix is in place
- 2026-04-16 planning and foundation for richer profiles is now explicit in repo:
  - [profile_visibility_and_identity_plan_2026-04-16.md](./profile_visibility_and_identity_plan_2026-04-16.md) defines the rollout for rich profile sections, visibility scopes, native identity parity, and delete-account cleanup
  - first foundation code is now present locally for section-based profile visibility and richer profile fields on edit/view routes
- 2026-04-17 rich-profile/privacy slice is now live on production:
  - backend and web deploy label `20260417-profile-visibility-native` is active on `rodnya-tree.ru`
  - `/#/profile/edit` on the live domain renders the rich-profile sections and the extended visibility model with `specific_trees` and `specific_users`
  - live API smoke on disposable accounts confirmed section-based visibility enforcement for both `specific_trees` and `specific_users`
- 2026-04-17 rich-profile field expansion is now live on production:
  - active web build marker is now `20260417-profile-rich-fields`
  - live `PUT /v1/profile/me/bootstrap` smoke on disposable accounts confirmed that `aboutFamily`, `hometown`, `languages`, and `interests` persist through the production API
  - live viewer-side API smoke confirmed the intended section split: `aboutFamily` stays hidden with the `about` section, `hometown` and `languages` stay visible with `background`, and `interests` stays hidden with `worldview`
  - live browser smoke confirmed `/#/profile/edit` renders all four new fields, and `/#/user/:userId` for an outsider shows `Родной город` and `Языки` while still hiding the private `about/worldview` content
- 2026-04-20 provider-based trust model superseded the old OTP branch:
  - phone verification is removed from the active product and backend contract
  - `/#/profile/edit` now manages trusted channels instead of SMS ownership
  - search/linking uses `username`, `profile code`, `invite`, `claim`, and `QR`
  - `/ready` and `/v1/admin/runtime` now focus on runtime/realtime/release health rather than SMS readiness
- 2026-04-17 VK ID web auth is now enabled on production:
  - backend config now serves `vkAuthEnabled=true` on both `/health` and `/ready`
  - `GET https://api.rodnya-tree.ru/v1/auth/vk/start` now redirects to `https://id.vk.ru/authorize` with `client_id=54549672`, the production callback `https://api.rodnya-tree.ru/v1/auth/vk/callback`, and `scope=phone email`
  - fresh browser smoke on `https://rodnya-tree.ru/#/login` shows the live `VK ID` quick-login button with `0` console errors
  - current limitation: this pass enables the real web flow first; Android return-to-app is still a follow-up step
- 2026-04-20 MAX mini app auth is now implemented in repo:
  - backend validates MAX `WebAppData` and supports `start -> complete -> exchange/link`
  - web shell contains `max_auth.html` for the mini-app handoff
  - current limitation remains native Android return-to-app polish, not the web flow itself
- 2026-04-17 native identity parity is now live without the runtime shim:
  - production backend was updated from the current repo state and `rodnya-backend.service` restarted successfully
  - the active Caddy admin config had stale runtime overrides that still sent claim-related routes to `127.0.0.1:8081`; reloading from `/etc/caddy/Caddyfile` removed those overrides
  - `claim_merge_shim` is no longer running, `:8081` is no longer listening, and the active proxy config no longer references `8081`
  - live disposable-account claim smoke passed after the shim shutdown and clean Caddy reload: offline-card claim ends at `2` persons, relation target remaps to the claimed offline card, and the same `identityId` is reused in a second tree
- 2026-04-17 delete-account teardown is now clean on the live web flow:
  - a disposable account logged in on `rodnya-tree.ru`, opened `/#/profile/settings`, completed the delete-account flow, and returned to `/#/login`
  - browser console stayed free of runtime errors, and the old trailing stories `401` did not reappear in the verified flow

## Residual notes
- As of 2026-04-21, the core MVP route contract is no longer blocked by live smoke failures. Remaining work is mostly polish backlog, release discipline maintenance, and future feature work rather than web-MVP rescue.
- Browser sessions can temporarily keep an older Flutter web bundle in memory; in testing, adding a cache-busting query or reloading the app was enough to see the latest production UI.
- `/#/settings` is not a valid route. The correct settings entry is `/#/profile/settings`, and direct smoke should use that path.
- `specific_branches` is now implemented in the profile visibility model and deployed to production.
- The old SMS/OTP direction is intentionally removed; trust now comes from linked provider identities and family invite/claim flows.
- 2026-04-20 direct chat parity is stronger in repo:
  - canonical direct chat ids are now resolved consistently for details, message list, send, edit, delete, read-state, and call creation
  - this closes the repo-side mismatch where reversed direct ids could still behave unevenly after the details screen opened successfully
- Validation note from 2026-04-12:
  a stale persisted `custom_api_session_v1` no longer blocks web startup. The app now clears the local session path safely enough to reach `/#/login` instead of dying in bootstrap, and unauthorized cleanup no longer adds an extra `POST /v1/auth/logout` on top of the expected `401` session/refresh pair.
- Web console is clean from runtime errors in the verified flows, but typography polish still deserves a follow-up pass for missing glyph warnings if they reappear in browser logs.
- Validation note from 2026-04-12:
  the web shell deploy path now force-syncs `icons`, `manifest.json`, `favicon.png`, `favicon.ico`, generated Flutter startup manifests, and `push/` into `build/web`. The old production warnings for missing `AssetManifest.bin.json` / `FontManifest.json` are closed.
- Validation note from 2026-04-11:
  local browser smoke should use `flutter build web`, not only `flutter build web --no-wasm-dry-run`. In this repo the `--no-wasm-dry-run` output can be sufficient for compile validation while still leaving a locally served `build/web` without final `AssetManifest`, `FontManifest`, and web icon files, which creates false 404s and `google_fonts` runtime noise on `/login`.

## Technical notes
- Web build had a compile blocker in `lib/screens/chat_screen.dart`: missing `ChatPreview` import.
- After fixing that import and cleaning generated Flutter state, the project builds successfully for web.
- Local custom backend now covers posts/feed/comment MVP flow and passes backend tests.
- Tree selection on web previously reused stale cached tree data across accounts; provider/cache logic now prefers fresh backend tree lists and replaces stale cached tree entries.
- Additional local custom-backend smoke passed on 2026-04-09: login, home feed, create-post, profile posts and empty notifications render correctly from the web build.

## Next repair order
1. Keep the new live smoke + runtime watch + backup drill discipline green on schedule, not only after manual deploys.
2. Do one more premium visual pass on tree view if the goal is beyond MVP-grade polish.
3. Keep tightening failure UX and route-by-route regression coverage instead of adding new brittle surface area.
4. After that, move to new user-facing work: family calendar, user-visible tree history, stronger memorial/gallery experience, and growth-oriented invite/claim improvements.
