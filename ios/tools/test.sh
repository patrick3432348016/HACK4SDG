#!/bin/bash
# Xcode tests cover maps, landmarks, solar/shade, routing, intents, streaks, persistence, demo data and walking logic.
# Return nonzero on build/test failure; pipefail preserves xcodebuild status without treating empty grep output as failure.
set -eo pipefail
cd "$(dirname "$0")/.."
SIM=${SIM:-iPhone 17}
xcodebuild test -project StreetWalk.xcodeproj -scheme StreetWalk -destination "platform=iOS Simulator,name=$SIM,OS=26.5" -derivedDataPath build/DD 2>&1 \
  | { grep -E "error:|✘|Test run with|passed after|failed after" | grep -vE "^✔ Test [^r]"; true; }
