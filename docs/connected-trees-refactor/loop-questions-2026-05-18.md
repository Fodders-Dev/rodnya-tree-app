# /loop escalation queue — 2026-05-18

Questions surface'нутые автономным loop'ом которые требуют
Артёмова decision. Append-only.

---

## Iteration 1 (2026-05-18T11:14Z): `_branchDigest` write-only field в home_screen

**Found**: `lib/screens/home_screen.dart:69` — поле
`BranchDigest? _branchDigest` имеет 2 write paths (line 199:
`_branchDigest = null;` при clear; line 278: `_branchDigest = digest;`
при successful fetch), но **никогда не читается** в build() либо
другом code path. `analyzer warning unused_field`.

Comment на line 66-69 ссылается на Phase 6.3:

> Phase 6.3: home-screen «Эта неделя в семье» strip. Loaded
> best-effort in the background; widget self-hides when null
> or empty. Older backends without the digest endpoint just
> never populate this — no errors visible to the user.

Это значит: либо feature shipped без UI wire-up (widget
`BranchDigestStrip` существует в `lib/widgets/branch_digest_strip.dart`,
import removed в iteration 1 потому что не used), либо widget
intentionally lazy — Phase 6.3 implementation incomplete.

`BranchDigestStrip` widget сам по себе живёт + tested (его import
теперь не нужен в home_screen, но widget может использоваться где-то
ещё либо как future-wire'ит target).

**Tried**: removed unused_import only (safe). Не trogал
`_branchDigest` field либо load logic — это design decision territory.

**Decision needed**: какой из вариантов:

A. **Wire widget в build()**: добавить `BranchDigestStrip(digest:
   _branchDigest)` в home_screen build column. Завершает Phase 6.3
   UX intent. Нужен design call: куда именно в home-screen layout
   strip монтировать (above posts list? между stories + posts?
   conditional на digest.isEmpty?).

B. **Delete field + load logic**: убрать `_branchDigest` declaration,
   удалить fetch вызов + clear (lines ~199, ~278), удалить связанные
   capability mixin imports если single-purpose. Признаёт Phase 6.3
   feature abandoned/deferred. Cascade ~10-20 LOC removal.

C. **Leave as is**: warning остаётся как 1-issue baseline.
   Не closure, но valid state — Phase 6.3 интенсивно lazy
   (feature flag-like через capability check ниже).

**Suggested next step**: B (delete) если Phase 6.3 strip больше не
roadmap'е либо A только когда design call есть. C временно
acceptable, но баseline drift накапливается.

**Files for follow-up**:
* `lib/screens/home_screen.dart` (declaration, load, clear)
* `lib/widgets/branch_digest_strip.dart` (widget — keep либо delete с option B)
* `lib/backend/interfaces/branch_digest_capable_family_tree_service.dart`
* `lib/backend/models/branch_digest.dart`

---
