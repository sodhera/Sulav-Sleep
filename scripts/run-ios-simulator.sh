#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="${TMPDIR:-/tmp}/sulav-sleep-tracker-run"
DEVICE_NAME="${IOS_SIMULATOR_DEVICE:-iPhone 17 Pro}"

mkdir -p "$RUN_DIR"

rsync -a --delete \
  --exclude ".git" \
  --exclude ".expo" \
  --exclude ".gstack" \
  --exclude "ios" \
  --exclude "android" \
  --exclude "node_modules" \
  "$ROOT_DIR"/ "$RUN_DIR"/

cd "$RUN_DIR"
npm install

RCT_USE_PREBUILT_RNCORE=0 \
RCT_USE_RN_DEP=0 \
npx expo run:ios --device "$DEVICE_NAME"
