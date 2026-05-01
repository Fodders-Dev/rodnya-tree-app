# Active Execution Plan

## Rodnya Claude Design UI/UX Migration

Goal: move the real Flutter app toward the Claude Design reference in
`https_rodnya-tree.ru.zip` without breaking existing backend/API behavior.
The reference is a design source, not code to port literally.

Current reference unpack path: `.tmp/claude_design_reference/`.

## Non-Negotiables

- Keep Android and web MVP stable.
- Preserve current backend services, models, routes, auth, posts, stories,
  chats, notifications, identity/common-tree/circles/privacy behavior.
- Do not touch calls/voice/video unless a task explicitly targets calls.
- Use real API data only; do not import prototype mock data.
- Make reversible wave-sized changes and verify after each meaningful wave.
- For web, do not stretch phone UI across desktop. Use side navigation,
  max-width content columns, and full-width tree canvas.
- Preserve or improve Russian UI copy quality.

## Verification After Each Wave

- `dart format` on changed Dart files, or `dart format .` when broad enough.
- `flutter analyze`.
- Relevant `flutter test`.
- If web UI behavior changed: `flutter build web`, serve `build/web`, and run
  a quick Playwright smoke pass against `http://127.0.0.1:3000/#/...`.
- Record remaining web/MVP blockers in `docs/mvp_web_audit_2026-04-09.md`
  while that audit is still active.

## Wave Status

- [ ] **Wave 1 — Design Foundation**
  - [x] Compare current `app_theme.dart`, `glass_panel.dart`,
        `main_navigation_bar.dart`, `app_backdrop.dart` with `styles.css` and
        `src/shell.jsx`.
  - [x] Introduce Flutter tokens for linen/sage/warm palette, glass surfaces,
        spacing/radii, and surface helpers.
  - [x] Update `AppBackdrop` and `GlassPanel` so existing screens inherit the
        new foundation without rewiring business logic.
  - [x] Update mobile bottom dock to five slots with active glass-pill behavior.
  - [x] Update desktop rail to the same visual system.
  - [x] Run format/analyze/relevant tests and fix regressions.
  - [x] Run `flutter build web`, `node tool/sync_web_shell_assets.js`, and
        Playwright smoke screenshots for desktop/tablet/mobile.
  - [x] Commit Wave 1 separately from unrelated calls/backend work.

- [ ] **Wave 2 — Home / Feed UX**
  - Feed-first topbar: `Родня`, notifications, tree action.
  - Pending identity merge banner when proposals exist.
  - Compact stories strip, events strip, compose teaser, audience/filter chips.
  - New post card hierarchy while preserving real feed APIs.
  - Loading, empty, offline states must not mask working API data.

- [ ] **Wave 3 — Tree UX**
  - Keep current `interactive_family_tree.dart` logic and generation grouping.
  - Add top toolbar, stats pill, generation bands/labels, selected path state,
    right-side zoom controls, bottom person sheet, circle/branch filter state.
  - On web, tree canvas is full-width and not centered as a phone layout.

- [ ] **Wave 4 — Compose + Audience Picker**
  - Port compose hierarchy and audience sheet UX natively to Flutter.
  - Use real circles/auto-circles: all family, close, branch, custom circles,
    and only-me only if backend supports it.
  - Preserve create post flow and media upload.

- [ ] **Wave 5 — Identity Review**
  - Move from flat list cards to clear A/B comparison with confidence, matching
    signals, privacy note, and actions: merge / different people / later.
  - Do not expose sensitive fields without access.
  - Keep empty state and back action polished.

- [ ] **Wave 6 — Auth / Profile / Relatives / Chats Polish**
  - Auth adopts the hero/sheet approach without breaking Google, Telegram, VK,
    MAX, or password flows.
  - Profile/relative cards, sections, edit sheets, search/chips/rows align with
    the new system.
  - No business-logic rewrites.

- [ ] **Wave 7 — Responsive Web Pass**
  - At width `>= 900`: side navigation, max-width feed/profile/chat columns,
    full-width tree canvas, adaptive compose/identity panels.
  - Validate 1440x900 desktop, 768x1024 tablet, 390x844 mobile.
  - Save Playwright before/after screenshots in `output/playwright/`.

## Acceptance Criteria

- UI visually follows Claude Design while retaining current functionality.
- Main flows still work: login, home, tree, relatives, chats, create post with
  audience, identity review.
- Mobile reads as one cohesive app; desktop web does not look like a stretched
  phone screen.
- No endless skeleton/offline states when API is working.
- `flutter analyze` is clean for the final migration state.

## Current Notes

- Existing dirty worktree contains unrelated calls/voice/backend edits. Do not
  stage them with UI waves.
- Production API still needs deployment for latest posts/media backend behavior;
  this UI migration must not hide that backend reality.
