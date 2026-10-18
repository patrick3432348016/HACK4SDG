#!/bin/zsh
# Record one shot: ./tools/record_shot.sh <shot> <seconds> [extra arguments].
# Use -hour for fixed time; output ../video/footage2/<shot>.mp4. Build/install with run.sh first using the same SIM.
set -e
cd "$(dirname "$0")/.."
SHOT=$1; SECS=$2; shift 2
SIM=${SIM:-iPhone 17 Pro}
OUT=${OUT:-../video/footage2/$SHOT.mp4}
UDID=$(xcrun simctl list devices available | grep -A20 -- "-- iOS 26.5 --" | grep "    $SIM (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
# Fix battery/signal but retain actual time because Live Activity appearance resets time overrides.
xcrun simctl status_bar "$UDID" clear
xcrun simctl status_bar "$UDID" override --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4
xcrun simctl terminate "$UDID" hk.hack4sdg.streetwalk >/dev/null 2>&1 || true
xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$OUT" >/dev/null 2>&1 &
REC=$!
sleep 1.5
xcrun simctl launch --terminate-running-process "$UDID" hk.hack4sdg.streetwalk -demo -skipOnboarding -resetData -videoClean -offline -lang en -nickname "${NICK:-Uncle Lee}" -videoShot "$SHOT" "$@" >/dev/null
sleep "$SECS"
kill -INT $REC; wait $REC 2>/dev/null || true
echo "$OUT"
