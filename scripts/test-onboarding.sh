#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output_dir="$(mktemp -d)"
trap 'rm -rf "$output_dir"' EXIT
swiftc ios/SulavSleep/SleepStreak.swift ios/SulavSleep/SleepModels.swift \
  ios/SulavSleepTests/OnboardingModelsTests.swift -o "$output_dir/onboarding-tests"
"$output_dir/onboarding-tests"
