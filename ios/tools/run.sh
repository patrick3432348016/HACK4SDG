#!/bin/sh
# 编译、安装并启动到 iPhone 17（iOS 26.5）模拟器。参数原样传给 App，例如 ./tools/run.sh -hour 15 -stats
set -e
cd "$(dirname "$0")/.."
DEST='platform=iOS Simulator,name=iPhone 17,OS=26.5'
xcodebuild -project StreetWalk.xcodeproj -scheme StreetWalk -destination "$DEST" -derivedDataPath build/DD build -quiet 2>&1 | grep -E "error:|warning: .*StreetWalk/" || true
APP=build/DD/Build/Products/Debug-iphonesimulator/StreetWalk.app
[ -d "$APP" ] || { echo "build failed"; exit 1; }
UDID=$(xcrun simctl list devices available | grep -A20 -- "-- iOS 26.5 --" | grep "iPhone 17 (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl location "$UDID" set 22.5044,114.1563 >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl terminate "$UDID" hk.hack4sdg.streetwalk >/dev/null 2>&1 || true
xcrun simctl launch "$UDID" hk.hack4sdg.streetwalk "$@"
echo "UDID=$UDID"
