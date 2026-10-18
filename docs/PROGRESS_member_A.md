# Member A Progress — Historical Snapshot, 2026-10-10

> This is a historical team status report, not current acceptance evidence. Several pending items below were subsequently implemented. Consult the [current README](../README.md), current code and dated validation records. The original branch note was updated on 2026-10-16 to refer to `main` (previously `prototype/ios-3d-diorama`); this does not mean GitHub's default-branch setting changed.

## Status at the time

The App could run a complete demonstration and a silent demo video had been recorded. Many review fixes were prepared in `wip/member-a-fixes/` but not yet integrated. Voice improvements, Dynamic Island banner animation, Mandarin and English remained pending in this snapshot.

## Implemented in that snapshot

1. Onboarding explained visibility, then selected home building, floor and avatar.
2. A white paper-style 3D model used nearby map data around a 200 m home area with solar shadows.
3. Today showed walking minutes, streak, a generated sentence and leave controls.
4. Simulated bump pairing asked once whether to enable outing alerts.
5. Outing banners shared a landmark rather than coordinates.
6. Automatic walking recorded the route and places passed.
7. Finding asked permission, then showed an arrow, distance and meeting confirmation.
8. Invitations suggested time/place with shade and seating reasons; supported alternatives, edits, cancellation, a 30-minute reminder and expiry.
9. Voice commands covered invitations, leave, landmark names and reports about heat or missing seating. Actions affecting others required recap and confirmation.
10. Live HKO weather supported typhoon / heavy-rain advice.
11. Landmark reports and management replies fed monthly aggregates with a minimum threshold of 10 people in the original design.
12. Leaderboards showed streaks and circle step comparisons.
13. Neighbors had separate sending/receiving alert switches and silent relationship removal.
14. Settings changed home, floor, avatar, alert hours, demo mode and local records.
15. Relationships, meetings, renamed landmarks and walking records survived restart.
16. Dark mode, large text, App icon, [demo video](demo/streetwalk_demo.mp4) and 19 automated tests were reported.

The historical [prototype status](prototype_status.md) distinguishes implemented and simulated behavior. Anonymous account counts must not be presented as verified unique residents.

## Prepared but not yet integrated at the time

The 2026-10-08 review confirmed 90 findings; see the [audit and item statuses](audit/member_a_audit_2026-10-08.md).

- Already fixed directly: a crash after 19:00 and authorization gaps in the backend draft.
- Four batches in [member-a-fixes](../wip/member-a-fixes/README.md): voice/social complete; walking/data and map/scene awaiting a final pass; UI/accessibility awaiting verification.

## Pending at the time

1. Dynamic Island banners expanding from the island, with walking minutes and finding distance beside it.
2. Voice improvements, researched in [tts_voices.md](research/tts_voices.md): first, master switch, three languages, voice preview, three speeds and instructions for downloading enhanced iPhone voices; second, proposed Google Chirp 3 HD prerecorded demo lines, awaiting credentials.
3. Mandarin and English interface and spoken prompts.
4. Remaining audit items: Mandarin support, stale documentation/comments and dead-code cleanup.

## Known bugs recorded at the time

- Reopening demo data the next day could show a zero-day streak because sample records were seeded only once. Workaround: `-resetData`.
- The orange microphone could crash in the simulator. The team attributed this to a timeout accessing the Mac microphone; real-iPhone testing was still required. This attribution was not a general proof that App code could never be involved.
- UI updates sometimes stalled, leaving banners or old page content. Two fixes had been attempted; the fuller fix was in the UI batch.
- Other open integration issues remained in the audit.

## Requests to member B at the time

- Confirm `Domain/Contracts.swift` changes: reschedule/cancel intents, monthly-report statistics and MainActor-only `NeighborRegistry`.
- Correct TemplateAI wording that falsely attributed a fixed afternoon-rain sentence to HKO or suggested waiting until after 18:00 even at 10:00.
- Replace template-only understanding through `AIService` with an appropriate real model. The official technical category weighs 20% and asks for effective GenAI use; it is not a separate 20% award merely for using a model. Current integration has progressed beyond this historical gap.
- Connect real Nearby Interaction / MultipeerConnectivity pairing through `BumpService`.
- Extend `Voice/Speech.swift` with language/voice selection and public speaking/stop controls instead of indirect internal-state access.

## Running the historical demo

The original environment required Xcode 26.6 and an iOS 26.5 simulator.

```sh
cd ios
./tools/run.sh -demo -skipOnboarding -resetData        # Clean demo data
./tools/run.sh -demo -resetOnboarding                 # Start onboarding
./tools/run.sh -demo -skipOnboarding -script -captions # About 100 seconds, with subtitles
./tools/test.sh                                      # Automated tests
```

The top-right Demo menu simulates other residents' outings, invitations and management replies.

## Historical manual checklist

These are expected results, not a new record of passing tests. Labels below are English descriptions of the original localized UI.

| # | Action | Expected result |
|---|---|---|
| 1 | Launch with `-resetOnboarding` and complete setup | Explanation, orange building, floor, avatar, then main screen with rising buildings |
| 2 | Inspect Today | 3D model, 24 walking minutes, 9-day streak and Demo label |
| 3 | Open leaderboard | At that time, others showed floors without names; my row remained fixed at the bottom |
| 4 | Neighbors → bump pairing | Simulated pairing after about 2 seconds, followed by the alert question |
| 5 | Demo → Mrs Chan goes out | Banner and Mrs Chan in the scene |
| 6 | Demo → go out | Elapsed minutes, moving avatar and orange route |
| 7 | While walking, choose Find her → Go | Full-screen route, near-distance arrow, then meeting confirmation |
| 8 | Invite, change time/place, confirm | Simulated acceptance after about 4 seconds |
| 9 | Edit or cancel a meeting | Edits await confirmation; cancellation asks first |
| 10 | Demo → Mrs Chan invites you, then Neighbors | Incoming card with accept, change time and decline |
| 11 | Inspect weather; select heat/rain demos | Weather text and corresponding banner; simulated weather must be labeled |
| 12 | Drag the demo time slider | Moving shadows, darkness at night, no crash |
| 13 | Report heat while walking; simulate management reply | Map marker and reply banner |
| 14 | Demo → monthly report | Queen's Hill Estate monthly walking report |
| 15 | Toggle alerts and remove neighbor | Confirmation followed by removal from list and map |
| 16 | Open Settings | Floor/avatar edits work; disabling demo removes simulated residents |
| 17 | Relaunch with `-demo -skipOnboarding` | Relationships, meetings and renamed landmarks persist |
| 18 | Simulator Features → Toggle Appearance | App and scene switch to dark mode |
