# Narrative onboarding verification — September 17, 2026

## Passed

- Debug iPhone 17 Pro / iOS 26.5 simulator build.
- Generic iOS device-target Debug compile with signing disabled, including the
  non-simulator analytics implementation. This is compile evidence, not device QA.
- `scripts/test-onboarding.sh`: untouched/zero/out-of-range dial validation,
  annual and lifetime estimates, exact-minute profile round-trip, old enum values.
- `scripts/test-streak.sh`: 25/25 existing checks.
- Normal Welcome → Get started route on an existing simulator installation.
  Draft recovered; an older undesired morning answer routed back to that question.
  Name cleared → Continue disabled; restored name → Continue enabled.
- Navigated name → dial → four symptoms → story → goal → desired morning →
  bedtime → wake → personalized encouragement → demo → commitment → account.
- Story unlock appeared after text completed. Accessible unlock actions advanced
  chapters. Selecting all four symptoms produced all four matching sentences.
- 60-minute input rendered 21,900 minutes/year and 1,216 days over the disclosed
  illustrative 80-year horizon. Desired Energized produced "6:30 AM feeling energized".
- Accessible Commit action reached the account screen; no account was created.
- Bundled video frames inspected: home, visible TikTok tap, launch, feed, shield.
  Corrected duplicate system status bar before final capture. Clip is 6.58 seconds,
  H.264, 604×1312, silent, approximately 207 KB. Playback uses AVPlayerLooper.
- City screenshot confirms midnight sky, stars, and brighter existing warm windows.

## Scope of proof

This was a resumed installation, not a pristine clean-install test. Physical dial
and swipe gestures were not exercised end-to-end because the computer-use
simulator window capture was too small/intermittent; progression was checked
through accessibility actions. Two-second hold/release timing, device haptics,
VoiceOver/Reduce Motion on-device behavior, and real Screen Time blocking remain
physical-iPhone QA. No authentication, purchase, deployment, policy publication,
or App Store upload occurred. Simulator event upload is disabled.

The symptom chapter screenshot predates the final 22pt four-sentence typography
adjustment, which reduces scrolling. Other narrative pages retain 28pt type.
The symptoms screenshot predates the final warm-window color enhancement.

## Release requirement

The requested always-on analytics behavior replaces an existing optional policy.
Reconcile the public privacy disclosure and App Store answers before distribution.
The simulator video is a recreation; do not describe it as real TikTok enforcement.
