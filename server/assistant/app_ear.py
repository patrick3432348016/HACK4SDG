"""A, 2026-10-12: forward B's Doubao streaming recognition through the Mac server, keeping credentials off the phone.

/v1/voice/ear follows B's audio protocol in upstream_b/docs/DOUBAO-WINDOWS.md.
First phone message supplies an optional direct-LAN token and locale zh-HK, zh-CN or en-US.
  Added en-US on 10-17: Doubao enable_lid automatically recognizes Chinese, English and Cantonese; locale selects error-message language.
  Observed request.language / audio.language fields had no effect on the streaming API.
Then send 16 kHz mono PCM16 little-endian binary in 200 ms / 6400-byte chunks; a stop message ends capture.
Server emits ready, transcript text/final, then errors where applicable; final marks an ended utterance.
Unlike B's web conversation, completed text returns to the phone first for local commands such as finding, edits and reports.
Other requests use /v1/assistant/turn for understanding/weather/confirmation; output uses /v1/speech/synthesize with Xiaohe.
Reuse VoiceSession connection, authentication, errors, chunk-size/rate checks and ten-minute limit.
"""
import asyncio
from contextlib import suppress
import json

import httpx
from fastapi import WebSocket
from starlette.websockets import WebSocketDisconnect

from .doubao import Doubao, parse_asr
from .errors import AssistantError
from .realtime import VoiceSession

MAX_EARS = 4
# 10-18: reduce App utterance-end silence to Doubao's 0.8-second minimum; B's web configuration retains 1.2 seconds.
# AppStore+Conversation joins closely following fragments after pauses; explicit Done submits immediately.
EAR_END_WINDOW_MS = 800
LOCALES = {"zh-HK", "zh-CN", "en-US"}


def pick(locale, yue, cmn, en):
    """Select messages from the phone's locale because the App displays them directly."""
    return en if locale == "en-US" else cmn if locale == "zh-CN" else yue


def settle(final: str, partial: str) -> str:
    """Observed on 2026-10-12: enable_nonstream second-pass recognition could replace correct short streaming text with unrelated content.
    For short, almost entirely divergent final results, prefer the last streaming text; retain second pass for longer utterances."""
    p = "".join(c for c in partial if c.isalnum())
    f = "".join(c for c in final if c.isalnum())
    if len(p) < 2 or not f:
        return final
    overlap = len(set(p) & set(f)) / len(set(p))
    return partial if overlap < 0.34 else final


class EarSession(VoiceSession):
    """Capture-only VoiceSession sends transcripts but leaves responses to the phone."""

    async def read_asr(self, upstream):
        last = ""
        async for packet in upstream:
            partial, final, changed = self.tracker.feed(parse_asr(packet))
            if changed:
                last = partial
                await self.send("transcript", text=partial, final=False)
            if final.strip():
                await self.send("transcript", text=settle(final.strip(), last).strip(), final=True)
                last = ""


def add_ear_route(app, settings, lan_caller):
    @app.websocket("/v1/voice/ear")
    async def ear(socket: WebSocket):
        await socket.accept()
        counted = False
        locale = "zh-HK"  # Use hello.locale for subsequent directly displayed messages.
        try:
            if settings.doubao is None:
                raise AssistantError("EAR_NOT_CONFIGURED", "語音伺服器未設定豆包識別。 Voice server has no speech recognition set up.", 503)
            hello = json.loads(await asyncio.wait_for(socket.receive_text(), timeout=10))
            if not isinstance(hello, dict) or hello.get("locale", "zh-HK") not in LOCALES:
                raise ValueError()
            locale = hello.get("locale", "zh-HK")
            token = hello.get("token")
            if isinstance(token, str) and token and len(token) <= 4096:
                await app.state.business.identity(token)       # Verify through Supabase; reject self-declared identity.
            elif not (settings.speech_lan_open and lan_caller(socket)):
                raise AssistantError("UNAUTHORIZED", pick(locale, "請先登入。", "请先登录。", "Please sign in first."), 401)
            if getattr(app.state, "ear_connections", 0) >= MAX_EARS:
                raise AssistantError("BUSY", pick(locale, "太多人同時講緊，請稍後再試。", "太多人同时在说话，请稍后再试。",
                                                  "Too many people talking. Please try again soon."), 429)
            app.state.ear_connections = getattr(app.state, "ear_connections", 0) + 1
            counted = True
            async with httpx.AsyncClient(timeout=httpx.Timeout(25, connect=8), follow_redirects=False) as client:
                factory = getattr(app.state, "doubao_factory", Doubao)
                async with asyncio.timeout(600):
                    config = settings.doubao.model_copy(update={"end_window_ms": min(settings.doubao.end_window_ms, EAR_END_WINDOW_MS)})
                    await EarSession(socket, factory(config, client), None).run()
        except (ValueError, KeyError, TypeError):
            with suppress(Exception):
                await socket.send_json({"type": "error", "code": "INVALID_HELLO",
                                        "message": pick(locale, "連線資料唔啱。", "连接资料不对。", "Connection details are wrong.")})
        except WebSocketDisconnect:
            pass
        except AssistantError as exc:
            with suppress(Exception):
                await socket.send_json({"type": "error", "code": exc.code, "message": exc.message})
        except TimeoutError:
            with suppress(Exception):
                message = pick(locale, "講咗十分鐘，請再撳一次咪。", "说了十分钟，请再按一次麦克风。",
                               "That was 10 minutes. Tap Speak again.")
                await socket.send_json({"type": "error", "code": "SESSION_TIMEOUT", "message": message})
        except Exception:
            with suppress(Exception):
                await socket.send_json({"type": "error", "code": "EAR_FAILED", "message": pick(
                    locale, "豆包識別連唔到。", "连不上豆包识别。", "Can't reach speech recognition.")})
        finally:
            if counted:
                app.state.ear_connections -= 1
            with suppress(Exception):
                await socket.close()
