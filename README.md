# HACK4SDG · StreetWalk

> **Historical branch:** this is `prototype/ios-3d-diorama`. For the current application, English source comments, and integrated documentation, **[open main](https://github.com/patrick3432348016/HACK4SDG/tree/main)**. The guides below describe main unless explicitly labeled historical; this branch retains older application code and media.

Hong Kong Inter-University GenAI Hackathon for SDGs 2026 — Track 2: **Sustainable Northern Metropolis**.

Residents of newly occupied Northern Metropolis estates often pass one another on the same paths without getting to know each other. StreetWalk helps residents of all ages turn everyday walks into opportunities to meet: recognize familiar neighbors, pair phones in person, arrange a walk by voice, and find each other when it is time to meet. The interface includes support for older residents.

## Beginner's guide: let WorkBuddy help you deploy

New to installing apps from source? **Copy the entire message below into WorkBuddy or another coding agent.** It includes the repository link and the instructions to get started; there is no need to package the files manually if the agent can access GitHub.

```text
I am a beginner. Help me install and run StreetWalk on my iPhone:
https://github.com/patrick3432348016/HACK4SDG

Use the main branch, not the historical default branch. Read README.md and
ios/DEVICE_INSTALL.md first, then check my computer and iPhone setup.
Guide me step by step and carry out the installation where your tools allow.
Explain any steps I must complete myself, including Xcode setup, Apple ID
signing, Developer Mode, and device trust prompts.
If I need the voice service, follow server/README.md to help configure it.
Check that the app launches, help troubleshoot errors, and clearly explain
anything that still needs setup or verification.
```

**What you need:** a Mac with compatible Xcode, an iPhone, a USB data cable, and an Apple ID. The agent can help with setup, commands, and troubleshooting; you will still need to complete Apple sign-in and prompts on your devices. See the [device installation guide on main](https://github.com/patrick3432348016/HACK4SDG/blob/main/ios/DEVICE_INSTALL.md) for the full steps.

## Current status — 18 October 2026

The team reports three rounds of testing with members and roommates on 16–18 October, including an iPhone 15 and an iPhone Air. The user reports that neighbor pairing, voice invitations with acceptance on the other phone, and live finding have passed on two network-connected iPhones. These are **team-reported results**, not an independent reliability assessment or a trial with target residents. Demo mode includes simulated people and events.

Use **`main`** for the integrated application. At this documentation review, main was `f8d63c9749ff5fc12b1d887afc3510ca2cc36dfd`; the repository's default branch was still `prototype/ios-3d-diorama`, a different version. Record the exact commit used for installation, testing, and demonstrations.

| Capability | Implementation and limits |
|---|---|
| Live map, 3D paper-style scene, landmarks, building shade, and routing | Location → 400 m grid → OpenStreetMap/Overpass, with five endpoints, caching, retries, and fallback data; rendered with SceneKit. Drag, pinch, rotate, and a blue current-location marker. Building heights and shade are estimates. |
| Walking guidance | Landmark cards describe estimated daytime shade, streetlights after dark, and seating where data is available. These are not independently verified safety or accessibility guarantees. |
| Home learning and walk recording | Core Location and Core Motion, overnight home learning, departure detection at about 50 m, and manual start/end controls. A stationary period of about ten minutes can end a walk. See `Services/HomeLearner` and `LocationMonitor`. |
| Community and invitations | Supabase in Singapore provides anonymous authentication, nicknames, nearby rankings, neighbor relationships, meetups, outings, reports, and feedback. Demo mode uses a local service. Queued writes and confirmed delivery are different states. |
| Choosing a meeting place | Explicit ranking rules use shade, seating, and both participants' walking times. The assistant explains the choice in one sentence. Time and place can be changed independently, with manual time/place/walking-duration controls. Do not describe the ranking rules themselves as GenAI. |
| In-person pairing | Nearby Interaction/UWB with server pairing, adapted from member B's `ios/UWBMeetDemo/`; cellular connectivity and QR fallback are supported. Current tuning is approximately 0.30 m held for 0.8 s, not a measured success guarantee. |
| Live finding | After mutual agreement, a private pair channel exchanges precise GPS coordinates for distance and compass guidance. Within about 30 m, the app attempts UWB guidance on supported devices. See `Services/LiveFindSession`. |
| Dynamic Island and Live Activity | `StreetWalkWidgets` extension. |
| Weather | Hong Kong Observatory district/hourly data; Open-Meteo outside Hong Kong. |
| Voice assistant | Member B's Doubao stack: streaming recognition, model-based understanding, and Xiaohe speech in three languages. Start `tools/voice_server.sh` on a Mac. Continuous conversation routes some commands locally and others to the server. Local templates and system speech provide a limited fallback when the server is unavailable. |
| Languages | **Cantonese / Traditional Chinese, Mandarin / Simplified Chinese, and English.** Switch in onboarding or Settings; the default follows the system language. English place names are used when available. English documentation does not remove any app language or its test fixtures. |

## Install on an iPhone

Follow the **[device installation guide](ios/DEVICE_INSTALL.md)**. Install Xcode, sign in with an Apple ID, connect the phone, and run:

```sh
git clone --branch main https://github.com/patrick3432348016/HACK4SDG.git
cd HACK4SDG/ios
zsh tools/install_device.sh
```

A free Apple developer account can be used; its installed development build normally expires after seven days and must be installed again.

## Remaining validation and submission work

- [ ] Record the commit, devices, accounts, language, network, steps, and evidence for the three core flows. Check outdoor finding/UWB, outing reminders, background recording, Live Activity, stationary auto-stop, and map gestures.
- [ ] Verify deployed RLS and privacy controls. The SQL in [the backend guide](supabase/README.md) contains **proposals not confirmed as deployed**. Do not run it or delete test users as part of a documentation change.
- [ ] Verify the English feedback schema: the app can send `lang=en`, while `002_feedback.sql` currently accepts only `yue` and `cmn`.
- [ ] Compare the GenAI flow with a non-AI baseline on the same Cantonese, Mandarin, and English tasks. Report completion, field accuracy, latency, failures, and fallback behavior.
- [ ] Complete the pitch deck and WorkBuddy evidence; identify the team, team number, members, and universities. The final submission date is 18 October.
- [ ] Check the audible difference between slow and normal speech.
- [ ] Optional: a paid Apple developer account for TestFlight and APNs work. Reliable background push delivery is not established by the current implementation.
- [x] Doubao recognition, understanding, and speech are integrated; replacing them with GLM is no longer planned.
- [x] Three-language UI, permission descriptions, and voice support are present in the source.
- [x] The team reports reinstalling demo phones from main; record the installed commit for reproducibility.

The promotional-video project was removed from main in `f8d63c9`; it is maintained locally and is not part of this checkout.

## Documentation

- [Original product specification](docs/product-spec-v1.0.md) — dated design baseline, not a current implementation checklist.
- [Layout sketch](docs/design/layout_sketch.html) — open in a browser; a historical sketch, not the current iOS UI reference.
- [Earlier demo recording](docs/demo/streetwalk_demo.mp4).
- [Member A's historical progress and manual checklist](docs/PROGRESS_member_A.md).
- [Backend schema, access rules, and tests](supabase/README.md).
- [Voice server setup and integration](server/README.md).
- [English translation scope and verification](docs/reviews/2026-10-19-english-translation.md) — preserves app languages and original evidence; records the existing Windows test failures.
- [English-only material recheck](docs/reviews/2026-10-19-english-recheck.md) — remaining exceptions, both-branch fixes, and a repeatable language check.

Historical documents retain their dates, findings, and unresolved items. For implementation, use current source and record the branch and commit.

## iOS prototype (`ios/`)

The repository's development setup uses Xcode 26.6 and the iOS 26.5 simulator runtime (`xcodebuild -downloadPlatform iOS`). Check local Xcode/device compatibility before installation.

```sh
cd ios
./tools/selftest.sh       # Core logic: maps, landmarks, sun position, shade, and weather parsing
./tools/test.sh           # Xcode unit tests; returns nonzero on failure
./tools/install_device.sh # Build and install on a connected iPhone
./tools/run.sh -demo      # Build and launch in the iPhone 17 simulator at Queen's Hill Estate
./tools/record_demo.sh    # Record a demo; close other simulators first
```

Set `SIM="iPhone 17 Pro"` to select another simulator. The previous README reported 282 iOS tests; this documentation change does not independently verify that count or their results.

Launch arguments:

- Demo: `-demo`, `-script` (main sequence, about 105 seconds), `-captions` (Chinese/English captions), `-script2` (neighbors, information/voice cards, time slider), `-script3` (rescheduling, report replies, departure reminders, expiration, unlinking, settings), and `-resetOnboarding -scriptOnboarding`.
- State: `-skipOnboarding`, `-resetOnboarding`, `-resetData` (clear local records), `-withNeighbor`, `-hour 15`, `-offline` (bundled map, no weather fetch), `-logNotifications`, `-autoWalk`, and `-scriptWalk` (leave, reminder hours, demo settings, and home-change cancellation).
- Rendering: `-stats`, `-tilt`, `-pitch`, `-ovy`, and `-ovd`.

### Ownership and directories

Paths below are relative to `ios/StreetWalk/` unless stated otherwise.

| Directory | Owner | Responsibility |
|---|---|---|
| `App/`, `Design/`, `Store/`, `UI/` | A | App structure, design system, state and flows, screens, and settings; `AppStore` is split into feature extensions. |
| `Store/Community.swift`, `Backend/` | A | Shared community data. Normal mode uses `SupabaseCommunityService`; demo mode uses `LocalCommunityService`. |
| `Store/LocalStore.swift` | A | Persistence for neighbors, meetups, reports, landmark names, daily walks, and leave. |
| `Services/` | A | Weather, motion/location/pedometer integration, stop detection, backfill, leave, local notifications, and phone calls. |
| `Map/` | A | Grid-based Overpass loading, caching/fallbacks, landmark selection, and routing. |
| `Scene/` | A | SceneKit model, camera, characters, projected labels, and tilt-shift effects. |
| `Shade/` | A | NOAA sun position and building ray-cast shade estimates. |
| `AI/`, `Assistant/` | B | Doubao server integration and `TemplateAI` fallback/meeting-place rules. |
| `Voice/` | B | Recognition and speech in three languages, using server or system voices. |
| `Bump/` | A + B | Nearby Interaction and QR pairing; simulated pairing in demo mode. |
| `Domain/Contracts.swift` | A + B | Shared interfaces from specification §8. Contract changes require both sides to agree; the earlier reschedule/cancel and monthly-report changes retain their documented integration checks. |
| `StreetWalkTests/` (under `ios/`) | A | Xcode unit tests. |

The Xcode project uses synchronized folders. Add Swift files under `ios/StreetWalk/`; routine additions do not require editing `project.pbxproj`.

### Privacy and evidence boundaries

**Ordinary outing updates share only a nearby landmark. When both participants agree to find each other, precise location is shared temporarily and stops when the finding session ends.**

- Map services receive a coarse geographic area. Outside Hong Kong, weather requests include a location rounded to approximately 0.1°. Do not claim that every weather request is location-free.
- Finding uses a private real-time pair channel; precise coordinates do leave the phone during an agreed session. This does not establish end-to-end encryption or prove every exit path has been independently tested.
- Profile data can include block and floor when sharing is enabled. Speech passes through the voice server and Doubao, and test conversation logging must be accounted for in a complete privacy notice.
- Monthly aggregates require at least ten distinct anonymous user IDs. This is not verification of ten distinct residents. Sample reports and management responses must remain labeled as examples.
- The current deletion flow clears selected tables, de-identifies the profile, and signs out. It must not be described as complete deletion of every account and server record.
- Ordinary scene presence is limited to neighbors and landmark-level outing information. Live finding has the separate consent boundary described above.

## Attribution

Map data © OpenStreetMap contributors, licensed under ODbL. Bundled example data for Queen's Hill Estate is in `ios/StreetWalk/Resources/fallback_queenshill.json`.
