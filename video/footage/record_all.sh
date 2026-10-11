#!/bin/zsh
# 录宣传片素材：iPhone Air 模拟器，无字幕、全分辨率。每段记录录屏开始时刻和 App 日志（带时间戳），方便按脚本秒数切片。
# 用法：video/footage/record_all.sh [段名...]   默认全部
set -e
cd "$(dirname "$0")/../../ios"
OUT=../video/footage/raw
SIM_NAME="iPhone Air"
APPID=hk.hack4sdg.streetwalk
UDID=$(SIM="$SIM_NAME" ./tools/run.sh -demo -skipOnboarding -hour 10 | grep UDID= | sed 's/UDID=//')
[ -n "$UDID" ] || { echo "编译或启动失败"; exit 1; }
xcrun simctl terminate "$UDID" $APPID || true
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4
xcrun simctl ui "$UDID" appearance light

rec() {   # rec 名 秒数 参数...
  local name=$1 secs=$2; shift 2
  echo "== $name ($secs s): $*"
  xcrun simctl terminate "$UDID" $APPID >/dev/null 2>&1 || true
  # 模拟器有时会自己关机（10-11 录 main 时遇到）：每段前确保开着，并重设状态栏
  xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
  xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularBars 4
  xcrun simctl location "$UDID" set 22.5044,114.1563 >/dev/null 2>&1 || true
  sleep 1
  xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$OUT/$name.mov" > "$OUT/$name.rec.log" 2>&1 &
  local rp=$!
  while ! grep -q "Recording started" "$OUT/$name.rec.log" 2>/dev/null; do sleep 0.1; done
  python3 -c 'import time;print("%.3f"%time.time())' > "$OUT/$name.start"
  sleep 1
  xcrun simctl launch --console-pty --terminate-running-process "$UDID" $APPID "$@" 2>&1 \
    | perl -MTime::HiRes=time -ne '$|=1; printf "%.3f %s", time, $_' > "$OUT/$name.app.log" &
  local lp=$!
  sleep $secs
  kill -INT $rp; wait $rp 2>/dev/null || true
  kill $lp 2>/dev/null || true
  xcrun simctl terminate "$UDID" $APPID >/dev/null 2>&1 || true
  sleep 2
  local sz=$(stat -f %z "$OUT/$name.mov" 2>/dev/null || echo 0)
  local st=$(xcrun simctl list devices | grep "$UDID" | grep -c Booted)
  echo "   -> $name.mov ${sz} bytes, booted=$st"
}

want() { [ $# -eq 0 ] || [[ " $ALL " == *" $1 "* ]]; }
ALL="$*"
[ -z "$ALL" ] && ALL="main script2 script3 onboarding bump island_banner island_find cmn"
for n in ${=ALL}; do
  case $n in
    main)          rec main 112 -demo -skipOnboarding -resetData -script -hour 10 ;;
    script2)       rec script2 38 -demo -skipOnboarding -resetData -script2 -hour 10 ;;
    script3)       rec script3 76 -demo -skipOnboarding -resetData -script3 -hour 10 ;;
    onboarding)    rec onboarding 34 -demo -resetData -resetOnboarding -scriptOnboarding -hour 10 ;;
    bump)          rec bump 46 -demoMode NO -skipOnboarding -resetData -scriptBump -bumpScanCode jiefong:0123456789abcdef0123456789abcdef ;;
    island_banner) rec island_banner 28 -demo -skipOnboarding -resetData -scriptIsland banner -hour 10 ;;
    island_find)   rec island_find 22 -demo -skipOnboarding -resetData -scriptIsland find -hour 10 ;;
    cmn)           rec cmn 40 -demo -skipOnboarding -resetData -script -hour 10 -lang cmn ;;
  esac
done
xcrun simctl status_bar "$UDID" clear
ls -la $OUT
