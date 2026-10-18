# StreetWalk · Install on your iPhone

Use your own Mac and Apple ID to install StreetWalk for testing. A free Apple ID is sufficient for a development installation.

## Before you start

- A Mac capable of running a version of Xcode that supports the connected phone's iOS version.
- An iPhone meeting the app's deployment target (the earlier installation guide specified iOS 18 or later). UWB pairing requires supported hardware; use QR pairing when precise ranging is unavailable.
- A USB cable that supports data, not only charging.
- An Apple ID.

## First installation

Most of the initial setup time is spent downloading Xcode; allow approximately 30–60 minutes, depending on the network.

1. Install **Xcode** from the Mac App Store. Open it once and install the requested components, including iOS.
2. Open **Xcode → Settings → Apple Accounts**, click **+**, and sign in.
3. Check out the integrated **main** branch:
   ```sh
   git clone --branch main https://github.com/patrick3432348016/HACK4SDG.git
   cd HACK4SDG/ios
   ```
   If the team supplied `StreetWalk_install.zip`, extract it first and use the directory containing `tools/install_device.sh`. The old package placed this at `~/Downloads/StreetWalk`.
4. Connect and unlock the iPhone. Accept **Trust This Computer** on the phone and **Allow Accessory to Connect** on the Mac.
5. In Terminal, from the iOS project directory, run:
   ```sh
   zsh tools/install_device.sh
   ```
6. Follow the script's instructions, then run the same command again if requested:
   - Enable **Settings → Privacy & Security → Developer Mode**, restart, unlock, and confirm.
   - If prompted after installation, trust the developer under **Settings → General → VPN & Device Management**.
   - Wait for Xcode to download any required device-support components before retrying.
7. The script reports when the app has been installed and opened. Record the commit used for each test or demo phone.

## Renewing a free development installation

A build installed with a free Apple ID normally stops opening after seven days. Reconnect the phone and rerun the installation command using the same project and signing identity. Do not delete the app if you need to preserve its local data.

## First use

- Choose a nickname. Allow location access as explained by onboarding; **Always** access supports automatic home/departure detection. Allow notifications, and allow Nearby Interaction and Local Network when pairing.
- Select **Cantonese / Traditional Chinese, Mandarin / Simplified Chinese, or English** in onboarding or Settings. The initial language follows the system.
- **Add a neighbor:** open the Neighbors tab on both phones and start pairing. Hold the phones close together. The integrated app currently uses approximately 0.30 m for 0.8 s; these are tuning values, not guaranteed ranging accuracy. Use QR as a fallback.
- **Find someone:** after pairing, select the neighbor and request to find them. The other person must agree before temporary precise-location sharing begins.
- **Outing reminders:** overnight home learning and the relevant permissions are needed for automatic departure behavior. Test this separately from manual walk controls.
- The community board covers the nearby area.
- For Doubao speech and understanding, run `tools/voice_server.sh` from the repository root on the Mac. With both devices on the same Wi-Fi, the app can discover the server. See [the voice-server guide](../server/README.md). System speech and local templates provide fallback behavior.

## Troubleshooting

Capture the visible error and share the build log with the project owner: `ios/build/device_build.log` in a repository checkout, or `StreetWalk/build/device_build.log` in the earlier ZIP package. Check logs for private information before sharing them.
