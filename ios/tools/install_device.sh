#!/bin/zsh
# 编译真机版并装到所有用数据线插着、已开开发者模式的 iPhone，然后打开 App。
# 用法：cd ios && ./tools/install_device.sh
# 免费团队的描述文件 7 天过期，过期后重跑一次即可。
set -e
cd "$(dirname "$0")/.."
TEAM=57KPZRQR4A
BUNDLE=hk.hack4sdg.streetwalk
APP=build/DDdevice/Build/Products/Debug-iphoneos/StreetWalk.app
J=$(mktemp)
xcrun devicectl list devices --json-output "$J" >/dev/null 2>&1
DEVICES=("${(@f)$(python3 -c "
import json
for x in json.load(open('$J'))['result']['devices']:
    c = x['connectionProperties']
    if c.get('pairingState') == 'paired' and c.get('transportType') == 'wired':
        print(x['identifier'] + ' ' + x['hardwareProperties']['udid'] + ' ' + x['deviceProperties'].get('name', ''))
")}")
rm -f "$J"
if [[ -z "${DEVICES[1]}" ]]; then
  echo "没有找到插着的 iPhone：请插上数据线、解锁手机、按「信任」。"; exit 1
fi
for line in "${DEVICES[@]}"; do
  id=${line%% *}; rest=${line#* }; udid=${rest%% *}; name=${rest#* }
  echo "== $name"
  xcodebuild -project StreetWalk.xcodeproj -scheme StreetWalk -configuration Debug \
    -destination "id=$udid" -derivedDataPath build/DDdevice \
    -allowProvisioningUpdates -allowProvisioningDeviceRegistration DEVELOPMENT_TEAM=$TEAM \
    build -quiet > build/device_build.log 2>&1 || { echo "编译失败，看 ios/build/device_build.log"; exit 1; }
  xcrun devicectl device install app --device "$id" "$APP" >/dev/null
  if xcrun devicectl device process launch --device "$id" $BUNDLE 2>&1 | grep -q Launched; then
    echo "   已安装并打开"
  else
    echo "   已安装；打不开的话：手机 设置 → 通用 → VPN 与设备管理 → 信任开发者"
  fi
done
