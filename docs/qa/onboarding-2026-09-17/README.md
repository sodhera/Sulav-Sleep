# Narrative onboarding verification — September 17, 2026

## Feedback revision

The later revision removes the lifetime footnote and analytics status, splits
four symptom sentences into two short chapters, and paints unrevealed letters
transparent in a full-width UIKit label. This keeps word breaks fixed while
typing. Sentences alternate white/yellow from white; the slider reads
**Continue**. The demo now loops home → TikTok tap → logo losing saturation →
shield, with no feed. Its page has only the requested question, phone, and
**Yes** button. The simulator screenshots are [symptom story](story-revised.jpg),
[cost](cost-revised.jpg), [encouragement](plan-revised.jpg), and [demo](demo-revised.jpg).
They confirm readable text and controls on iPhone 17 Pro at default text size.
The final consequence chapter now uses Continue to open the goal options
directly; the separately typed goal question was removed after it caused a
visible title-to-options jump. A simulator accessibility activation of the
last chapter's Continue control opened the [goal options](goal-options-direct.jpg)
with one stable title and four choices.

The revised iPhone 17 Pro simulator build, `scripts/test-onboarding.sh`, and
`git diff --check` passed. Screenshots were taken from direct review routes;
the original full-navigation evidence below predates this revision. Physical
iPhone Screen Time behavior and haptics remain outside simulator proof.

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

The older `symptoms.png` screenshot predates the short chapter revision, and
the older `demo.png` and video description above predate the grayscale recut.

## Release requirement

The requested always-on analytics behavior replaces an existing optional policy.
Reconcile the public privacy disclosure and App Store answers before distribution.
The simulator video is a recreation; do not describe it as real TikTok enforcement.
