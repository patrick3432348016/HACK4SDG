# Integrating the Assistant into the Main App

> Historical member-B package contract. For the current integrated service, including English support and Doubao, see [server/README.md](../../README.md). The original package below supported `zh-HK` and `zh-CN`.

## iOS integration

In Xcode, choose **Add Package Dependencies → Add Local**, select this package's `ios` folder, and add `MobilityAssistant` to the main App target. Alternatively publish the package in the team's Git repository. It requires iOS 17 and no third-party Swift dependencies.

Add `NSMicrophoneUsageDescription` to the main App's Info.plist, explaining that recordings are sent to the configured service. This original B package does not persist raw audio. Use HTTPS; do not copy the integration shell's relaxed Debug ATS settings.

```swift
import MobilityAssistant
import SwiftUI

// Create on MainActor and retain through StateObject or another stable owner.
let client = try AssistantClient(baseURL: URL(string: "https://assistant.example.com")!) {
    // Obtain the current token on every request to support token refresh.
    try await yourAuthManager.currentAccessToken()
}
let model = AssistantViewModel(
    client: client,
    identityScope: "production:" + yourAuthenticatedUserID
)
// Use this integration UI, or bind the model to the main App's own interface.
AssistantPanel(model: model)
```

`yourAuthManager` and `yourAuthenticatedUserID` stand for A's existing authentication system; they are not package symbols. Never embed Azure, Qwen or backend administrator credentials in the App. The default `local-demo-only` token is for local tests only.

`identityScope` must separate environments and users; do not derive it from a rotating token. The model persists the operation ID before execution and uses it to query the original result after a timeout or process termination. Recreate the ViewModel when switching accounts. Call `backgrounded()` when leaving or suspending the view; `AssistantPanel` already does this. Cancelling a network request does not undo a business operation.

Flow: text or recording → review transcript → send → select contact/place → confirmation card → confirm or cancel. Users may edit text and continue. The model must not automatically execute operations requiring confirmation.

## HTTP API exposed to the App

Every `/v1/` request requires `Authorization: Bearer <A user token>`. Production forwards the token to A for verification and never trusts a client-supplied user ID. Demo mode accepts only `DEMO_TOKEN`, mapped to `demo-user`.

| Method and path | Input | Result / purpose |
|---|---|---|
| `GET /healthz` | No authentication | Process liveness, not provider availability |
| `GET /v1/capabilities` | User token | Demo/production mode and configured speech/model capabilities |
| `POST /v1/speech/transcribe?locale=zh-HK` | Raw `audio/wav`, 16 kHz mono PCM16, 0.2–30 seconds | `text`, `locale`, `duration_seconds`, `source` |
| `POST /v1/speech/synthesize` | `{"text":"Hello","locale":"zh-HK"}` | MP3 audio; supply text appropriate to the selected locale |
| `POST /v1/assistant/turn` | `{"text":"...","locale":"zh-HK","conversation_id":null}` | Commands, daily greetings, landmark naming, place recommendations, suggestions and monthly reports |
| `POST /v1/conversations/{id}/choice` | `{"kind":"contact","value":"returned ID"}`; kind may also be `place` | Continue with a choice offered by the service; arbitrary choices are rejected |
| `POST /v1/drafts/{id}/confirm` | None | Atomically claim and submit; repeated calls must not duplicate writes |
| `POST /v1/drafts/{id}/cancel` | None | Cancel an unsubmitted confirmation card only |
| `POST /v1/drafts/{id}/reconcile` | None | Query only; never submit an unsubmitted card |

This original contract supports `zh-HK`/`zh-CN`. Times use ISO 8601 with a time zone; relative times are interpreted in Hong Kong time. Conversation and draft IDs are 32-character hexadecimal strings.

Unified business reply:

```json
{
  "conversation_id": "32-character hexadecimal ID",
  "status": "needs_confirmation",
  "message": "Explanation and confirmation for display",
  "speech_text": "Text to speak",
  "command": {"intent": "invite"},
  "choices": [],
  "draft_id": "32-character hexadecimal ID, or null",
  "data": {},
  "demo": true
}
```

`command` contains the complete Command model, with absent fields set to null/false. Never infer success from `message`. States are `needs_input`, `choose_contact`, `choose_place`, `needs_confirmation`, `completed`, `cancelled`, `uncertain`, and `info`. `info` can represent advice or rejection; inspect `data.operation_status`. Only `completed` means a successful receipt was obtained.

Errors use `{"error":{"code":"SPEECH_NOT_CONFIGURED","message":"...","request_id":"..."}}`. Common HTTP statuses: 401 invalid login; 409 expired/conflicting state; 413 oversized body; 422 invalid parameters/audio; 429 service rate limit; 502 upstream call/format failure; 503 unconfigured/unavailable; 504 upstream timeout. Do not automatically retry operations with side effects.

## Business APIs required from A

B forwards the original user's bearer token. **A must authenticate and authorize every request.** B's demo identity must never grant access to real data.

### 1. `GET /assistant/session`

Return `{"user_id":"stable business user ID"}` on success, or 401/403 for invalid or unauthorized access. Do not return credentials or unrelated profile data.

### 2. `GET /assistant/context?at=<ISO8601>`

Return only the minimum context the current user may access. `at` is the requested meeting time, or the current time when no activity is specified.

```json
{
  "version": "context-version-123",
  "contacts": [{"id":"c1","name":"Uncle Chan","aliases":["Mr Chan"]}],
  "places": [{
    "id":"p1","name":"Garden","description":"Community garden meeting point",
    "is_open":true,"self_walk_minutes":8,
    "contact_walk_minutes":{"c1":10},
    "shade_fraction":0.8,
    "shade_valid_from":"2026-10-11T15:45:00+08:00",
    "shade_valid_until":"2026-10-11T16:30:00+08:00",
    "source":"A shade model v1, fraction of the meeting area"
  }],
  "weather": {
    "observed_at":"2026-10-10T10:00:00+08:00",
    "summary":"Upstream weather summary",
    "source":"Actual weather source",
    "outdoor_warning":false
  },
  "walks":[{"day":"2026-09-20","minutes":30,"metres":1500}],
  "walk_coverage":{"start":"2026-09-01","end_exclusive":"2026-10-01"}
}
```

- Change `version` when business data affecting operation validity changes. Do not change it merely because request time changes, or keep it permanently fixed.
- `is_open` describes the requested time; use null when unknown. Walking durations are minutes from A's routing calculation or a disclosed estimate. Missing values are not zero.
- Shade describes only the meeting area. Missing provenance or validity intervals mean unknown. Binary shade may use a documented 0/1 convention, but must not be advertised as a precise area fraction.
- Contacts may share names, but IDs must be unique. Add aliases only for a known same person; never ask the model to guess identity.
- `weather` may be null, in which case B reports missing data. A's trusted weather summary is not rewritten by the model.
- `walks` contains consented, deduplicated records, at most 10,000. `walk_coverage` declares a complete half-open date interval. B sets `data.report_available=true` only when coverage includes the previous full calendar month. Missing or partial coverage is unavailable, not zero activity. Complete coverage with no records legitimately means zero. A separate aggregate endpoint may be added later; this version uses this contract.
- Preserve and revalidate the selected contact ID while collecting time or walking constraints. If it disappears, return 409 `CONTACT_CHANGED`; do not substitute another person with the same name. Ask the user to restart and choose a current contact.

### 3. `POST /assistant/actions`

Header: `Idempotency-Key: <draft_id>`.

```json
{
  "operation_id":"the same draft_id",
  "expected_context_version":"context-version-123",
  "action": {
    "kind":"invite","contact_id":"c1","place_id":"p1",
    "starts_at":"2026-10-11T16:00:00+08:00",
    "max_walk_minutes":15,"prefer_shade":true
  }
}
```

Other actions: `{"kind":"leave","date":"2026-10-11"}` and `{"kind":"rename","new_name":"Xiao Ming"}`.

In **one atomic business transaction**, A validates authorization, context version, date, contact, place and constraints, then deduplicates by `(user_id, operation_id)`. Reject reuse of an ID with a different payload. B's SQLite duplicate prevention cannot replace A's idempotent writes.

Return HTTP 200 JSON:

- Completed: `{"status":"succeeded","receipt_id":"business record ID","message":"optional explanation"}`.
- Definitely not written: `{"status":"rejected","receipt_id":null,"message":"business rejection"}`.
- Processing: `{"status":"pending","receipt_id":null,"message":"processing"}`.

Use an explicit `rejected` receipt for business rejection. Non-2xx responses, disconnects and malformed receipts cannot prove that no write occurred; B therefore marks the result uncertain and does not retry automatically.

### 4. `GET /assistant/actions/{operation_id}`

Authenticate the user and return the same status/receipt structure. If absent, return HTTP 200 `{"status":"not_found"}`. **`not_found` does not prove that the earlier request never wrote data.** B keeps the result uncertain and must not issue another write automatically. A must provide authoritative status or resolve it in the main App. Retain completed-operation deduplication and receipts for at least 30 days.

## Confirmation invariants

1. Resolve contacts and places to real business IDs; model-generated IDs are never directly executable.
2. Raw user text, structured intent and API errors cannot substitute for a business receipt.
3. Repeated confirmation and client reconnection must not create another write.
4. Editing invalidates the previous card; cancelled unsubmitted cards cannot execute. Undoing an already submitted action requires A's separate business operation.
5. After timeout or process termination, restore the original operation ID and query its result. Do not merely clear the error and recreate the same invitation.
