# AGENTS.md instructions

We want everything to be documented such that later on Codex has an idea about what we are doing and what we were trying to do.

We also want very frequent commits.

We also need proper developer style documentation for usage and mechanisms too.

Before changing the app UI, read `DESIGN.md` and update it when design decisions change.

## gstack

Use the gstack `/browse` skill for all web browsing. Never use `mcp__claude-in-chrome__*` tools.

Available gstack skills in Codex: `/office-hours`, `/plan-ceo-review`, `/plan-eng-review`, `/plan-design-review`, `/design-consultation`, `/review`, `/ship`, `/browse`, `/qa`, `/qa-only`, `/design-review`, `/setup-browser-cookies`, `/retro`, `/investigate`, `/document-release`, `/careful`, `/freeze`, `/guard`, `/unfreeze`, `/gstack-upgrade`.

## iOS

This project is a native SwiftUI iOS app (the flagship client). `ios/SulavSleep.xcodeproj` is the source of truth.

Before changing native UI or app behavior:

- Read `DESIGN.md`.
- Keep developer documentation in `docs/development.md` and product intent in `docs/product-brief.md` current.
- Prefer the `build-ios-apps` skills for SwiftUI, Liquid Glass, simulator build/run, App Intents, performance, and leak work.
- Build with `xcodebuild` or `./scripts/run-ios-simulator.sh`; do not reintroduce Expo/React Native unless explicitly requested.

## Android

`android/` is a native Kotlin + Jetpack Compose port (core MVP, July 2026)
sharing the same Supabase backend and the `sleep_profile` user-metadata sync.
Read `docs/android.md` before touching it — it carries the iOS↔Android file
parity map and the phase-2 list (app blocking, paywall, Google sign-in,
widgets). Build with `cd android && ./gradlew assembleDebug`. Service keys
live in gitignored `android/secrets.properties` (template committed as
`secrets.properties.example`). The same DESIGN.md rules apply; Android
renders the fallback glass grammar, not Liquid Glass.
