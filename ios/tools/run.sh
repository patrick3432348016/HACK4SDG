#!/bin/sh
# Build/install/launch on the iPhone 17 iOS 26.5 simulator, forwarding App arguments unchanged.
# Select another simulator with SIM="iPhone 17 Pro" ./tools/run.sh ...; use separate simulators for parallel work.
# Test location flow with ALWAYS=1 ./tools/run.sh -skipOnboarding -simWalk and xcrun simctl location.
set -e
cd "$(dirname "$0")/.."
SIM=${SIM:-iPhone 17}
DEST="platform=iOS Simulator,name=$SIM,OS=26.5"
LOG=build/last-build.log
mkdir -p build
# Stop on build failure instead of installing a stale previous build.
if ! xcodebuild -project StreetWalk.xcodeproj -scheme StreetWalk -destination "$DEST" -derivedDataPath build/DD build -quiet > "$LOG" 2>&1; then
  grep -E "error:" "$LOG" | head -20
  echo "build failed（完整日志：ios/$LOG）"
  exit 1
fi
grep -E "warning: .*StreetWalk/" "$LOG" | sort -u || true
APP=build/DD/Build/Products/Debug-iphonesimulator/StreetWalk.app
UDID=$(xcrun simctl list devices available | grep -A20 -- "-- iOS 26.5 --" | grep "    $SIM (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl location "$UDID" set 22.5044,114.1563 >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP"
# NOGRANT=1 preserves permission prompts; ALWAYS=1 grants Always for background tests with -simWalk.
if [ -n "$ALWAYS" ]; then
  xcrun simctl privacy "$UDID" grant location-always hk.hack4sdg.streetwalk >/dev/null 2>&1 || true
elif [ -z "$NOGRANT" ]; then
  xcrun simctl privacy "$UDID" grant location hk.hack4sdg.streetwalk >/dev/null 2>&1 || true
fi
xcrun simctl terminate "$UDID" hk.hack4sdg.streetwalk >/dev/null 2>&1 || true
# Terminate an existing process before launch because background location may have started it without requested arguments.
xcrun simctl launch --terminate-running-process "$UDID" hk.hack4sdg.streetwalk "$@"
echo "UDID=$UDID"
