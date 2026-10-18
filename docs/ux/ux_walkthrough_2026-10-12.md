# StreetWalk UX Walkthrough — 2026-10-12

> Historical reviewer walkthrough, not interviews with recruited residents or a current acceptance result. Many findings were addressed later; check current code and device evidence before treating them as open. Screenshots remain original visual evidence. English wording below describes the original Cantonese UI rather than altering those screenshots.

Method: iPhone 15 simulator, iOS 26.5, location set to Queen's Hill Estate. The reviewer completed first-use onboarding, then demo invitations, replies, edits, outings, finding, pairing and Settings, followed by a normal-mode view against the real backend. Two hypothetical perspectives were used: a 70-year-old first-time App user, Uncle Lee, and a 40-year-old new resident, Mr Chan. These were personas, not two observed research participants. Screenshots are under `docs/ux/shots/`. This review itself did not modify App code.

## 1. Five principal findings at the time

1. **P0: speech did not follow the screen.** Navigation, cancellation, confirmation, tab changes and closing Settings left old speech running. New informational messages expired after six seconds in the queue. A roughly 40-second privacy narration continued over home selection, suppressing its instruction. After rapid invitation confirmation, a 12-second confirmation prompt continued while the actual sent/accepted results were never spoken.
2. **P0: onboarding did not explain purpose or next action.** Six profile-oriented steps led directly to the main screen without teaching invitations, outings, finding or microphone use.
3. **P1: poor visual priority.** The same scene occupied 42% of all three tabs, leaving only one to one-and-a-half cards visible. An unactionable no-neighbors-outside card often came first, while incoming invitations were hidden lower on Neighbors.
4. **P1: no in-App text-size control.** System scaling was capped, smaller sizes had no effect, and larger text did not reduce the scene footprint.
5. **P1: technical wording and unclear actions.** Hidden/cache/server-address/AI/circle/leave/percentage jargon confused the persona walkthrough. Departure, editing and cancellation looked equally important; rescheduling initially kept the same time; eight-second banners disappeared quickly.

## 2. Findings and proposed changes

Original priority scale: P0 blocks use, P1 causes substantial confusion, P2 polish. Effort: S under half a day, M one–two days, L over three days. These are historical estimates, not new delivery promises. Code line numbers refer to that snapshot and may have moved.

| # | Priority / effort | Observation and user impact | Proposed change / evidence |
|---|---|---|---|
| 1 | P0 / S | Long privacy speech continued into home selection; its new instruction never played. | Stop speech on every onboarding transition; speak one short instruction and shorten privacy summary. `Announcer.swift:29,48–64`, `Onboarding.swift:56,264,424,623,722`. [Screen](shots/ux_03_onb_pickhome.png) |
| 2 | P0 / S | Confirming within a second left the 12-second prompt playing, while sent/accepted results expired. Cancellation also left it speaking. | Confirm: stop then speak result. Cancel/dismiss: stop without replacement. `AppStore+Voice.swift:233,252`, `AppStore+Meetup.swift:79,116`. [Confirm](shots/ux_23_quick_ok.png), [cancel](shots/ux_16_after_cancel.png) |
| 3 | P0 / S | Only microphone, replay and preview stopped speech; tabs, Settings and backgrounding did not. | Add interrupt/queue-clear hooks to tab, phase, Settings, card dismissal, finding, pairing and `appActive(false)`. `Announcer.swift:72`, `MainView.swift:516`, `AppStore.swift:49,59,63,76`, `AppStore+Services.swift:6`. |
| 4 | P0 / M | Six setup steps collected data without explaining product purpose or the first useful action. | Introduce purpose, concise privacy, combined floor/nickname, microphone trial and a first-day checklist. [Consent](shots/ux_01_onb_consent.png), [floor](shots/ux_05_onb_floor.png), [avatar](shots/ux_06_onb_avatar.png), [nickname](shots/ux_07_onb_nickname.png), [main](shots/ux_08_first_main.png) |
| 5 | P0 / S | An invitation banner vanished after eight seconds; Today had no persistent invitation, Neighbors buried it, and tabs had no badge. | Keep response banners longer, at least 30 seconds, retain a top Today card and show a Neighbors badge. Prioritize incoming replies. `AppStore.swift:207`, `Tabs.swift:632–660`. [Banner](shots/ux_41_invite_banner.png), [card](shots/ux_42_invite_card.png), [buttons](shots/ux_43_invite_buttons.png) |
| 6 | P1 / M | A 42% scene repeated across tabs, hiding content and making pages look alike. | Show a smaller scene only on Today; give other tabs the full content area. `Design.swift:11`. [Today](shots/ux_08_first_main.png), [board](shots/ux_29_board_scrolled.png) |
| 7 | P1 / M | Fixed 34/24/20 typography scaled only within a system range; no in-App choice. Larger text left one card visible. | Add prominent size controls, including a smaller 20 pt body option, and reduce the scene at larger sizes. `Design.swift:35–66`, `RootView.swift:30`, `MainView.swift:505`. [Small](shots/ux_38_type_xsmall.png), [large](shots/ux_39_type_axl.png) |
| 8 | P1 / S | Unlabeled orange microphone did not explain its purpose or accepted input. | Add a Speak label and a one-time actionable example. `MainView.swift:429`. [Screen](shots/ux_08_first_main.png) |
| 9 | P1 / M | Fixed Today ordering put non-actionable outside status before an imminent meeting. | One urgency-selected hero: incoming request, today's departure, outside neighbor, weather invitation, first pairing. `Tabs.swift:16–31`. [Screen](shots/ux_24_today_appts.png) |
| 10 | P1 / M | 88 speech call sites, spoken toasts and 12–13-second recaps produced excessive delayed output; first server audio took 0.5–3 seconds in logs. | Prioritize decisions and incoming social requests, shorten recaps, and cache fixed prompts. `AppStore.swift:225–227`. |
| 11 | P1 / S | All banners vanished after eight seconds. The review assumed older users might need longer; this was not a measured resident timing study. | Keep informational banners brief but preserve response-required cards, as in finding 5. [Screen](shots/ux_31_out_banner.png) |
| 12 | P1 / M | Change Time opened the original time and five confusing actions. | Preselect a different time, offer direct choices and retain only Send / Cancel Edit. `AppStore+Meetup.swift:125,248`. [Screen](shots/ux_44_invite_reschedule.png) |
| 13 | P1 / S | Departure had the same secondary styling as edit/cancel. | Within 30 minutes, make Departure primary and group edit/cancel. `Tabs.swift:235`. [Screen](shots/ux_25_today_appt_card.png) |
| 14 | P1 / S | Scene could not pan/zoom but some unlabeled landmarks were tappable, creating inconsistent expectations. | Choose either truly view-only with an accessible list, or clearly labeled tappable landmarks. Later interaction decisions supersede this old proposal. `MainView.swift:284`. [Screen](shots/ux_40_scene_drag.png) |
| 15 | P1 / S | A landmark's primary action was rare renaming rather than meeting there. | Make Invite Here primary, or Walk Outside without neighbors; reduce rename prominence. `Cards.swift:193`. [Screen](shots/ux_11_landmark_card.png) |
| 16 | P1 / S | Hidden/cache/AI/circle/leave and shade percentages were unclear. | Use ordinary language, remove technical labels and show sunny/shady instead of percentages. Never assert someone is home without evidence. `AppStore+Map.swift:275`, `MapService.swift:14`. [Main](shots/ux_08_first_main.png), [map](shots/ux_03_onb_pickhome.png), [landmarks](shots/ux_10_today_landmarks.png) |
| 17 | P1 / S | Server address, seven-step voice download guide, demo and location diagnostics made Settings roughly eight screens long. | Keep size/sound/language/profile/alerts prominent; collapse setup diagnostics under Advanced. `VoiceSettingsSection.swift:303–346`, `Settings.swift:73–84`. [Server](shots/ux_35_settings_voice_top.png), [guide](shots/ux_36_settings_guide.png) |
| 18 | P1 / M | Small, pale building targets took three taps; guidance did not change after selection. | Suggest the nearest residence for confirmation, provide clearer orange selection and retain manual choice. [Before](shots/ux_03_onb_pickhome.png), [after](shots/ux_04_onb_picked.png) |
| 19 | P1 / M | My avatar was offscreen after departure; the action falsely said I was already at the bench. Arrow appeared only nearby. | Frame both people, show a large arrow at distance and use stage-correct departure/approaching/met actions. `FullScreen.swift:559`. [Far](shots/ux_26_find_full.png), [near](shots/ux_49_find_near.png) |
| 20 | P2 / S | Four avatar choices overloaded first use and the final row was covered. | Initially ask only mobility and defer optional appearance choices. This was a proposal, not a restriction on inclusive current design. [Screen](shots/ux_06_onb_avatar.png) |
| 21 | P2 / S | Floor wheel was slow for high floors; the building illustration looked draggable but was not. | Use large minus/plus and numeric input, or make the illustration genuinely adjustable. `Onboarding.swift:596,635`. [Screen](shots/ux_05_onb_floor.png) |
| 22 | P2 / S | Meeting finding and ad-hoc finding had different bottom controls. | Reuse one bottom bar. [Meeting](shots/ux_26_find_full.png), [ad-hoc](shots/ux_48_find_live.png) |
| 23 | P2 / S | After meeting, a rename card remained and Today still prompted finding the same person. | Clear selected landmarks and show walking together. [After](shots/ux_27_after_end.png), [met](shots/ux_50_find_met.png) |
| 24 | P2 / M | Notification/location prompts followed onboarding, then two microphone dialogs; wording mentioned implementation details. | Ask permissions when needed and use plain purpose explanations. The old proposal delayed Always until after a first walk; later feedback changed its timing. `Notifier.swift:15`. [Prompt 1](shots/ux_17_mic_perm.png), [prompt 2](shots/ux_18_mic_perm2.png) |
| 25 | P2 / S | The first normal-mode card explained permission/backfill mechanics at excessive length. | One plain sentence and an enable action. `LocationViews.swift:267`. [Screen](shots/ux_51_real_today.png) |
| 26 | P2 / S | Small gray headings obscured section hierarchy and important status. | Bold black 24 pt section headings; reserve gray for secondary text. `Tabs.swift:904`. [Screen](shots/ux_22_neighbors_scrolled.png) |
| 27 | P2 / S | Change Time wrapped into two lines resembling two buttons. | Stack actions or shorten the label. `Tabs.swift:739`. [Screen](shots/ux_43_invite_buttons.png) |
| 28 | P2 / S | Roughly 51 x 31 switches and 94 x 32 floor controls had short targets; labels were not tappable. | Whole-row interaction and large explicit on/off controls. [Neighbors](shots/ux_22_neighbors_scrolled.png), [Settings](shots/ux_32_settings_top.png) |
| 29 | P2 / S | Scrolled content overlapped the Settings title. | Opaque navigation background. [Screen](shots/ux_36_settings_guide.png) |
| 30 | P2 / S | Only about two leaderboard rows were visible, partly covered by my fixed row. | Reclaim scene space as in finding 6. [Screen](shots/ux_29_board_scrolled.png) |
| 31 | P2 / S | The real board contained test accounts; this walkthrough created anonymous account `d0a56c37-1c9f-443c-949f-088b6573fddd`. | Arrange authorized cleanup of identified test accounts before a real-data demo. This translation performs no deletion. [Screen](shots/ux_52_real_board.png) |
| 32 | P2 / S | Heard-input text repeated nearly the same large recap. | Small transcript label, one large structured result. [Screen](shots/ux_20_voice_confirm.png) |
| 33 | P2 / S | Suggested landmark renaming was rare and looked like changing official place names. | Prefer weather and finding examples. `AppStore+Voice.swift:118`. [Screen](shots/ux_19_listening.png) |
| 34 | P2 / S | Time alternatives proactively suggested after-sunset walks. | Avoid after-sunset suggestions unless explicitly requested; this is a design precaution, not a verified safety guarantee. [Screen](shots/ux_15_propose_changed.png) |
| 35 | P2 / S | Floating microphone overlapped the bottom card and risked accidental taps. | Hide or integrate it while the card is shown. [Screen](shots/ux_14_propose_card.png) |

## 3. Speech interruption rules proposed then

`Announcer` queued rather than interrupted. Informational messages older than `staleAfter=6` expired; prompts cleared queued information but not currently playing audio. `hold()` was the only direct stop path, also reached indirectly by replay/preview. Navigation, dismissal and backgrounding did not stop output, and every toast spoke.

Desired rule: **when the screen changes, stop obsolete speech; speak the new relevant instruction or confirmed result promptly.**

| User action | Historical behavior | Desired behavior |
|---|---|---|
| Onboarding next/back/consent | Old page kept speaking; new prompt could expire | Stop, then one short new instruction |
| Confirm/send/go/enable | Old prompt could continue 13 seconds and hide the result | Stop, then result |
| Cancel/reject/dismiss/swipe card away | Confirmation instruction continued | Stop without replacement |
| Switch tabs | Continued | Stop obsolete output; consider urgent incoming requests separately |
| Open/close Settings or Done | Preview continued | Stop |
| Enter/leave finding or pairing | Continued | Replace with relevant new-screen guidance |
| Background/lock | No handling | Stop App speech; use authorized system notifications for walks |
| Microphone | Stopped correctly | Retain |
| Replay | Stopped and restarted | Retain |

Implementation proposal: add `interrupt()` to clear queue, cancel pump and stop the speaker. Trigger it from tab/phase/Settings/finding/pairing changes, dismissed voice/proposal/selection cards and `appActive(false)`. Prompts and user-action results should replace obsolete information. Make toast speech opt-in for important cases. Coordinate changes to `Announcer.swift`, `AppStore+Voice.swift` and `Speech.swift` with the voice owner; the old note reported concurrent work there.

## 4. Proposed screen priorities

One orange primary action per screen; scene mainly on Today; response-required requests first; microphone labeled.

- **Today at home:** compact scene, one hero invitation/departure/social action, then walking summary and weather. The wireframe proposed Mrs Chan's invitation with accept/change/decline, a 24-minute/9-day summary, a weather suggestion and labeled microphone, with a two-request tab badge.
- **Today while walking:** elapsed time and an available neighbor to find; quick heat, seating and difficult-path reports below.
- **Neighbors:** incoming invitations, compact neighbor rows and invitation actions, with pairing prominent when no neighbors exist. The old wireframe's at-home assertion must be interpreted through the later privacy correction: absent outing data does not prove home presence.
- **Leaderboard:** prioritize my rank/streak and the list, with no scene. Any suggested catch-up figure must derive from actual records rather than be invented.
- **Finding:** a large directional arrow, peer/distance/place, both people framed, stage-specific departure/approaching/met action and End in a corner.

## 5. Proposed five-step onboarding

The old six-step flow plus 3–5 system dialogs and a 40-second opening narration should become five steps, each with one purpose, at most two visible sentences and one spoken sentence under eight seconds. Stop the previous step before speaking.

| Step | Screen content | Short spoken purpose | Actions |
|---|---|---|---|
| Welcome | Explain recording walks, pairing in person and voice invitations | Record walks and invite neighbors | Start; optional skip introduction |
| Privacy | Three summaries with detailed audience/data handling available | Explain local tracks and neighbor visibility | Agree / decline |
| Home | Explain location, request permission, suggest a nearby residence | Ask whether this is the user's building | Yes / choose another |
| Floor and nickname | Large controls and suggested nicknames | Ask floor and preferred name | Continue |
| Trial | Ask about today's weather by speech or a tappable example | Try speaking | Hear answer, then finish |

The original proposal used a default older walking avatar; this is not a current requirement to classify all residents as older. Current scope includes all ages. Its privacy summary is also not a complete policy: current voice processing and mutually consented precise live finding must be disclosed.

After setup, a first-day card proposed three tasks: walk ten minutes, pair with a neighbor and invite them tomorrow. The original proposal dismissed after completion; later feedback retained it until manual dismissal.

Permission timing was proposed around the first relevant use: notifications after a first neighbor, microphone/recognition on first tap, and Always after the first walk. Later code/feedback may supersede this timing. Estimated persona completion times of about two minutes for guided use and forty seconds for skipping were design estimates, not measured resident outcomes.

## Test limitations

- Pairing and finding used demo data; no real UWB or live direction reliability was tested here.
- Microphone did not crash in this simulator run: after two dialogs it entered listening, and a tappable example completed the invitation.
- A LAN Mac voice server was running; logs showed roughly 0.5–3 seconds to first audio. This is not a broad latency benchmark.
- Initial simulator location was misconfigured to San Francisco, producing Pacific Building / CitizenM Union Square; resetting location restored Queen's Hill. This was setup error, while also showing the App did not warn that the location was outside Hong Kong.
- The normal-mode test created the anonymous account identified in finding 31; cleanup remained a separately controlled task.
