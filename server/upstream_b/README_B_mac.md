# Mac / Xcode reference delivery

> Historical member B delivery. Paths and validation results below refer to the original ZIP layout, not the integrated repository. For the current StreetWalk server, use [server/README.md](../README.md).

Requires macOS 13+, Xcode 15+, and Python 3.12. Intel and Apple Silicon use native Python. The target is **My Mac**; this delivery does not migrate the real-time client to iPhone.

## Quick start

1. Extract the whole ZIP, preserving its directory structure. Install Python 3.12 from python.org or use `brew install python@3.12` if Homebrew is available.
2. Double-click `macOS/Setup.command` to install dependencies; the first run needs network access. If it is not executable, run `bash macOS/Setup.command` from the extracted root.
3. Open `macOS/VoiceAssistantMac.xcodeproj`, choose **VoiceAssistantMac → My Mac**, and press **⌘R**.
4. Wait for the local service to start. Configuration is loaded automatically. Start the Cantonese conversation and allow both macOS and page microphone permissions.

No repeated API-key entry or separate backend start is required. Local ad-hoc signing is the default; a developer Team is not required first. The Mac user must complete Xcode's installation/licensing prompts.

Alternatively, double-click `macOS/Run-in-Browser.command` to start the same backend in the system browser. Press Control-C in its terminal to stop it. Browser testing can help diagnose WebKit audio issues, but does not prove the native shell has passed acceptance.

## Preserved capabilities

- Doubao streaming ASR → Ark structured understanding → existing scope/business rules → Doubao Cantonese TTS.
- Continuous Cantonese conversation, interruption, text input, confirmation cards, and a ten-minute session limit.
- Observatory North District station readings/rainfall, Hong Kong-wide forecasts, and current warnings with the existing freshness checks.
- Xiaohe 2.0 female voice, speed, model, and resource settings exported from the then-running Windows service.
- Business operations remain demo data. Unconnected transport, accounts, and invitations do not become real through this migration.

The original delivery copied `backend/assistant/` and `windows/web/` byte-for-byte and recorded hashes in `CORE-SHA256.json`. That manifest describes the original package; later comment translations do not preserve those file hashes. The windows/web directory name is a source-layout convention, not a Windows-only restriction. This shell does not revert to the older iOS short-recording client.

## Configuration and files

At the user's explicit request, the original private ZIP included active provider configuration in `Private/voice-config.json`. This document does not reproduce credentials. The package was intended only for trusted recipients and was unsuitable for public GitHub upload; its .gitignore excluded Private and local runtime directories.

The configuration remains an external resource in the extracted source directory, not Swift source or the App Bundle. It is read at each launch. Page edits affect backend memory for that run; edit the JSON to persist a configuration change.

The page's clear-credentials action clears memory only. It does not delete the packaged JSON, which is loaded again on restart. Complete removal requires deleting the configuration file separately.

The SwiftUI/WKWebView app hosts the original page and launches Python from the project's .venv on an available 127.0.0.1 port. Closing the last window or quitting stops only the backend it created. Observatory links open in the system browser. Only the local page can request microphone access; camera access is denied.

This is a source-directory development delivery: **copying only the built .app is insufficient**. After moving the whole directory, rerun Setup and rebuild; virtual environments are not portable between paths. No notarized public .dmg or App Store package is included.

## Validation boundaries

The delivery environment was Windows without Xcode/macOS SDK. Existing backend/frontend tests and the new launcher covered HTTP startup, test configuration, and shutdown cleanup. These results do not establish Xcode compilation or Mac microphone behavior.

The original report records 19 matching core hashes, 79 backend tests passing, and existing UI-state/audio-resampling tests passing. The retained ios directory serves older structure tests; open the macOS project for this delivery.

Mac build:

```sh
xcodebuild -project macOS/VoiceAssistantMac.xcodeproj -scheme VoiceAssistantMac -configuration Debug -destination 'platform=macOS' build
```

Integrity and backend checks in the original package:

```sh
.venv/bin/python tools/verify_mac_delivery.py
.venv/bin/python tools/verify_backend.py
```

Manual trial: greet the assistant → ask today's North District weather → ask about tomorrow → interrupt its answer → test medical/investment refusals → close the window and confirm microphone release. Voice naturalness, speaker echo, and suitable pacing for older residents require actual-device evaluation.
