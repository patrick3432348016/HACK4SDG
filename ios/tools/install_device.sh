#!/bin/zsh
# Build, install and launch the device App on all cable-connected iPhones.
# Usage: cd ios && zsh tools/install_device.sh.
# Use an Xcode-signed-in Apple ID, including free accounts; select among teams with TEAM=XXXXXXXXXX.
# Free-account installations expire after 7 days; reconnect and rerun to renew.
set -e
cd "$(dirname "$0")/.."
OWNER_TEAM=57KPZRQR4A   # Original author's team uses the original bundle identifier.
APP=build/DDdevice/Build/Products/Debug-iphoneos/StreetWalk.app
mkdir -p build

if [[ "$(xcode-select -p 2>/dev/null)" != *Xcode*.app* ]]; then
  echo "Xcode not found. Install it from the App Store and open it once to finish installing components."
  echo "(If this persists, run: sudo xcode-select -s /Applications/Xcode.app)"; exit 1
fi

# Without an explicit team, choose the first Xcode account, preferring a paid team.
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
  echo "Sign in to Xcode first: Settings > Apple Accounts > + > sign in with your Apple ID, then retry."; exit 1
fi
# For other free-account teams, append the team identifier to obtain a globally unique bundle ID.
if [[ "$TEAM" == "$OWNER_TEAM" ]]; then PREFIX=hk.hack4sdg; else PREFIX=hk.hack4sdg.t${TEAM:l}; fi
BUNDLE=$PREFIX.streetwalk
echo "Signing team: $TEAM; bundle ID: $BUNDLE"

# Find cable-connected iPhones.
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
# First-time devices require pairing and the phone's Trust This Computer prompt.
for id in $(echo "$LIST" | awk '$2 != "paired" {print $1}'); do
  echo "Tap Trust on the phone and enter its passcode..."
  xcrun devicectl manage pair --device "$id" >/dev/null 2>&1 || true
done
[[ -n "$(echo "$LIST" | awk '$2 != "paired"')" ]] && LIST=$(devices)
LIST=$(echo "$LIST" | awk '$2 == "paired"')
if [[ -z "$LIST" ]]; then
  echo "No connected iPhone found. Connect a data cable, unlock the phone, tap Trust, and retry."; exit 1
fi

for line in ${(f)LIST}; do
  read id state udid name <<< "$line"
  echo "== $name"
  mode=$(xcrun devicectl device info details --device "$id" 2>/dev/null | awk -F': ' '/developerModeStatus/ {print $2}')
  if [[ "$mode" == disabled ]]; then
    echo "   Enable Developer Mode on the phone: Settings > Privacy & Security > Developer Mode > On > Restart."
    echo "   After restarting and unlocking, tap Turn On and run this command again."
    continue
  fi
  if ! xcodebuild -project StreetWalk.xcodeproj -scheme StreetWalk -configuration Debug \
      -destination "id=$udid" -derivedDataPath build/DDdevice \
      -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
      DEVELOPMENT_TEAM=$TEAM BUNDLE_ID_PREFIX=$PREFIX build -quiet > build/device_build.log 2>&1; then
    echo "   Build failed; final error lines:"; grep -E "error" build/device_build.log | tail -5
    echo "   (Full log: ios/build/device_build.log)"; exit 1
  fi
  xcrun devicectl device install app --device "$id" "$APP" >/dev/null
  if xcrun devicectl device process launch --device "$id" $BUNDLE 2>&1 | grep -q Launched; then
    echo "   Installed and launched"
  else
    echo "   Installed. First trust the developer: Settings > General > VPN & Device Management > developer profile > Trust. Then open StreetWalk."
  fi
done
