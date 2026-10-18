from collections import OrderedDict, deque
from contextlib import asynccontextmanager
import hashlib
import logging
import time
from uuid import uuid4
import httpx
from fastapi import FastAPI, Request, Depends, Path
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, Response, StreamingResponse
import ipaddress
from .business import Business
from .config import Settings
from .errors import AssistantError
from .models import TurnRequest, ChoiceRequest, SpeakRequest, Reply
from .providers import Providers
from .service import Assistant
from .store import Store
from .sovits import SovitsEngine, SpeechService, SynthesisFailed
from .supabase_business import SupabaseBusiness, UploadedContext
# A integration, 2026-10-12: B's Doubao ASR, policy/model/HKO understanding and Xiaohe synthesis.
from .app_ear import add_ear_route
from .app_policy import TurnPolicy
from .doubao import Doubao
from .doubao_speech import DoubaoEngine, doubao_voice_id

log = logging.getLogger("assistant")


def error_response(code, message, status, request_id=None):
    return JSONResponse({"error": {"code": code, "message": message, "request_id": request_id or uuid4().hex}}, status_code=status)


class BodyLimit:
    def __init__(self, app, limit):
        self.app, self.limit = app, limit

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        chunks, size = [], 0
        while True:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            size += len(message.get("body", b""))
            if size > self.limit:
                return await error_response("BODY_TOO_LARGE", "请求过大，请缩短录音或文字。", 413)(scope, receive, send)
            chunks.append(message)
            if not message.get("more_body"):
                break
        iterator = iter(chunks)

        async def replay():
            try:
                return next(iterator)
            except StopIteration:
                return await receive()
        await self.app(scope, replay, send)


class Limiter:
    """Single-process guard. A reverse proxy must enforce global limits in production."""
    def __init__(self, limit):
        self.limit, self.entries = limit, OrderedDict()

    def check(self, key):
        now = time.monotonic()
        bucket = self.entries.setdefault(key, deque())
        self.entries.move_to_end(key)
        while bucket and bucket[0] < now - 60:
            bucket.popleft()
        if len(bucket) >= self.limit:
            raise AssistantError("RATE_LIMITED", "请求过于频繁，请稍后重试。", 429)
        bucket.append(now)
        while len(self.entries) > 5000:
            self.entries.popitem(last=False)


def voice_id(settings):
    """Change voice ID after model/reference changes to invalidate App and server caches."""
    import os
    ref = os.path.basename(settings.sovits_ref_wav or "none")
    return f"sovits-v2ProPlus-{ref.rsplit('.', 1)[0]}-1"


def tts_text(text, locale):
    """10-18: correct Mandarin App-name pronunciation with a synthesis-only homophone; leave display text and Cantonese unchanged."""
    return text.replace("街坊行", "街坊形") if locale == "zh-CN" else text


def is_lan_caller(request):
    """Direct LAN/localhost synthesis may omit authentication when no tunnel/proxy is involved."""
    if any(h in request.headers for h in ("cf-connecting-ip", "x-forwarded-for", "forwarded", "x-real-ip", "cf-ray")):
        return False
    try:
        address = ipaddress.ip_address(request.client.host if request.client else "")
    except ValueError:
        return False
    return address.is_private or address.is_loopback or address.is_link_local


def create_app(settings=None, client=None, clock=None, speech=None):
    settings = settings or Settings.from_env()
    settings.validate()
    store = Store(settings.database)
    limiter = Limiter(settings.requests_per_minute)
    speech_limiter = Limiter(max(settings.requests_per_minute, 300))
    if speech is None and settings.tts == "sovits":
        speech = SpeechService(lambda: SovitsEngine(settings.sovits_root, settings.sovits_ref_wav, settings.sovits_ref_text,
                                                    settings.sovits_device),
                               settings.speech_cache_dir, voice_id(settings), log_text=settings.log_speech_text)
    elif speech is None and settings.tts == "doubao":
        speech = SpeechService(lambda: DoubaoEngine(settings.doubao), settings.speech_cache_dir, doubao_voice_id(settings.doubao),
                               log_text=settings.log_speech_text, locales=DoubaoEngine.locales, workers=3)

    @asynccontextmanager
    async def lifespan(app):
        vendor_client = client or httpx.AsyncClient(timeout=httpx.Timeout(25, connect=5), follow_redirects=False,
                                                  limits=httpx.Limits(max_connections=30, max_keepalive_connections=10))
        business = (SupabaseBusiness(settings, vendor_client, store, clock) if settings.mode == "supabase"
                    else Business(settings, vendor_client, store))
        providers = Providers(settings, vendor_client)
        app.state.speech = speech
        if speech is not None:
            speech.start(warm_text=None if settings.tts == "doubao" else "你好。")
        app.state.business, app.state.providers = business, providers
        app.state.assistant = Assistant(settings, store, business, providers, clock)
        # Use B's Doubao policy/HKO path when configured; otherwise retain Qwen or limited rules.
        app.state.policy = (TurnPolicy(settings, store, app.state.assistant, Doubao(settings.doubao, vendor_client))
                            if settings.doubao is not None else None)
        store.cleanup()
        app.state.last_cleanup = time.monotonic()
        yield
        if speech is not None:
            speech.stop()
        if client is None:
            await vendor_client.aclose()

    app = FastAPI(title="Hack4SDG Member B Assistant", version="1.0.0", lifespan=lifespan,
                  docs_url="/docs" if settings.mode == "demo" else None,
                  redoc_url=None, openapi_url="/openapi.json" if settings.mode == "demo" else None)
    app.add_middleware(BodyLimit, limit=settings.max_body_bytes)

    @app.middleware("http")
    async def envelope(request, call_next):
        request.state.request_id = uuid4().hex
        if settings.mode == "production" and request.url.scheme != "https" and request.url.path != "/healthz":
            return error_response("HTTPS_REQUIRED", "请使用 HTTPS 连接。", 400, request.state.request_id)
        start = time.monotonic()
        try:
            response = await call_next(request)
        except Exception:
            # Deliberately exclude request body, tokens and upstream exception strings.
            log.error("request_failed request_id=%s", request.state.request_id)
            response = error_response("INTERNAL_ERROR", "服务暂时无法处理请求，请稍后重试。", 500, request.state.request_id)
        response.headers["X-Request-ID"] = request.state.request_id
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Server-Timing"] = f"app;dur={(time.monotonic() - start) * 1000:.0f}"
        return response

    @app.exception_handler(AssistantError)
    async def assistant_error(request, exc):
        return error_response(exc.code, exc.message, exc.status, request.state.request_id)

    @app.exception_handler(RequestValidationError)
    async def validation_error(request, exc):
        return error_response("INVALID_REQUEST", "请求字段、语言或格式不正确。", 422, request.state.request_id)

    async def principal(request: Request):
        header = request.headers.get("authorization", "")
        scheme, _, token = header.partition(" ")
        if scheme.lower() != "bearer" or not token or len(token) > 4096:
            raise AssistantError("UNAUTHORIZED", "请先登录或配置联调令牌。", 401)
        # Limit before introspection to also protect A's authentication endpoint.
        limiter.check(hashlib.sha256(token.encode()).hexdigest())
        owner = await app.state.business.identity(token)
        if time.monotonic() - app.state.last_cleanup > 3600:
            store.cleanup()
            app.state.last_cleanup = time.monotonic()
        return owner, token

    @app.get("/healthz")
    async def health():
        return {"status": "ok"}

    @app.get("/v1/capabilities")
    async def capabilities(user=Depends(principal)):
        return {"mode": settings.mode, "speech": settings.speech_ready, "language_model": settings.model_ready,
                "interpretation": "qwen" if settings.model_ready else "limited_demo_rules",
                "business": "demo" if settings.mode == "demo" else "live", "max_audio_seconds": 30,
                "locales": ["zh-HK", "zh-CN", "en-US"], "tts": settings.tts}

    @app.post("/v1/speech/transcribe")
    async def transcribe(request: Request, locale: str = "zh-HK", user=Depends(principal)):
        if locale not in {"zh-HK", "zh-CN", "en-US"}:
            raise AssistantError("INVALID_LOCALE", "仅支持粤语、普通话或英文。", 422)
        if request.headers.get("content-type", "").split(";")[0].lower() != "audio/wav":
            raise AssistantError("INVALID_AUDIO", "请上传 WAV 音频。", 415)
        return await app.state.providers.transcribe(await request.body(), locale)

    async def speech_principal(request: Request):
        """Synthesis requires login except permitted direct LAN requests; tunnels always require authentication."""
        header = request.headers.get("authorization", "")
        scheme, _, token = header.partition(" ")
        if scheme.lower() == "bearer" and token and len(token) <= 4096:
            speech_limiter.check(hashlib.sha256(token.encode()).hexdigest())
            return await app.state.business.identity(token), token
        if settings.speech_lan_open and is_lan_caller(request):
            speech_limiter.check("lan:" + (request.client.host if request.client else ""))
            return ("lan", None)
        raise AssistantError("UNAUTHORIZED", "请先登录。", 401)

    @app.get("/v1/voice")
    async def voice_info():
        """Unauthenticated discovery/status endpoint contains no user data."""
        engine = app.state.speech
        return {"service": "jiefong-voice", "tts": settings.tts, "voice_id": engine.voice_id if engine else None,
                "status": engine.status if engine else ("ready" if settings.tts == "azure" else "off"),
                "locales": list(engine.locales) if engine else [], "assistant": settings.mode,
                "sample_rate": engine.sample_rate if engine else None,
                # A, 2026-10-12: ear advertises streaming recognition and brain identifies the understanding provider.
                "ear": settings.doubao is not None, "brain": "doubao" if settings.doubao is not None else (
                    "model" if settings.model_ready else "rules")}

    @app.post("/v1/speech/synthesize")
    async def synthesize(body: SpeakRequest, request: Request, user=Depends(speech_principal)):
        engine = app.state.speech
        text = tts_text(body.text, body.locale)
        if engine is None:
            if user[0] == "lan":
                raise AssistantError("UNAUTHORIZED", "请先登录。", 401)
            audio = await app.state.providers.speak(text, body.locale)
            return Response(audio, media_type="audio/mpeg")
        if body.locale not in engine.locales:
            raise AssistantError("TTS_LOCALE_UNSUPPORTED", "This voice can't speak this language yet." if body.locale == "en-US"
                                 else "本机声音暂时只有粤语；请用手机系统声音。", 503)
        if engine.status != "ready":
            raise AssistantError("TTS_NOT_READY", "声音模型仲未准备好。", 503)
        speed = body.speed or 1.0
        if body.prefetch:
            key, job = engine.enqueue(text, body.locale, speed, priority=1)
            return JSONResponse({"cached": job is None, "key": key}, status_code=200 if job is None else 202)
        hit, chunks = await engine.stream(text, body.locale, speed)
        try:
            first = await chunks.__anext__()
        except (SynthesisFailed, StopAsyncIteration):
            raise AssistantError("TTS_FAILED", "Couldn't make the voice. Using the phone voice." if body.locale == "en-US"
                                 else "合成唔到呢句，请用系统声音。", 503)

        async def body_iter():
            yield first
            async for part in chunks:
                yield part
        return StreamingResponse(body_iter(), media_type="audio/wav",
                                 headers={"X-Voice-ID": engine.voice_id, "X-TTS-Cache": "hit" if hit else "miss"})

    @app.post("/v1/assistant/context")
    async def upload_context(body: UploadedContext, user=Depends(principal)):
        """App uploads landmark names, walking minutes and shade, without coordinates, in Supabase mode only."""
        if settings.mode != "supabase":
            raise AssistantError("NOT_SUPPORTED", "测试模式使用虚构地点。", 409)
        return {"version": app.state.business.save_context(user[0], body)}

    # Business API required by B, implemented here for Supabase and future HTTP production integration.

    def business_api():
        if settings.mode != "supabase":
            raise AssistantError("NOT_SUPPORTED", "只有 supabase 模式提供业务接口。", 404)
        return app.state.business

    @app.get("/assistant/session")
    async def a_session(user=Depends(principal)):
        business_api()
        return {"user_id": user[0]}

    @app.get("/assistant/context")
    async def a_context(at: str | None = None, user=Depends(principal)):
        business = business_api()
        from datetime import datetime
        try:
            when = datetime.fromisoformat(at) if at else None
        except ValueError:
            raise AssistantError("INVALID_REQUEST", "时间格式不正确。", 422)
        if when is not None and when.utcoffset() is None:
            raise AssistantError("INVALID_REQUEST", "时间要带时区。", 422)
        context = await business.context(user[1], business.clock(), when)
        return context.model_dump(mode="json")

    @app.post("/assistant/actions")
    async def a_actions(request: Request, user=Depends(principal)):
        business = business_api()
        try:
            body = await request.json()
        except ValueError:
            raise AssistantError("INVALID_REQUEST", "请求格式不正确。", 422)
        key = request.headers.get("idempotency-key", "")
        if not isinstance(body, dict) or not key or body.get("operation_id") != key or not isinstance(body.get("action"), dict):
            raise AssistantError("INVALID_REQUEST", "需要 Idempotency-Key，且与 operation_id 相同。", 422)
        result = await business.execute(user[1], user[0], key, {"action": body["action"],
                                                                "expected_context_version": body.get("expected_context_version")})
        return result.model_dump()

    @app.get("/assistant/actions/{operation_id}")
    async def a_action(operation_id: str = Path(pattern=r"^[A-Za-z0-9_-]{1,100}$"), user=Depends(principal)):
        result = await business_api().reconcile(user[1], user[0], operation_id)
        return result.model_dump()

    @app.post("/v1/assistant/turn", response_model=Reply)
    async def turn(body: TurnRequest, user=Depends(principal)):
        if app.state.policy is not None:
            return await app.state.policy.turn(*user, body)
        return await app.state.assistant.turn(*user, body)

    @app.post("/v1/conversations/{conversation_id}/choice", response_model=Reply)
    async def choice(body: ChoiceRequest, conversation_id: str = Path(pattern=r"^[a-f0-9]{32}$"), user=Depends(principal)):
        return await app.state.assistant.choose(*user, conversation_id, body)

    @app.post("/v1/drafts/{draft_id}/confirm", response_model=Reply)
    async def confirm(draft_id: str = Path(pattern=r"^[a-f0-9]{32}$"), user=Depends(principal)):
        return await app.state.assistant.confirm(*user, draft_id)

    @app.post("/v1/drafts/{draft_id}/cancel", response_model=Reply)
    async def cancel(draft_id: str = Path(pattern=r"^[a-f0-9]{32}$"), user=Depends(principal)):
        store.cancel(draft_id, user[0])
        return app.state.assistant.draft_reply(user[0], draft_id)

    @app.post("/v1/drafts/{draft_id}/reconcile", response_model=Reply)
    async def reconcile(draft_id: str = Path(pattern=r"^[a-f0-9]{32}$"), user=Depends(principal)):
        draft = store.draft(draft_id, user[0])
        if draft["status"] in {"executing", "uncertain"}:
            return await app.state.assistant.confirm(*user, draft_id)
        return app.state.assistant.draft_reply(user[0], draft_id)

    add_ear_route(app, settings, is_lan_caller)
    return app
