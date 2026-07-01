#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE_NAME="${IOS_SIMULATOR_DEVICE:-iPhone 17 Pro}"
PROJECT_PATH="$ROOT_DIR/ios/SulavSleep.xcodeproj"
SCHEME="SulavSleep"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/ios/build/DerivedData}"

SIM_ID="$(xcrun simctl list devices available | awk -v name="$DEVICE_NAME" '
  $0 ~ name && $0 ~ /Shutdown|Booted/ {
    match($0, /\\(([0-9A-F-]+)\\)/, m)
    if (m[1] != "") {
      print m[1]
      exit
    }
  }
')"

if [[ -z "$SIM_ID" ]]; then
  echo "Could not find an available simulator named '$DEVICE_NAME'." >&2
  exit 1
fi

xcrun simctl boot "$SIM_ID" >/dev/null 2>&1 || true

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

APP_PATH="$(find "$DERIVED_DATA_PATH/Build/Products/${CONFIGURATION}-iphonesimulator" -maxdepth 1 -name 'SulavSleep.app' -print -quit)"
if [[ -z "$APP_PATH" ]]; then
  echo "Build succeeded but SulavSleep.app was not found." >&2
  exit 1
fi

xcrun simctl install "$SIM_ID" "$APP_PATH"
xcrun simctl launch "$SIM_ID" com.anonymous.sulav-sleep
