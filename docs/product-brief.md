# Sulav Sleep Product Brief

Sulav Sleep is a bedtime commitment app. The product is not just a sleep journal; the core behavior is that one hour before bedtime the app enters Wind Down, blocks distracting apps where the operating system allows it, encourages warm/red display settings, and exposes only a small set of calming or emergency actions.

## Current prototype

The first app is intentionally simple and simulator friendly. It demonstrates the intended product shape without native blocking integrations:

- Wind Down begins one hour before the target bedtime.
- Sleep Lock represents the six-hour no-phone commitment window.
- A night opening is logged as an interruption.
- Morning check-in captures energy, mood, and whether the user woke rested.
- Dream check-in captures a short dream note.
- The visual system uses warm, rounded, low-stimulation surfaces designed to remain legible when an iOS Color Tint or red light filter is active.

## Platform mechanism assumptions

iOS has user-accessible Color Filters in Accessibility settings, including a tint mode that can be configured as a red filter. The app should not assume it can silently toggle that system setting. The likely iOS path is guided setup plus Screen Time-related APIs for app shielding.

Android has more flexible system settings and app-usage surfaces, but the production blocker still needs explicit user permissions and careful policy review.

Until those integrations are implemented, the app should present Wind Down and Sleep Lock as product states and keep enforcement code behind platform-specific modules.
