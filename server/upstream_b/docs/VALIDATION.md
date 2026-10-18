# Historical validation record and handoff acceptance

> These are dated reports from member B's standalone delivery. Later entries supersede earlier statements only for the checks they explicitly describe. They are not independent validation of current StreetWalk or its deployed services.

## 12 October 2026 — initial Windows Doubao increment

- 66 Python tests passed, including a mock ASR → business checks → TTS WebSocket flow; real local HTTP business smoke passed.
- test_capture.cjs passed synthetic PCM resampling/packetization at 16/44.1/48 kHz.
- test_voice_ui.cjs passed stale-audio rejection after interruption, microphone release, permission arriving after cancellation, and local-only device checks.
- The Windows page was opened to verify unconfigured status and local refusal display.
- At this stage, **no real Doubao calls, microphone trials, older-speaker accuracy, speaker echo, voice quality, sustained conversation, or cloud latency had been measured**. Provider responses were fixtures.
- The new Windows route used Doubao; iOS still used the old client and was not a completed real-time migration. See DOUBAO-WINDOWS.md.

The following earlier baseline is retained for traceability.

## 10 October 2026 — iOS/backend baseline

Environment: Windows, Python 3.12, no Swift/Xcode; Docker client present but daemon unavailable.

| Check | Reported result | What it establishes |
|---|---|---|
| python -m unittest discover -s tests -v | 41 passed | Business/state safety, API contracts, and provider request adaptation with mocked networking |
| python -m compileall -q assistant | Passed | Python syntax only |
| python tools/check_delivery.py | Passed | Xcode references, package paths, plist/scheme structure; not Swift compilation |
| tools/smoke.py against Uvicorn | Passed | Actual local HTTP invitation → place selection → confirmation → duplicate confirmation using one receipt |

Coverage included duplicate-name disambiguation; refusing to replace a deleted contact with another same-name person; preserving/revalidating contact IDs during clarification; complete/partial/missing monthly data; missing time/walking-limit prompts; stale places/weather; forged identity rejection; cross-user draft isolation; rate limiting; secret-free errors; old-card invalidation; cancelled/expired draft rejection; one claim under concurrent confirmation; original-receipt recovery after interruption; no blind retry of uncertain writes; no false success on rejection; no canned transcription without configuration; SSML escaping; and structured-output validation.

The Starlette test client emitted an httpx deprecation warning without failing the 41 tests. This did not establish future-version compatibility; current dependencies were pinned.

An attempted existing WSL Ubuntu launch failed with HCS_E_HYPERV_NOT_INSTALLED, so it provided no Swift compilation evidence. No system components or virtualization settings were changed. iOS cancellation guards were added to prevent stale replies overwriting input or starting playback, but still required Mac/device checks.

## Items not verified in that baseline

| Item | Status | Required environment |
|---|---|---|
| Six Swift contract tests | Not run | Mac or GitHub macOS runner |
| iOS Debug/Release builds | Not run | Xcode/macOS runner |
| iPhone installation, recording, system speech | Not run | Signing and physical iPhone |
| Real Azure recognition/synthesis and Qwen understanding | Deferred by user | Authorized configured APIs |
| A's app and real business API | Teammate integration pending | Four endpoints in INTEGRATION.md |
| Docker build/public deployment | Not run | Docker daemon, TLS proxy, deployment account |

The delivery was **module code with backend checks, not production acceptance**.

## Mac handoff order

1. Install dependencies and rerun the backend checks, or use python tools/verify_backend.py. Historical test counts may differ from current code.
2. Run swift test --package-path ios and both Debug/Release xcodebuild commands.
3. Install on iPhone, enter the computer's same-Wi-Fi address, and check demo/unconfigured labels.
4. Exercise all supplied text examples and confirm that every write requires approval. The earlier handoff called these seven examples; use the actual current example list.
5. Record results below. Preserve Xcode errors/request_id, excluding tokens and real audio from shared logs.

## Physical-device checklist

All entries below were pending in the original checklist.

| Scenario | Expected behavior | Original result |
|---|---|---|
| First microphone denial | Clear explanation; text input remains usable | Pending |
| Recording under 0.2 s or over 30 s | Reject too short; automatically stop at 30 s | Pending |
| Abandon recording/call/background | No abandoned upload; usable recovered UI | Pending |
| Recording without API configuration | Explicit unconfigured state; no fake recognized sentence | Pending |
| Cantonese/Mandarin system speech | Correct language or clear missing-voice explanation | Pending |
| Wrong recognized name with API enabled | Editable transcript before submission; no automatic action | Pending |
| Select place and confirm | Actual receipt or explicitly labeled test result | Pending |
| Repeated taps/network loss/process restart | No duplicate write; restore/query original operation | Pending |
| Server completed but phone timed out | Reconcile the same operation and restore completion | Pending |
| Refresh an expired token | Recover pending operation under the same account identity | Pending |
| Switch users | Never load another user's pending operation | Pending |
| Release over HTTP | Reject HTTP; allow valid HTTPS | Pending |
| VoiceOver/large text | Main controls accessible; confirmation content untruncated | Pending |

Provider-enabled evaluation must separate Cantonese/Mandarin and include multiple speakers, speeds, noise conditions, mixed names, and corrections. Report intent/field accuracy, completion, and latency percentiles. This baseline had none of those measured results.

## 12 October — response latency and false interruption fix

- With authorized real provider access, synthesized Cantonese asking what the assistant can do was streamed in 200-ms PCM chunks. No microphone was used; audio stayed in memory.
- Before the fix, one sample took 19.218 s from final recognition to interpretation and about 20.50 s to first audio.
- Set Chat API thinking.type=disabled and removed volume-threshold-only cancellation, retaining ASR-content/manual interruption.
- After the fix, the same single sample took 2.266 s to interpretation and about 3.33 s to first audio; 31 chunks arrived and answer_done completed. These are not percentiles or human usability results.
- Twenty Doubao-module tests and frontend state checks passed, including noise-onset preservation of pending replies.
- Reproduction: python tools/check_voice_roundtrip.py, with provider authorization and saved local configuration. It uses Python 3.12 audioop and is incompatible with Python 3.13's removal of that module.
- Real microphones, speaker echo, accents, and interruption remained pending.

## 12 October — North District weather integration

- Live public endpoints returned station temperatures, North District rainfall, Hong Kong-wide forecasts, and warning summaries. Responses distinguished observation location from forecast coverage.
- All 79 backend tests, structure checks, HTTP smoke, UI-state, and PCM checks passed. Weather tests covered dates, regions, freshness, cancelled/expired warnings, networking, and malformed data.
- One synthesized Cantonese North District weather question completed ASR → Ark → Observatory → TTS with a weather field, 67 audio chunks, and answer_done. Text result: 4.485 s; final recognition to first audio: about 5.70 s. This was one synthetic-input trial, not older-user validation or a latency distribution.
- Before weather integration, the user reported that the original voice conversation connected. Actual microphone weather use still required trial.
- The then-running Windows service had the feature loaded. That version restored credentials only in service memory and its original delivery package contained no credentials. Later private-package decisions differ; consult the current configuration guide.
