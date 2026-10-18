# StreetWalk · Mac voice server

The integrated app has used **member B's Doubao/Volcengine stack since 12 October 2026**: streaming recognition, model-based understanding, and Xiaohe speech. GPT-SoVITS remains an optional local speech path.

## Three languages

English support was added on 17 October. The app sends `"locale": "en-US"` in the initial `/v1/voice/ear` message, assistant turns, and speech requests. No separate server startup setting is required.

Doubao streaming recognition distinguishes Cantonese, Mandarin, and English. All three use B's policy routing, including invitations with minutes/duration, Observatory weather, leave, emergency guidance, and refusal of medication advice. English speech uses Xiaohe with `explicit_language=en`; Chinese names can remain in the spoken text. An optional `speaker_en` setting selects another English voice.

`server/tests/live_three_lang.py` exercises real provider calls and writes samples to `docs/voice_samples/three_lang/`. It is not an offline test; run it only with authorization for provider usage.

| Component | Responsibility | Implementation |
|---|---|---|
| Recognition | Stream phone microphone audio through the Mac to Doubao; finalize text after the user finishes | B's `doubao.py`/`realtime.py`, A's `app_ear.py` and `/v1/voice/ear` |
| Understanding | Scope rules, model topic/command routing, North District weather, and invitation confirmation | B's `voice_policy.py`, `weather.py`, `service.py`; A's `app_policy.py` and `/v1/assistant/turn` |
| Speech | Xiaohe output with server/phone caching; earlier Mac measurements found about 0.7 seconds to the first chunk | `doubao_speech.py` through `SpeechService` |

Continuous conversation is in `ios/StreetWalk/Store/AppStore+Conversation.swift`: tap the microphone once, speak without pressing a finish button, and interrupt speech by speaking. The phone first handles supported local commands such as finding, rescheduling, cancellation, reports, and landmark renaming; remaining requests go to the server. Actions affecting other people still require confirmation.

When the Mac is unavailable, Apple recognition, `TemplateAI`, and system speech provide fallback. This does **not** guarantee equivalent understanding of arbitrary natural-language requests.

## Configuration handling

The private repository contains B's provider configuration at `server/private/doubao.json`, following the user's 12 October decision for internal team testing. **Keep the repository private and do not expose provider credentials.** They are not sent to the phone. An external `~/Desktop/HACK/voice-runtime/doubao.json` takes precedence.

## First run on a teammate's Mac

```sh
git clone --branch main https://github.com/patrick3432348016/HACK4SDG.git
cd HACK4SDG
tools/voice_server.sh
```

The script creates a Python environment on first use, taking about a minute with Python 3.10+ or uv available. Later starts do not load a local model for Doubao. Connect the phone and Mac to the same Wi-Fi for Bonjour discovery. See [iPhone installation](../ios/DEVICE_INSTALL.md).

## Starting a test session

```sh
cd ~/Desktop/HACK/HACK4SDG
tools/voice_server.sh                 # Local-network discovery
tools/voice_server.sh --tunnel        # HTTPS tunnel; requires cloudflared
tools/voice_server.sh --voice=sovits   # Optional older local GPT-SoVITS voice
```

- The terminal prints the LAN address. If discovery fails, enter it under App Settings → Voice → Voice Server.
- Keep the Mac awake with its lid open. Tunnel requests for recognition, speech, and assistant actions require app authentication.
- `--verbose` includes synthesized sentences in logs. Treat those logs as potentially containing personal data.
- `--test` runs server tests; Ctrl-C stops the service. Older notes mention 60 and 107 tests; these are historical counts, not current acceptance results.
- Simulator conversation input without speaking: launch with `-debugCommands -earFeed a.wav,b.wav [-earGap seconds]`, using 16 kHz mono WAV, then write `mic` to `Documents/debug-commands.txt`.

### Team measurements on one Mac — 12 October 2026

| Stage | Reported latency |
|---|---|
| End of speech to final transcript | About 1.2–1.6 s; Doubao endpointing pause about 1.2 s |
| Model understanding | About 3–4 s, occasionally over 12 s; app falls back after 12 s |
| Weather, including Observatory fetch | About 3.5–4 s |
| First speech chunk | About 0.6–1 s; cached phrases start immediately |

These are dated observations, not guarantees. Doubao's second-pass recognition can hallucinate on very short utterances. `app_ear.settle()` prefers the streaming transcript when the final transcript disagrees substantially.

## Optional legacy path: local GPT-SoVITS

Use only with `--voice=sovits`. Keep models (about 1.4 GB) and the Python environment (about 1.1 GB) outside Git under `~/Desktop/HACK/voice-runtime/`, or override with `VOICE_RUNTIME`.

```text
voice-runtime/
  gptsovits/                 GPT-SoVITS at commit 1b47ca0, with pretrained_models
  ref/cv_yue_f2.wav + .txt   CC0 Common Voice Cantonese reference and transcript
  venv/                      Python 3.10 environment created by uv
  requirements.lock.txt      Exact installed versions
  nltk_data/                 English dictionaries/taggers for mixed-language text
  data/                      assistant.sqlite3 and cached synthesized WAV files
```

The original runtime was copied from a temporary scratchpad on 11 October because temporary directories may be cleared at restart. Required pretrained assets include `s1v3.ckpt`, `v2Pro/s2Gv2ProPlus.pth`, `chinese-roberta-wwm-ext-large`, `chinese-hubert-base`, `sv/pretrained_eres2netv2w24s4ep4.ckpt`, and `fast_langdetect`. The recorded lock included torch 2.6.0, transformers 4.57.6, and fastapi 0.143.0.

```sh
RT=~/Desktop/HACK/voice-runtime
git clone https://github.com/RVC-Boss/GPT-SoVITS "$RT/gptsovits"
git -C "$RT/gptsovits" checkout 1b47ca0
# Download the listed v2ProPlus pretrained assets according to the upstream README.
uv venv --python 3.10 "$RT/venv"
uv pip install --python "$RT/venv/bin/python" -r "$RT/requirements.lock.txt"
# Download NLTK assets directly if its downloader fails behind a proxy.
mkdir -p "$RT/nltk_data/corpora" "$RT/nltk_data/taggers"
curl -L -o "$RT/nltk_data/corpora/cmudict.zip" https://raw.githubusercontent.com/nltk/nltk_data/gh-pages/packages/corpora/cmudict.zip
curl -L -o "$RT/nltk_data/taggers/averaged_perceptron_tagger_eng.zip" https://raw.githubusercontent.com/nltk/nltk_data/gh-pages/packages/taggers/averaged_perceptron_tagger_eng.zip
(cd "$RT/nltk_data/corpora" && unzip -o cmudict.zip)
(cd "$RT/nltk_data/taggers" && unzip -o averaged_perceptron_tagger_eng.zip)
# Convert CC0 common_voice_yue_31206624.mp3 to ref/cv_yue_f2.wav;
# place its original Cantonese transcript in ref/cv_yue_f2.txt.
```

The lockfile and reference assets must be supplied from the runtime; this repository does not bundle them.

### Legacy GPT-SoVITS measurements — 11 October 2026

M1 Pro, CPU, with other simulators and Unity running and reported system load 15–20:

| Condition | First audio | Notes |
|---|---|---|
| New streamed synthesis | 2.2–3.6 s | Approximately real-time synthesis thereafter |
| Server-cached phrase | 0.03 s | App prewarms common phrases on connection |
| Phone-cached phrase | Immediate | Available offline |
| Mac unavailable | Immediate system-voice fallback | |
| No audio for more than 6 s | System voice after 6 s | |
| Model loading | About 17 s | |

## Interfaces

B's inherited endpoints are documented in [INTEGRATION.md](upstream_b/docs/INTEGRATION.md): `/healthz`, `/v1/capabilities`, `/v1/speech/transcribe` (legacy Azure path), `/v1/speech/synthesize`, `/v1/assistant/turn`, `/v1/conversations/{id}/choice`, and `/v1/drafts/{id}/confirm|cancel|reconcile`.

A's additions:

| Method/path | Purpose |
|---|---|
| `GET /v1/voice` | Unauthenticated discovery metadata: voice version, model status, and assistant mode; no user data |
| `POST /v1/speech/synthesize` | Adds `speed` (0.7–1.3) and `prefetch`. SoVITS streams PCM16 32 kHz mono WAV with length 0xFFFFFFFF and `X-TTS-Cache: hit/miss`; its Mandarin path returns 503 for app fallback. |
| `POST /v1/assistant/context` | Upload landmarks, walking minutes, and half-hour shade samples for the next three days, **without coordinates**. Extra fields return 422. |
| `GET /assistant/session`, `GET /assistant/context?at=`, `POST /assistant/actions`, `GET /assistant/actions/{id}` | B's required business API, implemented against Supabase by `supabase_business.py`; actions carry `Idempotency-Key`. |

### Authentication, confirmation, and privacy

- In `ASSISTANT_MODE=supabase`, use the app's anonymous Supabase access token. The server validates it through `GET /auth/v1/user`, caching verification for 60 seconds. It does not accept a client-asserted user ID. Business requests use that user's token so RLS remains authoritative.
- Speech requests from a direct private LAN address without proxy headers may be unauthenticated for demos/simulators. Tunnel/proxy requests require authentication.
- Invitations use `meetups.id = uuid5(user, draft ID)`; repeat confirmation of the same draft maps to one row. B's SQLite `business_receipts` stores receipts.
- An uncertain result permits only reconciliation of the original ID. The app must not blindly repeat the write.
- Leave upserts `leaves`; nickname changes update `profiles.nickname` with a 1–20-character limit.
- Assistant context contains landmark names, walking minutes, and shade fractions, not coordinates/home location. This statement is limited to that endpoint: the app's agreed live-finding channel separately carries precise coordinates.
- LAN HTTP carries bearer tokens without transport encryption. Use a trusted LAN; use the HTTPS tunnel for external testing.
- Audio is forwarded to Doubao. A complete privacy notice must include actual logging and retention behavior; inherited deployment notes do not prove the current configuration.

### Legacy Qwen configuration

Earlier integration notes used limited rules when no Qwen key was configured. The current default uses B's Doubao Ark model; it is not accurately described as an unconnected model stub.

For the optional Qwen path, configure the matching account endpoint/model through the process environment:

```sh
export QWEN_API_KEY=... QWEN_BASE_URL=https://dashscope.aliyuncs.com/compatible-mode/v1 QWEN_MODEL=qwen-plus
tools/voice_server.sh
```

Model interpretation still passes through the same confirmation cards and validation.

## Validation

```sh
tools/voice_server.sh --test
(cd server && python3 -m unittest discover -s tests -p 'test_*.py')
~/Desktop/HACK/voice-runtime/venv/bin/python server/tools/verify_backend.py
python3 server/tools/tts_probe.py "一句粤语"
```

The final quoted phrase is an intentionally preserved Cantonese speech sample (“a Cantonese sentence”). The probe requires a running server, measures time to first audio, and saves a WAV.

A Windows review of the pre-translation main source ran 114 tests: 110 passed, three failed, and one errored, all involving unsupported `%-d` date formatting. This documentation work does not fix that issue or establish iOS/Mac acceptance. Live provider/backend tests must be reported separately.

## Changes to B's original delivery

Earlier integration copied B's files into `server/assistant/`. The following changes were additions for A's app:

- `config.py`: Supabase mode and `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `TTS_PROVIDER`, `SOVITS_*`, `SPEECH_CACHE_DIR`, `SPEECH_LAN_OPEN`, and `VOICE_LOG_TEXT`.
- `providers.py`: permit limited fallback rules in Supabase mode without Qwen; production mode still rejects incomplete configuration. Add Traditional-Chinese minute forms, Chinese-number minutes, and nickname-change phrasing.
- `models.py`: add `SpeakRequest.speed` and `prefetch`.
- `service.py`: add structured `data.action` to confirmation replies so the app does not infer actions from message text.
- `app.py`: select `Business`/`SupabaseBusiness`, add discovery/context/business endpoints, and stream SoVITS WAV output.
- New files: `sovits.py`, `supabase_business.py`, their tests, and `tools/tts_probe.py`.
- The app uses its own voice-card UI rather than B's `AssistantPanel`/`AudioController`. Client/model/view-model rules were adapted into `ios/StreetWalk/Assistant/`. Legacy Azure transcription is not the current streaming recognition path.

### Doubao integration — 12 October

- Copy B's `doubao.py`, `realtime.py`, `voice_policy.py`, `weather.py`, `windows.py`, and tests; adjust the Windows page path to `server/windows/web/`. Reference docs, Mac shell, and tools remain in `upstream_b/`; their original `backend/` layout is not the integrated layout.
- B targets Python 3.12; the shared SoVITS runtime uses 3.10. `compat.py`, loaded first by `__init__.py`, supplies `asyncio.timeout` and consistent `TimeoutError`. Start with `python -m assistant.serve` so patches load before uvicorn/websockets.
- Configure `DOUBAO_CONFIG` and `TTS_PROVIDER=doubao`. Without a separate Qwen configuration, use B's Ark model with thinking disabled.
- `SpeechService` supports concurrent synthesis and language-specific output, including Doubao Mandarin.
- B's `/windows/realtime` is limited to the local web UI. The app uses `/v1/voice/ear` for recognition and routes the text itself, then uses `/v1/assistant/turn` through `app_policy.TurnPolicy`.
- Routing order follows B: local rules → Doubao routing → weather/fixed responses/app actions. The app renders its own localized cards instead of speaking integration-only test wording.
- Board/history replies direct users to the corresponding app screens instead of falsely saying these features are unconnected.
