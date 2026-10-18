# Member B — Mobility voice assistant

> Historical standalone delivery. This document preserves its original scope, paths, and validation boundaries. The integrated StreetWalk app now uses Doubao; see [the current server guide](../README.md). Do not follow the old package-upload instructions to replace the integrated repository.

A module for a native iPhone app: **Swift package + SwiftUI integration shell + Python/FastAPI service**. It excludes proximity pairing and does not recreate member A's UI, accounts, or database.

The original delivery was a runnable backend and iOS source awaiting Mac compilation/acceptance, **not a verified production app**. The user had deferred real API validation. Azure/Qwen quality, iPhone microphone behavior, and production business endpoints were unverified. Production mode refuses incomplete configuration so demo data cannot silently become a real service.

## Original delivery layout

| Path | Purpose |
|---|---|
| `backend/` | Speech/model adapters, business flows, confirmation state, deployment configuration, and tests |
| `ios/` | Importable MobilityAssistant Swift package, minimum iOS 17 |
| `ios/Demo/VoiceAssistantDemo.xcodeproj` | Independent iPhone integration shell |
| `docs/INTEGRATION.md` | A's integration steps and business contract |
| `docs/DEPLOYMENT.md` | API configuration, deployment, retention, and release gates |
| `docs/VALIDATION.md` | Verified/unverified items and device acceptance |
| `.github/workflows/assistant.yml` | Linux backend tests, Mac Swift tests, and iOS Debug/Release builds |

The original handoff required the package's complete contents, including .github, at a repository root, excluding the outer pairing project, .env, data/, and real recordings. That was a standalone-delivery instruction; this imported directory uses a different layout. Passing Mac CI does not replace iPhone acceptance.

## What can be checked without provider configuration

- Text invitation → explicit person/date/time/walking limit → meeting-place selection → confirmation → saved **test action**.
- Text leave and nickname changes require explicit confirmation; cancellation performs no business write.
- Daily sentence, landmark-name candidates, and monthly reports use clearly labeled fictional statistics/places.
- Missing weather is acknowledged rather than invented.
- Recording permission/capture requires iPhone testing. Unconfigured transcription returns a configuration error; it does not substitute a canned transcript.
- Installed system voices can speak locally; the UI identifies that cloud synthesis is not being used.

Without provider keys, text interpretation is limited rules for integration testing, not evidence of model understanding. These original Cantonese/Mandarin fixtures are intentionally preserved:

```text
约陈伯明天下午四点散步，遮荫优先，最多15分钟
約陳伯聽日下晝四點行下，唔好咁晒，最多15分钟
明天请假
改名为小明
散步建议
给社区花园起名
今日一句
生成月报
```

They cover inviting Mr Chan tomorrow at 4 pm with shade preference and a 15-minute limit, leave tomorrow, nickname change, walking advice, naming the community garden, a daily sentence, and a monthly report.

## Quick integration on a Mac

1. Install Python 3.12 and Xcode supporting the test phone's OS. From the original backend directory:
   ```sh
   python3.12 -m venv .venv
   source .venv/bin/activate
   python -m pip install -r requirements.txt -c constraints.txt
   python -m unittest discover -s tests -v
   python -m uvicorn assistant.app:create_app --factory --host 0.0.0.0 --port 8000 --no-access-log
   ```
   This is for a trusted LAN. The default mode is demo with token local-demo-only; do not expose that default publicly. On Windows, use python -m venv .venv and .venv\Scripts\Activate.ps1.
2. Open ios/Demo/VoiceAssistantDemo.xcodeproj, select your signing Team and a unique bundle identifier if needed, choose the iPhone, and run.
3. Use the same Wi-Fi. Enter the computer's LAN URL, such as http://192.168.1.20:8000, and the demo token. **localhost is not the computer from a physical phone**; it works in the simulator.
4. Keep account ID demo-user, connect, choose a text example, select the place, and confirm.
5. Test microphone denial/approval, the 30-second limit, abandoned recording, backgrounding, and Cantonese/Mandarin system speech.

The integration shell permits HTTP in Debug, **not Release**. Do not copy Debug ATS exceptions into A's production app. Transcription first fills an editable text field; it does not automatically execute a command.

## Engineering checks

This command runs backend tests, structure checks, and a real HTTP smoke test against a temporary service without using existing provider credentials or changing the integration database:

```sh
python tools/verify_backend.py
```

For separate structure and smoke checks, with the backend running:

```sh
python tools/check_delivery.py
python tools/smoke.py --url http://127.0.0.1:8000
```

On Mac:

```sh
swift test --package-path ios
xcodebuild -project ios/Demo/VoiceAssistantDemo.xcodeproj -scheme VoiceAssistantDemo -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project ios/Demo/VoiceAssistantDemo.xcodeproj -scheme VoiceAssistantDemo -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

## Product boundaries

- **Invitation sent** and **recipient accepted** are separate outcomes. B handles sending and cannot infer mutual acceptance from one call.
- Compare meeting-point shade and both walking times only. Do not claim route-wide shade, emissions reduction, health benefits, or medical safety.
- Filter places that are not explicitly open, lack walking data, or exceed the limit. With shade requested, require valid shade data, sort by shade descending, then by the greater walking time ascending. Otherwise minimize the greater walking time first. No random scores or unverified weights.
- Shade requires provenance and a validity interval covering the requested time. Weather requires a source and age under two hours. A supplies opening/walking data valid for the request.
- Monthly reports default to the previous complete Hong Kong calendar month. A declares activity coverage; missing/partial data is not zero activity. Code computes counts, minutes, and metres; the model cannot rewrite them.
- Landmark nicknames are candidates, not automatic live-map changes. A's backend performs leave/nickname writes.
- Confirmation cards expire after ten minutes. Editing invalidates the old card. Concurrent duplicate confirmation makes one write call. After timeout, reconcile the original operation rather than blindly retrying.

## Original references

- [Azure short-audio recognition](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/rest-speech-to-text-short)
- [Azure speech synthesis](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/rest-text-to-speech)
- [Azure language support](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support)
- [Qwen structured output](https://help.aliyun.com/en/model-studio/qwen-structured-output)
- [Apple AVAudioRecorder](https://developer.apple.com/documentation/avfaudio/avaudiorecorder)

This original client uploads a short recording after the user stops it, rather than continuous conversation. Its 30-second cap is below the short-audio REST limit cited by that delivery.
