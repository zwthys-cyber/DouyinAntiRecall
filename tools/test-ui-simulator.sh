#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP_PATH="$PWD/build/DARBadgeTests.app"
mkdir -p "$APP_PATH"
SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
# GitHub's standard macOS image is Apple Silicon; match its simulator architecture.
xcrun --sdk iphonesimulator clang -target "$(uname -m)-apple-ios17.0-simulator" \
  -isysroot "$SDK_PATH" -fobjc-arc -fblocks -DDAR_TESTING=1 -Isrc \
  -Wall -Wextra -Werror -framework Foundation -framework UIKit -framework CoreGraphics \
  src/DouyinAntiRecall.m src/DARCache.m src/DARBadge.m tests/BadgeUITests.m \
  -o "$APP_PATH/DARBadgeTests"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string local.douyin.badge-tests' "$APP_PATH/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string DARBadgeTests' "$APP_PATH/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleName string DARBadgeTests' "$APP_PATH/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$APP_PATH/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleVersion string 1' "$APP_PATH/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 1.0' "$APP_PATH/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :MinimumOSVersion string 17.0' "$APP_PATH/Info.plist"
codesign --force --sign - --timestamp=none "$APP_PATH"
xcrun simctl list devices available -j > build/simulator-devices.json
DEVICE_ID="$(python3 - <<'PY'
import json
with open('build/simulator-devices.json') as f:
    devices = json.load(f)['devices']
for runtime, group in devices.items():
    if '.iOS-' not in runtime:
        continue
    for device in group:
        if device.get('isAvailable') and device['name'].startswith('iPhone'):
            print(device['udid'])
            raise SystemExit(0)
raise SystemExit('No available iOS simulator on this GitHub runner')
PY
)"
xcrun simctl boot "$DEVICE_ID" || true
xcrun simctl bootstatus "$DEVICE_ID" -b
xcrun simctl install "$DEVICE_ID" "$APP_PATH"
xcrun simctl launch --console --terminate-running-process "$DEVICE_ID" local.douyin.badge-tests \
  | tee build/badge-ui-tests.log
# simctl may return success even if the app exits with an assertion failure.
rg -q 'PASS: UIKit badge placement' build/badge-ui-tests.log
