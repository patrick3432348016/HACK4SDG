"""成员 A：本机粤语播报（SpeechService）测试。用假引擎，唔使 torch / 模型。"""
import asyncio
from pathlib import Path
import struct
import tempfile
import threading
import time
import unittest

from fastapi.testclient import TestClient

from assistant.app import create_app, is_lan_caller
from assistant.config import Settings
from assistant.sovits import SpeechService, SynthesisFailed, clean_text, wav_header


class FakeEngine:
    sample_rate = 32000

    def __init__(self, delay=0.0, fail=False, gate=None):
        self.calls, self.delay, self.fail, self.gate = [], delay, fail, gate
        self.loaded = False

    def load(self):
        self.loaded = True

    def stream(self, text, speed):
        self.calls.append(text)
        if self.gate is not None and text != "你好。":
            self.gate.wait(5)
        if self.fail and text != "你好。":
            raise RuntimeError("boom")
        for i in range(3):
            time.sleep(self.delay)
            yield bytes([i + 1, 0]) * 160   # 160 个 PCM16 样本


def collect(service, text, **kw):
    async def run():
        hit, it = await service.stream(text, **kw)
        return hit, b"".join([part async for part in it])
    return asyncio.run(run())


class SpeechServiceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.temp.cleanup()

    def service(self, engine, voice="v1"):
        s = SpeechService(lambda: engine, self.temp.name, voice)
        s.start()
        s.ready.wait(5)
        return s

    def test_stream_then_cache_hit_without_resynthesis(self):
        engine = FakeEngine()
        s = self.service(engine)
        hit, first = collect(s, "阿芳出咗門。")
        self.assertFalse(hit)
        self.assertEqual(first[:4], b"RIFF")
        self.assertEqual(struct.unpack("<I", first[40:44])[0], 0xFFFFFFFF)   # 流式：长度未知
        self.assertEqual(len(first), 44 + 3 * 320)
        time.sleep(0.05)
        hit, second = collect(s, "阿芳出咗門。")
        self.assertTrue(hit)
        self.assertEqual(struct.unpack("<I", second[40:44])[0], 3 * 320)   # 缓存档案：正确长度
        self.assertEqual(second[44:], first[44:])
        self.assertEqual(engine.calls, ["你好。", "阿芳出咗門。"])
        # 重开服务：由磁盘缓存读，唔再合成
        engine2 = FakeEngine()
        s2 = self.service(engine2)
        self.assertTrue(collect(s2, "阿芳出咗門。")[0])
        self.assertEqual(engine2.calls, ["你好。"])
        s.stop(); s2.stop()

    def test_cache_key_depends_on_voice_speed_and_text(self):
        s = SpeechService(FakeEngine, self.temp.name, "v1")
        other = SpeechService(FakeEngine, self.temp.name, "v2")
        self.assertNotEqual(s.key("你好", "zh-HK", 1.0), other.key("你好", "zh-HK", 1.0))
        self.assertNotEqual(s.key("你好", "zh-HK", 1.0), s.key("你好", "zh-HK", 0.9))
        self.assertEqual(s.key("「你好」", "zh-HK", 1.0), s.key("你好", "zh-HK", 1.0))

    def test_same_sentence_in_flight_is_synthesized_once(self):
        gate = threading.Event()
        engine = FakeEngine(gate=gate)
        s = self.service(engine)

        async def both():
            a = asyncio.ensure_future(s.stream("同一句。"))
            b = asyncio.ensure_future(s.stream("同一句。"))
            (_, ia), (_, ib) = await a, await b
            gate.set()
            return b"".join([x async for x in ia]), b"".join([x async for x in ib])
        a, b = asyncio.run(both())
        self.assertEqual(a, b)
        self.assertEqual(engine.calls.count("同一句。"), 1)
        s.stop()

    def test_live_requests_jump_ahead_of_prefetch(self):
        gate = threading.Event()
        engine = FakeEngine(gate=gate)
        s = self.service(engine)
        s.enqueue("預熱一", priority=1)
        time.sleep(0.05)          # 工作线程揸住第一句（等 gate）
        s.enqueue("預熱二", priority=1)
        s.enqueue("而家要講", priority=0)
        gate.set()
        deadline = time.time() + 5
        while len(engine.calls) < 4 and time.time() < deadline:
            time.sleep(0.01)
        self.assertEqual(engine.calls[1:], ["預熱一", "而家要講", "預熱二"])
        s.stop()

    def test_failure_raises_before_any_audio_and_is_not_cached(self):
        engine = FakeEngine(fail=True)
        s = self.service(engine)
        with self.assertRaises(SynthesisFailed):
            collect(s, "壞咗。")
        self.assertEqual(list(Path(self.temp.name).glob("*.wav")), [])
        s.stop()

    def test_clean_text_and_header(self):
        self.assertEqual(clean_text("「阿芳」出咗門\n喺涼亭·大樹底"), "阿芳出咗門。喺涼亭，大樹底")
        h = wav_header(32000, 640)
        self.assertEqual(len(h), 44)
        self.assertEqual(struct.unpack("<I", h[24:28])[0], 32000)


class SpeechRouteTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.engine = FakeEngine()
        speech = SpeechService(lambda: self.engine, str(Path(self.temp.name) / "cache"), "test-voice")
        settings = Settings(database=str(Path(self.temp.name) / "db.sqlite3"), requests_per_minute=500)
        self.app = create_app(settings, speech=speech)
        self.lan = TestClient(self.app, client=("192.168.1.30", 50000))
        self.lan.__enter__()
        speech.ready.wait(5)

    def tearDown(self):
        self.lan.__exit__(None, None, None)
        self.temp.cleanup()

    def test_voice_info_and_lan_synthesis(self):
        info = self.lan.get("/v1/voice").json()
        self.assertEqual((info["status"], info["voice_id"], info["locales"]), ("ready", "test-voice", ["zh-HK"]))
        r = self.lan.post("/v1/speech/synthesize", json={"text": "你好嗎", "locale": "zh-HK"})
        self.assertEqual(r.status_code, 200, r.text)
        self.assertEqual(r.headers["content-type"], "audio/wav")
        self.assertEqual(r.headers["x-tts-cache"], "miss")
        self.assertTrue(r.content.startswith(b"RIFF"))
        time.sleep(0.05)
        self.assertEqual(self.lan.post("/v1/speech/synthesize", json={"text": "你好嗎"}).headers["x-tts-cache"], "hit")

    def test_mandarin_falls_back_and_prefetch_returns_immediately(self):
        r = self.lan.post("/v1/speech/synthesize", json={"text": "你好", "locale": "zh-CN"})
        self.assertEqual(r.status_code, 503)
        self.assertEqual(r.json()["error"]["code"], "TTS_LOCALE_UNSUPPORTED")
        r = self.lan.post("/v1/speech/synthesize", json={"text": "預熱呢句", "prefetch": True})
        self.assertIn(r.status_code, (200, 202))

    def test_tunnel_or_proxy_callers_must_sign_in(self):
        r = self.lan.post("/v1/speech/synthesize", json={"text": "你好"}, headers={"CF-Connecting-IP": "8.8.8.8"})
        self.assertEqual(r.status_code, 401)
        with TestClient(self.app, client=("8.8.8.8", 1)) as public:
            self.assertEqual(public.post("/v1/speech/synthesize", json={"text": "你好"}).status_code, 401)

    def test_lan_detection(self):
        class R:
            def __init__(self, host, headers=None):
                self.client = type("C", (), {"host": host})
                self.headers = headers or {}
        self.assertTrue(is_lan_caller(R("127.0.0.1")))
        self.assertTrue(is_lan_caller(R("10.0.0.5")))
        self.assertFalse(is_lan_caller(R("127.0.0.1", {"cf-connecting-ip": "1.2.3.4"})))
        self.assertFalse(is_lan_caller(R("8.8.8.8")))


if __name__ == "__main__":
    unittest.main()
