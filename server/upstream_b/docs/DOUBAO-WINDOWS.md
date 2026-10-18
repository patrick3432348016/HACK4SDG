# Doubao real-time Cantonese assistant — Windows integration

> Historical member B note, 12 October 2026 (Asia/Shanghai). A real ASR → Ark → TTS loop using synthesized input passed, and the user reported that conversation connected. Observatory weather was integrated. Older residents' speech, speaker echo, latency distributions, and iPhone integration still required separate acceptance. Use [the current server guide](../../README.md) for integrated StreetWalk.

## Selected design and scope

The original request was continuous Cantonese conversation for older users, limited to the walking app. Medication, investment, politics, sexual content, and unrelated topics receive bounded responses. Pairing was outside this module; a teammate would integrate A's app. This historical audience emphasis does not replace StreetWalk's current all-age resident scope.

The pipeline is ASR 2.0 bidirectional streaming → Ark structured routing → constrained business response → TTS 2.0 streaming. **It does not use Seeduplex 3.0 end-to-end speech**, and separate ASR/TTS Cantonese support is not evidence for Seeduplex. The modular design limits output before playback at the cost of fixed wording, no general chat, and latency across several stages.

Walking-related weather/transport were authorized. Weather covers North District observations/rainfall, Hong Kong-wide forecasts, and current warnings. Transport has no live feed and explicitly says so; it does not invent routes/timetables. Rankings/history are not fabricated. Invitations, meeting places, leave, nicknames, and reports use existing integration demo data; writes require a confirmation card and are labeled test actions.

## Required configuration

1. A Doubao voice API key with streaming ASR/TTS access, or the older App ID plus Access Token alternative.
2. A separate Ark key and enabled Doubao text model/endpoint supporting JSON output. Do not assume app login or the speech key grants model access.
3. A Cantonese-capable speaker ID from the console. Code sends explicit_dialect=yue; verify actual speaker support. Default resource is seed-tts-2.0; cloned voices may use seed-icl-2.0.
4. ASR defaults to volc.seedasr.sauc.duration. Use an enabled matching resource, not an end-to-end conversation resource.

Enter credentials into local password fields; do not paste them into chat or public GitHub. In this original page, Save to Local Service retains configuration **only in process memory**, restoring it on refresh/another browser on the same machine. Restart clears it. Unsaved edits disappear on refresh. The page does not write localStorage, cookies, or configuration files.

Original logs exclude credentials, recordings, transcripts, and raw upstream errors. Clear removes the page/service-memory configuration; other open pages need refreshing to discard their copies. This mechanism is for local integration, not shared/public deployment. The later private Mac package and integrated server have different configuration handling.

## Startup and use

On the original configured Windows machine, open windows/Start-Windows.cmd and browse http://127.0.0.1:8765 in Edge or Chrome.

On another machine, install Python 3.12 and run:

```sh
python -m pip install -r backend/requirements.txt -c backend/constraints.txt
```

Then run the startup script.

- Without APIs, Microphone Check tests permission/volume without uploading sound; Local Refusal Rules tests fixed rules. Neither proves recognition or model inference.
- With configuration, Start Cantonese Conversation captures continuously and responds after provider endpointing. Connected means the recognition channel opened, not that Ark/TTS permissions already passed.
- New recognized speech interrupts old playback/generation; a manual interrupt button is also available. Local volume changes alone do not cancel a pending answer. Isolate audio by turn_id and discard old packets.
- For slow speakers, endpoint waiting can be set to 1.8 or 2.5 seconds; actual behavior depends on provider/network.
- Backgrounding the page, ending, device loss, or connection failure stops capture. Sessions last at most ten minutes; reconnecting creates a new business session.
- Echo cancellation depends on browser/device. Start with headphones, then test speakers. Volume thresholds do not establish speaker identity.

The shell binds locally and does not provide public authentication or iPhone network access. Production integration needs HTTPS/WSS, authentication, server-held credentials, and A's business API.

## Response restrictions

1. Clear restricted keywords produce fixed refusals; explicit emergencies take priority.
2. Remaining input goes to Doubao for a bounded topic and Command JSON. Reject free-form answers, extra fields, or invalid structure.
3. Speak fixed Cantonese responses and validated official weather fields. Do not play arbitrary model text or user-supplied nickname/contact text; detailed business information stays on the confirmation card.
4. Business intents still pass parameter validation, candidate selection, confirmation, and idempotency checks. In this original Windows shell, saying confirm alone does not write.
5. Explain missing data. No fictional weather, automatic web search, Azure/Qwen fallback, or fake transcription.

Recognition, classification, and extraction can still be wrong. Bounded output is not proof of perfect classification. Emergency guidance does not call a service or replace it. Dynamic names/places are UI data, not unrestricted speech input in this version.

## Audio and conversation protocol

Input: 16 kHz mono PCM16 little-endian, in 200-ms / 6,400-byte chunks. AudioWorklet resamples continuously and sends binary WebSocket frames; it does not wait to upload a completed WAV.

The first /windows/realtime JSON message is {token, config}; fields follow assistant/doubao.py:DoubaoConfig. This is a local Windows configuration contract. Production clients should send authentication only.

Client messages after setup:

- PCM binary audio.
- {type: "text", text}, {type: "interrupt"}, or {type: "stop"}.
- {type: "action", kind: "choice", choice_kind: "contact" | "place", value}.
- {type: "action", kind: "confirm" | "cancel"}.

Server events: ready, transcript {text, final}, interrupted {turn_id}, thinking, answer {text, policy, business}, audio {turn_id, data, sample_rate: 24000}, answer_done, turn_error, and error. Audio data is base64 mono PCM16. On interruption, clear queued audio and discard older turn IDs. Trigger only on definite ASR segments; accumulated old sentences must not execute again.

Displayed latency measures **final transcript to first audio received**, excluding speech-end recognition/endpointing. Do not label it full end-to-end latency.

## Validation and device acceptance

```sh
python tools/verify_backend.py
node tools/test_capture.cjs
node tools/test_voice_ui.cjs
```

Checks cover binary ASR framing, truncated/oversized decompression rejection, final-sentence deduplication, sanitized provider errors, missing credentials/cross-origin rejection, refusal/emergency priority, prevention of model-text playback, confirmed writes, mock WebSocket flow, stale audio after interruption, and late microphone-permission cleanup. Synthetic fixtures/MockTransport do not establish real provider quality.

| Scenario | Acceptance |
|---|---|
| Hong Kong Cantonese, older speakers, slow speech/pauses | Understand intent without rushing; clarify incorrect names/times |
| Invite → clarify time → choose place → confirm | Complete flow with test writes only |
| Restricted/unrelated or disguised out-of-scope requests | Fixed scope response, never arbitrary generated speech |
| North District weather | Label station/time and forecast coverage; do not use current temperature for a future date; disclose stale/missing data |
| Transport | Clearly state missing data |
| Interruptions, rapid speech, network loss, backgrounding | No stale playback, duplicate action, or retained microphone |
| Five-minute conversation | No growing audio queue, repeated final sentence, or connection leak |
| First full turn | Verify ASR, Ark, TTS, and speaker permissions separately; measure actual latency |

## Sources consulted on 12 October 2026

- [Doubao streaming ASR protocol](https://docs.volcengine.com/docs/DoubaoVoice/LargemodelstreamingautomaticspeechrecognitionAPI?lang=zh)
- [Streaming TTS HTTP](https://docs.volcengine.com/docs/DoubaoVoice/unidirectional-streaming-text-to-speech-http?lang=zh)
- [Ark structured function calling](https://docs.volcengine.com/docs/ark/function-calling?lang=zh)
- [Older end-to-end speech API, not this pipeline](https://docs.volcengine.com/docs/DoubaoVoice/End-to-endreal-timespeechlargemodelAPIaccessdocument?lang=zh)
- [Seeduplex 3.0, not implemented here](https://docs.volcengine.com/docs/DoubaoVoice/access-mustread?lang=zh)

Old/new TTS documentation describes dialect voices differently. Validate the enabled resource and speaker; do not assume a Mandarin voice supports Cantonese.
