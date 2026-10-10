#!/bin/bash
# Xcode 单元测试（StreetWalkTests）：地图解析与风格化、地标、太阳与遮荫、寻路、语音意图、连续天数、持久化、示範数据、散步逻辑。
# 编译或测试失败时返回非零（pipefail：取 xcodebuild 的退出码，grep 冇输出都唔会当失败）。
set -eo pipefail
cd "$(dirname "$0")/.."
SIM=${SIM:-iPhone 17}
xcodebuild test -project StreetWalk.xcodeproj -scheme StreetWalk -destination "platform=iOS Simulator,name=$SIM,OS=26.5" -derivedDataPath build/DD 2>&1 \
  | { grep -E "error:|✘|Test run with|passed after|failed after" | grep -vE "^✔ Test [^r]"; true; }
