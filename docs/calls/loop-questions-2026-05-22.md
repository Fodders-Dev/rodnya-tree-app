# Bug 2/3 UI state desync — investigation findings

> Per Артёмов direct dispatch после Bug A device-verify (Samsung S20 FE
> через ADB). Bug A (foreground service) shipped `766e5e0` — video/audio
> bilateral works. Но UI state desync surfaced separately: button labels
> не отражают actual track state.

---

## Symptoms (Артёмов repro)

1. **Mute button desync**: UI shows mic перечеркнут (off), НО peer
   слышит звук. Inverse тоже наблюдается.
2. **Camera button desync**: tap camera → preview окно появляется
   briefly → пропадает. Peer всё ещё видит video. UI shows camera off
   хотя actually on.

Оба симптома — UI state НЕ соответствует actual LiveKit publication.

---

## Mute state flow

**Field**: `bool _microphoneEnabled = true` —
`lib/services/call_coordinator_service.dart:139`

**Getter**: `bool get microphoneEnabled` (line 174) — read by
CallScreen button icon + tooltip (`call_screen.dart:842-845`).

**Writes**:
- `_connectRoom`: `_microphoneEnabled = true` (line 1004) — BEFORE
  `_publishLocalMicrophone(room)` (line 1011). Initial state correct.
- `toggleMicrophone` mute path (line 517): `_microphoneEnabled = false`
  AFTER `setMicrophoneEnabled(false)` await. Correct.
- **`toggleMicrophone` un-mute path (line 505-510)**: NO write к
  `_microphoneEnabled`. Только `_publishLocalMicrophone(room)` →
  `_microphonePublishFailed = !published`. ⚠️
- `_publishLocalMicrophone` (line 1328-1351): только sets `_microphoneEnabled
  = false` на failure paths (3 spots). Никогда не sets к true на success.
- `reset()` (line 1648): `_microphoneEnabled = true` (defensive).
- `_applyCall` cleanup paths (line 1704): `_microphoneEnabled = false`
  через terminal/null state reset. (NB: NOT `_microphoneEnabled = true`
  на active transitions — это OK, `_connectRoom` setup.)

**ROOT CAUSE #1 — Bug 2 mute desync (Q1 regression от ship `b914905`)**:
`toggleMicrophone` un-mute path:
```dart
final nextValue = !_microphoneEnabled;  // true (был muted)
if (nextValue) {
  final published = await _publishLocalMicrophone(room);
  _microphonePublishFailed = !published;
  // ❌ MISSING: _microphoneEnabled = published;
}
```

После un-mute с успешной publication:
- `_microphonePublishFailed = false` ✓
- `_microphoneEnabled` остаётся `false` ❌ (был false после предыдущего mute)
- UI getter `microphoneEnabled` returns false → icon shows mic OFF
- Peer слышит (publication actually active в LiveKit)

Артёмов symptom: «UI shows перечеркнут НО звук peer слышит» — exact match.

До Q1 ship (commit `b914905`), `toggleMicrophone` была:
```dart
final nextValue = !_microphoneEnabled;
await room.localParticipant?.setMicrophoneEnabled(nextValue);
_microphoneEnabled = nextValue;  // ← unconditional
notifyListeners();
```

Q1 разделил on/off branches для verification + truthful UI на failure,
но потерял unconditional `_microphoneEnabled = true` на success enable path.

**Дополнительный edge case**: даже если бы мы добавили
`_microphoneEnabled = true` на success, при server-side mute (peer
mute-кнопкой управляет нашим mic — это редко но возможно через LiveKit
admin permissions) либо при automatic re-mute после reconnect, Dart
field никогда не обновится — нет subscription к
`TrackMutedEvent`/`TrackPublishedEvent`/`TrackUnpublishedEvent`.

---

## Camera state flow

**Field**: `bool _cameraEnabled = false` —
`call_coordinator_service.dart:148`

**Getter**: `cameraEnabled` (line ~175) — read by CallScreen button
icon (line 875), preview render (line 525-527 в `_localVideoTrack`
gate), PIP visibility (line 884).

**Writes**:
- `_connectRoom`: `_cameraEnabled = call.mediaMode.isVideo` (line 1005).
- `toggleCamera` (line 550): `_cameraEnabled = nextValue` AFTER
  `setCameraEnabled` await. Correct on its own.
- `switchCamera` success (line 567): `_cameraEnabled = true`.
- `selectCameraDevice` success (line 636): `_cameraEnabled = true`.
- **`_applyCall` (line 751-753)**: `if (!nextCall.mediaMode.isVideo)
  { _cameraEnabled = false; }`. ⚠️
- `_resumeLocalMediaAfterReconnect` (line 1223): uses `_cameraEnabled`
  to re-publish, не writes.
- `reset()` (line 1650), cleanup paths: `_cameraEnabled = false`.

**ROOT CAUSE #2 — Bug 3 camera desync**:
`_applyCall` line 751-753:
```dart
if (!nextCall.mediaMode.isVideo) {
  _cameraEnabled = false;
}
```

Сценарий:
1. User в audio call (`call.mediaMode == CallMediaMode.audio`).
2. Tap camera → `toggleCamera`:
   - `setCameraEnabled(true, ...)` succeeds → preview visible
   - `_cameraEnabled = true` → UI shows camera on
3. **Event-driven re-apply** через `_applyCall(snapshot)`:
   - Snapshot from backend полл / realtime / recovery refresh
   - `nextCall.mediaMode == audio` (backend не знает что user локально включил камеру — `mediaMode` server-truth и не меняется по local toggle)
   - Line 752 fires: `_cameraEnabled = false`
4. UI shows camera OFF (preview disappears)
5. LiveKit camera publication остаётся ACTIVE (нет
   `setCameraEnabled(false)` call) → peer всё ещё видит video

Артёмов symptom: «preview окно появляется briefly → пропадает. Peer
всё ещё видит мой video. UI shows camera off хотя actually on» — exact
match.

Trigger source for `_applyCall` re-fire:
- Backend events: `_handleCallEvent` (line ~268) → `_applyCall(event.call)`
- Realtime: `notification.created` push event → `_applyCall`
- Recovery timer: `_scheduleActiveCallRecovery` каждые 2 секунды (line ~50,
  `_activeCallRecoveryInterval`) refetches backend snapshot

The 2s recovery timer guarantees frequent re-apply → camera state
desync triggers BY DESIGN на любом audio call с активированной камерой.

---

## LiveKit event subscriptions

`_connectRoom` registers EventsListener<RoomEvent> с handlers:
- `RoomDisconnectedEvent`, `RoomReconnectingEvent`, `RoomReconnectedEvent`
- `ParticipantConnectionQualityUpdatedEvent`
- `ParticipantConnectedEvent`, `ParticipantDisconnectedEvent`
- Generic `ParticipantEvent`, `RoomEvent` (fire `notifyListeners()`
  для UI rebuild)

**Missing**: NO specific listeners for `LocalTrackPublishedEvent`,
`LocalTrackUnpublishedEvent`, `TrackMutedEvent`, `TrackUnmutedEvent`.

The generic `ParticipantEvent` catch-all fires `notifyListeners()`
→ UI rebuilds → но `_microphoneEnabled` / `_cameraEnabled` fields
DON'T get re-read from LiveKit. Getters return stale Dart values.

LiveKit exposes truth via `participant.isMicrophoneEnabled()` /
`participant.isCameraEnabled()` (both check `getTrackPublicationBySource(...)?.muted`).

---

## Proposed fix

**Approach**: combine immediate targeted fixes (small + safe) + add
defensive sync from LiveKit truth (medium + safer long-term).

### Fix A — `toggleMicrophone` un-mute sets `_microphoneEnabled` (trivial)

```dart
if (nextValue) {
  final published = await _publishLocalMicrophone(room);
  _microphonePublishFailed = !published;
  _microphoneEnabled = published;  // ← ADD
}
```

Scope: 1 line + test update.
Risk: very low.
Addresses: Bug 2 mute desync, exact symptom.

### Fix B — `_applyCall` preserve local camera override

```dart
if (!nextCall.mediaMode.isVideo) {
  // Не reset'им cameraEnabled когда room connected и local camera
  // была активирована — user мог upgrade audio→video через local
  // toggle, backend mediaMode за этим не следит. Reset только когда
  // call inactive либо нет room — actual track is gone anyway.
  if (_room == null) {
    _cameraEnabled = false;
  }
}
```

Scope: ~5 lines + test.
Risk: low. Edge case — если backend explicitly downgrades video→audio
(rare), local camera UI overrides backend signal. Acceptable trade-off:
user's last explicit action wins.
Addresses: Bug 3 camera desync, exact symptom.

### Fix C — Defensive sync via LiveKit local track events (medium)

Add to `_connectRoom` event listener:
```dart
..on<LocalTrackPublishedEvent>((event) {
  _syncMediaStateFromLiveKit(room);
})
..on<LocalTrackUnpublishedEvent>((event) {
  _syncMediaStateFromLiveKit(room);
})
..on<TrackMutedEvent>((event) {
  _syncMediaStateFromLiveKit(room);
})
..on<TrackUnmutedEvent>((event) {
  _syncMediaStateFromLiveKit(room);
})
```

Plus helper:
```dart
void _syncMediaStateFromLiveKit(Room room) {
  final participant = room.localParticipant;
  if (participant == null) return;
  final micActual = participant.isMicrophoneEnabled();
  final camActual = participant.isCameraEnabled();
  var changed = false;
  if (_microphoneEnabled != micActual) {
    _microphoneEnabled = micActual;
    changed = true;
  }
  if (_cameraEnabled != camActual) {
    _cameraEnabled = camActual;
    changed = true;
  }
  if (changed) {
    notifyListeners();
    unawaited(_updateForegroundService());
  }
}
```

Scope: ~30 lines + test.
Risk: medium. LiveKit может fire events frequently — notifyListeners
spam риск. Mitigation: change detection (only notify on diff).
Addresses: ANY future desync (server-side mute, automatic remute on
reconnect, codec re-init).

### Recommendation

**Ship A + B together** в этой iteration (immediate symptom fixes,
~6 LOC implementation + tests, low risk). **Defer C** к следующей
iteration после device-verify Fix A+B — если ещё какие-то edge cases
выплывут, тогда C добавим. Это "safe fix" путь: minimal change,
maximum impact, verify per layer.

Если Артём хочет ship A + B + C атомарно — тоже OK, scope всё ещё
< 100 LOC (включая tests), но С добавляет moving parts которые лучше
сначала verify изолированно.

---

## Files touched (Fix A + B вариант)

- `lib/services/call_coordinator_service.dart`:
  - `toggleMicrophone` line ~510 — add `_microphoneEnabled = published`
  - `_applyCall` line ~751 — wrap reset with `if (_room == null)`
- `test/call_coordinator_service_test.dart`:
  - New test: `toggleMicrophone enable updates _microphoneEnabled на
    success` — uses Q1 debug seam либо новый seam для simulating publish
  - New test: `_applyCall не reset'ит _cameraEnabled когда room
    connected и backend mediaMode audio`

Estimated scope: ~40 LOC (6 production + ~30 tests + ~5 comments).
Risk: low.
Single-file production change + single test file change.

---

## Fix C scope если decided ship-together

- `lib/services/call_coordinator_service.dart`:
  - `_connectRoom` event listener — 4 new `..on<...Event>` lines
  - New `_syncMediaStateFromLiveKit` helper — ~20 lines
- `test/call_coordinator_service_test.dart`:
  - Test для sync helper с simulated participant publication state

Adds ~30 LOC production + ~40 LOC test.
Total A+B+C: ~110 LOC.

---

## Architecture concern (long-term, не fix this iteration)

Текущий design: Dart fields `_microphoneEnabled` / `_cameraEnabled`
как single source of truth + LiveKit publication state как parallel
truth. Race conditions inevitable.

Long-term right answer: getter returns
`_room?.localParticipant?.isMicrophoneEnabled() ?? _microphoneEnabled`
(LiveKit truth когда room connected, Dart field как fallback для
pre-connect либo disconnect transitions). Это makes Dart field a
write-only intent buffer, не state.

Scope этого refactor — отдельный 200-300 LOC ship, нужно coordinate с
CallScreen rebuilds (currently triggered только notifyListeners — LiveKit
async events нужны events bridge). Defer пока specific bugs не surfaced
ещё.

---

## ⏸️ STOP — жду Артёмов OK

**Pick**:
1. **Ship Fix A + B only** (~40 LOC, low risk, addresses exact
   reported symptoms) — recommended
2. **Ship Fix A + B + C** (~110 LOC, medium risk, defensive coverage)
3. **Defer all** — есть other priorities

После твоего OK я proceed Phase 3 (implementation) + Phase 4 (tests) +
Phase 5 (device verify).
