# Northern Metropolis proximity-pairing UWB prototype

> Historical standalone prototype, separate from the integrated StreetWalk app. Its validation status and thresholds below apply to this project only. StreetWalk later adapted parts of it; see the root README for current integration and team-reported tests.

This independent iPhone project was designed for a Sustainable Northern Metropolis demonstration: encrypted pairing → actual UWB ranging → nearby profile card → mutual confirmation → exchange of fictional demo contact fields → local persistence.

**The original delivery had not passed Xcode compilation or device validation. Source code is not a proven app or an installable IPA. Windows cannot provide Xcode verification, and a simulator cannot establish UWB hardware behavior.**

## Original test assumptions

- User-reported devices: iPhone 18 Pro / iOS 27.0 and iPhone 15 Pro / iOS 26.5.2. These identities/versions had not been read from the devices.
- Delivery workstation: Windows without Mac, Xcode, or a Swift compiler.
- Deployment target: iOS 17.0. Xcode/macOS must support the connected phone's actual OS; lowering deployment target does not solve unsupported device tooling.
- Check NISession.deviceCapabilities.supportsPreciseDistanceMeasurement at startup. Stop explicitly if unsupported; never show a simulated distance as real.
- Two foreground devices and one pair only. No background operation, multi-person nearest-peer selection, production accounts, or cloud friend synchronization.
- Earlier notes said judging weights were unknown. That statement is superseded by the project controller's verified 18 October rubric: five main-prize categories at 20% each, under Sustainable Northern Metropolis.

## Xcode and installation

1. Use a Mac capable of the required Xcode version. Xcode is available from the Mac App Store, not Windows.
2. Copy the entire UWBMeetDemo directory and open UWBMeetDemo.xcodeproj. No XcodeGen, CocoaPods, or third-party Swift packages are required.
3. Sign in through Xcode → Settings → Apple Accounts. Never commit passwords, certificates, or signing files.
4. Under target Signing & Capabilities, enable automatic signing and select your Team. Change org.hack4sdg.uwbmeetdemo if a unique identifier is needed.
5. Connect each phone, trust the Mac, enable Developer Mode, choose the actual device, and Run. Install the same project on both.
6. Allow Local Network and Nearby Interaction. If denied, change permissions in iOS Settings and restart. Keep Wi-Fi/Bluetooth available; initially use a normal shared LAN without guest isolation for troubleshooting.

Personal Apple Accounts can be used for device testing, subject to current Xcode signing/device/capability limits. Recheck signing before the demo. A remote/cloud Mac still requires signing and installation; it does not make Xcode run on Windows. A nearby Mac is preferable for simultaneous two-device debugging.

## Demonstration procedure

1. Reset Demo on both phones; this clears only this app's test friend records.
2. A selects Patrick and initiates. B selects Xiao Chen, enters A's one-time pairing code, and joins. The code excludes unrelated devices and may be entered during setup; it does not replace UWB triggering.
3. Network/Bonjour connects the devices and exchanges Nearby Interaction tokens. Show actual distance, or Waiting for Ranging until a measurement arrives.
4. Approach slowly from a distance. Original experimental parameters: <=0.30 m for 0.50 s, resetting incomplete dwell after a reading gap over 0.35 s. These were not device-validated or guaranteed across models.
5. Show confirmation cards only after both sides measure proximity. Check names, choose **fictional demo fields**, and confirm separately. Do not read system contacts.
6. Exchange fields only after mutual approval. Each phone persists the received card before acknowledging it; success requires local persistence and the peer's acknowledgement.
7. Inspect both success screens/friend lists. Without the peer's save receipt, mark the record incomplete rather than successful.
8. Reset both phones for the next round. Backgrounding, rejection, connection loss, or the three-minute timeout requires a fresh attempt.

This project does not use NFC, NameDrop, fake distances, timed automatic success, or a browser simulation. Direction arrows are outside this prototype's scope. Repeating a pair updates records by stable demo-device ID rather than duplicating them; reinstalling changes that ID.

## Modules and boundaries

- Core/: proximity gate, mutual-confirmation state, sequence checks, and TCP framing, independent of iOS hardware.
- App/: SwiftUI, Network, Nearby Interaction, and protected local JSON storage.
- A discovery token identifies one NI session, not an account. Public cards also travel encrypted; contact fields are sent only after mutual confirmation.
- Each initiator generates an 80-bit pairing secret, shared face-to-face by screen entry, never transmitted as the pairing code over the network. CryptoKit HKDF derives keys; ChaChaPoly authenticates/encrypts messages; session/sequence checks reject replay and reordering.
- This is a controlled two-device demo, not an audited production identity system. Anyone knowing the code can join; projecting it publicly does not establish verified identities.
- Contact values are visibly fictional DEMO_* strings. No automatic WeChat/WhatsApp friend action occurs.
- Do not store raw ranging logs or access location/camera/contacts. Diagnostics record stage, duration, and errors, not card fields, tokens, or pairing codes.
- Real-account integration requires authenticated identity binding and redesigned synchronization, revocation/deletion, sensitive storage, and connection authentication. Local demo relationships are not platform relationships.

## Checks

From this directory on Mac:

```sh
swift test
xcodebuild -project UWBMeetDemo.xcodeproj -scheme UWBMeetDemo -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Swift tests cover sustained proximity, interrupted/invalid readings, mutual approval, cancellation, framing, and replay. They do not establish hardware/API operation. The build checks the iOS project; simulator UWB should explicitly report unsupported. Device installation still needs signing.

Windows structure check:

```powershell
python tools/check_project.py
```

After adding/removing Swift sources, tools/generate_project.py can regenerate references. It rewrites project configuration; do not run casually after manual Team/Bundle ID changes.

## Required two-device acceptance

All original results below were **not tested**.

| Scenario | Expected result | Original result |
|---|---|---|
| Approach and mutually confirm for ten rounds | Correct peer, actual distance trigger, both saved; record duration/failures | Not tested |
| Remain apart for over 0.5 s | No confirmation card | Not tested |
| Brief proximity, then separation/reading gap | Stale readings do not accumulate dwell | Not tested |
| One side withholds/rejects approval | No contact exchange or success | Not tested |
| Close/background one app | Explicit end; a fresh attempt recovers | Not tested |
| Wrong code or third nearby device | No card exchange; re-pairing recovers | Not tested |
| Local Network/NI permission denied | Clear blocked/error state, no fabricated success | Not tested |
| Repeat the same pair | No duplicate friend record | Not tested |
| Restart app | Saved friends persist; incomplete records remain incomplete | Not tested |
| Share no contact fields | Public cards can still exchange with empty optional fields | Not tested |
| Disconnect during confirmation/save | Missing receipt means incomplete; inspect both phones | Not tested |
| Clear demo data | Only this app's test friends are removed | Not tested |

Network interruption cannot guarantee simultaneous screen updates. Local persistence, peer receipts, and incomplete markers prevent silently claiming success, but still require device acceptance before recording a real backup demo.

## Original technical references

- [Nearby Interaction](https://developer.apple.com/documentation/nearbyinteraction/)
- [Discovery-token exchange](https://developer.apple.com/documentation/nearbyinteraction/discovering-peers-with-multipeer-connectivity)
- [Network peer-to-peer interfaces](https://developer.apple.com/documentation/network/nwparameters/includepeertopeer)
- [Moving from Multipeer Connectivity to Network](https://developer.apple.com/documentation/technotes/tn3213-moving-from-multipeer-connectivity-to-network-framework)
- [Device capability checks](https://developer.apple.com/documentation/nearbyinteraction/nidevicecapability)
- [Download Xcode](https://apps.apple.com/app/xcode/id497799835)
- [Personal accounts and device testing](https://developer.apple.com/support/compare-memberships/)
