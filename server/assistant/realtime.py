"""Loopback WebSocket session, real audio streaming and cancellation by turn ID."""
import asyncio
import base64
from contextlib import suppress
import json
import secrets
import socket as network_socket
import ssl
import time
from uuid import uuid4
import httpx
from fastapi import WebSocket
from pydantic import ValidationError
from starlette.websockets import WebSocketDisconnect
from websockets.exceptions import InvalidStatus
from .doubao import Doubao, DoubaoConfig, asr_packet, parse_asr
from .errors import AssistantError
from .voice_policy import VoicePolicy


class TranscriptTracker:
    """ASR returns cumulative utterances. Speak each final segment exactly once."""
    def __init__(self):
        self.end = -1
        self.interim = ""

    def feed(self, packet):
        result = packet.get("result", {})
        if not isinstance(result, dict):
            return "", "", False
        finals, partials = [], []
        for utterance in result.get("utterances", []):
            end, text = utterance.get("end_time"), utterance.get("text", "")
            if not isinstance(end, (int, float)) or end <= self.end or not isinstance(text, str):
                continue
            if utterance.get("definite") is True:
                finals.append((end, text))
            elif text.strip():
                partials.append(text)
        if finals:
            self.end = max(end for end, _ in finals)
        partial = "".join(partials)[:2000]
        changed = bool(partial and partial != self.interim)
        self.interim = partial
        return partial, "".join(text for _, text in sorted(finals))[:2000], changed


class VoiceSession:
    def __init__(self, socket, provider, policy):
        self.socket, self.provider, self.policy = socket, provider, policy
        self.send_lock = asyncio.Lock()
        self.response = None
        self.turn = 0
        self.pending = ""
        self.tracker = TranscriptTracker()
        self.last_text_at = 0.0
        self.started = time.monotonic()
        self.audio_bytes = 0

    async def send(self, kind, **data):
        async with self.send_lock:
            await asyncio.wait_for(self.socket.send_json({"type": kind, **data}), timeout=5)

    async def cancel(self):
        self.turn += 1
        if self.response:
            self.response.cancel()
            with suppress(asyncio.CancelledError):
                await self.response
            self.response = None
        await self.send("interrupted", turn_id=self.turn)

    async def schedule(self, text=None, action=None):
        await self.cancel()
        turn = self.turn
        if text:
            self.pending = (self.pending + text)[:2000]
        self.response = asyncio.create_task(self.respond(turn, action))

    async def respond(self, turn, action):
        try:
            await asyncio.sleep(.35)  # combine adjacent final segments from one spoken request
            text, self.pending = self.pending, ""
            await self.send("thinking", turn_id=turn)
            started = time.monotonic()
            async with asyncio.timeout(40):
                answer = await self.policy.action(action) if action else await self.policy.answer(text)
                if turn != self.turn:
                    return
                await self.send("answer", turn_id=turn, **answer,
                                understanding_ms=round((time.monotonic() - started) * 1000))
                first = True
                carry = b""
                async for chunk in self.provider.synthesize(answer["text"]):
                    if turn != self.turn:
                        return
                    # Preserve PCM sample alignment even when HTTP chunks split a sample.
                    chunk = carry + chunk
                    carry = chunk[len(chunk) // 2 * 2:]
                    chunk = chunk[:len(chunk) // 2 * 2]
                    for offset in range(0, len(chunk), 24000):
                        await self.send("audio", turn_id=turn, sample_rate=24000,
                            data=base64.b64encode(chunk[offset:offset+24000]).decode(),
                            first=first, response_ms=round((time.monotonic() - started) * 1000))
                        first = False
                if carry:
                    raise AssistantError("TTS_INVALID", "语音最后一包不完整。", 502)
                await self.send("answer_done", turn_id=turn)
        except asyncio.CancelledError:
            raise
        except AssistantError as exc:
            await self.send("turn_error", turn_id=turn, code=exc.code, message=exc.message)
        except Exception:
            await self.send("turn_error", turn_id=turn, code="TURN_FAILED", message="今次回应未完成，请重试；冇自动提交操作。")

    async def read_asr(self, upstream):
        async for packet in upstream:
            partial, final, changed = self.tracker.feed(parse_asr(packet))
            if changed:
                # A new partial means a fresh utterance. Cancel stale playback/generation.
                if self.response:
                    await self.cancel()
                await self.send("transcript", text=partial, final=False)
            if final.strip():
                await self.send("transcript", text=final.strip(), final=True)
                await self.schedule(text=final.strip())

    async def read_browser(self, upstream):
        while True:
            message = await asyncio.wait_for(self.socket.receive(), timeout=35)
            if message["type"] == "websocket.disconnect":
                return
            if message.get("bytes") is not None:
                pcm = message["bytes"]
                if not pcm or len(pcm) > 12800 or len(pcm) % 2:
                    raise AssistantError("INVALID_PCM", "录音数据格式不正确，请重新连接。", 422)
                self.audio_bytes += len(pcm)
                if self.audio_bytes > (time.monotonic() - self.started + 3) * 40000:
                    raise AssistantError("AUDIO_RATE", "录音发送速度异常，请重新连接。", 429)
                await upstream.send(asr_packet(pcm))
                continue
            raw = message.get("text", "")
            if len(raw) > 6000:
                raise AssistantError("MESSAGE_LIMIT", "请求过长。", 422)
            event = json.loads(raw)
            if not isinstance(event, dict):
                raise ValueError()
            kind = event.get("type")
            if kind == "stop":
                await upstream.send(asr_packet(b"", final=True))
                return
            if kind == "interrupt":
                self.pending = ""
                await self.cancel()
            elif kind in {"text", "action"}:
                if time.monotonic() - self.last_text_at < .8:
                    continue
                self.last_text_at = time.monotonic()
                if kind == "text":
                    text = event.get("text")
                    if not isinstance(text, str) or not 1 <= len(text.strip()) <= 2000:
                        raise ValueError()
                    self.pending = ""
                    await self.send("transcript", text=text.strip(), final=True)
                    await self.schedule(text=text.strip())
                else:
                    self.pending = ""
                    await self.schedule(action=event)

    async def run(self):
        tasks = []
        try:
            async with self.provider.asr_connect() as upstream:
                await upstream.send(self.provider.asr_start())
                # Wait for service acknowledgement; a local socket opening is not ASR readiness.
                try:
                    parse_asr(await asyncio.wait_for(upstream.recv(), timeout=12))
                except TimeoutError:
                    raise AssistantError("ASR_ACK_TIMEOUT", "豆包连接已建立，但识别服务未在 12 秒内确认初始化。", 504) from None
                await self.send("ready", message="豆包识别通道已连接，可以用粤语讲话。", max_session_seconds=600)
                tasks = [asyncio.create_task(self.read_asr(upstream)), asyncio.create_task(self.read_browser(upstream))]
                done, _ = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
                for task in done:
                    task.result()
        except InvalidStatus as exc:
            # Never echo vendor headers/body: they may contain credential or account data.
            http_status = exc.response.status_code
            descriptions = {
                401: "ASR 鉴权失败（HTTP 401）：请核对语音 API Key 是否有效、是否已被禁用。",
                403: "ASR 拒绝访问（HTTP 403）：请核对密钥的豆包语音权限及所选 ASR 资源是否已开通。",
                429: "ASR 请求受限（HTTP 429）：请检查并发额度、资源用量和账户限制后重试。",
            }
            raise AssistantError(f"ASR_HTTP_{http_status}", descriptions.get(http_status,
                f"豆包 ASR 握手失败（HTTP {http_status}），请核对接口资源或稍后重试。"), 502) from None
        except ssl.SSLError:
            raise AssistantError("ASR_TLS", "无法建立豆包 ASR 的 TLS 安全连接，请检查系统时间、证书及网络代理。", 502) from None
        except network_socket.gaierror:
            raise AssistantError("ASR_DNS", "无法解析豆包 ASR 域名，请检查网络及 DNS。", 502) from None
        except PermissionError:
            raise AssistantError("ASR_NETWORK_DENIED", "本机系统或运行环境拒绝了 ASR 网络访问；这不是云端鉴权结果。", 502) from None
        except TimeoutError:
            raise AssistantError("ASR_CONNECT_TIMEOUT", "连接豆包 ASR 超时，请检查网络、代理及服务可达性。", 504) from None
        except OSError:
            raise AssistantError("ASR_NETWORK", "豆包 ASR 网络连接失败或被中断，请检查网络、防火墙及代理。", 502) from None
        finally:
            for task in tasks:
                task.cancel()
            if self.response:
                self.response.cancel()
                tasks.append(self.response)
            await asyncio.gather(*tasks, return_exceptions=True)


def add_realtime_route(app, settings):
    @app.websocket("/windows/realtime")
    async def realtime(socket: WebSocket):
        origin = socket.headers.get("origin")
        host = socket.headers.get("host", "")
        expected = ("https://" if socket.url.scheme == "wss" else "http://") + host
        if (socket.client and socket.client.host not in {"127.0.0.1", "::1", "testclient"}) or origin != expected:
            await socket.close(code=1008)
            return
        await socket.accept()
        try:
            message = await asyncio.wait_for(socket.receive_text(), timeout=10)
            if len(message) > 12000:
                raise ValueError()
            body = json.loads(message)
            if not isinstance(body, dict) or not isinstance(body.get("token"), str) or not secrets.compare_digest(body["token"], settings.demo_token):
                raise ValueError()
            config = DoubaoConfig.model_validate(body.get("config"))
            if getattr(app.state, "voice_connections", 0) >= 2:
                raise AssistantError("BUSY", "最多同时打开两个语音会话，请先关闭其他页面连接。", 429)
            app.state.voice_connections = getattr(app.state, "voice_connections", 0) + 1
            try:
                async with httpx.AsyncClient(timeout=httpx.Timeout(25, connect=8), follow_redirects=False) as client:
                    factory = getattr(app.state, "doubao_factory", Doubao)
                    provider = factory(config, client)
                    policy = VoicePolicy(provider, settings, app.state.business.store, app.state.business,
                                         "voice-" + uuid4().hex, settings.demo_token)
                    async with asyncio.timeout(600):
                        await VoiceSession(socket, provider, policy).run()
            finally:
                app.state.voice_connections -= 1
        except (ValidationError, ValueError, KeyError, TypeError):
            with suppress(Exception):
                await socket.send_json({"type": "error", "code": "INVALID_CONFIG", "message": "配置不完整或消息格式错误。请填写语音凭证、方舟 Key、模型 ID 和粤语音色 ID。"})
        except WebSocketDisconnect:
            pass
        except AssistantError as exc:
            with suppress(Exception):
                await socket.send_json({"type": "error", "code": exc.code, "message": exc.message})
        except TimeoutError:
            with suppress(Exception):
                await socket.send_json({"type": "error", "code": "SESSION_TIMEOUT", "message": "会话超时或已达到十分钟上限，请重新连接。"})
        except Exception:
            with suppress(Exception):
                await socket.send_json({"type": "error", "code": "VOICE_CONNECTION", "message": "豆包语音连接失败，请检查网络、凭证及 ASR 资源权限。"})
        finally:
            with suppress(Exception):
                await socket.close()
