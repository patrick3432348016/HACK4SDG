"""Loopback-only Windows test surface. Keys and audio are never persisted here."""
from dataclasses import replace
from pathlib import Path
import re
import secrets
import tempfile

from fastapi import Request
from fastapi.responses import FileResponse, JSONResponse
from starlette.middleware.trustedhost import TrustedHostMiddleware
from .app import create_app, error_response
from .config import Settings
from .errors import AssistantError
from .providers import Providers
from .doubao import DoubaoConfig
from .realtime import add_realtime_route
from .voice_policy import local_decision

# 成员 A 改：仓库入面网页放 server/windows/web（B 原本系 backend/../windows/web）。
WEB = Path(__file__).resolve().parents[1] / "windows" / "web"


def create_windows_app(settings=None, client=None):
    # Explicitly isolate this tester from environment credentials and production data.
    temporary = tempfile.TemporaryDirectory(prefix="hack4sdg-voice-")
    settings = settings or Settings(database=str(Path(temporary.name) / "test.sqlite3"),
                                    demo_token=secrets.token_urlsafe(32))
    if settings.mode != "demo":
        raise ValueError("Windows tester is demo-only")
    app = create_app(settings, client=client)
    app.state.temporary = temporary
    app.state.voice_config = None  # Memory only; shared by local browser windows until service exit.
    add_realtime_route(app, settings)
    app.add_middleware(TrustedHostMiddleware, allowed_hosts=["127.0.0.1", "localhost", "[::1]"])

    @app.middleware("http")
    async def local_only(request, call_next):
        if request.client and request.client.host not in {"127.0.0.1", "::1", "testclient"}:
            return error_response("LOCAL_ONLY", "此测试工具只允许本机访问。", 403)
        origin = request.headers.get("origin")
        if origin and origin != str(request.base_url).rstrip("/"):
            return error_response("ORIGIN_REJECTED", "请从本机测试页面操作。", 403)
        response = await call_next(request)
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; script-src 'self'; style-src 'self'; "
            "connect-src 'self'; media-src 'self' blob:; img-src 'self' data:; "
            "frame-ancestors 'none'; base-uri 'none'; form-action 'none'")
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Permissions-Policy"] = "microphone=(self), camera=()"
        response.headers["Cache-Control"] = "no-store"
        return response

    @app.get("/")
    async def index():
        return FileResponse(WEB / "index.html")

    @app.get("/app.js")
    async def javascript():
        return FileResponse(WEB / "app.js", media_type="text/javascript")

    @app.get("/capture.js")
    async def capture_worklet():
        return FileResponse(WEB / "capture.js", media_type="text/javascript")

    @app.get("/style.css")
    async def stylesheet():
        return FileResponse(WEB / "style.css", media_type="text/css")

    @app.get("/windows/session")
    async def session():
        return JSONResponse({"application": "hack4sdg-windows-voice", "token": settings.demo_token})

    @app.api_route("/windows/config", methods=["GET", "POST", "DELETE"])
    async def voice_config(request: Request):
        if not secrets.compare_digest(request.headers.get("authorization", ""), "Bearer " + settings.demo_token):
            raise AssistantError("UNAUTHORIZED", "请刷新页面。", 401)
        if request.method == "DELETE":
            app.state.voice_config = None
            return {"saved": False}
        if request.method == "POST":
            raw = bytearray()
            async for chunk in request.stream():
                raw.extend(chunk)
                if len(raw) > 12000:
                    raise AssistantError("INVALID_CONFIG", "配置过长。", 422)
            try:
                parsed = DoubaoConfig.model_validate_json(bytes(raw))
            except ValueError:
                raise AssistantError("INVALID_CONFIG", "配置不完整或格式错误，未保存。", 422) from None
            app.state.voice_config = parsed
            return {"saved": True}
        saved = app.state.voice_config
        if saved is None:
            return {"config": None}
        values = saved.model_dump(mode="json")
        for name in ("speech_key", "access_key", "ark_key"):
            values[name] = getattr(saved, name).get_secret_value()
        return {"config": values}

    @app.post("/windows/policy-check")
    async def policy_check(request: Request):
        if not secrets.compare_digest(request.headers.get("authorization", ""), "Bearer " + settings.demo_token):
            raise AssistantError("UNAUTHORIZED", "请刷新页面。", 401)
        try:
            body = await request.json()
            text = body.get("text")
            if not isinstance(text, str) or not 1 <= len(text) <= 2000:
                raise ValueError()
        except (ValueError, AttributeError):
            raise AssistantError("INVALID_TEXT", "请提供短文本。", 422) from None
        decision = local_decision(text)
        kind = decision.topic if decision else "requires_model"
        return {"mode": "offline_rules_only", "decision": kind, "label": {
            "deny": "固定拒答", "emergency": "固定求助提示", "requires_model": "未命中本地规则；仍需豆包判断"}[kind]}

    @app.post("/windows/transcribe")
    async def transcribe(request: Request, locale: str = "zh-HK"):
        if not secrets.compare_digest(request.headers.get("authorization", ""), "Bearer " + settings.demo_token):
            raise AssistantError("UNAUTHORIZED", "请刷新测试页面。", 401)
        if locale not in {"zh-HK", "zh-CN"}:
            raise AssistantError("INVALID_LOCALE", "请选择粤语或普通话。", 422)
        if request.headers.get("content-type") != "audio/wav":
            raise AssistantError("INVALID_AUDIO", "请上传 WAV 音频。", 415)
        region = request.headers.get("x-speech-region", "").strip().lower()
        key = request.headers.get("x-speech-key", "").strip()
        if not re.fullmatch(r"[a-z][a-z0-9]{1,40}", region) or not key or len(key) > 256:
            raise AssistantError("INVALID_CONFIG", "请填写 Azure Speech Key 和 Region，例如 eastasia。", 422)
        # Region is a single DNS label, never a caller-controlled URL/host.
        configured = replace(settings, azure_key=key,
            azure_stt_url=f"https://{region}.stt.speech.microsoft.com/speech/recognition/conversation/cognitiveservices/v1")
        provider = Providers(configured, app.state.providers.client)
        try:
            return await provider.transcribe(await request.body(), locale)
        except AssistantError as exc:
            if exc.code == "PROVIDER_REJECTED":
                raise AssistantError(exc.code, "Azure 拒绝请求：请核对 Speech Key、资源 Region、额度和网络访问设置。", exc.status) from None
            raise

    return app
