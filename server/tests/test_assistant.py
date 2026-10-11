import asyncio
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
from datetime import datetime, timedelta
import io
import json
from pathlib import Path
import tempfile
import unittest
import wave
import httpx
from fastapi.testclient import TestClient

from assistant.app import create_app
from assistant.business import Business, demo_context
from assistant.config import Settings
from assistant.errors import AssistantError
from assistant.models import Command, Context
from assistant.providers import Providers, demo_interpret, validate_wav
from assistant.service import HK, rank_places
from assistant.store import Store

NOW = datetime(2026, 10, 10, 10, 0, tzinfo=HK)
AUTH = {"Authorization": "Bearer local-demo-only"}


def wav_bytes(seconds=1, rate=16000, channels=1):
    output = io.BytesIO()
    with wave.open(output, "wb") as f:
        f.setnchannels(channels)
        f.setsampwidth(2)
        f.setframerate(rate)
        f.writeframes(b"\0\0" * int(rate * seconds) * channels)
    return output.getvalue()


class APITests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.settings = Settings(database=str(Path(self.temp.name) / "db.sqlite3"), requests_per_minute=200)
        self.app = create_app(self.settings, clock=lambda: NOW)
        self.client = TestClient(self.app)
        self.client.__enter__()

    def tearDown(self):
        self.client.__exit__(None, None, None)
        self.temp.cleanup()

    def post(self, path, **body):
        return self.client.post(path, json=body, headers=AUTH)

    def turn(self, text, conversation_id=None):
        result = self.post("/v1/assistant/turn", text=text, locale="zh-HK", conversation_id=conversation_id)
        self.assertEqual(result.status_code, 200, result.text)
        return result.json()

    def invite(self):
        reply = self.turn("约陈伯明天下午四点散步，遮荫优先，最多15分钟")
        self.assertEqual(reply["status"], "choose_place", reply)
        reply = self.post(f"/v1/conversations/{reply['conversation_id']}/choice", kind="place", value="garden")
        self.assertEqual(reply.status_code, 200, reply.text)
        return reply.json()

    def test_auth_and_capabilities(self):
        self.assertEqual(self.client.get("/healthz").status_code, 200)
        self.assertEqual(self.client.get("/v1/capabilities").status_code, 401)
        result = self.client.get("/v1/capabilities", headers=AUTH).json()
        self.assertEqual(result["mode"], "demo")
        self.assertFalse(result["speech"])
        self.assertEqual(result["interpretation"], "limited_demo_rules")

    def test_full_invite_confirm_idempotent_persisted(self):
        draft = self.invite()
        self.assertEqual(draft["status"], "needs_confirmation")
        self.assertIn("仍需对方接受", draft["message"])
        path = f"/v1/drafts/{draft['draft_id']}/confirm"
        first = self.post(path).json()
        second = self.post(path).json()
        self.assertEqual(first["status"], "completed")
        self.assertTrue(first["demo"])
        self.assertEqual(first["data"]["receipt_id"], second["data"]["receipt_id"])
        reopened = Store(self.settings.database)
        self.assertEqual(reopened.draft(draft["draft_id"], "demo-user")["status"], "committed")

    def test_followup_time_and_walk(self):
        reply = self.turn("约陈伯散步")
        self.assertEqual(reply["status"], "needs_input")
        reply = self.turn("明天下午四点", reply["conversation_id"])
        self.assertEqual(reply["status"], "needs_input")
        reply = self.turn("最多15分钟", reply["conversation_id"])
        self.assertEqual(reply["status"], "choose_place")
        self.assertEqual(reply["command"]["starts_at"], "2026-10-11T16:00:00+08:00")

    def test_unknown_contact_requires_selection(self):
        reply = self.turn("约王伯明天下午四点散步，最多15分钟")
        self.assertEqual(reply["status"], "choose_contact")
        result = self.post(f"/v1/conversations/{reply['conversation_id']}/choice", kind="contact", value="lee")
        self.assertEqual(result.json()["status"], "choose_place")
        invalid = self.post(f"/v1/conversations/{reply['conversation_id']}/choice", kind="place", value="invented")
        self.assertEqual(invalid.status_code, 409)

    def test_stale_draft_cannot_execute_after_edit(self):
        draft = self.invite()
        self.turn("改明天下午五点", draft["conversation_id"])
        result = self.post(f"/v1/drafts/{draft['draft_id']}/confirm")
        self.assertEqual(result.json()["status"], "cancelled")

    def test_cancel_then_confirm_does_not_execute(self):
        draft = self.invite()
        self.post(f"/v1/drafts/{draft['draft_id']}/cancel")
        result = self.post(f"/v1/drafts/{draft['draft_id']}/confirm").json()
        self.assertEqual(result["status"], "cancelled")
        self.assertIsNone(result["data"]["receipt_id"])

    def test_cannot_cancel_completed_action(self):
        draft = self.invite()
        self.post(f"/v1/drafts/{draft['draft_id']}/confirm")
        self.assertEqual(self.post(f"/v1/drafts/{draft['draft_id']}/cancel").status_code, 409)

    def test_expired_draft_rejected(self):
        draft = self.invite()
        store = Store(self.settings.database)
        with store.connection() as db:
            db.execute("UPDATE drafts SET expires=0 WHERE id=?", (draft["draft_id"],))
        self.assertEqual(self.post(f"/v1/drafts/{draft['draft_id']}/confirm").status_code, 409)
        response = self.post(f"/v1/drafts/{draft['draft_id']}/reconcile").json()
        self.assertEqual(response["data"]["operation_status"], "expired")
        self.assertEqual(response["status"], "info")

    def test_unknown_outcome_never_retries_write(self):
        draft = self.invite()
        count = 0
        async def timeout(*args):
            nonlocal count
            count += 1
            raise AssistantError("TIMEOUT", "timeout", 504)
        self.app.state.business.execute = timeout
        path = f"/v1/drafts/{draft['draft_id']}/confirm"
        self.assertEqual(self.post(path).json()["status"], "uncertain")
        self.assertEqual(self.post(path).json()["status"], "uncertain")
        self.assertEqual(count, 1)
        result = self.post("/v1/assistant/turn", text="改名为小明", conversation_id=draft["conversation_id"])
        self.assertEqual(result.status_code, 409)

    def test_reconcile_does_not_submit_pending_draft(self):
        draft = self.invite()
        result = self.post(f"/v1/drafts/{draft['draft_id']}/reconcile").json()
        self.assertEqual(result["status"], "needs_confirmation")
        self.assertIsNone(result["data"]["receipt_id"])

    def test_no_speech_api_never_fakes_transcript(self):
        response = self.client.post("/v1/speech/transcribe?locale=zh-HK", content=wav_bytes(), headers={**AUTH, "Content-Type": "audio/wav"})
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json()["error"]["code"], "SPEECH_NOT_CONFIGURED")
        self.assertNotIn("text", response.json())

    def test_invalid_audio_and_body_limit(self):
        result = self.client.post("/v1/speech/transcribe", content=b"bad", headers={**AUTH, "Content-Type": "audio/wav"})
        self.assertEqual(result.status_code, 422)
        result = self.client.post("/v1/speech/transcribe", content=b"x" * 2_000_001, headers=AUTH)
        self.assertEqual(result.status_code, 413)

    def test_no_weather_not_invented(self):
        reply = self.turn("散步建议")
        self.assertFalse(reply["data"]["weather_available"])
        self.assertIn("没有", reply["message"])

    def test_monthly_statistics_computed(self):
        reply = self.turn("生成月报")
        self.assertEqual(reply["data"]["period_start"], "2026-09-01")
        self.assertEqual(reply["data"]["metres"], 1500)
        self.assertEqual(reply["data"]["minutes"], 30)
        self.assertEqual(reply["data"]["active_days"], 1)

    def test_daily_and_landmark(self):
        self.assertEqual(self.turn("今日一句")["status"], "info")
        reply = self.turn("给社区花园起名")
        self.assertEqual(reply["data"]["place_id"], "garden")
        self.assertIn("尚未保存", reply["message"])

    def test_rename_and_leave_require_confirmation(self):
        for text in ("改名为小明", "明天请假"):
            with self.subTest(text=text):
                self.assertEqual(self.turn(text)["status"], "needs_confirmation")

    def test_validation_does_not_echo_sensitive_input(self):
        result = self.post("/v1/assistant/turn", text="secret-private", locale="invalid")
        self.assertEqual(result.status_code, 422)
        self.assertNotIn("secret-private", result.text)
        self.assertIn("X-Request-ID", result.headers)

    def test_past_time_not_confirmable(self):
        self.assertEqual(self.turn("约陈伯2026-10-09下午四点散步，最多15分钟")["status"], "needs_input")

    def test_ambiguous_contact_never_silently_chooses(self):
        async def context(*args):
            data = demo_context(NOW).model_dump()
            data["contacts"].append({"id": "chan2", "name": "陈伯", "aliases": []})
            return Context.model_validate(data)
        self.app.state.business.context = context
        reply = self.turn("约陈伯明天下午四点散步，最多15分钟")
        self.assertEqual(reply["status"], "choose_contact")
        self.assertEqual(len(reply["choices"]), 2)

    def test_removed_selected_contact_is_not_replaced_by_same_name(self):
        phase = 0
        async def context(*args):
            data = demo_context(NOW).model_dump()
            if phase == 0:
                data["contacts"].append({"id": "chan2", "name": "陈伯", "aliases": []})
            else:
                data["contacts"] = [{"id": "chan2", "name": "陈伯", "aliases": []}]
                for place in data["places"]:
                    place["contact_walk_minutes"]["chan2"] = 5
            return Context.model_validate(data)
        self.app.state.business.context = context
        reply = self.turn("约陈伯明天下午四点散步，最多15分钟")
        self.assertEqual(reply["status"], "choose_contact")
        phase = 1
        result = self.post(f"/v1/conversations/{reply['conversation_id']}/choice", kind="contact", value="chan")
        self.assertEqual(result.status_code, 409)
        self.assertEqual(result.json()["error"]["code"], "CONTACT_CHANGED")

    def test_missing_monthly_history_is_not_zero_activity(self):
        async def context(*args):
            return Context(version="no-history-supplied")
        self.app.state.business.context = context
        reply = self.turn("生成月报")
        self.assertFalse(reply["data"]["report_available"])
        self.assertNotIn("0次散步", reply["message"])

    def test_partial_monthly_coverage_is_not_a_complete_report(self):
        async def context(*args):
            data = demo_context(NOW).model_dump()
            data["walk_coverage"] = {"start": "2026-09-15", "end_exclusive": "2026-10-01"}
            return Context.model_validate(data)
        self.app.state.business.context = context
        reply = self.turn("生成月报")
        self.assertFalse(reply["data"]["report_available"])
        self.assertNotIn("walk_count", reply["data"])

    def test_explicit_complete_empty_history_is_valid_zero_activity(self):
        async def context(*args):
            return Context.model_validate({"version": "complete-empty", "walks": [],
                "walk_coverage": {"start": "2026-09-01", "end_exclusive": "2026-10-01"}})
        self.app.state.business.context = context
        reply = self.turn("生成月报")
        self.assertTrue(reply["data"]["report_available"])
        self.assertEqual(reply["data"]["walk_count"], 0)

    def test_selected_contact_survives_followup_and_is_revalidated(self):
        phase = 0
        async def context(*args):
            data = demo_context(NOW).model_dump()
            data["contacts"].append({"id": "chan2", "name": "陈伯", "aliases": []})
            if phase:
                data["contacts"] = [c for c in data["contacts"] if c["id"] != "chan"]
            return Context.model_validate(data)
        self.app.state.business.context = context
        reply = self.turn("约陈伯散步")
        reply = self.post(f"/v1/conversations/{reply['conversation_id']}/choice", kind="contact", value="chan").json()
        self.assertEqual(reply["status"], "needs_input")
        phase = 1
        result = self.post("/v1/assistant/turn", text="明天下午四点", conversation_id=reply["conversation_id"])
        self.assertEqual(result.status_code, 409)
        self.assertEqual(result.json()["error"]["code"], "CONTACT_CHANGED")

    def test_neither_stale_weather_nor_future_weather_is_current(self):
        for delta in [timedelta(hours=-3), timedelta(hours=1)]:
            async def context(*args):
                data = demo_context(NOW).model_dump()
                data["weather"] = {"observed_at": NOW + delta, "summary": "sunny", "source": "test"}
                return Context.model_validate(data)
            self.app.state.business.context = context
            self.assertFalse(self.turn("散步建议")["data"]["weather_available"])

    def test_interrupted_process_reconciles_saved_receipt(self):
        draft = self.invite()
        store = Store(self.settings.database)
        self.assertTrue(store.claim(draft["draft_id"], "demo-user"))
        store.demo_execute(draft["draft_id"], "demo-user", {})
        # Process dies after business writes, before B saves the final state.
        result = self.post(f"/v1/drafts/{draft['draft_id']}/reconcile").json()
        self.assertEqual(result["status"], "completed")

    def test_completed_conversation_does_not_repeat_previous_intent(self):
        draft = self.invite()
        self.post(f"/v1/drafts/{draft['draft_id']}/confirm")
        result = self.turn("好的", draft["conversation_id"])
        self.assertEqual(result["status"], "info")
        self.assertIsNone(result["draft_id"])

    def test_client_cannot_inject_business_identity_or_context(self):
        result = self.post("/v1/assistant/turn", text="改名为小明", user_id="someone-else", context={})
        self.assertEqual(result.status_code, 422)

    def test_business_rejection_does_not_show_success(self):
        from assistant.models import Execution
        async def reject(*args):
            return Execution(status="rejected", message="version conflict")
        self.app.state.business.execute = reject
        draft = self.invite()
        result = self.post(f"/v1/drafts/{draft['draft_id']}/confirm").json()
        self.assertEqual(result["status"], "info")
        self.assertEqual(result["data"]["operation_status"], "failed")

    def test_prod_transport_and_auth_ownership(self):
        settings = replace(self.settings, mode="production", azure_key="test", azure_stt_url="https://test/stt", azure_tts_url="https://test/tts",
                           qwen_key="test", qwen_base_url="https://test/v1", qwen_model="test", business_base_url="https://business.test")
        def handler(request):
            if request.url.path == "/assistant/session":
                if request.headers["Authorization"] == "Bearer bob":
                    return httpx.Response(200, json={"user_id": "bob"})
                return httpx.Response(401)
            raise AssertionError("Unexpected provider call")
        upstream = httpx.AsyncClient(transport=httpx.MockTransport(handler))
        app = create_app(settings, client=upstream)
        draft = self.invite()
        with TestClient(app, base_url="https://assistant.test") as client:
            self.assertEqual(client.get("/v1/capabilities", headers={"Authorization": "Bearer expired"}).status_code, 401)
            response = client.post(f"/v1/drafts/{draft['draft_id']}/confirm", headers={"Authorization": "Bearer bob"})
            self.assertEqual(response.status_code, 404)
            self.assertEqual(client.get("http://assistant.test/v1/capabilities", headers=AUTH).status_code, 400)
        asyncio.run(upstream.aclose())

    def test_rate_limit(self):
        app = create_app(replace(self.settings, requests_per_minute=2))
        with TestClient(app) as client:
            self.assertEqual(client.get("/v1/capabilities", headers=AUTH).status_code, 200)
            self.assertEqual(client.get("/v1/capabilities", headers=AUTH).status_code, 200)
            self.assertEqual(client.get("/v1/capabilities", headers=AUTH).status_code, 429)


class LogicTests(unittest.TestCase):
    def test_shade_ranking_and_stale_data(self):
        from assistant.business import demo_context
        context = demo_context(NOW)
        command = Command(intent="invite", starts_at=NOW, prefer_shade=True, max_walk_minutes=15)
        self.assertEqual(rank_places(context, "chan", command), [])
        for p in context.places:
            p.shade_valid_from, p.shade_valid_until = NOW - timedelta(minutes=1), NOW + timedelta(minutes=1)
            p.source = "test"
        self.assertEqual(rank_places(context, "chan", command)[0].id, "pavilion")
        command.prefer_shade = False
        self.assertEqual(rank_places(context, "chan", command)[0].id, "plaza")
        context.places[1].is_open = None
        self.assertNotEqual(rank_places(context, "chan", command)[0].id, "plaza")

    def test_ambiguous_time_and_negation_not_guessed(self):
        self.assertIsNone(demo_interpret("约陈伯明天四点散步", None, NOW).starts_at)
        self.assertEqual(demo_interpret("不要约陈伯", None, NOW).intent, "help")

    def test_bad_wave_formats(self):
        for audio in (wav_bytes(rate=8000), wav_bytes(channels=2), wav_bytes(seconds=31), wav_bytes()[:-30]):
            with self.assertRaises(AssistantError):
                validate_wav(audio)

    def test_production_fails_closed(self):
        with self.assertRaises(ValueError):
            Settings(mode="production").validate()
        with self.assertRaises(ValueError):
            Settings(qwen_base_url="http://unsafe.test").validate()

    def test_claim_atomic_and_owner_isolated(self):
        with tempfile.TemporaryDirectory() as temp:
            store = Store(str(Path(temp) / "test.sqlite3"))
            session = store.session(None, "alice")
            draft = store.save(session, "alice", {}, {"action": {"kind": "leave"}})
            with self.assertRaises(AssistantError):
                store.draft(draft, "bob")
            with self.assertRaises(AssistantError):
                store.session(session["id"], "bob")
            with ThreadPoolExecutor(max_workers=8) as executor:
                outcomes = list(executor.map(lambda _: store.claim(draft, "alice"), range(8)))
            self.assertEqual(sum(outcomes), 1)

    def test_stale_session_write_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            store = Store(str(Path(temp) / "db.sqlite3"))
            first = store.session(None, "a")
            store.save(first, "a", {})
            current = store.session(first["id"], "a")
            store.save(current, "a", {})
            with self.assertRaises(AssistantError):
                store.save(current, "a", {})


class ProviderTests(unittest.IsolatedAsyncioTestCase):
    async def test_qwen_structured_command_and_secret_not_in_errors(self):
        def handler(request):
            body = json.loads(request.content)
            self.assertEqual(body["response_format"], {"type": "json_object"})
            self.assertNotIn("contact_id", body["messages"][1]["content"])
            return httpx.Response(200, json={"choices": [{"finish_reason": "stop", "message": {"content": '{"intent":"rename","new_name":"小明"}'}}]})
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            settings = Settings(qwen_key="never-log-this", qwen_base_url="https://qwen.test/v1", qwen_model="test")
            result = await Providers(settings, client).interpret("改名", None, NOW, "zh-HK")
            self.assertEqual(result.new_name, "小明")

    async def test_bad_model_json_and_provider_failures(self):
        for status, body in [(200, {"choices": [{"finish_reason": "stop", "message": {"content": "not-json"}}]}), (401, {"secret": "DO_NOT_EXPOSE"}), (429, {})]:
            async with httpx.AsyncClient(transport=httpx.MockTransport(lambda req: httpx.Response(status, json=body))) as client:
                settings = Settings(qwen_key="key", qwen_base_url="https://test/v1", qwen_model="test")
                with self.assertRaises(AssistantError) as caught:
                    await Providers(settings, client).interpret("text", None, NOW, "zh-HK")
                self.assertNotIn("DO_NOT_EXPOSE", str(caught.exception))

    async def test_azure_real_adapter_request_and_ssml_escaping(self):
        def handler(request):
            if request.url.path == "/stt":
                self.assertEqual(request.url.params["language"], "zh-HK")
                self.assertTrue(request.content.startswith(b"RIFF"))
                return httpx.Response(200, json={"RecognitionStatus": "Success", "DisplayText": "约陈伯"})
            self.assertIn(b"&lt;break/&gt;", request.content)
            self.assertNotIn(b"<break/>", request.content)
            return httpx.Response(200, content=b"ID3test", headers={"content-type": "audio/mpeg"})
        settings = Settings(azure_key="key", azure_stt_url="https://test/stt", azure_tts_url="https://test/tts")
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            provider = Providers(settings, client)
            self.assertEqual((await provider.transcribe(wav_bytes(), "zh-HK"))["text"], "约陈伯")
            self.assertTrue((await provider.speak("<break/>", "zh-CN")).startswith(b"ID3"))

    async def test_business_auth_and_idempotency_contract(self):
        def handler(request):
            self.assertEqual(request.headers["Authorization"], "Bearer USER_TOKEN")
            if request.url.path.endswith("/session"):
                return httpx.Response(200, json={"user_id": "alice"})
            if request.method == "POST":
                self.assertEqual(request.headers["Idempotency-Key"], "operation123")
                self.assertEqual(json.loads(request.content)["expected_context_version"], "v2")
            return httpx.Response(200, json={"status": "succeeded", "receipt_id": "receipt123"})
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            settings = Settings(mode="production", business_base_url="https://business.test")
            business = Business(settings, client, None)
            self.assertEqual(await business.identity("USER_TOKEN"), "alice")
            result = await business.execute("USER_TOKEN", "alice", "operation123", {"action": {"kind": "rename"}, "expected_context_version": "v2"})
            self.assertEqual(result.receipt_id, "receipt123")


if __name__ == "__main__":
    unittest.main()
