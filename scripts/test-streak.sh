#!/bin/bash
# Compile and run the streak rule tests.
#
# `ios/SulavSleep/SleepStreak.swift` is deliberately dependency-free (Foundation
# only), so it and its tests compile as a plain Swift executable — no Xcode test
# target, no simulator, ~2 seconds. Keep SleepStreak.swift free of SwiftUI and
# of the app's model types and this keeps working.
set -euo pipefail

cd "$(dirname "$0")/.."
out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

swiftc -O \
  ios/SulavSleep/SleepStreak.swift \
  ios/SulavSleepTests/SleepStreakTests.swift \
  -o "$out/streak-tests"

"$out/streak-tests"
