"""Windows surface tests. Azure responses are mocked, NOT real recognition evidence."""
import tempfile
from pathlib import Path
import unittest
import httpx
from fastapi.testclient import TestClient
from assistant.config import Settings
from assistant.windows import create_windows_app
from test_assistant import wav_bytes


class WindowsTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.calls = []
        def vendor(request):
            self.calls.append(request)
            return httpx.Response(200, json={"RecognitionStatus": "Success", "DisplayText": "聽日去散步。"})
        self.upstream = httpx.AsyncClient(transport=httpx.MockTransport(vendor))
        self.app = create_windows_app(Settings(database=str(Path(self.directory.name)/"db.sqlite3")), client=self.upstream)
        self.client = TestClient(self.app, base_url="http://127.0.0.1:8765")
        self.client.__enter__()
        self.token = self.client.get("/windows/session").json()["token"]
        self.headers = {"Authorization": "Bearer " + self.token, "Content-Type": "audio/wav", "X-Speech-Key": "test-key", "X-Speech-Region": "eastasia"}

    def tearDown(self):
        self.client.__exit__(None, None, None)
        self.directory.cleanup()
        self.app.state.temporary.cleanup()

    def test_page_and_key_not_embedded(self):
        result = self.client.get("/")
        self.assertEqual(result.status_code, 200)
        self.assertIn("实时粤语助手", result.text)
        self.assertNotIn("test-key", result.text)
        self.assertIn("frame-ancestors 'none'", result.headers["Content-Security-Policy"])
        self.assertEqual(self.client.get("/app.js").status_code, 200)

    def test_memory_config_reload_clear_and_no_secret_echo(self):
        auth = {"Authorization": "Bearer " + self.token}
        config = {"speech_key":"synthetic-speech", "ark_key":"synthetic-ark", "model":"test-model", "speaker":"test-speaker"}
        self.assertIsNone(self.client.get("/windows/config", headers=auth).json()["config"])
        saved = self.client.post("/windows/config", headers=auth, json=config)
        self.assertEqual(saved.json(), {"saved":True})
        self.assertNotIn("synthetic", saved.text)
        loaded = self.client.get("/windows/config", headers=auth)
        self.assertEqual(loaded.json()["config"]["ark_key"], config["ark_key"])
        self.assertEqual(loaded.headers["Cache-Control"], "no-store")
        bad = self.client.post("/windows/config", headers=auth, json={**config,"speaker":"invalid speaker"})
        self.assertEqual(bad.status_code, 422)
        self.assertNotIn("synthetic", bad.text)
        self.assertEqual(self.client.get("/windows/config", headers=auth).json()["config"]["speaker"], "test-speaker")
        self.assertEqual(self.client.delete("/windows/config", headers=auth).json(), {"saved":False})
        self.assertIsNone(self.client.get("/windows/config", headers=auth).json()["config"])
        self.assertEqual(self.calls, [])

    def test_memory_config_auth_origin_and_size_limit(self):
        auth = {"Authorization": "Bearer " + self.token}
        for method in ("GET", "POST", "DELETE"):
            self.assertEqual(self.client.request(method, "/windows/config").status_code, 401)
            self.assertEqual(self.client.request(method, "/windows/config", headers={**auth,"Origin":"https://attacker.example"}).status_code, 403)
        self.assertEqual(self.client.post("/windows/config", headers=auth, content=b"x"*12001).status_code, 422)

    def test_real_adapter_contract_without_tts(self):
        result = self.client.post("/windows/transcribe?locale=zh-HK", content=wav_bytes(), headers=self.headers)
        self.assertEqual(result.status_code, 200, result.text)
        self.assertEqual(result.json()["source"], "azure")
        self.assertEqual(self.calls[0].url.host, "eastasia.stt.speech.microsoft.com")
        self.assertEqual(self.calls[0].url.params["language"], "zh-HK")
        self.assertEqual(self.calls[0].headers["Ocp-Apim-Subscription-Key"], "test-key")
        self.assertNotIn("test-key", result.text)

    def test_no_speech_and_vendor_error(self):
        for vendor_body, status, code in [({"RecognitionStatus":"NoMatch"}, 200, "NO_SPEECH"), ({"secret":"test-key"}, 401, "PROVIDER_REJECTED")]:
            self.app.state.providers.client = httpx.AsyncClient(transport=httpx.MockTransport(lambda r: httpx.Response(status, json=vendor_body)))
            response = self.client.post("/windows/transcribe", content=wav_bytes(), headers=self.headers)
            self.assertEqual(response.json()["error"]["code"], code)
            self.assertNotIn("test-key", response.text)

    def test_reject_bad_audio_locale_region_and_missing_key(self):
        for headers, audio, path in [
            (self.headers, b"bad", "/windows/transcribe"),
            (self.headers, wav_bytes(), "/windows/transcribe?locale=en-US"),
            ({**self.headers, "X-Speech-Region":"evil.com/path"}, wav_bytes(), "/windows/transcribe"),
            ({**self.headers, "X-Speech-Key":""}, wav_bytes(), "/windows/transcribe"),
            ({**self.headers, "Authorization":"Bearer invalid"}, wav_bytes(), "/windows/transcribe")]:
            self.assertGreaterEqual(self.client.post(path, content=audio, headers=headers).status_code, 400)
        self.assertEqual(self.calls, [])

    def test_cross_origin_and_host_rejected(self):
        self.assertEqual(self.client.get("/windows/session", headers={"Host":"attacker.example"}).status_code, 400)
        self.assertEqual(self.client.post("/windows/transcribe", content=wav_bytes(), headers={**self.headers, "Origin":"https://attacker.example"}).status_code, 403)
        self.assertEqual(self.calls, [])

    def test_text_demo_still_available(self):
        response = self.client.post("/v1/assistant/turn", headers={"Authorization":"Bearer " + self.token}, json={"text":"明天请假", "locale":"zh-CN"})
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["demo"])
        self.assertEqual(response.json()["status"], "needs_confirmation")


if __name__ == "__main__":
    unittest.main()
