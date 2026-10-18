# Member A Audit: Findings and Historical Resolution Status

Audit date: **2026-10-08**. Seven review perspectives produced 196 reports, deduplicated to 104; challenge review accepted 90 and rejected 14. These are the team's historical review records, not a fresh independent verification of the current build.

“Merged” refers to four batches integrated on 2026-10-10 into `prototype/ios-3d-diorama`; see [patch archive](../../wip/member-a-fixes/README.md). Detailed original evidence, locations and proposed fixes remain in the [unaltered source audit JSON](member_a_audit_2026-10-08.json). That archival evidence retains original-language quotations; the complete finding/status index below is English. Later code may supersede pending or rejected conclusions, especially language support and live-location privacy. Translation alone does not close findings.

| ID | Finding | Severity | Batch | Historical status |
|---|---|---|---|---|
| A01 | Launching or foregrounding after 19:00 crashed due to an invalid shade-time Range. | High | Map/scene | Fixed directly in the main version; full map2 fix also merged |
| A08 | Onboarding could not complete where residential building data was missing, including new estates. | High | Map/scene | Merged; reviewed and follow-up corrections applied |
| A10 | UI updates stalled: old tabs, undismissed banners, empty cards and lingering dimming. | High | UI/accessibility | Merged; review incomplete, integration follow-up required |
| A32 | After sunset, computed 100% shade produced false building-shade claims in cards, invitations and weather. | High | Map/scene | Merged; reviewed and follow-up corrections applied |
| A02 | Voice landmark renaming executed without recap, could not withdraw, and its name-input button did not work. | Medium | Voice/social | Merged; reviewed |
| A03 | Inviting a non-neighbor exposed the person's floor and supplied all residents' names to AI. | Medium | Voice/social | Merged; reviewed |
| A04 | Consent did not explain audiences, contradicted behavior and lacked refusal/replay. | Medium | UI/accessibility | Merged; review incomplete, integration follow-up required |
| A05 | Device walking stopped on lock/background; new devices defaulted to demo, contradicting automatic-recording claims. | Medium | Walk/data | Merged; reviewed and follow-up corrections applied |
| A06 | Walks started only within a narrow 55–96 m band, missing longer departures; inaccurate fixes ended them early. | Medium | Walk/data | Merged; reviewed and follow-up corrections applied |
| A07 | Demo reset and simulated walks overwrote or swallowed real records despite preservation comments. | Medium | Walk/data | Merged; reviewed and follow-up corrections applied |
| A09 | 3D-only home selection blocked VoiceOver/Switch Control and offered roughly 10 pt low-building targets. | Medium | UI/accessibility | Merged; review incomplete, integration follow-up required |
| A11 | Finding broadcasts discarded original speech and sent wording inconsistent with the user's chosen message. | Medium | Voice/social | Merged; reviewed |
| A20 | The ten-minute-late prompt required a demo-menu trigger that was inaccessible during meeting finding. | Medium | Voice/social | Merged; reviewed |
| A21 | Full-screen finding hid the microphone, preventing spoken broadcasts. | Medium | Voice/social | Merged; reviewed |
| A26 | Size filtering removed a newly selected low-rise home from the 200 m base. | Medium | Map/scene | Merged; reviewed and follow-up corrections applied |
| A27 | Failed maps silently became a sample estate presented as nearby/home; stale cache was skipped and old meeting places became blank. | Medium | Map/scene | Merged; reviewed and follow-up corrections applied |
| A28 | A failed Overpass fallback and poor timeout/retry policy could leave users waiting over two minutes with only a spinner. | Medium | Map/scene | Merged; reviewed and follow-up corrections applied |
| A29 | Fewer than three or duplicate-named landmarks caused silent invitation, finding and outing failures. | Medium | Map/scene | Merged; reviewed and follow-up corrections applied |
| A33 | Disabling demo retained time/weather overrides with no way to restore them. | Medium | Walk/data | Merged; reviewed and follow-up corrections applied |
| A39 | Speech and visuals were inconsistent: some confirmations were visual-only, while many results were speech-only. | Medium | Voice/social | Merged; reviewed |
| A40 | Demo, AI and Settings text fell below the design sizes/contrast; smaller system text reduced 24 pt body text to about 20 pt. | Medium | UI/accessibility | Merged; review incomplete, integration follow-up required |
| A41 | Large text truncated banners, walking status, appearance choices and finding actions. | Medium | Voice/social + UI/accessibility | Merged; reviewed |
| A42 | Avatar colors were indistinguishable under some color-vision simulations; gray avatars lacked dark-mode contrast. | Medium | UI/accessibility | Merged; review incomplete, integration follow-up required |
| A45 | Landmark details/rename required a roughly 19 x 10 pt 3D target unavailable to VoiceOver, contradicting the view-only scene rule. | Medium | UI/accessibility | Merged; review incomplete, integration follow-up required |
| A46 | Reduce Motion omitted camera flights, rising buildings, glow pulses and multiple slide/scale transitions. | Medium | Map/scene + UI/accessibility | Merged; reviewed and follow-up corrections applied |
| A47 | First microphone use recorded before authorization completed and did not explain failure. | Medium | Voice/social | Merged; reviewed |
| A48 | The leaderboard barely showed a complete rank and failed to pin my row at larger sizes. | Medium | UI/accessibility | Merged; review incomplete, integration follow-up required |
| A50 | Avatars offered only one skin tone and no age variation. | Medium | UI/accessibility | Merged; review incomplete, integration follow-up required |
| A56 | Leave supported only today; tomorrow's voice request incorrectly marked today. | Medium | Walk/data | Merged; reviewed and follow-up corrections applied |
| A59 | Draft RLS hid outings from neighbors, left several tables unprotected and allowed unilateral meetup/relationship insertion. | Medium | Docs | Fixed directly in the main version |
| A100 | Routing treated water as walkable and sent the avatar through ponds. | Low | Map/scene | Merged; reviewed and follow-up corrections applied |
| A102 | Documentation/comments/launch arguments disagreed with code on base size, -stats, demo duration and feature counts. | Low | Docs/languages | Pending in original record |
| A103 | Dead code included unused gestures/inertia, functions/properties, no-ops and unreachable weather branches. | Low | Map/scene | Merged; reviewed and follow-up corrections applied |
| A104 | The prototype backlog omitted QR pairing, age/skin choices and color-vision checks. | Low | Docs/languages | Pending in original record |
| A12 | F1 stopping places of at least two minutes within 30 m were replaced by 26 m pass-through events and uploads without disclosure. | Low | Walk/data | Merged; reviewed and follow-up corrections applied |
| A13 | The App stored non-neighbor outings and announced their floors and location state. | Low | Voice/social | Merged; reviewed |
| A15 | The pairing alert prompt described receiving only, but enabling it also shared my outings. | Low | Voice/social | Merged; reviewed |
| A16 | Most simulated residents/events lacked Demo labels despite documentation claiming universal labeling. | Low | UI/accessibility | Merged; review incomplete, integration follow-up required |
| A18 | Reports were offered/accepted outside walks; withdrawal could remove the wrong item or fail to synchronize, and the API included precise coordinates. | Low | Voice/social | Merged; reviewed |
| A19 | CommunityService lacked finding/progress/message and summary/leave/profile/withdrawal interfaces, leaving AppStore to fabricate peer events. | Low | Voice/social | Merged; reviewed |
| A22 | Stale finding state and unscoped delayed tasks could announce peer acceptance before asking. | Low | Voice/social | Merged; reviewed |
| A23 | Rebuilding circle members left undismissable empty finding cards or named non-neighbors in the scene. | Low | Map/scene | Merged; reviewed and follow-up corrections applied |
| A24 | Adding save fields made old saves unreadable and allowed empty state to overwrite all user records. | Low | Walk/data | Merged; reviewed and follow-up corrections applied |
| A25 | Crop-array landmark IDs could point elsewhere after home/cache changes despite shared-ID documentation. | Low | Map/scene | Merged; reviewed and follow-up corrections applied |
| A30 | Render/main threads shared scene state without synchronization, risking intermittent crashes. | Low | Map/scene | Merged; reviewed and follow-up corrections applied |
| A31 | The static scene still rendered at 60 fps with 4x MSAA, 16-sample shadows and 30 label publications per second. | Low | Map/scene | Merged; reviewed and follow-up corrections applied |
| A34 | Sun/shadows updated only at map load, and Today did not refresh across midnight. | Low | Walk/data | Merged; reviewed and follow-up corrections applied |
| A35 | Regenerate-at-current-location used the wrong position and silently replaced the saved home. | Low | Walk/data | Merged; reviewed and follow-up corrections applied |
| A36 | Peer replies arriving before map load produced blank names and places in banners/speech. | Low | Voice/social | Merged; reviewed |
| A37 | Leave added a streak day, allowing ranking inflation through daily leave. | Low | Walk/data | Merged; reviewed and follow-up corrections applied |
| A38 | Normal-mode pairing falsely said everyone was already a neighbor and recognized only existing circle residents. | Low | Voice/social | Merged; reviewed |
| A43 | VoiceOver focus did not follow cards/banners, which disappeared before users could find actions. | Low | UI/accessibility | Merged; review incomplete, integration follow-up required |
| A49 | Mandarin recognition, speech, interface and settings were absent, beyond the documented UI-only gap. | Low | Docs/languages | Pending in original record |
| A52 | Leaderboard omitted building identifiers, month-end winners and winner badges without documenting them as pending. | Low | UI/accessibility | Merged; review incomplete, integration follow-up required |
| A54 | Walking/running-only classification excluded wheelchair users. | Low | Walk/data | Merged; reviewed and follow-up corrections applied |
| A55 | Stopping outside never ended walks and counted sitting as walking minutes. | Low | Walk/data | Merged; reviewed and follow-up corrections applied |
| A58 | No local/push notifications existed; departures and outings were visible only while the App was open. | Low | Walk/data | Merged; reviewed and follow-up corrections applied |
| A60 | Prototype status labeled manually triggered or hard-coded late prompts, broadcasts, calls and cadence hints as real. | Low | Docs/languages | Pending in original record |
| A61 | test.sh returned zero even when tests failed. | Low | Walk/data | Merged; reviewed and follow-up corrections applied |
| A62 | Relative-date labels called both yesterday and three days ahead the day after tomorrow. | Low | Voice/social | Merged; reviewed |
| A64 | Invented streak/place values appeared before map load or after real walks without landmarks. | Low | Walk/data | Merged; reviewed and follow-up corrections applied |
| A65 | No outing event was treated as proof of being home; disabling receive still showed the peer outside. | Low | UI/accessibility | Merged; review incomplete, integration follow-up required |
| A66 | Equal alert start/end hours silently disabled alerts forever. | Low | Walk/data | Merged; reviewed and follow-up corrections applied |
| A67 | ETA used straight-line inter-person distance rather than remaining route and asserted peer departure on my departure. | Low | Voice/social | Merged; reviewed |
| A68 | Monthly-report demo text called mixed sample records real, and some totals lacked the ten-person threshold. | Low | UI/accessibility | Merged; review incomplete, integration follow-up required |
| A69 | Local-only rename/report wording falsely promised circle synchronization or management delivery. | Low | Voice/social | Merged; reviewed |
| A70 | Silent-unlink wording omitted that unfinished meetings would notify the peer of cancellation. | Low | UI/accessibility | Merged; review incomplete, integration follow-up required |
| A73 | Each launch requested location, beyond the stated walking-only use. | Low | Map/scene | Merged; reviewed and follow-up corrections applied |
| A74 | GPS jumps or stale fixes generated one-minute false walks that increased streaks. | Low | Walk/data | Merged; reviewed and follow-up corrections applied |
| A75 | Returning from background could add hundreds of simulated minutes at once. | Low | Walk/data | Merged; reviewed and follow-up corrections applied |
| A76 | Backgrounding did not save immediately. | Low | Walk/data | Merged; reviewed and follow-up corrections applied |
| A77 | Incoming alerts spoke during listening and interrupted recognition. | Low | Voice/social | Merged; reviewed |
| A79 | Successful pairing during a walk teleported my avatar home. | Low | Map/scene | Merged; reviewed and follow-up corrections applied |
| A80 | Home changes could not be cancelled and stepping back from floor selection left the wrong scene state. | Low | Walk/data | Merged; reviewed and follow-up corrections applied |
| A81 | Weather prompts became multiple sentences and suggested waiting for rain to stop based only on rain probability. | Low | Voice/social | Merged; reviewed |
| A82 | Afternoon/evening passers still used morning wording; sample counts could fall below the ten-person threshold. | Low | UI/accessibility | Merged; review incomplete, integration follow-up required |
| A83 | Daily greetings retained old landmark names after renaming. | Low | Voice/social | Merged; reviewed |
| A84 | Reschedule examples always suggested the same fixed 16:00 time. | Low | Voice/social | Merged; reviewed |
| A85 | Steps were only minutes times 100, and real-device cadence-drop hints never triggered. | Low | Walk/data | Merged; reviewed and follow-up corrections applied |
| A88 | Local/backend fields diverged from specification section 7 without explaining walks, leave, reports and users. | Low | Docs | Fixed directly in the main version |
| A89 | Several VoiceOver labels were incorrect or ambiguous. | Low | UI/accessibility | Merged; review incomplete, integration follow-up required |
| A90 | App speech collided with VoiceOver and interrupted other App speech. | Low | Voice/social | Merged; reviewed |
| A92 | Automatic walking forcibly switched to Today. | Low | Walk/data | Merged; reviewed and follow-up corrections applied |
| A93 | Duplicate home-selection notices overlapped progress indicators. | Low | UI/accessibility | Merged; review incomplete, integration follow-up required |
| A94 | Full-screen finding toasts covered the top card. | Low | UI/accessibility | Merged; review incomplete, integration follow-up required |
| A95 | Today could display several orange primary actions at once. | Low | UI/accessibility | Merged; review incomplete, integration follow-up required |
| A96 | The Demo capsule appeared system blue. | Low | UI/accessibility | Merged; review incomplete, integration follow-up required |
| A97 | The translucent time-slider sheet exposed orange controls underneath, obscuring Done. | Low | UI/accessibility | Merged; review incomplete, integration follow-up required |
| A98 | Edge homes left a large part of the 200 m base outside fetched map coverage. | Low | Map/scene | Merged; reviewed and follow-up corrections applied |
| A99 | Area names came from individual buildings or a public toilet instead of the estate. | Low | Map/scene | Merged; reviewed and follow-up corrections applied |

## Fourteen findings rejected in that review

These were rejected then, not certified impossible in every later version. Consult the original evidence before reusing a conclusion.

- **A14** — Claim: outings were never withdrawn on background/termination/reset/home change and lacked expiry.
- **A17** — Claim: clearing records failed to remove home/floor/cache or synchronize unlink/cancellation.
- **A44** — Claim: finding used only a visual arrow without accessible direction or landmark icons.
- **A51** — Claim: pairing lacked failure/timeout/unsupported states, QR fallback and post-pair approach guidance.
- **A53** — Claim: calling had no number source because PhoneBook was empty and backend collected no phone numbers.
- **A57** — Claim: identity/nickname were absent, onboarding did not ask and my identity was hard-coded.
- **A63** — Claim: privacy, device walking and meeting lifecycle had no unit tests.
- **A71** — Claim: real-time finding conflicted with coordinate-free privacy without a documented resolution.
- **A72** — Claim: Overpass received roughly 560 m including third-party mirrors despite a 400 m README description.
- **A78** — Claim: the demo time slider permanently expired meetings or consumed reminders early.
- **A86** — Claim: sample circles lacked building-based new-resident grouping and multiple-circle membership.
- **A87** — Claim: shade and neighbor-creation signatures diverged from specification section 8 without documentation.
- **A91** — Claim: main-screen VoiceOver order left microphone/Settings after content without explicit ordering.
- **A101** — Claim: avatar rebuilding after appearance/mobility changes stopped movement.
