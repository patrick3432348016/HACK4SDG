"""成员 A 加（2026-10-12）：App 嘅「耳仔」—— B 嘅豆包流式识别，经 Mac 服务器转发（密钥唔使去手机）。

WebSocket /v1/voice/ear，协议沿用 B（upstream_b/docs/DOUBAO-WINDOWS.md「音频与对话协议」）嘅收音部分：
- 手机第一条：{"token": Supabase access token（局域网直连可以冇）, "locale": "zh-HK"|"zh-CN"|"en-US"}
  （10-17 加 en-US：豆包流式识别本身中英粤自动分辨（enable_lid），请求唔使改；locale 只决定错误讯息用边种语言。
  实测 request.language / audio.language 喺流式接口冇作用。）
- 之后：16 kHz 单声道 PCM16 小端二进制，每段 200 ms（6400 字节）；{"type":"stop"} 结束。
- 服务器：ready → transcript {text, final}（final = 豆包判定一句讲完）→ error。
同 B 唯一唔同：一句讲完唔会由服务器自己答，而系交返手机——手机先睇系咪 App 自己做嘅指令（找人、改约、反映…），
唔系先交 /v1/assistant/turn（B 嗰套理解、天气、确认卡）。播报由手机经 /v1/speech/synthesize（同一把小何声）。
连接、确认、错误讯息、每段大小同速度检查、十分钟上限全部用 B 嘅 VoiceSession。
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
# 10-18 真机：讲完要等好耐先出字。App 耳仔讲完停 0.8 秒就算一句（豆包最短；doubao.json 嘅 1.2 秒留俾 B 嘅网页）；
# 讲到一半停耐咗，手机会将紧接嘅下半句串返埋（AppStore+Conversation），仲有「说完了」掣即刻交。
EAR_END_WINDOW_MS = 800
LOCALES = {"zh-HK", "zh-CN", "en-US"}


def pick(locale, yue, cmn, en):
    """按手机揀嘅语言揀讯息（手机直接显示）。"""
    return en if locale == "en-US" else cmn if locale == "zh-CN" else yue


def settle(final: str, partial: str) -> str:
    """豆包「二遍识别」（enable_nonstream）对好短嘅句子会乱认（2026-10-12 实测：「咁聽日呢」→「帮我导航到大沥公园」），
    但边讲边出嘅字系啱嘅。二遍结果同最后一次边讲边出嘅字差唔多冇一个字一样，就信边讲边出嘅字；长句照用二遍（通常更准）。"""
    p = "".join(c for c in partial if c.isalnum())
    f = "".join(c for c in final if c.isalnum())
    if len(p) < 2 or not f:
        return final
    overlap = len(set(p) & set(f)) / len(set(p))
    return partial if overlap < 0.34 else final


class EarSession(VoiceSession):
    """B 嘅 VoiceSession，只收音：一句讲完照送 transcript，但唔自己答（交返手机）。"""

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
        locale = "zh-HK"  # 手机揀嘅语言（hello.locale）：之后嘅讯息用呢种语言（手机直接显示）
        try:
            if settings.doubao is None:
                raise AssistantError("EAR_NOT_CONFIGURED", "語音伺服器未設定豆包識別。 Voice server has no speech recognition set up.", 503)
            hello = json.loads(await asyncio.wait_for(socket.receive_text(), timeout=10))
            if not isinstance(hello, dict) or hello.get("locale", "zh-HK") not in LOCALES:
                raise ValueError()
            locale = hello.get("locale", "zh-HK")
            token = hello.get("token")
            if isinstance(token, str) and token and len(token) <= 4096:
                await app.state.business.identity(token)       # Supabase 核实，唔收自报身份
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
