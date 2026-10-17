"""成员 A 加（2026-10-12）：App 全部播报改用 B 嘅豆包粤语声（小何）。

请求同 B 嘅 Doubao.synthesize（doubao.py）一样：TTS 2.0 单向流式、PCM 24 kHz、explicit_dialect=yue、B 揀嘅语速；
只系改成同步版本，交俾 SpeechService（sovits.py）嘅工作线程用，缓存、边合成边传、预热全部共用。
普通话（zh-CN）唔加方言参数。英文（en-US，10-17 加）：explicit_language=en；音色默认照用小何（doubao.json 可另设 speaker_en）。语速：App「語速」0.75 / 1.0 / 1.25 → 喺 B 嘅基准（speech_rate，默认 -15）上下 25（10-17 拉开）。
密钥只喺 Mac 服务器（voice-runtime/doubao.json），唔会去到手机；日志唔印密钥同厂商原始错误。
"""
from __future__ import annotations

import base64
import json

import httpx

from .doubao import MAX_PACKET, TTS_URL, DoubaoConfig


class DoubaoSpeechFailed(Exception):
    """豆包合成失败（鉴权 / 网络 / 音色唔支持）。SpeechService 会当呢句失败，App 转系统声音。"""


class DoubaoEngine:
    sample_rate = 24000
    locales = ("zh-HK", "zh-CN", "en-US")

    def __init__(self, config: DoubaoConfig, client: httpx.Client | None = None):
        self.config, self.client = config, client

    def load(self):
        if self.client is None:
            self.client = httpx.Client(timeout=httpx.Timeout(20, connect=5), follow_redirects=False)

    def rate(self, speed: float) -> int:
        return max(-50, min(100, round(self.config.speech_rate + (speed - 1.0) * 100)))

    def body(self, text: str, speed: float, locale: str) -> dict:
        additions = {"explicit_language": "en" if locale == "en-US" else "zh-cn"}
        if locale == "zh-HK":
            additions["explicit_dialect"] = "yue"
        speaker = (self.config.speaker_en or self.config.speaker) if locale == "en-US" else self.config.speaker
        return {"user": {"uid": "jiefong-voice"}, "req_params": {
            "text": text, "speaker": speaker,
            "audio_params": {"format": "pcm", "sample_rate": self.sample_rate, "speech_rate": self.rate(speed)},
            "additions": json.dumps(additions)}}

    def stream(self, text: str, speed: float = 1.0, locale: str = "zh-HK"):
        """逐段返回 PCM16 小端（长度一定系双数，唔会切开一个样本）。"""
        received, done, carry = 0, False, b""
        try:
            with self.client.stream("POST", TTS_URL, headers=self.config.headers(self.config.tts_resource),
                                    json=self.body(text, speed, locale)) as response:
                if not response.is_success:
                    raise DoubaoSpeechFailed(f"HTTP {response.status_code}")
                for line in response.iter_lines():
                    if not line or line.startswith(("event:", ":")):
                        continue
                    if line.startswith("data:"):
                        line = line[5:].strip()
                    if len(line) > MAX_PACKET:
                        raise DoubaoSpeechFailed("packet too large")
                    item = json.loads(line)
                    code = item.get("code")
                    if code not in (0, 20000000):
                        raise DoubaoSpeechFailed(f"code {code}")
                    if item.get("data"):
                        audio = carry + base64.b64decode(item["data"], validate=True)
                        cut = len(audio) // 2 * 2
                        carry = audio[cut:]
                        received += cut
                        if received > self.sample_rate * 2 * 90:
                            raise DoubaoSpeechFailed("audio too long")
                        if cut:
                            yield audio[:cut]
                    if code == 20000000:
                        done = True
                        break
        except httpx.HTTPError as exc:
            raise DoubaoSpeechFailed(type(exc).__name__) from None
        except (ValueError, TypeError, AttributeError) as exc:
            raise DoubaoSpeechFailed(type(exc).__name__) from None
        if not received or not done:
            raise DoubaoSpeechFailed("incomplete")


def doubao_voice_id(config: DoubaoConfig) -> str:
    """换音色 / 基准语速就换 id，App 同服务器嘅缓存自动作废。"""
    en = f"-en.{config.speaker_en}" if config.speaker_en else ""
    return f"doubao-{config.speaker}{en}-{config.tts_resource}-r{config.speech_rate}-1"
