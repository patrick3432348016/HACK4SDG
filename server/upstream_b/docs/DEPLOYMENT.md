# Configuration and deployment

> Historical standalone member B deployment guide. Paths, providers, and retention statements describe that version. The integrated Doubao server has additional behavior; consult [the current guide](../../README.md) and verify the actual deployment.

## Integrate locally before enabling real APIs

Without environment variables, ASSISTANT_MODE=demo uses limited text rules and local test business data. Complete Azure/Qwen configuration can enable real providers in demo mode while business data remains fictional. Display these capabilities separately; provider access does not make the whole demo production-validated.

| Variable | Meaning |
|---|---|
| `ASSISTANT_MODE` | demo or production |
| `ASSISTANT_DATABASE` | SQLite path; default data/assistant.sqlite3 |
| `DEMO_TOKEN` | Local integration token; the default is unsuitable for public service |
| `AZURE_SPEECH_KEY` | Server-only Speech key |
| `AZURE_STT_URL` | Complete HTTPS recognition URL; code appends the language parameter |
| `AZURE_TTS_URL` | Complete HTTPS synthesis URL |
| `QWEN_API_KEY` | Server-only model key |
| `QWEN_BASE_URL` | Region-matched compatible API root without /chat/completions |
| `QWEN_MODEL` | Available text-model ID supporting JSON Object output |
| `BUSINESS_BASE_URL` | A's HTTPS business API root; see INTEGRATION.md |

Endpoints must use HTTPS and cannot contain URL credentials, query strings, or fragments. The service does not guess account regions or model names. Verify actual model, voice, and quota availability with the configured account.

Azure input is 16 kHz mono PCM16 WAV, capped at 30 seconds; transcription is not streamed. Original voices are zh-HK-HiuMaanNeural and zh-CN-XiaoxiaoNeural, subject to resource availability. Escape text before constructing SSML so input cannot become markup.

Qwen uses response_format=json_object, followed by strict field/type and business-data validation. Valid JSON does not prove correct intent. Untrusted text cannot rewrite system instructions or execute database operations.

## Startup

Native Python does not automatically load .env. Supply variables through the process environment or a secret manager; Docker Compose reads backend/.env.

```sh
cd backend
cp .env.example .env
# Keep demo mode for initial text integration; real keys are optional.
docker compose up --build -d
docker compose logs --tail=50
```

Compose binds only 127.0.0.1:8000; external access requires a TLS reverse proxy. Docker Desktop was unavailable in the original delivery environment, so this build path was unverified. Local Python startup and HTTP smoke testing were reported as passing.

Use **one Uvicorn worker, one service instance**, and persistent storage. SQLite transactions protect confirmation claims; the in-memory rate limiter is not distributed. Before scaling, migrate session/draft storage and shared rate limiting instead of adding independent replicas.

## Public ingress requirements

- Valid HTTPS domain/certificate. Production rejects plaintext business requests; /healthz is only an internal liveness check.
- Enforce a 2 MB body limit, read timeouts, connection limits, and global per-source/per-user rate limits at the proxy. The app's default 60 requests/minute per token is a second layer, not protection against rotating invalid tokens.
- Trust forwarding headers only from the actual proxy. Configure FORWARDED_ALLOW_IPS for its real address, never * for untrusted public sources. Container proxies are not necessarily 127.0.0.1.
- Do not expose the Uvicorn port publicly. Exclude Authorization, audio, user text, and complete business responses from access logs. Example startup disables access logs; application errors record only request_id in this version.
- Do not enable unrestricted CORS. Native apps do not need it; future web clients require explicit allowed origins.
- Check /healthz, authenticated /v1/capabilities, and complete business flows after deployment. Liveness alone says nothing about providers, data quality, authorization, or successful operations.

## Retention and recovery in the original version

- Raw server audio is processed in memory. The original version does not store transcript history or complete conversations in its database; verify the integrated server's separate logging behavior before making that claim.
- Structured conversations contain intent/names, expire after 24 idle hours, and are cleaned hourly or at restart.
- Confirmation actions/status/receipts are retained for 30 days. executing/uncertain actions remain until authoritative reconciliation to prevent duplicate writes. Assign an operator to resolve them.
- SQLite volumes and backups contain user data; use restricted access and encrypted storage. Establish backup/deletion procedures. Reconcile unresolved operations before handling deletion; do not claim deletion without business consequences while outcomes remain unknown.
- iOS recordings use the app temporary directory and are removed on completion/cancellation. Abnormal termination may leave files; clean this module's expired recordings before the next recording.
- The integration shell stores tokens in Keychain; the production app should use A's authentication storage. UserDefaults stores only pending operation IDs, never tokens.

## Required release acceptance after provider enablement

1. Real Cantonese/Mandarin speech covering names, accents, noise, date changes, and recognition failures; measure intent/field accuracy and latency.
2. Device permission denial, recording interruption, automatic stop, voice language, background cancellation, and recovery after termination.
3. A's authentication, user isolation, data validity windows, write deduplication, timeout reconciliation, and version conflicts.
4. Compare identical meeting-place candidates against a walking-time-only baseline. A must independently validate shade; sorting tests do not validate a 3D model.
5. Container build, TLS proxy, persistent-volume restart, backup recovery, and ingress rate limits.

Until these pass, do not present source delivery, demo mode, or MockTransport tests as a verified production deployment.
