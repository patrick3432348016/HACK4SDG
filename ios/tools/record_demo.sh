#!/bin/zsh
# Build/install, fix status time to 9:41, record -script -captions for about 105 seconds, then encode 1280-high H.264 with ffmpeg.
# Usage: ./tools/record_demo.sh [output.mp4], default ../docs/demo/streetwalk_demo.mp4.
# Close other simulators before recording; concurrent 3D rendering can stall UI, banners and cards.
set -e
cd "$(dirname "$0")/.."
OUT=${1:-../docs/demo/streetwalk_demo.mp4}
RAW=build/demo_raw.mp4
mkdir -p "$(dirname "$OUT")" build
UDID=$(./tools/run.sh -demo -skipOnboarding -hour 10 | grep UDID= | sed 's/UDID=//')
[ -n "$UDID" ] || { echo "编译或启动失败"; exit 1; }
xcrun simctl terminate "$UDID" hk.hack4sdg.streetwalk || true
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4
sleep 1
xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$RAW" >/dev/null 2>&1 &
REC=$!
sleep 2
xcrun simctl launch "$UDID" hk.hack4sdg.streetwalk -demo -skipOnboarding -script -captions -hour 10 >/dev/null
sleep 108
kill -INT $REC; wait $REC 2>/dev/null || true
xcrun simctl status_bar "$UDID" clear
ffmpeg -y -v error -ss 3 -i "$RAW" -vf "scale=-2:1280,fps=30" -c:v libx264 -preset slow -crf 23 -pix_fmt yuv420p -movflags +faststart "$OUT"
echo "视频：$OUT（$(du -h "$OUT" | cut -f1)）"
