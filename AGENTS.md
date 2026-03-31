# Lineage agent guide

## Mission
Ship a reliable Flutter MVP for Android and web as fast as possible. iOS later.

## Product
Lineage is a family tree + private family social network for relatives.
Short-term MVP:
- auth and onboarding
- family tree CRUD and viewing
- 1:1 text chat
- notifications
- basic media upload
- stable Android and web builds

Voice/video calls are phase 2 unless the task explicitly targets calls.

## Platform reality
The product must work for users in Russia.
Treat Firebase cloud and hosted Supabase as legacy dependencies to phase out if they create availability risk.

## Preferred backend direction
Prefer self-hostable or Russian-friendly infrastructure.
Default target direction:
- PostgreSQL
- object storage
- own auth or self-hosted auth
- own realtime/chat backend
- Android push path that does not depend only on FCM

Self-hosted Supabase is acceptable if it reduces migration time.
Avoid big-bang rewrites. First create abstractions and adapters, then migrate feature by feature.

## Engineering rules
- Be autonomous inside the task.
- Do not stop after analysis; implement, verify, and summarize.
- Do not ask follow-up questions unless truly blocked.
- Inspect the existing code before editing.
- Prefer minimal, reversible changes over wide refactors.
- Keep screens thin; move logic into services/repositories/providers.
- Do not introduce duplicate architecture.
- Preserve or improve Russian UI text quality when touching user-facing strings.

## Verification
Before finishing a task:
- run dart format on changed files
- run flutter analyze
- run relevant flutter tests
- if web UI changed, run a quick browser smoke test
- summarize changed files, what passed, and remaining risks

## Commands
- flutter pub get
- dart format .
- flutter analyze
- flutter test

## Browser testing
Use Playwright only for web smoke tests, not for Android-native flows.