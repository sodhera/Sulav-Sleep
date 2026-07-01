# Sulav Sleep Product Brief

Sulav Sleep is a bedtime commitment app. The current native iOS version focuses on a calm nightly loop: choose a sleep schedule, start a sleep session, wake up, and review the rhythm of recent nights.

## Current Product

- Onboarding collects name, usual bedtime, and usual wake time.
- Home shows a greeting, tonight's schedule, `Sleep Now`, `Set Bedtime`, last-night duration, score, and current streak.
- Active sleep mode hides navigation, shows elapsed sleep time, and provides a single `Wake up` action.
- Reports shows a seven-night wave chart, average duration, average score, and a history list.
- Settings lets the user edit their name, open schedule editing, or reset all data.

## Native Direction

The app is now SwiftUI-first instead of React Native/Expo. Native iOS is the right base for the next product steps because the app will need system-level integrations over time: App Intents, Shortcuts, widgets, Screen Time-style permissions, and iOS visual language like Liquid Glass.

## Storage

The prototype is local-first. It uses UserDefaults-backed JSON and no backend:

- Profile: `sulav.profile.v1`
- Sessions: `sulav.sessions.v1`
- Active session: `sulav.active.v1`

This keeps the app simulator-friendly while preserving the behavior from the React prototype.

## Platform Mechanism Assumptions

iOS does not allow an app to silently toggle Accessibility Color Filters or arbitrarily block other apps without explicit user-controlled system permissions. Future enforcement work should live behind native platform modules and be documented before implementation.

The first native system surface is App Intents:

- Start sleep from Shortcuts/Siri-compatible surfaces.
- Open Sulav Sleep from system surfaces.

## Visual Direction

The app should still feel like a warm bedside instrument:

- Low stimulation at night.
- Legible under red tint.
- Sparse during active sleep.
- Native Liquid Glass for controls and grouped surfaces on iOS 26+.
- Material fallback for older supported iOS versions.

