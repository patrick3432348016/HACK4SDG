#!/bin/zsh
# 编译真机版并装到所有用数据线插着的 iPhone，然后打开 App。
# 用法：cd ios && zsh tools/install_device.sh
# 签名用 Xcode 里登录的 Apple ID（免费账号也可以）；有几个账号时可指定：TEAM=XXXXXXXXXX zsh tools/install_device.sh
# 免费账号装的 App 7 天后打不开，到时插线重跑一次即可。
set -e
cd "$(dirname "$0")/.."
OWNER_TEAM=57KPZRQR4A   # 本项目原作者的团队，用原本的 App 编号
APP=build/DDdevice/Build/Products/Debug-iphoneos/StreetWalk.app
mkdir -p build

if [[ "$(xcode-select -p 2>/dev/null)" != *Xcode*.app* ]]; then
  echo "找不到 Xcode：请先从 App Store 安装 Xcode，打开一次让它装完组件。"
  echo "（装好后仍报这句，在终端运行：sudo xcode-select -s /Applications/Xcode.app）"; exit 1
fi

# 签名团队：没指定就用 Xcode 里登录的第一个（有付费团队优先用付费的）
if [[ -z "$TEAM" ]]; then
  TEAM=$(defaults export com.apple.dt.Xcode - 2>/dev/null | python3 -c "
import sys, plistlib
try: d = plistlib.loads(sys.stdin.buffer.read())
except Exception: sys.exit()
teams = [t for ts in d.get('IDEProvisioningTeamByIdentifier', {}).values() for t in ts]
teams.sort(key=lambda t: t.get('isFreeProvisioningTeam', 0))
if teams: print(teams[0]['teamID'])
")
fi
if [[ -z "$TEAM" ]]; then
  echo "Xcode 还没登录 Apple ID：打开 Xcode → 设置（Settings）→ Apple 账户（Apple Accounts）→ 左下角 + → 登录你的 Apple ID，再重跑。"; exit 1
fi
# 免费账号的 App 编号全世界不能重复，别人的账号就在后面加上团队号
if [[ "$TEAM" == "$OWNER_TEAM" ]]; then PREFIX=hk.hack4sdg; else PREFIX=hk.hack4sdg.t${TEAM:l}; fi
BUNDLE=$PREFIX.streetwalk
echo "签名团队 $TEAM，App 编号 $BUNDLE"

# 找插着线的 iPhone
devices() {
  local J=$(mktemp)
  xcrun devicectl list devices --json-output "$J" >/dev/null 2>&1
  python3 -c "
import json
for x in json.load(open('$J'))['result']['devices']:
    c = x['connectionProperties']
    if c.get('transportType') == 'wired':
        print(x['identifier'], c.get('pairingState'), x['hardwareProperties']['udid'], x['deviceProperties'].get('name', 'iPhone'))
"
  rm -f "$J"
}
LIST=$(devices)
# 第一次插的手机要先配对（手机上会弹「要信任这台电脑吗？」）
for id in $(echo "$LIST" | awk '$2 != "paired" {print $1}'); do
  echo "请在手机上按「信任」并输入锁屏密码……"
  xcrun devicectl manage pair --device "$id" >/dev/null 2>&1 || true
done
[[ -n "$(echo "$LIST" | awk '$2 != "paired"')" ]] && LIST=$(devices)
LIST=$(echo "$LIST" | awk '$2 == "paired"')
if [[ -z "$LIST" ]]; then
  echo "没有找到插着的 iPhone：请用数据线插上、解锁手机、按「信任」，再重跑。"; exit 1
fi

for line in ${(f)LIST}; do
  read id state udid name <<< "$line"
  echo "== $name"
  mode=$(xcrun devicectl device info details --device "$id" 2>/dev/null | awk -F': ' '/developerModeStatus/ {print $2}')
  if [[ "$mode" == disabled ]]; then
    echo "   要先打开开发者模式：手机 设置 → 隐私与安全性 → 开发者模式 → 打开 → 重新启动；"
    echo "   重启解锁后按「打开」，再重跑这个命令。"
    continue
  fi
  if ! xcodebuild -project StreetWalk.xcodeproj -scheme StreetWalk -configuration Debug \
      -destination "id=$udid" -derivedDataPath build/DDdevice \
      -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
      DEVELOPMENT_TEAM=$TEAM BUNDLE_ID_PREFIX=$PREFIX build -quiet > build/device_build.log 2>&1; then
    echo "   编译失败，最后几行："; grep -E "error" build/device_build.log | tail -5
    echo "   （完整记录在 ios/build/device_build.log）"; exit 1
  fi
  xcrun devicectl device install app --device "$id" "$APP" >/dev/null
  if xcrun devicectl device process launch --device "$id" $BUNDLE 2>&1 | grep -q Launched; then
    echo "   已安装并打开"
  else
    echo "   已安装。第一次要信任开发者：手机 设置 → 通用 → VPN 与设备管理 → 点开发者那一栏 → 信任，然后点「街坊行」图标打开。"
  fi
done
