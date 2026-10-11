"""成员 A：Supabase 业务适配（mode=supabase）测试。Supabase 用 httpx.MockTransport 模拟，唔连真服务器。"""
import asyncio
from datetime import datetime, timedelta
import json
from pathlib import Path
import tempfile
import unittest

import httpx
from fastapi.testclient import TestClient

from assistant.app import create_app
from assistant.config import Settings
from assistant.service import HK
from assistant.supabase_business import meetup_id

NOW = datetime(2026, 10, 10, 10, 0, tzinfo=HK)
ALICE = "aaaaaaaa-0000-4000-8000-000000000001"
FANG = "ffffffff-0000-4000-8000-000000000002"
STRANGER = "99999999-0000-4000-8000-000000000003"
TOKENS = {"alice-token": ALICE}


class FakeSupabase:
    """最少嘅 Supabase：auth/v1/user、my_neighbors、meetups（含 RLS 只准约街坊）、leaves、profiles。"""

    def __init__(self):
        self.neighbours = {ALICE: [{"id": FANG, "nickname": "阿芳"}]}
        self.meetups = {}
        self.leaves = set()
        self.nicknames = {ALICE: "阿明"}
        self.calls = []
        self.fail_insert = None   # 例如 500：模拟「写咗但係冇答」
        self.rls_only = None      # 模拟 RLS 只认呢啲人系互为街坊（my_neighbors 同 RLS 唔一致时）

    def handler(self, request: httpx.Request):
        assert request.headers["apikey"] == "anon-key"
        token = request.headers.get("authorization", "").removeprefix("Bearer ")
        user = TOKENS.get(token)
        path = request.url.path
        self.calls.append((request.method, path))
        if user is None:
            return httpx.Response(401, json={"msg": "invalid JWT"})
        if path == "/auth/v1/user":
            return httpx.Response(200, json={"id": user, "role": "authenticated"})
        if path == "/rest/v1/rpc/my_neighbors":
            return httpx.Response(200, json=[{**n, "avatar": {}, "block": None, "floor": None} for n in self.neighbours.get(user, [])])
        if path == "/rest/v1/meetups" and request.method == "POST":
            row = json.loads(request.content)
            allowed = self.rls_only if self.rls_only is not None else {n["id"] for n in self.neighbours.get(user, [])}
            if row["inviter"] != user or row["invitee"] not in allowed:
                return httpx.Response(403, json={"code": "42501", "message": "new row violates row-level security policy"})
            if self.fail_insert:
                self.meetups[row["id"]] = row
                return httpx.Response(self.fail_insert)
            if row["id"] in self.meetups:
                return httpx.Response(409, json={"code": "23505"})
            self.meetups[row["id"]] = row
            return httpx.Response(201)
        if path == "/rest/v1/meetups" and request.method == "GET":
            wanted = request.url.params["id"].removeprefix("eq.")
            row = self.meetups.get(wanted)
            return httpx.Response(200, json=[{"id": row["id"]}] if row and user in (row["inviter"], row["invitee"]) else [])
        if path == "/rest/v1/leaves" and request.method == "POST":
            row = json.loads(request.content)
            if row["user_id"] != user:
                return httpx.Response(403)
            self.leaves.add((user, row["day"]))
            return httpx.Response(201)
        if path == "/rest/v1/profiles" and request.method == "PATCH":
            self.nicknames[user] = json.loads(request.content)["nickname"]
            return httpx.Response(200, json=[{"id": user, "nickname": self.nicknames[user]}])
        raise AssertionError(f"unexpected {request.method} {path}")

    def inserted(self):
        return [c for c in self.calls if c == ("POST", "/rest/v1/meetups")]


def context_body(**place_overrides):
    slots = []
    start = NOW.replace(hour=6)
    for i in range(3 * 30):
        a = start + timedelta(minutes=30 * i)
        slots.append({"start": a.isoformat(), "end": (a + timedelta(minutes=30)).isoformat(), "fraction": 0.8})
    pavilion = {"id": "lm-1", "name": "涼亭", "publish_name": "涼亭", "has_seat": True, "self_walk_minutes": 4,
                "contact_walk_minutes": {FANG: 6}, "shade": slots, **place_overrides}
    plaza = {"id": "lm-2", "name": "大樹底", "publish_name": "公園櫈仔", "has_seat": False, "self_walk_minutes": 9,
             "contact_walk_minutes": {FANG: 12}, "shade": slots}
    return {"places": [pavilion, plaza], "walk_source": "估計", "shade_source": "測試遮蔭"}


class SupabaseAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.fake = FakeSupabase()
        self.upstream = httpx.AsyncClient(transport=httpx.MockTransport(self.fake.handler))
        self.settings = Settings(mode="supabase", supabase_url="https://sb.test", supabase_key="anon-key",
                                 database=str(Path(self.temp.name) / "db.sqlite3"), requests_per_minute=500)
        self.app = create_app(self.settings, client=self.upstream, clock=lambda: NOW)
        self.client = TestClient(self.app)
        self.client.__enter__()
        self.auth = {"Authorization": "Bearer alice-token"}

    def tearDown(self):
        self.client.__exit__(None, None, None)
        asyncio.run(self.upstream.aclose())
        self.temp.cleanup()

    def post(self, path, body=None, **headers):
        return self.client.post(path, json=body or {}, headers={**self.auth, **headers})

    def turn(self, text, conversation_id=None):
        r = self.post("/v1/assistant/turn", {"text": text, "locale": "zh-HK", "conversation_id": conversation_id})
        self.assertEqual(r.status_code, 200, r.text)
        return r.json()

    def upload(self, body=None):
        r = self.post("/v1/assistant/context", body or context_body())
        self.assertEqual(r.status_code, 200, r.text)
        return r.json()["version"]

    def draft(self):
        self.upload()
        reply = self.turn("約阿芳聽日下晝四點行下")
        self.assertEqual(reply["status"], "needs_input", reply)
        self.assertIsNone(reply["command"]["max_walk_minutes"])   # 唔猜步行上限：要问
        reply = self.turn("最多行十五分鐘", reply["conversation_id"])
        self.assertEqual(reply["status"], "choose_place", reply)
        self.assertEqual([c["id"] for c in reply["choices"]], ["lm-1", "lm-2"])
        reply = self.post(f"/v1/conversations/{reply['conversation_id']}/choice", {"kind": "place", "value": "lm-1"}).json()
        self.assertEqual(reply["status"], "needs_confirmation", reply)
        return reply

    def test_invite_writes_one_meetup_for_mutual_neighbour(self):
        reply = self.draft()
        self.assertFalse(reply["demo"])
        self.assertEqual(reply["data"]["action"]["contact_id"], FANG)
        self.assertEqual(reply["data"]["action"]["starts_at"], "2026-10-11T16:00:00+08:00")
        first = self.post(f"/v1/drafts/{reply['draft_id']}/confirm").json()
        second = self.post(f"/v1/drafts/{reply['draft_id']}/confirm").json()
        self.assertEqual(first["status"], "completed", first)
        self.assertEqual(first["data"]["receipt_id"], meetup_id(ALICE, reply["draft_id"]))
        self.assertEqual(second["data"]["receipt_id"], first["data"]["receipt_id"])
        self.assertEqual(len(self.fake.inserted()), 1)
        row = next(iter(self.fake.meetups.values()))
        self.assertEqual((row["inviter"], row["invitee"], row["status"]), (ALICE, FANG, "waiting"))
        self.assertEqual(row["landmark_name"], "涼亭")
        self.assertEqual(row["at"], "2026-10-11T08:00:00+00:00")
        self.assertIn("有樓遮住", row["reason"])

    def test_tokens_verified_by_supabase_not_self_reported(self):
        self.assertEqual(self.client.get("/v1/capabilities", headers={"Authorization": "Bearer forged"}).status_code, 401)
        self.assertEqual(self.client.get("/assistant/session", headers=self.auth).json(), {"user_id": ALICE})
        r = self.post("/v1/assistant/turn", {"text": "改名为小明", "user_id": FANG})
        self.assertEqual(r.status_code, 422)
        # 核实结果缓存：多次请求只问 Supabase 一次
        before = sum(1 for c in self.fake.calls if c[1] == "/auth/v1/user")
        for _ in range(3):
            self.client.get("/v1/capabilities", headers=self.auth)
        self.assertEqual(sum(1 for c in self.fake.calls if c[1] == "/auth/v1/user"), before)

    def test_context_upload_refuses_coordinates(self):
        body = context_body()
        body["places"][0]["pos"] = {"x": 1, "y": 2}
        self.assertEqual(self.post("/v1/assistant/context", body).status_code, 422)
        body = context_body()
        body["home"] = [22.5, 114.1]
        self.assertEqual(self.post("/v1/assistant/context", body).status_code, 422)

    def test_context_picks_shade_for_requested_time_and_hides_strangers(self):
        body = context_body()
        body["places"][0]["contact_walk_minutes"][STRANGER] = 3
        self.upload(body)
        ctx = self.client.get("/assistant/context", params={"at": "2026-10-11T16:10:00+08:00"}, headers=self.auth).json()
        self.assertEqual([c["name"] for c in ctx["contacts"]], ["阿芳"])
        pavilion = ctx["places"][0]
        self.assertEqual(pavilion["shade_fraction"], 0.8)
        self.assertEqual(pavilion["shade_valid_from"], "2026-10-11T16:00:00+08:00")
        self.assertNotIn(STRANGER, pavilion["contact_walk_minutes"])
        late = self.client.get("/assistant/context", params={"at": "2026-10-20T16:10:00+08:00"}, headers=self.auth).json()
        self.assertIsNone(late["places"][0]["shade_fraction"])   # 冇数据就系未知，唔当 0

    def test_rls_rejection_is_reported_not_success(self):
        reply = self.draft()
        self.fake.rls_only = set()   # 服务器 RLS 话唔系互为街坊
        result = self.post(f"/v1/drafts/{reply['draft_id']}/confirm").json()
        self.assertEqual(result["status"], "info")
        self.assertEqual(result["data"]["operation_status"], "failed")
        self.assertEqual(self.fake.meetups, {})

    def test_unlinked_before_confirm_is_rejected_by_version(self):
        reply = self.draft()
        # 对方喺确认之前解除咗街坊：版本变咗 → 拒绝，冇写入
        self.fake.neighbours[ALICE] = []
        result = self.post(f"/v1/drafts/{reply['draft_id']}/confirm").json()
        self.assertEqual(result["status"], "info")
        self.assertEqual(result["data"]["operation_status"], "failed")
        self.assertEqual(self.fake.meetups, {})

    def test_unknown_outcome_reconciles_by_derived_id(self):
        reply = self.draft()
        self.fake.fail_insert = 500
        result = self.post(f"/v1/drafts/{reply['draft_id']}/confirm").json()
        self.assertEqual(result["status"], "uncertain")
        self.fake.fail_insert = None
        result = self.post(f"/v1/drafts/{reply['draft_id']}/reconcile").json()
        self.assertEqual(result["status"], "completed")
        self.assertEqual(len(self.fake.inserted()), 1)   # 查结果唔会再写

    def test_business_api_idempotency_key(self):
        version = self.upload()
        ctx = self.client.get("/assistant/context", headers=self.auth).json()
        action = {"kind": "invite", "contact_id": FANG, "place_id": "lm-2", "starts_at": "2026-10-11T08:00:00+08:00",
                  "max_walk_minutes": 15, "prefer_shade": False}
        body = {"operation_id": "op-1", "expected_context_version": ctx["version"], "action": action}
        self.assertTrue(ctx["version"].startswith(version))
        missing = self.post("/assistant/actions", body)
        self.assertEqual(missing.status_code, 422)
        first = self.post("/assistant/actions", body, **{"Idempotency-Key": "op-1"}).json()
        again = self.post("/assistant/actions", body, **{"Idempotency-Key": "op-1"}).json()
        self.assertEqual(first["status"], "succeeded")
        self.assertEqual(first, again)
        changed = self.post("/assistant/actions", {**body, "action": {**action, "place_id": "lm-1"}}, **{"Idempotency-Key": "op-1"}).json()
        self.assertEqual(changed["status"], "rejected")
        self.assertEqual(len(self.fake.inserted()), 1)
        self.assertEqual(self.client.get("/assistant/actions/op-1", headers=self.auth).json()["status"], "succeeded")
        self.assertEqual(self.client.get("/assistant/actions/op-404", headers=self.auth).json()["status"], "not_found")
        self.assertEqual(self.fake.meetups[meetup_id(ALICE, "op-1")]["landmark_name"], "公園櫈仔")   # 用原名，对方对得上

    def test_leave_and_rename_need_confirmation_then_write(self):
        self.upload()
        reply = self.turn("明天请假")
        self.assertEqual(reply["status"], "needs_confirmation")
        self.assertEqual(self.fake.leaves, set())
        self.assertEqual(self.post(f"/v1/drafts/{reply['draft_id']}/confirm").json()["status"], "completed")
        self.assertEqual(self.fake.leaves, {(ALICE, "2026-10-11")})
        reply = self.turn("改名做小明")   # 粤语讲法
        self.assertEqual(self.post(f"/v1/drafts/{reply['draft_id']}/confirm").json()["status"], "completed")
        self.assertEqual(self.fake.nicknames[ALICE], "小明")


if __name__ == "__main__":
    unittest.main()
