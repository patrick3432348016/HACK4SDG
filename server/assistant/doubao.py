"""Doubao ASR 2.0 + Ark structured understanding + TTS 2.0 adapters.

No credentials, recordings or raw vendor error bodies are logged or persisted.
Protocol references and verification limits: docs/DOUBAO-WINDOWS.md.
"""
import base64
import gzip
import io
import json
import struct
from uuid import uuid4
from typing import Literal
import httpx
from pydantic import BaseModel, ConfigDict, Field, SecretStr, model_validator
from websockets.asyncio.client import connect
from .errors import AssistantError

ASR_URL = "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async"
ARK_URL = "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
TTS_URL = "https://openspeech.bytedance.com/api/v3/tts/unidirectional"
MAX_PACKET = 2_000_000


class DoubaoConfig(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    speech_key: SecretStr = SecretStr("")
    app_id: str = Field(default="", max_length=80, pattern=r"^[a-zA-Z0-9_-]*$")
    access_key: SecretStr = SecretStr("")
    ark_key: SecretStr = SecretStr("")
    model: str = Field(min_length=1, max_length=120, pattern=r"^[a-zA-Z0-9_.-]+$")
    speaker: str = Field(min_length=1, max_length=120, pattern=r"^[a-zA-Z0-9_.-]+$")
    asr_resource: Literal["volc.seedasr.sauc.duration", "volc.seedasr.sauc.concurrent", "volc.bigasr.sauc.duration"] = "volc.seedasr.sauc.duration"
    tts_resource: Literal["seed-tts-2.0", "seed-icl-2.0"] = "seed-tts-2.0"
    end_window_ms: int = Field(default=1200, ge=800, le=3000)
    speech_rate: int = Field(default=-15, ge=-30, le=20)

    @model_validator(mode="after")
    def credentials(self):
        if not self.speech_key.get_secret_value() and not (self.app_id and self.access_key.get_secret_value()):
            raise ValueError("Speech credential required")
        if not self.ark_key.get_secret_value():
            raise ValueError("Ark credential required")
        for value in (self.speech_key, self.access_key, self.ark_key):
            text = value.get_secret_value()
            if len(text) > 512 or any(ord(c) < 33 or ord(c) > 126 for c in text):
                raise ValueError("Invalid credential")
        return self

    def headers(self, resource):
        headers = {"X-Api-Resource-Id": resource, "X-Api-Request-Id": str(uuid4()), "X-Api-Connect-Id": str(uuid4())}
        if self.speech_key.get_secret_value():
            headers["X-Api-Key"] = self.speech_key.get_secret_value()
        else:
            headers.update({"X-Api-App-Key": self.app_id, "X-Api-Access-Key": self.access_key.get_secret_value()})
        return headers


def asr_packet(payload: bytes, *, initial=False, final=False):
    payload = gzip.compress(payload)
    return bytes([0x11, 0x10 if initial else (0x22 if final else 0x20), 0x11 if initial else 0x01, 0]) + struct.pack(">I", len(payload)) + payload


def parse_asr(packet):
    try:
        if not isinstance(packet, bytes) or not 8 <= len(packet) <= MAX_PACKET or packet[0] >> 4 != 1:
            raise ValueError()
        offset = (packet[0] & 15) * 4
        kind, flags = packet[1] >> 4, packet[1] & 15
        serialization, compression = packet[2] >> 4, packet[2] & 15
        if offset < 4 or kind not in (9, 15) or serialization != 1 or compression not in (0, 1):
            raise ValueError()
        if kind == 15:
            raise AssistantError("ASR_REJECTED", "豆包识别拒绝请求，请核对语音凭证、资源开通情况及模型版本。", 502)
        if flags & 1:
            offset += 4  # signed server sequence, including negative final sequence
        size = struct.unpack_from(">I", packet, offset)[0]
        payload = packet[offset + 4:]
        if len(payload) != size:
            raise ValueError()
        if compression:
            with gzip.GzipFile(fileobj=io.BytesIO(payload)) as zipped:
                payload = zipped.read(MAX_PACKET + 1)
        if len(payload) > MAX_PACKET:
            raise ValueError()
        data = json.loads(payload)
        if not isinstance(data, dict):
            raise ValueError()
        if data.get("code", 20000000) not in (0, 1000, 20000000):
            raise AssistantError("ASR_REJECTED", "豆包识别未完成，请核对配置或重试。", 502)
        return data
    except (ValueError, TypeError, struct.error, OSError, EOFError) as exc:
        raise AssistantError("ASR_PROTOCOL", "识别服务返回了不完整或不支持的数据。", 502) from exc


class Doubao:
    def __init__(self, config: DoubaoConfig, client: httpx.AsyncClient):
        self.config, self.client = config, client

    def asr_connect(self):
        return connect(ASR_URL, additional_headers=self.config.headers(self.config.asr_resource),
                       open_timeout=12, close_timeout=2, max_size=MAX_PACKET, max_queue=16, proxy=None)

    def asr_start(self):
        return asr_packet(json.dumps({"user": {"uid": "windows-voice-test"},
            "audio": {"format": "pcm", "codec": "raw", "rate": 16000, "bits": 16, "channel": 1},
            "request": {"model_name": "bigmodel", "enable_nonstream": True, "enable_lid": True,
                        "enable_itn": True, "enable_punc": True, "enable_ddc": False,
                        "show_utterances": True, "result_type": "full",
                        "end_window_size": self.config.end_window_ms}}, ensure_ascii=False).encode(), initial=True)

    async def json_completion(self, system, payload):
        try:
            response = await self.client.post(ARK_URL, headers={"Authorization": "Bearer " + self.config.ark_key.get_secret_value()},
                json={"model": self.config.model, "messages": [{"role": "system", "content": system},
                    {"role": "user", "content": json.dumps(payload, ensure_ascii=False)}],
                    "response_format": {"type": "json_object"}, "thinking": {"type": "disabled"},
                    "temperature": 0, "max_tokens": 700})
            if not response.is_success:
                raise AssistantError("ARK_REJECTED", "豆包理解服务拒绝请求，请检查方舟 API Key、模型 ID 和调用权限。", 502)
            item = response.json()["choices"][0]
            if item.get("finish_reason") != "stop" or len(item["message"]["content"]) > 12000:
                raise ValueError()
            return json.loads(item["message"]["content"])
        except httpx.TimeoutException as exc:
            raise AssistantError("ARK_TIMEOUT", "理解服务响应超时，请再讲一次。", 504) from exc
        except httpx.HTTPError as exc:
            raise AssistantError("ARK_NETWORK", "连接豆包理解服务失败，请检查网络。", 503) from exc
        except (ValueError, KeyError, TypeError, IndexError) as exc:
            raise AssistantError("ARK_INVALID", "豆包未返回有效的业务结果，本次不会执行操作。", 502) from exc

    async def synthesize(self, approved_text):
        # This method is only called with text constructed by the policy renderer.
        body = {"user": {"uid": "windows-voice-test"}, "req_params": {
            "text": approved_text, "speaker": self.config.speaker,
            "audio_params": {"format": "pcm", "sample_rate": 24000, "speech_rate": self.config.speech_rate},
            "additions": json.dumps({"explicit_language": "zh-cn", "explicit_dialect": "yue"})}}
        received, done = 0, False
        try:
            async with self.client.stream("POST", TTS_URL, headers=self.config.headers(self.config.tts_resource), json=body) as response:
                if not response.is_success:
                    raise AssistantError("TTS_REJECTED", "粤语播报未接通，请核对 TTS 权限、粤语音色 ID 和资源版本。", 502)
                async for line in response.aiter_lines():
                    if not line or line.startswith(("event:", ":")):
                        continue
                    if line.startswith("data:"):
                        line = line[5:].strip()
                    if len(line) > MAX_PACKET:
                        raise ValueError()
                    item = json.loads(line)
                    code = item.get("code")
                    if code not in (0, 20000000):
                        raise AssistantError("TTS_REJECTED", "豆包未能合成粤语，请确认音色支持 yue 方言。", 502)
                    if item.get("data"):
                        audio = base64.b64decode(item["data"], validate=True)
                        received += len(audio)
                        if received > 24000 * 2 * 45:
                            raise ValueError()
                        yield audio
                    if code == 20000000:
                        done = True
                        break
            if not received or not done:
                raise AssistantError("TTS_INCOMPLETE", "语音返回不完整，请重新尝试。", 502)
        except httpx.HTTPError as exc:
            raise AssistantError("TTS_NETWORK", "粤语播报连接中断，请检查网络。", 503) from exc
        except (ValueError, TypeError, AttributeError) as exc:
            raise AssistantError("TTS_INVALID", "语音服务返回了无效音频。", 502) from exc
