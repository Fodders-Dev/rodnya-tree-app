# Message-send speed — how to measure (and the SPEED-6 gate)

SPEED-1..5 are shipped (backend live; client in 1.0.26+34 via OTA). SPEED-6 (move
messages out of the whole-document JSONB into an append-only `chat_messages` table,
send = INSERT) is the only remaining structural item — a **prod-DB data migration,
not fully testable locally**. Decision rule: **do it only if real numbers still fall
short after 1–5.** Instrumentation is already in the code; here's how to read it.

## Client — tap → bubble (target: <16 ms = one frame)
`PerfTrace('chat.tap-to-bubble')` in `lib/screens/chat_screen.dart` fires from the
send tap to the first frame with the optimistic bubble. In a debug/profile build,
`flutter logs` (or `adb logcat | grep '\[perf\]'`) shows:
```
[perf] chat.tap-to-bubble: 8ms
```
- <16 ms → the "Telegram instant" feel is achieved (SPEED-1 did this). This number is
  network-independent, so it should already be tiny. If it isn't, that's a client
  jank bug, NOT a reason for SPEED-6.

## Client — tap → ack (the «часики → галочка», network-bound)
`PerfTrace('chat.send-to-ack')` (already existed) logs the full round-trip:
```
[perf] chat.send-to-ack: 180ms
```
- Target p50 <300 ms, p95 <800 ms on mobile data (Nielsen/RAIL + RU-RTT ~20–80 ms).
  SPEED-2/3/4 attack this. If p95 is comfortably under target → **SPEED-6 not needed.**

## Server — where the ack ms go
Every send logs a grep-able line (`ssh` to prod, `journalctl -u rodnya-backend -f` or
the app log), split into phases:
```
[send-timing] chat=<id> access=<ms> persist=<ms> ack=<ms> dedup=false
[send-timing] chat=<id> fanout=<ms> recipients=<n>
```
- `ack` = time to the sender's 200 (auth + access read + persist). This is what the
  user feels. `fanout` runs AFTER the ack (backgrounded) — it does NOT delay the user.
- **The SPEED-6 signal:** watch `persist`. Today it's a whole-document read-modify-write,
  so it grows with total chat history and serializes under concurrent senders (the
  global `_mutateQueue`). If `persist` is a few ms and flat → the JSONB store is fine at
  this scale, **skip SPEED-6.** If `persist` climbs into tens/hundreds of ms as history
  grows, or `ack` p95 balloons when several people send at once → **that's the trigger**
  to build SPEED-6.

## How to sample honestly
1. On a real RuStore-installed device (not emulator), send ~20 messages fast in a busy
   group chat; collect `chat.send-to-ack` p50/p95 from `[perf]` logs.
2. On the server, grep `[send-timing]` over the same burst; note `persist` and whether
   `ack` inflates under the concurrent senders.
3. Repeat once the chat has a large history (the JSONB store degrades with size).

If both client p95 and server `persist` stay under target across those → **1–5 already
delivered Telegram-grade send speed; SPEED-6 is premature optimization.** If not, build
SPEED-6 on a branch (PostgresStore overrides for addChatMessage + message reads +
markDelivered + unread + reactions + search + a JSONB→table migration; dedup on
(chatId, senderId, clientMessageId)); merge = deploy only on an explicit go, with prod
validation — it can't be fully proven locally (postgres-store tests run on a mock).
