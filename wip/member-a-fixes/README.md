# Member A: Four Audit Fix Batches (Merged)

These patches address the [2026-10-08 audit](../../docs/audit/member_a_audit_2026-10-08.md). All four were merged on **2026-10-10** into `prototype/ios-3d-diorama`, in voice → walking → map → UI order, one commit per batch. They are historical patch artifacts; **do not reapply them**. Original patch bytes and original-language evidence are retained.

| Patch | Scope | Historical integration status |
|---|---|---|
| `voice.patch` | Rename recap, faithful broadcasts, automatic ten-minute-late prompt, finding microphone, speech/VoiceOver queue and complete CommunityService contract | Merged |
| `walk.patch` | Stopping places, locked-screen backfill, measured steps, multi-day leave, local notifications, tolerant saves and device demo defaults | Merged; one incorrect unit test corrected |
| `map2.patch` | Missing-residence fallback, sufficient landmarks, sunset wording, Overpass endpoints, disclosed location failure, thread safety and idle rendering | Merged |
| `ui.patch` | Stalled UI, color-vision palette, skin/age choices, leaderboard, accessible building list and consent | Merged; integration exposed lost updates from store-level withAnimation, subsequently fixed. Banners, cards and toasts became persistent views |

Cross-batch integration connected `uploadDay`, date-specific `setLeave` including voice requests, and `updateProfile` including building/skin/age. Settings added age, skin tone and privacy explanations. Onboarding offered the sample estate after ten seconds waiting for location/map data. This record does not constitute a new acceptance run of current code.
