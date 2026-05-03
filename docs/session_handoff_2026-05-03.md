# Session handoff — 2026-05-02 → 2026-05-03

This is the wrap-up note from the long Anthropic-Claude session that
spanned tree redesign, chat domain polish, multi-device sessions
(via parallel chats), and assorted UI work. The user went on a break
to test before the next session — this doc is the resume point.

## What shipped (in chronological commit order on `main`)

| Commit | Domain | What |
|---|---|---|
| `4e83061` | Tree | Person card redesign (Lora fname + Manrope lname + † deceased + pending dot + dimmed-when-not-on-active-path) |
| `3f4770a` | Tree | Connector colors via design tokens + accent active path + smaller junctions; generation badge restyled |
| `df670e4` | Tree | Bezier-curve connectors per Claude Design reference (replaces H-bus elbows) |
| `44499d1` | Tree | Bottom sheet — collapsed peek + tap-to-expand action row |
| `df9fed9` | Tree | Drop duplicate stat chips from canvas viewport overlay |
| `7a03eb4` `d1671a6` `e7325e2` | Tree | Layout fix: spouses always share a generation row, anchored by their kids; siblings respect own-children floor; implicit couples via shared kids |
| `0ea0c9a` | Tree | Drop stat pills from desktop toolbar |
| `be08529` `220a8c1` | Tree | Full-bleed canvas: tree paints directly on the page backdrop (mobile + desktop) |
| `667062a` | Tree | Double-tap card opens full profile (drilldown) |
| `0ac0b74` | Tree | Show "+" quick-add badge on selected card too |
| `7e06e8e` | Tree | Edit-mode actions live in the bottom sheet, drop floating panel |
| `0cbdbd8` | Tree | Drop duplicate "+ Add person" buttons + push canvas overlay below chrome |
| `fd275e9` | Chat | Hive cache for chat previews + debounced metadata writes |
| `d23d9eb` | Chat | StreamBuilder initialData + RepaintBoundary on chat tiles |
| `4e68b68` | Chat | Bubble + composer + topbar polish to match Claude Design |
| `159589b` | Chat | "в сети" / "была N минут назад" presence subtitle |
| `6924c4a` | Chat | Smart photo grid + theme-aligned voice player + Telegram-style receipts |
| `68da455` | Calls (parallel chat 1) | Per-session LiveKit identity + Telegram-style multi-device UX (fixed 5s disconnect duplicateIdentity bug) |
| `6ed2f9f` | Calls (parallel chat 1) | Direct-chat title shows other participant + per-instance session id |
| `b9eb0d8` | Multi-device (parallel chat 2) | Telegram-style multi-device session management + QR login (sessions API, remote logout, QR scan/display screens) |
| `b46bc03` | Multi-device (parallel chat 2) | Rate limiting + OAuth device context threading + WS reconnect guard |
| `4315a6d` | Auth | Hero + sheet redesign per Claude Design reference |
| `bff0378` | Media | Universal MediaLightbox + posts now open in fullscreen |

## Quality gates as of last commit

- `flutter analyze`: clean (0 issues).
- Flutter tests: 332/333 passing locally. The single pre-existing
  failure is `tree_selector_screen_test`'s "TreeSelectorScreen
  группирует активное, свои и чужие деревья" which has been
  flagged in earlier session notes as pre-existing and unrelated to
  current work.
- Backend tests: 127/127 passing (multi-device session work verified).
- Web build: green.
- Production deploys: all auto-deployed via GitHub Actions; route
  smoke verifies authenticated routes (home, tree, relatives, chats,
  profile, settings, notifications, create-post, relative-details,
  chat-view, invite-flow-authenticated, claim-flow-authenticated).
- Pre-existing intermittent: `[anonymous] invite-flow` smoke flakes
  occasionally — unrelated to recent work.

## What needs user testing on real devices

These work locally but the user explicitly wanted real-device E2E:

1. **QR login flow.** Profile → Безопасность → Активные сеансы.
   On the second device, scan with `/profile/sessions/scan`. Verify
   the session appears on Device A's "Активные сеансы" list and
   the new device lands on `/profile`.

2. **Multi-device call.** Log in to the same account on PC + phone.
   Make a call. Verify:
   - PC and phone DON'T both auto-join (one wins, the other shows
     "Звонок принят на другом устройстве" snackbar)
   - Call doesn't disconnect after 5s
   - Call summary appears in chat (📞 Аудиозвонок · M:SS)

3. **Presence subtitle.** Direct chat with another live user.
   Verify subtitle reads "в сети" while they're connected, "был(а)
   N минут назад" after they close.

4. **Smart photo grid.** Send 1, 2, 3, 4, 5+ photos to a chat.
   Verify each layout — single 220x220, side-by-side 50/50,
   1-big-left + 2-stacked-right, 2x2 grid, 2x2 grid with "+N"
   overlay.

5. **Read receipts.** Send a message, ask peer to read it. Verify
   blue ✓✓ + "Прочитано" footer on the latest own message.

6. **Universal media viewer.** Open a post with a photo from the
   feed. Verify fullscreen lightbox opens with pinch-zoom + swipe
   between photos in carousel posts.

## What's queued but wasn't done

These are flagged in todo but explicitly deferred:

- **Viewer unification** (chat `_AttachmentViewerDialog` →
  `MediaLightbox`). The chat side has its own paginated viewer
  that supports local XFile previews, sender labels, etc. The
  user's complaint was "no viewer in posts" — solved. Refactoring
  the chat viewer is a refactor with ~300 LOC churn and no user-
  facing benefit; defer until there's a concrete reason to unify.

- **Profile screen final pass.** A `_HeroCard` redesign was already
  shipped earlier in this session (cover banner + overlapping
  avatar + tokens). The current 5887-line `profile_screen.dart` is
  too large to safely autonomous-refactor without user feedback.
  When the user is back: pick the specific subsections that look
  off, fix targeted.

- **Identity review (Wave 5).** Already mature in code:
  `_ConfidenceHeader`, `_PersonPairPreview`, `_PersonCompareCard`,
  `_MatchSignals`, `_ComparisonTable`, privacy note all present.
  No work needed.

- **Storefront / RuStore release kit.** Needs user-driven decisions
  on store listing copy, screenshot kit, version bump strategy.
  Cannot be done autonomously.

- **Stories** (24h ephemeral) — model + service + create + viewer
  + rail are all shipped. There's no reference jsx for stories
  in `.tmp/claude_design_reference/src/` so further work would be
  spec'd from scratch with the user.

## Outstanding questions for the user (when back)

1. Auth screen on web showed a dark auth card on the verification
   screenshot. Likely driven by system color-scheme preference.
   Decide whether to force light theme or accept system-following.

2. Check `_AttachmentViewerDialog` (chat photo viewer) — it uses
   `Colors.white` and `Colors.blue.shade700` in some buttons.
   Could harmonize with the design tokens later. Not critical.

3. The pre-existing `tree_selector_screen_test` failure has been
   flagged for many sessions but never fixed. Decide whether to
   fix or update the test.

## File structure changes added today

New files:
- `lib/services/chat_preview_cache.dart`
- `lib/widgets/media_lightbox.dart`
- `docs/session_handoff_2026-05-03.md` (this file)

From parallel chats:
- `lib/screens/sessions_screen.dart`
- `lib/screens/qr_login_display_screen.dart`
- `lib/screens/qr_login_scan_screen.dart`
- `lib/services/auth_sessions_service.dart`
- `lib/services/session_revocation_watcher.dart`
- `lib/utils/device_descriptor.dart`
- `backend/test/auth-sessions.test.js`

## Resume strategy

When the user is back:

1. **Real-device test pass.** Use the checklist above. Capture
   anything that looks off.
2. **Triage feedback.** If presence subtitle / WebRTC stability /
   QR login work as expected, we have a feature-complete MVP for
   the Wave 6 "polish" track.
3. **Pick next focus.** Either deeper polish on one screen the
   user wants improved, or the deferred Storefront/RuStore release
   prep, or new feature direction.
