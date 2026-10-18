# Recreational Social App — Development Specification v1.0

> Historical design baseline dated 6 October 2026. Requirements, proposed thresholds, technology choices, and acceptance targets below describe that version; they are not claims that the current app implements or has validated every item. See the root README and current source for the integrated product, three-language support, and the approved live-finding privacy boundary.

- Date: 2026-10-06
- Baseline: Recreational Social App Requirements v0.4, Track 2
- Platform: native iPhone app
- Prototype deadline: 2026-10-18
- **[TBD]** means no agreement has been reached. The value in parentheses is the implementation default until a decision is made.

## 1. Product

The app automatically records walks by residents of newly occupied Northern Metropolis estates. People who frequently walk in the same area appear on a shared community board. When two people meet, bringing their phones together makes them neighbors. Neighbors can receive each other's outing reminders, arrange a walk by voice, and use the app to find each other on the day.

The audience is new residents of all ages. Inclusive design must make every feature usable by older residents too.

## 2. Scope

This version includes F1–F10 below.

It excludes in-app chat, forwarding, general-purpose question answering, and health advice. Group classes, points, suggestion voting, and a general AI bot from v0.1 are outside this version.

## 3. Functional specification

### F1 — Automatic walk recording

- Start recording when walking is detected and finish when walking stops, without user interaction.
- Detect walking with Core Motion; enable location while walking.
- Stop recording within the home area and stop showing the user's location to others.
- Each walk produces one **walk record** and one or more **stopping points**.
- A stopping point means remaining nearby for at least **[TBD] (2 minutes)** within **[TBD] (30 metres)**.
- Keep raw routes on the phone; upload only the landmarks associated with stopping points.
- Acceptance: record a complete walk without the user touching the phone.

### F2 — Community circles

- Group users who share at least three stopping points within one week.
- An estate can contain multiple circles, and a person can belong to multiple circles.
- When an estate has just opened and there is insufficient data, initially group residents by building.
- Use predefined groups in the prototype.

### F3 — Landmark naming (AI)

- Given a stopping point's coordinates and nearby facilities, generate a name residents would naturally use, such as “the seats behind Block 7.”
- Allow voice renaming; the new name applies to everyone in the same circle.
- Display locations as “landmark name + nearby,” without coordinates or a map.

### F4 — Community board

- Provide one ranked board per circle.
- Ranking basis: **[TBD] (consecutive days of walking)**.
- Represent each member with a cartoon avatar, block and floor, and an AI-generated daily sentence, such as “The resident on the 12th floor walked to the riverside today.”
- Do not show names, photos, or unit numbers to non-neighbors.
- Allow leave requests by voice; preserve the walking streak during leave.
- Compare circles' total steps each month. Announce the winning circle at month-end and give its members a cartoon badge.

### F5 — Proximity pairing

- Treat two phones within **[TBD] (10 cm)** as a pairing gesture and establish a neighbor relationship.
- Do not provide user search, remote invitations, or invitation links.
- Speak a confirmation on both phones after pairing.
- Either person can unlink at any time without notifying the other.
- Proposed implementation: Nearby Interaction/UWB, with session credentials exchanged over MultipeerConnectivity.
- Hardware assumption: iPhone 11 or later on both sides, excluding SE; both apps remain in the foreground.
- Fallback: QR pairing for unsupported devices and demonstrations.
- Acceptance target: complete pairing within two seconds.

### F6 — Outing reminders

- When a neighbor starts walking, send a short reminder, such as “Mrs Chan on the 12th floor has just gone out, probably near the riverside.”
- Enable both directions by default, asking both people when they become neighbors.
- Allow sending and receiving to be disabled independently; allow a receiving time window.
- Acceptance: receive a reminder within two minutes of departure, containing a landmark and no coordinates.

### F7 — Voice invitations (AI)

- Start a meetup with one sentence, such as “Invite Mrs Chan for a walk tomorrow.” Only neighbors can be invited.
- Extract the person and time.
- Choose a place that both people often pass, is close to both, has seats, and preferably has shade at the agreed time.
- The recipient accepts with one confirmation; both then hear the complete arrangement.
- Allow time and place to be changed by voice or buttons.
- Acceptance target: no unrelated screen between the spoken request and receipt by the other person; explain the place choice in one sentence. Actions affecting another person still require confirmation.

### F8 — Finding each other

- Notify the user when the other person leaves and estimate their arrival time.
- Vibrate within 50 m. Within UWB range, show a large arrow and landmark icon pointing toward the other person, without a map.
- Allow a short message such as “I am at the pavilion” to be relayed.
- If the participants have not met ten minutes after the agreed time, ask whether to make a phone call.

### F9 — Weather and shade advice (AI)

- Use the forecast, shade data, and departure habits to suggest an earlier, later, or cancelled walk the previous evening or before departure; recommend shaded routes.
- If cadence falls substantially during a walk, suggest a rest and identify the nearest seat.
- Limit each suggestion to one sentence; do not repeat it if ignored.

### F10 — Northern Metropolis monthly report (AI)

- During a walk, accept reports such as “It is too sunny here” or “There are no seats here,” and attach them to the nearest landmark.
- Generate a monthly report from anonymous estate-wide walking data and resident reports, intended for social workers, estate management, and new-development-area teams.
- Cover busy unshaded routes, frequent stopping places without seating, construction detours, and informal meeting places.
- Output only landmark-level aggregates involving at least **[TBD] (10 people)**; never output individual routes.
- Keep this module independent: removing F10 must not affect F1–F9.

## 4. General requirements

- Prioritize voice and visuals over nested menus. Every voice action needs a large-button alternative.
- Minimum text size: 24 pt, adjustable. Check the palette for color-vision accessibility.
- Avatars should represent wheelchairs, walking sticks, strollers, different ages, and skin tones.
- Provide both visual and spoken prompts.
- Support Cantonese and Mandarin in this original baseline. English was added later.
- During onboarding, explain who can see what and obtain informed consent.

## 5. Technology choices

| Component | Choice | Status in this baseline |
|---|---|---|
| App | SwiftUI | Confirmed; continue from the StreetWalk prototype |
| Backend | **[TBD] (Supabase)** | Pending |
| LLM API | **[TBD]** | Pending |
| Speech recognition | iOS Speech (`zh-HK`, `zh-CN`) | Confirmed; measure outdoor Cantonese recognition, including older speakers. If below 80%, add read-back confirmation. |
| Speech synthesis | AVSpeechSynthesizer | Confirmed |
| Pairing and finding | Nearby Interaction + MultipeerConnectivity | Confirmed |
| 3D buildings | Lands Department 3D Digital Map, Cesium 3D Tiles through CSDI | **[TBD]** Check whether Fung Wong Leng Estate is covered. Otherwise extrude building footprints using estimated floor heights. |
| Shade | 3D buildings + sun-position algorithm | Confirmed; tree shade excluded |

## 6. Responsibilities

### Member A

- App structure, navigation, design system, login, and consent.
- Backend and all tables.
- All screens and visuals, including B's features and pairing animations.
- F1, F2, F4 ranking/leave/competition, F6, and F8.
- Shade calculation.

### Member B

- Speech-recognition and synthesis wrappers.
- F3, F4 daily descriptions, F7, F9, and F10.
- Voice commands for leave and renaming.
- F5 pairing and spoken-confirmation logic.

### Collaboration rules

- B supplies the interfaces in §8; A's screens call them. B does not implement the UI.
- A first completes the screens with mock data, replacing each mock as B delivers the corresponding interface.
- Once agreed, interface changes require both members' approval.

## 7. Initial data model

Confirm this draft together on day one.

| Table | Main fields |
|---|---|
| `users` | ID, nickname, block, floor, avatar, home area, language, creation time |
| `landmarks` | ID, name, coordinates, seating availability, estate, circle ID |
| `circles` | ID, name, estate |
| `circle_members` | Circle ID, user ID |
| `neighbors` | Two user IDs, creation time, each user's send/receive reminder settings |
| `walks` | ID, user ID, start/end times, steps, visited landmark IDs, daily sentence |
| `leaves` | User ID, start/end dates |
| `meetups` | ID, inviter, recipient, time, landmark ID, selection reason, status: pending/accepted/completed/cancelled |
| `reports` | ID, user ID, landmark ID, original text, category, time |

## 8. Interfaces

### Supplied by A, called by B

| Interface | Input | Output |
|---|---|---|
| `getShade(landmarkId, timeRange)` | Landmark, time range | Shade fraction from 0 to 1 |
| `createNeighbor(userA, userB)` | Two user IDs | Success/failure |

### Supplied by B, called by A

| Interface | Input | Output |
|---|---|---|
| `parseVoice(audio)` | Recording | Intent (invite/leave/rename/report) and parameters |
| `dailyLine(walk)` | One walk record | One sentence |
| `nameLandmark(coord, facilities)` | Coordinates and nearby facilities | Landmark name |
| `pickMeetupSpot(userA, userB, time)` | Two users and a time | `{landmarkId, reason}` |
| `walkAdvice(userId, date)` | User and date | One suggestion, or null |
| `monthlyReport(estateId, month)` | Estate and month | Monthly report |
| `speak(text)` | Text | Spoken playback |

Add input/output examples for every interface on day one.
