# Calls — urgent escalation (2026-05-22)

> Surfaced Phase 1 audit'ом. Items here marked для приоритетного
> Артёмова внимания при return. See `AUDIT-2026-05-22.md` для full
> context.

---

## ✅ Bug A — RESOLVED 2026-05-22 (loop iteration 3 / Q3)

`FOREGROUND_SERVICE_MICROPHONE` permission + Kotlin foreground service
landed. Артём pre-approved scope + UX defaults перед ship. См.
loop-log-2026-05-22.md iteration 3 для details. **Device verification
(Samsung A50 + Huawei MatePad) ещё нужна.**

---

## 🔴 Bug A — Missing `FOREGROUND_SERVICE_MICROPHONE` permission +
##         no foreground service (Android 14+) [HISTORICAL — fixed]

**Severity**: production-breaking на modern Android (Android 14+
~50% install base в 2026).

**Pointer**: `android/app/src/main/AndroidManifest.xml:6-28` —
декларированы только `RECORD_AUDIO` + `MANAGE_OWN_CALLS`. Нет
`FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_MICROPHONE`. Нет
foreground service stub'а для активного звонка —
`RodnyaConnectionService` объявлен только для incoming telecom UI,
не для media.

**Symptom**: на Android 14+ микрофон silently revokes из mic capture
когда экран блокируется или приложение backgrounded. Producer side
(собеседник Артёма) перестаёт слышать. **С 95% pointer на Артёмов
reported Bug 1 — «Audio one-way Samsung A50, Huawei MatePad»**.
Samsung A50 = Android 13+. Huawei MatePad 11.5s = EMUI/HarmonyOS
который особенно агрессивен на background mic kills.

**Это НЕ device-specific quirk** — documented Android behavior
change. Любой WebRTC/calls приложение без foreground service ломается
на Android 14+ когда screen blank.

**Fix shape** (per audit estimate, ~5-8 hours):
1. AndroidManifest.xml — add `FOREGROUND_SERVICE` +
   `FOREGROUND_SERVICE_MICROPHONE` permissions.
2. New Kotlin service `RodnyaCallForegroundService` который стартует
   при `_applyCall(state=active)` через MethodChannel call и
   стопится при terminal/disconnect. Создаёт notification (required
   по Android API) с call participants info + actions.
3. Flutter side — `CallCoordinatorService._applyCall` triggers
   service start/stop через `MethodChannel('rodnya.calls/foreground')`.
4. Tests — integration test verifying service lifecycle на active
   call transitions.

**Why escalate а не auto-fix**:
* Scope > 300 LOC (loop'а safe-fix threshold)
* Кросс-platform native code (Kotlin) + Manifest changes — нужен
  Артёмов sign-off на architecture
* Notification UX design нужен (что показывать, какие action
  buttons) — это product call, не loop decision
* Без device verification (Samsung A50 + Huawei) нельзя 100%
  confirmed что fix actually resolves Артёмов симптом

**Recommended**: Артём, когда return, approve scope + UX call
+ device-test access, тогда single PR ~5-8h ship.

---

## 🟠 Bug 1 sub-cause #2 — Silent mic publication failure

**Pointer**: `lib/services/call_coordinator_service.dart:913-920` —
`await room.localParticipant?.setMicrophoneEnabled(true)` если
throws, исключение catches generic'ом вокруг `room.connect`,
`_microphoneEnabled = true` на line 917 ДО await, UI показывает «mic
on» хотя трек не опубликован. Нет inspection
`localParticipant.audioTrackPublications` после await.

**Symptom**: silent microphone failure (любая permission
revocation, AudioRecord init failure, codec init failure) — UI
shows mic enabled, отправляющий audio path mute. Maskирует
любой permission/HAL issue. Может частично объяснять Bug 1 даже
после Bug A fix.

**Fix shape** (per audit estimate, trivial < 50 LOC):
* Wrap `setMicrophoneEnabled` в свой try/catch
* On failure expose `microphonePublishFailed` flag через notifier
* Verify `audioTrackPublications.any((p) => p.source ==
  TrackSource.microphone && !p.muted)` после await
* UI surface error через snackbar / error banner

**Loop ability**: SAFE fix — clear root cause, code-only verifiable,
< 300 LOC, no cross-cutting changes. **Phase 2 iteration может
взять этот fix без Артёмова signal — будет picked up в следующих
iterations.**

---

## Что Артёму делать при return

1. **Прочитать `AUDIT-2026-05-22.md`** — full picture: 4 reported
   bugs analyzed + 15 discovered + Telegram gaps + priority order.
2. **Approve / re-scope Bug A fix** — production-breaking, нужен
   Артёмов sign-off на Kotlin service scope + notification UX.
   Без approval Bug A остаётся deferred.
3. **Optional: review Phase 2 iteration log** в
   `loop-log-2026-05-22.md` — что loop успел сделать за время
   отсутствия.
4. **Decide priority** — Bug A vs Telegram polish (mute/speaker
   UX) vs iOS CallKit work vs другое.
