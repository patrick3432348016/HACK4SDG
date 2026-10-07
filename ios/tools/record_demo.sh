#!/bin/zsh
# 录演示视频：编译安装 → 状态栏固定 9:41 → 录屏跑 -script -captions（约 105 秒）→ 用 ffmpeg 压成 1280 高的 H.264。
# 用法：./tools/record_demo.sh [输出.mp4]   默认 ../docs/demo/streetwalk_demo.mp4
# 注意：录之前关掉其他开着的模拟器（几台一齐渲染 3D 场景时，录屏会令界面更新跟唔上，横幅、卡片会卡住）。
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
