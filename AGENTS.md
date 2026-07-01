# AGENTS.md instructions

We want everything to be documented such that later on Codex has an idea about what we are doing and what we were trying to do.

We also want very frequent commits.

We also need proper developer style documentation for usage and mechanisms too.

Before changing the app UI, read `DESIGN.md` and update it when design decisions change.

## gstack

Use the gstack `/browse` skill for all web browsing. Never use `mcp__claude-in-chrome__*` tools.

Available gstack skills in Codex: `/office-hours`, `/plan-ceo-review`, `/plan-eng-review`, `/plan-design-review`, `/design-consultation`, `/review`, `/ship`, `/browse`, `/qa`, `/qa-only`, `/design-review`, `/setup-browser-cookies`, `/retro`, `/investigate`, `/document-release`, `/careful`, `/freeze`, `/guard`, `/unfreeze`, `/gstack-upgrade`.

## iOS

This project is now a native SwiftUI iOS app. `ios/SulavSleep.xcodeproj` is the source of truth.

Before changing native UI or app behavior:

- Read `DESIGN.md`.
- Keep developer documentation in `docs/development.md` and product intent in `docs/product-brief.md` current.
- Prefer the `build-ios-apps` skills for SwiftUI, Liquid Glass, simulator build/run, App Intents, performance, and leak work.
- Build with `xcodebuild` or `./scripts/run-ios-simulator.sh`; do not reintroduce Expo/React Native unless explicitly requested.
