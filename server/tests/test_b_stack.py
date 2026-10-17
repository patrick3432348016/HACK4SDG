"""成员 A（2026-10-12）：换成 B 新版嗰套之后嘅接驳测试——豆包播报、话题判断（B 嘅 VoicePolicy）、识别通道。只用假供应商。"""
import asyncio
import base64
from datetime import datetime, timedelta
import json
from pathlib import Path
import tempfile
import unittest
import httpx
from fastapi.testclient import TestClient
from assistant.app import create_app
from assistant.app_ear import settle
from assistant.app_policy import BOARD, TurnPolicy
from assistant.business import Business
from assistant.config import Settings
from assistant.doubao import DoubaoConfig
from assistant.doubao_speech import DoubaoEngine, DoubaoSpeechFailed
from assistant.models import TurnRequest
from assistant.service import HK, Assistant
from assistant.store import Store
from assistant.voice_policy import CMN, DENIED, EMERGENCY, EN
from test_doubao import CONFIG, FakeProvider, server_packet


class DoubaoSpeechTests(unittest.TestCase):
    def engine(self, lines, seen):
        def handler(request):
            seen.append(json.loads(request.content))
            return httpx.Response(200, content="\n".join(lines).encode())
        return DoubaoEngine(DoubaoConfig.model_validate(CONFIG), httpx.Client(transport=httpx.MockTransport(handler)))

    def test_streams_even_pcm_with_cantonese_dialect_and_pace(self):
        seen = []
        audio = base64.b64encode(b"\x01\x02\x03").decode(), base64.b64encode(b"\x04\x05\x06\x07\x08").decode()
        engine = self.engine([json.dumps({"code": 0, "data": audio[0]}), json.dumps({"code": 0, "data": audio[1]}),
                              json.dumps({"code": 20000000})], seen)
        chunks = list(engine.stream("你好", 1.1, "zh-HK"))
        self.assertTrue(all(len(c) % 2 == 0 for c in chunks))
        self.assertEqual(b"".join(chunks), b"\x01\x02\x03\x04\x05\x06\x07\x08")
        params = seen[0]["req_params"]
        self.assertEqual(json.loads(params["additions"])["explicit_dialect"], "yue")
        self.assertEqual(params["audio_params"]["speech_rate"], -5)   # B 嘅基准 -15，快一档 +10

    def test_mandarin_has_no_dialect_and_vendor_error_fails(self):
        seen = []
        engine = self.engine([json.dumps({"code": 0, "data": base64.b64encode(b"\0\0").decode()}), json.dumps({"code": 20000000})], seen)
        list(engine.stream("你好", 1.0, "zh-CN"))
        self.assertNotIn("explicit_dialect", json.loads(seen[0]["req_params"]["additions"]))
        bad = self.engine([json.dumps({"code": 45000000, "message": "secret detail"})], [])
        with self.assertRaises(DoubaoSpeechFailed) as ctx:
            list(bad.stream("你好"))
        self.assertNotIn("secret", str(ctx.exception))


    def test_english_uses_en_language_and_optional_english_speaker(self):
        seen = []
        ok = [json.dumps({"code": 0, "data": base64.b64encode(b"\0\0").decode()}), json.dumps({"code": 20000000})]
        list(self.engine(ok, seen).stream("Hello", 1.0, "en-US"))
        additions = json.loads(seen[0]["req_params"]["additions"])
        self.assertEqual(additions, {"explicit_language": "en"})
        self.assertEqual(seen[0]["req_params"]["speaker"], CONFIG["speaker"])   # 默认照用小何
        other = DoubaoEngine(DoubaoConfig.model_validate({**CONFIG, "speaker_en": "en_female_test"}))
        self.assertEqual(other.body("Hi", 1.0, "en-US")["req_params"]["speaker"], "en_female_test")
        self.assertEqual(other.body("你好", 1.0, "zh-HK")["req_params"]["speaker"], CONFIG["speaker"])


class FakeWeather:
    def __init__(self):
        self.queries = []

    async def answer(self, query, locale="zh-HK"):
        self.queries.append(query)
        if locale == "en-US":
            return {"text": "Observatory: Sheung Shui 26 degrees.", "weather": {"source": "香港天文台"}}
        return {"text": "天文台實況：上水二十六度。", "weather": {"source": "香港天文台"}}


class TurnPolicyTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.settings = Settings(database=str(Path(self.directory.name) / "db.sqlite3"))
        self.store = Store(self.settings.database)
        self.provider = FakeProvider()
        self.weather = FakeWeather()
        assistant = Assistant(self.settings, self.store, Business(self.settings, None, self.store), self.provider)
        self.policy = TurnPolicy(self.settings, self.store, assistant, self.provider, self.weather)

    async def asyncTearDown(self):
        self.directory.cleanup()

    async def ask(self, text, conversation=None, locale="zh-HK"):
        return await self.policy.turn("owner", "local-demo-only", TurnRequest(text=text, locale=locale, conversation_id=conversation))

    async def test_scope_rules_answer_without_model(self):
        self.assertEqual((await self.ask("股票點買")).message, DENIED)
        reply = await self.ask("救命，有人暈倒")
        self.assertEqual((reply.message, reply.data["policy"], reply.status), (EMERGENCY, "emergency", "info"))
        self.assertEqual(self.provider.calls, 0)

    async def test_weather_follow_up_keeps_previous_query(self):
        self.provider.decision = {"topic": "weather", "weather": {"place": "sheung_shui"}}
        first = await self.ask("上水今日天氣點")
        self.assertEqual(first.data["policy"], "weather")
        self.assertEqual(first.message, "天文台實況：上水二十六度。")
        self.provider.decision = {"topic": "board"}
        board = await self.ask("排行榜呢", first.conversation_id)
        self.assertEqual(board.message, BOARD)

    async def test_english_scope_rules_and_weather_answer_in_english(self):
        reply = await self.ask("Help! I fell down and can't get up", locale="en-US")
        self.assertEqual((reply.message, reply.data["policy"]), (EN["emergency"], "emergency"))
        self.assertEqual((await self.ask("Can I take this medicine with tea?", locale="en-US")).message, EN["deny"])
        self.assertEqual((await self.ask("救命，有人晕倒了", locale="zh-CN")).message, CMN["emergency"])   # 普通话都行 B 嘅范围规则
        self.assertEqual(self.provider.calls, 0)
        self.provider.decision = {"topic": "weather"}
        weather = await self.ask("What's the weather today?", locale="en-US")
        self.assertEqual(weather.message, "Observatory: Sheung Shui 26 degrees.")
        self.provider.decision = {"topic": "help"}
        self.assertEqual((await self.ask("Hello", locale="en-US")).message, EN["help"])

    async def test_model_copying_now_minutes_is_pinned(self):
        # 10-18 真机：豆包将 now 嘅分钟抄入 starts_at（「下午3点散步40分钟」→ 15:02）
        when = (datetime.now(HK) + timedelta(days=1)).replace(hour=15, minute=2, second=41, microsecond=0)
        self.provider.decision = {"topic": "app", "command": {"intent": "invite", "contact_query": "邻居", "starts_at": when.isoformat(),
                                                              "max_walk_minutes": 40}}
        reply = await self.ask("约邻居明天下午3点散步40分钟", locale="zh-CN")
        at = datetime.fromisoformat(reply.command.starts_at.isoformat())
        self.assertEqual((at.hour, at.minute, at.second), (15, 0, 0))

    async def test_app_command_goes_through_b_confirmation(self):
        reply = await self.ask("聽日請假")
        self.assertEqual(reply.status, "needs_confirmation")
        self.assertEqual(reply.data["policy"], "app")
        self.assertEqual(reply.data["action"]["kind"], "leave")


class EarSocketTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        config = Path(self.directory.name) / "doubao.json"
        config.write_text(json.dumps(CONFIG))
        self.app = create_app(Settings(database=str(Path(self.directory.name) / "db.sqlite3"), doubao_config=str(config),
                                       tts_provider="none"))
        self.client = TestClient(self.app)
        self.client.__enter__()

    def tearDown(self):
        self.client.__exit__(None, None, None)
        self.directory.cleanup()

    def test_ear_relays_transcripts_and_never_answers_itself(self):
        class ASR:
            def __init__(self): self.queue = asyncio.Queue()
            async def __aenter__(self): return self
            async def __aexit__(self, *args): pass
            async def send(self, packet):
                if packet[1] == 0x20:
                    await self.queue.put(server_packet({"result": {"utterances": [{"text": "北区", "end_time": 900, "definite": False}]}}))
                    await self.queue.put(server_packet({"result": {"utterances": [{"text": "北区今日天气点", "end_time": 1000, "definite": True}]}}))
            async def recv(self): return server_packet({})
            def __aiter__(self): return self
            async def __anext__(self): return await self.queue.get()

        class Provider(FakeProvider):
            def asr_connect(self): return ASR()
            def asr_start(self): return b"init"
        self.app.state.doubao_factory = Provider
        with self.client.websocket_connect("/v1/voice/ear") as socket:
            socket.send_json({"token": "local-demo-only", "locale": "zh-HK"})
            self.assertEqual(socket.receive_json()["type"], "ready")
            socket.send_bytes(b"\0\0" * 3200)
            partial, final = socket.receive_json(), socket.receive_json()
            self.assertEqual((partial["text"], partial["final"]), ("北区", False))
            self.assertEqual((final["text"], final["final"]), ("北区今日天气点", True))
            socket.send_json({"type": "stop"})

    def test_short_utterance_keeps_streaming_text_when_second_pass_hallucinates(self):
        self.assertEqual(settle("帮我导航到大沥公园。", "咁听日咧"), "咁听日咧")
        self.assertEqual(settle("边只股票好啲？", "军事股票好啲"), "边只股票好啲？")
        self.assertEqual(settle("北区今日天气点啊", ""), "北区今日天气点啊")

    def test_ear_needs_login_off_lan(self):
        with self.client.websocket_connect("/v1/voice/ear") as socket:
            socket.send_json({"locale": "zh-HK"})
            self.assertEqual(socket.receive_json()["code"], "UNAUTHORIZED")
        with self.client.websocket_connect("/v1/voice/ear") as socket:   # 英文：接受 en-US，讯息用英文
            socket.send_json({"locale": "en-US"})
            self.assertEqual(socket.receive_json()["message"], "Please sign in first.")
        with self.client.websocket_connect("/v1/voice/ear") as socket:
            socket.send_json({"locale": "fr-FR"})
            self.assertEqual(socket.receive_json()["code"], "INVALID_HELLO")

    def test_voice_info_reports_doubao_stack_without_secrets(self):
        info = self.client.get("/v1/voice").json()
        self.assertTrue(info["ear"])
        self.assertEqual(info["brain"], "doubao")
        self.assertNotIn("fake-", json.dumps(info))
