#!/bin/sh
# Xcode 单元测试（StreetWalkTests）：地图解析与风格化、地标、太阳与遮荫、寻路、语音意图、连续天数、持久化、示範数据。
set -e
cd "$(dirname "$0")/.."
SIM=${SIM:-iPhone 17}
xcodebuild test -project StreetWalk.xcodeproj -scheme StreetWalk -destination "platform=iOS Simulator,name=$SIM,OS=26.5" -derivedDataPath build/DD 2>&1 \
  | grep -E "error:|✘|Test run with|passed after|failed after" | grep -vE "^✔ Test " || true
