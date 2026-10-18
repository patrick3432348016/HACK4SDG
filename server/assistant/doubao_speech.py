"""A, 2026-10-12: connect App synthesis to B's Doubao Xiaohe voice.

Match B's Doubao.synthesize: TTS 2.0 unidirectional streaming, 24 kHz PCM, Cantonese dialect and selected speed.
Use a synchronous adapter in SpeechService workers, sharing caching, streaming and warmup.
Mandarin omits dialect; English uses explicit_language=en and optional speaker_en. App speeds 0.75/1/1.25 offset baseline speech_rate by +/-25.
Credentials stay on the server; logs omit keys and raw provider errors.
"""
from __future__ import annotations

import base64
import json

import httpx

from .doubao import MAX_PACKET, TTS_URL, DoubaoConfig


class DoubaoSpeechFailed(Exception):
    """Authentication, network or unsupported-voice errors fail the utterance and trigger App system-voice fallback."""


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
        """Yield even-length little-endian PCM16 chunks without splitting samples."""
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
    """Changing speaker or baseline speed changes voice ID and invalidates both caches."""
    en = f"-en.{config.speaker_en}" if config.speaker_en else ""
    return f"doubao-{config.speaker}{en}-{config.tts_resource}-r{config.speech_rate}-1"
