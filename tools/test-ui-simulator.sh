#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP_PATH="$PWD/build/DARBadgeTests.app"
mkdir -p "$APP_PATH"
SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
# GitHub's standard macOS image is Apple Silicon; match its simulator architecture.
xcrun --sdk iphonesimulator clang -target "$(uname -m)-apple-ios17.0-simulator" \
  -isysroot "$SDK_PATH" -fobjc-arc -fblocks -DDAR_TESTING=1 -Isrc \
  -Wall -Wextra -Werror -framework Foundation -framework UIKit -framework CoreGraphics -framework AVFoundation -framework CoreMedia -framework ImageIO -framework Photos -framework UniformTypeIdentifiers \
  src/DouyinAntiRecall.m src/DARCache.m src/DARBadge.m src/DAROptions.m src/DARRuntime.m src/DARSettings.m src/DARIP.m src/DARAudio.m src/DARMedia.m src/DARPhotoDate.m tests/FeatureUITests.m tests/BadgeUITests.m \
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
python3 - "$DEVICE_ID" <<'PYBOOT'
import subprocess, sys
subprocess.run(['xcrun', 'simctl', 'bootstatus', sys.argv[1], '-b'], check=True, timeout=180)
PYBOOT
xcrun simctl install "$DEVICE_ID" "$APP_PATH"
python3 - "$DEVICE_ID" <<'PYLAUNCH'
import pathlib, subprocess, sys, time
identifier = sys.argv[1]
container = subprocess.check_output(['xcrun', 'simctl', 'get_app_container', identifier,
                                     'local.douyin.badge-tests', 'data'], text=True, timeout=60).strip()
result = pathlib.Path(container) / 'Library/Caches/badge-result.txt'
result.unlink(missing_ok=True)
command = ['xcrun', 'simctl', 'launch', '--terminate-running-process',
           identifier, 'local.douyin.badge-tests']
with open('build/badge-launch.log', 'w') as launch_log:
    process = subprocess.Popen(command, stdout=launch_log, stderr=subprocess.STDOUT, text=True)
    status = ''
    deadline = time.monotonic() + 240
    while time.monotonic() < deadline:
        current = result.read_text() if result.exists() else ''
        if current != status:
            status = current
            print(status, flush=True)
        if status.startswith(('PASS:', 'FAIL:')):
            break
        if process.poll() not in (None, 0):
            break
        time.sleep(2)
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
print(pathlib.Path('build/badge-launch.log').read_text())
pathlib.Path('build/badge-ui-tests.log').write_text(status)
if not status.startswith('PASS: UIKit badge placement'):
    raise SystemExit('UIKit test app failed or timed out. Last checkpoint: ' + (status or 'not started'))
PYLAUNCH
