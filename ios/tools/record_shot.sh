#!/bin/zsh
# 录宣传片单个镜头：./tools/record_shot.sh <镜头> <秒数> [额外参数…]
# 要定钟点就加 -hour 16 之类。输出 ../video/footage2/<镜头>.mp4。要先用 run.sh 编译装好（SIM 同 run.sh 一样）。
set -e
cd "$(dirname "$0")/.."
SHOT=$1; SECS=$2; shift 2
SIM=${SIM:-iPhone 17 Pro}
OUT=${OUT:-../video/footage2/$SHOT.mp4}
UDID=$(xcrun simctl list devices available | grep -A20 -- "-- iOS 26.5 --" | grep "    $SIM (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
# 状态栏：电量、信号固定；时间用真时间（Live Activity 一出现系统就会重设覆盖嘅时间，前后会跳）
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
