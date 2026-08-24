#!/bin/bash
# Compile and run the morning card's copy rule tests.
#
# `ios/SulavSleep/SleepWakeCelebration.swift` is deliberately dependency-free
# (Foundation only), so it and its tests compile as a plain Swift executable —
# no Xcode test target, no simulator, ~2 seconds. Keep
# SleepWakeCelebration.swift free of SwiftUI and of the app's model types and
# this keeps working.
set -euo pipefail

cd "$(dirname "$0")/.."
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

swiftc -O \
  ios/SulavSleep/SleepWakeCelebration.swift \
  ios/SulavSleepTests/SleepWakeCelebrationTests.swift \
  -o "$out/wake-celebration-tests"

"$out/wake-celebration-tests"
